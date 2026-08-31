kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  apiServerAddress: "127.0.0.1"
  apiServerPort: ${api_server_port}
  disableDefaultCNI: true
  kubeProxyMode: "${kube_proxy_mode}"
nodes:
  - role: control-plane
%{ if length(control_plane_kubeadm_config_patches) > 0 ~}
    kubeadmConfigPatches:
%{ for config_patch in control_plane_kubeadm_config_patches ~}
      - |
        ${indent(8, trimspace(config_patch))}
%{ endfor ~}
%{ endif ~}
%{ if length(ports) > 0 ~}
    extraPortMappings:
%{ for port in ports ~}
      - containerPort: ${port.container_port}
        hostPort: ${port.host_port}
%{ if try(port.listen_address, "") != "" ~}
        listenAddress: "${port.listen_address}"
%{ endif ~}
        protocol: ${port.protocol}
%{ endfor ~}
%{ endif ~}
%{ if length(extra_mounts) > 0 ~}
    extraMounts:
%{ for mnt in extra_mounts ~}
      - hostPath: ${mnt.host_path}
        containerPath: ${mnt.container_path}
        readOnly: ${mnt.read_only}
%{ endfor ~}
%{ endif ~}
%{ for _ in workers ~}
  - role: worker
%{ if length(extra_mounts) > 0 ~}
    extraMounts:
%{ for mnt in extra_mounts ~}
      - hostPath: ${mnt.host_path}
        containerPath: ${mnt.container_path}
        readOnly: ${mnt.read_only}
%{ endfor ~}
%{ endif ~}
%{ endfor ~}
