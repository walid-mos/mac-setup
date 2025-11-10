#!/usr/bin/env bash

# =============================================================================
# Brew Casks
# =============================================================================
# Install Homebrew cask applications from TOML configuration.
# =============================================================================

module_brew_casks() {
  log_section " Installing Homebrew Casks"

  # Get all cask categories from TOML
  local categories=("browsers" "productivity" "media" "dev" "creative" "utilities")
  local all_casks=()

  # Collect all casks from different categories
  for category in "${categories[@]}"; do
    local casks
    casks=$(parse_toml_array "$TOML_CONFIG" "brew.casks.$category" 2>/dev/null)

    if [[ -n "$casks" ]]; then
      log_subsection "Category: $category"

      while IFS= read -r cask; do
        [[ -z "$cask" ]] && continue
        # Skip comments and invalid cask names
        [[ "$cask" =~ ^[[:space:]]*# ]] && continue
        [[ "$cask" =~ ^[[:space:]]*$ ]] && continue
        [[ "$cask" =~ = ]] && continue
        all_casks+=("$cask")

        if is_brew_cask_installed "$cask"; then
          log_verbose "Already installed: $cask"
        else
          log_info "Installing cask: $cask"

          if [[ "$DRY_RUN" == "true" ]]; then
            log_dry_run "Would install cask: $cask"
          else
            brew install --cask "$cask" || {
              log_error "Failed to install cask: $cask"
            }

            if is_brew_cask_installed "$cask"; then
              log_success "Installed cask: $cask"
            fi
          fi
        fi
      done <<< "$casks"
    fi
  done

  # Summary
  if [[ ${#all_casks[@]} -eq 0 ]]; then
    log_warning "No brew casks found in TOML configuration"
  else
    log_success "Processed ${#all_casks[@]} brew casks"
  fi

  return 0
}

# Run module if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  module_brew_casks
fi
