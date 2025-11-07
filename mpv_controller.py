#!/usr/bin/env python3
"""
Headless Pi MPV Player - MPV Controller Module (FIXED)
Handles video playback using MPV with hardware acceleration for Raspberry Pi
Works with or without HDMI display connected
FIXES: HDMI audio output and screen blanking issues
"""

import os
import json
import time
import logging
import subprocess
import threading
import socket
import re
from pathlib import Path

logger = logging.getLogger(__name__)

class MPVController:
    """
    Controller for MPV player with IPC socket communication
    Optimized for Raspberry Pi with hardware acceleration and headless support
    """
    
    def __init__(self, config):
        self.config = config
        self.current_file = None
        self.process = None
        self.state = 'stopped'
        self.position = 0
        self.duration = 0
        self.volume = config.get('volume', 100)
        self.hdmi_output = config.get('hdmi_output', 'auto')  # auto, HDMI-A-1, HDMI-A-2
        
        # MPV IPC socket path
        self.mpv_socket = '/tmp/mpvsocket'
        
        # Start monitoring thread
        self.monitor_running = True
        self.monitor_thread = threading.Thread(target=self._monitor_position, daemon=True)
        self.monitor_thread.start()
        
        # Ensure blank screen when stopped
        self._ensure_blank_screen()
        
        logger.info("MPV controller initialized")
    
    def play(self, filepath):
        """Start playing a video file"""
        try:
            # Stop current playback if any
            self.stop()
            
            if not os.path.exists(filepath):
                logger.error(f"File not found: {filepath}")
                return False
            
            self.current_file = filepath
            
            # Build MPV command with hardware acceleration
            cmd = ['mpv']
            
            # Detect HDMI connection and select output
            hdmi_info = self._detect_hdmi()
            
            if hdmi_info['connected']:
                # Use hardware rendering when display is connected
                logger.info(f"Display detected on {hdmi_info['output']} - using hardware rendering")
                
                # DRM output for direct rendering
                cmd.extend([
                    '--vo=gpu',  # GPU accelerated video output
                    '--gpu-context=drm',  # DRM context for headless
                    f'--drm-connector={hdmi_info["output"]}',  # Use detected HDMI
                ])
                
                # Try multiple DRM devices in order
                drm_device = self._find_drm_device()
                if drm_device:
                    cmd.append(f'--drm-device={drm_device}')
                
                # Hardware decoding
                if self.config.get('hardware_accel', True):
                    cmd.extend([
                        '--hwdec=auto-copy',  # Auto hardware decoding with copy-back
                        '--hwdec-codecs=all',  # Enable for all codecs
                    ])
                
                # FIXED: Audio output via HDMI for Raspberry Pi 4
                # Check for vc4hdmi devices (Pi 4)
                audio_device = self._get_hdmi_audio_device()
                if audio_device:
                    cmd.append(f'--audio-device={audio_device}')
                    logger.info(f"Using audio device: {audio_device}")
                else:
                    # Fallback to ALSA default
                    cmd.extend([
                        '--ao=alsa',
                        '--audio-channels=stereo',
                    ])
            else:
                # Headless mode - no display connected
                logger.info("No display detected - running in headless mode")
                cmd.extend([
                    '--vo=null',  # Null video output (no display needed)
                    '--no-video',  # Don't process video (faster in headless)
                ])
                
                # Still output audio if available
                if self.config.get('audio_in_headless', True):
                    cmd.extend([
                        '--ao=alsa',
                        '--audio-device=alsa/default',
                        '--audio-channels=stereo',
                    ])
                else:
                    cmd.append('--ao=null')
            
            # Display settings
            cmd.extend([
                '--fullscreen',
                '--no-border',
                '--no-osc',
                '--no-osd-bar',
                '--no-input-default-bindings',
                '--no-input-cursor',
                '--cursor-autohide=no',
                '--no-terminal',
                '--quiet',
                '--really-quiet',
                '--keep-open=no',  # Exit when playback ends
                '--idle=no',  # Don't stay idle after playback
                f'--volume={self.volume}',
            ])
            
            # IPC socket for control
            cmd.append(f'--input-ipc-server={self.mpv_socket}')
            
            # Add the file to play
            cmd.append(filepath)
            
            # Log the command for debugging
            logger.debug(f"MPV Command: {' '.join(cmd)}")
            
            # Set environment for DRM if needed
            env = os.environ.copy()
            if hdmi_info['connected']:
                env['DISPLAY'] = ''  # Clear DISPLAY for DRM mode
            
            # Start MPV process
            self.process = subprocess.Popen(
                cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                stdin=subprocess.DEVNULL,
                env=env
            )
            
            self.state = 'playing'
            time.sleep(1.0)  # Give MPV time to start
            
            logger.info(f"MPV started playing: {filepath}")
            return True
            
        except Exception as e:
            logger.error(f"Error starting MPV: {e}")
            return False
    
    def _get_hdmi_audio_device(self):
        """Get the correct HDMI audio device for Raspberry Pi"""
        try:
            # Run aplay -l to get audio devices
            result = subprocess.run(['aplay', '-l'], capture_output=True, text=True)
            if result.returncode == 0:
                output = result.stdout
                
                # Check for Pi 4 HDMI audio (vc4hdmi0 or vc4hdmi1)
                if 'vc4hdmi0' in output:
                    logger.debug("Found vc4hdmi0 audio device")
                    return 'alsa/hdmi:CARD=vc4hdmi0,DEV=0'
                elif 'vc4hdmi1' in output:
                    logger.debug("Found vc4hdmi1 audio device")
                    return 'alsa/hdmi:CARD=vc4hdmi1,DEV=0'
                elif 'vc4hdmi' in output:
                    logger.debug("Found vc4hdmi audio device")
                    return 'alsa/hdmi:CARD=vc4hdmi,DEV=0'
                elif 'HDMI' in output:
                    logger.debug("Found generic HDMI audio device")
                    return 'alsa/hdmi:CARD=HDMI,DEV=0'
        except Exception as e:
            logger.debug(f"Error detecting HDMI audio device: {e}")
        
        return None
    
    def _detect_hdmi(self):
        """Detect HDMI connection and select output"""
        hdmi_info = {'connected': False, 'output': 'HDMI-A-1'}
        
        try:
            # If manual output is specified, use it
            if self.hdmi_output != 'auto':
                hdmi_info['output'] = self.hdmi_output
                # Still check if something is connected
                hdmi_info['connected'] = self._check_display_connected()
                return hdmi_info
            
            # Auto-detect HDMI output
            # First try tvservice (Raspberry Pi specific)
            try:
                result = subprocess.run(['tvservice', '-s'], capture_output=True, text=True, timeout=2)
                if result.returncode == 0:
                    stdout = result.stdout.lower()
                    if 'hdmi' in stdout and 'off' not in stdout and 'unknown' not in stdout:
                        hdmi_info['connected'] = True
                        # Try to detect which HDMI port from tvservice output
                        if 'hdmi:0' in stdout or 'hdmi0' in stdout:
                            hdmi_info['output'] = 'HDMI-A-1'
                        elif 'hdmi:1' in stdout or 'hdmi1' in stdout:
                            hdmi_info['output'] = 'HDMI-A-2'
                        logger.debug(f"Detected HDMI via tvservice: {hdmi_info['output']}")
                        return hdmi_info
            except:
                pass
            
            # Check /sys/class/drm for connected displays
            import glob
            for card_path in glob.glob('/sys/class/drm/card*-HDMI-*/status'):
                try:
                    with open(card_path, 'r') as f:
                        if f.read().strip() == 'connected':
                            hdmi_info['connected'] = True
                            # Extract HDMI port from path
                            match = re.search(r'card\d+-HDMI-A-(\d+)', card_path)
                            if match:
                                port_num = match.group(1)
                                hdmi_info['output'] = f'HDMI-A-{port_num}'
                            logger.debug(f"Detected HDMI via sysfs: {hdmi_info['output']}")
                            return hdmi_info
                except:
                    continue
            
        except Exception as e:
            logger.debug(f"HDMI detection error: {e}")
        
        return hdmi_info
    
    def _find_drm_device(self):
        """Find the appropriate DRM device"""
        # Try common DRM devices on Raspberry Pi
        drm_devices = ['/dev/dri/card1', '/dev/dri/card0']
        for device in drm_devices:
            if os.path.exists(device):
                logger.debug(f"Using DRM device: {device}")
                return device
        return None
    
    def _check_display_connected(self):
        """Check if any display is connected"""
        try:
            # Try tvservice first
            try:
                result = subprocess.run(['tvservice', '-s'], capture_output=True, text=True, timeout=2)
                if result.returncode == 0:
                    stdout = result.stdout.lower()
                    if 'hdmi' in stdout and 'off' not in stdout and 'unknown' not in stdout:
                        return True
            except:
                pass
            
            # Check /sys/class/drm
            import glob
            for status_file in glob.glob('/sys/class/drm/card*-*/status'):
                try:
                    with open(status_file, 'r') as f:
                        if f.read().strip() == 'connected':
                            return True
                except:
                    continue
            
            return False
            
        except Exception as e:
            logger.debug(f"Display detection error: {e}")
            return False
    
    def _ensure_blank_screen(self):
        """FIXED: Ensure screen is completely blank when no video is playing"""
        try:
            # Method 1: Use vcgencmd to turn display on but blank
            subprocess.run(['vcgencmd', 'display_power', '1'], 
                          capture_output=True, timeout=1)
            
            # Method 2: Clear the console and hide cursor
            if os.path.exists('/dev/tty1'):
                try:
                    # Clear console
                    subprocess.run(['clear'], capture_output=True, timeout=1)
                    # Turn off cursor
                    with open('/dev/tty1', 'w') as tty:
                        tty.write('\033[?25l')  # Hide cursor
                        tty.write('\033[2J\033[H')  # Clear screen and move cursor to home
                except:
                    pass
            
            # Method 3: Set console blank time to 1 second (will blank after 1 second of inactivity)
            subprocess.run(['sudo', 'sh', '-c', 'echo 1 > /sys/module/kernel/parameters/consoleblank'],
                          capture_output=True, timeout=1)
            
        except:
            pass
    
    def pause(self):
        """Toggle pause/resume"""
        try:
            if self._send_command(['cycle', 'pause']):
                if self.state == 'playing':
                    self.state = 'paused'
                elif self.state == 'paused':
                    self.state = 'playing'
                return True
            return False
        except Exception as e:
            logger.error(f"Error toggling pause: {e}")
            return False
    
    def resume(self):
        """Resume playback if paused"""
        if self.state == 'paused':
            return self.pause()
        return True
    
    def stop(self):
        """Stop playback and ensure blank screen"""
        try:
            # Send quit command to MPV
            self._send_command(['quit'])
            
            # Terminate process if still running
            if self.process and self.process.poll() is None:
                self.process.terminate()
                time.sleep(0.5)
                if self.process.poll() is None:
                    self.process.kill()
            
            self.process = None
            self.state = 'stopped'
            self.current_file = None
            self.position = 0
            self.duration = 0
            
            # Clean up socket
            if os.path.exists(self.mpv_socket):
                try:
                    os.remove(self.mpv_socket)
                except:
                    pass
            
            # Ensure blank screen
            self._ensure_blank_screen()
            
            logger.info("Playback stopped")
            return True
            
        except Exception as e:
            logger.error(f"Error stopping playback: {e}")
            return False
    
    def seek(self, position):
        """Seek to specific position in seconds"""
        try:
            if self._send_command(['seek', position, 'absolute']):
                self.position = position
                return True
            return False
        except Exception as e:
            logger.error(f"Error seeking: {e}")
            return False
    
    def skip(self, seconds):
        """Skip forward or backward by specified seconds"""
        try:
            # Get current position first
            current_pos = self.get_position()
            new_pos = max(0, current_pos + seconds)
            
            # Don't seek beyond duration if known
            if self.duration > 0:
                new_pos = min(new_pos, self.duration)
            
            return self.seek(new_pos)
        except Exception as e:
            logger.error(f"Error skipping: {e}")
            return False
    
    def set_volume(self, level):
        """Set volume level (0-100)"""
        try:
            self.volume = max(0, min(100, level))
            if self._send_command(['set_property', 'volume', self.volume]):
                return True
            return False
        except Exception as e:
            logger.error(f"Error setting volume: {e}")
            return False
    
    def get_state(self):
        """Get current player state"""
        # Check if process is still running
        if self.process and self.process.poll() is not None:
            self.state = 'stopped'
            self.current_file = None
            self._ensure_blank_screen()
        
        return self.state
    
    def get_position(self):
        """Get current playback position in seconds"""
        return self.position
    
    def get_duration(self):
        """Get media duration in seconds"""
        return self.duration
    
    def get_volume(self):
        """Get current volume level"""
        return self.volume
    
    def get_hdmi_outputs(self):
        """Get list of available HDMI outputs"""
        outputs = []
        try:
            # Check for HDMI outputs in /sys/class/drm
            import glob
            for card_path in glob.glob('/sys/class/drm/card*-HDMI-*'):
                match = re.search(r'card\d+-HDMI-A-(\d+)', card_path)
                if match:
                    port_num = match.group(1)
                    hdmi_name = f'HDMI-A-{port_num}'
                    
                    # Check if connected
                    status_file = os.path.join(card_path, 'status')
                    connected = False
                    if os.path.exists(status_file):
                        try:
                            with open(status_file, 'r') as f:
                                connected = f.read().strip() == 'connected'
                        except:
                            pass
                    
                    outputs.append({
                        'name': hdmi_name,
                        'connected': connected,
                        'current': hdmi_name == self.hdmi_output
                    })
        except Exception as e:
            logger.error(f"Error getting HDMI outputs: {e}")
        
        # Always include auto option
        outputs.insert(0, {
            'name': 'auto',
            'connected': True,
            'current': self.hdmi_output == 'auto'
        })
        
        return outputs
    
    def set_hdmi_output(self, output):
        """Set HDMI output (auto, HDMI-A-1, HDMI-A-2, etc.)"""
        self.hdmi_output = output
        self.config['hdmi_output'] = output
        logger.info(f"HDMI output set to: {output}")
        
        # If currently playing, restart playback with new output
        if self.state == 'playing' and self.current_file:
            current_pos = self.position
            self.play(self.current_file)
            if current_pos > 0:
                time.sleep(0.5)
                self.seek(current_pos)
        
        return True
    
    def _send_command(self, command):
        """Send command to MPV via IPC socket"""
        try:
            if not os.path.exists(self.mpv_socket):
                return False
            
            # Create socket connection
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.settimeout(1.0)
            sock.connect(self.mpv_socket)
            
            # Send command as JSON
            cmd_json = json.dumps({'command': command}) + '\n'
            sock.send(cmd_json.encode('utf-8'))
            
            # Read response
            response = b''
            while True:
                data = sock.recv(4096)
                if not data:
                    break
                response += data
                if b'\n' in response:
                    break
            
            sock.close()
            
            # Parse response
            if response:
                result = json.loads(response.decode('utf-8').strip())
                return result.get('error') == 'success'
            
            return False
            
        except Exception as e:
            logger.debug(f"IPC command failed: {e}")
            return False
    
    def _get_property(self, property_name):
        """Get property value from MPV"""
        try:
            if not os.path.exists(self.mpv_socket):
                return None
            
            # Create socket connection
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.settimeout(0.5)
            sock.connect(self.mpv_socket)
            
            # Send command
            cmd_json = json.dumps({'command': ['get_property', property_name]}) + '\n'
            sock.send(cmd_json.encode('utf-8'))
            
            # Read response
            response = b''
            while True:
                data = sock.recv(4096)
                if not data:
                    break
                response += data
                if b'\n' in response:
                    break
            
            sock.close()
            
            # Parse response
            if response:
                result = json.loads(response.decode('utf-8').strip())
                if result.get('error') == 'success':
                    return result.get('data')
            
            return None
            
        except:
            return None
    
    def _monitor_position(self):
        """Monitor playback position in background"""
        while self.monitor_running:
            try:
                if self.state == 'playing':
                    # Update position
                    pos = self._get_property('time-pos')
                    if pos is not None:
                        self.position = float(pos)
                    
                    # Update duration
                    dur = self._get_property('duration')
                    if dur is not None:
                        self.duration = float(dur)
                    
                    # Check if playback ended
                    if self.duration > 0 and self.position >= self.duration - 1:
                        # Handle loop if enabled
                        if self.config.get('loop', False):
                            self.seek(0)
                        else:
                            self.state = 'stopped'
                            self._ensure_blank_screen()
                            
            except Exception as e:
                logger.debug(f"Monitor error: {e}")
            
            time.sleep(0.5)
    
    def cleanup(self):
        """Cleanup resources"""
        self.monitor_running = False
        self.stop()

