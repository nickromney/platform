import threading
import time

import pytest

from app import app


@pytest.fixture(scope="session")
def flask_server():
    """Start Flask server in a background thread for testing"""

    def run_server():
        app.run(host="127.0.0.1", port=5001, debug=False, use_reloader=False)

    thread = threading.Thread(target=run_server, daemon=True)
    thread.start()
    time.sleep(2)  # Give server time to start
    yield "http://127.0.0.1:5001"


@pytest.fixture(scope="session")
def base_url(flask_server, request):
    """Provide base URL for tests - uses CLI arg if provided, otherwise starts local server"""
    # If --base-url provided via CLI, use it (for Docker Compose testing)
    cli_base_url = request.config.getoption("--base-url", default=None)
    if cli_base_url:
        return cli_base_url
    # Otherwise use local Flask server (for make python-test)
    return flask_server
