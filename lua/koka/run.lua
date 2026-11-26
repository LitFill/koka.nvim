---@mod koka.run
---@brief [[
---Run a command in a terminal tab and report the exit code.
---@brief ]]

local koka_ui = require('koka.ui')

local M = {}

-- Track the tab holding the most recent run terminal so it can be reused.
local state = { tab = nil }

---Start a terminal job in the current window and report the exit code.
---@param cmd string[] The command and its arguments
---@param cwd string Working directory
---@param title string Title used in the exit message
---@param on_exit? function Called with the exit code after the job ends
local function launch(cmd, cwd, title, on_exit)
  vim.fn.jobstart(cmd, {
    cwd = cwd,
    term = true,
    on_exit = function(_, exit_code)
      if exit_code == 0 then
        koka_ui.notify(string.format('✓ %s completed successfully', title), vim.log.levels.INFO)
      else
        koka_ui.notify(string.format('✗ %s failed with exit code %d', title, exit_code), vim.log.levels.ERROR)
      end
      if on_exit then
        on_exit(exit_code)
      end
    end,
  })
  state.tab = vim.api.nvim_get_current_tabpage()
end

---Run a command in a terminal tab, reusing the previous koka run tab.
---@param cmd string[] The command and its arguments
---@param cwd string Working directory
---@param title string Title used in the exit message
---@param on_exit? function Called with the exit code after the job ends
function M.run_term(cmd, cwd, title, on_exit)
  if state.tab and vim.api.nvim_tabpage_is_valid(state.tab) then
    vim.api.nvim_set_current_tabpage(state.tab)

    -- Close leftover terminal windows, counting the windows that remain.
    local remaining = 0
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(state.tab)) do
      local buf = vim.api.nvim_win_get_buf(win)
      if vim.bo[buf].buftype == 'terminal' then
        pcall(vim.api.nvim_win_close, win, true)
      else
        remaining = remaining + 1
      end
    end

    if remaining == 0 and not vim.api.nvim_tabpage_is_valid(state.tab) then
      -- Closing the last window closed the tab; open a fresh one.
      vim.cmd('tabnew')
    else
      vim.cmd('new')
    end
    launch(cmd, cwd, title, on_exit)
    return
  end

  vim.cmd('tabnew')
  launch(cmd, cwd, title, on_exit)
end

return M
