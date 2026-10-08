-- Building topos-lsp and topos (the CLI) with Cargo, from GitHub or a topos checkout (`source`)
local bin = require('topos.bin')
local config = require('topos.config')

local M = {}

M.repository = 'https://github.com/MasterTemple/topos-bible'

-- The commands to run in order: `cargo install` into the plugin's build/ folder
function M.commands()
  local root = bin.build_root()
  local source = config.options.source
  if not source then
    return { { 'cargo', 'install', '--git', M.repository, '--root', root, 'topos-lsp', 'topos-bible-cli' } }
  end
  source = vim.fn.expand(source)
  -- The checkout's own target folder, so a rebuild only builds what changed
  local function install(crate)
    local path = vim.fs.joinpath(source, 'crates', crate)
    return { 'cargo', 'install', '--path', path, '--root', root, '--target-dir', vim.fs.joinpath(source, 'target') }
  end
  return { install('topos-lsp'), install('topos-cli') }
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

-- Builds unless both binaries are already there (`force` builds anyway); `done(ok)` runs after
function M.build(force, done)
  done = done or function() end
  if not force and bin.path('lsp') and bin.path('cli') then
    vim.notify('topos: already built (use :ToposBuild! to rebuild)')
    return done(true)
  end
  if vim.fn.executable('cargo') == 0 then
    vim.notify('topos: building needs Rust (https://rustup.rs)', vim.log.levels.ERROR)
    return done(false)
  end
  local from = config.options.source and vim.fn.expand(config.options.source) or M.repository
  vim.notify(('topos: building topos-lsp and topos from %s (this takes a few minutes the first time)...'):format(from))
  run(M.commands(), function(ok, stderr)
    vim.schedule(function()
      if ok then
        vim.notify('topos: built topos-lsp and topos')
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
