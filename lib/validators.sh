#!/usr/bin/env bash

# =============================================================================
# Validation Functions
# =============================================================================
# Pre-flight checks and validations before running installation modules.
# =============================================================================

# -----------------------------------------------------------------------------
# Validate running on macOS
# -----------------------------------------------------------------------------
validate_macos() {
  log_subsection "Validating macOS"

  if ! is_macos; then
    log_error_exit "This script must be run on macOS"
  fi

  local version
  version="$(get_macos_version)"
  log_success "Running on macOS $version"

  # Check minimum version (macOS 11.0 Big Sur or later)
  if ! check_macos_version "11.0"; then
    log_warning "macOS version older than Big Sur (11.0) detected"
    log_warning "Some features may not work correctly"

    if ! ask_yes_no "Continue anyway?" "n"; then
      log_error_exit "Installation cancelled by user"
    fi
  fi

  return 0
}

# -----------------------------------------------------------------------------
# Validate not running as sudo
# -----------------------------------------------------------------------------
validate_not_sudo() {
  log_subsection "Validating user permissions"

  if is_sudo; then
    log_error_exit "This script should NOT be run with sudo. Please run as normal user."
  fi

  log_success "Running as normal user (not root)"
  return 0
}

# -----------------------------------------------------------------------------
# Validate internet connectivity
# -----------------------------------------------------------------------------
validate_internet() {
  log_subsection "Validating internet connection"

  if ! check_internet; then
    log_error_exit "No internet connection detected. Please check your network and try again."
  fi

  log_success "Internet connection is available"
  return 0
}

# -----------------------------------------------------------------------------
# Validate disk space
# -----------------------------------------------------------------------------
validate_disk_space() {
  local required_gb="${1:-10}"  # Default 10GB minimum

  log_subsection "Validating disk space"

  local available_gb
  available_gb="$(get_available_space)"

  log_info "Available disk space: ${available_gb}GB"

  if [[ $available_gb -lt $required_gb ]]; then
    log_error "Insufficient disk space. Required: ${required_gb}GB, Available: ${available_gb}GB"

    if ! ask_yes_no "Continue anyway?" "n"; then
      log_error_exit "Installation cancelled due to insufficient disk space"
    fi
  else
    log_success "Sufficient disk space available"
  fi

  return 0
}

# -----------------------------------------------------------------------------
# Validate Xcode Command Line Tools
# -----------------------------------------------------------------------------
validate_xcode_cli() {
  log_subsection "Validating Xcode Command Line Tools"

  if xcode-select -p &> /dev/null; then
    log_success "Xcode Command Line Tools are installed"
    return 0
  else
    log_warning "Xcode Command Line Tools not found"
    return 1
  fi
}

# -----------------------------------------------------------------------------
# Validate Homebrew
# -----------------------------------------------------------------------------
validate_homebrew() {
  log_subsection "Validating Homebrew"

  if command_exists brew; then
    local brew_version
    brew_version="$(brew --version | head -n1)"
    log_success "Homebrew is installed: $brew_version"
    return 0
  else
    log_warning "Homebrew is not installed"
    return 1
  fi
}

# -----------------------------------------------------------------------------
# Validate Git
# -----------------------------------------------------------------------------
validate_git() {
  log_subsection "Validating Git"

  if command_exists git; then
    local git_version
    git_version="$(git --version)"
    log_success "$git_version is installed"
    return 0
  else
    log_error "Git is not installed"
    return 1
  fi
}

# -----------------------------------------------------------------------------
# Require specific tool (exit if not found)
# -----------------------------------------------------------------------------
# Usage: require_tool <command> [error_message]
# Example: require_tool brew "Please run module 01 (Homebrew) first"
require_tool() {
  local tool="$1"
  local error_msg="${2:-$tool is required but not installed}"

  if ! command_exists "$tool"; then
    log_error_exit "$error_msg"
  fi

  return 0
}

# -----------------------------------------------------------------------------
# Validate required commands
# -----------------------------------------------------------------------------
validate_required_commands() {
  local commands=("curl" "bash" "grep" "sed" "awk")
  local missing_commands=()

  log_subsection "Validating required commands"

  for cmd in "${commands[@]}"; do
    if command_exists "$cmd"; then
      log_verbose "✓ $cmd is available"
    else
      log_error "✗ $cmd is not available"
      missing_commands+=("$cmd")
    fi
  done

  if [[ ${#missing_commands[@]} -gt 0 ]]; then
    log_error_exit "Missing required commands: ${missing_commands[*]}"
  fi

  log_success "All required commands are available"
  return 0
}

# -----------------------------------------------------------------------------
# Validate TOML config file exists
# -----------------------------------------------------------------------------
validate_toml_config() {
  log_subsection "Validating TOML configuration"

  if [[ ! -f "$TOML_CONFIG" ]]; then
    log_error_exit "TOML configuration file not found: $TOML_CONFIG"
  fi

  log_success "TOML configuration found: $TOML_CONFIG"
  return 0
}

# -----------------------------------------------------------------------------
# Validate dotfiles repository URL
# -----------------------------------------------------------------------------
validate_dotfiles_repo() {
  log_subsection "Validating dotfiles repository"

  if [[ -z "$DOTFILES_REPO" ]]; then
    log_error_exit "DOTFILES_REPO is not set in configuration"
  fi

  log_info "Dotfiles repository: $DOTFILES_REPO"

  # Check if it's a valid Git URL
  if [[ ! "$DOTFILES_REPO" =~ ^(https?|git)://.*\.git$ ]] && [[ ! "$DOTFILES_REPO" =~ ^git@.*\.git$ ]]; then
    log_warning "Dotfiles repository URL may not be valid: $DOTFILES_REPO"

    if ! ask_yes_no "Continue anyway?" "n"; then
      log_error_exit "Installation cancelled by user"
    fi
  fi

  log_success "Dotfiles repository URL validated"
  return 0
}

# -----------------------------------------------------------------------------
# Validate existing dotfiles directory
# -----------------------------------------------------------------------------
validate_existing_dotfiles() {
  log_subsection "Checking for existing dotfiles"

  if [[ -d "$DOTFILES_DIR" ]]; then
    log_warning "Dotfiles directory already exists: $DOTFILES_DIR"

    if dir_exists_and_not_empty "$DOTFILES_DIR"; then
      log_warning "Directory is not empty"

      if [[ "$BACKUP_EXISTING_CONFIGS" == "true" ]]; then
        log_info "Existing directory will be backed up before proceeding"
      else
        log_error "Directory exists and BACKUP_EXISTING_CONFIGS is false"

        if ! ask_yes_no "Remove existing directory and continue?" "n"; then
          log_error_exit "Installation cancelled by user"
        fi
      fi
    fi
  else
    log_success "Dotfiles directory does not exist (will be created)"
  fi

  return 0
}

# -----------------------------------------------------------------------------
# Run all validations
# -----------------------------------------------------------------------------
run_all_validations() {
  log_section "Pre-flight Validation"

  local validation_failed=false

  # Critical validations (must pass)
  validate_macos || validation_failed=true
  validate_not_sudo || validation_failed=true
  validate_internet || validation_failed=true
  validate_required_commands || validation_failed=true
  validate_toml_config || validation_failed=true
  validate_dotfiles_repo || validation_failed=true

  # Warning validations (can continue)
  validate_disk_space 10 || true
  validate_xcode_cli || log_warning "Xcode CLI tools will be installed in module 01"
  validate_homebrew || log_warning "Homebrew will be installed in module 02"
  validate_git || log_warning "Git will be installed with Xcode CLI tools"
  validate_existing_dotfiles || true

  if [[ "$validation_failed" == "true" ]]; then
    log_error_exit "Pre-flight validation failed. Please fix the errors above and try again."
  fi

  log_success "All critical validations passed"
  echo ""

  return 0
}

# -----------------------------------------------------------------------------
# Display validation summary
# -----------------------------------------------------------------------------
display_validation_summary() {
  log_subsection "Validation Summary"

  echo -e "${COLOR_BOLD}Configuration:${COLOR_RESET}"
  echo -e "  Dotfiles Repo: ${COLOR_CYAN}$DOTFILES_REPO${COLOR_RESET}"
  echo -e "  Dotfiles Dir:  ${COLOR_CYAN}$DOTFILES_DIR${COLOR_RESET}"
  echo -e "  TOML Config:   ${COLOR_CYAN}$TOML_CONFIG${COLOR_RESET}"
  echo -e "  Log File:      ${COLOR_CYAN}$LOG_FILE${COLOR_RESET}"
  echo -e "  Backup Dir:    ${COLOR_CYAN}$BACKUP_DIR${COLOR_RESET}"
  echo ""

  echo -e "${COLOR_BOLD}Options:${COLOR_RESET}"
  echo -e "  Dry Run:       ${COLOR_YELLOW}$DRY_RUN${COLOR_RESET}"
  echo -e "  Verbose:       ${COLOR_YELLOW}$VERBOSE_MODE${COLOR_RESET}"
  echo -e "  Backup:        ${COLOR_YELLOW}$BACKUP_EXISTING_CONFIGS${COLOR_RESET}"
  echo -e "  Stow Adopt:    ${COLOR_YELLOW}$STOW_ADOPT${COLOR_RESET}"
  echo ""

  if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "Running in DRY RUN mode - no changes will be made"
    echo ""
  fi

  if ! ask_yes_no "Proceed with installation?" "y"; then
    log_error_exit "Installation cancelled by user"
  fi

  echo ""
}
