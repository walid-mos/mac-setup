#!/usr/bin/env bash

# =============================================================================
# Module 05: Brew Packages
# =============================================================================
# Install Homebrew formula packages from TOML configuration.
# =============================================================================

module_06_brew_packages() {
  log_section "Module 05: Installing Homebrew Packages"

  # Get all package categories from TOML
  local categories=("core_tools" "terminals" "shell" "docker" "dev" "languages")
  local all_packages=()

  # Collect all packages from different categories
  for category in "${categories[@]}"; do
    local packages
    packages=$(parse_toml_array "$TOML_CONFIG" "brew.packages.$category" 2>/dev/null)

    if [[ -n "$packages" ]]; then
      log_subsection "Category: $category"

      while IFS= read -r package; do
        [[ -z "$package" ]] && continue
        # Skip comments and invalid package names
        [[ "$package" =~ ^[[:space:]]*# ]] && continue
        [[ "$package" =~ ^[[:space:]]*$ ]] && continue
        [[ "$package" =~ = ]] && continue
        all_packages+=("$package")

        if is_brew_package_installed "$package"; then
          log_verbose "Already installed: $package"
        else
          log_info "Installing: $package"

          if [[ "$DRY_RUN" == "true" ]]; then
            log_dry_run "Would install: $package"
          else
            brew install "$package" || {
              log_error "Failed to install: $package"
            }

            if is_brew_package_installed "$package"; then
              log_success "Installed: $package"
            fi
          fi
        fi
      done <<< "$packages"
    fi
  done

  # Summary
  if [[ ${#all_packages[@]} -eq 0 ]]; then
    log_warning "No brew packages found in TOML configuration"
  else
    log_success "Processed ${#all_packages[@]} brew packages"
  fi

  return 0
}

# Run module if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  module_06_brew_packages
fi
