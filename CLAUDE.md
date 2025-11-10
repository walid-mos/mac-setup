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
- **`modules/`**: 13 independent installation modules (can run standalone or selectively)
- **`automatisations/`**: User-defined custom scripts (auto-discovered, run last)

### Execution Flow

```
setup.sh
  ↓
Validation (validators.sh) → User confirmation
  ↓
Module execution (sequential, order matters):
  prerequisites → homebrew → script-dependencies → [TOML parser init]
  → curl-tools → brew-packages → brew-casks → oh-my-zsh
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

## Module Dependencies

Critical dependencies (order matters):
- **Module 1** (prerequisites) → provides `git`
- **Module 2** (homebrew) → provides `brew`
- **Module 3** (script-dependencies) → provides `dasel` + `jq` (REQUIRED for TOML parsing)
- **Module 5** (brew-packages) → provides `stow`, `fzf`
- **Module 7** (oh-my-zsh) → must run BEFORE stow-dotfiles

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

### Clone Repos Module Details
- **Intelligent destination mapping**:
  1. Check `repo_overrides` first (specific repo → path)
  2. Check `destinations` (org/group → path)
  3. Interactive fallback (fzf selection or custom path)
- **Authentication**: Prompts for `gh auth login` / `glab auth login` if needed
- **Interactive selection**: Uses fzf multi-select with destination preview
- **Format**: `repo-name [destination/] description`

### Automatisations System
- **Auto-discovery**: All `*.sh` files in `automatisations/`
- **Execution order**: Alphabetical by filename
- **Naming convention**:
  - File: `kebab-case.sh` (e.g., `backup-configs.sh`)
  - Function: `automation_snake_case` (e.g., `automation_backup_configs`)
  - TOML key: same as filename without `.sh`
- **Error handling**: Interactive prompt to continue or abort on failure
- **Required**: Must return 0 (success) or 1 (failure)

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
- `STOW_AUTO_DETECT`: Auto-detect all stow packages (default: true)

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
