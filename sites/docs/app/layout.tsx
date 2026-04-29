import { Footer, Layout, Navbar } from 'nextra-theme-docs'
import { Head } from 'nextra/components'
import { getPageMap } from 'nextra/page-map'
import 'nextra-theme-docs/style.css'
import './styles.css'

export const metadata = {
  metadataBase: new URL('http://localhost:3000'),
  title: {
    default: 'Platform Docs',
    template: '%s - Platform Docs'
  },
  description:
    'Local platform-engineering docs for running the Kubernetes stack, sample apps, and supporting operations.',
  icons: {
    icon: [{ url: '/favicon.ico' }, { url: '/icon.svg', type: 'image/svg+xml' }],
  }
}

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  const pageMap = await getPageMap()
  const navbar = (
    <Navbar
      logo={<strong>Platform</strong>}
      projectLink="https://github.com/nickromney/platform"
    />
  )
  const footer = <Footer>Local platform docs. Source repo: ~/Developer/personal/platform.</Footer>

  return (
    <html lang="en" dir="ltr" suppressHydrationWarning>
      <Head />
      <body>
        <div className="platform-banner">
          These docs describe a local-only platform stack. Treat public exposure as a separate security review.
        </div>
        <Layout
          pageMap={pageMap}
          navbar={navbar}
          footer={footer}
          docsRepositoryBase="https://github.com/nickromney/platform-docs/blob/main"
          editLink="Edit this page"
          feedback={{ content: 'Question or correction? Leave feedback.' }}
          sidebar={{ defaultMenuCollapseLevel: 1, autoCollapse: true }}
          toc={{ float: true }}
          navigation={{ prev: true, next: true }}
          darkMode
        >
          {children}
        </Layout>
      </body>
    </html>
  )
}
