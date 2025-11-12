#!/usr/bin/env bash

# Automation script to configure Cloudflare DNS on all network interfaces
# Configures all active network interfaces to use Cloudflare's 1.1.1.1 DNS servers
# with Google DNS as fallback, replacing ISP DNS servers

set -euo pipefail

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$PROJECT_ROOT/lib/config.sh" ]]; then
  source "$PROJECT_ROOT/lib/config.sh"
  source "$PROJECT_ROOT/lib/logger.sh"
  source "$PROJECT_ROOT/lib/helpers.sh"
fi

# DNS Configuration
readonly CLOUDFLARE_IPV4_PRIMARY="1.1.1.1"
readonly CLOUDFLARE_IPV4_SECONDARY="1.0.0.1"
readonly CLOUDFLARE_IPV6_PRIMARY="2606:4700:4700::1111"
readonly CLOUDFLARE_IPV6_SECONDARY="2606:4700:4700::1001"
readonly GOOGLE_DNS_FALLBACK="8.8.8.8"

# Interfaces to exclude (inactive or virtual)
readonly EXCLUDED_INTERFACES=(
  "*"  # Asterisk line from networksetup output
  "iPhone USB"
  "Bluetooth PAN"
  "Thunderbolt Bridge"
)

# Helper function to check if interface should be excluded
is_excluded_interface() {
  local interface="$1"

  for excluded in "${EXCLUDED_INTERFACES[@]}"; do
    if [[ "$interface" == "$excluded" ]]; then
      return 0
    fi
  done

  return 1
}

# Helper function to get current DNS servers for an interface
get_current_dns() {
  local interface="$1"
  local current_dns

  current_dns=$(networksetup -getdnsservers "$interface" 2>/dev/null || echo "")

  # networksetup returns "There aren't any DNS Servers set on <interface>." when empty
  if [[ "$current_dns" == *"aren't any DNS"* ]]; then
    echo ""
  else
    echo "$current_dns"
  fi
}

# Helper function to check if DNS is already configured with Cloudflare
is_cloudflare_configured() {
  local interface="$1"
  local current_dns

  current_dns=$(get_current_dns "$interface")

  # Check if Cloudflare primary DNS is already first in the list
  if [[ "$current_dns" == *"$CLOUDFLARE_IPV4_PRIMARY"* ]]; then
    return 0
  fi

  return 1
}

# Helper function to configure DNS for a single interface
configure_interface_dns() {
  local interface="$1"
  local dns_servers="$CLOUDFLARE_IPV4_PRIMARY $CLOUDFLARE_IPV4_SECONDARY $CLOUDFLARE_IPV6_PRIMARY $CLOUDFLARE_IPV6_SECONDARY $GOOGLE_DNS_FALLBACK"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would set DNS for '$interface' to: $dns_servers"
    return 0
  fi

  # Apply DNS configuration
  if networksetup -setdnsservers "$interface" $dns_servers 2>/dev/null; then
    log_success "Configured DNS for '$interface'"
    return 0
  else
    log_error "Failed to configure DNS for '$interface'"
    return 1
  fi
}

# Helper function to verify DNS configuration
verify_dns_configuration() {
  local interface="$1"
  local current_dns

  current_dns=$(get_current_dns "$interface")

  if [[ "$current_dns" == *"$CLOUDFLARE_IPV4_PRIMARY"* ]]; then
    log_verbose "Verified: '$interface' is using Cloudflare DNS"
    return 0
  else
    log_warning "Verification failed: '$interface' DNS may not be configured correctly"
    return 1
  fi
}

# Helper function to clear DNS cache
clear_dns_cache() {
  log_step "Clearing DNS cache..."

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY RUN] Would clear DNS cache with: sudo killall -HUP mDNSResponder"
    return 0
  fi

  if sudo killall -HUP mDNSResponder 2>/dev/null; then
    log_success "DNS cache cleared"
    return 0
  else
    log_warning "Could not clear DNS cache (mDNSResponder may not be running)"
    return 0  # Not a fatal error
  fi
}

# Main automation function
automation_configure_cloudflare_dns() {
  log_subsection "Configure Cloudflare DNS"

  log_info "Configuring all network interfaces to use Cloudflare DNS (1.1.1.1)"
  log_info "DNS servers: $CLOUDFLARE_IPV4_PRIMARY, $CLOUDFLARE_IPV4_SECONDARY (IPv4)"
  log_info "             $CLOUDFLARE_IPV6_PRIMARY, $CLOUDFLARE_IPV6_SECONDARY (IPv6)"
  log_info "             $GOOGLE_DNS_FALLBACK (Google DNS fallback)"

  # Get list of all network services
  log_step "Detecting network interfaces..."

  local all_interfaces
  all_interfaces=$(networksetup -listallnetworkservices 2>/dev/null)

  if [[ -z "$all_interfaces" ]]; then
    log_error "Failed to list network interfaces"
    return 1
  fi

  # Process each interface
  local configured_count=0
  local skipped_count=0
  local failed_count=0

  while IFS= read -r interface; do
    # Skip excluded interfaces
    if is_excluded_interface "$interface"; then
      log_verbose "Skipping excluded interface: '$interface'"
      continue
    fi

    log_step "Processing interface: '$interface'"

    # Check if already configured
    if is_cloudflare_configured "$interface"; then
      log_info "Already configured with Cloudflare DNS, skipping"
      ((skipped_count++))
      continue
    fi

    # Show current DNS configuration
    local current_dns
    current_dns=$(get_current_dns "$interface")
    if [[ -n "$current_dns" ]]; then
      log_verbose "Current DNS: $current_dns"
    else
      log_verbose "Current DNS: (none set)"
    fi

    # Configure DNS
    if configure_interface_dns "$interface"; then
      ((configured_count++))

      # Verify configuration (only in non-dry-run mode)
      if [[ "$DRY_RUN" != "true" ]]; then
        verify_dns_configuration "$interface"
      fi
    else
      ((failed_count++))
    fi

  done <<< "$all_interfaces"

  # Clear DNS cache
  if [[ $configured_count -gt 0 ]]; then
    clear_dns_cache
  fi

  # Summary
  log_info ""
  log_info "Summary:"
  log_info "  Configured: $configured_count interface(s)"
  log_info "  Skipped (already configured): $skipped_count interface(s)"

  if [[ $failed_count -gt 0 ]]; then
    log_error "  Failed: $failed_count interface(s)"
    return 1
  fi

  if [[ $configured_count -gt 0 ]]; then
    log_success "Cloudflare DNS configuration complete"
  else
    log_info "No changes needed - all interfaces already configured"
  fi

  return 0
}

# Support standalone execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  automation_configure_cloudflare_dns
fi
