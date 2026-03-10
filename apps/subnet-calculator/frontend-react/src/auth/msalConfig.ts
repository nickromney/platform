/**
 * MSAL Configuration for local development
 * Used when AUTH_METHOD === 'msal'
 */

import { type Configuration, LogLevel } from '@azure/msal-browser'
import { APP_CONFIG } from '../config'

/**
 * Configuration object to be passed to MSAL instance on creation
 */
export const msalConfig: Configuration = {
  auth: {
    clientId: APP_CONFIG.auth.clientId || '',
    authority: `https://login.microsoftonline.com/${APP_CONFIG.auth.tenantId || 'common'}`,
    redirectUri: APP_CONFIG.auth.redirectUri || window.location.origin,
  },
  cache: {
    cacheLocation: 'localStorage', // Store tokens in localStorage
    storeAuthStateInCookie: false, // Set to true for IE11 or Edge
  },
  system: {
    loggerOptions: {
      loggerCallback: (level, message, containsPii) => {
        if (containsPii) {
          return
        }
        switch (level) {
          case LogLevel.Error:
            console.error(message)
            return
          case LogLevel.Info:
            console.info(message)
            return
          case LogLevel.Verbose:
            console.debug(message)
            return
          case LogLevel.Warning:
            console.warn(message)
            return
          default:
            return
        }
      },
    },
  },
}

/**
 * Scopes for the access token
 */
export const loginRequest = {
  scopes: ['User.Read'],
}
