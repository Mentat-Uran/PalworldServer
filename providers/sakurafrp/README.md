# Sakura FRP provider

Set `NETWORK_MODE=tunnel`, `TUNNEL_PROVIDER=sakurafrp`, and optionally
`TUNNEL_EXECUTABLE` in the local `.env`. Use the official Sakura FRP launcher
to configure a UDP tunnel to the game port. Management ports must not be
tunneled.

The launcher auto-discovery name is declared in this provider's `provider.json`;
set `TUNNEL_EXECUTABLE` explicitly when the launcher is installed elsewhere.
