# Go Apps Pass 7

Targets:

```sh
make -C apps shared-apphttp-test shared-appshell-test shared-idpauth-test \
  apim-simulator-test chatgpt-sim-test idp-core-test langfuse-demos-test \
  platform-mcp-test sentiment-test subnetcalc-test
```

```sh
image_build_catalog_build_loop workload workload
```

Baseline:

- Go unit-test aggregate: passed; output SHA-256 `8e12321fbe80e15a7986e066f1112f0936102f12e1765c4087ca992b1ed33895`.
- Duplicate prebuild fixture with cache disabled: 283.2ms mean, 10.5ms sigma.
- Real `build-linux` prebuild path is blocked on this host by Go 1.26.4 cross-compilation errors for `internal/runtime/cgroup` and `internal/runtime/syscall/linux`; see `build-linux-failure.txt`.

Change:

- Cache exact image prebuild command strings for the current image-build process.
- Keep `PREBUILD <image>: <command>` output for each image ID so catalog progress remains visible.
- Only skip a command after the same exact command has already succeeded.

Result:

- Duplicate prebuild fixture with cache enabled: 173.0ms mean, 9.4ms sigma.
- Fixture output SHA-256 stayed `1c1fead8dfc612640aaf46edc72fbb77a897a191a2bf2ef576110449f9c116d4`.
- Duplicate Go prebuild work dropped from two command executions to one for identical command strings.

Isomorphism proof:

- Image build loop still visits and builds both image IDs.
- Cache key is the exact prebuild command text, so distinct commands remain distinct.
- Failed prebuild commands are not cached.
