import { resolve } from 'node:path'
import { defineConfig } from 'vite'

// https://vitejs.dev/config/
export default defineConfig({
  server: {
    host: '0.0.0.0',
    port: 3000,
    strictPort: true,
  },
  preview: {
    host: '0.0.0.0',
    port: 3000,
    strictPort: true,
  },
  build: {
    outDir: 'dist',
    sourcemap: true,
  },
  resolve: {
    alias: {
      // Order matters - specific paths before general path
      '@subnet-calculator/shared-frontend/api': resolve(__dirname, '../shared-frontend/src/api/index.ts'),
      '@subnet-calculator/shared-frontend/types': resolve(__dirname, '../shared-frontend/src/types/index.ts'),
      '@subnet-calculator/shared-frontend': resolve(__dirname, '../shared-frontend/src/index.ts'),
    },
  },
})
