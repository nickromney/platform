"""Cloud provider modes used by subnet calculations."""

from enum import Enum


class CloudMode(str, Enum):
    """Supported cloud reservation strategies for IPv4 subnets."""

    STANDARD = "Standard"
    AWS = "AWS"
    AZURE = "Azure"
    OCI = "OCI"
