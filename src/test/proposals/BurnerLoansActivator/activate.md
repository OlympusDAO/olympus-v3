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
| BLAUNCH-S06 | Zero backing is rejected                                                          | [test_givenZeroBacking_whenTimelockActivates_reverts][test_givenZeroBacking_whenTimelockActivates_reverts]                                                               |
| BLAUNCH-C01 | Zero governance timelock is rejected                                              | [test_whenTimelockIsZero_reverts][test_whenTimelockIsZero_reverts]                                                                                                       |
| BLAUNCH-C02 | Missing component code is rejected                                                | [test_whenComponentHasNoCode_reverts][test_whenComponentHasNoCode_reverts]                                                                                               |
| BLAUNCH-C04 | Revenue task bound to a different distributor is rejected                         | [test_whenRevenueTaskBoundToDifferentDistributor_reverts][test_whenRevenueTaskBoundToDifferentDistributor_reverts]                                                       |
| BLAUNCH-O01 | Disabled external backing oracle is rejected before proposal preparation          | [test_givenBackingOracleDisabled_whenPreparationValidated_reverts][test_givenBackingOracleDisabled_whenPreparationValidated_reverts]                                     |
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

[test_whenCallerIsNotTimelock_reverts]: ./activate.t.sol#L28
[test_givenPreparedStack_whenTimelockActivates]: ./activate.t.sol#L42
[test_givenAlreadyActivated_whenTimelockActivates_reverts]: ./activate.t.sol#L105
[test_givenInactivePolicy_whenTimelockActivates_reverts]: ./activate.t.sol#L113
[test_givenRiskPreviouslyEnabled_givenReferrerAllowed_whenTimelockActivates_reverts]: ./activate.t.sol#L254
[test_givenLateTaskFailure_whenTimelockActivates_reverts]: ./activate.t.sol#L275
[test_givenPriceSupportMissing_whenTimelockActivates_reverts]: ./activate.t.sol#L292
[test_givenZeroBacking_whenTimelockActivates_reverts]: ./activate.t.sol#L311
[test_whenTimelockIsZero_reverts]: ./activate.t.sol#L324
[test_whenComponentHasNoCode_reverts]: ./activate.t.sol#L335
[test_whenCreatedByAnyCaller]: ./activate.t.sol#L348
[test_whenRevenueTaskBoundToDifferentDistributor_reverts]: ./activate.t.sol#L212
[test_givenBackingOracleDisabled_whenPreparationValidated_reverts]: ./activate.t.sol#L228
[test_givenBackingOracleInactive_whenPreparationValidated_reverts]: ./activate.t.sol#L241
[test_givenMissingRole_whenTimelockActivates_reverts]: ./activate.t.sol#L128
[test_givenWrongTimelockTarget_whenTimelockActivates_reverts]: ./activate.t.sol#L160

[test_whenAuthHasNoCode_reverts]: ./activate.t.sol#L188
[test_whenAuthBoundToDifferentCore_reverts]: ./activate.t.sol#L200
