---@mod koka.config.internal
---
---@brief [[
---
---WARNING: This is not part of the public API.
---
---@brief ]]

---@class koka.Config koka.nvim plugin configuration.
local KokaDefaultConfig = {
  ---@class koka.lsp.ClientConfig koka language client options
  lsp = {
    ---@type boolean | (fun():boolean) Whether to automatically attach the LSP client.
    auto_attach = true,
    ---@type (fun(client:vim.lsp.Client,bufnr:number))
    on_attach = function(_, _) end,
    settings = {},
  },
}

local kokanvim = vim.g.koka or {}
---@type koka.Opts
local opts = type(kokanvim) == 'function' and kokanvim() or kokanvim

---@type koka.Config
local KokaConfig = vim.tbl_deep_extend('force', {}, KokaDefaultConfig, opts)

-- Validate config
if KokaConfig.lsp then
  if type(KokaConfig.lsp.auto_attach) ~= 'boolean' and type(KokaConfig.lsp.auto_attach) ~= 'function' then
    vim.notify('koka.nvim: config.lsp.auto_attach must be boolean or function', vim.log.levels.WARN)
    KokaConfig.lsp.auto_attach = true
  end
  if type(KokaConfig.lsp.on_attach) ~= 'function' then
    vim.notify('koka.nvim: config.lsp.on_attach must be function', vim.log.levels.WARN)
    KokaConfig.lsp.on_attach = function() end
  end
end

return KokaConfig
