# honk (prebuilt)

This package vendors the official upstream release binary for the HG5585F
(AN7581, aarch64, musl):

- project: <https://github.com/daeuniverse/honk>
- tag: `v0.1.0-beta.5`
- asset: `honk-core-v0.1.0-beta.5-aarch64-unknown-linux-musl-stock-full.tar.gz`
- SHA-256: `1a2d9a1c1acff586d6a90ed84963c60f4a711ec3125180db5b4927d26909918b`

`stock` = system allocator (lower RSS peak than mimalloc); `full` = Clash API +
native API + embedded doona UI. `scripts/hg5585f/update-honk.py` refreshes this
pin to the newest upstream release (including prereleases) before a manual CI
build; tag builds keep the committed pin for reproducibility.

The binary is GPL-3.0-only. The corresponding source is available at:

    https://github.com/daeuniverse/honk/tree/v0.1.0-beta.5

Installed on the router:

- `/usr/bin/honk-core` (prebuilt binary), `/etc/init.d/honk` (procd init)
- `/etc/config/honk` + `/etc/honk/config.dae` (conffiles)
- `/etc/uci-defaults/90-honk-autostart` — migrates the old `honk.config.enabled`
  option onto the `/etc/rc.d/S99honk` link; starting at boot is the link, so
  enable the service with `/etc/init.d/honk enable`.
- `/lib/upgrade/keep.d/honk` — keeps `/etc/honk/data/` across sysupgrade.
- LuCI: `luci-app-honk` + `luci-lib-daeuniverse` add the service page (start /
  stop / restart, start-at-boot switch, config editor, log).

Do not enable honk and dae at the same time: both create the `dae0` link pair
and the `daens` network namespace. Keep `/etc/honk/config.dae` free of
subscription credentials in public repositories.
