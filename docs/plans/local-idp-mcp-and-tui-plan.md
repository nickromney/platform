# Local IDP MCP And TUI Plan

The TUI, MCP, and developer portal should be clients of the same FastAPI
contract. They are surfaces over the IDP, not the IDP itself.

Initial read-only capabilities:

- platform status
- runtime metadata
- catalog list and app detail
- deployments
- scorecards
- secret binding posture
- available actions

Guarded dry-run capabilities:

- create environment
- delete environment
- promote deployment
- roll back deployment
- scaffold app

MCP mutating tools default to dry-run and return confirmation metadata. The TUI
may keep its existing status JSON fallback while the FastAPI service is being
introduced.
