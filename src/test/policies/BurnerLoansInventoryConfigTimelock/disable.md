# BurnerLoansInventoryConfigTimelock.disable coverage plan

Source: [disable](../../../bases/EnablerV2.sol#L72). Concrete behavior: [_beforeDisable](../../../policies/burnerloans/BurnerLoansInventoryConfigTimelock.sol#L325).

## Scope and fixtures

TL is this timelock; I is its immutable Inventory. ADMIN and BL-admin mean `ADMIN_ROLE` and `BURNER_LOANS_ADMIN_ROLE`. I selects TL as its recovery controller; TL has no ADMIN grant. OHM amounts use 9 decimals. Unless varied, both policies are active/enabled, controller=TL, cached ROLES is initialized, and the shared recovery key is free. Unchanged means no committed logs or changes to queue metadata, payloads, keys, balances, provider claims, principal, debt cap or MINTR approval. Only burn/rescue are queued: the debt cap remains ADMIN-only directly on Inventory; `syncMintApproval` remains immediate BL-admin-only repair.

## Authorization

Local enabled, cached ROLES, empty payload.

| ID | Caller | Authority | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINCT-DISABLE-A01 | Fuzz ADMIN-only, EMERGENCY-only and overlap; seed each | Accepted transition roles | Success | enabled=false; timestamp=now; Disabled then Transition(caller,false,empty,now) | Covered: [test][test_givenPermittedCaller_whenDisabled_thenExactTransition]; [test][test_givenEachPermittedRole_whenDisabled_thenExactTransition] |
| BLINCT-DISABLE-A02 | Fuzz outside ADMIN and EMERGENCY holder sets; seed BL-admin-only | No grant | NotAuthorised() | Unchanged | Covered: [test][test_givenUnauthorizedCaller_whenDisabled_reverts]; [test][test_givenBurnerLoansAdminOnly_whenDisabled_reverts] |

## Lifecycle

Use ADMIN; disable does not require own Kernel activity or target readiness.

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLINCT-DISABLE-L01 | ADMIN | true | true | Success | Preserve queued work/key | Covered: [test][test_givenPermittedCaller_whenDisabled_thenExactTransition]; [test][test_givenEachPermittedRole_whenDisabled_thenExactTransition] |
| BLINCT-DISABLE-L02 | ADMIN | false | true | Success with cached ROLES | Remain Kernel-inactive | Covered: [test][test_givenPermittedCaller_whenDisabled_thenExactTransition]; [test][test_givenEachPermittedRole_whenDisabled_thenExactTransition] |
| BLINCT-DISABLE-L03 | ADMIN | true | false | NotEnabled() | Unchanged | Covered: [test][test_givenAlreadyDisabled_whenDisabled_reverts] |
| BLINCT-DISABLE-L04 | ADMIN | false | false | NotEnabled() | Unchanged | Covered: [test][test_givenAlreadyDisabled_whenDisabled_reverts] |

## Payload

Otherwise permitted transition.

| ID | Caller | Input / fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINCT-DISABLE-I01 | ADMIN | Nonempty bytes length 1..256; explicit encoded-zero seed | BurnerLoans_InvalidEnablerData() | Unchanged | Covered: [test][test_givenNonemptyData_whenDisabled_reverts]; [test][test_givenNonemptyPayloadBoundaries_whenCalled_reverts] |

## Dependency independence

Use ADMIN, local enabled; pending work exists. No Inventory view should be called.

| ID | Caller | Target fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLINCT-DISABLE-D01 | ADMIN | I inactive | Success | Pending work/key preserved; no Inventory reads | Covered: [test][test_givenInactiveInventory_whenDisabled_thenNoDependencyRead] |
| BLINCT-DISABLE-D02 | ADMIN | I disabled | Success | Pending work/key preserved; no Inventory reads | Covered: [test][test_givenPausedInventory_whenDisabled_thenNoDependencyRead] |
| BLINCT-DISABLE-D03 | ADMIN | I reports another Kernel | Success | Pending work/key preserved; no Inventory reads | Covered: [test][test_givenInventoryKernelMismatch_whenDisabled_thenNoDependencyRead] |
| BLINCT-DISABLE-D04 | ADMIN | Controller changed | Success | Pending work/key preserved; no Inventory reads | Covered: [test][test_givenControllerReplaced_whenDisabled_thenNoDependencyRead] |

- [x] Review these expectations.
- [x] Complete passing test mappings.

[test_givenPermittedCaller_whenDisabled_thenExactTransition]: ./disable.t.sol#L23
[test_givenEachPermittedRole_whenDisabled_thenExactTransition]: ./disable.t.sol#L145
[test_givenUnauthorizedCaller_whenDisabled_reverts]: ./disable.t.sol#L48
[test_givenBurnerLoansAdminOnly_whenDisabled_reverts]: ./disable.t.sol#L173
[test_givenAlreadyDisabled_whenDisabled_reverts]: ./disable.t.sol#L60
[test_givenNonemptyData_whenDisabled_reverts]: ./disable.t.sol#L69
[test_givenNonemptyPayloadBoundaries_whenCalled_reverts]: ./disable.t.sol#L133
[test_givenInactiveInventory_whenDisabled_thenNoDependencyRead]: ./disable.t.sol#L97
[test_givenPausedInventory_whenDisabled_thenNoDependencyRead]: ./disable.t.sol#L106
[test_givenInventoryKernelMismatch_whenDisabled_thenNoDependencyRead]: ./disable.t.sol#L115
[test_givenControllerReplaced_whenDisabled_thenNoDependencyRead]: ./disable.t.sol#L124
