#!/usr/bin/env bash

# =============================================================================
# Curl-based Tools
# =============================================================================
# Install tools via curl commands from TOML configuration.
# Commands are executed as-is without modification.
# =============================================================================

# Validate curl install command format
validate_curl_command() {
  local cmd="$1"

  # Must contain curl or wget (it's a curl-tools module)
  if [[ ! "$cmd" =~ (curl|wget) ]]; then
    return 1
  fi

  # Block obviously dangerous patterns
  if [[ "$cmd" =~ (rm\ -rf|mkfs|dd\ if=|>\s*/dev/) ]]; then
    return 1
  fi

  return 0
}

module_curl_tools() {
  log_section "Installing Curl-based Tools"

  # Dynamically detect all curl tools from TOML
  local tools
  tools=$(get_toml_section_keys "$TOML_CONFIG" "curl_tools")

  if [[ -z "$tools" ]]; then
    log_warning "No curl tools found in TOML configuration"
    return 0
  fi

  local installed_count=0
  local total_count=0

  # Install each tool
  while IFS= read -r tool_name; do
    [[ -z "$tool_name" ]] && continue
    ((total_count++))

    log_subsection "$tool_name"

    # Get the full command from TOML
    local install_command
    install_command=$(parse_toml_value "$TOML_CONFIG" "curl_tools.$tool_name")

    # Strip surrounding single quotes from TOML string value
    install_command="${install_command#\'}"
    install_command="${install_command%\'}"

    if [[ -z "$install_command" ]]; then
      log_error "No installation command found for: $tool_name"
      continue
    fi

    # Check if already installed (simple command check)
    local binary_name
    case "$tool_name" in
      claude_cli)
        binary_name="claude"
        ;;
      oh_my_zsh)
        if [[ -d "$HOME/.oh-my-zsh" ]]; then
          log_success "oh-my-zsh is already installed"
          continue
        fi
        binary_name=""
        ;;
      *)
        binary_name="$tool_name"
        ;;
    esac

    if [[ -n "$binary_name" ]] && command_exists "$binary_name"; then
      log_success "$tool_name is already installed"
      "$binary_name" --version 2>/dev/null || true
      ((installed_count++))
      continue
    fi

    log_info "Installing $tool_name..."
    log_verbose "Command: $install_command"

    # Validate command format
    if ! validate_curl_command "$install_command"; then
      log_error "Invalid curl command format for $tool_name (must contain curl or wget)"
      log_warning "Skipping: $install_command"
      continue
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
      log_dry_run "Would execute: $install_command"
      continue
    fi

    # Execute the installation command
    if eval "$install_command"; then
      log_success "$tool_name installed successfully"
      ((installed_count++))

      # Show version if possible
      if [[ -n "$binary_name" ]] && command_exists "$binary_name"; then
        "$binary_name" --version 2>/dev/null || true
      fi
    else
      log_error "Failed to install $tool_name"
      log_warning "Command failed: $install_command"
    fi
  done <<< "$tools"

  # Summary
  if [[ $total_count -eq 0 ]]; then
    log_warning "No curl tools configured"
  else
    log_success "Processed $installed_count/$total_count curl tools"
  fi

  return 0
}

# Run module if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  module_curl_tools
fi
