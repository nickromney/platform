resource "kubernetes_namespace_v1" "sso" {
  count = var.enable_sso ? 1 : 0

  metadata {
    name = "sso"
    labels = {
      "platform.publiccloudexperiments.net/namespace-role" = "shared"
      "platform.publiccloudexperiments.net/sensitivity"    = "restricted"
      "kyverno.io/isolate"                                 = "true"
    }
  }

  depends_on = [
    kind_cluster.local,
    null_resource.ensure_kind_kubeconfig,
  ]
}

resource "random_password" "dex_oauth2_proxy_client_secret" {
  count = var.enable_sso ? 1 : 0

  length  = 32
  special = false
}

resource "random_password" "dex_argocd_client_secret" {
  count = var.enable_sso ? 1 : 0

  length  = 32
  special = false
}

resource "random_password" "dex_headlamp_client_secret" {
  count = var.enable_sso ? 1 : 0

  length  = 32
  special = false
}

resource "random_password" "oauth2_proxy_cookie_secret" {
  count = var.enable_sso ? 1 : 0

  length  = 32
  special = false
}

resource "terraform_data" "dex_demo_password_hash" {
  count = var.enable_sso ? 1 : 0

  triggers_replace = sha256(var.gitea_member_user_pwd)
  input            = bcrypt(var.gitea_member_user_pwd)

  lifecycle {
    ignore_changes = [input]
  }
}

resource "kubernetes_secret_v1" "oauth2_proxy_oidc" {
  count = var.enable_sso ? 1 : 0

  metadata {
    name      = "oauth2-proxy-oidc"
    namespace = kubernetes_namespace_v1.sso[0].metadata[0].name
  }

  type = "Opaque"

  data = {
    "client-id"     = "oauth2-proxy"
    "client-secret" = random_password.dex_oauth2_proxy_client_secret[0].result
    "cookie-secret" = random_password.oauth2_proxy_cookie_secret[0].result
  }
}

resource "kubernetes_secret_v1" "signoz_auth_proxy_credentials" {
  count = var.enable_sso && var.enable_signoz ? 1 : 0

  metadata {
    name      = "signoz-auth-proxy-credentials"
    namespace = "observability"
  }

  type = "Opaque"

  data = {
    SIGNOZ_URL      = "http://signoz:8080"
    SIGNOZ_USER     = "demo@admin.test"
    SIGNOZ_PASSWORD = var.gitea_member_user_pwd
  }

  depends_on = [
    kubernetes_namespace_v1.observability,
  ]
}

resource "kubernetes_secret_v1" "signoz_bootstrap_credentials" {
  count = var.enable_sso && var.enable_signoz ? 1 : 0

  metadata {
    name      = "signoz-bootstrap-credentials"
    namespace = "observability"
  }

  type = "Opaque"

  data = {
    SIGNOZ_BOOTSTRAP_PASSWORD = var.gitea_member_user_pwd
  }

  depends_on = [
    kubernetes_namespace_v1.observability,
  ]
}

data "external" "mkcert_ca_cert" {
  count = var.enable_sso && var.enable_headlamp ? 1 : 0

  program = ["/bin/bash", "./scripts/fetch-mkcert-ca-cert.sh"]

  depends_on = [
    null_resource.bootstrap_mkcert_ca,
  ]
}

resource "kubernetes_secret_v1" "headlamp_mkcert_ca" {
  count = var.enable_sso && var.enable_headlamp ? 1 : 0

  metadata {
    name      = "mkcert-ca"
    namespace = kubernetes_namespace_v1.headlamp[0].metadata[0].name
  }

  data = {
    "ca.crt" = data.external.mkcert_ca_cert[0].result.value
  }

  type = "Opaque"

  depends_on = [
    kubernetes_namespace_v1.headlamp,
    data.external.mkcert_ca_cert,
  ]
}

resource "kubectl_manifest" "argocd_app_dex" {
  count = var.enable_sso && var.enable_argocd ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: dex
  namespace: ${var.argocd_namespace}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: sso
    server: https://kubernetes.default.svc
  source:
    repoURL: ${local.policies_repo_url_cluster}
    targetRevision: main
    path: ${local.vendored_chart_paths.dex}
    helm:
      releaseName: dex
      values: |
        # dex DHI image (2.44.0-debian13) is built with Go 1.25 which strictly
        # validates RFC 3986 IP literals. Dex's Kubernetes storage backend
        # unconditionally wraps KUBERNETES_SERVICE_HOST in brackets, which Go 1.25
        # rejects for IPv4. Use the upstream image (older Go) until dex fixes the
        # URL construction bug.
        config:
          issuer: ${local.dex_public_url}
          storage:
            type: kubernetes
            config:
              inCluster: true
          web:
            http: 0.0.0.0:5556

          oauth2:
            skipApprovalScreen: true

          enablePasswordDB: true
          staticPasswords:
            - email: "demo@admin.test"
              emailVerified: true
              hash: "${terraform_data.dex_demo_password_hash[0].output}"
              username: "demo-admin"
              userID: "0a1f0e7f-75fa-40cc-90bc-9e876c0919dc"
            - email: "demo@dev.test"
              emailVerified: true
              hash: "${terraform_data.dex_demo_password_hash[0].output}"
              username: "demo@dev.test"
              userID: "cfe2f539-3972-4310-bc7e-8579af6c4b20"
            - email: "demo@uat.test"
              emailVerified: true
              hash: "${terraform_data.dex_demo_password_hash[0].output}"
              username: "demo@uat.test"
              userID: "e3bbece5-a293-47d9-9d7d-3d8cb218fc23"

          staticClients:
            - id: oauth2-proxy
              name: "oauth2-proxy"
              secret: ${random_password.dex_oauth2_proxy_client_secret[0].result}
              redirectURIs:
                - ${local.argocd_public_url}/oauth2/callback
                - ${local.gitea_public_url}/oauth2/callback
                - ${local.hubble_public_url}/oauth2/callback
                - ${local.grafana_public_url}/oauth2/callback
                - ${local.signoz_public_url}/oauth2/callback
                - ${local.sentiment_dev_public_url}/oauth2/callback
                - ${local.sentiment_uat_public_url}/oauth2/callback
                - ${local.subnetcalc_dev_public_url}/oauth2/callback
                - ${local.subnetcalc_uat_public_url}/oauth2/callback
            - id: argocd
              name: "argocd"
              secret: ${random_password.dex_argocd_client_secret[0].result}
              redirectURIs:
                - ${local.argocd_public_url}/auth/callback
            - id: headlamp
              name: "headlamp"
              secret: ${random_password.dex_headlamp_client_secret[0].result}
              redirectURIs:
                - ${local.headlamp_public_url}/oidc-callback
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - SkipDryRunOnMissingResource=true
__YAML__

  wait              = true
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = false

  depends_on = [
    helm_release.argocd,
    kubernetes_secret_v1.argocd_repo_policies,
    null_resource.sync_gitea_policies_repo,
    null_resource.argocd_repo_server_restart,
    kubernetes_namespace_v1.sso,
    kubernetes_secret_v1.oauth2_proxy_oidc,
  ]
}

resource "null_resource" "configure_kind_apiserver_oidc" {
  count = var.enable_sso && var.enable_gateway_tls && var.provision_kind_cluster ? 1 : 0

  triggers = {
    configure_script_sha = filesha256(abspath("${local.stack_dir}/scripts/configure-kind-apiserver-oidc.sh"))
    helper_lib_sha       = filesha256(abspath("${local.stack_dir}/scripts/kind-apiserver-oidc-lib.sh"))
    render_helper_sha    = filesha256(abspath("${local.stack_dir}/scripts/render-kind-apiserver-oidc-manifest.py"))
    gateway_service_uid  = kubernetes_service_v1.platform_gateway_nginx_internal[0].metadata[0].uid
    cluster_name         = var.cluster_name
    dex_host             = local.dex_public_host
    oidc_client_id       = "headlamp"
    oidc_issuer_url      = local.dex_public_url
    mkcert_ca_dest       = "/etc/kubernetes/pki/mkcert-rootCA.pem"
  }

  provisioner "local-exec" {
    command     = "bash \"${local.stack_dir}/scripts/configure-kind-apiserver-oidc.sh\" --execute"
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG                  = local.kubeconfig_path_expanded
      CLUSTER_NAME                = var.cluster_name
      DEX_HOST                    = local.dex_public_host
      DEX_NAMESPACE               = "sso"
      OIDC_ISSUER_URL             = local.dex_public_url
      OIDC_CLIENT_ID              = "headlamp"
      MKCERT_CA_DEST              = "/etc/kubernetes/pki/mkcert-rootCA.pem"
      OIDC_DISCOVERY_WAIT_SECONDS = "900"
    }
  }

  depends_on = [
    null_resource.ensure_kind_kubeconfig,
    kubernetes_service_v1.platform_gateway_nginx_internal,
    null_resource.argocd_refresh_gitops_repo_apps,
    kubectl_manifest.argocd_app_dex,
    kubectl_manifest.argocd_app_oauth2_proxy_argocd,
    kubectl_manifest.argocd_app_oauth2_proxy_gitea,
    kubectl_manifest.argocd_app_oauth2_proxy_hubble,
    kubectl_manifest.argocd_app_oauth2_proxy_grafana,
    kubectl_manifest.argocd_app_oauth2_proxy_signoz,
    kubectl_manifest.argocd_app_oauth2_proxy_sentiment,
    kubectl_manifest.argocd_app_oauth2_proxy_sentiment_uat,
    kubectl_manifest.argocd_app_oauth2_proxy_subnetcalc,
    kubectl_manifest.argocd_app_oauth2_proxy_subnetcalc_uat,
  ]
}

resource "null_resource" "recover_kind_cluster_after_oidc_restart" {
  count = var.enable_sso && var.enable_gateway_tls && var.provision_kind_cluster ? 1 : 0

  triggers = {
    recovery_script_sha = filesha256(abspath("${local.stack_dir}/scripts/recover-kind-cluster-after-apiserver-restart.sh"))
    helper_lib_sha      = filesha256(abspath("${local.stack_dir}/scripts/kind-apiserver-oidc-lib.sh"))
    oidc_resource_id    = null_resource.configure_kind_apiserver_oidc[0].id
  }

  provisioner "local-exec" {
    command     = "bash \"${local.stack_dir}/scripts/recover-kind-cluster-after-apiserver-restart.sh\" --execute"
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = local.kubeconfig_path_expanded
    }
  }

  depends_on = [
    null_resource.configure_kind_apiserver_oidc,
  ]
}

resource "null_resource" "check_kind_cluster_health_after_oidc" {
  count = var.enable_sso && var.enable_gateway_tls && var.provision_kind_cluster ? 1 : 0

  triggers = {
    health_script_sha         = filesha256(abspath("${local.stack_dir}/scripts/check-cluster-health.sh"))
    health_resource_sha       = filesha256(abspath("${local.stack_dir}/sso.tf"))
    kind_stage_900_tfvars_sha = try(filesha256(var.kind_stage_900_tfvars_file), "absent")
    kind_target_tfvars_sha    = try(filesha256(var.kind_target_tfvars_file), "absent")
    operator_overrides_sha    = try(filesha256(var.kind_operator_overrides_file), "absent")
    recovery_resource_id      = null_resource.recover_kind_cluster_after_oidc_restart[0].id
  }

  provisioner "local-exec" {
    command     = <<__EOT__
set -euo pipefail
export KUBECONFIG="${local.kubeconfig_path_expanded}"
KIND_STAGE_900_TFVARS_FILE="${var.kind_stage_900_tfvars_file}"
KIND_TARGET_TFVARS_FILE="${var.kind_target_tfvars_file}"
KIND_OPERATOR_OVERRIDES_FILE="${var.kind_operator_overrides_file}"
PLATFORM_TFVARS_FILE="$${PLATFORM_TFVARS:-}"
check_args=()
if [[ -n "$${KIND_STAGE_900_TFVARS_FILE}" && -f "$${KIND_STAGE_900_TFVARS_FILE}" ]]; then
  check_args+=(--var-file "$${KIND_STAGE_900_TFVARS_FILE}")
fi
if [[ -n "$${KIND_TARGET_TFVARS_FILE}" && -f "$${KIND_TARGET_TFVARS_FILE}" ]]; then
  check_args+=(--var-file "$${KIND_TARGET_TFVARS_FILE}")
fi
if [[ -n "$${PLATFORM_TFVARS_FILE}" && -f "$${PLATFORM_TFVARS_FILE}" ]]; then
  check_args+=(--var-file "$${PLATFORM_TFVARS_FILE}")
fi
if [[ -f "$${KIND_OPERATOR_OVERRIDES_FILE}" ]]; then
  check_args+=(--var-file "$${KIND_OPERATOR_OVERRIDES_FILE}")
fi
"${local.stack_dir}/scripts/check-cluster-health.sh" --execute "$${check_args[@]}"
__EOT__
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [
    null_resource.recover_kind_cluster_after_oidc_restart,
  ]
}

resource "kubectl_manifest" "clusterrolebinding_oidc_demo_admin_cluster_admin" {
  count = var.enable_sso && var.enable_gateway_tls && var.enable_demo_cluster_admin_binding ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: oidc-demo-admin-cluster-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: User
    apiGroup: rbac.authorization.k8s.io
    name: demo@admin.test
__YAML__

  wait              = true
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = true

  depends_on = [
    null_resource.check_kind_cluster_health_after_oidc,
  ]
}

resource "kubectl_manifest" "argocd_app_oauth2_proxy_argocd" {
  count = var.enable_sso && var.enable_argocd ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: oauth2-proxy-argocd
  namespace: ${var.argocd_namespace}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: sso
    server: https://kubernetes.default.svc
  source:
    repoURL: ${local.policies_repo_url_cluster}
    targetRevision: main
    path: ${local.vendored_chart_paths.oauth2_proxy}
    helm:
      releaseName: oauth2-proxy-argocd
      values: |
        image:
          registry: ${local.hardened_image_registry_effective}
          repository: oauth2-proxy
          tag: 7.15.2-debian13
        config:
          existingSecret: oauth2-proxy-oidc
          cookieName: kind-sso-admin
          configFile: ""

        service:
          portNumber: 4180

        resources:
          requests:
            cpu: 50m
            memory: 64Mi

        livenessProbe:
          initialDelaySeconds: 10
          timeoutSeconds: 15
          failureThreshold: 10

        readinessProbe:
          initialDelaySeconds: 5
          timeoutSeconds: 15
          failureThreshold: 10

        extraArgs:
          provider: oidc
          scope: "openid email profile"
          oidc-issuer-url: ${local.dex_public_url}
          profile-url: http://dex.sso.svc.cluster.local:5556/dex/userinfo
          oidc-email-claim: email
          insecure-oidc-allow-unverified-email: "true"
          user-id-claim: email
          skip-oidc-discovery: "true"
          ssl-insecure-skip-verify: "true"
          login-url: ${local.dex_public_url}/auth?prompt=login
          redeem-url: http://dex.sso.svc.cluster.local:5556/dex/token
          oidc-jwks-url: http://dex.sso.svc.cluster.local:5556/dex/keys
          redirect-url: ${local.argocd_public_url}/oauth2/callback
          upstream: http://argocd-server.argocd.svc.cluster.local:8080
          email-domain: "admin.test"
          cookie-domain: ${local.admin_cookie_domain}
          whitelist-domain: ${local.admin_whitelist_domains}
          cookie-secure: "true"
          show-debug-on-error: "true"
          pass-access-token: "true"
          pass-user-headers: "true"
          set-xauthrequest: "true"
          set-authorization-header: "true"
          reverse-proxy: "true"
          skip-provider-button: "true"
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - SkipDryRunOnMissingResource=true
__YAML__

  wait              = true
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = false

  depends_on = [
    helm_release.argocd,
    kubernetes_secret_v1.argocd_repo_policies,
    null_resource.sync_gitea_policies_repo,
    null_resource.argocd_repo_server_restart,
    kubernetes_namespace_v1.sso,
    kubernetes_secret_v1.oauth2_proxy_oidc,
    kubectl_manifest.argocd_app_dex,
  ]
}

resource "kubectl_manifest" "argocd_app_oauth2_proxy_gitea" {
  count = var.enable_sso && var.enable_argocd ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: oauth2-proxy-gitea
  namespace: ${var.argocd_namespace}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: sso
    server: https://kubernetes.default.svc
  source:
    repoURL: ${local.policies_repo_url_cluster}
    targetRevision: main
    path: ${local.vendored_chart_paths.oauth2_proxy}
    helm:
      releaseName: oauth2-proxy-gitea
      values: |
        image:
          registry: ${local.hardened_image_registry_effective}
          repository: oauth2-proxy
          tag: 7.15.2-debian13
        config:
          existingSecret: oauth2-proxy-oidc
          cookieName: kind-sso-admin
          configFile: ""

        service:
          portNumber: 4180

        resources:
          requests:
            cpu: 50m
            memory: 64Mi

        livenessProbe:
          initialDelaySeconds: 10
          timeoutSeconds: 15
          failureThreshold: 10

        readinessProbe:
          initialDelaySeconds: 5
          timeoutSeconds: 15
          failureThreshold: 10

        extraArgs:
          provider: oidc
          scope: "openid email profile"
          oidc-issuer-url: ${local.dex_public_url}
          profile-url: http://dex.sso.svc.cluster.local:5556/dex/userinfo
          oidc-email-claim: email
          insecure-oidc-allow-unverified-email: "true"
          user-id-claim: email
          skip-oidc-discovery: "true"
          ssl-insecure-skip-verify: "true"
          login-url: ${local.dex_public_url}/auth?prompt=login
          redeem-url: http://dex.sso.svc.cluster.local:5556/dex/token
          oidc-jwks-url: http://dex.sso.svc.cluster.local:5556/dex/keys
          redirect-url: ${local.gitea_public_url}/oauth2/callback
          upstream: http://gitea-http.gitea.svc.cluster.local:3000
          email-domain: "admin.test"
          cookie-domain: ${local.admin_cookie_domain}
          whitelist-domain: ${local.admin_whitelist_domains}
          cookie-secure: "true"
          show-debug-on-error: "true"
          pass-access-token: "true"
          pass-user-headers: "true"
          set-xauthrequest: "true"
          set-authorization-header: "true"
          reverse-proxy: "true"
          skip-provider-button: "true"
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - SkipDryRunOnMissingResource=true
__YAML__

  wait              = true
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = false

  depends_on = [
    helm_release.argocd,
    kubernetes_secret_v1.argocd_repo_policies,
    null_resource.sync_gitea_policies_repo,
    null_resource.argocd_repo_server_restart,
    kubernetes_namespace_v1.sso,
    kubernetes_secret_v1.oauth2_proxy_oidc,
    kubectl_manifest.argocd_app_dex,
  ]
}

resource "kubectl_manifest" "argocd_app_oauth2_proxy_hubble" {
  count = var.enable_sso && var.enable_hubble && var.enable_argocd ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: oauth2-proxy-hubble
  namespace: ${var.argocd_namespace}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: sso
    server: https://kubernetes.default.svc
  source:
    repoURL: ${local.policies_repo_url_cluster}
    targetRevision: main
    path: ${local.vendored_chart_paths.oauth2_proxy}
    helm:
      releaseName: oauth2-proxy-hubble
      values: |
        image:
          registry: ${local.hardened_image_registry_effective}
          repository: oauth2-proxy
          tag: 7.15.2-debian13
        config:
          existingSecret: oauth2-proxy-oidc
          cookieName: kind-sso-admin
          configFile: ""

        service:
          portNumber: 4180

        resources:
          requests:
            cpu: 50m
            memory: 64Mi

        livenessProbe:
          initialDelaySeconds: 10
          timeoutSeconds: 15
          failureThreshold: 10

        readinessProbe:
          initialDelaySeconds: 5
          timeoutSeconds: 15
          failureThreshold: 10

        extraArgs:
          provider: oidc
          scope: "openid email profile"
          oidc-issuer-url: ${local.dex_public_url}
          profile-url: http://dex.sso.svc.cluster.local:5556/dex/userinfo
          oidc-email-claim: email
          insecure-oidc-allow-unverified-email: "true"
          user-id-claim: email
          skip-oidc-discovery: "true"
          ssl-insecure-skip-verify: "true"
          login-url: ${local.dex_public_url}/auth
          redeem-url: http://dex.sso.svc.cluster.local:5556/dex/token
          oidc-jwks-url: http://dex.sso.svc.cluster.local:5556/dex/keys
          redirect-url: ${local.hubble_public_url}/oauth2/callback
          upstream: http://hubble-ui.kube-system.svc.cluster.local:80
          email-domain: "admin.test"
          cookie-domain: ${local.admin_cookie_domain}
          whitelist-domain: ${local.admin_whitelist_domains}
          cookie-secure: "true"
          show-debug-on-error: "true"
          pass-user-headers: "true"
          set-xauthrequest: "true"
          set-authorization-header: "true"
          reverse-proxy: "true"
          skip-provider-button: "true"
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - SkipDryRunOnMissingResource=true
__YAML__

  wait              = true
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = false

  depends_on = [
    helm_release.argocd,
    kubernetes_secret_v1.argocd_repo_policies,
    null_resource.sync_gitea_policies_repo,
    null_resource.argocd_repo_server_restart,
    kubernetes_namespace_v1.sso,
    kubernetes_secret_v1.oauth2_proxy_oidc,
    kubectl_manifest.argocd_app_dex,
  ]
}

resource "kubectl_manifest" "argocd_app_oauth2_proxy_grafana" {
  count = var.enable_sso && var.enable_argocd && var.enable_grafana ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: oauth2-proxy-grafana
  namespace: ${var.argocd_namespace}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: sso
    server: https://kubernetes.default.svc
  source:
    repoURL: ${local.policies_repo_url_cluster}
    targetRevision: main
    path: ${local.vendored_chart_paths.oauth2_proxy}
    helm:
      releaseName: oauth2-proxy-grafana
      values: |
        image:
          registry: ${local.hardened_image_registry_effective}
          repository: oauth2-proxy
          tag: 7.15.2-debian13
        config:
          existingSecret: oauth2-proxy-oidc
          cookieName: kind-sso-admin
          configFile: ""

        service:
          portNumber: 4180

        resources:
          requests:
            cpu: 50m
            memory: 64Mi

        livenessProbe:
          initialDelaySeconds: 10
          timeoutSeconds: 15
          failureThreshold: 10

        readinessProbe:
          initialDelaySeconds: 5
          timeoutSeconds: 15
          failureThreshold: 10

        extraArgs:
          provider: oidc
          scope: "openid email profile"
          oidc-issuer-url: ${local.dex_public_url}
          profile-url: http://dex.sso.svc.cluster.local:5556/dex/userinfo
          oidc-email-claim: email
          insecure-oidc-allow-unverified-email: "true"
          user-id-claim: email
          skip-oidc-discovery: "true"
          ssl-insecure-skip-verify: "true"
          login-url: ${local.dex_public_url}/auth?prompt=login
          redeem-url: http://dex.sso.svc.cluster.local:5556/dex/token
          oidc-jwks-url: http://dex.sso.svc.cluster.local:5556/dex/keys
          redirect-url: ${local.grafana_public_url}/oauth2/callback
          upstream: http://grafana.observability.svc.cluster.local:3000
          email-domain: "admin.test"
          cookie-domain: ${local.admin_cookie_domain}
          whitelist-domain: ${local.admin_whitelist_domains}
          cookie-secure: "true"
          show-debug-on-error: "true"
          pass-user-headers: "true"
          set-xauthrequest: "true"
          reverse-proxy: "true"
          skip-provider-button: "true"
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - SkipDryRunOnMissingResource=true
__YAML__

  wait              = true
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = false

  depends_on = [
    helm_release.argocd,
    kubernetes_secret_v1.argocd_repo_policies,
    null_resource.sync_gitea_policies_repo,
    null_resource.argocd_repo_server_restart,
    kubernetes_namespace_v1.sso,
    kubernetes_secret_v1.oauth2_proxy_oidc,
    kubectl_manifest.argocd_app_dex,
  ]
}

resource "kubectl_manifest" "argocd_app_oauth2_proxy_signoz" {
  count = var.enable_sso && var.enable_argocd && var.enable_signoz ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: oauth2-proxy-signoz
  namespace: ${var.argocd_namespace}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: sso
    server: https://kubernetes.default.svc
  source:
    repoURL: ${local.policies_repo_url_cluster}
    targetRevision: main
    path: ${local.vendored_chart_paths.oauth2_proxy}
    helm:
      releaseName: oauth2-proxy-signoz
      parameters:
        # Guardrail: Helm parameters can override helm.values (including via manual ArgoCD edits).
        # Keep SigNoz behind oauth2-proxy (SSO) and the SigNoz auth-bridge.
        - name: extraArgs.upstream
          value: http://signoz-auth-proxy.observability.svc.cluster.local:3000
      values: |
        image:
          registry: ${local.hardened_image_registry_effective}
          repository: oauth2-proxy
          tag: 7.15.2-debian13
        config:
          existingSecret: oauth2-proxy-oidc
          cookieName: kind-sso-admin
          configFile: ""

        service:
          portNumber: 4180

        # SigNoz is UI-heavy and is frequently hit by E2E; keep it resilient during rolling updates
        # and transient probe slowness.
        replicaCount: 2

        resources:
          requests:
            cpu: 50m
            memory: 64Mi

        livenessProbe:
          initialDelaySeconds: 10
          timeoutSeconds: 15
          failureThreshold: 10

        readinessProbe:
          initialDelaySeconds: 5
          timeoutSeconds: 15
          failureThreshold: 10

        extraArgs:
          provider: oidc
          scope: "openid email profile"
          oidc-issuer-url: ${local.dex_public_url}
          profile-url: http://dex.sso.svc.cluster.local:5556/dex/userinfo
          oidc-email-claim: email
          insecure-oidc-allow-unverified-email: "true"
          user-id-claim: email
          skip-oidc-discovery: "true"
          ssl-insecure-skip-verify: "true"
          login-url: ${local.dex_public_url}/auth
          redeem-url: http://dex.sso.svc.cluster.local:5556/dex/token
          oidc-jwks-url: http://dex.sso.svc.cluster.local:5556/dex/keys
          redirect-url: ${local.signoz_public_url}/oauth2/callback
          upstream: http://signoz-auth-proxy.observability.svc.cluster.local:3000
          email-domain: "admin.test"
          cookie-domain: ${local.admin_cookie_domain}
          whitelist-domain: ${local.admin_whitelist_domains}
          cookie-secure: "true"
          show-debug-on-error: "true"
          pass-user-headers: "true"
          set-xauthrequest: "true"
          reverse-proxy: "true"
          skip-provider-button: "true"
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - SkipDryRunOnMissingResource=true
__YAML__

  wait              = true
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = false

  depends_on = [
    helm_release.argocd,
    kubernetes_secret_v1.argocd_repo_policies,
    null_resource.sync_gitea_policies_repo,
    null_resource.argocd_repo_server_restart,
    kubernetes_namespace_v1.sso,
    kubernetes_secret_v1.oauth2_proxy_oidc,
    kubectl_manifest.argocd_app_dex,
  ]
}

resource "kubectl_manifest" "argocd_app_oauth2_proxy_sentiment" {
  count = var.enable_sso && var.enable_argocd && local.enable_sentiment_workloads_effective ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: oauth2-proxy-sentiment-dev
  namespace: ${var.argocd_namespace}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: sso
    server: https://kubernetes.default.svc
  source:
    repoURL: ${local.policies_repo_url_cluster}
    targetRevision: main
    path: ${local.vendored_chart_paths.oauth2_proxy}
    helm:
      releaseName: oauth2-proxy-sentiment-dev
      values: |
        image:
          registry: ${local.hardened_image_registry_effective}
          repository: oauth2-proxy
          tag: 7.15.2-debian13
        config:
          existingSecret: oauth2-proxy-oidc
          cookieName: kind-sso-dev
          configFile: ""

        service:
          portNumber: 4180

        resources:
          requests:
            cpu: 50m
            memory: 64Mi

        livenessProbe:
          initialDelaySeconds: 10
          timeoutSeconds: 15
          failureThreshold: 10

        readinessProbe:
          initialDelaySeconds: 5
          timeoutSeconds: 15
          failureThreshold: 10

        extraArgs:
          provider: oidc
          scope: "openid email profile"
          oidc-issuer-url: ${local.dex_public_url}
          profile-url: http://dex.sso.svc.cluster.local:5556/dex/userinfo
          oidc-email-claim: email
          insecure-oidc-allow-unverified-email: "true"
          user-id-claim: email
          skip-oidc-discovery: "true"
          ssl-insecure-skip-verify: "true"
          login-url: ${local.dex_public_url}/auth
          redeem-url: http://dex.sso.svc.cluster.local:5556/dex/token
          oidc-jwks-url: http://dex.sso.svc.cluster.local:5556/dex/keys
          redirect-url: ${local.sentiment_dev_public_url}/oauth2/callback
          upstream: http://sentiment-router.dev.svc.cluster.local:8080
          upstream-timeout: 180s
          email-domain: "dev.test"
          cookie-domain: ${local.dev_cookie_domain}
          whitelist-domain: ${local.dev_whitelist_domains}
          cookie-secure: "true"
          show-debug-on-error: "true"
          pass-access-token: "true"
          pass-user-headers: "true"
          set-xauthrequest: "true"
          set-authorization-header: "true"
          reverse-proxy: "true"
          skip-provider-button: "true"
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - SkipDryRunOnMissingResource=true
__YAML__

  wait              = true
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = false

  depends_on = [
    helm_release.argocd,
    kubernetes_secret_v1.argocd_repo_policies,
    null_resource.sync_gitea_policies_repo,
    null_resource.argocd_repo_server_restart,
    kubernetes_namespace_v1.sso,
    kubernetes_secret_v1.oauth2_proxy_oidc,
    kubectl_manifest.argocd_app_dex,
    # When enable_app_of_apps=true, apps are managed via the GitOps tree.
    kubectl_manifest.argocd_app_of_apps,
  ]
}

resource "kubectl_manifest" "argocd_app_oauth2_proxy_sentiment_uat" {
  count = var.enable_sso && var.enable_argocd && local.enable_sentiment_workloads_effective ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: oauth2-proxy-sentiment-uat
  namespace: ${var.argocd_namespace}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: sso
    server: https://kubernetes.default.svc
  source:
    repoURL: ${local.policies_repo_url_cluster}
    targetRevision: main
    path: ${local.vendored_chart_paths.oauth2_proxy}
    helm:
      releaseName: oauth2-proxy-sentiment-uat
      values: |
        image:
          registry: ${local.hardened_image_registry_effective}
          repository: oauth2-proxy
          tag: 7.15.2-debian13
        config:
          existingSecret: oauth2-proxy-oidc
          cookieName: kind-sso-uat
          configFile: ""

        service:
          portNumber: 4180

        resources:
          requests:
            cpu: 50m
            memory: 64Mi

        livenessProbe:
          initialDelaySeconds: 10
          timeoutSeconds: 15
          failureThreshold: 10

        readinessProbe:
          initialDelaySeconds: 5
          timeoutSeconds: 15
          failureThreshold: 10

        extraArgs:
          provider: oidc
          scope: "openid email profile"
          oidc-issuer-url: ${local.dex_public_url}
          profile-url: http://dex.sso.svc.cluster.local:5556/dex/userinfo
          oidc-email-claim: email
          insecure-oidc-allow-unverified-email: "true"
          user-id-claim: email
          skip-oidc-discovery: "true"
          ssl-insecure-skip-verify: "true"
          login-url: ${local.dex_public_url}/auth?prompt=login
          redeem-url: http://dex.sso.svc.cluster.local:5556/dex/token
          oidc-jwks-url: http://dex.sso.svc.cluster.local:5556/dex/keys
          redirect-url: ${local.sentiment_uat_public_url}/oauth2/callback
          upstream: http://sentiment-router.uat.svc.cluster.local:8080
          upstream-timeout: 180s
          # UAT apps should only accept demo@uat.test (not demo@admin.test).
          email-domain: "uat.test"
          cookie-domain: ${local.uat_cookie_domain}
          whitelist-domain: ${local.uat_whitelist_domains}
          cookie-secure: "true"
          show-debug-on-error: "true"
          pass-access-token: "true"
          pass-user-headers: "true"
          set-xauthrequest: "true"
          set-authorization-header: "true"
          reverse-proxy: "true"
          skip-provider-button: "true"
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - SkipDryRunOnMissingResource=true
__YAML__

  wait              = true
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = false

  depends_on = [
    helm_release.argocd,
    kubernetes_secret_v1.argocd_repo_policies,
    null_resource.sync_gitea_policies_repo,
    null_resource.argocd_repo_server_restart,
    kubernetes_namespace_v1.sso,
    kubernetes_secret_v1.oauth2_proxy_oidc,
    kubectl_manifest.argocd_app_dex,
    # When enable_app_of_apps=true, apps are managed via the GitOps tree.
    kubectl_manifest.argocd_app_of_apps,
  ]
}

resource "kubectl_manifest" "argocd_app_oauth2_proxy_subnetcalc" {
  count = var.enable_sso && var.enable_argocd && local.enable_subnetcalc_workloads_effective ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: oauth2-proxy-subnetcalc-dev
  namespace: ${var.argocd_namespace}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: sso
    server: https://kubernetes.default.svc
  source:
    repoURL: ${local.policies_repo_url_cluster}
    targetRevision: main
    path: ${local.vendored_chart_paths.oauth2_proxy}
    helm:
      releaseName: oauth2-proxy-subnetcalc-dev
      values: |
        image:
          registry: ${local.hardened_image_registry_effective}
          repository: oauth2-proxy
          tag: 7.15.2-debian13
        config:
          existingSecret: oauth2-proxy-oidc
          cookieName: kind-sso-dev
          configFile: ""

        service:
          portNumber: 4180

        resources:
          requests:
            cpu: 50m
            memory: 64Mi

        livenessProbe:
          initialDelaySeconds: 10
          timeoutSeconds: 15
          failureThreshold: 10

        readinessProbe:
          initialDelaySeconds: 5
          timeoutSeconds: 15
          failureThreshold: 10

        extraArgs:
          provider: oidc
          scope: "openid email profile"
          oidc-issuer-url: ${local.dex_public_url}
          profile-url: http://dex.sso.svc.cluster.local:5556/dex/userinfo
          oidc-email-claim: email
          insecure-oidc-allow-unverified-email: "true"
          user-id-claim: email
          skip-oidc-discovery: "true"
          ssl-insecure-skip-verify: "true"
          login-url: ${local.dex_public_url}/auth
          redeem-url: http://dex.sso.svc.cluster.local:5556/dex/token
          oidc-jwks-url: http://dex.sso.svc.cluster.local:5556/dex/keys
          redirect-url: ${local.subnetcalc_dev_public_url}/oauth2/callback
          upstream: http://subnetcalc-router.dev.svc.cluster.local:8080
          email-domain: "dev.test"
          cookie-domain: ${local.dev_cookie_domain}
          whitelist-domain: ${local.dev_whitelist_domains}
          cookie-secure: "true"
          show-debug-on-error: "true"
          # Only allow the logout landing page + favicon unauthenticated.
          # /.auth/* should stay protected so the frontend "whoami" endpoint isn't silently unauthenticated.
          skip-auth-regex: "^/(logged-out\\.html|favicon\\.svg)$"
          pass-access-token: "true"
          pass-user-headers: "true"
          set-xauthrequest: "true"
          set-authorization-header: "true"
          reverse-proxy: "true"
          skip-provider-button: "true"
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - SkipDryRunOnMissingResource=true
__YAML__

  wait              = true
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = false

  depends_on = [
    helm_release.argocd,
    kubernetes_secret_v1.argocd_repo_policies,
    null_resource.sync_gitea_policies_repo,
    null_resource.argocd_repo_server_restart,
    kubernetes_namespace_v1.sso,
    kubernetes_secret_v1.oauth2_proxy_oidc,
    kubectl_manifest.argocd_app_dex,
    # When enable_app_of_apps=true, apps are managed via the GitOps tree.
    kubectl_manifest.argocd_app_of_apps,
  ]
}

resource "kubectl_manifest" "argocd_app_oauth2_proxy_subnetcalc_uat" {
  count = var.enable_sso && var.enable_argocd && local.enable_subnetcalc_workloads_effective ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: oauth2-proxy-subnetcalc-uat
  namespace: ${var.argocd_namespace}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: sso
    server: https://kubernetes.default.svc
  source:
    repoURL: ${local.policies_repo_url_cluster}
    targetRevision: main
    path: ${local.vendored_chart_paths.oauth2_proxy}
    helm:
      releaseName: oauth2-proxy-subnetcalc-uat
      values: |
        image:
          registry: ${local.hardened_image_registry_effective}
          repository: oauth2-proxy
          tag: 7.15.2-debian13
        config:
          existingSecret: oauth2-proxy-oidc
          cookieName: kind-sso-uat
          configFile: ""

        service:
          portNumber: 4180

        resources:
          requests:
            cpu: 50m
            memory: 64Mi

        livenessProbe:
          initialDelaySeconds: 10
          timeoutSeconds: 15
          failureThreshold: 10

        readinessProbe:
          initialDelaySeconds: 5
          timeoutSeconds: 15
          failureThreshold: 10

        extraArgs:
          provider: oidc
          scope: "openid email profile"
          oidc-issuer-url: ${local.dex_public_url}
          profile-url: http://dex.sso.svc.cluster.local:5556/dex/userinfo
          oidc-email-claim: email
          insecure-oidc-allow-unverified-email: "true"
          user-id-claim: email
          skip-oidc-discovery: "true"
          ssl-insecure-skip-verify: "true"
          login-url: ${local.dex_public_url}/auth
          redeem-url: http://dex.sso.svc.cluster.local:5556/dex/token
          oidc-jwks-url: http://dex.sso.svc.cluster.local:5556/dex/keys
          redirect-url: ${local.subnetcalc_uat_public_url}/oauth2/callback
          upstream: http://subnetcalc-router.uat.svc.cluster.local:8080
          # UAT apps should only accept demo@uat.test (not demo@admin.test).
          email-domain: "uat.test"
          cookie-domain: ${local.uat_cookie_domain}
          whitelist-domain: ${local.uat_whitelist_domains}
          cookie-secure: "true"
          show-debug-on-error: "true"
          # Only allow the logout landing page + favicon unauthenticated.
          # /.auth/* should stay protected so the frontend "whoami" endpoint isn't silently unauthenticated.
          skip-auth-regex: "^/(logged-out\\.html|favicon\\.svg)$"
          pass-access-token: "true"
          pass-user-headers: "true"
          set-xauthrequest: "true"
          set-authorization-header: "true"
          reverse-proxy: "true"
          skip-provider-button: "true"
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - SkipDryRunOnMissingResource=true
__YAML__

  wait              = true
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = false

  depends_on = [
    helm_release.argocd,
    kubernetes_secret_v1.argocd_repo_policies,
    null_resource.sync_gitea_policies_repo,
    null_resource.argocd_repo_server_restart,
    kubernetes_namespace_v1.sso,
    kubernetes_secret_v1.oauth2_proxy_oidc,
    kubectl_manifest.argocd_app_dex,
    # When enable_app_of_apps=true, subnetcalc-uat is managed via the GitOps tree.
    kubectl_manifest.argocd_app_of_apps,
  ]
}

# Note: Legacy direct app definitions removed - using app-of-apps approach
# Apps are now defined in apps/argocd-apps/ (dev, uat, apim)
