#!/usr/bin/env bash

# =============================================================================
# Homebrew
# =============================================================================
# Install Homebrew package manager.
# =============================================================================

# Detect brew path based on architecture
get_brew_path() {
  if [[ -f "/opt/homebrew/bin/brew" ]]; then
    echo "/opt/homebrew/bin/brew"
  elif [[ -f "/usr/local/bin/brew" ]]; then
    echo "/usr/local/bin/brew"
  fi
}

# Source brew shellenv and clear hash table
ensure_brew_in_path() {
  local brew_path
  brew_path="$(get_brew_path)"

  if [[ -n "$brew_path" ]]; then
    eval "$("$brew_path" shellenv)" 2>/dev/null || true
    hash -r
    return 0
  fi
  return 1
}

module_homebrew() {
  log_section "Homebrew: Installing Homebrew"

  # Ensure Homebrew is in PATH if already installed
  # Critical for non-login shells (e.g., bash <(curl ...)) where .zprofile isn't sourced
  ensure_brew_in_path

  # Check if Homebrew is already installed
  if command_exists brew; then
    log_success "Homebrew is already installed"
    log_info "$(brew --version | head -n1)"

    # Update Homebrew
    log_info "Updating Homebrew..."
    if [[ "$DRY_RUN" == "true" ]]; then
      log_dry_run "Would run: brew update"
    else
      brew update || log_warning "Failed to update Homebrew"
    fi

    return 0
  fi

  # Fresh installation
  log_info "Installing Homebrew from $HOMEBREW_INSTALL_URL"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_dry_run "Would install Homebrew"
    return 0
  fi

  /bin/bash -c "$(curl -fsSL "$HOMEBREW_INSTALL_URL")" || {
    log_error_exit "Failed to install Homebrew"
  }

  log_success "Homebrew installed successfully"

  # Add to PATH for current session
  log_info "Configuring Homebrew in PATH..."
  if ! ensure_brew_in_path; then
    log_error_exit "Homebrew binary not found after installation"
  fi

  # Verify installation
  if command_exists brew; then
    log_success "$(brew --version | head -n1) is now available"
  else
    log_error_exit "Homebrew not found after installation"
  fi

  # Add to shell profile for future sessions
  local brew_path
  brew_path="$(get_brew_path)"
  local zprofile="$HOME/.zprofile"

  if [[ ! -f "$zprofile" ]] || ! grep -q "brew shellenv" "$zprofile"; then
    log_info "Adding Homebrew initialization to $zprofile"
    {
      echo ""
      echo "# Homebrew"
      echo "eval \"\$($brew_path shellenv)\""
    } >> "$zprofile"
    log_success "Homebrew added to shell profile"
  fi

  return 0
}

# Run module if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  module_homebrew
fi
