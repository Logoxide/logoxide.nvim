-- Searching with the topos CLI (`topos -m json`), and showing results in Telescope or quickfix
local bin = require('logoxide.bin')
local config = require('logoxide.config')

local M = {}

-- The search kinds for a single passage: the CLI flag and how a title describes it
M.kinds = {
  explicit_overlap = { flag = '-o', title = 'Search "%s" for explicit overlap' },
  any_overlap = { flag = '--any-overlap', title = 'Search "%s" for any overlap' },
  exact_overlap = { flag = '--exact-overlap', title = 'Search "%s" for exact overlap' },
  inside = { flag = '-i', title = 'Search inside "%s"' },
  exclude_overlap = { flag = '--exclude-overlap', title = 'Search outside "%s" (no overlap)' },
}

-- The folder to search: the language server's for this buffer, a root marker, or the cwd
function M.root(bufnr)
  bufnr = bufnr or 0
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr, name = 'logoxide' })) do
    if client.root_dir then
      return client.root_dir
    end
  end
  return vim.fs.root(bufnr, config.options.lsp.root_markers) or vim.fn.getcwd()
end

-- Splits like a shell: `-g "Pauline Epistles" -b John` is 4 words
function M.split(text)
  local words, word, quote, started = {}, {}, nil, false
  for char in text:gmatch('.') do
    if quote then
      if char == quote then
        quote = nil
      else
        table.insert(word, char)
      end
    elseif char == '"' or char == "'" then
      quote, started = char, true
    elseif char:match('%s') then
      if started then
        table.insert(words, table.concat(word))
        word, started = {}, false
      end
    else
      table.insert(word, char)
      started = true
    end
  end
  if started then
    table.insert(words, table.concat(word))
  end
  return words
end

-- The CLI, or nil after saying how to get it
local function cli()
  local path = bin.path('cli')
  if not path then
    vim.notify('logoxide: the topos CLI is not built yet; run :LxBuild', vim.log.levels.ERROR)
  end
  return path
end

-- `topos -m json --sort`, with the cache as `cache` says
local function command(path)
  local cmd = { path, '-m', 'json', '--sort' }
  local cache = config.options.cache
  if cache ~= nil then
    table.insert(cmd, cache and '--cache' or '--no-cache')
  end
  return cmd
end

-- One CLI match as a list item (filename, lnum, col, text) plus what the pickers show; a match
-- in `--text` (no path) is in the buffer `bufnr`
local function item(line, root, bufnr)
  local ok, m = pcall(vim.json.decode, line)
  if not ok or type(m) ~= 'table' or (type(m.path) ~= 'string' and not bufnr) then
    return nil
  end
  local path, filename
  if type(m.path) == 'string' then
    path = m.path:gsub('^%./', '')
    filename = path:match('^/') and path or vim.fs.joinpath(root, path)
  else
    local name = vim.api.nvim_buf_get_name(bufnr)
    path = name ~= '' and vim.fn.fnamemodify(name, ':.') or '[No Name]'
    filename = name ~= '' and name or nil
  end
  local line_text = vim.trim(m.line_text or '')
  return {
    bufnr = not filename and bufnr or nil,
    filename = filename,
    path = path,
    lnum = m.line,
    col = m.column,
    end_lnum = m.end_line,
    end_col = m.end_column,
    reference = m.reference,
    text = m.reference .. ': ' .. line_text,
    line_text = line_text,
  }
end

-- An item as a Telescope entry
local function entry(it)
  local where = string.format('%s:%d', it.path or vim.fn.fnamemodify(it.filename, ':.'), it.lnum)
  local label = it.reference and (it.reference .. '  ') or ''
  local text = it.line_text or it.text or ''
  return {
    value = it,
    display = label .. where .. '  ' .. text,
    ordinal = label .. where .. ' ' .. text,
    filename = it.filename,
    bufnr = it.bufnr,
    lnum = it.lnum,
    col = it.col,
  }
end

-- Whether results open in Telescope (else the quickfix list), as `picker` says
local function use_telescope()
  local picker = config.options.picker
  local has_telescope = picker ~= 'quickfix' and pcall(require, 'telescope')
  if picker == 'telescope' and not has_telescope then
    vim.notify('logoxide: Telescope is not installed; using the quickfix list', vim.log.levels.WARN)
  end
  return has_telescope
end

-- Shows items the way go-to-references does: a Telescope picker, or the quickfix list
function M.show(title, items)
  if #items == 0 then
    return vim.notify(title .. ': nothing found')
  end
  if not use_telescope() then
    vim.fn.setqflist({}, ' ', { title = title, items = items })
    return vim.cmd('botright copen')
  end
  local conf = require('telescope.config').values
  require('telescope.pickers')
    .new({}, {
      prompt_title = title,
      finder = require('telescope.finders').new_table({ results = items, entry_maker = entry }),
      previewer = conf.qflist_previewer({}),
      sorter = conf.generic_sorter({}),
    })
    :find()
end

-- What the CLI searches for a buffer: its file if it's saved, else its text
local function buffer_source(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name ~= '' and not vim.bo[bufnr].modified and vim.uv.fs_stat(name) then
    return { name }
  end
  return { '--text', table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), '\n') }
end

-- Whether any argument is an existing file or folder (else the search covers the root)
local function names_a_path(args, root)
  for _, arg in ipairs(args) do
    if not arg:match('^%-') and vim.uv.fs_stat(vim.fs.joinpath(root, arg)) then
      return true
    end
  end
  return false
end

-- Runs `topos -m json --sort ARGS` in the root and shows what it finds (in the buffer
-- `opts.bufnr`, if given)
function M.run(args, title, opts)
  opts = opts or {}
  local path = cli()
  if not path then
    return
  end
  local root = opts.root or M.root()
  local cmd = command(path)
  vim.list_extend(cmd, args)
  if opts.bufnr then
    vim.list_extend(cmd, buffer_source(opts.bufnr))
  -- Searching the root unless a path was given (and never reading stdin)
  elseif not names_a_path(args, root) then
    table.insert(cmd, '.')
  end
  vim.system(cmd, { cwd = root, text = true }, function(result)
    vim.schedule(function()
      -- Exit code 1 only means nothing was found
      if result.code > 1 then
        local message = vim.trim(result.stderr or '')
        return vim.notify('logoxide: ' .. (message ~= '' and message or 'the search failed'), vim.log.levels.ERROR)
      end
      local items = {}
      for line in (result.stdout or ''):gmatch('[^\n]+') do
        table.insert(items, item(line, root, opts.bufnr))
      end
      M.show(title, items)
      if opts.done then
        opts.done(items)
      end
    end)
  end)
end

-- The reference under the cursor, written in full (`John 3:16`), or nil
function M.reference_at_cursor()
  local path = bin.path('cli')
  if not path then
    return nil
  end
  local line = vim.api.nvim_get_current_line()
  local col = vim.api.nvim_win_get_cursor(0)[2] + 1
  local result = vim.system({ path, '-m', 'json', '--text', line }, { text = true }):wait()
  for json in (result.stdout or ''):gmatch('[^\n]+') do
    local ok, m = pcall(vim.json.decode, json)
    if ok and m.column <= col and col <= m.end_column then
      return m.reference
    end
  end
  return nil
end

-- One kind of search for one passage (the reference under the cursor if `passage` is empty)
function M.passage(kind, passage)
  local spec = M.kinds[kind]
  passage = (passage and vim.trim(passage) ~= '') and vim.trim(passage) or M.reference_at_cursor()
  if not passage then
    return vim.notify('logoxide: give a passage, or put the cursor on a reference', vim.log.levels.WARN)
  end
  M.run({ spec.flag, passage }, spec.title:format(passage))
end

-- The CLI's options for what's typed in a live search: a passage (`mat 1`, or a book alone) keeps
-- the references inside it, and options (`-g Gospels`) are passed as they are
function M.filter(prompt)
  prompt = vim.trim(prompt or '')
  if prompt == '' then
    return {}
  elseif prompt:match('^%-') then
    return M.split(prompt)
  end
  return { '-i', prompt }
end

--[[
The references in the current buffer (`scope` 'buffer') or under the current directory
('directory'), narrowed by a passage: in Telescope, what's typed in the prompt (starting with
`passage`) filters them as you type; in the quickfix list, `passage` does once
]]
function M.references(scope, passage)
  local bufnr = scope == 'buffer' and vim.api.nvim_get_current_buf() or nil
  local root = bufnr and M.root(bufnr) or vim.fn.getcwd()
  local where = bufnr and 'this buffer' or vim.fn.fnamemodify(root, ':~')
  passage = vim.trim(passage or '')
  if not use_telescope() then
    local title = 'References in ' .. where .. (passage ~= '' and (' (' .. passage .. ')') or '')
    return M.run(M.filter(passage), title, { root = root, bufnr = bufnr })
  end
  local path = cli()
  if not path then
    return
  end
  local source = bufnr and buffer_source(bufnr) or { '.' }
  local conf = require('telescope.config').values
  require('telescope.pickers')
    .new({}, {
      prompt_title = 'References in ' .. where .. ' (a passage, or topos options)',
      default_text = passage,
      debounce = 100,
      finder = require('telescope.finders').new_job(function(prompt)
        local cmd = command(path)
        vim.list_extend(cmd, M.filter(prompt))
        return vim.list_extend(cmd, source)
      end, function(line)
        local it = item(line, root, bufnr)
        return it and entry(it)
      end, nil, root),
      previewer = conf.qflist_previewer({}),
      sorter = require('telescope.sorters').empty(),
    })
    :find()
end

return M
