import nextra from 'nextra'

const withNextra = nextra({
  latex: true,
  defaultShowCopyCode: true,
  search: {
    codeblocks: false
  },
  contentDirBasePath: '/'
})

export default withNextra({
  reactStrictMode: true,
  async redirects() {
    return [
      { source: '/kubernetes', destination: '/journeys/kubernetes', permanent: false },
      { source: '/terraform-terragrunt', destination: '/journeys/terraform-terragrunt', permanent: false },
      { source: '/cilium-hubble', destination: '/journeys/cilium-hubble', permanent: false },
      { source: '/kyverno', destination: '/journeys/kyverno', permanent: false },
      { source: '/argocd-gitops', destination: '/journeys/argocd-gitops', permanent: false },
      { source: '/gitea-version-control', destination: '/journeys/gitea-version-control', permanent: false },
      { source: '/sso-dex-keycloak', destination: '/journeys/sso-dex-keycloak', permanent: false },
      { source: '/apis-apim-simulator', destination: '/journeys/apis-apim-simulator', permanent: false },
      { source: '/self-hosted-ai-sentiment', destination: '/journeys/self-hosted-ai-sentiment', permanent: false },
      { source: '/gaps', destination: '/journeys/gaps', permanent: false }
    ]
  }
})
