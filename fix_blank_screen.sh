#!/bin/bash

echo "==================================="
echo "Permanent Screen Blanking Fix"
echo "==================================="
echo ""

# This script applies multiple methods to ensure screen stays blank

echo "1. Updating boot parameters..."
# Backup cmdline.txt if not already backed up
if [ ! -f /boot/cmdline.txt.backup ]; then
    sudo cp /boot/cmdline.txt /boot/cmdline.txt.backup
fi

# Remove any existing quiet parameters to avoid duplication
sudo sed -i 's/ quiet//g; s/ loglevel=[0-9]//g; s/ logo.nologo//g; s/ vt.global_cursor_default=[0-9]//g; s/ consoleblank=[0-9]//g; s/ console=tty[0-9]//g' /boot/cmdline.txt

# Add comprehensive quiet boot parameters
sudo sed -i '$ s/$/ quiet loglevel=0 logo.nologo vt.global_cursor_default=0 consoleblank=1 console=tty3/' /boot/cmdline.txt

echo "2. Disabling boot messages in config.txt..."
# Add display blanking settings to config.txt
if ! grep -q "disable_splash=1" /boot/config.txt; then
    echo "" | sudo tee -a /boot/config.txt > /dev/null
    echo "# Disable boot splash and logos" | sudo tee -a /boot/config.txt > /dev/null
    echo "disable_splash=1" | sudo tee -a /boot/config.txt > /dev/null
    echo "boot_delay=0" | sudo tee -a /boot/config.txt > /dev/null
fi

echo "3. Disabling getty service on tty1..."
sudo systemctl stop getty@tty1.service
sudo systemctl disable getty@tty1.service
sudo systemctl mask getty@tty1.service

echo "4. Creating early blank screen service..."
# Create systemd service that blanks screen very early
sudo tee /etc/systemd/system/blank-screen-early.service > /dev/null << 'EOF'
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
EOF

echo "5. Creating persistent blank screen timer..."
# Create a timer that keeps blanking the screen periodically
sudo tee /etc/systemd/system/blank-screen-timer.service > /dev/null << 'EOF'
[Unit]
Description=Periodic Screen Blanking

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'clear > /dev/tty1 2>&1; echo -e "\\033[?25l\\033[2J\\033[H" > /dev/tty1 2>&1'
StandardOutput=null
StandardError=null
EOF

sudo tee /etc/systemd/system/blank-screen-timer.timer > /dev/null << 'EOF'
[Unit]
Description=Run blank screen every 10 seconds
After=multi-user.target

[Timer]
OnBootSec=5
OnUnitActiveSec=10

[Install]
WantedBy=timers.target
EOF

echo "6. Creating console blanking script..."
# Create a comprehensive blanking script
sudo tee /usr/local/bin/blank-console > /dev/null << 'EOF'
#!/bin/bash
# Blank all consoles
for tty in /dev/tty[1-6]; do
    if [ -e "$tty" ]; then
        echo -e "\033[?25l\033[2J\033[H" > "$tty" 2>/dev/null
        setterm -blank 1 -powerdown 1 > "$tty" 2>/dev/null
        clear > "$tty" 2>/dev/null
    fi
done
EOF
sudo chmod +x /usr/local/bin/blank-console

echo "7. Setting up rc.local..."
# Create or update rc.local
sudo tee /etc/rc.local > /dev/null << 'EOF'
#!/bin/bash
# Blank console on boot
/usr/local/bin/blank-console &

# Additional blanking after short delay
(sleep 2 && /usr/local/bin/blank-console) &
(sleep 5 && /usr/local/bin/blank-console) &

exit 0
EOF
sudo chmod +x /etc/rc.local

echo "8. Enabling rc-local service..."
# Enable rc-local service if not enabled
sudo systemctl enable rc-local.service 2>/dev/null || true

echo "9. Configuring kernel console blanking..."
# Set kernel parameters for console blanking
echo "kernel.printk = 0 0 0 0" | sudo tee /etc/sysctl.d/20-quiet-console.conf > /dev/null
sudo sysctl -p /etc/sysctl.d/20-quiet-console.conf 2>/dev/null

echo "10. Disabling cloud-init (if present)..."
if [ -d /etc/cloud ]; then
    sudo touch /etc/cloud/cloud-init.disabled
fi

echo "11. Enabling and starting blank screen services..."
sudo systemctl daemon-reload
sudo systemctl enable blank-screen-early.service
sudo systemctl enable blank-screen-timer.timer
sudo systemctl start blank-screen-early.service
sudo systemctl start blank-screen-timer.timer

echo "12. Running immediate blank..."
/usr/local/bin/blank-console

echo ""
echo "==================================="
echo "Screen blanking fix complete!"
echo "==================================="
echo ""
echo "The screen should now stay blank after reboot."
echo "Multiple layers of blanking have been applied:"
echo "  ✓ Boot parameters updated (quiet, loglevel=0)"
echo "  ✓ Console redirected to tty3"
echo "  ✓ Getty disabled on tty1"
echo "  ✓ Early blanking service installed"
echo "  ✓ Periodic blanking timer enabled"
echo "  ✓ Kernel console output disabled"
echo ""
echo "Please reboot to verify: sudo reboot"
echo ""
