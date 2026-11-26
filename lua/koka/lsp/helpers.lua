---@mod koka.lsp.helpers
---
---@brief [[
---
---WARNING: This is not part of the public API.
---Breking changes to this module will not be reflected in the semantic versioning
---of this plugin.
---@brief ]]
local M = {}
local koka_cmd = require('koka.koka_cmd')

M.koka_client_name = 'koka'

---@param bufnr? number the buffer to get clients for
---@param filter? vim.lsp.get_clients.Filter
---@return vim.lsp.Client[] kk_clients The koka clients
M.get_active_lsp_clients = function(bufnr, filter)
  local client_filter = vim.tbl_deep_extend('force', filter or {}, {
    name = M.koka_client_name,
  })
  if bufnr then
    client_filter.bufnr = bufnr
  end
  return vim.lsp.get_clients(client_filter)
end

---Check if a Koka LSP client is active for a buffer.
---@param bufnr? number
---@return boolean
M.has_client = function(bufnr)
  return #M.get_active_lsp_clients(bufnr) > 0
end

--- Get Koka LSP command
---
---@param project_config koka.project.Config
---@return table
M.get_lsp_cmd = function(project_config)
  local cmd = { 'koka', '--language-server' }
  vim.list_extend(cmd, koka_cmd.common_args(project_config, { buildtag = 'nvim' }))
  table.insert(cmd, '--lsstdio')
  return cmd
end

return M
