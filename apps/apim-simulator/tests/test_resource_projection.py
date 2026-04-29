from __future__ import annotations

import json

import pytest

from app.config import (
    ApiConfig,
    ApiReleaseConfig,
    ApiRevisionConfig,
    ApiSchemaConfig,
    DiagnosticConfig,
    DiagnosticDataMaskingConfig,
    DiagnosticHttpMessageConfig,
    DiagnosticMaskingRuleConfig,
    GatewayConfig,
    GroupConfig,
    LoggerApplicationInsightsConfig,
    LoggerConfig,
    NamedValueConfig,
    OperationConfig,
    OperationParameterConfig,
    OperationRepresentationConfig,
    OperationRequestMetadataConfig,
    OperationResponseMetadataConfig,
    ProductConfig,
    Subscription,
    SubscriptionConfig,
    SubscriptionKeyPair,
    TagConfig,
    load_config,
)
from app.resource_projection import project_summary
from app.urls import http_url


@pytest.mark.contract("PROJECTION-SUMMARY")
def test_project_summary_uses_service_scoped_ids_and_masks_secrets() -> None:
    cfg = GatewayConfig(
        service={
            "name": "lab-sim",
            "display_name": "Lab Simulator",
            "public_network_access_enabled": False,
            "virtual_network_type": "Internal",
            "hostname_configurations": [{"type": "Proxy", "host_name": "api.example.test"}],
        },
        allow_anonymous=True,
        groups={"admins": GroupConfig(id="admins", name="Admins", users=["dev-1"])},
        products={"starter": ProductConfig(name="Starter", require_subscription=True, groups=["admins"])},
        tags={"starter": TagConfig(display_name="Starter")},
        users={
            "dev-1": {
                "id": "dev-1",
                "email": "dev@example.com",
                "name": "Dev One",
                "first_name": "Dev",
                "last_name": "One",
                "state": "active",
            }
        },
        loggers={
            "appinsights": LoggerConfig(
                logger_type="application_insights",
                resource_id="/subscriptions/test/resourceGroups/rg/providers/Microsoft.Insights/components/demo",
                application_insights=LoggerApplicationInsightsConfig(
                    instrumentation_key="ikey-secret",
                    connection_string="InstrumentationKey=ikey-secret;IngestionEndpoint=https://example.test/",
                ),
            )
        },
        diagnostics={
            "applicationinsights": DiagnosticConfig(
                identifier="applicationinsights",
                logger_id="appinsights",
                always_log_errors=True,
                sampling_percentage=5.0,
                verbosity="verbose",
                frontend_request=DiagnosticHttpMessageConfig(
                    body_bytes=32,
                    headers_to_log=["content-type"],
                    data_masking=DiagnosticDataMaskingConfig(
                        headers=[DiagnosticMaskingRuleConfig(mode="Mask", value="authorization")]
                    ),
                ),
            )
        },
        subscription=SubscriptionConfig(
            required=True,
            subscriptions={
                "starter-dev": Subscription(
                    id="starter-dev",
                    name="starter-dev",
                    keys=SubscriptionKeyPair(primary="primary", secondary="secondary"),
                    products=["starter"],
                )
            },
        ),
        named_values={"backend-secret": NamedValueConfig(value="super-secret-token", secret=True)},
        apis={
            "hello": ApiConfig(
                name="hello",
                path="hello",
                upstream_base_url=http_url("upstream"),
                products=["starter"],
                revision="2",
                revision_description="Current revision",
                source_api_id="service/lab-sim/apis/hello;rev=1",
                is_current=True,
                is_online=True,
                tags=["starter"],
                operations={
                    "getHello": OperationConfig(
                        name="getHello",
                        method="GET",
                        url_template="/hello/{name}",
                        description="Return a greeting",
                        tags=["starter"],
                        template_parameters=[
                            OperationParameterConfig(name="name", required=True, type="string", description="Name")
                        ],
                        request=OperationRequestMetadataConfig(
                            headers=[
                                OperationParameterConfig(
                                    name="x-trace-id",
                                    required=False,
                                    type="string",
                                    description="Optional trace correlation header",
                                )
                            ]
                        ),
                        responses=[
                            OperationResponseMetadataConfig(
                                status_code=200,
                                description="Greeting payload",
                                representations=[
                                    OperationRepresentationConfig(
                                        content_type="application/json",
                                        schema_id="HelloResponse",
                                        type_name="HelloResponse",
                                    )
                                ],
                            )
                        ],
                    )
                },
                schemas={
                    "HelloResponse": ApiSchemaConfig(
                        content_type="application/json",
                        value='{"type":"object","properties":{"message":{"type":"string"}}}',
                    )
                },
                revisions={
                    "1": ApiRevisionConfig(
                        revision="1", description="Initial revision", is_current=False, is_online=False
                    ),
                    "2": ApiRevisionConfig(
                        revision="2",
                        description="Current revision",
                        is_current=True,
                        is_online=True,
                        source_api_id="service/lab-sim/apis/hello;rev=1",
                    ),
                },
                releases={
                    "public": ApiReleaseConfig(
                        name="public",
                        api_id="service/lab-sim/apis/hello;rev=2",
                        notes="Shipped publicly",
                        revision="2",
                    )
                },
            )
        },
    )
    cfg.routes = cfg.materialize_routes()

    payload = project_summary(cfg, trace_store={"trace-1": {"id": "trace-1"}})

    assert payload["service"]["id"] == "service/lab-sim"
    assert payload["service"]["public_network_access_enabled"] is False
    assert payload["service"]["virtual_network_type"] == "Internal"
    assert payload["service"]["hostname_configurations"] == [
        {
            "type": "Proxy",
            "host_name": "api.example.test",
            "negotiate_client_certificate": False,
            "default_ssl_binding": False,
        }
    ]
    assert payload["service"]["counts"]["apis"] == 1
    assert payload["service"]["counts"]["operations"] == 1
    assert payload["service"]["counts"]["api_revisions"] == 2
    assert payload["service"]["counts"]["api_releases"] == 1
    assert payload["service"]["counts"]["loggers"] == 1
    assert payload["service"]["counts"]["diagnostics"] == 1
    assert payload["service"]["counts"]["tags"] == 1
    assert payload["service"]["counts"]["recent_traces"] == 1
    assert payload["apis"][0]["resource_id"] == "service/lab-sim/apis/hello"
    assert payload["apis"][0]["revision"] == "2"
    assert payload["apis"][0]["tags"] == ["starter"]
    assert payload["apis"][0]["operations"][0]["resource_id"] == "service/lab-sim/apis/hello/operations/getHello"
    assert payload["apis"][0]["operations"][0]["tags"] == ["starter"]
    assert payload["apis"][0]["operations"][0]["description"] == "Return a greeting"
    assert payload["apis"][0]["operations"][0]["template_parameters"][0]["name"] == "name"
    assert payload["apis"][0]["operations"][0]["request"]["headers"][0]["name"] == "x-trace-id"
    assert payload["apis"][0]["operations"][0]["responses"][0]["representations"][0]["schema_id"] == "HelloResponse"
    assert payload["apis"][0]["schemas"][0]["resource_id"] == "service/lab-sim/apis/hello/schemas/HelloResponse"
    assert payload["apis"][0]["revisions"][0]["resource_id"] == "service/lab-sim/apis/hello/revisions/1"
    assert payload["apis"][0]["releases"][0]["resource_id"] == "service/lab-sim/apis/hello/releases/public"
    assert payload["tags"][0]["resource_id"] == "service/lab-sim/tags/starter"
    assert payload["products"][0]["groups"] == ["admins"]
    assert payload["users"][0]["groups"] == ["admins"]
    assert payload["users"][0]["first_name"] == "Dev"
    assert payload["groups"][0]["products"] == ["starter"]
    assert payload["loggers"][0]["resource_id"] == "service/lab-sim/loggers/appinsights"
    assert payload["loggers"][0]["application_insights"]["instrumentation_key"] == "***"
    assert payload["diagnostics"][0]["resource_id"] == "service/lab-sim/diagnostics/applicationinsights"
    assert payload["diagnostics"][0]["logger_resource_id"] == "service/lab-sim/loggers/appinsights"
    assert payload["diagnostics"][0]["frontend_request"]["headers_to_log"] == ["content-type"]
    assert payload["subscriptions"][0]["resource_id"] == "service/lab-sim/subscriptions/starter-dev"
    assert payload["named_values"][0]["value"] == "***"
    assert payload["named_values"][0]["resolved"]["value"] == "***"


def test_load_config_accepts_api_and_route_authored_files(tmp_path, monkeypatch) -> None:
    api_authored = tmp_path / "api-authored.json"
    api_authored.write_text(
        json.dumps(
            {
                "allow_anonymous": True,
                "apis": {
                    "sample": {
                        "name": "sample",
                        "path": "sample",
                        "upstream_base_url": http_url("upstream"),
                        "operations": {"health": {"name": "health", "method": "GET", "url_template": "/health"}},
                    }
                },
            }
        ),
        encoding="utf-8",
    )
    monkeypatch.setenv("APIM_CONFIG_PATH", str(api_authored))

    loaded_api = load_config()

    assert loaded_api.service.name == "apim-simulator"
    assert list(loaded_api.apis) == ["sample"]
    assert loaded_api.routes == []

    route_authored = tmp_path / "route-authored.json"
    route_authored.write_text(
        json.dumps(
            {
                "allow_anonymous": True,
                "routes": [
                    {
                        "name": "legacy",
                        "path_prefix": "/api",
                        "upstream_base_url": http_url("upstream"),
                        "upstream_path_prefix": "/api",
                    }
                ],
            }
        ),
        encoding="utf-8",
    )
    monkeypatch.setenv("APIM_CONFIG_PATH", str(route_authored))

    loaded_route = load_config()

    assert loaded_route.service.display_name == "Local APIM Simulator"
    assert loaded_route.apis == {}
    assert loaded_route.routes[0].name == "legacy"
