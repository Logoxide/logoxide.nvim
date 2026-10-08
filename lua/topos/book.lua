--[[
Whole books of the `bible` option as read-only buffers, named like `topos-bible://BSB/JHN`.
Go-to-definition on a reference opens one at the passage; `:edit topos-bible://BSB/JHN` works too.
topos-lsp renders the book (with `markup`'s labels) and colors it with semantic tokens, which
`markup`'s colors set; references from a verse list every reference to it in the workspace.
]]
local config = require('topos.config')

local M = {}

M.scheme = 'topos-bible'

-- `markup` key → semantic token type, and the highlight it links to without a `color`
M.highlights = {
  verse_numbers = { 'verseNumber', 'Number' },
  chapter_numbers = { 'chapterNumber', 'Title' },
  words_of_jesus = { 'wordsOfJesus', 'DiagnosticError' },
  headings = { 'heading', 'Title' },
  notes = { 'note', 'Comment' },
}

-- The highlight group for a token type in book buffers
function M.group(token)
  return ('@lsp.type.%s.%s'):format(token, M.scheme)
end

-- Sets the highlights from `markup`'s colors (again after a colorscheme clears them)
function M.apply_highlights()
  for key, highlight in pairs(M.highlights) do
    local color = (config.options.markup[key] or {}).color
    local spec
    if type(color) == 'string' then
      spec = { fg = color }
    elseif type(color) == 'table' then
      spec = color
    else
      spec = { link = highlight[2], default = true }
    end
    vim.api.nvim_set_hl(0, M.group(highlight[1]), spec)
  end
end

-- The topos-lsp client to ask: the one in the buffer we came from, else any
local function client_for(bufnr)
  local previous = vim.fn.bufnr('#')
  if previous > 0 and previous ~= bufnr then
    local client = vim.lsp.get_clients({ bufnr = previous, name = 'topos' })[1]
    if client then
      return client
    end
  end
  return vim.lsp.get_clients({ name = 'topos' })[1]
end

-- Fills a `topos-bible://` buffer with its book, read-only, and attaches the language server
function M.read(bufnr, uri)
  local client = client_for(bufnr)
  if not client then
    return vim.notify('topos: topos-lsp is not running, so it can\'t open ' .. uri, vim.log.levels.ERROR)
  end
  local response, err = client:request_sync('topos/book', { uri = uri }, 10000, bufnr)
  if not response or response.err then
    local message = err or (response and response.err.message) or 'no response'
    return vim.notify('topos: ' .. message, vim.log.levels.ERROR)
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
  vim.b[bufnr].topos_book = book.title
  bo.filetype = M.scheme
  vim.lsp.buf_attach_client(bufnr, client.id)
end

function M.setup()
  local group = vim.api.nvim_create_augroup('topos_books', { clear = true })
  vim.api.nvim_create_autocmd('BufReadCmd', {
    group = group,
    pattern = M.scheme .. '://*',
    callback = function(args)
      M.read(args.buf, args.match)
    end,
  })
  vim.api.nvim_create_autocmd('ColorScheme', { group = group, callback = M.apply_highlights })
  M.apply_highlights()
end

return M
