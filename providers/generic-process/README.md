# Generic process provider

Set `NETWORK_MODE=tunnel`, `TUNNEL_PROVIDER=generic-process`,
`TUNNEL_EXECUTABLE`, and optional `TUNNEL_ARGUMENTS` in the local `.env`.
Arguments are not written to support bundles or operational logs.

Provider choices are discovered from `provider.json` files under `providers/`;
you can add a provider-specific folder and configure its executable without
changing the central tunnel lifecycle script.
