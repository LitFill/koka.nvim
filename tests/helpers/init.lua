-- Test helpers and setup for koka.nvim tests

---@diagnostic disable: duplicate-set-field

local helpers = {}

-- Mock vim global for testing
_G.vim = _G.vim or {}

-- Get the absolute path to the test directory
local function get_test_dir()
  local current_file = debug.getinfo(1, 'S').source:sub(2)
  local test_dir = vim.fs.dirname(current_file)
  return test_dir
end

helpers.test_dir = get_test_dir()
helpers.example_projects_dir = vim.fs.joinpath(helpers.test_dir, 'example-projects')

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
vim.api.nvim_buf_get_name = vim.api.nvim_buf_get_name
  or function(bufnr)
    if bufnr == 42 then
      return '/test/project/main.kk'
    end
    return '/test/project/main.kk'
  end

vim.api.nvim_get_current_buf = vim.api.nvim_get_current_buf or function()
  return 0
end

-- Mock vim.lsp functions
vim.lsp = vim.lsp or {}
vim.lsp.get_active_clients = vim.lsp.get_active_clients or function(_)
  return {}
end

vim.lsp.get_clients = vim.lsp.get_clients or function(_)
  return {}
end

vim.lsp.start_client = vim.lsp.start_client or function(_)
  return 1 -- Return mock client id
end

vim.lsp.stop_client = vim.lsp.stop_client or function(_)
  return true
end

vim.lsp.buf_attach_client = vim.lsp.buf_attach_client or function(_, _)
  return true
end

vim.lsp.start = vim.lsp.start or function(_, _)
  return 1 -- Return mock client id
end

vim.lsp.config = vim.lsp.config or {}

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

-- Temporary stub for mock_fs_find to help with test migration
helpers.mock_fs_find = function(_)
  -- This is a temporary stub - tests should be updated to use real project structures
  print('WARNING: Using deprecated mock_fs_find - please update test to use real project structures')
end

helpers.reset_mocks = function()
  -- Reset global state between tests
  _G.vim.g = {}
  package.loaded['koka.project'] = nil
  package.loaded['koka.lsp'] = nil
  package.loaded['koka.commands.codelens'] = nil
end

return helpers
