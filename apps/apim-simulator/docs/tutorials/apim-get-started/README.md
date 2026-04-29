# APIM Get-Started Tutorial Mirror

This directory mirrors the 11-item [Azure API Management "Get started" tutorial sequence from Microsoft Learn](https://learn.microsoft.com/en-us/azure/api-management/), but mapped onto `apim-simulator`.

Source sequence, verified on 2026-04-08 from the API Management TOC:

1. Import your first API
2. Create and publish a product
3. Mock API responses
4. Protect your API
5. Monitor published APIs
6. Debug your APIs
7. Add revisions
8. Add multiple versions
9. Customise developer portal
10. Manage APIs in Visual Studio Code
11. Link to an API Center

## Orient Yourself First

If you are new to APIM, use the operator console before you start tutorial 1:

```bash
make up-ui
```

Then open `http://localhost:3007`, click `Load Local Demo`, and connect.

That gives you a low-context view of the simulator’s current APIs, routes,
policies, traces, and subscriptions before you begin modifying anything.

## Common Setup

Run the direct public stack from the repo root:

```bash
make up
export APIM_BASE=http://localhost:8000
export APIM_TENANT_KEY=local-dev-tenant-key
```

These tutorials assume the API you import in step 1 uses:

- API ID: `tutorial-api`
- API path: `tutorial-api`
- product ID: `tutorial-product`
- subscription ID: `tutorial-sub`
- subscription key: `tutorial-key`

Each mirrored step also has a companion `tutorialNN.sh` script in this
directory. Run `--setup` or `--execute` to apply a step. Run `--verify` to
validate the existing tutorial state without restarting the stack. Run
`--dry-run` to preview the setup path without side effects.

Use [`./docs/tutorials/apim-get-started/tutorial-cleanup.sh`](tutorial-cleanup.sh)
with `--dry-run` to preview or `--execute` to stop the tutorial compose stacks
and remove orphaned containers.

## Status Matrix

| Step | Microsoft Learn | Simulator | Local guide |
| --- | --- | --- | --- |
| 1 | [Import your first API](https://learn.microsoft.com/en-us/azure/api-management/import-and-publish) | Supported | [01](./01-import-your-first-api.md) |
| 2 | [Create and publish a product](https://learn.microsoft.com/en-us/azure/api-management/api-management-howto-add-products) | Supported | [02](./02-create-and-publish-a-product.md) |
| 3 | [Mock API responses](https://learn.microsoft.com/en-us/azure/api-management/mock-api-responses) | Supported | [03](./03-mock-api-responses.md) |
| 4 | [Protect your API](https://learn.microsoft.com/en-us/azure/api-management/transform-api) | Supported | [04](./04-protect-your-api.md) |
| 5 | [Monitor published APIs](https://learn.microsoft.com/en-us/azure/api-management/api-management-howto-use-azure-monitor) | Adapted | [05](./05-monitor-published-apis.md) |
| 6 | [Debug your APIs](https://learn.microsoft.com/en-us/azure/api-management/api-management-howto-api-inspector) | Adapted | [06](./06-debug-your-apis.md) |
| 7 | [Add revisions](https://learn.microsoft.com/en-us/azure/api-management/api-management-get-started-revise-api) | Partial | [07](./07-add-revisions.md) |
| 8 | [Add multiple versions](https://learn.microsoft.com/en-us/azure/api-management/api-management-get-started-publish-versions) | Supported | [08](./08-add-multiple-versions.md) |
| 9 | [Customise developer portal](https://learn.microsoft.com/en-us/azure/api-management/api-management-howto-developer-portal-customize) | Not appropriate | [09](./09-customise-developer-portal.md) |
| 10 | [Manage APIs in Visual Studio Code](https://learn.microsoft.com/en-us/azure/api-management/visual-studio-code-tutorial) | Adapted | [10](./10-manage-apis-in-visual-studio-code.md) |
| 11 | [Link to an API Center](https://learn.microsoft.com/en-us/azure/api-management/tutorials/link-api-center) | Not appropriate | [11](./11-link-to-an-api-center.md) |

## Interpretation Rules

- `Supported` means the simulator can demonstrate the main tutorial behaviour locally.
- `Adapted` means the Azure-specific surface is different, but the learning goal maps cleanly.
- `Partial` means the simulator supports the control-plane shape but not the full Azure runtime semantics.
- `Not appropriate` means the Azure feature is intentionally outside the simulator's local-gateway scope.
