# BurnerLoansConfig.constructor coverage plan

The [constructor](../../../policies/burnerloans/BurnerLoansConfig.sol#L67) accepts `(Kernel, IBurnerLoansCore)` and stores Core immutably, deriving OHM from it. There is no unlinked Config phase or setFacility. Exposing core() through IBurnerLoansCoreBound instead of the former facility() getter is a planned interface update. Coverage remains recorded per row.

## Domains and notation

Deploy Core first. Its downstream pointers may be unset and it may be inactive/disabled when Config is constructed. Config's constructor validates identity, not operational readiness or selection as Core's controller. Module handles are initialized by Kernel activation/configureDependencies separately. Reverts leave no deployment or committed logs; constructor compatibility failures use the product-owned InvalidCore error, except that a readable foreign Kernel uses PolicyDependency_KernelMismatch(candidate,expectedKernel,reportedKernel).

Failed/malformed Core Kernel reads use PolicyDependency_InvalidDependency(candidate); required interface and OHM read failures use BurnerLoansConfig_InvalidCore(candidate). A successful canonical kernel() read that reports another Kernel is a separate mismatch, with expectedKernel equal to the constructor Kernel; it is not an InvalidCore metadata failure.

## Invalid Core and compatibility

| ID | Caller | Candidate / condition | Result | Test |
| --- | --- | --- | --- | --- |
| BLCC-I01 | Fuzz deployer | Core=0 | BurnerLoansConfig_InvalidCore(candidate) | Covered: [test][test_whenCoreIsZero_reverts] |
| BLCC-I02 | Fuzz deployer | Core nonzero EOA | BurnerLoansConfig_InvalidCore(candidate) | Covered: [test][test_whenCoreIsEOA_reverts] |
| BLCC-I03 | Fuzz deployer | Core missing IBurnerLoansCore | BurnerLoansConfig_InvalidCore(candidate) | Covered: [test][test_givenCoreMissingCoreInterface_whenDeployed_reverts] |
| BLCC-I04 | Fuzz deployer | Core missing IVersioned | BurnerLoansConfig_InvalidCore(candidate) | Covered: [test][test_givenCoreMissingVersionInterface_whenDeployed_reverts] |
| BLCC-I05 | Fuzz deployer | Core ERC165 reverts | BurnerLoansConfig_InvalidCore(candidate) | Covered: [test][test_givenRevertingERC165_whenDeployed_reverts] |
| BLCC-I06 | Fuzz deployer | Core ERC165 malformed | BurnerLoansConfig_InvalidCore(candidate) | Covered: [test][test_givenMalformedERC165_whenDeployed_reverts] |
| BLCC-I07 | Fuzz deployer | Core reports other Kernel | PolicyDependency_KernelMismatch(candidate,expectedKernel,reportedKernel) | Covered: [test][test_givenWrongKernel_whenDeployed_reverts] |
| BLCC-T01 | Fuzz deployer | Compatible Core ohm() getter reverts | BurnerLoansConfig_InvalidCore(candidate) | Covered: [test][test_givenRevertingOhm_whenDeployed_reverts] |
| BLCC-T02 | Any deployer | Core kernel() returns 0, 1, 31, 33, 64 or 65,536 bytes | PolicyDependency_InvalidDependency(candidate) | Covered: [test][test_givenMalformedCoreKernel_whenDeployed_reverts] |
| BLCC-T03 | Any deployer | Core ohm() returns 0, 1, 31, 33, 64 or 65,536 bytes | BurnerLoansConfig_InvalidCore(candidate) | Covered: [test][test_givenMalformedCoreOhm_whenDeployed_reverts] |

## Deployment lifecycle

All identity checks pass. Neither Config selection nor Core operational readiness is a constructor prerequisite.

| ID | Caller | Core active | Core enabled | Result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCC-L01 | Fuzz deployer | true | true | Success | Immutable Core/OHM; own disabled; configOperator=0 | Covered: [test][test_givenCoreActiveEnabled_whenDeployed] |
| BLCC-L02 | Fuzz deployer | true | false | Success | Same defaults; no enablement calls | Covered: [test][test_givenCoreActiveDisabled_whenDeployed] |
| BLCC-L03 | Fuzz deployer | false | true | Success | Same defaults; no activation calls | Covered: [test][test_givenCoreInactiveEnabled_whenDeployed] |
| BLCC-L04 | Fuzz deployer | false | false | Success | Same defaults; downstream pointers may be unset | Covered: [test][test_givenCoreInactiveDisabled_whenDeployed] |

## Construction assertions and legacy evidence

Assert immutable core() (the shared binding getter, replacing facility()), derived OHM, Kernel binding, disabled local state, seven-day grace period and initial inherited events. No caller grant, market, token balance or Core controller pointer changes. Test supportsInterface separately. Core later selecting this Config is an OCG operation, not a constructor side effect.

[Legacy constructor tests](constructor.t.sol) inform identity validation only. The removed `setFacility` tests are historical context. The former unlinked-success behavior is deliberately removed and is not coverage for this constructor.

- [x] Implement constructor binding and remove setFacility after plan review.
- [x] Implement focused constructor tests and map these rows.

[test_whenCoreIsZero_reverts]: ./constructor.t.sol#L36
[test_whenCoreIsEOA_reverts]: ./constructor.t.sol#L49
[test_givenCoreMissingCoreInterface_whenDeployed_reverts]: ./constructor.t.sol#L62
[test_givenCoreMissingVersionInterface_whenDeployed_reverts]: ./constructor.t.sol#L82
[test_givenRevertingERC165_whenDeployed_reverts]: ./constructor.t.sol#L99
[test_givenMalformedERC165_whenDeployed_reverts]: ./constructor.t.sol#L116
[test_givenWrongKernel_whenDeployed_reverts]: ./constructor.t.sol#L133
[test_givenRevertingOhm_whenDeployed_reverts]: ./constructor.t.sol#L152
[test_givenCoreActiveEnabled_whenDeployed]: ./constructor.t.sol#L197
[test_givenCoreActiveDisabled_whenDeployed]: ./constructor.t.sol#L207
[test_givenCoreInactiveEnabled_whenDeployed]: ./constructor.t.sol#L218
[test_givenCoreInactiveDisabled_whenDeployed]: ./constructor.t.sol#L229

[test_givenMalformedCoreKernel_whenDeployed_reverts]: ./constructor.t.sol#L165

[test_givenMalformedCoreOhm_whenDeployed_reverts]: ./constructor.t.sol#L181
