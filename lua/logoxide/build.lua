-- Building logoxide-lsp (the language server) and lx (installing Bibles), from logoxide, and topos (the
-- CLI, from topos) with Cargo, from checkouts (`source`) or GitHub
local bin = require('logoxide.bin')
local config = require('logoxide.config')

local M = {}

M.repositories = {
  topos = 'https://github.com/MasterTemple/logoxide',
  logoxide = 'https://github.com/MasterTemple/logoxide',
}

-- The checkouts to build from: `source` is a topos checkout, or { topos = ..., logoxide = ... };
-- logoxide defaults to `logoxide` beside topos (where it finds topos)
function M.sources()
  local source = config.options.source
  if type(source) == 'string' then
    source = { topos = source }
  end
  source = source or {}
  local topos = source.topos and vim.fn.expand(source.topos)
  local logoxide = source.logoxide and vim.fn.expand(source.logoxide)
  if not logoxide and topos then
    logoxide = vim.fs.joinpath(vim.fs.dirname(vim.fs.normalize(topos)), 'logoxide')
  end
  if logoxide and not vim.uv.fs_stat(logoxide) then
    logoxide = nil
  end
  return topos, logoxide
end

-- The commands to run in order: `cargo install` into the plugin's build/ folder
function M.commands()
  local root = bin.build_root()
  local topos, logoxide = M.sources()
  -- A checkout's own target folder, so a rebuild only builds what changed
  local function install(checkout, crate)
    local path = vim.fs.joinpath(checkout, 'crates', crate)
    return { 'cargo', 'install', '--path', path, '--root', root, '--target-dir', vim.fs.joinpath(checkout, 'target') }
  end
  local function from_git(repository, package)
    return { 'cargo', 'install', '--git', repository, '--root', root, package }
  end
  local lsp = logoxide and install(logoxide, 'logoxide-lsp') or from_git(M.repositories.logoxide, 'logoxide-lsp')
  -- PDFs for the `pdf` option
  if require('logoxide.config').options.pdf then
    vim.list_extend(lsp, { '--features', 'pdf' })
  end
  return {
    lsp,
    logoxide and install(logoxide, 'lx') or from_git(M.repositories.logoxide, 'lx'),
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
  if not force and bin.path('lsp') and bin.path('cli') and bin.path('lx') then
    vim.notify('logoxide: already built (use :LxBuild! to rebuild)')
    return done(true)
  end
  if vim.fn.executable('cargo') == 0 then
    vim.notify('logoxide: building needs Rust (https://rustup.rs)', vim.log.levels.ERROR)
    return done(false)
  end
  local topos, logoxide = M.sources()
  vim.notify(
    ('logoxide: building logoxide-lsp and lx from %s and topos from %s (this takes a few minutes the first time)...'):format(
      logoxide or M.repositories.logoxide,
      topos or M.repositories.topos
    )
  )
  run(M.commands(), function(ok, stderr)
    vim.schedule(function()
      if ok then
        vim.notify('logoxide: built logoxide-lsp, lx, and topos')
        done(true)
      else
        local lines = vim.split(stderr or '', '\n', { trimempty = true })
        local tail = table.concat(vim.list_slice(lines, math.max(1, #lines - 15)), '\n')
        vim.notify('logoxide: the build failed:\n' .. tail, vim.log.levels.ERROR)
        done(false)
      end
    end)
  end)
end

return M
