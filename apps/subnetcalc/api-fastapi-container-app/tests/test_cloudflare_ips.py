"""Tests for the cloudflare_ips module."""

from __future__ import annotations

import socket
from urllib.error import HTTPError, URLError
from ipaddress import IPv4Network, IPv6Network
from unittest.mock import MagicMock, patch

import pytest

# Import module for cache manipulation in fixtures
from app import cloudflare_ips

# Import specific functions for tests
from app.cloudflare_ips import (
    FALLBACK_IPV4_RANGES,
    FALLBACK_IPV6_RANGES,
    get_cloudflare_ipv4_ranges,
    get_cloudflare_ipv6_ranges,
    get_cloudflare_ranges_info,
    refresh_cloudflare_ranges,
)


@pytest.fixture(autouse=True)
def reset_cache():
    """Reset the module cache before each test."""
    cloudflare_ips._cached_ipv4_ranges = None
    cloudflare_ips._cached_ipv6_ranges = None
    cloudflare_ips._cache_source_ipv4 = "not_loaded"
    cloudflare_ips._cache_source_ipv6 = "not_loaded"
    yield
    # Reset after test as well
    cloudflare_ips._cached_ipv4_ranges = None
    cloudflare_ips._cached_ipv6_ranges = None
    cloudflare_ips._cache_source_ipv4 = "not_loaded"
    cloudflare_ips._cache_source_ipv6 = "not_loaded"


class TestFallbackRanges:
    """Tests for fallback range constants."""

    def test_fallback_ipv4_ranges_not_empty(self):
        """Verify fallback IPv4 ranges are defined."""
        assert len(FALLBACK_IPV4_RANGES) > 0

    def test_fallback_ipv6_ranges_not_empty(self):
        """Verify fallback IPv6 ranges are defined."""
        assert len(FALLBACK_IPV6_RANGES) > 0

    def test_fallback_ipv4_ranges_are_networks(self):
        """Verify fallback IPv4 ranges are IPv4Network objects."""
        for network in FALLBACK_IPV4_RANGES:
            assert isinstance(network, IPv4Network)

    def test_fallback_ipv6_ranges_are_networks(self):
        """Verify fallback IPv6 ranges are IPv6Network objects."""
        for network in FALLBACK_IPV6_RANGES:
            assert isinstance(network, IPv6Network)

    def test_known_ipv4_ranges_in_fallback(self):
        """Verify known Cloudflare IPv4 ranges are in fallback."""
        fallback_strs = [str(r) for r in FALLBACK_IPV4_RANGES]
        assert "104.16.0.0/13" in fallback_strs
        assert "173.245.48.0/20" in fallback_strs

    def test_known_ipv6_ranges_in_fallback(self):
        """Verify known Cloudflare IPv6 ranges are in fallback."""
        fallback_strs = [str(r) for r in FALLBACK_IPV6_RANGES]
        assert "2606:4700::/32" in fallback_strs


class TestFetchSuccess:
    """Tests for successful fetch from Cloudflare."""

    @patch("app.cloudflare_ips.urlopen")
    def test_fetch_ipv4_success(self, mock_urlopen):
        """Test successful IPv4 range fetch."""
        mock_response = MagicMock()
        mock_response.read.return_value = b"104.16.0.0/13\n173.245.48.0/20\n"
        mock_urlopen.return_value.__enter__.return_value = mock_response

        ranges = get_cloudflare_ipv4_ranges()

        assert len(ranges) == 2
        assert all(isinstance(r, IPv4Network) for r in ranges)
        assert cloudflare_ips._cache_source_ipv4 == "cloudflare"

    @patch("app.cloudflare_ips.urlopen")
    def test_fetch_ipv6_success(self, mock_urlopen):
        """Test successful IPv6 range fetch."""
        mock_response = MagicMock()
        mock_response.read.return_value = b"2606:4700::/32\n2400:cb00::/32\n"
        mock_urlopen.return_value.__enter__.return_value = mock_response

        ranges = get_cloudflare_ipv6_ranges()

        assert len(ranges) == 2
        assert all(isinstance(r, IPv6Network) for r in ranges)
        assert cloudflare_ips._cache_source_ipv6 == "cloudflare"


class TestFetchFailure:
    """Tests for fallback when fetch fails."""

    @patch("app.cloudflare_ips.urlopen")
    def test_timeout_falls_back_to_hardcoded(self, mock_urlopen):
        """Test that timeout falls back to hardcoded ranges."""
        mock_urlopen.side_effect = socket.timeout("Timeout")

        ranges = get_cloudflare_ipv4_ranges()

        assert ranges == FALLBACK_IPV4_RANGES
        assert cloudflare_ips._cache_source_ipv4 == "fallback"

    @patch("app.cloudflare_ips.urlopen")
    def test_http_error_falls_back_to_hardcoded(self, mock_urlopen):
        """Test that HTTP error falls back to hardcoded ranges."""
        mock_urlopen.side_effect = HTTPError(
            url="https://www.cloudflare.com/ips-v4/",
            code=404,
            msg="Not Found",
            hdrs=None,
            fp=None,
        )

        ranges = get_cloudflare_ipv4_ranges()

        assert ranges == FALLBACK_IPV4_RANGES
        assert cloudflare_ips._cache_source_ipv4 == "fallback"

    @patch("app.cloudflare_ips.urlopen")
    def test_connection_error_falls_back_to_hardcoded(self, mock_urlopen):
        """Test that connection error falls back to hardcoded ranges."""
        mock_urlopen.side_effect = URLError("Connection refused")

        ranges = get_cloudflare_ipv6_ranges()

        assert ranges == FALLBACK_IPV6_RANGES
        assert cloudflare_ips._cache_source_ipv6 == "fallback"

    @patch("app.cloudflare_ips.urlopen")
    def test_empty_response_falls_back_to_hardcoded(self, mock_urlopen):
        """Test that empty response falls back to hardcoded ranges."""
        mock_response = MagicMock()
        mock_response.read.return_value = b""
        mock_urlopen.return_value.__enter__.return_value = mock_response

        ranges = get_cloudflare_ipv4_ranges()

        assert ranges == FALLBACK_IPV4_RANGES
        assert cloudflare_ips._cache_source_ipv4 == "fallback"


class TestCaching:
    """Tests for caching behavior."""

    @patch("app.cloudflare_ips.urlopen")
    def test_cache_prevents_repeated_fetches(self, mock_urlopen):
        """Test that cached results prevent repeated network calls."""
        mock_response = MagicMock()
        mock_response.read.return_value = b"104.16.0.0/13\n"
        mock_urlopen.return_value.__enter__.return_value = mock_response

        # First call
        get_cloudflare_ipv4_ranges()
        # Second call should use cache
        get_cloudflare_ipv4_ranges()

        # urlopen should only be called once
        assert mock_urlopen.call_count == 1


class TestRangesInfo:
    """Tests for get_cloudflare_ranges_info function."""

    @patch("app.cloudflare_ips.urlopen")
    def test_ranges_info_structure(self, mock_urlopen):
        """Test that ranges info returns correct structure."""
        # Make fetch fail to use fallback
        mock_urlopen.side_effect = socket.timeout("Timeout")

        info = get_cloudflare_ranges_info()

        assert "ipv4" in info
        assert "ipv6" in info
        assert "source" in info["ipv4"]
        assert "count" in info["ipv4"]
        assert "ranges" in info["ipv4"]
        assert "source" in info["ipv6"]
        assert "count" in info["ipv6"]
        assert "ranges" in info["ipv6"]


class TestRefresh:
    """Tests for refresh_cloudflare_ranges function."""

    @patch("app.cloudflare_ips.urlopen")
    def test_refresh_clears_cache(self, mock_urlopen):
        """Test that refresh clears the cache and fetches fresh data."""
        mock_response = MagicMock()
        mock_response.read.return_value = b"104.16.0.0/13\n"
        mock_urlopen.return_value.__enter__.return_value = mock_response

        # First call to populate cache
        get_cloudflare_ipv4_ranges()

        # Refresh should clear cache and fetch again
        result = refresh_cloudflare_ranges()

        # urlopen should be called multiple times (once for initial, twice for refresh)
        assert mock_urlopen.call_count >= 2
        assert "ipv4" in result
        assert "ipv6" in result
