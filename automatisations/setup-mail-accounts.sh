#!/usr/bin/env bash

# ============================================================================
# Mail Accounts Configuration Display
# Shows email account configurations one by one (read-only)
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
# Gmail Account Display
# ============================================================================
display_gmail_account() {
  local email="$1"
  local display_name="$2"

  clear
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📧  Configuration Gmail"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "  Email:         $email"
  echo "  Nom:           $display_name"
  echo "  Type:          Gmail (OAuth2)"
  echo ""
  echo "  ┌─ Configuration Serveur ────────────────────────────────────────┐"
  echo "  │  IMAP:         imap.gmail.com"
  echo "  │  Port IMAP:    993"
  echo "  │  SMTP:         smtp.gmail.com"
  echo "  │  Port SMTP:    587"
  echo "  │  Auth:         OAuth2 (authentification navigateur requise)"
  echo "  └────────────────────────────────────────────────────────────────┘"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Afficherait le compte Gmail: $email"
  fi

  return 0
}

# ============================================================================
# Microsoft Account Display
# ============================================================================
display_microsoft_account() {
  local email="$1"
  local display_name="$2"

  clear
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📧  Configuration Microsoft/Outlook"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "  Email:         $email"
  echo "  Nom:           $display_name"
  echo "  Type:          Microsoft (OAuth2)"
  echo ""
  echo "  ┌─ Configuration Serveur ────────────────────────────────────────┐"
  echo "  │  IMAP:         outlook.office365.com"
  echo "  │  Port IMAP:    993"
  echo "  │  SMTP:         smtp.office365.com"
  echo "  │  Port SMTP:    587"
  echo "  │  Auth:         OAuth2 (authentification navigateur requise)"
  echo "  └────────────────────────────────────────────────────────────────┘"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Afficherait le compte Microsoft: $email"
  fi

  return 0
}

# ============================================================================
# IMAP Account Display
# ============================================================================
display_imap_account() {
  local email="$1"
  local display_name="$2"
  local imap_server="$3"
  local imap_port="$4"
  local smtp_server="$5"
  local smtp_port="$6"

  clear
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📧  Configuration IMAP"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "  Email:         $email"
  echo "  Nom:           $display_name"
  echo "  Type:          IMAP (Mot de passe)"
  echo ""
  echo "  ┌─ Serveur Entrant (IMAP) ──────────────────────────────────────┐"
  echo "  │  Serveur:      $imap_server"
  echo "  │  Port:         $imap_port"
  echo "  │  Utilisateur:  $email"
  echo "  │  SSL:          Oui (requis)"
  echo "  └────────────────────────────────────────────────────────────────┘"
  echo ""
  echo "  ┌─ Serveur Sortant (SMTP) ──────────────────────────────────────┐"
  echo "  │  Serveur:      $smtp_server"
  echo "  │  Port:         $smtp_port"
  echo "  │  Utilisateur:  $email"
  echo "  │  SSL:          Oui (STARTTLS)"
  echo "  └────────────────────────────────────────────────────────────────┘"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Afficherait le compte IMAP: $email"
  fi

  return 0
}

# ============================================================================
# Main Automation Function
# ============================================================================
automation_setup_mail_accounts() {
  log_section "Affichage des configurations mail"

  # ----------------------------------
  # Step 1: Check if enabled
  # ----------------------------------
  local enabled
  enabled=$(parse_toml_value "$TOML_CONFIG" "mail.enabled" | sed "s/^'//;s/'$//")

  if [[ "$enabled" != "true" ]]; then
    log_info "L'automatisation mail est désactivée (mail.enabled = false)"
    log_info "Passage de la configuration des comptes mail..."
    return 0
  fi

  # ----------------------------------
  # Step 2: Count accounts
  # ----------------------------------
  log_step "Vérification de la configuration des comptes mail..."

  local account_count=0
  while true; do
    local account_name
    account_name=$(parse_toml_value "$TOML_CONFIG" "mail.accounts.[$account_count].name" 2>/dev/null | sed "s/^'//;s/'$//")
    [[ -z "$account_name" ]] && break
    account_count=$((account_count + 1))
  done

  if [[ $account_count -eq 0 ]]; then
    log_warning "Aucun compte mail configuré dans mac-setup.toml"
    log_info "Ajoutez des comptes dans la section [mail.accounts] pour utiliser cette automatisation"
    return 0
  fi

  log_info "Trouvé $account_count compte(s) mail à afficher"

  # ----------------------------------
  # Step 3: Introduction
  # ----------------------------------
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📧  Affichage des configurations de comptes mail"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "Ce script affiche les détails de configuration de chaque compte"
  echo "email pour que vous puissiez les configurer manuellement."
  echo ""
  echo "📋  Informations affichées:"
  echo "    • Adresse email et nom d'affichage"
  echo "    • Type de compte (Gmail, Microsoft, IMAP)"
  echo "    • Serveurs IMAP et SMTP avec ports"
  echo "    • Méthode d'authentification"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  if [[ "$DRY_RUN" != "true" ]]; then
    read -p "Appuyez sur ENTRÉE pour commencer..."
  fi

  # ----------------------------------
  # Step 4: Display each account
  # ----------------------------------
  for ((i=0; i<account_count; i++)); do
    local account_type email display_name account_name

    # Read basic account info
    account_name=$(parse_toml_value "$TOML_CONFIG" "mail.accounts.[$i].name" | sed "s/^'//;s/'$//")
    email=$(parse_toml_value "$TOML_CONFIG" "mail.accounts.[$i].email" | sed "s/^'//;s/'$//")
    display_name=$(parse_toml_value "$TOML_CONFIG" "mail.accounts.[$i].display_name" | sed "s/^'//;s/'$//")
    account_type=$(parse_toml_value "$TOML_CONFIG" "mail.accounts.[$i].type" | sed "s/^'//;s/'$//")

    # Validate required fields
    if [[ -z "$email" || -z "$display_name" || -z "$account_type" ]]; then
      log_error "Compte #$((i + 1)) ($account_name): Champs requis manquants"
      continue
    fi

    # Show progress
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Compte $((i + 1)) sur $account_count"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Route to appropriate display function
    case "$account_type" in
      Gmail)
        display_gmail_account "$email" "$display_name"
        ;;

      Microsoft|Outlook)
        display_microsoft_account "$email" "$display_name"
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
            log_error "Compte #$((i + 1)): Configuration IMAP/SMTP manquante"
            continue
          fi
        fi

        display_imap_account "$email" "$display_name" "$imap_server" "$imap_port" "$smtp_server" "$smtp_port"
        ;;
    esac

    # Ask to continue to next account (skip for last account)
    if [[ $i -lt $((account_count - 1)) ]]; then
      echo ""
      read -p "Continuer au suivant? [Y/n] " -n 1 -r
      echo ""
      if [[ $REPLY =~ ^[Nn]$ ]]; then
        log_info "Arrêt demandé par l'utilisateur"
        break
      fi
    fi
  done

  # ----------------------------------
  # Step 5: Final Summary
  # ----------------------------------
  clear
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📧  Affichage des comptes mail - Terminé"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Afficherait $account_count compte(s)"
  else
    log_success "Configurations affichées: $account_count compte(s)"
    echo ""
    echo "📋  Vous pouvez maintenant configurer ces comptes manuellement"
    echo "    dans Mail.app (Mail > Réglages > Comptes)."
    echo ""
  fi

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  return 0
}

# ============================================================================
# Standalone Execution
# ============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  automation_setup_mail_accounts
fi
