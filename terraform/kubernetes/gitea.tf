resource "kubernetes_secret_v1" "gitea_admin" {
  count = var.enable_gitea ? 1 : 0

  metadata {
    name      = "gitea-admin-secret"
    namespace = kubernetes_namespace_v1.gitea[0].metadata[0].name
  }

  data = {
    username = var.gitea_admin_username
    password = var.gitea_admin_pwd
  }

  type = "Opaque"
}

resource "kubernetes_config_map_v1" "gitea_custom_templates" {
  count = var.enable_gitea ? 1 : 0

  metadata {
    name      = "gitea-custom-templates"
    namespace = kubernetes_namespace_v1.gitea[0].metadata[0].name
  }

  data = {
    "head_navbar.tmpl" = file("${path.module}/templates/gitea/base/head_navbar.tmpl")
  }
}

resource "kubernetes_secret_v1" "gitea_registry_creds" {
  for_each = var.enable_gitea ? local.registry_secret_namespaces_effective : toset([])

  metadata {
    name      = "gitea-registry-creds"
    namespace = each.value
  }

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        (var.gitea_registry_host) = {
          username = var.gitea_admin_username
          password = var.gitea_admin_pwd
          auth     = base64encode("${var.gitea_admin_username}:${var.gitea_admin_pwd}")
        }
      }
    })
  }

  type = "kubernetes.io/dockerconfigjson"

  depends_on = [
    kubernetes_namespace_v1.argocd,
    kubernetes_namespace_v1.gitea,
    kubernetes_namespace_v1.gitea_runner,
    kubernetes_namespace_v1.dev,
    kubernetes_namespace_v1.uat,
  ]
}

resource "kubectl_manifest" "argocd_app_gitea" {
  count = var.enable_gitea && var.enable_argocd ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gitea
  namespace: ${var.argocd_namespace}
spec:
  project: default
  destination:
    namespace: ${kubernetes_namespace_v1.gitea[0].metadata[0].name}
    server: https://kubernetes.default.svc
  source:
    repoURL: https://dl.gitea.io/charts/
    chart: gitea
    targetRevision: ${var.gitea_chart_version}
    helm:
      releaseName: gitea
      values: |
        service:
          http:
            type: NodePort
            nodePort: ${var.gitea_http_node_port}
          ssh:
            type: NodePort
            nodePort: ${var.gitea_ssh_node_port}
        ingress:
          enabled: false
        image:
          tag: "1.25.4"
        strategy:
          type: Recreate
        resources:
          requests:
            cpu: 50m
            memory: 128Mi
          limits:
            cpu: 250m
            memory: 384Mi
        postgresql:
          enabled: true
          primary:
            resources:
              requests:
                cpu: 50m
                memory: 128Mi
              limits:
                cpu: 250m
                memory: 256Mi
        postgresql-ha:
          enabled: false
        valkey-cluster:
          enabled: false
        valkey:
          enabled: true
          architecture: standalone
          global:
            valkey:
              password: changeme
          master:
            resources:
              requests:
                cpu: 25m
                memory: 64Mi
              limits:
                cpu: 100m
                memory: 128Mi
        extraVolumes:
          - name: gitea-custom-templates
            configMap:
              name: gitea-custom-templates
        extraContainerVolumeMounts:
          - name: gitea-custom-templates
            mountPath: /data/gitea/templates/base
        gitea:
          admin:
            existingSecret: gitea-admin-secret
            passwordKey: password
            username: ${var.gitea_admin_username}
            email: "admin@gitea.test"
          metrics:
            enabled: ${var.enable_observability_agent}
          config:
            log:
              LEVEL: debug
            server:
              DISABLE_SSH: false
              SSH_PORT: ${var.gitea_ssh_node_port}
              DOMAIN: "${var.enable_gateway_tls ? "gitea.admin.127.0.0.1.sslip.io" : "127.0.0.1"}"
              ROOT_URL: "${var.enable_gateway_tls ? "https://gitea.admin.127.0.0.1.sslip.io/" : "http://127.0.0.1:${var.gitea_http_node_port}/"}"
              PUBLIC_URL_DETECTION: auto
            packages:
              ENABLED: true
            actions:
              ENABLED: true
            security:
              INSTALL_LOCK: true
              REVERSE_PROXY_LIMIT: "2"
              REVERSE_PROXY_TRUSTED_PROXIES: 127.0.0.1/32,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16
              # Use a non-email username to satisfy Gitea's username validation.
              REVERSE_PROXY_AUTHENTICATION_USER: X-Forwarded-User
              REVERSE_PROXY_AUTHENTICATION_EMAIL: X-Forwarded-Email
              REVERSE_PROXY_AUTHENTICATION_FULL_NAME: X-Forwarded-Email
            service:
              ENABLE_REVERSE_PROXY_AUTHENTICATION: "${var.enable_sso ? "true" : "false"}"
              ENABLE_REVERSE_PROXY_AUTO_REGISTRATION: "${var.enable_sso ? "true" : "false"}"
              REQUIRE_SIGNIN_VIEW: "${var.enable_sso ? "true" : "false"}"
              # Mirror the headers here because existing app.ini values under [service] persist.
              REVERSE_PROXY_AUTHENTICATION_USER: X-Forwarded-User
              REVERSE_PROXY_AUTHENTICATION_EMAIL: X-Forwarded-Email
              REVERSE_PROXY_AUTHENTICATION_FULL_NAME: X-Forwarded-Email
              ENABLE_REVERSE_PROXY_EMAIL: "${var.enable_sso ? "true" : "false"}"
              ENABLE_REVERSE_PROXY_FULL_NAME: "${var.enable_sso ? "true" : "false"}"
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
__YAML__

  wait              = true
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = false

  depends_on = [
    helm_release.argocd,
    kubernetes_namespace_v1.gitea,
    kubernetes_secret_v1.gitea_admin,
    kubernetes_config_map_v1.gitea_custom_templates,
  ]
}

resource "null_resource" "gitea_promote_admin" {
  for_each = toset(local.gitea_admin_promote_users_effective)

  triggers = {
    user       = each.value
    script_sha = filesha256("${path.module}/scripts/promote-gitea-admin.sh")
    gitea_http = tostring(var.gitea_http_node_port)
    admin_user = var.gitea_admin_username
    admin_pwd  = sha1(var.gitea_admin_pwd)
  }

  provisioner "local-exec" {
    command = "bash \"${path.module}/scripts/promote-gitea-admin.sh\""
    environment = {
      GITEA_HTTP_BASE      = "http://${local.gitea_http_host_local}:${var.gitea_http_node_port}"
      GITEA_ADMIN_USERNAME = var.gitea_admin_username
      GITEA_ADMIN_PWD      = var.gitea_admin_pwd
      GITEA_PROMOTE_USER   = each.value
    }
  }

  depends_on = [
    kubectl_manifest.argocd_app_gitea,
    null_resource.gitea_unset_must_change_password,
  ]
}

resource "null_resource" "gitea_org" {
  count = var.enable_gitea && local.gitea_repo_owner_is_org ? 1 : 0

  triggers = {
    org_name          = local.gitea_repo_owner
    org_full_name     = var.gitea_org_full_name
    org_email         = var.gitea_org_email
    org_visibility    = var.gitea_org_visibility
    org_members       = join(",", var.gitea_org_members)
    org_member_emails = join(",", var.gitea_org_member_emails)
    gitea_http        = tostring(var.gitea_http_node_port)
    admin_user        = var.gitea_admin_username
    admin_pwd         = sha1(var.gitea_admin_pwd)
    script_sha        = filesha256("${path.module}/scripts/ensure-gitea-org.sh")
  }

  provisioner "local-exec" {
    command = "bash \"${path.module}/scripts/ensure-gitea-org.sh\""
    environment = {
      GITEA_HTTP_BASE           = "http://${local.gitea_http_host_local}:${var.gitea_http_node_port}"
      GITEA_ADMIN_USERNAME      = var.gitea_admin_username
      GITEA_ADMIN_PWD           = var.gitea_admin_pwd
      GITEA_ORG_NAME            = local.gitea_repo_owner
      GITEA_ORG_FULL_NAME       = var.gitea_org_full_name
      GITEA_ORG_EMAIL           = var.gitea_org_email
      GITEA_ORG_VISIBILITY      = var.gitea_org_visibility
      GITEA_ORG_MEMBERS         = join(",", var.gitea_org_members)
      GITEA_ORG_MEMBER_EMAILS   = join(",", var.gitea_org_member_emails)
      GITEA_MEMBERS_DEFAULT_PWD = var.gitea_member_user_pwd
    }
  }

  depends_on = [
    kubectl_manifest.argocd_app_gitea,
    null_resource.gitea_unset_must_change_password,
  ]
}

resource "null_resource" "gitea_unset_must_change_password" {
  count = var.enable_gitea ? 1 : 0

  triggers = {
    script_sha = filesha256("${path.module}/scripts/unset-gitea-must-change-password.sh")
  }

  provisioner "local-exec" {
    command = "bash \"${path.module}/scripts/unset-gitea-must-change-password.sh\""
    environment = {
      KUBECONFIG = local.kubeconfig_path_expanded
    }
  }

  depends_on = [
    kubectl_manifest.argocd_app_gitea,
  ]
}
