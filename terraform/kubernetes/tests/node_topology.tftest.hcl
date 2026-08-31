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
# The stack writes the kind config twice: inline into the tehcyx/kind provider
# (kind_cluster.local) and as a rendered file (local_file.kind_config) for the
# kind CLI and the diagnostics that read it. Both are asserted, because a fix
# to only one of them is a single-node cluster that schedules nothing.

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

  # The provider path. tehcyx/kind v0.11.0 maps node.kubeadm_config_patches
  # onto v1alpha4.Node.KubeadmConfigPatches, which kind applies to the
  # generated kubeadm InitConfiguration as an RFC 7386 merge patch.
  assert {
    condition     = length(kind_cluster.local[0].kind_config[0].node) == 1
    error_message = "Expected the inline kind_config to declare exactly one node at worker_count = 0"
  }

  assert {
    condition     = kind_cluster.local[0].kind_config[0].node[0].role == "control-plane"
    error_message = "Expected the only inline node to be the control plane"
  }

  # An explicitly empty taints list is kubeadm's "register this node with no
  # taints"; leaving the field absent is what asks for the control-plane taint.
  assert {
    condition = length([
      for patch in kind_cluster.local[0].kind_config[0].node[0].kubeadm_config_patches :
      patch
      if strcontains(patch, "kind: InitConfiguration") && strcontains(patch, "taints: []")
    ]) == 1
    error_message = "Expected the inline control-plane node to carry a kubeadm patch clearing nodeRegistration.taints"
  }

  # The rendered-template path has to agree with the inline path.
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
    condition     = length(kind_cluster.local[0].kind_config[0].node[0].kubeadm_config_patches) == 0
    error_message = "Expected the inline control-plane node to keep its default taint at worker_count = 1"
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
