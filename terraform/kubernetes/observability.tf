resource "kubernetes_namespace_v1" "observability" {
  count = local.enable_observability_effective ? 1 : 0

  metadata {
    name = "observability"
    annotations = {
      "argocd.argoproj.io/sync-wave" = "80"
    }
    labels = {
      "app.kubernetes.io/managed-by"                       = "argocd"
      "app.kubernetes.io/name"                             = "observability"
      "platform.publiccloudexperiments.net/namespace-role" = "shared"
      "platform.publiccloudexperiments.net/sensitivity"    = "confidential"
      "kyverno.io/isolate"                                 = "true"
    }
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations["argocd.argoproj.io/tracking-id"],
    ]
  }

  depends_on = [
    kind_cluster.local,
    local_sensitive_file.kubeconfig,
  ]
}

resource "kubectl_manifest" "argocd_app_signoz" {
  count = var.enable_signoz && var.enable_argocd && !var.enable_app_of_apps ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: signoz
  namespace: ${var.argocd_namespace}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: observability
    server: https://kubernetes.default.svc
  ignoreDifferences:
    - group: apps
      kind: Deployment
      name: signoz-clickhouse-operator
      jsonPointers:
        - /metadata/annotations
        - /metadata/labels
        - /spec
    - group: apps
      kind: StatefulSet
      name: signoz
      jsonPointers:
        - /metadata/annotations
        - /metadata/labels
        - /spec
  source:
    repoURL: ${local.policies_repo_url_cluster}
    targetRevision: main
    path: ${local.vendored_chart_paths.signoz}
    helm:
      values: |
        clickhouse:
          persistence:
            enabled: false
          resources:
            requests:
              cpu: 250m
              memory: 1Gi
            limits:
              cpu: 1500m
              memory: 2Gi
          zookeeper:
            persistence:
              enabled: false
            resources:
              requests:
                cpu: 25m
                memory: 64Mi
              limits:
                cpu: 100m
                memory: 256Mi

        signoz:
          env:
            signoz_tokenizer_jwt_secret: "local-kind-unsafe-dev-jwt-secret"
          persistence:
            enabled: true
            size: 1Gi
            storageClass: standard
          resources:
            requests:
              cpu: 50m
              memory: 128Mi
            limits:
              cpu: 200m
              memory: 512Mi

        schemaMigrator:
          upgradeHelmHooks: true

        otelCollector:
          resources:
            requests:
              cpu: 25m
              memory: 64Mi
            limits:
              cpu: 100m
              memory: 256Mi
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
    retry:
      limit: 5
      backoff:
        duration: 10s
        factor: 2
        maxDuration: 3m
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
    kubernetes_namespace_v1.observability,
  ]
}

resource "kubectl_manifest" "argocd_app_prometheus" {
  count = local.enable_prometheus_effective && var.enable_argocd && !var.enable_app_of_apps ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: prometheus
  namespace: ${var.argocd_namespace}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: observability
    server: https://kubernetes.default.svc
  source:
    repoURL: ${local.policies_repo_url_cluster}
    targetRevision: main
    path: ${local.vendored_chart_paths.prometheus}
    helm:
      releaseName: prometheus
      values: |
        alertmanager:
          enabled: false
        configmapReload:
          prometheus:
            image:
              repository: ${local.hardened_image_registry_effective}/prometheus-config-reloader
              tag: 0.89.0-debian13
        kube-state-metrics:
          enabled: true
          image:
            registry: ${local.hardened_image_registry_effective}
            repository: kube-state-metrics
            tag: 2.18.0-debian13
          resources:
            requests:
              cpu: 10m
              memory: 48Mi
            limits:
              cpu: 40m
              memory: 96Mi
        prometheus-node-exporter:
          enabled: true
          image:
            registry: ${local.hardened_image_registry_effective}
            repository: node-exporter
            tag: 1.10.2-debian13
          resources:
            requests:
              cpu: 8m
              memory: 16Mi
            limits:
              cpu: 32m
              memory: 48Mi
        prometheus-pushgateway:
          enabled: false
        server:
          image:
            repository: ${local.hardened_image_registry_effective}/prometheus
            tag: ${var.prometheus_image_tag}
          persistentVolume:
            enabled: false
          resources:
            requests:
              cpu: 75m
              memory: 192Mi
            limits:
              cpu: 300m
              memory: 384Mi
          extraFlags:
            - enable-feature=promql-at-modifier
            - enable-feature=extra-scrape-metrics
            - web.enable-lifecycle
            - web.enable-remote-write-receiver
          retention: 4h
        extraScrapeConfigs: |
          - job_name: argocd-metrics
            kubernetes_sd_configs:
              - role: pod
                namespaces:
                  names:
                    - argocd
            relabel_configs:
              - source_labels: [__meta_kubernetes_pod_label_app_kubernetes_io_part_of]
                action: keep
                regex: argocd
              - source_labels: [__meta_kubernetes_pod_container_port_name]
                action: keep
                regex: metrics
              - source_labels: [__meta_kubernetes_pod_phase]
                action: drop
                regex: Pending|Succeeded|Failed|Completed
          - job_name: hubble-metrics
            kubernetes_sd_configs:
              - role: pod
                namespaces:
                  names:
                    - kube-system
            relabel_configs:
              - source_labels: [__meta_kubernetes_pod_label_k8s_app]
                action: keep
                regex: cilium
              - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
                action: keep
                regex: "true"
              - replacement: "9965"
                target_label: __address__
                source_labels: [__address__]
                regex: (.+):\d+
                action: replace
              - replacement: "$1:9965"
                target_label: __address__
                source_labels: [__address__]
                regex: (.+)
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
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
    kubernetes_namespace_v1.observability,
  ]
}

resource "kubectl_manifest" "argocd_app_grafana" {
  count = local.enable_grafana_effective && var.enable_argocd && !var.enable_app_of_apps ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: grafana
  namespace: ${var.argocd_namespace}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: observability
    server: https://kubernetes.default.svc
  source:
    repoURL: ${local.policies_repo_url_cluster}
    targetRevision: main
    path: ${local.vendored_chart_paths.grafana}
    helm:
      releaseName: grafana
      values: |
        image:
          registry: ${local.grafana_image_registry_effective}
          repository: ${local.grafana_image_repository_effective}
          tag: ${local.grafana_image_tag_effective}
        sidecar:
          image:
            registry: ${var.grafana_sidecar_image_registry}
            repository: ${var.grafana_sidecar_image_repository}
            tag: ${var.grafana_sidecar_image_tag}
        admin:
          existingSecret: grafana-admin-credentials
          userKey: admin-user
          passwordKey: admin-password
        persistence:
          enabled: false
        resources:
          requests:
            cpu: 20m
            memory: 48Mi
          limits:
            cpu: 75m
            memory: 192Mi
        extraInitContainers:
          - name: stage-victorialogs-plugin
            image: ${local.grafana_image_registry_effective}/${local.grafana_image_repository_effective}:${local.grafana_image_tag_effective}
            imagePullPolicy: IfNotPresent
            command:
              - /bin/sh
              - -ec
            args:
              - |
                plugin_src=/opt/grafana/plugins/victoriametrics-logs-datasource
                plugin_dst=/var/lib/grafana/plugins/victoriametrics-logs-datasource
                if [ ! -d "$${plugin_src}" ]; then
                  exit 0
                fi
                mkdir -p /var/lib/grafana/plugins
                rm -rf "$${plugin_dst}"
                cp -a "$${plugin_src}" "$${plugin_dst}"
            volumeMounts:
              - name: storage
                mountPath: /var/lib/grafana
        env:
          TMPDIR: /var/lib/grafana
${local.grafana_plugins_values_yaml}
        livenessProbe:
          initialDelaySeconds: ${var.grafana_liveness_initial_delay_seconds}
        service:
          type: ClusterIP
          port: 3000
        grafana.ini:
          server:
            root_url: ${local.grafana_public_url}
          dashboards:
            default_home_dashboard_path: /var/lib/grafana/dashboards/default/platform-launchpad.json
          auth:
            disable_login_form: true
          auth.proxy:
            enabled: true
            # oauth2-proxy forwards the stable user email separately from the opaque OIDC subject.
            # Use the email header so Grafana keys auth-proxy users consistently.
            header_name: X-Forwarded-Email
            header_property: email
            auto_sign_up: true
        dashboardProviders:
          dashboardproviders.yaml:
            apiVersion: 1
            providers:
              - name: default
                orgId: 1
                folder: Platform
                type: file
                disableDeletion: false
                editable: true
                options:
                  path: /var/lib/grafana/dashboards/default
        datasources:
          datasources.yaml:
            apiVersion: 1
            datasources:
              - name: Prometheus
                type: prometheus
                access: proxy
                url: http://prometheus-server.observability.svc.cluster.local
                isDefault: true
              - name: VictoriaLogs
                type: victoriametrics-logs-datasource
                access: proxy
                url: http://victoria-logs-victoria-logs-single-server.observability.svc.cluster.local:9428
                uid: victorialogs
                jsonData:
                  maxLines: 1000
              - name: Loki
                type: loki
                access: proxy
                url: http://loki.observability.svc.cluster.local:3100
                uid: loki
                jsonData:
                  maxLines: 1000
        dashboards:
          default:
            # codex:platform-launchpad:start
            platform-launchpad:
              json: |
                {
                  "annotations": {
                    "list": []
                  },
                  "editable": true,
                  "graphTooltip": 0,
                  "panels": [
                    {
                      "gridPos": {
                        "h": 3,
                        "w": 24,
                        "x": 0,
                        "y": 0
                      },
                      "id": 1,
                      "options": {
                        "content": "## Platform Launchpad\nClick a tile to open the app or dashboard URL. Health uses deployment readiness with Argo CD fallback where possible.",
                        "mode": "markdown"
                      },
                      "title": "Entry Points",
                      "type": "text"
                    },
                    {
                      "datasource": "Prometheus",
                      "description": "${local.grafana_public_url}/d/platform-app-overview/platform-app-golden-signals",
                      "fieldConfig": {
                        "defaults": {
                          "color": {
                            "mode": "thresholds"
                          },
                          "mappings": [
                            {
                              "options": {
                                "0": {
                                  "text": "Down"
                                },
                                "1": {
                                  "text": "Healthy"
                                }
                              },
                              "type": "value"
                            }
                          ],
                          "max": 1,
                          "min": 0,
                          "thresholds": {
                            "mode": "absolute",
                            "steps": [
                              {
                                "color": "red",
                                "value": 0
                              },
                              {
                                "color": "green",
                                "value": 1
                              }
                            ]
                          },
                          "unit": "short"
                        }
                      },
                      "gridPos": {
                        "h": 5,
                        "w": 6,
                        "x": 0,
                        "y": 3
                      },
                      "id": 2,
                      "links": [
                        {
                          "targetBlank": true,
                          "title": "Open Platform App Golden Signals",
                          "url": "${local.grafana_public_url}/d/platform-app-overview/platform-app-golden-signals"
                        }
                      ],
                      "options": {
                        "colorMode": "background",
                        "graphMode": "none"
                      },
                      "targets": [
                        {
                          "expr": "((max(kube_deployment_status_replicas_available{namespace=\"observability\",deployment=\"grafana\"}) > bool 0) or max(argocd_app_info{name=\"grafana\",health_status=\"Healthy\",sync_status=\"Synced\"}) or vector(0))",
                          "refId": "A"
                        }
                      ],
                      "title": "Platform App Golden Signals",
                      "type": "stat"
                    },
                    {
                      "datasource": "Prometheus",
                      "description": "${local.grafana_public_url}/d/platform-namespace-health/platform-namespace-health",
                      "fieldConfig": {
                        "defaults": {
                          "color": {
                            "mode": "thresholds"
                          },
                          "mappings": [
                            {
                              "options": {
                                "0": {
                                  "text": "Down"
                                },
                                "1": {
                                  "text": "Healthy"
                                }
                              },
                              "type": "value"
                            }
                          ],
                          "max": 1,
                          "min": 0,
                          "thresholds": {
                            "mode": "absolute",
                            "steps": [
                              {
                                "color": "red",
                                "value": 0
                              },
                              {
                                "color": "green",
                                "value": 1
                              }
                            ]
                          },
                          "unit": "short"
                        }
                      },
                      "gridPos": {
                        "h": 5,
                        "w": 6,
                        "x": 6,
                        "y": 3
                      },
                      "id": 3,
                      "links": [
                        {
                          "targetBlank": true,
                          "title": "Open Platform Namespace Health",
                          "url": "${local.grafana_public_url}/d/platform-namespace-health/platform-namespace-health"
                        }
                      ],
                      "options": {
                        "colorMode": "background",
                        "graphMode": "none"
                      },
                      "targets": [
                        {
                          "expr": "((max(kube_deployment_status_replicas_available{namespace=\"observability\",deployment=\"grafana\"}) > bool 0) or max(argocd_app_info{name=\"grafana\",health_status=\"Healthy\",sync_status=\"Synced\"}) or vector(0))",
                          "refId": "A"
                        }
                      ],
                      "title": "Platform Namespace Health",
                      "type": "stat"
                    },
                    {
                      "datasource": "Prometheus",
                      "description": "${local.argocd_public_url}",
                      "fieldConfig": {
                        "defaults": {
                          "color": {
                            "mode": "thresholds"
                          },
                          "mappings": [
                            {
                              "options": {
                                "0": {
                                  "text": "Down"
                                },
                                "1": {
                                  "text": "Healthy"
                                }
                              },
                              "type": "value"
                            }
                          ],
                          "max": 1,
                          "min": 0,
                          "thresholds": {
                            "mode": "absolute",
                            "steps": [
                              {
                                "color": "red",
                                "value": 0
                              },
                              {
                                "color": "green",
                                "value": 1
                              }
                            ]
                          },
                          "unit": "short"
                        }
                      },
                      "gridPos": {
                        "h": 5,
                        "w": 6,
                        "x": 12,
                        "y": 3
                      },
                      "id": 4,
                      "links": [
                        {
                          "targetBlank": true,
                          "title": "Open Argo CD",
                          "url": "${local.argocd_public_url}"
                        }
                      ],
                      "options": {
                        "colorMode": "background",
                        "graphMode": "none"
                      },
                      "targets": [
                        {
                          "expr": "((max(kube_deployment_status_replicas_available{namespace=\"argocd\",deployment=\"argocd-server\"}) > bool 0) or (sum(argocd_app_info{health_status=\"Healthy\"}) > bool 0) or vector(0))",
                          "refId": "A"
                        }
                      ],
                      "title": "Argo CD",
                      "type": "stat"
                    },
                    {
                      "datasource": "Prometheus",
                      "description": "${local.dex_public_url}",
                      "fieldConfig": {
                        "defaults": {
                          "color": {
                            "mode": "thresholds"
                          },
                          "mappings": [
                            {
                              "options": {
                                "0": {
                                  "text": "Down"
                                },
                                "1": {
                                  "text": "Healthy"
                                }
                              },
                              "type": "value"
                            }
                          ],
                          "max": 1,
                          "min": 0,
                          "thresholds": {
                            "mode": "absolute",
                            "steps": [
                              {
                                "color": "red",
                                "value": 0
                              },
                              {
                                "color": "green",
                                "value": 1
                              }
                            ]
                          },
                          "unit": "short"
                        }
                      },
                      "gridPos": {
                        "h": 5,
                        "w": 6,
                        "x": 18,
                        "y": 3
                      },
                      "id": 5,
                      "links": [
                        {
                          "targetBlank": true,
                          "title": "Open Dex",
                          "url": "${local.dex_public_url}"
                        }
                      ],
                      "options": {
                        "colorMode": "background",
                        "graphMode": "none"
                      },
                      "targets": [
                        {
                          "expr": "((max(kube_deployment_status_replicas_available{namespace=\"sso\",deployment=\"dex\"}) > bool 0) or vector(0))",
                          "refId": "A"
                        }
                      ],
                      "title": "Dex",
                      "type": "stat"
                    },
                    {
                      "datasource": "Prometheus",
                      "description": "${local.gitea_public_url}",
                      "fieldConfig": {
                        "defaults": {
                          "color": {
                            "mode": "thresholds"
                          },
                          "mappings": [
                            {
                              "options": {
                                "0": {
                                  "text": "Down"
                                },
                                "1": {
                                  "text": "Healthy"
                                }
                              },
                              "type": "value"
                            }
                          ],
                          "max": 1,
                          "min": 0,
                          "thresholds": {
                            "mode": "absolute",
                            "steps": [
                              {
                                "color": "red",
                                "value": 0
                              },
                              {
                                "color": "green",
                                "value": 1
                              }
                            ]
                          },
                          "unit": "short"
                        }
                      },
                      "gridPos": {
                        "h": 5,
                        "w": 6,
                        "x": 0,
                        "y": 8
                      },
                      "id": 6,
                      "links": [
                        {
                          "targetBlank": true,
                          "title": "Open Gitea",
                          "url": "${local.gitea_public_url}"
                        }
                      ],
                      "options": {
                        "colorMode": "background",
                        "graphMode": "none"
                      },
                      "targets": [
                        {
                          "expr": "((max(kube_deployment_status_replicas_available{namespace=\"gitea\",deployment=\"gitea\"}) > bool 0) or max(argocd_app_info{name=\"gitea\",health_status=\"Healthy\",sync_status=\"Synced\"}) or vector(0))",
                          "refId": "A"
                        }
                      ],
                      "title": "Gitea",
                      "type": "stat"
                    },
                    {
                      "datasource": "Prometheus",
                      "description": "${local.headlamp_public_url}",
                      "fieldConfig": {
                        "defaults": {
                          "color": {
                            "mode": "thresholds"
                          },
                          "mappings": [
                            {
                              "options": {
                                "0": {
                                  "text": "Down"
                                },
                                "1": {
                                  "text": "Healthy"
                                }
                              },
                              "type": "value"
                            }
                          ],
                          "max": 1,
                          "min": 0,
                          "thresholds": {
                            "mode": "absolute",
                            "steps": [
                              {
                                "color": "red",
                                "value": 0
                              },
                              {
                                "color": "green",
                                "value": 1
                              }
                            ]
                          },
                          "unit": "short"
                        }
                      },
                      "gridPos": {
                        "h": 5,
                        "w": 6,
                        "x": 6,
                        "y": 8
                      },
                      "id": 7,
                      "links": [
                        {
                          "targetBlank": true,
                          "title": "Open Headlamp",
                          "url": "${local.headlamp_public_url}"
                        }
                      ],
                      "options": {
                        "colorMode": "background",
                        "graphMode": "none"
                      },
                      "targets": [
                        {
                          "expr": "((max(kube_deployment_status_replicas_available{namespace=\"headlamp\",deployment=\"headlamp\"}) > bool 0) or max(argocd_app_info{name=\"headlamp\",health_status=\"Healthy\",sync_status=\"Synced\"}) or max(argocd_app_info{name=\"platform-gateway-routes\",health_status=\"Healthy\",sync_status=\"Synced\"}) or vector(0))",
                          "refId": "A"
                        }
                      ],
                      "title": "Headlamp",
                      "type": "stat"
                    },
                    {
                      "datasource": "Prometheus",
                      "description": "${local.hubble_public_url}",
                      "fieldConfig": {
                        "defaults": {
                          "color": {
                            "mode": "thresholds"
                          },
                          "mappings": [
                            {
                              "options": {
                                "0": {
                                  "text": "Down"
                                },
                                "1": {
                                  "text": "Healthy"
                                }
                              },
                              "type": "value"
                            }
                          ],
                          "max": 1,
                          "min": 0,
                          "thresholds": {
                            "mode": "absolute",
                            "steps": [
                              {
                                "color": "red",
                                "value": 0
                              },
                              {
                                "color": "green",
                                "value": 1
                              }
                            ]
                          },
                          "unit": "short"
                        }
                      },
                      "gridPos": {
                        "h": 5,
                        "w": 6,
                        "x": 12,
                        "y": 8
                      },
                      "id": 8,
                      "links": [
                        {
                          "targetBlank": true,
                          "title": "Open Hubble",
                          "url": "${local.hubble_public_url}"
                        }
                      ],
                      "options": {
                        "colorMode": "background",
                        "graphMode": "none"
                      },
                      "targets": [
                        {
                          "expr": "((max(kube_deployment_status_replicas_available{namespace=\"sso\",deployment=\"oauth2-proxy-hubble\"}) > bool 0) or max(argocd_app_info{name=\"platform-gateway-routes\",health_status=\"Healthy\",sync_status=\"Synced\"}) or vector(0))",
                          "refId": "A"
                        }
                      ],
                      "title": "Hubble",
                      "type": "stat"
                    },
                    {
                      "datasource": "Prometheus",
                      "description": "${local.kyverno_public_url}/",
                      "fieldConfig": {
                        "defaults": {
                          "color": {
                            "mode": "thresholds"
                          },
                          "mappings": [
                            {
                              "options": {
                                "0": {
                                  "text": "Down"
                                },
                                "1": {
                                  "text": "Healthy"
                                }
                              },
                              "type": "value"
                            }
                          ],
                          "max": 1,
                          "min": 0,
                          "thresholds": {
                            "mode": "absolute",
                            "steps": [
                              {
                                "color": "red",
                                "value": 0
                              },
                              {
                                "color": "green",
                                "value": 1
                              }
                            ]
                          },
                          "unit": "short"
                        }
                      },
                      "gridPos": {
                        "h": 5,
                        "w": 6,
                        "x": 18,
                        "y": 8
                      },
                      "id": 9,
                      "links": [
                        {
                          "targetBlank": true,
                          "title": "Open Kyverno Policy UI",
                          "url": "${local.kyverno_public_url}/"
                        }
                      ],
                      "options": {
                        "colorMode": "background",
                        "graphMode": "none"
                      },
                      "targets": [
                        {
                          "expr": "((max(kube_deployment_status_replicas_available{namespace=\"policy-reporter\",deployment=~\"policy-reporter|policy-reporter-ui\"}) > bool 0) or max(argocd_app_info{name=\"policy-reporter\",health_status=\"Healthy\",sync_status=\"Synced\"}) or vector(0))",
                          "refId": "A"
                        }
                      ],
                      "title": "Kyverno Policy UI",
                      "type": "stat"
                    },
                    {
                      "datasource": "Prometheus",
                      "description": "${local.sentiment_dev_public_url}",
                      "fieldConfig": {
                        "defaults": {
                          "color": {
                            "mode": "thresholds"
                          },
                          "mappings": [
                            {
                              "options": {
                                "0": {
                                  "text": "Down"
                                },
                                "1": {
                                  "text": "Healthy"
                                }
                              },
                              "type": "value"
                            }
                          ],
                          "max": 1,
                          "min": 0,
                          "thresholds": {
                            "mode": "absolute",
                            "steps": [
                              {
                                "color": "red",
                                "value": 0
                              },
                              {
                                "color": "green",
                                "value": 1
                              }
                            ]
                          },
                          "unit": "short"
                        }
                      },
                      "gridPos": {
                        "h": 5,
                        "w": 6,
                        "x": 0,
                        "y": 13
                      },
                      "id": 10,
                      "links": [
                        {
                          "targetBlank": true,
                          "title": "Open Sentiment DEV",
                          "url": "${local.sentiment_dev_public_url}"
                        }
                      ],
                      "options": {
                        "colorMode": "background",
                        "graphMode": "none"
                      },
                      "targets": [
                        {
                          "expr": "(((max(kube_deployment_status_replicas_available{namespace=\"sso\",deployment=\"oauth2-proxy-sentiment-dev\"}) > bool 0) * (max(kube_deployment_status_replicas_available{namespace=\"dev\",deployment=\"sentiment-router\"}) > bool 0) * (max(kube_deployment_status_replicas_available{namespace=\"dev\",deployment=\"sentiment-auth-ui\"}) > bool 0)) or vector(0))",
                          "refId": "A"
                        }
                      ],
                      "title": "Sentiment DEV",
                      "type": "stat"
                    },
                    {
                      "datasource": "Prometheus",
                      "description": "${local.subnetcalc_dev_public_url}",
                      "fieldConfig": {
                        "defaults": {
                          "color": {
                            "mode": "thresholds"
                          },
                          "mappings": [
                            {
                              "options": {
                                "0": {
                                  "text": "Down"
                                },
                                "1": {
                                  "text": "Healthy"
                                }
                              },
                              "type": "value"
                            }
                          ],
                          "max": 1,
                          "min": 0,
                          "thresholds": {
                            "mode": "absolute",
                            "steps": [
                              {
                                "color": "red",
                                "value": 0
                              },
                              {
                                "color": "green",
                                "value": 1
                              }
                            ]
                          },
                          "unit": "short"
                        }
                      },
                      "gridPos": {
                        "h": 5,
                        "w": 6,
                        "x": 6,
                        "y": 13
                      },
                      "id": 11,
                      "links": [
                        {
                          "targetBlank": true,
                          "title": "Open SubnetCalc DEV",
                          "url": "${local.subnetcalc_dev_public_url}"
                        }
                      ],
                      "options": {
                        "colorMode": "background",
                        "graphMode": "none"
                      },
                      "targets": [
                        {
                          "expr": "(((max(kube_deployment_status_replicas_available{namespace=\"sso\",deployment=\"oauth2-proxy-subnetcalc-dev\"}) > bool 0) * (max(kube_deployment_status_replicas_available{namespace=\"dev\",deployment=\"subnetcalc-router\"}) > bool 0) * (max(kube_deployment_status_replicas_available{namespace=\"dev\",deployment=\"subnetcalc-frontend\"}) > bool 0)) or vector(0))",
                          "refId": "A"
                        }
                      ],
                      "title": "SubnetCalc DEV",
                      "type": "stat"
                    },
                    {
                      "datasource": "Prometheus",
                      "description": "${local.sentiment_uat_public_url}",
                      "fieldConfig": {
                        "defaults": {
                          "color": {
                            "mode": "thresholds"
                          },
                          "mappings": [
                            {
                              "options": {
                                "0": {
                                  "text": "Down"
                                },
                                "1": {
                                  "text": "Healthy"
                                }
                              },
                              "type": "value"
                            }
                          ],
                          "max": 1,
                          "min": 0,
                          "thresholds": {
                            "mode": "absolute",
                            "steps": [
                              {
                                "color": "red",
                                "value": 0
                              },
                              {
                                "color": "green",
                                "value": 1
                              }
                            ]
                          },
                          "unit": "short"
                        }
                      },
                      "gridPos": {
                        "h": 5,
                        "w": 6,
                        "x": 12,
                        "y": 13
                      },
                      "id": 12,
                      "links": [
                        {
                          "targetBlank": true,
                          "title": "Open Sentiment UAT",
                          "url": "${local.sentiment_uat_public_url}"
                        }
                      ],
                      "options": {
                        "colorMode": "background",
                        "graphMode": "none"
                      },
                      "targets": [
                        {
                          "expr": "(((max(kube_deployment_status_replicas_available{namespace=\"sso\",deployment=\"oauth2-proxy-sentiment-uat\"}) > bool 0) * (max(kube_deployment_status_replicas_available{namespace=\"uat\",deployment=\"sentiment-router\"}) > bool 0) * (max(kube_deployment_status_replicas_available{namespace=\"uat\",deployment=\"sentiment-auth-ui\"}) > bool 0)) or vector(0))",
                          "refId": "A"
                        }
                      ],
                      "title": "Sentiment UAT",
                      "type": "stat"
                    },
                    {
                      "datasource": "Prometheus",
                      "description": "${local.subnetcalc_uat_public_url}",
                      "fieldConfig": {
                        "defaults": {
                          "color": {
                            "mode": "thresholds"
                          },
                          "mappings": [
                            {
                              "options": {
                                "0": {
                                  "text": "Down"
                                },
                                "1": {
                                  "text": "Healthy"
                                }
                              },
                              "type": "value"
                            }
                          ],
                          "max": 1,
                          "min": 0,
                          "thresholds": {
                            "mode": "absolute",
                            "steps": [
                              {
                                "color": "red",
                                "value": 0
                              },
                              {
                                "color": "green",
                                "value": 1
                              }
                            ]
                          },
                          "unit": "short"
                        }
                      },
                      "gridPos": {
                        "h": 5,
                        "w": 6,
                        "x": 18,
                        "y": 13
                      },
                      "id": 13,
                      "links": [
                        {
                          "targetBlank": true,
                          "title": "Open SubnetCalc UAT",
                          "url": "${local.subnetcalc_uat_public_url}"
                        }
                      ],
                      "options": {
                        "colorMode": "background",
                        "graphMode": "none"
                      },
                      "targets": [
                        {
                          "expr": "(((max(kube_deployment_status_replicas_available{namespace=\"sso\",deployment=\"oauth2-proxy-subnetcalc-uat\"}) > bool 0) * (max(kube_deployment_status_replicas_available{namespace=\"uat\",deployment=\"subnetcalc-router\"}) > bool 0) * (max(kube_deployment_status_replicas_available{namespace=\"uat\",deployment=\"subnetcalc-frontend\"}) > bool 0)) or vector(0))",
                          "refId": "A"
                        }
                      ],
                      "title": "SubnetCalc UAT",
                      "type": "stat"
                    }
                  ],
                  "refresh": "30s",
                  "schemaVersion": 39,
                  "tags": [
                    "platform",
                    "launchpad",
                    "entrypoints"
                  ],
                  "templating": {
                    "list": [
                      {
                        "name": "prometheus",
                        "type": "datasource",
                        "query": "prometheus",
                        "current": {
                          "selected": false,
                          "value": "Prometheus"
                        }
                      }
                    ]
                  },
                  "time": {
                    "from": "now-15m",
                    "to": "now"
                  },
                  "title": "Platform Launchpad",
                  "uid": "platform-launchpad"
                }
            # codex:platform-launchpad:end
            platform-overview:
              json: |
                {
                  "annotations": {"list": []},
                  "editable": true,
                  "graphTooltip": 0,
                  "panels": [
                    {
                      "datasource": "Prometheus",
                      "fieldConfig": {"defaults": {"unit": "reqps"}, "overrides": []},
                      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
                      "id": 1,
                      "targets": [
                        {
                          "expr": "sum(rate(traces_span_metrics_calls_total{service_name=~\"sentiment-api|subnetcalc-api\",k8s_namespace_name=~\"dev|uat\"}[5m])) by (k8s_namespace_name,service_name)",
                          "legendFormat": "{{k8s_namespace_name}}/{{service_name}}",
                          "refId": "A"
                        }
                      ],
                      "title": "Request rate (rps)",
                      "type": "timeseries"
                    },
                    {
                      "datasource": "Prometheus",
                      "fieldConfig": {"defaults": {"unit": "percent"}, "overrides": []},
                      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0},
                      "id": 2,
                      "targets": [
                        {
                          "expr": "100 * (sum(rate(traces_span_metrics_calls_total{service_name=~\"sentiment-api|subnetcalc-api\",k8s_namespace_name=~\"dev|uat\",http_status_code=~\"4..|5..\"}[5m])) by (k8s_namespace_name,service_name) / clamp_min(sum(rate(traces_span_metrics_calls_total{service_name=~\"sentiment-api|subnetcalc-api\",k8s_namespace_name=~\"dev|uat\"}[5m])) by (k8s_namespace_name,service_name), 0.0001))",
                          "legendFormat": "{{k8s_namespace_name}}/{{service_name}}",
                          "refId": "A"
                        }
                      ],
                      "title": "Error rate (%)",
                      "type": "timeseries"
                    },
                    {
                      "datasource": "Prometheus",
                      "fieldConfig": {"defaults": {"unit": "ms"}, "overrides": []},
                      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
                      "id": 3,
                      "targets": [
                        {
                          "expr": "histogram_quantile(0.95, sum(rate(traces_span_metrics_duration_milliseconds_bucket{service_name=~\"sentiment-api|subnetcalc-api\",k8s_namespace_name=~\"dev|uat\"}[5m])) by (le,k8s_namespace_name,service_name))",
                          "legendFormat": "{{k8s_namespace_name}}/{{service_name}}",
                          "refId": "A"
                        }
                      ],
                      "title": "Latency p95 (ms)",
                      "type": "timeseries"
                    },
                    {
                      "datasource": "Prometheus",
                      "fieldConfig": {"defaults": {"unit": "short"}, "overrides": []},
                      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8},
                      "id": 4,
                      "targets": [
                        {
                          "expr": "sum(increase(sentiment_comments_created_total{k8s_namespace_name=~\"dev|uat\"}[1h])) by (k8s_namespace_name)",
                          "legendFormat": "{{k8s_namespace_name}}",
                          "refId": "A"
                        }
                      ],
                      "title": "Sentiment comments (last 1h)",
                      "type": "timeseries"
                    },
                    {
                      "datasource": "Prometheus",
                      "fieldConfig": {"defaults": {"unit": "ms"}, "overrides": []},
                      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 16},
                      "id": 5,
                      "targets": [
                        {
                          "expr": "histogram_quantile(0.95, sum(rate(llm_inference_latency_ms_bucket{k8s_namespace_name=~\"dev|uat\"}[5m])) by (le,k8s_namespace_name))",
                          "legendFormat": "{{k8s_namespace_name}}",
                          "refId": "A"
                        }
                      ],
                      "title": "LLM inference p95 (ms)",
                      "type": "timeseries"
                    },
                    {
                      "datasource": "Prometheus",
                      "fieldConfig": {"defaults": {"unit": "percentunit", "min": 0, "max": 1}, "overrides": []},
                      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 16},
                      "id": 6,
                      "targets": [
                        {
                          "expr": "avg(up{service=\"otel-collector\"})",
                          "refId": "A"
                        }
                      ],
                      "title": "Collector scrape availability",
                      "type": "stat"
                    }
                  ],
                  "refresh": "30s",
                  "schemaVersion": 39,
                  "tags": ["platform", "otel", "dev", "uat"],
                  "templating": {"list": []},
                  "time": {"from": "now-6h", "to": "now"},
                  "title": "Platform App Golden Signals",
                  "uid": "platform-app-overview",
                  "version": 1
                }
            platform-namespace-health:
              json: |
                {
                  "annotations": {"list": []},
                  "editable": true,
                  "graphTooltip": 0,
                  "panels": [
                    {
                      "datasource": "Prometheus",
                      "fieldConfig": {"defaults": {"unit": "cores"}, "overrides": []},
                      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
                      "id": 1,
                      "targets": [
                        {
                          "expr": "sum(rate(container_cpu_usage_seconds_total{namespace=~\"dev|uat\",container!=\"\",image!=\"\"}[5m])) by (namespace)",
                          "legendFormat": "{{namespace}}",
                          "refId": "A"
                        }
                      ],
                      "title": "CPU usage by namespace",
                      "type": "timeseries"
                    },
                    {
                      "datasource": "Prometheus",
                      "fieldConfig": {"defaults": {"unit": "bytes"}, "overrides": []},
                      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0},
                      "id": 2,
                      "targets": [
                        {
                          "expr": "sum(container_memory_working_set_bytes{namespace=~\"dev|uat\",container!=\"\",image!=\"\"}) by (namespace)",
                          "legendFormat": "{{namespace}}",
                          "refId": "A"
                        }
                      ],
                      "title": "Memory working set by namespace",
                      "type": "timeseries"
                    },
                    {
                      "datasource": "Prometheus",
                      "fieldConfig": {"defaults": {"unit": "Bps"}, "overrides": []},
                      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
                      "id": 3,
                      "targets": [
                        {
                          "expr": "sum(rate(container_network_receive_bytes_total{namespace=~\"dev|uat\"}[5m])) by (namespace)",
                          "legendFormat": "{{namespace}} rx",
                          "refId": "A"
                        },
                        {
                          "expr": "sum(rate(container_network_transmit_bytes_total{namespace=~\"dev|uat\"}[5m])) by (namespace)",
                          "legendFormat": "{{namespace}} tx",
                          "refId": "B"
                        }
                      ],
                      "title": "Network throughput by namespace",
                      "type": "timeseries"
                    },
                    {
                      "datasource": "Prometheus",
                      "fieldConfig": {"defaults": {"unit": "short"}, "overrides": []},
                      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8},
                      "id": 4,
                      "targets": [
                        {
                          "expr": "count(up{job=\"kubernetes-pods\",namespace=~\"dev|uat\"} == 1) by (namespace)",
                          "legendFormat": "{{namespace}}",
                          "refId": "A"
                        }
                      ],
                      "title": "Scraped pods up",
                      "type": "timeseries"
                    }
                  ],
                  "refresh": "30s",
                  "schemaVersion": 39,
                  "tags": ["platform", "kubernetes", "dev", "uat"],
                  "templating": {"list": []},
                  "time": {"from": "now-6h", "to": "now"},
                  "title": "Platform Namespace Health",
                  "uid": "platform-namespace-health",
                  "version": 1
                }
            platform-logs:
              json: |
                {
                  "annotations": {"list": []},
                  "editable": true,
                  "graphTooltip": 1,
                  "panels": [
                    {
                      "datasource": {"type": "victoriametrics-logs-datasource", "uid": "victorialogs"},
                      "fieldConfig": {"defaults": {"unit": "short"}, "overrides": []},
                      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
                      "id": 1,
                      "options": {"legend": {"displayMode": "list", "placement": "bottom"}},
                      "targets": [
                        {
                          "datasource": {"type": "victoriametrics-logs-datasource", "uid": "victorialogs"},
                          "expr": "* | stats by (k8s.namespace.name) count() logs_total",
                          "legendFormat": "{{k8s.namespace.name}}",
                          "queryType": "statsRange",
                          "refId": "A",
                          "step": "1m"
                        }
                      ],
                      "title": "Logs by Namespace",
                      "type": "timeseries"
                    },
                    {
                      "datasource": {"type": "victoriametrics-logs-datasource", "uid": "victorialogs"},
                      "fieldConfig": {"defaults": {"unit": "short"}, "overrides": []},
                      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 0},
                      "id": 2,
                      "options": {"legend": {"displayMode": "list", "placement": "bottom"}},
                      "targets": [
                        {
                          "datasource": {"type": "victoriametrics-logs-datasource", "uid": "victorialogs"},
                          "expr": "error | stats by (k8s.namespace.name) count() error_logs",
                          "legendFormat": "{{k8s.namespace.name}}",
                          "queryType": "statsRange",
                          "refId": "A",
                          "step": "1m"
                        }
                      ],
                      "title": "Error Logs by Namespace",
                      "type": "timeseries"
                    },
                    {
                      "datasource": {"type": "victoriametrics-logs-datasource", "uid": "victorialogs"},
                      "gridPos": {"h": 12, "w": 24, "x": 0, "y": 8},
                      "id": 3,
                      "options": {
                        "dedupStrategy": "none",
                        "enableLogDetails": true,
                        "prettifyLogMessage": false,
                        "showCommonLabels": false,
                        "showLabels": true,
                        "showTime": true,
                        "sortOrder": "Descending",
                        "wrapLogMessage": true
                      },
                      "targets": [
                        {
                          "datasource": {"type": "victoriametrics-logs-datasource", "uid": "victorialogs"},
                          "expr": "error",
                          "maxLines": 100,
                          "queryType": "instant",
                          "refId": "A"
                        }
                      ],
                      "title": "Recent Error Logs",
                      "type": "logs"
                    }
                  ],
                  "refresh": "30s",
                  "schemaVersion": 39,
                  "tags": ["platform", "logs", "victorialogs"],
                  "templating": {"list": []},
                  "time": {"from": "now-6h", "to": "now"},
                  "title": "Platform Logs",
                  "uid": "platform-logs",
                  "version": 1
                }
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
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
    kubernetes_namespace_v1.observability,
    kubectl_manifest.argocd_app_prometheus,
  ]
}

resource "kubernetes_secret_v1" "grafana_admin_credentials" {
  count = local.enable_grafana_effective ? 1 : 0

  metadata {
    name      = "grafana-admin-credentials"
    namespace = "observability"
  }

  type = "Opaque"

  data = {
    "admin-user"     = "admin"
    "admin-password" = var.gitea_admin_pwd
  }

  depends_on = [
    kubernetes_namespace_v1.observability,
  ]
}

resource "kubectl_manifest" "argocd_app_otel_collector_prometheus" {
  count = local.enable_otel_gateway_effective && var.enable_argocd && !var.enable_app_of_apps ? 1 : 0

  yaml_body = templatefile("${path.module}/templates/argocd-app-otel-gateway.yaml.tftpl", {
    argocd_namespace                      = var.argocd_namespace
    policies_repo_url_cluster             = local.policies_repo_url_cluster
    opentelemetry_collector_chart_path    = local.vendored_chart_paths.opentelemetry_collector
    opentelemetry_collector_chart_version = var.opentelemetry_collector_chart_version
    enable_prometheus_fanout              = local.enable_prometheus_effective || local.enable_grafana_effective
    enable_signoz_fanout                  = var.enable_signoz
    enable_loki_fanout                    = local.enable_loki_effective
    enable_victoria_logs_fanout           = local.enable_victoria_logs_effective
    enable_tempo_fanout                   = local.enable_tempo_effective
  })

  wait              = true
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = false

  depends_on = [
    helm_release.argocd,
    kubernetes_secret_v1.argocd_repo_policies,
    null_resource.sync_gitea_policies_repo,
    null_resource.argocd_repo_server_restart,
    kubernetes_namespace_v1.observability,
  ]
}

resource "kubectl_manifest" "argocd_app_loki" {
  count = local.enable_loki_effective && var.enable_argocd && !var.enable_app_of_apps ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: loki
  namespace: ${var.argocd_namespace}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: observability
    server: https://kubernetes.default.svc
  source:
    repoURL: ${local.policies_repo_url_cluster}
    targetRevision: main
    path: ${local.vendored_chart_paths.loki}
    helm:
      releaseName: loki
      values: |
        deploymentMode: SingleBinary

        loki:
          image:
            registry: ${local.hardened_image_registry_effective}
            repository: loki
            tag: ${var.loki_image_tag}
          auth_enabled: false
          containerSecurityContext:
            readOnlyRootFilesystem: false
          commonConfig:
            path_prefix: /tmp/loki
            replication_factor: 1
          storage:
            type: filesystem
            filesystem:
              chunks_directory: /tmp/loki/chunks
              rules_directory: /tmp/loki/rules
          rulerConfig:
            wal:
              dir: /tmp/loki/ruler-wal
          schemaConfig:
            configs:
              - from: 2024-01-01
                store: tsdb
                object_store: filesystem
                schema: v13
                index:
                  prefix: loki_index_
                  period: 24h
          limits_config:
            retention_period: 24h
            max_query_length: 0
            max_query_parallelism: 8

        singleBinary:
          replicas: 1
          persistence:
            enabled: false
          resources:
            requests:
              cpu: 50m
              memory: 96Mi
            limits:
              cpu: 150m
              memory: 384Mi

        sidecar:
          image:
            repository: ${local.hardened_image_registry_effective}/k8s-sidecar
            tag: 2.5.1-debian13

        gateway:
          enabled: false

        lokiCanary:
          enabled: false

        chunksCache:
          enabled: false
        resultsCache:
          enabled: false

        backend:
          replicas: 0
        read:
          replicas: 0
        write:
          replicas: 0

        monitoring:
          selfMonitoring:
            enabled: false
            grafanaAgent:
              installOperator: false

        test:
          enabled: false
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
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
    kubernetes_namespace_v1.observability,
  ]
}

resource "kubectl_manifest" "argocd_app_victoria_logs" {
  count = local.enable_victoria_logs_effective && var.enable_argocd && !var.enable_app_of_apps ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: victoria-logs
  namespace: ${var.argocd_namespace}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: observability
    server: https://kubernetes.default.svc
  source:
    repoURL: ${local.policies_repo_url_cluster}
    targetRevision: main
    path: ${local.vendored_chart_paths.victoria_logs}
    helm:
      releaseName: victoria-logs
      values: |
        server:
          retentionPeriod: 1d
          persistentVolume:
            enabled: false
          resources:
            requests:
              cpu: 25m
              memory: 64Mi
            limits:
              cpu: 150m
              memory: 256Mi
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
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
    kubernetes_namespace_v1.observability,
  ]
}

resource "kubectl_manifest" "argocd_app_tempo" {
  count = local.enable_tempo_effective && var.enable_argocd && !var.enable_app_of_apps ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: tempo
  namespace: ${var.argocd_namespace}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: observability
    server: https://kubernetes.default.svc
  source:
    repoURL: ${local.policies_repo_url_cluster}
    targetRevision: main
    path: ${local.vendored_chart_paths.tempo}
    helm:
      releaseName: tempo
      values: |
        tempo:
          image:
            repository: ${local.hardened_image_registry_effective}/tempo
            tag: 2.10.1-debian13
          memBallastSizeMbs: 0
          storage:
            trace:
              backend: local
              local:
                path: /var/tempo/traces
              wal:
                path: /var/tempo/wal
          retention: 24h
          resources:
            requests:
              cpu: 25m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi

        persistence:
          enabled: false

        serviceMonitor:
          enabled: false

        config:
          compactor:
            compaction:
              block_retention: 24h
          querier:
            frontend_worker_count: 1
          ingester:
            trace_idle_period: 10s
            max_bytes_per_trace: 50000
            max_traces_per_user: 10000
          distributor:
            receivers:
              otlp:
                protocols:
                  grpc:
                    endpoint: 0.0.0.0:4317
                  http:
                    endpoint: 0.0.0.0:4318
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
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
    kubernetes_namespace_v1.observability,
  ]
}

resource "kubectl_manifest" "argocd_app_otel_collector_agent" {
  count = var.enable_observability_agent && var.enable_signoz && var.enable_argocd && !var.enable_app_of_apps ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: otel-collector-agent
  namespace: ${var.argocd_namespace}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: observability
    server: https://kubernetes.default.svc
  source:
    repoURL: ${local.policies_repo_url_cluster}
    targetRevision: main
    path: ${local.vendored_chart_paths.opentelemetry_collector}
    helm:
      releaseName: otel-collector-agent
      values: |
        mode: daemonset

        image:
          repository: otel/opentelemetry-collector-contrib

        service:
          enabled: true
          type: ClusterIP

        ports:
          otlp:
            hostPort: 0
          otlp-http:
            hostPort: 0
          jaeger-compact:
            enabled: false
          jaeger-thrift:
            enabled: false
          jaeger-grpc:
            enabled: false
          zipkin:
            enabled: false

        presets:
          logsCollection:
            enabled: true
            includeCollectorLogs: false
          kubernetesAttributes:
            enabled: true

        resources:
          requests:
            cpu: 25m
            memory: 64Mi
          limits:
            cpu: 100m
            memory: 256Mi

        config:
          receivers:
            otlp:
              protocols:
                grpc:
                  endpoint: 0.0.0.0:4317
                http:
                  endpoint: 0.0.0.0:4318
            prometheus:
              config:
                scrape_configs:
                  - job_name: argocd
                    metrics_path: /metrics
                    static_configs:
                      - targets:
                          - argocd-application-controller-metrics.argocd.svc.cluster.local:8082
                          - argocd-server-metrics.argocd.svc.cluster.local:8083
                          - argocd-repo-server-metrics.argocd.svc.cluster.local:8084
                          - argocd-applicationset-controller-metrics.argocd.svc.cluster.local:8080
                  - job_name: gitea
                    metrics_path: /metrics
                    static_configs:
                      - targets:
                          - gitea-http.gitea.svc.cluster.local:3000
                  - job_name: oauth2-proxy
                    metrics_path: /metrics
                    static_configs:
                      - targets:
                          - oauth2-proxy-argocd.sso.svc.cluster.local:44180
                          - oauth2-proxy-gitea.sso.svc.cluster.local:44180
                          - oauth2-proxy-hubble.sso.svc.cluster.local:44180
                          - oauth2-proxy-signoz.sso.svc.cluster.local:44180
                          - oauth2-proxy-sentiment-dev.sso.svc.cluster.local:44180
                          - oauth2-proxy-sentiment-uat.sso.svc.cluster.local:44180
                          - oauth2-proxy-subnetcalc-dev.sso.svc.cluster.local:44180
                          - oauth2-proxy-subnetcalc-uat.sso.svc.cluster.local:44180
                  - job_name: nginx-gateway-fabric
                    metrics_path: /metrics
                    static_configs:
                      - targets:
                          - nginx-gateway.nginx-gateway.svc.cluster.local:9113

          processors:
            batch: {}

          exporters:
            otlp:
              endpoint: signoz-otel-collector.observability.svc.cluster.local:4317
              tls:
                insecure: true

          service:
            pipelines:
              logs:
                receivers: [filelog, otlp]
                processors: [k8sattributes, batch]
                exporters: [otlp]
              metrics:
                receivers: [prometheus, otlp]
                processors: [k8sattributes, batch]
                exporters: [otlp]
              traces:
                receivers: [otlp]
                processors: [k8sattributes, batch]
                exporters: [otlp]
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
    kubernetes_namespace_v1.observability,
    kubectl_manifest.argocd_app_signoz,
  ]
}

resource "kubectl_manifest" "signoz_ui_nodeport" {
  count = var.enable_signoz && !var.enable_app_of_apps ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: v1
kind: Service
metadata:
  name: signoz-ui
  namespace: observability
  labels:
    app.kubernetes.io/name: signoz-ui
spec:
  type: NodePort
  selector:
    app.kubernetes.io/component: signoz
    app.kubernetes.io/instance: signoz
    app.kubernetes.io/name: signoz
  ports:
    - name: http
      port: 8080
      targetPort: http
      nodePort: ${var.signoz_ui_node_port}
__YAML__

  wait              = false
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = false

  depends_on = [
    kubectl_manifest.argocd_app_signoz,
  ]
}

resource "kubectl_manifest" "grafana_ui_nodeport" {
  count = local.enable_grafana_effective && !var.enable_app_of_apps ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: v1
kind: Service
metadata:
  name: grafana-ui
  namespace: observability
  labels:
    app.kubernetes.io/name: grafana-ui
spec:
  type: NodePort
  selector:
    app.kubernetes.io/name: grafana
    app.kubernetes.io/instance: grafana
  ports:
    - name: http
      port: 3000
      targetPort: 3000
      nodePort: ${var.grafana_ui_node_port}
__YAML__

  wait              = false
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = false

  depends_on = [
    kubectl_manifest.argocd_app_grafana,
  ]
}
