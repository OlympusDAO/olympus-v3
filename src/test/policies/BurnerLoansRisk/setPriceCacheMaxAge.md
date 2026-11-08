# BurnerLoansRisk.setPriceCacheMaxAge coverage plan

Source: [setPriceCacheMaxAge](../../../policies/burnerloans/BurnerLoansRisk.sol#L597). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLRISK-CACHE-AGE` identifies this contract/function.

Implemented same-value rule: authorize first, then return without writes/events when unchanged. Changing-value rows exclude the current value.

The setter permits ADMIN_ROLE or Risk's own selected nonzero configOperator. The operator may be this system's ConfigTimelock, another controller, or an EOA; it need not equal Core.configOperator() or Config.configOperator(). Config has no automatic authority and no ADMIN grant. Unauthorized mixed-authority callers receive NotAuthorised(). Risk enforces its own active/enabled admission; Core and upstream-controller lifecycle are not read. Cache/oracle address replacements remain ADMIN-only.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Local policy lifecycle

All inputs and required services are otherwise valid. Earlier local transition/authorization guards follow concrete source ordering.

| ID | Caller | Local active | Local enabled | Expected execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLRISK-CACHE-AGE-L05 | Fuzz ADMIN or selected configOperator; guarantee both exclusive classes | true | true | Same valid function result | No changes on rejection | Covered: [test][test_givenAdmin_whenAgeChanges], [test][test_givenAdmin_whenAgeBoundaries], [test][test_givenOperator_whenAgeChanges], [test][test_givenOperator_whenAgeBoundaries] |
| BLRISK-CACHE-AGE-L06 | Fuzz ADMIN or selected configOperator; guarantee both exclusive classes | true | false | NotEnabled() | No changes on rejection | Covered: [test][test_givenDisabled_whenAdminChangesAge_reverts], [test][test_givenDisabled_whenOperatorChangesAge_reverts] |
| BLRISK-CACHE-AGE-L07 | Fuzz ADMIN or selected configOperator; guarantee both exclusive classes | false | true | BurnerLoans_PolicyNotActive(Risk) | No changes on rejection | Covered: [test][test_givenInactive_whenAdminChangesAge_reverts], [test][test_givenInactive_whenOperatorChangesAge_reverts] |
| BLRISK-CACHE-AGE-L08 | Fuzz ADMIN or selected configOperator; guarantee both exclusive classes | false | false | BurnerLoans_PolicyNotActive(Risk) | No changes on rejection | Covered: [test][test_givenInactiveAndDisabled_whenAdminChangesAge_reverts], [test][test_givenInactiveAndDisabled_whenOperatorChangesAge_reverts] |

## Authorization

| ID | Caller | Inputs / competing fault | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-CACHE-AGE-A01 | Fuzz ADMIN_ROLE holder distinct from selected configOperator | Fuzz age 0..MAX48; seed 0,1,MAX48 | Success | Risk stores age and emits PriceCacheMaxAgeSet(age); no cache refresh | Covered: [test][test_givenAdmin_whenAgeChanges], [test][test_givenAdmin_whenAgeBoundaries] |
| BLRISK-CACHE-AGE-A02 | Selected nonzero configOperator without ADMIN_ROLE | Stored authority matches; fuzz age 0..MAX48 | Success without ADMIN grant or lookup | Store age; exact Risk event; no Core/FLOAN/Custody update | Covered: [test][test_givenOperator_whenAgeChanges], [test][test_givenOperator_whenAgeBoundaries] |
| BLRISK-CACHE-AGE-A03 | Former configOperator without ADMIN_ROLE | Risk.configOperator has changed to another address | NotAuthorised() | Unchanged; old operator cannot configure Risk | Covered: [test][test_givenOperator_whenReplaced_reverts] |
| BLRISK-CACHE-AGE-A07 | Fuzz unauthorized EOA/contracts | Caller lacks ADMIN and is not selected configOperator | NotAuthorised() | Unchanged; no committed logs | Covered: [test][test_whenUnauthorizedCallerChangesAge_reverts] |

## Zero-value configuration

Fixed for this table: Accounting / events: Store0; PriceCacheMaxAgeSet(0).

| ID | Caller | Invalid parameter | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLRISK-CACHE-AGE-P01 | ADMIN_ROLE holder | age=0 | Success | Covered: [test][test_givenAdmin_whenAgeChanges], [test][test_givenAdmin_whenAgeBoundaries] |

## Numeric boundaries and arithmetic

| ID | Caller | Numeric input / arithmetic condition | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-CACHE-AGE-N01 | ADMIN_ROLE holder | age fuzz1..MAX48; seed1,MAX48 | Success | Store requested age; exact event | Covered: [test][test_givenAdmin_whenAgeChanges], [test][test_givenAdmin_whenAgeBoundaries] |
| BLRISK-CACHE-AGE-N02 | Selected nonzero configOperator | Stored authority matches; age fuzz0..MAX48 | Success | Store/event without oracle/cache refresh | Covered: [test][test_givenOperator_whenAgeChanges], [test][test_givenOperator_whenAgeBoundaries] |

## Successful execution

Fixed for this table: Accounting / events: Required no-op: no write/event; implemented no-op.

| ID | Caller | Operation / pre-state | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLRISK-CACHE-AGE-P02 | ADMIN_ROLE holder | age equals stored age | Success | Covered: [test][test_whenAgeIsUnchanged] |

## Stored-controller independence

Retired IDs BLRISK-CACHE-AGE-A04/A05/A06 expected reverse lifecycle checks that Risk does not perform. Use a changed age; independently seed Core activity/enablement and stored-controller lifecycle. Risk must itself be active/enabled for these successful calls.

| ID | Caller | Controller active | Controller enabled | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLRISK-CACHE-AGE-L01 | Stored nonzero controller without ADMIN | true | true | Success | Changed age/event; no controller lifecycle or Kernel getter | Covered: [test][test_givenControllerActiveAndEnabled_whenAgeChanges] |
| BLRISK-CACHE-AGE-L02 | Stored nonzero controller without ADMIN | true | false | Success | Upstream public controller enforces its own admission | Covered: [test][test_givenControllerActiveAndDisabled_whenAgeChanges] |
| BLRISK-CACHE-AGE-L03 | Stored nonzero controller without ADMIN | false | true | Success | No reverse activity check | Covered: [test][test_givenControllerInactiveAndEnabled_whenAgeChanges] |
| BLRISK-CACHE-AGE-L04 | Stored nonzero controller without ADMIN | false | false | Success | No reverse lifecycle check | Covered: [test][test_givenControllerInactiveAndDisabled_whenAgeChanges] |
| BLRISK-CACHE-AGE-D01 | Stored nonzero controller without ADMIN | Fuzz true/false | Fuzz true/false | Success while controller kernel()/isEnabled() getters revert | No controller getters called | Covered: [test][test_givenControllerActiveAndEnabled_whenAgeChanges], [test][test_givenControllerActiveAndDisabled_whenAgeChanges], [test][test_givenControllerInactiveAndEnabled_whenAgeChanges], [test][test_givenControllerInactiveAndDisabled_whenAgeChanges] |
| BLRISK-CACHE-AGE-A08 | Old controller without ADMIN | Fuzz true/false | Fuzz true/false | NotAuthorised() after Risk selects another controller | Old authority cannot update even if Core Config or Config.configOperator still equals it | Covered: [test][test_givenOperator_whenReplaced_reverts] |

[test_givenAdmin_whenAgeBoundaries]: setPriceCacheMaxAge.t.sol#L36

[test_givenAdmin_whenAgeChanges]: setPriceCacheMaxAge.t.sol#L28

[test_givenControllerActiveAndDisabled_whenAgeChanges]: setPriceCacheMaxAge.t.sol#L184

[test_givenControllerActiveAndEnabled_whenAgeChanges]: setPriceCacheMaxAge.t.sol#L161

[test_givenControllerInactiveAndDisabled_whenAgeChanges]: setPriceCacheMaxAge.t.sol#L230

[test_givenControllerInactiveAndEnabled_whenAgeChanges]: setPriceCacheMaxAge.t.sol#L207

[test_givenDisabled_whenAdminChangesAge_reverts]: setPriceCacheMaxAge.t.sol#L66

[test_givenDisabled_whenOperatorChangesAge_reverts]: setPriceCacheMaxAge.t.sol#L74

[test_givenInactiveAndDisabled_whenAdminChangesAge_reverts]: setPriceCacheMaxAge.t.sol#L106

[test_givenInactiveAndDisabled_whenOperatorChangesAge_reverts]: setPriceCacheMaxAge.t.sol#L119

[test_givenInactive_whenAdminChangesAge_reverts]: setPriceCacheMaxAge.t.sol#L86

[test_givenInactive_whenOperatorChangesAge_reverts]: setPriceCacheMaxAge.t.sol#L94

[test_givenOperator_whenAgeBoundaries]: setPriceCacheMaxAge.t.sol#L54

[test_givenOperator_whenAgeChanges]: setPriceCacheMaxAge.t.sol#L43

[test_givenOperator_whenReplaced_reverts]: setPriceCacheMaxAge.t.sol#L144

[test_whenAgeIsUnchanged]: setPriceCacheMaxAge.t.sol#L153

[test_whenUnauthorizedCallerChangesAge_reverts]: setPriceCacheMaxAge.t.sol#L132
