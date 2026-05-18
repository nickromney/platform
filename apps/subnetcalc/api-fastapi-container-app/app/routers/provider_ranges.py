"""Provider range endpoints.

Provider checks are deliberately cache-backed/local by default. Large provider
feeds such as AWS and Azure are only pulled through explicit refresh endpoints.
"""

import json
from dataclasses import dataclass
from ipaddress import (
    AddressValueError,
    IPv4Address,
    IPv4Network,
    IPv6Address,
    IPv6Network,
    NetmaskValueError,
    ip_address,
    ip_network,
)
from urllib.request import Request, urlopen

from fastapi import APIRouter, Depends, HTTPException

from ..auth_utils import get_current_user
from ..cloudflare_ips import FALLBACK_IPV4_RANGES, FALLBACK_IPV6_RANGES
from ..models.subnet import ProviderCacheRequest, ProviderRangeRequest

router = APIRouter(prefix="/api/v1/provider-ranges", tags=["provider-ranges"])
REQUEST_TIMEOUT = 20.0


@dataclass(frozen=True)
class ProviderRange:
    """Bundled provider ranges and source metadata."""

    bundled_ipv4: tuple[IPv4Network, ...]
    bundled_ipv6: tuple[IPv6Network, ...]
    source_note: str | None = None


PROVIDERS: dict[str, ProviderRange] = {
    "cloudflare": ProviderRange(
        bundled_ipv4=tuple(FALLBACK_IPV4_RANGES),
        bundled_ipv6=tuple(FALLBACK_IPV6_RANGES),
    ),
    "aws": ProviderRange(
        bundled_ipv4=(ip_network("3.5.140.0/22"),),
        bundled_ipv6=(ip_network("2600:1f14::/35"),),
    ),
    "azure": ProviderRange(
        bundled_ipv4=(ip_network("20.33.0.0/16"),),
        bundled_ipv6=(),
        source_note="Microsoft publishes Azure Service Tags as date-stamped JSON and authenticated API feeds.",
    ),
    "stripe": ProviderRange(
        bundled_ipv4=(ip_network("3.18.12.63/32"), ip_network("3.130.192.231/32")),
        bundled_ipv6=(),
    ),
    "openai": ProviderRange(
        bundled_ipv4=(),
        bundled_ipv6=(),
        source_note="OpenAI does not publish an official provider IP range feed for general allowlisting.",
    ),
}

PROVIDER_SOURCE_URLS: dict[str, str] = {
    "cloudflare": "https://www.cloudflare.com/ips-v4/",
    "aws": "https://ip-ranges.amazonaws.com/ip-ranges.json",
    "stripe": "https://stripe.com/files/ips/ips_webhooks.json",
}

_live_cache: dict[str, tuple[tuple[IPv4Network, ...], tuple[IPv6Network, ...]]] = {}


def _parse_address_or_network(address: str) -> IPv4Address | IPv4Network | IPv6Address | IPv6Network:
    try:
        if "/" in address:
            return ip_network(address, strict=False)
        return ip_address(address)
    except (AddressValueError, NetmaskValueError, ValueError) as exc:
        raise HTTPException(status_code=400, detail=f"Invalid IP address or network: {exc}") from exc


def _matches_range(
    candidate: IPv4Address | IPv4Network | IPv6Address | IPv6Network,
    provider_range: IPv4Network | IPv6Network,
) -> bool:
    if isinstance(candidate, (IPv4Network, IPv6Network)):
        return candidate.subnet_of(provider_range) or candidate.supernet_of(provider_range)
    return candidate in provider_range


def _parse_range(value: str) -> IPv4Network | IPv6Network:
    if "/" in value:
        return ip_network(value, strict=False)
    parsed_address = ip_address(value)
    if isinstance(parsed_address, IPv4Address):
        return ip_network(f"{parsed_address}/32", strict=False)
    return ip_network(f"{parsed_address}/128", strict=False)


def _split_ranges(values: list[str]) -> tuple[tuple[IPv4Network, ...], tuple[IPv6Network, ...]]:
    ipv4_ranges: list[IPv4Network] = []
    ipv6_ranges: list[IPv6Network] = []
    for value in values:
        provider_range = _parse_range(value)
        if isinstance(provider_range, IPv4Network):
            ipv4_ranges.append(provider_range)
        else:
            ipv6_ranges.append(provider_range)
    return tuple(ipv4_ranges), tuple(ipv6_ranges)


def _parse_provider_payload(provider: str, payload: bytes) -> tuple[tuple[IPv4Network, ...], tuple[IPv6Network, ...]]:
    if provider == "cloudflare":
        return _split_ranges([line.strip() for line in payload.decode("utf-8").splitlines() if line.strip()])

    data = json.loads(payload.decode("utf-8"))
    if provider == "aws":
        values = [item["ip_prefix"] for item in data.get("prefixes", []) if item.get("ip_prefix")]
        values.extend(item["ipv6_prefix"] for item in data.get("ipv6_prefixes", []) if item.get("ipv6_prefix"))
        return _split_ranges(values)
    if provider == "stripe":
        values = []
        for item in data.values():
            if isinstance(item, list):
                values.extend(str(value) for value in item)
        return _split_ranges(values)
    if provider == "azure":
        values = []
        for item in data.get("values", []):
            properties = item.get("properties", {})
            values.extend(str(value) for value in properties.get("addressPrefixes", []))
        return _split_ranges(values)

    raise HTTPException(status_code=400, detail=f"Provider does not support refresh: {provider}")


def invalidate_provider_cache(provider: str) -> None:
    """Clear the explicit live range cache for a provider."""
    _live_cache.pop(provider.lower(), None)


def _ranges_for_provider(
    provider_name: str, provider: ProviderRange
) -> tuple[str, tuple[IPv4Network, ...], tuple[IPv6Network, ...]]:
    live_ranges = _live_cache.get(provider_name)
    if live_ranges is not None:
        return "live-cache", live_ranges[0], live_ranges[1]
    return "bundled", provider.bundled_ipv4, provider.bundled_ipv6


@router.post("/check")
async def check_provider_range(
    request: ProviderRangeRequest,
    current_user: str = Depends(get_current_user),
):
    """Check whether an address or CIDR belongs to a provider range."""
    provider_name = request.provider.lower()
    provider = PROVIDERS.get(provider_name)
    if provider is None:
        raise HTTPException(status_code=400, detail=f"Unsupported provider: {request.provider}")

    candidate = _parse_address_or_network(request.address)
    range_source, ipv4_ranges, ipv6_ranges = _ranges_for_provider(provider_name, provider)
    if isinstance(candidate, (IPv4Address, IPv4Network)):
        ranges = ipv4_ranges
        ip_version = 4
    else:
        ranges = ipv6_ranges
        ip_version = 6

    matched_ranges = [str(provider_range) for provider_range in ranges if _matches_range(candidate, provider_range)]
    response = {
        "address": request.address,
        "provider": provider_name,
        "is_provider_range": bool(matched_ranges),
        "ip_version": ip_version,
        "range_source": range_source,
    }
    if provider.source_note:
        response["range_source_note"] = provider.source_note
    if matched_ranges:
        response["matched_ranges"] = matched_ranges
    return response


@router.post("/cache/invalidate")
async def invalidate_provider_range_cache(
    request: ProviderCacheRequest,
    current_user: str = Depends(get_current_user),
):
    """Invalidate a provider's explicit live range cache."""
    provider_name = request.provider.lower()
    if provider_name not in PROVIDERS:
        raise HTTPException(status_code=400, detail=f"Unsupported provider: {request.provider}")
    invalidate_provider_cache(provider_name)
    return {"provider": provider_name, "cache_status": "invalidated"}


@router.post("/cache/refresh")
async def refresh_provider_range_cache(
    request: ProviderCacheRequest,
    current_user: str = Depends(get_current_user),
):
    """Refresh a provider's live range cache from its configured source."""
    provider_name = request.provider.lower()
    if provider_name not in PROVIDERS:
        raise HTTPException(status_code=400, detail=f"Unsupported provider: {request.provider}")
    source_url = PROVIDER_SOURCE_URLS.get(provider_name)
    if not source_url:
        raise HTTPException(
            status_code=400, detail=f"Provider does not have a configured refresh source: {provider_name}"
        )

    request_obj = Request(source_url, headers={"User-Agent": "subnetcalc-api/1.0"})
    with urlopen(request_obj, timeout=REQUEST_TIMEOUT) as response:
        payload = response.read()
    ipv4_ranges, ipv6_ranges = _parse_provider_payload(provider_name, payload)
    _live_cache[provider_name] = (ipv4_ranges, ipv6_ranges)

    return {
        "provider": provider_name,
        "cache_status": "refreshed",
        "range_source": "live-cache",
        "range_source_url": source_url,
        "ipv4_range_count": len(ipv4_ranges),
        "ipv6_range_count": len(ipv6_ranges),
    }
