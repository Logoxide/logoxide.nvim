-- Exercises the plugin in headless Neovim (run by tests/nvim/run.sh, which sets REPO, TOPOS, and
-- WORK)
local REPO, TOPOS, WORK = vim.env.REPO, vim.env.TOPOS, vim.env.WORK
local out = {}
local function log(...) table.insert(out, table.concat(vim.tbl_map(tostring, {...}), " ")); vim.fn.writefile(out, WORK .. "/out.txt") end
local ok, err = xpcall(function()
vim.env.XDG_CONFIG_HOME = WORK .. "/config"; vim.env.XDG_CACHE_HOME = WORK .. "/cache"
vim.opt.rtp:prepend(REPO)
if vim.env.WITH_TELESCOPE then
  for _, p in ipairs({ "plenary.nvim", "telescope.nvim" }) do vim.opt.rtp:prepend((vim.env.PLUGINS or vim.fn.expand("~/.local/share/nvim/lazy")) .. "/" .. p) end
end
vim.cmd("runtime plugin/topos-bible.lua")
require("topos").setup({ cmd = { lsp = TOPOS .. "/target/debug/topos-lsp", cli = TOPOS .. "/target/debug/topos" }, auto_build = false,
  -- Server settings, as in a lazy.nvim spec's `opts`
  settings = { ["reference-diagnostics"] = "hint" },
  bible = WORK .. "/Bibles/BSB",
  markup = { words_of_jesus = { color = "#ff0000" } } })
vim.cmd("edit " .. WORK .. "/ws/open.txt")
vim.wait(5000, function() return #vim.lsp.get_clients({ bufnr = 0, name = "topos" }) > 0 end)
vim.wait(500)
local client = vim.lsp.get_clients({ bufnr = 0, name = "topos" })[1]
log("lsp", client and client.name, "hints", vim.lsp.inlay_hint.is_enabled({ bufnr = 0 }))
vim.wait(3000, function() return #vim.diagnostic.get(0) > 0 end)
for _, d in ipairs(vim.diagnostic.get(0)) do
  log("diagnostic", vim.diagnostic.severity[d.severity], d.code, d.message)
end
local telescope = vim.env.WITH_TELESCOPE ~= nil
local function results(cmd)
  local before = vim.fn.getqflist({ id = 0 }).id
  if type(cmd) == "function" then cmd() else vim.cmd(cmd) end
  if telescope then
    vim.wait(5000, function() return vim.bo.filetype == "TelescopePrompt" end)
    vim.wait(300)
    local picker = require("telescope.actions.state").get_current_picker(vim.api.nvim_get_current_buf())
    local title, n = picker.prompt_title, picker.manager:num_results()
    require("telescope.actions").close(vim.api.nvim_get_current_buf())
    vim.wait(100)
    return title, n
  end
  vim.wait(5000, function() return vim.fn.getqflist({ id = 0 }).id ~= before end)
  local title, n = vim.fn.getqflist({ title = 1 }).title, #vim.fn.getqflist()
  vim.cmd("cclose")
  vim.cmd("buffer " .. WORK .. "/ws/open.txt")
  return title, n
end
log("search", results("ToposSearch"))
log("query", results("ToposQuery -g Gospels --exclude-book Luke"))
log("explicit", results("ToposExplicitOverlap John 3:16"))
vim.api.nvim_win_set_cursor(0, { 1, 6 })
log("exact at cursor", results("ToposExactOverlap"))
log("any", results("ToposAnyOverlap John 3"))
log("inside", results("ToposInside John 3"))
log("complete flags", table.concat(vim.fn.getcompletion("ToposQuery -g Pau", "cmdline"), "|"))
log("complete ref", table.concat(vim.list_slice(vim.fn.getcompletion("ToposExplicitOverlap John 3:1", "cmdline"), 1, 3), "|"))
local ca = vim.lsp.util.make_range_params(0, client.offset_encoding); ca.context = { diagnostics = {} }
local actions = vim.lsp.buf_request_sync(0, "textDocument/codeAction", ca, 5000)
local action, reformat
for _, r in pairs(actions) do
  for _, a in ipairs(r.result) do
    if a.title:find("for any overlap") then action = a end
    if a.title:find("^Reformat as") then reformat = a end
  end
end
log("code action", action.title, results(function() client:exec_cmd(action.command, { bufnr = 0 }) end))
vim.lsp.util.apply_workspace_edit(reformat.edit, client.offset_encoding)
log("reformat", reformat.title, vim.api.nvim_get_current_line())
if telescope then
  log("telescope ext", results(function() require("telescope").extensions.topos.explicit_overlap({ passage = "Rom 8:28" }) end))
  log("telescope ext query", results(function() require("telescope").extensions.topos.query({ args = '-g "Pauline Epistles"' }) end))
end
-- The Bible: the reference's text in hover
vim.cmd("buffer " .. WORK .. "/ws/open.txt")
vim.api.nvim_win_set_cursor(0, { 1, 6 })
do
  local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
  local hover = vim.lsp.buf_request_sync(0, "textDocument/hover", params, 5000)
  local value = ""
  for _, r in pairs(hover or {}) do value = r.result and r.result.contents.value or value end
  log("hover text", value:match("\n\n(> [^\n]*)"))
end
-- Go to definition opens the whole book, read-only, at the verse
vim.lsp.buf.definition()
vim.wait(5000, function() return vim.api.nvim_buf_get_name(0):find("^topos%-bible://") ~= nil end)
local book = vim.api.nvim_get_current_buf()
log("book", vim.api.nvim_buf_get_name(book), vim.bo.filetype, vim.bo.modifiable, vim.bo.buftype)
log("book line", vim.api.nvim_get_current_line())
local cursor = vim.api.nvim_win_get_cursor(0)
log("book cursor", cursor[1], cursor[2])
log("book title", vim.b.topos_book)
-- Colored by semantic tokens: words of Jesus in `markup`'s color
vim.wait(5000, function() return #vim.inspect_pos(book, 3, 60).semantic_tokens > 0 end)
for _, token in ipairs(vim.inspect_pos(book, 3, 60).semantic_tokens) do
  log("woj", token.opts.hl_group, vim.api.nvim_get_hl(0, { name = token.opts.hl_group }).fg)
end
for _, token in ipairs(vim.inspect_pos(book, 3, 1).semantic_tokens) do log("verse number", token.opts.hl_group) end
-- References from a verse: every reference that names it (open.txt's, a.md's two, and b.txt's)
do
  local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
  params.context = { includeDeclaration = true }
  local result = vim.lsp.buf_request_sync(book, "textDocument/references", params, 5000) or {}
  local n = 0
  for _, r in pairs(result) do n = n + #(r.result or {}) end
  log("book references", n)
end
-- <C-]> (the LSP's tagfunc) opens it too
vim.cmd("buffer " .. WORK .. "/ws/open.txt")
vim.api.nvim_win_set_cursor(0, { 1, 6 })
vim.cmd.normal({ args = { vim.keycode("<C-]>") }, bang = true })
vim.wait(3000, function() return vim.api.nvim_get_current_buf() == book end)
log("tag", vim.api.nvim_get_current_buf() == book, vim.api.nvim_win_get_cursor(0)[1])
vim.cmd("buffer " .. WORK .. "/ws/open.txt")
-- :ToposLspStart in an unnamed buffer with no file type, then again to restart
local first = vim.lsp.get_clients({ name = "topos" })[1].id
vim.cmd("enew")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "Read jn 3:16 today" })
local scratch = vim.api.nvim_get_current_buf()
log("unnamed before", #vim.lsp.get_clients({ bufnr = scratch, name = "topos" }))
vim.cmd("ToposLspStart")
vim.wait(5000, function() return #vim.lsp.get_clients({ bufnr = scratch, name = "topos" }) > 0 end)
vim.wait(3000, function() return #vim.diagnostic.get(scratch) > 0 end)
local diagnostics = vim.diagnostic.get(scratch)
log("unnamed after", #vim.lsp.get_clients({ bufnr = scratch, name = "topos" }), diagnostics[1] and diagnostics[1].message)
-- Reformatting from a code action works in the unnamed buffer too
do
  local c = vim.lsp.get_clients({ bufnr = scratch, name = "topos" })[1]
  local params = {
    textDocument = { uri = vim.uri_from_bufnr(scratch) },
    range = { start = { line = 0, character = 6 }, ["end"] = { line = 0, character = 6 } },
    context = { diagnostics = {} },
  }
  local result = vim.lsp.buf_request_sync(scratch, "textDocument/codeAction", params, 3000) or {}
  for _, r in pairs(result) do
    for _, a in ipairs(r.result or {}) do
      if a.title:find("^Reformat as") then c:exec_cmd(a.command, { bufnr = scratch }) end
    end
  end
  log("unnamed reformat", vim.api.nvim_buf_get_lines(scratch, 0, 1, false)[1])
end
-- Editing the unnamed buffer updates its diagnostics
vim.api.nvim_buf_set_lines(scratch, 0, -1, false, { "Now rom 8:28" })
vim.api.nvim_exec_autocmds("TextChanged", { buffer = scratch })
vim.wait(3000, function()
  local d = vim.diagnostic.get(scratch)[1]
  return d and d.message == "Romans 8:28"
end)
log("unnamed edited", vim.diagnostic.get(scratch)[1] and vim.diagnostic.get(scratch)[1].message)
vim.cmd("ToposLspStart")
vim.wait(5000, function()
  local c = vim.lsp.get_clients({ name = "topos" })[1]
  return c and c.id ~= first and c.attached_buffers[scratch] ~= nil
end)
local restarted = vim.lsp.get_clients({ name = "topos" })
local open = vim.fn.bufnr(WORK .. "/ws/open.txt")
log("restarted", #restarted, restarted[1].id ~= first, restarted[1].attached_buffers[scratch] ~= nil, restarted[1].attached_buffers[open] ~= nil)
vim.cmd("buffer " .. open)
vim.cmd("checkhealth topos")
local health = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
log("health ok", select(2, health:gsub("OK", "")), "errors", select(2, health:gsub("ERROR", "")))
end, debug.traceback)
if not ok then log("ERROR", err) end
vim.cmd("qa!")
