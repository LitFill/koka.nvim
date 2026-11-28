---@mod koka.ui
---@brief [[
---Draw virtual text one time.
---@brief ]]

local M = {}

---Draw virtual text at a column.
---The text is one highlight group. `strict = false` keeps the mark when the
---line shrank, so no pcall is needed.
---@param bufnr number The buffer
---@param ns number The namespace id
---@param line number Zero-based row
---@param col number Zero-based column
---@param text string The virtual text
---@param hl string The highlight group
function M.virt_text(bufnr, ns, line, col, text, hl)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  vim.api.nvim_buf_set_extmark(bufnr, ns, line, col, {
    virt_text = { { text, hl } },
    virt_text_pos = 'inline',
    hl_mode = 'combine',
    strict = false,
  })
end

---Show a message with one prefix.
---@param msg string The message
---@param level? number The vim.log level
function M.notify(msg, level)
  vim.notify('[koka.nvim] ' .. msg, level or vim.log.levels.INFO)
end

return M
