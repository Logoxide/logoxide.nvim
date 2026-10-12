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

-- Moves `win` to `location` (opening its book there, when `from` went to another book), at the
-- same screen row as the cursor in `from`
local function follow(from, win, location)
  if not (location and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_is_valid(from)) then
    return
  end
  local offset = vim.api.nvim_win_get_cursor(from)[1] - vim.fn.line('w0', from)
  following[win] = true
  pcall(vim.api.nvim_win_call, win, function()
    if vim.api.nvim_buf_get_name(0) ~= location.uri then
      vim.cmd('edit ' .. vim.fn.fnameescape(location.uri))
    end
    local row = math.min(location.range.start.line + 1, vim.api.nvim_buf_line_count(0))
    vim.fn.winrestview({ lnum = row, col = 0, topline = math.max(1, row - offset) })
  end)
  following[win] = nil
end

-- Keeps each window of a pair on the verse (and book) the other's cursor is on, until one closes
local function link(a, b)
  local group = vim.api.nvim_create_augroup(('logoxide_parallel_%d_%d'):format(a, b), { clear = true })
  local function sync(from, to)
    local bible = bible_of(vim.api.nvim_win_get_buf(to))
    if bible and bible_of(vim.api.nvim_win_get_buf(from)) then
      same_verse(from, bible, function(location)
        follow(from, to, location)
      end)
    end
  end
  -- And when either goes to another book (:LxNextBook), the other goes too
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'BufWinEnter' }, {
    group = group,
    callback = function()
      local win = vim.api.nvim_get_current_win()
      if following[win] then
        return
      elseif win == a then
        sync(a, b)
      elseif win == b then
        sync(b, a)
      end
    end,
  })
  vim.api.nvim_create_autocmd('WinClosed', {
    group = group,
    callback = function(args)
      local closed = tonumber(args.match)
      if closed == a or closed == b then
        pcall(vim.api.nvim_del_augroup_by_id, group)
      end
    end,
  })
end

-- :LxParallel [name]: this whole book in another Bible, in a split at the same verse, and
-- both kept on the same verse as either's cursor moves (to another book too)
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
  end)
end

return M
