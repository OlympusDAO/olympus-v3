# BurnerLoansComposites.VERSION coverage plan

Source: [VERSION](../../../periphery/BurnerLoansComposites.sol).

Scenario scope: `BLCOMP-VERSION`. Version reporting is permissionless and independent of roles or operational state. Both return values are named in IVersioned. Co-located interface assertions verify ERC165 discovery. Calls do not read dependencies, change state, move tokens or emit logs.

## Version and interface discovery

| ID | Caller | Contract context | Expected returns | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCOMP-VERSION-P01 | Fuzz all callers | Bound Core inactive and disabled | VERSION=(major=1,minor=0); supportsInterface(IVersioned)=true | No writes or logs | Covered: [test_whenVersionQueried_thenVersionIsDiscoverable](VERSION.t.sol#L14) |

- [x] Run focused tests and update mappings.
