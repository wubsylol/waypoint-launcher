# Windows runtime download descriptor

`distribution.json` is copied unchanged from the creator's Waypoint 1.1.1
release (`Waypoint.app/Contents/Resources/WindowsRuntime/distribution.json`).
The release DMG was checked against its published SHA-256 before extraction.

This descriptor contains public URLs and hashes, not the Wine runtime itself.
The existing runtime installer verifies the downloaded archive and manifest;
its matching corresponding-source archive is identified by `sourceURL` and
`sourceSHA256`. Keep those fields together when updating the runtime.

The local fork release bundles this descriptor, its own compiled Windows title
bridge, and the existing graphics download metadata/licence. It does not bundle
Apple graphics binaries or download a game during packaging. The existing host,
Rosetta, licence and per-title Preview checks still apply.

Upstream source: https://github.com/wowlocal/waypoint-launcher/releases/tag/v1.1.1
