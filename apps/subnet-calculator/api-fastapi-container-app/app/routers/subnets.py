"""Subnet calculation endpoints.

Provides IPv4/IPv6 subnet calculations with cloud provider-specific modes.
"""

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

from fastapi import APIRouter, Depends, HTTPException

from ..auth_utils import get_current_user
from ..cloudflare_ips import (
    get_cloudflare_ipv4_ranges,
    get_cloudflare_ipv6_ranges,
)
from ..models.subnet import (
    SubnetIPv4Request,
    SubnetIPv4Response,
    SubnetIPv6Request,
    SubnetIPv6Response,
    ValidateRequest,
)

router = APIRouter(prefix="/api/v1/ipv4", tags=["subnets"])
router_ipv6 = APIRouter(prefix="/api/v1/ipv6", tags=["subnets"])

# RFC1918 Private Address Ranges
RFC1918_RANGES = [
    ip_network("10.0.0.0/8"),
    ip_network("172.16.0.0/12"),
    ip_network("192.168.0.0/16"),
]

# RFC6598 Shared Address Space
RFC6598_RANGE = ip_network("100.64.0.0/10")

# Cloudflare IP ranges are now dynamically fetched from cloudflare_ips module
# See app/cloudflare_ips.py for implementation with fallback to hardcoded ranges


@router.post("/subnet-info", response_model=SubnetIPv4Response)
async def calculate_ipv4_subnet(request: SubnetIPv4Request, current_user: str = Depends(get_current_user)):
    """Calculate IPv4 subnet information including usable IP ranges.

    Cloud provider IP reservations:
    - Azure/AWS: Reserve 5 IPs (.0, .1, .2, .3, and broadcast)
    - OCI: Reserve 3 IPs (.0, .1, and broadcast)
    - Standard: Reserve 2 IPs (.0 and broadcast)
    - /31 and /32: No reservations (point-to-point and host routes)

    Args:
        request: Subnet calculation request with network and mode
        current_user: Current authenticated user (from dependency)

    Returns:
        Subnet information with usable IP ranges

    Raises:
        HTTPException: 400 if network format is invalid or unsupported mode
    """
    network_str = request.network
    mode = request.mode

    # Validate mode
    valid_modes = ["Azure", "AWS", "OCI", "Standard"]
    if mode not in valid_modes:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid mode '{mode}'. Must be one of: {', '.join(valid_modes)}",
        )

    # Parse network
    try:
        network = ip_network(network_str, strict=False)
    except (AddressValueError, NetmaskValueError) as e:
        raise HTTPException(status_code=400, detail=f"Invalid network format: {str(e)}") from e

    # Only support IPv4
    if not isinstance(network, IPv4Network):
        raise HTTPException(status_code=400, detail="This endpoint only supports IPv4 networks")

    prefix_len = network.prefixlen
    total_addresses = network.num_addresses

    # Calculate usable IPs based on mode and prefix length
    if prefix_len < 31:
        # Standard subnets have network and broadcast addresses
        # Calculate first usable based on mode
        if mode in ["Azure", "AWS"]:
            first_usable_offset = 4  # Skip .0, .1, .2, .3
        elif mode == "OCI":
            first_usable_offset = 2  # Skip .0, .1
        else:  # Standard
            first_usable_offset = 1  # Skip .0

        first_usable_ip = str(network.network_address + first_usable_offset)
        last_usable_ip = str(network.broadcast_address - 1)  # Skip broadcast

        # Calculate usable addresses
        reserved_at_start = first_usable_offset
        reserved_at_end = 1  # broadcast
        usable_addresses = total_addresses - reserved_at_start - reserved_at_end

        return SubnetIPv4Response(
            network=network_str,
            mode=mode,
            network_address=str(network.network_address),
            broadcast_address=str(network.broadcast_address),
            netmask=str(network.netmask),
            wildcard_mask=str(network.hostmask),
            prefix_length=prefix_len,
            total_addresses=total_addresses,
            usable_addresses=usable_addresses,
            first_usable_ip=first_usable_ip,
            last_usable_ip=last_usable_ip,
        )
    else:
        # /31 (point-to-point) or /32 (host route) - no reservations
        if prefix_len == 31:
            # RFC 3021 - /31 point-to-point links
            first_usable_ip = str(network.network_address)
            last_usable_ip = str(network.network_address + 1)
            usable_addresses = 2

            return SubnetIPv4Response(
                network=network_str,
                mode=mode,
                network_address=str(network.network_address),
                broadcast_address=None,
                netmask=str(network.netmask),
                wildcard_mask=str(network.hostmask),
                prefix_length=prefix_len,
                total_addresses=total_addresses,
                usable_addresses=usable_addresses,
                first_usable_ip=first_usable_ip,
                last_usable_ip=last_usable_ip,
                note="RFC 3021 point-to-point link (no broadcast)",
            )
        else:  # /32
            # Single host
            host_ip = str(network.network_address)

            return SubnetIPv4Response(
                network=network_str,
                mode=mode,
                network_address=host_ip,
                broadcast_address=None,
                netmask=str(network.netmask),
                wildcard_mask=str(network.hostmask),
                prefix_length=prefix_len,
                total_addresses=1,
                usable_addresses=1,
                first_usable_ip=host_ip,
                last_usable_ip=host_ip,
                note="Single host address",
            )


@router_ipv6.post("/subnet-info", response_model=SubnetIPv6Response)
async def calculate_ipv6_subnet(request: SubnetIPv6Request, current_user: str = Depends(get_current_user)):
    """Calculate IPv6 subnet information.

    IPv6 subnets don't have the same reserved addresses as IPv4.

    Args:
        request: Subnet calculation request with network
        current_user: Current authenticated user (from dependency)

    Returns:
        Subnet information

    Raises:
        HTTPException: 400 if network format is invalid or not IPv6
    """
    network_str = request.network

    # Parse network
    try:
        network = ip_network(network_str, strict=False)
    except (AddressValueError, NetmaskValueError) as e:
        raise HTTPException(status_code=400, detail=f"Invalid network format: {str(e)}") from e

    # Only support IPv6
    if not isinstance(network, IPv6Network):
        raise HTTPException(status_code=400, detail="This endpoint only supports IPv6 networks")

    return SubnetIPv6Response(
        network=network_str,
        network_address=str(network.network_address),
        prefix_length=network.prefixlen,
        total_addresses=str(network.num_addresses),  # Can be huge, use string
        note="IPv6 subnets do not have reserved addresses like IPv4",
    )


@router.post("/validate")
async def validate_address(request: ValidateRequest, current_user: str = Depends(get_current_user)):
    """Validate if an IPv4/IPv6 address or CIDR range is well-formed.

    Returns validation result with type (address or network) and details.

    Args:
        request: Validation request with address
        current_user: Current authenticated user (from dependency)

    Returns:
        Validation result with IP type and details

    Raises:
        HTTPException: 400 if address format is invalid
    """
    address_str = request.address

    # Check if it's CIDR notation (contains /)
    if "/" in address_str:
        # Parse as network
        try:
            network = ip_network(address_str, strict=False)
            return {
                "valid": True,
                "type": "network",
                "address": address_str,
                "network_address": str(network.network_address),
                "netmask": str(network.netmask),
                "prefix_length": network.prefixlen,
                "num_addresses": network.num_addresses,
                "is_ipv4": isinstance(network, IPv4Network),
                "is_ipv6": isinstance(network, IPv6Network),
            }
        except (AddressValueError, NetmaskValueError, ValueError):
            raise HTTPException(status_code=400, detail="Invalid IP network format") from None
    else:
        # Parse as individual address
        try:
            addr = ip_address(address_str)
            return {
                "valid": True,
                "type": "address",
                "address": str(addr),
                "is_ipv4": isinstance(addr, IPv4Address),
                "is_ipv6": isinstance(addr, IPv6Address),
            }
        except (AddressValueError, ValueError):
            raise HTTPException(status_code=400, detail="Invalid IP address format") from None


@router.post("/check-private")
async def check_private(request: ValidateRequest, current_user: str = Depends(get_current_user)):
    """Check if an IPv4 address or range is RFC1918 (private) or RFC6598 (shared).

    RFC1918 ranges: 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16
    RFC6598 range: 100.64.0.0/10 (shared address space)

    Args:
        request: Validation request with address
        current_user: Current authenticated user (from dependency)

    Returns:
        Private/shared address check result

    Raises:
        HTTPException: 400 if address is invalid or not IPv4
    """
    address_str = request.address

    # Parse as network or address
    try:
        # Try network first
        try:
            ip_obj = ip_network(address_str, strict=False)
        except (AddressValueError, NetmaskValueError, ValueError):
            ip_obj = ip_address(address_str)

        # Only process IPv4
        if isinstance(ip_obj, (IPv6Address, IPv6Network)):
            raise HTTPException(status_code=400, detail="This endpoint only supports IPv4 addresses")

        # Check RFC1918
        is_rfc1918 = False
        matched_rfc1918 = None
        for rfc1918_range in RFC1918_RANGES:
            if isinstance(ip_obj, IPv4Network):
                if ip_obj.subnet_of(rfc1918_range) or ip_obj.supernet_of(rfc1918_range):
                    is_rfc1918 = True
                    matched_rfc1918 = str(rfc1918_range)
                    break
            else:  # IPv4Address
                if ip_obj in rfc1918_range:
                    is_rfc1918 = True
                    matched_rfc1918 = str(rfc1918_range)
                    break

        # Check RFC6598
        is_rfc6598 = False
        if isinstance(ip_obj, IPv4Network):
            is_rfc6598 = ip_obj.subnet_of(RFC6598_RANGE) or ip_obj.supernet_of(RFC6598_RANGE)
        else:  # IPv4Address
            is_rfc6598 = ip_obj in RFC6598_RANGE

        response = {
            "address": address_str,
            "is_rfc1918": is_rfc1918,
            "is_rfc6598": is_rfc6598,
        }

        if matched_rfc1918:
            response["matched_rfc1918_range"] = matched_rfc1918

        if is_rfc6598:
            response["matched_rfc6598_range"] = str(RFC6598_RANGE)

        return response

    except (AddressValueError, NetmaskValueError, ValueError) as e:
        raise HTTPException(status_code=400, detail=f"Invalid IP address or network: {str(e)}") from e


@router.post("/check-cloudflare")
async def check_cloudflare(request: ValidateRequest, current_user: str = Depends(get_current_user)):
    """Check if an IP address or range is within Cloudflare's IPv4 or IPv6 ranges.

    Cloudflare IP ranges are fetched dynamically from https://www.cloudflare.com/ips-v4/
    and https://www.cloudflare.com/ips-v6/ with fallback to hardcoded ranges if unavailable.

    Returns matched Cloudflare ranges and IP version.

    Args:
        request: Validation request with address
        current_user: Current authenticated user (from dependency)

    Returns:
        Cloudflare range check result

    Raises:
        HTTPException: 400 if address format is invalid
    """
    address_str = request.address

    # Parse as network or address
    try:
        # Try network first
        try:
            ip_obj = ip_network(address_str, strict=False)
        except (AddressValueError, NetmaskValueError, ValueError):
            ip_obj = ip_address(address_str)

        # Determine which Cloudflare ranges to check (dynamically fetched)
        if isinstance(ip_obj, (IPv4Address, IPv4Network)):
            cloudflare_ranges = get_cloudflare_ipv4_ranges()
            ip_version = 4
        else:
            cloudflare_ranges = get_cloudflare_ipv6_ranges()
            ip_version = 6

        # Check against Cloudflare ranges
        matched_ranges = []
        for cf_range in cloudflare_ranges:
            if isinstance(ip_obj, (IPv4Network, IPv6Network)):
                # For networks, check if it's a subnet or supernet
                if ip_obj.subnet_of(cf_range) or ip_obj.supernet_of(cf_range):
                    matched_ranges.append(str(cf_range))
            else:  # Address
                if ip_obj in cf_range:
                    matched_ranges.append(str(cf_range))

        response = {
            "address": address_str,
            "is_cloudflare": len(matched_ranges) > 0,
            "ip_version": ip_version,
        }

        if matched_ranges:
            response["matched_ranges"] = matched_ranges

        return response

    except (AddressValueError, NetmaskValueError, ValueError) as e:
        raise HTTPException(status_code=400, detail=f"Invalid IP address or network: {str(e)}") from e
