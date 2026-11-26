---@mod koka.config.internal
---
---@brief [[
---
---WARNING: This is not part of the public API.
---
---@brief ]]

local koka_ui = require('koka.ui')

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
  ---@class koka.inlay.Config Inlay hint options.
  inlay = {
    ---@type boolean Whether to show inlay hints for total functions.
    enabled = false,
    ---@type number Delay in milliseconds before a refresh runs.
    debounce_ms = 300,
    ---@type number Maximum number of hints to show in one buffer.
    max_results = 50,
    ---@type boolean Whether to refresh hints after writing a buffer.
    on_write = false,
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
    koka_ui.notify('config.lsp.auto_attach must be boolean or function', vim.log.levels.WARN)
    KokaConfig.lsp.auto_attach = true
  end
  if type(KokaConfig.lsp.on_attach) ~= 'function' then
    koka_ui.notify('config.lsp.on_attach must be function', vim.log.levels.WARN)
    KokaConfig.lsp.on_attach = function() end
  end
end

if KokaConfig.inlay then
  if type(KokaConfig.inlay.enabled) ~= 'boolean' then
    koka_ui.notify('config.inlay.enabled must be boolean', vim.log.levels.WARN)
    KokaConfig.inlay.enabled = false
  end
  if type(KokaConfig.inlay.debounce_ms) ~= 'number' or KokaConfig.inlay.debounce_ms < 0 then
    koka_ui.notify('config.inlay.debounce_ms must be a non-negative number', vim.log.levels.WARN)
    KokaConfig.inlay.debounce_ms = 300
  end
  if type(KokaConfig.inlay.max_results) ~= 'number' or KokaConfig.inlay.max_results < 1 then
    koka_ui.notify('config.inlay.max_results must be a positive number', vim.log.levels.WARN)
    KokaConfig.inlay.max_results = 50
  end
end

return KokaConfig
