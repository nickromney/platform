"""
Cloudflare IP range management with dynamic fetching and fallback.

This module provides Cloudflare IP ranges for validation purposes.
It attempts to fetch the latest ranges from Cloudflare's published endpoints,
falling back to hardcoded ranges if the endpoints are unavailable.

Cloudflare publishes their IP ranges at:
- IPv4: https://www.cloudflare.com/ips-v4/
- IPv6: https://www.cloudflare.com/ips-v6/
"""

import logging
from ipaddress import IPv4Network, IPv6Network, ip_network

import httpx

logger = logging.getLogger(__name__)

# Cloudflare IP range endpoints
CLOUDFLARE_IPV4_URL = "https://www.cloudflare.com/ips-v4/"
CLOUDFLARE_IPV6_URL = "https://www.cloudflare.com/ips-v6/"

# Request timeout in seconds
REQUEST_TIMEOUT = 5.0

# Fallback IPv4 Ranges (last updated: 2025-01)
FALLBACK_IPV4_RANGES: list[IPv4Network] = [
    ip_network("173.245.48.0/20"),
    ip_network("103.21.244.0/22"),
    ip_network("103.22.200.0/22"),
    ip_network("103.31.4.0/22"),
    ip_network("141.101.64.0/18"),
    ip_network("108.162.192.0/18"),
    ip_network("190.93.240.0/20"),
    ip_network("188.114.96.0/20"),
    ip_network("197.234.240.0/22"),
    ip_network("198.41.128.0/17"),
    ip_network("162.158.0.0/15"),
    ip_network("104.16.0.0/13"),
    ip_network("104.24.0.0/14"),
    ip_network("172.64.0.0/13"),
    ip_network("131.0.72.0/22"),
]

# Fallback IPv6 Ranges (last updated: 2025-01)
FALLBACK_IPV6_RANGES: list[IPv6Network] = [
    ip_network("2400:cb00::/32"),
    ip_network("2606:4700::/32"),
    ip_network("2803:f800::/32"),
    ip_network("2405:b500::/32"),
    ip_network("2405:8100::/32"),
    ip_network("2a06:98c0::/29"),
    ip_network("2c0f:f248::/32"),
]

# Cache for fetched ranges
_cached_ipv4_ranges: list[IPv4Network] | None = None
_cached_ipv6_ranges: list[IPv6Network] | None = None
_cache_source_ipv4: str = "not_loaded"
_cache_source_ipv6: str = "not_loaded"


def _fetch_ip_ranges(url: str) -> list[str] | None:
    """
    Fetch IP ranges from Cloudflare's published endpoint.

    Args:
        url: The Cloudflare IP ranges URL

    Returns:
        List of IP range strings, or None if fetch failed
    """
    try:
        with httpx.Client(timeout=REQUEST_TIMEOUT) as client:
            response = client.get(url)
            response.raise_for_status()

            # Parse the response - one CIDR per line
            content = response.text.strip()
            ranges = [line.strip() for line in content.split("\n") if line.strip()]

            if not ranges:
                logger.warning("Empty response from %s", url)
                return None

            logger.info("Successfully fetched %d IP ranges from %s", len(ranges), url)
            return ranges

    except httpx.TimeoutException:
        logger.warning("Timeout fetching Cloudflare IP ranges from %s", url)
        return None
    except httpx.HTTPStatusError as e:
        logger.warning("HTTP error fetching Cloudflare IP ranges from %s: %s", url, e)
        return None
    except httpx.RequestError as e:
        logger.warning("Request error fetching Cloudflare IP ranges from %s: %s", url, e)
        return None


def _parse_ipv4_ranges(range_strings: list[str]) -> list[IPv4Network]:
    """Parse a list of CIDR strings into IPv4Network objects."""
    networks = []
    for cidr in range_strings:
        try:
            # strict=False allows host bits to be set (e.g., "192.168.1.1/24" -> "192.168.1.0/24")
            network = ip_network(cidr, strict=False)
            if isinstance(network, IPv4Network):
                networks.append(network)
            else:
                logger.warning("Expected IPv4 but got IPv6: %s", cidr)
        except ValueError as e:
            logger.warning("Invalid IPv4 CIDR %s: %s", cidr, e)
    return networks


def _parse_ipv6_ranges(range_strings: list[str]) -> list[IPv6Network]:
    """Parse a list of CIDR strings into IPv6Network objects."""
    networks = []
    for cidr in range_strings:
        try:
            # strict=False allows host bits to be set (e.g., "2001:db8::1/32" -> "2001:db8::/32")
            network = ip_network(cidr, strict=False)
            if isinstance(network, IPv6Network):
                networks.append(network)
            else:
                logger.warning("Expected IPv6 but got IPv4: %s", cidr)
        except ValueError as e:
            logger.warning("Invalid IPv6 CIDR %s: %s", cidr, e)
    return networks


def get_cloudflare_ipv4_ranges() -> list[IPv4Network]:
    """
    Get Cloudflare IPv4 ranges.

    Attempts to fetch from Cloudflare's published endpoint.
    Falls back to hardcoded ranges if fetch fails.

    Returns:
        List of IPv4Network objects representing Cloudflare's IP ranges
    """
    global _cached_ipv4_ranges, _cache_source_ipv4

    # Return cached if available
    if _cached_ipv4_ranges is not None:
        return _cached_ipv4_ranges

    # Try to fetch from Cloudflare
    range_strings = _fetch_ip_ranges(CLOUDFLARE_IPV4_URL)

    if range_strings:
        parsed = _parse_ipv4_ranges(range_strings)
        if parsed:
            _cached_ipv4_ranges = parsed
            _cache_source_ipv4 = "cloudflare"
            logger.info("Using %d IPv4 ranges fetched from Cloudflare", len(parsed))
            return _cached_ipv4_ranges

    # Fall back to hardcoded ranges
    logger.info("Using fallback IPv4 ranges (%d ranges)", len(FALLBACK_IPV4_RANGES))
    _cached_ipv4_ranges = FALLBACK_IPV4_RANGES
    _cache_source_ipv4 = "fallback"
    return _cached_ipv4_ranges


def get_cloudflare_ipv6_ranges() -> list[IPv6Network]:
    """
    Get Cloudflare IPv6 ranges.

    Attempts to fetch from Cloudflare's published endpoint.
    Falls back to hardcoded ranges if fetch fails.

    Returns:
        List of IPv6Network objects representing Cloudflare's IP ranges
    """
    global _cached_ipv6_ranges, _cache_source_ipv6

    # Return cached if available
    if _cached_ipv6_ranges is not None:
        return _cached_ipv6_ranges

    # Try to fetch from Cloudflare
    range_strings = _fetch_ip_ranges(CLOUDFLARE_IPV6_URL)

    if range_strings:
        parsed = _parse_ipv6_ranges(range_strings)
        if parsed:
            _cached_ipv6_ranges = parsed
            _cache_source_ipv6 = "cloudflare"
            logger.info("Using %d IPv6 ranges fetched from Cloudflare", len(parsed))
            return _cached_ipv6_ranges

    # Fall back to hardcoded ranges
    logger.info("Using fallback IPv6 ranges (%d ranges)", len(FALLBACK_IPV6_RANGES))
    _cached_ipv6_ranges = FALLBACK_IPV6_RANGES
    _cache_source_ipv6 = "fallback"
    return _cached_ipv6_ranges


def is_using_live_cloudflare_ranges() -> bool:
    """
    Check if Cloudflare IP ranges were successfully fetched from the remote endpoints.

    Returns:
        True if at least one of IPv4/IPv6 ranges was fetched live from Cloudflare,
        False if both are using fallback ranges.
    """
    # Ensure ranges are loaded
    get_cloudflare_ipv4_ranges()
    get_cloudflare_ipv6_ranges()

    return _cache_source_ipv4 == "cloudflare" or _cache_source_ipv6 == "cloudflare"


def get_cloudflare_ranges_info() -> dict:
    """
    Get information about the current Cloudflare IP ranges.

    Returns:
        Dict with source info and range counts
    """
    ipv4_ranges = get_cloudflare_ipv4_ranges()
    ipv6_ranges = get_cloudflare_ipv6_ranges()

    return {
        "ipv4": {
            "source": _cache_source_ipv4,
            "count": len(ipv4_ranges),
            "ranges": [str(r) for r in ipv4_ranges],
        },
        "ipv6": {
            "source": _cache_source_ipv6,
            "count": len(ipv6_ranges),
            "ranges": [str(r) for r in ipv6_ranges],
        },
    }


def refresh_cloudflare_ranges() -> dict:
    """
    Force refresh of Cloudflare IP ranges from the remote endpoints.

    Returns:
        Dict with refresh results
    """
    global _cached_ipv4_ranges, _cached_ipv6_ranges, _cache_source_ipv4, _cache_source_ipv6

    # Clear cache to force refresh
    _cached_ipv4_ranges = None
    _cached_ipv6_ranges = None
    _cache_source_ipv4 = "not_loaded"
    _cache_source_ipv6 = "not_loaded"

    # Fetch fresh ranges
    ipv4_ranges = get_cloudflare_ipv4_ranges()
    ipv6_ranges = get_cloudflare_ipv6_ranges()

    return {
        "ipv4": {
            "source": _cache_source_ipv4,
            "count": len(ipv4_ranges),
        },
        "ipv6": {
            "source": _cache_source_ipv6,
            "count": len(ipv6_ranges),
        },
    }
