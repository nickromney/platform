# Provider range check

The user checks whether an address belongs to a cloud provider's published ranges, using `#provider-form` (`#provider-address` and `#provider-name`, submitted with `#provider-btn`).

## Sub-features

- `provider-match` reports a match for an address inside the provider's ranges, for example Cloudflare `104.16.1.1`.
- `provider-miss` reports no match for an address outside them.

## How to get to it (user POV)

- Sign in, then use the Provider Range Check panel.

## Driving it with control.sh

Preconditions:

- `doctor` prints `OK`.

- **Not yet driven.** Add a `provider <address> <provider>` command to `drive.mjs` that fills `#provider-address`, selects `#provider-name` and clicks `#provider-btn`.

## Gotchas

- Treat this recipe as unverified until a run's evidence exists.
