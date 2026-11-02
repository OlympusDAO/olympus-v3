# ERC7726OracleFactory.setPriceCache coverage plan

Source: [ERC7726OracleFactory](../../../../policies/price/ERC7726OracleFactory.sol), [IERC7726OracleFactory](../../../../policies/interfaces/price/IERC7726OracleFactory.sol).

The permitted caller holds ADMIN_ROLE. The fixture grants that role only to `admin`; unauthorized fuzzing excludes `admin` and includes address zero. A valid replacement advertises IPriceCache and reports the factory's Kernel. Cache activity and local enablement are deliberately not required for selection. Unchanged means the selected pointer and local lifecycle state are preserved and no logs commit. This action has no numeric inputs or token/accounting effects.

Own Kernel activity, local enablement and caller authorization precede unchanged-address rejection. Reject the current pointer before interface or Kernel probes, including after cache metadata drifts.

## Authorization

Local active=true and local enabled=true; the candidate differs unless specified.

| ID | Caller | Candidate | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| ERC7726-CACHE-A01 | ORACLE_MANAGER_ROLE without ADMIN_ROLE | Valid replacement | ROLES_RequireRole(ADMIN_ROLE) | Unchanged | Covered: [test][test_whenCallerIsOracleManager_reverts] |
| ERC7726-CACHE-A02 | Fuzz all callers excluding admin | Valid replacement | ROLES_RequireRole(ADMIN_ROLE) | Unchanged | Covered: [test][test_whenCallerIsNotAdmin_reverts] |
| ERC7726-CACHE-A03 | Fuzz all callers excluding admin | Current cache | ROLES_RequireRole(ADMIN_ROLE), before unchanged-address rejection | Unchanged | Covered: [test][test_whenCallerIsNotAdmin_whenPriceCacheUnchanged_reverts] |

## Lifecycle

The candidate is the current cache.

| ID | Caller | Local active | Local enabled | History | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ERC7726-CACHE-L01 | Fuzz all callers | true | false | Initially disabled | NotEnabled(), before authorization/equality | Unchanged | Covered: [test][test_givenDisabled_whenPriceCacheUnchanged_reverts] |
| ERC7726-CACHE-L02 | ADMIN_ROLE holder | true | true | Fuzz initially enabled or disabled then enabled again | ERC7726OracleFactory_UnchangedAddress(cache) | Unchanged; no cache probes | Covered: [test][test_whenPriceCacheUnchanged_reverts] |
| ERC7726-CACHE-L03 | ADMIN_ROLE holder | false | true | Enabled, then Kernel-deactivated | ERC7726OracleFactory_PolicyNotActive() before local enablement and caller checks | Unchanged; no cache probes | Covered: [test][test_givenInactive_whenPriceCacheUnchanged_revertsActivityFirst] |

## Invalid inputs

ADMIN_ROLE caller; local active=true, local enabled=true unless the test also varies activity.

| ID | Candidate | Execution | Effects | Test |
| --- | --- | --- | --- | --- |
| ERC7726-CACHE-I01 | Zero address | ERC7726OracleFactory_InvalidPriceCache(0) | Unchanged | Covered: [test][test_whenPriceCacheAddressIsZero_reverts] |
| ERC7726-CACHE-I02 | Contract lacking IPriceCache | ERC7726OracleFactory_InvalidPriceCache(candidate) | Unchanged | Covered: [test][test_whenPriceCacheDoesNotImplementIPriceCache_reverts] |
| ERC7726-CACHE-I03 | IPriceCache reporting a foreign Kernel | PolicyDependency_KernelMismatch(candidate,expectedKernel,reportedKernel) | Unchanged | Covered: [test][test_whenPriceCacheUsesDifferentKernel_reverts] |
| ERC7726-CACHE-I04 | Current cache; interface and Kernel getters revert if probed | ERC7726OracleFactory_UnchangedAddress(cache), before compatibility probes | Unchanged; zero interface/Kernel calls and no logs | Covered: [test][test_whenPriceCacheUnchanged_reverts] |

## Successful execution

ADMIN_ROLE caller; local active=true, local enabled=true.

| ID | History | Candidate | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| ERC7726-CACHE-P01 | Fuzz initially enabled or disabled then enabled again | Different compatible cache | Success | Pointer/getter selects replacement; exact PriceCacheSet(candidate) event | Covered: [test][test_whenCallerIsAdmin_setsPriceCache] |

[test_whenCallerIsAdmin_setsPriceCache]: ./setPriceCache.t.sol#L24
[test_whenPriceCacheAddressIsZero_reverts]: ./setPriceCache.t.sol#L38
[test_whenCallerIsOracleManager_reverts]: ./setPriceCache.t.sol#L50
[test_whenCallerIsNotAdmin_reverts]: ./setPriceCache.t.sol#L59
[test_whenPriceCacheDoesNotImplementIPriceCache_reverts]: ./setPriceCache.t.sol#L70
[test_whenPriceCacheUsesDifferentKernel_reverts]: ./setPriceCache.t.sol#L84
[test_whenPriceCacheUnchanged_reverts]: ./setPriceCache.t.sol#L100
[test_whenCallerIsNotAdmin_whenPriceCacheUnchanged_reverts]: ./setPriceCache.t.sol#L162
[test_givenDisabled_whenPriceCacheUnchanged_reverts]: ./setPriceCache.t.sol#L173

[test_givenInactive_whenPriceCacheUnchanged_revertsActivityFirst]: ./setPriceCache.t.sol#L130

## Guard-precedence regression

The following row maps the narrow competing-fault regression; it does not expand the other scenario domains.

| ID | Caller | Local active | Local enabled | Fixture and input domain | Exact result and precedence | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| ERC7726-CACHE-L04 | Any address, fuzz, without authorization exclusions | false | Fuzz false/true | Kernel-deactivated after optional local enablement; creation is enabled; Current selected `priceCache` address | `ERC7726OracleFactory_PolicyNotActive()` before local enablement, caller and action checks | Revert; no effects of the attempted action commit. Selected cache pointer is explicitly asserted unchanged. | Covered: [test][test_givenInactive_whenAnyCallerChangesFactory_revertsActivityFirst] |

[test_givenInactive_whenAnyCallerChangesFactory_revertsActivityFirst]: ./setPriceCache.t.sol#L192
