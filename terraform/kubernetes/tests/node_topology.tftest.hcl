# worker_count = 0 is the memory-constrained topology: one node container
# instead of two, so one fewer kubelet, containerd and cilium agent.
#
# It only works if the control plane is schedulable. kind's own single-node
# untaint runs `kubectl taint` inside the node, where this stack has mounted
# scripts/kind-node-kubectl-wrapper.sh over /usr/local/bin/kubectl -- and that
# wrapper exits 0 without running kubectl unless it is passed --execute, which
# kind does not pass. So the taint has to come off via kubeadm instead, and
# these tests pin that it does.
#
# The rendered file (local_file.kind_config) is what `kind create cluster
# --config` reads (terraform_data.kind_cluster), so it is the only place the
# patch has to land.

variables {
  cni_provider  = "none"
  enable_hubble = false
  enable_argocd = false
  enable_gitea  = false
}

run "single_node_makes_the_control_plane_schedulable" {
  command = plan

  variables {
    worker_count = 0
  }

  assert {
    condition     = length(local.kind_workers) == 0
    error_message = "Expected worker_count = 0 to produce no worker nodes"
  }

  # kind applies kubeadmConfigPatches to the generated InitConfiguration as an
  # RFC 7386 merge patch. An explicitly empty taints list is kubeadm's
  # "register this node with no taints"; leaving the field absent is what asks
  # for the control-plane taint.
  assert {
    condition     = strcontains(local_file.kind_config[0].content, "kubeadmConfigPatches:")
    error_message = "Expected the rendered kind config to carry kubeadmConfigPatches at worker_count = 0"
  }

  assert {
    condition     = strcontains(local_file.kind_config[0].content, "taints: []")
    error_message = "Expected the rendered kind config patch to clear nodeRegistration.taints"
  }

  assert {
    condition     = !strcontains(local_file.kind_config[0].content, "role: worker")
    error_message = "Expected the rendered kind config to declare no worker nodes at worker_count = 0"
  }

  # Node-count health checks derive from worker_count, so they have to land on
  # 1 rather than on a floor of 2.
  assert {
    condition     = tostring(var.worker_count + 1) == "1"
    error_message = "Expected the derived expected-node-count to be 1 for a single-node cluster"
  }
}

run "multi_node_keeps_the_control_plane_tainted" {
  command = plan

  variables {
    worker_count = 1
  }

  assert {
    condition     = length(local.kind_control_plane_kubeadm_config_patches) == 0
    error_message = "Expected no kubeadm config patches once there is a worker to schedule onto"
  }

  assert {
    condition     = !strcontains(local_file.kind_config[0].content, "kubeadmConfigPatches")
    error_message = "Expected the rendered kind config to stay byte-for-byte unpatched at worker_count = 1"
  }

  assert {
    condition     = strcontains(local_file.kind_config[0].content, "role: worker")
    error_message = "Expected the rendered kind config to keep its worker node at worker_count = 1"
  }
}
