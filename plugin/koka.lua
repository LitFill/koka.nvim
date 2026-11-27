-- Introduce a new filetype for koka
vim.filetype.add {
  extension = {
    kk = 'koka',
  },
}

vim.treesitter.language.register('koka', 'koka')

-- Register the :checkhealth koka module.
-- `vim.health` is a runtime module and is absent in minimal contexts (e.g.
-- nixpkgs' neovim require check), so guard the registration.
if vim.health and vim.health.register then
  vim.health.register('koka', require('koka.health').check)
end
