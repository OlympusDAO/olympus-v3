# BurnerLoansYieldClaimer.execute coverage plan

Scope: Heart entry point, gas-isolated self-call, per-asset failure handling, and resumable registry
progress. [selfExecuteTask](./selfExecuteTask.md) owns the direct-call boundary.

## Domains and assertions

Only `HEART_ROLE` may call `execute`. The role check precedes every lifecycle branch. A
Kernel-inactive or locally disabled task returns before its external self-call. The self-call then
returns before reading the registry when Burner Loans is Kernel-inactive or locally disabled. The
Burner Loans registry is append-only in production; execution nevertheless normalizes the stored
cursor modulo the live count when both policies are available.

With enough gas, execution visits each registry entry at most once, starting at `nextAssetIndex %
assetCount`. Before each isolated claim, it stores the following index. A claim failure, including
exhaustion of the gas forwarded to that claim, therefore advances progress and cannot starve later
assets. The task starts no new lookup when remaining gas is at or below `minimumGasToAttempt`, and
starts no claim when the post-lookup gas cannot preserve both the cursor-write buffer and
`gasReserve`.

Unchanged means the cursor, target claim state, gas configuration, and lifecycle state retain their
pre-call values. A failed outer self-call commits no internal state or events. Check exact error and
bounded failure-selector data.

## Authorization and lifecycle

| ID | Caller | Task Kernel | Task local | Burner Loans Kernel | Burner Loans local | Registry behavior | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| EXEC-A01 | Any caller without `HEART_ROLE`, fuzz | Active/inactive | Enabled/disabled | Active/inactive | Enabled/disabled | Fuzz readable/reverting | `ROLES_RequireRole(HEART_ROLE)` before lifecycle checks | Unchanged; no event | Covered: [enabled][test_givenCallerWithoutHeartRole_reverts], [disabled][test_givenDisabled_whenCallerWithoutHeartRole_reverts] |
| EXEC-L01 | Heart | Active | Disabled | Active/inactive | Enabled/disabled | Reverting count getter | Silent success before self-call or registry access | Cursor and target state unchanged; no event | Covered: [test][test_givenDisabled_isNoOpBeforeRegistryRead] |
| EXEC-L02 | Heart | Inactive | Enabled/disabled | Active/inactive | Enabled/disabled | Reverting count getter | Silent success before self-call or registry access | Cursor and target state unchanged; no event | Covered: [test][test_givenTaskInactive_executeDoesNotQueryBurnerLoans] |
| EXEC-L03 | Heart | Active | Enabled | Active | Disabled | Reverting count getter | Silent success in the self-call before registry access | Cursor and target state unchanged; no event | Covered: [unit][test_givenBurnerLoansDisabled_executeDoesNotQueryRegistry], [integration][test_givenBurnerLoansDisabled_skipsEveryAsset] |
| EXEC-L04 | Heart | Active | Enabled | Inactive | Enabled | Reverting count getter | Silent success in the self-call before local-state or registry access | Cursor and target state unchanged; no event | Covered: [test][test_givenBurnerLoansInactive_executeDoesNotQueryRegistry] |
| EXEC-L05 | Heart | Active | Enabled | Inactive | Disabled | Reverting count getter | Silent success in the self-call before local-state or registry access | Cursor and target state unchanged; no event | Covered: [test][test_givenBurnerLoansInactive_executeDoesNotQueryRegistry] |

## Traversal and progress

| ID | Asset count | Starting cursor | Claim behavior | Gas budget | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| EXEC-P01 | 0 | Any stored value | N/A | Sufficient | Silent success | Cursor unchanged; no claim/event | Covered: [test][test_givenNoRegisteredAssets_isNoOp] |
| EXEC-P02 | 1 | 0 | Success | Sufficient | Visit once | Claim committed; cursor wraps to zero | Covered: [test][test_givenClaimSucceeds_callsBurnerLoans] |
| EXEC-P03 | Multiple | 0 or selected valid index | All succeed | Sufficient | Visit each asset once in circular order | Claims committed; cursor returns to start | Covered: [zero start][test_givenMultipleClaimsSucceed_claimsEveryAsset], [selected start][test_givenSelectedCursor_executesInCircularOrder] |
| EXEC-P04 | Multiple | Valid selected index | All succeed | Sufficient | First claim uses selected index | Exact circular order; cursor returns to start | Covered: [test][test_givenSelectedCursor_executesInCircularOrder] |
| EXEC-P05 | Multiple | Out of range after fixture shrink | All succeed | Sufficient | Normalize cursor modulo count | Each live asset visited once; normalized cursor retained | Covered: [test][test_givenCursorOutOfRangeAfterRegistryShrink_normalizesTraversal] |
| EXEC-G01 | Multiple | 0 | Earlier claim succeeds; later claim exhausts forwarded gas | Sufficient outer budget | Report later failure and pause with cleanup gas | Cursor advances past failed asset; earlier work is not rolled back | Covered: [progress and resume][test_givenLaterClaimExhaustsGas_preservesProgressAndResumes]; supplementary [first-claim cleanup subset][test_givenClaimExhaustsGas_laterHeartTaskStillExecutes] |
| EXEC-G02 | Same as EXEC-G01 on next beat | Cursor after failed asset | Later claims succeed | Sufficient outer budget | Resume at first unattempted asset | Later assets progress without starvation | Covered: [test][test_givenLaterClaimExhaustsGas_preservesProgressAndResumes] |
| EXEC-G03 | Nonempty | Any | Not reached | At or below attempt threshold | Silent pause before asset lookup | Cursor unchanged; no claim/failure event | Covered: [test][test_givenAttemptThresholdExceedsAvailableGas_pausesBeforeLookup] |
| EXEC-G04 | Multiple | First asset | Successful claims | Enough for a subset | Repeated beats resume until all assets have been attempted | No starvation; cursor identifies first unattempted asset after each beat | Covered: [test][test_givenLimitedExecutionGas_repeatedBeatsReachEveryAsset] |
| EXEC-G05 | Multiple | First asset | Not reached | Post-lookup gas cannot preserve cursor-write buffer plus reserve | Silent pause before cursor update | Cursor remains on unattempted asset; no claim/failure event | Covered: [test][test_givenPostLookupGasCannotPreserveReserve_pausesBeforeCursorAdvance] |

## Failure isolation

| ID | Failure point | Revert data | Earlier work | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- |
| EXEC-F01 | Individual `claimYield` | Four-byte selector | None or prior claims | Continue while budget permits | Failed claim rolls back; `YieldAssetClaimFailed(asset, selector)`; cursor advances | Covered: [ordinary revert][test_givenClaimReverts_reportsFailure], [gas exhaustion][test_givenLaterClaimExhaustsGas_preservesProgressAndResumes], [same-beat production payout][test_givenFirstClaimReverts_laterClaimPaysTreasuryInSameBeat] |
| EXEC-F02 | Individual `claimYield` | Short or oversized | None | Continue while budget permits | Event reports the available bounded prefix | Covered: [short][test_givenClaimRevertsWithLessThanSelector_reportsAvailablePrefix], [oversized][test_givenClaimRevertsWithLargeData_reportsBoundedFailure] |
| EXEC-F03 | Registry count getter | Selector | None | Outer self-call failure is caught | `ExecutionFailed(selector)`; cursor unchanged | Covered: [test][test_givenAssetRegistryReadReverts_reportsExecutionFailure] |
| EXEC-F04 | Later indexed getter | Selector | Prior claim and cursor advance | Outer self-call failure is caught | Prior claim and cursor changes roll back; `ExecutionFailed(selector)` | Covered: [test][test_givenLaterAssetReadReverts_rollsBackEarlierClaimAndCursor] |
| EXEC-F05 | Self-call entry | Empty/out of gas | None | Outer self-call failure is caught | `ExecutionFailed(0x00000000)`; cursor unchanged | Covered: [test][test_givenMinimumTaskGasLimit_reportsExecutionFailure] |

## Heart isolation

| ID | Yield Claimer outcome | Later Heart task | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| EXEC-H01 | One claim exhausts its forwarded gas | Valid | Heart continues | Yield failure reported; later task executes once | Covered: [test][test_givenClaimExhaustsGas_laterHeartTaskStillExecutes] |

## Production integration

| ID | Production state | Task outcome | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- |
| EXEC-I01 | Burner Loans locally disabled with yield on multiple assets | Task skips before registry traversal | No claim attempt or failure event | Vault/Treasury balances and cursor unchanged | Covered: [test][test_givenBurnerLoansDisabled_skipsEveryAsset] |
| EXEC-I02 | Periodic task outer self-call exhausts its configured gas | `ExecutionFailed(0x00000000)` | The automation attempt does not consume the underlying permissionless claim path | Claimable yield is unchanged after task failure, then a direct claim reduces it | Covered: [test][test_givenPeriodicTaskExceedsGasLimit_directClaimRemainsAvailable] |
| EXEC-I03 | Multiple accrued-yield assets, enabled production target | Bounded Heart beats traverse registry | Each healthy asset pays its previewed yield | Exact Treasury gains and matching vault losses; cursor remains in range | Covered: [test][test_givenMultipleYieldAssets_boundedBeatsPayTreasuryAndResume] |
| EXEC-I04 | One asset-specific ordinary claim revert, later healthy production asset | Report first failure and continue in same bounded beat | Failed yield remains available; later payout commits | Failure selector event; exact later Treasury/vault deltas; complete cursor wrap | Covered: [test][test_givenFirstClaimReverts_laterClaimPaysTreasuryInSameBeat] |

## Stateful sequences

The focused invariant randomizes registry growth/shrink, cursor selection, gas configuration,
task activation, local task/target enablement, authorized execution, and unauthorized cursor calls.
It checks cursor preservation on skips or full-task rollback, advancement for successful and failed
isolated attempts, circular order when all attempts succeed, and the gas-setting constraints.
After each campaign, lifecycle and budget recovery must reach every live asset.

Covered: [invariant][invariant_gasSettingsRemainValid].

[test_givenCallerWithoutHeartRole_reverts]: ./execute.t.sol#L40
[test_givenDisabled_whenCallerWithoutHeartRole_reverts]: ./execute.t.sol#L210
[test_givenDisabled_isNoOpBeforeRegistryRead]: ./execute.t.sol#L142
[test_givenTaskInactive_executeDoesNotQueryBurnerLoans]: ./execute.t.sol#L156
[test_givenBurnerLoansDisabled_executeDoesNotQueryRegistry]: ./execute.t.sol#L180
[test_givenBurnerLoansInactive_executeDoesNotQueryRegistry]: ./execute.t.sol#L194
[test_givenNoRegisteredAssets_isNoOp]: ./execute.t.sol#L388
[test_givenClaimSucceeds_callsBurnerLoans]: ./execute.t.sol#L59
[test_givenMultipleClaimsSucceed_claimsEveryAsset]: ./execute.t.sol#L71
[test_givenSelectedCursor_executesInCircularOrder]: ./execute.t.sol#L92
[test_givenCursorOutOfRangeAfterRegistryShrink_normalizesTraversal]: ./execute.t.sol#L111
[test_givenLaterClaimExhaustsGas_preservesProgressAndResumes]: ./execute.t.sol#L339
[test_givenAttemptThresholdExceedsAvailableGas_pausesBeforeLookup]: ./execute.t.sol#L272
[test_givenLimitedExecutionGas_repeatedBeatsReachEveryAsset]: ./execute.t.sol#L401
[test_givenPostLookupGasCannotPreserveReserve_pausesBeforeCursorAdvance]: ./execute.t.sol#L292
[test_givenClaimReverts_reportsFailure]: ./execute.t.sol#L229
[test_givenClaimRevertsWithLessThanSelector_reportsAvailablePrefix]: ./execute.t.sol#L245
[test_givenClaimRevertsWithLargeData_reportsBoundedFailure]: ./execute.t.sol#L260
[test_givenAssetRegistryReadReverts_reportsExecutionFailure]: ./execute.t.sol#L425
[test_givenLaterAssetReadReverts_rollsBackEarlierClaimAndCursor]: ./execute.t.sol#L441
[test_givenMinimumTaskGasLimit_reportsExecutionFailure]: ./execute.t.sol#L369
[test_givenClaimExhaustsGas_laterHeartTaskStillExecutes]: ./execute.t.sol#L312
[test_givenBurnerLoansDisabled_skipsEveryAsset]: ./executeIntegration.t.sol#L49
[test_givenPeriodicTaskExceedsGasLimit_directClaimRemainsAvailable]: ./executeIntegration.t.sol#L92
[test_givenMultipleYieldAssets_boundedBeatsPayTreasuryAndResume]: ./executeIntegration.t.sol#L124
[test_givenFirstClaimReverts_laterClaimPaysTreasuryInSameBeat]: ./executeIntegration.t.sol#L172
[invariant_gasSettingsRemainValid]: ./execute.invariant.t.sol#L152
