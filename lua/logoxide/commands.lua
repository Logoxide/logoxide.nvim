-- The :Topos* commands and their completions
local bin = require('logoxide.bin')
local search = require('logoxide.search')

local M = {}

-- Completes the CLI's options and their values, by asking the CLI (clap's completion protocol,
-- the same one shell completion uses)
function M.complete_flags(_, cmdline, pos)
  local path = bin.path('cli')
  if not path then
    return {}
  end
  local words = search.split(cmdline:sub(1, pos))
  table.remove(words, 1) -- the command
  if cmdline:sub(1, pos):match('%s$') then
    table.insert(words, '')
  end
  local cmd = { path, '--', 'topos' }
  vim.list_extend(cmd, words)
  local result = vim
    .system(cmd, {
      text = true,
      env = {
        COMPLETE = 'bash',
        _CLAP_IFS = '\n',
        _CLAP_COMPLETE_INDEX = tostring(#words),
        _CLAP_COMPLETE_COMP_TYPE = '9',
        _CLAP_COMPLETE_SPACE = 'true',
      },
    })
    :wait()
  local candidates = {}
  for candidate in (result.stdout or ''):gmatch('[^\n]+') do
    -- Values with spaces (Pauline Epistles) are quoted, so they stay one argument
    table.insert(candidates, candidate:find(' ') and ('"' .. candidate .. '"') or candidate)
  end
  return candidates
end

--[[
Completes a reference (books, then chapters, verses, and range ends). The command line swaps in
a candidate for the last word only (`lead`), so each is the suggestion without the words before
it: after `mt 5:`, `5:3`; after `mt`, `Matthew 1` (the book's name replaces the abbreviation)
]]
function M.complete_passage(lead, cmdline, pos)
  local path = bin.path('cli')
  if not path then
    return {}
  end
  local typed = cmdline:sub(1, pos):gsub('^%S+%s*', '')
  local before = typed:sub(1, #typed - #(lead or ''))
  local skip = select(2, before:gsub('%S+', ''))
  local result = vim.system({ path, '--complete', typed }, { text = true }):wait()
  local seen, candidates = {}, {}
  for candidate in (result.stdout or ''):gmatch('[^\n]+') do
    local rest
    if candidate:lower():sub(1, #before) == before:lower() then
      rest = candidate:sub(#before + 1)
    else
      rest = table.concat(vim.list_slice(vim.split(candidate, ' ', { trimempty = true }), skip + 1), ' ')
    end
    -- What's typed is already on the command line (topos offers it first, for editors)
    if rest ~= '' and not seen[rest] and candidate ~= vim.trim(typed) then
      seen[rest] = true
      table.insert(candidates, rest)
    end
  end
  return candidates
end

local function api()
  return require('logoxide')
end

local function bible_names()
  return require('logoxide.bibles').names()
end

local commands = {
  LxSearch = {
    function(opts)
      api().search(opts.args)
    end,
    { nargs = '*', complete = 'dir', desc = 'Every Bible reference in the workspace (or the paths given)' },
  },
  LxQuery = {
    function(opts)
      api().query(opts.args)
    end,
    { nargs = '+', complete = M.complete_flags, desc = 'Search with the CLI\'s options, like -g Wisdom' },
  },
  LxFileReferences = {
    function(opts)
      api().file_references(opts.args)
    end,
    {
      nargs = '*',
      complete = M.complete_passage,
      desc = 'The references in this buffer, narrowed by a passage as you type it (in Telescope)',
    },
  },
  LxDirReferences = {
    function(opts)
      api().dir_references(opts.args)
    end,
    {
      nargs = '*',
      complete = M.complete_passage,
      desc = 'The references under the current directory, narrowed by a passage as you type it (in Telescope)',
    },
  },
  LxCopy = {
    function(opts)
      api().copy(opts.reg)
    end,
    { register = true, desc = 'Copy the passage under the cursor, in the form chosen (the templates)' },
  },
  LxInsert = {
    function()
      api().insert()
    end,
    { desc = 'Write the passage under the cursor with the template chosen, as its code action does' },
  },
  LxLspStop = {
    function()
      api().lsp_stop()
    end,
    { desc = 'Stop logoxide-lsp (and don\'t start it with new buffers until :LxLspStart)' },
  },
  LxLspStart = {
    function()
      api().lsp_start()
    end,
    { desc = 'Start logoxide-lsp for this buffer (whatever its file type), or restart it' },
  },
  LxBible = {
    function(opts)
      api().bible(opts.args)
    end,
    {
      nargs = '?',
      complete = bible_names,
      desc = 'The Bible references use when they name none (choose one without a name)',
    },
  },
  LxParallel = {
    function(opts)
      api().parallel(opts.args, opts.mods)
    end,
    { nargs = '?', complete = bible_names, desc = 'This whole book in another Bible, side by side on the same verse' },
  },
  LxSwitch = {
    function(opts)
      api().switch(opts.args)
    end,
    { nargs = '?', complete = bible_names, desc = 'This whole book in another Bible, here, at the same verse' },
  },
  LxResume = {
    function(opts)
      api().resume(opts.mods)
    end,
    { desc = 'Back to the last place read in a whole book' },
  },
  LxRead = {
    function(opts)
      api().read(opts.args, opts.mods)
    end,
    {
      nargs = '*',
      complete = function(...)
        return require('logoxide.read').complete(...)
      end,
      desc = 'Open a whole book of the Bible (choose one without a book)',
    },
  },
  LxBibleAdd = {
    function(opts)
      api().bible_add(opts.args)
    end,
    { nargs = 1, desc = 'Install a Bible: a logoxide package\'s git URL, or ebible:<id> / fetch:<id>' },
  },
  LxBibleSearch = {
    function(opts)
      api().bible_search(opts.args)
    end,
    { nargs = '*', desc = 'Search the catalogs (eBible.org, fetch.bible) for a Bible to install' },
  },
  LxBibleRemove = {
    function(opts)
      api().bible_remove(opts.args)
    end,
    {
      nargs = 1,
      complete = function()
        return require('logoxide.packages').ids()
      end,
      desc = 'Remove a Bible package from logoxide.toml',
    },
  },
  LxBuild = {
    function(opts)
      api().build(opts.bang)
    end,
    { bang = true, desc = 'Build logoxide-lsp and topos (! rebuilds)' },
  },
}

local passages = {
  LxExplicitOverlap = 'explicit_overlap',
  LxAnyOverlap = 'any_overlap',
  LxExactOverlap = 'exact_overlap',
  LxInside = 'inside',
  LxExcludeOverlap = 'exclude_overlap',
}
for name, kind in pairs(passages) do
  commands[name] = {
    function(opts)
      api()[kind](opts.args)
    end,
    {
      nargs = '*',
      complete = M.complete_passage,
      desc = search.kinds[kind].title:format('{passage}') .. ' (the reference under the cursor by default)',
    },
  }
end

-- :LxNextBook, :LxPrevVerse, ... in a whole book (with a count, that many)
for _, unit in ipairs({ 'book', 'chapter', 'verse', 'heading' }) do
  for direction, word in pairs({ next = 'Next', prev = 'Prev' }) do
    commands['Lx' .. word .. unit:gsub('^%l', string.upper)] = {
      function(opts)
        api()[direction .. '_' .. unit](math.max(opts.count, 1))
      end,
      { count = 1, desc = ('In a whole book, the %s %s'):format(direction == 'next' and 'next' or 'previous', unit) },
    }
  end
end

function M.create()
  for name, command in pairs(commands) do
    vim.api.nvim_create_user_command(name, command[1], command[2])
  end
end

return M
