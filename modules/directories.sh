#!/usr/bin/env bash

# =============================================================================
# Directory Structure
# =============================================================================
# Create development directory structure dynamically from TOML configuration.
# =============================================================================

module_directories() {
  log_section " Creating Directory Structure"

  # Ensure Development root exists
  ensure_directory "$DEV_ROOT" || {
    log_error_exit "Failed to create Development root: $DEV_ROOT"
  }

  log_info "Development root: $DEV_ROOT"

  # Extract all unique destinations from TOML
  log_subsection "Parsing TOML destinations"

  local destinations=()
  local seen_dirs=()

  # Parse [repositories.destinations] section
  log_verbose "Parsing [repositories.destinations]..."
  local dest_values
  dest_values=$(parse_toml_array "$TOML_CONFIG" "repositories.destinations" 2>/dev/null || true)

  if [[ -z "$dest_values" ]]; then
    # Fallback: parse manually with awk (BSD awk compatible)
    dest_values=$(awk '
      /^\[repositories\.destinations\]/ { in_section=1; next }
      in_section && /^\[/ { exit }
      in_section && /=/ && /"/ {
        # Extract value between quotes
        line = $0
        sub(/^[^"]*"/, "", line)
        sub(/".*$/, "", line)
        if (line) print line
      }
    ' "$TOML_CONFIG")
  fi

  while IFS= read -r dest; do
    [[ -z "$dest" ]] && continue
    destinations+=("$dest")
    log_verbose "Found destination: $dest"
  done <<< "$dest_values"

  # Parse [repositories.repo_overrides] section
  log_verbose "Parsing [repositories.repo_overrides]..."
  local override_values
  override_values=$(parse_toml_array "$TOML_CONFIG" "repositories.repo_overrides" 2>/dev/null || true)

  if [[ -z "$override_values" ]]; then
    # Fallback: parse manually with awk (BSD awk compatible)
    override_values=$(awk '
      /^\[repositories\.repo_overrides\]/ { in_section=1; next }
      in_section && /^\[/ { exit }
      in_section && /=/ && /"/ {
        # Extract value between quotes
        line = $0
        sub(/^[^"]*"/, "", line)
        sub(/".*$/, "", line)
        if (line) print line
      }
    ' "$TOML_CONFIG")
  fi

  while IFS= read -r dest; do
    [[ -z "$dest" ]] && continue
    destinations+=("$dest")
    log_verbose "Found override destination: $dest"
  done <<< "$override_values"

  # Get unique destinations (using mapfile to avoid word splitting issues)
  local unique_destinations=()
  mapfile -t unique_destinations < <(printf '%s\n' "${destinations[@]}" | sort -u)

  if [[ ${#unique_destinations[@]} -eq 0 ]]; then
    log_warning "No destinations found in TOML configuration"
    log_info "Creating default Development folder only"
    log_success "Directory structure setup completed"
    return 0
  fi

  log_success "Found ${#unique_destinations[@]} unique destination(s)"
  echo ""

  # Create all destination directories
  log_subsection "Creating Directories"

  local created=0
  local existed=0

  for dest in "${unique_destinations[@]}"; do
    local full_path="$DEV_ROOT/$dest"

    if [[ -d "$full_path" ]]; then
      log_verbose "Already exists: $dest"
      ((existed++))
    else
      log_info "Creating: $dest"

      if [[ "$DRY_RUN" == "true" ]]; then
        log_dry_run "Would create: $full_path"
        ((created++))
      else
        mkdir -p "$full_path" || {
          log_error "Failed to create: $full_path"
          continue
        }
        log_success "Created: $dest"
        ((created++))
      fi
    fi
  done

  # Summary
  echo ""
  log_subsection "Directory Structure Summary"
  echo -e "  Created: ${COLOR_GREEN}$created${COLOR_RESET}"
  echo -e "  Already existed: ${COLOR_YELLOW}$existed${COLOR_RESET}"
  echo ""

  # Display directory tree
  log_info "Directory structure:"
  if command_exists tree; then
    tree -L 2 -d "$DEV_ROOT" 2>/dev/null || {
      ls -la "$DEV_ROOT" 2>/dev/null || true
    }
  else
    find "$DEV_ROOT" -type d -maxdepth 2 2>/dev/null | sed "s|$DEV_ROOT|~/Development|" | sort || {
      ls -la "$DEV_ROOT" 2>/dev/null || true
    }
  fi

  echo ""
  log_success "Directory structure created dynamically from TOML"
  log_info "To add new directories, edit mac-setup.toml [repositories.destinations]"

  return 0
}

# Run module if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  module_directories
fi
