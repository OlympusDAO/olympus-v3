# constructor scenarios

Source: `src/policies/BackingOracleConfigTimelock.sol` and inherited framework hooks.

ADMIN = distinct _ADMIN actor; backing_admin = proposer; EMERGENCY = emergency.
Construction requires the oracle and timelock to report the same Kernel; this is
compatibility, independent of readiness. A foreign Kernel is rejected with the
oracle address, expected queue Kernel and reported oracle Kernel. Successful
construction asserts both Kernel getters equal the supplied Kernel.

Backing is reserve per OHM in 18 decimals; ordinary enabled backing is 100e18.
Reverts preserve authoritative backing, operator selection, action IDs, flags,
payloads and reservations. No token custody or transfers occur. Roles are independent
of Kernel membership and local enablement. Both policies use real Kernel/ROLES.

The default queue is active, enabled and selected on its immutable active oracle.
The oracle starts paused unless givenEnabled/recovery setup enables it. Constructor
cases have no queue lifecycle yet. Queue activation permits a paused oracle and
does not read its enabled flag. Runtime queue/execution require both policies
active/enabled and current selection. Cancellation reads no target metadata.

All three consumed IDs (IBackingOracle/IConfigOperator/IEnabler) are explicitly
removed in turn. Same-Kernel binding is required before readiness, without reading
target membership/enablement/selection. The four target lifecycle pairs are fuzzed
with readiness getters reverting. Address zero/one/MAX160 and zero Kernel are seeded.

| ID | Caller | Local active | Local enabled | Oracle active | Oracle enabled | Input/history | Expected execution | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BO-CONSTRUCTOR-01 | ADMIN | N/A | N/A | Fuzz false/true | Fuzz false/true | when Constructed Before Readiness | Success; exact authoritative state/getter assertions | Covered: [test][test_whenConstructedBeforeReadiness] |
| BO-CONSTRUCTOR-02 | ADMIN | N/A | N/A | Not read | Not read | when Each Consumed Interface Missing reverts | BackingOracleTimelock_InvalidBackingOracle | Covered: [test][test_whenEachConsumedInterfaceMissing_reverts] |
| BO-CONSTRUCTOR-03 | ADMIN | N/A | N/A | Not read | Not read | Oracle reports a different Kernel from the queue constructor Kernel | PolicyDependency_KernelMismatch(target,expected,reported) | Covered: [test][test_whenForeignKernel_reverts] |
| BO-CONSTRUCTOR-04 | ADMIN | N/A | N/A | Not read | Not read | when Malformed Kernel reverts | PolicyDependency_InvalidDependency(target) | Covered: [test][test_whenMalformedKernel_reverts] |
| BO-TIMELOCK-CONSTRUCTOR-02 | ADMIN | N/A | N/A | Not read | Not read | when Zero Kernel reverts | BackingOracleTimelock_ZeroKernelAddress | Covered: [test][test_whenZeroKernel_reverts] |
| BO-TIMELOCK-CONSTRUCTOR-01 | ADMIN | N/A | N/A | Not read | Not read | when Oracle Address Boundary Seeds reverts | BackingOracleTimelock_InvalidBackingOracle | Covered: [test][test_whenOracleAddressBoundarySeeds_reverts] |

[test_whenConstructedBeforeReadiness]: ./constructor.t.sol#L23
[test_whenEachConsumedInterfaceMissing_reverts]: ./constructor.t.sol#L76
[test_whenForeignKernel_reverts]: ./constructor.t.sol#L83
[test_whenMalformedKernel_reverts]: ./constructor.t.sol#L98
[test_whenZeroKernel_reverts]: ./constructor.t.sol#L110
[test_whenOracleAddressBoundarySeeds_reverts]: ./constructor.t.sol#L128
