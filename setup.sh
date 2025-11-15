#!/usr/bin/env bash

# =============================================================================
# Mac Setup Automation Script
# =============================================================================
# Main orchestrator script for automated macOS setup.
# =============================================================================

set -eo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source libraries
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/config.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/logger.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/helpers.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/validators.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/toml-parser.sh"

# Source all modules
# shellcheck disable=SC1091
source "$SCRIPT_DIR/modules/prerequisites.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/modules/homebrew.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/modules/script-dependencies.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/modules/curl-tools.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/modules/brew-packages.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/modules/brew-casks.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/modules/stow-dotfiles.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/modules/git-config.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/modules/directories.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/modules/clone-repos.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/modules/macos-defaults.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/modules/automatisations.sh"

# =============================================================================
# Parse Command Line Arguments
# =============================================================================

show_usage() {
  cat << EOF
Usage: $0 [OPTIONS]

Mac Setup Automation Script - Automated installation and configuration for macOS

OPTIONS:
  -h, --help              Show this help message
  -d, --dry-run          Preview what would be done without making changes
  -v, --verbose          Enable verbose output
  -m, --module MODULE    Run only specific module (e.g., 01, 03, 05)
  -s, --skip MODULE      Skip specific module (can be used multiple times)
  --skip-macos           Skip macOS defaults configuration
  --skip-repos           Skip repository cloning (same as --skip clone-repos)
  --no-backup            Don't backup existing configurations
  --adopt                Adopt existing configs with stow instead of backing up
  --no-force-stow        Disable force mode (keep existing backup/adopt logic)

EXAMPLES:
  $0                              Run full installation
  $0 --dry-run                    Preview installation without making changes
  $0 --module stow-dotfiles       Run only stow dotfiles module
  $0 --skip clone-repos           Run all modules except clone repos
  $0 --verbose                    Run with detailed logging

MODULES (in execution order):
  prerequisites       - Xcode CLI tools (provides git)
  homebrew            - Homebrew installation
  script-dependencies - Script tools (dasel, jq)
  curl-tools          - Curl-based tools (Claude CLI, fnm, pnpm)
  brew-packages       - Homebrew packages (stow, neovim, etc.)
  brew-casks          - Homebrew applications
  stow-dotfiles       - Stow dotfiles (dynamic package detection)
  git-config          - Git configuration
  directories         - Directory structure
  clone-repos         - Clone repositories (interactive fzf)
  macos-defaults      - macOS system defaults

CONFIGURATION:
  Edit mac-setup.toml to customize packages, apps, and settings
  Edit lib/config.sh to customize script behavior

LOG FILE:
  $LOG_FILE

For more information, see README.md
EOF
}

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -h|--help)
        show_usage
        exit 0
        ;;
      -d|--dry-run)
        DRY_RUN=true
        shift
        ;;
      -v|--verbose)
        VERBOSE_MODE=true
        shift
        ;;
      -m|--module)
        RUN_ONLY_MODULE="$2"
        shift 2
        ;;
      -s|--skip)
        SKIP_MODULES+=("$2")
        shift 2
        ;;
      --skip-macos)
        APPLY_MACOS_DEFAULTS=false
        shift
        ;;
      --skip-repos)
        SKIP_MODULES+=("clone-repos")
        shift
        ;;
      --no-backup)
        BACKUP_EXISTING_CONFIGS=false
        shift
        ;;
      --adopt)
        STOW_ADOPT=true
        shift
        ;;
      --no-force-stow)
        STOW_FORCE=false
        shift
        ;;
      *)
        echo "Unknown option: $1"
        show_usage
        exit 1
        ;;
    esac
  done
}

# =============================================================================
# Module Execution
# =============================================================================

should_run_module() {
  local module_num="$1"

  # Check if we should only run a specific module
  if [[ -n "$RUN_ONLY_MODULE" ]] && [[ "$module_num" != "$RUN_ONLY_MODULE" ]]; then
    return 1
  fi

  # Check if module is in skip list
  if [[ ${#SKIP_MODULES[@]} -gt 0 ]]; then
    for skip in "${SKIP_MODULES[@]}"; do
      if [[ "$module_num" == "$skip" ]]; then
        return 1
      fi
    done
  fi

  return 0
}

run_module() {
  local module_num="$1"
  local module_name="$2"
  local module_func="$3"

  if ! should_run_module "$module_num"; then
    log_verbose "Skipping module $module_num: $module_name"
    return 0
  fi

  log_step "$module_name"

  if "$module_func"; then
    return 0
  else
    log_error "Module $module_num failed: $module_name"
    return 1
  fi
}

# =============================================================================
# Post-Setup Manual Steps
# =============================================================================

show_post_setup_manual_steps() {
  log_section "Manual Steps Required"
  log_info ""
  log_info "The following configuration requires manual action in System Settings:"
  log_info ""
  log_subsection "Disable Gatekeeper (Allow Apps from Anywhere)"
  log_step "1. Open: System Settings > Privacy & Security"
  log_step "2. Scroll down to the 'Security' section"
  log_step "3. Find 'Allow applications from:' and select 'Anywhere'"
  log_step "4. Click 'Allow' to confirm the change"
  log_info ""
  log_info "Note: You may need to navigate away from Privacy & Security"
  log_info "      and back to see the 'Anywhere' option appear."
  log_info ""
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
  # Parse arguments
  parse_arguments "$@"

  # Initialize logging
  init_logging

  # Print banner
  print_banner

  # Run validations
  run_all_validations

  # Display validation summary and get user confirmation
  display_validation_summary

  # Track module execution
  local total_modules=11
  local successful_modules=0
  local failed_modules=0

  # Start timer
  local start_time
  start_time=$(date +%s)

  # Execute modules in the correct order
  # Prerequisites (Xcode CLI - provides git)
  if run_module "prerequisites" "Prerequisites" "module_prerequisites"; then
    ((successful_modules++))
  else
    ((failed_modules++))
  fi

  # Homebrew (provides brew)
  if run_module "homebrew" "Homebrew" "module_homebrew"; then
    ((successful_modules++))
  else
    ((failed_modules++))
  fi

  # Script dependencies (dasel, jq - requires brew)
  if run_module "script-dependencies" "Script Dependencies" "module_script_dependencies"; then
    ((successful_modules++))
  else
    ((failed_modules++))
    log_error_exit "Failed to install script dependencies. Cannot continue."
  fi

  # Initialize TOML parser (after dasel is installed)
  init_toml_parser

  # Curl Tools (Claude CLI, fnm, pnpm)
  if run_module "curl-tools" "Curl Tools" "module_curl_tools"; then
    ((successful_modules++))
  else
    ((failed_modules++))
  fi

  # Brew Packages (stow, neovim, tmux, etc.)
  if run_module "brew-packages" "Brew Packages" "module_brew_packages"; then
    ((successful_modules++))
  else
    ((failed_modules++))
  fi

  # Brew Casks (applications)
  if run_module "brew-casks" "Brew Casks" "module_brew_casks"; then
    ((successful_modules++))
  else
    ((failed_modules++))
  fi

  # Stow Dotfiles (requires git and stow)
  if run_module "stow-dotfiles" "Stow Dotfiles" "module_stow_dotfiles"; then
    ((successful_modules++))
  else
    ((failed_modules++))
  fi

  # Git Configuration
  if run_module "git-config" "Git Configuration" "module_git_config"; then
    ((successful_modules++))
  else
    ((failed_modules++))
  fi

  # Directory Structure
  if run_module "directories" "Directory Structure" "module_directories"; then
    ((successful_modules++))
  else
    ((failed_modules++))
  fi

  # Clone Repositories (requires jq)
  if run_module "clone-repos" "Clone Repositories" "module_clone_repos"; then
    ((successful_modules++))
  else
    ((failed_modules++))
  fi

  # macOS Defaults
  if run_module "macos-defaults" "macOS Defaults" "module_macos_defaults"; then
    ((successful_modules++))
  else
    ((failed_modules++))
  fi

  # Custom Automatisations (runs after all main modules)
  if run_module "automatisations" "Automatisations" "module_automatisations"; then
    ((successful_modules++))
  else
    ((failed_modules++))
  fi

  # End timer
  local end_time
  end_time=$(date +%s)
  local duration=$((end_time - start_time))
  local minutes=$((duration / 60))
  local seconds=$((duration % 60))

  # Print summary
  print_summary "$total_modules" "$successful_modules" "$failed_modules"

  log_info "Total execution time: ${minutes}m ${seconds}s"

  # Show manual steps if Gatekeeper was configured
  if [[ "$SYSTEM_DISABLE_GATEKEEPER" == "true" ]]; then
    echo ""
    show_post_setup_manual_steps
  fi

  # Finalize logging
  finalize_logging

  # Final message
  echo ""
  if [[ $failed_modules -eq 0 ]]; then
    log_success "Mac setup completed successfully!"
    echo ""
    log_info "Next steps:"
    echo "  1. Restart your terminal or run: source ~/.zshrc"
    echo "  2. Verify installations: brew list, git --version, etc."
    echo "  3. Review log file: $LOG_FILE"
    echo ""
  else
    log_error "Mac setup completed with $failed_modules failed module(s)"
    log_info "Check log file for details: $LOG_FILE"
    exit 1
  fi
}

# Run main function
main "$@"
