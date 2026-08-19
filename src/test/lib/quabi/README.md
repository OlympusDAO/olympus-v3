# Quabi

Recovers the functions that a contract declares with a given modifier by reading the compiler AST
out of the build artifacts over `vm.ffi`. The ABI does not record modifiers, so the AST is the only
compiler output that carries them.

- `Quabi.sol` - the library.
- `path.sh` - locates the artifact of a contract under `./out/`.
- `jq.sh` - runs a jq query against an artifact and ABI-encodes the result for Solidity.

Nothing references this directory. The permission lists that the test fixtures need are generated
offline into `src/test/lib/generated/ModulePermissions.sol` by `shell/gen_perms.sh`, so the tests
need neither `ffi` nor `ast` at run time.

Using it again would reintroduce three requirements: `ffi = true` and `ast = true` in
`foundry.toml`, and a current `out/` at the time the tests run. The last one is the sharp edge:
`forge coverage` compiles in memory and writes nothing to `out/`, so without a preceding build every
fixture call reverts in `setUp()` with "Path not found", and with a stale one the fixture silently
misses the selectors added since that build.
