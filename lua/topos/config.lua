-- The plugin's options and their defaults (see :help topos-bible-setup)
local M = {}

M.defaults = {
  -- biblix-lsp's settings, overriding ~/.config/topos/config.toml (the CLI's keys), like
  -- { format = 'abbreviation', ['psg-fmt'] = { join_adjacent = true },
  --   ['inlay-hints'] = 'never', ['reference-diagnostics'] = 'hint', ext = 'md,txt',
  --   hover = { 'osis', 'book', 'genres', 'verses' } }
  settings = {},
  -- A folder of USX files (one book each, like JHN.usx, as Paratext, the Digital Bible Library,
  -- and eBible.org publish them): hover shows a reference's text, and go-to-definition opens the
  -- whole book in a read-only buffer
  bible = nil,
  -- More Bibles by name, each a folder of USX files, or a folder and other ways to write its name:
  -- { KJV = '~/Bibles/KJV', NET = { path = '~/Bibles/NET', aliases = { 'NET2' } } }. A reference
  -- followed by a Bible's name or alias (John 3:16 KJV, John 3:16 (KJV)) uses that Bible's text
  -- in hover and go-to-definition, and its own verse counts
  bibles = {},
  -- The Bible for references that name none (a name or alias): `bible`'s by default, else the
  -- first of `bibles` by name. :ToposBible changes it while Neovim runs
  default_bible = nil,
  -- Bibles whose text hover also shows, after the one a reference names, like { 'BSB', 'KJV' }
  hover_bibles = nil,
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
  -- Search EPUBs in the workspace too: go-to-references and the search commands list their
  -- references, which open in a read-only buffer of the book's text (`topos-file:///…/Gill.epub`)
  -- at the reference. Off by default: a book takes a moment to read the first time (then it's
  -- cached, with the topos CLI's cache)
  epub = false,
  -- Search PDFs the same way, building biblix-lsp with PDF support (MuPDF: needs a C compiler and
  -- takes longer)
  pdf = false,
  -- Ways to insert a passage's text below a reference, each a code action ("Insert Callout"):
  --   name         the action is "Insert {name}"
  --   display      what is inserted: {text} (the passage), {reference} (John 3:16), {osis}
  --                (John.3.16), {bible} (the Bible's name); default '{text}'
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
  cmd = { lsp = nil, cli = nil, bx = nil },
  -- What :ToposBuild builds from: a topos checkout ('~/src/topos', with biblix beside it), or
  -- { topos = '~/src/topos', biblix = '~/src/biblix' }; nil for GitHub (biblix-lsp can't be
  -- installed from GitHub until biblix is published, so set a biblix checkout for now)
  source = nil,
  -- Build the binaries when setup can't find them (takes a few minutes the first time)
  auto_build = true,
  -- Where :ToposNextBook, :ToposNextChapter, :ToposNextVerse (and :ToposPrev*) go past the end
  -- (or start). They have no keys of their own; for example:
  --   vim.keymap.set('n', ']b', function() require('topos').next_book(vim.v.count1) end)
  --   vim.keymap.set('n', '[b', function() require('topos').prev_book(vim.v.count1) end)
  --   ]c / [c for chapters (next_chapter, prev_chapter), ]v / [v for verses (next_verse,
  --   prev_verse)
  navigation = {
    -- 'wrap' (Revelation → Genesis) or 'stop'
    books = 'wrap',
    -- 'next' (the next book's first chapter, as `books` says), 'wrap' (this book's first), or
    -- 'stop'
    chapters = 'next',
    -- 'next' (the next chapter's first verse, as `chapters` says), 'wrap' (this chapter's
    -- first), or 'stop'
    verses = 'next',
  },
  -- 'telescope', 'quickfix', or 'auto' (Telescope if it is installed)
  picker = 'auto',
}

M.options = vim.deepcopy(M.defaults)

function M.set(opts)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
end

-- `bibles` with each folder expanded (`~/Bibles/KJV`)
local function expanded_bibles()
  local bibles = {}
  for name, bible in pairs(M.options.bibles or {}) do
    if type(bible) == 'table' then
      bibles[name] = { path = vim.fn.expand(bible.path), aliases = bible.aliases or {} }
    else
      bibles[name] = vim.fn.expand(bible)
    end
  end
  return bibles
end

-- The language server's settings: `bible`, `bibles`, `default_bible`, `hover_bibles`, `markup`,
-- `insertions`, `epub`, and `pdf`, then `lsp.settings`, then the top-level `settings`
function M.lsp_settings()
  local base = { markup = M.options.markup, insertions = M.options.insertions }
  if M.options.bible then
    base.bible = vim.fn.expand(M.options.bible)
  end
  if next(M.options.bibles or {}) then
    base.bibles = expanded_bibles()
  end
  base['default-bible'] = M.options.default_bible
  base['hover-bibles'] = M.options.hover_bibles
  if M.options.epub then
    base.epub = true
  end
  if M.options.pdf then
    base.pdf = true
  end
  return vim.tbl_deep_extend('force', base, M.options.lsp.settings or {}, M.options.settings or {})
end

return M
