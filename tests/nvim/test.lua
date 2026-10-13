-- Exercises the plugin in headless Neovim (run by tests/nvim/run.sh, which sets REPO, TOPOS,
-- LOGOXIDE, and WORK)
local REPO, TOPOS, LOGOXIDE, WORK = vim.env.REPO, vim.env.TOPOS, vim.env.LOGOXIDE, vim.env.WORK
local out = {}
local function log(...) table.insert(out, table.concat(vim.tbl_map(tostring, {...}), " ")); vim.fn.writefile(out, WORK .. "/out.txt") end
local ok, err = xpcall(function()
vim.env.XDG_CONFIG_HOME = WORK .. "/config"; vim.env.XDG_CACHE_HOME = WORK .. "/cache"
vim.opt.rtp:prepend(REPO)
if vim.env.WITH_TELESCOPE then
  for _, p in ipairs({ "plenary.nvim", "telescope.nvim" }) do vim.opt.rtp:prepend((vim.env.PLUGINS or vim.fn.expand("~/.local/share/nvim/lazy")) .. "/" .. p) end
end
vim.cmd("runtime plugin/logoxide.lua")
require("logoxide").setup({ cmd = { lsp = LOGOXIDE .. "/target/debug/logoxide-lsp", cli = TOPOS .. "/target/debug/topos" }, auto_build = false,
  -- Server settings, as in a lazy.nvim spec's `opts`
  settings = { ["reference-diagnostics"] = "hint" },
  bible = WORK .. "/Bibles/BSB",
  bibles = { KJV = { path = WORK .. "/Bibles/KJV", aliases = { "AV" } } },
  markup = { words_of_jesus = { color = "#ff0000" }, verse_numbers = { highlight = "Special" } },
  templates = { callout = { display = "> [!bible] {reference}\n{text}", line_prefix = "> ", action = "insert" },
    verse = { display = "{first:1}", markup = { headings = { show = false } } } } })
vim.cmd("edit " .. WORK .. "/ws/open.txt")
vim.wait(5000, function() return #vim.lsp.get_clients({ bufnr = 0, name = "logoxide" }) > 0 end)
vim.wait(500)
local client = vim.lsp.get_clients({ bufnr = 0, name = "logoxide" })[1]
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
log("search", results("LxSearch"))
log("query", results("LxQuery -g Gospels --exclude-book Luke"))
log("explicit", results("LxExplicitOverlap John 3:16"))
vim.api.nvim_win_set_cursor(0, { 1, 6 })
log("exact at cursor", results("LxExactOverlap"))
log("any", results("LxAnyOverlap John 3"))
log("inside", results("LxInside John 3"))
log("complete flags", table.concat(vim.fn.getcompletion("LxQuery -g Pau", "cmdline"), "|"))
log("complete ref", table.concat(vim.list_slice(vim.fn.getcompletion("LxExplicitOverlap John 3:1", "cmdline"), 1, 3), "|"))
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
  log("telescope ext", results(function() require("telescope").extensions.logoxide.explicit_overlap({ passage = "Rom 8:28" }) end))
  log("telescope ext query", results(function() require("telescope").extensions.logoxide.query({ args = '-g "Pauline Epistles"' }) end))
end
-- :LxFileReferences and :LxDirReferences: the references narrowed by a passage or a book alone
-- (as you type, in Telescope), in an unsaved buffer's own text too
do
  local function count(buf, cmd)
    vim.cmd(buf)
    return select(2, results(cmd))
  end
  local b = "edit " .. WORK .. "/ws/b.txt"
  local all, john, gospels = count(b, "LxFileReferences"), count(b, "LxFileReferences john 3"), count(b, "LxFileReferences -g Gospels")
  vim.cmd(b); vim.api.nvim_buf_set_lines(0, -1, -1, false, { "Mark 1:1 and Mark 2:3" })
  local unsaved = count("buffer " .. WORK .. "/ws/b.txt", "LxFileReferences mar")
  vim.cmd("buffer " .. WORK .. "/ws/b.txt | edit!")
  vim.cmd("enew"); vim.api.nvim_buf_set_lines(0, 0, -1, false, { "Jude 5" })
  local unnamed = vim.api.nvim_get_current_buf()
  local jude = count("buffer " .. unnamed, "LxFileReferences")
  vim.cmd("bwipeout! " .. unnamed)
  log("file references", all, john, gospels, unsaved, jude)
  log("dir references", count("buffer " .. WORK .. "/ws/open.txt", "LxDirReferences john"), select(2, results("LxDirReferences rom 8")))
  if telescope then
    vim.cmd("buffer " .. WORK .. "/ws/b.txt")
    require("telescope").extensions.logoxide.file_references({ passage = "rom" })
    vim.wait(5000, function() return vim.bo.filetype == "TelescopePrompt" end)
    vim.wait(300)
    local picker = require("telescope.actions.state").get_current_picker(vim.api.nvim_get_current_buf())
    local typed = { picker.manager:num_results() }
    for _, prompt in ipairs({ "john", "", "zzz" }) do
      picker:set_prompt(prompt)
      vim.wait(500)
      table.insert(typed, picker.manager:num_results())
    end
    require("telescope.actions").close(vim.api.nvim_get_current_buf())
    vim.wait(100)
    log("live references", table.concat(typed, " "))
  end
end
-- The Bible: the reference's text in hover
vim.cmd("buffer " .. WORK .. "/ws/open.txt")
vim.api.nvim_win_set_cursor(0, { 1, 6 })
do
  local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
  local hover = vim.lsp.buf_request_sync(0, "textDocument/hover", params, 5000)
  local value = ""
  for _, r in pairs(hover or {}) do value = r.result and r.result.contents.value or value end
  log("hover text", value:match("\n```logoxide[^\n]*\n([^\n]*)"))
end
-- The hover float colors its passage
vim.lsp.buf.hover()
vim.wait(3000, function() return vim.b.lsp_floating_preview ~= nil end)
do
  local win = vim.b.lsp_floating_preview
  local float = vim.api.nvim_win_get_buf(win)
  local ns = vim.api.nvim_get_namespaces().topos_bible_fences
  local groups = {}
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(float, ns, 0, -1, { details = true })) do
    local text = vim.api.nvim_buf_get_text(float, mark[2], mark[3], mark[4].end_row or mark[2], mark[4].end_col, {})[1]
    local token = mark[4].hl_group:match("type%.(%w+)")
    if token then table.insert(groups, token .. "=" .. text) end
  end
  log("hover colors", table.concat(groups, " "))
  vim.api.nvim_win_close(win, true)
end
-- blink.cmp's documentation: the plugin's draw colors a resolved completion's passage
do
  local item = client:request_sync("completionItem/resolve", { label = "John 3:16", data = { passage = "John 3:16" } }, 5000, 0).result
  local buf = vim.api.nvim_create_buf(false, true)
  require("logoxide").blink_draw({
    item = item,
    window = { get_buf = function() return buf end },
    default_implementation = function()
      local lines = {}
      vim.lsp.util.convert_input_to_markdown_lines(item.documentation, lines)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    end,
  })
  local ns = vim.api.nvim_get_namespaces().topos_bible_fences
  local groups = {}
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
    local token = mark[4].hl_group:match("type%.(%w+)")
    if token then table.insert(groups, token .. "=" .. vim.api.nvim_buf_get_text(buf, mark[2], mark[3], mark[2], mark[4].end_col, {})[1]) end
  end
  log("blink colors", vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1], table.concat(groups, " "))
end
-- Completion offers the chapter already typed first, unless complete_typed is false
do
  local before = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "Matthew 1" })
  vim.wait(300) -- didChange is debounced
  local function first()
    local params = { textDocument = vim.lsp.util.make_text_document_params(0), position = { line = 0, character = 9 } }
    local items = (client:request_sync("textDocument/completion", params, 5000, 0) or {}).result
    return items and (items.items or items)[1].label
  end
  local typed = first()
  require("logoxide.config").options.complete_typed = false
  client:notify("workspace/didChangeConfiguration", { settings = { logoxide = require("logoxide.config").lsp_settings() } })
  vim.wait(300)
  log("complete typed", typed, first())
  require("logoxide.config").options.complete_typed = true
  client:notify("workspace/didChangeConfiguration", { settings = { logoxide = require("logoxide.config").lsp_settings() } })
  vim.api.nvim_buf_set_lines(0, 0, -1, false, before)
  vim.bo.modified = false
  vim.wait(300)
end
-- `hover.trim` leaves out a heading's leading line break, and `hover.max` cuts the text
do
  local options = require("logoxide.config").options
  local function configure()
    client:notify("workspace/didChangeConfiguration", { settings = { logoxide = require("logoxide.config").lsp_settings() } })
    vim.wait(300)
  end
  local function first_line()
    local params = vim.lsp.util.make_position_params(0, "utf-16")
    params.position = { line = 0, character = 6 }
    local value = ""
    for _, r in pairs(vim.lsp.buf_request_sync(0, "textDocument/hover", params, 5000) or {}) do value = r.result and r.result.contents.value or value end
    return vim.inspect(value:match("\n```logoxide[^\n]*\n([^\n]*)"))
  end
  options.markup.headings.display = "\n{text}"
  configure()
  local untrimmed = first_line()
  options.hover = { trim = true, max = 10 }
  configure()
  log("hover trim", untrimmed, first_line())
  options.markup.headings.display = "{text}"
  options.hover = { trim = false, max = 2000 }
  configure()
end
-- Go to definition opens the whole book, read-only, at the verse
vim.lsp.buf.definition()
vim.wait(5000, function() return vim.api.nvim_buf_get_name(0):find("^logoxide://") ~= nil end)
local book = vim.api.nvim_get_current_buf()
log("book", vim.api.nvim_buf_get_name(book), vim.bo.filetype, vim.bo.modifiable, vim.bo.buftype)
log("book line", vim.api.nvim_get_current_line())
local cursor = vim.api.nvim_win_get_cursor(0)
log("book cursor", cursor[1], cursor[2])
log("book title", vim.b.logoxide_book)
-- Colored by semantic tokens: words of Jesus in `markup`'s color
vim.wait(5000, function() return #vim.inspect_pos(book, 3, 60).semantic_tokens > 0 end)
for _, token in ipairs(vim.inspect_pos(book, 3, 60).semantic_tokens) do
  log("woj", token.opts.hl_group, vim.api.nvim_get_hl(0, { name = token.opts.hl_group }).fg)
end
for _, token in ipairs(vim.inspect_pos(book, 3, 1).semantic_tokens) do
  log("verse number", token.opts.hl_group, vim.api.nvim_get_hl(0, { name = token.opts.hl_group, link = true }).link)
end
-- References from a verse: every reference that names it (open.txt's, a.md's two, and b.txt's)
do
  local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
  params.context = { includeDeclaration = true }
  local result = vim.lsp.buf_request_sync(book, "textDocument/references", params, 5000) or {}
  local n = 0
  for _, r in pairs(result) do n = n + #(r.result or {}) end
  log("book references", n)
end
-- Hovering a verse in the book counts its references
do
  vim.api.nvim_win_set_cursor(0, { 4, 10 })
  local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
  local hover = vim.lsp.buf_request_sync(book, "textDocument/hover", params, 5000) or {}
  for _, r in pairs(hover) do log("verse hover", (r.result.contents.value:gsub("\n", " "))) end
end
-- <C-]> (the LSP's tagfunc) opens it too
vim.cmd("buffer " .. WORK .. "/ws/open.txt")
vim.api.nvim_win_set_cursor(0, { 1, 6 })
vim.cmd.normal({ args = { vim.keycode("<C-]>") }, bang = true })
vim.wait(3000, function() return vim.api.nvim_get_current_buf() == book end)
log("tag", vim.api.nvim_get_current_buf() == book, vim.api.nvim_win_get_cursor(0)[1])
vim.cmd("buffer " .. WORK .. "/ws/open.txt")
-- Go to declaration opens the book too
vim.api.nvim_win_set_cursor(0, { 1, 6 })
vim.lsp.buf.declaration()
vim.wait(3000, function() return vim.api.nvim_get_current_buf() == book end)
log("declaration", vim.api.nvim_get_current_buf() == book)
vim.cmd("buffer " .. WORK .. "/ws/open.txt")
-- Insert Callout: the passage below the reference
do
  vim.api.nvim_win_set_cursor(0, { 1, 6 })
  local params = vim.lsp.util.make_range_params(0, client.offset_encoding)
  params.context = { diagnostics = {} }
  for _, r in pairs(vim.lsp.buf_request_sync(0, "textDocument/codeAction", params, 5000) or {}) do
    for _, a in ipairs(r.result or {}) do
      -- With several Bibles, an insertion per Bible
      if a.title == "Insert callout (BSB)" then vim.lsp.util.apply_workspace_edit(a.edit, client.offset_encoding) end
    end
  end
  log("callout", table.concat(vim.api.nvim_buf_get_lines(0, 1, 4, false), "|"))
end
-- :LxCopy and :LxInsert: the templates filled for the reference, chosen in a picker
do
  local function choose(cmd, done)
    local select, offered = vim.ui.select, 0
    vim.ui.select = function(items, _, chosen) offered = #items; chosen(items[1]) end
    vim.api.nvim_win_set_cursor(0, { 1, 6 })
    local columns, lines = vim.o.columns, vim.o.lines
    if telescope then vim.o.columns, vim.o.lines = 200, 50 end -- wide enough for Telescope's previewer
    vim.cmd(cmd)
    if telescope then
      vim.wait(5000, function() return vim.bo.filetype == "TelescopePrompt" end)
      vim.wait(300)
      local picker = require("telescope.actions.state").get_current_picker(vim.api.nvim_get_current_buf())
      local n = picker.manager:num_results()
      local preview = picker.previewer.state and picker.previewer.state.bufnr
      if preview then
        log(cmd .. " preview", vim.bo[preview].filetype, table.concat(vim.api.nvim_buf_get_lines(preview, 0, 6, false), "|"))
      end
      require("telescope.actions").select_default(vim.api.nvim_get_current_buf())
      vim.wait(300)
      vim.o.columns, vim.o.lines = columns, lines
      vim.ui.select = select
      return n
    end
    vim.wait(2000, done)
    vim.ui.select = select
    return offered
  end
  vim.fn.setreg("x", "")
  local n = choose("LxCopy x", function() return vim.fn.getreg("x") ~= "" end)
  log("copy", n, vim.fn.getregtype("x"), table.concat(vim.fn.getreg("x", 1, true), "|"))
  local before = vim.api.nvim_buf_line_count(0)
  local actions = choose("LxInsert", function() return vim.api.nvim_buf_line_count(0) ~= before end)
  log("insert", actions, vim.api.nvim_buf_line_count(0) - before, vim.api.nvim_buf_get_lines(0, 1, 2, false)[1])
  vim.cmd("silent undo")
  -- Inlay hints from a template by name, with its markup (no heading)
  local params = { textDocument = vim.lsp.util.make_text_document_params(0),
    range = { start = { line = 0, character = 0 }, ["end"] = { line = 1, character = 0 } } }
  local function hints(value)
    local cfg = require("logoxide.config")
    cfg.options.settings["inlay-hints"] = value
    client.settings = { logoxide = cfg.lsp_settings() }
    client:notify("workspace/didChangeConfiguration", { settings = client.settings })
    vim.wait(200)
  end
  hints("verse")
  local hint = ""
  for _, r in pairs(vim.lsp.buf_request_sync(0, "textDocument/inlayHint", params, 5000) or {}) do
    hint = r.result and r.result[1] and r.result[1].label or hint
  end
  log("verse hint", hint)
  hints(nil)
end
-- Several Bibles: a reference followed by a Bible's name uses it; :LxBible sets the default
do
  log("bibles", table.concat(require("logoxide.bibles").names(), "|"))
  -- Written now, so the workspace searches above don't count it
  vim.fn.writefile({ "Read John 3:16 KJV", "and John 3:16", "John 3:17 AV" }, WORK .. "/ws/kjv.txt")
  vim.cmd("edit " .. WORK .. "/ws/kjv.txt")
  vim.wait(5000, function() return #vim.lsp.get_clients({ bufnr = 0, name = "logoxide" }) > 0 end)
  local function hover(line, col)
    vim.api.nvim_win_set_cursor(0, { line, col })
    local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
    local value = ""
    for _, r in pairs(vim.lsp.buf_request_sync(0, "textDocument/hover", params, 5000) or {}) do
      value = r.result and r.result.contents.value or value
    end
    return value
  end
  local named = hover(1, 6)
  log("named hover", named:match("^[^\n]*"), named:match("that he gave"))
  -- `hover.title` names the Bible shown (sent with the settings :LxBible sends)
  local hover_options = require("logoxide.config").options.hover
  hover_options.title = "{reference} from {bible}"
  vim.cmd("LxBible BSB")
  vim.wait(3000, function() return hover(2, 6):find("from BSB", 1, true) ~= nil end)
  log("default hover", hover(2, 6):match("^[^\n]*"))
  vim.wait(3000, function() return #vim.diagnostic.get(0, { severity = vim.diagnostic.severity.WARN }) > 0 end)
  for _, d in ipairs(vim.diagnostic.get(0, { severity = vim.diagnostic.severity.WARN })) do
    log("missing in KJV", d.message)
  end
  vim.cmd("LxBible AV")
  vim.wait(3000, function() return hover(2, 6):find("from KJV", 1, true) ~= nil end)
  log("set default hover", hover(2, 6):match("^[^\n]*"))
  hover_options.title = nil
  vim.cmd("LxBible BSB")
  vim.wait(3000, function() return hover(2, 6):find("^%*%*John 3:16%*%*\n") ~= nil end)
end
-- :LxParallel: the KJV's John next to the BSB's, on the same verse
do
  vim.cmd("edit logoxide://BSB/JHN")
  local bsb_win = vim.api.nvim_get_current_win()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local row
  for i, l in ipairs(lines) do if l:find("^%[16%]") then row = i end end
  vim.api.nvim_win_set_cursor(0, { row, 0 })
  vim.cmd("LxParallel KJV")
  vim.wait(5000, function() return vim.api.nvim_buf_get_name(0):find("KJV") ~= nil end)
  local kjv_win = vim.api.nvim_get_current_win()
  log("parallel", vim.api.nvim_buf_get_name(0), vim.api.nvim_get_current_line())
  -- Moving in the BSB moves the KJV: John 4's label, which the KJV lacks, goes to its start,
  -- and the chapter label goes to the KJV's
  vim.api.nvim_set_current_win(bsb_win)
  for i, l in ipairs(lines) do if l == "John 3" then row = i end end
  vim.api.nvim_win_set_cursor(bsb_win, { row, 0 })
  vim.api.nvim_exec_autocmds("CursorMoved", {})
  vim.wait(3000, function()
    local kjv = vim.api.nvim_win_get_buf(kjv_win)
    local at = vim.api.nvim_win_get_cursor(kjv_win)[1]
    return vim.api.nvim_buf_get_lines(kjv, at - 1, at, false)[1] == "John 3"
  end)
  local at = vim.api.nvim_win_get_cursor(kjv_win)[1]
  log("parallel follows", vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(kjv_win), at - 1, at, false)[1])
  -- The next book in the BSB is the next book in the KJV too
  vim.cmd("LxNextBook")
  vim.wait(3000, function() return vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(kjv_win)) == "logoxide://KJV/ROM" end)
  log("parallel book", vim.api.nvim_buf_get_name(0), vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(kjv_win)))
  -- A verse in the middle of a line: the KJV's cursor on its start, not the line's
  for i, l in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    local col = l:find("[29]", 1, true)
    if col then vim.api.nvim_win_set_cursor(bsb_win, { i, col + 1 }) end
  end
  vim.api.nvim_exec_autocmds("CursorMoved", {})
  vim.wait(3000, function() return vim.api.nvim_win_get_cursor(kjv_win)[2] > 0 end)
  do
    local cursor = vim.api.nvim_win_get_cursor(kjv_win)
    local line = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(kjv_win), cursor[1] - 1, cursor[1], false)[1]
    log("parallel column", line:sub(cursor[2] + 1, cursor[2] + 13))
  end
  -- Going to the KJV doesn't move the BSB's cursor (it's in the verse already), and marks the
  -- verse there (only the verse, not its whole line), not in the KJV
  local before = vim.api.nvim_win_get_cursor(bsb_win)
  vim.api.nvim_set_current_win(kjv_win)
  vim.api.nvim_exec_autocmds("CursorMoved", {})
  local ns = vim.api.nvim_get_namespaces().logoxide_parallel_verse
  local function marked(win)
    local bufnr = vim.api.nvim_win_get_buf(win)
    local texts = {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })) do
      local text = vim.api.nvim_buf_get_text(bufnr, m[2], m[3], m[4].end_row, m[4].end_col, {})
      table.insert(texts, table.concat(text, "\n") .. "=" .. m[4].hl_group)
    end
    return table.concat(texts, "|")
  end
  vim.wait(3000, function() return marked(bsb_win) ~= "" end)
  log("parallel stays", vim.deep_equal(before, vim.api.nvim_win_get_cursor(bsb_win)), marked(bsb_win), "kjv:" .. marked(kjv_win))
  vim.api.nvim_win_close(kjv_win, true)
  -- The next run (with Telescope) uses the same workspace
  os.remove(WORK .. "/ws/kjv.txt")
end
-- :LxSwitch: the same verse in another Bible, in this window (Telescope previews it there);
-- :LxResume: back to the last place read, which is saved too
do
  vim.cmd("only")
  vim.cmd("edit logoxide://BSB/ROM")
  for i, l in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    local col = l:find("[29]", 1, true)
    if col then vim.api.nvim_win_set_cursor(0, { i, col - 1 }) end
  end
  local win = vim.api.nvim_get_current_win()
  local function at_cursor()
    local cursor = vim.api.nvim_win_get_cursor(0)
    return vim.api.nvim_get_current_line():sub(cursor[2] + 1, cursor[2] + 13)
  end
  if telescope then
    local columns, lines = vim.o.columns, vim.o.lines
    vim.o.columns, vim.o.lines = 200, 50 -- wide enough for Telescope's previewer
    vim.cmd("LxSwitch")
    vim.wait(5000, function() return vim.bo.filetype == "TelescopePrompt" end)
    local picker = require("telescope.actions.state").get_current_picker(vim.api.nvim_get_current_buf())
    local preview = function()
      local p = picker.previewer and picker.previewer.state
      if not (p and p.winid and vim.api.nvim_win_is_valid(p.winid)) then return "" end
      local row = vim.api.nvim_win_get_cursor(p.winid)[1]
      return vim.api.nvim_buf_get_lines(p.bufnr, row - 1, row, false)[1] or ""
    end
    vim.wait(3000, function() return preview():find("For whom", 1, true) ~= nil end)
    log("switch picker", picker.manager:num_results(), preview():find("For whom", 1, true) ~= nil)
    require("telescope.actions").select_default(vim.api.nvim_get_current_buf())
    vim.o.columns, vim.o.lines = columns, lines
  else
    vim.cmd("LxSwitch KJV")
  end
  vim.wait(5000, function() return vim.api.nvim_buf_get_name(0) == "logoxide://KJV/ROM" and at_cursor():find("^%[29%]") ~= nil end)
  log("switch", vim.api.nvim_buf_get_name(0), vim.api.nvim_get_current_win() == win, at_cursor())
  vim.cmd("buffer " .. WORK .. "/ws/open.txt")
  vim.cmd("LxResume")
  log("resume", vim.api.nvim_buf_get_name(0), at_cursor(), vim.fn.filereadable(vim.fn.stdpath("state") .. "/logoxide/last.json"))
  vim.cmd("buffer " .. WORK .. "/ws/open.txt")
end
-- :LxReadAt: a reference opens its book at the verse, in the Bible named (Telescope completes
-- what's typed and previews the verse)
do
  local function at_cursor()
    local cursor = vim.api.nvim_win_get_cursor(0)
    return vim.api.nvim_get_current_line():sub(cursor[2] + 1, cursor[2] + 13)
  end
  vim.cmd("LxReadAt rom 8:29 KJV")
  vim.wait(5000, function() return at_cursor():find("^%[29%]") ~= nil end)
  log("read at", vim.api.nvim_buf_get_name(0), at_cursor())
  vim.cmd("buffer " .. WORK .. "/ws/open.txt")
  if telescope then
    local columns, lines = vim.o.columns, vim.o.lines
    vim.o.columns, vim.o.lines = 200, 50
    vim.cmd("LxReadAt")
    vim.wait(5000, function() return vim.bo.filetype == "TelescopePrompt" end)
    local prompt = vim.api.nvim_get_current_buf()
    local picker = require("telescope.actions.state").get_current_picker(prompt)
    picker:set_prompt("Romans 8:28")
    local function selected()
      local entry = require("telescope.actions.state").get_selected_entry()
      return entry and entry.value or ""
    end
    vim.wait(5000, function() return selected() == "Romans 8:28" end)
    local preview = function()
      local p = picker.previewer and picker.previewer.state
      if not (p and p.winid and vim.api.nvim_win_is_valid(p.winid)) then return "" end
      local row = vim.api.nvim_win_get_cursor(p.winid)[1]
      return vim.api.nvim_buf_get_lines(p.bufnr, row - 1, row, false)[1] or ""
    end
    vim.wait(3000, function() return preview():find("[28]", 1, true) ~= nil end)
    log("read at picker", selected(), preview():find("[28]", 1, true) ~= nil)
    picker:set_prompt("Romans 8:29")
    vim.wait(5000, function() return selected() == "Romans 8:29" end)
    require("telescope.actions").select_default(prompt)
    vim.o.columns, vim.o.lines = columns, lines
    vim.wait(5000, function() return at_cursor():find("^%[29%]") ~= nil end)
    log("read at chosen", vim.api.nvim_buf_get_name(0), at_cursor())
    vim.cmd("buffer " .. WORK .. "/ws/open.txt")
  end
end
-- :LxRead: a book by name, the next and previous book, another Bible, and the picker
do
  vim.cmd("LxRead jn")
  log("read", vim.api.nvim_buf_get_name(0), vim.bo.filetype)
  require("logoxide").next_book()
  local next_book = vim.api.nvim_buf_get_name(0)
  require("logoxide").prev_book()
  log("read next", next_book, vim.api.nvim_buf_get_name(0))
  vim.cmd("LxRead John AV")
  log("read bible", vim.api.nvim_buf_get_name(0))
  log("read complete", table.concat(vim.fn.getcompletion("LxRead Ro", "cmdline"), "|"),
    table.concat(vim.fn.getcompletion("LxRead Romans K", "cmdline"), "|"))
  -- Moving by verse, chapter, and book: where the cursor lands (the book, and what follows it)
  local function where()
    local col = vim.api.nvim_win_get_cursor(0)[2]
    return vim.api.nvim_buf_get_name(0):match("%u+$") .. ":" .. vim.api.nvim_get_current_line():sub(col + 1, col + 4)
  end
  local function moves(...)
    local seen = {}
    for _, cmd in ipairs({ ... }) do vim.cmd(cmd); table.insert(seen, where()) end
    return table.concat(seen, " ")
  end
  vim.cmd("LxRead John BSB")
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  -- Past John's last verse, the next chapter: Romans 8 (the next book); back again
  log("move verses", moves("LxNextVerse", "LxNextVerse", "lua require('logoxide').next_verse()", "LxPrevVerse", "lua require('logoxide').prev_verse(1)"))
  log("move chapters", moves("LxNextChapter", "LxNextChapter", "LxPrevChapter"))
  -- Books wrap (Romans → John) unless `navigation` says not to; verses can wrap in their chapter
  log("move books", moves("LxNextBook", "LxNextBook", "3LxPrevBook"))
  local navigation = require("logoxide.config").options.navigation
  navigation.books, navigation.verses = "stop", "wrap"
  vim.cmd("LxRead John BSB")
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  log("move wrap", moves("LxPrevBook", "LxNextVerse", "LxNextVerse", "LxNextVerse"))
  navigation.books, navigation.verses = "wrap", "next"
  -- Headings: John's title, then its section heading; Romans (none) at its start; back to John's
  vim.cmd("LxRead John BSB")
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  log("move headings", moves("LxNextHeading", "LxNextHeading", "LxPrevHeading"))
  -- Poetry: a line each, `q2` indented, and a blank line between stanzas; then `markup.indent`
  vim.cmd("edit logoxide://KJV/PSA")
  log("poetry", table.concat(vim.api.nvim_buf_get_lines(0, 1, 5, false), "|"))
  local markup = require("logoxide.config").options.markup
  local function indent(spaces)
    markup.indent = spaces
    local settings = { logoxide = require("logoxide.config").lsp_settings() }
    for _, c in ipairs(vim.lsp.get_clients({ name = "logoxide" })) do
      c.settings = settings
      c:notify("workspace/didChangeConfiguration", { settings = settings })
    end
    vim.wait(500)
  end
  indent({ q1 = 1, q2 = 5 })
  vim.cmd("bwipeout")
  vim.cmd("edit logoxide://KJV/PSA")
  log("poetry indent", table.concat(vim.api.nvim_buf_get_lines(0, 1, 3, false), "|"))
  indent({ q1 = 0, q2 = 2, q3 = 4, q4 = 6 })
  -- `markup.verse_lines`: Romans 8:28 and 29 on lines of their own
  markup.verse_lines = true
  indent(markup.indent)
  pcall(vim.cmd, "bwipeout logoxide://BSB/ROM") -- opened before, with the old settings
  vim.cmd("edit logoxide://BSB/ROM")
  log("verse lines", table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "|"))
  vim.cmd("bwipeout")
  markup.verse_lines = false
  indent(markup.indent)
  vim.cmd("LxRead John BSB")
  if telescope then
    vim.o.columns, vim.o.lines = 200, 50 -- wide enough for Telescope's previewer
    vim.cmd("LxRead")
    vim.wait(5000, function() return vim.bo.filetype == "TelescopePrompt" end)
    local picker = require("telescope.actions.state").get_current_picker(vim.api.nvim_get_current_buf())
    -- The selected book (the current one, the BSB's John) previewed with its colors
    local preview
    vim.wait(3000, function()
      preview = picker.previewer and picker.previewer.state and picker.previewer.state.bufnr
      return preview and #vim.api.nvim_buf_get_extmarks(preview, -1, 0, -1, {}) > 0
    end)
    assert(preview, "no preview")
    local marks = vim.api.nvim_buf_get_extmarks(preview, -1, 0, -1, { details = true })
    log("read picker", picker.prompt_title, picker.manager:num_results(), vim.api.nvim_buf_get_lines(preview, 0, 1, false)[1],
      marks[1] and marks[1][4].hl_group)
    require("telescope.actions").close(vim.api.nvim_get_current_buf())
    vim.wait(100)
  end
end
vim.cmd("buffer " .. WORK .. "/ws/open.txt")
-- :LxLspStart in an unnamed buffer with no file type, then again to restart
local first = vim.lsp.get_clients({ name = "logoxide" })[1].id
vim.cmd("enew")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "Read jn 3:16 today" })
local scratch = vim.api.nvim_get_current_buf()
log("unnamed before", #vim.lsp.get_clients({ bufnr = scratch, name = "logoxide" }))
vim.cmd("LxLspStart")
vim.wait(5000, function() return #vim.lsp.get_clients({ bufnr = scratch, name = "logoxide" }) > 0 end)
vim.wait(3000, function() return #vim.diagnostic.get(scratch) > 0 end)
local diagnostics = vim.diagnostic.get(scratch)
log("unnamed after", #vim.lsp.get_clients({ bufnr = scratch, name = "logoxide" }), diagnostics[1] and diagnostics[1].message)
-- Reformatting from a code action works in the unnamed buffer too
do
  local c = vim.lsp.get_clients({ bufnr = scratch, name = "logoxide" })[1]
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
vim.cmd("LxLspStart")
vim.wait(5000, function()
  local c = vim.lsp.get_clients({ name = "logoxide" })[1]
  return c and c.id ~= first and c.attached_buffers[scratch] ~= nil
end)
local restarted = vim.lsp.get_clients({ name = "logoxide" })
local open = vim.fn.bufnr(WORK .. "/ws/open.txt")
log("restarted", #restarted, restarted[1].id ~= first, restarted[1].attached_buffers[scratch] ~= nil, restarted[1].attached_buffers[open] ~= nil)
-- :LxLspStop: no server, no diagnostics of its own, and none started for a new note; then
-- :LxLspStart again, which starts with new notes too
do
  vim.cmd("LxLspStop")
  vim.wait(3000, function() return #vim.lsp.get_clients({ name = "logoxide" }) == 0 end)
  vim.fn.writefile({ "John 3:16" }, WORK .. "/ws/stopped.txt")
  vim.cmd("edit " .. WORK .. "/ws/stopped.txt")
  vim.wait(500)
  log("stopped", #vim.lsp.get_clients({ name = "logoxide" }), #vim.diagnostic.get(scratch))
  vim.cmd("LxLspStart")
  vim.wait(5000, function() return #vim.lsp.get_clients({ bufnr = 0, name = "logoxide" }) > 0 end)
  vim.fn.writefile({ "John 3:17" }, WORK .. "/ws/again.txt")
  vim.cmd("edit " .. WORK .. "/ws/again.txt")
  vim.wait(5000, function() return #vim.lsp.get_clients({ bufnr = 0, name = "logoxide" }) > 0 end)
  log("started again", #vim.lsp.get_clients({ bufnr = 0, name = "logoxide" }))
  for _, name in ipairs({ "stopped.txt", "again.txt" }) do
    vim.cmd("bwipeout " .. WORK .. "/ws/" .. name)
    os.remove(WORK .. "/ws/" .. name)
  end
  vim.cmd("LxLspStart")
  vim.wait(5000, function() return #vim.lsp.get_clients({ name = "logoxide" }) > 0 end)
  client = vim.lsp.get_clients({ name = "logoxide" })[1]
end
vim.cmd("buffer " .. open)
vim.wait(5000, function() return #vim.lsp.get_clients({ bufnr = 0, name = "logoxide" }) > 0 end)
-- `epub`: the EPUB's references, opened in its text at the reference
do
  local client = vim.lsp.get_clients({ name = "logoxide" })[1]
  local command = { command = "logoxide.search", arguments = { { mode = "explicit-overlap", passage = "Rom 8:28" } } }
  local function book_location()
    local response = client:request_sync("workspace/executeCommand", command, 20000, open)
    for _, location in ipairs(response and response.result or {}) do
      if location.uri:find("^logoxide%-file://") then return location end
    end
  end
  vim.uv.fs_copyfile(WORK .. "/Gill.epub", WORK .. "/ws/Gill.epub")
  log("book off", book_location() == nil)
  local settings = require("logoxide.config").lsp_settings()
  settings.epub = true
  client:notify("workspace/didChangeConfiguration", { settings = { logoxide = settings } })
  vim.wait(500)
  local location = book_location()
  vim.lsp.util.show_document(location, client.offset_encoding, { focus = true })
  vim.wait(5000, function() return vim.bo.filetype == "logoxide-file" end)
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()
  log("book file", vim.bo.filetype, vim.bo.readonly, line:sub(col + 1, col + 8), vim.b.logoxide_book)
  client:notify("workspace/didChangeConfiguration", { settings = { logoxide = require("logoxide.config").lsp_settings() } })
  vim.cmd("buffer " .. open)
  os.remove(WORK .. "/ws/Gill.epub")
end
-- `lsp.search_folders`: go to references and the searches cover a folder outside the workspace
do
  -- (:LxLspStart above started it for another buffer)
  local client = vim.lsp.get_clients({ name = "logoxide" })[1]
  vim.lsp.buf_attach_client(0, client.id)
  local cfg = require("logoxide.config")
  local function in_vault()
    vim.api.nvim_win_set_cursor(0, { 1, 6 })
    local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
    params.context = { includeDeclaration = true }
    local response = client:request_sync("textDocument/references", params, 5000, 0)
    local n = 0
    for _, location in ipairs(response and response.result or {}) do
      if location.uri:find("/vault/v%.md$") then n = n + 1 end
    end
    return n
  end
  local before = in_vault()
  cfg.options.lsp.search_folders = { WORK .. "/vault" }
  client:notify("workspace/didChangeConfiguration", { settings = { logoxide = cfg.lsp_settings() } })
  vim.wait(300)
  local after = in_vault()
  local cli = 0
  results(function()
    require("logoxide.search").run({ "-o", "John 3:16" }, "vault", { done = function(items)
      for _, it in ipairs(items) do
        if (it.filename or ""):find("/vault/v%.md$") then cli = cli + 1 end
      end
    end })
  end)
  log("search folders", before, after, cli)
  cfg.options.lsp.search_folders = {}
  client:notify("workspace/didChangeConfiguration", { settings = { logoxide = cfg.lsp_settings() } })
  vim.cmd("buffer " .. open)
end
vim.cmd("checkhealth logoxide")
local health = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
log("health ok", select(2, health:gsub("OK", "")), "errors", select(2, health:gsub("ERROR", "")))
-- Each Bible's folder is checked
do
  local health, oks = vim.health, 0
  vim.health = setmetatable({ ok = function(m) if m:find("^Bible ") then oks = oks + 1 end end }, { __index = function() return function() end end })
  require("logoxide.health").check()
  vim.health = health
  log("health bibles", oks)
end
-- :LxRead starts logoxide-lsp when it isn't running
do
  for _, c in ipairs(vim.lsp.get_clients({ name = "logoxide" })) do c:stop(true) end
  vim.wait(3000, function() return #vim.lsp.get_clients({ name = "logoxide" }) == 0 end)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(b):find("^logoxide://") then vim.api.nvim_buf_delete(b, { force = true }) end
  end
  vim.cmd("enew")
  vim.cmd("LxRead Romans")
  log("read starts lsp", #vim.lsp.get_clients({ name = "logoxide" }), vim.api.nvim_buf_get_name(0), vim.api.nvim_buf_line_count(0) > 1)
end
end, debug.traceback)
if not ok then log("ERROR", err) end
vim.cmd("qa!")
