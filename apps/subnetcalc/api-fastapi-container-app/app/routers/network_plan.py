"""Network planning endpoints."""

from ipaddress import AddressValueError, IPv4Address, IPv4Network, NetmaskValueError, ip_network

from fastapi import APIRouter, Depends, HTTPException

from ..auth_utils import get_current_user
from ..models.cloud_mode import CloudMode
from ..models.subnet import NetworkPlanRequest

router = APIRouter(prefix="/api/v1/network-plan", tags=["network-plan"])


def _reserved_address_count(mode: CloudMode, prefix_length: int) -> int:
    if prefix_length >= 31:
        return 0
    if mode in {CloudMode.AWS, CloudMode.AZURE}:
        return 5
    if mode == CloudMode.OCI:
        return 3
    return 2


def _first_usable_offset(mode: CloudMode, prefix_length: int) -> int:
    if prefix_length >= 31:
        return 0
    if mode in {CloudMode.AWS, CloudMode.AZURE}:
        return 4
    if mode == CloudMode.OCI:
        return 2
    return 1


def _usable_addresses(total_addresses: int, mode: CloudMode, prefix_length: int) -> int:
    if prefix_length >= 31:
        return total_addresses
    return max(0, total_addresses - _reserved_address_count(mode, prefix_length))


def _smallest_prefix_for_hosts(hosts: int, mode: CloudMode) -> int:
    for prefix_length in range(32, -1, -1):
        total_addresses = 1 << (32 - prefix_length)
        if _usable_addresses(total_addresses, mode, prefix_length) >= hosts:
            return prefix_length
    raise HTTPException(status_code=400, detail=f"Host requirement is too large: {hosts}")


def _align_to_block(address: int, block_size: int) -> int:
    remainder = address % block_size
    if remainder == 0:
        return address
    return address + (block_size - remainder)


def _allocation_response(name: str, network: IPv4Network, mode: CloudMode) -> dict:
    total_addresses = network.num_addresses
    prefix_length = network.prefixlen
    first_offset = _first_usable_offset(mode, prefix_length)
    if prefix_length >= 31:
        last_usable = network.network_address + (total_addresses - 1)
    else:
        last_usable = network.broadcast_address - 1

    return {
        "name": name,
        "network": str(network),
        "prefix_length": prefix_length,
        "total_addresses": total_addresses,
        "usable_addresses": _usable_addresses(total_addresses, mode, prefix_length),
        "first_usable_ip": str(network.network_address + first_offset),
        "last_usable_ip": str(last_usable),
    }


@router.post("/allocate")
async def allocate_network_plan(request: NetworkPlanRequest, current_user: str = Depends(get_current_user)):
    """Allocate IPv4 subnets for named host requirements."""
    try:
        parent = ip_network(request.parent, strict=False)
    except (AddressValueError, NetmaskValueError, ValueError) as exc:
        raise HTTPException(status_code=400, detail=f"Invalid parent network: {exc}") from exc

    if not isinstance(parent, IPv4Network):
        raise HTTPException(status_code=400, detail="Network planning currently supports IPv4 parent networks")

    requirements = sorted(request.requirements, key=lambda requirement: requirement.hosts, reverse=True)
    current_address = int(parent.network_address)
    end_address = int(parent.broadcast_address)
    allocations: list[dict] = []

    for requirement in requirements:
        prefix_length = _smallest_prefix_for_hosts(requirement.hosts, request.mode)
        block_size = 1 << (32 - prefix_length)
        network_start = _align_to_block(current_address, block_size)
        network_end = network_start + block_size - 1
        if network_end > end_address:
            raise HTTPException(status_code=400, detail=f"Insufficient space for requirement: {requirement.name}")

        network = IPv4Network((IPv4Address(network_start), prefix_length))
        allocations.append(_allocation_response(requirement.name, network, request.mode))
        current_address = network_end + 1

    return {
        "parent": str(parent),
        "mode": request.mode.value,
        "allocations": allocations,
    }
