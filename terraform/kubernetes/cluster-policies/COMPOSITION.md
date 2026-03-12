# Policy Composition

Generated with [`terraform/kubernetes/scripts/show-policy-composition.sh`](../scripts/show-policy-composition.sh) using `--target all --format markdown`.

This view answers three related questions:

- what the current checked-in policy composition includes after filter application
- which source files contribute each rendered resource
- which policies in each overlay survive the active slice

Active filters:

- namespace: `all`
- direction: `all`
- label terms: `none`

## Cilium

Rendered from [`terraform/kubernetes/cluster-policies/cilium`](./cilium) after filter application.

### Top-Level Rendered Set

| Kind | Name | Source Files |
| --- | --- | --- |
| `CiliumCIDRGroup` | `approved-egress-cidrs` | [`terraform/kubernetes/cluster-policies/cilium/shared/approved-egress-cidrs.yaml`](./cilium/shared/approved-egress-cidrs.yaml) |
| `CiliumClusterwideNetworkPolicy` | `allow-application-backend-egress-via-cidrgroup` | [`terraform/kubernetes/cluster-policies/cilium/shared/application-backend-egress-via-cidrgroup.yaml`](./cilium/shared/application-backend-egress-via-cidrgroup.yaml) |
| `CiliumClusterwideNetworkPolicy` | `allow-application-backend-egress-via-fqdn` | [`terraform/kubernetes/cluster-policies/cilium/shared/application-backend-egress-via-fqdn.yaml`](./cilium/shared/application-backend-egress-via-fqdn.yaml) |
| `CiliumClusterwideNetworkPolicy` | `allow-sentiment-llama-cpp-world-egress` | [`terraform/kubernetes/cluster-policies/cilium/shared/sentiment-llama-cpp-world-egress.yaml`](./cilium/shared/sentiment-llama-cpp-world-egress.yaml) |
| `CiliumClusterwideNetworkPolicy` | `allow-sentiment-llm-dns-egress` | [`terraform/kubernetes/cluster-policies/cilium/shared/sentiment-api-dns-egress.yaml`](./cilium/shared/sentiment-api-dns-egress.yaml) |
| `CiliumClusterwideNetworkPolicy` | `apim-baseline` | [`terraform/kubernetes/cluster-policies/cilium/shared/apim-baseline.yaml`](./cilium/shared/apim-baseline.yaml) |
| `CiliumClusterwideNetworkPolicy` | `application-baseline` | [`terraform/kubernetes/cluster-policies/cilium/shared/application-baseline.yaml`](./cilium/shared/application-baseline.yaml) |
| `CiliumClusterwideNetworkPolicy` | `argocd-hardened` | [`terraform/kubernetes/cluster-policies/cilium/shared/argocd-hardened.yaml`](./cilium/shared/argocd-hardened.yaml) |
| `CiliumClusterwideNetworkPolicy` | `argocd-repo-server-helm-egress` | [`terraform/kubernetes/cluster-policies/cilium/shared/argocd-hardened.yaml`](./cilium/shared/argocd-hardened.yaml) |
| `CiliumClusterwideNetworkPolicy` | `deny-application-cloud-metadata` | [`terraform/kubernetes/cluster-policies/cilium/shared/application-cloud-metadata-deny.yaml`](./cilium/shared/application-cloud-metadata-deny.yaml) |
| `CiliumClusterwideNetworkPolicy` | `deny-application-sentiment-to-subnetcalc` | [`terraform/kubernetes/cluster-policies/cilium/shared/application-project-boundaries.yaml`](./cilium/shared/application-project-boundaries.yaml) |
| `CiliumClusterwideNetworkPolicy` | `deny-application-subnetcalc-to-sentiment` | [`terraform/kubernetes/cluster-policies/cilium/shared/application-project-boundaries.yaml`](./cilium/shared/application-project-boundaries.yaml) |
| `CiliumClusterwideNetworkPolicy` | `deny-cloud-metadata-egress` | [`terraform/kubernetes/cluster-policies/cilium/shared/deny-cloud-metadata-egress.yaml`](./cilium/shared/deny-cloud-metadata-egress.yaml) |
| `CiliumClusterwideNetworkPolicy` | `gitea-hardened` | [`terraform/kubernetes/cluster-policies/cilium/shared/gitea-hardened.yaml`](./cilium/shared/gitea-hardened.yaml) |
| `CiliumClusterwideNetworkPolicy` | `gitea-runner-hardened` | [`terraform/kubernetes/cluster-policies/cilium/shared/gitea-runner-hardened.yaml`](./cilium/shared/gitea-runner-hardened.yaml) |
| `CiliumClusterwideNetworkPolicy` | `nginx-gateway-control-plane` | [`terraform/kubernetes/cluster-policies/cilium/shared/azure-auth-nginx-gateway-ingress.yaml`](./cilium/shared/azure-auth-nginx-gateway-ingress.yaml) |
| `CiliumClusterwideNetworkPolicy` | `observability-hardened` | [`terraform/kubernetes/cluster-policies/cilium/shared/observability-hardened.yaml`](./cilium/shared/observability-hardened.yaml) |
| `CiliumClusterwideNetworkPolicy` | `platform-baseline-headlamp` | [`terraform/kubernetes/cluster-policies/cilium/shared/platform-baseline.yaml`](./cilium/shared/platform-baseline.yaml) |
| `CiliumClusterwideNetworkPolicy` | `platform-gateway-hardened` | [`terraform/kubernetes/cluster-policies/cilium/shared/platform-gateway-hardened.yaml`](./cilium/shared/platform-gateway-hardened.yaml) |
| `CiliumClusterwideNetworkPolicy` | `sso-hardened` | [`terraform/kubernetes/cluster-policies/cilium/shared/sso-hardened.yaml`](./cilium/shared/sso-hardened.yaml) |
| `CiliumNetworkPolicy` | `sentiment-api-egress` | [`terraform/kubernetes/cluster-policies/cilium/projects/sentiment/sentiment-runtime.yaml`](./cilium/projects/sentiment/sentiment-runtime.yaml) |
| `CiliumNetworkPolicy` | `sentiment-backend-ingress` | [`terraform/kubernetes/cluster-policies/cilium/projects/sentiment/sentiment-runtime.yaml`](./cilium/projects/sentiment/sentiment-runtime.yaml) |
| `CiliumNetworkPolicy` | `sentiment-frontend-ingress` | [`terraform/kubernetes/cluster-policies/cilium/projects/sentiment/sentiment-runtime.yaml`](./cilium/projects/sentiment/sentiment-runtime.yaml) |
| `CiliumNetworkPolicy` | `sentiment-litellm-ingress-egress` | [`terraform/kubernetes/cluster-policies/cilium/projects/sentiment/sentiment-runtime.yaml`](./cilium/projects/sentiment/sentiment-runtime.yaml) |
| `CiliumNetworkPolicy` | `sentiment-llama-ingress` | [`terraform/kubernetes/cluster-policies/cilium/projects/sentiment/sentiment-runtime.yaml`](./cilium/projects/sentiment/sentiment-runtime.yaml) |
| `CiliumNetworkPolicy` | `sentiment-router-http-routes` | [`terraform/kubernetes/cluster-policies/cilium/projects/sentiment/sentiment-http-routes.yaml`](./cilium/projects/sentiment/sentiment-http-routes.yaml) |
| `CiliumNetworkPolicy` | `sentiment-router-ingress` | [`terraform/kubernetes/cluster-policies/cilium/projects/sentiment/sentiment-runtime.yaml`](./cilium/projects/sentiment/sentiment-runtime.yaml) |
| `CiliumNetworkPolicy` | `subnetcalc-api-http-routes` | [`terraform/kubernetes/cluster-policies/cilium/projects/subnetcalc/subnetcalc-http-routes.yaml`](./cilium/projects/subnetcalc/subnetcalc-http-routes.yaml) |
| `CiliumNetworkPolicy` | `subnetcalc-cloudflare-live-fetch` | [`terraform/kubernetes/cluster-policies/cilium/dev/overrides/subnetcalc-cloudflare-live-fetch.yaml`](./cilium/dev/overrides/subnetcalc-cloudflare-live-fetch.yaml) |
| `CiliumNetworkPolicy` | `subnetcalc-frontend-ingress` | [`terraform/kubernetes/cluster-policies/cilium/projects/subnetcalc/subnetcalc-runtime.yaml`](./cilium/projects/subnetcalc/subnetcalc-runtime.yaml) |
| `CiliumNetworkPolicy` | `subnetcalc-router-http-routes` | [`terraform/kubernetes/cluster-policies/cilium/projects/subnetcalc/subnetcalc-http-routes.yaml`](./cilium/projects/subnetcalc/subnetcalc-http-routes.yaml) |
| `CiliumNetworkPolicy` | `subnetcalc-router-ingress` | [`terraform/kubernetes/cluster-policies/cilium/projects/subnetcalc/subnetcalc-runtime.yaml`](./cilium/projects/subnetcalc/subnetcalc-runtime.yaml) |

### Overlay: shared

| Source | Rendered Resources |
| --- | --- |
| [`terraform/kubernetes/cluster-policies/cilium/shared/apim-baseline.yaml`](./cilium/shared/apim-baseline.yaml) | `CiliumClusterwideNetworkPolicy/apim-baseline` |
| [`terraform/kubernetes/cluster-policies/cilium/shared/application-backend-egress-via-cidrgroup.yaml`](./cilium/shared/application-backend-egress-via-cidrgroup.yaml) | `CiliumClusterwideNetworkPolicy/allow-application-backend-egress-via-cidrgroup` |
| [`terraform/kubernetes/cluster-policies/cilium/shared/application-backend-egress-via-fqdn.yaml`](./cilium/shared/application-backend-egress-via-fqdn.yaml) | `CiliumClusterwideNetworkPolicy/allow-application-backend-egress-via-fqdn` |
| [`terraform/kubernetes/cluster-policies/cilium/shared/application-baseline.yaml`](./cilium/shared/application-baseline.yaml) | `CiliumClusterwideNetworkPolicy/application-baseline` |
| [`terraform/kubernetes/cluster-policies/cilium/shared/application-cloud-metadata-deny.yaml`](./cilium/shared/application-cloud-metadata-deny.yaml) | `CiliumClusterwideNetworkPolicy/deny-application-cloud-metadata` |
| [`terraform/kubernetes/cluster-policies/cilium/shared/application-project-boundaries.yaml`](./cilium/shared/application-project-boundaries.yaml) | `CiliumClusterwideNetworkPolicy/deny-application-sentiment-to-subnetcalc`<br />`CiliumClusterwideNetworkPolicy/deny-application-subnetcalc-to-sentiment` |
| [`terraform/kubernetes/cluster-policies/cilium/shared/approved-egress-cidrs.yaml`](./cilium/shared/approved-egress-cidrs.yaml) | `CiliumCIDRGroup/approved-egress-cidrs` |
| [`terraform/kubernetes/cluster-policies/cilium/shared/argocd-hardened.yaml`](./cilium/shared/argocd-hardened.yaml) | `CiliumClusterwideNetworkPolicy/argocd-hardened`<br />`CiliumClusterwideNetworkPolicy/argocd-repo-server-helm-egress` |
| [`terraform/kubernetes/cluster-policies/cilium/shared/azure-auth-nginx-gateway-ingress.yaml`](./cilium/shared/azure-auth-nginx-gateway-ingress.yaml) | `CiliumClusterwideNetworkPolicy/nginx-gateway-control-plane` |
| [`terraform/kubernetes/cluster-policies/cilium/shared/deny-cloud-metadata-egress.yaml`](./cilium/shared/deny-cloud-metadata-egress.yaml) | `CiliumClusterwideNetworkPolicy/deny-cloud-metadata-egress` |
| [`terraform/kubernetes/cluster-policies/cilium/shared/gitea-hardened.yaml`](./cilium/shared/gitea-hardened.yaml) | `CiliumClusterwideNetworkPolicy/gitea-hardened` |
| [`terraform/kubernetes/cluster-policies/cilium/shared/gitea-runner-hardened.yaml`](./cilium/shared/gitea-runner-hardened.yaml) | `CiliumClusterwideNetworkPolicy/gitea-runner-hardened` |
| [`terraform/kubernetes/cluster-policies/cilium/shared/observability-hardened.yaml`](./cilium/shared/observability-hardened.yaml) | `CiliumClusterwideNetworkPolicy/observability-hardened` |
| [`terraform/kubernetes/cluster-policies/cilium/shared/platform-baseline.yaml`](./cilium/shared/platform-baseline.yaml) | `CiliumClusterwideNetworkPolicy/platform-baseline-headlamp` |
| [`terraform/kubernetes/cluster-policies/cilium/shared/platform-gateway-hardened.yaml`](./cilium/shared/platform-gateway-hardened.yaml) | `CiliumClusterwideNetworkPolicy/platform-gateway-hardened` |
| [`terraform/kubernetes/cluster-policies/cilium/shared/sentiment-api-dns-egress.yaml`](./cilium/shared/sentiment-api-dns-egress.yaml) | `CiliumClusterwideNetworkPolicy/allow-sentiment-llm-dns-egress` |
| [`terraform/kubernetes/cluster-policies/cilium/shared/sentiment-llama-cpp-world-egress.yaml`](./cilium/shared/sentiment-llama-cpp-world-egress.yaml) | `CiliumClusterwideNetworkPolicy/allow-sentiment-llama-cpp-world-egress` |
| [`terraform/kubernetes/cluster-policies/cilium/shared/sso-hardened.yaml`](./cilium/shared/sso-hardened.yaml) | `CiliumClusterwideNetworkPolicy/sso-hardened` |

### Overlay: dev

| Source | Rendered Resources |
| --- | --- |
| [`terraform/kubernetes/cluster-policies/cilium/dev/overrides/subnetcalc-cloudflare-live-fetch.yaml`](./cilium/dev/overrides/subnetcalc-cloudflare-live-fetch.yaml) | `CiliumNetworkPolicy/subnetcalc-cloudflare-live-fetch` |
| [`terraform/kubernetes/cluster-policies/cilium/projects/sentiment/sentiment-http-routes.yaml`](./cilium/projects/sentiment/sentiment-http-routes.yaml) | `CiliumNetworkPolicy/sentiment-router-http-routes` |
| [`terraform/kubernetes/cluster-policies/cilium/projects/sentiment/sentiment-runtime.yaml`](./cilium/projects/sentiment/sentiment-runtime.yaml) | `CiliumNetworkPolicy/sentiment-router-ingress`<br />`CiliumNetworkPolicy/sentiment-backend-ingress`<br />`CiliumNetworkPolicy/sentiment-frontend-ingress`<br />`CiliumNetworkPolicy/sentiment-api-egress`<br />`CiliumNetworkPolicy/sentiment-litellm-ingress-egress`<br />`CiliumNetworkPolicy/sentiment-llama-ingress` |
| [`terraform/kubernetes/cluster-policies/cilium/projects/subnetcalc/subnetcalc-http-routes.yaml`](./cilium/projects/subnetcalc/subnetcalc-http-routes.yaml) | `CiliumNetworkPolicy/subnetcalc-router-http-routes`<br />`CiliumNetworkPolicy/subnetcalc-api-http-routes` |
| [`terraform/kubernetes/cluster-policies/cilium/projects/subnetcalc/subnetcalc-runtime.yaml`](./cilium/projects/subnetcalc/subnetcalc-runtime.yaml) | `CiliumNetworkPolicy/subnetcalc-router-ingress`<br />`CiliumNetworkPolicy/subnetcalc-frontend-ingress` |

### Overlay: uat

| Source | Rendered Resources |
| --- | --- |
| [`terraform/kubernetes/cluster-policies/cilium/projects/sentiment/sentiment-http-routes.yaml`](./cilium/projects/sentiment/sentiment-http-routes.yaml) | `CiliumNetworkPolicy/sentiment-router-http-routes` |
| [`terraform/kubernetes/cluster-policies/cilium/projects/sentiment/sentiment-runtime.yaml`](./cilium/projects/sentiment/sentiment-runtime.yaml) | `CiliumNetworkPolicy/sentiment-router-ingress`<br />`CiliumNetworkPolicy/sentiment-backend-ingress`<br />`CiliumNetworkPolicy/sentiment-frontend-ingress`<br />`CiliumNetworkPolicy/sentiment-api-egress`<br />`CiliumNetworkPolicy/sentiment-litellm-ingress-egress`<br />`CiliumNetworkPolicy/sentiment-llama-ingress` |
| [`terraform/kubernetes/cluster-policies/cilium/projects/subnetcalc/subnetcalc-http-routes.yaml`](./cilium/projects/subnetcalc/subnetcalc-http-routes.yaml) | `CiliumNetworkPolicy/subnetcalc-router-http-routes`<br />`CiliumNetworkPolicy/subnetcalc-api-http-routes` |
| [`terraform/kubernetes/cluster-policies/cilium/projects/subnetcalc/subnetcalc-runtime.yaml`](./cilium/projects/subnetcalc/subnetcalc-runtime.yaml) | `CiliumNetworkPolicy/subnetcalc-router-ingress`<br />`CiliumNetworkPolicy/subnetcalc-frontend-ingress` |

### Overlay: sit

| Source | Rendered Resources |
| --- | --- |
| [`terraform/kubernetes/cluster-policies/cilium/projects/sentiment/sentiment-http-routes.yaml`](./cilium/projects/sentiment/sentiment-http-routes.yaml) | `CiliumNetworkPolicy/sentiment-router-http-routes` |
| [`terraform/kubernetes/cluster-policies/cilium/projects/sentiment/sentiment-runtime.yaml`](./cilium/projects/sentiment/sentiment-runtime.yaml) | `CiliumNetworkPolicy/sentiment-router-ingress`<br />`CiliumNetworkPolicy/sentiment-backend-ingress`<br />`CiliumNetworkPolicy/sentiment-frontend-ingress`<br />`CiliumNetworkPolicy/sentiment-api-egress`<br />`CiliumNetworkPolicy/sentiment-litellm-ingress-egress`<br />`CiliumNetworkPolicy/sentiment-llama-ingress` |
| [`terraform/kubernetes/cluster-policies/cilium/projects/subnetcalc/subnetcalc-http-routes.yaml`](./cilium/projects/subnetcalc/subnetcalc-http-routes.yaml) | `CiliumNetworkPolicy/subnetcalc-router-http-routes`<br />`CiliumNetworkPolicy/subnetcalc-api-http-routes` |
| [`terraform/kubernetes/cluster-policies/cilium/projects/subnetcalc/subnetcalc-runtime.yaml`](./cilium/projects/subnetcalc/subnetcalc-runtime.yaml) | `CiliumNetworkPolicy/subnetcalc-router-ingress`<br />`CiliumNetworkPolicy/subnetcalc-frontend-ingress` |

## Kyverno

Rendered from [`terraform/kubernetes/cluster-policies/kyverno`](./kyverno) after filter application.

### Top-Level Rendered Set

| Kind | Name | Source Files |
| --- | --- | --- |
| `ClusterPolicy` | `default-deny-namespaces` | [`terraform/kubernetes/cluster-policies/kyverno/shared/namespace-default-deny.yaml`](./kyverno/shared/namespace-default-deny.yaml) |
| `ClusterPolicy` | `protect-default-deny-netpol` | [`terraform/kubernetes/cluster-policies/kyverno/shared/protect-default-deny.yaml`](./kyverno/shared/protect-default-deny.yaml) |
| `ClusterPolicy` | `require-app-labels-application-namespaces` | [`terraform/kubernetes/cluster-policies/kyverno/shared/require-app-labels-application-namespaces.yaml`](./kyverno/shared/require-app-labels-application-namespaces.yaml) |
| `ClusterPolicy` | `restrict-image-registries` | [`terraform/kubernetes/cluster-policies/kyverno/shared/restrict-image-registries.yaml`](./kyverno/shared/restrict-image-registries.yaml) |
| `ClusterPolicy` | `uat-restrict-capabilities` | [`terraform/kubernetes/cluster-policies/kyverno/uat/uat-restrict-capabilities.yaml`](./kyverno/uat/uat-restrict-capabilities.yaml) |

### Overlay: shared

| Source | Rendered Resources |
| --- | --- |
| [`terraform/kubernetes/cluster-policies/kyverno/shared/namespace-default-deny.yaml`](./kyverno/shared/namespace-default-deny.yaml) | `ClusterPolicy/default-deny-namespaces` |
| [`terraform/kubernetes/cluster-policies/kyverno/shared/protect-default-deny.yaml`](./kyverno/shared/protect-default-deny.yaml) | `ClusterPolicy/protect-default-deny-netpol` |
| [`terraform/kubernetes/cluster-policies/kyverno/shared/require-app-labels-application-namespaces.yaml`](./kyverno/shared/require-app-labels-application-namespaces.yaml) | `ClusterPolicy/require-app-labels-application-namespaces` |
| [`terraform/kubernetes/cluster-policies/kyverno/shared/restrict-image-registries.yaml`](./kyverno/shared/restrict-image-registries.yaml) | `ClusterPolicy/restrict-image-registries` |

### Overlay: uat

| Source | Rendered Resources |
| --- | --- |
| [`terraform/kubernetes/cluster-policies/kyverno/uat/uat-restrict-capabilities.yaml`](./kyverno/uat/uat-restrict-capabilities.yaml) | `ClusterPolicy/uat-restrict-capabilities` |

