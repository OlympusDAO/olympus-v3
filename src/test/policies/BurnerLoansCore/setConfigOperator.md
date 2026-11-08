# BurnerLoansCore.setConfigOperator coverage plan

Desired API: `setConfigOperator(address)` with the corresponding `configOperator()` getter. Source references: [shared operator rotation](../../../policies/utils/ConfigOperatorSingleStep.sol#L27) and [current Core market handoff](../../../policies/burnerloans/BurnerLoansCore.sol#L679). Production now uses the shared operator API and the product-specific handoff rules below.

Coverage records implemented scenario domains and assertions. Test pass/fail results are separate from coverage.

## Domains and notation

Scenario scope: `BLCORE-CONFIGURATOR` identifies this contract/function. These IDs remain stable through the API rename, preserving reciprocal test mappings.

ADMIN only; nonReentrant; Core activity required, but local enablement is not. Config is an upstream authority, not an operational dependency. Core must not query its activity, enablement, Kernel, interface, facility or OHM. An unchanged address reverts with ConfigOperator_Unchanged(); zero remains invalid. Governance is responsible for choosing a usable Config contract. No reverse upstream compatibility or lifecycle calls remain.

Hand off each registered FLOAN market manager and Core's selected config operator atomically. Risk, Inventory and Payout authorities remain independent. No Risk authority preparation or agreement check is required. Reuse `ConfigOperatorSingleStep` for shared authority storage and rotation, with a Core override retaining the product-specific validation, lifecycle/settlement guards and atomic transfer of every registered FLOAN market manager. The shared base permits zero revocation; Core retains its nonzero controller requirement and the explicit error expectations below.

Mapped tests exercise setConfigOperator/configOperator and the shared ConfigOperatorSet event. The former configurator API and event are removed.

## Authorization

| ID | Caller | Local active | Local enabled | Input | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCORE-CONFIGURATOR-A01 | Fuzz caller excluding all ADMIN holders | true | Fuzz true/false independently | Valid/invalid candidate | ROLES_RequireRole(ADMIN_ROLE) after own activity and before input validation | Unchanged; no FLOAN manager calls | Covered: [test][test_givenUnauthorized_whenConfigOperatorSet_reverts] |

## Lifecycle

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCORE-CONFIGURATOR-L01 | Fuzz ADMIN_ROLE holder | true | true | Success with valid inputs | Function-specific effects on success; otherwise Unchanged | Covered: [test][test_givenCompatibleAuthority_whenConfigOperatorSet] |
| BLCORE-CONFIGURATOR-L02 | Fuzz ADMIN_ROLE holder | true | false | Success with valid inputs | Function-specific effects on success; otherwise Unchanged | Covered: [test][test_givenCompatibleAuthority_whenConfigOperatorSet] |
| BLCORE-CONFIGURATOR-L03 | Fuzz ADMIN_ROLE holder | false | true | BurnerLoans_PolicyNotActive(BurnerLoansCore) | Function-specific effects on success; otherwise Unchanged | Covered: [test][test_givenCoreInactive_whenConfigOperatorSet_reverts] ; [test][test_givenInactive_whenUnauthorizedAndInvalid_reverts] |
| BLCORE-CONFIGURATOR-L04 | Fuzz ADMIN_ROLE holder | false | false | BurnerLoans_PolicyNotActive(BurnerLoansCore) | Function-specific effects on success; otherwise Unchanged | Covered: [test][test_givenCoreInactive_whenConfigOperatorSet_reverts] ; [test][test_givenInactive_whenUnauthorizedAndInvalid_reverts] |

## Inputs and upstream independence

| ID | Caller | Candidate / reported state | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-CONFIGURATOR-D01 | Fuzz ADMIN_ROLE holder | 0 | BurnerLoans_ZeroAddress() (required) | Unchanged | Covered: [test][test_whenZeroConfigOperatorSet_reverts] |
| BLCORE-CONFIGURATOR-D02 | Fuzz ADMIN_ROLE holder | Current address | ConfigOperator_Unchanged() | No manager writes, authority handoff or event | Covered: [test][test_givenSameConfigOperator_whenSelected_reverts] |
| BLCORE-CONFIGURATOR-D03 | Fuzz ADMIN_ROLE holder | Distinct nonzero address; independently fuzz active/enabled true/false | Success | No Config lifecycle getters; manager/pointer handoff exact | Covered: [test][test_givenCandidateLifecycleIndependent_whenConfigOperatorSet] |
| BLCORE-CONFIGURATOR-D04 | Fuzz ADMIN_ROLE holder | Distinct controller fixture rejects kernel()/facility()/ohm()/supportsInterface() reads | Success | No reverse compatibility reads | Covered: [test][test_givenCandidateGettersRevert_whenConfigOperatorSet] |

## Market handoff and atomic rollback

| ID | Caller | Pre-state / fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-CONFIGURATOR-P01 | Fuzz ADMIN_ROLE holder | Registered markets count 0,1,multiple; live loans and grants | Success | All managers next; Core authority next; Risk/Inventory/Payout operators untouched without any preparation on Risk; stable facility/market/position IDs and accounting | Covered: [test][test_givenCompatibleAuthority_whenConfigOperatorSet], [test][test_givenNoMarkets_whenConfigOperatorSelected], [test][test_givenMultipleMarkets_whenConfigOperatorSelected] |
| BLCORE-CONFIGURATOR-P02 | Fuzz ADMIN_ROLE holder | Late FLOAN manager handoff raises injected module error | Exact module error | Earlier manager changes, pointers and logs roll back | Covered: [test][test_givenLateManagerFailure_whenConfigOperatorSet_reverts] |

## Shared assertions

Old Config loses selected-address and FLOAN manager authority. New Config is constructor-bound to Core; deployment/setup is an upstream governance responsibility. No automatic queue migration. Selected and previously selected Payout contracts retain their local Payout-timelock authority, covering routing and recovery; Config handoff does not overwrite it.

## Independent downstream authorities

All market and Core handoff prerequisites pass. Retired BLCORE-CONFIGURATOR-P03 required Risk authority agreement; the following cases replace that rejected requirement.

| ID | Caller | Risk state / authority | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCORE-CONFIGURATOR-P04 | Fuzz ADMIN_ROLE holder | Risk operator zero or distinct from both outgoing and incoming Config; guarantee both classes | Success | Every registered market manager and Core pointer move to next Config; Risk operator/cache/oracle/age and Inventory/Payout operators unchanged | Covered: [test][test_givenIndependentRiskAuthority_whenConfigOperatorSet], [test][test_whenIndependentRiskAuthoritySeeds] |
| BLCORE-CONFIGURATOR-D05 | Fuzz ADMIN_ROLE holder | Risk authority getters/setters revert if called; independently fuzz Risk active/enabled true/false | Success | No Risk introspection or mutation; market handoff remains atomic | Covered: [test][test_givenRiskMetadataUnavailable_whenConfigOperatorSet] |

[test_givenCandidateGettersRevert_whenConfigOperatorSet]: setConfigOperator.t.sol#L137
[test_givenCandidateLifecycleIndependent_whenConfigOperatorSet]: setConfigOperator.t.sol#L122
[test_givenCompatibleAuthority_whenConfigOperatorSet]: setConfigOperator.t.sol#L89
[test_givenCoreInactive_whenConfigOperatorSet_reverts]: setConfigOperator.t.sol#L44
[test_givenIndependentRiskAuthority_whenConfigOperatorSet]: setConfigOperator.t.sol#L149
[test_givenLateManagerFailure_whenConfigOperatorSet_reverts]: setConfigOperator.t.sol#L212
[test_givenMultipleMarkets_whenConfigOperatorSelected]: setConfigOperator.t.sol#L261
[test_givenNoMarkets_whenConfigOperatorSelected]: setConfigOperator.t.sol#L241
[test_givenRiskMetadataUnavailable_whenConfigOperatorSet]: setConfigOperator.t.sol#L180
[test_givenSameConfigOperator_whenSelected_reverts]: setConfigOperator.t.sol#L67
[test_givenUnauthorized_whenConfigOperatorSet_reverts]: setConfigOperator.t.sol#L24
[test_whenIndependentRiskAuthoritySeeds]: setConfigOperator.t.sol#L204
[test_whenZeroConfigOperatorSet_reverts]: setConfigOperator.t.sol#L61

[test_givenInactive_whenUnauthorizedAndInvalid_reverts]: setConfigOperator.t.sol#L276
