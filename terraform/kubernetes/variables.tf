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
  default     = "kindest/node:v1.35.0"
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
  description = "Enable SSO for the platform UIs by deploying Dex (OIDC IdP) and protecting UI routes via oauth2-proxy (small-footprint demo)."
  type        = bool
  default     = false
}

variable "enable_app_of_apps" {
  description = "Enable an Argo CD app-of-apps root Application (managed by Terraform) which syncs a directory of manifests from the GitOps/policies repo."
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Versions
# -----------------------------------------------------------------------------

variable "cilium_version" {
  description = "Cilium chart version."
  type        = string
  default     = "1.19.1"
}

variable "argocd_chart_version" {
  description = "Argo CD chart version."
  type        = string
  default     = "9.4.7"
}

variable "argocd_image_repository" {
  description = "Argo CD container image repository used by the argo-cd Helm chart."
  type        = string
  default     = "dhi.io/argocd"
}

variable "argocd_image_tag" {
  description = "Argo CD container image tag used by the argo-cd Helm chart."
  type        = string
  default     = "3.3.2-debian13"
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
  default     = "12.5.0"
}

variable "prometheus_chart_version" {
  description = "Prometheus chart version (prometheus-community/prometheus)."
  type        = string
  default     = "28.13.0"
}

variable "prometheus_image_tag" {
  description = "Prometheus hardened container image tag."
  type        = string
  default     = "3.10.0-debian13"
}

variable "grafana_chart_version" {
  description = "Grafana chart version (grafana/grafana)."
  type        = string
  default     = "10.5.15"
}

variable "loki_chart_version" {
  description = "Loki chart version (grafana/loki)."
  type        = string
  default     = "6.53.0"
}

variable "tempo_chart_version" {
  description = "Tempo chart version (grafana/tempo)."
  type        = string
  default     = "1.24.4"
}

variable "signoz_chart_version" {
  description = "SigNoz chart version."
  type        = string
  default     = "0.114.0"
}

variable "headlamp_chart_version" {
  description = "Headlamp chart version."
  type        = string
  default     = "0.40.0"
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
  default     = "v1.19.4"
}

variable "cert_manager_image_tag" {
  description = "cert-manager hardened container image tag."
  type        = string
  default     = "1.19.4-debian13"
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

variable "oauth2_proxy_chart_version" {
  description = "oauth2-proxy chart version (oauth2-proxy.github.io/manifests)."
  type        = string
  default     = "10.1.4"
}

variable "opentelemetry_collector_chart_version" {
  description = "OpenTelemetry Collector chart version (open-telemetry/opentelemetry-collector)."
  type        = string
  default     = "0.146.1"
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

variable "enable_app_repo_subnet_calculator" {
  description = "Seed the monorepo app apps/subnet-calculator into in-cluster Gitea as a standalone repo (enables Gitea Actions pipelines)."
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

check "enable_app_repo_subnet_calculator_requires_gitea_and_actions_runner" {
  assert {
    condition = !var.enable_app_repo_subnet_calculator || (
      var.enable_gitea && (
        var.enable_actions_runner || (
          var.prefer_external_workload_images &&
          lookup(var.external_workload_image_refs, "subnetcalc-api-fastapi-container-app", "") != "" &&
          lookup(var.external_workload_image_refs, "subnetcalc-apim-simulator", "") != "" &&
          lookup(var.external_workload_image_refs, "subnetcalc-frontend-react", "") != ""
        )
      )
    )
    error_message = "enable_app_repo_subnet_calculator requires enable_gitea=true and either enable_actions_runner=true or explicit external subnetcalc image refs when prefer_external_workload_images=true."
  }
}

variable "subnet_calculator_source_dir" {
  description = "Host path to the monorepo app directory for subnet-calculator. Empty means auto-detect (repo_root/apps/subnet-calculator)."
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

variable "llm_gateway_external_name" {
  description = "DNS name used by the in-cluster llm-gateway ExternalName service."
  type        = string
  default     = "host.docker.internal"
}

variable "llm_gateway_external_cidr" {
  description = "Optional explicit CIDR for the direct LLM gateway policy. Set this when the host-side name is not resolvable from the machine rendering the policies repo."
  type        = string
  default     = ""
}

variable "llm_gateway_mode" {
  description = "Legacy LLM gateway mode for sentiment workloads. Use 'disabled' for the SST default, 'litellm' for the in-cluster LiteLLM broker, or 'direct' for a host-backed ExternalName service."
  type        = string
  default     = "disabled"

  validation {
    condition     = contains(["disabled", "litellm", "direct"], var.llm_gateway_mode)
    error_message = "llm_gateway_mode must be one of: disabled, litellm, direct."
  }
}

variable "llama_cpp_hf_repo" {
  description = "Hugging Face repository containing the GGUF model used by the in-cluster llama.cpp backend when llm_gateway_mode is litellm."
  type        = string
  default     = "bartowski/SmolLM2-1.7B-Instruct-GGUF"
}

variable "llama_cpp_image" {
  description = "Container image for the in-cluster llama.cpp backend."
  type        = string
  default     = "ghcr.io/ggml-org/llama.cpp:server"
}

variable "llama_cpp_hf_file" {
  description = "GGUF filename fetched by the in-cluster llama.cpp backend when llm_gateway_mode is litellm."
  type        = string
  default     = "SmolLM2-1.7B-Instruct-Q4_K_M.gguf"
}

variable "llama_cpp_model_alias" {
  description = "Model alias exposed by the in-cluster llama.cpp OpenAI-compatible API."
  type        = string
  default     = "local-classifier"
}

variable "llama_cpp_ctx_size" {
  description = "Context size for the in-cluster llama.cpp backend."
  type        = number
  default     = 2048
}

variable "litellm_upstream_model" {
  description = "LiteLLM upstream model identifier used by the in-cluster broker."
  type        = string
  default     = "openai/local-classifier"
}

variable "litellm_upstream_api_base" {
  description = "LiteLLM upstream API base URL used by the in-cluster broker."
  type        = string
  default     = "http://llama-cpp:8080/v1"
}

variable "litellm_upstream_api_key" {
  description = "LiteLLM upstream API key used by the in-cluster broker."
  type        = string
  default     = "dummy"
  sensitive   = true
}
