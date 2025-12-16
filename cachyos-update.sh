#!/bin/bash
# CachyOS Update Service
# Handles pacman, yay (AUR), and Flatpak updates

# Configuration
LOG_FILE="/var/log/cachyos-update.log"
LOCK_FILE="/var/run/cachyos-update.lock"

# Better user detection for yay
get_real_user() {
    local user=""

    # Method 1: Check SUDO_USER (most reliable when run with sudo)
    if [[ -n "$SUDO_USER" && "$SUDO_USER" != "root" && "$SUDO_USER" != "." ]]; then
        user="$SUDO_USER"
        echo "$user"
        return 0
    fi

    # Method 2: Check systemd-logind for active sessions
    if command -v loginctl &> /dev/null; then
        user=$(loginctl list-users --no-legend 2>/dev/null | grep -v "^[[:space:]]*0[[:space:]]" | awk '{print $2}' | head -n1)
        if [[ -n "$user" && "$user" != "root" && "$user" != "." ]]; then
            echo "$user"
            return 0
        fi
    fi

    # Method 3: Check who's currently logged in
    if command -v who &> /dev/null; then
        user=$(who 2>/dev/null | awk '{print $1}' | grep -v "^root$" | sort -u | head -n1)
        if [[ -n "$user" && "$user" != "root" && "$user" != "." ]]; then
            echo "$user"
            return 0
        fi
    fi

    # Method 4: Check /home directories for non-system users
    if [[ -d "/home" ]]; then
        for home_dir in /home/*/; do
            if [[ -d "$home_dir" ]]; then
                local potential_user=$(basename "$home_dir")
                # Skip common non-user directories
                if [[ "$potential_user" != "lost+found" && "$potential_user" != "." && "$potential_user" != ".." ]]; then
                    # Check if it's a real user with UID >= 1000
                    local uid=$(id -u "$potential_user" 2>/dev/null)
                    if [[ -n "$uid" && "$uid" -ge 1000 ]]; then
                        user="$potential_user"
                        echo "$user"
                        return 0
                    fi
                fi
            fi
        done
    fi

    # Method 5: Check /etc/passwd for users with home dirs and shell
    user=$(getent passwd | grep -E ":/home/[^:]+:" | grep -E ":(bash|zsh|fish|sh)$" | cut -d: -f1 | head -n1)
    if [[ -n "$user" && "$user" != "root" && "$user" != "." ]]; then
        echo "$user"
        return 0
    fi

    # If all methods fail, return empty
    echo ""
}

USER_NAME="$(get_real_user)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Error handling
handle_error() {
    log_message "ERROR: $1"
    echo -e "${RED}Error: $1${NC}"
    cleanup_and_exit 1
}

# Cleanup function
cleanup_and_exit() {
    rm -f "$LOCK_FILE"
    exit ${1:-0}
}

# Check if script is already running
check_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local pid=$(cat "$LOCK_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            handle_error "Update service is already running (PID: $pid)"
        else
            rm -f "$LOCK_FILE"
        fi
    fi
    echo $$ > "$LOCK_FILE"
}

# Update pacman packages
update_pacman() {
    log_message "Starting pacman update..."
    echo -e "${BLUE}Updating official repositories (pacman)...${NC}"

    if pacman -Syu --noconfirm; then
        log_message "Pacman update completed successfully"
        echo -e "${GREEN}✓ Pacman update completed${NC}"
    else
        handle_error "Pacman update failed"
    fi
}

# Update AUR packages with yay
update_aur() {
    log_message "Starting AUR update with yay..."
    echo -e "${BLUE}Updating AUR packages (yay)...${NC}"

    # Check if yay is installed (should be pre-installed on CachyOS)
    if ! command -v yay &> /dev/null; then
        log_message "WARNING: yay not found, skipping AUR updates"
        echo -e "${YELLOW}⚠ yay not installed, skipping AUR updates${NC}"
        return 0
    fi

    # Get the real user with detailed logging
    local real_user="$USER_NAME"
    log_message "Initial user detection result: '$real_user'"
    log_message "SUDO_USER environment: '$SUDO_USER'"
    log_message "Current working directory: '$(pwd)'"

    # Additional validation and cleaning
    if [[ -z "$real_user" || "$real_user" == "." || "$real_user" == ".." || "$real_user" == "root" ]]; then
        log_message "WARNING: Invalid or empty user detected ('$real_user'), attempting manual detection"

        # Try one more manual method
        real_user=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 && $7 ~ /(bash|zsh|fish|sh)$/ {print $1; exit}')
        log_message "Manual detection result: '$real_user'"

        if [[ -z "$real_user" || "$real_user" == "." || "$real_user" == ".." || "$real_user" == "root" ]]; then
            log_message "WARNING: Cannot determine valid user for yay, skipping AUR updates"
            echo -e "${YELLOW}⚠ Cannot determine valid user for yay, skipping AUR updates${NC}"
            return 0
        fi
    fi

    # Final validation
    if ! id "$real_user" &>/dev/null; then
        log_message "WARNING: User '$real_user' does not exist, skipping AUR updates"
        echo -e "${YELLOW}⚠ User '$real_user' does not exist, skipping AUR updates${NC}"
        return 0
    fi

    local user_home="/home/$real_user"
    if [[ ! -d "$user_home" ]]; then
        log_message "WARNING: Home directory '$user_home' not found, skipping AUR updates"
        echo -e "${YELLOW}⚠ Home directory '$user_home' not found, skipping AUR updates${NC}"
        return 0
    fi

    # Check if sudo is configured for passwordless package management
    log_message "Checking sudo configuration for user '$real_user'"
    if ! sudo -u "$real_user" -n sudo -l | grep -q "pacman\|yay\|NOPASSWD.*ALL" 2>/dev/null; then
        log_message "WARNING: User '$real_user' doesn't have passwordless sudo for package management"
        echo -e "${YELLOW}⚠ Passwordless sudo not configured for user '$real_user'${NC}"
        echo -e "${YELLOW}  Please run: sudo visudo -f /etc/sudoers.d/cachyos-update${NC}"
        echo -e "${YELLOW}  And add: $real_user ALL=(ALL) NOPASSWD: /usr/bin/pacman, /usr/bin/yay${NC}"
        return 0
    fi

    # Run yay as the actual user with environment setup
    log_message "Running yay as user: '$real_user' with home: '$user_home'"
    echo -e "${BLUE}Running yay as user: $real_user${NC}"

    # First try: AUR-only update (safer approach)
    log_message "Attempting AUR-only update first"
    if sudo -u "$real_user" -H bash -c "export HOME='$user_home' && cd '$user_home' && yay -Sua --noconfirm --needed" 2>&1 | tee -a "$LOG_FILE"; then
        local exit_code=${PIPESTATUS[0]}
        if [[ $exit_code -eq 0 ]]; then
            log_message "AUR-only update completed successfully"
            echo -e "${GREEN}✓ AUR-only update completed${NC}"
            return 0
        else
            log_message "AUR-only update completed with exit code $exit_code"
        fi
    fi

    # Second try: Full yay update if AUR-only had issues
    log_message "Attempting full yay update"
    if sudo -u "$real_user" -H bash -c "export HOME='$user_home' && cd '$user_home' && yay -Syu --noconfirm --needed --aur" 2>&1 | tee -a "$LOG_FILE"; then
        local exit_code=${PIPESTATUS[0]}
        if [[ $exit_code -eq 0 ]]; then
            log_message "Full AUR update completed successfully"
            echo -e "${GREEN}✓ Full AUR update completed${NC}"
        else
            log_message "WARNING: Full AUR update completed with exit code $exit_code"
            echo -e "${YELLOW}⚠ AUR update completed with warnings (exit code: $exit_code)${NC}"
        fi
    else
        local exit_code=$?
        log_message "ERROR: AUR update failed with exit code $exit_code"
        echo -e "${YELLOW}⚠ AUR update failed (exit code: $exit_code)${NC}"
    fi
}

# Update Flatpak packages
update_flatpak() {
    log_message "Starting Flatpak update..."
    echo -e "${BLUE}Updating Flatpak packages...${NC}"

    # Check if Flatpak is installed
    if ! command -v flatpak &> /dev/null; then
        log_message "WARNING: Flatpak not found, skipping Flatpak updates"
        echo -e "${YELLOW}⚠ Flatpak not installed, skipping Flatpak updates${NC}"
        return 0
    fi

    # Get the user (same detection as AUR updates)
    local real_user="$USER_NAME"
    if [[ -z "$real_user" || "$real_user" == "." || "$real_user" == ".." || "$real_user" == "root" ]]; then
        real_user=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 && $7 ~ /(bash|zsh|fish|sh)$/ {print $1; exit}')
    fi

    if [[ -z "$real_user" || "$real_user" == "." || "$real_user" == ".." || "$real_user" == "root" ]]; then
        log_message "WARNING: Cannot determine user for Flatpak, trying system-wide updates"
        echo -e "${YELLOW}⚠ Cannot determine user, trying system-wide Flatpak updates${NC}"

        # Try system-wide Flatpak update as fallback
        if flatpak update --system -y 2>&1 | tee -a "$LOG_FILE"; then
            log_message "System-wide Flatpak update completed"
            echo -e "${GREEN}✓ System-wide Flatpak update completed${NC}"
        else
            log_message "WARNING: System-wide Flatpak update had issues"
            echo -e "${YELLOW}⚠ System-wide Flatpak update had issues${NC}"
        fi
        return 0
    fi

    local user_home="/home/$real_user"
    log_message "Running Flatpak updates as user: '$real_user'"
    echo -e "${BLUE}Running Flatpak as user: $real_user${NC}"

    # Update user Flatpak packages
    if sudo -u "$real_user" -H bash -c "export HOME='$user_home' && cd '$user_home' && flatpak update --user -y" 2>&1 | tee -a "$LOG_FILE"; then
        log_message "User Flatpak update completed successfully"
        echo -e "${GREEN}✓ User Flatpak update completed${NC}"
    else
        log_message "WARNING: User Flatpak update had issues, trying system-wide"
        echo -e "${YELLOW}⚠ User Flatpak update had issues, trying system-wide${NC}"

        # Fallback to system-wide if user update fails
        if flatpak update --system -y 2>&1 | tee -a "$LOG_FILE"; then
            log_message "System-wide Flatpak update completed"
            echo -e "${GREEN}✓ System-wide Flatpak update completed${NC}"
        else
            log_message "WARNING: System-wide Flatpak update also had issues"
            echo -e "${YELLOW}⚠ System-wide Flatpak update also had issues${NC}"
        fi
    fi

    # Clean up unused Flatpak runtimes (try both user and system)
    log_message "Cleaning up unused Flatpak runtimes..."

    # User cleanup
    if [[ -n "$real_user" && "$real_user" != "root" ]]; then
        sudo -u "$real_user" -H bash -c "export HOME='$user_home' && flatpak uninstall --user --unused -y" 2>&1 | tee -a "$LOG_FILE"
    fi

    # System cleanup
    if flatpak uninstall --system --unused -y 2>&1 | tee -a "$LOG_FILE"; then
        log_message "Flatpak cleanup completed"
        echo -e "${GREEN}✓ Flatpak cleanup completed${NC}"
    fi
}

# Clean package cache
cleanup_cache() {
    log_message "Cleaning package caches..."
    echo -e "${BLUE}Cleaning package caches...${NC}"

    # Clean pacman cache (keep last 3 versions)
    if command -v paccache &> /dev/null; then
        if paccache -rk3; then
            log_message "Pacman cache cleaned"
        fi
    else
        log_message "WARNING: paccache not found, skipping pacman cache cleanup"
    fi

    # Clean yay cache if available
    if command -v yay &> /dev/null && [[ -n "$USER_NAME" && "$USER_NAME" != "root" ]]; then
        sudo -u "$USER_NAME" yay -Sc --noconfirm
        log_message "Yay cache cleaned"
    fi

    echo -e "${GREEN}✓ Cache cleanup completed${NC}"
}

# Main update function
main() {
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        handle_error "This script must be run as root (use sudo)"
    fi

    # Setup
    check_lock
    log_message "=== Starting CachyOS update service ==="
    echo -e "${GREEN}Starting CachyOS update service...${NC}"

    # Create log file if it doesn't exist
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"

    # Perform updates
    update_pacman
    update_aur
    update_flatpak
    cleanup_cache

    # Finish
    log_message "=== Update service completed successfully ==="
    echo -e "${GREEN}All updates completed successfully!${NC}"

    # Check if reboot is needed
    if [[ -f /var/run/reboot-required ]]; then
        log_message "System reboot recommended"
        echo -e "${YELLOW}⚠ System reboot recommended${NC}"
    fi

    cleanup_and_exit 0
}

# Handle signals
trap 'handle_error "Script interrupted"' SIGINT SIGTERM

# Run main function
main "$@"
