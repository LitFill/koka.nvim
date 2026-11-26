-- Introduce a new filetype for koka
vim.filetype.add {
  extension = {
    kk = 'koka',
  },
}

vim.treesitter.language.register('koka', 'koka')

-- Register the :checkhealth koka module.
vim.health.register('koka', require('koka.health').check)
