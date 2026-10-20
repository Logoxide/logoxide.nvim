-- The plugin's options and their defaults (see :help logoxide-setup)
local M = {}

M.defaults = {
  -- logoxide-lsp's settings, overriding ~/.config/topos/config.toml (the CLI's keys; every key
  -- and its values are in :help logoxide-settings), like
  -- { format = 'abbreviation',                        -- 'name', 'abbreviation', 'osis', 'usfm'
  --   ['psg-fmt'] = { join_adjacent = true },
  --   ['inlay-hints'] = 'never',                      -- 'changed', 'always', 'osis', 'usfm',
  --                                                   -- 'never', a template's name, or '{first:1}'
  --   ['reference-diagnostics'] = 'hint',             -- 'info', 'hint', 'never'
  --   ['reference-diagnostics-template'] = 'verse',   -- a template's name, or a template
  --   ext = 'md,txt',
  --   hover = { 'osis', 'book', 'genres', 'verses' } } -- the lines under a reference's hover
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
  -- first of `bibles` by name. :LxBible changes it while Neovim runs
  default_bible = nil,
  -- Bibles whose text hover also shows, after the one a reference names, like { 'BSB', 'KJV' }
  hover_bibles = nil,
  -- How hover (and completion documentation) shows a passage's text, a note's, or an entry's:
  --   trim  leave out its leading whitespace (a chapter label or heading displayed after a line
  --         break, '\n{text}', starts the float with a blank line). Off by default
  --   max   how many characters (bytes) to show before cutting it with ' …'; false (or 0) for
  --         no limit
  --   title  the hover's first line: {reference} (as formatted), {bible} (the Bible whose text
  --          shows first), {translation} (the Bible the reference names; when it names none,
  --          nothing, with the brackets around it); false for no first line. Default
  --          '**{reference}** ({translation})'
  --   book   what hovering a verse in a whole book shows, in this order: 'references' (how many
  --          references name it, in how many files), 'translations' (the verse in the other
  --          Bibles: `hover_bibles`' when set, else every other), and 'current' (the verse in the
  --          Bible being read); {} for no hover. Default { 'references' }
  --   line   hovering a line away from any reference shows every reference on it, one after
  --          another (so a line's only reference hovers from anywhere on it). Off by default
  hover = { trim = false, max = 2000, title = nil, book = nil, line = false },
  -- How Bible text is written and colored (see :help logoxide-markup). Each element has:
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
    -- templates (nil: no limit; whole books still wrap at the window's width)
    width = nil,
    -- Spaces before each line of poetry, by its USFM marker: a verse's first line (q1) at the
    -- margin, the lines that continue it (q2, q3, ...) further in. Other markers can be added,
    -- like qr (Selah), qm1, pi1 (indented paragraphs), or li1 (lists)
    indent = { q1 = 0, q2 = 2, q3 = 4, q4 = 6 },
    -- Each verse on a line of its own (a verse that starts a line of poetry keeps its indent)
    verse_lines = false,
    -- A blank line between paragraphs (and around poetry), but not under a heading
    paragraph_gaps = false,
  },
  -- Completion offers the chapter or verse already typed, first (`Matthew 1` offers Matthew 1,
  -- then Matthew 10, ...), so its passage shows in the documentation. On by default
  complete_typed = true,
  -- Search EPUBs in the workspace too: go-to-references and the search commands list their
  -- references, which open in a read-only buffer of the book's text (`logoxide-file:///…/Gill.epub`)
  -- at the reference. Off by default: a book takes a moment to read the first time (then it's
  -- cached, with the topos CLI's cache)
  epub = false,
  -- Search PDFs the same way, building logoxide-lsp with PDF support (MuPDF: needs a C compiler and
  -- takes longer)
  pdf = false,
  -- Commentaries whose notes on a passage hover shows after its text, each labeled with the
  -- commentary's name and the verses the note covers: true for every commentary the project
  -- uses (lx add them), or their ids, like { 'mhcc' }. Off by default
  commentaries = nil,
  -- A commentary's note also covers the verses after it up to its next note in the chapter, so
  -- hovering a verse the commentary skips shows the note before it. Off by default
  stretch_notes = false,
  -- Hovering a Strong's number (G25, H430, G0025) shows its entry in the project's Strong's
  -- dictionaries (lexicons with keys = "strongs-greek" or "strongs-hebrew"). Off by default
  strongs = false,
  -- Named templates for a reference: code actions that write a passage's text, the forms
  -- :LxCopy and :LxInsert offer, and what settings['reference-diagnostics-template'] and
  -- ['inlay-hints'] can name
  --   display      what it writes: {text} (the passage), {first:N} and {last:N} (its first or
  --                last N verses), {reference} (John 3:16), {osis} (John.3.16), {usfm}
  --                (JHN 3:16), {bible} (the Bible's name), {translation} (its name unless it's
  --                the default Bible and the reference names none; then nothing, with the
  --                brackets around it, so '{reference} ({translation})' is 'John 3:16');
  --                default '{text}'
  --   line_prefix  written before each line of the text, like '> '
  --   markup       `markup` for this template, over the one above (same keys; no colors)
  --   action       its code action: 'insert' (on the lines below: "Insert callout"),
  --                'replace-line' (the reference's whole line), 'replace' (just the
  --                reference, keeping the rest of its line), or nil (none: for :LxCopy,
  --                diagnostics, and inlay hints)
  -- like { callout = { display = '> [!bible] {reference}\n{text}', line_prefix = '> ',
  --   action = 'insert' }, verse = { display = '{first:1}', markup = { headings = { show = false } } } }
  templates = {},
  lsp = {
    enabled = true,
    filetypes = { 'markdown', 'text' },
    -- The folder searched by go-to-references, the code actions, and the search commands
    root_markers = { '.git', '.obsidian' },
    -- More folders those searches cover, beside the root: like { '~/Obsidian' } to find
    -- references in a vault from notes elsewhere (relative ones are in the root)
    search_folders = {},
    -- Show how each reference is written in your format (see `settings['inlay-hints']`)
    inlay_hints = true,
    -- The same as the top-level `settings` (which win where both set a key)
    settings = {},
  },
  -- Paths to the binaries; nil uses the plugin's own build, then your PATH
  cmd = { lsp = nil, cli = nil, lx = nil },
  -- What :LxBuild builds from: nil for GitHub, a topos checkout ('~/src/topos', with logoxide
  -- beside it), or { topos = '~/src/topos', logoxide = '~/src/logoxide' }
  source = nil,
  -- Build the binaries when setup can't find them (takes a few minutes the first time)
  auto_build = true,
  -- Where :LxNextBook, :LxNextChapter, :LxNextVerse, :LxNextHeading (and :LxPrev*) go past the
  -- end (or start). They have no keys of their own; for example:
  --   vim.keymap.set('n', ']b', function() require('logoxide').next_book(vim.v.count1) end)
  --   vim.keymap.set('n', '[b', function() require('logoxide').prev_book(vim.v.count1) end)
  --   ]c / [c for chapters (next_chapter, prev_chapter), ]v / [v for verses (next_verse,
  --   prev_verse), ]h / [h for headings (next_heading, prev_heading)
  navigation = {
    -- 'wrap' (Revelation → Genesis) or 'stop'
    books = 'wrap',
    -- 'next' (the next book's first chapter, as `books` says), 'wrap' (this book's first), or
    -- 'stop'
    chapters = 'next',
    -- 'next' (the next chapter's first verse, as `chapters` says), 'wrap' (this chapter's
    -- first), or 'stop'
    verses = 'next',
    -- 'next' (the next book's first heading, as `books` says), 'wrap' (this book's first), or
    -- 'stop'
    headings = 'next',
  },
  -- :LxParallel's windows: the verse the cursor is on is marked in the others
  -- (LogoxideParallelVerse, linked to CursorLine by default)
  --   highlight  a highlight group to link to ('Visual'), or false to mark nothing
  --   color      or a background color ('#2a3340'), or a highlight definition
  --              ({ bg = '#2a3340', italic = true })
  parallel = { highlight = nil, color = nil },
  -- :LxReadAt's preview: how many verses before the one chosen are shown above it (the chapter
  -- from its label when there are fewer)
  read_at = { context = 3 },
  -- 'telescope', 'quickfix', or 'auto' (Telescope if it is installed)
  picker = 'auto',
  -- Whether searches reuse the topos CLI's cache for files that haven't changed (`--cache`);
  -- false never does (`--no-cache`), and nil leaves it to ~/.config/topos/config.toml
  cache = true,
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

-- The language server's settings: `bible`, `bibles`, `default_bible`, `hover_bibles`, `hover`, `markup`,
-- `templates`, `complete_typed`, `epub`, `pdf`, `commentaries`, `stretch_notes`, and `strongs`, then `lsp.settings`, then the top-level `settings`
-- `lsp.search_folders`, `~` and environment variables expanded
function M.search_folders()
  return vim.tbl_map(function(folder)
    return vim.fn.expand(folder)
  end, M.options.lsp.search_folders or {})
end

function M.lsp_settings()
  local base = { markup = M.options.markup }
  -- A table of names (an empty one would be a JSON array)
  if next(M.options.templates or {}) then
    base.templates = M.options.templates
  end
  -- The old option, which the server explains
  base.insertions = M.options.insertions
  -- An empty table is a JSON array, which isn't `indent`'s map
  if vim.tbl_isempty(M.options.markup.indent or {}) then
    base.markup = vim.tbl_extend('force', M.options.markup, { indent = vim.empty_dict() })
  end
  if M.options.bible then
    base.bible = vim.fn.expand(M.options.bible)
  end
  if next(M.options.bibles or {}) then
    base.bibles = expanded_bibles()
  end
  base['default-bible'] = M.options.default_bible
  base['hover-bibles'] = M.options.hover_bibles
  local hover = M.options.hover or {}
  if hover.trim then
    base['hover-trim'] = true
  end
  if hover.line then
    base['hover-line'] = true
  end
  if hover.max ~= nil then
    base['hover-max'] = hover.max or 0
  end
  if hover.title ~= nil then
    base['hover-title'] = hover.title or ''
  end
  if hover.book ~= nil then
    -- An empty table is a JSON array, which is what `book-hover` takes
    base['book-hover'] = hover.book
  end
  if M.options.complete_typed == false then
    base['complete-typed'] = false
  end
  if M.options.epub then
    base.epub = true
  end
  if M.options.pdf then
    base.pdf = true
  end
  base.commentaries = M.options.commentaries
  if M.options.stretch_notes then
    base['stretch-notes'] = true
  end
  if M.options.strongs then
    base.strongs = true
  end
  if next(M.options.lsp.search_folders or {}) then
    base['search-folders'] = M.search_folders()
  end
  return vim.tbl_deep_extend('force', base, M.options.lsp.settings or {}, M.options.settings or {})
end

return M
