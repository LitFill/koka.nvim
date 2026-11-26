---@mod koka.ui
---@brief [[
---Draw virtual text one time.
---@brief ]]

local M = {}

---Draw virtual text at the end of a line.
---The text is one highlight group. The draw is guarded.
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
  pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, line, col, {
    virt_text = { { text, hl } },
    virt_text_pos = 'eol',
    hl_mode = 'combine',
  })
end

return M
