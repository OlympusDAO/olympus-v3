# distribute scenario plan

Source: [RevenueDistributor](../../../policies/RevenueDistributor.sol).

Scope: reserve new receipts and attempt current RD payouts. Pending views are checked alongside execution; explicit historical-recipient retry is in [transferPendingPayout](./transferPendingPayout.md).

Co-located getters: successful distribution, donations and debt settlement leave assetState, ordered routes, active membership and assetDistributionHash unchanged. A compatible Treasury upgrade refreshes treasury(); Treasury changes alone do not change the route hash. Check treasury()/yieldRecipient() against actual destinations and pending getters against independent allocations; getter callers are permissionless across lifecycle states.

Default: the acting policy is Kernel-active. Inactivity tests retain valid caller roles/operator binding and active dependencies; snapshot after deactivation, before the attempted action. Getters remain readable. Preserve existing guard precedence unless a row specifies a change.

## Domains and assertions

Own-policy admission: require Kernel-active RevenueDistributor; own inactivity uses `RevenueDistributor_PolicyNotActive(RD)` before body/input/idempotent work. Require own Kernel activity before local enabled state (when required), caller authority, inputs and dependency checks. Successful body scenarios assume Local active=true, except explicit admission failures.

Debt, custody and transfer quantities are uint256 token base units; `MAX` means `type(uint256).max`.

Permissionless: fuzz caller without exclusions. Requires locally enabled, Kernel-active RD and Active asset, in that order. Amounts are token base units. custody is B, sum of unpaid configured/yield/Treasury buckets is R, new receipts N=B-R. Valid custody is R..uint256.max.

Unchanged means balances, liabilities, route configuration, membership indexes and lifecycle state retain their pre-call values; a reverted transaction commits no events. Check exact error data. Views are permissionless, including while disabled or Kernel-inactive. Compute each non-Treasury share as floor(N*bps/10,000) independently, using full-precision arithmetic. Treasury receives N minus all shares, including rounding dust. Add exactly N to debt before delivery; decrease debt only by successful payments. Check custody/recipient deltas, per-recipient debt, deduplicated recipient and asset indexes, exact Distributed/DistributionDeferred logs, no second payment and unrelated-asset isolation.

## Lifecycle

| ID | Caller | Local active | Local enabled | Asset state | New receipts | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| DIST-L01 | Fuzz all callers | true | false | Active | Positive | NotEnabled() | Unchanged | Covered: [seed][test_givenDisabled_whenManagedBalanceArrives_reverts], [full matrix][test_givenDisabledDistributor_whenAnyCallerDistributes_revertsAndRollsBack]; [full matrix][test_givenInactiveDistributor_whenAnyCallerDistributes_revertsAndRollsBack] |
| DIST-L02 | Fuzz all callers | false | true | Active | Positive | RevenueDistributor_PolicyNotActive(RD) | Unchanged | Covered: [seed][test_givenKernelInactive_whenManagedBalanceArrives_reverts], [full matrix][test_givenDisabledDistributor_whenAnyCallerDistributes_revertsAndRollsBack]; [full matrix][test_givenInactiveDistributor_whenAnyCallerDistributes_revertsAndRollsBack] |

## Invalid inputs

| ID | Caller | Local active | Local enabled | Asset state | Custody B | Reserved debt R | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| DIST-I01 | Fuzz all callers | true | true | Fuzz zero, EOA, NeverListed, Retired | Any | Any | RevenueDistributor_AssetNotActive(asset) | Unchanged | Covered: [evidence][test_givenAssetNotActive_whenDistributed_reverts] |
| DIST-I02 | Fuzz all callers | true | true | Active | R-1 for positive R | Positive R>B | RevenueDistributor_InsufficientPayoutBalance(asset) | Unchanged; no new reservation or payout | Covered: [evidence][test_givenReservedDebtExceedsCustody_whenDistributed_reverts] |

## Numeric extremes and rounding

| ID | Caller | Route topology | Route BPS | Reserved debt R | New receipts N | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| DIST-P02 | Fuzz all callers | One configured recipient | 3,333 | 0 | Fuzz 1..MAX; seed 0,1,3,4,9,999,10,000,10,001,MAX | Success; configured floor(N*3333/10000), Treasury residual | Exact allocation and reserve cleanup | Covered: [fuzz][test_givenAliceConfiguredAsRecipient_whenBalanceIsFuzzed], [maximum][test_givenAliceConfiguredAsRecipient_whenBalanceIsMaximum_preservesExactTotal], [rounding seed][test_givenAliceConfiguredAsRecipient_whenBalanceHasRoundingDust], [events][test_givenAliceConfiguredAsRecipient_emitsEachRecipientPayout], [caller and boundary matrix][test_givenOneConfiguredRecipient_whenBoundaryBalancesDistributed_conservesExactAmount] |

## Transfer failures

| ID | Caller | Route topology | Failing destination class | Failed transfer behavior | Other transfers | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| DIST-T01 | Fuzz all callers | Includes selected class | Fuzz configured/yield/Treasury | Returns false | Succeed | Success; DistributionDeferred for the selected share | Selected debt retained with exact indexes/reserve; healthy shares paid | Covered: [configured seed][test_givenRecipientTransferFails_keepsOnlyRecipientPending], [full matrix][test_givenOneTransferReturnsFalse_whenAnyCallerDistributes_defersOnlySelectedClass] |
| DIST-T06 | Fuzz all callers | Configured and Treasury destinations | Both classes | Return false | None | Success; DistributionDeferred for each failed share | Every failed debt retained and indexed | Covered: [evidence][test_givenMultipleTransfersReturnFalse_defersEveryShare] |
| DIST-T02 | Fuzz all callers | Includes selected class | Fuzz configured/yield/Treasury | Reverts | Succeed | Success; DistributionDeferred for the selected share | Selected debt retained with exact indexes/reserve; healthy shares paid | Covered: [Treasury seed][test_givenTreasuryBlacklisted_retainsTreasuryShare], [full matrix][test_givenOneTransferReverts_whenAnyCallerDistributes_defersOnlySelectedClass] |
| DIST-T09 | Fuzz all callers | Configured and Treasury destinations | Both classes | Revert via propagated callback failure | None | Success; DistributionDeferred for each failed share | Every failed debt retained and custody unchanged | Covered: [evidence][test_givenCallbackFailureBubbles_defersEachShare] |
| DIST-T03 | Fuzz all callers | Treasury-only route | Treasury | Reports success without movement | N/A | Success according to SafeERC20 return convention | Record apparent delivery; residual custody becomes later receipts; document token admission assumption | Covered: [evidence][test_givenTokenReportsTransferSuccessWithoutMovement_recordsApparentDelivery] |

## Balance query failures

| ID | Caller | Local active | Local enabled | Asset state | `balanceOf` behavior | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| DIST-I03 | Fuzz all callers | true | true | Active | Reverts with controlled custom error | Bubble exact token query error | Unchanged; no new allocation, payout attempt or committed event | Covered: [evidence][test_givenActiveAsset_whenBalanceQueryReverts_bubblesExactError] |
| DIST-I07 | Fuzz all callers | true | true | Active | Returns one byte | Dependency ABI decode failure | Unchanged; no new allocation, payout attempt or committed event | Covered: [evidence][test_givenActiveAsset_whenBalanceQueryReturnsMalformedData_reverts] |

## Callbacks

| ID | Caller | Callback destination | Nested guarded call | Callback handling | Other destinations | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| DIST-C01 | Fuzz all callers | Fuzz configured/yield/Treasury | Distribute, retry, configuration or rescue | Caught | Succeed | Outer success; nested ReentrancyGuardReentrantCall() | Original allocation used; pay once | Covered: [distribution seed][test_givenCallbackToken_nestedDistributionFailsAndPaysOnce], [timelock roles][test_givenMaturedRouteChange_whenTokenCallsTimelockDuringDistribution_thenRouteStaysFixed], [guarded-write matrix][test_givenCallbackFromAnyPayoutClass_whenAnyGuardedWriteAttempted_outerDistributionPaysOnce], [getter observation][test_givenPayoutCallbackReadsPendingGetter_observesDebtBeforeDeliveryClearsIt] |
| DIST-C02 | Fuzz all callers | Fuzz configured/yield/Treasury | Guarded write | Propagated | Succeed | Outer success; affected transfer deferred | Debt and custody retained; no partial failed-token movement | Covered: [seed][test_givenCallbackFailureBubbles_defersEachShare], [caller, logs and retry][test_givenPropagatedGuardFailure_whenAnyCallerDistributes_defersThenRetriesExactly] |

## Allocation

| ID | Caller | Asset state | Route topology | Total non-Treasury BPS | Reserved debt R | New receipts N | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| DIST-P01 | Fuzz all callers | Active | Treasury-only | 0 | 0 | 0 | Success | No token call or distribution event | Covered: [balance seed][test_givenZeroBalance_succeedsWithoutTransfer], [call and event exclusion][test_givenZeroBalance_whenAnyCallerDistributes_makesNoTokenCallOrEvent] |
| DIST-P08 | Fuzz all callers | Active | Enumerate Treasury-only, repurchase-only, one configured, multiple configured, mixed | Fuzz valid total, including mixed routes with deliberate Treasury remainder; seed 1/9,999/10,000 for one share, 1/9,999 for two, and 1/9,998 for three | 0 | Fuzz 1..MAX; seed 1,MAX | Success; each explicit share rounds down and Treasury receives the residual | Every configured/yield/Treasury amount and aggregate reserve is conserved; exact transfers/events/index cleanup; other assets unchanged | Covered: [Treasury-only][test_givenTreasuryOnlyRoute_whenBalanceDistributed_paysExactAmount], [repurchase seed][test_givenYieldRecipientVaultEnabled_emitsRepurchaseAndTreasury], [one configured seed][test_givenAliceConfiguredAsRecipient_whenBalanceIsFuzzed], [topology fuzz][test_givenAnyValidRouteTopology_whenReceiptsDistributed_conservesExactAmount], [Treasury boundaries][test_givenTreasuryOnly_whenReceiptBoundariesDistributed], [repurchase boundaries][test_givenRepurchaseOnly_whenBpsAndReceiptBoundariesDistributed], [single-route boundaries][test_givenOneConfiguredRecipient_whenBpsAndReceiptBoundariesDistributed], [two-route boundaries][test_givenTwoConfiguredRecipients_whenBpsAndReceiptBoundariesDistributed], [mixed boundaries][test_givenMixedRecipients_whenBpsAndReceiptBoundariesDistributed] |

## Existing debt and new receipts

| ID | Caller | Existing debt bucket mask | Configured-recipient state | Custody B | Reserved debt R | New receipts N | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| DIST-P04 | Fuzz all callers | Fuzz nonempty configured/yield/Treasury subsets | Selected or removed independently | R or R+1 | Sum of existing debt | 0 or 1 | Success; allocate only surplus; retry current destinations | Former configured recipients remain owed until explicit retry | Covered: [full matrix][test_givenAnyExistingDebtSubset_whenZeroOrOneNewReceiptDistributed_allocatesOnlySurplus] |

## Treasury changes

| ID | Caller | Treasury transition | Configured-recipient relationship | Existing debt | New receipts N | Expected result | Effects and events | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| DIST-P05 | Fuzz all callers | Upgraded before distribution | A configured recipient now equals current Treasury | Any | Positive | RevenueDistributor_InvalidRecipient(currentTreasury) | Atomic rollback even if earlier routes reserved | Covered: [first route seed][test_givenConfiguredRecipientBecomesTreasury_givenNewReceipts_reverts], [later route seed][test_givenSecondConfiguredRecipientBecomesTreasury_reverts], [full matrix][test_givenConfiguredRecipientBecomesTreasury_whenAnyCallerDistributes_revertsAtomically] |
| DIST-P07 | Fuzz all callers | Receipts arrive, then compatible upgrade | One 3,333 BPS recipient remains distinct from new Treasury | None | 10 | Success; configured share=3, new Treasury residual=7 | treasury() equals replacement; old Treasury receives zero; independent route hash/membership unchanged; pending buckets clear | Covered: [seed][test_givenBalanceReceivedBeforeTreasuryUpgrade_paysNewTreasury], [full result][test_givenReceiptsBeforeTreasuryUpgrade_whenAnyCallerDistributes_usesCurrentTreasury] |
| DIST-P06 | Fuzz all callers | Upgraded so configured recipient equals Treasury | Configured and Treasury buckets overlap | Both positive | 0 | Success; combined entitlement attempted once | No new route-validation failure; deduplicate and clear paid debts | Covered: [full matrix][test_givenConfiguredRecipientBecomesTreasury_givenNoNewReceipts_paysPendingOnce] |

[test_givenDisabled_whenManagedBalanceArrives_reverts]: ./distribute.t.sol#L409
[test_givenKernelInactive_whenManagedBalanceArrives_reverts]: ./distribute.t.sol#L427
[test_givenZeroBalance_succeedsWithoutTransfer]: ./distribute.t.sol#L512
[test_givenAliceConfiguredAsRecipient_whenBalanceIsFuzzed]: ./distribute.t.sol#L526
[test_givenAliceConfiguredAsRecipient_whenBalanceIsMaximum_preservesExactTotal]: ./distribute.t.sol#L549
[test_givenAliceConfiguredAsRecipient_whenBalanceHasRoundingDust]: ./distribute.t.sol#L362
[test_givenYieldRecipientVaultEnabled_emitsRepurchaseAndTreasury]: ./distribute.t.sol#L336
[test_givenConfiguredRecipientBecomesTreasury_givenNewReceipts_reverts]: ./distribute.t.sol#L29
[test_givenSecondConfiguredRecipientBecomesTreasury_reverts]: ./distribute.t.sol#L71
[test_givenConfiguredRecipientBecomesTreasury_givenNoNewReceipts_paysPendingOnce]: ./distribute.t.sol#L113
[test_givenRecipientTransferFails_keepsOnlyRecipientPending]: ./distribute.t.sol#L445
[test_givenTreasuryBlacklisted_retainsTreasuryShare]: ./distribute.t.sol#L480
[test_givenCallbackToken_nestedDistributionFailsAndPaysOnce]: ./distribute.t.sol#L227
[test_givenMaturedRouteChange_whenTokenCallsTimelockDuringDistribution_thenRouteStaysFixed]: ./distribute.t.sol#L175
[test_givenCallbackFailureBubbles_defersEachShare]: ./distribute.t.sol#L258
[test_givenAliceConfiguredAsRecipient_emitsEachRecipientPayout]: ./distribute.t.sol#L318
[test_givenBalanceReceivedBeforeTreasuryUpgrade_paysNewTreasury]: ./distribute.t.sol#L294
[test_givenAssetNotActive_whenDistributed_reverts]: ./distribute.t.sol#L570
[test_givenReservedDebtExceedsCustody_whenDistributed_reverts]: ./distribute.t.sol#L601
[test_givenTreasuryOnlyRoute_whenBalanceDistributed_paysExactAmount]: ./distribute.t.sol#L621
[test_givenActiveAsset_whenBalanceQueryReverts_bubblesExactError]: ./distribute.t.sol#L642
[test_givenTokenReportsTransferSuccessWithoutMovement_recordsApparentDelivery]: ./distribute.t.sol#L664
[test_givenMultipleTransfersReturnFalse_defersEveryShare]: ./distribute.t.sol#L687
[test_givenActiveAsset_whenBalanceQueryReturnsMalformedData_reverts]: ./distribute.t.sol#L715
[test_givenAnyExistingDebtSubset_whenZeroOrOneNewReceiptDistributed_allocatesOnlySurplus]: ./distribute.t.sol#L951
[test_givenAnyValidRouteTopology_whenReceiptsDistributed_conservesExactAmount]: ./distribute.t.sol#L800
[test_givenCallbackFromAnyPayoutClass_whenAnyGuardedWriteAttempted_outerDistributionPaysOnce]: ./distribute.t.sol#L1106
[test_givenConfiguredRecipientBecomesTreasury_whenAnyCallerDistributes_revertsAtomically]: ./distribute.t.sol#L1010
[test_givenOneConfiguredRecipient_whenBoundaryBalancesDistributed_conservesExactAmount]: ./distribute.t.sol#L902
[test_givenOneTransferReturnsFalse_whenAnyCallerDistributes_defersOnlySelectedClass]: ./distribute.t.sol#L894
[test_givenOneTransferReverts_whenAnyCallerDistributes_defersOnlySelectedClass]: ./distribute.t.sol#L943
[test_givenPayoutCallbackReadsPendingGetter_observesDebtBeforeDeliveryClearsIt]: ./distribute.t.sol#L1177
[test_givenPropagatedGuardFailure_whenAnyCallerDistributes_defersThenRetriesExactly]: ./distribute.t.sol#L1220
[test_givenReceiptsBeforeTreasuryUpgrade_whenAnyCallerDistributes_usesCurrentTreasury]: ./distribute.t.sol#L1061
[test_givenDisabledDistributor_whenAnyCallerDistributes_revertsAndRollsBack]: ./distribute.t.sol#L737
[test_givenInactiveDistributor_whenAnyCallerDistributes_revertsAndRollsBack]: ./distribute.t.sol#L753
[test_givenZeroBalance_whenAnyCallerDistributes_makesNoTokenCallOrEvent]: ./distribute.t.sol#L769
[test_givenTreasuryOnly_whenReceiptBoundariesDistributed]: ./distribute.t.sol#L1466
[test_givenRepurchaseOnly_whenBpsAndReceiptBoundariesDistributed]: ./distribute.t.sol#L1472
[test_givenOneConfiguredRecipient_whenBpsAndReceiptBoundariesDistributed]: ./distribute.t.sol#L1484
[test_givenTwoConfiguredRecipients_whenBpsAndReceiptBoundariesDistributed]: ./distribute.t.sol#L1496
[test_givenMixedRecipients_whenBpsAndReceiptBoundariesDistributed]: ./distribute.t.sol#L1508

## Guard-precedence regression

The following row maps the narrow competing-fault regression; it does not expand the other scenario domains.

| ID | Caller | Local active | Local enabled | Fixture and input domain | Exact result and precedence | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| DIST-L03 | Any address, fuzz, without exclusions | false | false | Distributor locally disabled, then Kernel-deactivated; Asset=`address(0)` | `RevenueDistributor_PolicyNotActive(RD)` before local enablement and asset validation | Revert; no effects of the attempted action commit. | Covered: [test][test_givenInactiveAndDisabled_whenAnyCallerDistributes_revertsActivityFirst] |

[test_givenInactiveAndDisabled_whenAnyCallerDistributes_revertsActivityFirst]: ./distribute.t.sol#L1541
