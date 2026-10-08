-- The plugin's options and their defaults (see :help topos-bible-setup)
local M = {}

M.defaults = {
  -- topos-lsp's settings, overriding ~/.config/topos/config.toml (the CLI's keys), like
  -- { format = 'abbreviation', ['psg-fmt'] = { join_adjacent = true },
  --   ['inlay-hints'] = 'never', ['reference-diagnostics'] = 'hint', ext = 'md,txt',
  --   hover = { 'osis', 'book', 'genres', 'verses' } }
  settings = {},
  -- A folder of USX files (one book each, like JHN.usx, as Paratext, the Digital Bible Library,
  -- and eBible.org publish them): hover shows a reference's text, and go-to-definition opens the
  -- whole book in a read-only buffer
  bible = nil,
  -- How Bible text is written and colored. `show` and `display` change the text (`display` is a
  -- label: {verse}, {chapter}, {name} like John, {book} like JHN); `color` is a color ('red',
  -- '#5f87d7') or a highlight ({ fg = 'red', bold = true }), nil for the colorscheme's
  markup = {
    verse_numbers = { show = true, display = '[{verse}]', color = nil },
    chapter_numbers = { show = true, display = '{name} {chapter}', color = nil },
    words_of_jesus = { show = true, color = nil },
    headings = { show = true, color = nil },
    notes = { show = false, color = nil },
  },
  lsp = {
    enabled = true,
    filetypes = { 'markdown', 'text' },
    -- The folder searched by go-to-references, the code actions, and the search commands
    root_markers = { '.git', '.obsidian' },
    -- Show how each reference is written in your format (see `settings['inlay-hints']`)
    inlay_hints = true,
    -- The same as the top-level `settings` (which win where both set a key)
    settings = {},
  },
  -- Paths to the binaries; nil uses the plugin's own build, then your PATH
  cmd = { lsp = nil, cli = nil },
  -- What :ToposBuild builds: nil for the topos repository on GitHub, or a topos checkout
  source = nil,
  -- Build the binaries when setup can't find them (takes a few minutes the first time)
  auto_build = true,
  -- 'telescope', 'quickfix', or 'auto' (Telescope if it is installed)
  picker = 'auto',
}

M.options = vim.deepcopy(M.defaults)

function M.set(opts)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
end

-- The language server's settings: `bible` and `markup`, then `lsp.settings`, then the top-level
-- `settings`
function M.lsp_settings()
  local bible = M.options.bible and { bible = vim.fn.expand(M.options.bible), markup = M.options.markup }
    or { markup = M.options.markup }
  return vim.tbl_deep_extend('force', bible, M.options.lsp.settings or {}, M.options.settings or {})
end

return M
