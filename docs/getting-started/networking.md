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
