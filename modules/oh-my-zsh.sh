#!/usr/bin/env bash

# =============================================================================
# Oh My Zsh
# =============================================================================
# Install Oh My Zsh and custom plugins.
# =============================================================================

module_oh_my_zsh() {
  log_section " Installing Oh My Zsh"

  # Check if Oh My Zsh is already installed
  if [[ -d "$OH_MY_ZSH_DIR" ]]; then
    log_success "Oh My Zsh is already installed at: $OH_MY_ZSH_DIR"

    # Update Oh My Zsh
    log_info "Updating Oh My Zsh..."
    if [[ "$DRY_RUN" == "true" ]]; then
      log_dry_run "Would update Oh My Zsh"
    else
      (
        cd "$OH_MY_ZSH_DIR" || exit 1
        git pull origin master &>/dev/null || log_warning "Failed to update Oh My Zsh"
      )
    fi
  else
    log_info "Installing Oh My Zsh from $OH_MY_ZSH_INSTALL_URL"

    if [[ "$DRY_RUN" == "true" ]]; then
      log_dry_run "Would install Oh My Zsh"
    else
      # Set ZSH environment variable to custom location
      export ZSH="$OH_MY_ZSH_DIR"

      # Install Oh My Zsh (unattended mode)
      RUNZSH=no CHSH=no sh -c "$(curl -fsSL "$OH_MY_ZSH_INSTALL_URL")" || {
        log_error "Failed to install Oh My Zsh"
        return 1
      }

      log_success "Oh My Zsh installed successfully"
    fi
  fi

  # Install custom plugins
  log_subsection "Installing Custom Plugins"

  ensure_directory "$OH_MY_ZSH_CUSTOM/plugins"

  for plugin in "${OH_MY_ZSH_PLUGINS[@]}"; do
    # Skip built-in plugins
    if [[ "$plugin" == "git" ]] || [[ "$plugin" == "z" ]] || [[ "$plugin" == "docker" ]]; then
      log_verbose "Built-in plugin, skipping: $plugin"
      continue
    fi

    # Check if plugin has a repository URL
    # Handle plugin repositories
    local plugin_repo=""
    if [[ "$plugin" == "zsh-shift-select" ]]; then
      plugin_repo="https://github.com/jirutka/zsh-shift-select.git"
    fi

    if [[ -n "$plugin_repo" ]]; then
      local plugin_dir="$OH_MY_ZSH_CUSTOM/plugins/$plugin"

      if [[ -d "$plugin_dir/.git" ]]; then
        log_verbose "Plugin already installed: $plugin"

        # Update plugin
        log_info "Updating plugin: $plugin"
        if [[ "$DRY_RUN" == "true" ]]; then
          log_dry_run "Would update plugin: $plugin"
        else
          (
            cd "$plugin_dir" || exit 1
            git pull origin master &>/dev/null || git pull origin main &>/dev/null || log_warning "Failed to update: $plugin"
          )
        fi
      else
        log_info "Installing plugin: $plugin"

        if [[ "$DRY_RUN" == "true" ]]; then
          log_dry_run "Would clone: $plugin_repo -> $plugin_dir"
        else
          git clone "$plugin_repo" "$plugin_dir" || {
            log_error "Failed to install plugin: $plugin"
            continue
          }
          log_success "Installed plugin: $plugin"
        fi
      fi
    else
      log_warning "No repository URL for plugin: $plugin"
    fi
  done

  log_success "Oh My Zsh installation completed"
  return 0
}

# Run module if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  module_oh_my_zsh
fi
