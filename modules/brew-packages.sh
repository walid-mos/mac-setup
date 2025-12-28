#!/usr/bin/env bash

# =============================================================================
# Brew Packages
# =============================================================================
# Install Homebrew formula packages from TOML configuration.
# =============================================================================

module_brew_packages() {
  log_section " Installing Homebrew Packages"

  # Dynamically detect all package categories from TOML
  local categories
  categories=$(get_toml_section_keys "$TOML_CONFIG" "brew.packages")

  if [[ -z "$categories" ]]; then
    log_warning "No brew package categories found in TOML configuration"
    return 0
  fi

  local all_packages=()

  # Collect all packages from different categories
  while IFS= read -r category; do
    [[ -z "$category" ]] && continue
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
  done <<< "$categories"

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
  module_brew_packages
fi
