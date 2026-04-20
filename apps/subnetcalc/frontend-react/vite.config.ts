import react from '@vitejs/plugin-react'
import { resolve } from 'path'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@subnetcalc/shared-frontend/api': resolve(__dirname, '../shared-frontend/src/api/index.ts'),
      '@subnetcalc/shared-frontend/types': resolve(__dirname, '../shared-frontend/src/types/index.ts'),
      '@subnetcalc/shared-frontend': resolve(__dirname, '../shared-frontend/src/index.ts'),
    },
  },
})
