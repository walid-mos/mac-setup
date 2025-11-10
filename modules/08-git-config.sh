#!/usr/bin/env bash

# =============================================================================
# Module 07: Git Configuration
# =============================================================================
# Configure Git user information and global settings.
# =============================================================================

module_08_git_config() {
  log_section "Module 07: Configuring Git"

  # Get git config from TOML
  local git_user_name
  local git_user_email
  local git_push_auto_setup

  git_user_name=$(parse_toml_value "$TOML_CONFIG" "git.user_name" 2>/dev/null)
  git_user_email=$(parse_toml_value "$TOML_CONFIG" "git.user_email" 2>/dev/null)
  git_push_auto_setup=$(parse_toml_value "$TOML_CONFIG" "git.push_auto_setup_remote" 2>/dev/null)

  # Configure user.name
  if [[ -n "$git_user_name" ]]; then
    log_info "Setting git user.name: $git_user_name"

    if [[ "$DRY_RUN" == "true" ]]; then
      log_dry_run "Would set: git config --global user.name \"$git_user_name\""
    else
      git config --global user.name "$git_user_name" || {
        log_error "Failed to set git user.name"
      }
      log_success "Git user.name set to: $git_user_name"
    fi
  else
    log_warning "No git user_name found in TOML configuration"
  fi

  # Configure user.email
  if [[ -n "$git_user_email" ]]; then
    log_info "Setting git user.email: $git_user_email"

    if [[ "$DRY_RUN" == "true" ]]; then
      log_dry_run "Would set: git config --global user.email \"$git_user_email\""
    else
      git config --global user.email "$git_user_email" || {
        log_error "Failed to set git user.email"
      }
      log_success "Git user.email set to: $git_user_email"
    fi
  else
    log_warning "No git user_email found in TOML configuration"
  fi

  # Configure push.autoSetupRemote
  if [[ "$git_push_auto_setup" == "true" ]]; then
    log_info "Setting git push.autoSetupRemote: true"

    if [[ "$DRY_RUN" == "true" ]]; then
      log_dry_run "Would set: git config --global push.autoSetupRemote true"
    else
      git config --global push.autoSetupRemote true || {
        log_error "Failed to set git push.autoSetupRemote"
      }
      log_success "Git push.autoSetupRemote enabled"
    fi
  fi

  # Display current git config
  log_subsection "Current Git Configuration"

  local current_name
  local current_email
  local current_push

  current_name=$(git config --global user.name 2>/dev/null || echo "Not set")
  current_email=$(git config --global user.email 2>/dev/null || echo "Not set")
  current_push=$(git config --global push.autoSetupRemote 2>/dev/null || echo "Not set")

  echo -e "  user.name:            ${COLOR_CYAN}$current_name${COLOR_RESET}"
  echo -e "  user.email:           ${COLOR_CYAN}$current_email${COLOR_RESET}"
  echo -e "  push.autoSetupRemote: ${COLOR_CYAN}$current_push${COLOR_RESET}"
  echo ""

  log_success "Git configuration completed"
  return 0
}

# Run module if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  module_08_git_config
fi
