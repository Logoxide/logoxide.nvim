--[[
Several Bibles (`bible` and `bibles`): which one references use by default (:LxBible), and a
whole book next to the same book in another Bible, kept on the same verse (:LxParallel).
]]
local config = require('logoxide.config')

local M = {}

local function client()
  return vim.lsp.get_clients({ name = 'logoxide' })[1]
end

-- logoxide-lsp's Bibles, the default first: { { name, aliases, books } }
function M.list()
  local c = client()
  if not c then
    return {}
  end
  local response = c:request_sync('logoxide/bibles', vim.empty_dict(), 5000, 0)
  return response and response.result and response.result.bibles or {}
end

-- The names, for command completion
function M.names()
  return vim.tbl_map(function(bible)
    return bible.name
  end, M.list())
end

-- The Bible of a `logoxide://BSB/JHN` buffer
local function bible_of(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr):match('^logoxide://([^/]+)/')
  return name and vim.uri_decode(name)
end

-- Asks for a Bible (other than `except`), then calls `done` with its name
local function choose(prompt, except, done)
  local names = vim.tbl_filter(function(name)
    return name ~= except
  end, M.names())
  if #names == 0 then
    return vim.notify('logoxide: no other Bible (set `bible` or `bibles`)', vim.log.levels.WARN)
  end
  vim.ui.select(names, { prompt = prompt }, function(name)
    if name then
      done(name)
    end
  end)
end

-- :LxBible [name]: references that name no Bible use this one (without a name, choose one)
function M.set_default(name)
  if not name or name == '' then
    local current = M.list()[1]
    return choose('Default Bible' .. (current and (' (now ' .. current.name .. ')') or ''), nil, M.set_default)
  end
  config.options.default_bible = name
  local settings = { logoxide = config.lsp_settings() }
  for _, c in ipairs(vim.lsp.get_clients({ name = 'logoxide' })) do
    c.settings = settings
    c:notify('workspace/didChangeConfiguration', { settings = settings })
  end
end

-- Where the verse at the cursor of `win` is in `bible`'s book, then `done(location)`
local function same_verse(win, bible, done)
  local c = client()
  local bufnr = vim.api.nvim_win_get_buf(win)
  if not c then
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(win)
  local line = vim.api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], false)[1] or ''
  local params = {
    uri = vim.api.nvim_buf_get_name(bufnr),
    position = { line = cursor[1] - 1, character = vim.str_utfindex(line, 'utf-16', cursor[2], false) },
    bible = bible,
  }
  c:request('logoxide/sameVerse', params, function(err, location)
    if err then
      return vim.notify('logoxide: ' .. err.message, vim.log.levels.ERROR)
    end
    done(location)
  end, bufnr)
end

-- Windows `follow` is moving, whose moves aren't followed back
local following = {}

-- Each window kept on the same verse as others (:LxParallel) → its group, a set of windows
local groups = {}

-- The verse the cursor is on, marked in the group's other windows
local verse_ns = vim.api.nvim_create_namespace('logoxide_parallel_verse')

-- A 0-based LSP position in `bufnr` as a 0-based row and byte column
local function byte_position(bufnr, position)
  local row = math.min(position.line, vim.api.nvim_buf_line_count(bufnr) - 1)
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''
  local ok, col = pcall(vim.str_byteindex, line, 'utf-16', position.character, false)
  return row, ok and col or 0
end

local function unmark(win)
  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_buf_clear_namespace(vim.api.nvim_win_get_buf(win), verse_ns, 0, -1)
  end
end

-- Marks `range` (the verse) in `win`'s buffer, unless `parallel.highlight` is false
local function mark(win, range)
  unmark(win)
  if config.options.parallel.highlight == false then
    return
  end
  local bufnr = vim.api.nvim_win_get_buf(win)
  local row, col = byte_position(bufnr, range.start)
  local end_row, end_col = byte_position(bufnr, range['end'])
  if end_row > row or end_col > col then
    -- Under the text's own colors
    pcall(vim.api.nvim_buf_set_extmark, bufnr, verse_ns, row, col, {
      end_row = end_row,
      end_col = end_col,
      hl_group = 'LogoxideParallelVerse',
      priority = 100,
    })
  end
end

--[[
Moves `win` to `location`, the verse (opening its book there, when `from` went to another book),
at the same screen row as the cursor in `from`, and marks the verse; a cursor already in the
verse stays where it is
]]
local function follow(from, win, location)
  if not (location and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_is_valid(from)) then
    return
  end
  local offset = vim.api.nvim_win_get_cursor(from)[1] - vim.fn.line('w0', from)
  following[win] = true
  pcall(vim.api.nvim_win_call, win, function()
    if vim.api.nvim_buf_get_name(0) ~= location.uri then
      unmark(win)
      vim.cmd('edit ' .. vim.fn.fnameescape(location.uri))
    end
    local row, col = byte_position(0, location.range.start)
    local end_row, end_col = byte_position(0, location.range['end'])
    local cursor = vim.api.nvim_win_get_cursor(0)
    local at = { cursor[1] - 1, cursor[2] }
    local inside = (at[1] > row or (at[1] == row and at[2] >= col))
      and (at[1] < end_row or (at[1] == end_row and at[2] <= end_col))
    if not inside then
      vim.fn.winrestview({ lnum = row + 1, col = col, topline = math.max(1, row + 1 - offset) })
    end
  end)
  following[win] = nil
  mark(win, location.range)
end

-- Keeps the group's other windows on the verse (and book) `from`'s cursor is on
local function sync(from)
  if not bible_of(vim.api.nvim_win_get_buf(from)) then
    return
  end
  unmark(from)
  for to in pairs(groups[from]) do
    local bible = to ~= from and vim.api.nvim_win_is_valid(to) and bible_of(vim.api.nvim_win_get_buf(to))
    if bible then
      same_verse(from, bible, function(location)
        follow(from, to, location)
      end)
    end
  end
end

-- Puts `b` in `a`'s group (keeping each on the verse any other's cursor is on, until it closes)
local function link(a, b)
  local group = groups[a] or { [a] = true }
  group[b] = true
  groups[a], groups[b] = group, group
  local augroup = vim.api.nvim_create_augroup('logoxide_parallel', { clear = true })
  -- And when one goes to another book (:LxNextBook), the others go too
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'BufWinEnter' }, {
    group = augroup,
    callback = function()
      local win = vim.api.nvim_get_current_win()
      if groups[win] and not following[win] then
        sync(win)
      end
    end,
  })
  vim.api.nvim_create_autocmd('WinClosed', {
    group = augroup,
    callback = function(args)
      local closed = tonumber(args.match)
      local rest = groups[closed]
      if not rest then
        return
      end
      unmark(closed)
      rest[closed], groups[closed] = nil, nil
      -- One window left is no longer parallel
      if vim.tbl_count(rest) == 1 then
        local last = next(rest)
        unmark(last)
        groups[last] = nil
      end
    end,
  })
end

-- :LxParallel [name]: this whole book in another Bible, in a split at the same verse, and
-- all kept on the same verse as any one's cursor moves (to another book too), the verse marked
-- in the others (`parallel`); from a window already parallel, a third joins them
function M.parallel(name, mods)
  local win = vim.api.nvim_get_current_win()
  local current = bible_of(vim.api.nvim_win_get_buf(win))
  if not current then
    return vim.notify('logoxide: :LxParallel works in a whole book (go to definition on a reference)', vim.log.levels.WARN)
  end
  if not name or name == '' then
    return choose('Show next to ' .. current, current, function(chosen)
      M.parallel(chosen, mods)
    end)
  end
  same_verse(win, name, function(location)
    if not location then
      return vim.notify('logoxide: ' .. name .. ' doesn\'t have this book', vim.log.levels.WARN)
    end
    vim.cmd((mods and mods ~= '' and mods or 'vertical') .. ' split ' .. vim.fn.fnameescape(location.uri))
    local other = vim.api.nvim_get_current_win()
    follow(win, other, location)
    link(win, other)
    -- The verse marked in the others
    sync(other)
  end)
end

return M
