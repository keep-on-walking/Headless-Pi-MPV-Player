# 🎬 Headless Pi MPV Player

A powerful video player system for Raspberry Pi with web interface, Node-RED API control, and full headless operation support. Works with or without HDMI display connected!

![Version](https://img.shields.io/badge/version-1.0.0-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Platform](https://img.shields.io/badge/platform-Raspberry%20Pi-red)

## ✨ Features

- **🚀 Headless Operation** - Works perfectly without display connected
- **🎮 Web Interface** - Beautiful dark-themed control panel
- **🔌 Node-RED Integration** - Full HTTP API for automation
- **⚡ Hardware Acceleration** - Optimized MPV playback on Raspberry Pi
- **🎯 Skip Controls** - 30-second skip and custom duration support
- **📁 File Management** - Upload/delete videos via web interface
- **🖥️ HDMI Auto-Detection** - Automatically detects and uses connected display
- **🔊 HDMI Audio** - Audio output through HDMI when connected
- **🌐 Network Control** - Access from any device on your network
- **📱 Responsive Design** - Works on phones, tablets, and desktops

## 🛡️ Fixes Applied (Nov 2024)

This version includes critical fixes for common Raspberry Pi issues:

### ✅ 1080p Resolution Forcing
- **Issue**: 4K displays cause severe performance problems on Raspberry Pi
- **Fix**: Forces 1920x1080@60Hz output mode regardless of display capabilities
- **Result**: Smooth playback even when connected to 4K displays

### ✅ Pause/Resume Fixed
- **Issue**: Videos couldn't be unpaused after pausing
- **Fix**: Proper pause state tracking and IPC command handling
- **Result**: Reliable pause/resume functionality

### ✅ Audio Sync After Seeking
- **Issue**: Audio would disappear when skipping forward/backward
- **Fix**: Audio buffer management and forced resync after seeking
- **Result**: Audio plays correctly after any seek operation

### ✅ Screen Blanking
- **Issue**: Console text visible when no video playing
- **Fix**: Comprehensive screen blanking with multiple fallback methods
- **Result**: Clean black screen when idle

### ✅ HDMI Audio Detection
- **Issue**: No audio through HDMI on Raspberry Pi 4
- **Fix**: Automatic detection of vc4hdmi audio devices
- **Result**: Audio works automatically through HDMI

## 📋 Requirements

- Raspberry Pi (tested on Pi 3, Pi 4)
- Raspberry Pi OS Lite (recommended) or Desktop
- Python 3.7+
- Network connection
- (Optional) HDMI display

## 🚀 Quick Installation

### One-Command Install

```bash
curl -sSL https://raw.githubusercontent.com/keep-on-walking/Headless-Pi-MPV-Player/main/install.sh | bash
```

### Manual Installation

```bash
# Clone the repository
git clone https://github.com/keep-on-walking/Headless-Pi-MPV-Player.git
cd Headless-Pi-MPV-Player

# Run the installer
chmod +x install.sh
./install.sh
```

## 🎯 Usage

### Web Interface

After installation, access the player at:
```
http://[your-pi-ip]:5000
```

### Player Controls

- **Play/Pause/Stop** - Basic playback controls
- **Skip Forward/Back** - 10s, 30s, or custom duration
- **Seek** - Jump to specific position
- **Volume** - Adjust playback volume
- **File Management** - Upload, list, and delete videos

### HDMI Output Selection

The player automatically detects connected HDMI displays. You can also manually select:
- **Auto** - Automatically detect and use available display
- **HDMI-A-1** - Force output to first HDMI port
- **HDMI-A-2** - Force output to second HDMI port (Pi 4)

## 🔌 Node-RED Integration

### API Endpoints

| Method | Endpoint | Description | Payload Example |
|--------|----------|-------------|-----------------|
| POST | `/api/play` | Play video or resume | `{"file": "video.mp4"}` |
| POST | `/api/pause` | Toggle pause/resume | - |
| POST | `/api/stop` | Stop playback | - |
| POST | `/api/skip` | Skip forward/back | `{"seconds": 30}` |
| POST | `/api/seek` | Seek to position | `{"position": 300}` |
| POST | `/api/volume` | Set volume (0-100) | `{"level": 50}` |
| POST | `/api/hdmi` | Set HDMI output | `{"output": "auto"}` |
| GET | `/api/status` | Get player status | - |
| GET | `/api/files` | List media files | - |
| POST | `/api/upload` | Upload video file | multipart/form-data |
| DELETE | `/api/files/{name}` | Delete a video | - |
| GET | `/api/config` | Get configuration | - |
| POST | `/api/config` | Update config | `{"loop": true}` |
| GET | `/api/health` | Health check | - |

### Example Node-RED Flow

```json
[
    {
        "id": "play_video",
        "type": "http request",
        "method": "POST",
        "url": "http://192.168.1.100:5000/api/play",
        "payload": "{\"file\":\"sample.mp4\"}",
        "payloadType": "json"
    },
    {
        "id": "skip_forward",
        "type": "http request",
        "method": "POST",
        "url": "http://192.168.1.100:5000/api/skip",
        "payload": "{\"seconds\":30}",
        "payloadType": "json"
    }
]
```

### Python Example

```python
import requests

# Base API URL
api_base = "http://192.168.1.100:5000/api"

# Play a video
response = requests.post(f"{api_base}/play", 
    json={"file": "video.mp4"})

# Skip forward 30 seconds
response = requests.post(f"{api_base}/skip", 
    json={"seconds": 30})

# Get current status
response = requests.get(f"{api_base}/status")
status = response.json()
print(f"State: {status['state']}")
print(f"Position: {status['position']}s")
```

### cURL Examples

```bash
# Play a video
curl -X POST http://192.168.1.100:5000/api/play \
  -H "Content-Type: application/json" \
  -d '{"file":"video.mp4"}'

# Skip backward 30 seconds
curl -X POST http://192.168.1.100:5000/api/skip \
  -H "Content-Type: application/json" \
  -d '{"seconds":-30}'

# Get status
curl http://192.168.1.100:5000/api/status
```

## 📁 File Structure

```
~/headless-mpv-player/
├── app.py              # Main Flask application
├── mpv_controller.py   # MPV control module
├── requirements.txt    # Python dependencies
├── install.sh         # Installation script
├── uninstall.sh       # Uninstallation script
├── static/            # Web interface assets
│   ├── style.css      # Dark theme styles
│   └── app.js         # Client-side JavaScript
├── templates/         # HTML templates
│   └── index.html     # Web interface
└── venv/             # Python virtual environment

~/videos/              # Default media directory
~/headless-mpv-config.json  # Configuration file
```

## ⚙️ Configuration

The configuration file is located at `~/headless-mpv-config.json`:

```json
{
  "media_dir": "/home/pi/videos",
  "max_upload_size": 2147483648,
  "volume": 100,
  "loop": false,
  "hardware_accel": true,
  "hdmi_output": "auto",
  "audio_in_headless": true,
  "port": 5000
}
```

### Configuration Options

- `media_dir` - Directory for video files
- `max_upload_size` - Maximum upload file size in bytes (default: 2GB)
- `volume` - Default volume level (0-100)
- `loop` - Loop video playback
- `hardware_accel` - Enable hardware acceleration
- `hdmi_output` - HDMI output selection (auto/HDMI-A-1/HDMI-A-2)
- `audio_in_headless` - Output audio even without display
- `port` - Web server port

## 🛠️ Service Management

```bash
# Start service
sudo systemctl start headless-mpv-player

# Stop service
sudo systemctl stop headless-mpv-player

# Restart service
sudo systemctl restart headless-mpv-player

# Check status
sudo systemctl status headless-mpv-player

# View logs
sudo journalctl -u headless-mpv-player -f

# Enable auto-start on boot
sudo systemctl enable headless-mpv-player

# Disable auto-start
sudo systemctl disable headless-mpv-player
```

## 🎥 Supported Video Formats

- MP4, AVI, MKV, MOV
- WMV, FLV, WebM, M4V
- MPG, MPEG, 3GP, OGV

## 🔧 Troubleshooting

### No Video Playback
- Ensure video files are in `~/videos` directory
- Check file permissions: `chmod 644 ~/videos/*.mp4`
- Verify MPV is installed: `mpv --version`

### No Audio Through HDMI
- Check TV/monitor volume
- Ensure HDMI cable supports audio
- Restart the service after connecting HDMI

### Web Interface Not Accessible
- Check firewall: `sudo ufw allow 5000`
- Verify service is running: `systemctl status headless-mpv-player`
- Check network connection

### Videos Won't Upload
- Check disk space: `df -h`
- Verify upload size limit in config
- Ensure write permissions on media directory

### Service Won't Start
```bash
# Check detailed error messages
sudo journalctl -u headless-mpv-player -n 50

# Test manual start
cd ~/headless-mpv-player
source venv/bin/activate
python app.py
```

## 🔄 Updates

To update to the latest version:

```bash
cd ~/headless-mpv-player
git pull
sudo systemctl restart headless-mpv-player
```

## 🗑️ Uninstallation

To completely remove the player:

```bash
~/headless-mpv-player/uninstall.sh
```

## 📝 License

MIT License - See LICENSE file for details

## 🤝 Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

## 👥 Support

For issues, questions, or suggestions:
- Create an issue on [GitHub](https://github.com/keep-on-walking/Headless-Pi-MPV-Player/issues)
- Check existing issues for solutions

## 🙏 Credits

Built with:
- [MPV](https://mpv.io/) - Video player
- [Flask](https://flask.palletsprojects.com/) - Web framework
- [DRM/KMS](https://en.wikipedia.org/wiki/Direct_Rendering_Manager) - Hardware acceleration

## 📊 System Requirements

### Minimum
- Raspberry Pi 3
- 1GB RAM
- 8GB SD card
- Network connection

### Recommended
- Raspberry Pi 4
- 2GB+ RAM
- 16GB+ SD card
- Ethernet connection

---

**Made with ❤️ for Raspberry Pi enthusiasts**
