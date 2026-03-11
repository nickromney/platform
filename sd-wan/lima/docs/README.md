# SD-WAN Lima Docs

These docs are meant to be read in order: concept first, then host readiness, then lab shape, then live verification.

## Reading Order

1. [what-is-sd-wan.md](what-is-sd-wan.md) defines the SD-WAN idea and explains why this lab intentionally makes private addressing ambiguous.
1. [prerequisites.md](prerequisites.md) explains the host-side checks, explicit port usage, and why Lima auto-forwarding is disabled.
1. [architecture.md](architecture.md) walks through the request path, the overlapping address plan, and the resolver viewpoint with Mermaid diagrams.
1. [network-verification.md](network-verification.md) shows the lab behaving as designed, using live DNS, tunnel, and traceroute outputs.
