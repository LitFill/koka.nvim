---@mod koka.commands.treesitter
---@brief [[
---TreeSitter parser management commands for Koka
---@brief ]]

local M = {}

---Check if nvim-treesitter is available
---@return boolean available
local function is_treesitter_available()
  return pcall(require, 'nvim-treesitter')
end

---Get parser configurations
---@return table parser_configs
local function get_parser_configs()
  if not is_treesitter_available() then
    return {}
  end

  local parsers = require('nvim-treesitter.parsers')
  return parsers.get_parser_configs and parsers.get_parser_configs() or parsers
end

---Install Koka TreeSitter parser if not already available
---@return boolean success
function M.install_parser()
  if not is_treesitter_available() then
    vim.notify('[koka.nvim] nvim-treesitter is required for TreeSitter support', vim.log.levels.ERROR)
    return false
  end

  -- Check if parser is already installed/available
  local ok_parser, parser = pcall(require, 'nvim-treesitter.parsers')
  if ok_parser and parser and parser.koka then
    -- Parser already configured, skip
    return true
  end

  local list = get_parser_configs()

  -- Configure Koka parser
  list.koka = {
    install_info = {
      url = 'https://github.com/koka-community/tree-sitter-koka',
      files = { 'src/parser.c', 'src/scanner.c' },
      branch = 'main',
    },
  }

  vim.api.nvim_create_autocmd('User', {
    pattern = 'TSUpdate',
    callback = function()
      local parsers = get_parser_configs()
      parsers.koka = {
        install_info = {
          url = 'https://github.com/koka-community/tree-sitter-koka',
          files = { 'src/parser.c', 'src/scanner.c' },
          branch = 'main',
        },
      }
    end,
  })

  return true
end

return M
