variable "cluster_name" {
  description = "Cluster name (used for Kind provisioning and in-cluster identity settings)."
  type        = string
  default     = "kind-local"
}

variable "provision_kind_cluster" {
  description = "When true, provision and manage the Kind cluster in this stack. When false, use an existing Kubernetes cluster from kubeconfig."
  type        = bool
  default     = true
}

variable "worker_count" {
  description = "Number of worker nodes."
  type        = number
  default     = 1
}

variable "node_image" {
  description = "Kind node image."
  type        = string
  default     = "kindest/node:v1.35.1"
}

variable "kind_api_server_port" {
  description = "Host port for the kind API server."
  type        = number
  default     = 6443
}

variable "kind_config_path" {
  description = "Path to write generated kind config (gitignored)."
  type        = string
  default     = "./kind-config.yaml"
}

variable "kind_stack_dir" {
  description = "Absolute path to the repo-local terraform/kubernetes directory. Terragrunt sets this so generated files stay anchored to the real checkout instead of the cache copy."
  type        = string
  default     = ""
}

variable "runtime_artifact_scope" {
  description = "Optional target-scoped directory name under <kind_stack_dir>/.run for generated helper artifacts."
  type        = string
  default     = ""

  validation {
    condition     = trimspace(var.runtime_artifact_scope) == "" || length(regexall("^[A-Za-z0-9][A-Za-z0-9._-]*$", trimspace(var.runtime_artifact_scope))) > 0
    error_message = "runtime_artifact_scope must be empty or a simple directory name containing only letters, numbers, dot, underscore, and hyphen."
  }
}

variable "kubeconfig_path" {
  description = "Path to kubeconfig file."
  type        = string
  default     = "~/.kube/config"
}

variable "kubeconfig_context" {
  description = "kubectl context to use (empty means default)."
  type        = string
  default     = ""
}

variable "platform_devcontainer" {
  description = "Whether Terraform is running inside the host-socket devcontainer, where kind loopback endpoints must be rewritten to the host alias."
  type        = bool
  default     = false
}

variable "devcontainer_host_alias" {
  description = "Host alias used from inside the devcontainer to reach host-bound kind services."
  type        = string
  default     = "host.docker.internal"
}

variable "devcontainer_tls_server_name" {
  description = "TLS server name to retain when rewriting kind kubeconfig endpoints for the devcontainer."
  type        = string
  default     = "localhost"
}

# Absolute tfvars paths passed from the kind Makefile so cache-copied Terragrunt
# runs can still find the stage, target, and operator override files.
variable "kind_stage_900_tfvars_file" {
  description = "Absolute path to kubernetes/kind/stages/900-sso.tfvars."
  type        = string
  default     = ""
}

variable "kind_target_tfvars_file" {
  description = "Absolute path to kubernetes/kind/targets/kind.tfvars."
  type        = string
  default     = ""
}

variable "kind_operator_overrides_file" {
  description = "Absolute path to the rendered kind operator overrides tfvars file."
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Feature toggles (stage-driven)
# -----------------------------------------------------------------------------

variable "cni_provider" {
  description = "CNI provider for the kind cluster (none or cilium)."
  type        = string
  default     = "cilium"

  validation {
    condition     = contains(["none", "cilium"], lower(var.cni_provider))
    error_message = "cni_provider must be one of: none, cilium."
  }
}

variable "kind_disable_default_cni" {
  description = <<-EOT
    Override disable_default_cni in the kind cluster config independently of
    cni_provider. Set to true in bootstrap stages (e.g. 100-kind) so the cluster
    is created with the same networking config as full stages that use Cilium,
    avoiding a destroy/recreate when upgrading from the bootstrap stage.
    Defaults to null (derive from cni_provider).
  EOT
  type        = bool
  default     = null
}

variable "enable_hubble" {
  description = "Enable Hubble UI (requires cni_provider = cilium)."
  type        = bool
  default     = true
}

variable "enable_argocd" {
  description = "Install Argo CD."
  type        = bool
  default     = true
}

variable "enable_gitea" {
  description = "Deploy Gitea via Argo CD (Helm chart)."
  type        = bool
  default     = false
}

variable "enable_prometheus" {
  description = "Deploy Prometheus via Argo CD (Helm chart)."
  type        = bool
  default     = false
}

variable "enable_grafana" {
  description = "Deploy Grafana via Argo CD (Helm chart)."
  type        = bool
  default     = false
}

variable "enable_loki" {
  description = "Deploy Grafana Loki for log aggregation via Argo CD (Helm chart)."
  type        = bool
  default     = false
}

variable "enable_victoria_logs" {
  description = "Deploy VictoriaLogs for log aggregation via Argo CD (Helm chart)."
  type        = bool
  default     = false
}

variable "enable_tempo" {
  description = "Deploy Grafana Tempo for distributed tracing via Argo CD (Helm chart)."
  type        = bool
  default     = false
}

variable "enable_signoz" {
  description = "Deploy SigNoz via Argo CD (Helm chart)."
  type        = bool
  default     = false
}

variable "enable_otel_gateway" {
  description = "Deploy a stable OTLP gateway collector (otel-collector.observability.svc.cluster.local) that can fan out to Prometheus/Grafana and/or SigNoz."
  type        = bool
  default     = false
}

variable "enable_headlamp" {
  description = "Deploy Headlamp Kubernetes dashboard via Argo CD (Helm chart)."
  type        = bool
  default     = false
}

variable "enable_observability_agent" {
  description = "Deploy an OpenTelemetry Collector agent (DaemonSet) to scrape platform metrics and ship logs/metrics/traces to SigNoz."
  type        = bool
  default     = false
}

variable "enable_cilium_wireguard" {
  description = "Enable Cilium WireGuard transparent encryption for pod-to-pod traffic across nodes (mTLS at the network layer)."
  type        = bool
  default     = false
}

variable "enable_cilium_node_encryption" {
  description = "Enable WireGuard node-to-node encryption in addition to pod-to-pod (requires enable_cilium_wireguard)."
  type        = bool
  default     = false
}

variable "cilium_native_routing_cidr" {
  description = "Pod CIDR used by Cilium native routing and strict WireGuard mode."
  type        = string
  default     = "10.244.0.0/16"
}

variable "enable_policies" {
  description = "Enable Kyverno + cluster policies (Cilium + Kyverno) sourced from the in-cluster Gitea repo."
  type        = bool
  default     = false
}

variable "enable_cilium_policies" {
  description = "Enable the GitOps-managed Cilium policy Application sourced from the in-cluster Gitea repo. This is a sub-toggle of enable_policies."
  type        = bool
  default     = true
}

variable "enable_cilium_policy_audit_mode" {
  description = "Enable Cilium Policy Audit Mode at the daemon level so loaded Cilium policies emit AUDITED verdicts instead of enforcing drops."
  type        = bool
  default     = false
}

variable "enable_gateway_tls" {
  description = "Enable HTTPS host routing via NGINX Gateway Fabric + cert-manager (sourced from the in-cluster Gitea repo)."
  type        = bool
  default     = false
}

variable "enable_cert_manager" {
  description = "Enable cert-manager core installation via Argo CD independently of gateway TLS."
  type        = bool
  default     = false
}

variable "enable_sso" {
  description = "Enable SSO for the platform UIs by deploying the selected OIDC IdP and protecting UI routes via oauth2-proxy."
  type        = bool
  default     = false
}

variable "sso_provider" {
  description = "OIDC provider for Kubernetes SSO. Kubernetes stage 900 defaults to Keycloak; Dex is retained for lightweight/local compatibility paths."
  type        = string
  default     = "keycloak"

  validation {
    condition     = contains(["dex", "keycloak"], lower(trimspace(var.sso_provider)))
    error_message = "sso_provider must be one of: dex, keycloak."
  }
}

variable "enable_app_of_apps" {
  description = "Enable an Argo CD app-of-apps root Application (managed by Terraform) which syncs a directory of manifests from the GitOps/policies repo."
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Public hostnames and exposure guardrails
# -----------------------------------------------------------------------------

variable "platform_base_domain" {
  description = "Base DNS suffix used for gateway-facing platform URLs (for example 127.0.0.1.sslip.io or a real public domain)."
  type        = string
  default     = "127.0.0.1.sslip.io"

  validation {
    condition     = trimspace(var.platform_base_domain) != ""
    error_message = "platform_base_domain must not be empty."
  }
}

variable "platform_admin_base_domain" {
  description = "Optional alternate DNS suffix for admin/control-plane UI hosts. Leave empty to keep admin hosts under *.admin.<platform_base_domain>."
  type        = string
  default     = ""
}

variable "gateway_https_listen_address" {
  description = "Listen address used for the kind HTTPS gateway extraPortMapping. Keep 127.0.0.1 for local-only stacks; use a public bind or reverse proxy for remote access."
  type        = string
  default     = "127.0.0.1"

  validation {
    condition     = trimspace(var.gateway_https_listen_address) != ""
    error_message = "gateway_https_listen_address must not be empty."
  }
}

variable "expose_admin_nodeports" {
  description = "Expose direct admin NodePort surfaces (Argo CD, Hubble, Gitea, Grafana, SigNoz) in addition to the HTTPS gateway path."
  type        = bool
  default     = true
}

variable "admin_route_allowlist_cidrs" {
  description = "Optional list of source CIDRs allowed to reach admin/control-plane HTTPS routes at the gateway. Leave empty to allow the routes from any source IP."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.admin_route_allowlist_cidrs : trimspace(cidr) != ""])
    error_message = "admin_route_allowlist_cidrs entries must not be empty."
  }
}

variable "gateway_trusted_proxy_cidrs" {
  description = "Optional list of trusted proxy or WAF CIDRs whose X-Forwarded-For headers the platform gateway should trust when rewriting the client IP."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for cidr in var.gateway_trusted_proxy_cidrs : trimspace(cidr) != ""])
    error_message = "gateway_trusted_proxy_cidrs entries must not be empty."
  }
}

variable "public_demo_mode" {
  description = "Operator acknowledgement that this stack is being adapted for a non-local/publicly reachable demo environment and should enforce extra guardrails."
  type        = bool
  default     = false
}

variable "public_demo_acknowledged" {
  description = "Explicit acknowledgement of the shared-responsibility and hardening checklist for a public demo deployment."
  type        = bool
  default     = false
}

variable "enable_demo_cluster_admin_binding" {
  description = "Bind the platform admin OIDC group to cluster-admin for learning-cluster convenience."
  type        = bool
  default     = true
}

variable "headlamp_cluster_role_binding_create" {
  description = "Let the Headlamp chart create its cluster-wide role binding."
  type        = bool
  default     = true
}

variable "headlamp_oidc_skip_tls_verify" {
  description = "Pass -oidc-skip-tls-verify to Headlamp when talking to the local OIDC issuer."
  type        = bool
  default     = true
}

variable "public_demo_allow_demo_cluster_admin" {
  description = "Explicitly allow the platform admin OIDC group to remain cluster-admin when public_demo_mode=true."
  type        = bool
  default     = false
}

variable "public_demo_allow_headlamp_cluster_admin" {
  description = "Explicitly allow Headlamp to retain a cluster-admin role binding when public_demo_mode=true."
  type        = bool
  default     = false
}

variable "public_demo_allow_actions_runner_host_mounts" {
  description = "Explicitly allow the Actions runner to retain Docker socket or host apps mounts when public_demo_mode=true."
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Versions
# -----------------------------------------------------------------------------

variable "cilium_version" {
  description = "Cilium chart version."
  type        = string
  default     = "1.19.3"
}

variable "argocd_chart_version" {
  description = "Argo CD chart version."
  type        = string
  default     = "9.5.4"
}

variable "argocd_image_repository" {
  description = "Argo CD container image repository used by the argo-cd Helm chart."
  type        = string
  default     = "dhi.io/argocd"
}

variable "argocd_image_tag" {
  description = "Argo CD container image tag used by the argo-cd Helm chart."
  type        = string
  default     = "3.3.8-debian13"
}

variable "provision_argocd" {
  description = "When true, Terraform provisions and manages the ArgoCD Helm release and namespace. Set to false when ArgoCD is bootstrapped externally (e.g. via arkade) so Terraform manages only ArgoCD Applications without conflicting with the existing installation."
  type        = bool
  default     = true
}

variable "argocd_applicationset_enabled" {
  description = "Enable the ArgoCD ApplicationSet controller. Set to false on resource-constrained platforms during initial install; re-enable at the next apply stage."
  type        = bool
  default     = true
}

variable "argocd_notifications_enabled" {
  description = "Enable the ArgoCD Notifications controller. Set to false on resource-constrained platforms during initial install; re-enable at the next apply stage."
  type        = bool
  default     = true
}

variable "gitea_chart_version" {
  description = "Gitea chart version."
  type        = string
  default     = "12.5.3"
}

variable "prometheus_chart_version" {
  description = "Prometheus chart version (prometheus-community/prometheus)."
  type        = string
  default     = "29.2.1"
}

variable "prometheus_image_tag" {
  description = "Prometheus hardened container image tag."
  type        = string
  default     = "3.11.2-debian13"
}

variable "grafana_chart_version" {
  description = "Grafana chart version (grafana/grafana)."
  type        = string
  default     = "10.5.15"
}

variable "grafana_image_registry" {
  description = "Grafana container image registry."
  type        = string
  default     = "docker.io"
}

variable "grafana_image_repository" {
  description = "Grafana container image repository."
  type        = string
  default     = "grafana/grafana"
}

variable "grafana_image_tag" {
  description = "Grafana container image tag."
  type        = string
  default     = "12.3.1"
}

variable "grafana_sidecar_image_registry" {
  description = "Grafana sidecar container image registry."
  type        = string
  default     = "quay.io"
}

variable "grafana_sidecar_image_repository" {
  description = "Grafana sidecar container image repository."
  type        = string
  default     = "kiwigrid/k8s-sidecar"
}

variable "grafana_sidecar_image_tag" {
  description = "Grafana sidecar container image tag."
  type        = string
  default     = "2.5.0"
}

variable "grafana_victoria_logs_plugin_version" {
  description = "VictoriaLogs Grafana datasource plugin release version used for prebaked local Grafana images."
  type        = string
  default     = "0.26.3"
}

variable "grafana_victoria_logs_plugin_sha256" {
  description = "SHA-256 checksum for the VictoriaLogs Grafana datasource plugin archive used for prebaked local Grafana images."
  type        = string
  default     = "e9a452b866427f0de23e466b1af8228fbb1344267f929fb6b354f830279c748a"
}

variable "grafana_victoria_logs_plugin_url" {
  description = "VictoriaLogs Grafana datasource plugin bundle URL for chart-managed runtime installs. Leave empty when the plugin is already baked into the Grafana image."
  type        = string
  default     = "https://github.com/VictoriaMetrics/victorialogs-datasource/releases/download/v0.26.3/victoriametrics-logs-datasource-v0.26.3.zip;victoriametrics-logs-datasource"
}

variable "grafana_liveness_initial_delay_seconds" {
  description = "Grafana liveness probe initial delay in seconds."
  type        = number
  default     = 120
}

variable "loki_chart_version" {
  description = "Loki chart version (grafana/loki)."
  type        = string
  default     = "6.55.0"
}

variable "loki_image_tag" {
  description = "Loki hardened container image tag."
  type        = string
  default     = "3.6.7-debian13"
}

variable "victoria_logs_chart_version" {
  description = "VictoriaLogs chart version (victoria-metrics/victoria-logs-single)."
  type        = string
  default     = "0.12.2"
}

variable "tempo_chart_version" {
  description = "Tempo chart version (grafana/tempo)."
  type        = string
  default     = "1.24.4"
}

variable "signoz_chart_version" {
  description = "SigNoz chart version."
  type        = string
  default     = "0.120.0"
}

variable "headlamp_chart_version" {
  description = "Headlamp chart version."
  type        = string
  default     = "0.41.0"
}

variable "kyverno_chart_version" {
  description = "Kyverno chart version."
  type        = string
  default     = "3.7.1"
}

variable "policy_reporter_chart_version" {
  description = "Policy Reporter chart version."
  type        = string
  default     = "3.7.3"
}

variable "cert_manager_chart_version" {
  description = "cert-manager chart version (Jetstack)."
  type        = string
  default     = "v1.20.2"
}

variable "hardened_image_registry" {
  description = "Registry host[:port] used for hardened platform images (for example dhi.io or a local cache like host.lima.internal:5002)."
  type        = string
  default     = "dhi.io"
}

variable "dex_chart_version" {
  description = "Dex chart version (charts.dexidp.io)."
  type        = string
  default     = "0.24.0"
}

variable "keycloak_image" {
  description = "Keycloak image used for the Kubernetes stage-900 IdP."
  type        = string
  default     = "quay.io/keycloak/keycloak:26.6.1"
}

variable "keycloak_postgres_image" {
  description = "Postgres image used by the local Keycloak persistence slice."
  type        = string
  default     = "docker.io/postgres:17.6"
}

variable "keycloak_realm" {
  description = "Keycloak realm used for the local platform identity journey."
  type        = string
  default     = "platform"
}

variable "oauth2_proxy_chart_version" {
  description = "oauth2-proxy chart version (oauth2-proxy.github.io/manifests)."
  type        = string
  default     = "10.4.3"
}

variable "oauth2_proxy_session_store_image" {
  description = "Redis-compatible image used for oauth2-proxy server-side session storage."
  type        = string
  default     = "ecr-public.aws.com/docker/library/redis:8.2.3-alpine"
}

variable "opentelemetry_collector_chart_version" {
  description = "OpenTelemetry Collector chart version (open-telemetry/opentelemetry-collector)."
  type        = string
  default     = "0.152.0"
}

# -----------------------------------------------------------------------------
# Ports (NodePorts must be in 30000-32767)
# -----------------------------------------------------------------------------

variable "argocd_server_node_port" {
  description = "Argo CD server NodePort."
  type        = number
  default     = 30080
}

variable "hubble_ui_node_port" {
  description = "Hubble UI NodePort."
  type        = number
  default     = 31235
}

variable "gitea_http_node_port" {
  description = "Gitea HTTP NodePort."
  type        = number
  default     = 30090
}

variable "gitea_ssh_node_port" {
  description = "Gitea SSH NodePort."
  type        = number
  default     = 30022
}

variable "gitea_local_access_mode" {
  description = "How host-side automation reaches Gitea locally: direct localhost NodePorts or temporary kubectl port-forwards."
  type        = string
  default     = "nodeport"

  validation {
    condition     = contains(["nodeport", "port-forward"], lower(var.gitea_local_access_mode))
    error_message = "gitea_local_access_mode must be one of: nodeport, port-forward."
  }
}

variable "signoz_ui_node_port" {
  description = "SigNoz UI NodePort."
  type        = number
  default     = 30301
}

variable "signoz_ui_host_port" {
  description = "Host port mapped to SigNoz UI NodePort (via kind extraPortMappings)."
  type        = number
  default     = 3301
}

variable "grafana_ui_node_port" {
  description = "Grafana UI NodePort."
  type        = number
  default     = 30302
}

variable "grafana_ui_host_port" {
  description = "Host port mapped to Grafana UI NodePort (via kind extraPortMappings)."
  type        = number
  default     = 3302
}

variable "gateway_https_node_port" {
  description = "NodePort used for the HTTPS Gateway listener (must match apps/platform-gateway nginxproxy/service manifests)."
  type        = number
  default     = 30070
}

variable "gateway_https_host_port" {
  description = "Host port mapped to gateway_https_node_port via kind extraPortMappings."
  type        = number
  default     = 443
}

# -----------------------------------------------------------------------------
# Gateway routing
# -----------------------------------------------------------------------------

variable "platform_gateway_routes_path" {
  description = "Path in the in-cluster policies repo used by the platform-gateway-routes Argo CD application. Stage 900 switches this to the SSO-protected routes."
  type        = string
  default     = "apps/platform-gateway-routes"
}

# -----------------------------------------------------------------------------
# Argo CD
# -----------------------------------------------------------------------------

variable "argocd_namespace" {
  description = "Namespace for Argo CD."
  type        = string
  default     = "argocd"
}

# -----------------------------------------------------------------------------
# Gitea
# -----------------------------------------------------------------------------

variable "gitea_admin_username" {
  description = "Gitea admin username."
  type        = string
  default     = "gitea-admin"
}

variable "gitea_ssh_username" {
  description = "SSH username for Git operations against Gitea (typically 'git')."
  type        = string
  default     = "git"
}

variable "gitea_admin_pwd" {
  description = "Shared local admin password for Gitea/Grafana bootstrap. Set via TF_VAR_gitea_admin_pwd or the repo .env."
  type        = string
  sensitive   = true
  default     = null
}

variable "gitea_member_user_pwd" {
  description = "Shared demo password for auto-created Gitea members and SSO bootstrap users. Set via TF_VAR_gitea_member_user_pwd or the repo .env."
  type        = string
  sensitive   = true
  default     = null
}

variable "gitea_repo_owner" {
  description = "Owner (user or org) for repos seeded into Gitea. Defaults to gitea_admin_username when empty."
  type        = string
  default     = ""
}

variable "gitea_repo_owner_is_org" {
  description = "Whether gitea_repo_owner is an organization."
  type        = bool
  default     = false
}

variable "gitea_org_full_name" {
  description = "Full display name for the Gitea organization (when gitea_repo_owner_is_org)."
  type        = string
  default     = ""
}

variable "gitea_org_email" {
  description = "Contact email for the Gitea organization (when gitea_repo_owner_is_org)."
  type        = string
  default     = ""
}

variable "gitea_org_visibility" {
  description = "Visibility for the Gitea organization: public, limited, or private."
  type        = string
  default     = "private"
}

variable "gitea_org_members" {
  description = "Usernames to add to the Gitea organization Owners team."
  type        = list(string)
  default     = []
}

variable "gitea_org_member_emails" {
  description = "User emails to add to the Gitea organization Owners team (resolved to usernames)."
  type        = list(string)
  default     = []
}

variable "enable_argocd_oidc" {
  description = "Enable Argo CD's built-in OIDC login (keeps the Login button). When false, oauth2-proxy is the only auth gate."
  type        = bool
  default     = false
}

variable "gitea_admin_promote_users" {
  description = "Additional usernames to promote to Gitea admin via API (best-effort). gitea_admin_username is always included."
  type        = list(string)
  default     = []
}

variable "gitea_registry_host" {
  description = "Gitea container registry host:port reachable from Kind nodes (default: NodePort on localhost)."
  type        = string
  default     = "localhost:30090"
}

variable "gitea_registry_scheme" {
  description = "Scheme for the Gitea registry (http for local NodePort; https for external registry)."
  type        = string
  default     = "http"
}

variable "enable_host_local_registry" {
  description = "Write containerd registry overrides for a host-local registry so Kind nodes can pull developer-supplied images directly from the host."
  type        = bool
  default     = false
}

variable "host_local_registry_host" {
  description = "Host-local registry host:port reachable from Kind nodes when enable_host_local_registry=true."
  type        = string
  default     = "host.docker.internal:5002"
}

variable "host_local_registry_scheme" {
  description = "Scheme for the host-local registry (http for local Docker registry shortcuts; https for secured registries)."
  type        = string
  default     = "http"
}

variable "enable_actions_runner" {
  description = "Deploy an in-cluster Gitea Actions runner (requires enable_gitea + enable_argocd)."
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Monorepo app mounts + optional app repo seeding/builds
# -----------------------------------------------------------------------------

variable "enable_apps_dir_mount" {
  description = "Mount the repo's top-level ./apps directory into all Kind nodes (for local dev sync / optional in-cluster builds)."
  type        = bool
  default     = true
}

variable "apps_dir_host_path" {
  description = "Host path to the repo ./apps directory. Empty means auto-detect based on this module's location."
  type        = string
  default     = ""
}

variable "apps_dir_container_path" {
  description = "Path inside Kind node containers where the repo ./apps directory will be mounted."
  type        = string
  default     = "/workspace/apps"
}

variable "apps_dir_read_only" {
  description = "Whether the Kind node mount for apps_dir should be read-only."
  type        = bool
  default     = true
}

variable "enable_app_repo_sentiment" {
  description = "Seed the monorepo app apps/sentiment into in-cluster Gitea as a standalone repo (enables Gitea Actions pipelines)."
  type        = bool
  default     = false
}

variable "sentiment_source_dir" {
  description = "Host path to the monorepo app directory for sentiment. Empty means auto-detect (repo_root/apps/sentiment)."
  type        = string
  default     = ""
}

variable "enable_app_repo_subnetcalc" {
  description = "Seed the monorepo app apps/subnetcalc into in-cluster Gitea as a standalone repo (enables Gitea Actions pipelines)."
  type        = bool
  default     = false
}

check "enable_cilium_wireguard_requires_cilium_provider" {
  assert {
    condition     = !var.enable_cilium_wireguard || lower(var.cni_provider) == "cilium"
    error_message = "enable_cilium_wireguard requires cni_provider=cilium."
  }
}

check "enable_cilium_node_encryption_requires_wireguard" {
  assert {
    condition     = !var.enable_cilium_node_encryption || var.enable_cilium_wireguard
    error_message = "enable_cilium_node_encryption requires enable_cilium_wireguard=true."
  }
}

check "enable_hubble_requires_cilium_provider" {
  assert {
    condition     = !var.enable_hubble || lower(var.cni_provider) == "cilium"
    error_message = "enable_hubble requires cni_provider=cilium."
  }
}

check "enable_gitea_requires_enable_argocd" {
  assert {
    condition     = !var.enable_gitea || var.enable_argocd
    error_message = "enable_gitea requires enable_argocd to be true."
  }
}

check "enable_signoz_requires_enable_argocd" {
  assert {
    condition     = !var.enable_signoz || var.enable_argocd
    error_message = "enable_signoz requires enable_argocd to be true."
  }
}

check "enable_prometheus_requires_enable_argocd" {
  assert {
    condition     = !var.enable_prometheus || var.enable_argocd
    error_message = "enable_prometheus requires enable_argocd to be true."
  }
}

check "enable_otel_gateway_requires_enable_argocd" {
  assert {
    condition     = !var.enable_otel_gateway || var.enable_argocd
    error_message = "enable_otel_gateway requires enable_argocd to be true."
  }
}

check "enable_grafana_requires_prometheus_and_argocd" {
  assert {
    condition     = !var.enable_grafana || (var.enable_prometheus && var.enable_argocd)
    error_message = "enable_grafana requires enable_prometheus=true and enable_argocd=true."
  }
}

check "enable_loki_requires_argocd" {
  assert {
    condition     = !var.enable_loki || var.enable_argocd
    error_message = "enable_loki requires enable_argocd=true."
  }
}

check "enable_victoria_logs_requires_argocd" {
  assert {
    condition     = !var.enable_victoria_logs || var.enable_argocd
    error_message = "enable_victoria_logs requires enable_argocd=true."
  }
}

check "enable_tempo_requires_argocd" {
  assert {
    condition     = !var.enable_tempo || var.enable_argocd
    error_message = "enable_tempo requires enable_argocd=true."
  }
}

check "enable_headlamp_requires_enable_argocd" {
  assert {
    condition     = !var.enable_headlamp || var.enable_argocd
    error_message = "enable_headlamp requires enable_argocd to be true."
  }
}

check "enable_observability_agent_requires_signoz_and_argocd" {
  assert {
    condition     = !var.enable_observability_agent || (var.enable_signoz && var.enable_argocd)
    error_message = "enable_observability_agent requires enable_signoz=true and enable_argocd=true."
  }
}

check "enable_policies_requires_argocd_gitea_cilium" {
  assert {
    condition     = !var.enable_policies || (var.enable_argocd && var.enable_gitea && lower(var.cni_provider) == "cilium")
    error_message = "enable_policies requires enable_argocd=true, enable_gitea=true, and cni_provider=cilium."
  }
}

check "enable_cilium_policy_audit_mode_requires_cilium_provider" {
  assert {
    condition     = !var.enable_cilium_policy_audit_mode || lower(var.cni_provider) == "cilium"
    error_message = "enable_cilium_policy_audit_mode requires cni_provider=cilium."
  }
}

check "enable_gateway_tls_requires_argocd_and_gitea" {
  assert {
    condition     = !var.enable_gateway_tls || (var.enable_argocd && var.enable_gitea)
    error_message = "enable_gateway_tls requires enable_argocd=true and enable_gitea=true."
  }
}

check "enable_sso_requires_gateway_tls_argocd_gitea" {
  assert {
    condition     = !var.enable_sso || (var.enable_gateway_tls && var.enable_argocd && var.enable_gitea)
    error_message = "enable_sso requires enable_gateway_tls=true, enable_argocd=true, and enable_gitea=true."
  }
}

check "enable_actions_runner_requires_gitea_and_argocd" {
  assert {
    condition     = !var.enable_actions_runner || (var.enable_gitea && var.enable_argocd)
    error_message = "enable_actions_runner requires enable_gitea=true and enable_argocd=true."
  }
}

check "public_demo_mode_requires_acknowledgement" {
  assert {
    condition     = !var.public_demo_mode || var.public_demo_acknowledged
    error_message = "public_demo_mode=true requires public_demo_acknowledged=true."
  }
}

check "public_demo_mode_requires_non_loopback_base_domain" {
  assert {
    condition     = !var.public_demo_mode || lower(trimspace(var.platform_base_domain)) != "127.0.0.1.sslip.io"
    error_message = "public_demo_mode=true requires platform_base_domain to move off 127.0.0.1.sslip.io."
  }
}

check "public_demo_mode_disables_direct_admin_nodeports" {
  assert {
    condition     = !var.public_demo_mode || !var.expose_admin_nodeports
    error_message = "public_demo_mode=true requires expose_admin_nodeports=false so admin UIs stay behind the gateway/auth path."
  }
}

check "private_admin_nodeports_require_gitea_port_forward" {
  assert {
    condition     = var.expose_admin_nodeports || lower(var.gitea_local_access_mode) == "port-forward"
    error_message = "expose_admin_nodeports=false requires gitea_local_access_mode=port-forward."
  }
}

check "public_demo_mode_requires_demo_cluster_admin_ack" {
  assert {
    condition     = !var.public_demo_mode || !var.enable_demo_cluster_admin_binding || var.public_demo_allow_demo_cluster_admin
    error_message = "public_demo_mode=true requires public_demo_allow_demo_cluster_admin=true before the platform admin OIDC group can stay cluster-admin."
  }
}

check "public_demo_mode_requires_headlamp_cluster_admin_ack" {
  assert {
    condition     = !var.public_demo_mode || !var.enable_headlamp || !var.headlamp_cluster_role_binding_create || var.public_demo_allow_headlamp_cluster_admin
    error_message = "public_demo_mode=true requires public_demo_allow_headlamp_cluster_admin=true before Headlamp can keep a cluster-wide role binding."
  }
}

check "public_demo_mode_requires_headlamp_tls_verification" {
  assert {
    condition     = !var.public_demo_mode || !var.enable_headlamp || !var.enable_sso || !var.headlamp_oidc_skip_tls_verify
    error_message = "public_demo_mode=true requires headlamp_oidc_skip_tls_verify=false."
  }
}

check "public_demo_mode_requires_runner_host_mount_ack" {
  assert {
    condition = !var.public_demo_mode || !(
      var.enable_actions_runner &&
      (var.enable_docker_socket_mount || var.enable_apps_dir_mount)
    ) || var.public_demo_allow_actions_runner_host_mounts
    error_message = "public_demo_mode=true requires public_demo_allow_actions_runner_host_mounts=true before retaining runner Docker socket or apps-dir mounts."
  }
}

check "prefer_external_platform_images_requires_host_local_registry" {
  assert {
    condition = !var.prefer_external_platform_images || !var.provision_kind_cluster || (
      var.enable_host_local_registry &&
      trimspace(var.host_local_registry_host) != ""
    )
    error_message = "prefer_external_platform_images requires enable_host_local_registry=true and a non-empty host_local_registry_host."
  }
}

check "prefer_external_workload_images_requires_host_local_registry" {
  assert {
    condition = !var.prefer_external_workload_images || !var.provision_kind_cluster || (
      var.enable_host_local_registry &&
      trimspace(var.host_local_registry_host) != ""
    )
    error_message = "prefer_external_workload_images requires enable_host_local_registry=true and a non-empty host_local_registry_host."
  }
}

check "external_platform_image_refs_use_host_local_registry" {
  assert {
    condition = !var.prefer_external_platform_images || !var.provision_kind_cluster || alltrue([
      for key, ref in var.external_platform_image_refs :
      trimspace(ref) == "" || (
        key == "hardened-registry"
        ? trimspace(ref) == trimspace(var.host_local_registry_host)
        : startswith(trimspace(ref), "${trimspace(var.host_local_registry_host)}/")
      )
    ])
    error_message = "external_platform_image_refs must point at the configured host_local_registry_host when prefer_external_platform_images=true."
  }
}

check "external_workload_image_refs_use_host_local_registry" {
  assert {
    condition = !var.prefer_external_workload_images || !var.provision_kind_cluster || alltrue([
      for ref in values(var.external_workload_image_refs) :
      trimspace(ref) == "" || startswith(trimspace(ref), "${trimspace(var.host_local_registry_host)}/")
    ])
    error_message = "external_workload_image_refs must point at the configured host_local_registry_host when prefer_external_workload_images=true."
  }
}

check "enable_app_repo_sentiment_requires_gitea_and_actions_runner" {
  assert {
    condition = !var.enable_app_repo_sentiment || (
      var.enable_gitea && (
        var.enable_actions_runner || (
          var.prefer_external_workload_images &&
          lookup(var.external_workload_image_refs, "sentiment-api", "") != "" &&
          lookup(var.external_workload_image_refs, "sentiment-auth-ui", "") != ""
        )
      )
    )
    error_message = "enable_app_repo_sentiment requires enable_gitea=true and either enable_actions_runner=true or explicit external sentiment image refs when prefer_external_workload_images=true."
  }
}

check "enable_app_repo_subnetcalc_requires_gitea_and_actions_runner" {
  assert {
    condition = !var.enable_app_repo_subnetcalc || (
      var.enable_gitea && (
        var.enable_actions_runner || (
          var.prefer_external_workload_images &&
          lookup(var.external_workload_image_refs, "subnetcalc-api-fastapi-container-app", "") != "" &&
          lookup(var.external_workload_image_refs, "subnetcalc-apim-simulator", "") != "" &&
          lookup(var.external_workload_image_refs, "subnetcalc-frontend-typescript-vite", "") != ""
        )
      )
    )
    error_message = "enable_app_repo_subnetcalc requires enable_gitea=true and either enable_actions_runner=true or explicit external subnetcalc API/APIM/TypeScript frontend image refs when prefer_external_workload_images=true."
  }
}

variable "subnetcalc_source_dir" {
  description = "Host path to the monorepo app directory for subnetcalc. Empty means auto-detect (repo_root/apps/subnetcalc)."
  type        = string
  default     = ""
}

variable "enable_docker_socket_mount" {
  description = "Mount the host Docker socket into Kind nodes (required for in-cluster Actions runner builds)."
  type        = bool
  default     = true
}

variable "docker_socket_path" {
  description = "Host path to the Docker socket to mount into Kind nodes."
  type        = string
  default     = "/var/run/docker.sock"
}

variable "enable_image_preload" {
  description = "Pre-pull container images and load them into the kind cluster before installing Cilium."
  type        = bool
  default     = true
}

variable "image_preload_parallelism" {
  description = "Number of parallel docker pull operations during image preloading."
  type        = number
  default     = 4
}

variable "preload_image_list_path" {
  description = "Path to the target-owned preload image list used when enable_image_preload=true."
  type        = string
  default     = ""
}

variable "registry_secret_namespaces" {
  description = "Namespaces that should receive a gitea-registry-creds imagePullSecret."
  type        = list(string)
  default     = []
}

variable "prefer_external_workload_images" {
  description = "Prefer external image refs in seeded workload manifests. Gitea app workflows can still override tags on app code changes."
  type        = bool
  default     = false
}

variable "external_workload_image_refs" {
  description = "Optional external image references keyed by workload image name (sentiment-api, sentiment-auth-ui, subnetcalc-api-fastapi-container-app, subnetcalc-apim-simulator, subnetcalc-frontend-react, subnetcalc-frontend-typescript-vite)."
  type        = map(string)
  default     = {}
}

variable "prefer_external_platform_images" {
  description = "Prefer external platform image refs when intentionally short-circuiting platform work outside the cluster. Default platform rollout remains the in-cluster path."
  type        = bool
  default     = false
}

variable "enable_backstage" {
  description = "Deploy the Backstage developer portal. Kind writes this through an operator override after checking local Docker memory."
  type        = bool
  default     = true
}

variable "external_platform_image_refs" {
  description = "Optional external platform image references keyed by platform image name. Supported keys today: backstage, grafana, hardened-registry, idp-core, signoz-auth-proxy."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for key in keys(var.external_platform_image_refs) :
      contains(["backstage", "grafana", "hardened-registry", "idp-core", "signoz-auth-proxy"], key)
    ])
    error_message = "external_platform_image_refs supports only: backstage, grafana, hardened-registry, idp-core, signoz-auth-proxy."
  }
}
