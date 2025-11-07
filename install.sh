#!/bin/bash

#############################################
# Headless Pi MPV Player - Installation Script
# GitHub: keep-on-walking/Headless-Pi-MPV-Player
# One-command installer for Raspberry Pi
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
    print_header "Headless Pi MPV Player Installer"
    
    print_message "This script will install:" "$GREEN"
    echo "  • MPV player with hardware acceleration"
    echo "  • Python Flask web server"
    echo "  • Web interface with dark theme"
    echo "  • Node-RED API endpoints"
    echo "  • Systemd service for auto-start"
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
    
    print_message "Installing MPV player..." "$YELLOW"
    sudo apt-get install -y mpv
    
    print_message "Installing Python and pip..." "$YELLOW"
    sudo apt-get install -y python3 python3-pip python3-venv
    
    print_message "Installing system utilities..." "$YELLOW"
    sudo apt-get install -y git curl wget
    
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

# Audio settings
ao=alsa
audio-device=alsa/default:CARD=vc4hdmi
audio-channels=stereo
volume=100

# Display settings
fullscreen=yes
keep-open=no
idle=no
EOF
    
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
    if [ -d "$(dirname "$0")/app.py" ]; then
        # Local installation
        print_message "Installing from local files..." "$YELLOW"
        cp -r "$(dirname "$0")"/* "$INSTALL_DIR/"
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
    
    # Configure audio for HDMI
    print_header "Configuring Audio"
    
    print_message "Setting up HDMI audio..." "$YELLOW"
    
    # Create ALSA configuration
    cat > ~/.asoundrc << 'EOF'
pcm.!default {
    type hw
    card vc4hdmi
}

ctl.!default {
    type hw
    card vc4hdmi
}
EOF
    
    # Enable audio in config.txt
    if ! grep -q "hdmi_drive=2" /boot/config.txt 2>/dev/null; then
        print_message "Enabling HDMI audio in boot config..." "$YELLOW"
        echo "hdmi_drive=2" | sudo tee -a /boot/config.txt > /dev/null
    fi
    
    # Create systemd service
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
Environment="DISPLAY="
ExecStart=$INSTALL_DIR/venv/bin/python $INSTALL_DIR/app.py
Restart=always
RestartSec=5

# Permissions for DRM/KMS
SupplementaryGroups=video audio

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
    print_message "To uninstall, run: $INSTALL_DIR/uninstall.sh" "$YELLOW"
    echo ""
    print_message "Enjoy your Headless Pi MPV Player! 🎬" "$GREEN"
}

# Run main function
main "$@"
