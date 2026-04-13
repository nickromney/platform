VALID_STAGES := 100 200 300 400 500 600 700 800 900

STAGE_FILE_REL_100 := stages/100-cluster.tfvars
STAGE_FILE_REL_200 := stages/200-cilium.tfvars
STAGE_FILE_REL_300 := stages/300-hubble.tfvars
STAGE_FILE_REL_400 := stages/400-argocd.tfvars
STAGE_FILE_REL_500 := stages/500-gitea.tfvars
STAGE_FILE_REL_600 := stages/600-policies.tfvars
STAGE_FILE_REL_700 := stages/700-app-repos.tfvars
STAGE_FILE_REL_800 := stages/800-gateway-tls.tfvars
STAGE_FILE_REL_900 := stages/900-sso.tfvars

STAGE_DESC_KIND_100 := cluster
STAGE_DESC_KIND_200 := cilium
STAGE_DESC_KIND_300 := hubble
STAGE_DESC_KIND_400 := argocd core
STAGE_DESC_KIND_500 := gitea + full argocd controllers
STAGE_DESC_KIND_600 := policies
STAGE_DESC_KIND_700 := app repos + actions runner
STAGE_DESC_KIND_800 := observability + headlamp + gateway-tls
STAGE_DESC_KIND_900 := full stack + sso

STAGE_DESC_LIMA_100 := bootstrap k3s on Lima
STAGE_DESC_LIMA_200 := cilium
STAGE_DESC_LIMA_300 := hubble
STAGE_DESC_LIMA_400 := argocd core
STAGE_DESC_LIMA_500 := gitea
STAGE_DESC_LIMA_600 := policies
STAGE_DESC_LIMA_700 := app workloads from local images
STAGE_DESC_LIMA_800 := gateway tls + observability
STAGE_DESC_LIMA_900 := sso
