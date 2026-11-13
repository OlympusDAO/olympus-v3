# BurnerLoansActivator.activate coverage plan

The constructor fixes all targets and the sole timelock caller. Launch accepts no runtime parameters or tokens. Fresh-policy history enforces the empty referral whitelist assumption. Numeric boundaries belong to target configuration tests; this helper applies a fixed configuration. Local tests use real Burner Loans and custody contracts with a mock PRICE module and periodic task manager. Mainnet Heart and real Governor execution remain separate proposal-fork acceptance criteria.

| ID          | Scenario                                                                          | Test                                                                                                                                                                     |
| ----------- | --------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| BLAUNCH-A01 | Every unauthorized caller is rejected                                             | [test_whenCallerIsNotTimelock_reverts][test_whenCallerIsNotTimelock_reverts]                                                                                             |
| BLAUNCH-P01 | Fixed launch settings, Core-bound Auth selected once and existing task order      | [test_givenPreparedStack_whenTimelockActivates][test_givenPreparedStack_whenTimelockActivates]                                                                           |
| BLAUNCH-S01 | Replay is rejected                                                                | [test_givenAlreadyActivated_whenTimelockActivates_reverts][test_givenAlreadyActivated_whenTimelockActivates_reverts]                                                     |
| BLAUNCH-S02 | Any inactive policy is rejected                                                   | [test_givenInactivePolicy_whenTimelockActivates_reverts][test_givenInactivePolicy_whenTimelockActivates_reverts]                                                         |
| BLAUNCH-S03 | Previously enabled Risk with retained whitelist is rejected                       | [test_givenRiskPreviouslyEnabled_givenReferrerAllowed_whenTimelockActivates_reverts][test_givenRiskPreviouslyEnabled_givenReferrerAllowed_whenTimelockActivates_reverts] |
| BLAUNCH-S04 | Late external failure rolls back every earlier mutation                           | [test_givenLateTaskFailure_whenTimelockActivates_reverts][test_givenLateTaskFailure_whenTimelockActivates_reverts]                                                       |
| BLAUNCH-S05 | Missing OHM or USDS PRICE support is rejected; the OCG fork covers USDe admission | [test_givenPriceSupportMissing_whenTimelockActivates_reverts][test_givenPriceSupportMissing_whenTimelockActivates_reverts]                                               |
| BLAUNCH-S06 | Previously enabled backing oracle is rejected without overwriting backing                                                          | [test_givenBackingOraclePreviouslyEnabled_whenTimelockActivates_reverts][test_givenBackingOraclePreviouslyEnabled_whenTimelockActivates_reverts]                                                               |
| BLAUNCH-C01 | Zero governance timelock is rejected                                              | [test_whenTimelockIsZero_reverts][test_whenTimelockIsZero_reverts]                                                                                                       |
| BLAUNCH-C02 | Missing component code is rejected                                                | [test_whenComponentHasNoCode_reverts][test_whenComponentHasNoCode_reverts]                                                                                               |
| BLAUNCH-C04 | Revenue task bound to a different distributor is rejected                         | [test_whenRevenueTaskBoundToDifferentDistributor_reverts][test_whenRevenueTaskBoundToDifferentDistributor_reverts]                                                       |
| BLAUNCH-O01 | Fresh disabled BackingOracle is initialized to $11.99 and its queue is selected/enabled by OCG          | [test_givenFreshBackingOracle_whenTimelockActivates][test_givenFreshBackingOracle_whenTimelockActivates]                                     |
| BLAUNCH-O02 | Inactive external backing oracle is rejected before proposal preparation          | [test_givenBackingOracleInactive_whenPreparationValidated_reverts][test_givenBackingOracleInactive_whenPreparationValidated_reverts]                                     |
| BLAUNCH-C03 | Constructor caller receives no authority                                          | [test_whenCreatedByAnyCaller][test_whenCreatedByAnyCaller]                                                                                                               |
| BLAUNCH-C06 | Missing Auth code, including the zero address, is rejected                        | [test_whenAuthHasNoCode_reverts][test_whenAuthHasNoCode_reverts]                                                                                                         |
| BLAUNCH-C07 | Auth bound to another Core is rejected                                            | [test_whenAuthBoundToDifferentCore_reverts][test_whenAuthBoundToDifferentCore_reverts]                                                                                   |

- [x] Focused RED observed before behavior implementation.
- [x] Authorization, state, rollback and fixed configuration scenarios implemented.

| ID | Scenario | Test |
| --- | --- | --- |
| BLAUNCH-A02 | Any missing activator, settlement, custody or seizer role aborts activation | [test_givenMissingRole_whenTimelockActivates_reverts][test_givenMissingRole_whenTimelockActivates_reverts] |
| BLAUNCH-C05 | Any of the five queues with a missing or different immutable target aborts activation | [test_givenWrongTimelockTarget_whenTimelockActivates_reverts][test_givenWrongTimelockTarget_whenTimelockActivates_reverts] |

| ID | Scenario | Test |
| --- | --- | --- |
| BLAUNCH-S07 | Inactive PriceConfig is rejected even if USDe is already approved | [test][test_givenPriceConfigInactive_whenTimelockActivates_reverts] |
| BLAUNCH-S08 | Disabled PriceConfig is rejected even if USDe is already approved | [test][test_givenPriceConfigDisabled_whenTimelockActivates_reverts] |
| BLAUNCH-O03 | Inactive backing queue is rejected before mutations | [test][test_givenBackingQueueInactive_whenTimelockActivates_reverts] |

## Heart baseline acceptance criteria

The timelock remains the sole caller. The activator has no Policy/enabled lifecycle of its own;
Heart activity/enablement and all existing graph/freshness/role prerequisites remain mandatory.
There are no new runtime numeric inputs, token transfers, previews or ongoing stateful invariants.
The six reviewed mainnet identities are hard-coded in the activator, never supplied by the deployer
or derived from Heart's current list.
Selectors are fixed to zero, migrate(), zero, operate(), endEpoch(), zero. All six identities,
positions and selectors must match before launch mutation or insertion; count must be exactly six.
Reverts preserve the one-use flag, existing roles, task list, oracle, market, custody and queue state.
The proposal fork additionally proves rollback of roles temporarily granted by OCG.

| ID | Scenario | Test |
| --- | --- | --- |
| BLAUNCH-H01 | Missing task at any index, or empty list, rejects | [test][test_givenMissingHeartTask_whenTimelockActivates_reverts], [test][test_givenEmptyHeartTasks_whenTimelockActivates_reverts] |
| BLAUNCH-H02 | Extra task at any insertion point rejects | [test][test_givenExtraHeartTask_whenTimelockActivates_reverts] |
| BLAUNCH-H03 | Swapping any adjacent pair rejects | [test][test_givenReorderedHeartTasks_whenTimelockActivates_reverts] |
| BLAUNCH-H04 | Replacing any reviewed task identity rejects | [test][test_givenReplacedHeartTask_whenTimelockActivates_reverts] |
| BLAUNCH-H05 | Changing any selector rejects | [test][test_givenChangedHeartSelector_whenTimelockActivates_reverts], [fork test][test_givenHeartSelectorDrift_whenGovernanceExecutes_reverts] |
| BLAUNCH-H06 | Preinserted launch tasks, including count-preserving replacement, reject | [test][test_givenPreinsertedLaunchTask_whenTimelockActivates_reverts], [test][test_givenLaunchTaskReplacesOperator_whenTimelockActivates_reverts] |
| BLAUNCH-H07 | Drift present before activator deployment is not accepted as the baseline | [test][test_givenHeartDriftBeforeDeployment_whenTimelockActivates_reverts] |
| BLAUNCH-H08 | Restoring the genuine baseline permits retry, retaining every identity/selector | [test][test_givenRestoredHeartBaseline_whenTimelockActivates] |
| BLAUNCH-H09 | Real OCG execution with selector drift rolls back temporary ADMIN and permanent launch role grants, flag and launch mutations | [test][test_givenHeartSelectorDrift_whenGovernanceExecutes_reverts] |
| BLAUNCH-H10 | Failed and malformed Heart task reads fail closed with the Heart prerequisite error | [test][test_givenHeartReadFails_whenTimelockActivates_reverts], [test][test_givenMalformedHeartRead_whenTimelockActivates_reverts], [test][test_givenHeartReadHasTrailingData_whenTimelockActivates_reverts] |

- [x] Heart regressions RED before implementation (eight failures against the unchanged activator).
- [x] Simplified validation GREEN: 34 activator tests and 15 proposal/lifecycle fork tests.
- [x] Real OCG role rollback and restored-baseline retry reverified.
- [x] Deploy size, focused lint, formatting and scenario mapping reverified.
- [x] Deploy profile: runtime 24,570 bytes (6 bytes EIP-170 headroom), creation 34,398 bytes;
      constructor arguments included: 35,454 bytes (13,698 bytes EIP-3860 headroom).

[test_whenCallerIsNotTimelock_reverts]: ./activate.t.sol#L30
[test_givenPreparedStack_whenTimelockActivates]: ./activate.t.sol#L44
[test_givenAlreadyActivated_whenTimelockActivates_reverts]: ./activate.t.sol#L314
[test_givenInactivePolicy_whenTimelockActivates_reverts]: ./activate.t.sol#L322
[test_givenRiskPreviouslyEnabled_givenReferrerAllowed_whenTimelockActivates_reverts]: ./activate.t.sol#L465
[test_givenLateTaskFailure_whenTimelockActivates_reverts]: ./activate.t.sol#L487
[test_givenPriceSupportMissing_whenTimelockActivates_reverts]: ./activate.t.sol#L508
[test_givenBackingOraclePreviouslyEnabled_whenTimelockActivates_reverts]: ./activate.t.sol#L527
[test_whenTimelockIsZero_reverts]: ./activate.t.sol#L581
[test_whenComponentHasNoCode_reverts]: ./activate.t.sol#L592
[test_whenCreatedByAnyCaller]: ./activate.t.sol#L605
[test_whenRevenueTaskBoundToDifferentDistributor_reverts]: ./activate.t.sol#L421
[test_givenFreshBackingOracle_whenTimelockActivates]: ./activate.t.sol#L437
[test_givenBackingOracleInactive_whenPreparationValidated_reverts]: ./activate.t.sol#L452
[test_givenMissingRole_whenTimelockActivates_reverts]: ./activate.t.sol#L337
[test_givenWrongTimelockTarget_whenTimelockActivates_reverts]: ./activate.t.sol#L369

[test_whenAuthHasNoCode_reverts]: ./activate.t.sol#L397
[test_whenAuthBoundToDifferentCore_reverts]: ./activate.t.sol#L409

[test_givenPriceConfigInactive_whenTimelockActivates_reverts]: ./activate.t.sol#L542
[test_givenPriceConfigDisabled_whenTimelockActivates_reverts]: ./activate.t.sol#L568
[test_givenBackingQueueInactive_whenTimelockActivates_reverts]: ./activate.t.sol#L555
[test_givenMissingHeartTask_whenTimelockActivates_reverts]: ./activate.t.sol#L131
[test_givenEmptyHeartTasks_whenTimelockActivates_reverts]: ./activate.t.sol#L137
[test_givenExtraHeartTask_whenTimelockActivates_reverts]: ./activate.t.sol#L143
[test_givenReorderedHeartTasks_whenTimelockActivates_reverts]: ./activate.t.sol#L153
[test_givenReplacedHeartTask_whenTimelockActivates_reverts]: ./activate.t.sol#L162
[test_givenChangedHeartSelector_whenTimelockActivates_reverts]: ./activate.t.sol#L174
[test_givenPreinsertedLaunchTask_whenTimelockActivates_reverts]: ./activate.t.sol#L200
[test_givenHeartDriftBeforeDeployment_whenTimelockActivates_reverts]: ./activate.t.sol#L249
[test_givenRestoredHeartBaseline_whenTimelockActivates]: ./activate.t.sol#L258
[test_givenHeartSelectorDrift_whenGovernanceExecutes_reverts]: ../BurnerLoansProposal/heartOrderFork.t.sol#L32
[test_givenLaunchTaskReplacesOperator_whenTimelockActivates_reverts]: ./activate.t.sol#L186
[test_givenHeartReadFails_whenTimelockActivates_reverts]: ./activate.t.sol#L212
[test_givenMalformedHeartRead_whenTimelockActivates_reverts]: ./activate.t.sol#L224
[test_givenHeartReadHasTrailingData_whenTimelockActivates_reverts]: ./activate.t.sol#L236
