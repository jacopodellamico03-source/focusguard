import preact from '@preact/preset-vite'
import { defineConfig } from 'vitest/config'

export default defineConfig({
  // GitHub Pages serve il sito da /focusguard/.
  base: '/focusguard/',
  plugins: [preact()],
  test: {
    environment: 'node',
    env: { TZ: 'Europe/Rome' },
    include: ['src/**/*.test.ts'],
  },
})
