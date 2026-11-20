# BurnerLoansRiskConfigTimelock.changeKernel scenario plan

Source: [changeKernel](../../../Kernel.sol#L91).

Source precedents: [directly bound Payout queue](../../../policies/burnerloans/BurnerLoansPayoutConfigTimelock.sol#L67), [paused cancellation](../../../policies/deposits/DepositManagerConfigTimelock.sol#L582), [shared queue](../../../policies/utils/TimelockBatchQueue.sol#L115), [configuration commitments](../../../policies/utils/ConfigTimelockBatchQueue.sol#L162).

BLRCT is implemented with the interface details below. K is this queue's Kernel; T is the immutable Risk target. Risk's Core binding is not a target-discovery route and is not probed by this queue. Proposer classes are ADMIN-only, BLA-only, and their overlap; fuzz independently and guarantee each. Unauthorized proposers exclude all holders of either role. ADMIN target authority remains independent of queue authority. The queue receives no ADMIN grant or FLOAN write permission.

Initial delay D=86400 seconds; supported delay domain 86400..2592000 inclusive; execution window W=259200 seconds. There is no public delay setter. Times Q,E=Q+D,X=E+W are uint48; action IDs are uint64. Default queue and T are active/enabled, same K, T.configOperator()==BLRCT; ROLES initialized. Unchanged means all queue IDs/records/payloads/pre-state hashes/key owners, target configuration, market/position state, earned/pending rewards, balances, allowances and committed logs unchanged.

Product errors in IBurnerLoansRiskConfigTimelock: `BurnerLoansRiskTimelock_InvalidRisk(address risk)`, `BurnerLoansRiskTimelock_NotController()`, `BurnerLoansRiskTimelock_SubActionCallFailed(bytes4 selector)`. Own inactivity reuses `BurnerLoans_PolicyNotActive(BLRCT)`; subject pause uses IEnabler.NotEnabled(). PolicyDependency errors and status-read ABI rules are inherited unchanged: kernel()/isEnabled() require one canonical ABI word; short, trailing, dirty, or reverted responses reject with the shared invalid-dependency error. A canonical disabled status is an availability failure. Ordinary queue guard order is own activity→own enablement→proposer→target compatibility/readiness→operator selection→action validation; execute/cancel retain the shared base's earlier existence/terminal/time checks. Setting-specific errors come from Risk validation or equivalent canonical queue checks as specified per action.

Each global setting has one local key, each referrer one membership key shared by add/remove. Use localKey=keccak256(abi.encode(settingSelector)) for percentage/age, and keccak256(abi.encode(setReferrerAllowed.selector,referrer)) for membership. scopedKey=keccak256(abi.encode(T,localKey)) follows ConfigTimelockKeyLib. Commit destination T and stateHash=keccak256(abi.encode(selectedOperator,currentRelevantValue)), with the value encoded at its declared uint16/bool/uint48 type; never include live debt/custody balances. These exact encodings support independently constructed test expectations. Execution rechecks each sub-action against its committed state immediately before dispatch. Config/old Core may be independently paused/inactive without affecting this direct route. All getters in a function's rows are permissionless and read-only.

Scenario scope: `BLRCT-KERNEL`. Inherited KernelAdapter hook accepts only current Kernel address; product ADMIN does not replace the Kernel caller. R21,R24-R25. Migration changes the queue Kernel pointer, not immutable Risk or pending action destination; compatible startup in the new Kernel still requires explicit configuration/activation.

Review status: approved for implementation; scenario review completed. Rows are mapped to implemented tests below. Coverage records the stated domains; execution results are reported separately.

Use existing framework coverage for KernelAdapter caller restriction and same/zero pointer assignment. Product cases here cover only the new immutable Risk binding across migration.

## Kernel identity and immutable destination

Local lifecycle does not gate this framework hook. newKernel is a Kernel address, not a config target.

| ID | Caller | Local active | Local enabled | New Kernel / target | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLRCT-KERNEL-P01 | Current Kernel | Fuzz false/true | Fuzz false/true | Different Kernel K2; T still reports K | Inherited success | kernel()==K2; target/payload/keys unchanged; after restoring own membership and cached authorization in K2, queue/execute/activation reject PolicyDependency_KernelMismatch(T,K2,K) until target binding is compatible | Covered: [test_givenQueueMigratesAlone_whenPendingIntentExecuted_reverts][test_givenQueueMigratesAlone_whenPendingIntentExecuted_reverts] |
| BLRCT-KERNEL-P02 | Current Kernel | Fuzz false/true | Fuzz false/true | K2 and same T migrated compatibly; configure dependencies/reactivate | Success after explicit lifecycle restoration | No action re-targeting; pending commitments still require same operator/settings and original unexpired window | Covered: [test_givenCompatibleKernelMigration_whenPendingIntentExecuted][test_givenCompatibleKernelMigration_whenPendingIntentExecuted] |

- [x] Review these expectations.
- [x] Write tests before implementation and map passing evidence.

[test_givenCompatibleKernelMigration_whenPendingIntentExecuted]: changeKernel.t.sol#L46
[test_givenQueueMigratesAlone_whenPendingIntentExecuted_reverts]: changeKernel.t.sol#L13
