/**
 * IPv4 Subnet Calculator - Client-Side Application
 *
 * This demonstrates the "old way" of building web applications:
 * - Pure client-side HTML/JavaScript/CSS
 * - Direct API calls from browser (visible in Network tab)
 * - CORS headers required
 * - No server-side rendering or middleware
 *
 * Perfect for deployment to:
 * - GitHub Pages
 * - AWS S3 Static Website
 * - Azure Storage Static Website
 * - Any static file hosting
 */

// Check API health on page load
document.addEventListener('DOMContentLoaded', () => {
    checkApiHealth();
});

/**
 * Check if API is available
 */
async function checkApiHealth() {
    const statusDiv = document.getElementById('api-status');
    const statusMsg = document.getElementById('api-status-message');

    try {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 5000); // 5 second timeout

        const response = await fetch(`${API_CONFIG.BASE_URL}${API_CONFIG.PATHS.HEALTH}`, {
            signal: controller.signal
        });
        clearTimeout(timeoutId);

        if (!response.ok) {
            throw new Error(`API returned HTTP ${response.status}: ${response.statusText}`);
        }

        // Check content type before parsing JSON
        const contentType = response.headers.get('content-type');
        if (!contentType || !contentType.includes('application/json')) {
            throw new Error('API did not return JSON response. It may still be starting up.');
        }

        const data = await response.json();

        // Construct full endpoint URL
        const endpointUrl = API_CONFIG.BASE_URL
            ? `${API_CONFIG.BASE_URL}${API_CONFIG.PATHS.HEALTH}`
            : `${window.location.origin}${API_CONFIG.PATHS.HEALTH}`;

        statusDiv.className = 'alert alert-success';
        statusMsg.innerHTML = `
            <strong>API Status:</strong> ${data.status} |
            <strong>Backend:</strong> ${data.service} |
            <strong>Version:</strong> ${data.version}<br>
            <small>Frontend: <code>${window.location.origin}/</code> | Backend: <code>${endpointUrl}</code></small>
        `;
        statusDiv.style.display = 'block';
    } catch (error) {
        let errorMessage = error.message;

        // Provide user-friendly error messages
        if (error.name === 'AbortError') {
            errorMessage = 'API request timed out. The API may be starting up or unavailable.';
        } else if (error.message.includes('Failed to fetch') || error.message.includes('NetworkError')) {
            errorMessage = 'Unable to connect to API. Please ensure the backend is running.';
        }

        statusDiv.className = 'alert alert-error';
        statusMsg.innerHTML = `
            <strong>API Unavailable:</strong> ${errorMessage}<br>
            <small>Expected endpoint: <code>${API_CONFIG.BASE_URL}${API_CONFIG.PATHS.HEALTH}</code></small><br>
            <small>Make sure the API backend is deployed and accessible.</small>
        `;
        statusDiv.style.display = 'block';
    }
}

/**
 * Handle form submission
 */
document.getElementById('lookup-form').addEventListener('submit', async (e) => {
    e.preventDefault();

    const address = document.getElementById('ip-address').value.trim();
    const mode = document.getElementById('cloud-mode').value;

    if (!address) {
        showValidationError('Please enter an IP address or CIDR range');
        return;
    }

    hideValidationError();
    showLoading();
    hideResults();

    try {
        // Step 1: Validate the address/network
        const validateData = await callApi(API_CONFIG.PATHS.VALIDATE, { address });

        // Step 2: Check if RFC1918 or RFC6598 (IPv4 only)
        let privateData = null;
        if (validateData.is_ipv4) {
            privateData = await callApi(API_CONFIG.PATHS.CHECK_PRIVATE, { address });
        }

        // Step 3: Check if Cloudflare
        const cloudflareData = await callApi(API_CONFIG.PATHS.CHECK_CLOUDFLARE, { address });

        // Step 4: Get subnet info (if network)
        let subnetData = null;
        if (validateData.type === 'network') {
            subnetData = await callApi(API_CONFIG.PATHS.SUBNET_INFO, {
                network: address,
                mode: mode
            });
        }

        // Display results
        displayResults(validateData, privateData, cloudflareData, subnetData);

    } catch (error) {
        showError(error.message);
    } finally {
        hideLoading();
    }
});

/**
 * Call API endpoint
 */
async function callApi(path, body) {
    const url = `${API_CONFIG.BASE_URL}${path}`;

    try {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 10000); // 10 second timeout

        const response = await fetch(url, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify(body),
            signal: controller.signal
        });
        clearTimeout(timeoutId);

        if (!response.ok) {
            // Try to get error details from response
            const contentType = response.headers.get('content-type');
            let errorData = {};
            if (contentType && contentType.includes('application/json')) {
                errorData = await response.json().catch(() => ({}));
            }
            throw new Error(errorData.detail || `HTTP ${response.status}: ${response.statusText}`);
        }

        // Check content type before parsing JSON
        const contentType = response.headers.get('content-type');
        if (!contentType || !contentType.includes('application/json')) {
            throw new Error('API did not return JSON response. It may still be starting up.');
        }

        return response.json();
    } catch (error) {
        // Provide user-friendly error messages
        if (error.name === 'AbortError') {
            throw new Error('API request timed out. The API may be starting up or unavailable.');
        }
        if (error.message.includes('Failed to fetch') || error.message.includes('NetworkError')) {
            throw new Error('Unable to connect to API. Please ensure the backend is running.');
        }
        throw error;
    }
}

/**
 * Display results in table format
 */
function displayResults(validate, privateCheck, cloudflare, subnet) {
    const resultsContent = document.getElementById('results-content');

    let html = '<article>';

    // Basic Info
    html += '<h3>Address Information</h3>';
    html += '<table>';
    html += `<tr><th>Address</th><td>${validate.address}</td></tr>`;
    html += `<tr><th>Type</th><td>${validate.type === 'network' ? 'Network (CIDR)' : 'Host Address'}</td></tr>`;
    html += `<tr><th>IP Version</th><td>IPv${validate.is_ipv4 ? '4' : '6'}</td></tr>`;
    html += '</table>';

    // RFC1918/RFC6598 (IPv4 only)
    if (privateCheck) {
        html += '<h3>RFC Classification</h3>';
        html += '<table>';
        html += `<tr><th>RFC1918 Private</th><td>${privateCheck.is_rfc1918 ? `Yes (${privateCheck.matched_rfc1918_range})` : 'No'}</td></tr>`;
        html += `<tr><th>RFC6598 Shared</th><td>${privateCheck.is_rfc6598 ? `Yes (${privateCheck.matched_rfc6598_range})` : 'No'}</td></tr>`;
        html += '</table>';
    }

    // Cloudflare
    html += '<h3>Cloudflare Detection</h3>';
    html += '<table>';
    html += `<tr><th>Is Cloudflare IP</th><td>${cloudflare.is_cloudflare ? 'Yes' : 'No'}</td></tr>`;
    if (cloudflare.matched_ranges) {
        html += `<tr><th>Matched Ranges</th><td>${cloudflare.matched_ranges.join(', ')}</td></tr>`;
    }
    html += '</table>';

    // Subnet Info (if network)
    if (subnet) {
        html += `<h3>Subnet Information (${subnet.mode} Mode)</h3>`;
        html += '<table>';
        html += `<tr><th>Network Address</th><td>${subnet.network_address}</td></tr>`;

        if (subnet.broadcast_address) {
            html += `<tr><th>Broadcast Address</th><td>${subnet.broadcast_address}</td></tr>`;
        }

        html += `<tr><th>Netmask</th><td>${subnet.netmask}</td></tr>`;
        html += `<tr><th>Wildcard Mask</th><td>${subnet.wildcard_mask}</td></tr>`;
        html += `<tr><th>Prefix Length</th><td>/${subnet.prefix_length}</td></tr>`;
        html += `<tr><th>Total Addresses</th><td>${subnet.total_addresses.toLocaleString()}</td></tr>`;
        html += `<tr><th>Usable Addresses</th><td>${subnet.usable_addresses.toLocaleString()}</td></tr>`;
        html += `<tr><th>First Usable IP</th><td>${subnet.first_usable_ip}</td></tr>`;
        html += `<tr><th>Last Usable IP</th><td>${subnet.last_usable_ip}</td></tr>`;

        if (subnet.note) {
            html += `<tr><th>Note</th><td><em>${subnet.note}</em></td></tr>`;
        }

        html += '</table>';

        // Cloud provider reservations explanation
        html += '<h4>IP Reservations</h4>';
        html += '<ul>';
        if (subnet.prefix_length < 31) {
            switch (subnet.mode) {
                case 'Azure':
                case 'AWS':
                    html += '<li>.0 (network address)</li>';
                    html += '<li>.1 (gateway)</li>';
                    html += '<li>.2 (DNS server 1)</li>';
                    html += '<li>.3 (DNS server 2)</li>';
                    html += '<li>.255 (broadcast)</li>';
                    break;
                case 'OCI':
                    html += '<li>.0 (network address)</li>';
                    html += '<li>.1 (gateway)</li>';
                    html += '<li>.255 (broadcast)</li>';
                    break;
                default:
                    html += '<li>.0 (network address)</li>';
                    html += '<li>.255 (broadcast)</li>';
            }
        } else {
            html += `<li>${subnet.note}</li>`;
        }
        html += '</ul>';
    }

    html += '</article>';

    resultsContent.innerHTML = html;
    document.getElementById('results').style.display = 'block';
}

/**
 * Copy results to clipboard
 */
function copyResults() {
    const resultsContent = document.getElementById('results-content');
    const text = resultsContent.innerText;

    navigator.clipboard.writeText(text).then(() => {
        const btn = document.getElementById('copy-btn');
        const originalText = btn.textContent;
        btn.textContent = 'Copied!';
        setTimeout(() => {
            btn.textContent = originalText;
        }, 2000);
    }).catch(() => {
        alert('Failed to copy to clipboard');
    });
}

/**
 * Clear results and form
 */
function clearResults() {
    document.getElementById('ip-address').value = '';
    document.getElementById('cloud-mode').value = 'Azure';
    hideResults();
    hideValidationError();
}

/**
 * Try example address
 */
function tryExample(address) {
    document.getElementById('ip-address').value = address;
    // Use requestSubmit() to trigger a trusted submit event
    // This properly validates the form and triggers the submit handler
    document.getElementById('lookup-form').requestSubmit();
}

/**
 * Toggle dark/light theme
 */
function toggleTheme() {
    const html = document.documentElement;
    const currentTheme = html.getAttribute('data-theme');
    const newTheme = currentTheme === 'dark' ? 'light' : 'dark';

    html.setAttribute('data-theme', newTheme);

    // Update icon
    const icon = document.getElementById('theme-icon');
    icon.textContent = newTheme === 'dark' ? '☀️' : '🌙';

    // Save preference
    localStorage.setItem('theme', newTheme);
}

// Restore saved theme preference
(function() {
    const savedTheme = localStorage.getItem('theme');
    if (savedTheme) {
        document.documentElement.setAttribute('data-theme', savedTheme);
        document.getElementById('theme-icon').textContent = savedTheme === 'dark' ? '☀️' : '🌙';
    }
})();

/**
 * UI Helper Functions
 */
function showLoading() {
    document.getElementById('loading').style.display = 'block';
}

function hideLoading() {
    document.getElementById('loading').style.display = 'none';
}

function showResults() {
    document.getElementById('results').style.display = 'block';
}

function hideResults() {
    document.getElementById('results').style.display = 'none';
}

function showValidationError(message) {
    const error = document.getElementById('validation-error');
    error.textContent = message;
    error.style.display = 'block';
}

function hideValidationError() {
    document.getElementById('validation-error').style.display = 'none';
}

function showError(message) {
    const resultsContent = document.getElementById('results-content');
    resultsContent.innerHTML = `
        <article class="alert alert-error">
            <p><strong>Error:</strong> ${message}</p>
        </article>
    `;
    showResults();
}
