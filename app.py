#!/usr/bin/env python3
"""
Headless Pi MPV Player - Main Application
Video player with web interface and HTTP API for Raspberry Pi
Designed to work in headless mode and with Node-RED integration
"""

import os
import sys
import json
import time
import logging
import threading
from datetime import datetime
from pathlib import Path
from flask import Flask, request, jsonify, render_template, send_from_directory
from flask_cors import CORS
from werkzeug.utils import secure_filename
from werkzeug.exceptions import RequestEntityTooLarge

# Import our MPV controller
from mpv_controller import MPVController

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# Flask application setup
app = Flask(__name__)
CORS(app)

# Configuration
HOME_DIR = os.path.expanduser('~')
CONFIG_FILE = os.path.join(HOME_DIR, 'headless-mpv-config.json')
DEFAULT_CONFIG = {
    "media_dir": os.path.join(HOME_DIR, "videos"),
    "max_upload_size": 2147483648,  # 2GB in bytes
    "volume": 100,
    "loop": False,
    "hardware_accel": True,
    "hdmi_output": "auto",  # auto, HDMI-A-1, HDMI-A-2
    "audio_in_headless": True,
    "port": 5000
}

# Global variables
config = {}
player = None
start_time = time.time()

def load_config():
    """Load configuration from file"""
    global config
    try:
        if os.path.exists(CONFIG_FILE):
            with open(CONFIG_FILE, 'r') as f:
                loaded_config = json.load(f)
                config = {**DEFAULT_CONFIG, **loaded_config}
        else:
            config = DEFAULT_CONFIG.copy()
            save_config()
    except Exception as e:
        logger.error(f"Error loading config: {e}")
        config = DEFAULT_CONFIG.copy()
    return config

def save_config():
    """Save configuration to file"""
    try:
        with open(CONFIG_FILE, 'w') as f:
            json.dump(config, f, indent=2)
        return True
    except Exception as e:
        logger.error(f"Error saving config: {e}")
        return False

def get_media_files():
    """Get list of media files in the media directory"""
    media_dir = config.get('media_dir', os.path.join(HOME_DIR, 'videos'))
    supported_extensions = ['.mp4', '.avi', '.mkv', '.mov', '.wmv', '.flv', '.webm', 
                          '.m4v', '.mpg', '.mpeg', '.3gp', '.ogv']
    
    files = []
    try:
        Path(media_dir).mkdir(parents=True, exist_ok=True)
        for file in Path(media_dir).iterdir():
            if file.is_file() and file.suffix.lower() in supported_extensions:
                files.append({
                    'name': file.name,
                    'size': file.stat().st_size,
                    'modified': datetime.fromtimestamp(file.stat().st_mtime).isoformat()
                })
    except Exception as e:
        logger.error(f"Error listing media files: {e}")
    
    return sorted(files, key=lambda x: x['name'].lower())

def format_time(seconds):
    """Format seconds to human readable time"""
    hours = int(seconds // 3600)
    minutes = int((seconds % 3600) // 60)
    secs = int(seconds % 60)
    
    if hours > 0:
        return f"{hours:02d}:{minutes:02d}:{secs:02d}"
    else:
        return f"{minutes:02d}:{secs:02d}"

# Configure upload settings
app.config['MAX_CONTENT_LENGTH'] = DEFAULT_CONFIG['max_upload_size']
app.config['UPLOAD_FOLDER'] = DEFAULT_CONFIG['media_dir']

# Web routes
@app.route('/')
def index():
    """Main web interface"""
    return render_template('index.html')

# API routes for Node-RED integration
@app.route('/api/status', methods=['GET'])
def api_status():
    """Get current player status"""
    status = {
        'state': player.get_state(),
        'current_file': os.path.basename(player.current_file) if player.current_file else None,
        'position': player.get_position(),
        'duration': player.get_duration(),
        'position_formatted': format_time(player.get_position()),
        'duration_formatted': format_time(player.get_duration()),
        'volume': player.get_volume(),
        'hostname': os.uname().nodename,
        'hdmi_outputs': player.get_hdmi_outputs(),
        'current_hdmi': player.hdmi_output
    }
    return jsonify(status)

@app.route('/api/play', methods=['POST'])
def api_play():
    """Start playback - can specify file or resume current"""
    try:
        data = request.get_json() or {}
        filename = data.get('file')
        
        if filename:
            # Play specific file
            filepath = os.path.join(config['media_dir'], secure_filename(filename))
            if os.path.exists(filepath):
                success = player.play(filepath)
                return jsonify({
                    'success': success, 
                    'message': f'Playing {filename}' if success else f'Failed to play {filename}'
                })
            else:
                return jsonify({'success': False, 'message': 'File not found'}), 404
        else:
            # Resume playback
            success = player.resume()
            return jsonify({
                'success': success, 
                'message': 'Resumed playback' if success else 'Failed to resume'
            })
    except Exception as e:
        logger.error(f"Error in play endpoint: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500

@app.route('/api/pause', methods=['POST'])
def api_pause():
    """Toggle pause/resume"""
    try:
        success = player.pause()
        return jsonify({
            'success': success, 
            'message': 'Toggled pause' if success else 'Failed to toggle pause'
        })
    except Exception as e:
        logger.error(f"Error in pause endpoint: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500

@app.route('/api/stop', methods=['POST'])
def api_stop():
    """Stop playback"""
    try:
        success = player.stop()
        return jsonify({
            'success': success, 
            'message': 'Stopped playback' if success else 'Failed to stop'
        })
    except Exception as e:
        logger.error(f"Error in stop endpoint: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500

@app.route('/api/seek', methods=['POST'])
def api_seek():
    """Seek to specific position in seconds"""
    try:
        data = request.get_json() or {}
        position = float(data.get('position', 0))
        
        success = player.seek(position)
        return jsonify({
            'success': success, 
            'message': f'Seeked to {position}s' if success else 'Failed to seek',
            'position': position
        })
    except Exception as e:
        logger.error(f"Error in seek endpoint: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500

@app.route('/api/skip', methods=['POST'])
def api_skip():
    """Skip forward or backward by specified seconds"""
    try:
        data = request.get_json() or {}
        seconds = float(data.get('seconds', 30))
        
        success = player.skip(seconds)
        new_position = player.get_position()
        
        return jsonify({
            'success': success,
            'message': f'Skipped {seconds}s' if success else 'Failed to skip',
            'new_position': new_position,
            'new_position_formatted': format_time(new_position)
        })
    except Exception as e:
        logger.error(f"Error in skip endpoint: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500

@app.route('/api/volume', methods=['POST'])
def api_volume():
    """Set volume level (0-100)"""
    try:
        data = request.get_json() or {}
        level = max(0, min(100, int(data.get('level', 100))))
        
        success = player.set_volume(level)
        if success:
            config['volume'] = level
            save_config()
        
        return jsonify({
            'success': success, 
            'message': f'Volume set to {level}%' if success else 'Failed to set volume',
            'level': level
        })
    except Exception as e:
        logger.error(f"Error in volume endpoint: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500

@app.route('/api/hdmi', methods=['POST'])
def api_hdmi():
    """Set HDMI output"""
    try:
        data = request.get_json() or {}
        output = data.get('output', 'auto')
        
        success = player.set_hdmi_output(output)
        if success:
            config['hdmi_output'] = output
            save_config()
        
        return jsonify({
            'success': success,
            'message': f'HDMI output set to {output}' if success else 'Failed to set HDMI output',
            'output': output,
            'outputs': player.get_hdmi_outputs()
        })
    except Exception as e:
        logger.error(f"Error in hdmi endpoint: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500

@app.route('/api/files', methods=['GET'])
def api_files():
    """List available media files"""
    try:
        files = get_media_files()
        return jsonify(files)
    except Exception as e:
        logger.error(f"Error listing files: {e}")
        return jsonify([])

@app.route('/api/upload', methods=['POST'])
def api_upload():
    """Upload a new media file"""
    try:
        if 'file' not in request.files:
            return jsonify({'success': False, 'message': 'No file provided'}), 400
        
        file = request.files['file']
        if file.filename == '':
            return jsonify({'success': False, 'message': 'No file selected'}), 400
        
        # Check file extension
        supported_extensions = ['.mp4', '.avi', '.mkv', '.mov', '.wmv', '.flv', 
                              '.webm', '.m4v', '.mpg', '.mpeg', '.3gp', '.ogv']
        file_ext = Path(file.filename).suffix.lower()
        
        if file_ext not in supported_extensions:
            return jsonify({
                'success': False, 
                'message': f'Unsupported file type. Supported: {", ".join(supported_extensions)}'
            }), 400
        
        # Save file
        filename = secure_filename(file.filename)
        filepath = os.path.join(config['media_dir'], filename)
        
        # Create media directory if it doesn't exist
        Path(config['media_dir']).mkdir(parents=True, exist_ok=True)
        
        file.save(filepath)
        logger.info(f"File uploaded: {filename}")
        
        return jsonify({
            'success': True, 
            'message': f'File {filename} uploaded successfully',
            'filename': filename
        })
        
    except RequestEntityTooLarge:
        return jsonify({'success': False, 'message': 'File too large (max 2GB)'}), 413
    except Exception as e:
        logger.error(f"Error uploading file: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500

@app.route('/api/files/<filename>', methods=['DELETE'])
def api_delete_file(filename):
    """Delete a media file"""
    try:
        filepath = os.path.join(config['media_dir'], secure_filename(filename))
        
        if os.path.exists(filepath):
            # Stop playback if this file is currently playing
            if player.current_file and os.path.samefile(filepath, player.current_file):
                player.stop()
            
            os.remove(filepath)
            logger.info(f"File deleted: {filename}")
            
            return jsonify({
                'success': True, 
                'message': f'File {filename} deleted'
            })
        else:
            return jsonify({'success': False, 'message': 'File not found'}), 404
            
    except Exception as e:
        logger.error(f"Error deleting file: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500

@app.route('/api/config', methods=['GET'])
def api_get_config():
    """Get current configuration"""
    return jsonify({
        'media_dir': config['media_dir'],
        'volume': config['volume'],
        'loop': config['loop'],
        'hardware_accel': config['hardware_accel'],
        'hdmi_output': config['hdmi_output'],
        'port': config['port']
    })

@app.route('/api/config', methods=['POST'])
def api_set_config():
    """Update configuration"""
    try:
        data = request.get_json() or {}
        
        # Update allowed config values
        if 'volume' in data:
            config['volume'] = max(0, min(100, int(data['volume'])))
            player.set_volume(config['volume'])
        
        if 'loop' in data:
            config['loop'] = bool(data['loop'])
        
        if 'hardware_accel' in data:
            config['hardware_accel'] = bool(data['hardware_accel'])
        
        if 'hdmi_output' in data:
            config['hdmi_output'] = data['hdmi_output']
            player.set_hdmi_output(config['hdmi_output'])
        
        save_config()
        
        return jsonify({
            'success': True,
            'message': 'Configuration updated',
            'config': config
        })
    except Exception as e:
        logger.error(f"Error updating config: {e}")
        return jsonify({'success': False, 'message': str(e)}), 500

@app.route('/api/health', methods=['GET'])
def api_health():
    """Health check endpoint for monitoring"""
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.now().isoformat(),
        'uptime': time.time() - start_time,
        'version': '1.0.0'
    })

# Static file serving
@app.route('/static/<path:filename>')
def serve_static(filename):
    """Serve static files"""
    return send_from_directory('static', filename)

# Error handlers
@app.errorhandler(404)
def not_found(error):
    return jsonify({'success': False, 'message': 'Endpoint not found'}), 404

@app.errorhandler(500)
def internal_error(error):
    return jsonify({'success': False, 'message': 'Internal server error'}), 500

# Initialize application
def initialize():
    """Initialize the application"""
    global player, start_time
    
    start_time = time.time()
    
    # Load configuration
    load_config()
    
    # Create media directory if it doesn't exist
    Path(config['media_dir']).mkdir(parents=True, exist_ok=True)
    
    # Initialize player
    player = MPVController(config)
    
    logger.info("Headless Pi MPV Player initialized successfully")
    logger.info(f"Media directory: {config['media_dir']}")
    logger.info(f"Web interface: http://0.0.0.0:{config['port']}")
    logger.info(f"API endpoint: http://0.0.0.0:{config['port']}/api")

def cleanup():
    """Cleanup on shutdown"""
    if player:
        player.cleanup()
    logger.info("Headless Pi MPV Player shutdown")

if __name__ == '__main__':
    try:
        initialize()
        app.run(host='0.0.0.0', port=config['port'], debug=False)
    except KeyboardInterrupt:
        cleanup()
    except Exception as e:
        logger.error(f"Fatal error: {e}")
        cleanup()
        sys.exit(1)
