-- Test helpers and setup for koka.nvim tests

---@diagnostic disable: duplicate-set-field

local helpers = {}

-- Mock vim global for testing
_G.vim = _G.vim or {}

-- Get the absolute path to the test directory
local function get_test_dir()
  local current_file = debug.getinfo(1, 'S').source:sub(2)
  local dir = vim.fs.dirname(current_file)
  if not dir:match('^/') then
    dir = vim.fs.joinpath(vim.uv.cwd(), dir)
  end
  return dir
end

helpers.test_dir = get_test_dir()
helpers.example_projects_dir = vim.fs.joinpath(vim.fs.dirname(helpers.test_dir), 'example-projects')

-- Mock vim.notify
vim.notify = vim.notify or function(msg, level)
  print(string.format('[%s] %s', level or 'INFO', msg))
end

-- Mock vim.log
vim.log = vim.log or {
  levels = {
    DEBUG = 1,
    INFO = 2,
    WARN = 3,
    ERROR = 4,
  },
}

-- Mock vim.api functions
vim.api = vim.api or {}
vim.api.nvim_buf_get_name = function(_bufnr)
  return '/test/project/main.kk'
end

vim.api.nvim_get_current_buf = function()
  return 0
end

-- Mock vim.lsp functions
vim.lsp = vim.lsp or {}
vim.lsp.get_clients = function(_)
  return {}
end

vim.lsp.start = function(_, _)
  return 1 -- Return mock client id
end

vim.lsp.config = vim.lsp.config or {}

-- Run scheduled callbacks synchronously so tests can assert on them
vim.schedule = function(fn)
  fn()
end

-- Mock vim.defer_fn
vim.defer_fn = vim.defer_fn or function(fn, _)
  fn() -- Execute immediately in tests
end

-- Mock vim.fn functions
vim.fn = vim.fn or {}
vim.fn.fnamemodify = vim.fn.fnamemodify
  or function(path, modifier)
    if modifier == ':h' then
      return vim.fs.dirname(path)
    end
    return path
  end

vim.fn.has = vim.fn.has or function(feature)
  if feature == 'nvim-0.11' then
    return 1
  end
  return 0
end

vim.fn.jobstart = vim.fn.jobstart
  or function(_, opts)
    -- Mock jobstart - call on_exit with success
    if opts and opts.on_exit then
      opts.on_exit(1, 0)
    end
    return 1
  end

-- Test helper functions for real project structures
helpers.get_project_path = function(project_name)
  return vim.fs.joinpath(helpers.example_projects_dir, project_name)
end

helpers.get_file_path = function(project_name, file_path)
  return vim.fs.joinpath(helpers.get_project_path(project_name), file_path)
end

helpers.reset_mocks = function()
  -- Reset global state between tests
  _G.vim.g = {}
  package.loaded['koka.project'] = nil
  package.loaded['koka.lsp'] = nil
  package.loaded['koka.commands.codelens'] = nil
end

return helpers
