-- Introduce a new filetype for koka
vim.filetype.add {
  extension = {
    kk = 'koka',
  },
}

vim.treesitter.language.register('koka', 'koka')

-- Indentation is installed from a FileType autocommand rather than only from
-- ftplugin/koka.lua: plugins that set `indentexpr` from their own FileType
-- autocommand (nvim-treesitter, for one) register it from the user config,
-- which runs before plugin scripts, so this callback runs last and wins.
vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('kokanvim_indent', { clear = true }),
  pattern = 'koka',
  callback = function(args)
    require('koka.indent').setup(args.buf)
  end,
})

-- Register the :checkhealth koka module.
-- `vim.health` is a runtime module and is absent in minimal contexts (e.g.
-- nixpkgs' neovim require check), so guard the registration.
if vim.health and vim.health.register then
  vim.health.register('koka', require('koka.health').check)
end
