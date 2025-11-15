# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

Automated macOS setup system using TOML configuration and modular bash architecture. The system orchestrates installation of development tools, applications, dotfiles (via GNU Stow), and repository cloning with intelligent destination mapping.

## Architecture

### Two-Layer Configuration

1. **WHAT to install**: `mac-setup.toml` (packages, apps, git config, repo mappings)
2. **HOW to install**: `lib/config.sh` (paths, behavior flags, timeouts)

### Core Components

- **`setup.sh`**: Main orchestrator that sources libraries, modules, and executes them sequentially
- **`lib/`**: Shared utilities (logging, TOML parsing, helpers, validators)
- **`modules/`**: 12 independent installation modules (can run standalone or selectively)
- **`automatisations/`**: User-defined custom scripts (auto-discovered, run last)

### Execution Flow

```
setup.sh
  ↓
Validation (validators.sh) → User confirmation
  ↓
Module execution (sequential, order matters):
  prerequisites → homebrew → script-dependencies → [TOML parser init]
  → curl-tools → brew-packages → brew-casks
  → stow-dotfiles → git-config → directories → clone-repos
  → macos-defaults → automatisations
  ↓
Summary report
```

### Key Design Patterns

1. **Idempotency**: All modules check state before acting (safe to re-run)
2. **Dynamic Discovery**:
   - Stow packages auto-detected from dotfiles repo
   - Automatisations auto-discovered from `automatisations/*.sh`
3. **Intelligent Mapping**: Repository cloning with TOML-based destination mapping + interactive fallback
4. **Dry-run Support**: All operations respect `DRY_RUN` flag
5. **Logging**: Color-coded console output + file logging (`~/.mac-setup.log`)

## Bootstrap Installer

### Overview

`install.sh` is a bootstrap script designed for **quick installation on fresh macOS systems**. It provides a curl-friendly one-liner that downloads the repository and launches the setup process.

**Primary use case**: Install on a brand new Mac without any prior setup.

**Architecture**:
- `install.sh` clones to `/tmp/mac-setup-$$` (temporary, auto-cleaned by OS)
- `setup.sh` runs from `/tmp` and installs dotfiles to `~/.stow_repository` (permanent)
- Installation scripts are disposable, only dotfiles persist

### Design Philosophy

- **Zero external dependencies**: Uses ONLY tools present on macOS by default
- **Security-first**: Function wrapping prevents partial execution if network fails
- **User-friendly**: Interactive confirmation with clear summary
- **Flexible**: Supports both attended and unattended modes

### Tools Used (macOS Native Only)

The bootstrap script uses **ONLY** tools present on fresh macOS:

| Tool | Purpose | Always Available? |
|------|---------|-------------------|
| `bash` | Shell interpreter (3.2+) | ✅ Yes |
| `curl` | Download script/repo | ✅ Yes |
| `xcode-select` | Install/check Xcode CLT | ✅ Yes |
| `git` | Clone repository | ⚠️ Auto-installed via xcode-select |
| `tput` | Terminal colors | ✅ Yes |
| `uname` | OS detection | ✅ Yes |
| `command` | Check tool existence | ✅ Yes |
| `read` | User input | ✅ Yes |
| `sleep` | Wait during installation | ✅ Yes |

**IMPORTANT**: On fresh macOS, `/usr/bin/git` is only a **stub** that triggers Xcode CLT installation dialog. The script automatically installs Xcode CLT (~700MB) if not present.

**NEVER use**: `dasel`, `jq`, `brew`, `fzf`, or any tool installed by setup.sh

### Execution Flow

```
install.sh
  ↓
1. Prerequisites Check
   - Verify macOS (Darwin)
   - Check bash version (≥3.2)
   - Check curl available
   - Check Xcode CLT installed
     ↓ If NOT installed:
     - Trigger xcode-select --install (~700MB download)
     - Wait for installation to complete (max 10min timeout)
     - Verify git is now available
  ↓
2. Show Summary
   - Installation location
   - What will be installed
   - Warning about system modifications
  ↓
3. User Confirmation
   - Interactive prompt (unless --yes)
   - Default: NO (safe option)
  ↓
4. Clone Repository
   - To /tmp/mac-setup-$$ (temporary location)
   - From branch specified in DOTFILES_BRANCH (default: main)
   - Or update if already exists (unlikely in /tmp)
  ↓
5. Launch setup.sh
   - Pass through all args (--dry-run, --verbose, etc.)
   - Execute from /tmp location
   - setup.sh will clone dotfiles to ~/.stow_repository (permanent)
  ↓
6. Success Message
   - Next steps
   - Authentication reminders
```

### Usage

**One-liner (recommended):**
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/walid-mos/mac-setup/main/install.sh)
```

**With options:**
```bash
# Unattended mode (skip confirmation)
bash <(curl -fsSL https://raw.githubusercontent.com/.../install.sh) --yes

# Dry-run (pass to setup.sh)
bash <(curl -fsSL https://raw.githubusercontent.com/.../install.sh) --dry-run

# Verbose output (pass to setup.sh)
bash <(curl -fsSL https://raw.githubusercontent.com/.../install.sh) --verbose
```

**Two-step (more secure):**
```bash
# 1. Download and inspect
curl -fsSL https://raw.githubusercontent.com/.../install.sh -o install.sh
less install.sh

# 2. Execute after review
bash install.sh
```

### Security Features

1. **Function Wrapping**:
   - Entire script wrapped in `main()` function
   - Executed on last line only
   - Prevents partial execution if curl is interrupted mid-download
   - Example: `rm -rf /$VAR` won't execute as `rm -rf /` if download cuts off

2. **Curl Flags** (`-fsSL`):
   - `-f`: Fail silently on HTTP errors (4xx, 5xx)
   - `-s`: Silent mode (no progress bar)
   - `-S`: Show errors even in silent mode
   - `-L`: Follow redirects (GitHub raw URLs)

3. **Safe Defaults**:
   - Confirmation required by default (must explicitly opt-in)
   - Validates prerequisites before any operations
   - Clear error messages with actionable guidance

4. **No Destructive Operations**:
   - Only clones repo (or updates existing)
   - Delegates all system modifications to setup.sh
   - User sees setup.sh's own confirmation prompts

### Argument Handling

- `--help`, `-h`: Show usage and exit
- `--yes`, `-y`, `--unattended`: Skip confirmation prompt
- **All other args**: Passed directly to `setup.sh`
  - `--dry-run` → `./setup.sh --dry-run`
  - `--verbose` → `./setup.sh --verbose`
  - `--module X` → `./setup.sh --module X`
  - etc.

### Error Handling

| Scenario | Behavior |
|----------|----------|
| Not macOS | Exit with error, show detected OS |
| Bash < 3.2 | Exit with error, show current version |
| curl missing | Exit with error (should never happen on macOS) |
| Xcode CLT missing | Auto-install: trigger xcode-select --install, wait for completion |
| Xcode CLT timeout | Exit after 10min, ask user to complete manually |
| Git still missing after CLT | Exit with error (should never happen) |
| Repo exists (not git) | Exit, ask user to remove/rename directory |
| Repo exists (git) | Pull latest changes from origin/main |
| Clone fails | Exit with potential causes (network, auth, URL) |
| setup.sh missing | Exit, mention repo structure may have changed |
| setup.sh fails | Exit with setup.sh's exit code |

### Modifying the Bootstrap Script

**When to modify:**
- Changing repository URL or structure
- Adding new prerequisite checks
- Changing default installation directory
- Adding new bootstrap-level options

**When NOT to modify:**
- Changing what gets installed → Edit `mac-setup.toml`
- Changing installation behavior → Edit `lib/config.sh` or modules
- Adding tools/dependencies → Those go in modules, not bootstrap

**Testing changes:**
```bash
# Local testing (doesn't require GitHub)
./install.sh --dry-run

# Test with actual repo clone
./install.sh --yes --dry-run

# Full test on clean VM (recommended before releasing)
# Create macOS VM, then run one-liner
```

**⚠️ CRITICAL**: Never use tools not present on fresh macOS in `install.sh`!

### Configuration Variables

The bootstrap script uses these configuration variables (lines 20-23):

```bash
REPO_URL="https://github.com/walid-mos/mac-setup.git"
DOTFILES_BRANCH="main"                    # Branch to clone
INSTALL_DIR="/tmp/mac-setup-$$"           # Temporary directory (PID-based unique name)
SETUP_SCRIPT="${INSTALL_DIR}/setup.sh"
```

**Override via environment variables:**
```bash
# Use different branch
DOTFILES_BRANCH="develop" bash <(curl -fsSL .../install.sh)

# Use different repo (for testing forks)
REPO_URL="https://github.com/myuser/mac-setup.git" bash <(curl -fsSL .../install.sh)
```

**Important**: `INSTALL_DIR` is temporary - scripts are auto-cleaned by OS. Only dotfiles in `~/.stow_repository` persist.

### File Locations

- Bootstrap script: `install.sh` (repository root)
- Prerequisites check: `install.sh:61-146` (check_prerequisites with Xcode CLT auto-install)
- Summary display: `install.sh:148-183` (show_summary function)
- User confirmation: `install.sh:185-208` (confirm_installation function)
- Repository cloning: `install.sh:210-244` (clone_repository function)
- Setup execution: `install.sh:246-278` (run_setup function)
- Usage text: `install.sh:293-330` (show_usage function)
- Main logic: `install.sh:335-356` (main function)

## Module Dependencies

Critical dependencies (order matters):
- **Module 1** (prerequisites) → provides `git`
- **Module 2** (homebrew) → provides `brew`
- **Module 3** (script-dependencies) → provides `dasel` + `jq` (REQUIRED for TOML parsing)
- **Module 5** (brew-packages) → provides `stow`, `fzf`

## TOML Configuration Structure

```toml
[curl_tools]              # URLs for curl-based installers
[git]                     # Git user config
[brew.packages]           # Grouped arrays (core_tools, terminals, etc.)
[brew.casks]              # Grouped arrays (browsers, dev, etc.)
[repositories]            # GitHub orgs, GitLab groups
  github_orgs = []
  gitlab_groups = []
  [repositories.destinations]    # org/group → destination mapping
  [repositories.repo_overrides]  # repo-specific overrides
[automations]             # enabled + per-script flags
```

## Library Functions

### `lib/logger.sh`
- `log_info`, `log_success`, `log_error`, `log_warning`, `log_progress`
- `log_verbose` (only if `VERBOSE_MODE=true`)
- `log_section`, `log_subsection`, `log_step`
- `log_command` (respects dry-run)

### `lib/helpers.sh`
- `command_exists`, `require_tool`
- `ask_yes_no` (interactive prompts)
- `clone_repo`, `install_brew_package`
- `backup_path` (timestamped backups)
- `ensure_directory`, `dir_exists_and_not_empty`

### `lib/toml-parser.sh`
- `parse_toml_value` (single value)
- `parse_toml_array` (array values, one per line)
- Uses `dasel` (fallback to awk if unavailable)
- Must call `init_toml_parser` after dasel is installed

### `lib/validators.sh`
- Pre-flight checks (macOS version, disk space, network)
- Validates TOML config exists
- Interactive approval before execution

## Common Development Tasks

### Running the Full Setup
```bash
./setup.sh                    # Full installation
./setup.sh --dry-run          # Preview without changes
./setup.sh --verbose          # Detailed output
```

### Running Specific Modules
```bash
./setup.sh --module stow-dotfiles    # Single module
./setup.sh --skip clone-repos        # Skip specific module
```

### Testing Module Changes
```bash
# Standalone module execution (must source dependencies first)
source lib/config.sh
source lib/logger.sh
source lib/helpers.sh
source modules/stow-dotfiles.sh
module_stow_dotfiles
```

### Adding New Packages
Edit `mac-setup.toml`, then:
```bash
./setup.sh --module brew-packages    # For formulas
./setup.sh --module brew-casks       # For applications
```

### Creating Custom Automatisations
```bash
# 1. Create script in automatisations/
cp automatisations/example-automation.sh.template automatisations/my-task.sh

# 2. Implement automation_my_task() function

# 3. Configure in mac-setup.toml (optional):
[automations]
my-task = true

# 4. Run
./setup.sh --module automatisations
```

## Critical Implementation Notes

### Bash Best Practices (MANDATORY)
- **NEVER use `readonly` in functions**: Causes crashes when sourcing multiple times (violates global CLAUDE.md)
- Use `local` for all function variables
- Quote all variable expansions: `"$var"`, not `$var`
- Use `[[ ]]` for conditionals, not `[ ]`
- Use `set -eo pipefail` at module start

### Stow Module Details
- **Dynamic package detection**: Scans `DOTFILES_DIR` for all directories
- **Excludes**: `.git`, `mac-setup`, etc. (see `STOW_EXCLUDE_DIRS`)
- **Conflict handling**: Three modes via flags:
  - `--adopt`: Merge existing configs into dotfiles repo
  - Default (`BACKUP_EXISTING_CONFIGS=true`): Backup conflicting files
  - `--no-backup`: Fail on conflicts
- **Process**: Clone repo → detect packages → stow each individually
- **Zsh plugin management**: Handled by Zinit in dotfiles (no OMZ dependency)

### Clone Repos Module Details
- **Intelligent destination mapping**:
  1. Check `repo_overrides` first (specific repo → path)
  2. Check `destinations` (org/group → path)
  3. Interactive fallback (fzf selection or custom path)
- **Authentication**: Prompts for `gh auth login` / `glab auth login` if needed
- **Interactive selection**: Uses fzf multi-select with destination preview
- **Format**: `repo-name [destination/] description`
- **Parallel cloning** (New!):
  - Two-phase process: resolve destinations (sequential) → clone (parallel)
  - Clones up to `CLONE_PARALLEL_JOBS` repositories simultaneously (default: 5)
  - Uses bash native job control (`wait -n` for pool management)
  - Separate functions: `clone_single_repo()` (GitHub) and `clone_single_gitlab_repo()` (GitLab)
  - Background jobs with PID tracking for proper error handling
  - Dramatically faster for multiple repositories

### macOS Defaults Module Details
- **System preferences**: Configures Dock, Finder, and system settings
- **Full Disk Access**: Required for most settings (handled by permissions-preflight module)
- **Computer Name Configuration** (New!):
  - Interactive prompt to configure computer name during setup
  - Uses current Apple-assigned name as default
  - Sets all three macOS name types:
    - `ComputerName`: User-friendly name (System Settings, network shares)
    - `LocalHostName`: Bonjour hostname (sanitized, used for .local)
    - `HostName`: Fully qualified domain name
  - Requires sudo access
  - Controlled by `PROMPT_COMPUTER_NAME` flag (default: true)
  - Name validation: max 63 chars, special chars sanitized for LocalHostName
  - Respects dry-run mode
- **Service restart**: Automatically restarts Dock, Finder, SystemUIServer if `RESTART_SERVICES=true`

### Automatisations System
- **Auto-discovery**: All `*.sh` files in `automatisations/`
- **Execution order**: Alphabetical by filename
- **Naming convention**:
  - File: `kebab-case.sh` (e.g., `backup-configs.sh`)
  - Function: `automation_snake_case` (e.g., `automation_backup_configs`)
  - TOML key: same as filename without `.sh`
- **Error handling**: Interactive prompt to continue or abort on failure
- **Required**: Must return 0 (success) or 1 (failure)

### Mail Accounts Automation
- **Script**: `automatisations/setup-mail-accounts.sh`
- **Purpose**: Generates mobileconfig profiles for email accounts
- **Configuration**: `[mail]` section in `mac-setup.toml`
- **Process**:
  1. Reads account configs from TOML (email, servers, type)
  2. Generates `.mobileconfig` files from template
  3. Saves to `~/Desktop/mail-profiles/`
  4. Displays installation instructions
- **Provider Presets**: Built-in configs for Gmail, Microsoft/Outlook, iCloud, Yahoo
- **Security**: Passwords NOT stored in config - user enters on first Mail.app launch
- **Installation**: User installs profiles via System Settings > Profiles (requires manual interaction)
- **OAuth2 Support**: Gmail/Microsoft accounts require browser authentication
- **Template**: `templates/mail-account.mobileconfig.template`

## Important Variables

### Paths
- `DOTFILES_REPO`: Git URL for dotfiles
- `DOTFILES_DIR`: Clone destination (`$HOME/.stow_repository`)
- `DEV_ROOT`: Base for cloned repos (`$HOME/Development`)
- `TOML_CONFIG`: Path to `mac-setup.toml`
- `LOG_FILE`: Log destination (`$HOME/.mac-setup.log`)

### Behavior Flags
- `DRY_RUN`: Preview mode (no changes)
- `VERBOSE_MODE`: Detailed output
- `STOW_ADOPT`: Merge vs backup on conflicts
- `BACKUP_EXISTING_CONFIGS`: Auto-backup conflicts
- `APPLY_MACOS_DEFAULTS`: Run macOS system preferences
- `PROMPT_COMPUTER_NAME`: Prompt to configure computer name during setup (default: true)
- `CLONE_PARALLEL_JOBS`: Number of parallel git clone jobs (default: 5)

### Timeouts (seconds)
- `CURL_TIMEOUT`: 300
- `GIT_CLONE_TIMEOUT`: 600
- `BREW_INSTALL_TIMEOUT`: 1800

## Troubleshooting Guide

### "TOML file not found"
Must run from `mac-setup/` directory. Script expects `./mac-setup.toml`.

### "dasel not found" after script-dependencies
This is a bug - TOML parser init happens AFTER module 3. Never call `parse_toml_*` before `init_toml_parser` is run in `setup.sh:250`.

### Stow conflicts
- Use `--adopt` to merge existing configs
- Use `--no-backup` to see exact conflicts without auto-fixing
- Conflicting files backed up to `$BACKUP_DIR` (timestamped)

### Module execution order issues
Modules MUST run in defined order due to dependencies. Never skip:
- prerequisites (provides git)
- homebrew (provides brew)
- script-dependencies (provides dasel/jq for TOML parsing)

### Authentication failures (gh/glab)
Modules prompt for authentication if needed. Can pre-authenticate:
```bash
gh auth login
glab auth login
```

## Testing Changes

1. **Dry-run first**: `./setup.sh --dry-run --module <module-name>`
2. **Single module**: `./setup.sh --module <module-name>`
3. **Verbose mode**: Add `--verbose` to see detailed execution
4. **Check logs**: `cat ~/.mac-setup.log` for full output

## Code Modification Guidelines

### Adding a New Module
1. Create `modules/<name>.sh`
2. Implement `module_<name>()` function
3. Source in `setup.sh` (order matters!)
4. Add to execution section in `main()`
5. Update usage text with module name

### Modifying TOML Structure
1. Update `mac-setup.toml` with new sections
2. Add parsing logic in relevant module
3. Document in README.md configuration section
4. Consider fallback behavior if key missing

### Adding CLI Options
1. Add case in `parse_arguments()` function
2. Set appropriate variable
3. Update `show_usage()` text
4. Document in README.md

## File Locations

- Main entry: `setup.sh:355` (main function)
- Module execution loop: `setup.sh:227-320`
- TOML parser init: `setup.sh:250` (critical - after script-dependencies)
- Stow dynamic detection: `modules/stow-dotfiles.sh:68-86`
- Repo destination mapping: `modules/clone-repos.sh:13-53`
- Automation loader: `modules/automatisations.sh` (full implementation)
