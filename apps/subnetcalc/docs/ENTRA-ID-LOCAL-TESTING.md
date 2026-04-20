# Entra ID Local Testing

For Part 10 (Azure AD/Entra ID integration), we can use this tool for local testing:

**GitHub Repository:** <https://github.com/rysweet/entra-id-gen-exp>

This appears to be a legitimate tool for testing Entra ID integration locally without requiring an actual Azure AD tenant.

## Notes

- Review this tool when we reach Part 10
- Evaluate if it supports the OAuth 2.0 flows we need
- Check if it can simulate token issuance and validation
- Determine if it works with FastAPI's OAuth2 schemes

## Alternative Approaches

If the above tool doesn't work:

1. **Mock JWT tokens** - Create tokens that mimic Entra ID structure
1. **Azure AD B2C Free Tier** - Use actual Azure service (limited free tier)
1. **MSAL test environment** - Microsoft Authentication Library has test modes
1. **Local OIDC provider** - Tools like Keycloak or ORY Hydra

We'll evaluate these when we get to Part 10.
