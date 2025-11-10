# Mac Setup Automation

Automated macOS installation and configuration script using TOML configuration and GNU Stow for dotfiles management.

## Features

- **🔧 Automated Installation**: Complete Mac setup with a single command
- **📦 Dynamic Stow Detection**: Automatically detects and installs all dotfiles packages
- **⚙️ TOML Configuration**: Central, readable configuration for all packages and settings
- **🎨 Modular Architecture**: 11 independent modules for flexible installation
- **🔍 Interactive Repository Cloning**: Select repos to clone with fzf multi-select
- **📝 Comprehensive Logging**: Detailed logs with color-coded output
- **🔒 Idempotent**: Safe to run multiple times
- **🧪 Dry Run Mode**: Preview changes without modifying system

## Quick Start

```bash
# Clone this repository
git clone https://github.com/walid-mos/dotfiles.git ~/.stow_repository
cd ~/.stow_repository/mac-setup

# Edit configuration (optional)
vim mac-setup.toml

# Run installation
./setup.sh
```

## What Gets Installed

### 📦 Package Managers & Tools
- **Homebrew** - macOS package manager
- **PNPM** - Fast, disk space efficient package manager
- **fnm** - Fast Node.js version manager
- **Claude CLI** - Anthropic's Claude Code CLI

### 🛠️ Development Tools
- **Neovim** - Hyperextensible Vim-based text editor
- **Git** - Version control with custom configuration
- **GitHub CLI** (`gh`) - GitHub command-line tool
- **GitLab CLI** (`glab`) - GitLab command-line tool
- **fzf** - Fuzzy finder for interactive selections
- **ripgrep** - Ultra-fast grep alternative
- **Docker** + **Colima** - Containerization platform

### 💻 Terminal & Shell
- **Ghostty** - Native macOS terminal emulator
- **Zellij** - Terminal multiplexer
- **Oh My Zsh** - ZSH framework with plugins
- **Starship** - Fast, customizable shell prompt

### 📁 Applications
- **Visual Studio Code** - Code editor
- **Cursor** - AI-powered code editor
- **Raycast** - Productivity launcher
- **Rectangle** - Window management
- **IINA** - Modern media player
- And more... (see `mac-setup.toml`)

### ⚙️ Dotfiles (via Stow)
**Dynamic detection** - Automatically finds and symlinks ALL packages in your repository:
- `zsh/` - ZSH configuration
- `nvim/` - Neovim configuration
- `ghostty/` - Ghostty terminal configuration
- `claude/` - Claude CLI configuration
- Any other packages you add to your dotfiles repo!

### 📂 Directory Structure (Dynamic & Intelligent)
Created automatically based on your TOML configuration:

```
~/Development/
├── nextnode/                  # NextnodeSolutions + nextnode org repos
├── saas/                      # Personal projects (walid-mos)
└── clients/
    ├── igocreate/             # iGocreate organization repos
    └── fleurs-aujourdhui/     # Specific client projects (via overrides)
```

**Fully customizable** - Add new folders by updating `mac-setup.toml`!

## Installation Modules

The setup is divided into 11 independent modules:

| Module | Name | Description |
|--------|------|-------------|
| 01 | Prerequisites | Xcode Command Line Tools |
| 02 | Homebrew | Package manager installation |
| 03 | Stow Dotfiles | Clone dotfiles repo + dynamic stow installation |
| 04 | Curl Tools | Claude CLI, fnm, PNPM |
| 05 | Brew Packages | Formula packages (ripgrep, neovim, etc.) |
| 06 | Brew Casks | GUI applications (VSCode, Ghostty, etc.) |
| 07 | Git Configuration | User name, email, global settings |
| 08 | Directory Structure | **Dynamic** folder creation from TOML |
| 09 | Clone Repositories | **Intelligent** cloning with destination mapping |
| 10 | Oh My Zsh | ZSH framework + custom plugins |
| 11 | macOS Defaults | System preferences (Dock, Finder, etc.) |

## Usage

### Full Installation
```bash
./setup.sh
```

### Dry Run (Preview Only)
```bash
./setup.sh --dry-run
```

### Verbose Output
```bash
./setup.sh --verbose
```

### Run Specific Module
```bash
# Only install stow dotfiles
./setup.sh --module 03

# Only install brew packages
./setup.sh --module 05
```

### Skip Modules
```bash
# Skip repository cloning
./setup.sh --skip 09

# Skip macOS defaults
./setup.sh --skip-macos

# Skip multiple modules
./setup.sh --skip 05 --skip 06 --skip 09
```

### Stow Options
```bash
# Adopt existing configs instead of backing up
./setup.sh --adopt

# Don't backup existing configs (fail on conflicts)
./setup.sh --no-backup
```

## Configuration

### TOML Configuration (`mac-setup.toml`)

Defines **WHAT** to install:

```toml
[git]
user_name = "Your Name"
user_email = "your.email@example.com"

[brew.packages]
core_tools = ["stow", "fzf", "ripgrep", "neovim"]

[brew.casks]
browsers = ["firefox", "google-chrome"]

[repositories]
github_orgs = ["nextnode", "walid-mos"]
gitlab_groups = ["NextnodeSolutions", "igocreate"]

# Intelligent destination mapping
[repositories.destinations]
nextnode = "nextnode"
walid-mos = "saas"
NextnodeSolutions = "nextnode"
igocreate = "clients/igocreate"

# Specific repo overrides
[repositories.repo_overrides]
florist-bouquet-preview = "clients/fleurs-aujourdhui"
```

### Shell Configuration (`lib/config.sh`)

Defines **HOW** to install:

```bash
# Dotfiles
DOTFILES_REPO="https://github.com/walid-mos/dotfiles.git"
DOTFILES_DIR="$HOME/.stow_repository"

# Stow behavior
STOW_AUTO_DETECT=true      # Auto-detect ALL packages
STOW_ADOPT=false
BACKUP_EXISTING_CONFIGS=true

# Directory structure (dynamic from TOML)
DEV_ROOT="$HOME/Development"

# Cloning
CLONE_PARALLEL_JOBS=5

# macOS Defaults
APPLY_MACOS_DEFAULTS=true
DOCK_AUTOHIDE=false
FINDER_SHOW_HIDDEN=true
```

## Interactive Features

### Repository Cloning (Module 09) - Intelligent & Dynamic

The script provides **intelligent destination mapping**:

1. **Automatic Mapping**: Repos clone to destinations based on organization
   - `nextnode` org → `~/Development/nextnode/`
   - `walid-mos` → `~/Development/saas/`
   - `igocreate` → `~/Development/clients/igocreate/`

2. **Override System**: Specific repos can go to custom locations
   - `florist-bouquet-preview` → `~/Development/clients/fleurs-aujourdhui/`

3. **Interactive fzf Selection**:
   - Shows destination preview: `repo-name [nextnode/] Description`
   - Multi-select with Tab
   - Only clone what you need

4. **Fallback for Unmapped Repos**:
   - If no mapping exists, asks interactively where to clone
   - Can create new destination folders on the fly

```bash
# Will show intelligent repo selection
./setup.sh --module 09
```

### Conflict Handling (Module 03)

When stowing dotfiles, the script handles conflicts:

- **Backup mode** (default): Backs up conflicting files to timestamped folder
- **Adopt mode** (`--adopt`): Merges existing configs into dotfiles repo
- **Fail mode** (`--no-backup`): Stops on conflicts with clear error messages

## Project Structure

```
mac-setup/
├── setup.sh                # Main orchestrator script
├── mac-setup.toml         # TOML configuration (packages, apps)
├── README.md              # This file
├── lib/                   # Library functions
│   ├── config.sh         # Centralized variables
│   ├── logger.sh         # Colored logging utilities
│   ├── helpers.sh        # Common helper functions
│   ├── validators.sh     # Pre-flight checks
│   └── toml-parser.sh    # TOML parsing (dasel or fallback)
└── modules/               # Installation modules
    ├── 01-prerequisites.sh
    ├── 02-homebrew.sh
    ├── 03-stow-dotfiles.sh
    ├── 04-curl-tools.sh
    ├── 05-brew-packages.sh
    ├── 06-brew-casks.sh
    ├── 07-git-config.sh
    ├── 08-directories.sh
    ├── 09-clone-repos.sh
    ├── 10-oh-my-zsh.sh
    └── 11-macos-defaults.sh
```

## Logging

All operations are logged to:
```
~/.mac-setup.log
```

Color-coded console output:
- 🔵 **INFO**: General information
- ✅ **SUCCESS**: Completed successfully
- ⚠️ **WARNING**: Non-critical issues
- ❌ **ERROR**: Critical failures
- ℹ️ **VERBOSE**: Detailed debugging (with `--verbose`)

## Advanced Usage

### Environment Variable Overrides

```bash
# Change clone path
DEFAULT_CLONE_PATH="$HOME/Code" ./setup.sh

# Increase parallel jobs
CLONE_PARALLEL_JOBS=10 ./setup.sh

# Disable macOS defaults
APPLY_MACOS_DEFAULTS=false ./setup.sh

# Custom dotfiles repo
DOTFILES_REPO="https://github.com/myuser/dotfiles.git" ./setup.sh
```

### Run Single Module Manually

```bash
# Source required libraries
source lib/config.sh
source lib/logger.sh
source lib/helpers.sh

# Run specific module
source modules/05-brew-packages.sh
module_05_brew_packages
```

### Adding Custom Packages

Edit `mac-setup.toml`:

```toml
[brew.packages]
my_custom_tools = ["htop", "ncdu", "btop"]

[brew.casks]
my_apps = ["slack", "zoom"]
```

Run installation:
```bash
./setup.sh --module 05  # For packages
./setup.sh --module 06  # For casks
```

## Troubleshooting

### Issue: "TOML file not found"
**Solution**: Ensure you're in the `mac-setup/` directory when running the script.

### Issue: "Stow conflicts detected"
**Solution**: Use `--adopt` to merge configs or `--backup` (default) to backup conflicting files.

### Issue: "GitHub CLI not authenticated"
**Solution**: Run `gh auth login` before module 09, or the script will prompt you.

### Issue: "Permission denied on macOS defaults"
**Solution**: Some macOS defaults require sudo. The script will prompt when needed.

### Issue: "Homebrew not in PATH"
**Solution**: Restart your terminal or run:
```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
```

## Post-Installation

After successful installation:

1. **Restart Terminal** or source your shell:
   ```bash
   source ~/.zshrc
   ```

2. **Verify Installations**:
   ```bash
   brew --version
   git --version
   nvim --version
   pnpm --version
   claude --version
   ```

3. **Configure Git** (if not done via TOML):
   ```bash
   git config --global user.name "Your Name"
   git config --global user.email "your.email@example.com"
   ```

4. **Authenticate CLIs**:
   ```bash
   gh auth login    # GitHub
   glab auth login  # GitLab
   ```

5. **Review Log File**:
   ```bash
   cat ~/.mac-setup.log
   ```

## Uninstallation

To remove stowed dotfiles:
```bash
cd ~/.stow_repository
stow -D */  # Unstow all packages
```

To remove Homebrew packages:
```bash
brew list --formula  # List packages
brew uninstall <package>
```

## Contributing

This is a personal dotfiles setup, but feel free to fork and customize for your own use!

## License

MIT License - See LICENSE file for details

## Author

**walid-mos**
- GitHub: [@walid-mos](https://github.com/walid-mos)
- Email: pro.walid.mostefaoui@gmail.com

---

**⚠️ Note**: This script will make system-wide changes. Always review the configuration files before running, especially on production machines.
