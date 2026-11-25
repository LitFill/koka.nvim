# Koka.nvim

A comprehensive Neovim plugin for the
[Koka programming language](https://koka-lang.github.io/koka/doc/index.html),
providing syntax highlighting, LSP integration, TreeSitter support, and
intelligent code execution.

## Features

- 🎨 **Syntax Highlighting** - TreeSitter-based syntax highlighting for
  `.kk` files
- 🔍 **LSP Integration** - Full Language Server Protocol support with
  automatic server management
- 🚀 **Code Execution** - Smart function execution via codelens with `main`,
  `test*`, and `example*` function support
- ⚡ **TreeSitter Management** - Built-in commands for managing the Koka
  TreeSitter parser
- 📁 **Project Configuration** - Support for `koka.json` and `.koka.json`
  project configuration files
- 🎯 **Filetype Plugin** - Zero-configuration setup that activates
  automatically for `.kk` files

## Installation

### Lazy.nvim (Recommended)

```lua
{
  "syaiful6/koka.nvim",
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
  },
}
```

### Packer.nvim

```lua
use {
  "syaiful6/koka.nvim",
  requires = { "nvim-treesitter/nvim-treesitter" },
}
```

### vim-plug

```vim
Plug 'nvim-treesitter/nvim-treesitter'
Plug 'syaiful6/koka.nvim'
```

## Requirements

- Neovim 0.11.0 or later
- [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
- [Koka compiler](https://koka-lang.github.io/koka/doc/book.html#install)
  (for LSP and execution features)

## Usage

The plugin automatically activates when you open a `.kk` file. No manual setup
required!

### Koka Subcommands

All commands are under `:Koka <subcommand>`:

| Command | Description |
|---------|-------------|
| `:Koka run` | Run function at cursor |
| `:Koka build` | Build current file or project |
| `:Koka test` | Run all test functions in current buffer |
| `:Koka config` | Show current project configuration |
| `:Koka refresh_codelens` | Refresh code lenses |
| `:Koka goto <file>` | Open a `.kk` file by name (with or without `.kk`) |
| `:Koka help` | Show the command list in a float |
| `:Koka lsp start` | Start the Koka LSP server |
| `:Koka lsp stop` | Stop the Koka LSP server |
| `:Koka lsp restart` | Restart the Koka LSP server |

### Code Execution

The plugin provides intelligent code execution through codelens. Supported
function patterns:

- **`main()`** - Main entry point functions
- **`test*()`** - Test functions (e.g., `testBasic`, `testAdvanced`)
- **`example*()`** - Example functions (e.g., `exampleUsage`, `exampleSort`)

### Codelens Features

When LSP is active, codelens appear above runnable functions showing
"▶ function_name". Use `:Koka run` to execute the function at cursor:

- **Smart Compilation**: Uses `koka/compileFunction` for individual functions,
  `koka/compile` for main
- **Multi-target Support**: Supports C, JavaScript (Node.js), WebAssembly, and
  other Koka targets
- **Terminal Integration**: Opens execution results in a new terminal tab
- **Fallback Mode**: Works without LSP using direct `koka -e` execution

> **Note**: Codelens may be clickable in some Neovim configurations, but the
> recommended way to run functions is using `:Koka run` command.

## Project Configuration

Create a `koka.json` or `.koka.json` file in your project root:

```json
{
  "target": "c",
  "cwd": "./build",
  "include_dirs": ["lib", "src"],
  "compiler_args": ["--optimize=2"]
}
```

### Configuration Options

| Option | Type | Description | Default |
|--------|------|-------------|---------|
| `target` | string | Compilation target | `"c"` |
| `cwd` | string | Working directory for compiler/execution | Project root |
| `include_dirs` | string[] | Additional include directories | `[]` |
| `compiler_args` | string[] | Extra compiler arguments | `[]` |

Supported targets: `c`, `c32`, `c64c`, `wasm`, `jsnode`

**`wasm` target**: Compiles to WebAssembly. Requires a WebAssembly runtime to execute.

**`jsnode` target**: Compiles to Node.js JavaScript. Requires Node.js runtime.

### `koka.json` for `wasm` target example

```json
{
  "target": "wasm",
  "cwd": "./www",
  "include_dirs": ["src"],
  "compiler_args": ["--buildtag=jsnode"]
}
```

### `koka.json` for `jsnode` target example

```json
{
  "target": "jsnode",
  "cwd": "./www",
  "include_dirs": ["src"],
  "compiler_args": ["--buildtag=jsnode"]
}
```

## Advanced Configuration

### Lazy.nvim with Custom Setup

```lua
{
  "syaiful6/koka.nvim",
  dependencies = {
    "nvim-treesitter/nvim-treesitter",
    "neovim/nvim-lspconfig", -- Optional: for additional LSP features
  },
  config = function()
    -- Plugin automatically configures on filetype detection
    -- Optional: Add custom keymaps
    vim.api.nvim_create_autocmd("FileType", {
      pattern = "koka",
      callback = function()
        local buf = vim.api.nvim_get_current_buf()
        vim.keymap.set("n", "<leader>kr", ":Koka run<CR>",
          { buffer = buf, desc = "Run Koka function at cursor" })

        vim.keymap.set("n", "<leader>kb", ":Koka build<CR>",
          { buffer = buf, desc = "Build Koka file" })
      end,
    })
  end,
}
```

### LSP Configuration

The plugin automatically starts the Koka LSP server. For manual configuration:

```lua
-- In your LSP configuration
require'lspconfig'.koka.setup{
  -- LSP server will be managed by koka.nvim
  autostart = false,
}
```

## File Structure

```text
koka.nvim/
├── ftplugin/koka.lua           # Filetype plugin entry point
├── lua/koka/
│   ├── init.lua                # Empty module (filetype-based architecture)
│   ├── internal.lua            # Main plugin initialization
│   ├── commands/
│   │   ├── init.lua           # General commands setup
│   │   ├── codelens.lua       # Code execution and codelens
│   │   └── treesitter.lua     # TreeSitter management
│   ├── config/
│   │   └── internal.lua       # Configuration management
│   ├── lsp/
│   │   ├── init.lua           # LSP client management
│   │   └── helpers.lua        # LSP utility functions
│   ├── project.lua            # Project detection and config parsing
│   └── debugger.lua           # Code execution via LSP commands
└── queries/koka/              # TreeSitter queries
   ├── highlights.scm
   ├── indents.scm
   ├── injections.scm
   └── locals.scm
```

## Development

### Building and Testing

This project uses Nix for development environment and testing:

```bash
# Enter development shell
nix develop

# Run tests
busted tests/

# Run all checks (linting, type checking, tests)
nix flake check

# Format code
nix fmt
```

### Available Development Commands

```bash
# Run tests with specific Neovim versions
nix build ".#checks.x86_64-linux.nvim-stable-tests"
nix build ".#checks.x86_64-linux.nvim-nightly-tests"

# Type checking
nix build ".#checks.x86_64-linux.type-check-nightly"

# Build minimal Neovim with plugin for testing
nix build .#nvim-minimal-stable
```

## Architecture

This plugin follows a **filetype-based architecture**:

1. **`ftplugin/koka.lua`** - Activated automatically when opening `.kk` files
2. **`lua/koka/internal.lua`** - Handles plugin initialization and command setup
3. **Command modules** - Modular command implementations for different features
4. **Zero setup required** - Everything works out of the box

## Troubleshooting

### TreeSitter Issues

```bash
# Check parser status (via nvim-treesitter)
:TSInstall koka

# Reinstall parser
:TSUninstall koka
:TSInstall koka
```

### LSP Issues

```bash
# Check LSP client status and configuration
:LspInfo

# Start LSP server
:Koka lsp start

# Restart LSP server
:Koka lsp restart

# Stop LSP server
:Koka lsp stop
```

### Execution Issues

1. Ensure Koka compiler is installed and in PATH
2. Check project configuration with `:Koka config`
3. Verify LSP is running with `:LspInfo`
4. For C target, ensure you have a C compiler installed
5. For `wasm` target, ensure you have a WebAssembly runtime installed
6. For `jsnode` target, ensure Node.js is installed and in PATH

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Run `nix flake check` to ensure all checks pass
6. Submit a pull request

## Thanks

This plugin wouldn't be possible without these open source projects:

- [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
- [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig)
- [Koka Language](https://koka-lang.github.io/koka/)
- [tree-sitter-koka](https://github.com/koka-community/tree-sitter-koka)

## License

MIT License - see [LICENSE](LICENSE) file for details.
