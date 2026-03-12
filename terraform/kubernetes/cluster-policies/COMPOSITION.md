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
| `CiliumClusterwideNetworkPolicy` | `allow-dev-uat-apps-egress-via-cidrgroup` | [`terraform/kubernetes/cluster-policies/cilium/shared/allow-dev-uat-apps-egress-via-cidrgroup.yaml`](./cilium/shared/allow-dev-uat-apps-egress-via-cidrgroup.yaml) |
| `CiliumClusterwideNetworkPolicy` | `allow-dev-uat-apps-egress-via-fqdn` | [`terraform/kubernetes/cluster-policies/cilium/shared/allow-dev-uat-apps-egress-via-fqdn.yaml`](./cilium/shared/allow-dev-uat-apps-egress-via-fqdn.yaml) |
| `CiliumClusterwideNetworkPolicy` | `allow-sentiment-llama-cpp-world-egress` | [`terraform/kubernetes/cluster-policies/cilium/shared/sentiment-llama-cpp-world-egress.yaml`](./cilium/shared/sentiment-llama-cpp-world-egress.yaml) |
| `CiliumClusterwideNetworkPolicy` | `allow-sentiment-llm-dns-egress` | [`terraform/kubernetes/cluster-policies/cilium/shared/sentiment-api-dns-egress.yaml`](./cilium/shared/sentiment-api-dns-egress.yaml) |
| `CiliumClusterwideNetworkPolicy` | `apim-baseline` | [`terraform/kubernetes/cluster-policies/cilium/shared/apim-baseline.yaml`](./cilium/shared/apim-baseline.yaml) |
| `CiliumClusterwideNetworkPolicy` | `argocd-hardened` | [`terraform/kubernetes/cluster-policies/cilium/shared/argocd-hardened.yaml`](./cilium/shared/argocd-hardened.yaml) |
| `CiliumClusterwideNetworkPolicy` | `argocd-repo-server-helm-egress` | [`terraform/kubernetes/cluster-policies/cilium/shared/argocd-hardened.yaml`](./cilium/shared/argocd-hardened.yaml) |
| `CiliumClusterwideNetworkPolicy` | `deny-cloud-metadata-dev-uat-apps` | [`terraform/kubernetes/cluster-policies/cilium/shared/deny-cloud-metadata-dev-uat-apps.yaml`](./cilium/shared/deny-cloud-metadata-dev-uat-apps.yaml) |
| `CiliumClusterwideNetworkPolicy` | `deny-cloud-metadata-egress` | [`terraform/kubernetes/cluster-policies/cilium/shared/deny-cloud-metadata-egress.yaml`](./cilium/shared/deny-cloud-metadata-egress.yaml) |
| `CiliumClusterwideNetworkPolicy` | `deny-sentiment-to-subnetcalc-dev` | [`terraform/kubernetes/cluster-policies/cilium/dev/dev-project-isolation.yaml`](./cilium/dev/dev-project-isolation.yaml) |
| `CiliumClusterwideNetworkPolicy` | `deny-sentiment-to-subnetcalc-uat` | [`terraform/kubernetes/cluster-policies/cilium/uat/uat-project-isolation.yaml`](./cilium/uat/uat-project-isolation.yaml) |
| `CiliumClusterwideNetworkPolicy` | `deny-subnetcalc-to-sentiment-dev` | [`terraform/kubernetes/cluster-policies/cilium/dev/dev-project-isolation.yaml`](./cilium/dev/dev-project-isolation.yaml) |
| `CiliumClusterwideNetworkPolicy` | `deny-subnetcalc-to-sentiment-uat` | [`terraform/kubernetes/cluster-policies/cilium/uat/uat-project-isolation.yaml`](./cilium/uat/uat-project-isolation.yaml) |
| `CiliumClusterwideNetworkPolicy` | `dev-baseline` | [`terraform/kubernetes/cluster-policies/cilium/dev/dev-baseline.yaml`](./cilium/dev/dev-baseline.yaml) |
| `CiliumClusterwideNetworkPolicy` | `dev-sentiment-api-egress` | [`terraform/kubernetes/cluster-policies/cilium/dev/dev-mtls-sentiment.yaml`](./cilium/dev/dev-mtls-sentiment.yaml) |
| `CiliumClusterwideNetworkPolicy` | `dev-sentiment-backend-ingress` | [`terraform/kubernetes/cluster-policies/cilium/dev/dev-mtls-sentiment.yaml`](./cilium/dev/dev-mtls-sentiment.yaml) |
| `CiliumClusterwideNetworkPolicy` | `dev-sentiment-frontend-ingress` | [`terraform/kubernetes/cluster-policies/cilium/dev/dev-mtls-sentiment.yaml`](./cilium/dev/dev-mtls-sentiment.yaml) |
| `CiliumClusterwideNetworkPolicy` | `dev-sentiment-litellm-ingress-egress` | [`terraform/kubernetes/cluster-policies/cilium/dev/dev-mtls-sentiment.yaml`](./cilium/dev/dev-mtls-sentiment.yaml) |
| `CiliumClusterwideNetworkPolicy` | `dev-sentiment-llama-ingress` | [`terraform/kubernetes/cluster-policies/cilium/dev/dev-mtls-sentiment.yaml`](./cilium/dev/dev-mtls-sentiment.yaml) |
| `CiliumClusterwideNetworkPolicy` | `dev-sentiment-router-ingress` | [`terraform/kubernetes/cluster-policies/cilium/dev/dev-mtls-sentiment.yaml`](./cilium/dev/dev-mtls-sentiment.yaml) |
| `CiliumClusterwideNetworkPolicy` | `dev-subnetcalc-api-cloudflare-egress` | [`terraform/kubernetes/cluster-policies/cilium/dev/dev-subnetcalc-api-cloudflare-egress.yaml`](./cilium/dev/dev-subnetcalc-api-cloudflare-egress.yaml) |
| `CiliumClusterwideNetworkPolicy` | `dev-subnetcalc-frontend-ingress` | [`terraform/kubernetes/cluster-policies/cilium/dev/dev-mtls-subnetcalc.yaml`](./cilium/dev/dev-mtls-subnetcalc.yaml) |
| `CiliumClusterwideNetworkPolicy` | `dev-subnetcalc-router-ingress` | [`terraform/kubernetes/cluster-policies/cilium/dev/dev-mtls-subnetcalc.yaml`](./cilium/dev/dev-mtls-subnetcalc.yaml) |
| `CiliumClusterwideNetworkPolicy` | `gitea-hardened` | [`terraform/kubernetes/cluster-policies/cilium/shared/gitea-hardened.yaml`](./cilium/shared/gitea-hardened.yaml) |
| `CiliumClusterwideNetworkPolicy` | `gitea-runner-hardened` | [`terraform/kubernetes/cluster-policies/cilium/shared/gitea-runner-hardened.yaml`](./cilium/shared/gitea-runner-hardened.yaml) |
| `CiliumClusterwideNetworkPolicy` | `nginx-gateway-control-plane` | [`terraform/kubernetes/cluster-policies/cilium/shared/azure-auth-nginx-gateway-ingress.yaml`](./cilium/shared/azure-auth-nginx-gateway-ingress.yaml) |
| `CiliumClusterwideNetworkPolicy` | `observability-hardened` | [`terraform/kubernetes/cluster-policies/cilium/shared/observability-hardened.yaml`](./cilium/shared/observability-hardened.yaml) |
| `CiliumClusterwideNetworkPolicy` | `platform-baseline-headlamp` | [`terraform/kubernetes/cluster-policies/cilium/shared/platform-baseline.yaml`](./cilium/shared/platform-baseline.yaml) |
| `CiliumClusterwideNetworkPolicy` | `platform-gateway-hardened` | [`terraform/kubernetes/cluster-policies/cilium/shared/platform-gateway-hardened.yaml`](./cilium/shared/platform-gateway-hardened.yaml) |
| `CiliumClusterwideNetworkPolicy` | `sentiment-router-l7-dev` | [`terraform/kubernetes/cluster-policies/cilium/dev/sentiment-router-l7-dev.yaml`](./cilium/dev/sentiment-router-l7-dev.yaml) |
| `CiliumClusterwideNetworkPolicy` | `sentiment-router-l7-uat` | [`terraform/kubernetes/cluster-policies/cilium/uat/sentiment-router-l7-uat.yaml`](./cilium/uat/sentiment-router-l7-uat.yaml) |
| `CiliumClusterwideNetworkPolicy` | `sso-hardened` | [`terraform/kubernetes/cluster-policies/cilium/shared/sso-hardened.yaml`](./cilium/shared/sso-hardened.yaml) |
| `CiliumClusterwideNetworkPolicy` | `subnetcalc-api-l7-dev` | [`terraform/kubernetes/cluster-policies/cilium/dev/subnetcalc-l7-dev.yaml`](./cilium/dev/subnetcalc-l7-dev.yaml) |
| `CiliumClusterwideNetworkPolicy` | `subnetcalc-api-l7-uat` | [`terraform/kubernetes/cluster-policies/cilium/uat/subnetcalc-l7-uat.yaml`](./cilium/uat/subnetcalc-l7-uat.yaml) |
| `CiliumClusterwideNetworkPolicy` | `subnetcalc-router-l7-dev` | [`terraform/kubernetes/cluster-policies/cilium/dev/subnetcalc-l7-dev.yaml`](./cilium/dev/subnetcalc-l7-dev.yaml) |
| `CiliumClusterwideNetworkPolicy` | `subnetcalc-router-l7-uat` | [`terraform/kubernetes/cluster-policies/cilium/uat/subnetcalc-l7-uat.yaml`](./cilium/uat/subnetcalc-l7-uat.yaml) |
| `CiliumClusterwideNetworkPolicy` | `uat-baseline` | [`terraform/kubernetes/cluster-policies/cilium/uat/uat-baseline.yaml`](./cilium/uat/uat-baseline.yaml) |
| `CiliumClusterwideNetworkPolicy` | `uat-sentiment-api-egress` | [`terraform/kubernetes/cluster-policies/cilium/uat/uat-mtls-sentiment.yaml`](./cilium/uat/uat-mtls-sentiment.yaml) |
| `CiliumClusterwideNetworkPolicy` | `uat-sentiment-backend-ingress` | [`terraform/kubernetes/cluster-policies/cilium/uat/uat-mtls-sentiment.yaml`](./cilium/uat/uat-mtls-sentiment.yaml) |
| `CiliumClusterwideNetworkPolicy` | `uat-sentiment-frontend-ingress` | [`terraform/kubernetes/cluster-policies/cilium/uat/uat-mtls-sentiment.yaml`](./cilium/uat/uat-mtls-sentiment.yaml) |
| `CiliumClusterwideNetworkPolicy` | `uat-sentiment-litellm-ingress-egress` | [`terraform/kubernetes/cluster-policies/cilium/uat/uat-mtls-sentiment.yaml`](./cilium/uat/uat-mtls-sentiment.yaml) |
| `CiliumClusterwideNetworkPolicy` | `uat-sentiment-llama-ingress` | [`terraform/kubernetes/cluster-policies/cilium/uat/uat-mtls-sentiment.yaml`](./cilium/uat/uat-mtls-sentiment.yaml) |
| `CiliumClusterwideNetworkPolicy` | `uat-sentiment-router-ingress` | [`terraform/kubernetes/cluster-policies/cilium/uat/uat-mtls-sentiment.yaml`](./cilium/uat/uat-mtls-sentiment.yaml) |
| `CiliumClusterwideNetworkPolicy` | `uat-subnetcalc-frontend-ingress` | [`terraform/kubernetes/cluster-policies/cilium/uat/uat-mtls-subnetcalc.yaml`](./cilium/uat/uat-mtls-subnetcalc.yaml) |
| `CiliumClusterwideNetworkPolicy` | `uat-subnetcalc-router-ingress` | [`terraform/kubernetes/cluster-policies/cilium/uat/uat-mtls-subnetcalc.yaml`](./cilium/uat/uat-mtls-subnetcalc.yaml) |

### Overlay: shared

| Source | Rendered Resources |
| --- | --- |
| [`terraform/kubernetes/cluster-policies/cilium/shared/allow-dev-uat-apps-egress-via-cidrgroup.yaml`](./cilium/shared/allow-dev-uat-apps-egress-via-cidrgroup.yaml) | `CiliumClusterwideNetworkPolicy/allow-dev-uat-apps-egress-via-cidrgroup` |
| [`terraform/kubernetes/cluster-policies/cilium/shared/allow-dev-uat-apps-egress-via-fqdn.yaml`](./cilium/shared/allow-dev-uat-apps-egress-via-fqdn.yaml) | `CiliumClusterwideNetworkPolicy/allow-dev-uat-apps-egress-via-fqdn` |
| [`terraform/kubernetes/cluster-policies/cilium/shared/apim-baseline.yaml`](./cilium/shared/apim-baseline.yaml) | `CiliumClusterwideNetworkPolicy/apim-baseline` |
| [`terraform/kubernetes/cluster-policies/cilium/shared/approved-egress-cidrs.yaml`](./cilium/shared/approved-egress-cidrs.yaml) | `CiliumCIDRGroup/approved-egress-cidrs` |
| [`terraform/kubernetes/cluster-policies/cilium/shared/argocd-hardened.yaml`](./cilium/shared/argocd-hardened.yaml) | `CiliumClusterwideNetworkPolicy/argocd-hardened`<br />`CiliumClusterwideNetworkPolicy/argocd-repo-server-helm-egress` |
| [`terraform/kubernetes/cluster-policies/cilium/shared/azure-auth-nginx-gateway-ingress.yaml`](./cilium/shared/azure-auth-nginx-gateway-ingress.yaml) | `CiliumClusterwideNetworkPolicy/nginx-gateway-control-plane` |
| [`terraform/kubernetes/cluster-policies/cilium/shared/deny-cloud-metadata-dev-uat-apps.yaml`](./cilium/shared/deny-cloud-metadata-dev-uat-apps.yaml) | `CiliumClusterwideNetworkPolicy/deny-cloud-metadata-dev-uat-apps` |
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
| [`terraform/kubernetes/cluster-policies/cilium/dev/dev-baseline.yaml`](./cilium/dev/dev-baseline.yaml) | `CiliumClusterwideNetworkPolicy/dev-baseline` |
| [`terraform/kubernetes/cluster-policies/cilium/dev/dev-mtls-sentiment.yaml`](./cilium/dev/dev-mtls-sentiment.yaml) | `CiliumClusterwideNetworkPolicy/dev-sentiment-router-ingress`<br />`CiliumClusterwideNetworkPolicy/dev-sentiment-backend-ingress`<br />`CiliumClusterwideNetworkPolicy/dev-sentiment-frontend-ingress`<br />`CiliumClusterwideNetworkPolicy/dev-sentiment-api-egress`<br />`CiliumClusterwideNetworkPolicy/dev-sentiment-litellm-ingress-egress`<br />`CiliumClusterwideNetworkPolicy/dev-sentiment-llama-ingress` |
| [`terraform/kubernetes/cluster-policies/cilium/dev/dev-mtls-subnetcalc.yaml`](./cilium/dev/dev-mtls-subnetcalc.yaml) | `CiliumClusterwideNetworkPolicy/dev-subnetcalc-router-ingress`<br />`CiliumClusterwideNetworkPolicy/dev-subnetcalc-frontend-ingress` |
| [`terraform/kubernetes/cluster-policies/cilium/dev/dev-project-isolation.yaml`](./cilium/dev/dev-project-isolation.yaml) | `CiliumClusterwideNetworkPolicy/deny-sentiment-to-subnetcalc-dev`<br />`CiliumClusterwideNetworkPolicy/deny-subnetcalc-to-sentiment-dev` |
| [`terraform/kubernetes/cluster-policies/cilium/dev/dev-subnetcalc-api-cloudflare-egress.yaml`](./cilium/dev/dev-subnetcalc-api-cloudflare-egress.yaml) | `CiliumClusterwideNetworkPolicy/dev-subnetcalc-api-cloudflare-egress` |
| [`terraform/kubernetes/cluster-policies/cilium/dev/sentiment-router-l7-dev.yaml`](./cilium/dev/sentiment-router-l7-dev.yaml) | `CiliumClusterwideNetworkPolicy/sentiment-router-l7-dev` |
| [`terraform/kubernetes/cluster-policies/cilium/dev/subnetcalc-l7-dev.yaml`](./cilium/dev/subnetcalc-l7-dev.yaml) | `CiliumClusterwideNetworkPolicy/subnetcalc-router-l7-dev`<br />`CiliumClusterwideNetworkPolicy/subnetcalc-api-l7-dev` |

### Overlay: uat

| Source | Rendered Resources |
| --- | --- |
| [`terraform/kubernetes/cluster-policies/cilium/uat/sentiment-router-l7-uat.yaml`](./cilium/uat/sentiment-router-l7-uat.yaml) | `CiliumClusterwideNetworkPolicy/sentiment-router-l7-uat` |
| [`terraform/kubernetes/cluster-policies/cilium/uat/subnetcalc-l7-uat.yaml`](./cilium/uat/subnetcalc-l7-uat.yaml) | `CiliumClusterwideNetworkPolicy/subnetcalc-router-l7-uat`<br />`CiliumClusterwideNetworkPolicy/subnetcalc-api-l7-uat` |
| [`terraform/kubernetes/cluster-policies/cilium/uat/uat-baseline.yaml`](./cilium/uat/uat-baseline.yaml) | `CiliumClusterwideNetworkPolicy/uat-baseline` |
| [`terraform/kubernetes/cluster-policies/cilium/uat/uat-mtls-sentiment.yaml`](./cilium/uat/uat-mtls-sentiment.yaml) | `CiliumClusterwideNetworkPolicy/uat-sentiment-router-ingress`<br />`CiliumClusterwideNetworkPolicy/uat-sentiment-backend-ingress`<br />`CiliumClusterwideNetworkPolicy/uat-sentiment-frontend-ingress`<br />`CiliumClusterwideNetworkPolicy/uat-sentiment-api-egress`<br />`CiliumClusterwideNetworkPolicy/uat-sentiment-litellm-ingress-egress`<br />`CiliumClusterwideNetworkPolicy/uat-sentiment-llama-ingress` |
| [`terraform/kubernetes/cluster-policies/cilium/uat/uat-mtls-subnetcalc.yaml`](./cilium/uat/uat-mtls-subnetcalc.yaml) | `CiliumClusterwideNetworkPolicy/uat-subnetcalc-router-ingress`<br />`CiliumClusterwideNetworkPolicy/uat-subnetcalc-frontend-ingress` |
| [`terraform/kubernetes/cluster-policies/cilium/uat/uat-project-isolation.yaml`](./cilium/uat/uat-project-isolation.yaml) | `CiliumClusterwideNetworkPolicy/deny-sentiment-to-subnetcalc-uat`<br />`CiliumClusterwideNetworkPolicy/deny-subnetcalc-to-sentiment-uat` |

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

