# Local IDP Implementation Roadmap

The implementation order is contract first, then API, then user surfaces.

1. Add JSON schemas for catalog, runtime, status, actions, deployments, secret
   bindings, scorecards, environment requests, and audit events.
2. Add a FastAPI IDP core that reads existing catalog/status/script outputs.
3. Add explicit runtime adapters for kind, Lima, and generic Kubernetes.
4. Add dry-run workflow APIs for environment requests, promotion, rollback, and
   app scaffolding.
5. Add audit events under `.run/idp/audit.jsonl`.
6. Add a lightweight developer portal that consumes only FastAPI.
7. Add SDK and MCP clients over the same API contract.
8. Add resource-aware kind `950-local-idp` integration after the API and portal
   contract is stable.

The repo is the IDP. The developer portal is a developer experience layer over
that IDP. It does not run Terraform directly and does not embed cluster-admin
forms.
