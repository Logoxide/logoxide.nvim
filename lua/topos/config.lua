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
  -- How Bible text is written and colored (see :help topos-bible-markup). Each element has:
  --   show       whether it is shown (hidden headings and notes are left out; the others are
  --              plain text, without their display or color)
  --   display    how it is written: for verse and chapter numbers a label with {verse},
  --              {chapter}, {name} (John), and {book} (JHN); for the others a template with
  --              {text} (the element's text), like '## {text}' or '“{text}”'
  --   color      a color ('red', '#5f87d7') or a highlight definition ({ fg = 'red', bold = true })
  --   highlight  or a highlight group to link to ('Comment'), instead of `color`
  -- Without `color` or `highlight`, each links to a group of your colorscheme
  markup = {
    verse_numbers = { show = true, display = '[{verse}]' },
    chapter_numbers = { show = true, display = '{name} {chapter}' },
    headings = { show = true, display = '{text}' },
    notes = { show = false, display = '[{text}]' },
    words_of_jesus = { show = true, display = '{text}' },
    -- Translators' additions (KJV italics)
    added = { show = true, display = '{text}' },
    -- LORD in small capitals
    divine_name = { show = true, display = '{text}' },
    -- Quotations other than words of Jesus
    quotes = { show = true, display = '{text}' },
    -- Lines longer than this many characters break at a space, in whole books, hover, and
    -- insertions (nil: no limit; whole books still wrap at the window's width)
    width = nil,
  },
  -- Ways to insert a passage's text below a reference, each a code action ("Insert Callout"):
  --   name         the action is "Insert {name}"
  --   display      what is inserted: {text} (the passage), {reference} (John 3:16), {osis}
  --                (John.3.16); default '{text}'
  --   line_prefix  written before each line of {text}, like '> '
  --   markup       `markup` for this insertion, over the one above (same keys; no colors)
  --   replace      what it replaces: 'line' (the reference's whole line), 'inline' (just the
  --                reference, keeping the rest of its line), or nil (insert on the lines below)
  -- like { name = 'Callout', display = '> [!bible] {reference}\n{text}', line_prefix = '> ' }
  insertions = {},
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

-- The language server's settings: `bible`, `markup`, and `insertions`, then `lsp.settings`,
-- then the top-level `settings`
function M.lsp_settings()
  local base = { markup = M.options.markup, insertions = M.options.insertions }
  if M.options.bible then
    base.bible = vim.fn.expand(M.options.bible)
  end
  return vim.tbl_deep_extend('force', base, M.options.lsp.settings or {}, M.options.settings or {})
end

return M
