-- Finding the topos binaries: a configured path, the plugin's own build, then your PATH
local config = require('topos.config')

local M = {}

local exe = vim.fn.has('win32') == 1 and '.exe' or ''

-- The plugin's folder
function M.root()
  local source = debug.getinfo(1, 'S').source:sub(2)
  return vim.fn.fnamemodify(source, ':p:h:h:h')
end

-- Where :ToposBuild installs the binaries (`cargo install --root`)
function M.build_root()
  return vim.fs.joinpath(M.root(), 'build')
end

-- The plugin's build of `name`, like build/bin/topos-lsp
function M.built(name)
  return vim.fs.joinpath(M.build_root(), 'bin', name .. exe)
end

-- The binary to run for 'lsp' (topos-lsp) or 'cli' (topos), or nil if there is none
function M.path(kind)
  local configured = config.options.cmd[kind]
  if configured then
    return vim.fn.executable(configured) == 1 and configured or nil
  end
  local name = kind == 'lsp' and 'topos-lsp' or 'topos'
  local built = M.built(name)
  if vim.fn.executable(built) == 1 then
    return built
  end
  local found = vim.fn.exepath(name)
  return found ~= '' and found or nil
end

return M
