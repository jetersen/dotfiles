---
name: work-tailnet
description: Connect, disconnect, or check the work tailnet on Rocket or Framework. Use for "start work tailnet" or "join work VPN".
---

Rocket and Framework use one experimental daemon for both tailnets. Inspect
`tailscale network status` and `tailscale switch --list --json`, identify the
saved work profile, then use `tailscale network connect PROFILE` or
`tailscale network disconnect PROFILE`. Preserve the primary/preferred personal
profile and leave other saved profiles detached. Verify the selected work
profile reaches Running after connecting. Do not start a separate work daemon,
use the retired namespace CLI, or run `tailscale down` to disconnect only work.

If an existing profile is missing, stop and investigate the host's migration and
state. Do not enroll a replacement device for a migrated identity. A genuinely
new account requires explicit authorization and human SSO.

Run commands on the requested machine, using SSH when remote.
