# DepositManagerConfigTimelock.queueRescue coverage plan

Sources: [DMCT](../../../policies/deposits/DepositManagerConfigTimelock.sol),
[configuration queue](../../../policies/utils/ConfigTimelockBatchQueue.sol),
[queue lifecycle](../../../policies/utils/TimelockBatchQueue.sol), and
[DepositManager rescue acceptance](../DepositManager/rescue.md).
Closest precedent: [Inventory's Treasury-only delayed rescue](../BurnerLoansInventoryConfigTimelock/queueRescueSurplus.md).

## Acceptance criteria and current implementation

The API is `queueRescue(address token) returns (uint64 actionId)`. ADMIN or
DEPOSIT_MANAGER_ADMIN_ROLE holders may propose. DMCT must be DepositManager's selected config
operator. Anyone may execute a valid pending action after its delay and through the inclusive
expiry boundary. DM receives DMCT as msg.sender and independently authorizes the selected operator;
the external proposer's roles are not forwarded to DM.

DMCT must remain Kernel-active and locally enabled. DM must remain active in the same Kernel;
its local disabled state must not block rescue queueing or execution. Other configuration actions
keep their existing DM-enabled requirement. Rescue supports only unmanaged ERC-20 tokens and sends
their entire execution-time balance to the then-current TRSRY. There is no recipient/amount input,
token reservation, allowance grant or transfer at queue time.
Queue admission calls DM.previewRescue(T) for canonical token/balance/Treasury validation. DMCT has
no rescue role merely to obtain this quote. A zero quote is valid; the quoted amount is neither
stored as a payout amount nor hashed into the configuration commitment.

The implementation adds typed and batch rescue admission, selector-specific paused-manager
handling and execution dispatch to the existing queue. Rescue keys commit to token eligibility and the selected config operator,
independently of live balance and Treasury identity. Ordinary configuration retains its enabled
manager requirement. Named test links below identify rescue-specific evidence alongside the
existing generic queue lifecycle tests.

## Domains, fixtures and errors

- TL is DMCT; DM is its immutable manager; T and U are distinct eligible ERC-20 tokens. A holds
  ADMIN_ROLE; M holds DEPOSIT_MANAGER_ADMIN_ROLE. Fuzz proposer identities with ADMIN-only,
  manager-only and overlapping grants, guaranteeing each. TL itself has neither role on DM.
- Unauthorized proposers exclude every holder of either accepted role; seed EMERGENCY-only,
  DEPOSIT_OPERATOR-only, unrelated addresses and zero. Permissionless executor fuzzing has no role
  exclusions; include the proposer and unrelated EOAs/contracts as seeds.
- Unless varied, both policies are active/enabled in Kernel K, DM selects TL, ROLES is initialized,
  T is unmanaged, its balance read is canonical, and no T rescue is pending.
- `MAXn=2**n-1`. Token amounts B use raw units and fuzz 0..MAX256, guaranteeing 0, 1 and MAX256.
  Use zero Treasury token balance for the MAX256 fixture. Queue time Q is a positive uint48 second.
  Delay D is the stored `timelockDelay`, fuzzed across 1 day..30 days with both bounds seeded.
  X=Q+D; Y=X+3 days. Derive execution assertions from stored X/Y, not fixture clock assumptions.
- Unchanged means nextActionId, existing action metadata/payloads, configuration guards/key owners,
  token balances/allowances, DM custody/accounting/receipts/cap utilization, configuration and
  lifecycle fields stay equal. Reverts commit no logs. Failed execution retains the complete
  pending action and every reserved key; terminal success/cancellation clears payload/guards/keys
  while retaining proposer/timestamps and the appropriate terminal flag.

Use exact errors from [queue](../../../policies/interfaces/utils/ITimelockBatchQueue.sol),
[configuration queue](../../../policies/interfaces/utils/IConfigTimelockBatchQueue.sol),
[DMCT](../../../policies/interfaces/deposits/IDepositManagerConfigTimelock.sol),
[controller](../../../policies/interfaces/utils/IConfigOperator.sol), and
[DM rescue](../../../policies/interfaces/deposits/IDepositManager.sol).
Below `Action*` means `ITimelockBatchQueue_Action*`; `Config*` means
`IConfigTimelockBatchQueue_Config*`. `NotAuthorised()` is the inherited proposer error;
`NotEnabled()` is inherited from IEnabler. Token eligibility uses
`DepositManager_CannotRescueAsset(token)` as specified in the rescue plan. No new production error
family is required. DM.previewRescue is required by the paired rescue plan and shares its checks
with DM.rescue; DMCT must not duplicate DM's managed-token eligibility algorithm for admission.

Queue admission precedence: TL own activity, TL local enablement, proposer authority, DM Kernel
binding/activity, selected-operator identity, action-specific validation, then conflict reservation.
Rescue omits only DM local enablement. Preserve inherited checked counter/time arithmetic and the
generic execute/cancel state/window checks before their product hooks. Do not infer a universal
first error from a fixture containing an exhausted counter as well as invalid input.

## Authorization and lifecycle

Typed queue only; T eligible; free key. Guarantee every boolean pair named in a row independently.

| ID | Caller | Local active | Local enabled | DM active | DM enabled | Other condition | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| DMCT-RESCUE-A01 | Fuzz ADMIN-only, manager-only and overlap | true | true | true | Fuzz false/true | TL selected; TL has no DM roles | Return next ID | Queue one rescue; no transfer; target enablement unchanged | Covered: [test][test_givenAdminOnly_whenRescueQueued], [test][test_givenManagerOnly_whenRescueQueued], [test][test_givenBothProposerRoles_whenRescueQueued], [test][test_givenAdminOnly_whenBothManagerPauseStatesQueued], [test][test_givenManagerOnly_whenBothManagerPauseStatesQueued], [test][test_givenOverlappingRoles_whenBothManagerPauseStatesQueued] |
| DMCT-RESCUE-A02 | Fuzz outside ADMIN/manager holder sets | true | true | true | Fuzz false/true | TL selected | NotAuthorised() | Unchanged | Covered: [test][test_whenRescueProposerUnauthorized_reverts], [test][test_whenZeroProposerQueuesRescue_reverts], [test][test_givenEmergencyOnly_whenRescueQueued_reverts], [test][test_givenDepositOperatorOnly_whenRescueQueued_reverts], [test][test_givenUnauthorizedCaller_whenBothManagerPauseStatesQueued_revert] |
| DMCT-RESCUE-A03 | A | true | true | true | Fuzz false/true | DM selects another nonzero C | ConfigOperator_Unauthorized(TL) | Unchanged even though proposer is ADMIN | Covered: [test][test_givenAnotherConfigOperator_whenRescueQueued_reverts], [test][test_givenAnotherController_whenBothManagerPauseStatesQueued_revert] |
| DMCT-RESCUE-A04 | M | true | true | true | Fuzz false/true | DM config operator cleared to zero | ConfigOperator_Unauthorized(TL) | Unchanged | Covered: [test][test_givenNoConfigOperator_whenRescueQueued_reverts], [test][test_givenNoController_whenBothManagerPauseStatesQueued_revert] |
| DMCT-RESCUE-A05 | M | true | true | true | false | Attempt direct DM.rescue instead of proposing | ConfigOperator_Unauthorized(M) | No manager bypass; DMCT proposal still succeeds | Covered: [test][test_givenManagerOnly_givenDepositManagerDisabled_whenRescueQueuedAndExecuted] |
| DMCT-RESCUE-L01 | A | false | false | true | true | Unauthorized proposer and zero-token competing faults | DepositManagerConfigTimelock_PolicyInactive(TL) | Unchanged; own inactivity wins | Covered: [test][test_givenTimelockInactiveAndDisabled_whenRescueQueued_revertsActivityFirst] |
| DMCT-RESCUE-L02 | A | false | true | true | true | Otherwise admissible | DepositManagerConfigTimelock_PolicyInactive(TL) | Unchanged | Covered: [test][test_givenTimelockInactiveAndEnabled_whenRescueQueued_reverts] |
| DMCT-RESCUE-L03 | Unauthorized proposer | true | false | true | true | Zero-token competing fault | NotEnabled() | Unchanged; local pause wins over authority/input | Covered: [test][test_givenTimelockDisabled_whenUnauthorizedCallerQueuesZeroToken_revertsPauseFirst] |
| DMCT-RESCUE-L04 | A | true | true | false | Fuzz false/true | Same Kernel | PolicyDependency_NotActive(DM) | Unchanged | Covered: [test][test_givenDepositManagerInactive_whenRescueQueued_reverts], [test][test_givenInactiveManager_whenBothLocalPauseStatesQueued_revert] |
| DMCT-RESCUE-L05 | A | true | true | true | false | Otherwise admissible | Return next ID | DM stays disabled; queue creates no user accounting | Covered: [test][test_givenManagerOnly_givenDepositManagerDisabled_whenRescueQueuedAndExecuted] |
| DMCT-RESCUE-L06 | A | true | true | true | true | TL disabled then reEnabled within grace | Return next ID | Exactly one new action/key; history unchanged | Covered: [test][test_givenTimelockReEnabled_whenRescueQueued] |
| DMCT-RESCUE-L07 | Unauthorized proposer | true | true | false | true | DM inactive plus zero token | NotAuthorised() before target/input checks | Unchanged | Covered: [test][test_givenDepositManagerInactive_whenUnauthorizedCallerQueuesZeroToken_revertsAuthorityFirst] |

## Dependency binding and token admission

Use A and an otherwise operational TL. T is independent of any token returned dynamically by a
vault after onboarding. DM's stored custody-token identity is authoritative.

| ID | Caller | Binding / token condition | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| DMCT-RESCUE-D01 | A | DM reports K2 different from expected K; DM locally disabled too | PolicyDependency_KernelMismatch(DM,K,K2) | Unchanged; pause does not mask mismatch | Covered: [test][test_givenPausedManagerWithForeignKernel_whenRescueQueued_revertsMismatch] |
| DMCT-RESCUE-D02 | A | Required DM.kernel read fails or is malformed | PolicyDependency_InvalidDependency(DM) | Unchanged | Covered: [test][test_givenManagerKernelGetterReverts_whenRescueQueued_reverts], [test][test_givenManagerKernelGetterMalformed_whenRescueQueued_reverts] |
| DMCT-RESCUE-I01 | A | token=address(0), with no assets, idle asset and vault asset fixtures | DepositManager_CannotRescueAsset(address(0)) | No action/key/ID committed | Covered: [test][test_givenVaultCustody_whenZeroTokenQueued_reverts], [test][test_givenIdleCustody_whenZeroTokenQueued_reverts], [test][test_givenNoConfiguredAssets_whenZeroTokenQueued_reverts] |
| DMCT-RESCUE-I02 | A | Nonzero no-code token address | DepositManager_CannotRescueAsset(token) | Unchanged | Covered: [test][test_whenNoCodeTokenQueued_reverts] |
| DMCT-RESCUE-I03 | A | Configured underlying token; seed idle/vault custody | DepositManager_CannotRescueAsset(token) | Unchanged | Covered: [test][test_givenConfiguredUnderlying_whenRescueQueued_reverts], [test][test_givenIdleUnderlying_whenRescueQueued_reverts] |
| DMCT-RESCUE-I04 | A | Configured vault entry point | DepositManager_CannotRescueAsset(token) | Unchanged | Covered: [test][test_givenConfiguredVault_whenRescueQueued_reverts] |
| DMCT-RESCUE-I05 | A | Stored share token, including one from a vault whose live share() changed/reverts | DepositManager_CannotRescueAsset(token) | Unchanged; no reliance on mutable share metadata | Covered: [test][test_givenStoredExternalShare_whenRescueQueued_reverts], [test][test_givenVaultReportedShareChanges_whenStoredShareQueued_reverts], [test][test_givenVaultShareGetterReverts_whenStoredShareQueued_reverts] |
| DMCT-RESCUE-I06 | A | Managed underlying/vault/share after routes disabled or liabilities zero | DepositManager_CannotRescueAsset(token) | No queue-time managed-token escape | Covered: [test][test_givenDisabledEmptyRoute_whenUnderlyingQueued_reverts], [test][test_givenDisabledEmptyRoute_whenVaultQueued_reverts], [test][test_givenDisabledEmptyRoute_whenShareQueued_reverts] |
| DMCT-RESCUE-P01 | A | Eligible T, fuzz B=0..MAX256; seed 0,1,MAX256 | DM.previewRescue(T)=B; return next ID | No transfer, transferFrom, approve or token reservation; quote not fixed into later payout | Covered: [test][test_givenAdminOnly_whenRescueQueued], [test][test_whenRescueTokenBalanceIsZero], [test][test_whenRescueTokenBalanceIsOne], [test][test_whenRescueTokenBalanceIsMaximum] |
| DMCT-RESCUE-T03 | A | DM.previewRescue(T) encounters a stable typed token balance-read error | Same exact fixture error propagates from preview through queue admission | No action/key/ID or custody mutation | Covered: [test][test_givenPreviewBalanceReadFails_whenQueued_revertsExactTokenError] |
| DMCT-RESCUE-D06 | A | DM.previewRescue(T) encounters missing TRSRY; seed B=0 and B>0 | Policy_ModuleDoesNotExist(toKeycode("TRSRY")), matching direct preview and authorized rescue | No action/key/ID or custody mutation | Covered: [test][test_givenTreasuryMissing_whenQueued_revertsMatchingPreview], [test][test_givenTreasuryMissing_whenZeroBalanceQueued_reverts], [test][test_givenTreasuryMissing_whenPositiveBalanceQueued_reverts] |

## Stored operation, keys and batch equivalence

A successful typed proposal stores one sub-action `(DM,bytes4(keccak256("rescue(address)")),abi.encode(T))`
with exactly 32 payload bytes and destination DM. It consumes one uint64 ID and returns that ID.
Getters must agree on proposer, Q, X, Y, false terminal flags, sub-action count/selector/payload,
destination, expected state and scoped pending-key owner.

Require one conflict domain per `(DM,T,rescue)` shared by typed and generic-batch proposals. The exact
domain constant is an implementation detail; tests independently derive the selected encoding and
check observable key ownership. Unrelated T/U keys and existing cap/minimum/mode/period domains must
remain independent. Commit token rescue eligibility and selected-operator identity, not token balance, Treasury identity, proposer
role membership or DM local enablement. New receipts and Treasury upgrades must not stale recovery.
If T becomes any configured underlying/vault/stored share token, the rescue must stop before transfer.
Use ConfigStateChanged with the exact stored/current hashes for that eligibility drift.

Queue event order is ConfigStateQueued, TimelockSubActionQueued, TimelockActionQueued. Assert TL as
emitter and every indexed/non-indexed field: action ID, sub-action/state index, scoped key,
destination, expected hash, target, selector, payload hash, batch hash, proposer, X and Y.
Queue admission obtains the live balance through DM.previewRescue, but neither commits that balance
nor treats zero as an error. Preview failures must not leave a reserved key.

| ID | Caller | Proposal / pre-state | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| DMCT-RESCUE-P02 | Fuzz A or M | Typed proposal; free T key | Return n | nextActionId=n+1; exact one-action metadata/getters/events above; no custody changes | Covered: [test][test_givenAdminOnly_whenRescueQueued], [test][test_givenManagerOnly_whenRescueQueued], [test][test_givenBothProposerRoles_whenRescueQueued], [test][test_whenRescueQueued_emitsExactCommitmentAndQueueEvents] |
| DMCT-RESCUE-P03 | Fuzz A or M | Equivalent singleton queueBatch rescue | Same admission and commitment as typed queue, including paused DM | Same metadata except transaction-specific ID/time; no bypass | Covered: [test][test_givenEquivalentTypedAndBatchRescue_whenQueued_thenMetadataAgrees], [test][test_givenAdminAndManager_whenTypedBatchEquivalenceInBothPauseStates] |
| DMCT-RESCUE-P04 | A | T rescue already pending; typed or batch duplicate | ConfigKeyPending(scopedTKey,owner) | Original action unchanged; no consumed new ID | Covered: [test][test_givenPendingRescue_whenTypedOrBatchDuplicateQueued_reverts] |
| DMCT-RESCUE-P05 | M | T rescue pending; propose U rescue | Success | Independent U action/key; T action/key unchanged | Covered: [test][test_givenPendingRescue_whenAnotherTokenQueued_thenKeysAreIndependent] |
| DMCT-RESCUE-P06 | A | T rescue pending; queue cap/minimum/mode/period action with its prerequisites satisfied | Success | Existing configuration domains remain independent | Covered: [test][test_givenRescuePending_whenDepositCapQueued_thenDomainsAreIndependent], [test][test_givenRescuePending_whenMinimumDepositQueued_thenDomainsAreIndependent], [test][test_givenRescuePending_whenWithdrawalModeQueued_thenDomainsAreIndependent], [test][test_givenRescuePending_whenPeriodDisableQueued_thenDomainsAreIndependent] |
| DMCT-RESCUE-I07 | A | Batch rescue has non-DM target | ActionInvalid(target,rescueSelector) | Entire batch unchanged | Covered: [test][test_whenRescueBatchTargetWrong_reverts] |
| DMCT-RESCUE-I08 | A | Batch rescue payload length fuzzed outside 32; seed 0,1,31,33 and a longer bounded payload | ActionInvalid(DM,rescueSelector) | No partial metadata/key reservations | Covered: [test][test_whenRescuePayloadTooShort_reverts], [test][test_whenRescuePayloadTooLong_reverts], [test][test_whenRescuePayloadLengthBoundaries_revert] |
| DMCT-RESCUE-I09 | A | 32-byte payload word exceeds MAX160; seed MAX160+1,MAX256 | ActionInvalid(DM,rescueSelector) | No address truncation or ABI panic | Covered: [test][test_whenRescuePayloadAddressIsNoncanonical_reverts], [test][test_whenRescuePayloadAddressAtInvalidBounds_reverts] |
| DMCT-RESCUE-I10 | A | Batch contains unsupported selector | ActionInvalid(DM,unsupportedSelector) | Entire batch unchanged | Covered: [test][test_whenBatchSelectorUnsupported_reverts] |
| DMCT-RESCUE-L08 | A | DM paused; rescue-only batch with 1..15 distinct eligible tokens; seed 1 and 15 | Success | One key per token; no transfer | Covered: [test][test_givenManagerPaused_whenRescueOnlyBatchQueued], [test][test_givenManagerPaused_whenRescueBatchSizeBoundariesQueued] |
| DMCT-RESCUE-L09 | A | DM paused; mixed rescue/configuration batch, both orders | NotEnabled() for the enabled-only configuration action | Entire batch rolls back, including earlier rescue reservations | Covered: [test][test_givenManagerPaused_whenMixedBatchQueued_revertsAtomically], [test][test_givenManagerPaused_whenBothMixedBatchOrdersQueued_revert] |
| DMCT-RESCUE-P07 | A | DM enabled; mixed nonconflicting rescue/configuration batch | Success | Existing configuration validation retained; rescue schedules no immediate transfer | Covered: [test][test_givenManagerEnabled_whenMixedBatchQueued], [test][test_givenRescueOnlyBatch_whenManagerPausedAtExecution_sweepsBothTokens], [test][test_givenMixedBatch_whenManagerPausedAtExecution_revertsAtomically], [test][test_givenBatchPauseHistorySeeds_whenExecuting] |

Inherited empty/oversized-batch checks remain owned by [queueBatch](./queueBatch.md). The integration
rows above establish the new rescue selector's effect on batches without duplicating that whole plan.

## Numeric and notice-window boundaries

No public amount parameter exists. Counter exhaustion and timestamps use explicit storage/clock
fixtures. Except the exhausted-counter row, reserve a valid available ID and free T key.

| ID | Caller | Boundary / guaranteed seeds | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| DMCT-RESCUE-N01 | A | nextActionId=MAX64-1 | Return MAX64-1; nextActionId=MAX64 | One valid pending action; no narrowing | Covered: [test][test_givenLastAvailableActionId_whenRescueQueued] |
| DMCT-RESCUE-N02 | A | nextActionId=MAX64 | Panic(0x11) at checked increment | No action/key/ID mutation | Covered: [test][test_givenExhaustedActionCounter_whenRescueQueued_revertsWithoutPartialState] |
| DMCT-RESCUE-N03 | A | D fuzz 1day..30days, Q=MAX48-D-3days; seed both D bounds | Success; Y=MAX48 | Exact uint48 metadata, no truncation | Covered: [test][test_givenMaximumExpiry_whenRescueQueued], [test][test_givenMinimumAndMaximumDelay_whenMaximumExpiryQueued] |
| DMCT-RESCUE-N04 | A | Q=MAX48-D-3days+1 | Panic(0x11) at expiry addition | Complete queue rollback | Covered: [test][test_whenRescueExpiryAdditionOverflows_reverts] |
| DMCT-RESCUE-N05 | A | Q=MAX48-D+1 | Panic(0x11) at executableAt addition | Complete queue rollback | Covered: [test][test_whenRescueMaturityAdditionOverflows_reverts] |
| DMCT-RESCUE-N06 | Fuzz any executor | Valid pending rescue; now fuzz Q..X-1, seed Q and X-1 | ActionNotReady(id,X) | Pending operation/key/custody unchanged | Covered: [test][test_givenPendingRescue_whenExecutingBeforeMaturity_reverts], [test][test_whenRescueExecutedAtQueueTime_reverts], [test][test_whenRescueExecutedOneSecondBeforeMaturity_reverts] |
| DMCT-RESCUE-N07 | Fuzz any executor | Valid pending rescue; now fuzz X..Y, seed X,X+1,Y-1,Y | Success | Full live balance swept once; terminal metadata/key cleanup | Covered: [test][test_givenMatureRescue_whenExecutedWithinWindow], [test][test_whenRescueExecutedAtExactWindowBoundaries] |
| DMCT-RESCUE-N08 | Fuzz any executor | Valid pending rescue; now fuzz Y+1..MAX48 where nonempty; seed Y+1,MAX48 | ActionExpired(id,Y) | No transfer; expired action/key retained until cancellation | Covered: [test][test_givenExpiredRescue_whenExecuted_reverts], [test][test_whenRescueExecutedOneSecondAfterExpiry_reverts], [test][test_whenRescueExecutedAtMaximumTimestamp_reverts] |

## Rescue execution after queueing

These are action-specific integrations through `executeQueuedAction(id)`; they do not replace the
generic [executeQueuedAction](./executeQueuedAction.md) plan. Use a mature, unexpired pending rescue
and an unrelated executor unless varied. The executor receives no DM authority; TL is the DM caller.

| ID | Caller | Intervening transition / condition | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| DMCT-RESCUE-P08 | Fuzz any executor | Preview=1 at queue; another 2 raw units arrive; fresh preview=3 before execution | Success | Treasury +3, DM T=0; exact TokenRescued(T,3) matches fresh quote, sub-action and execution events | Covered: [test][test_givenAdditionalReceipts_whenRescueExecuted_matchesFreshPreviewAndEvents] |
| DMCT-RESCUE-P09 | Fuzz any executor | Queue at B=0, then positive receipt arrives | Success | Sweep full live B once | Covered: [test][test_givenZeroBalanceQueued_whenReceiptArrives_thenFullLiveBalanceRescued] |
| DMCT-RESCUE-P10 | Fuzz any executor | Direct ADMIN rescues first; no new receipt | Successful zero-balance execution | No DM transfer/event; TL still executes, clears action/key and emits terminal queue events | Covered: [test][test_givenAdminRescuedFirst_whenQueuedRescueExecuted_thenZeroBalanceTerminates] |
| DMCT-RESCUE-P11 | Fuzz any executor | Treasury R0 upgraded to R1 | Success | Only R1 gets live balance; no stale-Treasury payment | Covered: [test][test_givenTreasuryUpgraded_whenRescueExecuted_thenOnlyCurrentTreasuryPaid] |
| DMCT-RESCUE-L10 | Fuzz any executor | DM locally disabled after queue; also queue while disabled and keep it disabled | Success in both histories | DM remains disabled; no receipt/debt/custody-accounting change | Covered: [test][test_givenManagerOnly_givenDepositManagerDisabled_whenRescueQueuedAndExecuted], [test][test_givenDepositManagerPausedAfterQueue_whenRescueExecuted], [test][test_givenRescueOnlyBatch_whenManagerPausedAtExecution_sweepsBothTokens], [test][test_givenBatchPauseHistorySeeds_whenExecuting] |
| DMCT-RESCUE-L11 | Fuzz any executor | TL disabled after queue | NotEnabled() | Action/key retained; reEnable within grace permits retry before expiry | Covered: [test][test_givenTimelockPausedAfterQueue_whenExecutionRetriedAfterReEnable] |
| DMCT-RESCUE-L12 | Fuzz any executor | TL Kernel-inactive; local enabled fuzz false/true | DepositManagerConfigTimelock_PolicyInactive(TL) | Action/key retained; reactivation allows unexpired retry | Covered: [test][test_givenTimelockInactive_whenExecutionRetriedAfterActivation], [test][test_givenInactiveTimelock_whenBothPauseStatesRetried] |
| DMCT-RESCUE-L13 | Fuzz any executor | DM Kernel-inactive; local enabled fuzz false/true | PolicyDependency_NotActive(DM) | No transfer; pending action survives; reactivation allows retry | Covered: [test][test_givenDepositManagerInactive_whenExecutionRetriedAfterActivation], [test][test_givenInactiveManager_whenBothPauseStatesRetried] |
| DMCT-RESCUE-D03 | Fuzz any executor | DM reports foreign Kernel K2 after queue | PolicyDependency_KernelMismatch(DM,K,K2) | Pending operation/key retained | Covered: [test][test_givenManagerKernelDrift_whenRescueExecuted_revertsAndRetainsPending] |
| DMCT-RESCUE-D04 | Fuzz any executor | Selected operator rotated to C or zero | ConfigOperator_Unauthorized(TL) | No TL dispatch; restoration to TL allows unexpired retry | Covered: [test][test_givenManagerControllerRotated_whenExecutionRetriedAfterRestoration], [test][test_givenControllerRotatedOrCleared_whenBothRestoredAndRetried] |
| DMCT-RESCUE-A06 | Unrelated executor | Original M loses proposer role after valid queue | Success | Existing proposal remains executable; role revocation alone does not erase notice | Covered: [test][test_givenProposerRoleRevoked_whenUnrelatedExecutorRescues] |
| DMCT-RESCUE-D05 | Fuzz any executor | T onboarded as underlying, vault or stored share token after queue; seed all three | ConfigStateChanged(id,0,key,expectedHash,currentHash) | No token transfer; complete pending action/key retained | Covered: [test][test_givenQueuedTokenOnboardedAsUnderlying_whenRescueExecuted_reverts], [test][test_givenQueuedTokenOnboardedAsVault_whenRescueExecuted_reverts], [test][test_givenQueuedTokenOnboardedAsStoredShare_whenRescueExecuted_reverts] |
| DMCT-RESCUE-T01 | Fuzz any executor | Token balance/transfer reverts with exact typed fixture error | Exact error propagates through DM/DMCT | Token/state/log rollback; action not executed; keys retained | Covered: [test][test_givenTransferFails_whenRestoredBeforeExpiry_thenRescueRetries], [test][test_givenBalanceReadFailsAfterQueue_whenRescueExecuted_reverts] |
| DMCT-RESCUE-T02 | Fuzz any executor | Restore failed transfer and retry before expiry | Success | Live balance swept exactly once; key released | Covered: [test][test_givenTransferFails_whenRestoredBeforeExpiry_thenRescueRetries] |
| DMCT-RESCUE-C01 | Fuzz any executor | Token callback attempts same action execution | ActionAlreadyExecuted(id) in nested call; caught by token | Outer success exactly once; no duplicate sweep/events | Covered: [test][test_givenTokenCatchesSameActionCallback_whenRescueExecuted] |
| DMCT-RESCUE-C02 | Fuzz any executor | Token callback executes distinct mature U rescue; token propagates nested failure | DM ReentrancyGuardReentrantCall() | Both action executed flags/keys and both token balances roll back | Covered: [test][test_givenTokenPropagatesDistinctActionCallback_whenRescueExecuted_reverts] |

For C02 ensure the distinct queued action's admission/window/key checks all pass so that its call
reaches DM's shared guard; otherwise the test would prove the wrong boundary. Mandatory-transfer
and callback behavior belongs to [rescue](../DepositManager/rescue.md); these rows additionally prove
queue rollback. Do not create a second token-library return-shape matrix here.

## Cancellation, independence and stateful properties

Existing cancellation requires TL active and the EMERGENCY role, permits TL local disablement and
does not inspect DM readiness or selected operator. ADMIN-only and M-only do not acquire cancellation
authority. Use [cancelQueuedAction](./cancelQueuedAction.md) for shared state/error precedence.

| ID | Caller | Operation / transition | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| DMCT-RESCUE-P12 | Fuzz EMERGENCY holder | Cancel pending rescue before maturity, during window, and after expiry; seed each; TL enabled/disabled | Success | No transfer; cancellation metadata retained; T key/guards/payload released | Covered: [test][test_givenPendingRescue_whenEmergencyHolderCancels], [test][test_whenRescueCancelledBeforeMaturity], [test][test_whenRescueCancelledDuringWindowWhilePaused], [test][test_whenRescueCancelledAfterExpiry], [test][test_whenRescueCancelledBeforeMaturityWhilePaused], [test][test_whenRescueCancelledDuringWindowWhileEnabled], [test][test_whenRescueCancelledAfterExpiryWhilePaused] |
| DMCT-RESCUE-P13 | EMERGENCY holder | DM inactive/paused or controller rotated; TL active | Cancellation succeeds | Broken target/controller cannot trap rescue key | Covered: [test][test_givenManagerReadinessChanged_whenRescueCancelled], [test][test_givenManagerInactivePausedAndControllerRotated_whenRescueCancelled] |
| DMCT-RESCUE-A07 | Fuzz outside EMERGENCY holders | Cancel pending rescue; seed ADMIN-only and M-only | ROLES_RequireRole(EMERGENCY_ROLE) | Pending operation/key unchanged | Covered: [test][test_whenRescueCancelledByUnauthorizedCaller_reverts], [test][test_whenRescueCancelledByAdminOnly_reverts], [test][test_whenRescueCancelledByManagerOnly_reverts] |
| DMCT-RESCUE-P14 | Fuzz A or M | T rescue executed or cancelled, then propose T again | Return new ID | Old terminal metadata remains; new notice/key reservation | Covered: [test][test_givenRescueExecuted_whenSameTokenRequeued], [test][test_givenRescueCancelled_whenSameTokenRequeued] |
| DMCT-RESCUE-I11 | Fuzz any executor | Re-execute executed or cancelled rescue; seed each | ActionAlreadyExecuted(id) or ActionCancelled(id), respectively | No second transfer/key mutation | Covered: [test][test_givenRescueExecuted_whenExecutedAgain_reverts], [test][test_givenRescueCancelled_whenExecuted_reverts] |
| DMCT-RESCUE-P15 | Fuzz any executor | Older T rescue expired/stale; unrelated mature U rescue valid | U executes | No global queue-order blockage; T key/action untouched | Covered: [test][test_givenOlderRescueExpired_whenUnrelatedRescueExecuted], [test][test_givenOlderRescueStale_whenUnrelatedRescueExecuted] |
| DMCT-RESCUE-P16 | Stateful authorized/unauthorized handlers | Arbitrary queue/donate/rescue/cancel/execute, pauses, asset onboarding and controller changes | Every successful delegated transfer follows an unexpired mature action; ADMIN direct recovery is an explicit exception | Pending keys have one owner and release only on terminal success/cancel; managed custody/accounting conserved; Treasury-only payouts; no manager bypass or double execution | Covered: [invariant][invariant_rescueConservesCustodyAndPaysOnlyTreasury], [invariant][invariant_pendingKeysFollowModeledOwnershipAndTerminalCleanup], [invariant][invariant_delegatedRecoveryRespectsAuthorityAndNotice] |

## Implementation and size gates

Use the existing queue machinery; no second scheduler or recovery-controller system. Keep
metadata, conflict commitments and paused-rescue discrimination in TL. Use DM.previewRescue for
canonical admission and share DM's validation with rescue execution. The manager remains the final
authority for token eligibility and current Treasury at transfer time. Reuse its existing
config-authority predicate without changing manager-only bounded reEnable authority.

The [rescue plan's bytecode gate](../DepositManager/rescue.md#bytecode-acceptance) applies to DM and TL:
measure baseline/final deployment-profile runtime and initcode, record deltas/headroom, and keep
compiler settings unchanged. Measurements are recorded in the paired rescue plan after focused
deployment-profile builds.

- [x] Verify current queue lifecycle, exact errors, Inventory precedent and DM recovery boundaries.
- [x] Specify authority, paused recovery, canonical preview admission, keys, notice bounds, drift and rollback.
- [x] Capture failing direct-manager-bypass evidence before implementation; test typed queue and batch equivalence.
- [x] Implement the agreed API and selector-specific guards; preserve ordinary configuration gates.
- [x] Implement stateful conservation/queue-ownership coverage and reciprocal scenario mappings.
- [x] Run focused tests, Markdown/mapping checks, and baseline/final deploy-profile size validation.

[invariant_delegatedRecoveryRespectsAuthorityAndNotice]: ./queueRescue.invariant.t.sol#L103
[invariant_pendingKeysFollowModeledOwnershipAndTerminalCleanup]: ./queueRescue.invariant.t.sol#L87
[invariant_rescueConservesCustodyAndPaysOnlyTreasury]: ./queueRescue.invariant.t.sol#L54
[test_givenAdditionalReceipts_whenRescueExecuted_matchesFreshPreviewAndEvents]: ./queueRescue.t.sol#L990
[test_givenAdminAndManager_whenTypedBatchEquivalenceInBothPauseStates]: ./queueRescue.t.sol#L1667
[test_givenAdminOnly_whenBothManagerPauseStatesQueued]: ./queueRescue.t.sol#L1604
[test_givenAdminOnly_whenRescueQueued]: ./queueRescue.t.sol#L39
[test_givenAdminRescuedFirst_whenQueuedRescueExecuted_thenZeroBalanceTerminates]: ./queueRescue.t.sol#L1030
[test_givenAnotherConfigOperator_whenRescueQueued_reverts]: ./queueRescue.t.sol#L179
[test_givenAnotherController_whenBothManagerPauseStatesQueued_revert]: ./queueRescue.t.sol#L1637
[test_givenBalanceReadFailsAfterQueue_whenRescueExecuted_reverts]: ./queueRescue.t.sol#L1406
[test_givenBatchPauseHistorySeeds_whenExecuting]: ./queueRescue.t.sol#L1186
[test_givenBothProposerRoles_whenRescueQueued]: ./queueRescue.t.sol#L81
[test_givenConfiguredUnderlying_whenRescueQueued_reverts]: ./queueRescue.t.sol#L166
[test_givenConfiguredVault_whenRescueQueued_reverts]: ./queueRescue.t.sol#L429
[test_givenControllerRotatedOrCleared_whenBothRestoredAndRetried]: ./queueRescue.t.sol#L1703
[test_givenDepositManagerInactive_whenExecutionRetriedAfterActivation]: ./queueRescue.t.sol#L1246
[test_givenDepositManagerInactive_whenRescueQueued_reverts]: ./queueRescue.t.sol#L263
[test_givenDepositManagerInactive_whenUnauthorizedCallerQueuesZeroToken_revertsAuthorityFirst]: ./queueRescue.t.sol#L291
[test_givenDepositManagerPausedAfterQueue_whenRescueExecuted]: ./queueRescue.t.sol#L1114
[test_givenDepositOperatorOnly_whenRescueQueued_reverts]: ./queueRescue.t.sol#L567
[test_givenDisabledEmptyRoute_whenShareQueued_reverts]: ./queueRescue.t.sol#L468
[test_givenDisabledEmptyRoute_whenUnderlyingQueued_reverts]: ./queueRescue.t.sol#L456
[test_givenDisabledEmptyRoute_whenVaultQueued_reverts]: ./queueRescue.t.sol#L462
[test_givenEmergencyOnly_whenRescueQueued_reverts]: ./queueRescue.t.sol#L557
[test_givenEquivalentTypedAndBatchRescue_whenQueued_thenMetadataAgrees]: ./queueRescue.t.sol#L625
[test_givenExhaustedActionCounter_whenRescueQueued_revertsWithoutPartialState]: ./queueRescue.t.sol#L863
[test_givenExpiredRescue_whenExecuted_reverts]: ./queueRescue.t.sol#L942
[test_givenIdleCustody_whenZeroTokenQueued_reverts]: ./queueRescue.t.sol#L367
[test_givenIdleUnderlying_whenRescueQueued_reverts]: ./queueRescue.t.sol#L417
[test_givenInactiveManager_whenBothLocalPauseStatesQueued_revert]: ./queueRescue.t.sol#L1659
[test_givenInactiveManager_whenBothPauseStatesRetried]: ./queueRescue.t.sol#L1695
[test_givenInactiveTimelock_whenBothPauseStatesRetried]: ./queueRescue.t.sol#L1687
[test_givenLastAvailableActionId_whenRescueQueued]: ./queueRescue.t.sol#L855
[test_givenManagerControllerRotated_whenExecutionRetriedAfterRestoration]: ./queueRescue.t.sol#L1298
[test_givenManagerEnabled_whenMixedBatchQueued]: ./queueRescue.t.sol#L826
[test_givenManagerInactivePausedAndControllerRotated_whenRescueCancelled]: ./queueRescue.t.sol#L1496
[test_givenManagerKernelDrift_whenRescueExecuted_revertsAndRetainsPending]: ./queueRescue.t.sol#L1272
[test_givenManagerKernelGetterMalformed_whenRescueQueued_reverts]: ./queueRescue.t.sol#L348
[test_givenManagerKernelGetterReverts_whenRescueQueued_reverts]: ./queueRescue.t.sol#L330
[test_givenManagerOnly_givenDepositManagerDisabled_whenRescueQueuedAndExecuted]: ./queueRescue.t.sol#L145
[test_givenManagerOnly_whenBothManagerPauseStatesQueued]: ./queueRescue.t.sol#L1612
[test_givenManagerOnly_whenRescueQueued]: ./queueRescue.t.sol#L63
[test_givenManagerPaused_whenBothMixedBatchOrdersQueued_revert]: ./queueRescue.t.sol#L809
[test_givenManagerPaused_whenMixedBatchQueued_revertsAtomically]: ./queueRescue.t.sol#L795
[test_givenManagerPaused_whenRescueBatchSizeBoundariesQueued]: ./queueRescue.t.sol#L789
[test_givenManagerPaused_whenRescueOnlyBatchQueued]: ./queueRescue.t.sol#L784
[test_givenManagerReadinessChanged_whenRescueCancelled]: ./queueRescue.t.sol#L1480
[test_givenMatureRescue_whenExecutedWithinWindow]: ./queueRescue.t.sol#L926
[test_givenMaximumExpiry_whenRescueQueued]: ./queueRescue.t.sol#L874
[test_givenMinimumAndMaximumDelay_whenMaximumExpiryQueued]: ./queueRescue.t.sol#L879
[test_givenMixedBatch_whenManagerPausedAtExecution_revertsAtomically]: ./queueRescue.t.sol#L1159
[test_givenNoConfigOperator_whenRescueQueued_reverts]: ./queueRescue.t.sol#L195
[test_givenNoConfiguredAssets_whenZeroTokenQueued_reverts]: ./queueRescue.t.sol#L379
[test_givenNoController_whenBothManagerPauseStatesQueued_revert]: ./queueRescue.t.sol#L1648
[test_givenOlderRescueExpired_whenUnrelatedRescueExecuted]: ./queueRescue.t.sol#L1584
[test_givenOlderRescueStale_whenUnrelatedRescueExecuted]: ./queueRescue.t.sol#L1591
[test_givenOverlappingRoles_whenBothManagerPauseStatesQueued]: ./queueRescue.t.sol#L1620
[test_givenPausedManagerWithForeignKernel_whenRescueQueued_revertsMismatch]: ./queueRescue.t.sol#L308
[test_givenPendingRescue_whenAnotherTokenQueued_thenKeysAreIndependent]: ./queueRescue.t.sol#L673
[test_givenPendingRescue_whenEmergencyHolderCancels]: ./queueRescue.t.sol#L1437
[test_givenPendingRescue_whenExecutingBeforeMaturity_reverts]: ./queueRescue.t.sol#L515
[test_givenPendingRescue_whenTypedOrBatchDuplicateQueued_reverts]: ./queueRescue.t.sol#L650
[test_givenPreviewBalanceReadFails_whenQueued_revertsExactTokenError]: ./queueRescue.t.sol#L474
[test_givenProposerRoleRevoked_whenUnrelatedExecutorRescues]: ./queueRescue.t.sol#L1320
[test_givenQueuedTokenOnboardedAsStoredShare_whenRescueExecuted_reverts]: ./queueRescue.t.sol#L1365
[test_givenQueuedTokenOnboardedAsUnderlying_whenRescueExecuted_reverts]: ./queueRescue.t.sol#L1330
[test_givenQueuedTokenOnboardedAsVault_whenRescueExecuted_reverts]: ./queueRescue.t.sol#L1346
[test_givenRescueCancelled_whenExecuted_reverts]: ./queueRescue.t.sol#L1570
[test_givenRescueCancelled_whenSameTokenRequeued]: ./queueRescue.t.sol#L1539
[test_givenRescueExecuted_whenExecutedAgain_reverts]: ./queueRescue.t.sol#L1555
[test_givenRescueExecuted_whenSameTokenRequeued]: ./queueRescue.t.sol#L1522
[test_givenRescueOnlyBatch_whenManagerPausedAtExecution_sweepsBothTokens]: ./queueRescue.t.sol#L1124
[test_givenRescuePending_whenDepositCapQueued_thenDomainsAreIndependent]: ./queueRescue.t.sol#L686
[test_givenRescuePending_whenMinimumDepositQueued_thenDomainsAreIndependent]: ./queueRescue.t.sol#L694
[test_givenRescuePending_whenPeriodDisableQueued_thenDomainsAreIndependent]: ./queueRescue.t.sol#L711
[test_givenRescuePending_whenWithdrawalModeQueued_thenDomainsAreIndependent]: ./queueRescue.t.sol#L702
[test_givenStoredExternalShare_whenRescueQueued_reverts]: ./queueRescue.t.sol#L434
[test_givenTimelockDisabled_whenUnauthorizedCallerQueuesZeroToken_revertsPauseFirst]: ./queueRescue.t.sol#L246
[test_givenTimelockInactiveAndDisabled_whenRescueQueued_revertsActivityFirst]: ./queueRescue.t.sol#L211
[test_givenTimelockInactiveAndEnabled_whenRescueQueued_reverts]: ./queueRescue.t.sol#L232
[test_givenTimelockInactive_whenExecutionRetriedAfterActivation]: ./queueRescue.t.sol#L1221
[test_givenTimelockPausedAfterQueue_whenExecutionRetriedAfterReEnable]: ./queueRescue.t.sol#L1204
[test_givenTimelockReEnabled_whenRescueQueued]: ./queueRescue.t.sol#L278
[test_givenTokenCatchesSameActionCallback_whenRescueExecuted]: ./queueRescueCallback.t.sol#L16
[test_givenTokenPropagatesDistinctActionCallback_whenRescueExecuted_reverts]: ./queueRescueCallback.t.sol#L42
[test_givenTransferFails_whenRestoredBeforeExpiry_thenRescueRetries]: ./queueRescue.t.sol#L1385
[test_givenTreasuryMissing_whenPositiveBalanceQueued_reverts]: ./queueRescue.t.sol#L582
[test_givenTreasuryMissing_whenQueued_revertsMatchingPreview]: ./queueRescue.t.sol#L490
[test_givenTreasuryMissing_whenZeroBalanceQueued_reverts]: ./queueRescue.t.sol#L577
[test_givenTreasuryUpgraded_whenRescueExecuted_thenOnlyCurrentTreasuryPaid]: ./queueRescue.t.sol#L1073
[test_givenUnauthorizedCaller_whenBothManagerPauseStatesQueued_revert]: ./queueRescue.t.sol#L1631
[test_givenVaultCustody_whenZeroTokenQueued_reverts]: ./queueRescue.t.sol#L362
[test_givenVaultReportedShareChanges_whenStoredShareQueued_reverts]: ./queueRescue.t.sol#L440
[test_givenVaultShareGetterReverts_whenStoredShareQueued_reverts]: ./queueRescue.t.sol#L448
[test_givenZeroBalanceQueued_whenReceiptArrives_thenFullLiveBalanceRescued]: ./queueRescue.t.sol#L1018
[test_whenBatchSelectorUnsupported_reverts]: ./queueRescue.t.sol#L768
[test_whenNoCodeTokenQueued_reverts]: ./queueRescue.t.sol#L411
[test_whenRescueBatchTargetWrong_reverts]: ./queueRescue.t.sol#L719
[test_whenRescueCancelledAfterExpiry]: ./queueRescue.t.sol#L1460
[test_whenRescueCancelledAfterExpiryWhilePaused]: ./queueRescue.t.sol#L1475
[test_whenRescueCancelledBeforeMaturity]: ./queueRescue.t.sol#L1450
[test_whenRescueCancelledBeforeMaturityWhilePaused]: ./queueRescue.t.sol#L1465
[test_whenRescueCancelledByAdminOnly_reverts]: ./queueRescue.t.sol#L1512
[test_whenRescueCancelledByManagerOnly_reverts]: ./queueRescue.t.sol#L1517
[test_whenRescueCancelledByUnauthorizedCaller_reverts]: ./queueRescue.t.sol#L1506
[test_whenRescueCancelledDuringWindowWhileEnabled]: ./queueRescue.t.sol#L1470
[test_whenRescueCancelledDuringWindowWhilePaused]: ./queueRescue.t.sol#L1455
[test_whenRescueExecutedAtExactWindowBoundaries]: ./queueRescue.t.sol#L934
[test_whenRescueExecutedAtMaximumTimestamp_reverts]: ./queueRescue.t.sol#L974
[test_whenRescueExecutedAtQueueTime_reverts]: ./queueRescue.t.sol#L913
[test_whenRescueExecutedOneSecondAfterExpiry_reverts]: ./queueRescue.t.sol#L958
[test_whenRescueExecutedOneSecondBeforeMaturity_reverts]: ./queueRescue.t.sol#L918
[test_whenRescueExpiryAdditionOverflows_reverts]: ./queueRescue.t.sol#L887
[test_whenRescueMaturityAdditionOverflows_reverts]: ./queueRescue.t.sol#L900
[test_whenRescuePayloadAddressAtInvalidBounds_reverts]: ./queueRescue.t.sol#L762
[test_whenRescuePayloadAddressIsNoncanonical_reverts]: ./queueRescue.t.sol#L755
[test_whenRescuePayloadLengthBoundaries_revert]: ./queueRescue.t.sol#L746
[test_whenRescuePayloadTooLong_reverts]: ./queueRescue.t.sol#L741
[test_whenRescuePayloadTooShort_reverts]: ./queueRescue.t.sol#L736
[test_whenRescueProposerUnauthorized_reverts]: ./queueRescue.t.sol#L132
[test_whenRescueQueued_emitsExactCommitmentAndQueueEvents]: ./queueRescue.t.sol#L587
[test_whenRescueTokenBalanceIsMaximum]: ./queueRescue.t.sol#L121
[test_whenRescueTokenBalanceIsOne]: ./queueRescue.t.sol#L110
[test_whenRescueTokenBalanceIsZero]: ./queueRescue.t.sol#L100
[test_whenZeroProposerQueuesRescue_reverts]: ./queueRescue.t.sol#L547
