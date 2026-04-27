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

resource "random_password" "keycloak_postgres_password" {
  count = var.enable_sso && local.sso_provider_is_keycloak ? 1 : 0

  length  = 32
  special = false
}

resource "terraform_data" "dex_demo_password_hash" {
  count = var.enable_sso && local.sso_provider_is_dex ? 1 : 0

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

resource "kubectl_manifest" "oauth2_proxy_session_store_deployment" {
  count = var.enable_sso ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${local.oauth2_proxy_session_store_service}
  namespace: sso
  labels:
    app.kubernetes.io/name: ${local.oauth2_proxy_session_store_service}
    app.kubernetes.io/component: session-store
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: ${local.oauth2_proxy_session_store_service}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: ${local.oauth2_proxy_session_store_service}
        app.kubernetes.io/component: session-store
    spec:
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        runAsUser: 999
        runAsGroup: 999
        fsGroup: 999
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: redis
          image: ${var.oauth2_proxy_session_store_image}
          args:
            - redis-server
            - --save
            - ""
            - --appendonly
            - "no"
            - --protected-mode
            - "no"
            - --dir
            - /data
          ports:
            - name: redis
              containerPort: 6379
          readinessProbe:
            tcpSocket:
              port: redis
            initialDelaySeconds: 3
            periodSeconds: 5
          livenessProbe:
            tcpSocket:
              port: redis
            initialDelaySeconds: 10
            periodSeconds: 10
          resources:
            requests:
              cpu: 25m
              memory: 64Mi
            limits:
              cpu: 100m
              memory: 128Mi
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop:
                - ALL
          volumeMounts:
            - name: redis-data
              mountPath: /data
      volumes:
        - name: redis-data
          emptyDir: {}
__YAML__

  wait              = true
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = true

  depends_on = [
    kubernetes_namespace_v1.sso,
  ]
}

resource "kubectl_manifest" "oauth2_proxy_session_store_service" {
  count = var.enable_sso ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: v1
kind: Service
metadata:
  name: ${local.oauth2_proxy_session_store_service}
  namespace: sso
  labels:
    app.kubernetes.io/name: ${local.oauth2_proxy_session_store_service}
    app.kubernetes.io/component: session-store
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: ${local.oauth2_proxy_session_store_service}
  ports:
    - name: redis
      port: 6379
      targetPort: redis
__YAML__

  wait              = true
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = true

  depends_on = [
    kubectl_manifest.oauth2_proxy_session_store_deployment,
  ]
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

resource "kubernetes_secret_v1" "keycloak_bootstrap_admin" {
  count = var.enable_sso && local.sso_provider_is_keycloak ? 1 : 0

  metadata {
    name      = "keycloak-bootstrap-admin"
    namespace = kubernetes_namespace_v1.sso[0].metadata[0].name
  }

  type = "Opaque"

  data = {
    username = "keycloak-bootstrap-admin"
    password = var.gitea_member_user_pwd
  }
}

resource "kubernetes_secret_v1" "keycloak_admin" {
  count = var.enable_sso && local.sso_provider_is_keycloak ? 1 : 0

  metadata {
    name      = "keycloak-admin"
    namespace = kubernetes_namespace_v1.sso[0].metadata[0].name
  }

  type = "Opaque"

  data = {
    username = "keycloak-admin"
    password = var.gitea_member_user_pwd
  }
}

resource "kubernetes_secret_v1" "keycloak_postgres" {
  count = var.enable_sso && local.sso_provider_is_keycloak ? 1 : 0

  metadata {
    name      = "keycloak-postgres"
    namespace = kubernetes_namespace_v1.sso[0].metadata[0].name
  }

  type = "Opaque"

  data = {
    username = "keycloak"
    password = random_password.keycloak_postgres_password[0].result
    database = "keycloak"
  }
}

resource "kubernetes_config_map_v1" "keycloak_realm" {
  count = var.enable_sso && local.sso_provider_is_keycloak ? 1 : 0

  metadata {
    name      = "keycloak-realm"
    namespace = kubernetes_namespace_v1.sso[0].metadata[0].name
  }

  data = {
    "platform-realm.json" = jsonencode({
      realm       = local.keycloak_realm
      enabled     = true
      displayName = "Platform"
      groups = concat(
        [
          { name = local.sso_admin_group },
          { name = local.sso_viewer_group },
        ],
        [for group_name in local.sso_app_groups : { name = group_name }]
      )
      clientScopes = [
        {
          name        = "web-origins"
          protocol    = "openid-connect"
          description = "Allow OIDC clients to receive configured web origins"
          attributes = {
            "consent.screen.text"       = ""
            "display.on.consent.screen" = "false"
            "include.in.token.scope"    = "false"
          }
          protocolMappers = [
            {
              name            = "allowed web origins"
              protocol        = "openid-connect"
              protocolMapper  = "oidc-allowed-origins-mapper"
              consentRequired = false
              config = {
                "access.token.claim"        = "true"
                "introspection.token.claim" = "true"
              }
            }
          ]
        },
        {
          name        = "acr"
          protocol    = "openid-connect"
          description = "Expose authentication context class references"
          attributes = {
            "display.on.consent.screen" = "false"
            "include.in.token.scope"    = "false"
          }
          protocolMappers = [
            {
              name            = "acr loa level"
              protocol        = "openid-connect"
              protocolMapper  = "oidc-acr-mapper"
              consentRequired = false
              config = {
                "access.token.claim"        = "true"
                "id.token.claim"            = "true"
                "introspection.token.claim" = "true"
              }
            }
          ]
        },
        {
          name        = "basic"
          protocol    = "openid-connect"
          description = "Expose basic OpenID Connect session claims"
          attributes = {
            "display.on.consent.screen" = "false"
            "include.in.token.scope"    = "false"
          }
          protocolMappers = [
            {
              name            = "auth_time"
              protocol        = "openid-connect"
              protocolMapper  = "oidc-usersessionmodel-note-mapper"
              consentRequired = false
              config = {
                "access.token.claim"        = "true"
                "claim.name"                = "auth_time"
                "id.token.claim"            = "true"
                "introspection.token.claim" = "true"
                "jsonType.label"            = "long"
                "user.session.note"         = "AUTH_TIME"
              }
            },
            {
              name            = "sub"
              protocol        = "openid-connect"
              protocolMapper  = "oidc-sub-mapper"
              consentRequired = false
              config = {
                "access.token.claim"        = "true"
                "introspection.token.claim" = "true"
              }
            }
          ]
        },
        {
          name        = "email"
          protocol    = "openid-connect"
          description = "Expose email claims"
          attributes = {
            "consent.screen.text"       = "$${emailScopeConsentText}"
            "display.on.consent.screen" = "true"
            "include.in.token.scope"    = "true"
          }
          protocolMappers = [
            {
              name            = "email verified"
              protocol        = "openid-connect"
              protocolMapper  = "oidc-usermodel-property-mapper"
              consentRequired = false
              config = {
                "access.token.claim"        = "true"
                "claim.name"                = "email_verified"
                "id.token.claim"            = "true"
                "introspection.token.claim" = "true"
                "jsonType.label"            = "boolean"
                "user.attribute"            = "emailVerified"
                "userinfo.token.claim"      = "true"
              }
            },
            {
              name            = "email"
              protocol        = "openid-connect"
              protocolMapper  = "oidc-usermodel-attribute-mapper"
              consentRequired = false
              config = {
                "access.token.claim"        = "true"
                "claim.name"                = "email"
                "id.token.claim"            = "true"
                "introspection.token.claim" = "true"
                "jsonType.label"            = "String"
                "user.attribute"            = "email"
                "userinfo.token.claim"      = "true"
              }
            }
          ]
        },
        {
          name        = "profile"
          protocol    = "openid-connect"
          description = "Expose profile claims"
          attributes = {
            "consent.screen.text"       = "$${profileScopeConsentText}"
            "display.on.consent.screen" = "true"
            "include.in.token.scope"    = "true"
          }
          protocolMappers = [
            {
              name            = "username"
              protocol        = "openid-connect"
              protocolMapper  = "oidc-usermodel-attribute-mapper"
              consentRequired = false
              config = {
                "access.token.claim"        = "true"
                "claim.name"                = "preferred_username"
                "id.token.claim"            = "true"
                "introspection.token.claim" = "true"
                "jsonType.label"            = "String"
                "user.attribute"            = "username"
                "userinfo.token.claim"      = "true"
              }
            },
            {
              name            = "given name"
              protocol        = "openid-connect"
              protocolMapper  = "oidc-usermodel-attribute-mapper"
              consentRequired = false
              config = {
                "access.token.claim"        = "true"
                "claim.name"                = "given_name"
                "id.token.claim"            = "true"
                "introspection.token.claim" = "true"
                "jsonType.label"            = "String"
                "user.attribute"            = "firstName"
                "userinfo.token.claim"      = "true"
              }
            },
            {
              name            = "family name"
              protocol        = "openid-connect"
              protocolMapper  = "oidc-usermodel-attribute-mapper"
              consentRequired = false
              config = {
                "access.token.claim"        = "true"
                "claim.name"                = "family_name"
                "id.token.claim"            = "true"
                "introspection.token.claim" = "true"
                "jsonType.label"            = "String"
                "user.attribute"            = "lastName"
                "userinfo.token.claim"      = "true"
              }
            },
            {
              name            = "full name"
              protocol        = "openid-connect"
              protocolMapper  = "oidc-full-name-mapper"
              consentRequired = false
              config = {
                "access.token.claim"        = "true"
                "id.token.claim"            = "true"
                "introspection.token.claim" = "true"
                "userinfo.token.claim"      = "true"
              }
            }
          ]
        },
        {
          name        = local.sso_groups_claim
          protocol    = "openid-connect"
          description = "Expose Keycloak group memberships in OIDC tokens"
          attributes = {
            "display.on.consent.screen" = "false"
            "include.in.token.scope"    = "true"
          }
          protocolMappers = [
            {
              name            = local.sso_groups_claim
              protocol        = "openid-connect"
              protocolMapper  = "oidc-group-membership-mapper"
              consentRequired = false
              config = {
                "claim.name"           = local.sso_groups_claim
                "full.path"            = "false"
                "id.token.claim"       = "true"
                "access.token.claim"   = "true"
                "userinfo.token.claim" = "true"
              }
            }
          ]
        }
      ]
      clients = [
        {
          clientId                  = local.sso_apim_audience
          name                      = "APIM Simulator"
          enabled                   = true
          bearerOnly                = true
          publicClient              = false
          protocol                  = "openid-connect"
          fullScopeAllowed          = false
          standardFlowEnabled       = false
          directAccessGrantsEnabled = false
          serviceAccountsEnabled    = false
          defaultClientScopes       = []
          optionalClientScopes      = []
        },
        {
          clientId                  = "oauth2-proxy"
          name                      = "oauth2-proxy"
          enabled                   = true
          publicClient              = false
          protocol                  = "openid-connect"
          secret                    = random_password.dex_oauth2_proxy_client_secret[0].result
          fullScopeAllowed          = false
          standardFlowEnabled       = true
          directAccessGrantsEnabled = true
          redirectUris = [
            "${local.argocd_public_url}/oauth2/callback",
            "${local.gitea_public_url}/oauth2/callback",
            "${local.hubble_public_url}/oauth2/callback",
            "${local.grafana_public_url}/oauth2/callback",
            "${local.sentiment_dev_public_url}/oauth2/callback",
            "${local.sentiment_uat_public_url}/oauth2/callback",
            "${local.subnetcalc_dev_public_url}/oauth2/callback",
            "${local.subnetcalc_uat_public_url}/oauth2/callback",
            "${local.hello_platform_dev_public_url}/oauth2/callback",
            "${local.hello_platform_uat_public_url}/oauth2/callback",
            "${local.idp_portal_public_url}/oauth2/callback",
            "${local.idp_api_public_url}/oauth2/callback",
          ]
          webOrigins           = ["+"]
          defaultClientScopes  = ["web-origins", "acr", "profile", "basic", "email"]
          optionalClientScopes = [local.sso_groups_claim]
          protocolMappers = [
            {
              name            = "groups"
              protocol        = "openid-connect"
              protocolMapper  = "oidc-group-membership-mapper"
              consentRequired = false
              config = {
                "claim.name"           = local.sso_groups_claim
                "full.path"            = "false"
                "id.token.claim"       = "true"
                "access.token.claim"   = "true"
                "userinfo.token.claim" = "true"
              }
            },
            {
              name            = "oauth2-proxy-audience"
              protocol        = "openid-connect"
              protocolMapper  = "oidc-audience-mapper"
              consentRequired = false
              config = {
                "included.client.audience" = "oauth2-proxy"
                "id.token.claim"           = "false"
                "access.token.claim"       = "true"
              }
            },
            {
              name            = "${local.sso_apim_audience}-audience"
              protocol        = "openid-connect"
              protocolMapper  = "oidc-audience-mapper"
              consentRequired = false
              config = {
                "included.client.audience" = local.sso_apim_audience
                "id.token.claim"           = "false"
                "access.token.claim"       = "true"
              }
            }
          ]
        },
        {
          clientId                  = "argocd"
          name                      = "argocd"
          enabled                   = true
          publicClient              = false
          protocol                  = "openid-connect"
          secret                    = random_password.dex_argocd_client_secret[0].result
          fullScopeAllowed          = false
          standardFlowEnabled       = true
          directAccessGrantsEnabled = true
          redirectUris              = ["${local.argocd_public_url}/auth/callback"]
          webOrigins                = ["+"]
          defaultClientScopes       = ["web-origins", "acr", "profile", "basic", "email"]
          optionalClientScopes      = [local.sso_groups_claim]
          protocolMappers = [
            {
              name            = "groups"
              protocol        = "openid-connect"
              protocolMapper  = "oidc-group-membership-mapper"
              consentRequired = false
              config = {
                "claim.name"           = local.sso_groups_claim
                "full.path"            = "false"
                "id.token.claim"       = "true"
                "access.token.claim"   = "true"
                "userinfo.token.claim" = "true"
              }
            }
          ]
        },
        {
          clientId                  = "headlamp"
          name                      = "headlamp"
          enabled                   = true
          publicClient              = false
          protocol                  = "openid-connect"
          secret                    = random_password.dex_headlamp_client_secret[0].result
          fullScopeAllowed          = false
          standardFlowEnabled       = true
          directAccessGrantsEnabled = true
          redirectUris              = ["${local.headlamp_public_url}/oidc-callback"]
          webOrigins                = ["+"]
          defaultClientScopes       = ["web-origins", "acr", "profile", "basic", "email"]
          optionalClientScopes      = [local.sso_groups_claim]
          protocolMappers = [
            {
              name            = "groups"
              protocol        = "openid-connect"
              protocolMapper  = "oidc-group-membership-mapper"
              consentRequired = false
              config = {
                "claim.name"           = local.sso_groups_claim
                "full.path"            = "false"
                "id.token.claim"       = "true"
                "access.token.claim"   = "true"
                "userinfo.token.claim" = "true"
              }
            }
          ]
        },
      ]
      users = [
        {
          username      = "demo@admin.test"
          email         = "demo@admin.test"
          firstName     = "Demo"
          lastName      = "Admin"
          enabled       = true
          emailVerified = true
          groups        = [local.sso_admin_group, local.sso_viewer_group]
          credentials = [{
            type      = "password"
            value     = var.gitea_member_user_pwd
            temporary = false
          }]
        },
        {
          username      = "demo@dev.test"
          email         = "demo@dev.test"
          firstName     = "Demo"
          lastName      = "Dev"
          enabled       = true
          emailVerified = true
          groups        = [local.sso_viewer_group, "app-subnetcalc-dev", "app-sentiment-dev", "app-hello-platform-dev"]
          credentials = [{
            type      = "password"
            value     = var.gitea_member_user_pwd
            temporary = false
          }]
        },
        {
          username      = "demo@uat.test"
          email         = "demo@uat.test"
          firstName     = "Demo"
          lastName      = "UAT"
          enabled       = true
          emailVerified = true
          groups        = [local.sso_viewer_group, "app-subnetcalc-uat", "app-sentiment-uat", "app-hello-platform-uat"]
          credentials = [{
            type      = "password"
            value     = var.gitea_member_user_pwd
            temporary = false
          }]
        },
      ]
    })
  }
}

resource "kubectl_manifest" "keycloak_postgres" {
  count = var.enable_sso && local.sso_provider_is_keycloak ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: keycloak-postgres
  namespace: sso
spec:
  serviceName: keycloak-postgres
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: keycloak-postgres
  template:
    metadata:
      labels:
        app.kubernetes.io/name: keycloak-postgres
    spec:
      securityContext:
        fsGroup: 999
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: postgres
          image: ${var.keycloak_postgres_image}
          ports:
            - name: postgres
              containerPort: 5432
          env:
            - name: POSTGRES_DB
              valueFrom:
                secretKeyRef:
                  name: keycloak-postgres
                  key: database
            - name: POSTGRES_USER
              valueFrom:
                secretKeyRef:
                  name: keycloak-postgres
                  key: username
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: keycloak-postgres
                  key: password
            - name: PGDATA
              value: /var/lib/postgresql/data/pgdata
          resources:
            requests:
              cpu: 25m
              memory: 64Mi
            limits:
              cpu: 100m
              memory: 256Mi
          securityContext:
            runAsNonRoot: true
            runAsUser: 999
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql/data
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 1Gi
__YAML__

  wait              = true
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = true

  depends_on = [
    kubernetes_namespace_v1.sso,
    kubernetes_secret_v1.keycloak_postgres,
  ]
}

resource "kubectl_manifest" "keycloak_postgres_service" {
  count = var.enable_sso && local.sso_provider_is_keycloak ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: v1
kind: Service
metadata:
  name: keycloak-postgres
  namespace: sso
spec:
  selector:
    app.kubernetes.io/name: keycloak-postgres
  ports:
    - name: postgres
      port: 5432
      targetPort: postgres
__YAML__

  wait              = true
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = true

  depends_on = [
    kubernetes_namespace_v1.sso,
    kubectl_manifest.keycloak_postgres,
  ]
}

resource "kubectl_manifest" "keycloak" {
  count = var.enable_sso && local.sso_provider_is_keycloak ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: apps/v1
kind: Deployment
metadata:
  name: keycloak
  namespace: sso
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: keycloak
  template:
    metadata:
      labels:
        app.kubernetes.io/name: keycloak
    spec:
      securityContext:
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: keycloak
          image: ${var.keycloak_image}
          args:
            - start
            - --optimized
            - --import-realm
            - --http-enabled=true
            - --hostname=${local.keycloak_public_host}
            - --hostname-strict=false
            - --proxy-headers=xforwarded
          ports:
            - name: http
              containerPort: 8080
          env:
            - name: KC_BOOTSTRAP_ADMIN_USERNAME
              valueFrom:
                secretKeyRef:
                  name: keycloak-bootstrap-admin
                  key: username
            - name: KC_BOOTSTRAP_ADMIN_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: keycloak-bootstrap-admin
                  key: password
            - name: KC_DB
              value: postgres
            - name: KC_DB_URL_HOST
              value: keycloak-postgres.sso.svc.cluster.local
            - name: KC_DB_URL_DATABASE
              valueFrom:
                secretKeyRef:
                  name: keycloak-postgres
                  key: database
            - name: KC_DB_USERNAME
              valueFrom:
                secretKeyRef:
                  name: keycloak-postgres
                  key: username
            - name: KC_DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: keycloak-postgres
                  key: password
            - name: KC_CACHE
              value: local
            - name: JAVA_OPTS_KC_HEAP
              value: "-XX:InitialRAMPercentage=10 -XX:MaxRAMPercentage=40"
          resources:
            requests:
              cpu: "250m"
              memory: 768Mi
            limits:
              cpu: "750m"
              memory: 1280Mi
          readinessProbe:
            httpGet:
              path: /realms/${local.keycloak_realm}/.well-known/openid-configuration
              port: http
            initialDelaySeconds: 30
            periodSeconds: 10
            failureThreshold: 30
          startupProbe:
            httpGet:
              path: /realms/master
              port: http
            initialDelaySeconds: 30
            periodSeconds: 10
            failureThreshold: 60
          livenessProbe:
            httpGet:
              path: /realms/master
              port: http
            initialDelaySeconds: 180
            periodSeconds: 20
            failureThreshold: 10
          securityContext:
            runAsNonRoot: true
            runAsUser: 1000
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
          volumeMounts:
            - name: realm
              mountPath: /opt/keycloak/data/import
              readOnly: true
      volumes:
        - name: realm
          configMap:
            name: keycloak-realm
__YAML__

  wait              = true
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = true

  depends_on = [
    kubernetes_namespace_v1.sso,
    kubernetes_secret_v1.keycloak_bootstrap_admin,
    kubernetes_secret_v1.keycloak_admin,
    kubernetes_secret_v1.keycloak_postgres,
    kubernetes_config_map_v1.keycloak_realm,
    kubectl_manifest.keycloak_postgres,
    kubectl_manifest.keycloak_postgres_service,
  ]
}

resource "kubectl_manifest" "keycloak_service" {
  count = var.enable_sso && local.sso_provider_is_keycloak ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: v1
kind: Service
metadata:
  name: keycloak
  namespace: sso
spec:
  selector:
    app.kubernetes.io/name: keycloak
  ports:
    - name: http
      port: 8080
      targetPort: http
__YAML__

  wait              = true
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = true

  depends_on = [
    kubernetes_namespace_v1.sso,
    kubectl_manifest.keycloak,
  ]
}

resource "null_resource" "reconcile_keycloak_realm" {
  count = var.enable_sso && local.sso_provider_is_keycloak ? 1 : 0

  triggers = {
    realm_config_sha       = sha256(kubernetes_config_map_v1.keycloak_realm[0].data["platform-realm.json"])
    script_sha             = filesha256(abspath("${local.stack_dir}/scripts/reconcile-keycloak-realm.sh"))
    bootstrap_admin_secret = sha256(jsonencode(kubernetes_secret_v1.keycloak_bootstrap_admin[0].data))
    permanent_admin_secret = sha256(jsonencode(kubernetes_secret_v1.keycloak_admin[0].data))
  }

  provisioner "local-exec" {
    command = "bash \"${local.stack_dir}/scripts/reconcile-keycloak-realm.sh\" --execute"
    environment = {
      KUBECONFIG                      = local.kubeconfig_path_expanded
      KEYCLOAK_NAMESPACE              = kubernetes_namespace_v1.sso[0].metadata[0].name
      KEYCLOAK_REALM                  = local.keycloak_realm
      KEYCLOAK_REALM_CONFIGMAP        = kubernetes_config_map_v1.keycloak_realm[0].metadata[0].name
      KEYCLOAK_REALM_CONFIG_KEY       = "platform-realm.json"
      KEYCLOAK_BOOTSTRAP_ADMIN_SECRET = kubernetes_secret_v1.keycloak_bootstrap_admin[0].metadata[0].name
      KEYCLOAK_PERMANENT_ADMIN_SECRET = kubernetes_secret_v1.keycloak_admin[0].metadata[0].name
      REPO_ROOT                       = local.repo_root
    }
  }

  depends_on = [
    kubectl_manifest.keycloak,
    kubectl_manifest.keycloak_service,
  ]
}

resource "kubectl_manifest" "argocd_app_dex" {
  count = var.enable_sso && local.sso_provider_is_dex && var.enable_argocd ? 1 : 0

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
          issuer: ${local.sso_public_url}
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
              groups:
                - platform-admins
            - email: "demo@dev.test"
              emailVerified: true
              hash: "${terraform_data.dex_demo_password_hash[0].output}"
              username: "demo@dev.test"
              userID: "cfe2f539-3972-4310-bc7e-8579af6c4b20"
              groups:
                - platform-viewers
            - email: "demo@uat.test"
              emailVerified: true
              hash: "${terraform_data.dex_demo_password_hash[0].output}"
              username: "demo@uat.test"
              userID: "e3bbece5-a293-47d9-9d7d-3d8cb218fc23"
              groups:
                - platform-viewers

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
                - ${local.hello_platform_dev_public_url}/oauth2/callback
                - ${local.hello_platform_uat_public_url}/oauth2/callback
                - ${local.idp_portal_public_url}/oauth2/callback
                - ${local.idp_api_public_url}/oauth2/callback
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

resource "null_resource" "wait_for_platform_gateway_tls" {
  count = var.enable_sso && var.enable_gateway_tls && var.provision_kind_cluster ? 1 : 0

  triggers = {
    wait_script_sha              = filesha256(abspath("${local.stack_dir}/scripts/wait-for-platform-gateway-tls.sh"))
    gateway_name                 = "platform-gateway"
    tls_secret_name              = "platform-gateway-tls"
    cert_manager_config_app_name = "cert-manager-config"
  }

  provisioner "local-exec" {
    command     = "bash \"${local.stack_dir}/scripts/wait-for-platform-gateway-tls.sh\" --execute"
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG           = local.kubeconfig_path_expanded
      WAIT_TIMEOUT_SECONDS = "900"
    }
  }

  depends_on = [
    null_resource.ensure_kind_kubeconfig,
    null_resource.argocd_refresh_gitops_repo_apps,
    kubectl_manifest.argocd_app_cert_manager,
    kubectl_manifest.argocd_app_cert_manager_config,
    kubectl_manifest.argocd_app_nginx_gateway_fabric,
    kubectl_manifest.argocd_app_platform_gateway,
    kubectl_manifest.argocd_app_platform_gateway_routes,
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
    oidc_host            = local.sso_public_host
    oidc_client_id       = "headlamp"
    oidc_issuer_url      = local.sso_public_url
    mkcert_ca_dest       = "/etc/kubernetes/pki/mkcert-rootCA.pem"
  }

  provisioner "local-exec" {
    command     = "bash \"${local.stack_dir}/scripts/configure-kind-apiserver-oidc.sh\" --execute"
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG                  = local.kubeconfig_path_expanded
      CLUSTER_NAME                = var.cluster_name
      SSO_PROVIDER                = local.sso_provider_effective
      KEYCLOAK_REALM              = local.keycloak_realm
      DEX_HOST                    = local.sso_public_host
      DEX_NAMESPACE               = "sso"
      SSO_NAMESPACE               = "sso"
      SSO_DEPLOYMENT_NAME         = local.sso_provider_is_keycloak ? "keycloak" : "dex"
      SSO_SERVICE_NAME            = local.sso_provider_is_keycloak ? "keycloak" : "dex"
      SSO_DESCRIPTION             = local.sso_provider_is_keycloak ? "Keycloak" : "Dex"
      OIDC_ISSUER_URL             = local.sso_public_url
      OIDC_CLIENT_ID              = "headlamp"
      MKCERT_CA_DEST              = "/etc/kubernetes/pki/mkcert-rootCA.pem"
      OIDC_DISCOVERY_WAIT_SECONDS = "900"
    }
  }

  depends_on = [
    null_resource.ensure_kind_kubeconfig,
    kubernetes_service_v1.platform_gateway_nginx_internal,
    null_resource.argocd_refresh_gitops_repo_apps,
    null_resource.wait_for_platform_gateway_tls,
    null_resource.reconcile_keycloak_realm,
    kubectl_manifest.argocd_app_dex,
    kubectl_manifest.keycloak,
    kubectl_manifest.keycloak_service,
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
  - kind: Group
    apiGroup: rbac.authorization.k8s.io
    name: ${local.sso_admin_group}
__YAML__

  wait              = true
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = true

  depends_on = [
    null_resource.check_kind_cluster_health_after_oidc,
  ]
}

resource "kubectl_manifest" "clusterrole_oidc_platform_viewer" {
  count = var.enable_sso && var.enable_gateway_tls ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: oidc-platform-viewer
rules:
  - apiGroups: [""]
    resources: ["configmaps", "endpoints", "events", "namespaces", "nodes", "persistentvolumeclaims", "persistentvolumes", "pods", "pods/log", "services"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["apps"]
    resources: ["daemonsets", "deployments", "replicasets", "statefulsets"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["argoproj.io"]
    resources: ["applications", "applicationsets", "appprojects"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["gateway.networking.k8s.io", "gateway.nginx.org", "kyverno.io", "cilium.io"]
    resources: ["*"]
    verbs: ["get", "list", "watch"]
__YAML__

  wait              = true
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = true

  depends_on = [
    null_resource.check_kind_cluster_health_after_oidc,
  ]
}

resource "kubectl_manifest" "clusterrolebinding_oidc_platform_viewers" {
  count = var.enable_sso && var.enable_gateway_tls ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: oidc-platform-viewers
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: oidc-platform-viewer
subjects:
  - kind: Group
    apiGroup: rbac.authorization.k8s.io
    name: ${local.sso_viewer_group}
__YAML__

  wait              = true
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = true

  depends_on = [
    kubectl_manifest.clusterrole_oidc_platform_viewer,
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
          scope: "openid email profile groups"
          oidc-issuer-url: ${local.sso_public_url}
          profile-url: ${local.sso_userinfo_url}
          oidc-email-claim: email
          oidc-groups-claim: ${local.sso_groups_claim}
          insecure-oidc-allow-unverified-email: "true"
          user-id-claim: email
          skip-oidc-discovery: "true"
          ssl-insecure-skip-verify: "true"
          login-url: ${local.sso_login_url}
          redeem-url: ${local.sso_token_url}
          oidc-jwks-url: ${local.sso_jwks_url}
          redirect-url: ${local.argocd_public_url}/oauth2/callback
          upstream: http://argocd-server.argocd.svc.cluster.local:8080
          allowed-group: ${local.sso_viewer_group}
          cookie-domain: ${local.admin_cookie_domain}
          whitelist-domain: ${local.admin_whitelist_domains}
          cookie-secure: "true"
          session-store-type: redis
          redis-connection-url: ${local.oauth2_proxy_redis_url}
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
    kubectl_manifest.oauth2_proxy_session_store_service,
    kubectl_manifest.argocd_app_dex,
    kubectl_manifest.keycloak,
    kubectl_manifest.keycloak_service,
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
          scope: "openid email profile groups"
          oidc-issuer-url: ${local.sso_public_url}
          profile-url: ${local.sso_userinfo_url}
          oidc-email-claim: email
          oidc-groups-claim: ${local.sso_groups_claim}
          insecure-oidc-allow-unverified-email: "true"
          user-id-claim: email
          skip-oidc-discovery: "true"
          ssl-insecure-skip-verify: "true"
          login-url: ${local.sso_login_url}
          redeem-url: ${local.sso_token_url}
          oidc-jwks-url: ${local.sso_jwks_url}
          redirect-url: ${local.gitea_public_url}/oauth2/callback
          upstream: http://gitea-http.gitea.svc.cluster.local:3000
          allowed-group: ${local.sso_admin_group}
          cookie-domain: ${local.admin_cookie_domain}
          whitelist-domain: ${local.admin_whitelist_domains}
          cookie-secure: "true"
          session-store-type: redis
          redis-connection-url: ${local.oauth2_proxy_redis_url}
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
    kubectl_manifest.oauth2_proxy_session_store_service,
    kubectl_manifest.argocd_app_dex,
    kubectl_manifest.keycloak,
    kubectl_manifest.keycloak_service,
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
          scope: "openid email profile groups"
          oidc-issuer-url: ${local.sso_public_url}
          profile-url: ${local.sso_userinfo_url}
          oidc-email-claim: email
          oidc-groups-claim: ${local.sso_groups_claim}
          insecure-oidc-allow-unverified-email: "true"
          user-id-claim: email
          skip-oidc-discovery: "true"
          ssl-insecure-skip-verify: "true"
          login-url: ${local.sso_login_url}
          redeem-url: ${local.sso_token_url}
          oidc-jwks-url: ${local.sso_jwks_url}
          redirect-url: ${local.hubble_public_url}/oauth2/callback
          upstream: http://hubble-ui.kube-system.svc.cluster.local:80
          allowed-group: ${local.sso_admin_group}
          cookie-domain: ${local.admin_cookie_domain}
          whitelist-domain: ${local.admin_whitelist_domains}
          cookie-secure: "true"
          session-store-type: redis
          redis-connection-url: ${local.oauth2_proxy_redis_url}
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
    kubectl_manifest.oauth2_proxy_session_store_service,
    kubectl_manifest.argocd_app_dex,
    kubectl_manifest.keycloak,
    kubectl_manifest.keycloak_service,
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
          scope: "openid email profile groups"
          oidc-issuer-url: ${local.sso_public_url}
          profile-url: ${local.sso_userinfo_url}
          oidc-email-claim: email
          oidc-groups-claim: ${local.sso_groups_claim}
          insecure-oidc-allow-unverified-email: "true"
          user-id-claim: email
          skip-oidc-discovery: "true"
          ssl-insecure-skip-verify: "true"
          login-url: ${local.sso_login_url}
          redeem-url: ${local.sso_token_url}
          oidc-jwks-url: ${local.sso_jwks_url}
          redirect-url: ${local.grafana_public_url}/oauth2/callback
          upstream: http://grafana.observability.svc.cluster.local:3000
          allowed-group: ${local.sso_admin_group}
          cookie-domain: ${local.admin_cookie_domain}
          whitelist-domain: ${local.admin_whitelist_domains}
          cookie-secure: "true"
          session-store-type: redis
          redis-connection-url: ${local.oauth2_proxy_redis_url}
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
    kubectl_manifest.oauth2_proxy_session_store_service,
    kubectl_manifest.argocd_app_dex,
    kubectl_manifest.keycloak,
    kubectl_manifest.keycloak_service,
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
          scope: "openid email profile groups"
          oidc-issuer-url: ${local.sso_public_url}
          profile-url: ${local.sso_userinfo_url}
          oidc-email-claim: email
          oidc-groups-claim: ${local.sso_groups_claim}
          insecure-oidc-allow-unverified-email: "true"
          user-id-claim: email
          skip-oidc-discovery: "true"
          ssl-insecure-skip-verify: "true"
          login-url: ${local.sso_login_url}
          redeem-url: ${local.sso_token_url}
          oidc-jwks-url: ${local.sso_jwks_url}
          redirect-url: ${local.signoz_public_url}/oauth2/callback
          upstream: http://signoz-auth-proxy.observability.svc.cluster.local:3000
          allowed-group: ${local.sso_admin_group}
          cookie-domain: ${local.admin_cookie_domain}
          whitelist-domain: ${local.admin_whitelist_domains}
          cookie-secure: "true"
          session-store-type: redis
          redis-connection-url: ${local.oauth2_proxy_redis_url}
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
    kubectl_manifest.oauth2_proxy_session_store_service,
    kubectl_manifest.argocd_app_dex,
    kubectl_manifest.keycloak,
    kubectl_manifest.keycloak_service,
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
          - --provider=oidc
          - --scope=openid email profile groups
          - --oidc-issuer-url=${local.sso_public_url}
          - --profile-url=${local.sso_userinfo_url}
          - --oidc-email-claim=email
          - --oidc-groups-claim=${local.sso_groups_claim}
          - --insecure-oidc-allow-unverified-email=true
          - --user-id-claim=email
          - --skip-oidc-discovery=true
          - --ssl-insecure-skip-verify=true
          - --login-url=${local.sso_login_url}
          - --redeem-url=${local.sso_token_url}
          - --oidc-jwks-url=${local.sso_jwks_url}
          - --redirect-url=${local.sentiment_dev_public_url}/oauth2/callback
          - --upstream=http://sentiment-router.dev.svc.cluster.local:8080
          - --upstream-timeout=180s
          - --allowed-group=app-sentiment-dev
          - --allowed-group=${local.sso_admin_group}
          - --cookie-domain=${local.dev_cookie_domain}
          - --whitelist-domain=${local.dev_whitelist_domains}
          - --cookie-secure=true
          - --session-store-type=redis
          - --redis-connection-url=${local.oauth2_proxy_redis_url}
          - --show-debug-on-error=true
          - --pass-access-token=true
          - --pass-user-headers=true
          - --set-xauthrequest=true
          - --set-authorization-header=true
          - --reverse-proxy=true
          - --skip-provider-button=true
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
    kubectl_manifest.oauth2_proxy_session_store_service,
    kubectl_manifest.argocd_app_dex,
    kubectl_manifest.keycloak,
    kubectl_manifest.keycloak_service,
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
          - --provider=oidc
          - --scope=openid email profile groups
          - --oidc-issuer-url=${local.sso_public_url}
          - --profile-url=${local.sso_userinfo_url}
          - --oidc-email-claim=email
          - --oidc-groups-claim=${local.sso_groups_claim}
          - --insecure-oidc-allow-unverified-email=true
          - --user-id-claim=email
          - --skip-oidc-discovery=true
          - --ssl-insecure-skip-verify=true
          - --login-url=${local.sso_login_url}
          - --redeem-url=${local.sso_token_url}
          - --oidc-jwks-url=${local.sso_jwks_url}
          - --redirect-url=${local.sentiment_uat_public_url}/oauth2/callback
          - --upstream=http://sentiment-router.uat.svc.cluster.local:8080
          - --upstream-timeout=180s
          - --allowed-group=app-sentiment-uat
          - --allowed-group=${local.sso_admin_group}
          - --cookie-domain=${local.uat_cookie_domain}
          - --whitelist-domain=${local.uat_whitelist_domains}
          - --cookie-secure=true
          - --session-store-type=redis
          - --redis-connection-url=${local.oauth2_proxy_redis_url}
          - --show-debug-on-error=true
          - --pass-access-token=true
          - --pass-user-headers=true
          - --set-xauthrequest=true
          - --set-authorization-header=true
          - --reverse-proxy=true
          - --skip-provider-button=true
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
    kubectl_manifest.oauth2_proxy_session_store_service,
    kubectl_manifest.argocd_app_dex,
    kubectl_manifest.keycloak,
    kubectl_manifest.keycloak_service,
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
          - --provider=oidc
          - --scope=openid email profile groups
          - --oidc-issuer-url=${local.sso_public_url}
          - --profile-url=${local.sso_userinfo_url}
          - --oidc-email-claim=email
          - --oidc-groups-claim=${local.sso_groups_claim}
          - --insecure-oidc-allow-unverified-email=true
          - --user-id-claim=email
          - --skip-oidc-discovery=true
          - --ssl-insecure-skip-verify=true
          - --login-url=${local.sso_login_url}
          - --redeem-url=${local.sso_token_url}
          - --oidc-jwks-url=${local.sso_jwks_url}
          - --redirect-url=${local.subnetcalc_dev_public_url}/oauth2/callback
          - --upstream=http://subnetcalc-router.dev.svc.cluster.local:8080
          - --allowed-group=app-subnetcalc-dev
          - --allowed-group=${local.sso_admin_group}
          - --cookie-domain=${local.dev_cookie_domain}
          - --whitelist-domain=${local.dev_whitelist_domains}
          - --cookie-secure=true
          - --session-store-type=redis
          - --redis-connection-url=${local.oauth2_proxy_redis_url}
          - --show-debug-on-error=true
          - --skip-auth-regex=^/(logged-out\\.html|favicon\\.svg)$
          - --pass-access-token=true
          - --pass-user-headers=true
          - --set-xauthrequest=true
          - --set-authorization-header=true
          - --reverse-proxy=true
          - --skip-provider-button=true
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
    kubectl_manifest.oauth2_proxy_session_store_service,
    kubectl_manifest.argocd_app_dex,
    kubectl_manifest.keycloak,
    kubectl_manifest.keycloak_service,
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
          - --provider=oidc
          - --scope=openid email profile groups
          - --oidc-issuer-url=${local.sso_public_url}
          - --profile-url=${local.sso_userinfo_url}
          - --oidc-email-claim=email
          - --oidc-groups-claim=${local.sso_groups_claim}
          - --insecure-oidc-allow-unverified-email=true
          - --user-id-claim=email
          - --skip-oidc-discovery=true
          - --ssl-insecure-skip-verify=true
          - --login-url=${local.sso_login_url}
          - --redeem-url=${local.sso_token_url}
          - --oidc-jwks-url=${local.sso_jwks_url}
          - --redirect-url=${local.subnetcalc_uat_public_url}/oauth2/callback
          - --upstream=http://subnetcalc-router.uat.svc.cluster.local:8080
          - --allowed-group=app-subnetcalc-uat
          - --allowed-group=${local.sso_admin_group}
          - --cookie-domain=${local.uat_cookie_domain}
          - --whitelist-domain=${local.uat_whitelist_domains}
          - --cookie-secure=true
          - --session-store-type=redis
          - --redis-connection-url=${local.oauth2_proxy_redis_url}
          - --show-debug-on-error=true
          - --skip-auth-regex=^/(logged-out\\.html|favicon\\.svg)$
          - --pass-access-token=true
          - --pass-user-headers=true
          - --set-xauthrequest=true
          - --set-authorization-header=true
          - --reverse-proxy=true
          - --skip-provider-button=true
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
    kubectl_manifest.oauth2_proxy_session_store_service,
    kubectl_manifest.argocd_app_dex,
    kubectl_manifest.keycloak,
    kubectl_manifest.keycloak_service,
    # When enable_app_of_apps=true, subnetcalc-uat is managed via the GitOps tree.
    kubectl_manifest.argocd_app_of_apps,
  ]
}

resource "kubectl_manifest" "argocd_app_oauth2_proxy_hello_platform" {
  for_each = var.enable_sso && var.enable_argocd ? local.sso_hello_platform_proxy_apps : {}

  yaml_body = <<__YAML__
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${each.value.name}
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
      releaseName: ${each.value.name}
      values: |
        image:
          registry: ${local.hardened_image_registry_effective}
          repository: oauth2-proxy
          tag: 7.15.2-debian13
        config:
          existingSecret: oauth2-proxy-oidc
          cookieName: ${each.value.cookie_name}
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
          - --provider=oidc
          - --scope=openid email profile groups
          - --oidc-issuer-url=${local.sso_public_url}
          - --profile-url=${local.sso_userinfo_url}
          - --oidc-email-claim=email
          - --oidc-groups-claim=${local.sso_groups_claim}
          - --insecure-oidc-allow-unverified-email=true
          - --user-id-claim=email
          - --skip-oidc-discovery=true
          - --ssl-insecure-skip-verify=true
          - --login-url=${local.sso_login_url}
          - --redeem-url=${local.sso_token_url}
          - --oidc-jwks-url=${local.sso_jwks_url}
          - --redirect-url=${each.value.public_url}/oauth2/callback
          - --upstream=${each.value.upstream}
          - --allowed-group=${each.value.group}
          - --allowed-group=${local.sso_admin_group}
          - --cookie-domain=${each.value.cookie_domain}
          - --whitelist-domain=${each.value.whitelist_domain}
          - --cookie-secure=true
          - --session-store-type=redis
          - --redis-connection-url=${local.oauth2_proxy_redis_url}
          - --show-debug-on-error=true
          - --pass-access-token=true
          - --pass-user-headers=true
          - --set-xauthrequest=true
          - --set-authorization-header=true
          - --reverse-proxy=true
          - --skip-provider-button=true
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
    kubectl_manifest.oauth2_proxy_session_store_service,
    kubectl_manifest.argocd_app_dex,
    kubectl_manifest.keycloak,
    kubectl_manifest.keycloak_service,
    kubectl_manifest.argocd_app_of_apps,
  ]
}

resource "kubectl_manifest" "argocd_app_oauth2_proxy_idp" {
  for_each = var.enable_sso && var.enable_argocd ? local.sso_idp_proxy_apps : {}

  yaml_body = <<__YAML__
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${each.value.name}
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
      releaseName: ${each.value.name}
      values: |
        image:
          registry: ${local.hardened_image_registry_effective}
          repository: oauth2-proxy
          tag: 7.15.2-debian13
        config:
          existingSecret: oauth2-proxy-oidc
          cookieName: ${each.value.cookie_name}
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
          scope: "openid email profile groups"
          oidc-issuer-url: ${local.sso_public_url}
          profile-url: ${local.sso_userinfo_url}
          oidc-email-claim: email
          oidc-groups-claim: ${local.sso_groups_claim}
          insecure-oidc-allow-unverified-email: "true"
          user-id-claim: email
          skip-oidc-discovery: "true"
          ssl-insecure-skip-verify: "true"
          login-url: ${local.sso_login_url}
          redeem-url: ${local.sso_token_url}
          oidc-jwks-url: ${local.sso_jwks_url}
          redirect-url: ${each.value.public_url}/oauth2/callback
          upstream: ${each.value.upstream}
          allowed-group: ${each.value.group}
          cookie-domain: ${each.value.cookie_domain}
          whitelist-domain: ${each.value.whitelist_domain}
          cookie-secure: "true"
          session-store-type: redis
          redis-connection-url: ${local.oauth2_proxy_redis_url}
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
    kubectl_manifest.oauth2_proxy_session_store_service,
    kubectl_manifest.argocd_app_dex,
    kubectl_manifest.keycloak,
    kubectl_manifest.keycloak_service,
    kubectl_manifest.argocd_app_of_apps,
  ]
}

# Note: Legacy direct app definitions removed - using app-of-apps approach
# Apps are now defined in apps/argocd-apps/ (dev, uat, apim)
