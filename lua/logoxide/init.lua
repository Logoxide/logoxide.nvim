-- logoxide.nvim: find, search, and complete Bible references (see :help logoxide)
local bin = require('logoxide.bin')
local config = require('logoxide.config')

local M = {}

local started = false

-- Shows the locations from the code actions' `logoxide.search` like go-to-references does
local function search_command(command, ctx)
  local client = assert(vim.lsp.get_client_by_id(ctx.client_id))
  client:request('workspace/executeCommand', command, function(err, locations)
    if err then
      return vim.notify('logoxide: ' .. err.message, vim.log.levels.ERROR)
    end
    local items = vim.lsp.util.locations_to_items(locations or {}, client.offset_encoding)
    require('logoxide.search').show(command.title, items)
  end, ctx.bufnr)
end

-- The server's configuration (also used by :LxLspStart for any buffer)
local function lsp_config(path)
  local lsp = config.options.lsp
  return {
    cmd = { path },
    filetypes = lsp.filetypes,
    root_markers = lsp.root_markers,
    init_options = config.lsp_settings(),
    settings = { logoxide = config.lsp_settings() },
  }
end

-- Configures and enables logoxide-lsp (once its binary exists)
function M.start_lsp()
  local lsp = config.options.lsp
  local path = bin.path('lsp')
  if started or not lsp.enabled or not path then
    return
  end
  started = true
  vim.lsp.config('logoxide', lsp_config(path))
  vim.lsp.enable('logoxide')
  if lsp.inlay_hints then
    vim.api.nvim_create_autocmd('LspAttach', {
      group = vim.api.nvim_create_augroup('topos_inlay_hints', { clear = true }),
      callback = function(args)
        local client = vim.lsp.get_client_by_id(args.data.client_id)
        if client and client.name == 'logoxide' then
          vim.lsp.inlay_hint.enable(true, { bufnr = args.buf })
        end
      end,
    })
  end
end

-- Diagnostics for unnamed buffers, which Neovim files under their URI (`file://`), so neither
-- pushed nor pulled ones reach the buffer: the plugin asks the server for them and sets them
local unnamed_ns = vim.api.nvim_create_namespace('topos_unnamed_diagnostics')

local function unnamed_diagnostics(bufnr, client)
  local function refresh()
    if not vim.api.nvim_buf_is_valid(bufnr) or client:is_stopped() then
      return
    end
    local params = { textDocument = { uri = vim.uri_from_bufnr(bufnr) } }
    client:request('textDocument/diagnostic', params, function(err, report)
      if err or not report or not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      -- LSP columns are UTF-16; Neovim's are bytes
      local function col(line, character)
        local text = lines[line + 1] or ''
        local ok, byte = pcall(vim.str_byteindex, text, 'utf-16', character, false)
        return ok and byte or character
      end
      local diagnostics = vim.tbl_map(function(d)
        return {
          lnum = d.range.start.line,
          col = col(d.range.start.line, d.range.start.character),
          end_lnum = d.range['end'].line,
          end_col = col(d.range['end'].line, d.range['end'].character),
          severity = d.severity,
          message = d.message,
          source = d.source,
          code = d.code,
        }
      end, report.items or {})
      vim.diagnostic.set(unnamed_ns, bufnr, diagnostics)
    end, bufnr)
  end
  local group = vim.api.nvim_create_augroup('topos_unnamed_' .. bufnr, { clear = true })
  local timer = assert(vim.uv.new_timer())
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'InsertLeave' }, {
    group = group,
    buffer = bufnr,
    callback = function()
      timer:stop()
      timer:start(200, 0, vim.schedule_wrap(refresh))
    end,
  })
  vim.api.nvim_create_autocmd({ 'BufFilePost', 'BufWipeout' }, {
    group = group,
    buffer = bufnr,
    once = true,
    callback = function()
      -- Named now (or gone): Neovim's own diagnostics take over
      vim.diagnostic.reset(unnamed_ns, bufnr)
      pcall(vim.api.nvim_del_augroup_by_id, group)
      timer:close()
    end,
  })
  refresh()
end

--[[
:LxLspStart: restarts logoxide-lsp if it is running, or starts it for the current buffer even
if its file type isn't one of `lsp.filetypes` (or it has no name). A restart re-attaches every
buffer the server had, plus the current one.
]]
function M.lsp_start()
  local path = bin.path('lsp')
  if not path then
    return vim.notify('logoxide: logoxide-lsp is not built yet; run :LxBuild', vim.log.levels.ERROR)
  end
  local buffers = { [vim.api.nvim_get_current_buf()] = true }
  local running = vim.lsp.get_clients({ name = 'logoxide' })
  for _, client in ipairs(running) do
    for bufnr in pairs(client.attached_buffers) do
      buffers[bufnr] = true
    end
    client:stop(true)
  end
  if #running > 0 then
    vim.wait(2000, function()
      return #vim.lsp.get_clients({ name = 'logoxide' }) == 0
    end, 20)
  end
  local base = lsp_config(path)
  for bufnr in pairs(buffers) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      local client_id = vim.lsp.start({
        name = 'logoxide',
        cmd = base.cmd,
        -- The buffer's root, or the cwd (an unnamed buffer has no folder of its own)
        root_dir = vim.fs.root(bufnr, base.root_markers) or vim.fn.getcwd(),
        init_options = base.init_options,
        settings = base.settings,
      }, { bufnr = bufnr })
      local client = client_id and vim.lsp.get_client_by_id(client_id)
      if client and vim.api.nvim_buf_get_name(bufnr) == '' then
        -- Once initialized, so the request reaches the server
        vim.wait(2000, function()
          return client.initialized
        end, 20)
        unnamed_diagnostics(bufnr, client)
      end
    end
  end
  vim.notify(('logoxide: %s logoxide-lsp'):format(#running > 0 and 'restarted' or 'started'))
end

--[[
The running logoxide-lsp client, else one started for the current folder (attached to no buffer)
once it has initialized; nil after saying why if it can't start. For :LxRead and whole books,
which need the server even when no note has started it
]]
function M.ensure_lsp()
  local running = vim.lsp.get_clients({ name = 'logoxide' })[1]
  if running then
    return running
  end
  local path = bin.path('lsp')
  if not path then
    vim.notify('logoxide: logoxide-lsp is not built yet; run :LxBuild', vim.log.levels.ERROR)
    return nil
  end
  local base = lsp_config(path)
  local bufnr = vim.api.nvim_get_current_buf()
  local client_id = vim.lsp.start({
    name = 'logoxide',
    cmd = base.cmd,
    root_dir = vim.fs.root(bufnr, base.root_markers) or vim.fn.getcwd(),
    init_options = base.init_options,
    settings = base.settings,
  }, { bufnr = bufnr, attach = false })
  local client = client_id and vim.lsp.get_client_by_id(client_id)
  if not client or not vim.wait(5000, function()
    return client.initialized
  end, 20) then
    vim.notify('logoxide: logoxide-lsp did not start', vim.log.levels.ERROR)
    return nil
  end
  return client
end

-- Reformat actions in unnamed buffers carry their edits, for the buffer they came from (an
-- unnamed buffer's URI, `file://`, names no buffer a workspace edit could reach)
local function apply_edits_command(command, ctx)
  local client = vim.lsp.get_client_by_id(ctx.client_id)
  local edits = command.arguments and command.arguments[1] and command.arguments[1].edits or {}
  vim.lsp.util.apply_text_edits(edits, ctx.bufnr, client and client.offset_encoding or 'utf-16')
end

--[[
The commands as functions, for mappings and scripts (see :help logoxide-lua). Arguments are
what the command takes, as a string (`'-g Wisdom'`) or, for the searches, a list of words
]]
local function words(args)
  return type(args) == 'table' and args or require('logoxide.search').split(args or '')
end

-- :LxSearch [paths]
function M.search(paths)
  local args = words(paths)
  local title = #args > 0 and ('Bible references in ' .. table.concat(args, ' ')) or 'Bible references'
  require('logoxide.search').run(args, title)
end

-- :LxQuery {args}
function M.query(args)
  args = words(args)
  require('logoxide.search').run(args, 'topos ' .. table.concat(args, ' '))
end

-- :LxExplicitOverlap [passage] and the others (the reference under the cursor by default)
for _, kind in ipairs({ 'explicit_overlap', 'any_overlap', 'exact_overlap', 'inside', 'exclude_overlap' }) do
  M[kind] = function(passage)
    require('logoxide.search').passage(kind, passage)
  end
end

-- :LxBible [name]
function M.bible(name)
  require('logoxide.bibles').set_default(name)
end

-- :LxParallel [name], with a split modifier like 'horizontal'
function M.parallel(name, mods)
  require('logoxide.bibles').parallel(name, mods)
end

-- :LxRead [book] [bible], with a split modifier like 'vertical'
function M.read(book, mods)
  require('logoxide.read').read(book, mods)
end

-- :LxNextBook, :LxPrevChapter, :LxNextHeading, ... (count: how many; 1 by default)
for _, unit in ipairs({ 'book', 'chapter', 'verse', 'heading' }) do
  M['next_' .. unit] = function(count)
    require('logoxide.read')[unit](count or 1)
  end
  M['prev_' .. unit] = function(count)
    require('logoxide.read')[unit](-(count or 1))
  end
end

-- :LxBibleAdd {source}, :LxBibleSearch [words], :LxBibleRemove {id}
function M.bible_add(source)
  require('logoxide.packages').add(source)
end

function M.bible_search(query)
  require('logoxide.packages').search(query)
end

function M.bible_remove(id)
  require('logoxide.packages').remove(id)
end

-- :LxBuild[!] (force: rebuild), then starts the language server
function M.build(force)
  require('logoxide.build').build(force, function(ok)
    if ok then
      M.start_lsp()
    end
  end)
end

-- For blink.cmp's `completion.documentation.draw`: colors passages in completion documentation
function M.blink_draw(opts)
  require('logoxide.book').blink_draw(opts)
end

function M.setup(opts)
  config.set(opts)
  require('logoxide.commands').create()
  require('logoxide.book').setup()
  vim.lsp.commands['logoxide.search'] = search_command
  vim.lsp.commands['logoxide.applyEdits'] = apply_edits_command
  local ok, telescope = pcall(require, 'telescope')
  if ok then
    pcall(telescope.load_extension, 'logoxide')
  end
  if not config.options.lsp.enabled then
    return
  end
  if bin.path('lsp') and bin.path('cli') then
    M.start_lsp()
  elseif config.options.auto_build then
    require('logoxide.build').build(false, function(built)
      if built then
        M.start_lsp()
      end
    end)
  else
    vim.notify('logoxide: logoxide-lsp is not built; run :LxBuild', vim.log.levels.WARN)
  end
end

return M
