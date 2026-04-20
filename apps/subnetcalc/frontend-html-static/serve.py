#!/usr/bin/env python3
"""
Simple HTTP server for local development of static frontend.

Usage:
    uv run python serve.py           # Serve on default port 8001
    uv run python serve.py 3000      # Serve on custom port

This serves static files from the current directory.
The frontend will call the API at http://localhost:8080 (configured in js/config.js).

Make sure the API is running:
    cd ../api-fastapi-azure-function && uv run func start
    # OR
    cd .. && docker compose up
"""

import http.server
import socketserver
import sys
from pathlib import Path

# Default port
DEFAULT_PORT = 8001

# Get port from command line argument
if len(sys.argv) > 1:
    try:
        PORT = int(sys.argv[1])
    except ValueError:
        print(f"Error: Invalid port number '{sys.argv[1]}'")
        print(f"Usage: {sys.argv[0]} [port]")
        sys.exit(1)
else:
    PORT = DEFAULT_PORT

# Change to the directory containing this script
script_dir = Path(__file__).parent
if script_dir != Path.cwd():
    print(f"Changing directory to: {script_dir}")
    import os
    os.chdir(script_dir)

# Create handler with custom MIME types
class MyHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):
    """Custom handler to ensure proper MIME types"""

    def end_headers(self):
        # Add CORS headers for development (not needed in production)
        # This allows testing with different API URLs
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        super().end_headers()

    def guess_type(self, path):
        """Ensure JavaScript files are served with correct MIME type"""
        if path.endswith('.js'):
            return 'application/javascript'
        return super().guess_type(path)

# Create server
Handler = MyHTTPRequestHandler

try:
    with socketserver.TCPServer(("", PORT), Handler) as httpd:
        print("=" * 60)
        print("Static Frontend Development Server")
        print("=" * 60)
        print(f"Serving at: http://localhost:{PORT}")
        print(f"Directory: {Path.cwd()}")
        print("")
        print("Configuration:")
        print("  API URL: Configured in js/config.js")
        print("  Default: http://localhost:7071 (Azure Functions)")
        print("  Docker:  http://localhost:8080 (Docker Compose)")
        print("")
        print("Make sure the API is running:")
        print("  cd ../api-fastapi-azure-function && uv run func start")
        print("  OR")
        print("  cd .. && docker compose up")
        print("")
        print("Press Ctrl+C to stop the server")
        print("=" * 60)

        httpd.serve_forever()

except KeyboardInterrupt:
    print("\n\nServer stopped.")
    sys.exit(0)
except OSError as e:
    if e.errno == 48:  # Address already in use
        print(f"\nError: Port {PORT} is already in use.")
        print(f"Try a different port: python {sys.argv[0]} 3000")
    else:
        print(f"\nError: {e}")
    sys.exit(1)
