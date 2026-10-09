# rescuePendingPayout coverage plan

Rows group behavior cases. Targeted tests construct compatible state explicitly, then fuzz the operation input. Covered means the planned domain and shared assertions are implemented. A partial row must name its missing combinations or assertions. Lifecycle columns refer only to BurnerLoans.

Links distinguish fuzzed inputs/callers, explicit identity/layout checks and exact boundary checks. Short scope comments beside each test describe its varied states and inputs; this document records expected behavior. The [pending-payout fixture](./fixtures/BurnerLoansRescuePendingTest.sol) records exact debts and checks independent accounting, native event expectations, indexes and rollback.

BL accepts its bound Configurator or current admin. Admin can recover directly from locally disabled BL even when BLC/BLCT is disabled or Kernel-inactive. BL itself must remain Kernel-active.

## Domains and notation

- Caller: Configurator = currently bound Config contract; Admin = ADMIN_ROLE holder. Unauthorized callers exclude both classes; seed emergency-only, delegated operator, recipient and address(0).
- K = original keeper; F = current fee recipient; T = cached Treasury; O = an unrelated nonzero recipient with no reward. Construct each layout below using fixed role addresses. Identity overlap is explicit, not left to random addresses.

| Layout | Role identities |
| --- | --- |
| All distinct (D) | K, F, T distinct |
| Keeper = fee recipient (KF) | K = F ≠ T |
| Keeper = Treasury (KT) | K = T ≠ F |
| Fee recipient = Treasury (FT) | F = T ≠ K |
| Keeper = fee recipient = Treasury (KFT) | K = F = T |

- Identity/presence domain: all five layouts and all eight combinations of globally populated buckets (reward bit = 1, fee = 2, seizure = 4; 0 = empty, 3 = reward + fee, 7 = all). Allocation tests enumerate only compatible layouts and optional buckets; invalid-input tests exercise each role recipient and O. Real Treasury/distributor identities and a fixed keeper are reused; only transfer/destination-isolation tests fuzz destination addresses; authorization tests fuzz unauthorized callers. Seeds guarantee the discrete cases.
- Ordinary quantities: reward bucket = 10, fee bucket = 20, seizure bucket = 30 base units; absent buckets = 0. These are global recorded debts, not necessarily eligible for the selected recipient. Numeric and isolation tests separately vary solvent debts up to MAX, including E = 0, 1, MAX−1, MAX. Unrelated obligations and surplus never enlarge E.
- reward, fee, seizure = amounts owed to the selected recipient: their keeper reward; fees only when recipient = F; seizure only when recipient = T. E = reward + fee + seizure = pendingPayout(token, recipient).
- amount = amount_ in token base units; MAX = type(uint256).max. Ranges min..max include both endpoints. Test min, max−1 when in range, and max, plus fuzz min..max. Include MAX when in range.
- Default execution: Configurator caller, policy active, facility enabled. Allocation and callbacks additionally exercise disabled state; the L-table proves caller/policy/local-state combinations independently. Addresses are valid; destinations exclude zero, facility, token, Configurator and Kernel unless overridden. Token has exact-transfer semantics; preview callers are unrestricted.
- Unchanged = buckets, aggregate, balances, indexes and configuration unchanged; no committed rescue events.

Errors omit the `BurnerLoans_` prefix but retain exact arguments. Reward(x), Fee(x), Seizure(x) name the corresponding PendingSeizureRewardRescued, PendingFeeRescued and PendingSeizureRescued events.

## Shared assertions

Success: preview returns E; independent reward → fee → seizure allocation matches each authoritative debit. Aggregate/custody decrease by amount; destination balance increases by amount. Ineligible buckets, other keepers and other tokens stay unchanged. Check event emitter/arguments/order/count; omit zero-debit events. Raw keeper membership follows reward debt alone, even when fee/seizure debt keeps the address in the public recipient union; recipient sets reflect remaining current-role liabilities without duplicates; tokens disappear only when aggregate pending is zero, even with surplus remaining. Compare getters before/after and repeat previews using remaining E; a positive request after full drain must report insufficient entitlement. Amounts are base units; token decimals do not affect allocation.

Revert: match exact error data and Unchanged effects, including rollback of token/callback changes. Preview checks Kernel activity and omits caller and transfer checks. Zero amount reverts with ZeroAmount(); it does not return zero.

Check previews alongside execution: successful rescues use Alice; rejection cases use the execution caller. Authorization rows fuzz callers outside Configurator/Admin (including explicit zero/emergency/operator/recipient checks), proving previews remain permissionless without a separate caller input. Reads preserve state/logs. Compare successful previews with the entitlement getter, and input failures with execution when authorization/policy permit it. Transfer/callback failures do not imply preview failure.

Error check order means supplying multiple faults and asserting the first applicable error. Include simultaneous faults in the existing generators. Preview starts at policy activity and follows the same input order. Execution check order: reentrancy guard → caller → policy active → zero/no-code token → zero/forbidden destination → zero recipient → zero amount → amount exceeds E → transfer. Assert the earliest error, including unauthorized/inactive calls with invalid inputs; callback rows cover an entered guard. I-04 is also enforced by the shared production validator for surplus rescue; its tests stay in `rescue.t.sol`.

## Authorization and facility lifecycle

Lifecycle proofs use a fixed E=60, amount=1 request and each input fault, including simultaneous faults. The I-table owns complete invalid-input domains. Active preview follows input checks (E or input error); inactive preview rejects before inputs. Unauthorized seeds belong in the fuzz row.

| ID | Caller | Local | Policy | Preview | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| L-01 | Configurator | Enabled | Active | E=60; valid amount=1 | Success | Reward −1; transfer 1 | Covered: [Configurator success][test_authorization_givenEnabled_givenPolicyActive_whenCallerIsConfigurator] |
| L-26 | Configurator | Enabled | Active | Invalid input | Same input error as preview | Unchanged | Covered: [Configurator input errors][test_authorization_givenEnabled_givenPolicyActive_whenCallerIsConfigurator_whenInputsInvalid_reverts] |
| L-02 | Any outside Configurator/Admin (fuzz) | Enabled | Active | Input checks | NotAuthorised() | Unchanged | Covered: [fuzzed callers][test_authorization_givenEnabled_givenPolicyActive_whenCallerIsUnauthorized_reverts], [caller identities][test_authorization_whenUnauthorizedIdentitiesAreSeeded] |
| L-07 | Configurator | Disabled | Active | E=60; valid amount=1 | Success | Reward −1; transfer 1 | Covered: [Configurator success][test_authorization_givenDisabled_givenPolicyActive_whenCallerIsConfigurator] |
| L-27 | Configurator | Disabled | Active | Invalid input | Same input error as preview | Unchanged | Covered: [Configurator input errors][test_authorization_givenDisabled_givenPolicyActive_whenCallerIsConfigurator_whenInputsInvalid_reverts] |
| L-08 | Any outside Configurator/Admin (fuzz) | Disabled | Active | Input checks | NotAuthorised() | Unchanged | Covered: [fuzzed callers][test_authorization_givenDisabled_givenPolicyActive_whenCallerIsUnauthorized_reverts], [caller identities][test_authorization_whenUnauthorizedIdentitiesAreSeeded] |
| L-13 | Configurator | Enabled | Inactive | PolicyInactive() | PolicyInactive() | Unchanged | Covered: [Configurator rejection][test_authorization_givenEnabled_givenPolicyInactive_whenCallerIsConfigurator_reverts] |
| L-14 | Any outside Configurator/Admin (fuzz) | Enabled | Inactive | PolicyInactive() | NotAuthorised() | Unchanged | Covered: [fuzzed callers][test_authorization_givenEnabled_givenPolicyInactive_whenCallerIsUnauthorized_reverts], [caller identities][test_authorization_whenUnauthorizedIdentitiesAreSeeded] |
| L-19 | Configurator | Disabled | Inactive | PolicyInactive() | PolicyInactive() | Unchanged | Covered: [Configurator rejection][test_authorization_givenDisabled_givenPolicyInactive_whenCallerIsConfigurator_reverts] |
| L-20 | Any outside Configurator/Admin (fuzz) | Disabled | Inactive | PolicyInactive() | NotAuthorised() | Unchanged | Covered: [fuzzed callers][test_authorization_givenDisabled_givenPolicyInactive_whenCallerIsUnauthorized_reverts], [caller identities][test_authorization_whenUnauthorizedIdentitiesAreSeeded] |
| L-21 | Admin | Enabled | Active | E=60; valid amount=1 | Success | Reward −1; transfer 1 | Covered: [admin success][test_authorization_givenActiveFacility_whenAdminCallsDirectly] |
| L-28 | Admin | Enabled | Active | Invalid input | Same input error as preview | Unchanged | Covered: [admin input errors][test_authorization_givenActiveFacility_whenAdminCallsDirectly_whenInputsInvalid_reverts] |
| L-22 | Admin | Disabled | Active | E=60; valid amount=1 | Success | Reward −1; transfer 1 | Covered: [admin success][test_authorization_givenActiveFacility_whenAdminCallsDirectly] |
| L-29 | Admin | Disabled | Active | Invalid input | Same input error as preview | Unchanged | Covered: [admin input errors][test_authorization_givenActiveFacility_whenAdminCallsDirectly_whenInputsInvalid_reverts] |
| L-23 | Admin | Enabled | Inactive | PolicyInactive() | PolicyInactive() | Unchanged | Covered: [admin rejection][test_authorization_givenInactiveFacility_whenAdminCallsDirectly_reverts] |
| L-24 | Admin | Disabled | Inactive | PolicyInactive() | PolicyInactive() | Unchanged | Covered: [admin rejection][test_authorization_givenInactiveFacility_whenAdminCallsDirectly_reverts] |
| L-25 | Current granted admin | Enabled | Active | E=60; valid amount=1 | Success | Reward −1; transfer 1 | Covered: [admin success][test_authorization_givenAdminRoleGranted_whenNewAdminCalls] |
| L-30 | Caller before admin grant / after revoke | Enabled | Active | E=60; valid amount=1 | NotAuthorised() | Unchanged | Covered: [admin rejection][test_authorization_givenAdminRoleNotGranted_whenCallerRescues_reverts], [admin rejection][test_authorization_givenAdminRoleRevoked_whenFormerAdminRescues_reverts] |
| A-01 | Admin | Enabled/disabled | Active; BLC/BLCT independently disabled and active/inactive | E=10 | Pay reward 4 directly; BLC/BLCT not called or enabled | Shared assertions; no queued action | Covered: [admin rescues directly][test_givenConfigAndTimelockUnavailable_whenAdminRescuesDirectly] |

## Invalid inputs

Each named boundary test fixes one input error and one role layout: distinct roles (D), keeper = fee recipient (KF), keeper = Treasury (KT), fee recipient = Treasury (FT), or keeper = fee recipient = Treasury (KFT). Its focused helper seeds bucket subsets, local states, recipients and amount boundaries; it does not select a layout or error.

Each row uses the complete layout domain above, including empty/populated buckets and unrelated recipients. Other addresses are valid; destination is Alice except in the explicit invalid-destination rows. Fuzz amounts across 0..MAX with exact 0, 1 and MAX, except where the row fixes/restricts amount. Every rejection is Unchanged. I-06 also seeds other keeper/token liabilities and surplus, proving those never add to E.

| ID | Caller | Input / fuzz constraint | Preview | Execution | Test |
| --- | --- | --- | --- | --- | --- |
| I-01 | Configurator | token = 0 or nonzero address without code | InvalidAsset(token) | InvalidAsset(token) | Covered: [fuzz][test_invalidInputs_whenTokenIsZero_reverts], [fuzz][test_invalidInputs_whenTokenHasNoCode_reverts], [zero token: distinct roles (D)][test_invalidInputs_givenDistinct_whenTokenIsZero_whenDomainBoundariesAreSeeded_reverts], [zero token: keeper = fee (KF)][test_invalidInputs_givenKeeperIsFeeRecipient_whenTokenIsZero_whenDomainBoundariesAreSeeded_reverts], [zero token: keeper = Treasury (KT)][test_invalidInputs_givenKeeperIsTreasury_whenTokenIsZero_whenDomainBoundariesAreSeeded_reverts], [zero token: fee = Treasury (FT)][test_invalidInputs_givenFeeRecipientIsTreasury_whenTokenIsZero_whenDomainBoundariesAreSeeded_reverts], [zero token: all roles overlap (KFT)][test_invalidInputs_givenAllRolesOverlap_whenTokenIsZero_whenDomainBoundariesAreSeeded_reverts], [no code: distinct roles (D)][test_invalidInputs_givenDistinct_whenTokenHasNoCode_whenDomainBoundariesAreSeeded_reverts], [no code: keeper = fee (KF)][test_invalidInputs_givenKeeperIsFeeRecipient_whenTokenHasNoCode_whenDomainBoundariesAreSeeded_reverts], [no code: keeper = Treasury (KT)][test_invalidInputs_givenKeeperIsTreasury_whenTokenHasNoCode_whenDomainBoundariesAreSeeded_reverts], [no code: fee = Treasury (FT)][test_invalidInputs_givenFeeRecipientIsTreasury_whenTokenHasNoCode_whenDomainBoundariesAreSeeded_reverts], [no code: all roles overlap (KFT)][test_invalidInputs_givenAllRolesOverlap_whenTokenHasNoCode_whenDomainBoundariesAreSeeded_reverts], [faults compete][test_invalidInputs_whenFaultsCompete_reverts] |
| I-02 | Configurator | recipient = 0 | ZeroAddress() | ZeroAddress() | Covered: [fuzz][test_invalidInputs_whenRecipientIsZero_reverts], [distinct roles (D)][test_invalidInputs_givenDistinct_whenRecipientIsZero_whenDomainBoundariesAreSeeded_reverts], [keeper = fee (KF)][test_invalidInputs_givenKeeperIsFeeRecipient_whenRecipientIsZero_whenDomainBoundariesAreSeeded_reverts], [keeper = Treasury (KT)][test_invalidInputs_givenKeeperIsTreasury_whenRecipientIsZero_whenDomainBoundariesAreSeeded_reverts], [fee = Treasury (FT)][test_invalidInputs_givenFeeRecipientIsTreasury_whenRecipientIsZero_whenDomainBoundariesAreSeeded_reverts], [all roles overlap (KFT)][test_invalidInputs_givenAllRolesOverlap_whenRecipientIsZero_whenDomainBoundariesAreSeeded_reverts], [faults compete][test_invalidInputs_whenFaultsCompete_reverts] |
| I-03 | Configurator | destination = 0 | InvalidRescueDestination(0) | InvalidRescueDestination(0) | Covered: [fuzz][test_invalidInputs_whenDestinationIsZero_reverts], [distinct roles (D)][test_invalidInputs_givenDistinct_whenDestinationIsZero_whenDomainBoundariesAreSeeded_reverts], [keeper = fee (KF)][test_invalidInputs_givenKeeperIsFeeRecipient_whenDestinationIsZero_whenDomainBoundariesAreSeeded_reverts], [keeper = Treasury (KT)][test_invalidInputs_givenKeeperIsTreasury_whenDestinationIsZero_whenDomainBoundariesAreSeeded_reverts], [fee = Treasury (FT)][test_invalidInputs_givenFeeRecipientIsTreasury_whenDestinationIsZero_whenDomainBoundariesAreSeeded_reverts], [all roles overlap (KFT)][test_invalidInputs_givenAllRolesOverlap_whenDestinationIsZero_whenDomainBoundariesAreSeeded_reverts], [faults compete][test_invalidInputs_whenFaultsCompete_reverts] |
| I-04 | Configurator | Destination enum: facility, token contract, current Configurator, Kernel; vary amount independently and guarantee each at 0/1/MAX | InvalidRescueDestination(destination) | Same error | Covered: [fuzz][test_invalidInputs_whenDestinationIsForbidden_reverts], [distinct roles (D)][test_invalidInputs_givenDistinct_whenDestinationIsForbidden_whenDomainBoundariesAreSeeded_reverts], [keeper = fee (KF)][test_invalidInputs_givenKeeperIsFeeRecipient_whenDestinationIsForbidden_whenDomainBoundariesAreSeeded_reverts], [keeper = Treasury (KT)][test_invalidInputs_givenKeeperIsTreasury_whenDestinationIsForbidden_whenDomainBoundariesAreSeeded_reverts], [fee = Treasury (FT)][test_invalidInputs_givenFeeRecipientIsTreasury_whenDestinationIsForbidden_whenDomainBoundariesAreSeeded_reverts], [all roles overlap (KFT)][test_invalidInputs_givenAllRolesOverlap_whenDestinationIsForbidden_whenDomainBoundariesAreSeeded_reverts], [faults compete][test_invalidInputs_whenFaultsCompete_reverts] |
| I-05 | Configurator | amount = 0 | ZeroAmount() | ZeroAmount() | Covered: [fuzz][test_invalidInputs_whenAmountIsZero_reverts], [distinct roles (D)][test_invalidInputs_givenDistinct_whenAmountIsZero_whenDomainBoundariesAreSeeded_reverts], [keeper = fee (KF)][test_invalidInputs_givenKeeperIsFeeRecipient_whenAmountIsZero_whenDomainBoundariesAreSeeded_reverts], [keeper = Treasury (KT)][test_invalidInputs_givenKeeperIsTreasury_whenAmountIsZero_whenDomainBoundariesAreSeeded_reverts], [fee = Treasury (FT)][test_invalidInputs_givenFeeRecipientIsTreasury_whenAmountIsZero_whenDomainBoundariesAreSeeded_reverts], [all roles overlap (KFT)][test_invalidInputs_givenAllRolesOverlap_whenAmountIsZero_whenDomainBoundariesAreSeeded_reverts], [faults compete][test_invalidInputs_whenFaultsCompete_reverts] |
| I-06 | Configurator | Fuzz amount: E+1..MAX, with E < MAX | InsufficientPendingPayout(token, amount, E) | Same error | Covered: [fuzz][test_invalidInputs_whenAmountExceedsEntitlement_reverts], [distinct roles (D)][test_invalidInputs_givenDistinct_whenAmountExceedsEntitlement_whenDomainBoundariesAreSeeded_reverts], [keeper = fee (KF)][test_invalidInputs_givenKeeperIsFeeRecipient_whenAmountExceedsEntitlement_whenDomainBoundariesAreSeeded_reverts], [keeper = Treasury (KT)][test_invalidInputs_givenKeeperIsTreasury_whenAmountExceedsEntitlement_whenDomainBoundariesAreSeeded_reverts], [fee = Treasury (FT)][test_invalidInputs_givenFeeRecipientIsTreasury_whenAmountExceedsEntitlement_whenDomainBoundariesAreSeeded_reverts], [all roles overlap (KFT)][test_invalidInputs_givenAllRolesOverlap_whenAmountExceedsEntitlement_whenDomainBoundariesAreSeeded_reverts], [amount exceeds entitlement][test_numericExtremes_givenSingleBucket_whenAmountExceedsEntitlement_reverts], [fuzz][test_keeperIsolation_givenThreeKeepers_whenEachIsSelected], [boundaries][test_keeperIsolation_givenDistinct_whenMaskAndMaximumBoundariesAreSeeded], [boundaries][test_keeperIsolation_givenKeeperIsFeeRecipient_whenMaskAndMaximumBoundariesAreSeeded], [boundaries][test_keeperIsolation_givenKeeperIsTreasury_whenMaskAndMaximumBoundariesAreSeeded], [boundaries][test_keeperIsolation_givenFeeRecipientIsTreasury_whenMaskAndMaximumBoundariesAreSeeded], [boundaries][test_keeperIsolation_givenAllRolesOverlap_whenMaskAndMaximumBoundariesAreSeeded], [fuzz][test_tokenIsolation_givenTwoTokens_whenOneIsRescued], [boundaries][test_surplusIsolation_givenDistinct_whenMasksAndCustodyBoundariesAreSeeded], [boundaries][test_surplusIsolation_givenKeeperIsFeeRecipient_whenMasksAndCustodyBoundariesAreSeeded], [boundaries][test_surplusIsolation_givenKeeperIsTreasury_whenMasksAndCustodyBoundariesAreSeeded], [boundaries][test_surplusIsolation_givenFeeRecipientIsTreasury_whenMasksAndCustodyBoundariesAreSeeded], [boundaries][test_surplusIsolation_givenAllRolesOverlap_whenMasksAndCustodyBoundariesAreSeeded], [boundaries][test_tokenIsolation_whenEmptyPopulatedAndDrainBoundariesAreSeeded] |

## Payout allocation

E is the selected recipient’s total eligible pending payout: reward + fee + seizure. Use the fixed 10/20/30 debts. Each P-row has its own test, enumerating compatible role layouts and optional globally owed buckets, then fuzzing its amount interval and local enabled/disabled state. Destination is Alice; TX-05 covers destination variation separately. Each boundary driver also guarantees enabled/disabled cases. Preview = E; execution succeeds; unrelated buckets stay unchanged. Numerical variation is tested separately in N-02.

| ID | Caller | Eligible bucket condition | Amount range (inclusive) | Bucket effects | Events | Test |
| --- | --- | --- | --- | --- | --- | --- |
| P-01 | Configurator | reward > 0; fee/seizure arbitrary | `1..reward` | Reward −amount | Reward(amount) | Covered: [fuzz][test_payoutAllocation_givenReward_whenAmountIsWithinItsInterval], [boundaries][test_payoutAllocation_givenReward_whenBoundariesAreSeeded], [amount equals keeper reward][test_payoutAllocation_givenKeeperFeeAndTreasuryOverlap_whenAmountEqualsKeeperReward], [fuzz][test_numericExtremes_givenVariableSolventBuckets_whenAmountIsWithinEntitlement] |
| P-02 | Configurator | reward=0; fee>0; seizure arbitrary | `1..fee` | Fee −amount | Fee(amount) | Covered: [fuzz][test_payoutAllocation_givenFee_whenAmountIsWithinItsInterval], [boundaries][test_payoutAllocation_givenFee_whenBoundariesAreSeeded] |
| P-03 | Configurator | reward=fee=0; seizure>0 | `1..seizure` | Seizure −amount | Seizure(amount) | Covered: [fuzz][test_payoutAllocation_givenSeizure_whenAmountIsWithinItsInterval], [boundaries][test_payoutAllocation_givenSeizure_whenBoundariesAreSeeded] |
| P-04 | Configurator | reward>0; fee>0; seizure arbitrary | `reward+1..reward+fee` | Reward cleared; fee −(amount−reward) | Reward(reward) → Fee(amount−reward) | Covered: [fuzz][test_payoutAllocation_givenRewardAndFee_whenAmountIsWithinItsInterval], [boundaries][test_payoutAllocation_givenRewardAndFee_whenBoundariesAreSeeded], [amount equals reward and fee][test_payoutAllocation_givenKeeperFeeAndTreasuryOverlap_whenAmountEqualsRewardAndFee], [fuzz][test_numericExtremes_givenVariableSolventBuckets_whenAmountIsWithinEntitlement] |
| P-05 | Configurator | reward>0; fee=0; seizure>0 | `reward+1..reward+seizure` | Reward cleared; seizure −(amount−reward) | Reward(reward) → Seizure(amount−reward) | Covered: [fuzz][test_payoutAllocation_givenRewardAndSeizure_whenAmountIsWithinItsInterval], [boundaries][test_payoutAllocation_givenRewardAndSeizure_whenBoundariesAreSeeded] |
| P-06 | Configurator | reward=0; fee>0; seizure>0 | `fee+1..fee+seizure` | Fee cleared; seizure −(amount−fee) | Fee(fee) → Seizure(amount−fee) | Covered: [fuzz][test_payoutAllocation_givenFeeAndSeizure_whenAmountIsWithinItsInterval], [boundaries][test_payoutAllocation_givenFeeAndSeizure_whenBoundariesAreSeeded] |
| P-07 | Configurator | reward>0; fee>0; seizure>0 | `reward+fee+1..E` | Reward/fee cleared; seizure −(amount−reward−fee) | Reward(reward) → Fee(fee) → Seizure(amount−reward−fee) | Covered: [fuzz][test_payoutAllocation_givenRewardFeeAndSeizure_whenAmountIsWithinItsInterval], [boundaries][test_payoutAllocation_givenRewardFeeAndSeizure_whenBoundariesAreSeeded], [fuzz][test_numericExtremes_givenVariableSolventBuckets_whenAmountIsWithinEntitlement] |

## Numeric extremes

Numeric generators are confined to these tests and variable-debt isolation tests. Exact quantities are passed to setup. N-01 guarantees valid MAX entitlements; boundary seeds guarantee insufficient MAX requests where E < MAX.

| ID | Caller | Input / state | Preview | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- |
| N-01 | Configurator | amount=MAX; E=MAX; fuzz eligible splits | MAX | Success; full allocation and index removal | Covered: [fuzz][test_numericExtremes_givenMaxEntitlement_whenFullDebtIsRescued], [exact entitlement is rescued][test_numericExtremes_givenSingleBucket_whenExactEntitlementIsRescued], [fixed fixtures][test_numericExtremes_givenMaxEntitlement_whenBucketSubsetsAreSeeded] |
| N-02 | Configurator | Keeper = fee recipient = Treasury (KFT); positive variable reward/fee/seizure; total ≤ MAX; amount fuzzed 1..E | E | Explicit numerical interval allocation; seeds 1/1/1 and MAX−2/1/1 | Covered: [boundaries][test_numericExtremes_givenMixedBuckets_whenValidAmountBoundariesAreSeeded], [fuzz][test_numericExtremes_givenVariableSolventBuckets_whenAmountIsWithinEntitlement] |

## Transfers and destinations

Allocation tests cover standard transfers for every compatible layout. TX-03 additionally seeds all valid layout/mask/recipient combinations; TX-01 nonzero balances and TX-04 zero custody use keeper = fee recipient = Treasury (KFT) with amount 1..60. Preview returns E; transfer errors occur only during execution. Every failed execution preserves the pre-call snapshot, including a deliberately insolvent ledger in TX-04.

| ID | Caller | Transfer / destination condition | Execution | Effects / events | Test |
| --- | --- | --- | --- | --- | --- |
| TX-01 | Configurator | Standard ERC-20 transfer returns true; seed zero/nonzero destination balance | Success | Allocation events; one transfer of amount | Covered: [fuzz][test_payoutAllocation_givenReward_whenAmountIsWithinItsInterval], [boundaries][test_payoutAllocation_givenReward_whenBoundariesAreSeeded], [fuzz][test_payoutAllocation_givenFee_whenAmountIsWithinItsInterval], [boundaries][test_payoutAllocation_givenFee_whenBoundariesAreSeeded], [fuzz][test_payoutAllocation_givenSeizure_whenAmountIsWithinItsInterval], [boundaries][test_payoutAllocation_givenSeizure_whenBoundariesAreSeeded], [fuzz][test_payoutAllocation_givenRewardAndFee_whenAmountIsWithinItsInterval], [boundaries][test_payoutAllocation_givenRewardAndFee_whenBoundariesAreSeeded], [fuzz][test_payoutAllocation_givenRewardAndSeizure_whenAmountIsWithinItsInterval], [boundaries][test_payoutAllocation_givenRewardAndSeizure_whenBoundariesAreSeeded], [fuzz][test_payoutAllocation_givenFeeAndSeizure_whenAmountIsWithinItsInterval], [boundaries][test_payoutAllocation_givenFeeAndSeizure_whenBoundariesAreSeeded], [fuzz][test_payoutAllocation_givenRewardFeeAndSeizure_whenAmountIsWithinItsInterval], [boundaries][test_payoutAllocation_givenRewardFeeAndSeizure_whenBoundariesAreSeeded], [fuzz][test_transfers_givenExistingDestinationBalance_whenAmountIsRescued], [boundaries][test_transfers_givenExistingDestinationBalance_whenAmountBoundariesAreSeeded] |
| TX-03 | Configurator | Mock token blocks transfers to this otherwise valid destination | TransferBlocked(destination) | Unchanged; match the mock's exact error | Covered: [fuzz][test_transfers_givenBlockedDestination_whenAmountIsRescued_reverts], [boundaries][test_transfers_givenBlockedDestination_whenRecipientAndAmountBoundariesAreSeeded_reverts] |
| TX-04 | Configurator | Record valid pending debt, then burn all facility custody; request a valid positive amount | ERC20InsufficientBalance(facility, 0, amount) | Unchanged; debt remains outstanding and custody stays zero | Covered: [fuzz][test_transfers_givenDebtWithoutCustody_whenAmountIsRescued_reverts], [boundaries][test_transfers_givenDebtWithoutCustody_whenAmountBoundariesAreSeeded_reverts] |
| TX-05 | Configurator | Fuzz any permitted destination; seed selected recipient, unrelated address and another recipient with pending debt | Success | Only selected recipient’s eligible buckets debit; destination receives amount | Covered: [fuzz][test_transfers_givenExistingDestinationBalance_whenAmountIsRescued], [boundaries][test_transfers_givenExistingDestinationBalance_whenAmountBoundariesAreSeeded], [fuzz][test_keeperIsolation_givenThreeKeepers_whenEachIsSelected], [boundaries][test_keeperIsolation_givenDistinct_whenMaskAndMaximumBoundariesAreSeeded], [boundaries][test_keeperIsolation_givenKeeperIsFeeRecipient_whenMaskAndMaximumBoundariesAreSeeded], [boundaries][test_keeperIsolation_givenKeeperIsTreasury_whenMaskAndMaximumBoundariesAreSeeded], [boundaries][test_keeperIsolation_givenFeeRecipientIsTreasury_whenMaskAndMaximumBoundariesAreSeeded], [boundaries][test_keeperIsolation_givenAllRolesOverlap_whenMaskAndMaximumBoundariesAreSeeded] |

## Token callbacks

Explicit layouts: [All distinct (D)][test_callbacks_givenDistinct_whenCaughtCasesAreSeeded], [Keeper = fee recipient (KF)][test_callbacks_givenKeeperIsFeeRecipient_whenCaughtCasesAreSeeded], [Keeper = Treasury (KT)][test_callbacks_givenKeeperIsTreasury_whenCaughtCasesAreSeeded], [Fee recipient = Treasury (FT)][test_callbacks_givenFeeRecipientIsTreasury_whenCaughtCasesAreSeeded], [Keeper = fee recipient = Treasury (KFT)][test_callbacks_givenAllRolesOverlap_whenCaughtCasesAreSeeded].

Guarantee nested surplus rescue, pending rescue, setPriceCacheMaxAge and ordinary retry. Pending rescue/retry independently select K/F/T or O as the nested recipient; K/F/T are seeded for both outer and nested identities. Authorize the token through the real Config so guarded actions reach the facility guard. Fuzz bucket masks and valid/invalid nested inputs; enumerate nested K/F/T/O for valid pending-rescue/retry inputs. Zeroed inputs and actions without a recipient are checked once per outcome. Each layout driver seeds all buckets, enabled/disabled, amount 1/full entitlement, every action and caught/propagated outcomes; read callbacks seed partial/full rescues. The read fuzz test checks both a partial and full rescue from the same fixture.

| ID | Caller | Callback outcome | Outer execution | Effects / events | Test |
| --- | --- | --- | --- | --- | --- |
| CB-01 | Configurator | Token records and catches the nested guard error | Success | One outer allocation/payment; no nested or configuration changes | Covered: [caught fuzz][test_callbacks_whenNestedWriteFailureIsCaught], [distinct: caught seeds][test_callbacks_givenDistinct_whenCaughtCasesAreSeeded], [keeper is fee recipient: caught seeds][test_callbacks_givenKeeperIsFeeRecipient_whenCaughtCasesAreSeeded], [keeper is treasury: caught seeds][test_callbacks_givenKeeperIsTreasury_whenCaughtCasesAreSeeded], [fee recipient is treasury: caught seeds][test_callbacks_givenFeeRecipientIsTreasury_whenCaughtCasesAreSeeded], [all roles overlap: caught seeds][test_callbacks_givenAllRolesOverlap_whenCaughtCasesAreSeeded] |
| CB-02 | Configurator | Token wraps the nested failure in CallbackFailed() and reverts | CallbackFailed() | Unchanged, including callback and token state | Covered: [propagated fuzz][test_callbacks_whenNestedWriteFailureIsPropagated], [distinct: propagated seeds][test_callbacks_givenDistinct_whenPropagatedCasesAreSeeded], [keeper is fee recipient: propagated seeds][test_callbacks_givenKeeperIsFeeRecipient_whenPropagatedCasesAreSeeded], [keeper is treasury: propagated seeds][test_callbacks_givenKeeperIsTreasury_whenPropagatedCasesAreSeeded], [fee recipient is treasury: propagated seeds][test_callbacks_givenFeeRecipientIsTreasury_whenPropagatedCasesAreSeeded], [all roles overlap: propagated seeds][test_callbacks_givenAllRolesOverlap_whenPropagatedCasesAreSeeded] |
| CB-03 | Configurator | Mock calls getters/previews after its balance transfer; partial rescue (`amount < E`) | Success | Reads see remaining entitlement E−amount and updated buckets/indexes/custody | Covered: [distinct: partial reads seeds][test_callbacks_givenDistinct_whenPartialReadCasesAreSeeded], [keeper is fee recipient: partial reads seeds][test_callbacks_givenKeeperIsFeeRecipient_whenPartialReadCasesAreSeeded], [keeper is treasury: partial reads seeds][test_callbacks_givenKeeperIsTreasury_whenPartialReadCasesAreSeeded], [fee recipient is treasury: partial reads seeds][test_callbacks_givenFeeRecipientIsTreasury_whenPartialReadCasesAreSeeded], [all roles overlap: partial reads seeds][test_callbacks_givenAllRolesOverlap_whenPartialReadCasesAreSeeded], [partial reads fuzz][test_callbacks_whenReadsObservePartialRescue] |
| CB-04 | Configurator | Same read callback after full drain (`amount = E`); catch the preview error | Success | Getter returns 0; preview requesting 1 reverts with InsufficientPendingPayout(token, 1, 0) | Covered: [distinct: full reads seeds][test_callbacks_givenDistinct_whenFullReadCasesAreSeeded], [keeper is fee recipient: full reads seeds][test_callbacks_givenKeeperIsFeeRecipient_whenFullReadCasesAreSeeded], [keeper is treasury: full reads seeds][test_callbacks_givenKeeperIsTreasury_whenFullReadCasesAreSeeded], [fee recipient is treasury: full reads seeds][test_callbacks_givenFeeRecipientIsTreasury_whenFullReadCasesAreSeeded], [all roles overlap: full reads seeds][test_callbacks_givenAllRolesOverlap_whenFullReadCasesAreSeeded], [full reads fuzz][test_callbacks_whenReadsObserveFullRescue] |

## Keeper, token and surplus isolation

Apply all compatible role layouts. Other obligations do not add to E. Keeper explicit checks: [All distinct (D)][test_keeperIsolation_givenDistinct_whenMaskAndMaximumBoundariesAreSeeded], [Keeper = fee recipient (KF)][test_keeperIsolation_givenKeeperIsFeeRecipient_whenMaskAndMaximumBoundariesAreSeeded], [Keeper = Treasury (KT)][test_keeperIsolation_givenKeeperIsTreasury_whenMaskAndMaximumBoundariesAreSeeded], [Fee recipient = Treasury (FT)][test_keeperIsolation_givenFeeRecipientIsTreasury_whenMaskAndMaximumBoundariesAreSeeded], [Keeper = fee recipient = Treasury (KFT)][test_keeperIsolation_givenAllRolesOverlap_whenMaskAndMaximumBoundariesAreSeeded]. Surplus explicit checks: [All distinct (D)][test_surplusIsolation_givenDistinct_whenMasksAndCustodyBoundariesAreSeeded], [Keeper = fee recipient (KF)][test_surplusIsolation_givenKeeperIsFeeRecipient_whenMasksAndCustodyBoundariesAreSeeded], [Keeper = Treasury (KT)][test_surplusIsolation_givenKeeperIsTreasury_whenMasksAndCustodyBoundariesAreSeeded], [Fee recipient = Treasury (FT)][test_surplusIsolation_givenFeeRecipientIsTreasury_whenMasksAndCustodyBoundariesAreSeeded], [Keeper = fee recipient = Treasury (KFT)][test_surplusIsolation_givenAllRolesOverlap_whenMasksAndCustodyBoundariesAreSeeded].

| ID | Caller | Fuzz domain / guaranteed seeds | Amount | Required effects | Test |
| --- | --- | --- | --- | --- | --- |
| ISO-01 | Configurator | 3 distinct keepers; reward > 0, fee/seizure optional; all solvent amounts; select each; keeper may equal F/T | Exact 1,E; fuzz 1..E | Only selected keeper’s eligible buckets debit; other two rewards/indexes unchanged | Covered: [fuzz][test_keeperIsolation_givenThreeKeepers_whenEachIsSelected], [boundaries][test_keeperIsolation_givenDistinct_whenMaskAndMaximumBoundariesAreSeeded], [boundaries][test_keeperIsolation_givenKeeperIsFeeRecipient_whenMaskAndMaximumBoundariesAreSeeded], [boundaries][test_keeperIsolation_givenKeeperIsTreasury_whenMaskAndMaximumBoundariesAreSeeded], [boundaries][test_keeperIsolation_givenFeeRecipientIsTreasury_whenMaskAndMaximumBoundariesAreSeeded], [boundaries][test_keeperIsolation_givenAllRolesOverlap_whenMaskAndMaximumBoundariesAreSeeded] |
| ISO-02 | Configurator | Token A/B; seed B empty/nonempty; overlapping recipient identities across tokens | Partial/full A rescue | B ledger, balances and indexes unchanged; no cross-token entitlement | Covered: [fuzz][test_tokenIsolation_givenTwoTokens_whenOneIsRescued], [boundaries][test_tokenIsolation_whenEmptyPopulatedAndDrainBoundariesAreSeeded] |
| ISO-04 | Configurator | One identity owns all remaining buckets; all compatible layouts/masks; surplus 0/nonzero; seed debt MAX,MAX−1,MAX−5 and surplus 0,1,5 within custody limit | E | Pending token removed even with surplus; unrelated tokens remain | Covered: [fuzz][test_surplusIsolation_givenOneDebtOwner_whenTokenIsFullyDrained], [boundaries][test_surplusIsolation_givenDistinct_whenMasksAndCustodyBoundariesAreSeeded], [boundaries][test_surplusIsolation_givenKeeperIsFeeRecipient_whenMasksAndCustodyBoundariesAreSeeded], [boundaries][test_surplusIsolation_givenKeeperIsTreasury_whenMasksAndCustodyBoundariesAreSeeded], [boundaries][test_surplusIsolation_givenFeeRecipientIsTreasury_whenMasksAndCustodyBoundariesAreSeeded], [boundaries][test_surplusIsolation_givenAllRolesOverlap_whenMasksAndCustodyBoundariesAreSeeded] |

## Invariant coverage checklist

The [invariant suite](./BurnerLoansRescue.invariant.t.sol) interleaves accrual, retries, rescues and rejected calls. Its fixed fixture uses one token, two keepers and F=T. The per-call matrix above covers other layouts, multiple tokens, lifecycle combinations and callbacks.

| Property | Stateful check |
| --- | --- |
| Each bucket equals its independent model; aggregate equals their sum | Separate fee, seizure and keeper assertions |
| Custody backs pending debt; payments conserve tokens | Solvency and minted-token conservation after every action |
| Indexes represent outstanding debt without duplicates | Recipient membership/count, summed entitlement and token presence |
| Pending preview/getter agree; rejected rescues preserve accounting | Preview of each owed recipient; unauthorized, excessive and blocked-transfer attempts |

Sources: [facility](../../../policies/BurnerLoans.sol), [rescue interface](../../../policies/interfaces/IBurnerLoansRescue.sol), [payout accounting](../../../policies/libraries/BurnerLoansPayouts.sol), [existing tests](./rescuePendingPayout.t.sol).

[test_authorization_givenEnabled_givenPolicyActive_whenCallerIsConfigurator]: ./rescuePendingPayout.t.sol#L977
[test_authorization_givenEnabled_givenPolicyActive_whenCallerIsConfigurator_whenInputsInvalid_reverts]: ./rescuePendingPayout.t.sol#L991
[test_authorization_givenEnabled_givenPolicyActive_whenCallerIsUnauthorized_reverts]: ./rescuePendingPayout.t.sol#L1001
[test_authorization_whenUnauthorizedIdentitiesAreSeeded]: ./rescuePendingPayout.t.sol#L1194
[test_authorization_givenDisabled_givenPolicyActive_whenCallerIsConfigurator]: ./rescuePendingPayout.t.sol#L1011
[test_authorization_givenDisabled_givenPolicyActive_whenCallerIsConfigurator_whenInputsInvalid_reverts]: ./rescuePendingPayout.t.sol#L1026
[test_authorization_givenDisabled_givenPolicyActive_whenCallerIsUnauthorized_reverts]: ./rescuePendingPayout.t.sol#L1037
[test_authorization_givenEnabled_givenPolicyInactive_whenCallerIsConfigurator_reverts]: ./rescuePendingPayout.t.sol#L1049
[test_authorization_givenEnabled_givenPolicyInactive_whenCallerIsUnauthorized_reverts]: ./rescuePendingPayout.t.sol#L1065
[test_authorization_givenDisabled_givenPolicyInactive_whenCallerIsConfigurator_reverts]: ./rescuePendingPayout.t.sol#L1082
[test_authorization_givenDisabled_givenPolicyInactive_whenCallerIsUnauthorized_reverts]: ./rescuePendingPayout.t.sol#L1098
[test_authorization_givenActiveFacility_whenAdminCallsDirectly]: ./rescuePendingPayout.t.sol#L847
[test_authorization_givenActiveFacility_whenAdminCallsDirectly_whenInputsInvalid_reverts]: ./rescuePendingPayout.t.sol#L862
[test_authorization_givenInactiveFacility_whenAdminCallsDirectly_reverts]: ./rescuePendingPayout.t.sol#L879
[test_authorization_givenAdminRoleGranted_whenNewAdminCalls]: ./rescuePendingPayout.t.sol#L902
[test_authorization_givenAdminRoleNotGranted_whenCallerRescues_reverts]: ./rescuePendingPayout.t.sol#L911
[test_authorization_givenAdminRoleRevoked_whenFormerAdminRescues_reverts]: ./rescuePendingPayout.t.sol#L924
[test_givenConfigAndTimelockUnavailable_whenAdminRescuesDirectly]: ./rescuePendingPayout.t.sol#L942
[test_invalidInputs_whenTokenIsZero_reverts]: ./rescuePendingPayout.t.sol#L93
[test_invalidInputs_whenTokenHasNoCode_reverts]: ./rescuePendingPayout.t.sol#L117
[test_invalidInputs_whenFaultsCompete_reverts]: ./rescuePendingPayout.t.sol#L787
[test_invalidInputs_whenRecipientIsZero_reverts]: ./rescuePendingPayout.t.sol#L142
[test_invalidInputs_whenDestinationIsZero_reverts]: ./rescuePendingPayout.t.sol#L160
[test_invalidInputs_whenDestinationIsForbidden_reverts]: ./rescuePendingPayout.t.sol#L191
[test_invalidInputs_whenAmountIsZero_reverts]: ./rescuePendingPayout.t.sol#L223
[test_invalidInputs_whenAmountExceedsEntitlement_reverts]: ./rescuePendingPayout.t.sol#L246
[test_numericExtremes_givenSingleBucket_whenAmountExceedsEntitlement_reverts]: ./rescuePendingPayout.t.sol#L1647
[test_keeperIsolation_givenThreeKeepers_whenEachIsSelected]: ./rescuePendingPayout.t.sol#L1888
[test_keeperIsolation_givenDistinct_whenMaskAndMaximumBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L1986
[test_keeperIsolation_givenKeeperIsFeeRecipient_whenMaskAndMaximumBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L2023
[test_keeperIsolation_givenKeeperIsTreasury_whenMaskAndMaximumBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L2062
[test_keeperIsolation_givenFeeRecipientIsTreasury_whenMaskAndMaximumBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L2101
[test_keeperIsolation_givenAllRolesOverlap_whenMaskAndMaximumBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L2140
[test_tokenIsolation_givenTwoTokens_whenOneIsRescued]: ./rescuePendingPayout.t.sol#L2179
[test_surplusIsolation_givenDistinct_whenMasksAndCustodyBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L2330
[test_surplusIsolation_givenKeeperIsFeeRecipient_whenMasksAndCustodyBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L2336
[test_surplusIsolation_givenKeeperIsTreasury_whenMasksAndCustodyBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L2344
[test_surplusIsolation_givenFeeRecipientIsTreasury_whenMasksAndCustodyBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L2352
[test_surplusIsolation_givenAllRolesOverlap_whenMasksAndCustodyBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L2360
[test_tokenIsolation_whenEmptyPopulatedAndDrainBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L2403
[test_payoutAllocation_givenReward_whenAmountIsWithinItsInterval]: ./rescuePendingPayout.t.sol#L1231
[test_payoutAllocation_givenReward_whenBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L1254
[test_payoutAllocation_givenKeeperFeeAndTreasuryOverlap_whenAmountEqualsKeeperReward]: ./rescuePendingPayout.t.sol#L1532
[test_numericExtremes_givenVariableSolventBuckets_whenAmountIsWithinEntitlement]: ./rescuePendingPayout.t.sol#L1703
[test_payoutAllocation_givenFee_whenAmountIsWithinItsInterval]: ./rescuePendingPayout.t.sol#L1267
[test_payoutAllocation_givenFee_whenBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L1299
[test_payoutAllocation_givenSeizure_whenAmountIsWithinItsInterval]: ./rescuePendingPayout.t.sol#L1312
[test_payoutAllocation_givenSeizure_whenBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L1340
[test_payoutAllocation_givenRewardAndFee_whenAmountIsWithinItsInterval]: ./rescuePendingPayout.t.sol#L1353
[test_payoutAllocation_givenRewardAndFee_whenBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L1385
[test_payoutAllocation_givenKeeperFeeAndTreasuryOverlap_whenAmountEqualsRewardAndFee]: ./rescuePendingPayout.t.sol#L1543
[test_payoutAllocation_givenRewardAndSeizure_whenAmountIsWithinItsInterval]: ./rescuePendingPayout.t.sol#L1398
[test_payoutAllocation_givenRewardAndSeizure_whenBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L1431
[test_payoutAllocation_givenFeeAndSeizure_whenAmountIsWithinItsInterval]: ./rescuePendingPayout.t.sol#L1444
[test_payoutAllocation_givenFeeAndSeizure_whenBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L1480
[test_payoutAllocation_givenRewardFeeAndSeizure_whenAmountIsWithinItsInterval]: ./rescuePendingPayout.t.sol#L1493
[test_payoutAllocation_givenRewardFeeAndSeizure_whenBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L1520
[test_numericExtremes_givenMaxEntitlement_whenFullDebtIsRescued]: ./rescuePendingPayout.t.sol#L1597
[test_numericExtremes_givenSingleBucket_whenExactEntitlementIsRescued]: ./rescuePendingPayout.t.sol#L1623
[test_numericExtremes_givenMaxEntitlement_whenBucketSubsetsAreSeeded]: ./rescuePendingPayout.t.sol#L1680
[test_numericExtremes_givenMixedBuckets_whenValidAmountBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L1686
[test_transfers_givenExistingDestinationBalance_whenAmountIsRescued]: ./rescuePendingPayout.t.sol#L1738
[test_transfers_givenExistingDestinationBalance_whenAmountBoundariesAreSeeded]: ./rescuePendingPayout.t.sol#L1814
[test_transfers_givenBlockedDestination_whenAmountIsRescued_reverts]: ./rescuePendingPayout.t.sol#L1759
[test_transfers_givenBlockedDestination_whenRecipientAndAmountBoundariesAreSeeded_reverts]: ./rescuePendingPayout.t.sol#L1848
[test_transfers_givenDebtWithoutCustody_whenAmountIsRescued_reverts]: ./rescuePendingPayout.t.sol#L1791
[test_transfers_givenDebtWithoutCustody_whenAmountBoundariesAreSeeded_reverts]: ./rescuePendingPayout.t.sol#L1831
[test_callbacks_givenDistinct_whenCaughtCasesAreSeeded]: ./rescuePendingPayout.t.sol#L2593
[test_callbacks_givenKeeperIsFeeRecipient_whenCaughtCasesAreSeeded]: ./rescuePendingPayout.t.sol#L2613
[test_callbacks_givenKeeperIsTreasury_whenCaughtCasesAreSeeded]: ./rescuePendingPayout.t.sol#L2633
[test_callbacks_givenFeeRecipientIsTreasury_whenCaughtCasesAreSeeded]: ./rescuePendingPayout.t.sol#L2653
[test_callbacks_givenAllRolesOverlap_whenCaughtCasesAreSeeded]: ./rescuePendingPayout.t.sol#L2673
[test_callbacks_whenNestedWriteFailureIsCaught]: ./rescuePendingPayout.t.sol#L2466
[test_callbacks_whenNestedWriteFailureIsPropagated]: ./rescuePendingPayout.t.sol#L2533
[test_callbacks_givenDistinct_whenPropagatedCasesAreSeeded]: ./rescuePendingPayout.t.sol#L2598
[test_callbacks_givenKeeperIsFeeRecipient_whenPropagatedCasesAreSeeded]: ./rescuePendingPayout.t.sol#L2618
[test_callbacks_givenKeeperIsTreasury_whenPropagatedCasesAreSeeded]: ./rescuePendingPayout.t.sol#L2638
[test_callbacks_givenFeeRecipientIsTreasury_whenPropagatedCasesAreSeeded]: ./rescuePendingPayout.t.sol#L2658
[test_callbacks_givenAllRolesOverlap_whenPropagatedCasesAreSeeded]: ./rescuePendingPayout.t.sol#L2678
[test_callbacks_givenDistinct_whenPartialReadCasesAreSeeded]: ./rescuePendingPayout.t.sol#L2603
[test_callbacks_givenKeeperIsFeeRecipient_whenPartialReadCasesAreSeeded]: ./rescuePendingPayout.t.sol#L2623
[test_callbacks_givenKeeperIsTreasury_whenPartialReadCasesAreSeeded]: ./rescuePendingPayout.t.sol#L2643
[test_callbacks_givenFeeRecipientIsTreasury_whenPartialReadCasesAreSeeded]: ./rescuePendingPayout.t.sol#L2663
[test_callbacks_givenAllRolesOverlap_whenPartialReadCasesAreSeeded]: ./rescuePendingPayout.t.sol#L2683
[test_callbacks_whenReadsObservePartialRescue]: ./rescuePendingPayout.t.sol#L2789
[test_callbacks_givenDistinct_whenFullReadCasesAreSeeded]: ./rescuePendingPayout.t.sol#L2608
[test_callbacks_givenKeeperIsFeeRecipient_whenFullReadCasesAreSeeded]: ./rescuePendingPayout.t.sol#L2628
[test_callbacks_givenKeeperIsTreasury_whenFullReadCasesAreSeeded]: ./rescuePendingPayout.t.sol#L2648
[test_callbacks_givenFeeRecipientIsTreasury_whenFullReadCasesAreSeeded]: ./rescuePendingPayout.t.sol#L2668
[test_callbacks_givenAllRolesOverlap_whenFullReadCasesAreSeeded]: ./rescuePendingPayout.t.sol#L2688
[test_callbacks_whenReadsObserveFullRescue]: ./rescuePendingPayout.t.sol#L2809
[test_surplusIsolation_givenOneDebtOwner_whenTokenIsFullyDrained]: ./rescuePendingPayout.t.sol#L2286
[test_invalidInputs_givenDistinct_whenTokenIsZero_whenDomainBoundariesAreSeeded_reverts]: ./rescuePendingPayout.t.sol#L296
[test_invalidInputs_givenKeeperIsFeeRecipient_whenTokenIsZero_whenDomainBoundariesAreSeeded_reverts]: ./rescuePendingPayout.t.sol#L352
[test_invalidInputs_givenKeeperIsTreasury_whenTokenIsZero_whenDomainBoundariesAreSeeded_reverts]: ./rescuePendingPayout.t.sol#L408
[test_invalidInputs_givenFeeRecipientIsTreasury_whenTokenIsZero_whenDomainBoundariesAreSeeded_reverts]: ./rescuePendingPayout.t.sol#L464
[test_invalidInputs_givenAllRolesOverlap_whenTokenIsZero_whenDomainBoundariesAreSeeded_reverts]: ./rescuePendingPayout.t.sol#L520
[test_invalidInputs_givenDistinct_whenTokenHasNoCode_whenDomainBoundariesAreSeeded_reverts]: ./rescuePendingPayout.t.sol#L304
[test_invalidInputs_givenKeeperIsFeeRecipient_whenTokenHasNoCode_whenDomainBoundariesAreSeeded_reverts]: ./rescuePendingPayout.t.sol#L360
[test_invalidInputs_givenKeeperIsTreasury_whenTokenHasNoCode_whenDomainBoundariesAreSeeded_reverts]: ./rescuePendingPayout.t.sol#L416
[test_invalidInputs_givenFeeRecipientIsTreasury_whenTokenHasNoCode_whenDomainBoundariesAreSeeded_reverts]: ./rescuePendingPayout.t.sol#L472
[test_invalidInputs_givenAllRolesOverlap_whenTokenHasNoCode_whenDomainBoundariesAreSeeded_reverts]: ./rescuePendingPayout.t.sol#L528
[test_invalidInputs_givenDistinct_whenRecipientIsZero_whenDomainBoundariesAreSeeded_reverts]: ./rescuePendingPayout.t.sol#L312
[test_invalidInputs_givenKeeperIsFeeRecipient_whenRecipientIsZero_whenDomainBoundariesAreSeeded_reverts]: ./rescuePendingPayout.t.sol#L368
[test_invalidInputs_givenKeeperIsTreasury_whenRecipientIsZero_whenDomainBoundariesAreSeeded_reverts]: ./rescuePendingPayout.t.sol#L424
[test_invalidInputs_givenFeeRecipientIsTreasury_whenRecipientIsZero_whenDomainBoundariesAreSeeded_reverts]: ./rescuePendingPayout.t.sol#L480
[test_invalidInputs_givenAllRolesOverlap_whenRecipientIsZero_whenDomainBoundariesAreSeeded_reverts]: ./rescuePendingPayout.t.sol#L536
[test_invalidInputs_givenDistinct_whenDestinationIsZero_whenDomainBoundariesAreSeeded_reverts]: ./rescuePendingPayout.t.sol#L320
[test_invalidInputs_givenKeeperIsFeeRecipient_whenDestinationIsZero_whenDomainBoundariesAreSeeded_reverts]: ./rescuePendingPayout.t.sol#L376
[test_invalidInputs_givenKeeperIsTreasury_whenDestinationIsZero_whenDomainBoundariesAreSeeded_reverts]: ./rescuePendingPayout.t.sol#L432
[test_invalidInputs_givenFeeRecipientIsTreasury_whenDestinationIsZero_whenDomainBoundariesAreSeeded_reverts]: ./rescuePendingPayout.t.sol#L488
[test_invalidInputs_givenAllRolesOverlap_whenDestinationIsZero_whenDomainBoundariesAreSeeded_reverts]: ./rescuePendingPayout.t.sol#L544
[test_invalidInputs_givenDistinct_whenDestinationIsForbidden_whenDomainBoundariesAreSeeded_reverts]: ./rescuePendingPayout.t.sol#L328
[test_invalidInputs_givenKeeperIsFeeRecipient_whenDestinationIsForbidden_whenDomainBoundariesAreSeeded_reverts]: ./rescuePendingPayout.t.sol#L384
[test_invalidInputs_givenKeeperIsTreasury_whenDestinationIsForbidden_whenDomainBoundariesAreSeeded_reverts]: ./rescuePendingPayout.t.sol#L440
[test_invalidInputs_givenFeeRecipientIsTreasury_whenDestinationIsForbidden_whenDomainBoundariesAreSeeded_reverts]: ./rescuePendingPayout.t.sol#L496
[test_invalidInputs_givenAllRolesOverlap_whenDestinationIsForbidden_whenDomainBoundariesAreSeeded_reverts]: ./rescuePendingPayout.t.sol#L552
[test_invalidInputs_givenDistinct_whenAmountIsZero_whenDomainBoundariesAreSeeded_reverts]: ./rescuePendingPayout.t.sol#L336
[test_invalidInputs_givenKeeperIsFeeRecipient_whenAmountIsZero_whenDomainBoundariesAreSeeded_reverts]: ./rescuePendingPayout.t.sol#L392
[test_invalidInputs_givenKeeperIsTreasury_whenAmountIsZero_whenDomainBoundariesAreSeeded_reverts]: ./rescuePendingPayout.t.sol#L448
[test_invalidInputs_givenFeeRecipientIsTreasury_whenAmountIsZero_whenDomainBoundariesAreSeeded_reverts]: ./rescuePendingPayout.t.sol#L504
[test_invalidInputs_givenAllRolesOverlap_whenAmountIsZero_whenDomainBoundariesAreSeeded_reverts]: ./rescuePendingPayout.t.sol#L560
[test_invalidInputs_givenDistinct_whenAmountExceedsEntitlement_whenDomainBoundariesAreSeeded_reverts]: ./rescuePendingPayout.t.sol#L344
[test_invalidInputs_givenKeeperIsFeeRecipient_whenAmountExceedsEntitlement_whenDomainBoundariesAreSeeded_reverts]: ./rescuePendingPayout.t.sol#L400
[test_invalidInputs_givenKeeperIsTreasury_whenAmountExceedsEntitlement_whenDomainBoundariesAreSeeded_reverts]: ./rescuePendingPayout.t.sol#L456
[test_invalidInputs_givenFeeRecipientIsTreasury_whenAmountExceedsEntitlement_whenDomainBoundariesAreSeeded_reverts]: ./rescuePendingPayout.t.sol#L512
[test_invalidInputs_givenAllRolesOverlap_whenAmountExceedsEntitlement_whenDomainBoundariesAreSeeded_reverts]: ./rescuePendingPayout.t.sol#L568
