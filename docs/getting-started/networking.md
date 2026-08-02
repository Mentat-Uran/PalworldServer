# Networking

Choose `direct`, `community`, or `tunnel` in `.env`. The game UDP port is
`PORT`; the REST and legacy RCON ports are local management ports and must not
be forwarded to the Internet.

For Sakura FRP, create a UDP tunnel from `127.0.0.1:PORT` to the provider's
remote port, then set `NETWORK_MODE=tunnel`,
`TUNNEL_PROVIDER=sakurafrp`, and `TUNNEL_LOCAL_PORT=PORT`. The provider is
optional and disabled by default. See the official [Sakura FRP UDP FAQ](https://doc.natfrp.com/faq/network.html).

The local console can report a process, listener, and provider state. Only an
external player test proves that an outside player can join.

Provider choices are discovered from `providers/*/provider.json`. The built-in
`generic-process` provider accepts any explicitly configured launcher:

```env
NETWORK_MODE=tunnel
TUNNEL_PROVIDER=generic-process
TUNNEL_EXECUTABLE=C:\Path\to\your-provider.exe
TUNNEL_ARGUMENTS=your provider arguments
TUNNEL_LOCAL_PORT=8211
```

To add another provider to a local checkout, add a lowercase provider folder
with an `id`, `displayName`, `kind`, and optional `autoDiscoverExecutables` in
`provider.json`. Do not put tokens or tunnel arguments in that file. The
launcher validates the provider id from this catalog and only stops the PID it
recorded for the configured executable.
