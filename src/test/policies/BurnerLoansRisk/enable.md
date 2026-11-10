# BurnerLoansRisk.enable coverage plan

Source: [enable](../../../bases/EnablerV2.sol#L52).

## Domains and notation

Scenario scope: `BLRISK-ENABLE`. ROLES is initialized through Kernel activation. Risk owns no loans or custody. A successful transition changes only isEnabled, lastTransitionAt and the inherited lifecycle events. Other configuration and all external state remain unchanged. enable/disable require empty bytes. reEnable has no payload and shares enable's activation checks after its own history/grace checks.

## Dependency validation contract

Risk validates its immutable Core interface and matching Kernel; Core activity and enablement and controller readiness do not gate Risk activation. Backing oracle is an ordinary calculator with interface/version checks. Optional cache needs IPriceCache/IEnabler/IVersioned and a matching Kernel; no numeric cache version is queried but may be inactive or disabled because PRICE is the fallback. Kernel modules use module-version checks, not Policy lifecycle checks.

Use the same compatibility/readiness predicates in enable and reEnable, following the [shared lifecycle guidance](../../../../.agents/skills/policy-lifecycle/SKILL.md). Invalid metadata uses the consumer-owned InvalidDependency error; a compatible unavailable required service uses PolicyDependency_NotActive(dependency). Preserve own-policy, authorization, controller, payload, grace and guard errors. Revalidate reachable drift without corrupting immutable storage or probing ignored recovery-state getters.

Compatibility error ownership: cache → `BurnerLoans_InvalidPriceCache(cache)`; oracle → `BurnerLoans_InvalidBackingOracle(oracle)`.

## Authorization

Subject has the state required for this transition; all other prerequisites are ready.

| ID | Caller | Expected result | Effects | Test |
| --- | --- | --- | --- | --- |
| BLRISK-ENABLE-A01 | Fuzz caller excluding every permitted identity listed below | ROLES_RequireRole(ADMIN_ROLE) | No transition/logs | Covered: [test][test_whenUnauthorizedCaller_reverts] |
| BLRISK-ENABLE-A02 | ADMIN_ROLE holder | Success | Exact inherited events/timestamp and local flag | Covered: [test][test_givenAdmin_whenTransition] |

## Local lifecycle

For inactive rows, activate then Kernel-deactivate Risk so cached ROLES remains available.

| ID | Caller | Local active | Local enabled | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLRISK-ENABLE-L01 | ADMIN_ROLE holder | true | false | Success | Transition only on success | Covered: [test][test_givenAdmin_whenTransition] |
| BLRISK-ENABLE-L02 | ADMIN_ROLE holder | true | true | NotDisabled() | Transition only on success | Covered: [test][test_givenAdminActive_whenAlreadyEnabled_reverts] |
| BLRISK-ENABLE-L03 | ADMIN_ROLE holder | false | false | BurnerLoans_PolicyNotActive(Risk) | Transition only on success | Covered: [test][test_givenAdminInactive_whenTransition_reverts] |
| BLRISK-ENABLE-L04 | ADMIN_ROLE holder | false | true | NotDisabled() | Transition only on success | Covered: [test][test_givenAdminInactive_whenAlreadyEnabled_reverts] |

## Input validation

Correct source transition state and permitted caller; Risk active, so earlier guards pass.

| ID | Caller | data | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-ENABLE-I01 | ADMIN_ROLE holder | Fuzz nonempty bytes length 1..256; seed 0x00,0x01,ABI-zero,256 bytes | BurnerLoans_InvalidEnablerData() | No transition/logs | Covered: [test][test_givenAdmin_whenDataIsNonempty_reverts], [test][test_givenAdmin_whenPayloadBoundarySeeds_reverts] |

## Direct dependency compatibility

The Core binding must expose IBurnerLoansCore and report the same Kernel. Core readiness, selected configOperator readiness and market population are not activation prerequisites. Modules are supplied by Kernel activation. Cache may be inactive or disabled because direct PRICE remains available.

| ID | Caller | Dependency / fault | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-ENABLE-D01 | ADMIN_ROLE holder | Backing oracle no longer supports its interface | BurnerLoans_InvalidBackingOracle(oracle) | No transition/logs | Covered: [test][test_givenAdminOracleInterface_whenTransition_reverts] |
| BLRISK-ENABLE-D02 | ADMIN_ROLE holder | Nonzero cache loses required interfaces | BurnerLoans_InvalidPriceCache(cache) | No transition/logs | Covered: [test][test_givenAdminCacheInterface_whenTransition_reverts] |
| BLRISK-ENABLE-D03 | ADMIN_ROLE holder | Nonzero cache reports another Kernel | PolicyDependency_KernelMismatch(cache,expectedKernel,reportedKernel) | No transition/logs | Covered: [test][test_givenAdminCacheKernel_whenTransition_reverts] |
| BLRISK-ENABLE-D04 | ADMIN_ROLE holder | Compatible optional cache; independently fuzz active/enabled and guarantee all four states | Success | PRICE fallback remains available | Covered: [test][test_givenAdminCache11_whenTransition], [test][test_givenAdminCache10_whenTransition], [test][test_givenAdminCache01_whenTransition], [test][test_givenAdminCache00_whenTransition] |
| BLRISK-ENABLE-D05 | ADMIN_ROLE holder | Restore failed dependency and retry same transition | Success | No stale failed state; exact lifecycle fields/events | Covered: [test][test_givenAdmin_whenDependencyRestored] |

- [x] Complete focused tests and exact mappings.

## Core compatibility acceptance criteria

Constructor and activation share the same interface and Kernel validator. Interface rejection precedes Kernel probing. Failed activation preserves lifecycle fields, configuration, accounting and events; restoring compatibility permits retry. Core need not be active or enabled. Existing authorization, settlement and grace guards retain their order. No numeric action inputs, new accounting or token transfers are introduced. Existing lifecycle, authorization and grace matrices remain applicable.

| ID | Core condition | Expected result | Effects | Test |
| --- | --- | --- | --- | --- |
| BLRISK-ENABLE-K03 | Kernel getter returns short, oversized or noncanonical ABI data; fuzz non-32-byte responses and seed lengths 0,1,31,33,64 plus MAX256 word | PolicyDependency_InvalidDependency(Core) | Paused state and history preserved; restoration permits retry | Covered: [test][test_givenMalformedCoreKernel_whenActivated_revertsThenRestored]; [test][test_givenMalformedCoreKernelBoundaries_whenActivated_revertsThenRestored] |
| BLRISK-ENABLE-K01 | Core reports another Kernel | PolicyDependency_KernelMismatch(Core,expectedKernel,reportedKernel) | Paused state and history preserved; restoration permits retry | Covered: [test][test_givenDifferentCoreKernel_whenActivated_revertsThenRestored] |
| BLRISK-ENABLE-K02 | Core Kernel getter reverts | PolicyDependency_InvalidDependency(Core) | Paused state and history preserved; restoration permits retry | Covered: [test][test_givenRevertingCoreKernel_whenActivated_revertsThenRestored] |
| BLRISK-ENABLE-I20 | Missing Core interface support/response | BurnerLoansRisk_InvalidCore(Core) | Paused state and history preserved; restoration permits retry | Covered: [test][test_givenMissingCoreInterface_whenActivated_revertsThenRestored] |
| BLRISK-ENABLE-I21 | Reverting Core interface support/response | BurnerLoansRisk_InvalidCore(Core) | Paused state and history preserved; restoration permits retry | Covered: [test][test_givenRevertingCoreInterface_whenActivated_revertsThenRestored] |
| BLRISK-ENABLE-I22 | Malformed Core interface support/response | BurnerLoansRisk_InvalidCore(Core) | Paused state and history preserved; restoration permits retry | Covered: [test][test_givenMalformedCoreInterface_whenActivated_revertsThenRestored] |
| BLRISK-ENABLE-K05 | Same-Kernel compatible Core; all four active/enabled combinations | Success without Core readiness probes | Exact normal success; other state preserved | Covered: [test][test_givenCoreLifecycle_whenCompatible]; [test][test_whenCoreLifecycleSeeds] |

[test_givenAdminActive_whenAlreadyEnabled_reverts]: enable.t.sol#L63

[test_givenAdminCache00_whenTransition]: enable.t.sol#L249

[test_givenAdminCache01_whenTransition]: enable.t.sol#L234

[test_givenAdminCache10_whenTransition]: enable.t.sol#L219

[test_givenAdminCache11_whenTransition]: enable.t.sol#L204

[test_givenAdminCacheInterface_whenTransition_reverts]: enable.t.sol#L150

[test_givenAdminCacheKernel_whenTransition_reverts]: enable.t.sol#L178

[test_givenAdminInactive_whenAlreadyEnabled_reverts]: enable.t.sol#L72

[test_givenAdminInactive_whenTransition_reverts]: enable.t.sol#L83

[test_givenAdminOracleInterface_whenTransition_reverts]: enable.t.sol#L126

[test_givenAdmin_whenDataIsNonempty_reverts]: enable.t.sol#L94

[test_givenAdmin_whenDependencyRestored]: enable.t.sol#L264

[test_givenAdmin_whenPayloadBoundarySeeds_reverts]: enable.t.sol#L107

[test_givenAdmin_whenTransition]: enable.t.sol#L56

[test_whenUnauthorizedCaller_reverts]: enable.t.sol#L45

[test_givenMalformedCoreKernel_whenActivated_revertsThenRestored]: enable.t.sol#L283

[test_givenMalformedCoreKernelBoundaries_whenActivated_revertsThenRestored]: enable.t.sol#L300

[test_givenDifferentCoreKernel_whenActivated_revertsThenRestored]: enable.t.sol#L326

[test_givenRevertingCoreKernel_whenActivated_revertsThenRestored]: enable.t.sol#L343

[test_givenMissingCoreInterface_whenActivated_revertsThenRestored]: enable.t.sol#L359

[test_givenRevertingCoreInterface_whenActivated_revertsThenRestored]: enable.t.sol#L378

[test_givenMalformedCoreInterface_whenActivated_revertsThenRestored]: enable.t.sol#L400

[test_givenCoreLifecycle_whenCompatible]: enable.t.sol#L434

[test_whenCoreLifecycleSeeds]: enable.t.sol#L443
