# myVesta lifecycle fixtures

The fixtures contain only the patch anchors required by the lifecycle tests; no
production value or server identifier is included.

- `upstream-current` is derived from `myvesta/vesta` commit
  `3fbd496d05c3ef4e81e40fbad5c08f69f9369c1b` (retrieved 2026-08-22).
- `legacy-debian10` records the corresponding unpatched anchor dialect from the
  live-verified Debian 10 installation. The relevant upstream and legacy anchors
  are identical at this release, but they remain separate fixtures so a future
  upstream change cannot silently erase legacy coverage.

The full upstream files used for provenance had these SHA-256 checksums:

```text
19a9950f275efa9c4a632d28482aede6fe10aea8cbaef2605e5daed62683c1e0  admin/edit_web.html
cfbf6c27ac4f967e79972b53fbc68c99a11d1cd5f25f0725d83c03d8ec147567  admin/list_web.html
a3ee2c1f956cc51807b8e5e9c6f032ea67cb15534ccbd741d55c36c7c4ebd8a5  user/edit_web.html
bdf46fdfa8618d7bfe4b952aa4dc0c8b9af5e341dfc52fd72cf3aba9d3d5b49f  user/list_web.html
e6013ff63adaff05c0db913857d63553f92c596d5d95b547d2d3a20f622afb97  bin/v-rebuild-web-domains
```
