-- Exercises the plugin in headless Neovim (run by tests/nvim/run.sh, which sets REPO, TOPOS,
-- BIBLIX, and WORK)
local REPO, TOPOS, BIBLIX, WORK = vim.env.REPO, vim.env.TOPOS, vim.env.BIBLIX, vim.env.WORK
local out = {}
local function log(...) table.insert(out, table.concat(vim.tbl_map(tostring, {...}), " ")); vim.fn.writefile(out, WORK .. "/out.txt") end
local ok, err = xpcall(function()
vim.env.XDG_CONFIG_HOME = WORK .. "/config"; vim.env.XDG_CACHE_HOME = WORK .. "/cache"
vim.opt.rtp:prepend(REPO)
if vim.env.WITH_TELESCOPE then
  for _, p in ipairs({ "plenary.nvim", "telescope.nvim" }) do vim.opt.rtp:prepend((vim.env.PLUGINS or vim.fn.expand("~/.local/share/nvim/lazy")) .. "/" .. p) end
end
vim.cmd("runtime plugin/topos-bible.lua")
require("topos").setup({ cmd = { lsp = BIBLIX .. "/target/debug/biblix-lsp", cli = TOPOS .. "/target/debug/topos" }, auto_build = false,
  -- Server settings, as in a lazy.nvim spec's `opts`
  settings = { ["reference-diagnostics"] = "hint" },
  bible = WORK .. "/Bibles/BSB",
  bibles = { KJV = { path = WORK .. "/Bibles/KJV", aliases = { "AV" } } },
  markup = { words_of_jesus = { color = "#ff0000" }, verse_numbers = { highlight = "Special" } },
  insertions = { { name = "Callout", display = "> [!bible] {reference}\n{text}", line_prefix = "> " } } })
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
  log("hover text", value:match("\n```topos%-bible[^\n]*\n([^\n]*)"))
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
  require("topos").blink_draw({
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
      if a.title == "Insert Callout (BSB)" then vim.lsp.util.apply_workspace_edit(a.edit, client.offset_encoding) end
    end
  end
  log("callout", table.concat(vim.api.nvim_buf_get_lines(0, 1, 4, false), "|"))
end
-- Several Bibles: a reference followed by a Bible's name uses it; :ToposBible sets the default
do
  log("bibles", table.concat(require("topos.bibles").names(), "|"))
  -- Written now, so the workspace searches above don't count it
  vim.fn.writefile({ "Read John 3:16 KJV", "and John 3:16", "John 3:17 AV" }, WORK .. "/ws/kjv.txt")
  vim.cmd("edit " .. WORK .. "/ws/kjv.txt")
  vim.wait(5000, function() return #vim.lsp.get_clients({ bufnr = 0, name = "topos" }) > 0 end)
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
  log("default hover", hover(2, 6):match("\n(%*%u+%*)\n"))
  vim.wait(3000, function() return #vim.diagnostic.get(0, { severity = vim.diagnostic.severity.WARN }) > 0 end)
  for _, d in ipairs(vim.diagnostic.get(0, { severity = vim.diagnostic.severity.WARN })) do
    log("missing in KJV", d.message)
  end
  vim.cmd("ToposBible AV")
  vim.wait(3000, function() return hover(2, 6):find("*KJV*", 1, true) ~= nil end)
  log("set default hover", hover(2, 6):match("\n(%*%u+%*)\n"))
  vim.cmd("ToposBible BSB")
  vim.wait(3000, function() return hover(2, 6):find("*BSB*", 1, true) ~= nil end)
end
-- :ToposParallel: the KJV's John next to the BSB's, on the same verse
do
  vim.cmd("edit topos-bible://BSB/JHN")
  local bsb_win = vim.api.nvim_get_current_win()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local row
  for i, l in ipairs(lines) do if l:find("^%[16%]") then row = i end end
  vim.api.nvim_win_set_cursor(0, { row, 0 })
  vim.cmd("ToposParallel KJV")
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
  vim.api.nvim_win_close(kjv_win, true)
  -- The next run (with Telescope) uses the same workspace
  os.remove(WORK .. "/ws/kjv.txt")
end
-- :ToposRead: a book by name, the next and previous book, another Bible, and the picker
do
  vim.cmd("ToposRead jn")
  log("read", vim.api.nvim_buf_get_name(0), vim.bo.filetype)
  require("topos").next_book()
  local next_book = vim.api.nvim_buf_get_name(0)
  require("topos").prev_book()
  log("read next", next_book, vim.api.nvim_buf_get_name(0))
  vim.cmd("ToposRead John AV")
  log("read bible", vim.api.nvim_buf_get_name(0))
  log("read complete", table.concat(vim.fn.getcompletion("ToposRead Ro", "cmdline"), "|"),
    table.concat(vim.fn.getcompletion("ToposRead Romans K", "cmdline"), "|"))
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
  vim.cmd("ToposRead John BSB")
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  -- Past John's last verse, the next chapter: Romans 8 (the next book); back again
  log("move verses", moves("ToposNextVerse", "ToposNextVerse", "lua require('topos').next_verse()", "ToposPrevVerse", "lua require('topos').prev_verse(1)"))
  log("move chapters", moves("ToposNextChapter", "ToposNextChapter", "ToposPrevChapter"))
  -- Books wrap (Romans → John) unless `navigation` says not to; verses can wrap in their chapter
  log("move books", moves("ToposNextBook", "ToposNextBook", "3ToposPrevBook"))
  local navigation = require("topos.config").options.navigation
  navigation.books, navigation.verses = "stop", "wrap"
  vim.cmd("ToposRead John BSB")
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  log("move wrap", moves("ToposPrevBook", "ToposNextVerse", "ToposNextVerse", "ToposNextVerse"))
  navigation.books, navigation.verses = "wrap", "next"
  if telescope then
    vim.o.columns, vim.o.lines = 200, 50 -- wide enough for Telescope's previewer
    vim.cmd("ToposRead")
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
-- Each Bible's folder is checked
do
  local health, oks = vim.health, 0
  vim.health = setmetatable({ ok = function(m) if m:find("^Bible ") then oks = oks + 1 end end }, { __index = function() return function() end end })
  require("topos.health").check()
  vim.health = health
  log("health bibles", oks)
end
-- :ToposRead starts biblix-lsp when it isn't running
do
  for _, c in ipairs(vim.lsp.get_clients({ name = "topos" })) do c:stop(true) end
  vim.wait(3000, function() return #vim.lsp.get_clients({ name = "topos" }) == 0 end)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(b):find("^topos%-bible://") then vim.api.nvim_buf_delete(b, { force = true }) end
  end
  vim.cmd("enew")
  vim.cmd("ToposRead Romans")
  log("read starts lsp", #vim.lsp.get_clients({ name = "topos" }), vim.api.nvim_buf_get_name(0), vim.api.nvim_buf_line_count(0) > 1)
end
end, debug.traceback)
if not ok then log("ERROR", err) end
vim.cmd("qa!")
