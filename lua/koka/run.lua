---@mod koka.run
---@brief [[
---Run a command in a terminal tab and report the exit code.
---@brief ]]

local koka_ui = require('koka.ui')

local M = {}

---Run a command in a new terminal tab.
---Starts a terminal job and notifies by exit code.
---@param cmd string[] The command and its arguments
---@param cwd string Working directory
---@param title string Title used in the exit message
---@param on_exit? function Called with the exit code after the job ends
function M.run_term(cmd, cwd, title, on_exit)
  vim.cmd('tabnew')
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
end

return M
