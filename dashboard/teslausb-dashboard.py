#!/usr/bin/env python3
"""
TeslaUSB Health Monitoring Dashboard
Simple HTTP server providing system status for TeslaUSB Pi
"""

import http.server
import socketserver
import json
import os
import subprocess
import glob
from datetime import datetime

PORT = 80
CAM_MOUNT = "/mnt/cam"
ARCHIVE_MOUNT = "/mnt/archive"
TESLAUSB_LOG = "/mutable/archiveloop.log"

def run_cmd(cmd, default="N/A"):
    """Run shell command and return output or default on error"""
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=10)
        return result.stdout.strip() if result.returncode == 0 else default
    except:
        return default

def get_disk_usage():
    """Get SD card and mounted drive usage"""
    # Root partition (SD card)
    root = run_cmd("df -h / | tail -1 | awk '{print $2,$3,$4,$5}'")
    root_parts = root.split() if root != "N/A" else ["-", "-", "-", "-"]
    
    # CAM partition
    cam = run_cmd(f"df -h {CAM_MOUNT} 2>/dev/null | tail -1 | awk '{{print $2,$3,$4,$5}}'")
    cam_parts = cam.split() if cam != "N/A" and cam else ["-", "-", "-", "-"]
    
    # Archive partition (if mounted)
    archive = run_cmd(f"df -h {ARCHIVE_MOUNT} 2>/dev/null | tail -1 | awk '{{print $2,$3,$4,$5}}'")
    archive_parts = archive.split() if archive != "N/A" and archive else ["-", "-", "-", "-"]
    
    return {
        "root": {"size": root_parts[0], "used": root_parts[1], "avail": root_parts[2], "pct": root_parts[3]},
        "cam": {"size": cam_parts[0], "used": cam_parts[1], "avail": cam_parts[2], "pct": cam_parts[3]},
        "archive": {"size": archive_parts[0], "used": archive_parts[1], "avail": archive_parts[2], "pct": archive_parts[3]}
    }

def get_wifi_status():
    """Get WiFi connection status"""
    ssid = run_cmd("iwgetid -r 2>/dev/null || iw dev wlan0 info 2>/dev/null | grep ssid | awk '{print $2}'")
    signal = run_cmd("iwconfig wlan0 2>/dev/null | grep 'Signal level' | sed 's/.*Signal level=\(-[0-9]*\).*/\\1/ || cat /proc/net/wireless 2>/dev/null | tail -1 | awk '{print $4}' | sed 's/\\./dBm/'")
    ip = run_cmd("hostname -I | awk '{print $1}'")
    
    return {
        "ssid": ssid if ssid else "Not connected",
        "signal": signal if signal else "N/A",
        "ip": ip if ip else "N/A"
    }

def get_file_stats():
    """Get saved recording statistics"""
    recent_dir = "/mnt/cam/TeslaCam/RecentClips"
    saved_dir = "/mnt/cam/TeslaCam/SavedClips"
    sentry_dir = "/mnt/cam/TeslaCam/SentryClips"
    
    def count_files(directory):
        if os.path.exists(directory):
            try:
                return len([f for f in os.listdir(directory) if f.endswith('.mp4')])
            except:
                return 0
        return 0
    
    def get_last_modified(directory):
        if os.path.exists(directory):
            try:
                files = sorted(glob.glob(f"{directory}/*.mp4"), key=os.path.getmtime, reverse=True)
                if files:
                    mtime = os.path.getmtime(files[0])
                    return datetime.fromtimestamp(mtime).strftime("%Y-%m-%d %H:%M:%S")
            except:
                pass
        return "No files"
    
    return {
        "recent_clips": count_files(recent_dir),
        "saved_clips": count_files(saved_dir),
        "sentry_clips": count_files(sentry_dir),
        "last_recording": get_last_modified(recent_dir)
    }

def get_archive_status():
    """Get last archive information"""
    log_file = TESLAUSB_LOG
    last_archive = "No archive yet"
    files_archived = 0
    
    if os.path.exists(log_file):
        try:
            # Find last successful archive
            result = subprocess.run(
                f"grep 'archived successfully' {log_file} | tail -1",
                shell=True, capture_output=True, text=True
            )
            if result.stdout:
                line = result.stdout.strip()
                # Extract timestamp from log line
                parts = line.split()
                if len(parts) >= 2:
                    last_archive = f"{parts[0]} {parts[1]}"
            
            # Count archived files
            result = subprocess.run(
                f"grep -c 'archived successfully' {log_file}",
                shell=True, capture_output=True, text=True
            )
            if result.returncode == 0:
                files_archived = int(result.stdout.strip())
        except:
            pass
    
    return {
        "last_archive": last_archive,
        "total_archived": files_archived
    }

def get_errors():
    """Get recent errors from logs"""
    log_file = TESLAUSB_LOG
    errors = []
    
    if os.path.exists(log_file):
        try:
            result = subprocess.run(
                f"grep -i 'error\\|fail\\|warning' {log_file} | tail -20",
                shell=True, capture_output=True, text=True
            )
            if result.stdout:
                errors = result.stdout.strip().split('\n')[-10:]  # Last 10 errors
        except:
            pass
    
    if not errors:
        errors = ["No recent errors found"]
    
    return errors

def get_system_info():
    """Get basic system information"""
    uptime = run_cmd("uptime -p | sed 's/up //'").replace("up ", "")
    temp = run_cmd("vcgencmd measure_temp 2>/dev/null | cut -d= -f2 || cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null | awk '{print $1/1000\"°C\"}'")
    
    return {
        "uptime": uptime,
        "temperature": temp if temp else "N/A",
        "hostname": run_cmd("hostname")
    }

class DashboardHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/api/status':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            
            status = {
                "timestamp": datetime.now().isoformat(),
                "disk": get_disk_usage(),
                "wifi": get_wifi_status(),
                "files": get_file_stats(),
                "archive": get_archive_status(),
                "errors": get_errors(),
                "system": get_system_info()
            }
            
            self.wfile.write(json.dumps(status, indent=2).encode())
            return
        
        # Serve static files (index.html)
        if self.path == '/':
            self.path = '/index.html'
        
        return http.server.SimpleHTTPRequestHandler.do_GET(self)
    
    def log_message(self, format, *args):
        # Suppress default logging
        pass

if __name__ == '__main__':
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    
    with socketserver.TCPServer(("", PORT), DashboardHandler) as httpd:
        print(f"TeslaUSB Dashboard running on port {PORT}")
        httpd.serve_forever()
