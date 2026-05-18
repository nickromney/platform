"""Tests for subnet calculation endpoints."""

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.routers import provider_ranges


@pytest.fixture
def client():
    """Create test client with no authentication."""
    return TestClient(app)


class TestValidateEndpoint:
    """Tests for /api/v1/ipv4/validate endpoint."""

    def test_valid_ipv4_address(self, client):
        """Test validation of valid IPv4 address."""
        response = client.post("/api/v1/ipv4/validate", json={"address": "192.168.1.100"})
        assert response.status_code == 200
        data = response.json()
        assert data["valid"] is True
        assert data["type"] == "address"
        assert data["address"] == "192.168.1.100"
        assert data["is_ipv4"] is True
        assert data["is_ipv6"] is False

    def test_valid_ipv4_network(self, client):
        """Test validation of valid IPv4 network."""
        response = client.post("/api/v1/ipv4/validate", json={"address": "192.168.1.0/24"})
        assert response.status_code == 200
        data = response.json()
        assert data["valid"] is True
        assert data["type"] == "network"
        assert data["network_address"] == "192.168.1.0"
        assert data["prefix_length"] == 24
        assert data["num_addresses"] == 256
        assert data["is_ipv4"] is True

    def test_valid_ipv6_address(self, client):
        """Test validation of valid IPv6 address."""
        response = client.post("/api/v1/ipv4/validate", json={"address": "2001:db8::1"})
        assert response.status_code == 200
        data = response.json()
        assert data["valid"] is True
        assert data["type"] == "address"
        assert data["is_ipv6"] is True

    def test_invalid_address(self, client):
        """Test validation of invalid address."""
        response = client.post("/api/v1/ipv4/validate", json={"address": "not-an-ip"})
        assert response.status_code == 400

    def test_missing_address_field(self, client):
        """Test validation without address field."""
        response = client.post("/api/v1/ipv4/validate", json={})
        assert response.status_code == 422


class TestCheckPrivate:
    """Tests for /api/v1/ipv4/check-private endpoint."""

    def test_rfc1918_10_network(self, client):
        """Test RFC1918 10.0.0.0/8 detection."""
        response = client.post("/api/v1/ipv4/check-private", json={"address": "10.50.100.200"})
        assert response.status_code == 200
        data = response.json()
        assert data["is_rfc1918"] is True
        assert data["matched_rfc1918_range"] == "10.0.0.0/8"

    def test_rfc1918_172_network(self, client):
        """Test RFC1918 172.16.0.0/12 detection."""
        response = client.post("/api/v1/ipv4/check-private", json={"address": "172.20.1.1"})
        assert response.status_code == 200
        data = response.json()
        assert data["is_rfc1918"] is True
        assert data["matched_rfc1918_range"] == "172.16.0.0/12"

    def test_rfc1918_192_network(self, client):
        """Test RFC1918 192.168.0.0/16 detection."""
        response = client.post("/api/v1/ipv4/check-private", json={"address": "192.168.100.1"})
        assert response.status_code == 200
        data = response.json()
        assert data["is_rfc1918"] is True
        assert data["matched_rfc1918_range"] == "192.168.0.0/16"

    def test_rfc6598_shared_address_space(self, client):
        """Test RFC6598 100.64.0.0/10 detection."""
        response = client.post("/api/v1/ipv4/check-private", json={"address": "100.65.1.1"})
        assert response.status_code == 200
        data = response.json()
        assert data["is_rfc6598"] is True
        assert data["matched_rfc6598_range"] == "100.64.0.0/10"

    def test_public_ipv4_address(self, client):
        """Test public IPv4 address detection."""
        response = client.post("/api/v1/ipv4/check-private", json={"address": "8.8.8.8"})
        assert response.status_code == 200
        data = response.json()
        assert data["is_rfc1918"] is False
        assert data["is_rfc6598"] is False

    def test_ipv6_rejected(self, client):
        """Test that IPv6 addresses are rejected."""
        response = client.post("/api/v1/ipv4/check-private", json={"address": "2001:db8::1"})
        assert response.status_code == 400


class TestCheckCloudflare:
    """Tests for /api/v1/ipv4/check-cloudflare endpoint."""

    def test_cloudflare_ipv4_address(self, client):
        """Test Cloudflare IPv4 range detection."""
        response = client.post("/api/v1/ipv4/check-cloudflare", json={"address": "104.16.0.1"})
        assert response.status_code == 200
        data = response.json()
        assert data["is_cloudflare"] is True
        assert data["ip_version"] == 4
        assert len(data["matched_ranges"]) > 0

    def test_cloudflare_ipv6_address(self, client):
        """Test Cloudflare IPv6 range detection."""
        response = client.post("/api/v1/ipv4/check-cloudflare", json={"address": "2606:4700::1"})
        assert response.status_code == 200
        data = response.json()
        assert data["is_cloudflare"] is True
        assert data["ip_version"] == 6

    def test_non_cloudflare_ipv4(self, client):
        """Test non-Cloudflare IPv4 detection."""
        response = client.post("/api/v1/ipv4/check-cloudflare", json={"address": "8.8.8.8"})
        assert response.status_code == 200
        data = response.json()
        assert data["is_cloudflare"] is False

    def test_cloudflare_ipv4_network(self, client):
        """Test Cloudflare network range detection."""
        response = client.post("/api/v1/ipv4/check-cloudflare", json={"address": "104.16.0.0/13"})
        assert response.status_code == 200
        data = response.json()
        assert data["is_cloudflare"] is True

    def test_invalid_address_format(self, client):
        """Test invalid address format."""
        response = client.post("/api/v1/ipv4/check-cloudflare", json={"address": "not-an-ip"})
        assert response.status_code == 400


class TestProviderRanges:
    """Tests for /api/v1/provider-ranges endpoints."""

    def test_provider_range_check_supports_known_providers(self, client):
        """Provider checks identify bundled provider ranges without live fetches."""
        response = client.post("/api/v1/provider-ranges/check", json={"provider": "aws", "address": "3.5.140.1"})

        assert response.status_code == 200
        data = response.json()
        assert data["provider"] == "aws"
        assert data["is_provider_range"] is True
        assert data["range_source"] == "bundled"
        assert data["ip_version"] == 4
        assert "3.5.140.0/22" in data["matched_ranges"]

    def test_provider_range_refresh_and_invalidate_use_explicit_cache(self, client, monkeypatch):
        """Provider feeds are refreshed explicitly and fall back to bundled data after invalidation."""
        payload = b'{"prefixes":[{"ip_prefix":"203.0.113.0/24"}],"ipv6_prefixes":[]}'
        calls = 0

        class FakeResponse:
            def __enter__(self):
                return self

            def __exit__(self, *_args):
                return False

            def read(self):
                return payload

        def fake_urlopen(_request, timeout):
            nonlocal calls
            calls += 1
            assert timeout == provider_ranges.REQUEST_TIMEOUT
            return FakeResponse()

        monkeypatch.setitem(provider_ranges.PROVIDER_SOURCE_URLS, "aws", "https://example.test/aws.json")
        monkeypatch.setattr(provider_ranges, "urlopen", fake_urlopen)
        provider_ranges.invalidate_provider_cache("aws")

        response = client.post("/api/v1/provider-ranges/check", json={"provider": "aws", "address": "203.0.113.1"})
        assert response.status_code == 200
        assert response.json()["is_provider_range"] is False
        assert calls == 0

        response = client.post("/api/v1/provider-ranges/cache/refresh", json={"provider": "aws"})
        assert response.status_code == 200
        assert response.json()["cache_status"] == "refreshed"
        assert calls == 1

        response = client.post("/api/v1/provider-ranges/check", json={"provider": "aws", "address": "203.0.113.1"})
        assert response.status_code == 200
        assert response.json()["is_provider_range"] is True
        assert response.json()["range_source"] == "live-cache"

        response = client.post("/api/v1/provider-ranges/cache/invalidate", json={"provider": "aws"})
        assert response.status_code == 200
        assert response.json()["cache_status"] == "invalidated"

        response = client.post("/api/v1/provider-ranges/check", json={"provider": "aws", "address": "203.0.113.1"})
        assert response.status_code == 200
        assert response.json()["is_provider_range"] is False


class TestNetworkPlan:
    """Tests for /api/v1/network-plan endpoints."""

    def test_network_plan_allocates_host_requirements_with_cloud_reservations(self, client):
        """Network planning allocates descending host requirements inside the parent network."""
        response = client.post(
            "/api/v1/network-plan/allocate",
            json={
                "parent": "10.0.0.0/24",
                "mode": "Azure",
                "requirements": [{"name": "web", "hosts": 60}, {"name": "db", "hosts": 20}],
            },
        )

        assert response.status_code == 200
        data = response.json()
        assert data["parent"] == "10.0.0.0/24"
        assert data["mode"] == "Azure"
        assert data["allocations"] == [
            {
                "name": "web",
                "network": "10.0.0.0/25",
                "prefix_length": 25,
                "total_addresses": 128,
                "usable_addresses": 123,
                "first_usable_ip": "10.0.0.4",
                "last_usable_ip": "10.0.0.126",
            },
            {
                "name": "db",
                "network": "10.0.0.128/27",
                "prefix_length": 27,
                "total_addresses": 32,
                "usable_addresses": 27,
                "first_usable_ip": "10.0.0.132",
                "last_usable_ip": "10.0.0.158",
            },
        ]


class TestIPv4SubnetCalculation:
    """Tests for /api/v1/ipv4/subnet-info endpoint."""

    def test_cloud_mode_request_contract(self):
        """Test the CloudMode enum and request serialization contract."""
        from app.models.cloud_mode import CloudMode
        from app.models.subnet import SubnetIPv4Request

        assert CloudMode.STANDARD.value == "Standard"
        assert CloudMode.AWS.value == "AWS"
        assert CloudMode.AZURE.value == "Azure"
        assert CloudMode.OCI.value == "OCI"
        assert SubnetIPv4Request.model_fields["mode"].annotation is CloudMode

        request = SubnetIPv4Request(network="192.168.1.0/24", mode=CloudMode.AWS)
        assert request.model_dump(mode="json") == {"network": "192.168.1.0/24", "mode": "AWS"}
        assert request.model_dump_json() == '{"network":"192.168.1.0/24","mode":"AWS"}'

    def test_standard_subnet_azure_mode(self, client):
        """Test Azure mode subnet calculation."""
        response = client.post("/api/v1/ipv4/subnet-info", json={"network": "192.168.1.0/24", "mode": "Azure"})
        assert response.status_code == 200
        data = response.json()
        assert data["network_address"] == "192.168.1.0"
        assert data["broadcast_address"] == "192.168.1.255"
        assert data["prefix_length"] == 24
        assert data["total_addresses"] == 256
        assert data["usable_addresses"] == 251  # 256 - 5 (Azure reserves .0-.3 + broadcast)
        assert data["first_usable_ip"] == "192.168.1.4"
        assert data["last_usable_ip"] == "192.168.1.254"

    def test_standard_subnet_aws_mode(self, client):
        """Test AWS mode subnet calculation."""
        response = client.post("/api/v1/ipv4/subnet-info", json={"network": "10.0.1.0/24", "mode": "AWS"})
        assert response.status_code == 200
        data = response.json()
        assert data["usable_addresses"] == 251  # Same as Azure
        assert data["first_usable_ip"] == "10.0.1.4"

    def test_standard_subnet_oci_mode(self, client):
        """Test OCI mode subnet calculation."""
        response = client.post("/api/v1/ipv4/subnet-info", json={"network": "172.16.0.0/24", "mode": "OCI"})
        assert response.status_code == 200
        data = response.json()
        assert data["usable_addresses"] == 253  # 256 - 3 (OCI reserves .0-.1 + broadcast)
        assert data["first_usable_ip"] == "172.16.0.2"
        assert data["last_usable_ip"] == "172.16.0.254"

    def test_standard_subnet_standard_mode(self, client):
        """Test Standard mode subnet calculation."""
        response = client.post("/api/v1/ipv4/subnet-info", json={"network": "10.0.0.0/24", "mode": "Standard"})
        assert response.status_code == 200
        data = response.json()
        assert data["usable_addresses"] == 254  # 256 - 2 (network + broadcast)
        assert data["first_usable_ip"] == "10.0.0.1"
        assert data["last_usable_ip"] == "10.0.0.254"

    def test_slash_31_subnet(self, client):
        """Test /31 point-to-point subnet."""
        response = client.post("/api/v1/ipv4/subnet-info", json={"network": "10.0.0.0/31", "mode": "Standard"})
        assert response.status_code == 200
        data = response.json()
        assert data["total_addresses"] == 2
        assert data["usable_addresses"] == 2
        assert data["first_usable_ip"] == "10.0.0.0"
        assert data["last_usable_ip"] == "10.0.0.1"
        assert data["broadcast_address"] is None
        assert "RFC 3021" in data["note"]

    def test_slash_32_subnet(self, client):
        """Test /32 host route."""
        response = client.post("/api/v1/ipv4/subnet-info", json={"network": "10.0.0.1/32", "mode": "Standard"})
        assert response.status_code == 200
        data = response.json()
        assert data["total_addresses"] == 1
        assert data["usable_addresses"] == 1
        assert data["first_usable_ip"] == "10.0.0.1"
        assert data["last_usable_ip"] == "10.0.0.1"
        assert data["broadcast_address"] is None
        assert "Single host" in data["note"]

    def test_large_subnet(self, client):
        """Test large /8 subnet."""
        response = client.post("/api/v1/ipv4/subnet-info", json={"network": "10.0.0.0/8", "mode": "Azure"})
        assert response.status_code == 200
        data = response.json()
        assert data["total_addresses"] == 16777216

    def test_invalid_mode(self, client):
        """Test invalid mode parameter."""
        response = client.post("/api/v1/ipv4/subnet-info", json={"network": "192.168.1.0/24", "mode": "InvalidMode"})
        assert response.status_code == 400

    def test_missing_network_field(self, client):
        """Test missing network field."""
        response = client.post("/api/v1/ipv4/subnet-info", json={"mode": "Azure"})
        assert response.status_code == 422

    def test_ipv6_rejected(self, client):
        """Test that IPv6 networks are rejected."""
        response = client.post("/api/v1/ipv4/subnet-info", json={"network": "2001:db8::/64", "mode": "Azure"})
        assert response.status_code == 400

    def test_wildcard_mask(self, client):
        """Test wildcard mask calculation."""
        response = client.post("/api/v1/ipv4/subnet-info", json={"network": "192.168.1.0/24", "mode": "Standard"})
        assert response.status_code == 200
        data = response.json()
        assert data["wildcard_mask"] == "0.0.0.255"


class TestIPv6SubnetCalculation:
    """Tests for /api/v1/ipv6/subnet-info endpoint."""

    def test_standard_ipv6_subnet(self, client):
        """Test IPv6 subnet calculation."""
        response = client.post("/api/v1/ipv6/subnet-info", json={"network": "2001:db8::/64"})
        assert response.status_code == 200
        data = response.json()
        assert data["network_address"] == "2001:db8::"
        assert data["prefix_length"] == 64
        assert "IPv6 subnets do not have reserved" in data["note"]

    def test_ipv4_rejected(self, client):
        """Test that IPv4 networks are rejected."""
        response = client.post("/api/v1/ipv6/subnet-info", json={"network": "192.168.1.0/24"})
        assert response.status_code == 400
