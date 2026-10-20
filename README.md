# logoxide.nvim

Find, search, and complete Bible references in your notes, and read the passages they point to.
It runs logoxide's language server (`logoxide-lsp`, which was [topos](https://github.com/MasterTemple/topos-bible)'s `topos-lsp`)
and searches with topos's CLI (`topos`).

With [lazy.nvim](https://lazy.folke.io):

```lua
{
  'Logoxide/logoxide.nvim',
  main = 'logoxide',
  -- Builds logoxide-lsp and topos with Cargo (needs Rust: https://rustup.rs)
  build = ':LxBuild!',
  dependencies = { 'nvim-telescope/telescope.nvim' }, -- optional
  ft = { 'markdown', 'text' },
  cmd = { 'LxSearch', 'LxQuery', 'LxExplicitOverlap', 'LxAnyOverlap',
          'LxExactOverlap', 'LxInside', 'LxExcludeOverlap', 'LxFileReferences',
          'LxDirReferences', 'LxCopy', 'LxInsert', 'LxBuild', 'LxLspStart', 'LxLspStop',
          'LxBible', 'LxParallel', 'LxSwitch', 'LxResume', 'LxRead', 'LxReadAt',
          'LxBibleAdd', 'LxBibleSearch', 'LxBibleRemove', 'LxNextBook', 'LxPrevBook',
          'LxNextChapter', 'LxPrevChapter', 'LxNextVerse', 'LxPrevVerse',
          'LxNextHeading', 'LxPrevHeading' },
  opts = {
    -- A folder of USX files, one book each (JHN.usx): hover shows the text, and go to
    -- definition opens the whole book
    bible = '~/Bibles/BSB',
    -- More Bibles: a reference followed by one's name (John 3:16 KJV) uses it
    bibles = { KJV = { path = '~/Bibles/KJV', aliases = { 'AV' } } },
    hover_bibles = { 'KJV' }, -- hover shows the KJV too
    -- How it is written and colored (see :help logoxide-markup for every key)
    markup = {
      verse_numbers = { show = true, color = 'blue', display = '[{verse}]' },
      words_of_jesus = { show = true, color = 'red' },
      headings = { display = '## {text}', highlight = 'Title' }, -- a group instead of a color
      notes = { show = true, display = '({text})', highlight = 'Comment' },
      width = 80, -- break lines at 80 characters
      indent = { q1 = 0, q2 = 2 }, -- spaces before each line of poetry, by USFM marker
      verse_lines = true, -- each verse on a line of its own
      paragraph_gaps = true, -- a blank line between paragraphs
    },
    -- Named templates: code actions ("Insert callout"), :LxCopy's forms, and inlay hints
    templates = {
      -- action = 'insert' (below), 'replace-line', 'replace' (just the reference), or nil (none)
      callout = { display = '> [!bible] {reference}\n{text}', line_prefix = '> ', action = 'insert' },
      quote = { display = '“{text}” ({reference})', action = 'replace' },
      -- The first verse, without its heading: for ['reference-diagnostics-template'] = 'verse
      verse = { display = '{first:1}', markup = { headings = { show = false } } },
    },
    -- logoxide-lsp's settings: the CLI's config.toml keys, which these override
    -- (:help logoxide-settings lists every key and its values)
    settings = {
      format = 'name',                        -- or 'abbreviation' (Jn 3:16), 'osis', 'usfm'
      ['psg-fmt'] = { join_adjacent = true }, -- 3:16-18, not 3:16,17,18
      ['reference-diagnostics'] = 'hint',     -- 'info' (default), 'hint', or 'never'
      ['reference-diagnostics-template'] = 'verse', -- their text (the reference by default)
      ['inlay-hints'] = 'never',              -- 'changed' (default), 'always', 'osis', 'usfm', 'never',
                                              -- a template's name ('verse'), or a template
      ext = 'md,txt',                         -- what references and searches cover
    },
  },
}
```

- **Language server**: completion, hover, inlay hints, symbols, and diagnostics (each
  reference as formatted, and warnings for verses that don't exist); go to references (`grr`)
  lists the references that are exactly the one under the cursor, and the code actions (`gra`)
  reformat it or search for it by explicit overlap, any overlap, exact overlap, or inside it.
  `lsp.search_folders = { '~/Obsidian' }` has those searches (and `:LxSearch`) cover folders
  outside the workspace too
- **Books**: with `epub = true`, go-to-references and the search commands also list the
  references in the workspace's EPUBs (and with `pdf = true`, its PDFs, building logoxide-lsp with
  MuPDF); each opens in a read-only buffer of the book's text (`logoxide-file:///…/Gill.epub`) at
  the reference, where hover works too. Off by default: a book takes a moment to read the first
  time, then its references come from topos's cache (shared with the CLI). With epub.nvim
  installed (and topos on `$PATH`), an EPUB's references open in its rendered chapters instead, at
  the reference, and logoxide-lsp attaches to the chapters
- **Bible text**: with `bible`, hovering a reference shows its text (`K`), and so does a
  chapter or verse completion's documentation. Go to definition (`<C-]>`) or declaration opens
  the whole book in a read-only buffer at the passage, with verse numbers, chapters, headings,
  words of Jesus, and so on written and colored the way `markup` says. Go to references on a
  verse there lists every reference to it in your notes, and hovering it counts them (or, with
  `hover = { book = { 'current', 'translations', 'references' } }`, shows it in this Bible and
  your others too)
- **Reading**: `:LxRead John` opens a whole book (`1 cor` and `JHN` work too, and
  `:LxRead John KJV` another Bible's), and `:LxRead` alone chooses one in Telescope,
  previewing each book colored as it reads. `:LxReadAt John 3:16` opens a reference's book at
  its verse, and `:LxReadAt` alone (or `:LxReadAt KJV`) types one in Telescope: suggestions
  (books, then chapters, then verses) follow as you type, `<Tab>` takes one, and the preview shows
  the verse in the Bible below the verses before it (`read_at = { context = 3 }`). In a book,
  `:LxNextBook`, `:LxNextChapter`, `:LxNextVerse`, `:LxNextHeading` (and `:LxPrev*`) move through the Bible; `navigation` says
  what happens past the end (by default books wrap, chapters and headings go on to the next book,
  and verses to the next chapter). Poetry is a line each, indented by `markup.indent`;
  `markup.verse_lines` puts each verse on a line, and `markup.paragraph_gaps` a blank line
  between paragraphs. The plugin maps no keys; see below for some
- **Several Bibles**: with `bibles`, a reference followed by a Bible's name (`John 3:16 KJV`)
  uses that Bible for hover, go to definition, completion, templates, and its own verse counts;
  `:LxBible KJV` changes the default, and `:LxParallel KJV` opens the same book in another
  Bible next to the current one, kept on the same verse (and book, as either moves to another),
  with the verse marked in the other window (`parallel = { highlight = 'Visual' }` or
  `{ color = '#2a3340' }`; `CursorLine` by default); `:LxSwitch` opens it in another Bible in
  place, at the same verse (choosing one in Telescope previews the verse in each), and
  `:LxResume` goes back to the last place read in a whole book, in a later session too
- **Installing Bibles** (logoxide packages, with `lx`): `:LxBibleSearch world english` searches
  the catalogs (eBible.org's and fetch.bible's translations) and installs the one you choose,
  `:LxBibleAdd https://...` adds a package from its git repository (or `ebible:<id>`,
  `fetch:<id>`), and `:LxBibleRemove id` removes one. They use the current folder's
  `logoxide.toml` (else the library's own), like logoxide-lsp, which restarts to read them
- **Templates**: named forms of a passage (`{text}`, `{first:2}`, `{last:1}`, `{reference}`,
  ...), each with its own markup: code actions that write it below its reference (like an
  Obsidian callout), in place of its line, or in place of the reference; `:LxCopy` copies the
  passage under the cursor in one and `:LxInsert` writes it, choosing in Telescope with a
  preview (of the text, or for `:LxInsert` the diff of the buffer); and diagnostics and inlay hints can name one
  (`['reference-diagnostics-template'] = 'verse'`)
- **Commands**: `:LxSearch` (every reference), `:LxQuery -g Wisdom` (the CLI's options,
  completed with Tab), and `:LxExplicitOverlap John 3:16`, `:LxAnyOverlap`,
  `:LxExactOverlap`, `:LxInside`, `:LxExcludeOverlap` (the reference under the cursor
  by default), and `:LxFileReferences` / `:LxDirReferences` (the references in this buffer or
  under the current directory; in Telescope, typing a passage like `mat 1`, or a book alone,
  narrows them as you type)
- **Telescope**: `:Telescope logoxide`, plus a picker per search; without Telescope, results open
  in the quickfix list

Every command is a Lua function too (`require('logoxide').next_verse()`, `.read('John')`,
`.search()`, ...; see `:help logoxide-lua`), so you can map them; for example:

```lua
local logoxide = require('logoxide')
for lhs, move in pairs({
  [']b'] = logoxide.next_book, ['[b'] = logoxide.prev_book,
  [']c'] = logoxide.next_chapter, ['[c'] = logoxide.prev_chapter,
  [']v'] = logoxide.next_verse, ['[v'] = logoxide.prev_verse,
  [']h'] = logoxide.next_heading, ['[h'] = logoxide.prev_heading,
}) do
  vim.keymap.set('n', lhs, function() move(vim.v.count1) end)
end
```

With [blink.cmp](https://github.com/saghen/blink.cmp), color the passages in its
documentation window too:

```lua
completion = {
  documentation = { draw = function(opts) require('logoxide').blink_draw(opts) end },
}
```

The plugin and the CLI share `~/.config/topos/config.toml`. See `:help logoxide`, and
`:checkhealth logoxide` if something doesn't work.

## Building

`:LxBuild` installs `logoxide-lsp` and `lx` (from logoxide) and `topos` (from topos) into the plugin's
`build/` folder with `cargo install`, from checkouts if you set `source = '~/path/to/topos'` (with
logoxide beside it) or `source = { topos = ..., logoxide = ... }`, else from GitHub
([logoxide](https://github.com/Logoxide/logoxide) and [topos](https://github.com/MasterTemple/topos-bible)). Built from
both checkouts, logoxide-lsp and lx use the topos checkout's crates instead of crates.io's (Cargo's
`patch.crates-io`), so a change to topos reaches them before a release. Binaries on your `PATH` work too, and `cmd = { lsp = ..., cli = ..., lx = ... }`
picks them yourself.

## Tests

`tests/nvim/run.sh` tests the plugin in headless Neovim, with the quickfix list and with
Telescope if it is installed. It builds `topos` from a topos checkout (`TOPOS`, by default
`../../rust/topos`) and `logoxide-lsp` from a logoxide checkout (`LOGOXIDE`, by default
`../../rust/logoxide`).

<details>
<summary>Screenshots</summary>

![Neovim Quick Switcher Integration](./doc/imgs/neovim-quick-switcher.png)

![Neovim Telescope Integration](./doc/imgs/neovim-telescope.png)

</details>
