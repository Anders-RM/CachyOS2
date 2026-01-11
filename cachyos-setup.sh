#!/bin/bash

# CachyOS Setup Script (KDE Plasma)
# Installs and configures applications for a complete CachyOS KDE setup
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
    curl -sS https://downloads.1password.com/linux/keys/1password.asc | gpg --batch --yes --import

    # Install 1Password from AUR using yay
    print_status "Installing 1Password from AUR..."
    run_as_user yay -S --noconfirm --needed 1password

    # Add Floorp to custom allowed browsers list
    print_status "Adding Floorp to 1Password custom allowed browsers..."
    mkdir -p /etc/1password
    echo "floorp" > /etc/1password/custom_allowed_browsers
    chown root:root /etc/1password/custom_allowed_browsers
    chmod 755 /etc/1password/custom_allowed_browsers

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

    # Add 1Password to autostart (silent mode)
    print_status "Adding 1Password to autostart (silent)..."
    cat > "$autostart_dir/1password.desktop" << 'EOF'
[Desktop Entry]
Categories=Office;
Comment=Password manager and secure wallet
Exec=/opt/1Password/1password --silent %U
Icon=1password
Name=1Password
StartupNotify=true
StartupWMClass=1Password
Terminal=false
Type=Application
EOF
    chown "$ACTUAL_USER:$ACTUAL_USER" "$autostart_dir/1password.desktop"

    # Add Steam to autostart (silent mode)
    print_status "Adding Steam to autostart (silent)..."
    cat > "$autostart_dir/steam.desktop" << 'EOF'
[Desktop Entry]
Actions=Store;Community;Library;Servers;Screenshots;News;Settings;BigPicture;Friends;
Categories=Network;FileTransfer;Game;
Comment=Application for managing and playing games on Steam
Exec=/usr/bin/steam -silent %U
Icon=steam
Name=Steam
PrefersNonDefaultGPU=true
StartupNotify=true
Terminal=false
Type=Application
X-KDE-RunOnDiscreteGpu=true

[Desktop Action BigPicture]
Exec=steam steam://open/bigpicture
Name=Big Picture

[Desktop Action Community]
Exec=steam steam://url/SteamIDControlPage
Name=Community

[Desktop Action Friends]
Exec=steam steam://open/friends
Name=Friends

[Desktop Action Library]
Exec=steam steam://open/games
Name=Library

[Desktop Action News]
Exec=steam steam://open/news
Name=News

[Desktop Action Screenshots]
Exec=steam steam://open/screenshots
Name=Screenshots

[Desktop Action Servers]
Exec=steam steam://open/servers
Name=Servers

[Desktop Action Settings]
Exec=steam steam://open/settings
Name=Settings

[Desktop Action Store]
Exec=steam steam://store
Name=Store
EOF
    chown "$ACTUAL_USER:$ACTUAL_USER" "$autostart_dir/steam.desktop"

    # Add Budget spreadsheet to autostart
    print_status "Adding Budget spreadsheet to autostart..."
    cat > "$autostart_dir/budget.desktop" << EOF
[Desktop Entry]
Categories=Office;Spreadsheet;
Comment=Open budget spreadsheet
Exec=libreoffice --nologo --calc -o $ACTUAL_HOME/filen/mis/Buget.ods %U
Icon=libreoffice-calc
Name=Budget
StartupNotify=true
StartupWMClass=libreoffice-calc
Terminal=false
Type=Application
EOF
    chown "$ACTUAL_USER:$ACTUAL_USER" "$autostart_dir/budget.desktop"

    # Add Heroic Games Launcher to autostart
    print_status "Adding Heroic Games Launcher to autostart..."
    if [ -f "/usr/share/applications/heroic.desktop" ]; then
        cp /usr/share/applications/heroic.desktop "$autostart_dir/heroic.desktop"
        chown "$ACTUAL_USER:$ACTUAL_USER" "$autostart_dir/heroic.desktop"
    else
        print_warning "Heroic desktop file not found in /usr/share/applications/"
    fi

    # Add Octopi Notifier to autostart
    print_status "Adding Octopi Notifier to autostart..."
    if [ -f "/usr/share/applications/octopi-notifier.desktop" ]; then
        cp /usr/share/applications/octopi-notifier.desktop "$autostart_dir/octopi-notifier.desktop"
        chown "$ACTUAL_USER:$ACTUAL_USER" "$autostart_dir/octopi-notifier.desktop"
    else
        print_warning "Octopi Notifier desktop file not found in /usr/share/applications/"
    fi

    print_success "Autostart configured: Filen, 1Password, Steam, Budget, Heroic, Octopi"
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
    systemctl enable reflector.service

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
# KDE PLASMA DESKTOP CONFIGURATION
# ============================================================================

configure_kde_plasma() {
    print_status "Configuring KDE Plasma desktop settings..."

    local kde_config="$ACTUAL_HOME/.config"

    # -------------------------------------------------------------------------
    # Task Manager Favorites (Taskbar pinned apps)
    # -------------------------------------------------------------------------
    print_status "Configuring taskbar favorites (Floorp, Konsole)..."

    # Configure Plasma Shell favorites for task manager
    cat > "$kde_config/plasma-org.kde.plasma.desktop-appletsrc" << 'EOF'
[ActionPlugins][0]
RightButton;NoModifier=org.kde.contextmenu

[Containments][1]
activityId=
formfactor=2
immutability=1
lastScreen=0
location=4
plugin=org.kde.panel
wallpaperplugin=org.kde.image

[Containments][1][Applets][2]
immutability=1
plugin=org.kde.plasma.kickoff

[Containments][1][Applets][3]
immutability=1
plugin=org.kde.plasma.icontasks

[Containments][1][Applets][3][Configuration][General]
launchers=preferred://browser,applications:org.kde.konsole.desktop

[Containments][1][Applets][4]
immutability=1
plugin=org.kde.plasma.marginsseparator

[Containments][1][Applets][5]
immutability=1
plugin=org.kde.plasma.systemtray

[Containments][1][Applets][6]
immutability=1
plugin=org.kde.plasma.digitalclock

[Containments][1][General]
AppletOrder=2;3;4;5;6;
EOF
    chown "$ACTUAL_USER:$ACTUAL_USER" "$kde_config/plasma-org.kde.plasma.desktop-appletsrc"

    # -------------------------------------------------------------------------
    # Global Theme - Breeze Dark
    # -------------------------------------------------------------------------
    print_status "Setting Breeze Dark as global theme..."
    run_as_user plasma-apply-lookandfeel -a org.kde.breezedark.desktop

    # -------------------------------------------------------------------------
    # NumLock on boot
    # -------------------------------------------------------------------------
    print_status "Enabling NumLock on boot..."
    run_as_user mkdir -p "$kde_config"
    cat > "$kde_config/kcminputrc" << 'EOF'
[Keyboard]
NumLock=0
EOF
    chown "$ACTUAL_USER:$ACTUAL_USER" "$kde_config/kcminputrc"

    # -------------------------------------------------------------------------
    # Power/Idle Settings
    # -------------------------------------------------------------------------
    print_status "Configuring power settings..."
    cat > "$kde_config/powermanagementprofilesrc" << 'EOF'
[AC][DPMSControl]
idleTime=1800
lockBeforeTurnOff=0

[AC][DimDisplay]
idleTime=600000

[AC][HandleButtonEvents]
lidAction=1
powerButtonAction=16
powerDownAction=16

[AC][SuspendSession]
idleTime=3600000
suspendThenHibernate=false
suspendType=1
EOF
    chown "$ACTUAL_USER:$ACTUAL_USER" "$kde_config/powermanagementprofilesrc"

    # -------------------------------------------------------------------------
    # Desktop Icons (Trash on desktop)
    # -------------------------------------------------------------------------
    print_status "Configuring desktop icons..."
    local desktop_folder="$ACTUAL_HOME/Desktop"
    run_as_user mkdir -p "$desktop_folder"

    # Create trash shortcut on desktop
    cat > "$desktop_folder/trash.desktop" << 'EOF'
[Desktop Entry]
Name=Trash
Comment=Contains removed files
Icon=user-trash-full
EmptyIcon=user-trash
Type=Link
URL=trash:/
EOF
    chown "$ACTUAL_USER:$ACTUAL_USER" "$desktop_folder/trash.desktop"

    # -------------------------------------------------------------------------
    # Dolphin (file manager) settings
    # -------------------------------------------------------------------------
    print_status "Configuring Dolphin file manager..."
    cat > "$kde_config/dolphinrc" << 'EOF'
[General]
ShowFullPath=true
ShowFullPathInTitlebar=true

[MainWindow]
MenuBar=Disabled
ToolBarsMovable=Disabled
EOF
    chown "$ACTUAL_USER:$ACTUAL_USER" "$kde_config/dolphinrc"

    print_success "KDE Plasma desktop configuration applied"
    print_warning "Some settings may require logout/login to take effect"
}

# ============================================================================
# GIT CONFIGURATION
# ============================================================================

configure_git() {
    print_status "Configuring Git..."

    local gitconfig="$ACTUAL_HOME/.gitconfig"

    cat > "$gitconfig" << 'EOF'
[user]
    email = usual.dusk6145@fastmail.com
    name = Anders-RM
    signingkey = ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDiDjte+yS0mT30fXpScbgqyLahV/s0cc5TRZs03hcK1
[gpg]
    format = ssh
[gpg "ssh"]
    program = /opt/1Password/op-ssh-sign
[commit]
    gpgsign = true
[url "git@github.com:"]
    insteadOf = git://github.com/
EOF
    chown "$ACTUAL_USER:$ACTUAL_USER" "$gitconfig"

    # Configure SSH to use 1Password agent
    print_status "Configuring SSH for 1Password agent..."
    local sshdir="$ACTUAL_HOME/.ssh"
    local sshconfig="$sshdir/config"

    run_as_user mkdir -p "$sshdir"
    chmod 700 "$sshdir"

    cat > "$sshconfig" << 'EOF'
Host *
    IdentityAgent ~/.1password/agent.sock
EOF
    chown "$ACTUAL_USER:$ACTUAL_USER" "$sshconfig"
    chmod 600 "$sshconfig"

    print_success "Git and SSH configured with 1Password"
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
    echo -e "${GREEN}CachyOS KDE Setup Complete!${NC}"
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
    echo "  - Autostart: Filen, 1Password (silent), Steam (silent), Budget, Heroic, Octopi"
    echo "  - Filen: ~/filen created, desktop link added"
    echo "  - Reflector: daily at 18:00, mirrors from DE/SE/DK, sorted by rate"
    echo "  - Backup: script and timer installed"
    echo "  - Update service: runs every 3 hours (pacman, AUR, Flatpak)"
    echo "  - Git & SSH: 1Password agent, SSH signing, auto-sign commits"
    echo "  - KDE Plasma:"
    echo "      * Global theme: Breeze Dark (including GTK apps)"
    echo "      * Taskbar: Floorp and Konsole pinned"
    echo "      * Desktop: trash icon added"
    echo "      * Power: screen off 30min, suspend 1h"
    echo "      * NumLock: on at boot"
    echo "      * Window decorations: borderless maximized, minimal buttons"
    echo "      * Dolphin: full path in titlebar, menu bar hidden"
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
    echo "Reboot your system to ensure all changes take effect."
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    echo
    echo "============================================================"
    echo "       CachyOS Setup Script (KDE Plasma)"
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
    configure_kde_plasma
    configure_git
    setup_backup_script
    setup_update_service

    # Print summary
    print_summary
}

# Run main function
main "$@"
