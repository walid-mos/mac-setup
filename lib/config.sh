#!/usr/bin/env bash

# =============================================================================
# Mac Setup Configuration
# =============================================================================
# Centralized configuration file for all setup variables.
# Modify these values to customize the installation behavior.
# Can be overridden via environment variables.
# =============================================================================

# -----------------------------------------------------------------------------
# Dotfiles Repository
# -----------------------------------------------------------------------------
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/walid-mos/dotfiles.git}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.stow_repository}"
DOTFILES_BRANCH="${DOTFILES_BRANCH:-v3}"

# -----------------------------------------------------------------------------
# Stow Configuration
# -----------------------------------------------------------------------------
STOW_ADOPT="${STOW_ADOPT:-false}"                   # Adopt existing configs or backup?
STOW_VERBOSE="${STOW_VERBOSE:-false}"               # Detailed stow logs
STOW_EXCLUDE_DIRS=("mac-setup" ".git" ".github" "README.md" "CLAUDE.md" ".DS_Store")

# -----------------------------------------------------------------------------
# Backup Configuration
# -----------------------------------------------------------------------------
BACKUP_DIR="${BACKUP_DIR:-$HOME/.mac-setup-backup-$(date +%Y%m%d-%H%M%S)}"
BACKUP_EXISTING_CONFIGS="${BACKUP_EXISTING_CONFIGS:-true}"

# -----------------------------------------------------------------------------
# Logging Configuration
# -----------------------------------------------------------------------------
LOG_FILE="${LOG_FILE:-$HOME/.mac-setup.log}"
ENABLE_COLORS="${ENABLE_COLORS:-true}"
VERBOSE_MODE="${VERBOSE_MODE:-false}"

# -----------------------------------------------------------------------------
# Homebrew Configuration
# -----------------------------------------------------------------------------
HOMEBREW_INSTALL_URL="${HOMEBREW_INSTALL_URL:-https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh}"
HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-/opt/homebrew}"

# -----------------------------------------------------------------------------
# Oh My Zsh Configuration
# -----------------------------------------------------------------------------
OH_MY_ZSH_INSTALL_URL="${OH_MY_ZSH_INSTALL_URL:-https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh}"
OH_MY_ZSH_DIR="${OH_MY_ZSH_DIR:-$HOME/.config/zsh/.oh-my-zsh}"
OH_MY_ZSH_CUSTOM="${OH_MY_ZSH_CUSTOM:-$OH_MY_ZSH_DIR/custom}"
OH_MY_ZSH_PLUGINS=(
  "git"
)

# Custom plugin repositories
# Note: Using associative array - requires bash 4+
if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
  declare -A OH_MY_ZSH_PLUGIN_REPOS=()
fi

# -----------------------------------------------------------------------------
# Directory Structure
# -----------------------------------------------------------------------------
DEV_ROOT="${DEV_ROOT:-$HOME/Development}"

# Subdirectories are created dynamically from TOML [repositories.destinations]
# No hardcoded paths - fully scalable

# -----------------------------------------------------------------------------
# Git Repository Cloning
# -----------------------------------------------------------------------------
CLONE_PARALLEL_JOBS="${CLONE_PARALLEL_JOBS:-5}"  # Number of parallel git clone jobs

# -----------------------------------------------------------------------------
# macOS Defaults
# -----------------------------------------------------------------------------
APPLY_MACOS_DEFAULTS="${APPLY_MACOS_DEFAULTS:-true}"
RESTART_SERVICES="${RESTART_SERVICES:-true}"  # Restart Dock/Finder after config

# Dock configuration
DOCK_AUTOHIDE="${DOCK_AUTOHIDE:-false}"
DOCK_SIZE="${DOCK_SIZE:-48}"
DOCK_MRU_SPACES="${DOCK_MRU_SPACES:-false}"  # Disable "most recently used" spaces

# Finder configuration
FINDER_SHOW_HIDDEN="${FINDER_SHOW_HIDDEN:-true}"
FINDER_SHOW_EXTENSIONS="${FINDER_SHOW_EXTENSIONS:-true}"
FINDER_VIEW_STYLE="${FINDER_VIEW_STYLE:-Clmv}"  # Column view
FINDER_DISABLE_DS_STORE="${FINDER_DISABLE_DS_STORE:-true}"

# System configuration
SYSTEM_DISABLE_GATEKEEPER="${SYSTEM_DISABLE_GATEKEEPER:-true}"
SYSTEM_FAST_KEY_REPEAT="${SYSTEM_FAST_KEY_REPEAT:-true}"
SYSTEM_SPACES_SPAN_DISPLAYS="${SYSTEM_SPACES_SPAN_DISPLAYS:-true}"

# -----------------------------------------------------------------------------
# Node.js Configuration
# -----------------------------------------------------------------------------
NODEJS_DEFAULT_VERSION="${NODEJS_DEFAULT_VERSION:-latest}"  # fnm install version

# -----------------------------------------------------------------------------
# Docker/Colima Configuration
# -----------------------------------------------------------------------------
COLIMA_CPU="${COLIMA_CPU:-4}"                 # Number of CPUs
COLIMA_MEMORY="${COLIMA_MEMORY:-8}"           # Memory in GB
COLIMA_DISK="${COLIMA_DISK:-60}"              # Disk size in GB
COLIMA_ARCH="${COLIMA_ARCH:-aarch64}"         # Architecture (aarch64 for M1/M2)

# -----------------------------------------------------------------------------
# Timeouts (in seconds)
# -----------------------------------------------------------------------------
CURL_TIMEOUT="${CURL_TIMEOUT:-300}"
GIT_CLONE_TIMEOUT="${GIT_CLONE_TIMEOUT:-600}"
BREW_INSTALL_TIMEOUT="${BREW_INSTALL_TIMEOUT:-1800}"

# -----------------------------------------------------------------------------
# Script Behavior
# -----------------------------------------------------------------------------
DRY_RUN="${DRY_RUN:-false}"
SKIP_MODULES=()  # Array of module numbers to skip (e.g., "05" "09")
RUN_ONLY_MODULE=""  # Run only a specific module (e.g., "03")

# -----------------------------------------------------------------------------
# TOML Configuration File
# -----------------------------------------------------------------------------
TOML_CONFIG="${TOML_CONFIG:-$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")/mac-setup.toml}"

# -----------------------------------------------------------------------------
# Script Metadata
# -----------------------------------------------------------------------------
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="Mac Setup Automation"
SCRIPT_AUTHOR="walid-mos"

# -----------------------------------------------------------------------------
# Validation
# -----------------------------------------------------------------------------

# Ensure critical variables are set
if [[ -z "$DOTFILES_REPO" ]]; then
  echo "ERROR: DOTFILES_REPO is not set"
  exit 1
fi

if [[ -z "$DOTFILES_DIR" ]]; then
  echo "ERROR: DOTFILES_DIR is not set"
  exit 1
fi

# Export all variables for use in subshells
export DOTFILES_REPO DOTFILES_DIR DOTFILES_BRANCH
export STOW_ADOPT STOW_VERBOSE
export BACKUP_DIR BACKUP_EXISTING_CONFIGS
export LOG_FILE ENABLE_COLORS VERBOSE_MODE
export HOMEBREW_INSTALL_URL HOMEBREW_PREFIX
export OH_MY_ZSH_INSTALL_URL OH_MY_ZSH_DIR OH_MY_ZSH_CUSTOM
export DEV_ROOT
export CLONE_PARALLEL_JOBS
export APPLY_MACOS_DEFAULTS RESTART_SERVICES
export DOCK_AUTOHIDE DOCK_SIZE DOCK_MRU_SPACES
export FINDER_SHOW_HIDDEN FINDER_SHOW_EXTENSIONS FINDER_VIEW_STYLE FINDER_DISABLE_DS_STORE
export SYSTEM_DISABLE_GATEKEEPER SYSTEM_FAST_KEY_REPEAT SYSTEM_SPACES_SPAN_DISPLAYS
export NODEJS_DEFAULT_VERSION
export COLIMA_CPU COLIMA_MEMORY COLIMA_DISK COLIMA_ARCH
export CURL_TIMEOUT GIT_CLONE_TIMEOUT BREW_INSTALL_TIMEOUT
export DRY_RUN SKIP_MODULES RUN_ONLY_MODULE
export TOML_CONFIG
export SCRIPT_VERSION SCRIPT_NAME SCRIPT_AUTHOR
