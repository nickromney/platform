from fastapi.testclient import TestClient

from function_app import api

# Create test client for FastAPI app
client = TestClient(api)


def test_health_check():
    """Test health check endpoint"""
    response = client.get("/api/v1/health")

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "healthy"
    assert body["service"] == "Subnet Calculator API (Azure Function)"
    assert body["version"] == "1.0.0"
    assert "using_live_cloudflare_ranges" in body
    assert isinstance(body["using_live_cloudflare_ranges"], bool)


def test_swagger_ui_accessible():
    """Test that Swagger UI documentation is accessible"""
    response = client.get("/api/v1/docs")
    assert response.status_code == 200
    assert "text/html" in response.headers["content-type"]


def test_openapi_schema_accessible():
    """Test that OpenAPI schema is accessible"""
    response = client.get("/api/v1/openapi.json")
    assert response.status_code == 200
    schema = response.json()
    assert schema["info"]["title"] == "IPv4 Subnet Validation API"
    assert schema["info"]["version"] == "1.0.0"
    assert "paths" in schema


class TestValidateIPv4:
    """Tests for IPv4/IPv6 validation endpoint"""

    def test_valid_ipv4_address(self):
        response = client.post("/api/v1/ipv4/validate", json={"address": "192.168.1.1"})

        assert response.status_code == 200
        body = response.json()
        assert body["valid"] is True
        assert body["type"] == "address"
        assert body["is_ipv4"] is True
        assert body["is_ipv6"] is False

    def test_valid_ipv4_network(self):
        response = client.post("/api/v1/ipv4/validate", json={"address": "192.168.1.0/24"})

        assert response.status_code == 200
        body = response.json()
        assert body["valid"] is True
        assert body["type"] == "network"
        assert body["prefix_length"] == 24
        assert body["num_addresses"] == 256

    def test_valid_ipv6_address(self):
        response = client.post("/api/v1/ipv4/validate", json={"address": "2606:4700::1"})

        assert response.status_code == 200
        body = response.json()
        assert body["valid"] is True
        assert body["is_ipv4"] is False
        assert body["is_ipv6"] is True

    def test_invalid_address(self):
        response = client.post("/api/v1/ipv4/validate", json={"address": "999.999.999.999"})

        assert response.status_code == 400
        body = response.json()
        assert "detail" in body

    def test_missing_address_field(self):
        response = client.post("/api/v1/ipv4/validate", json={})

        assert response.status_code == 422  # FastAPI validation error
        body = response.json()
        assert "detail" in body


class TestCheckPrivate:
    """Tests for RFC1918/RFC6598 check endpoint"""

    def test_rfc1918_10_network(self):
        response = client.post("/api/v1/ipv4/check-private", json={"address": "10.1.1.1"})

        assert response.status_code == 200
        body = response.json()
        assert body["is_rfc1918"] is True
        assert body["is_rfc6598"] is False
        assert body["matched_rfc1918_range"] == "10.0.0.0/8"

    def test_rfc1918_172_network(self):
        response = client.post("/api/v1/ipv4/check-private", json={"address": "172.16.0.1"})

        assert response.status_code == 200
        body = response.json()
        assert body["is_rfc1918"] is True
        assert body["matched_rfc1918_range"] == "172.16.0.0/12"

    def test_rfc1918_192_network(self):
        response = client.post("/api/v1/ipv4/check-private", json={"address": "192.168.1.1"})

        assert response.status_code == 200
        body = response.json()
        assert body["is_rfc1918"] is True
        assert body["matched_rfc1918_range"] == "192.168.0.0/16"

    def test_rfc6598_shared_address_space(self):
        response = client.post("/api/v1/ipv4/check-private", json={"address": "100.64.1.1"})

        assert response.status_code == 200
        body = response.json()
        assert body["is_rfc1918"] is False
        assert body["is_rfc6598"] is True
        assert body["matched_rfc6598_range"] == "100.64.0.0/10"

    def test_public_ipv4_address(self):
        response = client.post("/api/v1/ipv4/check-private", json={"address": "8.8.8.8"})

        assert response.status_code == 200
        body = response.json()
        assert body["is_rfc1918"] is False
        assert body["is_rfc6598"] is False

    def test_ipv6_rejected(self):
        response = client.post("/api/v1/ipv4/check-private", json={"address": "2606:4700::1"})

        assert response.status_code == 400
        body = response.json()
        assert "only supports IPv4" in body["detail"]


class TestCheckCloudflare:
    """Tests for Cloudflare range check endpoint"""

    def test_cloudflare_ipv4_address(self):
        response = client.post("/api/v1/ipv4/check-cloudflare", json={"address": "104.16.1.1"})

        assert response.status_code == 200
        body = response.json()
        assert body["is_cloudflare"] is True
        assert body["ip_version"] == 4
        assert "104.16.0.0/13" in body["matched_ranges"]

    def test_cloudflare_ipv6_address(self):
        response = client.post("/api/v1/ipv4/check-cloudflare", json={"address": "2606:4700::1"})

        assert response.status_code == 200
        body = response.json()
        assert body["is_cloudflare"] is True
        assert body["ip_version"] == 6
        assert "2606:4700::/32" in body["matched_ranges"]

    def test_non_cloudflare_ipv4(self):
        response = client.post("/api/v1/ipv4/check-cloudflare", json={"address": "8.8.8.8"})

        assert response.status_code == 200
        body = response.json()
        assert body["is_cloudflare"] is False
        assert body["ip_version"] == 4

    def test_cloudflare_ipv4_network(self):
        response = client.post("/api/v1/ipv4/check-cloudflare", json={"address": "173.245.48.0/20"})

        assert response.status_code == 200
        body = response.json()
        assert body["is_cloudflare"] is True
        assert "173.245.48.0/20" in body["matched_ranges"]

    def test_invalid_address_format(self):
        response = client.post("/api/v1/ipv4/check-cloudflare", json={"address": "invalid"})

        assert response.status_code == 400
        body = response.json()
        assert "detail" in body


class TestSubnetInfo:
    """Tests for subnet information endpoint"""

    def test_standard_subnet_azure_mode(self):
        response = client.post("/api/v1/ipv4/subnet-info", json={"network": "192.168.1.0/24"})

        assert response.status_code == 200
        body = response.json()
        assert body["mode"] == "Azure"  # Default
        assert body["network_address"] == "192.168.1.0"
        assert body["broadcast_address"] == "192.168.1.255"
        assert body["netmask"] == "255.255.255.0"
        assert body["prefix_length"] == 24
        assert body["total_addresses"] == 256
        assert body["usable_addresses"] == 251  # 256 - 5 (Azure reserves 5)
        assert body["first_usable_ip"] == "192.168.1.4"  # Skip .0, .1, .2, .3
        assert body["last_usable_ip"] == "192.168.1.254"

    def test_standard_subnet_aws_mode(self):
        response = client.post("/api/v1/ipv4/subnet-info", json={"network": "10.0.0.0/24", "mode": "AWS"})

        assert response.status_code == 200
        body = response.json()
        assert body["mode"] == "AWS"
        assert body["usable_addresses"] == 251  # Same as Azure
        assert body["first_usable_ip"] == "10.0.0.4"

    def test_standard_subnet_oci_mode(self):
        response = client.post("/api/v1/ipv4/subnet-info", json={"network": "10.0.0.0/24", "mode": "OCI"})

        assert response.status_code == 200
        body = response.json()
        assert body["mode"] == "OCI"
        assert body["usable_addresses"] == 253  # 256 - 3 (OCI reserves 3)
        assert body["first_usable_ip"] == "10.0.0.2"  # Skip .0, .1

    def test_standard_subnet_standard_mode(self):
        response = client.post(
            "/api/v1/ipv4/subnet-info",
            json={"network": "10.0.0.0/24", "mode": "Standard"},
        )

        assert response.status_code == 200
        body = response.json()
        assert body["mode"] == "Standard"
        assert body["usable_addresses"] == 254  # 256 - 2
        assert body["first_usable_ip"] == "10.0.0.1"  # Skip .0 only

    def test_slash_31_subnet(self):
        response = client.post("/api/v1/ipv4/subnet-info", json={"network": "10.0.0.0/31"})

        assert response.status_code == 200
        body = response.json()
        assert body["total_addresses"] == 2
        assert body["usable_addresses"] == 2
        assert body["first_usable_ip"] == "10.0.0.0"
        assert body["last_usable_ip"] == "10.0.0.1"
        assert body["broadcast_address"] is None
        assert "point-to-point" in body["note"]

    def test_slash_32_subnet(self):
        response = client.post("/api/v1/ipv4/subnet-info", json={"network": "10.0.0.5/32"})

        assert response.status_code == 200
        body = response.json()
        assert body["total_addresses"] == 1
        assert body["usable_addresses"] == 1
        assert body["first_usable_ip"] == "10.0.0.5"
        assert body["last_usable_ip"] == "10.0.0.5"
        assert body["broadcast_address"] is None
        assert "Single host" in body["note"]

    def test_large_subnet(self):
        response = client.post("/api/v1/ipv4/subnet-info", json={"network": "10.0.0.0/16", "mode": "Azure"})

        assert response.status_code == 200
        body = response.json()
        assert body["total_addresses"] == 65536
        assert body["usable_addresses"] == 65531  # 65536 - 5
        assert body["first_usable_ip"] == "10.0.0.4"
        assert body["last_usable_ip"] == "10.0.255.254"

    def test_invalid_mode(self):
        response = client.post(
            "/api/v1/ipv4/subnet-info",
            json={"network": "10.0.0.0/24", "mode": "InvalidMode"},
        )

        assert response.status_code == 400
        body = response.json()
        assert "Invalid mode" in body["detail"]

    def test_missing_network_field(self):
        response = client.post("/api/v1/ipv4/subnet-info", json={"mode": "Azure"})

        assert response.status_code == 422  # FastAPI validation error
        body = response.json()
        assert "detail" in body

    def test_ipv6_rejected(self):
        response = client.post("/api/v1/ipv4/subnet-info", json={"network": "2001:db8::/32"})

        assert response.status_code == 400
        body = response.json()
        assert "only supports IPv4" in body["detail"]

    def test_wildcard_mask(self):
        response = client.post("/api/v1/ipv4/subnet-info", json={"network": "10.0.0.0/24"})

        assert response.status_code == 200
        body = response.json()
        assert body["wildcard_mask"] == "0.0.0.255"
