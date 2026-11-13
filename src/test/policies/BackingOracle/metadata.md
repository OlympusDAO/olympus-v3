# metadata scenarios

Source: `src/policies/BackingOracle.sol` and inherited framework hooks.

ADMIN = distinct _ADMIN actor; backing_admin = proposer; EMERGENCY = emergency.
Backing is reserve per OHM in 18 decimals; ordinary enabled backing is 100e18.
Reverts preserve authoritative backing, operator selection, action IDs, flags,
payloads and reservations. No token custody or transfers occur. Roles are independent
of Kernel membership and local enablement. Both policies use real Kernel/ROLES.

The oracle starts active and paused. givenEnabled sets backing to 100e18.
givenRecovered enables, pauses, re-enables without payload and deactivates/reactivates. ADMIN
retains direct writes alongside a selected operator; proposer role alone has no
setter authority. Getter/framework queries retain their read/setup semantics.

ROLES major one; no write permissions; VERSION 1.0 and 18 decimals. Oracle
advertises IBackingOracle, IConfigOperator, IVersioned and Enabler/re-enable/grace/ERC165 IDs,
but no timelock, queue or removed backing/setBacking-only interface ID. Invalid ERC165 ID is rejected.

| ID | Caller | Local active | Local enabled | Oracle active | Oracle enabled | Input/history | Expected execution | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BO-METADATA-01 | ADMIN | true | false/true (read/setup) | N/A | N/A | when Metadata | Success; exact authoritative state/getter assertions | Covered: [test][test_whenMetadata] |
| BO-METADATA-02 | ADMIN | true | false/true (read/setup) | N/A | N/A | when Zero Kernel reverts | BackingOracle_ZeroKernelAddress | Covered: [test][test_whenZeroKernel_reverts] |
| BO-METADATA-03 | ADMIN | true | false/true (read/setup) | N/A | N/A | when Framework Hooks | Success; exact authoritative state/getter assertions | Covered: [test][test_whenFrameworkHooks] |

[test_whenMetadata]: ./metadata.t.sol#L23
[test_whenZeroKernel_reverts]: ./metadata.t.sol#L61
[test_whenFrameworkHooks]: ./metadata.t.sol#L67
