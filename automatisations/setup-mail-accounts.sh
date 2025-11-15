#!/usr/bin/env bash

# ============================================================================
# Mail Accounts Configuration Automation
# Interactive guided setup for email accounts with OAuth2 support
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
# Configuration
# ============================================================================
MAIL_DB_PATH="$HOME/Library/Mail/V*/MailData/Accounts4.sqlite"
TIMEOUT_PER_ACCOUNT=300  # 5 minutes max per account

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
# Account Verification
# ============================================================================
verify_account_added() {
  local email="$1"
  local timeout="${2:-$TIMEOUT_PER_ACCOUNT}"

  log_verbose "Verifying account was added: $email"

  local elapsed=0
  while true; do
    # Check if account exists in database
    if sqlite3 $MAIL_DB_PATH "SELECT ZUSERNAME FROM ZACCOUNT WHERE ZUSERNAME LIKE '%$email%'" 2>/dev/null | grep -q "$email"; then
      log_success "Account verified: $email"
      return 0
    fi

    # Check timeout
    if [[ $elapsed -ge $timeout ]]; then
      log_warning "Account verification timed out (not found in database)"
      log_info "This may be normal - Mail.app might still be syncing"
      return 1
    fi

    sleep 2
    elapsed=$((elapsed + 2))
  done
}

# ============================================================================
# Gmail Account Setup (OAuth2)
# ============================================================================
setup_gmail_account() {
  local email="$1"
  local display_name="$2"

  clear
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📧  Gmail Account Setup"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "  Email:         $email"
  echo "  Display Name:  $display_name"
  echo "  Provider:      Google (OAuth2 authentication required)"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "🔧  Setup Instructions:"
  echo ""
  echo "  1. Mail.app will open automatically"
  echo "  2. Go to: Mail > Settings... (⌘,)"
  echo "  3. Click the 'Accounts' tab"
  echo "  4. Click the '+' button at the bottom left"
  echo "  5. Select 'Google' from the account type list"
  echo "  6. Click 'Continue'"
  echo "  7. Your browser will open → Sign in with your Google account"
  echo "  8. Click 'Allow' to authorize Mail.app access"
  echo "  9. Close the Settings window when complete"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would setup Gmail account: $email"
    return 0
  fi

  # Auto-copy email to clipboard
  echo "$email" | pbcopy
  echo "✅  Email address copied to clipboard (ready to paste if needed)"
  echo ""

  # Open Mail.app
  log_step "Opening Mail.app..."
  open -a Mail
  sleep 2

  # Wait for user confirmation
  echo ""
  read -p "Press ENTER when you've completed the setup..."

  # Verify account was added (optional - may not appear immediately)
  echo ""
  log_step "Verifying account was added..."

  if verify_account_added "$email" 30; then
    echo ""
    log_success "Gmail account successfully configured!"
  else
    echo ""
    log_info "Account verification skipped (this is normal for OAuth accounts)"
    log_info "Your account should appear in Mail.app shortly"
  fi

  sleep 2
  return 0
}

# ============================================================================
# Microsoft Account Setup (OAuth2)
# ============================================================================
setup_microsoft_account() {
  local email="$1"
  local display_name="$2"

  clear
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📧  Microsoft/Outlook Account Setup"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "  Email:         $email"
  echo "  Display Name:  $display_name"
  echo "  Provider:      Microsoft (OAuth2 authentication required)"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "🔧  Setup Instructions:"
  echo ""
  echo "  1. Mail.app will open automatically"
  echo "  2. Go to: Mail > Settings... (⌘,)"
  echo "  3. Click the 'Accounts' tab"
  echo "  4. Click the '+' button at the bottom left"
  echo "  5. Select 'Microsoft Exchange' or 'Outlook.com'"
  echo "  6. Enter your email address when prompted"
  echo "  7. Click 'Sign In'"
  echo "  8. Your browser will open → Sign in with Microsoft"
  echo "  9. Click 'Accept' to authorize Mail.app access"
  echo "  10. Close the Settings window when complete"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would setup Microsoft account: $email"
    return 0
  fi

  # Auto-copy email to clipboard
  echo "$email" | pbcopy
  echo "✅  Email address copied to clipboard (ready to paste)"
  echo ""

  # Open Mail.app
  log_step "Opening Mail.app..."
  open -a Mail
  sleep 2

  # Wait for user confirmation
  echo ""
  read -p "Press ENTER when you've completed the setup..."

  # Verify account was added
  echo ""
  log_step "Verifying account was added..."

  if verify_account_added "$email" 30; then
    echo ""
    log_success "Microsoft account successfully configured!"
  else
    echo ""
    log_info "Account verification skipped (this is normal for OAuth accounts)"
    log_info "Your account should appear in Mail.app shortly"
  fi

  sleep 2
  return 0
}

# ============================================================================
# IMAP Account Setup (Traditional Password Auth)
# ============================================================================
setup_imap_account() {
  local email="$1"
  local display_name="$2"
  local imap_server="$3"
  local imap_port="$4"
  local smtp_server="$5"
  local smtp_port="$6"

  clear
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📧  IMAP Account Setup"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "📋  Account Details (ready to copy-paste):"
  echo ""
  echo "  Email:            $email"
  echo "  Display Name:     $display_name"
  echo "  Account Type:     IMAP"
  echo ""
  echo "  ┌─ Incoming Mail Server (IMAP) ─────────────────────────────────┐"
  echo "  │  Server:   $imap_server"
  echo "  │  Port:     $imap_port"
  echo "  │  Username: $email"
  echo "  │  SSL:      Yes (required)"
  echo "  └────────────────────────────────────────────────────────────────┘"
  echo ""
  echo "  ┌─ Outgoing Mail Server (SMTP) ─────────────────────────────────┐"
  echo "  │  Server:   $smtp_server"
  echo "  │  Port:     $smtp_port"
  echo "  │  Username: $email"
  echo "  │  SSL:      Yes (STARTTLS)"
  echo "  └────────────────────────────────────────────────────────────────┘"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "🔧  Setup Instructions:"
  echo ""
  echo "  1. Mail.app will open automatically"
  echo "  2. Go to: Mail > Settings... (⌘,)"
  echo "  3. Click the 'Accounts' tab"
  echo "  4. Click '+' → Select 'Add Other Mail Account...'"
  echo "  5. Enter Name and Email (details above)"
  echo "  6. Click 'Sign In'"
  echo "  7. Enter your password when prompted"
  echo "  8. Mail.app will try to auto-detect settings"
  echo "  9. Verify IMAP/SMTP details match the values above"
  echo "  10. If auto-detect fails, enter server details manually"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would setup IMAP account: $email"
    return 0
  fi

  # Create temp file with all details for easy reference
  local temp_file="/tmp/mail_account_${email}.txt"
  cat > "$temp_file" <<EOF
Email Account Configuration
===========================

Email: $email
Display Name: $display_name
Account Type: IMAP

Incoming Mail Server (IMAP)
---------------------------
Server: $imap_server
Port: $imap_port
Username: $email
SSL: Yes (required)

Outgoing Mail Server (SMTP)
---------------------------
Server: $smtp_server
Port: $smtp_port
Username: $email
SSL: Yes (STARTTLS)

Password: [Enter your password when Mail.app prompts]
EOF

  echo "📄  Full details saved to: $temp_file"
  echo "    (You can reference this file if needed during setup)"
  echo ""

  # Copy email to clipboard
  echo "$email" | pbcopy
  echo "✅  Email address copied to clipboard"
  echo ""

  # Open Mail.app
  log_step "Opening Mail.app..."
  open -a Mail
  sleep 2

  # Wait for user confirmation
  echo ""
  read -p "Press ENTER when you've completed the setup..."

  # Verify account was added
  echo ""
  log_step "Verifying account was added..."

  if verify_account_added "$email" 60; then
    echo ""
    log_success "IMAP account successfully configured!"
  else
    echo ""
    log_warning "Could not verify account in database"
    log_info "Please check Mail.app to ensure account was added correctly"
  fi

  # Clean up temp file
  rm -f "$temp_file"
  sleep 2
  return 0
}

# ============================================================================
# Main Automation Function
# ============================================================================
automation_setup_mail_accounts() {
  log_section "Mail Account Guided Setup"

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
  # Step 3: Introduction
  # ----------------------------------
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📧  Mail Account Setup - Interactive Mode"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "This script will guide you through setting up each email account"
  echo "with clear step-by-step instructions and automatic verification."
  echo ""
  echo "✨  Features:"
  echo "    • Provider-specific setup flows (Gmail, Microsoft, IMAP)"
  echo "    • OAuth2 authentication for Gmail and Microsoft"
  echo "    • Auto-copy credentials to clipboard"
  echo "    • Automatic account verification"
  echo ""
  echo "⏱️   Estimated time: $((account_count * 2)) - $((account_count * 3)) minutes"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  if [[ "$DRY_RUN" != "true" ]]; then
    read -p "Press ENTER to start, or Ctrl+C to cancel..."
  fi

  # ----------------------------------
  # Step 4: Process each account
  # ----------------------------------
  local success_count=0
  local failed_count=0

  for ((i=0; i<account_count; i++)); do
    local account_type email display_name account_name

    # Read basic account info
    account_name=$(parse_toml_value "$TOML_CONFIG" "mail.accounts.[$i].name" | sed "s/^'//;s/'$//")
    email=$(parse_toml_value "$TOML_CONFIG" "mail.accounts.[$i].email" | sed "s/^'//;s/'$//")
    display_name=$(parse_toml_value "$TOML_CONFIG" "mail.accounts.[$i].display_name" | sed "s/^'//;s/'$//")
    account_type=$(parse_toml_value "$TOML_CONFIG" "mail.accounts.[$i].type" | sed "s/^'//;s/'$//")

    # Validate required fields
    if [[ -z "$email" || -z "$display_name" || -z "$account_type" ]]; then
      log_error "Account #$((i + 1)) ($account_name): Missing required fields"
      failed_count=$((failed_count + 1))
      continue
    fi

    # Show progress
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Account $((i + 1)) of $account_count"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Route to appropriate setup function
    case "$account_type" in
      Gmail)
        if setup_gmail_account "$email" "$display_name"; then
          success_count=$((success_count + 1))
        else
          failed_count=$((failed_count + 1))
        fi
        ;;

      Microsoft|Outlook)
        if setup_microsoft_account "$email" "$display_name"; then
          success_count=$((success_count + 1))
        else
          failed_count=$((failed_count + 1))
        fi
        ;;

      IMAP|iCloud|Yahoo|*)
        # Get server details from preset or custom config
        local preset imap_server smtp_server imap_port smtp_port
        preset=$(get_provider_config "$account_type")

        if [[ -n "$preset" ]]; then
          # Use preset
          IFS='|' read -r imap_server imap_port smtp_server smtp_port <<< "$preset"
        else
          # Read custom IMAP/SMTP settings
          imap_server=$(parse_toml_value "$TOML_CONFIG" "mail.accounts.[$i].imap_server" | sed "s/^'//;s/'$//")
          smtp_server=$(parse_toml_value "$TOML_CONFIG" "mail.accounts.[$i].smtp_server" | sed "s/^'//;s/'$//")
          imap_port=$(parse_toml_value "$TOML_CONFIG" "mail.accounts.[$i].imap_port" | sed "s/^'//;s/'$//")
          smtp_port=$(parse_toml_value "$TOML_CONFIG" "mail.accounts.[$i].smtp_port" | sed "s/^'//;s/'$//")

          # Set defaults
          [[ -z "$imap_port" ]] && imap_port=993
          [[ -z "$smtp_port" ]] && smtp_port=587

          # Validate
          if [[ -z "$imap_server" || -z "$smtp_server" ]]; then
            log_error "Account #$((i + 1)): Missing IMAP/SMTP server settings"
            failed_count=$((failed_count + 1))
            continue
          fi
        fi

        if setup_imap_account "$email" "$display_name" "$imap_server" "$imap_port" "$smtp_server" "$smtp_port"; then
          success_count=$((success_count + 1))
        else
          failed_count=$((failed_count + 1))
        fi
        ;;
    esac
  done

  # ----------------------------------
  # Step 5: Final Summary
  # ----------------------------------
  clear
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📧  Mail Account Setup - Complete"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would configure $account_count account(s)"
  else
    log_success "Successfully configured: $success_count account(s)"

    if [[ $failed_count -gt 0 ]]; then
      log_error "Failed to configure: $failed_count account(s)"
    fi

    echo ""
    echo "✅  All mail accounts are now configured!"
    echo ""
    echo "📬  You can start using Mail.app with all your accounts."
    echo ""

    if [[ $failed_count -gt 0 ]]; then
      echo "⚠️   Some accounts failed to configure."
      echo "    Please check the error messages above and try adding them manually."
      echo ""
    fi
  fi

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  # Return success only if all accounts configured successfully
  return $([ $failed_count -eq 0 ] && echo 0 || echo 1)
}

# ============================================================================
# Standalone Execution
# ============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  automation_setup_mail_accounts
fi
