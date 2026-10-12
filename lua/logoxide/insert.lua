--[[
Copying the passage under the cursor in a form, and inserting it (:LxCopy, :LxInsert):
logoxide-lsp fills each of the `templates` for the reference (`logoxide/templates`; just the
passage's text without any), and a picker shows what each writes.
]]
local config = require('logoxide.config')

local M = {}

-- The templates filled for the reference under the cursor, then `done(choices, client, bufnr)`
local function choices(done)
  local bufnr = vim.api.nvim_get_current_buf()
  local client = vim.lsp.get_clients({ bufnr = bufnr, name = 'logoxide' })[1]
  if not client then
    return vim.notify('logoxide: logoxide-lsp is not running here (:LxLspStart)', vim.log.levels.WARN)
  end
  local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
  client:request('logoxide/templates', params, function(err, result)
    if err then
      return vim.notify('logoxide: ' .. err.message, vim.log.levels.ERROR)
    end
    if not result or #result == 0 then
      return vim.notify('logoxide: put the cursor on a reference (in a Bible that has it)', vim.log.levels.WARN)
    end
    done(result, client, bufnr)
  end, bufnr)
end

-- How a choice is listed: its code action's title (`Insert callout`) when inserting, else its
-- name, with its Bible when there are several
local function label(choice)
  return choice.shown or choice.label
end

-- Chooses one (Telescope, previewing what each writes; else vim.ui.select), then `done(choice)`
local function pick(title, list, done)
  if config.options.picker == 'quickfix' or not pcall(require, 'telescope') then
    return vim.ui.select(list, { prompt = title, format_item = label }, function(choice)
      if choice then
        done(choice)
      end
    end)
  end
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local state = require('telescope.actions.state')
  require('telescope.pickers')
    .new({}, {
      prompt_title = title,
      finder = require('telescope.finders').new_table({
        results = list,
        entry_maker = function(choice)
          return { value = choice, display = label(choice), ordinal = label(choice) }
        end,
      }),
      sorter = conf.generic_sorter({}),
      previewer = require('telescope.previewers').new_buffer_previewer({
        title = 'Text',
        define_preview = function(self, entry)
          vim.wo[self.state.winid].wrap = true
          vim.wo[self.state.winid].linebreak = true
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, vim.split(entry.value.text, '\n'))
          vim.bo[self.state.bufnr].filetype = 'markdown'
        end,
      }),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local entry = state.get_selected_entry()
          actions.close(prompt_bufnr)
          if entry then
            done(entry.value)
          end
        end)
        return true
      end,
    })
    :find()
end

-- :LxCopy [register]: the passage under the cursor, in the form chosen, into a register (the
-- unnamed one by default); several lines are copied linewise
function M.copy(register)
  register = (register and register ~= '') and register or vim.v.register
  choices(function(list)
    pick('Copy as', list, function(choice)
      vim.fn.setreg(register, choice.text, choice.text:find('\n') and 'l' or 'c')
      vim.notify(('logoxide: copied %s into "%s'):format(label(choice), register))
    end)
  end)
end

-- :LxInsert: the passage under the cursor, written as the chosen template's code action does
-- (below the reference, or in place of its line or of the reference)
function M.insert()
  choices(function(list, client, bufnr)
    local actions = {}
    for _, choice in ipairs(list) do
      if choice.edit ~= vim.NIL and choice.edit then
        table.insert(actions, vim.tbl_extend('force', choice, { shown = choice.title }))
      end
    end
    if #actions == 0 then
      return vim.notify("logoxide: no template has an `action` (see :help logoxide-templates)", vim.log.levels.WARN)
    end
    pick('Insert', actions, function(choice)
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.lsp.util.apply_text_edits({ choice.edit }, bufnr, client.offset_encoding)
      end
    end)
  end)
end

return M
