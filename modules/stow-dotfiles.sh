#!/usr/bin/env bash

# =============================================================================
# Stow Dotfiles
# =============================================================================
# Clone dotfiles repository and install all packages dynamically with stow.
# Requires Git (prerequisites module) and Stow (brew-packages module) to be available.
# =============================================================================

module_stow_dotfiles() {
  log_section "Stow Dotfiles: Setting Up Configuration Files"

  # Save current directory to restore later
  local original_dir
  original_dir="$(pwd)"

  # Verify prerequisites
  require_tool git "Git not found. Please run prerequisites module first"
  require_tool stow "GNU Stow not found. Please run brew-packages module first or install stow manually"

  log_success "Prerequisites verified (git, stow)"

  # Step 2: Handle existing dotfiles directory
  if [[ -d "$DOTFILES_DIR" ]]; then
    log_warning "Dotfiles directory already exists: $DOTFILES_DIR"

    if dir_exists_and_not_empty "$DOTFILES_DIR/.git"; then
      log_info "Git repository detected in dotfiles directory"

      if ask_yes_no "Update existing repository instead of re-cloning?" "y"; then
        log_info "Updating existing dotfiles repository..."
        (
          cd "$DOTFILES_DIR" || exit 1
          git fetch origin || log_warning "Failed to fetch from origin"
          git pull origin "$DOTFILES_BRANCH" || log_warning "Failed to pull from origin"
        )
        log_success "Dotfiles repository updated"
      fi
    else
      if [[ "$BACKUP_EXISTING_CONFIGS" == "true" ]]; then
        log_info "Backing up existing dotfiles directory..."
        backup_path "$DOTFILES_DIR" || {
          log_error_exit "Failed to backup existing dotfiles"
        }

        log_info "Removing existing dotfiles directory..."
        rm -rf "$DOTFILES_DIR" || {
          log_error_exit "Failed to remove existing dotfiles directory"
        }
      else
        log_error_exit "Dotfiles directory exists and BACKUP_EXISTING_CONFIGS=false"
      fi
    fi
  fi

  # Step 3: Clone dotfiles repository if needed
  if [[ ! -d "$DOTFILES_DIR/.git" ]]; then
    log_subsection "Cloning Dotfiles Repository"

    log_info "Repository: $DOTFILES_REPO"
    log_info "Destination: $DOTFILES_DIR"
    log_info "Branch: $DOTFILES_BRANCH"

    clone_repo "$DOTFILES_REPO" "$DOTFILES_DIR" "$DOTFILES_BRANCH" || {
      log_error_exit "Failed to clone dotfiles repository"
    }

    log_success "Dotfiles repository cloned successfully"
  fi

  # Step 4: Dynamically detect all stow packages
  log_subsection "Detecting Stow Packages"

  local packages=()
  local excluded_pattern

  # Build grep exclusion pattern from STOW_EXCLUDE_DIRS
  excluded_pattern="^\\.\\|^README\\|^LICENSE\\|^CLAUDE"
  for exclude_dir in "${STOW_EXCLUDE_DIRS[@]}"; do
    excluded_pattern="${excluded_pattern}\\|^${exclude_dir}\$"
  done

  # Find all directories in dotfiles repo (excluding hidden and excluded dirs)
  while IFS= read -r dir; do
    [[ -z "$dir" ]] && continue
    packages+=("$dir")
  done < <(
    cd "$DOTFILES_DIR" || exit 1
    find . -maxdepth 1 -type d -not -name ".*" -exec basename {} \; | grep -v "$excluded_pattern" | sort
  )

  if [[ ${#packages[@]} -eq 0 ]]; then
    log_warning "No stow packages detected in $DOTFILES_DIR"
    cd "$original_dir" || log_warning "Failed to restore working directory to: $original_dir"
    return 0
  fi

  log_success "Detected ${#packages[@]} stow packages:"
  for pkg in "${packages[@]}"; do
    log_info "  - $pkg"
  done
  echo ""

  # Step 5: Stow each package
  log_subsection "Installing Dotfiles with Stow"

  local successful=0
  local failed=0
  local skipped=0

  cd "$DOTFILES_DIR" || {
    log_error_exit "Failed to change to dotfiles directory"
  }

  for package in "${packages[@]}"; do
    log_progress "Stowing: $package"

    if [[ "$DRY_RUN" == "true" ]]; then
      log_dry_run "Would stow: $package"
      ((successful++))
      continue
    fi

    # Force mode: unstow first, then stow (ultimate priority to STOW_DIRECTORY)
    if [[ "$STOW_FORCE" == "true" ]]; then
      log_verbose "Force mode: Removing existing symlinks for $package"
      stow -D "$package" 2>/dev/null || true  # Ignore errors if not stowed

      # Try to stow, capture output to detect conflicts
      local stow_output
      if [[ "$STOW_VERBOSE" == "true" ]]; then
        stow_output=$(stow -v "$package" 2>&1)
      else
        stow_output=$(stow "$package" 2>&1)
      fi
      local stow_status=$?

      # If stow failed, check if it's due to conflicts
      if [[ $stow_status -ne 0 ]]; then
        if echo "$stow_output" | grep -qE "existing target|not owned by stow|cannot stow"; then
          log_verbose "Conflicts detected, removing existing files/symlinks"

          # Extract conflicting paths from stow output (paths appear after "stow: ")
          local conflicting_paths
          conflicting_paths=$(echo "$stow_output" | \
            sed -n 's/.*stow: //p' | \
            sort -u)

          # Remove each conflicting file/symlink/directory
          while IFS= read -r path; do
            [[ -z "$path" ]] && continue
            local full_path="$HOME/$path"

            if [[ -L "$full_path" ]]; then
              log_verbose "Removing symlink: $path"
              rm -f "$full_path"
            elif [[ -f "$full_path" ]]; then
              log_verbose "Removing file: $path"
              rm -f "$full_path"
            elif [[ -d "$full_path" ]]; then
              log_verbose "Removing directory: $path"
              rm -rf "$full_path"
            fi
          done <<< "$conflicting_paths"

          # Retry stow after removing conflicts
          if [[ "$STOW_VERBOSE" == "true" ]]; then
            stow -v "$package" || {
              log_error "Failed to stow after cleanup: $package"
              ((failed++))
              continue
            }
          else
            stow "$package" 2>&1 | tee -a "$LOG_FILE" || {
              log_error "Failed to stow after cleanup: $package"
              ((failed++))
              continue
            }
          fi
        else
          # Non-conflict error
          log_error "Stow failed for: $package"
          echo "$stow_output" | tee -a "$LOG_FILE"
          ((failed++))
          continue
        fi
      fi

      log_success "Stowed (force): $package"
      ((successful++))
      continue
    fi

    # Non-force mode: legacy conflict detection and backup logic
    local stow_output
    stow_output=$(stow -n "$package" 2>&1)
    local stow_status=$?

    if [[ $stow_status -ne 0 ]]; then
      if echo "$stow_output" | grep -qE "existing target|cannot stow"; then
        log_warning "Conflicts detected for package: $package"

        if [[ "$STOW_ADOPT" == "true" ]]; then
          log_info "Adopting existing files for: $package"
          stow --adopt "$package" 2>&1 | tee -a "$LOG_FILE" || {
            log_error "Failed to adopt: $package"
            ((failed++))
            continue
          }
          log_success "Adopted: $package"
          ((successful++))
        elif [[ "$BACKUP_EXISTING_CONFIGS" == "true" ]]; then
          log_info "Backing up conflicting files for: $package"

          # Extract conflicting files from stow output (improved regex)
          local conflicting_files
          conflicting_files=$(echo "$stow_output" | \
            grep -oE '(existing target [^ ]+|over existing target [^ ]+)' | \
            awk '{print $NF}' | \
            sed 's/\.$//')

          if [[ -n "$conflicting_files" ]]; then
            log_info "Conflicting files detected:"
            echo "$conflicting_files" | while IFS= read -r file; do
              [[ -z "$file" ]] && continue
              log_info "  - $file"
            done

            while IFS= read -r file; do
              [[ -z "$file" ]] && continue
              local full_path="$HOME/$file"
              if [[ -e "$full_path" ]]; then
                backup_path "$full_path"
                rm -rf "$full_path"  # Use -rf to handle both files and directories
              fi
            done <<< "$conflicting_files"
          fi

          # Retry stow after backup
          if [[ "$STOW_VERBOSE" == "true" ]]; then
            stow -v "$package" || {
              log_error "Failed to stow: $package"
              ((failed++))
              continue
            }
          else
            stow "$package" 2>&1 | tee -a "$LOG_FILE" || {
              log_error "Failed to stow: $package"
              ((failed++))
              continue
            }
          fi

          log_success "Stowed (after backup): $package"
          ((successful++))
        else
          log_error "Conflicts exist and backup/adopt disabled for: $package"
          log_info "To resolve, set STOW_FORCE=true, STOW_ADOPT=true, or BACKUP_EXISTING_CONFIGS=true"
          ((failed++))
        fi
      else
        log_error "Stow failed for: $package"
        log_error "Stow output:"
        echo "$stow_output" | while IFS= read -r line; do
          log_error "  $line"
        done
        ((failed++))
      fi
    else
      # No conflicts, stow normally
      if [[ "$STOW_VERBOSE" == "true" ]]; then
        stow -v "$package" || {
          log_error "Failed to stow: $package"
          ((failed++))
          continue
        }
      else
        stow "$package" 2>&1 | tee -a "$LOG_FILE" || {
          log_error "Failed to stow: $package"
          ((failed++))
          continue
        }
      fi

      log_success "Stowed: $package"
      ((successful++))
    fi
  done

  echo ""
  log_subsection "Stow Summary"
  echo -e "${COLOR_GREEN}Successful: $successful${COLOR_RESET}"
  if [[ $failed -gt 0 ]]; then
    echo -e "${COLOR_RED}Failed: $failed${COLOR_RESET}"
  fi
  if [[ $skipped -gt 0 ]]; then
    echo -e "${COLOR_YELLOW}Skipped: $skipped${COLOR_RESET}"
  fi
  echo ""

  if [[ $failed -gt 0 ]]; then
    log_warning "Some packages failed to install. Check log file: $LOG_FILE"
  else
    log_success "All dotfiles packages installed successfully with stow"
  fi

  # Restore original directory before returning
  cd "$original_dir" || log_warning "Failed to restore working directory to: $original_dir"

  return 0
}

# Run module if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  module_stow_dotfiles
fi
