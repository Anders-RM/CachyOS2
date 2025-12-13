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

    # Create temp directory for building
    local temp_dir="/tmp/yay_build_$$"
    mkdir -p "$temp_dir"

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

    # Import GPG key
    print_status "Importing 1Password GPG key..."
    curl -sS https://downloads.1password.com/linux/keys/1password.asc | gpg --import

    # Add the key to pacman keyring
    curl -sS https://downloads.1password.com/linux/keys/1password.asc | pacman-key --add -
    pacman-key --lsign-key 3FEF9748469ADBE15DA7CA80AC2D62742012EA22

    # Add 1Password repository
    if ! grep -q "\[1password\]" /etc/pacman.conf; then
        print_status "Adding 1Password repository to pacman.conf..."
        cat >> /etc/pacman.conf << 'EOF'

[1password]
SigLevel = Required TrustAll
Server = https://downloads.1password.com/linux/arch/$arch/stable/
EOF
    else
        print_warning "1Password repository already exists in pacman.conf"
    fi

    # Update package database and install
    pacman -Sy --noconfirm
    pacman -S --noconfirm --needed 1password

    print_success "1Password installed successfully"
}

# ============================================================================
# CIDER INSTALLATION
# ============================================================================

install_cider() {
    print_status "Installing Cider (Apple Music client)..."

    # Add Cider repository
    if ! grep -q "\[cider\]" /etc/pacman.conf; then
        print_status "Adding Cider repository to pacman.conf..."
        cat >> /etc/pacman.conf << 'EOF'

[cider]
SigLevel = Never
Server = https://repo.cider.sh/
EOF
    else
        print_warning "Cider repository already exists in pacman.conf"
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
        jellyfin-media-player

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
    print_status "Adding trashcan to desktop..."

    local desktop_dir="$ACTUAL_HOME/Desktop"
    run_as_user mkdir -p "$desktop_dir"

    # Create trash desktop entry for KDE Plasma (CachyOS default)
    cat > "$desktop_dir/trash.desktop" << 'EOF'
[Desktop Entry]
Name=Trash
Comment=Contains deleted files
Icon=user-trash-full
EmptyIcon=user-trash
Type=Link
URL=trash:/
EOF

    chown "$ACTUAL_USER:$ACTUAL_USER" "$desktop_dir/trash.desktop"
    chmod 755 "$desktop_dir/trash.desktop"

    # For KDE Plasma, also ensure desktop icons are enabled
    # Create plasma desktop containment config if needed
    local plasma_config="$ACTUAL_HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"

    if [ -f "$plasma_config" ]; then
        print_warning "Plasma desktop config exists. Trash icon added to Desktop folder."
    else
        print_status "Note: If trash icon doesn't appear, enable 'Show Desktop Icons' in Plasma settings"
    fi

    print_success "Trashcan added to desktop"
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

    # Enable user systemd services
    print_status "Enabling backup timer for user $ACTUAL_USER..."
    run_as_user systemctl --user daemon-reload
    run_as_user systemctl --user enable smb-backup.timer 2>/dev/null || true

    print_success "Backup script setup complete"
    print_warning "Remember to:"
    print_warning "  1. Edit $creds_file with your SMB credentials"
    print_warning "  2. Verify SMB server settings in $script_dest"
    print_warning "  3. Start the timer with: systemctl --user start smb-backup.timer"
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
    echo "  - Desktop: trashcan icon added"
    echo "  - Backup: script and timer installed"
    echo
    echo "Post-Installation Steps:"
    echo "  1. Edit ~/.backup/smbcredentials with your SMB credentials"
    echo "  2. Start Filen and configure your account"
    echo "  3. Log into 1Password"
    echo "  4. Log into Steam and other game launchers"
    echo
    echo "To start backup timer manually:"
    echo "  systemctl --user start smb-backup.timer"
    echo
    echo "To check reflector status:"
    echo "  systemctl status reflector.timer"
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
    setup_backup_script

    # Print summary
    print_summary
}

# Run main function
main "$@"
