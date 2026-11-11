# BurnerLoansConfig.rescue coverage plan

Implemented Core-only forwarding: [Config.rescue](../../../policies/burnerloans/BurnerLoansConfig.sol#L271) → [Core.rescue](../../../policies/burnerloans/BurnerLoansCore.sol#L1025). Custody recovery has its own directly bound timelock.

## Domains and notation

Fuzz permitted configuration caller: independently fuzz ADMIN_ROLE holder, selected nonzero configOperator without ADMIN_ROLE, and overlapping authority. Guarantee each class; vary caller independently of amounts, pointers and lifecycle. Config itself has no ADMIN grant on downstream contracts. Unauthorized fuzzing excludes all ADMIN holders and the selected nonzero configOperator.

Unchanged means Config, Core, FLOAN, Inventory and Custody balances/accounting/configuration remain at the snapshot; a reverted transaction commits no events. Each failed prerequisite is isolated with the remaining prerequisites satisfied.

Execution authorization precedes Config activity then enablement. previewRescue is permissionless and applies the same Config/Core lifecycle and destination checks without checking the viewer or Config forwarding authority. Core rescue requires Core active but permits Core disabled. Core selects the forwarding Config by address; it has no downstream ADMIN grant. Custody is untouched and its lifecycle is irrelevant.

## Authorization

| ID | Caller | Local active | Local enabled | Input | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLCRE-A01 | Fuzz permitted configuration caller | true | true | Valid request; downstream explicitly selects Config | Success through stored operator authority; no downstream ADMIN lookup/grant needed | Function-specific effects below | Covered: [test][test_givenAuthorizedCaller_whenCoreRescued] |
| BLCRE-A02 | Fuzz unauthorized caller | true | true | Valid and invalid request | Rescue: NotAuthorised(); preview: current recoverable balance | Unchanged | Covered: [test][test_whenCallerIsUnauthorized_thenPreviewSucceedsAndRescueReverts] |

## Config lifecycle

| ID | Caller | Local active | Local enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCRE-L01 | Fuzz permitted configuration caller | false | true | BurnerLoans_PolicyNotActive(BurnerLoansConfig) | Unchanged | Covered: [test][test_givenConfigInactiveEnabled_whenRescued_reverts] ; [test][test_givenInactive_whenUnauthorizedAndInvalid_reverts] |
| BLCRE-L02 | Fuzz permitted configuration caller | false | false | BurnerLoans_PolicyNotActive(BurnerLoansConfig) | Unchanged | Covered: [test][test_givenConfigInactiveDisabled_whenRescued_reverts] ; [test][test_givenInactive_whenUnauthorizedAndInvalid_reverts] |
| BLCRE-L03 | Fuzz permitted configuration caller | true | false | NotEnabled() | Unchanged | Covered: [test][test_givenConfigActiveDisabled_whenRescued_reverts] |

## Owner dependencies

Config active/enabled and correctly selected; valid token/destination.

| ID | Caller | Core active | Core enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCRE-I01 | Fuzz permitted configuration caller | true | true | Success | Unchanged on rejection; otherwise owner-only rescue | Covered: [test][test_givenAuthorizedCaller_whenCoreRescued] |
| BLCRE-I02 | Fuzz permitted configuration caller | true | false | Success | Unchanged on rejection; otherwise owner-only rescue | Covered: [test][test_givenCoreDisabled_whenRescued] |
| BLCRE-I03 | Fuzz permitted configuration caller | false | true | BurnerLoans_PolicyNotActive(BurnerLoansCore) from Core.rescue | Unchanged on rejection; otherwise owner-only rescue | Covered: [test][test_givenCoreInactive_whenRescued_reverts] |
| BLCRE-I04 | Fuzz permitted configuration caller | false | false | BurnerLoans_PolicyNotActive(BurnerLoansCore) from Core.rescue | Unchanged on rejection; otherwise owner-only rescue | Covered: [test][test_givenCoreInactive_whenRescued_reverts] |

## Invalid inputs

Admission passes; vary one forbidden identity per case.

| ID | Caller | Input | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCRE-I05 | Fuzz permitted configuration caller | token=0 | BurnerLoans_InvalidAsset(0) | Unchanged | Covered: [test][test_whenTokenIsZero_reverts] |
| BLCRE-I06 | Fuzz permitted configuration caller | Nonzero token without code | BurnerLoans_InvalidAsset(token) | Unchanged | Covered: [test][test_whenTokenIsNoCode_reverts] |
| BLCRE-I07 | Fuzz permitted configuration caller | destination=zero | BurnerLoans_InvalidRescueDestination(destination) | Unchanged | Covered: [test][test_whenDestinationIsZero_reverts] |
| BLCRE-I08 | Fuzz permitted configuration caller | destination=Core | BurnerLoans_InvalidRescueDestination(destination) | Unchanged | Covered: [test][test_whenDestinationIsCore_reverts] |
| BLCRE-I09 | Fuzz permitted configuration caller | destination=selected Custody | BurnerLoans_InvalidRescueDestination(destination) | Unchanged | Covered: [test][test_whenDestinationIsPayout_reverts] |
| BLCRE-I10 | Fuzz permitted configuration caller | destination=token | BurnerLoans_InvalidRescueDestination(destination) | Unchanged | Covered: [test][test_whenDestinationIsToken_reverts] |
| BLCRE-I11 | Fuzz permitted configuration caller | destination=selected Config | BurnerLoans_InvalidRescueDestination(destination) | Unchanged | Covered: [test][test_whenDestinationIsConfig_reverts] |
| BLCRE-I12 | Fuzz permitted configuration caller | destination=Kernel | BurnerLoans_InvalidRescueDestination(destination) | Unchanged | Covered: [test][test_whenDestinationIsKernel_reverts] |

## Balances and successful execution

| ID | Caller | Core ERC20 balance B | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCRE-N01 | Fuzz permitted configuration caller | B=0 | Success; no token call | No AssetRescued event; no other contract rescue call | Covered: [test][test_givenZeroCoreBalance_whenRescued] |
| BLCRE-N02 | Fuzz permitted configuration caller | Fuzz B in 1..MAX256; seed 1,MAX256 | Transfer entire B | Core balance becomes zero; destination +B; Core AssetRescued; Custody reserves/flags untouched | Covered: [test][test_givenAuthorizedCaller_whenCoreRescued], [test][test_whenMaximumBalanceRescued] |

## Transfer and authority failures

| ID | Caller | Fault | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCRE-D01 | Fuzz permitted configuration caller | Token reverts on destination transfer | MockRevertingTransferToken.TransferReverted(destination) | Owner balance/accounting unchanged; no cross-owner call | Covered: [test][test_givenTokenTransferFails_whenRescued] |
| BLCRE-D02 | Fuzz permitted configuration caller | Core selects another Config; forwarding Config has no ADMIN grant | Core.NotAuthorised() | No recovery; this does not require granting Config ADMIN | Covered: [test][test_givenCoreSelectsAnotherConfig_whenRescued_reverts] |
| BLCRE-D03 | Fuzz permitted configuration caller | Core settlement guard entered | ReentrancyGuardReentrantCall() | Unchanged | Covered: [test][test_givenRescueCallback_whenNestedRecoveryCaught], [test][test_givenRescueCallback_whenNestedRecoveryPropagated] |

## Transfer callbacks and reentrancy

Config/Core are active, Config enabled and selected, Core idle; positive rescue balance and valid destination. Callback has a permitted Config caller identity so a nested rescue reaches Core's guard. Custody is not involved in this Core-only route.

| ID | Outer caller | Token callback behavior | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- |
| BLCRE-C01 | Fuzz ADMIN-only, selected configOperator-only and overlap callers | Call Config.rescue again; catch nested rejection | Nested ReentrancyGuardReentrantCall(); outer rescue succeeds | Direct Core balance transferred exactly once; no Custody transfer or reserve change | Covered: [test][test_givenRescueCallback_whenNestedRecoveryCaught] |
| BLCRE-C02 | Fuzz same permitted caller family | Same nested route; propagate nested rejection | Exact propagated token error rejects outer rescue | Direct Core/destination balances and all earlier subcalls/logs roll back | Covered: [test][test_givenRescueCallback_whenNestedRecoveryPropagated] |

## Regression evidence and completion

Use [existing Config rescue tests](rescue.t.sol) for authorization, empty/nonempty balances, forbidden destinations and transfer rollback. Adapt expectations to one owner per call; do not claim the legacy combined path proves this Core-only forwarding API.

- [x] Implemented ownership: Config→Core only.
- [x] Adapt existing recovery tests and map full domains after focused validation.

## Forwarding authority and quote identity

| ID | Quote requester | Config active | Config enabled | Core selection | Preview / execution | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLCRE-A03 | Fuzz every address | true | true | Another Config selected; this Config has no ADMIN role | Quote current Core balance; execution through this Config still rejects downstream NotAuthorised() | Covered: [test][test_givenConfigDeselected_whenAnyViewerQuotesRecovery] |

[test_givenAuthorizedCaller_whenCoreRescued]: ./rescue.t.sol#L24
[test_whenCallerIsUnauthorized_thenPreviewSucceedsAndRescueReverts]: ./rescue.t.sol#L51
[test_givenConfigInactiveEnabled_whenRescued_reverts]: ./rescue.t.sol#L70
[test_givenConfigInactiveDisabled_whenRescued_reverts]: ./rescue.t.sol#L87
[test_givenConfigActiveDisabled_whenRescued_reverts]: ./rescue.t.sol#L105
[test_givenCoreDisabled_whenRescued]: ./rescue.t.sol#L122
[test_givenCoreInactive_whenRescued_reverts]: ./rescue.t.sol#L142
[test_whenTokenIsZero_reverts]: ./rescue.t.sol#L160
[test_whenTokenIsNoCode_reverts]: ./rescue.t.sol#L174
[test_whenDestinationIsZero_reverts]: ./rescue.t.sol#L188
[test_whenDestinationIsCore_reverts]: ./rescue.t.sol#L205
[test_whenDestinationIsPayout_reverts]: ./rescue.t.sol#L222
[test_whenDestinationIsToken_reverts]: ./rescue.t.sol#L239
[test_whenDestinationIsConfig_reverts]: ./rescue.t.sol#L256
[test_whenDestinationIsKernel_reverts]: ./rescue.t.sol#L273
[test_givenZeroCoreBalance_whenRescued]: ./rescue.t.sol#L290
[test_whenMaximumBalanceRescued]: ./rescue.t.sol#L308
[test_givenTokenTransferFails_whenRescued]: ./rescue.t.sol#L318
[test_givenCoreSelectsAnotherConfig_whenRescued_reverts]: ./rescue.t.sol#L336
[test_givenRescueCallback_whenNestedRecoveryCaught]: ./rescue.t.sol#L351
[test_givenRescueCallback_whenNestedRecoveryPropagated]: ./rescue.t.sol#L375
[test_givenConfigDeselected_whenAnyViewerQuotesRecovery]: ./rescue.t.sol#L398
[test_givenInactive_whenUnauthorizedAndInvalid_reverts]: rescue.t.sol#L416
