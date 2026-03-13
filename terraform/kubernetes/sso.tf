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
    local_sensitive_file.kubeconfig,
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
    SIGNOZ_PASSWORD = "password123"
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
          issuer: https://dex.127.0.0.1.sslip.io/dex
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
              # password: password123
              hash: "$2y$10$/n1XH6BhemBb2RUv0w9.8OIoWOoCNpBB2hSidX9vEjV40O5aepT3G"
              username: "demo-admin"
              userID: "0a1f0e7f-75fa-40cc-90bc-9e876c0919dc"
            - email: "demo@dev.test"
              emailVerified: true
              # password: password123
              hash: "$2y$10$aDc6H5h5HocWZQqVW4atMuhcFKMdu1HIeN0cXd3SlTxmp8ggfknd6"
              username: "demo@dev.test"
              userID: "cfe2f539-3972-4310-bc7e-8579af6c4b20"
            - email: "demo@uat.test"
              emailVerified: true
              # password: password123
              hash: "$2y$10$aDc6H5h5HocWZQqVW4atMuhcFKMdu1HIeN0cXd3SlTxmp8ggfknd6"
              username: "demo@uat.test"
              userID: "e3bbece5-a293-47d9-9d7d-3d8cb218fc23"

          staticClients:
            - id: oauth2-proxy
              name: "oauth2-proxy"
              secret: ${random_password.dex_oauth2_proxy_client_secret[0].result}
              redirectURIs:
                - https://argocd.admin.127.0.0.1.sslip.io/oauth2/callback
                - https://gitea.admin.127.0.0.1.sslip.io/oauth2/callback
                - https://hubble.admin.127.0.0.1.sslip.io/oauth2/callback
                - https://grafana.admin.127.0.0.1.sslip.io/oauth2/callback
                - https://signoz.admin.127.0.0.1.sslip.io/oauth2/callback
                - https://sentiment.dev.127.0.0.1.sslip.io/oauth2/callback
                - https://sentiment.uat.127.0.0.1.sslip.io/oauth2/callback
                - https://subnetcalc.dev.127.0.0.1.sslip.io/oauth2/callback
                - https://subnetcalc.uat.127.0.0.1.sslip.io/oauth2/callback
            - id: argocd
              name: "argocd"
              secret: ${random_password.dex_argocd_client_secret[0].result}
              redirectURIs:
                - https://argocd.admin.127.0.0.1.sslip.io/auth/callback
            - id: headlamp
              name: "headlamp"
              secret: ${random_password.dex_headlamp_client_secret[0].result}
              redirectURIs:
                - https://headlamp.admin.127.0.0.1.sslip.io/oidc-callback
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
    script_sha          = filesha256(abspath("${path.module}/scripts/configure-kind-apiserver-oidc.sh"))
    gateway_service_uid = kubernetes_service_v1.platform_gateway_nginx_internal[0].metadata[0].uid
  }

  provisioner "local-exec" {
    command     = "bash \"${path.module}/scripts/configure-kind-apiserver-oidc.sh\""
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG                  = local.kubeconfig_path_expanded
      CLUSTER_NAME                = var.cluster_name
      DEX_HOST                    = "dex.127.0.0.1.sslip.io"
      DEX_NAMESPACE               = "sso"
      OIDC_ISSUER_URL             = "https://dex.127.0.0.1.sslip.io/dex"
      OIDC_CLIENT_ID              = "headlamp"
      MKCERT_CA_DEST              = "/etc/kubernetes/pki/mkcert-rootCA.pem"
      OIDC_DISCOVERY_WAIT_SECONDS = "900"
    }
  }

  depends_on = [
    local_sensitive_file.kubeconfig,
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

resource "kubectl_manifest" "clusterrolebinding_oidc_demo_admin_cluster_admin" {
  count = var.enable_sso && var.enable_gateway_tls ? 1 : 0

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
    null_resource.configure_kind_apiserver_oidc,
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
          registry: ${var.hardened_image_registry}
          repository: oauth2-proxy
          tag: 7.14.2-debian13
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
          oidc-issuer-url: https://dex.127.0.0.1.sslip.io/dex
          profile-url: http://dex.sso.svc.cluster.local:5556/dex/userinfo
          oidc-email-claim: email
          insecure-oidc-allow-unverified-email: "true"
          user-id-claim: email
          skip-oidc-discovery: "true"
          ssl-insecure-skip-verify: "true"
          login-url: https://dex.127.0.0.1.sslip.io/dex/auth?prompt=login
          redeem-url: http://dex.sso.svc.cluster.local:5556/dex/token
          oidc-jwks-url: http://dex.sso.svc.cluster.local:5556/dex/keys
          redirect-url: https://argocd.admin.127.0.0.1.sslip.io/oauth2/callback
          upstream: http://argocd-server.argocd.svc.cluster.local:8080
          email-domain: "admin.test"
          cookie-domain: .127.0.0.1.sslip.io
          whitelist-domain: .127.0.0.1.sslip.io
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
          registry: ${var.hardened_image_registry}
          repository: oauth2-proxy
          tag: 7.14.2-debian13
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
          oidc-issuer-url: https://dex.127.0.0.1.sslip.io/dex
          profile-url: http://dex.sso.svc.cluster.local:5556/dex/userinfo
          oidc-email-claim: email
          insecure-oidc-allow-unverified-email: "true"
          user-id-claim: email
          skip-oidc-discovery: "true"
          ssl-insecure-skip-verify: "true"
          login-url: https://dex.127.0.0.1.sslip.io/dex/auth?prompt=login
          redeem-url: http://dex.sso.svc.cluster.local:5556/dex/token
          oidc-jwks-url: http://dex.sso.svc.cluster.local:5556/dex/keys
          redirect-url: https://gitea.admin.127.0.0.1.sslip.io/oauth2/callback
          upstream: http://gitea-http.gitea.svc.cluster.local:3000
          email-domain: "admin.test"
          cookie-domain: .127.0.0.1.sslip.io
          whitelist-domain: .127.0.0.1.sslip.io
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
  count = var.enable_sso && var.enable_argocd ? 1 : 0

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
          registry: ${var.hardened_image_registry}
          repository: oauth2-proxy
          tag: 7.14.2-debian13
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
          oidc-issuer-url: https://dex.127.0.0.1.sslip.io/dex
          profile-url: http://dex.sso.svc.cluster.local:5556/dex/userinfo
          oidc-email-claim: email
          insecure-oidc-allow-unverified-email: "true"
          user-id-claim: email
          skip-oidc-discovery: "true"
          ssl-insecure-skip-verify: "true"
          login-url: https://dex.127.0.0.1.sslip.io/dex/auth
          redeem-url: http://dex.sso.svc.cluster.local:5556/dex/token
          oidc-jwks-url: http://dex.sso.svc.cluster.local:5556/dex/keys
          redirect-url: https://hubble.admin.127.0.0.1.sslip.io/oauth2/callback
          upstream: http://hubble-ui.kube-system.svc.cluster.local:80
          email-domain: "admin.test"
          cookie-domain: .127.0.0.1.sslip.io
          whitelist-domain: .127.0.0.1.sslip.io
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
          registry: ${var.hardened_image_registry}
          repository: oauth2-proxy
          tag: 7.14.2-debian13
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
          oidc-issuer-url: https://dex.127.0.0.1.sslip.io/dex
          profile-url: http://dex.sso.svc.cluster.local:5556/dex/userinfo
          oidc-email-claim: email
          insecure-oidc-allow-unverified-email: "true"
          user-id-claim: email
          skip-oidc-discovery: "true"
          ssl-insecure-skip-verify: "true"
          login-url: https://dex.127.0.0.1.sslip.io/dex/auth?prompt=login
          redeem-url: http://dex.sso.svc.cluster.local:5556/dex/token
          oidc-jwks-url: http://dex.sso.svc.cluster.local:5556/dex/keys
          redirect-url: https://grafana.admin.127.0.0.1.sslip.io/oauth2/callback
          upstream: http://grafana.observability.svc.cluster.local:3000
          email-domain: "admin.test"
          cookie-domain: .127.0.0.1.sslip.io
          whitelist-domain: .127.0.0.1.sslip.io
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
          registry: ${var.hardened_image_registry}
          repository: oauth2-proxy
          tag: 7.14.2-debian13
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
          oidc-issuer-url: https://dex.127.0.0.1.sslip.io/dex
          profile-url: http://dex.sso.svc.cluster.local:5556/dex/userinfo
          oidc-email-claim: email
          insecure-oidc-allow-unverified-email: "true"
          user-id-claim: email
          skip-oidc-discovery: "true"
          ssl-insecure-skip-verify: "true"
          login-url: https://dex.127.0.0.1.sslip.io/dex/auth
          redeem-url: http://dex.sso.svc.cluster.local:5556/dex/token
          oidc-jwks-url: http://dex.sso.svc.cluster.local:5556/dex/keys
          redirect-url: https://signoz.admin.127.0.0.1.sslip.io/oauth2/callback
          upstream: http://signoz-auth-proxy.observability.svc.cluster.local:3000
          email-domain: "admin.test"
          cookie-domain: .127.0.0.1.sslip.io
          whitelist-domain: .127.0.0.1.sslip.io
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
          registry: ${var.hardened_image_registry}
          repository: oauth2-proxy
          tag: 7.14.2-debian13
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
          oidc-issuer-url: https://dex.127.0.0.1.sslip.io/dex
          profile-url: http://dex.sso.svc.cluster.local:5556/dex/userinfo
          oidc-email-claim: email
          insecure-oidc-allow-unverified-email: "true"
          user-id-claim: email
          skip-oidc-discovery: "true"
          ssl-insecure-skip-verify: "true"
          login-url: https://dex.127.0.0.1.sslip.io/dex/auth
          redeem-url: http://dex.sso.svc.cluster.local:5556/dex/token
          oidc-jwks-url: http://dex.sso.svc.cluster.local:5556/dex/keys
          redirect-url: https://sentiment.dev.127.0.0.1.sslip.io/oauth2/callback
          upstream: http://sentiment-router.dev.svc.cluster.local:8080
          upstream-timeout: 180s
          email-domain: "dev.test"
          cookie-domain: .dev.127.0.0.1.sslip.io
          whitelist-domain: .dev.127.0.0.1.sslip.io
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
          registry: ${var.hardened_image_registry}
          repository: oauth2-proxy
          tag: 7.14.2-debian13
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
          oidc-issuer-url: https://dex.127.0.0.1.sslip.io/dex
          profile-url: http://dex.sso.svc.cluster.local:5556/dex/userinfo
          oidc-email-claim: email
          insecure-oidc-allow-unverified-email: "true"
          user-id-claim: email
          skip-oidc-discovery: "true"
          ssl-insecure-skip-verify: "true"
          login-url: https://dex.127.0.0.1.sslip.io/dex/auth?prompt=login
          redeem-url: http://dex.sso.svc.cluster.local:5556/dex/token
          oidc-jwks-url: http://dex.sso.svc.cluster.local:5556/dex/keys
          redirect-url: https://sentiment.uat.127.0.0.1.sslip.io/oauth2/callback
          upstream: http://sentiment-router.uat.svc.cluster.local:8080
          upstream-timeout: 180s
          # UAT apps should only accept demo@uat.test (not demo@admin.test).
          email-domain: "uat.test"
          cookie-domain: .uat.127.0.0.1.sslip.io
          whitelist-domain: .uat.127.0.0.1.sslip.io
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
          registry: ${var.hardened_image_registry}
          repository: oauth2-proxy
          tag: 7.14.2-debian13
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
          oidc-issuer-url: https://dex.127.0.0.1.sslip.io/dex
          profile-url: http://dex.sso.svc.cluster.local:5556/dex/userinfo
          oidc-email-claim: email
          insecure-oidc-allow-unverified-email: "true"
          user-id-claim: email
          skip-oidc-discovery: "true"
          ssl-insecure-skip-verify: "true"
          login-url: https://dex.127.0.0.1.sslip.io/dex/auth
          redeem-url: http://dex.sso.svc.cluster.local:5556/dex/token
          oidc-jwks-url: http://dex.sso.svc.cluster.local:5556/dex/keys
          redirect-url: https://subnetcalc.dev.127.0.0.1.sslip.io/oauth2/callback
          upstream: http://subnetcalc-router.dev.svc.cluster.local:8080
          email-domain: "dev.test"
          cookie-domain: .dev.127.0.0.1.sslip.io
          whitelist-domain: .dev.127.0.0.1.sslip.io
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
          registry: ${var.hardened_image_registry}
          repository: oauth2-proxy
          tag: 7.14.2-debian13
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
          oidc-issuer-url: https://dex.127.0.0.1.sslip.io/dex
          profile-url: http://dex.sso.svc.cluster.local:5556/dex/userinfo
          oidc-email-claim: email
          insecure-oidc-allow-unverified-email: "true"
          user-id-claim: email
          skip-oidc-discovery: "true"
          ssl-insecure-skip-verify: "true"
          login-url: https://dex.127.0.0.1.sslip.io/dex/auth
          redeem-url: http://dex.sso.svc.cluster.local:5556/dex/token
          oidc-jwks-url: http://dex.sso.svc.cluster.local:5556/dex/keys
          redirect-url: https://subnetcalc.uat.127.0.0.1.sslip.io/oauth2/callback
          upstream: http://subnetcalc-router.uat.svc.cluster.local:8080
          # UAT apps should only accept demo@uat.test (not demo@admin.test).
          email-domain: "uat.test"
          cookie-domain: .uat.127.0.0.1.sslip.io
          whitelist-domain: .uat.127.0.0.1.sslip.io
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
