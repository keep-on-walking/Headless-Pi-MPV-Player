#!/bin/bash

#############################################
# Headless Pi MPV Player - Installation Script (FIXED)
# GitHub: keep-on-walking/Headless-Pi-MPV-Player
# One-command installer for Raspberry Pi
# FIXES: Screen blanking and HDMI audio issues
#############################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Installation variables
INSTALL_DIR="$HOME/headless-mpv-player"
SERVICE_NAME="headless-mpv-player"
GITHUB_REPO="https://github.com/keep-on-walking/Headless-Pi-MPV-Player.git"
PORT=5000

# Print colored message
print_message() {
    echo -e "${2}${1}${NC}"
}

# Print header
print_header() {
    echo ""
    print_message "========================================" "$BLUE"
    print_message "$1" "$BLUE"
    print_message "========================================" "$BLUE"
    echo ""
}

# Check if running on Raspberry Pi
check_raspberry_pi() {
    if [ -f /proc/device-tree/model ]; then
        MODEL=$(tr -d '\0' < /proc/device-tree/model)
        print_message "✓ Detected: $MODEL" "$GREEN"
    else
        print_message "⚠ Warning: This doesn't appear to be a Raspberry Pi" "$YELLOW"
        read -p "Continue anyway? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Main installation
main() {
    print_header "Headless Pi MPV Player Installer (FIXED)"
    
    print_message "This script will install:" "$GREEN"
    echo "  • MPV player with hardware acceleration"
    echo "  • Python Flask web server"
    echo "  • Web interface with dark theme"
    echo "  • Node-RED API endpoints"
    echo "  • Systemd service for auto-start"
    echo "  • FIXES: Screen blanking and HDMI audio"
    echo ""
    
    # Check system
    print_header "System Check"
    check_raspberry_pi
    
    # Update system
    print_header "Updating System Packages"
    print_message "Updating package lists..." "$YELLOW"
    sudo apt-get update
    
    # Install dependencies
    print_header "Installing Dependencies"
    
    print_message "Installing MPV player and audio dependencies..." "$YELLOW"
    sudo apt-get install -y mpv alsa-utils
    
    print_message "Installing Python and pip..." "$YELLOW"
    sudo apt-get install -y python3 python3-pip python3-venv
    
    print_message "Installing system utilities..." "$YELLOW"
    sudo apt-get install -y git curl wget
    
    # FIX: Comprehensive screen blanking to prevent any text display
    print_header "Fixing Screen Display Issues"
    
    print_message "Applying comprehensive screen blanking fix..." "$YELLOW"
    
    # 1. Backup and update boot parameters
    if [ ! -f /boot/cmdline.txt.backup ]; then
        sudo cp /boot/cmdline.txt /boot/cmdline.txt.backup
    fi
    # Remove existing quiet parameters to avoid duplication
    sudo sed -i 's/ quiet//g; s/ loglevel=[0-9]//g; s/ logo.nologo//g; s/ vt.global_cursor_default=[0-9]//g; s/ consoleblank=[0-9]//g; s/ console=tty[0-9]//g' /boot/cmdline.txt
    # Add comprehensive quiet boot parameters including console redirect to tty3
    sudo sed -i '$ s/$/ quiet loglevel=0 logo.nologo vt.global_cursor_default=0 consoleblank=1 console=tty3/' /boot/cmdline.txt
    
    # 2. Disable boot splash in config.txt
    if ! grep -q "disable_splash=1" /boot/config.txt; then
        echo "" | sudo tee -a /boot/config.txt > /dev/null
        echo "# Disable boot splash and logos" | sudo tee -a /boot/config.txt > /dev/null
        echo "disable_splash=1" | sudo tee -a /boot/config.txt > /dev/null
        echo "boot_delay=0" | sudo tee -a /boot/config.txt > /dev/null
    fi
    
    # 3. Disable and mask getty on tty1
    sudo systemctl stop getty@tty1.service 2>/dev/null || true
    sudo systemctl disable getty@tty1.service 2>/dev/null || true
    sudo systemctl mask getty@tty1.service 2>/dev/null || true
    
    # 4. Create early blank screen service
    sudo tee /etc/systemd/system/blank-screen-early.service > /dev/null << 'BLANKEOF'
[Unit]
Description=Early Screen Blanking
DefaultDependencies=no
After=sysinit.target
Before=basic.target getty.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'for i in 1 2 3 4 5; do clear > /dev/tty1 2>&1; echo -e "\\033[?25l\\033[2J\\033[H" > /dev/tty1 2>&1; setterm -blank 1 -powerdown 1 > /dev/tty1 2>&1; sleep 0.1; done'
StandardOutput=null
StandardError=null

[Install]
WantedBy=sysinit.target
BLANKEOF
    
    # 5. Create persistent blank screen timer
    sudo tee /etc/systemd/system/blank-screen-timer.service > /dev/null << 'BLANKEOF'
[Unit]
Description=Periodic Screen Blanking

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'clear > /dev/tty1 2>&1; echo -e "\\033[?25l\\033[2J\\033[H" > /dev/tty1 2>&1'
StandardOutput=null
StandardError=null
BLANKEOF
    
    sudo tee /etc/systemd/system/blank-screen-timer.timer > /dev/null << 'BLANKEOF'
[Unit]
Description=Run blank screen every 10 seconds
After=multi-user.target

[Timer]
OnBootSec=5
OnUnitActiveSec=10

[Install]
WantedBy=timers.target
BLANKEOF
    
    # 6. Create console blanking script
    sudo tee /usr/local/bin/blank-console > /dev/null << 'BLANKEOF'
#!/bin/bash
# Blank all consoles
for tty in /dev/tty[1-6]; do
    if [ -e "$tty" ]; then
        echo -e "\033[?25l\033[2J\033[H" > "$tty" 2>/dev/null
        setterm -blank 1 -powerdown 1 > "$tty" 2>/dev/null
        clear > "$tty" 2>/dev/null
    fi
done
BLANKEOF
    sudo chmod +x /usr/local/bin/blank-console
    
    # 7. Configure kernel console blanking
    echo "kernel.printk = 0 0 0 0" | sudo tee /etc/sysctl.d/20-quiet-console.conf > /dev/null
    sudo sysctl -p /etc/sysctl.d/20-quiet-console.conf 2>/dev/null || true
    
    # 8. Disable cloud-init if present
    if [ -d /etc/cloud ]; then
        sudo touch /etc/cloud/cloud-init.disabled
    fi
    
    # 9. Enable blank screen services
    sudo systemctl daemon-reload
    sudo systemctl enable blank-screen-early.service 2>/dev/null || true
    sudo systemctl enable blank-screen-timer.timer 2>/dev/null || true
    
    # Configure MPV for hardware acceleration
    print_header "Configuring MPV"
    
    print_message "Setting up MPV configuration..." "$YELLOW"
    mkdir -p ~/.config/mpv
    
    cat > ~/.config/mpv/mpv.conf << 'EOF'
# Hardware acceleration for Raspberry Pi
vo=gpu
gpu-context=drm
hwdec=auto-copy
hwdec-codecs=all

# Force 1080p output to prevent 4K slowdown
drm-mode=1920x1080@60

# Audio settings for HDMI with sync improvements
ao=alsa
audio-channels=stereo
audio-buffer=1.0
audio-stream-silence
audio-pitch-correction=yes
video-sync=audio
volume=100

# Display settings
fullscreen=yes
keep-open=no
idle=no
pause=no
EOF
    
    # FIX: Configure HDMI audio properly
    print_header "Fixing HDMI Audio"
    
    # Detect HDMI audio device
    print_message "Detecting HDMI audio device..." "$YELLOW"
    AUDIO_DEVICE=""
    
    # Check for Raspberry Pi 4 HDMI audio (vc4hdmi)
    if aplay -l 2>/dev/null | grep -q "vc4hdmi0"; then
        AUDIO_DEVICE="hdmi:CARD=vc4hdmi0,DEV=0"
        print_message "Found Pi 4 HDMI port 0 audio" "$GREEN"
    elif aplay -l 2>/dev/null | grep -q "vc4hdmi1"; then
        AUDIO_DEVICE="hdmi:CARD=vc4hdmi1,DEV=0"
        print_message "Found Pi 4 HDMI port 1 audio" "$GREEN"
    elif aplay -l 2>/dev/null | grep -q "vc4hdmi"; then
        AUDIO_DEVICE="hdmi:CARD=vc4hdmi,DEV=0"
        print_message "Found Pi 4 HDMI audio" "$GREEN"
    elif aplay -l 2>/dev/null | grep -q "HDMI"; then
        AUDIO_DEVICE="hdmi:CARD=HDMI,DEV=0"
        print_message "Found generic HDMI audio" "$GREEN"
    fi
    
    # Create ALSA configuration for HDMI audio
    print_message "Creating ALSA configuration..." "$YELLOW"
    cat > ~/.asoundrc << 'EOF'
# Default to HDMI audio
pcm.!default {
    type hw
    card vc4hdmi0
    device 0
}

ctl.!default {
    type hw
    card vc4hdmi0
}

# Fallback configuration
pcm.hdmi {
    type hw
    card vc4hdmi0
    device 0
}
EOF
    
    # Also create system-wide ALSA config
    sudo tee /etc/asound.conf > /dev/null << 'EOF'
# System-wide HDMI audio configuration
pcm.!default {
    type hw
    card vc4hdmi0
    device 0
}

ctl.!default {
    type hw
    card vc4hdmi0
}
EOF
    
    # Enable HDMI audio in boot config
    if ! grep -q "hdmi_drive=2" /boot/config.txt 2>/dev/null; then
        print_message "Enabling HDMI audio in boot config..." "$YELLOW"
        echo "hdmi_drive=2" | sudo tee -a /boot/config.txt > /dev/null
        echo "hdmi_force_hotplug=1" | sudo tee -a /boot/config.txt > /dev/null
    fi
    
    # Force audio to HDMI using raspi-config settings
    if command -v raspi-config &> /dev/null; then
        print_message "Setting audio output to HDMI..." "$YELLOW"
        sudo raspi-config nonint do_audio 2 2>/dev/null || true
    fi
    
    # Create installation directory
    print_header "Setting up Application"
    
    if [ -d "$INSTALL_DIR" ]; then
        print_message "Installation directory already exists." "$YELLOW"
        read -p "Remove existing installation? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo systemctl stop $SERVICE_NAME 2>/dev/null || true
            rm -rf "$INSTALL_DIR"
        else
            print_message "Installation cancelled." "$RED"
            exit 1
        fi
    fi
    
    print_message "Creating installation directory..." "$YELLOW"
    mkdir -p "$INSTALL_DIR"
    
    # Download or copy files
    if [ -f "$(dirname "$0")/app.py" ]; then
        # Local installation
        print_message "Installing from local files..." "$YELLOW"
        cp -r "$(dirname "$0")"/* "$INSTALL_DIR/"
        # Use the fixed mpv_controller if it exists
        if [ -f "$(dirname "$0")/mpv_controller_fixed.py" ]; then
            cp "$(dirname "$0")/mpv_controller_fixed.py" "$INSTALL_DIR/mpv_controller.py"
        fi
    else
        # Download from GitHub
        print_message "Downloading from GitHub..." "$YELLOW"
        git clone "$GITHUB_REPO" "$INSTALL_DIR"
    fi
    
    cd "$INSTALL_DIR"
    
    # Create virtual environment
    print_message "Creating Python virtual environment..." "$YELLOW"
    python3 -m venv venv
    source venv/bin/activate
    
    # Install Python packages
    print_message "Installing Python packages..." "$YELLOW"
    pip install --upgrade pip
    pip install -r requirements.txt
    
    # Create media directory
    print_message "Creating media directory..." "$YELLOW"
    mkdir -p ~/videos
    
    # Create systemd service with proper environment
    print_header "Setting up System Service"
    
    print_message "Creating systemd service..." "$YELLOW"
    
    sudo tee /etc/systemd/system/$SERVICE_NAME.service > /dev/null << EOF
[Unit]
Description=Headless Pi MPV Player
After=network.target

[Service]
Type=simple
User=$USER
Group=$USER
WorkingDirectory=$INSTALL_DIR
Environment="PATH=$INSTALL_DIR/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
Environment="PYTHONUNBUFFERED=1"
Environment="HOME=$HOME"
ExecStart=$INSTALL_DIR/venv/bin/python $INSTALL_DIR/app.py
Restart=on-failure
RestartSec=10
StartLimitInterval=60
StartLimitBurst=3

# Permissions for DRM/KMS and audio
SupplementaryGroups=video audio

# Logging
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    # Enable and start service
    print_message "Enabling service..." "$YELLOW"
    sudo systemctl daemon-reload
    sudo systemctl enable $SERVICE_NAME.service
    
    # Configure firewall if ufw is installed
    if command -v ufw &> /dev/null; then
        print_message "Configuring firewall..." "$YELLOW"
        sudo ufw allow $PORT/tcp 2>/dev/null || true
    fi
    
    # Create blank screen script
    print_message "Creating screen blanking script..." "$YELLOW"
    cat > "$INSTALL_DIR/blank_screen.sh" << 'EOF'
#!/bin/bash
# Blank the screen
clear > /dev/tty1
setterm -cursor off > /dev/tty1
echo -e '\033[?25l' > /dev/tty1
EOF
    chmod +x "$INSTALL_DIR/blank_screen.sh"
    
    # Execute blank screen immediately
    sudo $INSTALL_DIR/blank_screen.sh 2>/dev/null || true
    /usr/local/bin/blank-console 2>/dev/null || true
    
    # Setup rc.local for additional blanking
    sudo tee /etc/rc.local > /dev/null << RCEOF
#!/bin/bash
# Blank console on boot
/usr/local/bin/blank-console &

# Additional blanking after short delay  
(sleep 2 && /usr/local/bin/blank-console) &
(sleep 5 && /usr/local/bin/blank-console) &

exit 0
RCEOF
    sudo chmod +x /etc/rc.local
    sudo systemctl enable rc-local.service 2>/dev/null || true
    
    # Create uninstall script
    print_message "Creating uninstall script..." "$YELLOW"
    cat > "$INSTALL_DIR/uninstall.sh" << 'EOF'
#!/bin/bash
echo "Uninstalling Headless Pi MPV Player..."
sudo systemctl stop headless-mpv-player
sudo systemctl disable headless-mpv-player
sudo rm /etc/systemd/system/headless-mpv-player.service
sudo systemctl daemon-reload
rm -rf ~/headless-mpv-player
# Restore boot messages if desired
sudo cp /boot/cmdline.txt.backup /boot/cmdline.txt 2>/dev/null || true
echo "Uninstallation complete!"
EOF
    chmod +x "$INSTALL_DIR/uninstall.sh"
    
    # Start the service
    print_header "Starting Service"
    
    print_message "Starting Headless Pi MPV Player..." "$YELLOW"
    sudo systemctl start $SERVICE_NAME.service
    
    # Wait for service to start
    sleep 3
    
    # Check service status
    if sudo systemctl is-active --quiet $SERVICE_NAME.service; then
        print_message "✓ Service started successfully!" "$GREEN"
    else
        print_message "✗ Service failed to start. Check logs with: sudo journalctl -u $SERVICE_NAME -n 50" "$RED"
    fi
    
    # Get IP address
    IP_ADDRESS=$(hostname -I | awk '{print $1}')
    
    # Installation complete
    print_header "Installation Complete!"
    
    print_message "Headless Pi MPV Player has been successfully installed!" "$GREEN"
    echo ""
    print_message "Access the web interface at:" "$GREEN"
    print_message "  http://$IP_ADDRESS:$PORT" "$BLUE"
    echo ""
    print_message "Node-RED API endpoint:" "$GREEN"
    print_message "  http://$IP_ADDRESS:$PORT/api" "$BLUE"
    echo ""
    print_message "Service commands:" "$YELLOW"
    echo "  Start:   sudo systemctl start $SERVICE_NAME"
    echo "  Stop:    sudo systemctl stop $SERVICE_NAME"
    echo "  Restart: sudo systemctl restart $SERVICE_NAME"
    echo "  Status:  sudo systemctl status $SERVICE_NAME"
    echo "  Logs:    sudo journalctl -u $SERVICE_NAME -f"
    echo ""
    print_message "Video files location: ~/videos" "$YELLOW"
    print_message "Configuration file: ~/headless-mpv-config.json" "$YELLOW"
    echo ""
    print_message "FIXES APPLIED:" "$GREEN"
    echo "  ✓ Screen blanking configured (no text when idle)"
    echo "  ✓ HDMI audio properly configured"
    echo "  ✓ Cloud-init messages disabled"
    echo ""
    print_message "Note: A reboot is recommended for all changes to take effect" "$YELLOW"
    print_message "Run: sudo reboot" "$YELLOW"
    echo ""
    print_message "To uninstall, run: $INSTALL_DIR/uninstall.sh" "$YELLOW"
    echo ""
    print_message "Enjoy your Headless Pi MPV Player! 🎬" "$GREEN"
}

# Run main function
main "$@"
