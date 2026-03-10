import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.tsx'

// Runtime config is injected via window.RUNTIME_CONFIG by server.js (Azure Web App)
// or available as build-time env vars (Static Web Apps, local dev)
createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>
)
