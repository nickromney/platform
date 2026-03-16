# Policy Composition

Generated with [`terraform/kubernetes/scripts/show-policy-composition.sh`](../scripts/show-policy-composition.sh) using `--target all --format markdown`.

This view answers three related questions:

- what the current checked-in policy composition includes after filter application
- which source files contribute each rendered resource
- which policies in each overlay survive the active slice

Important notes:

- this is a source-tree composition view, not a shipped stage-default view
- optional sentiment legacy LLM policies still appear here because they are checked in under `cluster-policies/`; the shipped kind, lima, and slicer stages default to in-process SST with `llm_gateway_mode = "disabled"`

Active filters:

- namespace: `all`
- direction: `all`
- label terms: `none`

## Cilium

Rendered from [`terraform/kubernetes/cluster-policies/cilium`](./cilium) after filter application.

Displayed policy source paths below are relative to [`terraform/kubernetes/cluster-policies/cilium`](./cilium).

### Top-Level Rendered Set

#### CiliumCIDRGroup

| Name | Source |
| --- | --- |
| `approved-egress-cidrs` | [`shared/approved-egress-cidrs.yaml`](./cilium/shared/approved-egress-cidrs.yaml) |

#### CiliumClusterwideNetworkPolicy

| Name | Source |
| --- | --- |
| `allow-application-backend-egress-via-cidrgroup` | [`shared/application-backend-egress-via-cidrgroup.yaml`](./cilium/shared/application-backend-egress-via-cidrgroup.yaml) |
| `allow-application-backend-egress-via-fqdn` | [`shared/application-backend-egress-via-fqdn.yaml`](./cilium/shared/application-backend-egress-via-fqdn.yaml) |
| `allow-sentiment-llama-cpp-world-egress` | [`shared/sentiment-llama-cpp-world-egress.yaml`](./cilium/shared/sentiment-llama-cpp-world-egress.yaml) |
| `allow-sentiment-dns-egress` | [`shared/sentiment-api-dns-egress.yaml`](./cilium/shared/sentiment-api-dns-egress.yaml) |
| `allow-shared-identity-egress-via-fqdn` | [`shared/shared-identity-egress-via-fqdn.yaml`](./cilium/shared/shared-identity-egress-via-fqdn.yaml) |
| `apim-baseline` | [`shared/apim-baseline.yaml`](./cilium/shared/apim-baseline.yaml) |
| `application-baseline` | [`shared/application-baseline.yaml`](./cilium/shared/application-baseline.yaml) |
| `argocd-hardened` | [`shared/argocd-hardened.yaml`](./cilium/shared/argocd-hardened.yaml) |
| `argocd-repo-server-helm-egress` | [`shared/argocd-hardened.yaml`](./cilium/shared/argocd-hardened.yaml) |
| `deny-application-cloud-metadata` | [`shared/application-cloud-metadata-deny.yaml`](./cilium/shared/application-cloud-metadata-deny.yaml) |
| `deny-application-sentiment-to-subnetcalc` | [`shared/application-project-boundaries.yaml`](./cilium/shared/application-project-boundaries.yaml) |
| `deny-application-subnetcalc-to-sentiment` | [`shared/application-project-boundaries.yaml`](./cilium/shared/application-project-boundaries.yaml) |
| `deny-cloud-metadata-egress` | [`shared/deny-cloud-metadata-egress.yaml`](./cilium/shared/deny-cloud-metadata-egress.yaml) |
| `gitea-hardened` | [`shared/gitea-hardened.yaml`](./cilium/shared/gitea-hardened.yaml) |
| `gitea-runner-hardened` | [`shared/gitea-runner-hardened.yaml`](./cilium/shared/gitea-runner-hardened.yaml) |
| `nginx-gateway-control-plane` | [`shared/azure-auth-nginx-gateway-ingress.yaml`](./cilium/shared/azure-auth-nginx-gateway-ingress.yaml) |
| `observability-hardened` | [`shared/observability-hardened.yaml`](./cilium/shared/observability-hardened.yaml) |
| `platform-baseline-headlamp` | [`shared/platform-baseline.yaml`](./cilium/shared/platform-baseline.yaml) |
| `platform-gateway-hardened` | [`shared/platform-gateway-hardened.yaml`](./cilium/shared/platform-gateway-hardened.yaml) |
| `shared-auth-proxy-bridge` | [`shared/shared-auth-proxy-bridge.yaml`](./cilium/shared/shared-auth-proxy-bridge.yaml) |
| `shared-baseline` | [`shared/shared-baseline.yaml`](./cilium/shared/shared-baseline.yaml) |
| `shared-identity-provider-ingress` | [`shared/shared-identity-provider-ingress.yaml`](./cilium/shared/shared-identity-provider-ingress.yaml) |
| `sso-hardened` | [`shared/sso-hardened.yaml`](./cilium/shared/sso-hardened.yaml) |

#### CiliumNetworkPolicy

| Name | Source |
| --- | --- |
| `sentiment-api-egress` | [`projects/sentiment/sentiment-runtime.yaml`](./cilium/projects/sentiment/sentiment-runtime.yaml) |
| `sentiment-backend-ingress` | [`projects/sentiment/sentiment-runtime.yaml`](./cilium/projects/sentiment/sentiment-runtime.yaml) |
| `sentiment-frontend-ingress` | [`projects/sentiment/sentiment-runtime.yaml`](./cilium/projects/sentiment/sentiment-runtime.yaml) |
| `sentiment-litellm-ingress-egress` | [`projects/sentiment/sentiment-runtime.yaml`](./cilium/projects/sentiment/sentiment-runtime.yaml) |
| `sentiment-llama-ingress` | [`projects/sentiment/sentiment-runtime.yaml`](./cilium/projects/sentiment/sentiment-runtime.yaml) |
| `sentiment-router-http-routes` | [`projects/sentiment/sentiment-http-routes.yaml`](./cilium/projects/sentiment/sentiment-http-routes.yaml) |
| `sentiment-router-ingress` | [`projects/sentiment/sentiment-runtime.yaml`](./cilium/projects/sentiment/sentiment-runtime.yaml) |
| `subnetcalc-api-http-routes` | [`projects/subnetcalc/subnetcalc-http-routes.yaml`](./cilium/projects/subnetcalc/subnetcalc-http-routes.yaml) |
| `subnetcalc-cloudflare-live-fetch` | [`dev/overrides/subnetcalc-cloudflare-live-fetch.yaml`](./cilium/dev/overrides/subnetcalc-cloudflare-live-fetch.yaml) |
| `subnetcalc-frontend-ingress` | [`projects/subnetcalc/subnetcalc-runtime.yaml`](./cilium/projects/subnetcalc/subnetcalc-runtime.yaml) |
| `subnetcalc-router-http-routes` | [`projects/subnetcalc/subnetcalc-http-routes.yaml`](./cilium/projects/subnetcalc/subnetcalc-http-routes.yaml) |
| `subnetcalc-router-ingress` | [`projects/subnetcalc/subnetcalc-runtime.yaml`](./cilium/projects/subnetcalc/subnetcalc-runtime.yaml) |

### Overlay: shared

#### CiliumCIDRGroup

| Name | Source |
| --- | --- |
| `approved-egress-cidrs` | [`shared/approved-egress-cidrs.yaml`](./cilium/shared/approved-egress-cidrs.yaml) |

#### CiliumClusterwideNetworkPolicy

| Name | Source |
| --- | --- |
| `allow-application-backend-egress-via-cidrgroup` | [`shared/application-backend-egress-via-cidrgroup.yaml`](./cilium/shared/application-backend-egress-via-cidrgroup.yaml) |
| `allow-application-backend-egress-via-fqdn` | [`shared/application-backend-egress-via-fqdn.yaml`](./cilium/shared/application-backend-egress-via-fqdn.yaml) |
| `allow-sentiment-llama-cpp-world-egress` | [`shared/sentiment-llama-cpp-world-egress.yaml`](./cilium/shared/sentiment-llama-cpp-world-egress.yaml) |
| `allow-sentiment-dns-egress` | [`shared/sentiment-api-dns-egress.yaml`](./cilium/shared/sentiment-api-dns-egress.yaml) |
| `allow-shared-identity-egress-via-fqdn` | [`shared/shared-identity-egress-via-fqdn.yaml`](./cilium/shared/shared-identity-egress-via-fqdn.yaml) |
| `apim-baseline` | [`shared/apim-baseline.yaml`](./cilium/shared/apim-baseline.yaml) |
| `application-baseline` | [`shared/application-baseline.yaml`](./cilium/shared/application-baseline.yaml) |
| `argocd-hardened` | [`shared/argocd-hardened.yaml`](./cilium/shared/argocd-hardened.yaml) |
| `argocd-repo-server-helm-egress` | [`shared/argocd-hardened.yaml`](./cilium/shared/argocd-hardened.yaml) |
| `deny-application-cloud-metadata` | [`shared/application-cloud-metadata-deny.yaml`](./cilium/shared/application-cloud-metadata-deny.yaml) |
| `deny-application-sentiment-to-subnetcalc` | [`shared/application-project-boundaries.yaml`](./cilium/shared/application-project-boundaries.yaml) |
| `deny-application-subnetcalc-to-sentiment` | [`shared/application-project-boundaries.yaml`](./cilium/shared/application-project-boundaries.yaml) |
| `deny-cloud-metadata-egress` | [`shared/deny-cloud-metadata-egress.yaml`](./cilium/shared/deny-cloud-metadata-egress.yaml) |
| `gitea-hardened` | [`shared/gitea-hardened.yaml`](./cilium/shared/gitea-hardened.yaml) |
| `gitea-runner-hardened` | [`shared/gitea-runner-hardened.yaml`](./cilium/shared/gitea-runner-hardened.yaml) |
| `nginx-gateway-control-plane` | [`shared/azure-auth-nginx-gateway-ingress.yaml`](./cilium/shared/azure-auth-nginx-gateway-ingress.yaml) |
| `observability-hardened` | [`shared/observability-hardened.yaml`](./cilium/shared/observability-hardened.yaml) |
| `platform-baseline-headlamp` | [`shared/platform-baseline.yaml`](./cilium/shared/platform-baseline.yaml) |
| `platform-gateway-hardened` | [`shared/platform-gateway-hardened.yaml`](./cilium/shared/platform-gateway-hardened.yaml) |
| `shared-auth-proxy-bridge` | [`shared/shared-auth-proxy-bridge.yaml`](./cilium/shared/shared-auth-proxy-bridge.yaml) |
| `shared-baseline` | [`shared/shared-baseline.yaml`](./cilium/shared/shared-baseline.yaml) |
| `shared-identity-provider-ingress` | [`shared/shared-identity-provider-ingress.yaml`](./cilium/shared/shared-identity-provider-ingress.yaml) |
| `sso-hardened` | [`shared/sso-hardened.yaml`](./cilium/shared/sso-hardened.yaml) |

### Overlay: dev

#### CiliumNetworkPolicy

| Name | Source |
| --- | --- |
| `sentiment-api-egress` | [`projects/sentiment/sentiment-runtime.yaml`](./cilium/projects/sentiment/sentiment-runtime.yaml) |
| `sentiment-backend-ingress` | [`projects/sentiment/sentiment-runtime.yaml`](./cilium/projects/sentiment/sentiment-runtime.yaml) |
| `sentiment-frontend-ingress` | [`projects/sentiment/sentiment-runtime.yaml`](./cilium/projects/sentiment/sentiment-runtime.yaml) |
| `sentiment-litellm-ingress-egress` | [`projects/sentiment/sentiment-runtime.yaml`](./cilium/projects/sentiment/sentiment-runtime.yaml) |
| `sentiment-llama-ingress` | [`projects/sentiment/sentiment-runtime.yaml`](./cilium/projects/sentiment/sentiment-runtime.yaml) |
| `sentiment-router-http-routes` | [`projects/sentiment/sentiment-http-routes.yaml`](./cilium/projects/sentiment/sentiment-http-routes.yaml) |
| `sentiment-router-ingress` | [`projects/sentiment/sentiment-runtime.yaml`](./cilium/projects/sentiment/sentiment-runtime.yaml) |
| `subnetcalc-api-http-routes` | [`projects/subnetcalc/subnetcalc-http-routes.yaml`](./cilium/projects/subnetcalc/subnetcalc-http-routes.yaml) |
| `subnetcalc-cloudflare-live-fetch` | [`dev/overrides/subnetcalc-cloudflare-live-fetch.yaml`](./cilium/dev/overrides/subnetcalc-cloudflare-live-fetch.yaml) |
| `subnetcalc-frontend-ingress` | [`projects/subnetcalc/subnetcalc-runtime.yaml`](./cilium/projects/subnetcalc/subnetcalc-runtime.yaml) |
| `subnetcalc-router-http-routes` | [`projects/subnetcalc/subnetcalc-http-routes.yaml`](./cilium/projects/subnetcalc/subnetcalc-http-routes.yaml) |
| `subnetcalc-router-ingress` | [`projects/subnetcalc/subnetcalc-runtime.yaml`](./cilium/projects/subnetcalc/subnetcalc-runtime.yaml) |

### Overlay: uat

#### CiliumNetworkPolicy

| Name | Source |
| --- | --- |
| `sentiment-api-egress` | [`projects/sentiment/sentiment-runtime.yaml`](./cilium/projects/sentiment/sentiment-runtime.yaml) |
| `sentiment-backend-ingress` | [`projects/sentiment/sentiment-runtime.yaml`](./cilium/projects/sentiment/sentiment-runtime.yaml) |
| `sentiment-frontend-ingress` | [`projects/sentiment/sentiment-runtime.yaml`](./cilium/projects/sentiment/sentiment-runtime.yaml) |
| `sentiment-litellm-ingress-egress` | [`projects/sentiment/sentiment-runtime.yaml`](./cilium/projects/sentiment/sentiment-runtime.yaml) |
| `sentiment-llama-ingress` | [`projects/sentiment/sentiment-runtime.yaml`](./cilium/projects/sentiment/sentiment-runtime.yaml) |
| `sentiment-router-http-routes` | [`projects/sentiment/sentiment-http-routes.yaml`](./cilium/projects/sentiment/sentiment-http-routes.yaml) |
| `sentiment-router-ingress` | [`projects/sentiment/sentiment-runtime.yaml`](./cilium/projects/sentiment/sentiment-runtime.yaml) |
| `subnetcalc-api-http-routes` | [`projects/subnetcalc/subnetcalc-http-routes.yaml`](./cilium/projects/subnetcalc/subnetcalc-http-routes.yaml) |
| `subnetcalc-frontend-ingress` | [`projects/subnetcalc/subnetcalc-runtime.yaml`](./cilium/projects/subnetcalc/subnetcalc-runtime.yaml) |
| `subnetcalc-router-http-routes` | [`projects/subnetcalc/subnetcalc-http-routes.yaml`](./cilium/projects/subnetcalc/subnetcalc-http-routes.yaml) |
| `subnetcalc-router-ingress` | [`projects/subnetcalc/subnetcalc-runtime.yaml`](./cilium/projects/subnetcalc/subnetcalc-runtime.yaml) |

### Overlay: sit

#### CiliumNetworkPolicy

| Name | Source |
| --- | --- |
| `sentiment-api-egress` | [`projects/sentiment/sentiment-runtime.yaml`](./cilium/projects/sentiment/sentiment-runtime.yaml) |
| `sentiment-backend-ingress` | [`projects/sentiment/sentiment-runtime.yaml`](./cilium/projects/sentiment/sentiment-runtime.yaml) |
| `sentiment-frontend-ingress` | [`projects/sentiment/sentiment-runtime.yaml`](./cilium/projects/sentiment/sentiment-runtime.yaml) |
| `sentiment-litellm-ingress-egress` | [`projects/sentiment/sentiment-runtime.yaml`](./cilium/projects/sentiment/sentiment-runtime.yaml) |
| `sentiment-llama-ingress` | [`projects/sentiment/sentiment-runtime.yaml`](./cilium/projects/sentiment/sentiment-runtime.yaml) |
| `sentiment-router-http-routes` | [`projects/sentiment/sentiment-http-routes.yaml`](./cilium/projects/sentiment/sentiment-http-routes.yaml) |
| `sentiment-router-ingress` | [`projects/sentiment/sentiment-runtime.yaml`](./cilium/projects/sentiment/sentiment-runtime.yaml) |
| `subnetcalc-api-http-routes` | [`projects/subnetcalc/subnetcalc-http-routes.yaml`](./cilium/projects/subnetcalc/subnetcalc-http-routes.yaml) |
| `subnetcalc-frontend-ingress` | [`projects/subnetcalc/subnetcalc-runtime.yaml`](./cilium/projects/subnetcalc/subnetcalc-runtime.yaml) |
| `subnetcalc-router-http-routes` | [`projects/subnetcalc/subnetcalc-http-routes.yaml`](./cilium/projects/subnetcalc/subnetcalc-http-routes.yaml) |
| `subnetcalc-router-ingress` | [`projects/subnetcalc/subnetcalc-runtime.yaml`](./cilium/projects/subnetcalc/subnetcalc-runtime.yaml) |

## Kyverno

Rendered from [`terraform/kubernetes/cluster-policies/kyverno`](./kyverno) after filter application.

### Top-Level Rendered Set

#### ClusterPolicy

| Name | Source |
| --- | --- |
| `default-deny-namespaces` | [`terraform/kubernetes/cluster-policies/kyverno/shared/namespace-default-deny.yaml`](./kyverno/shared/namespace-default-deny.yaml) |
| `protect-default-deny-netpol` | [`terraform/kubernetes/cluster-policies/kyverno/shared/protect-default-deny.yaml`](./kyverno/shared/protect-default-deny.yaml) |
| `require-app-labels-application-namespaces` | [`terraform/kubernetes/cluster-policies/kyverno/shared/require-app-labels-application-namespaces.yaml`](./kyverno/shared/require-app-labels-application-namespaces.yaml) |
| `restrict-image-registries` | [`terraform/kubernetes/cluster-policies/kyverno/shared/restrict-image-registries.yaml`](./kyverno/shared/restrict-image-registries.yaml) |
| `uat-restrict-capabilities` | [`terraform/kubernetes/cluster-policies/kyverno/uat/uat-restrict-capabilities.yaml`](./kyverno/uat/uat-restrict-capabilities.yaml) |

### Overlay: shared

#### ClusterPolicy

| Name | Source |
| --- | --- |
| `default-deny-namespaces` | [`terraform/kubernetes/cluster-policies/kyverno/shared/namespace-default-deny.yaml`](./kyverno/shared/namespace-default-deny.yaml) |
| `protect-default-deny-netpol` | [`terraform/kubernetes/cluster-policies/kyverno/shared/protect-default-deny.yaml`](./kyverno/shared/protect-default-deny.yaml) |
| `require-app-labels-application-namespaces` | [`terraform/kubernetes/cluster-policies/kyverno/shared/require-app-labels-application-namespaces.yaml`](./kyverno/shared/require-app-labels-application-namespaces.yaml) |
| `restrict-image-registries` | [`terraform/kubernetes/cluster-policies/kyverno/shared/restrict-image-registries.yaml`](./kyverno/shared/restrict-image-registries.yaml) |

### Overlay: uat

#### ClusterPolicy

| Name | Source |
| --- | --- |
| `uat-restrict-capabilities` | [`terraform/kubernetes/cluster-policies/kyverno/uat/uat-restrict-capabilities.yaml`](./kyverno/uat/uat-restrict-capabilities.yaml) |

