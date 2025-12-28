#!/usr/bin/env bash

# =============================================================================
# Homebrew
# =============================================================================
# Install Homebrew package manager.
# =============================================================================

module_homebrew() {
  log_section "Homebrew: Installing Homebrew"

  # Check if Homebrew is already installed
  if command_exists brew; then
    log_success "Homebrew is already installed"
    local brew_version
    brew_version="$(brew --version | head -n1)"
    log_info "$brew_version"

    # Update Homebrew
    log_info "Updating Homebrew..."
    if [[ "$DRY_RUN" == "true" ]]; then
      log_dry_run "Would run: brew update"
    else
      brew update || log_warning "Failed to update Homebrew"
    fi

    # Clear hash table in case brew commands were cached as "not found"
    hash -r
    return 0
  fi

  log_info "Installing Homebrew from $HOMEBREW_INSTALL_URL"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_dry_run "Would install Homebrew"
    return 0
  fi

  # Download and execute Homebrew installation script
  /bin/bash -c "$(curl -fsSL "$HOMEBREW_INSTALL_URL")" || {
    log_error_exit "Failed to install Homebrew"
  }

  log_success "Homebrew installed successfully"

  # Add Homebrew to PATH for current session
  log_info "Configuring Homebrew in PATH..."

  if [[ -f "$HOMEBREW_PREFIX/bin/brew" ]]; then
    eval "$("$HOMEBREW_PREFIX/bin/brew" shellenv)" || {
      log_warning "Failed to eval brew shellenv"
    }
  fi

  # Clear hash table after PATH update
  hash -r

  # Verify installation
  if command_exists brew; then
    local brew_version
    brew_version="$(brew --version | head -n1)"
    log_success "$brew_version is now available"
  else
    log_error_exit "Homebrew not found after installation"
  fi

  # Add Homebrew to shell profile (zsh)
  local zshrc="$HOME/.zprofile"
  local brew_init_line='eval "$(/opt/homebrew/bin/brew shellenv)"'

  if [[ ! -f "$zshrc" ]] || ! grep -q "brew shellenv" "$zshrc"; then
    log_info "Adding Homebrew initialization to $zshrc"
    echo "" >> "$zshrc"
    echo "# Homebrew" >> "$zshrc"
    echo "$brew_init_line" >> "$zshrc"
    log_success "Homebrew added to shell profile"
  fi

  return 0
}

# Run module if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  module_homebrew
fi
