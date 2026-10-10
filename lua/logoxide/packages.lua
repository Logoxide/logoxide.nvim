--[[
Bibles as logoxide packages, through `lx`: adding one from a git URL or a catalog (eBible.org's and
fetch.bible's translations, or the catalogs logoxide.toml names), searching the catalogs, and
removing one. `lx` runs in the current folder, so it uses the same project as logoxide-lsp: a
folder with a logoxide.toml, else the library's own. logoxide-lsp restarts afterwards to read them.
]]
local bin = require('logoxide.bin')

local M = {}

-- Runs lx with `args` in the current folder, then `done(stdout)` on success
local function lx(args, done)
  local path = bin.path('lx')
  if not path then
    return vim.notify('logoxide: lx is not built yet; run :LxBuild!', vim.log.levels.ERROR)
  end
  local cmd = { path }
  vim.list_extend(cmd, args)
  vim.system(cmd, { text = true, cwd = vim.fn.getcwd() }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        local message = vim.trim(result.stderr ~= '' and result.stderr or result.stdout or '')
        return vim.notify('logoxide: ' .. message, vim.log.levels.ERROR)
      end
      done(result.stdout or '')
    end)
  end)
end

-- logoxide-lsp reads its Bibles when it starts: restart it if it's running
local function reload()
  if #vim.lsp.get_clients({ name = 'logoxide' }) > 0 then
    require('logoxide').lsp_start()
  end
end

-- Installs with lx's arguments (`{ 'add', '--git', url }` or `{ 'import', 'ebible:id' }`)
local function install(args, what)
  vim.notify('logoxide: installing ' .. what .. '...')
  lx(args, function(stdout)
    local lines = vim.split(vim.trim(stdout), '\n')
    vim.notify('logoxide: ' .. (lines[#lines] or ('installed ' .. what)))
    reload()
  end)
end

-- What `lx import` takes: `ebible:<id>`, `fetch:<id>`, `ccel:<id>`, `sword:<repository>/<module>`
local IMPORTS = { ebible = true, fetch = true, ccel = true, sword = true }

-- :LxBibleAdd {source}: a git URL, or an import such as ebible:<id> (as :LxBibleSearch shows)
function M.add(source)
  source = vim.trim(source or '')
  if source == '' then
    return vim.notify('logoxide: give a git URL, or ebible:<id>, fetch:<id>, ccel:<id>, or sword:<repository>/<module> (see :LxBibleSearch)', vim.log.levels.WARN)
  end
  if IMPORTS[source:match('^(%a+):') or ''] then
    install({ 'import', source }, source)
  else
    install({ 'add', '--git', source }, source)
  end
end

-- :LxBibleSearch {words}: the catalogs' Bibles that match, to choose one to install
function M.search(query)
  local args = { 'search', '--json', '--limit', '50' }
  vim.list_extend(args, vim.split(vim.trim(query or ''), '%s+', { trimempty = true }))
  lx(args, function(stdout)
    local ok, found = pcall(vim.json.decode, stdout)
    if not ok or type(found) ~= 'table' or #found == 0 then
      return vim.notify('logoxide: no Bible found for "' .. (query or '') .. '"', vim.log.levels.WARN)
    end
    vim.ui.select(found, {
      prompt = 'Install a Bible',
      format_item = function(entry)
        local license = entry.license == 'LicenseRef-PublicDomain' and 'public domain' or (entry.license or '')
        return ('%s (%s): %s, %s, %s'):format(entry.abbreviation, entry.id, entry.name, entry.language, license)
      end,
    }, function(entry)
      if entry then
        install(entry.install, entry.name)
      end
    end)
  end)
end

-- :LxBibleRemove {id}: out of logoxide.toml (lx clean deletes versions nothing uses)
function M.remove(id)
  id = vim.trim(id or '')
  if id == '' then
    return vim.notify('logoxide: give the package id to remove', vim.log.levels.WARN)
  end
  lx({ 'remove', id }, function()
    vim.notify('logoxide: removed ' .. id)
    reload()
  end)
end

-- The project's package ids (`lx list`), for completion
function M.ids()
  local path = bin.path('lx')
  if not path then
    return {}
  end
  local result = vim.system({ path, 'list' }, { text = true, cwd = vim.fn.getcwd() }):wait()
  local ids = {}
  for line in (result.stdout or ''):gmatch('[^\n]+') do
    local id = line:match('^(%S+) %S+  ')
    if id then
      table.insert(ids, id)
    end
  end
  return ids
end

return M
