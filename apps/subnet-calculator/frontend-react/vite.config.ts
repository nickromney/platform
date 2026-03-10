import react from '@vitejs/plugin-react'
import { resolve } from 'path'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@subnet-calculator/shared-frontend/api': resolve(__dirname, '../shared-frontend/src/api/index.ts'),
      '@subnet-calculator/shared-frontend/types': resolve(__dirname, '../shared-frontend/src/types/index.ts'),
      '@subnet-calculator/shared-frontend': resolve(__dirname, '../shared-frontend/src/index.ts'),
    },
  },
})
