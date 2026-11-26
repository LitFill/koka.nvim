---@mod koka.project
---@brief [[
---Project detection and configuration management for Koka
---@brief ]]
local lsp_helpers = require('koka.lsp.helpers')

local project = {}

---Validate project configuration
---@param config koka.project.Config
---@return boolean ok True if valid, false otherwise
---@return string|nil err Error message if invalid, nil if valid
local function validate_config(config)
  -- Validate target (expanded to all current Koka targets)
  local valid_targets = {
    c = true,
    c32 = true,
    c64 = true,
    c64c = true,
    js = true,
    jsnode = true,
    jsweb = true,
    wasm = true,
    wasm32 = true,
    wasm64 = true,
    wasmjs = true,
    wasmweb = true,
    cs = true,
  }
  if not valid_targets[config.target] then
    vim.notify(
      string.format(
        'Koka project config: invalid target %s. Supported: c, c32, c64, c64c, js, jsnode, jsweb, wasm, wasm32, wasm64, wasmjs, wasmweb, cs. Falling back to c',
        config.target
      ),
      vim.log.levels.WARN
    )
    config.target = 'c'
  end

  -- Validate compiler_args is a table
  if config.compiler_args and type(config.compiler_args) ~= 'table' then
    return false, 'compiler_args must be a table'
  end

  -- Validate include_dirs is a table
  if config.include_dirs and type(config.include_dirs) ~= 'table' then
    return false, 'include_dirs must be a table'
  end

  return true, nil
end

---@class koka.project.Config
---@field cwd? string Current working directory for compiler / running the output
---@field target string target (c,c32,c64,c64c,js,jsnode,jsweb,wasm,wasm32,wasm64,wasmjs,wasmweb,cs)
---@field include_dirs string[] compiler include directories
---@field compiler_args string[] extra arguments to pass

---Get project directory by looking for koka.json, .koka.json, or package.kk
---@param path string The directory to search upward from
---@param callback? fun(project_dir: string?, project_config: koka.project.Config?) If `nil`, this function runs synchronously
---@return string? project_dir (if `callback ~= nil` and successful)
---@return koka.project.Config? project_config (if `callback ~= nil` and successful)
---Run sync_fn. Return its value when callback is nil. Else call callback with it.
---@param callback? fun(value: any)
---@param sync_fn fun(): any
---@return any
local function maybe_async(callback, sync_fn)
  if callback then
    callback(sync_fn())
  else
    return sync_fn()
  end
end

local function get_project_config(path, callback)
  -- First find the project directory by looking for koka.json, .koka.json, or package.kk
  local project_dir = vim.fs.dirname(vim.fs.find({ 'koka.json', '.koka.json', 'package.kk' }, {
    upward = true,
    path = path,
  })[1])

  if not project_dir then
    if callback then
      callback(nil, nil)
      return
    else
      return nil, nil
    end
  end

  -- Try to find and parse configuration files
  local config_files = { 'koka.json', '.koka.json' }
  local project_config = nil

  for _, config_file in ipairs(config_files) do
    local config_path = vim.fs.joinpath(project_dir, config_file)
    local file = io.open(config_path, 'r')
    if file then
      local content = file:read('*all')
      file:close()

      local ok, config = pcall(vim.json.decode, content, { luanil = { object = true, array = true } })
      if ok and config then
        project_config = config
        break
      else
        vim.notify(
          string.format('[koka.nvim] Error parsing config file %s: %s', config_path, config),
          vim.log.levels.ERROR
        )
      end
    end
  end

  if callback then
    callback(project_dir, project_config)
    return
  else
    return project_dir, project_config
  end
end

---The default implementation used for `vim.g.koka.server.root_dir`
---@param file_name string
---@param callback? fun(root_dir: string | nil) If `nil`, this function runs synchronously
---@return string | nil root_dir (if `callback ~= nil` and successful)
local function default_get_root_dir(file_name, callback)
  local function root_dir(project_dir, project_config)
    -- If project_config has explicit cwd, use that
    if project_config and project_config.cwd then
      return project_config.cwd
    end
    -- Otherwise use the project directory
    return project_dir
  end

  return maybe_async(callback, function()
    local stat = vim.uv.fs_stat(file_name)
    if not stat then
      return nil
    end
    local path = stat.type == 'file' and vim.fs.dirname(file_name) or file_name
    if not path or not vim.uv.fs_stat(path) then
      return nil
    end
    local project_dir, project_config = get_project_config(path)
    return root_dir(project_dir, project_config)
  end)
end

---Checks if there is an active Koka LSP client for file_name and returns its root directory if found.
---@param file_name string
---@return string | nil root_dir The root directory of the active client for file_name (if there is one)
local function get_mb_active_client_root(file_name)
  local clients = lsp_helpers.get_active_lsp_clients()
  local normalized_file_name = vim.fs.normalize(file_name)
  for _, client in ipairs(clients) do
    if client.config.root_dir then
      local normalized_root_dir = vim.fs.normalize(client.config.root_dir)
      -- Use path separator-aware prefix match to avoid /a/foo matching /a/foobar
      if vim.startswith(normalized_file_name .. '/', normalized_root_dir .. '/') then
        return normalized_root_dir
      end
    end
  end
  return nil
end

---Attempts to find the root for an existing active client. If no existing
---client root is found, returns the result of evaluating `config.root_dir`.
---@param config table LSP client configuration
---@param file_name string
---@param callback? fun(root_dir: string?) If `nil`, this function runs synchronously
---@return string | nil root_dir
function project.get_config_root_dir(config, file_name, callback)
  local reuse_active = get_mb_active_client_root(file_name)
  if reuse_active then
    return callback and callback(reuse_active) or reuse_active
  end
  if type(config.root_dir) == 'function' then
    local root_dir = config.root_dir(file_name, default_get_root_dir)
    return callback and callback(root_dir) or root_dir
  elseif type(config.root_dir) == 'string' then
    local root_dir = config.root_dir
    ---@cast root_dir string
    return callback and callback(root_dir) or root_dir
  else
    return default_get_root_dir(file_name, callback)
  end
end

---Get project configuration for the given file or current buffer
---@param file_name? string The file path (defaults to current buffer)
---@param callback? fun(project_config: koka.project.Config?) If `nil`, this function runs synchronously
---@return koka.project.Config? project_config (if `callback ~= nil` and successful)
function project.get_project_config(file_name, callback)
  file_name = file_name or vim.api.nvim_buf_get_name(0)
  local current_dir = vim.fs.dirname(file_name)

  return maybe_async(callback, function()
    local _, project_config = get_project_config(current_dir)
    return project_config
  end)
end

---Get resolved project configuration with defaults applied
---@param file_name? string The file path (defaults to current buffer)
---@param callback? fun(resolved_config: koka.project.Config) If `nil`, this function runs synchronously
---@return koka.project.Config? resolved_config (if `callback == nil` and successful)
function project.get_resolved_config(file_name, callback)
  file_name = file_name or vim.api.nvim_buf_get_name(0)
  local current_dir = vim.fs.dirname(file_name)

  local default_config = {
    target = 'c',
    cwd = nil, -- will be resolved
    include_dirs = {},
    compiler_args = {},
  }

  ---@param project_config? koka.project.Config
  ---@return koka.project.Config
  local function resolve_config(project_config)
    if project_config then
      return vim.tbl_deep_extend('force', {}, default_config, project_config)
    else
      return vim.deepcopy(default_config)
    end
  end

  ---@param project_dir? string
  ---@param project_config? koka.project.Config
  ---@return koka.project.Config
  local function finalize(project_dir, project_config)
    local resolved = resolve_config(project_config)
    -- Resolve cwd if not explicitly set
    if not resolved.cwd then
      resolved.cwd = project_dir or current_dir
    end
    -- If cwd is relative, resolve it relative to the project directory
    if resolved.cwd then
      if not (resolved.cwd:match('^/') or resolved.cwd:match('^%a:')) then
        local base_dir = project_dir or current_dir
        resolved.cwd = vim.fs.joinpath(base_dir, resolved.cwd)
      end
      resolved.cwd = vim.fs.normalize(resolved.cwd)
    end
    -- Validate the resolved config
    local valid, err = validate_config(resolved)
    if not valid then
      vim.notify('Koka project config validation error: ' .. tostring(err), vim.log.levels.WARN)
    end
    return resolved
  end

  if callback then
    get_project_config(current_dir, function(project_dir, project_config)
      callback(finalize(project_dir, project_config))
    end)
  else
    local project_dir, project_config = get_project_config(current_dir)
    return finalize(project_dir, project_config)
  end
end

return project
