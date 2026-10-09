-- Building biblix-lsp (the language server) and bx (installing Bibles), from biblix, and topos (the
-- CLI, from topos) with Cargo, from checkouts (`source`) or GitHub
local bin = require('topos.bin')
local config = require('topos.config')

local M = {}

M.repositories = {
  topos = 'https://github.com/MasterTemple/topos-bible',
  biblix = 'https://github.com/MasterTemple/biblix',
}

-- The checkouts to build from: `source` is a topos checkout, or { topos = ..., biblix = ... };
-- biblix defaults to `biblix` beside topos (where it finds topos)
function M.sources()
  local source = config.options.source
  if type(source) == 'string' then
    source = { topos = source }
  end
  source = source or {}
  local topos = source.topos and vim.fn.expand(source.topos)
  local biblix = source.biblix and vim.fn.expand(source.biblix)
  if not biblix and topos then
    biblix = vim.fs.joinpath(vim.fs.dirname(vim.fs.normalize(topos)), 'biblix')
  end
  if biblix and not vim.uv.fs_stat(biblix) then
    biblix = nil
  end
  return topos, biblix
end

-- The commands to run in order: `cargo install` into the plugin's build/ folder
function M.commands()
  local root = bin.build_root()
  local topos, biblix = M.sources()
  -- A checkout's own target folder, so a rebuild only builds what changed
  local function install(checkout, crate)
    local path = vim.fs.joinpath(checkout, 'crates', crate)
    return { 'cargo', 'install', '--path', path, '--root', root, '--target-dir', vim.fs.joinpath(checkout, 'target') }
  end
  local function from_git(repository, package)
    return { 'cargo', 'install', '--git', repository, '--root', root, package }
  end
  return {
    biblix and install(biblix, 'biblix-lsp') or from_git(M.repositories.biblix, 'biblix-lsp'),
    biblix and install(biblix, 'bx') or from_git(M.repositories.biblix, 'bx'),
    topos and install(topos, 'topos-cli') or from_git(M.repositories.topos, 'topos-bible-cli'),
  }
end

-- Runs the commands one after another, then `done(ok, stderr)`
local function run(commands, done)
  local command = table.remove(commands, 1)
  if not command then
    return done(true)
  end
  vim.system(command, { text = true }, function(result)
    if result.code ~= 0 then
      return done(false, result.stderr)
    end
    run(commands, done)
  end)
end

-- Builds unless the binaries are already there (`force` builds anyway); `done(ok)` runs after
function M.build(force, done)
  done = done or function() end
  if not force and bin.path('lsp') and bin.path('cli') and bin.path('bx') then
    vim.notify('topos: already built (use :ToposBuild! to rebuild)')
    return done(true)
  end
  if vim.fn.executable('cargo') == 0 then
    vim.notify('topos: building needs Rust (https://rustup.rs)', vim.log.levels.ERROR)
    return done(false)
  end
  local topos, biblix = M.sources()
  vim.notify(
    ('topos: building biblix-lsp and bx from %s and topos from %s (this takes a few minutes the first time)...'):format(
      biblix or M.repositories.biblix,
      topos or M.repositories.topos
    )
  )
  run(M.commands(), function(ok, stderr)
    vim.schedule(function()
      if ok then
        vim.notify('topos: built biblix-lsp, bx, and topos')
        done(true)
      else
        local lines = vim.split(stderr or '', '\n', { trimempty = true })
        local tail = table.concat(vim.list_slice(lines, math.max(1, #lines - 15)), '\n')
        vim.notify('topos: the build failed:\n' .. tail, vim.log.levels.ERROR)
        done(false)
      end
    end)
  end)
end

return M
