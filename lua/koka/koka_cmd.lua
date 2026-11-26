---@mod koka.koka_cmd
---@brief [[
---Build the koka argv one time.
---@brief ]]

local M = {}

---Build the common flags. No mode and no file.
---The flags are buildtag, target, include, compiler args, showtypesigs.
---@param config koka.project.Config The project config
---@param opts table Build options
---@return string[] args
function M.common_args(config, opts)
  local args = {}
  if opts.buildtag then
    table.insert(args, '--buildtag=' .. opts.buildtag)
  end
  if config.target and config.target ~= 'c' then
    table.insert(args, '--target=' .. config.target)
  end
  if config.include_dirs then
    for _, dir in ipairs(config.include_dirs) do
      table.insert(args, '--include=' .. dir)
    end
  end
  if opts.include then
    for _, dir in ipairs(opts.include) do
      table.insert(args, '--include=' .. dir)
    end
  end
  if config.compiler_args then
    vim.list_extend(args, config.compiler_args)
  end
  if opts.showtypesigs then
    table.insert(args, '--showtypesigs')
  end
  return args
end

---Build the full argv. It starts with koka.
---The options are mode, file, main_entry, buildtag, showtypesigs, include.
---@param config koka.project.Config The project config
---@param opts table Build options
---@return string[] cmd
function M.build(config, opts)
  local cmd = { 'koka' }
  vim.list_extend(cmd, M.common_args(config, opts))
  table.insert(cmd, opts.mode)
  table.insert(cmd, opts.file)
  if opts.main_entry then
    table.insert(cmd, '--main-entry=' .. opts.main_entry)
  end
  return cmd
end

return M
