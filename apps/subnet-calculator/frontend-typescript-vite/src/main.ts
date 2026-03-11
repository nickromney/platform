/**
 * Main application entry point
 */

import '../../shared-frontend/src/styles.css'
import { apiClient } from './api'
import { getAuthMethod, getStackDescription } from './config'
import { getCurrentUser } from './entraid-auth'
import { renderResults, showApiStatus, showError, showLoading, showUserInfo } from './ui'

// Theme management
function initTheme(): void {
  const savedTheme = localStorage.getItem('theme') || 'dark'
  document.documentElement.setAttribute('data-theme', savedTheme)
  updateThemeIcon(savedTheme)
}

function updateThemeIcon(theme: string): void {
  const icon = document.getElementById('theme-icon')
  if (icon) {
    icon.textContent = theme === 'dark' ? '☀️' : '🌙'
  }
}

function toggleTheme(): void {
  const currentTheme = document.documentElement.getAttribute('data-theme')
  const newTheme = currentTheme === 'dark' ? 'light' : 'dark'
  document.documentElement.setAttribute('data-theme', newTheme)
  localStorage.setItem('theme', newTheme)
  updateThemeIcon(newTheme)
}

// API health check
async function checkApiHealth(): Promise<void> {
  try {
    const health = await apiClient.checkHealth()
    showApiStatus(true, health.service, health.version, apiClient.getBaseUrl())
  } catch (error) {
    console.error('API health check failed:', error)
    showApiStatus(false)
    redirectToLoggedOutIfNeeded(error)
  }
}

// Form submission
async function handleSubmit(event: Event): Promise<void> {
  event.preventDefault()

  const form = event.target as HTMLFormElement
  const formData = new FormData(form)
  const address = formData.get('address') as string
  const mode = (formData.get('mode') as string) || 'Standard'

  if (!address) {
    showError('Address is required')
    return
  }

  // Validate mode is a valid CloudMode
  const validModes = ['Standard', 'AWS', 'Azure', 'OCI']
  const cloudMode = validModes.includes(mode) ? mode : 'Standard'

  // Start performance timing
  const overallRequestTimestamp = new Date().toISOString()
  const overallStartTime = performance.now()

  showLoading()

  try {
    const { results, timing, networkDiagnostics, secondaryNetworkDiagnostics } = await apiClient.performLookup(
      address,
      cloudMode as 'Standard' | 'AWS' | 'Azure' | 'OCI'
    )

    // End performance timing
    const overallResponseTimestamp = new Date().toISOString()
    const overallEndTime = performance.now()
    const overallDuration = overallEndTime - overallStartTime

    // Store timing for display
    const timingInfo = {
      overallDuration,
      overallRequestTimestamp,
      overallResponseTimestamp,
      address,
      mode: cloudMode,
      apiCalls: timing.apiCalls,
    }

    renderResults(results, timingInfo, networkDiagnostics, secondaryNetworkDiagnostics)
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unknown error occurred'
    showError(`Error: ${message}`)
  }
}

// Example button clicks
function handleExampleClick(event: Event): void {
  const button = event.target as HTMLButtonElement
  const address = button.dataset.address
  if (address) {
    const input = document.getElementById('ip-address') as HTMLInputElement
    if (input) {
      input.value = address
    }
  }
}

// Initialize app
async function init(): Promise<void> {
  // Set stack description based on config
  const stackDesc = document.getElementById('stack-description')
  if (stackDesc) {
    stackDesc.textContent = getStackDescription()
  }

  // Initialize theme
  initTheme()

  // Check authentication and show user info
  const authMethod = getAuthMethod()
  if (authMethod === 'entraid') {
    // Fetch and display Entra ID user
    const user = await getCurrentUser()
    showUserInfo(user, authMethod)
  } else {
    // For JWT or no auth, just update UI accordingly
    showUserInfo(null, authMethod)
  }

  // Theme switcher
  const themeSwitcher = document.getElementById('theme-switcher')
  if (themeSwitcher) {
    themeSwitcher.addEventListener('click', toggleTheme)
  }

  // Form submission
  const form = document.getElementById('lookup-form')
  if (form) {
    form.addEventListener('submit', handleSubmit)
  }

  // Example buttons
  const exampleButtons = document.querySelectorAll('.example-btn')
  for (const button of exampleButtons) {
    button.addEventListener('click', handleExampleClick)
  }

  // Check API health
  checkApiHealth()
}

function redirectToLoggedOutIfNeeded(error: unknown): void {
  const authMethod = getAuthMethod()
  if (authMethod !== 'oidc') {
    return
  }

  if (window.location.pathname.includes('/logged-out.html')) {
    return
  }

  const errorMessages = getErrorMessages(error)
  const unauthorized = errorMessages.some((msg) => {
    return msg.includes('401') || msg.includes('403') || msg.includes('failed to fetch')
  })

  if (unauthorized) {
    window.location.replace('/logged-out.html')
  }
}

function getErrorMessages(error: unknown): string[] {
  if (!(error instanceof Error)) {
    return []
  }

  const normalized = error.message.toLowerCase()
  const messages = [normalized]

  const cause = (error as Error & { cause?: unknown }).cause
  if (cause instanceof Error) {
    messages.push(cause.message.toLowerCase())
  }

  return messages
}

// Start app when DOM is ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init)
} else {
  init()
}
