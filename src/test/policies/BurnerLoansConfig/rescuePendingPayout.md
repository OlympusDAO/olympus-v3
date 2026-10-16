# BurnerLoansConfig.rescuePendingPayout scenario plan

BLC = BurnerLoansConfig; BL = its bound BurnerLoans facility. This plan covers BLC authorization and forwarding. [BL's plan](../BurnerLoans/rescuePendingPayout.md) owns payout mechanics. Existing suite: [rescuePendingPayout.t.sol](./rescuePendingPayout.t.sol). Grouped tests are mapped below.

BLC must be enabled and Kernel-active to forward either caller. When BLC or BLCT is disabled/inactive, admin recovery goes directly through BL, which must remain Kernel-active.

## Domains and shared assertions

- Permitted callers: admin and current nonzero configOperator, tested separately. Fuzz unauthorized callers, excluding all admins and the current nonzero operator; seed burner_loans_admin-only, emergency-only, former operator and payout recipient.
- Fixed fixture: BLC is BL's Configurator; BLC and BL are Kernel-active; keeper reward=10, fee=20 and seizure=30 token base units; custody=60; originalRecipient is the keeper; destination accepts tokens; amount=4. Use fixed role, token, recipient and destination addresses.
- BLC local enablement and Kernel membership are independent. Local disablement and Kernel deactivation both block forwarding. BL can be locally disabled, but must be Kernel-active.
- Success: expect one exact BL call with unchanged `(token,originalRecipient,destination,amount)`; destination balance +4, BL custody −4, remaining entitlement 6; reward debit event and one token transfer; fee/seizure and BLC configuration unchanged. BLC, keeper and Treasury receive no tokens.
- Unchanged: configuration, pending entitlement/reserve and balances unchanged; no committed rescue events. Authorization failure makes no BL call; dependency failure bubbles exact revert data.

## Authorization and lifecycle

Use the valid fixture and amount=0 to establish check precedence without duplicating BL's complete input matrix. Required order: caller authorization → BLC activity → BLC enabled → BL checks. Sentinel BL errors prove rejected callers and inactive BLC make no forwarding call. Each lifecycle axis is varied independently.

| ID | Caller | BLC local state | BLC Kernel membership | BL local state | BL Kernel membership | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| BLC-L01 | Admin; current operator | Enabled | Active | Enabled/disabled | Active | Valid request succeeds; invalid request bubbles BL error | Covered: [admin forwards pending payout][test_givenFacilityEnabled_whenAdminForwardsPendingPayout], [admin forwards pending payout][test_givenFacilityDisabled_whenAdminForwardsPendingPayout], [operator forwards pending payout][test_givenFacilityEnabled_whenOperatorForwardsPendingPayout], [operator forwards pending payout][test_givenFacilityDisabled_whenOperatorForwardsPendingPayout], [amount is zero][test_givenFacilityEnabled_whenAmountIsZero_reverts], [amount is zero][test_givenFacilityDisabled_whenAmountIsZero_reverts] |
| BLC-L02 | Any unauthorized caller | Enabled/disabled | Active/inactive | Enabled/disabled | Active/inactive | `BurnerLoansConfig_UnauthorizedConfigOperator(caller)` before forwarding; Unchanged | Covered: [fuzzed callers][test_givenConfigLifecycle_whenCallerIsUnauthorized_reverts], [caller identities][test_whenUnauthorizedIdentitiesAreSeeded_reverts] |
| BLC-L03 | Admin; current operator | Enabled | Active | Enabled/disabled | Inactive | `BurnerLoans_PolicyInactive()`, including with amount=0; Unchanged | Covered: [enabled config forwards][test_givenFacilityInactive_whenEnabledConfigForwards_reverts] |
| BLC-L04 | Former operator; new operator; admin | Enabled/disabled | Active | Enabled/disabled | Active | Former operator without admin fails L02; new nonzero operator and admin may forward only while BLC enabled; disabled BLC gives NotEnabled | Covered: [former operator forwards][test_givenOperatorRotated_whenFormerOperatorForwards_reverts], [current authority forwards][test_givenOperatorRotated_givenConfigEnabled_whenCurrentAuthorityForwards], [current authority forwards][test_givenOperatorRotated_givenConfigDisabled_whenCurrentAuthorityForwards_reverts], [former operator forwards][test_givenOperatorRevoked_whenFormerOperatorForwards_reverts], [admin forwards][test_givenOperatorRevoked_givenConfigEnabled_whenAdminForwards], [admin forwards][test_givenOperatorRevoked_givenConfigDisabled_whenAdminForwards_reverts] |
| BLC-L05 | Admin | Disabled | Active | Unbound | Unbound | NotEnabled() before forwarding; Unchanged | Covered: [admin forwards][test_givenFacilityUnset_whenAdminForwards_reverts] |
| BLC-L06 | Admin; current operator | Enabled/disabled | Inactive | Enabled/disabled | Active/inactive | `BurnerLoansConfig_PolicyInactive()` before forwarding, including invalid inputs; Unchanged | Covered: [authorized caller forwards][test_givenConfigInactive_whenAuthorizedCallerForwards_reverts] |
| BLC-L07 | Admin; current operator | Disabled | Active | Enabled/disabled | Active/inactive | NotEnabled() before forwarding, including amount=0; Unchanged | Covered: [authorized caller forwards][test_givenConfigDisabled_whenAuthorizedCallerForwards_reverts], [forwarded][test_givenFacilityInactive_givenConfigDisabled_whenForwarded_reverts], [disabled config forwards][test_givenFacilityConfiguratorChanged_whenDisabledConfigForwards_reverts] |

## Forwarding outcomes

| ID | Caller | Request / dependency state | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| BLC-P01 | Admin; current operator | Pending entitlement 10, amount=4; valid token/recipient/destination | Exact forwarding once; destination +4, custody −4, entitlement 6 | Covered: [admin forwards pending payout][test_givenFacilityEnabled_whenAdminForwardsPendingPayout], [admin forwards pending payout][test_givenFacilityDisabled_whenAdminForwardsPendingPayout], [operator forwards pending payout][test_givenFacilityEnabled_whenOperatorForwardsPendingPayout], [operator forwards pending payout][test_givenFacilityDisabled_whenOperatorForwardsPendingPayout] |
| BLC-B01 | Admin; current operator of outgoing BLC | BL selects another Configurator; both policies active; BLC enabled/disabled, BL disabled | Enabled BLC: `NotAuthorised()`; disabled BLC: NotEnabled(), including amount=0; Unchanged | Covered: [enabled config forwards][test_givenFacilityConfiguratorChanged_whenEnabledConfigForwards_reverts], [disabled config forwards][test_givenFacilityConfiguratorChanged_whenDisabledConfigForwards_reverts] |
| BLC-X01 | Admin; current operator | Valid request; token transfer raises a deterministic custom error | Bubble exact dependency error; Unchanged, including entitlement rollback | Covered: [token rejects transfer][test_whenTokenRejectsTransfer_reverts] |

## Invalid inputs

These representative cases prove BL rejects the forwarded request. Detailed BL boundaries and bucket combinations remain in its suite.

| ID | Caller | Invalid request | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| BLC-I01 | Admin; current operator | token=0 or nonzero address without code | `BurnerLoans_InvalidAsset(token)`; Unchanged | Covered: [token is zero][test_whenTokenIsZero_reverts], [token has no code][test_whenTokenHasNoCode_reverts] |
| BLC-I02 | Admin; current operator | destination=BL, token, BLC or Kernel; other inputs valid | `BurnerLoans_InvalidRescueDestination(destination)`; Unchanged | Covered: [destination is forbidden][test_whenDestinationIsForbidden_reverts] |
| BLC-I03 | Admin; current operator | destination=0; other inputs valid | `BurnerLoans_InvalidRescueDestination(0)`; Unchanged | Covered: [destination is zero][test_whenDestinationIsZero_reverts] |
| BLC-I04 | Admin; current operator | amount=0 | `BurnerLoans_ZeroAmount()`; Unchanged | Covered: [amount is zero][test_givenFacilityEnabled_whenAmountIsZero_reverts], [amount is zero][test_givenFacilityDisabled_whenAmountIsZero_reverts] |
| BLC-I05 | Admin; current operator | Pending entitlement 10, amount=11 | `BurnerLoans_InsufficientPendingPayout(token,11,10)`; Unchanged | Covered: [amount exceeds entitlement][test_whenAmountExceedsEntitlement_reverts] |
| BLC-I06 | Admin; current operator | originalRecipient=0; other inputs valid | `BurnerLoans_ZeroAddress()`; Unchanged | Covered: [recipient is zero][test_whenRecipientIsZero_reverts] |

[test_givenFacilityEnabled_whenAdminForwardsPendingPayout]: ./rescuePendingPayout.t.sol#L27
[test_givenFacilityDisabled_whenAdminForwardsPendingPayout]: ./rescuePendingPayout.t.sol#L41
[test_givenFacilityEnabled_whenOperatorForwardsPendingPayout]: ./rescuePendingPayout.t.sol#L57
[test_givenFacilityDisabled_whenOperatorForwardsPendingPayout]: ./rescuePendingPayout.t.sol#L71
[test_givenFacilityEnabled_whenAmountIsZero_reverts]: ./rescuePendingPayout.t.sol#L332
[test_givenFacilityDisabled_whenAmountIsZero_reverts]: ./rescuePendingPayout.t.sol#L347
[test_givenConfigLifecycle_whenCallerIsUnauthorized_reverts]: ./rescuePendingPayout.t.sol#L121
[test_whenUnauthorizedIdentitiesAreSeeded_reverts]: ./rescuePendingPayout.t.sol#L128
[test_givenFacilityInactive_whenEnabledConfigForwards_reverts]: ./rescuePendingPayout.t.sol#L189
[test_givenOperatorRotated_whenFormerOperatorForwards_reverts]: ./rescuePendingPayout.t.sol#L402
[test_givenOperatorRotated_givenConfigEnabled_whenCurrentAuthorityForwards]: ./rescuePendingPayout.t.sol#L431
[test_givenOperatorRotated_givenConfigDisabled_whenCurrentAuthorityForwards_reverts]: ./rescuePendingPayout.t.sol#L448
[test_givenOperatorRevoked_whenFormerOperatorForwards_reverts]: ./rescuePendingPayout.t.sol#L473
[test_givenOperatorRevoked_givenConfigEnabled_whenAdminForwards]: ./rescuePendingPayout.t.sol#L512
[test_givenOperatorRevoked_givenConfigDisabled_whenAdminForwards_reverts]: ./rescuePendingPayout.t.sol#L524
[test_givenFacilityUnset_whenAdminForwards_reverts]: ./rescuePendingPayout.t.sol#L610
[test_givenConfigInactive_whenAuthorizedCallerForwards_reverts]: ./rescuePendingPayout.t.sol#L145
[test_givenConfigDisabled_whenAuthorizedCallerForwards_reverts]: ./rescuePendingPayout.t.sol#L87
[test_givenFacilityInactive_givenConfigDisabled_whenForwarded_reverts]: ./rescuePendingPayout.t.sol#L208
[test_givenFacilityConfiguratorChanged_whenDisabledConfigForwards_reverts]: ./rescuePendingPayout.t.sol#L571
[test_givenFacilityConfiguratorChanged_whenEnabledConfigForwards_reverts]: ./rescuePendingPayout.t.sol#L546
[test_whenTokenRejectsTransfer_reverts]: ./rescuePendingPayout.t.sol#L384
[test_whenTokenIsZero_reverts]: ./rescuePendingPayout.t.sol#L239
[test_whenTokenHasNoCode_reverts]: ./rescuePendingPayout.t.sol#L257
[test_whenDestinationIsForbidden_reverts]: ./rescuePendingPayout.t.sol#L306
[test_whenDestinationIsZero_reverts]: ./rescuePendingPayout.t.sol#L288
[test_whenAmountExceedsEntitlement_reverts]: ./rescuePendingPayout.t.sol#L364
[test_whenRecipientIsZero_reverts]: ./rescuePendingPayout.t.sol#L277
