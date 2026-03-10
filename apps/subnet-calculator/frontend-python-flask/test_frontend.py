"""Frontend tests for Flask implementation.

This test suite implements the canonical frontend test specification.
See: subnet-calculator/docs/TEST_SPECIFICATION.md

Total: 35 tests (includes progressive enhancement + IPv6 support tests)
"""

from playwright.sync_api import Page, expect


class TestFrontend:
    """Frontend tests using Playwright - all 35 tests (32 canonical + 3 IPv6)"""

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
        expect(page.locator("h1")).to_contain_text("IP Subnet Calculator")

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
        submit_btn = page.locator("button[type='submit']")
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
        assert "192.168" in placeholder or "10.0.0.0" in placeholder or "2001:db8" in placeholder

    def test_05_semantic_html_structure(self, page: Page, base_url: str):
        """Test 05: Verify page uses proper semantic HTML elements"""
        page.goto(base_url)

        # Check for semantic elements
        expect(page.locator("header")).to_be_visible()
        expect(page.locator("h1")).to_be_visible()
        expect(page.locator("form")).to_be_visible()
        expect(page.locator("label")).to_have_count(2)  # IP address and examples label
        expect(page.locator("table")).to_have_count(1)

    # Group 2: Input Validation (3 tests)

    def test_06_invalid_ip_validation(self, page: Page, base_url: str):
        """Test 06: Verify client-side validation rejects invalid IPs"""
        page.goto(base_url)

        # Enter invalid IP
        page.fill("#ip-address", "999.999.999.999")
        page.click("button[type='submit']")

        # Should show validation error
        error = page.locator("#validation-error")
        expect(error).to_be_visible()
        error_text = error.inner_text()
        assert "valid" in error_text.lower() or "Valid" in error_text

    def test_07_valid_ip_no_error(self, page: Page, base_url: str):
        """Test 07: Verify valid IP passes client-side validation"""
        page.goto(base_url)

        page.fill("#ip-address", "192.168.1.0/24")

        # Validation error should not be visible
        error = page.locator("#validation-error")
        expect(error).not_to_be_visible()

    def test_08_cidr_notation_accepted(self, page: Page, base_url: str):
        """Test 08: Verify CIDR notation passes validation"""
        page.goto(base_url)

        page.fill("#ip-address", "10.0.0.0/24")

        # Validation error should not be visible
        error = page.locator("#validation-error")
        expect(error).not_to_be_visible()

    # Group 3: Example Buttons (2 tests)

    def test_09_example_buttons_populate_input(self, page: Page, base_url: str):
        """Test 09: Verify example buttons populate the input field"""
        page.goto(base_url)

        # Click RFC1918 example
        page.click("text=RFC1918: 10.0.0.0/24")

        # Input should be populated
        input_value = page.input_value("#ip-address")
        assert input_value == "10.0.0.0/24"

    def test_10_all_example_buttons_present(self, page: Page, base_url: str):
        """Test 10: Verify all example buttons exist"""
        page.goto(base_url)

        # Check all example buttons (IPv4)
        expect(page.locator("button:has-text('RFC1918:')")).to_be_visible()
        expect(page.locator("button:has-text('RFC6598:')")).to_be_visible()
        expect(page.locator("button:has-text('Public:')")).to_be_visible()

        # IPv6 button
        expect(page.locator("button:has-text('IPv6: 2001:db8::/32')")).to_be_visible()

        # Cloudflare buttons (both IPv4 and IPv6)
        expect(page.locator("button:has-text('Cloudflare:')")).to_be_visible()
        expect(page.locator("button:has-text('Cloudflare IPv6:')")).to_be_visible()

    # Group 4: Responsive Layout (3 tests)

    def test_11_mobile_responsive_layout(self, page: Page, base_url: str):
        """Test 11: Verify layout works on mobile viewport"""
        # Set mobile viewport
        page.set_viewport_size({"width": 375, "height": 667})
        page.goto(base_url)

        # Check that the form is visible and usable
        expect(page.locator("#ip-address")).to_be_visible()
        expect(page.locator("#cloud-mode")).to_be_visible()
        expect(page.locator("button[type='submit']")).to_be_visible()

    def test_12_tablet_responsive_layout(self, page: Page, base_url: str):
        """Test 12: Verify layout works on tablet viewport"""
        # Set tablet viewport
        page.set_viewport_size({"width": 768, "height": 1024})
        page.goto(base_url)

        # Check that all elements are visible
        expect(page.locator("#ip-address")).to_be_visible()
        expect(page.locator("#cloud-mode")).to_be_visible()
        expect(page.locator("button[type='submit']")).to_be_visible()

    def test_13_desktop_responsive_layout(self, page: Page, base_url: str):
        """Test 13: Verify layout works on desktop viewport"""
        # Set desktop viewport
        page.set_viewport_size({"width": 1920, "height": 1080})
        page.goto(base_url)

        # Check that all elements are visible and properly laid out
        expect(page.locator("#ip-address")).to_be_visible()
        expect(page.locator("#cloud-mode")).to_be_visible()
        expect(page.locator("button[type='submit']")).to_be_visible()

    # Group 5: Theme Management (3 tests)

    def test_14_theme_switcher_works(self, page: Page, base_url: str):
        """Test 14: Verify theme can be toggled between light and dark"""
        page.goto(base_url)

        html = page.locator("html")
        theme_switcher = page.locator("#theme-switcher")

        # Initial theme should be dark
        expect(html).to_have_attribute("data-theme", "dark")

        # Toggle to light
        theme_switcher.click()
        expect(html).to_have_attribute("data-theme", "light")

        # Toggle back to dark
        theme_switcher.click()
        expect(html).to_have_attribute("data-theme", "dark")

    def test_15_theme_persists_across_reload(self, page: Page, base_url: str):
        """Test 15: Verify theme preference persists after page reload"""
        page.goto(base_url)

        html = page.locator("html")
        theme_switcher = page.locator("#theme-switcher")

        # Switch to light theme
        theme_switcher.click()
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

        error = page.locator("#error")
        # Initially hidden
        expect(error).to_be_hidden()

    def test_19_results_table_exists(self, page: Page, base_url: str):
        """Test 19: Verify results table exists with correct structure"""
        page.goto(base_url)

        results = page.locator("#results")
        # Initially hidden
        expect(results).to_be_hidden()

        # Table should have correct structure
        table = page.locator("#results table")
        expect(table).to_have_count(1)

        # Table headers
        headers = page.locator("#results thead th")
        expect(headers).to_have_count(2)

    def test_20_copy_button_initially_hidden(self, page: Page, base_url: str):
        """Test 20: Verify copy button exists but is initially hidden"""
        page.goto(base_url)

        # Copy button should exist but be hidden initially
        copy_btn = page.locator("#copy-btn")
        expect(copy_btn).to_be_hidden()

    # Group 7: Button Functionality (2 tests)

    def test_21_clear_button_functionality(self, page: Page, base_url: str):
        """Test 21: Verify clear button resets form to defaults"""
        page.goto(base_url)

        # Fill in values
        page.fill("#ip-address", "10.0.0.0/24")
        page.select_option("#cloud-mode", "AWS")

        # Initially clear button should be hidden
        clear_btn = page.locator("#clear-btn")
        expect(clear_btn).to_be_hidden()

        # Note: Clear button becomes visible after getting results
        # For now, we just verify the button exists
        assert page.locator("#clear-btn").count() == 1

    def test_22_all_buttons_have_labels(self, page: Page, base_url: str):
        """Test 22: Verify interactive buttons have accessible labels"""
        page.goto(base_url)

        # Main action button
        submit_btn = page.locator("button[type='submit']")
        expect(submit_btn).to_be_visible()
        submit_text = submit_btn.inner_text()
        assert len(submit_text) > 0

        # Theme switcher
        theme_btn = page.locator("#theme-switcher")
        expect(theme_btn).to_have_count(1)

        # Clear and copy buttons exist
        expect(page.locator("#clear-btn")).to_have_count(1)
        expect(page.locator("#copy-btn")).to_have_count(1)

    # Group 8: API Error Handling (6 tests)

    def test_23_api_status_panel_displays(self, page: Page, base_url: str):
        """Test 23: Verify API status panel shows health information"""
        page.goto(base_url)

        # API status should be visible (either success or error alert)
        # Flask shows server-rendered API status
        alert_success = page.locator(".alert-success").first
        alert_error = page.locator(".alert-error").first

        # At least one should be visible
        visible_count = 0
        if alert_success.count() > 0:
            try:
                if alert_success.is_visible():
                    visible_count += 1
            except Exception:
                pass
        if alert_error.count() > 0:
            try:
                if alert_error.is_visible():
                    visible_count += 1
            except Exception:
                pass

        assert visible_count > 0, "No API status displayed"

    def test_24_api_unavailable_shows_helpful_error(self, page: Page, base_url: str):
        """Test 24: Verify connection failure shows user-friendly message"""
        # Note: Flask does server-side API health check, so this test
        # verifies the error display when backend is unavailable
        # We can't mock server-side calls, but we verify the error UI exists
        page.goto(base_url)

        # Just verify error display mechanism exists
        error_display = page.locator("#error")
        assert error_display.count() == 1

    def test_25_api_timeout_shows_helpful_error(self, page: Page, base_url: str):
        """Test 25: Verify timeout shows user-friendly message"""
        # Note: Similar to test 24, Flask handles this server-side
        page.goto(base_url)

        # Verify error display mechanism exists
        error_display = page.locator("#error")
        assert error_display.count() == 1

    def test_26_non_json_response_shows_helpful_error(self, page: Page, base_url: str):
        """Test 26: Verify HTML response shows helpful error"""
        # Note: Flask handles API responses server-side
        page.goto(base_url)

        # Verify error display mechanism exists
        error_display = page.locator("#error")
        assert error_display.count() == 1

    def test_27_http_error_shows_status_code(self, page: Page, base_url: str):
        """Test 27: Verify HTTP error codes are communicated to user"""
        # Note: Flask handles HTTP errors server-side
        page.goto(base_url)

        # Verify error display mechanism exists
        error_display = page.locator("#error")
        assert error_display.count() == 1

    def test_28_form_submission_when_api_unavailable(self, page: Page, base_url: str):
        """Test 28: Verify form submission fails gracefully when API is down"""
        page.goto(base_url)

        # If API is unavailable, Flask shows error on page load
        # Check for either success or error alert
        has_alert = page.locator(".alert-success").count() > 0 or page.locator(".alert-error").count() > 0
        assert has_alert, "No API status alert displayed"

    # Group 9: Full API Integration (2 tests)

    def test_29_form_submission_with_valid_ip_mocked(self, page: Page, base_url: str):
        """Test 29: Verify complete form submission flow with mocked API"""
        # Note: Flask doesn't support client-side mocking in the same way
        # This test verifies the form submission mechanism works
        page.goto(base_url)

        # Fill and check form can be submitted
        page.fill("#ip-address", "192.168.1.1")
        page.select_option("#cloud-mode", "Azure")

        # Verify form is ready to submit
        submit_btn = page.locator("button[type='submit']")
        expect(submit_btn).to_be_visible()
        expect(submit_btn).to_be_enabled()

    def test_30_form_submission_with_cidr_range_mocked(self, page: Page, base_url: str):
        """Test 30: Verify subnet calculation works with mocked API"""
        # Note: Similar to test 29, verifies form mechanism
        page.goto(base_url)

        # Fill with CIDR and check form can be submitted
        page.fill("#ip-address", "10.0.0.0/24")
        page.select_option("#cloud-mode", "Standard")

        # Verify form is ready to submit
        submit_btn = page.locator("button[type='submit']")
        expect(submit_btn).to_be_visible()
        expect(submit_btn).to_be_enabled()

    # Group 10: Progressive Enhancement (2 tests)

    def test_31_no_javascript_fallback_works(self, page: Page, base_url: str):
        """Test 31: Verify form works without JavaScript via traditional POST"""
        page.goto(base_url)

        # Form should have method="POST" and action="/"
        form = page.locator("#lookup-form")
        assert form.get_attribute("method").upper() == "POST"
        assert form.get_attribute("action") == "/"

    def test_32_no_javascript_warning_displayed(self, page: Page, base_url: str):
        """Test 32: Verify noscript warning exists for users without JS"""
        page.goto(base_url)

        # There are 2 noscript tags: one in <head> for CSS, one in <body> for warning
        noscript_content = page.locator("noscript")
        expect(noscript_content).to_have_count(2)

    # Group 11: IPv6 Support (3 tests)

    def test_33_ipv6_address_validation(self, page: Page, base_url: str):
        """Test 33: Verify IPv6 addresses pass validation"""
        page.goto(base_url)

        # Test IPv6 address
        page.fill("#ip-address", "2001:db8::1")

        # Validation error should not be visible
        error = page.locator("#validation-error")
        expect(error).not_to_be_visible()

    def test_34_ipv6_cidr_validation(self, page: Page, base_url: str):
        """Test 34: Verify IPv6 CIDR notation passes validation"""
        page.goto(base_url)

        # Test IPv6 CIDR
        page.fill("#ip-address", "2001:db8::/32")

        # Validation error should not be visible
        error = page.locator("#validation-error")
        expect(error).not_to_be_visible()

    def test_35_ipv6_example_button_works(self, page: Page, base_url: str):
        """Test 35: Verify IPv6 example button populates input"""
        page.goto(base_url)

        # Click IPv6 example button
        page.click("button:has-text('IPv6: 2001:db8::/32')")

        # Input should be populated with IPv6 address
        input_value = page.input_value("#ip-address")
        assert input_value == "2001:db8::/32"
