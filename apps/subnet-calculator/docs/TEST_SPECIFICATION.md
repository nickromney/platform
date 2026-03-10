# Frontend Test Specification

This document defines the complete test suite for all subnet calculator frontends.

## Overview

All frontends should implement identical behavior tests to ensure consistency across implementations. This specification defines 32 test scenarios that cover:

- Basic page functionality
- Input validation
- Theme management
- Responsive design
- API error handling
- Progressive enhancement (where applicable)
- Full integration tests

## Test Execution Requirements

- Each frontend must run the same set of tests
- Tests must be numbered and ordered identically
- Tests use Playwright for consistent browser automation
- All tests should pass for each implementation

## Current Test Counts

- **Flask Frontend**: Target 32 tests
- **Static HTML Frontend**: Target 32 tests
- **TypeScript Vite Frontend**: Target 30 tests (excludes 2 progressive enhancement tests)

---

## Canonical Test Suite

### Group 1: Basic Page & Elements (5 tests)

#### Test 01: Page Loads Successfully

**Description**: Verify the page loads and displays the main heading
**Applies to**: All frontends
**Assertions**:

- Page loads without errors
- H1 element contains "IPv4 Subnet Calculator"

#### Test 02: Form Elements Are Present

**Description**: Verify all required form elements exist and are visible
**Applies to**: All frontends
**Assertions**:

- IP address input field is visible
- Cloud mode selector is visible
- Submit button is visible
- Input has appropriate placeholder text

#### Test 03: Cloud Mode Selector Has All Options

**Description**: Verify cloud mode selector has correct options and default
**Applies to**: All frontends
**Assertions**:

- Selector has exactly 4 options (Standard, AWS, Azure, OCI)
- Default selected value is "Azure"
- Can change selection to other modes

#### Test 04: Input Placeholder Text

**Description**: Verify input field has helpful placeholder text
**Applies to**: All frontends
**Assertions**:

- Placeholder text exists
- Contains example IP format

#### Test 05: Semantic HTML Structure

**Description**: Verify page uses proper semantic HTML elements
**Applies to**: All frontends
**Assertions**:

- Header element exists and is visible
- H1 element exists and is visible
- Form element exists
- Main/section elements present
- Proper label elements for inputs

---

### Group 2: Input Validation (3 tests)

#### Test 06: Invalid IP Validation

**Description**: Verify client-side validation rejects invalid IPs
**Applies to**: All frontends
**Actions**:

- Fill input with "999.999.999.999"
- Click submit button
**Assertions**:
- Validation error is visible
- Error message mentions "valid" or "Invalid"

#### Test 07: Valid IP No Error

**Description**: Verify valid IP passes client-side validation
**Applies to**: All frontends
**Actions**:

- Fill input with "192.168.1.0/24"
**Assertions**:
- Validation error is NOT visible

#### Test 08: CIDR Notation Accepted

**Description**: Verify CIDR notation passes validation
**Applies to**: All frontends
**Actions**:

- Fill input with "10.0.0.0/24"
**Assertions**:
- Validation error is NOT visible

---

### Group 3: Example Buttons (2 tests)

#### Test 09: Example Buttons Populate Input

**Description**: Verify example buttons populate the input field
**Applies to**: All frontends
**Actions**:

- Click RFC1918 example button
**Assertions**:
- Input value equals "10.0.0.0/24"

#### Test 10: All Example Buttons Present

**Description**: Verify all example buttons exist
**Applies to**: All frontends
**Assertions**:

- RFC1918 button visible (class: btn-rfc1918)
- RFC6598 button visible (class: btn-rfc6598)
- Public IP button visible (class: btn-public)
- Cloudflare button visible (class: btn-cloudflare)

---

### Group 4: Responsive Layout (3 tests)

#### Test 11: Mobile Responsive Layout

**Description**: Verify layout works on mobile viewport
**Applies to**: All frontends
**Viewport**: 375x667
**Assertions**:

- IP address input is visible
- Cloud mode selector is visible
- Submit button is visible

#### Test 12: Tablet Responsive Layout

**Description**: Verify layout works on tablet viewport
**Applies to**: All frontends
**Viewport**: 768x1024
**Assertions**:

- IP address input is visible
- Cloud mode selector is visible
- Submit button is visible

#### Test 13: Desktop Responsive Layout

**Description**: Verify layout works on desktop viewport
**Applies to**: All frontends
**Viewport**: 1920x1080
**Assertions**:

- IP address input is visible
- Cloud mode selector is visible
- Submit button is visible

---

### Group 5: Theme Management (3 tests)

#### Test 14: Theme Switcher Works

**Description**: Verify theme can be toggled between light and dark
**Applies to**: Flask, Static HTML, TypeScript
**Actions**:

- Check initial theme is "dark"
- Click theme switcher
- Click theme switcher again
**Assertions**:
- HTML data-theme attribute changes from dark to light to dark
- Theme icon updates accordingly

#### Test 15: Theme Persists Across Reload

**Description**: Verify theme preference persists after page reload
**Applies to**: Flask, Static HTML, TypeScript
**Actions**:

- Switch to light theme
- Reload page
**Assertions**:
- Theme is still "light" after reload

#### Test 16: Dark Mode Is Default

**Description**: Verify dark mode is the default theme
**Applies to**: Flask, Static HTML, TypeScript
**Assertions**:

- HTML data-theme attribute equals "dark" on load

---

### Group 6: UI State & Display (4 tests)

#### Test 17: Loading State Exists

**Description**: Verify loading indicator exists and is initially hidden
**Applies to**: All frontends
**Assertions**:

- Loading element exists (id: loading)
- Initially hidden/not visible

#### Test 18: Error Display Exists

**Description**: Verify error display element exists and is initially hidden
**Applies to**: All frontends
**Assertions**:

- Error element exists
- Initially hidden/not visible

#### Test 19: Results Table Exists

**Description**: Verify results table exists with correct structure
**Applies to**: All frontends
**Assertions**:

- Results section exists (id: results)
- Initially hidden
- Contains table element
- Table has proper header structure

#### Test 20: Copy Button Initially Hidden

**Description**: Verify copy button exists but is initially hidden
**Applies to**: All frontends
**Assertions**:

- Copy button exists (id: copy-btn)
- Initially hidden/not visible

---

### Group 7: Button Functionality (2 tests)

#### Test 21: Clear Button Functionality

**Description**: Verify clear button resets form to defaults
**Applies to**: All frontends
**Actions**:

- Fill input with "10.0.0.0/24"
- Select cloud mode "AWS"
- Click clear button
**Assertions**:
- Input value is empty
- Cloud mode reset to "Azure"

#### Test 22: All Buttons Have Labels

**Description**: Verify interactive buttons have accessible labels
**Applies to**: All frontends
**Assertions**:

- Lookup button has visible text
- Clear button exists
- Theme switcher exists
- All buttons have text or aria-label

---

### Group 8: API Error Handling (6 tests)

#### Test 23: API Status Panel Displays

**Description**: Verify API status panel shows health information
**Applies to**: All frontends
**Assertions**:

- API status element is visible (id: api-status)
- Shows either "healthy" or "Unavailable" status

#### Test 24: API Unavailable Shows Helpful Error

**Description**: Verify connection failure shows user-friendly message
**Applies to**: All frontends
**Mock**: Abort health check API call
**Assertions**:

- API status shows "Unavailable"
- NO cryptic error messages like "Failed to execute 'json'"

#### Test 25: API Timeout Shows Helpful Error

**Description**: Verify timeout shows user-friendly message
**Applies to**: All frontends
**Mock**: Delay health check response >5 seconds
**Assertions**:

- Shows timeout or "starting up" message
- NO generic errors

#### Test 26: Non-JSON Response Shows Helpful Error

**Description**: Verify HTML response (e.g., during startup) shows helpful error
**Applies to**: All frontends
**Mock**: Return HTML instead of JSON from health check
**Assertions**:

- Shows "did not return JSON" or "starting up" message
- NO "Unexpected end of JSON input" error

#### Test 27: HTTP Error Shows Status Code

**Description**: Verify HTTP error codes are communicated to user
**Applies to**: All frontends
**Mock**: Return 503 Service Unavailable
**Assertions**:

- Shows "503" or "unavailable" in message

#### Test 28: Form Submission When API Unavailable

**Description**: Verify form submission fails gracefully when API is down
**Applies to**: All frontends
**Mock**: Abort all API calls
**Actions**:

- Fill input with "192.168.1.1"
- Submit form
**Assertions**:
- Error message displayed
- User-friendly error text (not cryptic)

---

### Group 9: Full API Integration (2 tests)

#### Test 29: Form Submission with Valid IP (Mocked)

**Description**: Verify complete form submission flow with mocked API
**Applies to**: All frontends
**Mock**: Mock all API endpoints with success responses
**Actions**:

- Fill input with "192.168.1.1"
- Select cloud mode "Azure"
- Submit form
**Assertions**:
- Results section becomes visible
- Results contain "192.168.1.1"
- Shows RFC1918/Private classification

#### Test 30: Form Submission with CIDR Range (Mocked)

**Description**: Verify subnet calculation works with mocked API
**Applies to**: All frontends
**Mock**: Mock all API endpoints including subnet-info
**Actions**:

- Fill input with "10.0.0.0/24"
- Select cloud mode "Standard"
- Submit form
**Assertions**:
- Results section becomes visible
- Shows "Subnet Information"
- Contains network address "10.0.0.0"
- Shows prefix "/24"

---

### Group 10: Progressive Enhancement (2 tests)

**Note**: These tests only apply to Flask and Static HTML frontends that support no-JavaScript fallback.

#### Test 31: No JavaScript Fallback Works

**Description**: Verify form works without JavaScript via traditional POST
**Applies to**: Flask, Static HTML only
**Assertions**:

- Form has method="POST"
- Form has action="/"
- Form can be submitted without JS

#### Test 32: No JavaScript Warning Displayed

**Description**: Verify noscript warning exists for users without JS
**Applies to**: Flask, Static HTML only
**Assertions**:

- Noscript tags exist (count: 2 for Flask/Static)
- One in head for CSS, one in body for message

---

## Test Naming Convention

### Python (Flask, Static HTML)

- Method naming: `test_01_page_loads`, `test_02_form_elements_present`, etc.
- Class: `TestFrontend`
- Framework: pytest + playwright

### TypeScript (Vite)

- Test naming: `test('01 - page loads successfully', ...)`
- Suite: `test.describe('Frontend Tests', ...)`
- Framework: Playwright Test (@playwright/test)

---

## Implementation Notes

### Test Order Requirements

1. Tests MUST be numbered 01-32 (or 01-30 for TypeScript)
1. Tests MUST appear in the same order in each file
1. Tests MUST use identical assertions where possible
1. Skip tests that don't apply using appropriate framework mechanisms:

- Python: `pytest.mark.skip` decorator
- TypeScript: `test.skip()` method

### Element ID Requirements

All frontends use these standard IDs:

- `#ip-address` - Main input field
- `#cloud-mode` - Cloud mode selector
- `#lookup-btn` or `button[type='submit']` - Submit button
- `#theme-switcher` - Theme toggle button
- `#loading` - Loading indicator
- `#results` - Results section
- `#copy-btn` - Copy button
- `#clear-btn` - Clear button
- `#validation-error` - Client-side validation error
- `#api-status` - API health status panel

### Button Classes

- `.btn-rfc1918` - RFC1918 example button
- `.btn-rfc6598` - RFC6598 example button
- `.btn-public` - Public IP example button
- `.btn-cloudflare` - Cloudflare IP example button

---

## Test Execution

### Local Development

Each frontend should support:

```bash
# Python frontends
cd subnet-calculator/frontend-{flask|html-static}
uv run pytest -v

# TypeScript frontend
cd subnet-calculator/frontend-typescript-vite
npm test
```

### Docker Compose

```bash
cd subnet-calculator
podman-compose up -d

# Run tests against running containers
cd frontend-python-flask
uv run pytest --base-url=http://localhost:8000 -v

cd frontend-html-static
uv run pytest --base-url=http://localhost:8001 -v

cd frontend-typescript-vite
BASE_URL=http://localhost:3000 npm test
```

### Root Makefile

```bash
# From repository root
make test # Run all tests
make python-test # Run Python tests only
make typescript-test # Run TypeScript tests only
```

---

## Success Criteria

- [ ] All frontends implement the same test scenarios
- [ ] Tests are numbered and ordered identically
- [ ] Flask: 32/32 tests pass
- [ ] Static HTML: 32/32 tests pass
- [ ] TypeScript: 30/30 tests pass (skips tests 31-32)
- [ ] Tests can run locally and via Docker Compose
- [ ] Root Makefile can run all tests
- [ ] All element IDs are consistent across frontends
- [ ] Default cloud mode is "Azure" everywhere
