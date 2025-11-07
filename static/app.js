/* Headless Pi MPV Player - Client-side JavaScript */

// Global variables
let currentStatus = null;
let statusInterval = null;
let progressUpdateInterval = null;

// API base URL (will be set dynamically)
let apiBase = '';

// Initialize on page load
document.addEventListener('DOMContentLoaded', () => {
    initializeApp();
});

function initializeApp() {
    // Set API base URL
    apiBase = `${window.location.protocol}//${window.location.host}/api`;
    
    // Update API endpoint display
    document.getElementById('api-base-url').textContent = apiBase;
    document.getElementById('api-endpoint').textContent = `API: ${window.location.port || '5000'}`;
    
    // Initialize event listeners
    setupEventListeners();
    
    // Start status polling
    startStatusPolling();
    
    // Load initial data
    loadFiles();
    loadConfiguration();
}

function setupEventListeners() {
    // Player controls
    document.getElementById('btn-play').addEventListener('click', handlePlay);
    document.getElementById('btn-pause').addEventListener('click', handlePause);
    document.getElementById('btn-stop').addEventListener('click', handleStop);
    
    // Skip controls
    document.getElementById('btn-skip-back-30').addEventListener('click', () => handleSkip(-30));
    document.getElementById('btn-skip-back-10').addEventListener('click', () => handleSkip(-10));
    document.getElementById('btn-skip-forward-10').addEventListener('click', () => handleSkip(10));
    document.getElementById('btn-skip-forward-30').addEventListener('click', () => handleSkip(30));
    
    // Custom skip
    document.getElementById('btn-skip-custom').addEventListener('click', () => {
        const seconds = parseFloat(document.getElementById('skip-seconds').value);
        if (!isNaN(seconds)) {
            handleSkip(seconds);
        }
    });
    
    // Seek control
    document.getElementById('btn-seek').addEventListener('click', () => {
        const position = parseFloat(document.getElementById('seek-position').value);
        if (!isNaN(position) && position >= 0) {
            handleSeek(position);
        }
    });
    
    // Volume control
    const volumeSlider = document.getElementById('volume');
    volumeSlider.addEventListener('input', (e) => {
        document.getElementById('volume-value').textContent = `${e.target.value}%`;
    });
    volumeSlider.addEventListener('change', (e) => {
        handleVolumeChange(parseInt(e.target.value));
    });
    
    // Progress bar click to seek
    document.getElementById('progress-bar').addEventListener('click', (e) => {
        if (currentStatus && currentStatus.duration > 0) {
            const rect = e.currentTarget.getBoundingClientRect();
            const percent = (e.clientX - rect.left) / rect.width;
            const position = percent * currentStatus.duration;
            handleSeek(position);
        }
    });
    
    // File upload
    setupFileUpload();
    
    // File list refresh
    document.getElementById('btn-refresh-files').addEventListener('click', loadFiles);
    
    // Configuration
    document.getElementById('config-loop').addEventListener('change', updateConfiguration);
    document.getElementById('config-hwaccel').addEventListener('change', updateConfiguration);
    
    // API copy button
    document.getElementById('btn-copy-api').addEventListener('click', () => {
        copyToClipboard(apiBase);
    });
}

// Status polling
function startStatusPolling() {
    // Initial status fetch
    fetchStatus();
    
    // Poll every 1 second
    statusInterval = setInterval(fetchStatus, 1000);
}

async function fetchStatus() {
    try {
        const response = await fetch(`${apiBase}/status`);
        if (!response.ok) throw new Error('Failed to fetch status');
        
        currentStatus = await response.json();
        updateUI(currentStatus);
        
        // Update connection status
        document.getElementById('connection-status').textContent = '● Connected';
        document.getElementById('connection-status').classList.remove('disconnected');
        
    } catch (error) {
        console.error('Status fetch error:', error);
        document.getElementById('connection-status').textContent = '● Disconnected';
        document.getElementById('connection-status').classList.add('disconnected');
    }
}

function updateUI(status) {
    // Update hostname
    document.getElementById('hostname').textContent = status.hostname || 'Unknown';
    
    // Update player state
    document.getElementById('player-state').textContent = 
        status.state.charAt(0).toUpperCase() + status.state.slice(1);
    
    // Update current file
    const currentFileElement = document.getElementById('current-file');
    currentFileElement.textContent = status.current_file || 'No file selected';
    
    // Update progress
    if (status.duration > 0) {
        const percent = (status.position / status.duration) * 100;
        document.getElementById('progress-fill').style.width = `${percent}%`;
    } else {
        document.getElementById('progress-fill').style.width = '0%';
    }
    
    // Update time displays
    document.getElementById('current-time').textContent = 
        status.position_formatted || '00:00';
    document.getElementById('duration').textContent = 
        status.duration_formatted || '00:00';
    document.getElementById('position-display').textContent = 
        `${Math.round(status.position)}s`;
    
    // Update volume
    document.getElementById('volume').value = status.volume;
    document.getElementById('volume-value').textContent = `${status.volume}%`;
    
    // Update HDMI outputs
    updateHDMIOutputs(status.hdmi_outputs);
    
    // Update HDMI status
    const hdmiConnected = status.hdmi_outputs?.some(o => o.connected && o.name !== 'auto');
    document.getElementById('hdmi-status').textContent = 
        hdmiConnected ? 'HDMI Connected' : 'Headless Mode';
}

function updateHDMIOutputs(outputs) {
    if (!outputs) return;
    
    const container = document.getElementById('hdmi-outputs');
    container.innerHTML = '';
    
    outputs.forEach(output => {
        const option = document.createElement('div');
        option.className = 'hdmi-option';
        if (output.current) option.classList.add('active');
        
        option.innerHTML = `
            <input type="radio" name="hdmi" value="${output.name}" 
                ${output.current ? 'checked' : ''}>
            <div class="hdmi-info">
                <span>${output.name.toUpperCase()}</span>
                ${output.name !== 'auto' ? 
                    `<span class="hdmi-status ${output.connected ? 'connected' : 'disconnected'}">
                        ${output.connected ? 'Connected' : 'Disconnected'}
                    </span>` : ''}
            </div>
        `;
        
        option.addEventListener('click', () => {
            handleHDMIChange(output.name);
        });
        
        container.appendChild(option);
    });
}

// Player control handlers
async function handlePlay() {
    try {
        const response = await fetch(`${apiBase}/play`, { method: 'POST' });
        const result = await response.json();
        if (result.success) {
            showToast('Playback started', 'success');
        } else {
            showToast(result.message || 'Failed to play', 'error');
        }
    } catch (error) {
        showToast('Error starting playback', 'error');
    }
}

async function handlePause() {
    try {
        const response = await fetch(`${apiBase}/pause`, { method: 'POST' });
        const result = await response.json();
        if (result.success) {
            showToast('Playback paused', 'success');
        } else {
            showToast(result.message || 'Failed to pause', 'error');
        }
    } catch (error) {
        showToast('Error pausing playback', 'error');
    }
}

async function handleStop() {
    try {
        const response = await fetch(`${apiBase}/stop`, { method: 'POST' });
        const result = await response.json();
        if (result.success) {
            showToast('Playback stopped', 'success');
        } else {
            showToast(result.message || 'Failed to stop', 'error');
        }
    } catch (error) {
        showToast('Error stopping playback', 'error');
    }
}

async function handleSkip(seconds) {
    try {
        const response = await fetch(`${apiBase}/skip`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ seconds })
        });
        const result = await response.json();
        if (result.success) {
            showToast(`Skipped ${seconds > 0 ? '+' : ''}${seconds}s`, 'success');
        } else {
            showToast(result.message || 'Failed to skip', 'error');
        }
    } catch (error) {
        showToast('Error skipping', 'error');
    }
}

async function handleSeek(position) {
    try {
        const response = await fetch(`${apiBase}/seek`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ position })
        });
        const result = await response.json();
        if (result.success) {
            showToast(`Seeked to ${Math.round(position)}s`, 'success');
        } else {
            showToast(result.message || 'Failed to seek', 'error');
        }
    } catch (error) {
        showToast('Error seeking', 'error');
    }
}

async function handleVolumeChange(level) {
    try {
        const response = await fetch(`${apiBase}/volume`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ level })
        });
        const result = await response.json();
        if (!result.success) {
            showToast(result.message || 'Failed to set volume', 'error');
        }
    } catch (error) {
        showToast('Error setting volume', 'error');
    }
}

async function handleHDMIChange(output) {
    try {
        const response = await fetch(`${apiBase}/hdmi`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ output })
        });
        const result = await response.json();
        if (result.success) {
            showToast(`HDMI output set to ${output}`, 'success');
        } else {
            showToast(result.message || 'Failed to set HDMI output', 'error');
        }
    } catch (error) {
        showToast('Error setting HDMI output', 'error');
    }
}

// File management
async function loadFiles() {
    try {
        const response = await fetch(`${apiBase}/files`);
        const files = await response.json();
        displayFiles(files);
    } catch (error) {
        showToast('Error loading files', 'error');
    }
}

function displayFiles(files) {
    const container = document.getElementById('file-list');
    
    if (files.length === 0) {
        container.innerHTML = '<div style="padding: 20px; text-align: center; color: var(--text-secondary);">No video files found</div>';
        return;
    }
    
    container.innerHTML = '';
    files.forEach(file => {
        const fileItem = document.createElement('div');
        fileItem.className = 'file-item';
        
        const fileSize = formatFileSize(file.size);
        const fileDate = new Date(file.modified).toLocaleDateString();
        
        fileItem.innerHTML = `
            <div class="file-info">
                <div class="file-name" data-filename="${file.name}">${file.name}</div>
                <div class="file-meta">${fileSize} • ${fileDate}</div>
            </div>
            <div class="file-actions">
                <button class="btn btn-primary btn-small" data-action="play" data-filename="${file.name}">▶ Play</button>
                <button class="btn btn-danger btn-small" data-action="delete" data-filename="${file.name}">🗑️</button>
            </div>
        `;
        
        container.appendChild(fileItem);
    });
    
    // Add click handlers for file actions
    container.querySelectorAll('[data-action="play"]').forEach(btn => {
        btn.addEventListener('click', () => playFile(btn.dataset.filename));
    });
    
    container.querySelectorAll('[data-action="delete"]').forEach(btn => {
        btn.addEventListener('click', () => deleteFile(btn.dataset.filename));
    });
    
    container.querySelectorAll('.file-name').forEach(elem => {
        elem.addEventListener('click', () => playFile(elem.dataset.filename));
    });
}

async function playFile(filename) {
    try {
        const response = await fetch(`${apiBase}/play`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ file: filename })
        });
        const result = await response.json();
        if (result.success) {
            showToast(`Playing ${filename}`, 'success');
        } else {
            showToast(result.message || 'Failed to play file', 'error');
        }
    } catch (error) {
        showToast('Error playing file', 'error');
    }
}

async function deleteFile(filename) {
    if (!confirm(`Delete ${filename}?`)) return;
    
    try {
        const response = await fetch(`${apiBase}/files/${encodeURIComponent(filename)}`, {
            method: 'DELETE'
        });
        const result = await response.json();
        if (result.success) {
            showToast(`Deleted ${filename}`, 'success');
            loadFiles(); // Reload file list
        } else {
            showToast(result.message || 'Failed to delete file', 'error');
        }
    } catch (error) {
        showToast('Error deleting file', 'error');
    }
}

// File upload
function setupFileUpload() {
    const uploadArea = document.getElementById('upload-area');
    const fileInput = document.getElementById('file-input');
    const browseBtn = document.getElementById('btn-browse');
    
    // Browse button
    browseBtn.addEventListener('click', () => fileInput.click());
    
    // File input change
    fileInput.addEventListener('change', (e) => {
        if (e.target.files.length > 0) {
            handleFiles(e.target.files);
        }
    });
    
    // Drag and drop
    uploadArea.addEventListener('dragover', (e) => {
        e.preventDefault();
        uploadArea.classList.add('drag-over');
    });
    
    uploadArea.addEventListener('dragleave', (e) => {
        e.preventDefault();
        uploadArea.classList.remove('drag-over');
    });
    
    uploadArea.addEventListener('drop', (e) => {
        e.preventDefault();
        uploadArea.classList.remove('drag-over');
        
        if (e.dataTransfer.files.length > 0) {
            handleFiles(e.dataTransfer.files);
        }
    });
    
    // Click to browse
    uploadArea.addEventListener('click', (e) => {
        if (e.target === uploadArea || e.target.parentElement === uploadArea) {
            fileInput.click();
        }
    });
}

async function handleFiles(files) {
    for (const file of files) {
        await uploadFile(file);
    }
    loadFiles(); // Reload file list
}

async function uploadFile(file) {
    const progressContainer = document.getElementById('upload-progress');
    const progressFill = document.getElementById('upload-progress-fill');
    const statusText = document.getElementById('upload-status');
    
    progressContainer.style.display = 'block';
    statusText.textContent = `Uploading ${file.name}...`;
    
    const formData = new FormData();
    formData.append('file', file);
    
    try {
        const xhr = new XMLHttpRequest();
        
        xhr.upload.addEventListener('progress', (e) => {
            if (e.lengthComputable) {
                const percent = (e.loaded / e.total) * 100;
                progressFill.style.width = `${percent}%`;
            }
        });
        
        xhr.addEventListener('load', () => {
            if (xhr.status === 200) {
                const result = JSON.parse(xhr.responseText);
                if (result.success) {
                    showToast(`Uploaded ${file.name}`, 'success');
                } else {
                    showToast(result.message || 'Upload failed', 'error');
                }
            } else {
                showToast(`Failed to upload ${file.name}`, 'error');
            }
            progressContainer.style.display = 'none';
            progressFill.style.width = '0%';
        });
        
        xhr.addEventListener('error', () => {
            showToast(`Error uploading ${file.name}`, 'error');
            progressContainer.style.display = 'none';
            progressFill.style.width = '0%';
        });
        
        xhr.open('POST', `${apiBase}/upload`);
        xhr.send(formData);
        
    } catch (error) {
        showToast(`Error uploading ${file.name}`, 'error');
        progressContainer.style.display = 'none';
        progressFill.style.width = '0%';
    }
}

// Configuration
async function loadConfiguration() {
    try {
        const response = await fetch(`${apiBase}/config`);
        const config = await response.json();
        
        document.getElementById('config-loop').checked = config.loop;
        document.getElementById('config-hwaccel').checked = config.hardware_accel;
        
    } catch (error) {
        console.error('Error loading configuration:', error);
    }
}

async function updateConfiguration() {
    const config = {
        loop: document.getElementById('config-loop').checked,
        hardware_accel: document.getElementById('config-hwaccel').checked
    };
    
    try {
        const response = await fetch(`${apiBase}/config`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(config)
        });
        
        const result = await response.json();
        if (result.success) {
            showToast('Configuration updated', 'success');
        } else {
            showToast('Failed to update configuration', 'error');
        }
    } catch (error) {
        showToast('Error updating configuration', 'error');
    }
}

// Utility functions
function formatFileSize(bytes) {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return Math.round(bytes / Math.pow(k, i) * 100) / 100 + ' ' + sizes[i];
}

function copyToClipboard(text) {
    navigator.clipboard.writeText(text).then(() => {
        showToast('Copied to clipboard', 'success');
    }).catch(() => {
        // Fallback method
        const textarea = document.createElement('textarea');
        textarea.value = text;
        textarea.style.position = 'fixed';
        textarea.style.opacity = '0';
        document.body.appendChild(textarea);
        textarea.select();
        try {
            document.execCommand('copy');
            showToast('Copied to clipboard', 'success');
        } catch (err) {
            showToast('Failed to copy', 'error');
        }
        document.body.removeChild(textarea);
    });
}

function showToast(message, type = 'info') {
    const container = document.getElementById('toast-container');
    const toast = document.createElement('div');
    toast.className = `toast ${type}`;
    
    const icon = {
        success: '✅',
        error: '❌',
        warning: '⚠️',
        info: 'ℹ️'
    }[type];
    
    toast.innerHTML = `<span>${icon}</span><span>${message}</span>`;
    container.appendChild(toast);
    
    setTimeout(() => {
        toast.style.opacity = '0';
        setTimeout(() => container.removeChild(toast), 300);
    }, 3000);
}

// Make copyToClipboard available globally for inline onclick
window.copyToClipboard = copyToClipboard;
