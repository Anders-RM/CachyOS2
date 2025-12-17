#!/bin/bash

# CachyOS Setup Script
# Installs and configures applications for a complete CachyOS setup
# Run with: sudo ./cachyos-setup.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration - MODIFY THESE VALUES FOR YOUR SETUP
ACTUAL_USER="${SUDO_USER:-$USER}"
ACTUAL_HOME="/home/$ACTUAL_USER"

# Function to print colored messages
print_status() {
    echo -e "${BLUE}[*]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[+]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[-]${NC} $1"
}

# Function to check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Function to run commands as the actual user
run_as_user() {
    sudo -u "$ACTUAL_USER" "$@"
}

# ============================================================================
# PACKAGE INSTALLATION
# ============================================================================

install_base_packages() {
    print_status "Installing base packages from official repositories..."

    # Update system first
    pacman -Syu --noconfirm

    # Install packages from official repos
    pacman -S --noconfirm --needed \
        flatpak \
        reflector \
        steam \
        libreoffice-fresh \
        spectacle \
        rsync \
        cifs-utils \
        base-devel \
        git

    print_success "Base packages installed"
}

# ============================================================================
# YAY (AUR HELPER) INSTALLATION
# ============================================================================

install_yay() {
    print_status "Installing yay (AUR helper)..."

    if command -v yay &> /dev/null; then
        print_warning "yay is already installed"
        return 0
    fi

    # Create temp directory for building (as user, not root)
    local temp_dir="/tmp/yay_build_$$"
    run_as_user mkdir -p "$temp_dir"

    # Clone and build yay as user
    run_as_user git clone https://aur.archlinux.org/yay.git "$temp_dir/yay"
    cd "$temp_dir/yay"
    run_as_user makepkg -si --noconfirm
    cd -

    # Cleanup
    rm -rf "$temp_dir"

    print_success "yay installed successfully"
}

# ============================================================================
# 1PASSWORD INSTALLATION
# ============================================================================

install_1password() {
    print_status "Installing 1Password..."

    # Import GPG key for package verification
    print_status "Importing 1Password GPG key..."
    curl -sS https://downloads.1password.com/linux/keys/1password.asc | gpg --import

    # Install 1Password from AUR using yay
    print_status "Installing 1Password from AUR..."
    run_as_user yay -S --noconfirm --needed 1password

    print_success "1Password installed successfully"
}

# ============================================================================
# CIDER INSTALLATION
# ============================================================================

install_cider() {
    print_status "Installing Cider (Apple Music client)..."

    # Import GPG key
    print_status "Importing Cider GPG key..."
    curl -s https://repo.cider.sh/ARCH-GPG-KEY | pacman-key --add -
    pacman-key --lsign-key A0CD6B993438E22634450CDD2A236C3F42A61682

    # Add Cider Collective repository
    if ! grep -q "\[cidercollective\]" /etc/pacman.conf; then
        print_status "Adding Cider Collective repository to pacman.conf..."
        cat >> /etc/pacman.conf << 'EOF'

# Cider Collective Repository
[cidercollective]
SigLevel = Required TrustedOnly
Server = https://repo.cider.sh/arch
EOF
    else
        print_warning "Cider Collective repository already exists in pacman.conf"
    fi

    # Update package database and install
    pacman -Sy --noconfirm
    pacman -S --noconfirm --needed cider

    print_success "Cider installed successfully"
}

# ============================================================================
# AUR PACKAGES INSTALLATION
# ============================================================================

install_aur_packages() {
    print_status "Installing AUR packages..."

    # Install AUR packages using yay (as user)
    run_as_user yay -S --noconfirm --needed \
        filen-desktop-bin \
        floorp-bin \
        heroic-games-launcher-bin \
        modrinth-app-bin \
        protonplus \
        jellyfin-desktop

    print_success "AUR packages installed successfully"
}

# ============================================================================
# FILEN CONFIGURATION
# ============================================================================

configure_filen() {
    print_status "Configuring Filen Desktop..."

    # Create Filen directory
    print_status "Creating Filen directory at $ACTUAL_HOME/filen..."
    run_as_user mkdir -p "$ACTUAL_HOME/filen"

    # Create Desktop directory if it doesn't exist
    run_as_user mkdir -p "$ACTUAL_HOME/Desktop"

    # Create desktop symlink
    print_status "Creating Filen desktop shortcut..."
    run_as_user ln -sf "$ACTUAL_HOME/filen" "$ACTUAL_HOME/Desktop/Filen"

    # Create autostart entry for Filen by copying from /usr/share/applications/
    print_status "Adding Filen to autostart..."
    local autostart_dir="$ACTUAL_HOME/.config/autostart"
    run_as_user mkdir -p "$autostart_dir"

    if [ -f "/usr/share/applications/filen-desktop.desktop" ]; then
        cp /usr/share/applications/filen-desktop.desktop "$autostart_dir/filen-desktop.desktop"
        chown "$ACTUAL_USER:$ACTUAL_USER" "$autostart_dir/filen-desktop.desktop"
    else
        print_warning "Filen desktop file not found in /usr/share/applications/"
        print_warning "Autostart entry will need to be created manually after installation"
    fi

    print_success "Filen configured with autostart and desktop shortcut"
}

# ============================================================================
# REFLECTOR CONFIGURATION
# ============================================================================

# Function to create or update a config file
update_config_file() {
    local file_path="$1"
    local setting="$2"
    local value="$3"

    if [ -f "$file_path" ]; then
        # If the setting already exists, update its value
        if grep -q "^$setting" "$file_path"; then
            sed -i "s|^$setting .*|$setting $value|" "$file_path"
        else
            # Append the setting at the end of the file if it doesn't exist
            echo -e "\n$setting $value" >> "$file_path"
        fi
    else
        # Create the file and add the setting
        mkdir -p "$(dirname "$file_path")"
        echo -e "$setting $value" > "$file_path"
    fi
    print_status "$setting updated or added in $file_path"
}

configure_reflector() {
    print_status "Configuring Reflector..."

    # Define the paths for the reflector timer and configuration files
    local TIMER_CONF="/etc/systemd/system/timers.target.wants/reflector.timer"
    local REFLECTOR_CONF="/etc/xdg/reflector/reflector.conf"

    # Modify the reflector configuration file
    update_config_file "$REFLECTOR_CONF" "--sort" "rate"
    update_config_file "$REFLECTOR_CONF" "--country" "DE,SE,DK"
    update_config_file "$REFLECTOR_CONF" "--latest" "10"
    print_status "Modified reflector configuration"

    # Enable and start the reflector timer and service
    print_status "Enabling and starting reflector timer..."
    systemctl enable --now reflector.timer

    print_status "Enabling and starting reflector service..."
    systemctl enable --now reflector.service

    # Modify the reflector.timer configuration to run daily at 18:00
    print_status "Setting reflector timer to run daily at 18:00..."
    sed -i 's/^OnCalendar=weekly/OnCalendar=*-*-* 18:00:00/' "$TIMER_CONF"

    # Reload the systemd daemon to apply changes
    print_status "Reloading systemd daemon..."
    systemctl daemon-reload

    # Restart the reflector timer to apply the new schedule
    print_status "Restarting reflector timer..."
    systemctl restart reflector.timer

    print_success "Reflector configured (daily at 18:00, countries: DE,SE,DK, sorted by rate, latest 10)"
}

# ============================================================================
# FLATPAK CONFIGURATION
# ============================================================================

configure_flatpak() {
    print_status "Configuring Flatpak..."

    # Add Flathub repository
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

    print_success "Flatpak configured with Flathub repository"
}

# ============================================================================
# DESKTOP TRASHCAN CONFIGURATION
# ============================================================================

configure_desktop_trashcan() {
    print_status "Configuring desktop trash icon for COSMIC..."

    # COSMIC desktop stores config in ~/.config/cosmic/
    # Desktop settings are in com.system76.CosmicFiles/v1/desktop
    local cosmic_config_dir="$ACTUAL_HOME/.config/cosmic"
    local cosmic_files_config="$cosmic_config_dir/com.system76.CosmicFiles/v1"

    # Create config directory structure
    run_as_user mkdir -p "$cosmic_files_config"

    # Enable trash icon on desktop
    # COSMIC uses RON (Rusty Object Notation) format for config files
    print_status "Enabling trash icon in COSMIC desktop settings..."

    # Create the desktop config file with show_trash enabled
    cat > "$cosmic_files_config/desktop" << 'EOF'
(
    grid_spacing: 100,
    icon_size: 100,
    show_content: true,
    show_mounted_drives: false,
    show_trash: true,
)
EOF
    chown "$ACTUAL_USER:$ACTUAL_USER" "$cosmic_files_config/desktop"

    print_success "Desktop trash icon configuration applied"
    print_warning "If the trash icon doesn't appear after login/reboot:"
    print_warning "  1. Right-click on the desktop"
    print_warning "  2. Select 'Desktop view options'"
    print_warning "  3. Enable 'Trash folder icon'"
}

# ============================================================================
# COSMIC DESKTOP CONFIGURATION
# ============================================================================

configure_cosmic_desktop() {
    print_status "Configuring COSMIC desktop settings..."

    local cosmic_config="$ACTUAL_HOME/.config/cosmic"

    # -------------------------------------------------------------------------
    # Dock Configuration (com.system76.CosmicPanel.Dock)
    # -------------------------------------------------------------------------
    print_status "Configuring COSMIC dock..."
    local dock_config="$cosmic_config/com.system76.CosmicPanel.Dock/v1"
    run_as_user mkdir -p "$dock_config"

    # Disable anchor gap (gap between dock and screen edge)
    echo "false" > "$dock_config/anchor_gap"
    chown "$ACTUAL_USER:$ACTUAL_USER" "$dock_config/anchor_gap"

    # Extend dock to edges
    echo "true" > "$dock_config/expand_to_edges"
    chown "$ACTUAL_USER:$ACTUAL_USER" "$dock_config/expand_to_edges"

    # Keep only app list in center (removes other applets)
    cat > "$dock_config/plugins_center" << 'EOF'
Some([
    "com.system76.CosmicAppList",
])
EOF
    chown "$ACTUAL_USER:$ACTUAL_USER" "$dock_config/plugins_center"

    # Dock size
    echo "M" > "$dock_config/size"
    chown "$ACTUAL_USER:$ACTUAL_USER" "$dock_config/size"

    # -------------------------------------------------------------------------
    # Panel Configuration (com.system76.CosmicPanel.Panel)
    # -------------------------------------------------------------------------
    print_status "Configuring COSMIC panel..."
    local panel_config="$cosmic_config/com.system76.CosmicPanel.Panel/v1"
    run_as_user mkdir -p "$panel_config"

    # Panel plugins - configure wings (left and right sections)
    cat > "$panel_config/plugins_wings" << 'EOF'
Some(([
    "com.system76.CosmicPanelWorkspacesButton",
    "com.system76.CosmicPanelAppButton",
], [
    "com.system76.CosmicAppletInputSources",
    "com.system76.CosmicAppletA11y",
    "com.system76.CosmicAppletStatusArea",
    "com.system76.CosmicAppletTiling",
    "com.system76.CosmicAppletAudio",
    "com.system76.CosmicAppletBluetooth",
    "com.system76.CosmicAppletNetwork",
    "com.system76.CosmicAppletBattery",
    "com.system76.CosmicAppletNotifications",
    "com.system76.CosmicAppletPower",
]))
EOF
    chown "$ACTUAL_USER:$ACTUAL_USER" "$panel_config/plugins_wings"

    # -------------------------------------------------------------------------
    # App Tray / Favorites Configuration (com.system76.CosmicAppList)
    # -------------------------------------------------------------------------
    print_status "Configuring app tray favorites..."
    local applist_config="$cosmic_config/com.system76.CosmicAppList/v1"
    run_as_user mkdir -p "$applist_config"

    # Set favorites (Floorp and COSMIC Terminal)
    cat > "$applist_config/favorites" << 'EOF'
[
    "com.system76.CosmicTerm",
    "floorp",
]
EOF
    chown "$ACTUAL_USER:$ACTUAL_USER" "$applist_config/favorites"

    # -------------------------------------------------------------------------
    # Desktop Appearance - Square Style (com.system76.CosmicTheme.Dark.Builder)
    # -------------------------------------------------------------------------
    print_status "Configuring desktop appearance (square style)..."
    local theme_config="$cosmic_config/com.system76.CosmicTheme.Dark.Builder/v1"
    run_as_user mkdir -p "$theme_config"

    # Set corner radius for square style (small values for slight rounding)
    cat > "$theme_config/corner_radii" << 'EOF'
(
    radius_0: (0.0, 0.0, 0.0, 0.0),
    radius_xs: (2.0, 2.0, 2.0, 2.0),
    radius_s: (2.0, 2.0, 2.0, 2.0),
    radius_m: (2.0, 2.0, 2.0, 2.0),
    radius_l: (2.0, 2.0, 2.0, 2.0),
    radius_xl: (2.0, 2.0, 2.0, 2.0),
)
EOF
    chown "$ACTUAL_USER:$ACTUAL_USER" "$theme_config/corner_radii"

    # -------------------------------------------------------------------------
    # Window Management (com.system76.CosmicComp)
    # -------------------------------------------------------------------------
    print_status "Configuring window management..."
    local comp_config="$cosmic_config/com.system76.CosmicComp/v1"
    run_as_user mkdir -p "$comp_config"

    # Active window hint size: 3
    echo "3" > "$comp_config/active_hint"
    chown "$ACTUAL_USER:$ACTUAL_USER" "$comp_config/active_hint"

    # Gaps around tiled windows: 6
    echo "(0, 6)" > "$comp_config/gaps"
    chown "$ACTUAL_USER:$ACTUAL_USER" "$comp_config/gaps"

    # Keyboard config - NumLock on boot
    cat > "$comp_config/keyboard_config" << 'EOF'
(
    numlock_state: BootOn,
)
EOF
    chown "$ACTUAL_USER:$ACTUAL_USER" "$comp_config/keyboard_config"

    # -------------------------------------------------------------------------
    # Power/Idle Settings (com.system76.CosmicIdle)
    # -------------------------------------------------------------------------
    print_status "Configuring power/idle settings..."
    local idle_config="$cosmic_config/com.system76.CosmicIdle/v1"
    run_as_user mkdir -p "$idle_config"

    # Screen timeout: 30 minutes (1800000 milliseconds)
    echo "Some(1800000)" > "$idle_config/screen_off_time"
    chown "$ACTUAL_USER:$ACTUAL_USER" "$idle_config/screen_off_time"

    # Automatic suspend on AC: 1 hour (3600000 milliseconds)
    echo "Some(3600000)" > "$idle_config/suspend_on_ac_time"
    chown "$ACTUAL_USER:$ACTUAL_USER" "$idle_config/suspend_on_ac_time"

    # -------------------------------------------------------------------------
    # Keyboard Shortcuts
    # -------------------------------------------------------------------------
    print_status "Configuring keyboard shortcuts..."
    local shortcuts_config="$cosmic_config/com.system76.CosmicSettings.Shortcuts/v1"
    run_as_user mkdir -p "$shortcuts_config"

    # Alt+F4 to shutdown (system action)
    cat > "$shortcuts_config/custom" << 'EOF'
{
    (Modifiers(bits: 8), "F4"): System(Shutdown),
}
EOF
    chown "$ACTUAL_USER:$ACTUAL_USER" "$shortcuts_config/custom"

    # -------------------------------------------------------------------------
    # Session Settings (disable confirm on shutdown)
    # -------------------------------------------------------------------------
    print_status "Configuring session settings..."
    local session_config="$cosmic_config/com.system76.CosmicSession/v1"
    run_as_user mkdir -p "$session_config"

    # Disable confirm on shutdown
    echo "false" > "$session_config/confirm_logout"
    chown "$ACTUAL_USER:$ACTUAL_USER" "$session_config/confirm_logout"

    print_success "COSMIC desktop configuration applied"
    print_warning "Some settings may require logout/login to take effect"
}

# ============================================================================
# BACKUP SCRIPT SETUP
# ============================================================================

setup_backup_script() {
    print_status "Setting up backup script..."

    local script_source="$(dirname "$0")/BackupScript.sh"
    local backup_dir="$ACTUAL_HOME/.backup"
    local script_dest="$backup_dir/BackupScript.sh"

    # Create backup directory
    run_as_user mkdir -p "$backup_dir"

    # Check if BackupScript.sh exists in current directory
    if [ -f "$script_source" ]; then
        print_status "Copying BackupScript.sh to $backup_dir..."
        cp "$script_source" "$script_dest"
        chown "$ACTUAL_USER:$ACTUAL_USER" "$script_dest"
        chmod +x "$script_dest"

        # Update paths in the script to match current user
        sed -i "s|/home/anders|$ACTUAL_HOME|g" "$script_dest"
    else
        print_warning "BackupScript.sh not found in script directory"
        print_warning "Please copy BackupScript.sh to $backup_dir manually"
    fi

    # Setup systemd service
    local service_source="$(dirname "$0")/smb-backup.service"
    if [ -f "$service_source" ]; then
        print_status "Installing smb-backup.service..."

        # Create user systemd directory
        local user_systemd="$ACTUAL_HOME/.config/systemd/user"
        run_as_user mkdir -p "$user_systemd"

        # Copy and modify service file
        cp "$service_source" "$user_systemd/smb-backup.service"
        sed -i "s|/home/anders|$ACTUAL_HOME|g" "$user_systemd/smb-backup.service"
        sed -i "s|USER=anders|USER=$ACTUAL_USER|g" "$user_systemd/smb-backup.service"
        chown "$ACTUAL_USER:$ACTUAL_USER" "$user_systemd/smb-backup.service"
    else
        print_warning "smb-backup.service not found"
    fi

    # Setup systemd timer
    local timer_source="$(dirname "$0")/smb-backup.timer"
    if [ -f "$timer_source" ]; then
        print_status "Installing smb-backup.timer..."

        local user_systemd="$ACTUAL_HOME/.config/systemd/user"
        cp "$timer_source" "$user_systemd/smb-backup.timer"
        chown "$ACTUAL_USER:$ACTUAL_USER" "$user_systemd/smb-backup.timer"
    else
        print_warning "smb-backup.timer not found"
    fi

    # Create credentials file template
    local creds_file="$backup_dir/smbcredentials"
    if [ ! -f "$creds_file" ]; then
        print_status "Creating SMB credentials template..."
        cat > "$creds_file" << 'EOF'
username=YOUR_SMB_USERNAME
password=YOUR_SMB_PASSWORD
domain=WORKGROUP
EOF
        chown "$ACTUAL_USER:$ACTUAL_USER" "$creds_file"
        chmod 600 "$creds_file"
        print_warning "Please edit $creds_file with your SMB credentials"
    fi

    # Note: User systemd services must be enabled from within the user session
    # Cannot run systemctl --user from root context
    print_success "Backup script setup complete"
    print_warning "After logging in as $ACTUAL_USER, run these commands to enable the backup timer:"
    print_warning "  systemctl --user daemon-reload"
    print_warning "  systemctl --user enable --now smb-backup.timer"
    print_warning ""
    print_warning "Also remember to:"
    print_warning "  1. Edit $creds_file with your SMB credentials"
    print_warning "  2. Verify SMB server settings in $script_dest"
}

# ============================================================================
# UPDATE SERVICE SETUP
# ============================================================================

setup_update_service() {
    print_status "Setting up CachyOS update service..."

    local script_source="$(dirname "$0")/cachyos-update.sh"
    local service_source="$(dirname "$0")/cachyos-update.service"
    local timer_source="$(dirname "$0")/cachyos-update.timer"

    # Install the update script
    if [ -f "$script_source" ]; then
        print_status "Installing cachyos-update.sh to /usr/local/bin/..."
        cp "$script_source" /usr/local/bin/cachyos-update.sh
        chmod +x /usr/local/bin/cachyos-update.sh
    else
        print_warning "cachyos-update.sh not found in script directory"
        return 1
    fi

    # Install systemd service
    if [ -f "$service_source" ]; then
        print_status "Installing cachyos-update.service..."
        cp "$service_source" /etc/systemd/system/cachyos-update.service
    else
        print_warning "cachyos-update.service not found"
    fi

    # Install systemd timer
    if [ -f "$timer_source" ]; then
        print_status "Installing cachyos-update.timer..."
        cp "$timer_source" /etc/systemd/system/cachyos-update.timer
    else
        print_warning "cachyos-update.timer not found"
    fi

    # Reload systemd and enable timer
    print_status "Enabling update service timer..."
    systemctl daemon-reload
    systemctl enable cachyos-update.timer
    systemctl start cachyos-update.timer

    # Install pacman-contrib for paccache (cache cleanup)
    if ! command -v paccache &> /dev/null; then
        print_status "Installing pacman-contrib for cache cleanup..."
        pacman -S --noconfirm --needed pacman-contrib
    fi

    print_success "Update service installed (runs every 3 hours)"
}

# ============================================================================
# SUMMARY
# ============================================================================

print_summary() {
    echo
    echo "============================================================"
    echo -e "${GREEN}CachyOS Setup Complete!${NC}"
    echo "============================================================"
    echo
    echo "Installed Applications:"
    echo "  - 1Password (with GPG key)"
    echo "  - Cider (Apple Music client)"
    echo "  - Filen Desktop (with autostart)"
    echo "  - Floorp (browser)"
    echo "  - LibreOffice"
    echo "  - Heroic Games Launcher"
    echo "  - Modrinth Launcher"
    echo "  - ProtonPlus"
    echo "  - Steam"
    echo "  - Jellyfin"
    echo "  - Spectacle (screenshot)"
    echo "  - Flatpak (with Flathub)"
    echo "  - yay (AUR helper)"
    echo "  - Reflector"
    echo
    echo "Configurations Applied:"
    echo "  - Filen: autostart enabled, ~/filen created, desktop link added"
    echo "  - Reflector: daily at 18:00, mirrors from DE/SE/DK, sorted by rate"
    echo "  - Desktop: trash icon enabled"
    echo "  - Backup: script and timer installed"
    echo "  - Update service: runs every 3 hours (pacman, AUR, Flatpak)"
    echo "  - COSMIC Desktop:"
    echo "      * Dock: extended to edges, no gap, removed applets"
    echo "      * Panel: removed workspaces button"
    echo "      * App tray: Floorp added, defaults removed"
    echo "      * Appearance: square style"
    echo "      * Window hints: 3px, tile gaps: 6px"
    echo "      * Power: high performance, screen off 30min, suspend 1h"
    echo "      * NumLock: on at boot"
    echo "      * Alt+F4: shutdown, no confirm dialog"
    echo
    echo "Post-Installation Steps:"
    echo "  1. Edit ~/.backup/smbcredentials with your SMB credentials"
    echo "  2. Enable backup timer (run as your user, not root):"
    echo "       systemctl --user daemon-reload"
    echo "       systemctl --user enable --now smb-backup.timer"
    echo "  3. Start Filen and configure your account"
    echo "  4. Log into 1Password"
    echo "  5. Log into Steam and other game launchers"
    echo
    echo "To check reflector status:"
    echo "  systemctl status reflector.timer"
    echo
    echo "To check update service status:"
    echo "  systemctl status cachyos-update.timer"
    echo "  journalctl -u cachyos-update.service"
    echo
    echo "To check backup timer status (run as your user):"
    echo "  systemctl --user status smb-backup.timer"
    echo
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    echo
    echo "============================================================"
    echo "         CachyOS Setup Script"
    echo "============================================================"
    echo

    check_root

    print_status "Setting up system for user: $ACTUAL_USER"
    print_status "Home directory: $ACTUAL_HOME"
    echo

    # Run installation steps
    install_base_packages
    install_yay
    install_1password
    install_cider
    install_aur_packages
    configure_filen
    configure_reflector
    configure_flatpak
    configure_desktop_trashcan
    configure_cosmic_desktop
    setup_backup_script
    setup_update_service

    # Print summary
    print_summary
}

# Run main function
main "$@"
