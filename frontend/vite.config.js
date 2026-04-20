import { existsSync } from 'node:fs'
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

const isDockerRuntime = existsSync('/.dockerenv')
const backendOrigin = process.env.VITE_BACKEND_ORIGIN || (isDockerRuntime ? 'http://nginx:8080' : 'http://localhost:8080')

export default defineConfig({
  plugins: [vue()],
  server: {
    allowedHosts: ['localhost', '127.0.0.1', 'app.lvh.me'],
    proxy: {
      '/products': {
        target: backendOrigin,
        changeOrigin: true,
      },
    },
  },
})
