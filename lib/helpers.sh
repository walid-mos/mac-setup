#!/usr/bin/env bash

# =============================================================================
# Helper Functions
# =============================================================================
# Common utility functions used across all modules.
# =============================================================================

# -----------------------------------------------------------------------------
# Check if command exists
# -----------------------------------------------------------------------------
command_exists() {
  command -v "$1" &> /dev/null
}

# -----------------------------------------------------------------------------
# Check if running on macOS
# -----------------------------------------------------------------------------
is_macos() {
  [[ "$(uname -s)" == "Darwin" ]]
}

# -----------------------------------------------------------------------------
# Get macOS version
# -----------------------------------------------------------------------------
get_macos_version() {
  sw_vers -productVersion
}

# -----------------------------------------------------------------------------
# Check minimum macOS version
# -----------------------------------------------------------------------------
check_macos_version() {
  local required_version="$1"
  local current_version
  current_version="$(get_macos_version)"

  if [[ "$(printf '%s\n' "$required_version" "$current_version" | sort -V | head -n1)" != "$required_version" ]]; then
    return 1
  fi
  return 0
}

# -----------------------------------------------------------------------------
# Check if running with sudo
# -----------------------------------------------------------------------------
is_sudo() {
  [[ $EUID -eq 0 ]]
}

# -----------------------------------------------------------------------------
# Check internet connectivity
# -----------------------------------------------------------------------------
check_internet() {
  if ping -c 1 -W 5 google.com &> /dev/null; then
    return 0
  fi
  return 1
}

# -----------------------------------------------------------------------------
# Get available disk space in GB
# -----------------------------------------------------------------------------
get_available_space() {
  df -g / | awk 'NR==2 {print $4}'
}

# -----------------------------------------------------------------------------
# Check if directory exists and is not empty
# -----------------------------------------------------------------------------
dir_exists_and_not_empty() {
  local dir="$1"
  [[ -d "$dir" ]] && [[ -n "$(ls -A "$dir" 2>/dev/null)" ]]
}

# -----------------------------------------------------------------------------
# Ask yes/no question
# -----------------------------------------------------------------------------
ask_yes_no() {
  local question="$1"
  local default="${2:-n}"  # Default to 'no'

  local prompt
  if [[ "$default" == "y" ]]; then
    prompt="[Y/n]"
  else
    prompt="[y/N]"
  fi

  while true; do
    read -r -p "$question $prompt: " response
    response="${response:-$default}"
    # Convert to lowercase (compatible with older bash)
    response_lower=$(echo "$response" | tr '[:upper:]' '[:lower:]')
    case "$response_lower" in
      y|yes) return 0 ;;
      n|no) return 1 ;;
      *) echo "Please answer yes or no." ;;
    esac
  done
}

# -----------------------------------------------------------------------------
# Wait for user confirmation
# -----------------------------------------------------------------------------
wait_for_user() {
  local message="${1:-Press Enter to continue...}"
  read -r -p "$message"
}

# -----------------------------------------------------------------------------
# Create directory if it doesn't exist
# -----------------------------------------------------------------------------
ensure_directory() {
  local dir="$1"

  if [[ ! -d "$dir" ]]; then
    log_verbose "Creating directory: $dir"
    mkdir -p "$dir" || {
      log_error "Failed to create directory: $dir"
      return 1
    }
  fi
  return 0
}

# -----------------------------------------------------------------------------
# Backup file or directory
# -----------------------------------------------------------------------------
backup_path() {
  local source="$1"
  local backup_name
  backup_name="$(basename "$source")"
  local backup_path="$BACKUP_DIR/$backup_name"

  if [[ ! -e "$source" ]]; then
    log_verbose "Nothing to backup: $source does not exist"
    return 0
  fi

  ensure_directory "$BACKUP_DIR"

  log_info "Backing up $source to $backup_path"
  cp -R "$source" "$backup_path" || {
    log_error "Failed to backup $source"
    return 1
  }

  log_success "Backed up: $source"
  return 0
}

# -----------------------------------------------------------------------------
# Download file with curl
# -----------------------------------------------------------------------------
download_file() {
  local url="$1"
  local output="$2"
  local timeout="${3:-$CURL_TIMEOUT}"

  log_verbose "Downloading: $url"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_dry_run "Would download: $url -> $output"
    return 0
  fi

  curl -fsSL --max-time "$timeout" "$url" -o "$output" || {
    log_error "Failed to download: $url"
    return 1
  }

  return 0
}

# -----------------------------------------------------------------------------
# Execute curl script
# -----------------------------------------------------------------------------
execute_curl_script() {
  local url="$1"
  local timeout="${2:-$CURL_TIMEOUT}"

  log_verbose "Executing script from: $url"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_dry_run "Would execute script from: $url"
    return 0
  fi

  bash -c "$(curl -fsSL --max-time "$timeout" "$url")" || {
    log_error "Failed to execute script from: $url"
    return 1
  }

  return 0
}

# -----------------------------------------------------------------------------
# Clone git repository
# -----------------------------------------------------------------------------
clone_repo() {
  local repo_url="$1"
  local destination="$2"
  local branch="${3:-main}"

  if [[ -d "$destination/.git" ]]; then
    log_warning "Repository already exists: $destination"
    return 0
  fi

  log_info "Cloning repository: $repo_url"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_dry_run "Would clone: $repo_url -> $destination"
    return 0
  fi

  timeout "$GIT_CLONE_TIMEOUT" git clone --branch "$branch" "$repo_url" "$destination" || {
    log_error "Failed to clone repository: $repo_url"
    return 1
  }

  log_success "Cloned: $repo_url"
  return 0
}

# -----------------------------------------------------------------------------
# Check if brew package is installed
# -----------------------------------------------------------------------------
is_brew_package_installed() {
  local package="$1"
  brew list "$package" &> /dev/null
}

# -----------------------------------------------------------------------------
# Check if brew cask is installed
# -----------------------------------------------------------------------------
is_brew_cask_installed() {
  local cask="$1"
  brew list --cask "$cask" &> /dev/null
}

# -----------------------------------------------------------------------------
# Install brew package
# -----------------------------------------------------------------------------
install_brew_package() {
  local package="$1"

  if is_brew_package_installed "$package"; then
    log_verbose "Already installed: $package"
    return 0
  fi

  log_info "Installing: $package"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_dry_run "Would install: $package"
    return 0
  fi

  timeout "$BREW_INSTALL_TIMEOUT" brew install "$package" || {
    log_error "Failed to install: $package"
    return 1
  }

  log_success "Installed: $package"
  return 0
}

# -----------------------------------------------------------------------------
# Install brew cask
# -----------------------------------------------------------------------------
install_brew_cask() {
  local cask="$1"

  if is_brew_cask_installed "$cask"; then
    log_verbose "Already installed: $cask"
    return 0
  fi

  log_info "Installing cask: $cask"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_dry_run "Would install cask: $cask"
    return 0
  fi

  timeout "$BREW_INSTALL_TIMEOUT" brew install --cask "$cask" || {
    log_error "Failed to install cask: $cask"
    return 1
  }

  log_success "Installed cask: $cask"
  return 0
}

# -----------------------------------------------------------------------------
# Set macOS default
# -----------------------------------------------------------------------------
set_macos_default() {
  local domain="$1"
  local key="$2"
  local type="$3"
  local value="$4"

  log_verbose "Setting default: $domain $key -$type $value"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_dry_run "Would set: defaults write $domain \"$key\" -$type \"$value\""
    return 0
  fi

  defaults write "$domain" "$key" -"$type" "$value" || {
    log_error "Failed to set default: $domain $key"
    return 1
  }

  return 0
}

# -----------------------------------------------------------------------------
# Restart macOS service
# -----------------------------------------------------------------------------
restart_service() {
  local service="$1"

  log_info "Restarting: $service"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_dry_run "Would restart: $service"
    return 0
  fi

  killall "$service" &> /dev/null || true
  return 0
}

# -----------------------------------------------------------------------------
# Add line to file if not present
# -----------------------------------------------------------------------------
add_line_to_file() {
  local line="$1"
  local file="$2"

  if grep -Fxq "$line" "$file" 2>/dev/null; then
    log_verbose "Line already exists in $file"
    return 0
  fi

  log_verbose "Adding line to $file"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_dry_run "Would add line to $file: $line"
    return 0
  fi

  echo "$line" >> "$file" || {
    log_error "Failed to add line to $file"
    return 1
  }

  return 0
}

# -----------------------------------------------------------------------------
# Source file if exists
# -----------------------------------------------------------------------------
source_if_exists() {
  local file="$1"

  if [[ -f "$file" ]]; then
    # shellcheck disable=SC1090
    source "$file" || {
      log_error "Failed to source: $file"
      return 1
    }
  fi

  return 0
}

# -----------------------------------------------------------------------------
# Get array from TOML
# -----------------------------------------------------------------------------
get_toml_array() {
  local key="$1"
  parse_toml_array "$TOML_CONFIG" "$key"
}

# -----------------------------------------------------------------------------
# Get value from TOML
# -----------------------------------------------------------------------------
get_toml_value() {
  local key="$1"
  parse_toml_value "$TOML_CONFIG" "$key"
}

# -----------------------------------------------------------------------------
# Parallel execution helper
# -----------------------------------------------------------------------------
run_parallel() {
  local max_jobs="$1"
  shift
  local commands=("$@")

  local pids=()
  local job_count=0

  for cmd in "${commands[@]}"; do
    eval "$cmd" &
    pids+=($!)
    ((job_count++))

    if [[ $job_count -ge $max_jobs ]]; then
      wait "${pids[@]}"
      pids=()
      job_count=0
    fi
  done

  # Wait for remaining jobs
  if [[ ${#pids[@]} -gt 0 ]]; then
    wait "${pids[@]}"
  fi
}

# -----------------------------------------------------------------------------
# Trim whitespace
# -----------------------------------------------------------------------------
trim() {
  local var="$*"
  var="${var#"${var%%[![:space:]]*}"}"
  var="${var%"${var##*[![:space:]]}"}"
  echo "$var"
}

# -----------------------------------------------------------------------------
# Check if variable is set
# -----------------------------------------------------------------------------
is_set() {
  local var_name="$1"
  [[ -n "${!var_name}" ]]
}

# -----------------------------------------------------------------------------
# Require variable to be set
# -----------------------------------------------------------------------------
require_var() {
  local var_name="$1"
  local error_message="${2:-Variable $var_name is required but not set}"

  if ! is_set "$var_name"; then
    log_error_exit "$error_message"
  fi
}
