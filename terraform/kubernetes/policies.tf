resource "kubectl_manifest" "argocd_app_kyverno" {
  count = var.enable_policies && var.enable_argocd && !var.enable_app_of_apps ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kyverno
  namespace: ${var.argocd_namespace}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: kyverno
    server: https://kubernetes.default.svc
  ignoreDifferences:
    - group: admissionregistration.k8s.io
      kind: MutatingWebhookConfiguration
      name: kyverno-policy-mutating-webhook-cfg
      jqPathExpressions:
        - .webhooks[].clientConfig.caBundle
    - group: admissionregistration.k8s.io
      kind: MutatingWebhookConfiguration
      name: kyverno-resource-mutating-webhook-cfg
      jqPathExpressions:
        - .webhooks[].clientConfig.caBundle
    - group: admissionregistration.k8s.io
      kind: MutatingWebhookConfiguration
      name: kyverno-verify-mutating-webhook-cfg
      jqPathExpressions:
        - .webhooks[].clientConfig.caBundle
    - group: admissionregistration.k8s.io
      kind: ValidatingWebhookConfiguration
      name: kyverno-cel-exception-validating-webhook-cfg
      jqPathExpressions:
        - .webhooks[].clientConfig.caBundle
    - group: admissionregistration.k8s.io
      kind: ValidatingWebhookConfiguration
      name: kyverno-cleanup-validating-webhook-cfg
      jqPathExpressions:
        - .webhooks[].clientConfig.caBundle
    - group: admissionregistration.k8s.io
      kind: ValidatingWebhookConfiguration
      name: kyverno-exception-validating-webhook-cfg
      jqPathExpressions:
        - .webhooks[].clientConfig.caBundle
    - group: admissionregistration.k8s.io
      kind: ValidatingWebhookConfiguration
      name: kyverno-global-context-validating-webhook-cfg
      jqPathExpressions:
        - .webhooks[].clientConfig.caBundle
    - group: admissionregistration.k8s.io
      kind: ValidatingWebhookConfiguration
      name: kyverno-policy-validating-webhook-cfg
      jqPathExpressions:
        - .webhooks[].clientConfig.caBundle
    - group: admissionregistration.k8s.io
      kind: ValidatingWebhookConfiguration
      name: kyverno-resource-validating-webhook-cfg
      jqPathExpressions:
        - .webhooks[].clientConfig.caBundle
    - group: admissionregistration.k8s.io
      kind: ValidatingWebhookConfiguration
      name: kyverno-ttl-validating-webhook-cfg
      jqPathExpressions:
        - .webhooks[].clientConfig.caBundle
    - group: apiextensions.k8s.io
      kind: CustomResourceDefinition
      name: deletingpolicies.policies.kyverno.io
      jqPathExpressions:
        - .spec
    - group: apiextensions.k8s.io
      kind: CustomResourceDefinition
      name: generatingpolicies.policies.kyverno.io
      jqPathExpressions:
        - .spec
    - group: apiextensions.k8s.io
      kind: CustomResourceDefinition
      name: imagevalidatingpolicies.policies.kyverno.io
      jqPathExpressions:
        - .spec
    - group: apiextensions.k8s.io
      kind: CustomResourceDefinition
      name: mutatingpolicies.policies.kyverno.io
      jqPathExpressions:
        - .spec
    - group: apiextensions.k8s.io
      kind: CustomResourceDefinition
      name: namespaceddeletingpolicies.policies.kyverno.io
      jqPathExpressions:
        - .spec
    - group: apiextensions.k8s.io
      kind: CustomResourceDefinition
      name: namespacedgeneratingpolicies.policies.kyverno.io
      jqPathExpressions:
        - .spec
    - group: apiextensions.k8s.io
      kind: CustomResourceDefinition
      name: namespacedimagevalidatingpolicies.policies.kyverno.io
      jqPathExpressions:
        - .spec
    - group: apiextensions.k8s.io
      kind: CustomResourceDefinition
      name: namespacedmutatingpolicies.policies.kyverno.io
      jqPathExpressions:
        - .spec
    - group: apiextensions.k8s.io
      kind: CustomResourceDefinition
      name: namespacedvalidatingpolicies.policies.kyverno.io
      jqPathExpressions:
        - .spec
    - group: apiextensions.k8s.io
      kind: CustomResourceDefinition
      name: policyexceptions.policies.kyverno.io
      jqPathExpressions:
        - .spec
    - group: apiextensions.k8s.io
      kind: CustomResourceDefinition
      name: validatingpolicies.policies.kyverno.io
      jqPathExpressions:
        - .spec
    - group: apiextensions.k8s.io
      kind: CustomResourceDefinition
      jqPathExpressions:
        - .metadata.annotations
        - .metadata.labels
        - .spec
  source:
    repoURL: ${local.policies_repo_url_cluster}
    targetRevision: main
    path: ${local.vendored_chart_paths.kyverno}
    helm:
      releaseName: kyverno
      values: |
        crds:
          install: true
          migration:
            enabled: false
        admissionController:
          replicas: 1
          securityContext:
            runAsNonRoot: true
            runAsUser: 65534
            runAsGroup: 65534
          forceFailurePolicyIgnore:
            enabled: true
          container:
            resources:
              limits:
                memory: 256Mi
              requests:
                memory: 128Mi
          image:
            registry: ${var.hardened_image_registry}
            repository: kyverno
            tag: 1.17.1-debian13
          initContainer:
            image:
              registry: ${var.hardened_image_registry}
              repository: kyverno-init
              tag: 1.17.1-debian13
            securityContext:
              runAsNonRoot: true
              runAsUser: 65534
              runAsGroup: 65534
        backgroundController:
          replicas: 1
          securityContext:
            runAsNonRoot: true
            runAsUser: 65534
            runAsGroup: 65534
          container:
            resources:
              limits:
                memory: 192Mi
              requests:
                memory: 64Mi
          image:
            registry: ${var.hardened_image_registry}
            repository: kyverno-background-controller
            tag: 1.17.1-debian13
        cleanupController:
          replicas: 1
          securityContext:
            runAsNonRoot: true
            runAsUser: 65534
            runAsGroup: 65534
          container:
            resources:
              limits:
                memory: 128Mi
              requests:
                memory: 64Mi
          image:
            registry: ${var.hardened_image_registry}
            repository: kyverno-cleanup-controller
            tag: 1.17.1-debian13
        reportsController:
          replicas: 1
          securityContext:
            runAsNonRoot: true
            runAsUser: 65534
            runAsGroup: 65534
          container:
            resources:
              limits:
                memory: 128Mi
              requests:
                memory: 64Mi
          image:
            registry: ${var.hardened_image_registry}
            repository: kyverno-reports-controller
            tag: 1.17.1-debian13
        cleanupJobs:
          admissionReports:
            enabled: false
          clusterAdmissionReports:
            enabled: false
          ephemeralReports:
            enabled: false
          clusterEphemeralReports:
            enabled: false
          updateRequests:
            enabled: false
        webhooksCleanup:
          enabled: false
        policyReportsCleanup:
          enabled: false
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
  ]
}

resource "kubectl_manifest" "argocd_app_kyverno_policies" {
  count = var.enable_policies && var.enable_argocd && !var.enable_app_of_apps ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kyverno-policies
  namespace: ${var.argocd_namespace}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: kyverno
    server: https://kubernetes.default.svc
  source:
    repoURL: ${local.policies_repo_url_cluster}
    targetRevision: main
    path: cluster-policies/kyverno
  ignoreDifferences:
    - group: kyverno.io
      kind: ClusterPolicy
      jqPathExpressions:
        - '.spec.rules[] | select(.name | startswith("autogen-"))'
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
    kubernetes_secret_v1.argocd_repo_policies,
    null_resource.sync_gitea_policies_repo,
    null_resource.argocd_repo_server_restart,
    kubectl_manifest.argocd_app_kyverno,
  ]
}

resource "kubectl_manifest" "argocd_app_policy_reporter" {
  count = var.enable_policies && var.enable_argocd && !var.enable_app_of_apps ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: policy-reporter
  namespace: ${var.argocd_namespace}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: policy-reporter
    server: https://kubernetes.default.svc
  source:
    repoURL: ${local.policies_repo_url_cluster}
    targetRevision: main
    path: ${local.vendored_chart_paths.policy_reporter}
    helm:
      releaseName: policy-reporter
      values: |
        ui:
          enabled: true
        plugin:
          kyverno:
            enabled: true
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
    kubectl_manifest.argocd_app_kyverno,
  ]
}

resource "kubectl_manifest" "argocd_app_cilium_policies" {
  count = var.enable_policies && var.enable_argocd && !var.enable_app_of_apps ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cilium-policies
  namespace: ${var.argocd_namespace}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: kube-system
    server: https://kubernetes.default.svc
  source:
    repoURL: ${local.policies_repo_url_cluster}
    targetRevision: main
    path: cluster-policies/cilium
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=false
      - ServerSideApply=true
      - SkipDryRunOnMissingResource=true
__YAML__

  wait              = true
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = false

  depends_on = [
    kubernetes_secret_v1.argocd_repo_policies,
    null_resource.sync_gitea_policies_repo,
    null_resource.argocd_repo_server_restart,
    helm_release.cilium,
  ]
}
