import { defineConfig } from 'vite'

export default defineConfig({
  test: {
    environment: 'jsdom',
  },
  build: {
    outDir: 'dist',
    sourcemap: false,
  },
})
