--[[
Reading a Bible directly: :LxRead John opens the whole book (`logoxide://BSB/JHN`), and
:LxRead alone chooses a book, in Telescope with the book rendered and colored as its preview.
In a whole book, :LxNextBook, :LxNextChapter, :LxNextVerse, :LxNextHeading, and their :LxPrev*
go to the next or previous one (each past the end as `navigation` says).
]]
local bin = require('logoxide.bin')
local book = require('logoxide.book')
local config = require('logoxide.config')

local M = {}

local function client()
  return vim.lsp.get_clients({ name = 'logoxide' })[1]
end

-- The Bible and book of a `logoxide://BSB/JHN` buffer
local function book_of(bufnr)
  local name, code = vim.api.nvim_buf_get_name(bufnr or 0):match('^logoxide://([^/]+)/([^/#?]+)')
  return name and vim.uri_decode(name), code
end

-- Book names by USFM code (JHN → John), from the CLI: every book it knows (`--list-books`),
-- written as USFM (`Matthew 1` → `MAT 1`). Its codes can't be read back for all books, since
-- some are words it leaves alone (MAT, NUM, ACT)
local names

local function name_codes()
  local path = bin.path('cli')
  if names or not path then
    return
  end
  names = {}
  local books = vim.system({ path, '--list-books' }, { text = true }):wait()
  local lines = {}
  for name in (books.stdout or ''):gmatch('[^\n]+') do
    table.insert(lines, name .. ' 1')
  end
  local text = table.concat(lines, '\n')
  local result = vim.system({ path, '--chapters', '-m', 'json', '-f', 'usfm', '--text', text }, { text = true }):wait()
  for json in (result.stdout or ''):gmatch('[^\n]+') do
    local ok, m = pcall(vim.json.decode, json)
    local code = ok and type(m) == 'table' and type(m.reference) == 'string' and m.reference:match('^(%S+)')
    if code and type(m.book) == 'string' then
      names[code] = m.book
    end
  end
end

-- A Bible's name as logoxide-lsp writes it in a URI (all but letters, digits, and -._~ escaped)
local function encode(name)
  return (name:gsub('[^%w%-._~]', function(char)
    return ('%%%02X'):format(char:byte())
  end))
end

-- A Bible from logoxide-lsp (its name or an alias; nil for the default) with its books:
-- { name, books = { { code, name, uri } } }
function M.bible(name)
  local bibles = require('logoxide.bibles').list()
  local found = bibles[1]
  if name then
    found = nil
    for _, bible in ipairs(bibles) do
      if bible.name == name or vim.tbl_contains(bible.aliases or {}, name) then
        found = bible
      end
    end
  end
  if not found then
    return nil
  end
  name_codes()
  local books = vim.tbl_map(function(code)
    return {
      code = code,
      name = names and names[code] or code,
      uri = ('%s://%s/%s'):format(book.scheme, encode(found.name), code),
    }
  end, found.books)
  return { name = found.name, books = books }
end

-- The book `text` names, of `books`: its USFM code, its name, or anything the CLI reads as it
-- (1 cor, Jn), else the first whose name starts with it
local function find(books, text)
  local lower = text:lower()
  for _, b in ipairs(books) do
    if b.code:lower() == lower or b.name:lower() == lower then
      return b
    end
  end
  local path = bin.path('cli')
  if path then
    local result = vim.system({ path, '--chapters', '-m', 'json', '--text', text .. ' 1' }, { text = true }):wait()
    local ok, m = pcall(vim.json.decode, (result.stdout or ''):match('[^\n]+') or '')
    if ok and type(m) == 'table' then
      for _, b in ipairs(books) do
        if b.name == m.book then
          return b
        end
      end
    end
  end
  for _, b in ipairs(books) do
    if vim.startswith(b.name:lower(), lower) then
      return b
    end
  end
end

-- `John KJV` → 'John', 'KJV' (when the last word is a Bible's name or alias)
local function split_bible(text)
  local rest, last = text:match('^(.-)%s*(%S+)$')
  if last then
    for _, bible in ipairs(require('logoxide.bibles').list()) do
      if bible.name == last or vim.tbl_contains(bible.aliases or {}, last) then
        return rest, bible.name
      end
    end
  end
  return text, nil
end

local function open(b, mods)
  vim.cmd((mods and mods ~= '' and (mods .. ' split ') or 'edit ') .. vim.fn.fnameescape(b.uri))
end

-- logoxide-lsp's semantic tokens in `lines`: { { row, from, to, type } }, each a 0-based row,
-- byte columns, and the type's name (`heading`)
local function decode(lines, tokens)
  -- Each token is 5 numbers: line and start (relative to the last), length, type, modifiers
  local decoded, line, start = {}, 0, 0
  local data = tokens and tokens.data or {}
  for i = 1, #data, 5 do
    line = line + data[i]
    start = (data[i] == 0 and start or 0) + data[i + 1]
    local text = lines[line + 1] or ''
    local ok_s, from = pcall(vim.str_byteindex, text, 'utf-16', start, false)
    local ok_e, to = pcall(vim.str_byteindex, text, 'utf-16', start + data[i + 2], false)
    local token = book.legend[data[i + 3] + 1]
    if ok_s and ok_e and token then
      table.insert(decoded, { line, from, to, token })
    end
  end
  return decoded
end

-- A whole book's text and tokens, for previews: `done({ lines, highlights })`, from a cache
local previews = {}

local function load_preview(uri, done)
  if previews[uri] then
    return done(previews[uri])
  end
  local c = client()
  if not c then
    return
  end
  c:request('logoxide/book', { uri = uri }, function(err, result)
    if err or not result then
      return
    end
    local lines = vim.split(result.text, '\n')
    local params = { textDocument = { uri = uri } }
    c:request('textDocument/semanticTokens/full', params, function(_, tokens)
      local highlights = vim.tbl_map(function(t)
        return { t[1], t[2], t[3], book.group(t[4]) }
      end, decode(lines, tokens))
      previews[uri] = { lines = lines, highlights = highlights }
      done(previews[uri])
    end)
  end)
end

local preview_ns = vim.api.nvim_create_namespace('logoxide_book_preview')

local function show_preview(bufnr, preview)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, preview.lines)
  vim.api.nvim_buf_clear_namespace(bufnr, preview_ns, 0, -1)
  for _, h in ipairs(preview.highlights) do
    pcall(vim.api.nvim_buf_set_extmark, bufnr, preview_ns, h[1], h[2], { end_col = h[3], hl_group = h[4] })
  end
end

-- For :LxSwitch's previews
M.load_preview, M.show_preview = load_preview, show_preview

-- Chooses a book of `bible` (Telescope with previews, else vim.ui.select), then opens it
local function pick(bible, current, mods)
  local index = 1
  for i, b in ipairs(bible.books) do
    if b.code == current then
      index = i
    end
  end
  local picker = config.options.picker
  if picker == 'quickfix' or not pcall(require, 'telescope') then
    return vim.ui.select(bible.books, {
      prompt = 'Read ' .. bible.name,
      format_item = function(b)
        return b.name
      end,
    }, function(b)
      if b then
        open(b, mods)
      end
    end)
  end
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local state = require('telescope.actions.state')
  require('telescope.pickers')
    .new({}, {
      prompt_title = 'Read ' .. bible.name,
      default_selection_index = index,
      finder = require('telescope.finders').new_table({
        results = bible.books,
        entry_maker = function(b)
          return { value = b, display = b.name, ordinal = b.name .. ' ' .. b.code }
        end,
      }),
      sorter = conf.generic_sorter({}),
      previewer = require('telescope.previewers').new_buffer_previewer({
        title = bible.name,
        define_preview = function(self, entry)
          local bufnr, winid = self.state.bufnr, self.state.winid
          vim.wo[winid].wrap = true
          vim.wo[winid].linebreak = true
          load_preview(entry.value.uri, function(preview)
            -- Only if this book is still the one previewed
            if self.state and self.state.bufnr == bufnr then
              show_preview(bufnr, preview)
            end
          end)
        end,
      }),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local entry = state.get_selected_entry()
          actions.close(prompt_bufnr)
          if entry then
            open(entry.value, mods)
          end
        end)
        return true
      end,
    })
    :find()
end

--[[
:LxRead [book] [bible]: opens the whole book (`John`, `1 cor`, `JHN`), in the Bible named
after it, else the current book's Bible, else the default; without a book, chooses one
]]
function M.read(args, mods)
  if not require('logoxide').ensure_lsp() then
    return
  end
  local current_bible, current_code = book_of(0)
  local text, named = split_bible(vim.trim(args or ''))
  local bible = M.bible(named or current_bible)
  if not bible or #bible.books == 0 then
    return vim.notify('logoxide: no Bible has books to read (set `bible` or `bibles`)', vim.log.levels.WARN)
  end
  if text == '' then
    return pick(bible, bible.name == current_bible and current_code or nil, mods)
  end
  local found = find(bible.books, text)
  if not found then
    return vim.notify(('logoxide: %s has no book "%s"'):format(bible.name, text), vim.log.levels.WARN)
  end
  open(found, mods)
end

-- Not in a whole book: says so (for the moving commands)
local function not_a_book()
  vim.notify('logoxide: not in a whole book (open one with :LxRead)', vim.log.levels.WARN)
end

-- In a whole book, opens the book `step` books away in the same Bible, past the last book to
-- the first if `navigation.books` is 'wrap', then calls `done()` there
function M.book(step, done)
  local bible_name, code = book_of(0)
  local bible = bible_name and M.bible(bible_name)
  if not bible then
    return not_a_book()
  end
  local count = #bible.books
  for i, b in ipairs(bible.books) do
    if b.code == code then
      local target = i + step
      if target < 1 or target > count then
        if config.options.navigation.books ~= 'wrap' then
          return vim.notify(('logoxide: the %s book of %s'):format(step > 0 and 'last' or 'first', bible.name))
        end
        target = (target - 1) % count + 1
      end
      open(bible.books[target])
      if done then
        done()
      end
      return
    end
  end
end

--[[
The chapters of the whole book in the current buffer, from logoxide-lsp's document symbols:
{ { start = { row, col }, verses = { { row, col } } } }, each a 0-based row and a byte column
(the symbols' are UTF-16)
]]
local function chapters()
  local c = client()
  local uri = vim.api.nvim_buf_get_name(0)
  local response = c and c:request_sync('textDocument/documentSymbol', { textDocument = { uri = uri } }, 5000, 0)
  local function position(p)
    local line = vim.api.nvim_buf_get_lines(0, p.line, p.line + 1, false)[1] or ''
    local ok, col = pcall(vim.str_byteindex, line, 'utf-16', p.character, false)
    return { p.line, ok and col or 0 }
  end
  local symbols = response and response.result or {}
  -- Before logoxide-lsp had them, a book's symbols were the references in its text
  for _, symbol in ipairs(symbols) do
    if symbol.kind ~= vim.lsp.protocol.SymbolKind.Namespace then
      vim.notify('logoxide: this logoxide-lsp can\'t move by chapter or verse; update it (:LxBuild!)', vim.log.levels.ERROR)
      return {}
    end
  end
  return vim.tbl_map(function(chapter)
    local verses = vim.tbl_map(function(verse)
      return position(verse.selectionRange.start)
    end, chapter.children or {})
    return { start = position(chapter.selectionRange.start), verses = verses }
  end, symbols)
end

-- The last of `positions` at or before the cursor (0 if the cursor is before them all)
local function index_at(positions)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor[1] - 1, cursor[2]
  local found = 0
  for i, p in ipairs(positions) do
    if p[1] < row or (p[1] == row and p[2] <= col) then
      found = i
    end
  end
  return found
end

-- Moves the cursor to a 0-based { row, col }, in the jumplist
local function jump(position)
  vim.cmd("normal! m'")
  vim.api.nvim_win_set_cursor(0, { position[1] + 1, position[2] })
end

--[[
From chapter `current` of `list`, the chapter `step` away, then `land(chapter, step)` on it; past
the book's end (or start), `navigation.chapters` says where: 'next' for the next book's first
chapter (the previous book's last), 'wrap' for this book's first (last), or 'stop'
]]
local function to_chapter(list, current, step, land)
  local target = current + step
  if target >= 1 and target <= #list then
    return land(list[target], step)
  end
  local past = config.options.navigation.chapters
  if past == 'wrap' then
    return land(list[(target - 1) % #list + 1], step)
  elseif past == 'next' then
    return M.book(step > 0 and 1 or -1, function()
      local others = chapters()
      local chapter = others[step > 0 and 1 or #others]
      if chapter then
        land(chapter, step)
      end
    end)
  end
  vim.notify(('logoxide: the %s chapter of the book'):format(step > 0 and 'last' or 'first'))
end

-- In a whole book, the chapter `step` chapters away (its label, or its first verse)
function M.chapter(step)
  if not book_of(0) then
    return not_a_book()
  end
  local list = chapters()
  if #list == 0 then
    return
  end
  local starts = vim.tbl_map(function(chapter)
    return chapter.start
  end, list)
  to_chapter(list, index_at(starts), step, function(chapter)
    jump(chapter.start)
  end)
end

--[[
In a whole book, the verse `step` verses away in its chapter; past the chapter's end (or start),
`navigation.verses` says where: 'next' for the next chapter's first verse (the previous chapter's
last, crossing books as `navigation.chapters` says), 'wrap' for this chapter's first (last), or
'stop'
]]
function M.verse(step)
  if not book_of(0) then
    return not_a_book()
  end
  local list = chapters()
  if #list == 0 then
    return
  end
  local current = math.max(1, index_at(vim.tbl_map(function(chapter)
    return chapter.start
  end, list)))
  local verses = list[current].verses
  local target = index_at(verses) + step
  if target >= 1 and target <= #verses then
    return jump(verses[target])
  end
  local past = config.options.navigation.verses
  if past == 'wrap' and #verses > 0 then
    return jump(verses[(target - 1) % #verses + 1])
  elseif past == 'next' then
    return to_chapter(list, current, step > 0 and 1 or -1, function(chapter, direction)
      jump(chapter.verses[direction > 0 and 1 or #chapter.verses] or chapter.start)
    end)
  end
  vim.notify(('logoxide: the %s verse of the chapter'):format(step > 0 and 'last' or 'first'))
end

--[[
The headings of the whole book in the current buffer, from logoxide-lsp's semantic tokens:
{ { row, col } }, 0-based; headings on consecutive lines (a psalm's book, its range, and its
title, or a heading wrapped at `markup.width`) are one
]]
local function headings()
  local c = client()
  local uri = vim.api.nvim_buf_get_name(0)
  local response = c and c:request_sync('textDocument/semanticTokens/full', { textDocument = { uri = uri } }, 5000, 0)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local list, last = {}, nil
  for _, t in ipairs(decode(lines, response and response.result)) do
    if t[4] == 'heading' then
      if not last or t[1] > last + 1 then
        table.insert(list, { t[1], t[2] })
      end
      last = t[1]
    end
  end
  return list
end

--[[
In a whole book, the heading `step` headings away; past the book's last (or before its first),
`navigation.headings` says where: 'next' for the next book's first heading (the previous book's
last, crossing books as `navigation.books` says; its start if it has none), 'wrap' for this
book's first (last), or 'stop'
]]
function M.heading(step)
  if not book_of(0) then
    return not_a_book()
  end
  local list = headings()
  local target = index_at(list) + step
  if target >= 1 and target <= #list then
    return jump(list[target])
  end
  local past = config.options.navigation.headings
  if past == 'wrap' and #list > 0 then
    return jump(list[(target - 1) % #list + 1])
  elseif past == 'next' then
    return M.book(step > 0 and 1 or -1, function()
      local others = headings()
      jump(others[step > 0 and 1 or #others] or { 0, 0 })
    end)
  end
  vim.notify(('logoxide: the %s heading of the book'):format(step > 0 and 'last' or 'first'))
end

-- Completes book names (the default Bible's), then Bible names after one; only the last word
-- is replaced, since names have spaces (1 Corinthians)
function M.complete(lead, cmdline, pos)
  local typed = cmdline:sub(1, pos):gsub('^%S+%s*', '')
  local start = #typed - #lead
  local bible = require('logoxide').ensure_lsp() and M.bible()
  local candidates = {}
  for _, b in ipairs(bible and bible.books or {}) do
    local options = { b.name }
    if vim.startswith(typed:lower(), b.name:lower() .. ' ') then
      options = vim.tbl_map(function(other)
        return b.name .. ' ' .. other
      end, require('logoxide.bibles').names())
    end
    for _, option in ipairs(options) do
      if vim.startswith(option:lower(), typed:lower()) then
        table.insert(candidates, option:sub(start + 1))
      end
    end
  end
  return candidates
end

-- The last place read in a whole book ({ uri, line, col }), kept in Neovim's state folder so
-- :LxResume finds it in a later session too
local last
local last_file = vim.fs.joinpath(vim.fn.stdpath('state'), 'logoxide', 'last.json')

local function save_last()
  if last then
    vim.fn.mkdir(vim.fs.dirname(last_file), 'p')
    pcall(vim.fn.writefile, { vim.json.encode(last) }, last_file)
  end
end

-- Remembers where the cursor is in whole books, saving it on leaving one (and Neovim)
function M.track()
  local group = vim.api.nvim_create_augroup('logoxide_last_place', { clear = true })
  local function remember(args)
    local cursor = vim.api.nvim_win_get_cursor(0)
    last = { uri = vim.api.nvim_buf_get_name(args.buf), line = cursor[1], col = cursor[2] }
  end
  local pattern = book.scheme .. '://*'
  vim.api.nvim_create_autocmd('CursorMoved', { group = group, pattern = pattern, callback = remember })
  vim.api.nvim_create_autocmd('BufLeave', {
    group = group,
    pattern = pattern,
    callback = function(args)
      remember(args)
      save_last()
    end,
  })
  vim.api.nvim_create_autocmd('VimLeavePre', { group = group, callback = save_last })
end

-- :LxResume: back to the last place read in a whole book (this session's, else the last saved)
function M.resume(mods)
  if not last then
    local ok, lines = pcall(vim.fn.readfile, last_file)
    local decoded, place = pcall(vim.json.decode, ok and lines[1] or '')
    last = decoded and type(place) == 'table' and type(place.uri) == 'string' and place or nil
  end
  if not last then
    return vim.notify('logoxide: no whole book read yet (:LxRead)', vim.log.levels.WARN)
  end
  local place = last
  open({ uri = place.uri }, mods)
  local count = vim.api.nvim_buf_line_count(0)
  pcall(vim.api.nvim_win_set_cursor, 0, { math.min(place.line, count), place.col })
  vim.cmd('normal! zz')
end

-- A 0-based UTF-16 LSP position in `lines` as a 0-based row and byte column
local function byte_position(lines, position)
  local row = math.max(0, math.min(position.line, #lines - 1))
  local ok, col = pcall(vim.str_byteindex, lines[row + 1] or '', 'utf-16', position.character, false)
  return row, ok and col or 0
end

--[[
Where `text` (`John 3:16`, `jn 3`, `John`) is in `bible`'s whole book, then `done(uri, range,
top)`: its verse's range (nil for a chapter or book), and where to show it from, `read_at.context`
verses before the verse (else the chapter's label; nil for the book's start); `done(nil)` if the
Bible doesn't have the book. The chapter and verse come from logoxide-lsp's document symbols (`John 3`,
`John 3:16-17`)
]]
local function locate(bible, text, done)
  local path, c = bin.path('cli'), client()
  local m
  if path then
    local result = vim.system({ path, '--chapters', '-m', 'json', '--text', text }, { text = true }):wait()
    if result.code ~= 0 and (result.stderr or ''):find('--chapters', 1, true) then
      return vim.notify('logoxide: this topos is too old for :LxReadAt; update it (:LxBuild!)', vim.log.levels.ERROR)
    end
    local ok, decoded = pcall(vim.json.decode, (result.stdout or ''):match('[^\n]+') or '')
    m = ok and type(decoded) == 'table' and decoded or nil
  end
  local found
  for _, b in ipairs(bible.books) do
    if m and b.name == m.book then
      found = b
    end
  end
  found = found or find(bible.books, text)
  if not found then
    return done(nil)
  end
  local start = m and type(m.segments) == 'table' and m.segments[1] and m.segments[1].start
  local chapter = type(start) == 'table' and start.chapter or tonumber(start)
  local verse = type(start) == 'table' and start.verse or nil
  if not (chapter and c) then
    return done(found.uri, nil)
  end
  c:request('textDocument/documentSymbol', { textDocument = { uri = found.uri } }, function(_, symbols)
    for _, symbol in ipairs(symbols or {}) do
      if tonumber(symbol.name:match('(%d+)$')) == chapter then
        local children = verse and symbol.children or {}
        for i, child in ipairs(children) do
          local first, last = child.name:match(':(%d+)%-?(%d*)$')
          first = tonumber(first)
          if first and first <= verse and verse <= (tonumber(last) or first) then
            local before = children[i - math.max(0, config.options.read_at.context or 0)]
            return done(found.uri, child.range, (before or symbol).range.start)
          end
        end
        return done(found.uri, nil, symbol.range.start)
      end
    end
    done(found.uri, nil)
  end)
end

-- Opens `text` (a reference) in `bible`'s whole book, with the cursor on its verse
local function open_at(bible, text, mods)
  locate(bible, text, function(uri, range, top)
    if not uri then
      return vim.notify(('logoxide: %s has no book for "%s"'):format(bible.name, text), vim.log.levels.WARN)
    end
    open({ uri = uri }, mods)
    local at = range and range.start or top
    if at then
      local row, col = byte_position(vim.api.nvim_buf_get_lines(0, 0, -1, false), at)
      pcall(vim.api.nvim_win_set_cursor, 0, { row + 1, col })
      vim.cmd('normal! zz')
    end
  end)
end

local verse_ns = vim.api.nvim_create_namespace('logoxide_read_at_verse')

--[[
Chooses a reference in Telescope, its prompt completed as you type (books, then chapters, then
verses, from `topos --complete`; <Tab> takes the one selected), previewing it in `bible`, then
opens it there
]]
local function pick_at(bible, mods)
  local path = bin.path('cli')
  if not path then
    return vim.notify('logoxide: the topos CLI is not built yet; run :LxBuild', vim.log.levels.ERROR)
  end
  local actions = require('telescope.actions')
  local state = require('telescope.actions.state')
  require('telescope.pickers')
    .new({}, {
      prompt_title = 'Read at (' .. bible.name .. ')',
      debounce = 50,
      finder = require('telescope.finders').new_job(function(prompt)
        return { path, '-m', 'json', '--complete', prompt or '' }
      end, function(line)
        local ok, s = pcall(vim.json.decode, line)
        if ok and type(s) == 'table' and type(s.text) == 'string' then
          return { value = s.text, display = s.label or s.text, ordinal = s.text, kind = s.kind }
        end
      end),
      sorter = require('telescope.sorters').empty(),
      previewer = require('telescope.previewers').new_buffer_previewer({
        title = bible.name,
        define_preview = function(self, entry)
          local bufnr, winid = self.state.bufnr, self.state.winid
          vim.wo[winid].wrap = true
          vim.wo[winid].linebreak = true
          locate(bible, entry.value, function(uri, range, top)
            if not uri then
              return vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { bible.name .. " doesn't have this book" })
            end
            load_preview(uri, function(preview)
              -- Only if this reference is still the one previewed
              if not (self.state and self.state.bufnr == bufnr and vim.api.nvim_win_is_valid(winid)) then
                return
              end
              show_preview(bufnr, preview)
              -- A verse is marked, below `read_at.context` verses before it; a chapter is shown
              -- from its label, and a book from its start
              local top_row = top and byte_position(preview.lines, top) or 0
              local row, col = top_row, 0
              if range then
                row, col = byte_position(preview.lines, range.start)
                local end_row, end_col = byte_position(preview.lines, range['end'])
                pcall(vim.api.nvim_buf_set_extmark, bufnr, verse_ns, row, col, {
                  end_row = end_row,
                  end_col = end_col,
                  hl_group = 'LogoxideParallelVerse',
                })
              end
              vim.api.nvim_win_call(winid, function()
                vim.fn.winrestview({ topline = top_row + 1, lnum = row + 1, col = col })
              end)
            end)
          end)
        end,
      }),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          local entry = state.get_selected_entry()
          local typed = vim.trim(state.get_current_line())
          actions.close(prompt_bufnr)
          local text = entry and entry.value or typed
          if text ~= '' then
            open_at(bible, text, mods)
          end
        end)
        -- What's selected, in the prompt, ready for its chapter (`John `) or verse (`John 3:`)
        map({ 'i', 'n' }, '<Tab>', function()
          local entry = state.get_selected_entry()
          if entry then
            local after = ({ book = ' ', chapter = ':' })[entry.kind] or ''
            state.get_current_picker(prompt_bufnr):set_prompt(entry.value .. after)
          end
        end)
        return true
      end,
    })
    :find()
end

--[[
:LxReadAt [reference] [bible]: opens the reference (`John 3:16`, `jn 3`) in the whole book, on its
verse, in the Bible named after it, else the current book's Bible, else the default; without a
reference, chooses one in Telescope (else asks for one)
]]
function M.read_at(args, mods)
  if not require('logoxide').ensure_lsp() then
    return
  end
  local current_bible = book_of(0)
  local text, named = split_bible(vim.trim(args or ''))
  local bible = M.bible(named or current_bible)
  if not bible or #bible.books == 0 then
    return vim.notify('logoxide: no Bible has books to read (set `bible` or `bibles`)', vim.log.levels.WARN)
  end
  if text ~= '' then
    return open_at(bible, text, mods)
  end
  if config.options.picker ~= 'quickfix' and pcall(require, 'telescope') then
    return pick_at(bible, mods)
  end
  vim.ui.input({ prompt = 'Read at (' .. bible.name .. '): ' }, function(input)
    if input and vim.trim(input) ~= '' then
      open_at(bible, vim.trim(input), mods)
    end
  end)
end

-- Completes a reference (books, then chapters, verses, and range ends), then Bible names after
-- one; only the last word is replaced
function M.complete_at(lead, cmdline, pos)
  local candidates = require('logoxide.commands').complete_passage(lead, cmdline, pos)
  local typed = cmdline:sub(1, pos):gsub('^%S+%s*', '')
  if typed:match('%d%s+%S*$') then
    for _, name in ipairs(require('logoxide.bibles').names()) do
      if vim.startswith(name:lower(), lead:lower()) then
        table.insert(candidates, name)
      end
    end
  end
  return candidates
end

return M
