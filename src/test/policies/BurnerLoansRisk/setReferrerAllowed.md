# BurnerLoansRisk.setReferrerAllowed scenario plan

Source: [setReferrerAllowed](../../../policies/burnerloans/BurnerLoansRisk.sol#L629).

Source precedents: [Risk cache-age setter](../../../policies/burnerloans/BurnerLoansRisk.sol#L597), [operator authority](../../../policies/utils/ConfigOperatorSingleStep.sol#L48).

The referral API and its errors/events are implemented below. Existing error selectors retain their declaring interfaces. ADMIN means any Kernel ADMIN role holder; O is Risk's selected nonzero configOperator, which need not be a Policy. BLA alone is not target authority. Authorized caller fuzzing guarantees ADMIN-only, O-only, and their overlap; unauthorized fuzzing excludes every ADMIN holder and O. Core, Config and BLRCT are upstream identities, not operational dependencies of these setters.

Unchanged means all referral settings, cache/oracle bindings, FLOAN positions/markets, payout buckets/indexes/reserves, token balances and allowances remain unchanged; a revert commits no logs. Local active and enabled are independent. Successful numeric/state rows assume Risk active/enabled and cached ROLES usable. Re-enabled means the successful disable/reEnable sequence has completed with settings preserved.

Scenario scope: `BLRISK-REFERRER`. Signature: `setReferrerAllowed(address referrer,bool allowed)`; getter `isReferrerAllowed(address)`. Initial membership is false. Zero is never admitted, including a no-op zero removal; error is existing `BurnerLoans_ZeroAddress()`. Event: `ReferrerAllowedSet(address indexed referrer,bool allowed)`. Whitelisting is eligibility, not borrower authority. Relevant requirements: R3,R7-R9,R18-R19; AE9-AE12,AE15,AE22,AE35.

Review detail: accept nonzero EOAs and contracts without ERC165 or Policy lifecycle requirements. No global ban on borrower/operator/protocol recipient equality applies. Payout-self delivery must retain its liability rather than treating a self-transfer as payment; that case is specified in creditFee.

Review status: approved for implementation; scenario review completed. Rows are mapped to implemented tests below. Coverage records the stated domains; execution results are reported separately.

## Authorization

Use a changed otherwise-valid input. Same-value calls must not bypass authorization.

| ID | Caller | Operator selection | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-REFERRER-A01 | Fuzz ADMIN-only | Zero, O, or a different address; seed each | Success | Store changed setting and one setting event | Covered: [test_givenAdmin_whenMembershipChanges][test_givenAdmin_whenMembershipChanges], [test_givenEachAdminOperatorSelection_whenChanged][test_givenEachAdminOperatorSelection_whenChanged] |
| BLRISK-REFERRER-A02 | O-only and ADMIN/O overlap | O selected | Success without querying upstream lifecycle | Store changed setting and one setting event | Covered: [test_givenOperator_whenMembershipChanges][test_givenOperator_whenMembershipChanges], [test_givenEachAdminOperatorSelection_whenChanged][test_givenEachAdminOperatorSelection_whenChanged] |
| BLRISK-REFERRER-A03 | Fuzz caller excluding every ADMIN and selected O | Include BLA-only, EMERGENCY-only, former O, unrelated contract/EOA | IPolicyAdmin.NotAuthorised() | Unchanged | Covered: [test_whenUnauthorizedCaller_reverts][test_whenUnauthorizedCaller_reverts], [test_givenBlaOnly_whenSettingChanged_reverts][test_givenBlaOnly_whenSettingChanged_reverts], [test_givenEmergencyOnly_whenSettingChanged_reverts][test_givenEmergencyOnly_whenSettingChanged_reverts], [test_givenFormerOperator_whenSettingChanged_reverts][test_givenFormerOperator_whenSettingChanged_reverts] |
| BLRISK-REFERRER-A04 | Unauthorized caller as above | Input equals current setting | IPolicyAdmin.NotAuthorised() before no-op | Unchanged | Covered: [test_whenUnauthorizedCaller_reverts][test_whenUnauthorizedCaller_reverts], [test_whenUnauthorizedSameValue_reverts][test_whenUnauthorizedSameValue_reverts], [test_givenBlaOnly_whenSettingChanged_reverts][test_givenBlaOnly_whenSettingChanged_reverts], [test_givenEmergencyOnly_whenSettingChanged_reverts][test_givenEmergencyOnly_whenSettingChanged_reverts], [test_givenFormerOperator_whenSettingChanged_reverts][test_givenFormerOperator_whenSettingChanged_reverts] |

## Local admission

Caller is ADMIN-only or selected O-only; guarantee both. Check competing unauthorized and invalid-input faults without changing the expected earlier lifecycle error.

| ID | Caller | Local active | Local enabled | History | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLRISK-REFERRER-L01 | ADMIN or O | false | true | Previously activated | BurnerLoans_PolicyNotActive(Risk) | Unchanged | Covered: [test_givenInactive_whenMembershipChanges_reverts][test_givenInactive_whenMembershipChanges_reverts] |
| BLRISK-REFERRER-L02 | ADMIN or O | false | false | Previously activated | BurnerLoans_PolicyNotActive(Risk) | Unchanged | Covered: [test_givenInactive_whenMembershipChanges_reverts][test_givenInactive_whenMembershipChanges_reverts] |
| BLRISK-REFERRER-L03 | ADMIN or O | true | false | Previously activated | IEnabler.NotEnabled() | Unchanged | Covered: [test_givenDisabled_whenMembershipChanges_reverts][test_givenDisabled_whenMembershipChanges_reverts] |
| BLRISK-REFERRER-L04 | ADMIN or O | true | true | Initial enable, re-enabled, and Kernel reactivated; seed each | Success | Only requested setting and event change | Covered: [test_givenReEnabled_whenMembershipChanges][test_givenReEnabled_whenMembershipChanges] |

## Upstream independence

Risk remains operational; use a changed input. No controller/Core/Config metadata call is permitted.

| ID | Caller | Controller active | Controller enabled | Core/Config active | Core/Config enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLRISK-REFERRER-D01 | ADMIN or O | Fuzz false/true | Fuzz false/true | Fuzz false/true independently | Fuzz false/true independently | Success even when upstream getters revert | Changed setting; no FLOAN write or payout repricing | Covered: [test_givenUnreadableController_whenMembershipChanges][test_givenUnreadableController_whenMembershipChanges], [test_givenIndependentUpstreamLifecycle_whenConfigured][test_givenIndependentUpstreamLifecycle_whenConfigured], [test_givenEveryIndependentUpstreamState_whenConfigured][test_givenEveryIndependentUpstreamState_whenConfigured] |

## Membership transitions

Caller ADMIN or O; nonzero referrer identity is independent of caller, borrower, operator and fee recipient. Seed each overlap and an unrelated EOA/contract.

| ID | Caller | Referrer | Old membership | Requested membership | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLRISK-REFERRER-I01 | ADMIN or O | Zero | false | Fuzz false/true; seed both | BurnerLoans_ZeroAddress() before same-value return | Unchanged | Covered: [test_whenZeroReferrer_reverts][test_whenZeroReferrer_reverts], [test_whenZeroReferrerBoundaries_reverts][test_whenZeroReferrerBoundaries_reverts] |
| BLRISK-REFERRER-P01 | ADMIN or O | Fuzz nonzero | false | true | Success | Membership true; exactly ReferrerAllowedSet(referrer,true); other addresses unchanged | Covered: [test_givenAdmin_whenMembershipChanges][test_givenAdmin_whenMembershipChanges], [test_givenOperator_whenMembershipChanges][test_givenOperator_whenMembershipChanges] |
| BLRISK-REFERRER-P02 | ADMIN or O | Fuzz nonzero | true | false | Success | Membership false; exactly ReferrerAllowedSet(referrer,false); old funded rewards untouched | Covered: [test_givenAdmin_whenMembershipChanges][test_givenAdmin_whenMembershipChanges], [test_givenOperator_whenMembershipChanges][test_givenOperator_whenMembershipChanges], [invariant_pendingKeysAndSettingsMatchIndependentModel][invariant_pendingKeysAndSettingsMatchIndependentModel] |
| BLRISK-REFERRER-P03 | ADMIN or O | Fuzz nonzero | false | false | Success, event-free no-op | Unchanged | Covered: [test_whenSameMembership][test_whenSameMembership] |
| BLRISK-REFERRER-P04 | ADMIN or O | Fuzz nonzero | true | true | Success, event-free no-op | Unchanged | Covered: [test_whenSameMembership][test_whenSameMembership] |
| BLRISK-REFERRER-P05 | ADMIN or O | Two independent addresses R1,R2 | R1 allowed; R2 absent | Remove R1, add R2, re-add R1 | Success per transaction | Only selected address changes each time; prior R1 obligations stay with R1 | Covered: [test_whenIndependentReferrersChange][test_whenIndependentReferrersChange], [invariant_pendingKeysAndSettingsMatchIndependentModel][invariant_pendingKeysAndSettingsMatchIndependentModel] |

- [x] Review these expectations.
- [x] Write tests before implementation and map passing evidence.

[invariant_pendingKeysAndSettingsMatchIndependentModel]: ../BurnerLoansRiskConfigTimelock/executeQueuedAction.invariants.t.sol#L203
[test_givenAdmin_whenMembershipChanges]: setReferrerAllowed.t.sol#L61
[test_givenBlaOnly_whenSettingChanged_reverts]: setReferrerAllowed.t.sol#L163
[test_givenDisabled_whenMembershipChanges_reverts]: setReferrerAllowed.t.sol#L116
[test_givenEachAdminOperatorSelection_whenChanged]: setReferrerAllowed.t.sol#L152
[test_givenEmergencyOnly_whenSettingChanged_reverts]: setReferrerAllowed.t.sol#L172
[test_givenEveryIndependentUpstreamState_whenConfigured]: setReferrerAllowedIntegration.t.sol#L41
[test_givenFormerOperator_whenSettingChanged_reverts]: setReferrerAllowed.t.sol#L183
[test_givenInactive_whenMembershipChanges_reverts]: setReferrerAllowed.t.sol#L103
[test_givenIndependentUpstreamLifecycle_whenConfigured]: setReferrerAllowedIntegration.t.sol#L12
[test_givenOperator_whenMembershipChanges]: setReferrerAllowed.t.sol#L74
[test_givenReEnabled_whenMembershipChanges]: setReferrerAllowed.t.sol#L125
[test_givenUnreadableController_whenMembershipChanges]: setReferrerAllowed.t.sol#L133
[test_whenIndependentReferrersChange]: setReferrerAllowed.t.sol#L91
[test_whenSameMembership]: setReferrerAllowed.t.sol#L81
[test_whenUnauthorizedCaller_reverts]: setReferrerAllowed.t.sol#L30
[test_whenUnauthorizedSameValue_reverts]: setReferrerAllowed.t.sol#L43
[test_whenZeroReferrerBoundaries_reverts]: setReferrerAllowed.t.sol#L55
[test_whenZeroReferrer_reverts]: setReferrerAllowed.t.sol#L48
