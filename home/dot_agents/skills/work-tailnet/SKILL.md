---
name: work-tailnet
description: Connect, disconnect, or check the work tailnet on Rocket or Framework. Use for "start work tailnet" or "join work VPN"; named OpenVPN connections are separate.
---

Run `work-tailnet on`, `off`, or `status` on the requested machine, using SSH when
remote. This CLI controls only the work instance, just like the Dux widget.

Check JSON status before and after. Connecting is asynchronous; allow up to
30 seconds for `connected: true`, otherwise report `error` or `backend`.
`hasProfile: false` requires first sign-in through `work-tailnet login` and human SSO.
Use `auto` only when office automation is requested on Framework.

Use this CLI rather than bare `tailscale` commands, which target the personal instance.
