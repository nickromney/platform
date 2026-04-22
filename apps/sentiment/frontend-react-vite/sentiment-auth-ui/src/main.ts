import { mountApp } from './app'

const root = document.getElementById('root')

if (!root) {
  throw new Error('Missing #root container')
}

mountApp(root)
