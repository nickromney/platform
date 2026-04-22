import type { ReactNode } from 'react'
import { StandardAuthProvider } from './standardAuthProvider'

export default function BasicAuthWrapper({ children }: { children: ReactNode }) {
  return <StandardAuthProvider>{children}</StandardAuthProvider>
}
