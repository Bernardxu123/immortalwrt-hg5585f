# honk (prebuilt)

This package vendors the official upstream release binary for the HG5585F
(AN7581, aarch64, musl):

- project: <https://github.com/daeuniverse/honk>
- tag: `v0.1.0-beta.3`
- asset: `honk-core-v0.1.0-beta.3-aarch64-unknown-linux-musl-stock-full.tar.gz`
- SHA-256: `770fe83aa09322ddffe1f16565a681e1ae1fb93db8746bc65db8b5d4d30fa55c`

`stock` = system allocator (lower RSS peak than mimalloc); `full` = Clash API +
native API + embedded doona UI.

The binary is GPL-3.0-only. The corresponding source is available at:

    https://github.com/daeuniverse/honk/tree/v0.1.0-beta.3

Do not enable honk and dae at the same time: both create the `dae0` link pair
and the `daens` network namespace. Keep `/etc/honk/config.dae` free of
subscription credentials in public repositories.
