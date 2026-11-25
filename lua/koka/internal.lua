---@type koka.Config
local KokaConfig = require('koka.config.internal')

---@class koka.internal.Api
local M = {}

local function start_or_attach()
  local Types = require('koka.types.internal')
  if Types.evaluate(KokaConfig.lsp.auto_attach) then
    local ok, lsp = pcall(require, 'koka.lsp')
    if ok then
      lsp.start()
    else
      vim.notify('Koka LSP failed to load: ' .. tostring(lsp), vim.log.levels.ERROR)
    end
  end
end

local function init()
  if vim.g.kokanvim_loaded then
    return
  end
  vim.g.kokanvim_loaded = true

  -- Setup TreeSitter commands and ensure parser is installed
  local ts_commands = require('koka.treesitter')
  ts_commands.install_parser()

  -- Setup other commands
  require('koka.commands.codelens').setup()
  require('koka.commands').setup()
  require('koka.commands.inlay').setup()
end

M.ftplugin = function()
  init()
  start_or_attach()
  ---TODO: implement nvim-dap adapater
end

return M
