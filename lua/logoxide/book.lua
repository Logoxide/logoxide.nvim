--[[
Whole books of the `bible` option as read-only buffers, named like `logoxide://BSB/JHN`.
Go-to-definition on a reference opens one at the passage; `:edit logoxide://BSB/JHN` works too.
logoxide-lsp renders the book (with `markup`'s labels) and colors it with semantic tokens, which
`markup`'s colors set; references from a verse list every reference to it in the workspace.

Books (EPUBs and PDFs, with the `epub` and `pdf` options) open the same way, as `logoxide-file:///…/Gill.epub`:
the book's text, where the workspace searches put its references.

Passages in hover (and completion documentation) are ```logoxide code blocks whose info
string, which Neovim hides, says what to color (line:column:length:type, in bytes); the plugin
colors them the same way.
]]
local config = require('logoxide.config')

local M = {}

M.scheme = 'logoxide'
-- An EPUB's or PDF's text, from the `epub` and `pdf` options' search results
M.file_scheme = 'logoxide-file'

-- `markup` key → semantic token type, and the highlight it links to without a `color`
M.highlights = {
  verse_numbers = { 'verseNumber', 'Number' },
  chapter_numbers = { 'chapterNumber', 'Title' },
  words_of_jesus = { 'wordsOfJesus', 'DiagnosticError' },
  headings = { 'heading', 'Title' },
  notes = { 'note', 'Comment' },
  added = { 'added', '@markup.italic' },
  divine_name = { 'divineName', '@markup.strong' },
  quotes = { 'quote', '@markup.quote' },
}

-- The token types in logoxide-lsp's order (the numbers in a code block's info string)
M.legend = { 'verseNumber', 'chapterNumber', 'wordsOfJesus', 'heading', 'note', 'added', 'divineName', 'quote' }

-- The highlight group for a token type in book buffers
function M.group(token)
  return ('@lsp.type.%s.%s'):format(token, M.scheme)
end

-- Sets the highlights from `markup`'s colors (again after a colorscheme clears them)
function M.apply_highlights()
  -- Normal's foreground only, so a float keeps its background
  local normal = vim.api.nvim_get_hl(0, { name = 'Normal', link = false })
  vim.api.nvim_set_hl(0, 'LogoxideBibleText', { fg = normal.fg, ctermfg = normal.ctermfg, default = true })
  for key, highlight in pairs(M.highlights) do
    local element = config.options.markup[key] or {}
    local color = element.color
    local spec
    if type(element.highlight) == 'string' then
      spec = { link = element.highlight }
    elseif type(color) == 'string' then
      spec = { fg = color }
    elseif type(color) == 'table' then
      spec = color
    else
      spec = { link = highlight[2], default = true }
    end
    vim.api.nvim_set_hl(0, M.group(highlight[1]), spec)
  end
end

-- The logoxide-lsp client to ask: the one in the buffer we came from, else any
local function client_for(bufnr)
  local previous = vim.fn.bufnr('#')
  if previous > 0 and previous ~= bufnr then
    local client = vim.lsp.get_clients({ bufnr = previous, name = 'logoxide' })[1]
    if client then
      return client
    end
  end
  -- Started if it isn't running (`:edit logoxide://BSB/JHN` before any note)
  return require('logoxide').ensure_lsp()
end

-- Fills a `logoxide://` buffer with its book, read-only, and attaches the language server
function M.read(bufnr, uri)
  local client = client_for(bufnr)
  if not client then
    return
  end
  local response, err = client:request_sync('logoxide/book', { uri = uri }, 10000, bufnr)
  if not response or response.err then
    local message = err or (response and response.err.message) or 'no response'
    return vim.notify('logoxide: ' .. message, vim.log.levels.ERROR)
  end
  local book = response.result
  local bo = vim.bo[bufnr]
  bo.modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(book.text, '\n'))
  bo.buftype = 'nofile'
  bo.bufhidden = 'hide'
  bo.swapfile = false
  bo.modified = false
  bo.modifiable = false
  bo.readonly = true
  vim.b[bufnr].logoxide_book = book.title
  bo.filetype = M.scheme
  vim.lsp.buf_attach_client(bufnr, client.id)
end

-- Fills a `logoxide-file://` buffer with the book's text, read-only, and attaches the language server
-- (hover on its references)
function M.read_file(bufnr, uri)
  local client = client_for(bufnr)
  if not client then
    return
  end
  local response, err = client:request_sync('logoxide/fileText', { uri = uri }, 60000, bufnr)
  if not response or response.err then
    local message = err or (response and response.err.message) or 'no response'
    return vim.notify('logoxide: ' .. message, vim.log.levels.ERROR)
  end
  local book = response.result
  local bo = vim.bo[bufnr]
  bo.modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(book.text, '\n'))
  bo.buftype = 'nofile'
  bo.bufhidden = 'hide'
  bo.swapfile = false
  bo.modified = false
  bo.modifiable = false
  bo.readonly = true
  vim.b[bufnr].logoxide_book = book.title
  bo.filetype = M.file_scheme
  vim.lsp.buf_attach_client(bufnr, client.id)
end

local fence_ns = vim.api.nvim_create_namespace('topos_bible_fences')

-- Colors the ```logoxide code blocks in a Markdown buffer (a hover or documentation float);
-- `tokens` is for blocks whose info string has none (completion documentation)
function M.color_fences(bufnr, tokens)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  vim.api.nvim_buf_clear_namespace(bufnr, fence_ns, 0, -1)
  for i, line in ipairs(lines) do
    local info = line:match('^%s*```+' .. vim.pesc(M.scheme) .. '%s*(.*)$')
    if info == '' and tokens then
      info = tokens
    end
    -- The block's text as text, not code (LogoxideBibleText)
    local last = info and i
    while last and lines[last + 1] and not lines[last + 1]:match('^%s*```+%s*$') do
      last = last + 1
    end
    if last and last > i then
      pcall(vim.api.nvim_buf_set_extmark, bufnr, fence_ns, i, 0, {
        end_row = last - 1,
        end_col = #lines[last],
        hl_group = 'LogoxideBibleText',
        priority = 150,
      })
    end
    for row, col, len, kind in (info or ''):gmatch('(%d+):(%d+):(%d+):(%d+)') do
      local token = M.legend[tonumber(kind) + 1]
      local lnum = i + tonumber(row) -- the block starts on the line after the fence (0-based i)
      if token and lines[lnum + 1] then
        pcall(vim.api.nvim_buf_set_extmark, bufnr, fence_ns, lnum, tonumber(col), {
          end_col = tonumber(col) + tonumber(len),
          hl_group = M.group(token),
          priority = 200,
        })
      end
    end
  end
end

--[[
blink.cmp's `completion.documentation.draw`: its own drawing, then the passage colored (from the
item's `data.tokens`, since blink.cmp shows a code block's info string)
  completion = { documentation = { draw = function(opts) require('logoxide').blink_draw(opts) end } }
]]
function M.blink_draw(opts)
  opts.default_implementation()
  local data = opts.item and opts.item.data
  if type(data) == 'table' and type(data.tokens) == 'string' then
    M.color_fences(opts.window:get_buf(), data.tokens)
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup('logoxide_books', { clear = true })
  vim.api.nvim_create_autocmd('BufReadCmd', {
    group = group,
    pattern = M.scheme .. '://*',
    callback = function(args)
      M.read(args.buf, args.match)
    end,
  })
  vim.api.nvim_create_autocmd('BufReadCmd', {
    group = group,
    pattern = M.file_scheme .. '://*',
    callback = function(args)
      M.read_file(args.buf, args.match)
    end,
  })
  vim.api.nvim_create_autocmd('ColorScheme', { group = group, callback = M.apply_highlights })
  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = 'markdown',
    callback = function(args)
      M.color_fences(args.buf)
    end,
  })
  M.apply_highlights()
end

return M
