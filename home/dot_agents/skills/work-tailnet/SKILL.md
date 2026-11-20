---
name: work-tailnet
description: Connect, disconnect, or check the work tailnet on Rocket or Framework. Use for "start work tailnet" or "join work VPN".
---

On Framework, one experimental daemon handles both tailnets. Inspect
`tailscale network status` and `tailscale switch --list --json`, identify the
saved work profile, then use `tailscale network connect PROFILE` or
`tailscale network disconnect PROFILE`. Preserve the primary/preferred personal
profile and leave other saved profiles detached. Verify the selected work
profile reaches Running after connecting. First-time sign-in needs human SSO;
do not start a separate work daemon or run `tailscale down` to disconnect work.

On Rocket, run `work-tailnet on`, `off`, or `status`. This CLI controls only its
isolated work instance, like the Dux widget. Check JSON status before and after;
allow up to 30 seconds for `connected: true`, otherwise report `error` or
`backend`. `hasProfile: false` requires `work-tailnet login` and human SSO.
Use `auto` only when office automation is requested.

Run commands on the requested machine, using SSH when remote.
