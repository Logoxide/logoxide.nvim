-- :checkhealth topos
local M = {}

function M.check()
  local bin = require('topos.bin')
  local config = require('topos.config')
  vim.health.start('topos-bible.nvim')
  for _, kind in ipairs({ 'lsp', 'cli' }) do
    local name = kind == 'lsp' and 'biblix-lsp' or 'topos'
    local path = bin.path(kind)
    if path then
      local version = vim.system({ path, '--version' }, { text = true }):wait().stdout or ''
      vim.health.ok(('%s: %s %s'):format(name, path, vim.trim(version)))
    else
      vim.health.error(name .. ' not found', { 'Run :ToposBuild (needs Rust: https://rustup.rs)' })
    end
  end
  if vim.fn.executable('cargo') == 1 then
    vim.health.ok('cargo is available to build with')
  else
    vim.health.warn('cargo not found: :ToposBuild needs Rust (https://rustup.rs)')
  end
  local settings = config.lsp_settings()
  local folders = {}
  if settings.bible then
    table.insert(folders, { vim.fn.fnamemodify(settings.bible, ':t'), settings.bible })
  end
  for name, bible in pairs(settings.bibles or {}) do
    table.insert(folders, { name, type(bible) == 'table' and bible.path or bible })
  end
  if #folders == 0 then
    vim.health.info('No Bible: set `bible` (or `bibles`) to a folder of USX files for passage text and go-to-definition')
  end
  for _, folder in ipairs(folders) do
    local name, path = folder[1], folder[2]
    local books = #vim.fn.glob(vim.fs.joinpath(path, '*.[uU][sS][xX]'), false, true)
    if books > 0 then
      vim.health.ok(('Bible %s: %s (%d books)'):format(name, path, books))
    else
      vim.health.error(('Bible %s: no USX files in %s'):format(name, path))
    end
  end
  if pcall(require, 'telescope') then
    vim.health.ok('Telescope: results open in its pickers')
  else
    vim.health.info('Telescope is not installed: results open in the quickfix list')
  end
  if #vim.lsp.get_clients({ name = 'topos' }) > 0 then
    vim.health.ok('biblix-lsp is running')
  elseif config.options.lsp.enabled then
    vim.health.info('biblix-lsp is not attached to any buffer yet (open a ' .. table.concat(config.options.lsp.filetypes, ' or ') .. ' file)')
  end
end

return M
