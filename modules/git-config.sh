#!/usr/bin/env bash

# =============================================================================
# Git Configuration
# =============================================================================
# Configure Git user information and global settings.
# =============================================================================

module_git_config() {
  log_section " Configuring Git"

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

  # Configure HTTPS protocol for GitHub/GitLab (no SSH keys needed)
  log_info "Configuring HTTPS protocol for GitHub and GitLab"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_dry_run "Would set: git config --global url.\"https://github.com/\".insteadOf \"ssh://git@github.com/\""
    log_dry_run "Would set: git config --global url.\"https://gitlab.com/\".insteadOf \"ssh://git@gitlab.com/\""
  else
    git config --global url."https://github.com/".insteadOf "ssh://git@github.com/" || {
      log_warning "Failed to set GitHub HTTPS URL rewrite"
    }
    git config --global url."https://gitlab.com/".insteadOf "ssh://git@gitlab.com/" || {
      log_warning "Failed to set GitLab HTTPS URL rewrite"
    }
    log_success "HTTPS protocol configured for GitHub and GitLab"
  fi

  # Configure credential helpers for GitHub and GitLab
  log_subsection "Configuring Git Credential Helpers"

  # Configure GitHub credential helper (gh)
  if command_exists gh && gh auth status &>/dev/null; then
    log_info "Configuring GitHub CLI as credential helper"

    if [[ "$DRY_RUN" == "true" ]]; then
      log_dry_run "Would run: gh auth setup-git"
    else
      gh auth setup-git &>/dev/null || {
        log_verbose "GitHub credential helper may already be configured"
      }
      log_success "GitHub credential helper configured"
    fi
  else
    log_verbose "GitHub CLI not authenticated - skipping credential helper setup"
  fi

  # Configure GitLab credential helper (glab)
  # NOTE: glab auth login SHOULD do this automatically, but there's a known bug (Issue #707)
  # where it doesn't always work. We explicitly configure it here to ensure HTTPS cloning works.
  if command_exists glab && glab auth status &>/dev/null 2>&1; then
    log_info "Configuring GitLab CLI as credential helper"

    if [[ "$DRY_RUN" == "true" ]]; then
      log_dry_run "Would set: git config --global credential.\"https://gitlab.com\".helper \"\""
      log_dry_run "Would set: git config --global --add credential.\"https://gitlab.com\".helper '!/path/to/glab auth git-credential'"
    else
      # Get the actual path to glab
      local glab_path
      glab_path=$(command -v glab)

      # Configure credential helper (use --replace-all to handle existing entries)
      # Quote the path to handle spaces in binary path
      git config --global --replace-all credential."https://gitlab.com".helper "!\"${glab_path}\" auth git-credential" || {
        # If --replace-all fails (no existing entry), try --add
        git config --global --add credential."https://gitlab.com".helper "!\"${glab_path}\" auth git-credential" || {
          log_warning "Failed to configure GitLab credential helper"
        }
      }
      log_success "GitLab credential helper configured"
    fi
  else
    log_verbose "GitLab CLI not authenticated - skipping credential helper setup"
  fi

  # Display current git config
  log_subsection "Current Git Configuration"

  local current_name
  local current_email
  local current_push
  local current_github_url
  local current_gitlab_url

  current_name=$(git config --global user.name 2>/dev/null || echo "Not set")
  current_email=$(git config --global user.email 2>/dev/null || echo "Not set")
  current_push=$(git config --global push.autoSetupRemote 2>/dev/null || echo "Not set")
  current_github_url=$(git config --global url."https://github.com/".insteadOf 2>/dev/null || echo "Not set")
  current_gitlab_url=$(git config --global url."https://gitlab.com/".insteadOf 2>/dev/null || echo "Not set")

  echo -e "  user.name:            ${COLOR_CYAN}$current_name${COLOR_RESET}"
  echo -e "  user.email:           ${COLOR_CYAN}$current_email${COLOR_RESET}"
  echo -e "  push.autoSetupRemote: ${COLOR_CYAN}$current_push${COLOR_RESET}"
  echo -e "  GitHub URL rewrite:   ${COLOR_CYAN}$current_github_url${COLOR_RESET}"
  echo -e "  GitLab URL rewrite:   ${COLOR_CYAN}$current_gitlab_url${COLOR_RESET}"
  echo ""

  log_success "Git configuration completed"
  return 0
}

# Run module if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  module_git_config
fi
