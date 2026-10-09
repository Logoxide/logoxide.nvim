--[[
Reading a Bible directly: :ToposRead John opens the whole book (`topos-bible://BSB/JHN`), and
:ToposRead alone chooses a book, in Telescope with the book rendered and colored as its preview.
In a whole book, ]b and [b go to the next and previous book (`book_keys`), and :ToposNextBook,
:ToposNextChapter, :ToposNextVerse, and their :ToposPrev* go to the next or previous one (each
past the end as `navigation` says).
]]
local bin = require('topos.bin')
local book = require('topos.book')
local config = require('topos.config')

local M = {}

local function client()
  return vim.lsp.get_clients({ name = 'topos' })[1]
end

-- The Bible and book of a `topos-bible://BSB/JHN` buffer
local function book_of(bufnr)
  local name, code = vim.api.nvim_buf_get_name(bufnr or 0):match('^topos%-bible://([^/]+)/([^/#?]+)')
  return name and vim.uri_decode(name), code
end

-- Book names by USFM code (JHN → John), from the CLI (it reads `JHN 1` as John 1)
local names = {}

local function name_codes(codes)
  local missing = vim.tbl_filter(function(code)
    return not names[code]
  end, codes)
  local path = bin.path('cli')
  if #missing == 0 or not path then
    return
  end
  local lines = vim.tbl_map(function(code)
    return code .. ' 1'
  end, missing)
  local result = vim.system({ path, '-m', 'json', '--text', table.concat(lines, '\n') }, { text = true }):wait()
  for json in (result.stdout or ''):gmatch('[^\n]+') do
    local ok, m = pcall(vim.json.decode, json)
    if ok and type(m) == 'table' and missing[m.line] and type(m.book) == 'string' then
      names[missing[m.line]] = m.book
    end
  end
end

-- A Bible's name as biblix-lsp writes it in a URI (all but letters, digits, and -._~ escaped)
local function encode(name)
  return (name:gsub('[^%w%-._~]', function(char)
    return ('%%%02X'):format(char:byte())
  end))
end

-- A Bible from biblix-lsp (its name or an alias; nil for the default) with its books:
-- { name, books = { { code, name, uri } } }
function M.bible(name)
  local bibles = require('topos.bibles').list()
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
  name_codes(found.books)
  local books = vim.tbl_map(function(code)
    return {
      code = code,
      name = names[code] or code,
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
    local result = vim.system({ path, '-m', 'json', '--text', text .. ' 1' }, { text = true }):wait()
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
    for _, bible in ipairs(require('topos.bibles').list()) do
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
  c:request('topos/book', { uri = uri }, function(err, result)
    if err or not result then
      return
    end
    local lines = vim.split(result.text, '\n')
    local params = { textDocument = { uri = uri } }
    c:request('textDocument/semanticTokens/full', params, function(_, tokens)
      -- Each token is 5 numbers: line and start (relative to the last), length, type, modifiers
      local highlights, line, start = {}, 0, 0
      local data = tokens and tokens.data or {}
      for i = 1, #data, 5 do
        line = line + data[i]
        start = (data[i] == 0 and start or 0) + data[i + 1]
        local text = lines[line + 1] or ''
        local ok_s, from = pcall(vim.str_byteindex, text, 'utf-16', start, false)
        local ok_e, to = pcall(vim.str_byteindex, text, 'utf-16', start + data[i + 2], false)
        local token = book.legend[data[i + 3] + 1]
        if ok_s and ok_e and token then
          table.insert(highlights, { line, from, to, book.group(token) })
        end
      end
      previews[uri] = { lines = lines, highlights = highlights }
      done(previews[uri])
    end)
  end)
end

local preview_ns = vim.api.nvim_create_namespace('topos_book_preview')

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
:ToposRead [book] [bible]: opens the whole book (`John`, `1 cor`, `JHN`), in the Bible named
after it, else the current book's Bible, else the default; without a book, chooses one
]]
function M.read(args, mods)
  if not require('topos').ensure_lsp() then
    return
  end
  local current_bible, current_code = book_of(0)
  local text, named = split_bible(vim.trim(args or ''))
  local bible = M.bible(named or current_bible)
  if not bible or #bible.books == 0 then
    return vim.notify('topos: no Bible has books to read (set `bible` or `bibles`)', vim.log.levels.WARN)
  end
  if text == '' then
    return pick(bible, bible.name == current_bible and current_code or nil, mods)
  end
  local found = find(bible.books, text)
  if not found then
    return vim.notify(('topos: %s has no book "%s"'):format(bible.name, text), vim.log.levels.WARN)
  end
  open(found, mods)
end

-- Not in a whole book: says so (for the moving commands)
local function not_a_book()
  vim.notify('topos: not in a whole book (open one with :ToposRead)', vim.log.levels.WARN)
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
          return vim.notify(('topos: the %s book of %s'):format(step > 0 and 'last' or 'first', bible.name))
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
The chapters of the whole book in the current buffer, from biblix-lsp's document symbols:
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
  return vim.tbl_map(function(chapter)
    local verses = vim.tbl_map(function(verse)
      return position(verse.selectionRange.start)
    end, chapter.children or {})
    return { start = position(chapter.selectionRange.start), verses = verses }
  end, response and response.result or {})
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
  vim.notify(('topos: the %s chapter of the book'):format(step > 0 and 'last' or 'first'))
end

-- In a whole book, the chapter `step` chapters away (its label, or its first verse)
function M.chapter(step)
  local list = book_of(0) and chapters() or {}
  if #list == 0 then
    return not_a_book()
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
  local list = book_of(0) and chapters() or {}
  if #list == 0 then
    return not_a_book()
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
  vim.notify(('topos: the %s verse of the chapter'):format(step > 0 and 'last' or 'first'))
end

-- Completes book names (the default Bible's), then Bible names after one; only the last word
-- is replaced, since names have spaces (1 Corinthians)
function M.complete(lead, cmdline, pos)
  local typed = cmdline:sub(1, pos):gsub('^%S+%s*', '')
  local start = #typed - #lead
  local bible = require('topos').ensure_lsp() and M.bible()
  local candidates = {}
  for _, b in ipairs(bible and bible.books or {}) do
    local options = { b.name }
    if vim.startswith(typed:lower(), b.name:lower() .. ' ') then
      options = vim.tbl_map(function(other)
        return b.name .. ' ' .. other
      end, require('topos.bibles').names())
    end
    for _, option in ipairs(options) do
      if vim.startswith(option:lower(), typed:lower()) then
        table.insert(candidates, option:sub(start + 1))
      end
    end
  end
  return candidates
end

-- ]b and [b in a whole book (from ftplugin/topos-bible.lua)
function M.map_keys(bufnr)
  local keys = config.options.book_keys
  if not keys then
    return
  end
  local function map(lhs, step, desc)
    if lhs then
      vim.keymap.set('n', lhs, function()
        M.book(step * vim.v.count1)
      end, { buffer = bufnr, desc = desc })
    end
  end
  map(keys.next, 1, 'Next book of the Bible')
  map(keys.previous, -1, 'Previous book of the Bible')
end

return M
