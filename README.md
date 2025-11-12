# Mac Setup Automation

Automated macOS installation and configuration script using TOML configuration and GNU Stow for dotfiles management.

---

## 🚀 Quick Start

**Get your Mac set up in one command:**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/walid-mos/dotfiles/main/mac-setup/install.sh)
```

*Installs everything: Homebrew, dev tools, applications, dotfiles, and more. Safe to run on a fresh Mac.*

---

## Features

- **🔧 Automated Installation**: Complete Mac setup with a single command
- **📦 Dynamic Stow Detection**: Automatically detects and installs all dotfiles packages
- **⚙️ TOML Configuration**: Central, readable configuration for all packages and settings
- **🎨 Modular Architecture**: 11 independent modules for flexible installation
- **🔍 Interactive Repository Cloning**: Select repos to clone with fzf multi-select
- **📝 Comprehensive Logging**: Detailed logs with color-coded output
- **🔒 Idempotent**: Safe to run multiple times
- **🧪 Dry Run Mode**: Preview changes without modifying system

## Installation

### ⚡ Quick Install (Recommended)

Run this one-liner on a fresh Mac to get started immediately:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/walid-mos/dotfiles/main/mac-setup/install.sh)
```

This will:
1. Verify prerequisites (git, bash)
2. Clone the repository to `/tmp` (temporary)
3. Show a summary of what will be installed
4. Ask for confirmation before proceeding
5. Run the full setup automatically
6. Dotfiles are installed to `~/.stow_repository` (permanent)

**Options:**
```bash
# Skip confirmation (unattended mode)
bash <(curl -fsSL https://raw.githubusercontent.com/walid-mos/dotfiles/main/mac-setup/install.sh) --yes

# Preview without making changes
bash <(curl -fsSL https://raw.githubusercontent.com/walid-mos/dotfiles/main/mac-setup/install.sh) --dry-run

# Verbose output
bash <(curl -fsSL https://raw.githubusercontent.com/walid-mos/dotfiles/main/mac-setup/install.sh) --verbose
```

### 🔒 Secure Install (Inspect First)

For maximum security, download and inspect the script before running:

```bash
# Download the installer
curl -fsSL https://raw.githubusercontent.com/walid-mos/dotfiles/main/mac-setup/install.sh -o mac-setup-install.sh

# Review the script (recommended)
less mac-setup-install.sh

# Run the installer
bash mac-setup-install.sh
```

### 🛠️ Manual Install (Full Control)

If you prefer to clone the repository yourself:

```bash
# Clone the repository
git clone https://github.com/walid-mos/dotfiles.git ~/.stow_repository
cd ~/.stow_repository/mac-setup

# Edit configuration (optional)
vim mac-setup.toml

# Run setup
./setup.sh
```

### Prerequisites

The installer requires:
- **macOS** (tested on macOS Ventura and later)
- **bash** 3.2+ (included with macOS)
- **curl** (included with macOS)

**Xcode Command Line Tools** (for git):
- If not installed, the installer will **automatically install them** (~700MB download)
- A system dialog will appear - click "Install" and accept the license
- Installation takes 2-3 minutes on a fast connection
- The script will wait for installation to complete before continuing

## What Gets Installed

### 📦 Package Managers & Tools
- **Homebrew** - macOS package manager
- **PNPM** - Fast, disk space efficient package manager
- **fnm** - Fast Node.js version manager
- **Claude CLI** - Anthropic's Claude Code CLI

### 🛠️ Development Tools
- **Neovim** - Hyperextensible Vim-based text editor
- **Git** - Version control with custom configuration
- **GitHub CLI** (`gh`) - GitHub command-line tool (requires manual `gh auth login`)
- **GitLab CLI** (`glab`) - GitLab command-line tool (requires manual `glab auth login`)
- **fzf** - Fuzzy finder for interactive selections
- **ripgrep** - Ultra-fast grep alternative
- **Docker** + **Colima** - Containerization platform (auto-configured via automatisations)
- **Railway CLI** - Deploy to Railway.app
- **Redis** - In-memory data store
- **Watchman** - File watching service

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

The setup is divided into 12 independent modules:

| Module | Name | Description |
|--------|------|-------------|
| 01 | Prerequisites | Xcode Command Line Tools |
| 02 | Homebrew | Package manager installation |
| 03 | Script Dependencies | Install dasel and jq for TOML parsing |
| 04 | Curl Tools | Claude CLI, fnm, PNPM |
| 05 | Brew Packages | Formula packages (ripgrep, neovim, etc.) |
| 06 | Brew Casks | GUI applications (VSCode, Ghostty, etc.) |
| 07 | Oh My Zsh | ZSH framework + custom plugins |
| 08 | Stow Dotfiles | Clone dotfiles repo + dynamic stow installation |
| 09 | Git Configuration | User name, email, global settings |
| 10 | Directory Structure | **Dynamic** folder creation from TOML |
| 11 | Clone Repositories | **Intelligent** cloning with destination mapping |
| 12 | macOS Defaults | System preferences (Dock, Finder, etc.) |
| 13 | Automatisations | **Custom automation scripts** (see below) |

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
# Only install brew packages
./setup.sh --module brew-packages

# Only run automatisations
./setup.sh --module automatisations

# Only clone repositories
./setup.sh --module clone-repos
```

### Skip Modules
```bash
# Skip repository cloning
./setup.sh --skip clone-repos

# Skip automatisations
./setup.sh --skip automatisations

# Skip multiple modules
./setup.sh --skip brew-packages --skip brew-casks
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

# Custom automatisations
[automations]
enabled = true
backup-configs = true
install-fonts = false
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

# Node.js Configuration
NODEJS_DEFAULT_VERSION="latest"  # fnm install version

# Docker/Colima Configuration
COLIMA_CPU=4                # Number of CPUs
COLIMA_MEMORY=8             # Memory in GB
COLIMA_DISK=60              # Disk size in GB
COLIMA_ARCH="aarch64"       # Architecture (aarch64 for M1/M2)

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

## Custom Automatisations

The `automatisations/` directory allows you to add **custom automation scripts** that run after all main modules complete.

### Features
- **Automatic Discovery**: All `.sh` files are detected and executed
- **Alphabetical Order**: Scripts run in alphabetical order
- **Opt-Out by Default**: Automatisations are **enabled by default**, set to `false` to disable
- **Interactive Error Handling**: Prompts whether to continue if a script fails
- **Full Module Support**: Access to all helper functions and logging

### Built-in Automatisations

#### 1. `setup-nodejs.sh` (Active by default)
Configures Node.js environment via fnm:
- Installs Node.js version specified in `NODEJS_DEFAULT_VERSION` (default: `"latest"`)
- Sets as default version
- Verifies pnpm installation

**To disable:**
```toml
[automations]
setup-nodejs = false
```

#### 2. `configure-docker.sh` (Active by default)
Sets up Docker/Colima with optimal settings:
- Configures CPU, memory, disk from `lib/config.sh`
- Starts Colima if not running
- Verifies Docker connectivity

**Configuration in `lib/config.sh`:**
```bash
COLIMA_CPU=4          # Adjust based on your Mac
COLIMA_MEMORY=8       # Memory in GB
COLIMA_DISK=60        # Disk size in GB
```

**To disable:**
```toml
[automations]
configure-docker = false
```

#### 3. `expand-macos-defaults.sh` (Active by default)
Additional macOS system preferences:
- **Trackpad**: Tap-to-click, three-finger drag
- **Screenshots**: Custom location (`~/Pictures/Screenshots`), PNG format, no shadow
- **Menu bar**: Battery percentage, date/time format
- **Mission Control**: Disable auto-rearrange, faster animations
- **Keyboard**: Disable press-and-hold (enable key repeat)
- **Energy**: Custom sleep settings
- **Security**: Disable Gatekeeper (allow apps from unidentified developers), disable quarantine warnings

**⚠️ Security Note:**
This automation disables Gatekeeper and quarantine warnings to facilitate development. To re-enable security:
```bash
sudo spctl --master-enable  # Re-enable Gatekeeper
```

**To disable:**
```toml
[automations]
expand-macos-defaults = false
```

### Creating Custom Automatisations

1. **Create a script** in `automatisations/`:
   ```bash
   # File: automatisations/my-custom-task.sh
   automation_my_custom_task() {
     log_info "Running my custom task..."
     # Your automation logic here
   }
   ```

2. **Script is active by default** - no TOML config needed!

3. **To disable** (opt-out approach):
   ```toml
   [automations]
   my-custom-task = false
   ```

4. **Run setup**:
   ```bash
   ./setup.sh  # Runs all modules including automatisations
   ```

### Example Use Cases
- Backup existing configurations before applying new ones
- Install custom fonts from a specific directory
- Set up project-specific environment variables
- Create additional symlinks for specific tools
- Run cleanup tasks or optimizations

### Automation Logic (Important!)

**Automatisations use an OPT-OUT approach:**
- ✅ **By default**: All `.sh` files in `automatisations/` run automatically
- ❌ **To disable**: Add `script-name = false` in `[automations]` section

This is different from traditional opt-in systems where you must explicitly enable features.

## Project Structure

```
mac-setup/
├── setup.sh                   # Main orchestrator script
├── mac-setup.toml            # TOML configuration (packages, apps)
├── README.md                 # This file
├── lib/                      # Library functions
│   ├── config.sh            # Centralized variables
│   ├── logger.sh            # Colored logging utilities
│   ├── helpers.sh           # Common helper functions
│   ├── validators.sh        # Pre-flight checks
│   └── toml-parser.sh       # TOML parsing (dasel or fallback)
├── modules/                  # Installation modules
│   ├── prerequisites.sh
│   ├── homebrew.sh
│   ├── script-dependencies.sh
│   ├── curl-tools.sh
│   ├── brew-packages.sh
│   ├── brew-casks.sh
│   ├── oh-my-zsh.sh
│   ├── stow-dotfiles.sh
│   ├── git-config.sh
│   ├── directories.sh
│   ├── clone-repos.sh
│   ├── macos-defaults.sh
│   └── automatisations.sh   # Dynamic automation loader
└── automatisations/          # Custom automation scripts
    ├── README.md            # Detailed documentation
    ├── .gitkeep             # Track empty directory
    └── example-automation.sh.template  # Template for new scripts
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
   gh auth login    # GitHub (required for repository cloning)
   glab auth login  # GitLab (required for repository cloning)
   ```

5. **VS Code Settings Sync** (if using VS Code):
   - Open VS Code
   - Sign in with GitHub account
   - Extensions and settings will sync automatically

6. **Review Log File**:
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
