from pathlib import Path

from app.catalog import (
    CatalogDocument,
    application_specs,
    deployment_records,
    find_application,
    load_catalog,
    scorecard_records,
    secret_bindings,
)


REPO_ROOT = Path(__file__).resolve().parents[3]


def test_load_catalog_projects_application_specs_from_platform_catalog() -> None:
    catalog = load_catalog(REPO_ROOT / "catalog/platform-apps.json")

    applications = application_specs(catalog)

    assert applications
    assert find_application(catalog, "hello-platform").owner == "team-dolphin"
    assert find_application(catalog, "missing") is None


def test_deployment_records_preserve_existing_projection_defaults() -> None:
    catalog = CatalogDocument.model_validate(
        {
            "applications": [
                {
                    "name": "fixture-service",
                    "owner": "team-platform",
                    "health": "/readyz",
                    "deployment": {
                        "controller": "argocd",
                        "image": "registry.local/fixture:base",
                        "sync": "automated",
                    },
                    "environments": [
                        {
                            "name": "dev",
                            "route": "https://fixture.dev.example.test",
                            "deployment": {"image": "registry.local/fixture:dev"},
                        },
                        {
                            "name": "uat",
                            "route": "https://fixture.uat.example.test",
                            "health": "/healthz",
                            "sync": "manual",
                        },
                    ],
                }
            ]
        }
    )

    assert [record.model_dump() for record in deployment_records(catalog)] == [
        {
            "app": "fixture-service",
            "environment": "dev",
            "route": "https://fixture.dev.example.test",
            "controller": "argocd",
            "image": "registry.local/fixture:dev",
            "health": "/readyz",
            "sync": "automated",
        },
        {
            "app": "fixture-service",
            "environment": "uat",
            "route": "https://fixture.uat.example.test",
            "controller": "argocd",
            "image": "registry.local/fixture:base",
            "health": "/healthz",
            "sync": "manual",
        },
    ]


def test_secret_bindings_default_missing_binding_fields_and_keep_extra_fields() -> None:
    catalog = CatalogDocument.model_validate(
        {
            "applications": [
                {
                    "name": "fixture-service",
                    "secrets": [
                        {"name": "runtime-token", "scope": "runtime"},
                        {"name": "oidc-client", "binding": "sso", "rotation": "platform"},
                    ],
                }
            ]
        }
    )

    assert [record.model_dump() for record in secret_bindings(catalog)] == [
        {
            "app": "fixture-service",
            "name": "runtime-token",
            "binding": "unknown",
            "rotation": "unknown",
            "scope": "runtime",
        },
        {
            "app": "fixture-service",
            "name": "oidc-client",
            "binding": "sso",
            "rotation": "platform",
        },
    ]


def test_scorecard_records_default_missing_fields_and_infer_owner() -> None:
    catalog = CatalogDocument.model_validate(
        {
            "applications": [
                {
                    "name": "owned-service",
                    "owner": "team-platform",
                    "scorecard": {"tier": "gold"},
                },
                {
                    "name": "anonymous-service",
                    "scorecard": {
                        "runtime_profile": "restricted",
                        "has_health_endpoint": True,
                        "has_network_policy": True,
                    },
                },
            ]
        }
    )

    assert [record.model_dump() for record in scorecard_records(catalog)] == [
        {
            "app": "owned-service",
            "runtime_profile": "unknown",
            "has_health_endpoint": False,
            "has_network_policy": False,
            "has_owner": True,
            "tier": "gold",
        },
        {
            "app": "anonymous-service",
            "runtime_profile": "restricted",
            "has_health_endpoint": True,
            "has_network_policy": True,
            "has_owner": False,
        },
    ]
