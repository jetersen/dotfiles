# Agent session search and backups

The Rocket [host module](../nixos/hosts/rocket/agent-observability.nix) owns the
search, embedding, refresh, backup, and HTTPS-route user services. Nix builds the
pinned binaries and model assets; no runtime installer or model download is
needed. Deploy through the normal NixOS cache and upgrade pipeline.

Keep the data filesystem mounted before activation. Application state remains
outside the Nix store. Activation merges declared search settings while
preserving other private settings. Existing units stay running across ownership
changes; restart the search services after activation to select new executable
paths. T3 retains its separate idle-update policy.

The T3 adapter reads its database without modifying it. T3 conversations use
AgentsView's ChatGPT exchange format, with a T3 title prefix and source link.
Changed copies retain their previous version in trash. A completed run does not
establish task completion; review and mark threads settled in T3.

## Backup prerequisites

Keep the homelab checkout and its Varlock schema and provider dependencies
available at the path declared in the service. Configure its existing S3
credentials and separate Kopia password in the secret provider. Initialize the
isolated agent repository prefix before enabling the backup timer. Do not
silently create a replacement repository when an existing connection fails.
Retain S3 access and the repository password independently of the machine.

The backup creates a consistent online SQLite snapshot, validates it, and stores
a manifest with the checksum and project, thread, and message counts. It also
snapshots the configured transcript and attachment roots. Working trees and
unrelated application state are outside this backup.

## Recovery

Restore into a separate private scratch directory first. Run SQLite
`PRAGMA quick_check` and verify the checksum and counts against the snapshot
manifest. Preserve the matching environment ID. Stop T3 before replacing its
live database; restore attachments and agent transcripts to their original
roots. The search index is disposable and can be rebuilt from those sources.
