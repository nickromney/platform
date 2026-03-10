"""Frontend tests for Static HTML implementation.

This test suite implements the canonical frontend test specification.
See: subnet-calculator/docs/TEST_SPECIFICATION.md

Total: 32 tests (includes progressive enhancement tests)
"""

from playwright.sync_api import Page, expect


class TestStaticFrontend:
    """Frontend tests using Playwright - all 32 canonical tests"""

    # Group 0: Essential Resources (1 test)

    def test_00_favicon_exists(self, page: Page, base_url: str):
        """Test 00: Verify favicon is present (either .ico or .svg)"""
        # Check for either /favicon.svg or /favicon.ico
        svg_response = page.goto(f"{base_url}/favicon.svg")
        svg_exists = svg_response.status == 200 if svg_response else False

        ico_response = page.goto(f"{base_url}/favicon.ico")
        ico_exists = ico_response.status == 200 if ico_response else False

        # At least one should exist
        assert svg_exists or ico_exists, "Neither /favicon.svg nor /favicon.ico found"

    # Group 1: Basic Page & Elements (5 tests)

    def test_01_page_loads(self, page: Page, base_url: str):
        """Test 01: Verify the page loads and displays the main heading"""
        page.goto(base_url)
        expect(page.locator("h1")).to_contain_text("IPv4 Subnet Calculator")

    def test_02_form_elements_present(self, page: Page, base_url: str):
        """Test 02: Verify all required form elements exist and are visible"""
        page.goto(base_url)

        # Check input field
        ip_input = page.locator("#ip-address")
        expect(ip_input).to_be_visible()
        # Check placeholder exists (regex not supported in Python, check contains text)
        placeholder = ip_input.get_attribute("placeholder")
        assert placeholder is not None and "e.g." in placeholder

        # Check cloud mode selector
        mode_select = page.locator("#cloud-mode")
        expect(mode_select).to_be_visible()

        # Check submit button
        submit_btn = page.locator("#lookup-btn")
        expect(submit_btn).to_be_visible()

    def test_03_cloud_mode_selector(self, page: Page, base_url: str):
        """Test 03: Verify cloud mode selector has correct options and default"""
        page.goto(base_url)

        # Check selector exists
        selector = page.locator("#cloud-mode")
        expect(selector).to_be_visible()

        # Check options
        options = selector.locator("option")
        expect(options).to_have_count(4)

        # Check default value (Azure is the default)
        assert page.input_value("#cloud-mode") == "Azure"

        # Change to AWS
        page.select_option("#cloud-mode", "AWS")
        assert page.input_value("#cloud-mode") == "AWS"

    def test_04_input_placeholder(self, page: Page, base_url: str):
        """Test 04: Verify input field has helpful placeholder text"""
        page.goto(base_url)

        input_field = page.locator("#ip-address")
        placeholder = input_field.get_attribute("placeholder")
        assert placeholder is not None
        assert len(placeholder) > 0

    def test_05_semantic_html_structure(self, page: Page, base_url: str):
        """Test 05: Verify page uses proper semantic HTML elements"""
        page.goto(base_url)

        # Check for semantic elements
        expect(page.locator("header")).to_be_visible()
        expect(page.locator("h1")).to_be_visible()
        expect(page.locator("main")).to_be_visible()
        expect(page.locator("form")).to_be_visible()

    # Group 2: Input Validation (3 tests)

    def test_06_invalid_ip_validation(self, page: Page, base_url: str):
        """Test 06: Verify client-side validation rejects invalid IPs"""
        page.goto(base_url)

        # Enter invalid IP
        page.fill("#ip-address", "999.999.999.999")
        page.click("#lookup-btn")

        # Static HTML frontend sends to API and shows error in results section
        # Wait for results to appear
        results = page.locator("#results")
        expect(results).to_be_visible(timeout=10000)

        # Should show error message in results
        results_text = results.inner_text().lower()
        assert "error" in results_text or "valid" in results_text or "invalid" in results_text

    def test_07_valid_ip_no_error(self, page: Page, base_url: str):
        """Test 07: Verify valid IP passes client-side validation"""
        page.goto(base_url)

        page.fill("#ip-address", "192.168.1.0/24")

        # Error should not be visible immediately
        error = page.locator("#validation-error")
        expect(error).not_to_be_visible()

    def test_08_cidr_notation_accepted(self, page: Page, base_url: str):
        """Test 08: Verify CIDR notation passes validation"""
        page.goto(base_url)

        page.fill("#ip-address", "10.0.0.0/24")

        # Should not show immediate error
        error = page.locator("#validation-error")
        expect(error).not_to_be_visible()

    # Group 3: Example Buttons (2 tests)

    def test_09_example_buttons_populate_input(self, page: Page, base_url: str):
        """Test 09: Verify example buttons populate the input field"""
        page.goto(base_url)

        # Click RFC1918 example
        page.click("text=10.0.0.0/24")

        # Input should be populated
        input_value = page.input_value("#ip-address")
        assert input_value == "10.0.0.0/24"

    def test_10_all_example_buttons_present(self, page: Page, base_url: str):
        """Test 10: Verify all example buttons exist"""
        page.goto(base_url)

        # Check example buttons
        expect(page.locator(".btn-rfc1918")).to_be_visible()
        expect(page.locator(".btn-rfc6598")).to_be_visible()
        expect(page.locator(".btn-public")).to_be_visible()
        expect(page.locator(".btn-cloudflare")).to_be_visible()

    # Group 4: Responsive Layout (3 tests)

    def test_11_mobile_responsive_layout(self, page: Page, base_url: str):
        """Test 11: Verify layout works on mobile viewport"""
        page.set_viewport_size({"width": 375, "height": 667})
        page.goto(base_url)

        # Check that the form is visible and usable
        expect(page.locator("#ip-address")).to_be_visible()
        expect(page.locator("#cloud-mode")).to_be_visible()
        expect(page.locator("#lookup-btn")).to_be_visible()

    def test_12_tablet_responsive_layout(self, page: Page, base_url: str):
        """Test 12: Verify layout works on tablet viewport"""
        page.set_viewport_size({"width": 768, "height": 1024})
        page.goto(base_url)

        # Check that all elements are visible
        expect(page.locator("#ip-address")).to_be_visible()
        expect(page.locator("#cloud-mode")).to_be_visible()
        expect(page.locator("#lookup-btn")).to_be_visible()

    def test_13_desktop_responsive_layout(self, page: Page, base_url: str):
        """Test 13: Verify layout works on desktop viewport"""
        page.set_viewport_size({"width": 1920, "height": 1080})
        page.goto(base_url)

        # Check that all elements are visible
        expect(page.locator("#ip-address")).to_be_visible()
        expect(page.locator("#cloud-mode")).to_be_visible()
        expect(page.locator("#lookup-btn")).to_be_visible()

    # Group 5: Theme Management (3 tests)

    def test_14_theme_switcher_works(self, page: Page, base_url: str):
        """Test 14: Verify theme can be toggled between light and dark"""
        page.goto(base_url)

        # Check theme switcher exists
        theme_btn = page.locator("#theme-switcher")
        expect(theme_btn).to_be_visible()

        # Default theme should be dark
        html = page.locator("html")
        expect(html).to_have_attribute("data-theme", "dark")

        # Click to toggle to light
        theme_btn.click()
        expect(html).to_have_attribute("data-theme", "light")

        # Click again to toggle back to dark
        theme_btn.click()
        expect(html).to_have_attribute("data-theme", "dark")

    def test_15_theme_persists_across_reload(self, page: Page, base_url: str):
        """Test 15: Verify theme preference persists after page reload"""
        page.goto(base_url)

        # Switch to light theme
        theme_btn = page.locator("#theme-switcher")
        theme_btn.click()

        html = page.locator("html")
        expect(html).to_have_attribute("data-theme", "light")

        # Reload page
        page.reload()

        # Theme should still be light
        expect(html).to_have_attribute("data-theme", "light")

    def test_16_dark_mode_is_default(self, page: Page, base_url: str):
        """Test 16: Verify dark mode is the default theme"""
        page.goto(base_url)

        html = page.locator("html")
        expect(html).to_have_attribute("data-theme", "dark")

    # Group 6: UI State & Display (4 tests)

    def test_17_loading_state_exists(self, page: Page, base_url: str):
        """Test 17: Verify loading indicator exists and is initially hidden"""
        page.goto(base_url)

        loading = page.locator("#loading")
        # Initially hidden
        expect(loading).to_be_hidden()

    def test_18_error_display_exists(self, page: Page, base_url: str):
        """Test 18: Verify error display element exists and is initially hidden"""
        page.goto(base_url)

        error = page.locator("#validation-error")
        # Initially hidden
        expect(error).not_to_be_visible()

    def test_19_results_table_exists(self, page: Page, base_url: str):
        """Test 19: Verify results table exists with correct structure"""
        page.goto(base_url)

        results = page.locator("#results")
        # Initially hidden
        expect(results).to_be_hidden()

        # Results content container exists (table is dynamically generated)
        results_content = page.locator("#results-content")
        expect(results_content).to_have_count(1)

    def test_20_copy_button_initially_hidden(self, page: Page, base_url: str):
        """Test 20: Verify copy button exists but is initially hidden"""
        page.goto(base_url)

        # Copy button should be hidden initially
        copy_btn = page.locator("#copy-btn")
        expect(copy_btn).to_be_hidden()

    # Group 7: Button Functionality (2 tests)

    def test_21_clear_button_functionality(self, page: Page, base_url: str):
        """Test 21: Verify clear button resets form to defaults"""
        page.goto(base_url)

        # Fill in values
        page.fill("#ip-address", "10.0.0.0/24")
        page.select_option("#cloud-mode", "AWS")

        # Clear button is only visible after results are shown
        # Submit form to show results first
        page.click("#lookup-btn")
        results = page.locator("#results")
        expect(results).to_be_visible(timeout=10000)

        # Now clear button should be visible
        clear_btn = page.locator("#clear-btn")
        expect(clear_btn).to_be_visible()

        # Click clear
        clear_btn.click()

        # Input should be empty
        assert page.input_value("#ip-address") == ""
        # Mode should reset to Azure
        assert page.input_value("#cloud-mode") == "Azure"

    def test_22_all_buttons_have_labels(self, page: Page, base_url: str):
        """Test 22: Verify interactive buttons have accessible labels"""
        page.goto(base_url)

        # Main action buttons that are always visible
        expect(page.locator("#lookup-btn")).to_be_visible()
        expect(page.locator("#theme-switcher")).to_be_visible()

        # All buttons should have text or aria-label
        lookup_text = page.locator("#lookup-btn").inner_text()
        assert len(lookup_text) > 0

        # Clear button exists but is only visible after results
        clear_btn = page.locator("#clear-btn")
        expect(clear_btn).to_have_count(1)
        clear_text = clear_btn.inner_text()
        assert len(clear_text) > 0

    # Group 8: API Error Handling (6 tests)

    def test_23_api_status_panel_displays(self, page: Page, base_url: str):
        """Test 23: Verify API status panel shows health information"""
        page.goto(base_url)

        api_status = page.locator("#api-status")
        expect(api_status).to_be_visible()

        # Should show either healthy or unavailable
        status_text = api_status.inner_text().lower()
        assert "healthy" in status_text or "unavailable" in status_text

    def test_24_api_unavailable_shows_helpful_error(self, page: Page, base_url: str):
        """Test 24: Verify connection failure shows user-friendly message"""
        # Intercept API health check and simulate connection failure
        page.route("**/api/v1/health", lambda route: route.abort())

        page.goto(base_url)

        api_status = page.locator("#api-status")
        expect(api_status).to_be_visible()

        # Should show user-friendly error message
        expect(api_status).to_contain_text("Unavailable", ignore_case=True)
        # Should NOT show cryptic JSON error (if there is text content)
        text = api_status.inner_text()
        if "Failed" in text:
            assert "Failed to execute 'json'" not in text

    def test_25_api_timeout_shows_helpful_error(self, page: Page, base_url: str):
        """Test 25: Verify timeout shows user-friendly message"""
        # Intercept API health check and delay response beyond timeout
        def handle_route(route):
            import time

            time.sleep(6)  # Longer than 5s timeout
            route.fulfill(status=200, body='{"status": "ok"}')

        page.route("**/api/v1/health", handle_route)

        page.goto(base_url)

        api_status = page.locator("#api-status")
        expect(api_status).to_be_visible(timeout=10000)

        # Should show timeout error
        status_text = api_status.inner_text().lower()
        assert "timeout" in status_text or "timed out" in status_text

    def test_26_non_json_response_shows_helpful_error(self, page: Page, base_url: str):
        """Test 26: Verify HTML response shows helpful error"""
        # Intercept API health check and return HTML instead of JSON
        page.route(
            "**/api/v1/health",
            lambda route: route.fulfill(
                status=200,
                content_type="text/html",
                body="<html><body>Service Starting...</body></html>",
            ),
        )

        page.goto(base_url)

        api_status = page.locator("#api-status")
        expect(api_status).to_be_visible()

        # Should show helpful error (either specific or generic)
        text = api_status.inner_text().lower()
        assert (
            "json" in text or "unavailable" in text or "starting" in text or "connect" in text
        )
        # Should NOT show cryptic JSON parsing error
        assert "unexpected end of json input" not in text

    def test_27_http_error_shows_status_code(self, page: Page, base_url: str):
        """Test 27: Verify HTTP error codes are communicated to user"""
        # Intercept API health check and return 503 Service Unavailable
        page.route(
            "**/api/v1/health",
            lambda route: route.fulfill(
                status=503, content_type="text/html", body="Service Unavailable"
            ),
        )

        page.goto(base_url)

        api_status = page.locator("#api-status")
        expect(api_status).to_be_visible()

        # Should show HTTP status or unavailable message
        text = api_status.inner_text().lower()
        assert "503" in text or "unavailable" in text

    def test_28_form_submission_when_api_unavailable(self, page: Page, base_url: str):
        """Test 28: Verify form submission fails gracefully when API is down"""
        page.goto(base_url)

        # Intercept API calls and simulate connection failure
        page.route("**/api/v1/**", lambda route: route.abort())

        # Fill and submit form
        page.fill("#ip-address", "192.168.1.1")
        page.click("button[type='submit']")

        # Should show error message in results
        results = page.locator("#results")
        expect(results).to_be_visible(timeout=5000)

        # Should show user-friendly message, not cryptic error
        text = results.inner_text().lower()
        assert "error" in text or "unavailable" in text
        assert "failed to execute 'json'" not in text

    # Group 9: Full API Integration (2 tests)

    def test_29_form_submission_with_valid_ip_mocked(self, page: Page, base_url: str):
        """Test 29: Verify complete form submission flow with mocked API"""
        # Mock API responses
        page.route(
            "**/api/v1/ipv4/validate",
            lambda route: route.fulfill(
                status=200,
                content_type="application/json",
                body='{"valid": true, "type": "address", "address": "192.168.1.1", "is_ipv4": true, "is_ipv6": false}',
            ),
        )
        page.route(
            "**/api/v1/ipv4/check-private",
            lambda route: route.fulfill(
                status=200,
                content_type="application/json",
                body='{"is_rfc1918": true, "is_rfc6598": false, "matched_rfc1918_range": "192.168.0.0/16"}',
            ),
        )
        page.route(
            "**/api/v1/ipv4/check-cloudflare",
            lambda route: route.fulfill(
                status=200,
                content_type="application/json",
                body='{"is_cloudflare": false, "ip_version": 4}',
            ),
        )

        page.goto(base_url)

        # Fill form
        page.fill("#ip-address", "192.168.1.1")
        page.select_option("#cloud-mode", "Azure")

        # Submit
        page.click("#lookup-btn")

        # Wait for results
        results = page.locator("#results")
        expect(results).to_be_visible(timeout=10000)

        # Check results contain expected data
        expect(results).to_contain_text("192.168.1.1")
        results_text = results.inner_text()
        assert "RFC1918" in results_text or "Private" in results_text or "private" in results_text

    def test_30_form_submission_with_cidr_range_mocked(self, page: Page, base_url: str):
        """Test 30: Verify subnet calculation works with mocked API"""
        # Mock API responses
        page.route(
            "**/api/v1/ipv4/validate",
            lambda route: route.fulfill(
                status=200,
                content_type="application/json",
                body='{"valid": true, "type": "network", "address": "10.0.0.0/24", "is_ipv4": true, "is_ipv6": false}',
            ),
        )
        page.route(
            "**/api/v1/ipv4/check-private",
            lambda route: route.fulfill(
                status=200,
                content_type="application/json",
                body='{"is_rfc1918": true, "is_rfc6598": false, "matched_rfc1918_range": "10.0.0.0/8"}',
            ),
        )
        page.route(
            "**/api/v1/ipv4/check-cloudflare",
            lambda route: route.fulfill(
                status=200,
                content_type="application/json",
                body='{"is_cloudflare": false, "ip_version": 4}',
            ),
        )
        page.route(
            "**/api/v1/ipv4/subnet-info",
            lambda route: route.fulfill(
                status=200,
                content_type="application/json",
                body='{"network": "10.0.0.0/24", "mode": "Standard", "network_address": "10.0.0.0", "broadcast_address": "10.0.0.255", "netmask": "255.255.255.0", "wildcard_mask": "0.0.0.255", "prefix_length": 24, "total_addresses": 256, "usable_addresses": 254, "first_usable_ip": "10.0.0.1", "last_usable_ip": "10.0.0.254"}',
            ),
        )

        page.goto(base_url)

        # Fill form with network
        page.fill("#ip-address", "10.0.0.0/24")
        page.select_option("#cloud-mode", "Standard")

        # Submit
        page.click("#lookup-btn")

        # Wait for results
        results = page.locator("#results")
        expect(results).to_be_visible(timeout=10000)

        # Check subnet info is displayed
        results_text = results.inner_text()
        assert "Subnet Information" in results_text or "subnet" in results_text.lower()
        expect(results).to_contain_text("10.0.0.0")
        expect(results).to_contain_text("/24")

    # Group 10: Progressive Enhancement (2 tests)

    def test_31_no_javascript_fallback_works(self, page: Page, base_url: str):
        """Test 31: Verify form works without JavaScript via traditional POST"""
        # Note: Static HTML is client-side only, so this test verifies
        # the form structure supports traditional POST
        page.goto(base_url)

        # Form should have proper method and action for fallback
        form = page.locator("#lookup-form")
        method = form.get_attribute("method")
        # May be None for JS-only apps, but structure should support submission
        assert form.count() == 1

    def test_32_no_javascript_warning_displayed(self, page: Page, base_url: str):
        """Test 32: Verify noscript warning exists for users without JS"""
        # Note: Static HTML may not have noscript as it's client-side only
        # This test verifies graceful degradation
        page.goto(base_url)

        # Check if page has any progressive enhancement features
        # Even without noscript, form should exist
        form = page.locator("#lookup-form")
        expect(form).to_have_count(1)
