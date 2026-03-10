# Stack intentions 20 October 2025

swa 1: public, @subnet-calculator/frontend-typescript-vite as frontend, calling backend @api-fastapi-azure-function/
but via a public uri.

- name for swa: swa-subnet-calc-noauth
- custom domain: <https://static-swa-no-auth.publiccloudexperiments.net>
- function app @subnet-calculator/api-fastapi-azure-function/ on azure app services
- custom domain for function app: <https://subnet-calc-fa-jwt-auth.publiccloudexperiments.net>
- frontend should communicate with backend function app with JWT auth

swa 2: public, @subnet-calculator/frontend-typescript-vite/ as frontend, calling swa linked backend
@subnet-calculator/api-fastapi-azure-function/

- name for swa: swa-subnet-calc-entraid-linked
- custom domain: <https://static-swa-entraid-linked.publiccloudexperiments.net>
- function app @subnet-calculator/api-fastapi-azure-function/ on azure app services
- custom domain for function app: <https://subnet-calc-fa-entraid-linked.publiccloudexperiments.net>
- frontend should communicate with backend function app using static web apps linked authentication
- ensure login, logout, redirect uris support azurestaticapps.net and publiccloudexperiments.net URIs

swa 3: private endpoint, @subnet-calculator/frontend-typescript-vite/ as frontend, calling swa linked backend
@subnet-calculator/api-fastapi-azure-function/

- name for swa: swa-subnet-calc-private-endpoint
- custom domain: <https://static-swa-private-endpoint.publiccloudexperiments.net>
- function app @subnet-calculator/api-fastapi-azure-function/ on azure app services
- no custom domain required for function app, but if we can specify a name, then subnet-calc-fa-private-endpoint
- swa should set publiccloudexperiments.net domain as primary
- swa should set azurestaticapps.net domain as disabled (may need a REST API call to disable this)
- private endpoints throughout
- create a vnet if you need to
- ensure login, logout, redirect uris support publiccloudexperiments.net URI
