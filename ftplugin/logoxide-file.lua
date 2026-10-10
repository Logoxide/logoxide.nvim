-- A book's text from logoxide.nvim (logoxide-file:///…/Gill.epub): long paragraphs, wrapped at words
vim.opt_local.wrap = true
vim.opt_local.linebreak = true
vim.opt_local.spell = false
vim.b.undo_ftplugin = 'setlocal wrap< linebreak< spell<'
