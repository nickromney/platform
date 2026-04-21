"""Pydantic models for subnet calculator API."""

from fastapi import HTTPException
from pydantic import BaseModel, Field, field_validator

from .cloud_mode import CloudMode


class SubnetIPv4Request(BaseModel):
    """Request model for IPv4 subnet calculation."""

    network: str = Field(..., description="IPv4 network in CIDR notation (e.g., 192.168.1.0/24)")
    mode: CloudMode = Field(
        default=CloudMode.AZURE,
        description="Cloud provider mode: Azure, AWS, OCI, or Standard",
    )

    @field_validator("mode", mode="before")
    @classmethod
    def validate_mode(cls, value: CloudMode | str) -> CloudMode:
        """Preserve the existing 400 response for unsupported cloud modes."""
        if isinstance(value, CloudMode):
            return value

        try:
            return CloudMode(value)
        except ValueError as exc:
            valid_modes = ", ".join(mode.value for mode in CloudMode)
            raise HTTPException(
                status_code=400,
                detail=f"Invalid mode '{value}'. Must be one of: {valid_modes}",
            ) from exc


class SubnetIPv4Response(BaseModel):
    """Response model for IPv4 subnet calculation."""

    network: str
    mode: str
    network_address: str
    broadcast_address: str | None
    netmask: str
    wildcard_mask: str
    prefix_length: int
    total_addresses: int
    usable_addresses: int
    first_usable_ip: str
    last_usable_ip: str
    note: str | None = None


class SubnetIPv6Request(BaseModel):
    """Request model for IPv6 subnet calculation."""

    network: str = Field(..., description="IPv6 network in CIDR notation (e.g., 2001:db8::/64)")


class SubnetIPv6Response(BaseModel):
    """Response model for IPv6 subnet calculation."""

    network: str
    network_address: str
    prefix_length: int
    total_addresses: str  # Too large for int
    note: str | None = None


class ValidateRequest(BaseModel):
    """Request model for IP address validation."""

    address: str = Field(..., description="IP address or CIDR notation")
