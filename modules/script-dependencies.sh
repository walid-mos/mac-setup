#!/usr/bin/env bash

# =============================================================================
# Script Dependencies: Script Dependencies
# =============================================================================
# Install tools required for the script itself to function properly.
# Requires Homebrew (Module 01) to be installed first.
# =============================================================================

module_script_dependencies() {
  log_section "Script Dependencies: Installing Script Dependencies"

  # Verify Homebrew is installed
  require_tool brew "Homebrew not found. Please run homebrew module first"

  # Required tools for script functionality
  local required_tools=(
    "jq"  # JSON parsing (for GitHub/GitLab API responses)
  )

  local installed=0
  local already_present=0

  for tool in "${required_tools[@]}"; do
    if command_exists "$tool"; then
      log_verbose "$tool is already installed"
      ((already_present++))
    else
      log_info "Installing required tool: $tool"

      if [[ "$DRY_RUN" == "true" ]]; then
        log_dry_run "Would install $tool via Homebrew"
        ((installed++))
      else
        brew install "$tool" || {
          log_error "Failed to install $tool"
          log_error "This tool is required for the script to function"
          return 1
        }
        # Clear bash hash table so new commands are found immediately
        hash -r
        log_success "Installed: $tool"
        ((installed++))
      fi
    fi
  done

  echo ""
  log_subsection "Dependencies Summary"
  echo -e "  Installed: ${COLOR_GREEN}$installed${COLOR_RESET}"
  echo -e "  Already present: ${COLOR_YELLOW}$already_present${COLOR_RESET}"
  echo ""

  log_success "Script dependencies ready"
  return 0
}

# Run module if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  module_script_dependencies
fi
