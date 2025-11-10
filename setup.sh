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
source "$SCRIPT_DIR/modules/00-prerequisites.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/modules/01-homebrew.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/modules/02-script-dependencies.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/modules/04-stow-dotfiles.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/modules/05-curl-tools.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/modules/06-brew-packages.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/modules/07-brew-casks.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/modules/08-git-config.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/modules/09-directories.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/modules/10-clone-repos.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/modules/11-oh-my-zsh.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/modules/12-macos-defaults.sh"

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
  --skip-repos           Skip repository cloning
  --no-backup            Don't backup existing configurations
  --adopt                Adopt existing configs with stow instead of backing up

EXAMPLES:
  $0                     Run full installation
  $0 --dry-run          Preview installation without making changes
  $0 --module 03        Run only module 03 (stow dotfiles)
  $0 --skip 09          Run all modules except 09 (clone repos)
  $0 --verbose          Run with detailed logging

MODULES:
  01 - Prerequisites (Xcode CLI tools)
  02 - Homebrew installation
  03 - Stow dotfiles (dynamic package detection)
  04 - Curl-based tools (Claude CLI, fnm, PNPM)
  05 - Brew packages
  06 - Brew casks
  07 - Git configuration
  08 - Directory structure
  09 - Clone repositories (interactive fzf)
  10 - Oh My Zsh
  11 - macOS defaults

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
        SKIP_MODULES+=("09")
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
  for skip in "${SKIP_MODULES[@]}"; do
    if [[ "$module_num" == "$skip" ]]; then
      return 1
    fi
  done

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
  local total_modules=12
  local successful_modules=0
  local failed_modules=0

  # Start timer
  local start_time
  start_time=$(date +%s)

  # Execute modules in the correct order
  # Module 00: Prerequisites (Xcode CLI - provides git)
  if run_module "00" "Prerequisites" "module_00_prerequisites"; then
    ((successful_modules++))
  else
    ((failed_modules++))
  fi

  # Module 01: Homebrew (provides brew)
  if run_module "01" "Homebrew" "module_01_homebrew"; then
    ((successful_modules++))
  else
    ((failed_modules++))
  fi

  # Module 02: Script dependencies (dasel, jq - requires brew)
  if run_module "02" "Script Dependencies" "module_02_script_dependencies"; then
    ((successful_modules++))
  else
    ((failed_modules++))
    log_error_exit "Failed to install script dependencies. Cannot continue."
  fi

  # Initialize TOML parser (after dasel is installed)
  init_toml_parser

  # Module 04: Stow Dotfiles (requires git and stow)
  if run_module "04" "Stow Dotfiles" "module_04_stow_dotfiles"; then
    ((successful_modules++))
  else
    ((failed_modules++))
  fi

  # Module 05: Curl Tools (Claude CLI, fnm, pnpm)
  if run_module "05" "Curl Tools" "module_05_curl_tools"; then
    ((successful_modules++))
  else
    ((failed_modules++))
  fi

  # Module 06: Brew Packages
  if run_module "06" "Brew Packages" "module_06_brew_packages"; then
    ((successful_modules++))
  else
    ((failed_modules++))
  fi

  # Module 07: Brew Casks
  if run_module "07" "Brew Casks" "module_07_brew_casks"; then
    ((successful_modules++))
  else
    ((failed_modules++))
  fi

  # Module 08: Git Configuration
  if run_module "08" "Git Configuration" "module_08_git_config"; then
    ((successful_modules++))
  else
    ((failed_modules++))
  fi

  # Module 09: Directory Structure
  if run_module "09" "Directory Structure" "module_09_directories"; then
    ((successful_modules++))
  else
    ((failed_modules++))
  fi

  # Module 10: Clone Repositories (requires jq)
  if run_module "10" "Clone Repositories" "module_10_clone_repos"; then
    ((successful_modules++))
  else
    ((failed_modules++))
  fi

  # Module 11: Oh My Zsh
  if run_module "11" "Oh My Zsh" "module_11_oh_my_zsh"; then
    ((successful_modules++))
  else
    ((failed_modules++))
  fi

  # Module 12: macOS Defaults
  if run_module "12" "macOS Defaults" "module_12_macos_defaults"; then
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
