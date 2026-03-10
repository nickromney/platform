# Backend profile: existing kubeconfig cluster (for local k3s/lima or any external cluster)

provision_kind_cluster = false
cluster_name           = "local-existing"
kubeconfig_path        = "~/.kube/config"
kubeconfig_context     = ""
cilium_native_routing_cidr = "10.42.0.0/16"
argocd_image_repository    = "quay.io/argoproj/argocd"
argocd_image_tag           = "v3.2.7"
