# Subnet lookup through APIM

The signed-in user enters an address or CIDR and presses Lookup. The frontend calls validate, private-range, Cloudflare and subnet-info endpoints through the router and APIM simulator, then renders the results, including cloud-mode reservations.

## Sub-features

- `lookup-cidr` returns Valid, Type, RFC1918, Cloudflare and subnet details for a CIDR.
- `lookup-azure-mode` (the default `#cloud-mode`) reserves 5 addresses, so the first usable address is `.4`.
- `lookup-apim-hop` produces one `apim request` log line per API call.

## How to get to it (user POV)

- Sign in, type into the address box, then press Lookup. The example buttons (`[data-example]`) fill in common inputs.

## Driving it with control.sh

Preconditions:

- `doctor` prints `OK`.

- **Lookup.** `control.sh --execute drive lookup 10.0.0.0/24`. `03-lookup-results.txt` contains `Valid Yes`, `Type Network (CIDR)`, `RFC1918 Yes (10.0.0.0/8)`, `Mode Azure`, `Usable Addresses 251`, `First Usable IP 10.0.0.4` and `Last Usable IP 10.0.0.254`.
- **APIM hop.** `control.sh --execute logs`. `apim-simulator.log` has `POST path=/api/v1/ipv4/subnet-info status=200` at the lookup's timestamp. On 2026-10-10 there were 7 requests, including health.

## Gotchas

- The results panel shows "Loading..." first. Use evidence captured after the content arrives.
- Other cloud modes (`#cloud-mode`) change the usable counts. They are not yet driven.
