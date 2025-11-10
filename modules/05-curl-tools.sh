#!/usr/bin/env bash

# =============================================================================
# Module 04: Curl-based Tools
# =============================================================================
# Install tools via curl scripts: Claude CLI, fnm, PNPM.
# =============================================================================

module_05_curl_tools() {
  log_section "Module 04: Installing Curl-based Tools"

  local tools_to_install=()

  # Read tool URLs from TOML config
  local claude_url
  local fnm_url
  local pnpm_url

  claude_url="$(get_toml_value "curl_tools.claude_cli" 2>/dev/null || echo "$CLAUDE_CLI_INSTALL_URL")"
  fnm_url="$(get_toml_value "curl_tools.fnm" 2>/dev/null || echo "$FNM_INSTALL_URL")"
  pnpm_url="$(get_toml_value "curl_tools.pnpm" 2>/dev/null || echo "$PNPM_INSTALL_URL")"

  # Install Claude CLI
  log_subsection "Claude CLI"

  if command_exists claude; then
    log_success "Claude CLI is already installed"
    claude --version 2>/dev/null || true
  else
    log_info "Installing Claude CLI from $claude_url"

    if [[ "$DRY_RUN" == "true" ]]; then
      log_dry_run "Would install Claude CLI"
    else
      bash <(curl -fsSL "$claude_url") || {
        log_error "Failed to install Claude CLI"
      }

      if command_exists claude; then
        log_success "Claude CLI installed successfully"
      else
        log_warning "Claude CLI installation completed but command not found in PATH"
      fi
    fi
  fi

  # Install fnm (Fast Node Manager)
  log_subsection "fnm (Fast Node Manager)"

  if command_exists fnm; then
    log_success "fnm is already installed"
    fnm --version 2>/dev/null || true
  else
    log_info "Installing fnm from $fnm_url"

    if [[ "$DRY_RUN" == "true" ]]; then
      log_dry_run "Would install fnm"
    else
      curl -fsSL "$fnm_url" | bash || {
        log_error "Failed to install fnm"
      }

      # Source fnm in current shell
      if [[ -f "$HOME/.bashrc" ]]; then
        # shellcheck disable=SC1090
        source "$HOME/.bashrc" 2>/dev/null || true
      fi

      if command_exists fnm; then
        log_success "fnm installed successfully"
        fnm --version
      else
        log_warning "fnm installation completed but command not found in PATH"
        log_info "You may need to restart your shell or source ~/.bashrc"
      fi
    fi
  fi

  # Install PNPM
  log_subsection "PNPM"

  if command_exists pnpm; then
    log_success "PNPM is already installed"
    pnpm --version 2>/dev/null || true
  else
    log_info "Installing PNPM from $pnpm_url"

    if [[ "$DRY_RUN" == "true" ]]; then
      log_dry_run "Would install PNPM"
    else
      curl -fsSL "$pnpm_url" | sh - || {
        log_error "Failed to install PNPM"
      }

      # Source PNPM in current shell
      if [[ -d "$HOME/Library/pnpm" ]]; then
        export PNPM_HOME="$HOME/Library/pnpm"
        export PATH="$PNPM_HOME:$PATH"
      fi

      if command_exists pnpm; then
        log_success "PNPM installed successfully"
        pnpm --version
        log_info "Note: Node.js version management is handled by fnm (installed above)"
      else
        log_warning "PNPM installation completed but command not found in PATH"
        log_info "You may need to restart your shell"
      fi
    fi
  fi

  log_success "Curl-based tools installation completed"
  return 0
}

# Run module if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  module_05_curl_tools
fi
