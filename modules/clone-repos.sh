#!/usr/bin/env bash

# =============================================================================
# Clone Repositories
# =============================================================================
# Clone repositories from GitHub/GitLab with intelligent destination mapping.
# Requires jq (Module 02) for JSON parsing.
# =============================================================================

# -----------------------------------------------------------------------------
# Get destination for a repository
# -----------------------------------------------------------------------------
get_repo_destination() {
  local repo_name="$1"
  local org_or_group="$2"

  # Check repo_overrides first
  local override_dest
  override_dest=$(awk -v repo="$repo_name" '
    /^\[repositories\.repo_overrides\]/ { in_section=1; next }
    in_section && /^\[/ { exit }
    in_section && $0 ~ "^"repo" *= *" {
      # Extract value between quotes (BSD awk compatible)
      sub(/^[^"]*"/, "")
      sub(/".*$/, "")
      print
      exit
    }
  ' "$TOML_CONFIG")

  if [[ -n "$override_dest" ]]; then
    echo "$override_dest"
    return 0
  fi

  # Check organization/group mapping
  local org_dest
  org_dest=$(awk -v org="$org_or_group" '
    /^\[repositories\.destinations\]/ { in_section=1; next }
    in_section && /^\[/ { exit }
    in_section && $0 ~ "^"org" *= *" {
      # Extract value between quotes (BSD awk compatible)
      sub(/^[^"]*"/, "")
      sub(/".*$/, "")
      print
      exit
    }
  ' "$TOML_CONFIG")

  if [[ -n "$org_dest" ]]; then
    echo "$org_dest"
    return 0
  fi

  # No mapping found
  return 1
}

# -----------------------------------------------------------------------------
# Interactive destination selection
# -----------------------------------------------------------------------------
select_destination_interactive() {
  local repo_name="$1"

  # Get all available destinations from TOML
  local destinations=()

  while IFS= read -r dest; do
    [[ -z "$dest" ]] && continue
    destinations+=("$dest")
  done < <(awk '
    /^\[repositories\.destinations\]/ { in_section=1; next }
    /^\[repositories\.repo_overrides\]/ { in_section=1; next }
    in_section && /^\[/ { exit }
    in_section && /=/ && /"/ {
      # Extract value between quotes (BSD awk compatible)
      line = $0
      sub(/^[^"]*"/, "", line)
      sub(/".*$/, "", line)
      if (line) print line
    }
  ' "$TOML_CONFIG" | sort -u)

  # Add custom option
  destinations+=("[Nouveau dossier...]")

  echo ""
  log_question "Aucun mapping trouvé pour '$repo_name'. Où cloner ce repo ?"
  echo ""

  # Use fzf for selection
  local selected
  selected=$(printf '%s\n' "${destinations[@]}" | fzf \
    --height=40% \
    --border \
    --header="Sélectionner la destination pour $repo_name" \
    --prompt="Destination> ")

  if [[ -z "$selected" ]]; then
    return 1
  fi

  if [[ "$selected" == "[Nouveau dossier...]" ]]; then
    read -r -p "Entrer le chemin (relatif à ~/Development/): " custom_dest
    echo "$custom_dest"
  else
    echo "$selected"
  fi

  return 0
}

# -----------------------------------------------------------------------------
# Setup job pool using FIFO semaphore (Bash 3.2 compatible)
# -----------------------------------------------------------------------------
setup_job_pool() {
  local max_jobs="$1"
  local fifo_path="/tmp/clone-limiter-$$"

  # Create named pipe
  mkfifo "$fifo_path"

  # Open file descriptor 3 for read/write on the FIFO
  exec 3<>"$fifo_path"

  # Remove FIFO file (still accessible via FD 3)
  rm "$fifo_path"

  # Initialize semaphore with N tokens
  local i
  for i in $(seq 1 "$max_jobs"); do
    echo >&3
  done
}

# -----------------------------------------------------------------------------
# Cleanup job pool
# -----------------------------------------------------------------------------
cleanup_job_pool() {
  # Close file descriptor 3 if it's open
  exec 3>&- 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# Clone a single repository (helper for parallel execution)
# -----------------------------------------------------------------------------
clone_single_repo() {
  local repo_name="$1"
  local clone_url="$2"
  local dest="$3"
  local repo_path="$DEV_ROOT/$dest/$repo_name"

  # Check if already exists
  if [[ -d "$repo_path/.git" ]]; then
    return 0
  fi

  # Ensure destination directory exists
  mkdir -p "$DEV_ROOT/$dest" 2>/dev/null

  # Capture stderr for error logging
  local stderr_output
  stderr_output=$(run_with_timeout "$GIT_CLONE_TIMEOUT" git clone "$clone_url" "$repo_path" 2>&1)
  local exit_code=$?

  if [[ $exit_code -eq 0 ]]; then
    echo "✓ $repo_name"
    if [[ "$VERBOSE_MODE" == "true" ]]; then
      log_verbose "Cloned: $repo_name"
    fi
    return 0
  else
    echo "✗ $repo_name" >&2
    # Log detailed error to log file (always logged, regardless of verbose mode)
    log_git_error "$clone_url" "$exit_code" "$stderr_output"
    if [[ "$VERBOSE_MODE" == "true" ]]; then
      # In verbose mode, also show error summary on console
      echo "  → Error: Exit code $exit_code" >&2
    fi
    return 1
  fi
}

# -----------------------------------------------------------------------------
# Clone a single GitLab repository (helper for parallel execution)
# -----------------------------------------------------------------------------
clone_single_gitlab_repo() {
  local repo_name="$1"
  local group="$2"
  local dest="$3"
  local repo_path="$DEV_ROOT/$dest/$repo_name"
  local full_path="$group/$repo_name"

  # Check if already exists
  if [[ -d "$repo_path/.git" ]]; then
    return 0
  fi

  # Ensure destination directory exists
  mkdir -p "$DEV_ROOT/$dest" 2>/dev/null

  # Capture stderr for error logging
  local stderr_output
  stderr_output=$(run_with_timeout "$GIT_CLONE_TIMEOUT" glab repo clone "$full_path" "$repo_path" 2>&1)
  local exit_code=$?

  if [[ $exit_code -eq 0 ]]; then
    echo "✓ $repo_name"
    if [[ "$VERBOSE_MODE" == "true" ]]; then
      log_verbose "Cloned: $repo_name (GitLab)"
    fi
    return 0
  else
    echo "✗ $repo_name" >&2
    # Log detailed error to log file (always logged, regardless of verbose mode)
    log_git_error "$full_path" "$exit_code" "$stderr_output"
    if [[ "$VERBOSE_MODE" == "true" ]]; then
      # In verbose mode, also show error summary on console
      echo "  → Error: Exit code $exit_code" >&2
    fi
    return 1
  fi
}

# -----------------------------------------------------------------------------
# Main module function
# -----------------------------------------------------------------------------
module_clone_repos() {
  log_section " Cloning Repositories"

  # Verify prerequisites
  require_tool jq "jq not found. Please run script-dependencies module first"

  # Check if fzf is installed
  if ! command_exists fzf; then
    log_warning "fzf not found - installing via Homebrew..."
    install_brew_package "fzf" || {
      log_error "Failed to install fzf - repository cloning will be skipped"
      return 1
    }
  fi

  # Get GitHub organizations from TOML
  local github_orgs
  github_orgs=$(parse_toml_array "$TOML_CONFIG" "repositories.github_orgs" 2>/dev/null)

  # Get GitLab groups from TOML
  local gitlab_groups
  gitlab_groups=$(parse_toml_array "$TOML_CONFIG" "repositories.gitlab_groups" 2>/dev/null)

  local total_cloned=0

  # Process GitHub organizations
  if [[ -n "$github_orgs" ]]; then
    log_subsection "GitHub Organizations"

    while IFS= read -r org; do
      [[ -z "$org" ]] && continue

      log_info "Processing GitHub organization: $org"

      if ! command_exists gh; then
        log_error "GitHub CLI (gh) not installed - skipping GitHub repos"
        log_info "Install with: brew install gh"
        break
      fi

      # Check if authenticated
      if ! gh auth status &>/dev/null; then
        if [[ "$DRY_RUN" == "true" ]]; then
          log_warning "GitHub CLI not authenticated (skipping auth in dry-run mode)"
          log_info "In real run, you would be prompted to authenticate with: gh auth login"
          break
        fi

        log_warning "GitHub CLI not authenticated"

        if ask_yes_no "Authenticate with GitHub now?" "y"; then
          log_info "Starting GitHub authentication..."
          gh auth login --hostname github.com --git-protocol https --web < /dev/tty || {
            log_error "GitHub authentication failed - skipping GitHub repositories"
            log_info "You can authenticate manually later with: gh auth login"
            break
          }
          log_success "GitHub authentication successful"
        else
          log_info "Skipping GitHub repositories (not authenticated)"
          break
        fi
      fi

      # Configure gh to use HTTPS by default
      # The 'url' field in the API response will respect this git_protocol setting
      log_verbose "Configuring gh to use HTTPS protocol"
      gh config set git_protocol https &>/dev/null || log_verbose "Could not set gh git_protocol (already set or permission issue)"

      # Fetch all repositories from organization
      # NOTE: Using 'url' field instead of 'sshUrl' to respect git_protocol setting
      # When git_protocol=https, the 'url' field returns HTTPS URLs
      log_info "Fetching repositories from $org..."

      local repos
      repos=$(gh repo list "$org" --limit 1000 --json name,url,description 2>/dev/null)

      if [[ -z "$repos" ]] || [[ "$repos" == "[]" ]]; then
        log_warning "No repositories found for organization: $org"
        continue
      fi

      # Build repo list with destinations for preview
      local -a repo_list_lines=()
      local repo_data=()

      while IFS= read -r repo_json; do
        local repo_name
        local repo_desc
        local clone_url

        repo_name=$(echo "$repo_json" | jq -r '.name')
        repo_desc=$(echo "$repo_json" | jq -r '.description // "No description"')
        clone_url=$(echo "$repo_json" | jq -r '.url')

        # Get destination for this repo
        local dest
        dest=$(get_repo_destination "$repo_name" "$org")

        if [[ -z "$dest" ]]; then
          dest="[NO MAPPING]"
        fi

        # Store repo data for later
        repo_data+=("$repo_name|$clone_url|$dest")

        # Format for fzf display (delimiter-based) - using array to preserve newlines
        repo_list_lines+=("$(printf "%s|%s|%s" "$repo_name" "$dest" "$repo_desc")")
      done < <(echo "$repos" | jq -c '.[]')

      if [[ ${#repo_list_lines[@]} -eq 0 ]]; then
        log_warning "No repositories to display for $org"
        continue
      fi

      # Interactive selection with fzf
      log_info "Select repositories to clone (Tab=select, Enter=confirm):"
      echo ""

      local selected_repos
      selected_repos=$(printf '%s\n' "${repo_list_lines[@]}" | fzf --multi \
        --height=80% \
        --border \
        --delimiter='|' \
        --with-nth=1,2 \
        --nth=1 \
        --header="Select repos to clone from $org (Tab=multi-select, Enter=confirm)" \
        --preview="echo {3}" \
        --preview-window=up:3:wrap \
        --preview-label="Description")

      if [[ -z "$selected_repos" ]]; then
        log_info "No repositories selected for $org"
        continue
      fi

      # Phase 1: Resolve destinations and prepare clone list
      local -a repos_to_clone=()

      while IFS= read -r selected_line; do
        local repo_name
        repo_name=$(echo "$selected_line" | cut -d'|' -f1)

        # Find repo data
        local repo_info
        repo_info=$(printf '%s\n' "${repo_data[@]}" | grep "^$repo_name|")

        if [[ -z "$repo_info" ]]; then
          log_error "Failed to find data for: $repo_name"
          continue
        fi

        local clone_url dest
        clone_url=$(echo "$repo_info" | cut -d'|' -f2)
        dest=$(echo "$repo_info" | cut -d'|' -f3)

        # Handle repos without mapping
        if [[ "$dest" == "[NO MAPPING]" ]]; then
          dest=$(select_destination_interactive "$repo_name")
          if [[ -z "$dest" ]]; then
            log_warning "Skipped: $repo_name (no destination selected)"
            continue
          fi
        fi

        local repo_path="$DEV_ROOT/$dest/$repo_name"

        if [[ -d "$repo_path/.git" ]]; then
          log_verbose "Repository already exists: $repo_name"
          continue
        fi

        # Add to clone list
        repos_to_clone+=("$repo_name|$clone_url|$dest")
      done <<< "$selected_repos"

      # Phase 2: Clone repositories in parallel
      if [[ ${#repos_to_clone[@]} -gt 0 ]]; then
        log_info "Cloning ${#repos_to_clone[@]} repositories (max ${CLONE_PARALLEL_JOBS} parallel jobs)..."
        echo ""

        if [[ "$DRY_RUN" == "true" ]]; then
          for repo_info in "${repos_to_clone[@]}"; do
            local repo_name dest
            repo_name=$(echo "$repo_info" | cut -d'|' -f1)
            dest=$(echo "$repo_info" | cut -d'|' -f3)
            log_dry_run "Would clone: $org/$repo_name -> $DEV_ROOT/$dest/$repo_name"
            ((total_cloned++))
          done
        else
          # Setup job pool with FIFO semaphore
          setup_job_pool "$CLONE_PARALLEL_JOBS"

          # Track clone results
          local -a clone_pids=()

          # Launch all clone jobs with semaphore control
          for repo_info in "${repos_to_clone[@]}"; do
            local repo_name clone_url dest
            repo_name=$(echo "$repo_info" | cut -d'|' -f1)
            clone_url=$(echo "$repo_info" | cut -d'|' -f2)
            dest=$(echo "$repo_info" | cut -d'|' -f3)

            # Launch clone in background with semaphore
            (
              read -u 3  # Acquire token (blocks if none available)
              clone_single_repo "$repo_name" "$clone_url" "$dest"
              local result=$?
              echo >&3  # Return token
              exit $result
            ) &
            clone_pids+=($!)
          done

          # Wait for all background jobs and count successes
          for pid in "${clone_pids[@]}"; do
            if wait "$pid"; then
              ((total_cloned++))
            fi
          done

          # Cleanup job pool
          cleanup_job_pool

          echo ""
          log_success "Cloned $total_cloned repositories from $org"
        fi
      fi

    done < <(printf '%s\n' "$github_orgs")
  fi

  # Process GitLab groups
  if [[ -n "$gitlab_groups" ]]; then
    log_subsection "GitLab Groups"

    while IFS= read -r group; do
      [[ -z "$group" ]] && continue

      log_info "Processing GitLab group: $group"

      if ! command_exists glab; then
        log_error "GitLab CLI (glab) not installed - skipping GitLab repos"
        log_info "Install with: brew install glab"
        break
      fi

      # Check if authenticated
      if ! glab auth status </dev/null &>/dev/null 2>&1; then
        if [[ "$DRY_RUN" == "true" ]]; then
          log_warning "GitLab CLI not authenticated (skipping auth in dry-run mode)"
          log_info "In real run, you would be prompted to authenticate with: glab auth login"
          break
        fi

        log_warning "GitLab CLI not authenticated"

        if ask_yes_no "Authenticate with GitLab now?" "y"; then
          log_info "Starting GitLab authentication..."
          glab auth login --hostname gitlab.com --git-protocol https < /dev/tty || {
            log_error "GitLab authentication failed - skipping GitLab repositories"
            log_info "You can authenticate manually later with: glab auth login"
            break
          }
          log_success "GitLab authentication successful"
        else
          log_info "Skipping GitLab repositories (not authenticated)"
          break
        fi
      fi

      # Configure glab to use HTTPS by default
      log_verbose "Configuring glab to use HTTPS protocol"
      glab config set -h gitlab.com git_protocol https &>/dev/null || log_verbose "Could not set glab git_protocol (already set or permission issue)"

      # Fetch repositories
      log_info "Fetching repositories from $group..."

      local repos
      repos=$(glab repo list --group "$group" --per-page 100 2>/dev/null)

      if [[ -z "$repos" ]]; then
        log_warning "No repositories found for group: $group"
        continue
      fi

      # Parse and add destinations
      local -a repo_list_lines=()
      local repo_names=()

      while IFS= read -r repo_line; do
        [[ -z "$repo_line" ]] && continue
        [[ "$repo_line" =~ ^GROUP ]] && continue  # Skip header

        local repo_name
        repo_name=$(echo "$repo_line" | awk '{print $1}')

        # Get destination
        local dest
        dest=$(get_repo_destination "$repo_name" "$group")

        if [[ -z "$dest" ]]; then
          dest="[NO MAPPING]"
        fi

        repo_names+=("$repo_name|$dest")
        repo_list_lines+=("$(printf "%s|%s" "$repo_name" "$dest")")
      done < <(echo "$repos" | tail -n +2)

      if [[ ${#repo_list_lines[@]} -eq 0 ]]; then
        continue
      fi

      # Interactive selection
      log_info "Select repositories to clone (Tab=select, Enter=confirm):"
      echo ""

      local selected_repos
      selected_repos=$(printf '%s\n' "${repo_list_lines[@]}" | fzf --multi \
        --height=80% \
        --border \
        --delimiter='|' \
        --with-nth=1,2 \
        --nth=1 \
        --header="Select repos to clone from $group (Tab=multi-select, Enter=confirm)")

      if [[ -z "$selected_repos" ]]; then
        log_info "No repositories selected for $group"
        continue
      fi

      # Phase 1: Resolve destinations and prepare clone list
      local -a repos_to_clone=()

      while IFS= read -r selected_line; do
        local repo_name
        repo_name=$(echo "$selected_line" | cut -d'|' -f1)

        # Find destination
        local repo_info dest
        repo_info=$(printf '%s\n' "${repo_names[@]}" | grep "^$repo_name|")
        dest=$(echo "$repo_info" | cut -d'|' -f2)

        # Handle repos without mapping
        if [[ "$dest" == "[NO MAPPING]" ]]; then
          dest=$(select_destination_interactive "$repo_name")
          if [[ -z "$dest" ]]; then
            log_warning "Skipped: $repo_name (no destination selected)"
            continue
          fi
        fi

        local repo_path="$DEV_ROOT/$dest/$repo_name"

        if [[ -d "$repo_path/.git" ]]; then
          log_verbose "Repository already exists: $repo_name"
          continue
        fi

        # Add to clone list
        repos_to_clone+=("$repo_name|$dest")
      done <<< "$selected_repos"

      # Phase 2: Clone repositories in parallel
      if [[ ${#repos_to_clone[@]} -gt 0 ]]; then
        log_info "Cloning ${#repos_to_clone[@]} repositories (max ${CLONE_PARALLEL_JOBS} parallel jobs)..."
        echo ""

        if [[ "$DRY_RUN" == "true" ]]; then
          for repo_info in "${repos_to_clone[@]}"; do
            local repo_name dest
            repo_name=$(echo "$repo_info" | cut -d'|' -f1)
            dest=$(echo "$repo_info" | cut -d'|' -f2)
            log_dry_run "Would clone: $group/$repo_name -> $DEV_ROOT/$dest/$repo_name"
            ((total_cloned++))
          done
        else
          # Setup job pool with FIFO semaphore
          setup_job_pool "$CLONE_PARALLEL_JOBS"

          # Track clone results
          local -a clone_pids=()

          # Launch all clone jobs with semaphore control
          for repo_info in "${repos_to_clone[@]}"; do
            local repo_name dest
            repo_name=$(echo "$repo_info" | cut -d'|' -f1)
            dest=$(echo "$repo_info" | cut -d'|' -f2)

            # Launch clone in background with semaphore
            (
              read -u 3  # Acquire token (blocks if none available)
              clone_single_gitlab_repo "$repo_name" "$group" "$dest"
              local result=$?
              echo >&3  # Return token
              exit $result
            ) &
            clone_pids+=($!)
          done

          # Wait for all background jobs and count successes
          for pid in "${clone_pids[@]}"; do
            if wait "$pid"; then
              ((total_cloned++))
            fi
          done

          # Cleanup job pool
          cleanup_job_pool

          echo ""
          log_success "Cloned $total_cloned repositories from $group"
        fi
      fi

    done < <(printf '%s\n' "$gitlab_groups")
  fi

  # Summary
  echo ""
  if [[ $total_cloned -eq 0 ]]; then
    log_info "No repositories were cloned"
  else
    log_success "Successfully cloned $total_cloned repositories"
  fi

  return 0
}

# Run module if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  module_clone_repos
fi
