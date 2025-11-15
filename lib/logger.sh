#!/usr/bin/env bash

# =============================================================================
# Logging Utilities
# =============================================================================
# Provides colored logging functions with timestamps and log levels.
# Usage:
#   log_info "Installing package..."
#   log_success "Installation complete!"
#   log_error "Failed to install package"
#   log_warning "Package already installed, skipping"
# =============================================================================

# Color codes
if [[ "$ENABLE_COLORS" == "true" ]]; then
  COLOR_RESET='\033[0m'
  COLOR_RED='\033[0;31m'
  COLOR_GREEN='\033[0;32m'
  COLOR_YELLOW='\033[0;33m'
  COLOR_BLUE='\033[0;34m'
  COLOR_MAGENTA='\033[0;35m'
  COLOR_CYAN='\033[0;36m'
  COLOR_WHITE='\033[0;37m'
  COLOR_BOLD='\033[1m'
  COLOR_DIM='\033[2m'
else
  COLOR_RESET=''
  COLOR_RED=''
  COLOR_GREEN=''
  COLOR_YELLOW=''
  COLOR_BLUE=''
  COLOR_MAGENTA=''
  COLOR_CYAN=''
  COLOR_WHITE=''
  COLOR_BOLD=''
  COLOR_DIM=''
fi

# Symbols
SYMBOL_INFO="ℹ"
SYMBOL_SUCCESS="✓"
SYMBOL_ERROR="✗"
SYMBOL_WARNING="⚠"
SYMBOL_PROGRESS="→"
SYMBOL_QUESTION="?"

# -----------------------------------------------------------------------------
# Get timestamp for log entries
# -----------------------------------------------------------------------------
get_timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

# -----------------------------------------------------------------------------
# Write to log file
# -----------------------------------------------------------------------------
write_to_log() {
  local level="$1"
  shift
  local message="$*"

  if [[ -n "$LOG_FILE" ]]; then
    echo "[$(get_timestamp)] [$level] $message" >> "$LOG_FILE"
  fi
}

# -----------------------------------------------------------------------------
# Print colored message
# -----------------------------------------------------------------------------
print_message() {
  local color="$1"
  local symbol="$2"
  local level="$3"
  shift 3
  local message="$*"

  # Print to console
  echo -e "${color}${COLOR_BOLD}[${symbol}]${COLOR_RESET} ${color}${message}${COLOR_RESET}"

  # Write to log file
  write_to_log "$level" "$message"
}

# -----------------------------------------------------------------------------
# Log functions
# -----------------------------------------------------------------------------

log_info() {
  print_message "$COLOR_BLUE" "$SYMBOL_INFO" "INFO" "$@"
}

log_success() {
  print_message "$COLOR_GREEN" "$SYMBOL_SUCCESS" "SUCCESS" "$@"
}

log_error() {
  print_message "$COLOR_RED" "$SYMBOL_ERROR" "ERROR" "$@"
}

log_warning() {
  print_message "$COLOR_YELLOW" "$SYMBOL_WARNING" "WARNING" "$@"
}

log_progress() {
  print_message "$COLOR_CYAN" "$SYMBOL_PROGRESS" "PROGRESS" "$@"
}

log_question() {
  print_message "$COLOR_MAGENTA" "$SYMBOL_QUESTION" "QUESTION" "$@" >&2
}

# -----------------------------------------------------------------------------
# Verbose logging (only shown if VERBOSE_MODE=true)
# -----------------------------------------------------------------------------
log_verbose() {
  if [[ "$VERBOSE_MODE" == "true" ]]; then
    echo -e "${COLOR_DIM}[VERBOSE] $*${COLOR_RESET}"
    write_to_log "VERBOSE" "$@"
  fi
}

# -----------------------------------------------------------------------------
# Debug logging (only shown if DEBUG_MODE=true)
# -----------------------------------------------------------------------------
log_debug() {
  if [[ "$DEBUG_MODE" == "true" ]]; then
    echo -e "${COLOR_DIM}[DEBUG] $*${COLOR_RESET}"
    write_to_log "DEBUG" "$@"
  fi
}

# -----------------------------------------------------------------------------
# Section headers
# -----------------------------------------------------------------------------
log_section() {
  local title="$1"
  echo ""
  echo -e "${COLOR_BOLD}${COLOR_CYAN}═══════════════════════════════════════════════════════════════════${COLOR_RESET}"
  echo -e "${COLOR_BOLD}${COLOR_CYAN}  $title${COLOR_RESET}"
  echo -e "${COLOR_BOLD}${COLOR_CYAN}═══════════════════════════════════════════════════════════════════${COLOR_RESET}"
  echo ""
  write_to_log "SECTION" "$title"
}

# -----------------------------------------------------------------------------
# Subsection headers
# -----------------------------------------------------------------------------
log_subsection() {
  local title="$1"
  echo ""
  echo -e "${COLOR_BOLD}${COLOR_WHITE}─── $title ───${COLOR_RESET}"
  echo ""
  write_to_log "SUBSECTION" "$title"
}

# -----------------------------------------------------------------------------
# Step counter
# -----------------------------------------------------------------------------
STEP_COUNTER=0

log_step() {
  ((STEP_COUNTER++))
  local message="$1"
  echo -e "${COLOR_BOLD}${COLOR_MAGENTA}Step $STEP_COUNTER:${COLOR_RESET} $message"
  write_to_log "STEP" "Step $STEP_COUNTER: $message"
}

reset_step_counter() {
  STEP_COUNTER=0
}

# -----------------------------------------------------------------------------
# Progress bar
# -----------------------------------------------------------------------------
show_progress() {
  local current="$1"
  local total="$2"
  local width=50
  local percentage=$((current * 100 / total))
  local filled=$((width * current / total))
  local empty=$((width - filled))

  printf "\r${COLOR_CYAN}Progress: [${COLOR_RESET}"
  printf "%${filled}s" | tr ' ' '█'
  printf "%${empty}s" | tr ' ' '░'
  printf "${COLOR_CYAN}] ${COLOR_BOLD}%3d%%${COLOR_RESET}" "$percentage"
}

clear_progress() {
  echo ""
}

# -----------------------------------------------------------------------------
# Dry run message
# -----------------------------------------------------------------------------
log_dry_run() {
  echo -e "${COLOR_YELLOW}${COLOR_BOLD}[DRY RUN]${COLOR_RESET} ${COLOR_YELLOW}$*${COLOR_RESET}"
  write_to_log "DRY-RUN" "$@"
}

# -----------------------------------------------------------------------------
# Command execution with logging
# -----------------------------------------------------------------------------
log_command() {
  local command="$*"
  log_verbose "Executing: $command"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_dry_run "Would execute: $command"
    return 0
  fi

  if [[ "$VERBOSE_MODE" == "true" ]]; then
    eval "$command"
  else
    eval "$command" >> "$LOG_FILE" 2>&1
  fi
}

# -----------------------------------------------------------------------------
# Git Error Logging with Pattern Detection and Suggestions
# -----------------------------------------------------------------------------
log_git_error() {
  local repo_url="$1"
  local exit_code="$2"
  local stderr_content="$3"
  local expected_path="$4"

  # Log basic error info
  log_error "Failed to clone repository: $repo_url"

  # Check if destination path verification failed
  if [[ -n "$expected_path" ]] && [[ ! -d "$expected_path/.git" ]]; then
    log_error "Repository not found at expected location: $expected_path"
  fi

  # Decode exit code
  local exit_description
  case "$exit_code" in
    0)   exit_description="Success" ;;
    1)   exit_description="Generic error" ;;
    124) exit_description="Timeout" ;;
    128) exit_description="Fatal error" ;;
    255) exit_description="SSH connection failure" ;;
    *)   exit_description="Unknown error" ;;
  esac

  log_error "Git exit code: $exit_code ($exit_description)"

  # Log stderr if available
  if [[ -n "$stderr_content" ]]; then
    log_error "Git stderr:"
    while IFS= read -r line; do
      log_error "  $line"
    done <<< "$stderr_content"
  fi

  # Pattern detection and suggestions
  local detected_issue=""
  local suggestion=""

  # Timeout detection
  if [[ "$exit_code" == "124" ]]; then
    detected_issue="Git clone timeout"
    suggestion="Check network connection or increase GIT_CLONE_TIMEOUT in lib/config.sh (current: ${GIT_CLONE_TIMEOUT}s)"

  # Auth failures
  elif [[ "$stderr_content" =~ "Permission denied"|"Could not read from remote"|"publickey" ]]; then
    detected_issue="SSH authentication failure"
    if [[ "$repo_url" =~ ^git@ ]]; then
      suggestion="Run 'ssh-add -l' to check SSH keys, or 'gh auth login' for GitHub CLI auth"
    else
      suggestion="Run 'gh auth login' (GitHub) or 'glab auth login' (GitLab) for authentication"
    fi

  # Repository not found
  elif [[ "$stderr_content" =~ "not found"|"Repository not found" ]]; then
    detected_issue="Repository not found"
    suggestion="Verify repository URL in mac-setup.toml and ensure repository exists and is accessible"

  # Branch not found
  elif [[ "$stderr_content" =~ "branch".*"not found"|"Remote branch".*"not found" ]]; then
    detected_issue="Branch not found"
    suggestion="Check branch name in mac-setup.toml or DOTFILES_BRANCH variable"

  # Network issues
  elif [[ "$stderr_content" =~ "Failed to connect"|"Connection timed out"|"Could not resolve hostname" ]]; then
    detected_issue="Network connectivity issue"
    suggestion="Check internet connection and DNS resolution"
  fi

  # Log detected issue and suggestion
  if [[ -n "$detected_issue" ]]; then
    log_error ""
    log_error "Detected issue: $detected_issue"
    log_error "Suggestion: $suggestion"
  fi
}

# -----------------------------------------------------------------------------
# Error handling
# -----------------------------------------------------------------------------
log_error_exit() {
  log_error "$@"
  log_error "Exiting due to error. Check log file: $LOG_FILE"
  exit 1
}

# -----------------------------------------------------------------------------
# Initialize logging
# -----------------------------------------------------------------------------
init_logging() {
  # Create log file directory if it doesn't exist
  local log_dir
  log_dir="$(dirname "$LOG_FILE")"
  mkdir -p "$log_dir"

  # Initialize log file
  echo "═══════════════════════════════════════════════════════════════════" > "$LOG_FILE"
  echo "$SCRIPT_NAME v$SCRIPT_VERSION" >> "$LOG_FILE"
  echo "Log started: $(get_timestamp)" >> "$LOG_FILE"
  echo "═══════════════════════════════════════════════════════════════════" >> "$LOG_FILE"
  echo "" >> "$LOG_FILE"

  log_info "Logging initialized. Log file: $LOG_FILE"
}

# -----------------------------------------------------------------------------
# Finalize logging
# -----------------------------------------------------------------------------
finalize_logging() {
  echo "" >> "$LOG_FILE"
  echo "═══════════════════════════════════════════════════════════════════" >> "$LOG_FILE"
  echo "Log ended: $(get_timestamp)" >> "$LOG_FILE"
  echo "═══════════════════════════════════════════════════════════════════" >> "$LOG_FILE"
}

# -----------------------------------------------------------------------------
# Print banner
# -----------------------------------------------------------------------------
print_banner() {
  echo ""
  echo -e "${COLOR_BOLD}${COLOR_CYAN}"
  cat << 'EOF'
╔═══════════════════════════════════════════════════════════════════╗
║                                                                   ║
║               Mac Setup Automation Script                        ║
║                                                                   ║
║   Automated installation and configuration for macOS             ║
║                                                                   ║
╚═══════════════════════════════════════════════════════════════════╝
EOF
  echo -e "${COLOR_RESET}"
  echo -e "${COLOR_DIM}Version: $SCRIPT_VERSION${COLOR_RESET}"
  echo -e "${COLOR_DIM}Author: $SCRIPT_AUTHOR${COLOR_RESET}"
  echo ""
}

# -----------------------------------------------------------------------------
# Summary report
# -----------------------------------------------------------------------------
print_summary() {
  local total_steps="$1"
  local successful_steps="$2"
  local failed_steps="$3"

  log_section "Installation Summary"

  echo -e "${COLOR_BOLD}Total steps:${COLOR_RESET} $total_steps"
  echo -e "${COLOR_GREEN}${COLOR_BOLD}Successful:${COLOR_RESET} ${COLOR_GREEN}$successful_steps${COLOR_RESET}"

  if [[ $failed_steps -gt 0 ]]; then
    echo -e "${COLOR_RED}${COLOR_BOLD}Failed:${COLOR_RESET} ${COLOR_RED}$failed_steps${COLOR_RESET}"
  fi

  echo ""
  echo -e "${COLOR_DIM}Full log available at: $LOG_FILE${COLOR_RESET}"
  echo ""
}
