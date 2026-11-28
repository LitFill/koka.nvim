---@mod koka.health
---@brief [[
---Health check for koka.nvim. Run with :checkhealth koka.
---@brief ]]

local M = {}

---Run the koka health check.
function M.check()
  local health = vim.health or require('health')
  local start = health.start or health.report_start
  local ok = health.ok or health.report_ok
  local warn = health.warn or health.report_warn
  local err = health.error or health.report_error
  local info = health.info or health.report_info

  if vim.fn.has('nvim-0.11') ~= 1 then
    err('koka.nvim requires Neovim 0.11 or above', {
      'Upgrade Neovim; the plugin uses vim.lsp.config, client:request and jobstart{term=true}.',
    })
    return
  end

  start('koka.nvim report')

  -- koka compiler in PATH.
  if vim.fn.executable('koka') == 1 then
    ok('koka compiler found in PATH')
  else
    err('koka compiler not found in PATH', {
      'Install the koka compiler and make sure `koka` is executable.',
    })
  end

  -- TreeSitter parser.
  local ts = require('koka.treesitter')
  if ts.is_parser_installed() then
    ok('koka TreeSitter parser installed')
  else
    warn('koka TreeSitter parser not installed', {
      'Install the parser for syntax features.',
    })
  end

  -- LSP status.
  local lsp = require('koka.lsp')
  if lsp.get_status() then
    ok('LSP client running for this buffer')
  else
    info('LSP client not running for this buffer (start with :Koka lsp start)')
  end

  -- Inlay hints.
  local inlay = require('koka.commands.inlay')
  if inlay.is_enabled() then
    ok('inlay hints enabled')
  else
    info('inlay hints disabled (enable with :Koka inlay)')
  end

  -- Resolved project config.
  local project = require('koka.project')
  local config = project.get_resolved_config(vim.api.nvim_buf_get_name(0))
  start('project configuration')
  info(string.format('target: %s', config.target or 'c'))
  info(string.format('cwd: %s', config.cwd or 'not set'))
end

return M
