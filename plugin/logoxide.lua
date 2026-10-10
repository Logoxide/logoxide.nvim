-- The commands exist from startup (so lazy.nvim can load the plugin on first use); setup() is
-- what starts the language server
if vim.g.loaded_logoxide then
  return
end
vim.g.loaded_logoxide = true
require('logoxide.commands').create()
