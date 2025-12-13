#!/bin/bash

# SMB Backup Script for CachyOS
# Backs up files from local directory to SMB share with timestamped folder

# Configuration - MODIFY THESE VALUES FOR YOUR SETUP
LOCAL_SOURCE="/home/anders/filen/"  # Change 'anders' to your username
SMB_SERVER="192.168.3.2"
SMB_SHARE="Anders"
SMB_PATH="smb://${SMB_SERVER}/${SMB_SHARE}"

# Create timestamp for backup folder (YYYY-MM-DD_HH-MM-SS)
TIMESTAMP=$(date +"%Y_%m_%d - %H_%M")
BACKUP_FOLDER="${TIMESTAMP}"

# SMB credentials - For automated backups, use credentials file
CREDENTIALS_FILE="/home/anders/.backup/smbcredentials"  # Change 'anders' to your username

# Check if running in automated mode (no terminal)
if [ ! -t 0 ]; then
    AUTOMATED_MODE=true
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Running in automated mode" >> /home/anders/.backup/backup.log
else
    AUTOMATED_MODE=false
fi

# Handle credentials
if [ -f "$CREDENTIALS_FILE" ]; then
    echo "Using credentials file: $CREDENTIALS_FILE"
else
    if [ "$AUTOMATED_MODE" = true ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: Credentials file not found for automated backup!" >> /home/anders/.backup/backup.log
        echo "Error: Credentials file '$CREDENTIALS_FILE' not found!"
        echo "Please create it with your SMB credentials for automated backups."
        exit 1
    else
        # Interactive mode - prompt for credentials
        read -p "Enter SMB username: " SMB_USER
        read -s -p "Enter SMB password: " SMB_PASS
        echo
    fi
fi

# Create temporary mount point
MOUNT_POINT="/tmp/smb_backup_$$"
mkdir -p "$MOUNT_POINT"

# Function to log messages
log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message"
    if [ "$AUTOMATED_MODE" = true ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" >> /home/anders/.backup/backup.log
    fi
}

# Function to cleanup on exit
cleanup() {
    log_message "Cleaning up..."
    if mountpoint -q "$MOUNT_POINT"; then
        sudo umount "$MOUNT_POINT" 2>/dev/null
    fi
    rmdir "$MOUNT_POINT" 2>/dev/null
    exit $1
}

# Set trap for cleanup
trap 'cleanup 1' INT TERM EXIT

log_message "Starting backup process..."
log_message "Source: $LOCAL_SOURCE"
log_message "Destination: $SMB_PATH/$BACKUP_FOLDER"
log_message "Timestamp: $TIMESTAMP"

# Check if source directory exists
if [ ! -d "$LOCAL_SOURCE" ]; then
    log_message "ERROR: Source directory '$LOCAL_SOURCE' does not exist!"
    exit 1
fi

# Check if source directory has files
if [ -z "$(ls -A "$LOCAL_SOURCE" 2>/dev/null)" ]; then
    log_message "WARNING: Source directory '$LOCAL_SOURCE' is empty!"
    if [ "$AUTOMATED_MODE" = false ]; then
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Backup cancelled."
            exit 0
        fi
    fi
fi

# Check if required tools are installed
if ! command -v rsync &> /dev/null; then
    echo "Error: rsync is not installed. Install with: sudo pacman -S rsync"
    exit 1
fi

if ! command -v mount.cifs &> /dev/null; then
    echo "Error: cifs-utils is not installed. Install with: sudo pacman -S cifs-utils"
    exit 1
fi

# Mount SMB share
log_message "Mounting SMB share..."
if [ -f "$CREDENTIALS_FILE" ]; then
    # Mount using credentials file
    sudo mount -t cifs "//$SMB_SERVER/$SMB_SHARE" "$MOUNT_POINT" -o credentials="$CREDENTIALS_FILE",uid=$(id -u),gid=$(id -g),iocharset=utf8
else
    # Mount using provided credentials (interactive mode only)
    sudo mount -t cifs "//$SMB_SERVER/$SMB_SHARE" "$MOUNT_POINT" -o username="$SMB_USER",password="$SMB_PASS",uid=$(id -u),gid=$(id -g),iocharset=utf8
fi

# Check if mount was successful
if [ $? -ne 0 ]; then
    log_message "ERROR: Failed to mount SMB share!"
    if [ "$AUTOMATED_MODE" = false ]; then
        echo "Please check:"
        echo "- Network connectivity to $SMB_SERVER"
        echo "- SMB credentials"
        echo "- SMB share name '$SMB_SHARE'"
    fi
    exit 1
fi

log_message "SMB share mounted successfully at $MOUNT_POINT"

# Create backup folder on SMB share
BACKUP_PATH="$MOUNT_POINT/$BACKUP_FOLDER"
log_message "Creating backup folder: $BACKUP_FOLDER"
mkdir -p "$BACKUP_PATH"

if [ $? -ne 0 ]; then
    log_message "ERROR: Failed to create backup folder on SMB share!"
    exit 1
fi

# Perform the backup using rsync
log_message "Starting file copy..."
if [ "$AUTOMATED_MODE" = false ]; then
    echo "This may take a while depending on the amount of data..."
    # Use rsync with progress for interactive mode
    rsync -av --progress "$LOCAL_SOURCE" "$BACKUP_PATH/"
else
    # Use rsync without progress for automated mode
    rsync -av "$LOCAL_SOURCE" "$BACKUP_PATH/"
fi

RSYNC_EXIT_CODE=$?

# Check rsync result
if [ $RSYNC_EXIT_CODE -eq 0 ]; then
    log_message "✓ Backup completed successfully!"
    log_message "Files backed up to: $SMB_PATH/$BACKUP_FOLDER"
    
    # Display backup summary
    FILE_COUNT=$(find "$BACKUP_PATH" -type f | wc -l)
    BACKUP_SIZE=$(du -sh "$BACKUP_PATH" | cut -f1)
    log_message "Summary: Files copied: $FILE_COUNT, Total size: $BACKUP_SIZE"
    
    # Send notification in automated mode (if GUI available)
    if [ "$AUTOMATED_MODE" = true ] && command -v notify-send &> /dev/null && [ -n "$DISPLAY" ]; then
        notify-send "Backup Completed" "Successfully backed up $FILE_COUNT files ($BACKUP_SIZE) to SMB share"
    fi
    
else
    log_message "✗ Backup completed with errors (rsync exit code: $RSYNC_EXIT_CODE)"
    
    # Send error notification in automated mode
    if [ "$AUTOMATED_MODE" = true ] && command -v notify-send &> /dev/null && [ -n "$DISPLAY" ]; then
        notify-send "Backup Error" "Backup completed with errors. Check /home/anders/.backup/backup.log"
    fi
fi

# Cleanup will be handled by the trap
trap 'cleanup 0' EXIT

log_message "Backup process finished."
