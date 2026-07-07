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
    null_resource.ensure_kind_kubeconfig,
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
          enabled: ${var.enable_alertmanager}
          image:
            repository: ${local.hardened_image_registry_effective}/alertmanager
            tag: 0.31.1-debian13
          persistence:
            enabled: false
          resources:
            requests:
              cpu: 25m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 256Mi
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
              cpu: 25m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 256Mi
        prometheus-node-exporter:
          enabled: true
          image:
            registry: ${local.hardened_image_registry_effective}
            repository: node-exporter
            tag: 1.10.2-debian13
          resources:
            requests:
              cpu: 10m
              memory: 24Mi
            limits:
              cpu: 100m
              memory: 64Mi
        prometheus-pushgateway:
          enabled: false
        server:
          image:
            repository: quay.io/prometheus/prometheus
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
        serverFiles:
          alerting_rules.yml:
            groups:
              - name: platform-starter.rules
                rules:
                  - alert: PlatformPodCrashLooping
                    expr: sum by (namespace, pod, container) (rate(kube_pod_container_status_restarts_total{namespace!~"kube-system|local-path-storage",container!="POD"}[5m])) > 0
                    for: 10m
                    labels:
                      severity: warning
                    annotations:
                      summary: "Pod container is restarting repeatedly"
                      description: "Container {{ $labels.container }} in pod {{ $labels.namespace }}/{{ $labels.pod }} has a sustained restart rate."
                      runbook_url: "https://github.com/nickromney/platform/blob/main/kubernetes/kind/docs/runbooks.md#platformpodcrashlooping"
                  - alert: PlatformDeploymentReplicasUnavailable
                    expr: kube_deployment_status_replicas_unavailable{namespace!~"kube-system|local-path-storage"} > 0
                    for: 10m
                    labels:
                      severity: warning
                    annotations:
                      summary: "Deployment has unavailable replicas"
                      description: "Deployment {{ $labels.namespace }}/{{ $labels.deployment }} has unavailable replicas for more than 10 minutes."
                      runbook_url: "https://github.com/nickromney/platform/blob/main/kubernetes/kind/docs/runbooks.md#platformdeploymentreplicasunavailable"
                  - alert: PlatformPersistentVolumeClaimFilling
                    expr: (1 - (kubelet_volume_stats_available_bytes{namespace!=""} / kubelet_volume_stats_capacity_bytes{namespace!=""})) > 0.85
                    for: 10m
                    labels:
                      severity: warning
                    annotations:
                      summary: "PersistentVolumeClaim usage is above 85%"
                      description: "PVC {{ $labels.namespace }}/{{ $labels.persistentvolumeclaim }} is more than 85% full."
                      runbook_url: "https://github.com/nickromney/platform/blob/main/kubernetes/kind/docs/runbooks.md#platformpersistentvolumeclaimfilling"
                  - alert: PlatformNodeMemoryPressure
                    expr: (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) < 0.10
                    for: 10m
                    labels:
                      severity: warning
                    annotations:
                      summary: "Node memory availability is below 10%"
                      description: "Node exporter reports less than 10% memory available on {{ $labels.instance }}."
                      runbook_url: "https://github.com/nickromney/platform/blob/main/kubernetes/kind/docs/runbooks.md#platformnodememorypressure"
                  - alert: PlatformCertificateExpiringSoon
                    expr: (certmanager_certificate_expiration_timestamp_seconds - time()) < 1209600
                    for: 30m
                    labels:
                      severity: warning
                    annotations:
                      summary: "cert-manager certificate expires in less than 14 days"
                      description: "Certificate {{ $labels.namespace }}/{{ $labels.name }} expires in less than 14 days."
                      runbook_url: "https://github.com/nickromney/platform/blob/main/kubernetes/kind/docs/runbooks.md#platformcertificateexpiringsoon"
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
          - job_name: platform-mcp
            kubernetes_sd_configs:
              - role: pod
                namespaces:
                  names:
                    - mcp
            relabel_configs:
              - source_labels: [__meta_kubernetes_pod_label_app_kubernetes_io_name]
                action: keep
                regex: platform-mcp
              - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
                action: keep
                regex: "true"
              - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
                target_label: __metrics_path__
                regex: (.+)
              - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
                target_label: __address__
                regex: ([^:]+)(?::\d+)?;(\d+)
                replacement: "$1:$2"
              - source_labels: [__meta_kubernetes_namespace]
                target_label: namespace
              - source_labels: [__meta_kubernetes_pod_label_app]
                target_label: app
          - job_name: backstage-catalog
            kubernetes_sd_configs:
              - role: pod
                namespaces:
                  names:
                    - idp
            relabel_configs:
              - source_labels: [__meta_kubernetes_pod_label_app_kubernetes_io_name]
                action: keep
                regex: backstage
              - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
                action: keep
                regex: "true"
              - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
                target_label: __metrics_path__
                regex: (.+)
              - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
                target_label: __address__
                regex: ([^:]+)(?::\d+)?;(\d+)
                replacement: "$1:$2"
              - source_labels: [__meta_kubernetes_namespace]
                target_label: namespace
              - source_labels: [__meta_kubernetes_pod_label_app]
                target_label: app
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
        dashboards:
          default:
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
                      "description": "https://grafana.admin.127.0.0.1.sslip.io/d/backstage-observability/backstage-observability",
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
                          "title": "Open Backstage Observability",
                          "url": "https://grafana.admin.127.0.0.1.sslip.io/d/backstage-observability/backstage-observability"
                        }
                      ],
                      "options": {
                        "colorMode": "background",
                        "graphMode": "none"
                      },
                      "targets": [
                        {
                          "expr": "((max(kube_deployment_status_replicas_available{namespace=\"idp\",deployment=\"backstage\"}) > bool 0) or max(argocd_app_info{name=\"idp\",health_status=\"Healthy\",sync_status=\"Synced\"}) or vector(0))",
                          "refId": "A"
                        }
                      ],
                      "title": "Backstage Observability",
                      "type": "stat"
                    },
                    {
                      "datasource": "Prometheus",
                      "description": "https://grafana.admin.127.0.0.1.sslip.io/d/platform-app-overview/platform-app-golden-signals",
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
                          "title": "Open Platform App Golden Signals",
                          "url": "https://grafana.admin.127.0.0.1.sslip.io/d/platform-app-overview/platform-app-golden-signals"
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
                      "description": "https://grafana.admin.127.0.0.1.sslip.io/d/platform-mcp-observability/platform-mcp-observability",
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
                          "title": "Open Platform MCP",
                          "url": "https://grafana.admin.127.0.0.1.sslip.io/d/platform-mcp-observability/platform-mcp-observability"
                        }
                      ],
                      "options": {
                        "colorMode": "background",
                        "graphMode": "none"
                      },
                      "targets": [
                        {
                          "expr": "((max(kube_deployment_status_replicas_available{namespace=\"mcp\",deployment=\"platform-mcp\"}) > bool 0) or max(argocd_app_info{name=\"mcp\",health_status=\"Healthy\",sync_status=\"Synced\"}) or vector(0))",
                          "refId": "A"
                        }
                      ],
                      "title": "Platform MCP",
                      "type": "stat"
                    },
                    {
                      "datasource": "Prometheus",
                      "description": "https://grafana.admin.127.0.0.1.sslip.io/d/platform-namespace-health/platform-namespace-health",
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
                          "title": "Open Platform Namespace Health",
                          "url": "https://grafana.admin.127.0.0.1.sslip.io/d/platform-namespace-health/platform-namespace-health"
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
                      "description": "https://argocd.admin.127.0.0.1.sslip.io",
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
                          "title": "Open Argo CD",
                          "url": "https://argocd.admin.127.0.0.1.sslip.io"
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
                      "description": "https://gitea.admin.127.0.0.1.sslip.io",
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
                          "title": "Open Gitea",
                          "url": "https://gitea.admin.127.0.0.1.sslip.io"
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
                      "description": "https://headlamp.admin.127.0.0.1.sslip.io",
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
                          "title": "Open Headlamp",
                          "url": "https://headlamp.admin.127.0.0.1.sslip.io"
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
                      "description": "https://hubble.admin.127.0.0.1.sslip.io",
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
                          "title": "Open Hubble",
                          "url": "https://hubble.admin.127.0.0.1.sslip.io"
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
                      "description": "https://keycloak.127.0.0.1.sslip.io/admin/platform/console/#/platform/users",
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
                          "title": "Open Keycloak",
                          "url": "https://keycloak.127.0.0.1.sslip.io/admin/platform/console/#/platform/users"
                        }
                      ],
                      "options": {
                        "colorMode": "background",
                        "graphMode": "none"
                      },
                      "targets": [
                        {
                          "expr": "((max(kube_deployment_status_replicas_available{namespace=\"sso\",deployment=\"keycloak\"}) > bool 0) or vector(0))",
                          "refId": "A"
                        }
                      ],
                      "title": "Keycloak",
                      "type": "stat"
                    },
                    {
                      "datasource": "Prometheus",
                      "description": "https://kyverno.admin.127.0.0.1.sslip.io/",
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
                          "title": "Open Kyverno Policy UI",
                          "url": "https://kyverno.admin.127.0.0.1.sslip.io/"
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
                      "description": "https://mcp-console.127.0.0.1.sslip.io",
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
                          "title": "Open MCP Inspector",
                          "url": "https://mcp-console.127.0.0.1.sslip.io"
                        }
                      ],
                      "options": {
                        "colorMode": "background",
                        "graphMode": "none"
                      },
                      "targets": [
                        {
                          "expr": "(((max(kube_deployment_status_replicas_available{namespace=\"sso\",deployment=\"oauth2-proxy-mcp-console\"}) > bool 0) * (max(kube_deployment_status_replicas_available{namespace=\"mcp\",deployment=\"mcp-inspector\"}) > bool 0)) or vector(0))",
                          "refId": "A"
                        }
                      ],
                      "title": "MCP Inspector",
                      "type": "stat"
                    },
                    {
                      "datasource": "Prometheus",
                      "description": "https://mcp.127.0.0.1.sslip.io/mcp",
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
                          "title": "Open Platform MCP Endpoint",
                          "url": "https://mcp.127.0.0.1.sslip.io/mcp"
                        }
                      ],
                      "options": {
                        "colorMode": "background",
                        "graphMode": "none"
                      },
                      "targets": [
                        {
                          "expr": "((max(kube_deployment_status_replicas_available{namespace=\"mcp\",deployment=\"platform-mcp\"}) > bool 0) or max(argocd_app_info{name=\"mcp\",health_status=\"Healthy\",sync_status=\"Synced\"}) or vector(0))",
                          "refId": "A"
                        }
                      ],
                      "title": "Platform MCP Endpoint",
                      "type": "stat"
                    },
                    {
                      "datasource": "Prometheus",
                      "description": "https://portal.127.0.0.1.sslip.io",
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
                        "y": 18
                      },
                      "id": 14,
                      "links": [
                        {
                          "targetBlank": true,
                          "title": "Open Developer Portal",
                          "url": "https://portal.127.0.0.1.sslip.io"
                        }
                      ],
                      "options": {
                        "colorMode": "background",
                        "graphMode": "none"
                      },
                      "targets": [
                        {
                          "expr": "(((max(kube_deployment_status_replicas_available{namespace=\"sso\",deployment=\"oauth2-proxy-backstage\"}) > bool 0) * (max(kube_deployment_status_replicas_available{namespace=\"idp\",deployment=\"backstage\"}) > bool 0)) or vector(0))",
                          "refId": "A"
                        }
                      ],
                      "title": "Developer Portal",
                      "type": "stat"
                    },
                    {
                      "datasource": "Prometheus",
                      "description": "https://portal-api.127.0.0.1.sslip.io",
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
                        "y": 18
                      },
                      "id": 15,
                      "links": [
                        {
                          "targetBlank": true,
                          "title": "Open Portal API",
                          "url": "https://portal-api.127.0.0.1.sslip.io"
                        }
                      ],
                      "options": {
                        "colorMode": "background",
                        "graphMode": "none"
                      },
                      "targets": [
                        {
                          "expr": "(((max(kube_deployment_status_replicas_available{namespace=\"sso\",deployment=\"oauth2-proxy-idp-core\"}) > bool 0) * (max(kube_deployment_status_replicas_available{namespace=\"idp\",deployment=\"idp-core\"}) > bool 0)) or vector(0))",
                          "refId": "A"
                        }
                      ],
                      "title": "Portal API",
                      "type": "stat"
                    },
                    {
                      "datasource": "Prometheus",
                      "description": "https://subnetcalc.dev.127.0.0.1.sslip.io/api",
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
                        "y": 18
                      },
                      "id": 16,
                      "links": [
                        {
                          "targetBlank": true,
                          "title": "Open APIM Simulator",
                          "url": "https://subnetcalc.dev.127.0.0.1.sslip.io/api"
                        }
                      ],
                      "options": {
                        "colorMode": "background",
                        "graphMode": "none"
                      },
                      "targets": [
                        {
                          "expr": "(((max(kube_deployment_status_replicas_available{namespace=\"sso\",deployment=\"oauth2-proxy-apim\"}) > bool 0) * (max(kube_deployment_status_replicas_available{namespace=\"apim\",deployment=\"subnetcalc-apim-simulator\"}) > bool 0)) or vector(0))",
                          "refId": "A"
                        }
                      ],
                      "title": "APIM Simulator",
                      "type": "stat"
                    },
                    {
                      "datasource": "Prometheus",
                      "description": "https://auth-chat.dev.127.0.0.1.sslip.io",
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
                        "y": 18
                      },
                      "id": 17,
                      "links": [
                        {
                          "targetBlank": true,
                          "title": "Open Auth Chat DEV",
                          "url": "https://auth-chat.dev.127.0.0.1.sslip.io"
                        }
                      ],
                      "options": {
                        "colorMode": "background",
                        "graphMode": "none"
                      },
                      "targets": [
                        {
                          "expr": "(((max(kube_deployment_status_replicas_available{namespace=\"sso\",deployment=\"oauth2-proxy-auth-chat\"}) > bool 0) * (max(kube_deployment_status_replicas_available{namespace=\"dev\",deployment=\"auth-chat\"}) > bool 0)) or vector(0))",
                          "refId": "A"
                        }
                      ],
                      "title": "Auth Chat DEV",
                      "type": "stat"
                    },
                    {
                      "datasource": "Prometheus",
                      "description": "https://chatgpt.dev.127.0.0.1.sslip.io",
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
                        "y": 23
                      },
                      "id": 18,
                      "links": [
                        {
                          "targetBlank": true,
                          "title": "Open ChatGPT Sim DEV",
                          "url": "https://chatgpt.dev.127.0.0.1.sslip.io"
                        }
                      ],
                      "options": {
                        "colorMode": "background",
                        "graphMode": "none"
                      },
                      "targets": [
                        {
                          "expr": "(((max(kube_deployment_status_replicas_available{namespace=\"sso\",deployment=\"oauth2-proxy-chatgpt-sim\"}) > bool 0) * (max(kube_deployment_status_replicas_available{namespace=\"dev\",deployment=\"chatgpt-sim\"}) > bool 0)) or vector(0))",
                          "refId": "A"
                        }
                      ],
                      "title": "ChatGPT Sim DEV",
                      "type": "stat"
                    },
                    {
                      "datasource": "Prometheus",
                      "description": "https://langfuse.admin.127.0.0.1.sslip.io",
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
                        "y": 23
                      },
                      "id": 19,
                      "links": [
                        {
                          "targetBlank": true,
                          "title": "Open Langfuse",
                          "url": "https://langfuse.admin.127.0.0.1.sslip.io"
                        }
                      ],
                      "options": {
                        "colorMode": "background",
                        "graphMode": "none"
                      },
                      "targets": [
                        {
                          "expr": "(((max(kube_deployment_status_replicas_available{namespace=\"sso\",deployment=\"oauth2-proxy-langfuse\"}) > bool 0) * (max(kube_deployment_status_replicas_available{namespace=\"langfuse\",deployment=\"langfuse-web\"}) > bool 0)) or vector(0))",
                          "refId": "A"
                        }
                      ],
                      "title": "Langfuse",
                      "type": "stat"
                    },
                    {
                      "datasource": "Prometheus",
                      "description": "https://lf-evals.dev.127.0.0.1.sslip.io",
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
                        "y": 23
                      },
                      "id": 20,
                      "links": [
                        {
                          "targetBlank": true,
                          "title": "Open Langfuse Eval Runner DEV",
                          "url": "https://lf-evals.dev.127.0.0.1.sslip.io"
                        }
                      ],
                      "options": {
                        "colorMode": "background",
                        "graphMode": "none"
                      },
                      "targets": [
                        {
                          "expr": "(((max(kube_deployment_status_replicas_available{namespace=\"sso\",deployment=\"oauth2-proxy-langfuse-eval-runner\"}) > bool 0) * (max(kube_deployment_status_replicas_available{namespace=\"dev\",deployment=\"langfuse-eval-runner\"}) > bool 0)) or vector(0))",
                          "refId": "A"
                        }
                      ],
                      "title": "Langfuse Eval Runner DEV",
                      "type": "stat"
                    },
                    {
                      "datasource": "Prometheus",
                      "description": "https://lf-agent.dev.127.0.0.1.sslip.io",
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
                        "y": 23
                      },
                      "id": 21,
                      "links": [
                        {
                          "targetBlank": true,
                          "title": "Open Langfuse Tool Agent DEV",
                          "url": "https://lf-agent.dev.127.0.0.1.sslip.io"
                        }
                      ],
                      "options": {
                        "colorMode": "background",
                        "graphMode": "none"
                      },
                      "targets": [
                        {
                          "expr": "(((max(kube_deployment_status_replicas_available{namespace=\"sso\",deployment=\"oauth2-proxy-langfuse-tool-agent\"}) > bool 0) * (max(kube_deployment_status_replicas_available{namespace=\"dev\",deployment=\"langfuse-tool-agent\"}) > bool 0)) or vector(0))",
                          "refId": "A"
                        }
                      ],
                      "title": "Langfuse Tool Agent DEV",
                      "type": "stat"
                    },
                    {
                      "datasource": "Prometheus",
                      "description": "https://lf-chat.dev.127.0.0.1.sslip.io",
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
                        "y": 28
                      },
                      "id": 22,
                      "links": [
                        {
                          "targetBlank": true,
                          "title": "Open Langfuse Trace Chat DEV",
                          "url": "https://lf-chat.dev.127.0.0.1.sslip.io"
                        }
                      ],
                      "options": {
                        "colorMode": "background",
                        "graphMode": "none"
                      },
                      "targets": [
                        {
                          "expr": "(((max(kube_deployment_status_replicas_available{namespace=\"sso\",deployment=\"oauth2-proxy-langfuse-trace-chat\"}) > bool 0) * (max(kube_deployment_status_replicas_available{namespace=\"dev\",deployment=\"langfuse-trace-chat\"}) > bool 0)) or vector(0))",
                          "refId": "A"
                        }
                      ],
                      "title": "Langfuse Trace Chat DEV",
                      "type": "stat"
                    },
                    {
                      "datasource": "Prometheus",
                      "description": "https://sentiment.dev.127.0.0.1.sslip.io",
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
                        "y": 28
                      },
                      "id": 23,
                      "links": [
                        {
                          "targetBlank": true,
                          "title": "Open Sentiment DEV",
                          "url": "https://sentiment.dev.127.0.0.1.sslip.io"
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
                      "description": "https://subnetcalc.dev.127.0.0.1.sslip.io",
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
                        "y": 28
                      },
                      "id": 24,
                      "links": [
                        {
                          "targetBlank": true,
                          "title": "Open SubnetCalc DEV",
                          "url": "https://subnetcalc.dev.127.0.0.1.sslip.io"
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
                      "description": "https://sentiment.uat.127.0.0.1.sslip.io",
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
                        "y": 28
                      },
                      "id": 25,
                      "links": [
                        {
                          "targetBlank": true,
                          "title": "Open Sentiment UAT",
                          "url": "https://sentiment.uat.127.0.0.1.sslip.io"
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
                      "description": "https://subnetcalc.uat.127.0.0.1.sslip.io",
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
                        "y": 33
                      },
                      "id": 26,
                      "links": [
                        {
                          "targetBlank": true,
                          "title": "Open SubnetCalc UAT",
                          "url": "https://subnetcalc.uat.127.0.0.1.sslip.io"
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
                          "expr": "(100 * (sum(rate(traces_span_metrics_calls_total{service_name=~\"sentiment-api|subnetcalc-api\",k8s_namespace_name=~\"dev|uat\",http_status_code=~\"4..|5..\"}[5m])) by (k8s_namespace_name,service_name) / clamp_min(sum(rate(traces_span_metrics_calls_total{service_name=~\"sentiment-api|subnetcalc-api\",k8s_namespace_name=~\"dev|uat\"}[5m])) by (k8s_namespace_name,service_name), 0.0001))) or (0 * sum(rate(traces_span_metrics_calls_total{service_name=~\"sentiment-api|subnetcalc-api\",k8s_namespace_name=~\"dev|uat\"}[5m])) by (k8s_namespace_name,service_name))",
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
                          "expr": "histogram_quantile(0.95, sum(rate(llm_inference_latency_ms_bucket{k8s_namespace_name=~\"dev|uat\"}[5m])) by (le,k8s_namespace_name)) or on(k8s_namespace_name) (0 * max by (k8s_namespace_name) (sentiment_comments_created_total{k8s_namespace_name=~\"dev|uat\"}))",
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
                          "expr": "count by (namespace) (up{job=\"kubernetes-pods\",namespace=~\"dev|uat\"} == 1) or on(namespace) (0 * max by (namespace) (kube_namespace_status_phase{namespace=~\"dev|uat\",phase=\"Active\"}))",
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
            platform-mcp-observability:
              json: |
                {
                  "annotations": {"list": []},
                  "editable": true,
                  "graphTooltip": 1,
                  "panels": [
                    {
                      "gridPos": {"h": 3, "w": 24, "x": 0, "y": 0},
                      "id": 1,
                      "options": {
                        "content": "## Platform MCP Observability\nThis dashboard proves the MCP workload is deployed, scrapeable, callable, and logging. A fresh stack legitimately starts with zero tool calls; use the smoke command below or MCP Inspector to generate traffic.",
                        "mode": "markdown"
                      },
                      "title": "How to read this dashboard",
                      "type": "text"
                    },
                    {
                      "gridPos": {"h": 4, "w": 8, "x": 0, "y": 3},
                      "id": 2,
                      "options": {
                        "content": "### Endpoints\n- MCP API: https://mcp.127.0.0.1.sslip.io/mcp\n- MCP Console: https://mcp-console.127.0.0.1.sslip.io\n- Smoke: `curl -fsS https://mcp.127.0.0.1.sslip.io/mcp -H \"Authorization: Bearer $${PLATFORM_MCP_BEARER_TOKEN}\" -H \"Content-Type: application/json\" -d '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}'`",
                        "mode": "markdown"
                      },
                      "title": "Operator links",
                      "type": "text"
                    },
                    {
                      "datasource": "Prometheus",
                      "fieldConfig": {
                        "defaults": {
                          "color": {"mode": "thresholds"},
                          "mappings": [{"options": {"0": {"text": "No replicas"}, "1": {"text": "Ready"}}, "type": "value"}],
                          "max": 1,
                          "min": 0,
                          "thresholds": {"mode": "absolute", "steps": [{"color": "red", "value": 0}, {"color": "green", "value": 1}]},
                          "unit": "short"
                        },
                        "overrides": []
                      },
                      "gridPos": {"h": 4, "w": 4, "x": 8, "y": 3},
                      "id": 3,
                      "options": {"colorMode": "background", "graphMode": "none", "justifyMode": "center"},
                      "targets": [{"expr": "((sum(kube_deployment_status_replicas_available{namespace=\"mcp\",deployment=\"platform-mcp\"}) > bool 0) or vector(0))", "refId": "A"}],
                      "title": "MCP Deployment Ready",
                      "type": "stat"
                    },
                    {
                      "datasource": "Prometheus",
                      "fieldConfig": {
                        "defaults": {
                          "color": {"mode": "thresholds"},
                          "mappings": [{"options": {"0": {"text": "Not scraped"}, "1": {"text": "Scraped"}}, "type": "value"}],
                          "max": 1,
                          "min": 0,
                          "thresholds": {"mode": "absolute", "steps": [{"color": "red", "value": 0}, {"color": "green", "value": 1}]},
                          "unit": "short"
                        },
                        "overrides": []
                      },
                      "gridPos": {"h": 4, "w": 4, "x": 12, "y": 3},
                      "id": 4,
                      "options": {"colorMode": "background", "graphMode": "none", "justifyMode": "center"},
                      "targets": [{"expr": "(max(up{job=\"platform-mcp\"}) or vector(0))", "refId": "A"}],
                      "title": "Prometheus Scrape",
                      "type": "stat"
                    },
                    {
                      "datasource": "Prometheus",
                      "fieldConfig": {"defaults": {"unit": "short"}, "overrides": []},
                      "gridPos": {"h": 4, "w": 4, "x": 16, "y": 3},
                      "id": 5,
                      "options": {"colorMode": "value", "graphMode": "area", "justifyMode": "center"},
                      "targets": [{"expr": "(sum(platform_mcp_tool_calls_total) or vector(0))", "refId": "A"}],
                      "title": "Total Tool Calls",
                      "type": "stat"
                    },
                    {
                      "datasource": "Prometheus",
                      "fieldConfig": {"defaults": {"unit": "ms"}, "overrides": []},
                      "gridPos": {"h": 4, "w": 4, "x": 20, "y": 3},
                      "id": 6,
                      "options": {"colorMode": "value", "graphMode": "area", "justifyMode": "center"},
                      "targets": [{"expr": "((sum(rate(platform_mcp_tool_duration_seconds_sum[5m])) / clamp_min(sum(rate(platform_mcp_tool_calls_total[5m])), 0.001)) * 1000 or vector(0))", "refId": "A"}],
                      "title": "Mean Tool Latency",
                      "type": "stat"
                    },
                    {
                      "datasource": "Prometheus",
                      "fieldConfig": {"defaults": {"unit": "short"}, "overrides": []},
                      "gridPos": {"h": 7, "w": 8, "x": 0, "y": 7},
                      "id": 7,
                      "options": {"displayMode": "gradient", "legend": {"displayMode": "list", "placement": "bottom"}, "orientation": "horizontal"},
                      "targets": [{"expr": "sum(platform_mcp_tool_calls_total) by (tool, status)", "legendFormat": "{{tool}} {{status}}", "refId": "A"}],
                      "title": "Tool Calls by Tool",
                      "type": "bargauge"
                    },
                    {
                      "datasource": "Prometheus",
                      "fieldConfig": {"defaults": {"unit": "reqps"}, "overrides": []},
                      "gridPos": {"h": 7, "w": 8, "x": 8, "y": 7},
                      "id": 8,
                      "options": {"legend": {"displayMode": "list", "placement": "bottom"}, "tooltip": {"mode": "multi", "sort": "desc"}},
                      "targets": [{"expr": "sum(rate(platform_mcp_tool_calls_total[5m])) by (tool, status)", "legendFormat": "{{tool}} {{status}}", "refId": "A"}],
                      "title": "Tool Call Rate",
                      "type": "timeseries"
                    },
                    {
                      "datasource": "Prometheus",
                      "fieldConfig": {"defaults": {"unit": "ms"}, "overrides": []},
                      "gridPos": {"h": 7, "w": 8, "x": 16, "y": 7},
                      "id": 9,
                      "options": {"legend": {"displayMode": "list", "placement": "bottom"}, "tooltip": {"mode": "multi", "sort": "desc"}},
                      "targets": [{"expr": "(sum(rate(platform_mcp_tool_duration_seconds_sum[5m])) by (tool) / clamp_min(sum(rate(platform_mcp_tool_calls_total[5m])) by (tool), 0.001)) * 1000", "legendFormat": "{{tool}}", "refId": "A"}],
                      "title": "Average Tool Duration",
                      "type": "timeseries"
                    },
                    {
                      "datasource": "Prometheus",
                      "fieldConfig": {"defaults": {"unit": "short"}, "overrides": []},
                      "gridPos": {"h": 6, "w": 8, "x": 0, "y": 14},
                      "id": 10,
                      "options": {"showHeader": true},
                      "targets": [{"expr": "up{job=\"platform-mcp\"}", "format": "table", "instant": true, "refId": "A"}],
                      "title": "Scrape Target Details",
                      "type": "table"
                    },
                    {
                      "datasource": "Prometheus",
                      "fieldConfig": {"defaults": {"unit": "short"}, "overrides": []},
                      "gridPos": {"h": 6, "w": 8, "x": 8, "y": 14},
                      "id": 11,
                      "options": {"showHeader": true},
                      "targets": [{"expr": "kube_pod_container_status_restarts_total{namespace=\"mcp\",container=\"server\"}", "format": "table", "instant": true, "refId": "A"}],
                      "title": "Container Restarts",
                      "type": "table"
                    },
                    {
                      "datasource": "Prometheus",
                      "fieldConfig": {"defaults": {"unit": "bytes"}, "overrides": []},
                      "gridPos": {"h": 6, "w": 8, "x": 16, "y": 14},
                      "id": 12,
                      "options": {"legend": {"displayMode": "list", "placement": "bottom"}},
                      "targets": [{"expr": "sum(container_memory_working_set_bytes{namespace=\"mcp\",pod=~\"platform-mcp-.*\",container=\"server\"})", "legendFormat": "platform-mcp", "refId": "A"}],
                      "title": "Memory Working Set",
                      "type": "timeseries"
                    },
                    {
                      "datasource": {"type": "victoriametrics-logs-datasource", "uid": "victorialogs"},
                      "gridPos": {"h": 10, "w": 24, "x": 0, "y": 20},
                      "id": 13,
                      "options": {"dedupStrategy": "none", "enableLogDetails": true, "prettifyLogMessage": false, "showLabels": true, "showTime": true, "sortOrder": "Descending", "wrapLogMessage": true},
                      "targets": [{"datasource": {"type": "victoriametrics-logs-datasource", "uid": "victorialogs"}, "expr": "k8s.namespace.name:mcp", "maxLines": 100, "queryType": "instant", "refId": "A"}],
                      "title": "Recent MCP Namespace Logs",
                      "type": "logs"
                    }
                  ],
                  "refresh": "30s",
                  "schemaVersion": 39,
                  "tags": ["platform", "mcp", "prometheus", "victorialogs"],
                  "templating": {"list": []},
                  "time": {"from": "now-15m", "to": "now"},
                  "title": "Platform MCP Observability",
                  "uid": "platform-mcp-observability",
                  "version": 2
                }
            backstage-observability:
              json: |
                {
                  "annotations": {
                    "list": []
                  },
                  "editable": true,
                  "graphTooltip": 1,
                  "panels": [
                    {
                      "id": 1,
                      "type": "text",
                      "title": "How to read this dashboard",
                      "gridPos": {
                        "h": 3,
                        "w": 24,
                        "x": 0,
                        "y": 0
                      },
                      "options": {
                        "mode": "markdown",
                        "content": "## Backstage Catalog Observability\nThis dashboard proves both Backstage runtime health and catalog quality. The catalog metrics endpoint counts entity kinds, APIs, service annotation coverage, API relationships, and unreadable catalog locations."
                      }
                    },
                    {
                      "id": 2,
                      "type": "stat",
                      "title": "Backstage Ready",
                      "datasource": "Prometheus",
                      "gridPos": {
                        "h": 4,
                        "w": 4,
                        "x": 0,
                        "y": 3
                      },
                      "fieldConfig": {
                        "defaults": {
                          "unit": "short",
                          "min": 0,
                          "max": 1
                        },
                        "overrides": []
                      },
                      "targets": [
                        {
                          "expr": "((sum(kube_deployment_status_replicas_available{namespace=\"idp\",deployment=\"backstage\"}) > bool 0) or vector(0))",
                          "refId": "A"
                        }
                      ]
                    },
                    {
                      "id": 3,
                      "type": "stat",
                      "title": "Catalog Scrape",
                      "datasource": "Prometheus",
                      "gridPos": {
                        "h": 4,
                        "w": 4,
                        "x": 4,
                        "y": 3
                      },
                      "fieldConfig": {
                        "defaults": {
                          "unit": "short",
                          "min": 0,
                          "max": 1
                        },
                        "overrides": []
                      },
                      "targets": [
                        {
                          "expr": "(max(up{job=\"backstage-catalog\"}) or vector(0))",
                          "refId": "A"
                        }
                      ]
                    },
                    {
                      "id": 4,
                      "type": "stat",
                      "title": "Catalog APIs",
                      "datasource": "Prometheus",
                      "gridPos": {
                        "h": 4,
                        "w": 4,
                        "x": 8,
                        "y": 3
                      },
                      "fieldConfig": {
                        "defaults": {
                          "unit": "short"
                        },
                        "overrides": []
                      },
                      "targets": [
                        {
                          "expr": "(max(backstage_catalog_apis_total) or vector(0))",
                          "refId": "A"
                        }
                      ]
                    },
                    {
                      "id": 5,
                      "type": "stat",
                      "title": "Services With Kubernetes Selector",
                      "datasource": "Prometheus",
                      "gridPos": {
                        "h": 4,
                        "w": 6,
                        "x": 12,
                        "y": 3
                      },
                      "fieldConfig": {
                        "defaults": {
                          "unit": "short"
                        },
                        "overrides": []
                      },
                      "targets": [
                        {
                          "expr": "(max(backstage_catalog_service_annotations_total{annotation=\"kubernetes_label_selector\",state=\"present\"}) or vector(0))",
                          "refId": "A"
                        }
                      ]
                    },
                    {
                      "id": 6,
                      "type": "stat",
                      "title": "Services Missing Kubernetes Selector",
                      "datasource": "Prometheus",
                      "gridPos": {
                        "h": 4,
                        "w": 6,
                        "x": 18,
                        "y": 3
                      },
                      "fieldConfig": {
                        "defaults": {
                          "unit": "short"
                        },
                        "overrides": []
                      },
                      "targets": [
                        {
                          "expr": "(max(backstage_catalog_service_annotations_total{annotation=\"kubernetes_label_selector\",state=\"missing\"}) or vector(0))",
                          "refId": "A"
                        }
                      ]
                    },
                    {
                      "id": 7,
                      "type": "bargauge",
                      "title": "Catalog Entities by Kind",
                      "datasource": "Prometheus",
                      "gridPos": {
                        "h": 8,
                        "w": 8,
                        "x": 0,
                        "y": 7
                      },
                      "fieldConfig": {
                        "defaults": {
                          "unit": "short"
                        },
                        "overrides": []
                      },
                      "targets": [
                        {
                          "expr": "max by (kind) (backstage_catalog_entities_total)",
                          "legendFormat": "{{kind}}",
                          "refId": "A"
                        }
                      ]
                    },
                    {
                      "id": 8,
                      "type": "bargauge",
                      "title": "Components by Type",
                      "datasource": "Prometheus",
                      "gridPos": {
                        "h": 8,
                        "w": 8,
                        "x": 8,
                        "y": 7
                      },
                      "fieldConfig": {
                        "defaults": {
                          "unit": "short"
                        },
                        "overrides": []
                      },
                      "targets": [
                        {
                          "expr": "max by (type) (backstage_catalog_components_total)",
                          "legendFormat": "{{type}}",
                          "refId": "A"
                        }
                      ]
                    },
                    {
                      "id": 9,
                      "type": "bargauge",
                      "title": "Service Annotation Coverage",
                      "datasource": "Prometheus",
                      "gridPos": {
                        "h": 8,
                        "w": 8,
                        "x": 16,
                        "y": 7
                      },
                      "fieldConfig": {
                        "defaults": {
                          "unit": "short"
                        },
                        "overrides": []
                      },
                      "targets": [
                        {
                          "expr": "max by (annotation, state) (backstage_catalog_service_annotations_total)",
                          "legendFormat": "{{annotation}} {{state}}",
                          "refId": "A"
                        }
                      ]
                    },
                    {
                      "id": 10,
                      "type": "stat",
                      "title": "API Relationships",
                      "datasource": "Prometheus",
                      "gridPos": {
                        "h": 5,
                        "w": 8,
                        "x": 0,
                        "y": 15
                      },
                      "fieldConfig": {
                        "defaults": {
                          "unit": "short"
                        },
                        "overrides": []
                      },
                      "targets": [
                        {
                          "expr": "max by (relationship) (backstage_catalog_api_relationships_total)",
                          "legendFormat": "{{relationship}}",
                          "refId": "A"
                        }
                      ]
                    },
                    {
                      "id": 11,
                      "type": "stat",
                      "title": "Unreadable Catalog Locations",
                      "datasource": "Prometheus",
                      "gridPos": {
                        "h": 5,
                        "w": 8,
                        "x": 8,
                        "y": 15
                      },
                      "fieldConfig": {
                        "defaults": {
                          "unit": "short"
                        },
                        "overrides": []
                      },
                      "targets": [
                        {
                          "expr": "(max(backstage_catalog_locations_missing_total) or vector(0))",
                          "refId": "A"
                        }
                      ]
                    },
                    {
                      "id": 12,
                      "type": "timeseries",
                      "title": "Backstage CPU",
                      "datasource": "Prometheus",
                      "gridPos": {
                        "h": 8,
                        "w": 8,
                        "x": 16,
                        "y": 15
                      },
                      "fieldConfig": {
                        "defaults": {
                          "unit": "cores"
                        },
                        "overrides": []
                      },
                      "targets": [
                        {
                          "expr": "sum(rate(container_cpu_usage_seconds_total{namespace=\"idp\",pod=~\"backstage-.*\",container=\"backstage\"}[5m]))",
                          "legendFormat": "backstage",
                          "refId": "A"
                        }
                      ]
                    },
                    {
                      "id": 13,
                      "type": "timeseries",
                      "title": "Backstage Memory",
                      "datasource": "Prometheus",
                      "gridPos": {
                        "h": 8,
                        "w": 12,
                        "x": 0,
                        "y": 20
                      },
                      "fieldConfig": {
                        "defaults": {
                          "unit": "bytes"
                        },
                        "overrides": []
                      },
                      "targets": [
                        {
                          "expr": "sum(container_memory_working_set_bytes{namespace=\"idp\",pod=~\"backstage-.*\",container=\"backstage\"})",
                          "legendFormat": "backstage",
                          "refId": "A"
                        }
                      ]
                    },
                    {
                      "id": 14,
                      "type": "logs",
                      "title": "Recent Backstage Logs",
                      "datasource": {
                        "type": "victoriametrics-logs-datasource",
                        "uid": "victorialogs"
                      },
                      "gridPos": {
                        "h": 8,
                        "w": 12,
                        "x": 12,
                        "y": 23
                      },
                      "options": {
                        "dedupStrategy": "none",
                        "enableLogDetails": true,
                        "showLabels": true,
                        "showTime": true,
                        "sortOrder": "Descending",
                        "wrapLogMessage": true
                      },
                      "targets": [
                        {
                          "datasource": {
                            "type": "victoriametrics-logs-datasource",
                            "uid": "victorialogs"
                          },
                          "expr": "k8s.namespace.name:idp backstage",
                          "maxLines": 100,
                          "queryType": "instant",
                          "refId": "A"
                        }
                      ]
                    }
                  ],
                  "refresh": "30s",
                  "schemaVersion": 39,
                  "tags": [
                    "platform",
                    "backstage",
                    "catalog",
                    "victorialogs",
                    "otel"
                  ],
                  "templating": {
                    "list": []
                  },
                  "time": {
                    "from": "now-15m",
                    "to": "now"
                  },
                  "title": "Backstage Observability",
                  "uid": "backstage-observability",
                  "version": 2
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
                    },
                    {
                      "datasource": {"type": "victoriametrics-logs-datasource", "uid": "victorialogs"},
                      "gridPos": {"h": 12, "w": 24, "x": 0, "y": 20},
                      "id": 4,
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
                          "expr": "k8s.namespace.name:mcp",
                          "maxLines": 100,
                          "queryType": "instant",
                          "refId": "A"
                        }
                      ],
                      "title": "MCP Namespace Logs",
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

  yaml_body = templatefile("${local.stack_dir}/templates/argocd-app-otel-gateway.yaml.tftpl", {
    argocd_namespace                      = var.argocd_namespace
    policies_repo_url_cluster             = local.policies_repo_url_cluster
    opentelemetry_collector_chart_path    = local.vendored_chart_paths.opentelemetry_collector
    opentelemetry_collector_chart_version = var.opentelemetry_collector_chart_version
    enable_prometheus_fanout              = local.enable_prometheus_effective || local.enable_grafana_effective
    enable_victoria_logs_fanout           = local.enable_victoria_logs_effective
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
  type: ${local.admin_service_type}
  selector:
    app.kubernetes.io/name: grafana
    app.kubernetes.io/instance: grafana
  ports:
    - name: http
      port: 3000
      targetPort: 3000
${var.expose_admin_nodeports ? "      nodePort: ${var.grafana_ui_node_port}" : ""}
__YAML__

  wait              = false
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = false

  depends_on = [
    kubectl_manifest.argocd_app_grafana,
  ]
}
