# BurnerLoansRisk.setReferralFeeBps scenario plan

Source: [setReferralFeeBps](../../../policies/burnerloans/BurnerLoansRisk.sol#L610).

Source precedents: [Risk cache-age setter](../../../policies/burnerloans/BurnerLoansRisk.sol#L597), [operator authority](../../../policies/utils/ConfigOperatorSingleStep.sol#L48).

The referral API and its errors/events are implemented below. Existing error selectors retain their declaring interfaces. ADMIN means any Kernel ADMIN role holder; O is Risk's selected nonzero configOperator, which need not be a Policy. BLA alone is not target authority. Authorized caller fuzzing guarantees ADMIN-only, O-only, and their overlap; unauthorized fuzzing excludes every ADMIN holder and O. Core, Config and BLRCT are upstream identities, not operational dependencies of these setters.

Unchanged means all referral settings, cache/oracle bindings, FLOAN positions/markets, payout buckets/indexes/reserves, token balances and allowances remain unchanged; a revert commits no logs. Local active and enabled are independent. Successful numeric/state rows assume Risk active/enabled and cached ROLES usable. Re-enabled means the successful disable/reEnable sequence has completed with settings preserved.

Scenario scope: `BLRISK-REFERRAL-BPS`. Signature: `setReferralFeeBps(uint16 bps)`; getter `referralFeeBps()`. One global percentage covers every approved address, asset, borrow and extension. Scale is 10,000 BPS = 100%; initial value is zero. Error: `BurnerLoansRisk_InvalidReferralFeeBps(uint16 bps)`; event `ReferralFeeBpsSet(uint16 bps)`. Relevant requirements: R4-R9, R18-R19; AE3-AE8, AE10, AE15, AE35.

Review status: approved for implementation; scenario review completed. Rows are mapped to implemented tests below. Coverage records the stated domains; execution results are reported separately.

## Authorization

Use a changed otherwise-valid input. Same-value calls must not bypass authorization.

| ID | Caller | Operator selection | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-REFERRAL-BPS-A01 | Fuzz ADMIN-only | Zero, O, or a different address; seed each | Success | Store changed setting and one setting event | Covered: [test_givenAdmin_whenPercentageChanges][test_givenAdmin_whenPercentageChanges], [test_whenPercentageBoundaryTransitions][test_whenPercentageBoundaryTransitions], [test_givenEachAdminOperatorSelection_whenChanged][test_givenEachAdminOperatorSelection_whenChanged] |
| BLRISK-REFERRAL-BPS-A02 | O-only and ADMIN/O overlap | O selected | Success without querying upstream lifecycle | Store changed setting and one setting event | Covered: [test_whenPercentageBoundaryTransitions][test_whenPercentageBoundaryTransitions], [test_givenOperator_whenPercentageChanges][test_givenOperator_whenPercentageChanges], [test_givenEachAdminOperatorSelection_whenChanged][test_givenEachAdminOperatorSelection_whenChanged] |
| BLRISK-REFERRAL-BPS-A03 | Fuzz caller excluding every ADMIN and selected O | Include BLA-only, EMERGENCY-only, former O, unrelated contract/EOA | IPolicyAdmin.NotAuthorised() | Unchanged | Covered: [test_whenUnauthorizedCaller_reverts][test_whenUnauthorizedCaller_reverts], [test_givenBlaOnly_whenSettingChanged_reverts][test_givenBlaOnly_whenSettingChanged_reverts], [test_givenEmergencyOnly_whenSettingChanged_reverts][test_givenEmergencyOnly_whenSettingChanged_reverts], [test_givenFormerOperator_whenSettingChanged_reverts][test_givenFormerOperator_whenSettingChanged_reverts] |
| BLRISK-REFERRAL-BPS-A04 | Unauthorized caller as above | Input equals current setting | IPolicyAdmin.NotAuthorised() before no-op | Unchanged | Covered: [test_whenUnauthorizedCaller_reverts][test_whenUnauthorizedCaller_reverts], [test_whenUnauthorizedSameValue_reverts][test_whenUnauthorizedSameValue_reverts], [test_givenBlaOnly_whenSettingChanged_reverts][test_givenBlaOnly_whenSettingChanged_reverts], [test_givenEmergencyOnly_whenSettingChanged_reverts][test_givenEmergencyOnly_whenSettingChanged_reverts], [test_givenFormerOperator_whenSettingChanged_reverts][test_givenFormerOperator_whenSettingChanged_reverts] |

## Local admission

Caller is ADMIN-only or selected O-only; guarantee both. Check competing unauthorized and invalid-input faults without changing the expected earlier lifecycle error.

| ID | Caller | Local active | Local enabled | History | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLRISK-REFERRAL-BPS-L01 | ADMIN or O | false | true | Previously activated | BurnerLoans_PolicyNotActive(Risk) | Unchanged | Covered: [test_givenInactive_whenPercentageChanges_reverts][test_givenInactive_whenPercentageChanges_reverts] |
| BLRISK-REFERRAL-BPS-L02 | ADMIN or O | false | false | Previously activated | BurnerLoans_PolicyNotActive(Risk) | Unchanged | Covered: [test_givenInactive_whenPercentageChanges_reverts][test_givenInactive_whenPercentageChanges_reverts] |
| BLRISK-REFERRAL-BPS-L03 | ADMIN or O | true | false | Previously activated | IEnabler.NotEnabled() | Unchanged | Covered: [test_givenDisabled_whenPercentageChanges_reverts][test_givenDisabled_whenPercentageChanges_reverts] |
| BLRISK-REFERRAL-BPS-L04 | ADMIN or O | true | true | Initial enable, re-enabled, and Kernel reactivated; seed each | Success | Only requested setting and event change | Covered: [test_givenReEnabled_whenPercentageChanges][test_givenReEnabled_whenPercentageChanges] |

## Upstream independence

Risk remains operational; use a changed input. No controller/Core/Config metadata call is permitted.

| ID | Caller | Controller active | Controller enabled | Core/Config active | Core/Config enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLRISK-REFERRAL-BPS-D01 | ADMIN or O | Fuzz false/true | Fuzz false/true | Fuzz false/true independently | Fuzz false/true independently | Success even when upstream getters revert | Changed setting; no FLOAN write or payout repricing | Covered: [test_givenUnreadableController_whenPercentageChanges][test_givenUnreadableController_whenPercentageChanges], [test_givenIndependentUpstreamLifecycle_whenConfigured][test_givenIndependentUpstreamLifecycle_whenConfigured], [test_givenEveryIndependentUpstreamState_whenConfigured][test_givenEveryIndependentUpstreamState_whenConfigured] |

## Percentage boundaries

Caller ADMIN or O. Values different from current state except the explicit no-op row. No transfer or external calculator call is expected.

| ID | Caller | BPS domain / guaranteed seeds | Execution | Stored state / event / downstream proof | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-REFERRAL-BPS-N01 | ADMIN or O | Fuzz 0..10000; seed 0,1,9999,10000 | Success | Store exact bps; one ReferralFeeBpsSet(bps); next splits use it on both operations and two assets | Covered: [test_givenSharedReferralPercentage_whenDifferentMarketsAndTermsQuoted][test_givenSharedReferralPercentage_whenDifferentMarketsAndTermsQuoted], [test_givenAdmin_whenPercentageChanges][test_givenAdmin_whenPercentageChanges], [test_whenPercentageBoundaryTransitions][test_whenPercentageBoundaryTransitions], [test_givenOperator_whenPercentageChanges][test_givenOperator_whenPercentageChanges] |
| BLRISK-REFERRAL-BPS-I01 | ADMIN or O | Fuzz 10001..MAX16; seed 10001,65535 | BurnerLoansRisk_InvalidReferralFeeBps(bps) | Unchanged | Covered: [test_whenInvalidPercentage_reverts][test_whenInvalidPercentage_reverts], [test_whenInvalidPercentageBoundaries_reverts][test_whenInvalidPercentageBoundaries_reverts] |
| BLRISK-REFERRAL-BPS-P01 | ADMIN or O | Same valid bps; seed 0,1,10000 | Success, event-free no-op | No writes; no earned reward repricing | Covered: [test_whenSamePercentage][test_whenSamePercentage], [invariant_pendingKeysAndSettingsMatchIndependentModel][invariant_pendingKeysAndSettingsMatchIndependentModel] |
| BLRISK-REFERRAL-BPS-P02 | ADMIN or O | Transitions 0→10000→1→0 with pending rewards | Success for each changed value | Each new split uses current bps; old pending token/recipient/amount and aggregate reserve remain fixed | Covered: [test_whenPercentageBoundaryTransitions][test_whenPercentageBoundaryTransitions], [invariant_pendingKeysAndSettingsMatchIndependentModel][invariant_pendingKeysAndSettingsMatchIndependentModel] |

- [x] Review these expectations.
- [x] Write tests before implementation and map passing evidence.

[invariant_pendingKeysAndSettingsMatchIndependentModel]: ../BurnerLoansRiskConfigTimelock/executeQueuedAction.invariants.t.sol#L203
[test_givenAdmin_whenPercentageChanges]: setReferralFeeBps.t.sol#L65
[test_givenBlaOnly_whenSettingChanged_reverts]: setReferralFeeBps.t.sol#L159
[test_givenDisabled_whenPercentageChanges_reverts]: setReferralFeeBps.t.sol#L112
[test_givenEachAdminOperatorSelection_whenChanged]: setReferralFeeBps.t.sol#L148
[test_givenEmergencyOnly_whenSettingChanged_reverts]: setReferralFeeBps.t.sol#L168
[test_givenEveryIndependentUpstreamState_whenConfigured]: setReferralFeeBpsIntegration.t.sol#L41
[test_givenFormerOperator_whenSettingChanged_reverts]: setReferralFeeBps.t.sol#L177
[test_givenInactive_whenPercentageChanges_reverts]: setReferralFeeBps.t.sol#L99
[test_givenIndependentUpstreamLifecycle_whenConfigured]: setReferralFeeBpsIntegration.t.sol#L12
[test_givenOperator_whenPercentageChanges]: setReferralFeeBps.t.sol#L84
[test_givenReEnabled_whenPercentageChanges]: setReferralFeeBps.t.sol#L121
[test_givenSharedReferralPercentage_whenDifferentMarketsAndTermsQuoted]: feeIntegration.t.sol#L338
[test_givenUnreadableController_whenPercentageChanges]: setReferralFeeBps.t.sol#L129
[test_whenInvalidPercentageBoundaries_reverts]: setReferralFeeBps.t.sol#L59
[test_whenInvalidPercentage_reverts]: setReferralFeeBps.t.sol#L46
[test_whenPercentageBoundaryTransitions]: setReferralFeeBps.t.sol#L76
[test_whenSamePercentage]: setReferralFeeBps.t.sol#L89
[test_whenUnauthorizedCaller_reverts]: setReferralFeeBps.t.sol#L29
[test_whenUnauthorizedSameValue_reverts]: setReferralFeeBps.t.sol#L41
