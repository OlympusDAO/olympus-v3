# BurnerLoansRisk.disable coverage plan

Source: [disable](../../../bases/EnablerV2.sol#L72).

## Domains and notation

Scenario scope: `BLRISK-DISABLE`. ROLES is initialized through Kernel activation. Risk owns no loans or custody. A successful transition changes only isEnabled, lastTransitionAt and the inherited lifecycle events. Other configuration and all external state remain unchanged. enable/disable require empty bytes. reEnable has no payload and shares enable's activation checks after its own history/grace checks.

## Authorization

Subject has the state required for this transition; all other prerequisites are ready.

| ID | Caller | Expected result | Effects | Test |
| --- | --- | --- | --- | --- |
| BLRISK-DISABLE-A01 | Fuzz caller excluding every permitted identity listed below | NotAuthorised() | No transition/logs | Covered: [test][test_whenUnauthorizedCaller_reverts] |
| BLRISK-DISABLE-A02 | Fuzz ADMIN or EMERGENCY_ROLE holder; guarantee each exclusive class | Success | Exact inherited events/timestamp and local flag | Covered: [test][test_givenBrokenPricingDependencies_whenDisabled], [test][test_givenAdmin_whenTransition], [test][test_givenEmergency_whenTransition] |

## Local lifecycle

For inactive rows, activate then Kernel-deactivate Risk so cached ROLES remains available.

| ID | Caller | Local active | Local enabled | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLRISK-DISABLE-L01 | Fuzz ADMIN or EMERGENCY_ROLE holder; guarantee each exclusive class | true | false | NotEnabled() | Transition only on success | Covered: [test][test_givenAdminActive_whenAlreadyDisabled_reverts], [test][test_givenEmergencyActive_whenAlreadyDisabled_reverts] |
| BLRISK-DISABLE-L02 | Fuzz ADMIN or EMERGENCY_ROLE holder; guarantee each exclusive class | true | true | Success | Transition only on success | Covered: [test][test_givenBrokenPricingDependencies_whenDisabled], [test][test_givenAdmin_whenTransition], [test][test_givenEmergency_whenTransition] |
| BLRISK-DISABLE-L03 | Fuzz ADMIN or EMERGENCY_ROLE holder; guarantee each exclusive class | false | false | NotEnabled() | Transition only on success | Covered: [test][test_givenAdminInactive_whenAlreadyDisabled_reverts], [test][test_givenEmergencyInactive_whenAlreadyDisabled_reverts] |
| BLRISK-DISABLE-L04 | Fuzz ADMIN or EMERGENCY_ROLE holder; guarantee each exclusive class | false | true | Success | Transition only on success | Covered: [test][test_givenAdminInactive_whenTransition], [test][test_givenEmergencyInactive_whenTransition] |

## Input validation

Correct source transition state and permitted caller; Risk active, so earlier guards pass.

| ID | Caller | data | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-DISABLE-I01 | Fuzz ADMIN or EMERGENCY_ROLE holder; guarantee each exclusive class | Fuzz nonempty bytes length 1..256; seed 0x00,0x01,ABI-zero,256 bytes | BurnerLoans_InvalidEnablerData() | No transition/logs | Covered: [test][test_givenAdmin_whenDataIsNonempty_reverts], [test][test_givenAdmin_whenPayloadBoundarySeeds_reverts], [test][test_givenEmergency_whenDataIsNonempty_reverts], [test][test_givenEmergency_whenPayloadBoundarySeeds_reverts] |

- [x] Complete focused tests and exact mappings.

[test_givenAdminActive_whenAlreadyDisabled_reverts]: disable.t.sol#L70

[test_givenAdminInactive_whenAlreadyDisabled_reverts]: disable.t.sol#L81

[test_givenAdminInactive_whenTransition]: disable.t.sol#L92

[test_givenAdmin_whenDataIsNonempty_reverts]: disable.t.sol#L99

[test_givenAdmin_whenPayloadBoundarySeeds_reverts]: disable.t.sol#L112

[test_givenAdmin_whenTransition]: disable.t.sol#L63

[test_givenBrokenPricingDependencies_whenDisabled]: disable.t.sol#L18

[test_givenEmergencyActive_whenAlreadyDisabled_reverts]: disable.t.sol#L136

[test_givenEmergencyInactive_whenAlreadyDisabled_reverts]: disable.t.sol#L147

[test_givenEmergencyInactive_whenTransition]: disable.t.sol#L158

[test_givenEmergency_whenDataIsNonempty_reverts]: disable.t.sol#L165

[test_givenEmergency_whenPayloadBoundarySeeds_reverts]: disable.t.sol#L178

[test_givenEmergency_whenTransition]: disable.t.sol#L129

[test_whenUnauthorizedCaller_reverts]: disable.t.sol#L52
