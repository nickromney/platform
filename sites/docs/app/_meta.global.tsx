const meta = {
  index: {
    type: 'page',
    title: 'Start'
  },
  tutorials: {
    type: 'page',
    title: 'Tutorials',
    items: {
      'first-kind-stack': 'Run the Kind stack',
      'kind-walkthrough': 'Kind full walkthrough',
      'lima-walkthrough': 'Lima full walkthrough',
      'slicer-walkthrough': 'Slicer full walkthrough',
      'sd-wan-lima-walkthrough': 'SD-WAN Lima lab',
      'container-workflow': 'Build and use containers',
      'first-app-loop': 'Run an app locally'
    }
  },
  journeys: {
    type: 'page',
    title: 'Journeys',
    items: {
      index: 'All journeys',
      kubernetes: 'Learn Kubernetes',
      'terraform-terragrunt': 'Learn Terraform and Terragrunt',
      'cilium-hubble': 'Learn Cilium and Hubble',
      kyverno: 'Learn Kyverno',
      'argocd-gitops': 'Learn GitOps with Argo CD',
      'gitea-version-control': 'Learn Gitea',
      'sso-dex-keycloak': 'Learn SSO with Dex and Keycloak',
      'apis-apim-simulator': 'Learn APIs with APIM simulator',
      'self-hosted-ai-sentiment': 'Learn self-hosted AI',
      gaps: 'Closure index'
    }
  },
  concepts: {
    type: 'page',
    title: 'Concepts',
    items: {
      'mental-model': 'Mental model',
      'stage-ladder': 'Stage ladder',
      'reader-paths': 'Reader paths',
      'iac-boundaries': 'IaC boundaries',
      'terraform-opentofu-terragrunt': 'Terraform, OpenTofu, and Terragrunt',
      'manifest-assembly': 'Manifest assembly',
      'platform-pathways': 'Platform pathways',
      'version-management': 'Version management',
      'identity-and-access': 'Identity and access',
      'local-runtimes': 'Local runtimes',
      visuals: 'Visual explanations'
    }
  },
  operations: {
    type: 'page',
    title: 'Operations',
    items: {
      prerequisites: 'Prerequisites',
      'tooling-requirements': 'Tooling requirements',
      'daily-loop': 'Daily loop',
      'guided-workflows': 'Guided workflows',
      'health-and-urls': 'Health and URLs',
      'review-environments': 'Review environments',
      footguns: 'Footguns',
      'reset-and-cleanup': 'Reset and cleanup',
      troubleshooting: 'Troubleshooting'
    }
  },
  apps: {
    type: 'page',
    title: 'Sample Apps',
    items: {
      'patterns': 'Application patterns',
      'apim-simulator': 'APIM simulator',
      'platform-mcp': 'Platform MCP',
      'backstage-idp': 'Portal and IDP',
      subnetcalc: 'Subnetcalc',
      sentiment: 'Sentiment'
    }
  },
  security: {
    type: 'page',
    title: 'Security',
    items: {
      'hardening-choices': 'Hardening choices',
      cilium: 'Cilium policy',
      hubble: 'Hubble flow evidence',
      kyverno: 'Kyverno admission',
      'public-demo-boundary': 'Public demo boundary'
    }
  },
  reference: {
    type: 'page',
    title: 'Reference',
    items: {
      commands: 'Commands',
      contracts: 'Contracts',
      'shell-scripts': 'Shell scripts',
      makefiles: 'Makefiles',
      'source-repo-cleanup-plan': 'Source cleanup plan',
      'repository-map': 'Repository map',
      glossary: 'Glossary'
    }
  }
} as const

export default meta
