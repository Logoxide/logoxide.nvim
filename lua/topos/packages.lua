--[[
Bibles as biblix packages, through `bx`: adding one from a git URL or a catalog (eBible.org's and
fetch.bible's translations, or the catalogs biblix.toml names), searching the catalogs, and
removing one. `bx` runs in the current folder, so it uses the same project as biblix-lsp: a
folder with a biblix.toml, else the library's own. biblix-lsp restarts afterwards to read them.
]]
local bin = require('topos.bin')

local M = {}

-- Runs bx with `args` in the current folder, then `done(stdout)` on success
local function bx(args, done)
  local path = bin.path('bx')
  if not path then
    return vim.notify('topos: bx is not built yet; run :ToposBuild!', vim.log.levels.ERROR)
  end
  local cmd = { path }
  vim.list_extend(cmd, args)
  vim.system(cmd, { text = true, cwd = vim.fn.getcwd() }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        local message = vim.trim(result.stderr ~= '' and result.stderr or result.stdout or '')
        return vim.notify('topos: ' .. message, vim.log.levels.ERROR)
      end
      done(result.stdout or '')
    end)
  end)
end

-- biblix-lsp reads its Bibles when it starts: restart it if it's running
local function reload()
  if #vim.lsp.get_clients({ name = 'topos' }) > 0 then
    require('topos').lsp_start()
  end
end

-- Installs with bx's arguments (`{ 'add', '--git', url }` or `{ 'import', 'ebible:id' }`)
local function install(args, what)
  vim.notify('topos: installing ' .. what .. '...')
  bx(args, function(stdout)
    local lines = vim.split(vim.trim(stdout), '\n')
    vim.notify('topos: ' .. (lines[#lines] or ('installed ' .. what)))
    reload()
  end)
end

-- What `bx import` takes: `ebible:<id>`, `fetch:<id>`, `ccel:<id>`, `sword:<repository>/<module>`
local IMPORTS = { ebible = true, fetch = true, ccel = true, sword = true }

-- :ToposBibleAdd {source}: a git URL, or an import such as ebible:<id> (as :ToposBibleSearch shows)
function M.add(source)
  source = vim.trim(source or '')
  if source == '' then
    return vim.notify('topos: give a git URL, or ebible:<id>, fetch:<id>, ccel:<id>, or sword:<repository>/<module> (see :ToposBibleSearch)', vim.log.levels.WARN)
  end
  if IMPORTS[source:match('^(%a+):') or ''] then
    install({ 'import', source }, source)
  else
    install({ 'add', '--git', source }, source)
  end
end

-- :ToposBibleSearch {words}: the catalogs' Bibles that match, to choose one to install
function M.search(query)
  local args = { 'search', '--json', '--limit', '50' }
  vim.list_extend(args, vim.split(vim.trim(query or ''), '%s+', { trimempty = true }))
  bx(args, function(stdout)
    local ok, found = pcall(vim.json.decode, stdout)
    if not ok or type(found) ~= 'table' or #found == 0 then
      return vim.notify('topos: no Bible found for "' .. (query or '') .. '"', vim.log.levels.WARN)
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

-- :ToposBibleRemove {id}: out of biblix.toml (bx clean deletes versions nothing uses)
function M.remove(id)
  id = vim.trim(id or '')
  if id == '' then
    return vim.notify('topos: give the package id to remove', vim.log.levels.WARN)
  end
  bx({ 'remove', id }, function()
    vim.notify('topos: removed ' .. id)
    reload()
  end)
end

-- The project's package ids (`bx list`), for completion
function M.ids()
  local path = bin.path('bx')
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
