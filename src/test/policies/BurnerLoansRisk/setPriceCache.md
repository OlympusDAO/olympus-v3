# BurnerLoansRisk.setPriceCache coverage plan

Source: [setPriceCache](../../../policies/burnerloans/BurnerLoansRisk.sol#L581). Coverage is recorded in the Test column; legacy references alone do not prove the rewritten API.

## Domains and notation

Scenario scope: `BLRISK-PRICE-CACHE` identifies this contract/function.

Governance uses Risk's Kernel-resolved ROLES. Risk must be active; ADMIN may replace pricing addresses while paused to repair the service. A nonzero cache must advertise IPriceCache, IEnabler and IVersioned and report the same Kernel. Risk does not query VERSION(). This optional shared service has no Core binding; PRICE fallback deliberately allows binding a cache that is inactive or disabled. Unlike required Core services, candidate readiness is assessed when the cache is used.

Use the [shared scenario guidance](../../../../.agents/skills/solidity-test-scenarios/SKILL.md) for numeric maxima, identity partitions, exact revert data, rollback and independent expected results.

## Local policy lifecycle

All inputs and required services are otherwise valid. Earlier local transition/authorization guards follow concrete source ordering.

| ID | Caller | Local active | Local enabled | Expected execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLRISK-PRICE-CACHE-L01 | ADMIN_ROLE holder | true | true | Same valid function result | No changes on rejection | Covered: [test][test_givenEnabled_whenDependencyChanges] |
| BLRISK-PRICE-CACHE-L02 | ADMIN_ROLE holder | true | false | Same valid function result | No changes on rejection | Covered: [test][test_givenDisabled_whenDependencyChanges] |
| BLRISK-PRICE-CACHE-L03 | ADMIN_ROLE holder | false | true | BurnerLoans_PolicyNotActive(Risk) | No changes on rejection | Covered: [test][test_givenInactive_whenDependencyChanges_reverts] |
| BLRISK-PRICE-CACHE-L04 | ADMIN_ROLE holder | false | false | BurnerLoans_PolicyNotActive(Risk) | No changes on rejection | Covered: [test][test_givenInactiveAndDisabled_whenDependencyChanges_reverts] |

## Authorization

Fixed for this table: Accounting / events: Unchanged; no committed logs.

| ID | Caller | Inputs / competing fault | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLRISK-PRICE-CACHE-A01 | Fuzz callers excluding ADMIN_ROLE holders | Caller lacks ADMIN; fuzz all callers excluding every ADMIN holder, including selected Config without ADMIN | ROLES_RequireRole(ADMIN_ROLE) | Covered: [test][test_whenUnauthorizedCaller_reverts] |

## Dependency compatibility

Fixed for this table: Accounting / events: Unchanged; no committed logs.

| ID | Caller | Dependency / binding condition | Execution / return | Test |
| --- | --- | --- | --- | --- |
| BLRISK-PRICE-CACHE-D01 | ADMIN_ROLE holder | ADMIN; major=1; reported Kernel differs | PolicyDependency_KernelMismatch(cache,expectedKernel,reportedKernel) | Covered: [test][test_whenKernelMismatches_reverts] |

## Invalid inputs

| ID | Caller | Invalid parameter | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-PRICE-CACHE-I01 | ADMIN_ROLE holder | ADMIN; cache=0 | Clear and emit PriceCacheSet(0) | No Core config or snapshot mutation | Covered: [test][test_whenCleared] |
| BLRISK-PRICE-CACHE-I02 | ADMIN_ROLE holder | ADMIN; IPriceCache absent | BurnerLoans_InvalidPriceCache(cache) | Unchanged; no committed logs | Covered: [test][test_whenMissingCacheInterface_reverts] |
| BLRISK-PRICE-CACHE-I03 | ADMIN_ROLE holder | ADMIN; IPriceCache present but IEnabler absent | BurnerLoans_InvalidPriceCache(cache) | Unchanged; no committed logs | Covered: [test][test_whenMissingEnabler_reverts] |
| BLRISK-PRICE-CACHE-I04 | ADMIN_ROLE holder | Nonzero EOA | BurnerLoans_InvalidPriceCache(cache) | Unchanged; no committed logs | Covered: [test][test_whenEoa_reverts] |
| BLRISK-PRICE-CACHE-I05 | ADMIN_ROLE holder | IPriceCache/IEnabler supported; IVersioned not advertised | BurnerLoans_InvalidPriceCache(cache) | Unchanged; no committed logs | Covered: [test][test_whenMissingVersionInterface_reverts] |
| BLRISK-PRICE-CACHE-I06 | ADMIN_ROLE holder | ERC165 reverts | BurnerLoans_InvalidPriceCache(cache) | Unchanged; no committed logs | Covered: [test][test_whenRevertingERC165_reverts] |
| BLRISK-PRICE-CACHE-I07 | ADMIN_ROLE holder | ERC165 returns malformed data | BurnerLoans_InvalidPriceCache(cache) | Unchanged; no committed logs | Covered: [test][test_whenMalformedERC165_reverts] |

Numeric cache versions and their getters are not part of admission; the former P01 and P02 numeric-version/getter requirements are retired.

| ID | Caller | Cache compatibility | Expected result | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-PRICE-CACHE-P10 | Fuzz ADMIN_ROLE holder | Required IPriceCache/IEnabler/IVersioned interfaces and matching Kernel; VERSION() reverts | Store and emit PriceCacheSet(cache) | No version lookup | Covered: [test][test_givenVersionGetterReverts_whenSelected] |

## Successful execution

| ID | Caller | Operation / pre-state | Execution / return | Accounting / events | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-PRICE-CACHE-P03 | ADMIN_ROLE holder | ADMIN; kernel getter reverts | PolicyDependency_InvalidDependency(cache) | Unchanged; no committed logs | Covered: [test][test_whenRevertingKernel_reverts], [test][test_whenMalformedKernel_reverts], [test][test_whenNoncanonicalKernel_reverts] |
| BLRISK-PRICE-CACHE-P04 | ADMIN_ROLE holder | ADMIN; compatible cache active=true; enabled=true | Store and emit PriceCacheSet(cache) | Installation has no activity/enabled gate; snapshot behavior checked separately | Covered: [test][test_givenCache11_whenSelected] |
| BLRISK-PRICE-CACHE-P05 | ADMIN_ROLE holder | ADMIN; compatible cache active=true; enabled=false | Store and emit PriceCacheSet(cache) | Installation has no activity/enabled gate; snapshot behavior checked separately | Covered: [test][test_givenCache10_whenSelected] |
| BLRISK-PRICE-CACHE-P06 | ADMIN_ROLE holder | ADMIN; compatible cache active=false; enabled=true | Store and emit PriceCacheSet(cache) | Installation has no activity/enabled gate; snapshot behavior checked separately | Covered: [test][test_givenCache01_whenSelected] |
| BLRISK-PRICE-CACHE-P07 | ADMIN_ROLE holder | ADMIN; compatible cache active=false; enabled=false | Store and emit PriceCacheSet(cache) | Installation has no activity/enabled gate; snapshot behavior checked separately | Covered: [test][test_givenCache00_whenSelected] |
| BLRISK-PRICE-CACHE-P08 | ADMIN_ROLE holder | ADMIN; same compatible pointer | BurnerLoans_UnchangedAddress(candidate) | Unchanged; no setter event | Covered: [test][test_givenCache_whenUnchanged_reverts] |

## Same contract address

ADMIN-only code-address selection: submitting the current address must revert, including zero when the optional dependency is already unset. Implemented equality rejection precedes dependency reads and event emission.

| ID | Caller | Input | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLRISK-PRICE-CACHE-P09 | Fuzz ADMIN_ROLE holder | Optional cache is already unset; candidate=0 | BurnerLoans_UnchangedAddress(0) | Unchanged; no downstream validation or events | Covered: [test][test_givenNoCache_whenUnchanged_reverts] |

[test_givenCache00_whenSelected]: setPriceCache.t.sol#L238

[test_givenCache01_whenSelected]: setPriceCache.t.sol#L227

[test_givenCache10_whenSelected]: setPriceCache.t.sol#L216

[test_givenCache11_whenSelected]: setPriceCache.t.sol#L205

[test_givenCache_whenUnchanged_reverts]: setPriceCache.t.sol#L249

[test_givenDisabled_whenDependencyChanges]: setPriceCache.t.sol#L52

[test_givenEnabled_whenDependencyChanges]: setPriceCache.t.sol#L47

[test_givenInactiveAndDisabled_whenDependencyChanges_reverts]: setPriceCache.t.sol#L67

[test_givenInactive_whenDependencyChanges_reverts]: setPriceCache.t.sol#L59

[test_givenNoCache_whenUnchanged_reverts]: setPriceCache.t.sol#L267

[test_givenVersionGetterReverts_whenSelected]: setPriceCache.t.sol#L95

[test_whenCleared]: setPriceCache.t.sol#L182

[test_whenEoa_reverts]: setPriceCache.t.sol#L177

[test_whenKernelMismatches_reverts]: setPriceCache.t.sol#L187

[test_whenMalformedERC165_reverts]: setPriceCache.t.sol#L123

[test_whenMalformedKernel_reverts]: setPriceCache.t.sol#L149

[test_whenMissingCacheInterface_reverts]: setPriceCache.t.sol#L83

[test_whenMissingEnabler_reverts]: setPriceCache.t.sol#L89

[test_whenMissingVersionInterface_reverts]: setPriceCache.t.sol#L107

[test_whenNoncanonicalKernel_reverts]: setPriceCache.t.sol#L161

[test_whenRevertingERC165_reverts]: setPriceCache.t.sol#L113

[test_whenRevertingKernel_reverts]: setPriceCache.t.sol#L133

[test_whenUnauthorizedCaller_reverts]: setPriceCache.t.sol#L75
