# Security Policy

`apim-simulator` is a local development and testing tool. It is not intended for production or internet-facing deployment.

## Safe Use

- Keep the simulator on the local machine or a private lab network you control.
- Do not expose or port-forward the demo Keycloak service on `localhost:8180`.
- Do not expose management-enabled stacks, demo tenant keys, or tutorial subscription keys beyond local development use.
- Demo credentials and keys checked into this repository are intentional and exist only for local tutorials, smoke tests, and example clients.

## Reporting

Report security issues through GitHub Security Advisories if available:

- [GitHub Security Advisories](https://github.com/nickromney/apim-simulator/security/advisories/new)

If that flow is unavailable, open a GitHub issue without posting exploit details or live secrets:

- [GitHub Issues](https://github.com/nickromney/apim-simulator/issues)
