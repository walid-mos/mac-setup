#!/usr/bin/env bash

# ============================================================================
# Mail Accounts Configuration Automation
# Generates mobileconfig profiles for email accounts
# ============================================================================

set -euo pipefail

# Source libraries (for standalone execution)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$PROJECT_ROOT/lib/config.sh" ]]; then
  source "$PROJECT_ROOT/lib/config.sh"
  source "$PROJECT_ROOT/lib/logger.sh"
  source "$PROJECT_ROOT/lib/helpers.sh"
  source "$PROJECT_ROOT/lib/toml-parser.sh"
fi

# ============================================================================
# Provider Presets
# ============================================================================
get_provider_config() {
  local provider_type="$1"

  case "$provider_type" in
    Gmail)
      echo "imap.gmail.com|993|smtp.gmail.com|587"
      ;;
    Microsoft|Outlook)
      echo "outlook.office365.com|993|smtp.office365.com|587"
      ;;
    iCloud)
      echo "imap.mail.me.com|993|smtp.mail.me.com|587"
      ;;
    Yahoo)
      echo "imap.mail.yahoo.com|993|smtp.mail.yahoo.com|587"
      ;;
    *)
      echo ""
      ;;
  esac
}

# ============================================================================
# UUID Generation
# ============================================================================
generate_uuid() {
  if command -v uuidgen &> /dev/null; then
    uuidgen
  else
    # Fallback to random generation
    cat /dev/urandom | LC_ALL=C tr -dc 'A-F0-9' | fold -w 32 | head -n 1 | \
      sed -e 's/\(.\{8\}\)\(.\{4\}\)\(.\{4\}\)\(.\{4\}\)/\1-\2-\3-\4-/'
  fi
}

# ============================================================================
# Profile Generation
# ============================================================================
generate_profile() {
  local index="$1"
  local account_name email display_name account_type
  local imap_server imap_port imap_username
  local smtp_server smtp_port smtp_username

  # Read account configuration from TOML (remove quotes from dasel output)
  account_name=$(parse_toml_value "$TOML_CONFIG" "mail.accounts.[$index].name" | sed "s/^'//;s/'$//")
  email=$(parse_toml_value "$TOML_CONFIG" "mail.accounts.[$index].email" | sed "s/^'//;s/'$//")
  display_name=$(parse_toml_value "$TOML_CONFIG" "mail.accounts.[$index].display_name" | sed "s/^'//;s/'$//")
  account_type=$(parse_toml_value "$TOML_CONFIG" "mail.accounts.[$index].type" | sed "s/^'//;s/'$//")

  # Validate required fields
  if [[ -z "$account_name" || -z "$email" || -z "$display_name" || -z "$account_type" ]]; then
    log_error "Account #$((index + 1)): Missing required fields (name, email, display_name, or type)"
    return 1
  fi

  # Get provider preset if available
  local preset
  preset=$(get_provider_config "$account_type")

  if [[ -n "$preset" ]]; then
    # Use preset values
    IFS='|' read -r imap_server imap_port smtp_server smtp_port <<< "$preset"
    imap_username="$email"
    smtp_username="$email"
    log_verbose "Using preset configuration for $account_type"
  else
    # Read custom IMAP/SMTP settings (remove quotes from dasel output)
    imap_server=$(parse_toml_value "$TOML_CONFIG" "mail.accounts.[$index].imap_server" | sed "s/^'//;s/'$//")
    imap_port=$(parse_toml_value "$TOML_CONFIG" "mail.accounts.[$index].imap_port" | sed "s/^'//;s/'$//")
    imap_username=$(parse_toml_value "$TOML_CONFIG" "mail.accounts.[$index].imap_username" | sed "s/^'//;s/'$//")
    smtp_server=$(parse_toml_value "$TOML_CONFIG" "mail.accounts.[$index].smtp_server" | sed "s/^'//;s/'$//")
    smtp_port=$(parse_toml_value "$TOML_CONFIG" "mail.accounts.[$index].smtp_port" | sed "s/^'//;s/'$//")
    smtp_username=$(parse_toml_value "$TOML_CONFIG" "mail.accounts.[$index].smtp_username" | sed "s/^'//;s/'$//")

    # Set defaults if not provided
    [[ -z "$imap_port" ]] && imap_port=993
    [[ -z "$smtp_port" ]] && smtp_port=587
    [[ -z "$imap_username" ]] && imap_username="$email"
    [[ -z "$smtp_username" ]] && smtp_username="$email"

    # Validate custom configuration
    if [[ -z "$imap_server" || -z "$smtp_server" ]]; then
      log_error "Account #$((index + 1)): Custom type requires imap_server and smtp_server"
      return 1
    fi
  fi

  # Generate UUIDs for this profile
  local profile_uuid incoming_uuid
  profile_uuid=$(generate_uuid)
  incoming_uuid=$(generate_uuid)

  # Create account ID (sanitized)
  local account_id
  account_id=$(echo "$account_name" | tr '[:upper:]' '[:lower:]' | tr -s ' ' '-' | tr -cd 'a-z0-9-')

  # Output directory
  local output_dir="$HOME/Desktop/mail-profiles"
  local output_file="$output_dir/${account_id}.mobileconfig"

  # Read template
  local template_file="$PROJECT_ROOT/templates/mail-account.mobileconfig.template"
  if [[ ! -f "$template_file" ]]; then
    log_error "Template file not found: $template_file"
    return 1
  fi

  local template_content
  template_content=$(cat "$template_file")

  # Replace placeholders
  local profile_content
  profile_content=$(echo "$template_content" | \
    sed "s|{{ACCOUNT_ID}}|$account_id|g" | \
    sed "s|{{ACCOUNT_NAME}}|$account_name|g" | \
    sed "s|{{EMAIL_ADDRESS}}|$email|g" | \
    sed "s|{{DISPLAY_NAME}}|$display_name|g" | \
    sed "s|{{IMAP_SERVER}}|$imap_server|g" | \
    sed "s|{{IMAP_PORT}}|$imap_port|g" | \
    sed "s|{{IMAP_USERNAME}}|$imap_username|g" | \
    sed "s|{{SMTP_SERVER}}|$smtp_server|g" | \
    sed "s|{{SMTP_PORT}}|$smtp_port|g" | \
    sed "s|{{SMTP_USERNAME}}|$smtp_username|g" | \
    sed "s|{{PROFILE_UUID}}|$profile_uuid|g" | \
    sed "s|{{INCOMING_UUID}}|$incoming_uuid|g")

  # Write profile
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would generate: $output_file"
    log_verbose "  Email: $email"
    log_verbose "  IMAP: $imap_server:$imap_port"
    log_verbose "  SMTP: $smtp_server:$smtp_port"
  else
    echo "$profile_content" > "$output_file"
    log_success "Generated profile: $output_file"
    log_verbose "  Email: $email"
    log_verbose "  IMAP: $imap_server:$imap_port"
    log_verbose "  SMTP: $smtp_server:$smtp_port"
  fi

  return 0
}

# ============================================================================
# Main Automation Function
# ============================================================================
automation_setup_mail_accounts() {
  log_info "Starting mail accounts configuration..."

  # ----------------------------------
  # Step 1: Check if enabled
  # ----------------------------------
  local enabled
  enabled=$(parse_toml_value "$TOML_CONFIG" "mail.enabled" | sed "s/^'//;s/'$//")

  if [[ "$enabled" != "true" ]]; then
    log_info "Mail automation is disabled in config (mail.enabled = false)"
    log_info "Skipping mail account setup..."
    return 0
  fi

  # ----------------------------------
  # Step 2: Count accounts
  # ----------------------------------
  log_step "Checking mail accounts configuration..."

  local account_count=0
  while true; do
    local account_name
    account_name=$(parse_toml_value "$TOML_CONFIG" "mail.accounts.[$account_count].name" 2>/dev/null | sed "s/^'//;s/'$//")
    [[ -z "$account_name" ]] && break
    account_count=$((account_count + 1))
  done

  if [[ $account_count -eq 0 ]]; then
    log_warning "No mail accounts configured in mac-setup.toml"
    log_info "Add accounts in the [mail.accounts] section to use this automation"
    return 0
  fi

  log_info "Found $account_count mail account(s) to configure"

  # ----------------------------------
  # Step 3: Create output directory
  # ----------------------------------
  local output_dir="$HOME/Desktop/mail-profiles"

  if [[ "$DRY_RUN" != "true" ]]; then
    mkdir -p "$output_dir"
    log_verbose "Created output directory: $output_dir"
  fi

  # ----------------------------------
  # Step 4: Generate profiles
  # ----------------------------------
  log_step "Generating mobileconfig profiles..."

  local success_count=0
  local failed_count=0

  for ((i=0; i<account_count; i++)); do
    if generate_profile "$i"; then
      success_count=$((success_count + 1))
    else
      failed_count=$((failed_count + 1))
    fi
  done

  # ----------------------------------
  # Step 5: Display results and instructions
  # ----------------------------------
  echo ""
  log_section "Mail Account Setup Summary"
  echo ""

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would generate $success_count profile(s)"
    if [[ $failed_count -gt 0 ]]; then
      log_warning "$failed_count profile(s) would fail due to configuration errors"
    fi
  else
    log_success "Successfully generated $success_count profile(s)"
    if [[ $failed_count -gt 0 ]]; then
      log_error "$failed_count profile(s) failed to generate"
    fi

    echo ""
    log_info "Profiles saved to: $output_dir"
    echo ""
    log_info "Next steps:"
    echo ""
    echo "  1. Open System Settings > Profiles"
    echo "  2. Drag and drop each .mobileconfig file (or double-click)"
    echo "  3. Click 'Install' for each profile"
    echo "  4. Open Mail.app - accounts will appear automatically"
    echo "  5. Enter your password when prompted (Mail.app will ask)"
    echo ""
    log_info "Special notes:"
    echo ""
    echo "  - Gmail/Google accounts: Use app-specific passwords if 2FA enabled"
    echo "    Generate at: https://myaccount.google.com/apppasswords"
    echo ""
    echo "  - Microsoft/Outlook accounts: May require OAuth2 browser authentication"
    echo ""
    echo "  - After installation, you can delete the profiles from Desktop"
    echo "    (they're already installed in System Settings)"
    echo ""
  fi

  # Return success only if all profiles generated successfully
  if [[ $failed_count -gt 0 ]]; then
    return 1
  fi

  log_success "Mail accounts automation completed"
  return 0
}

# ============================================================================
# Standalone Execution
# ============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  automation_setup_mail_accounts
fi
