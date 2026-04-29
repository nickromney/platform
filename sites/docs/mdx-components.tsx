import { Callout, Cards, FileTree, Steps, Tabs } from 'nextra/components'
import { useMDXComponents as getDocsMDXComponents } from 'nextra-theme-docs'
import { ThemeImage } from './components/ThemeMedia'

const docsComponents = getDocsMDXComponents()

export function useMDXComponents(components = {}) {
  return {
    ...docsComponents,
    Cards,
    Callout,
    FileTree,
    Steps,
    Tabs,
    ThemeImage,
    ...components
  }
}
