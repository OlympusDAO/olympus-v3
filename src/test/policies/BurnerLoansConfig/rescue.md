# BurnerLoansConfig.rescue coverage plan

Scope: BLC's authorization and forwarding to BL. BLC = BurnerLoansConfig; BL = BurnerLoans. Bucket allocation and numeric boundaries belong to [BL rescue](../BurnerLoans/rescue.md). Facility initialization/binding belongs to [constructor](./constructor.t.sol) and [setFacility](./setFacility.t.sol).

BLC must be enabled and Kernel-active to forward either caller. If BLC/BLCT is disabled or inactive, admin recovery goes directly through active BL.

## Domains and assertions

- Admin = ADMIN_ROLE holder; Operator = current nonzero configOperator. Test these caller classes separately. Unauthorized callers include zero, emergency-only, burner_loans_admin-only and former operators, unless independently authorized.
- BLC must be locally enabled and Kernel-active; disablement or deactivation blocks forwarding. BL may also be disabled but must be Kernel-active. Default: both policies enabled and active, BLC selected as BL Configurator.
- Fixed successful request: token custody at BL=79, pending reserve=60 (reward=10, fees=20, seizure=30), destination balance=7; BL preview=19. BLC forwards exactly token/destination; BL pays 19, ending with custody=60 and destination=26.
- Success: exactly one BL AssetRescued and token Transfer; no BLC rescue event or token custody. Each debt/aggregate/index, BLC binding/operator and other balances/configuration stay unchanged. Compare BL preview with the independent expected amount.
- Unchanged: all those balances and state remain unchanged; no committed events. Forwarded errors retain exact revert data. BL destination errors use InvalidRescueDestination, including zero.
- Each row links to tests with reciprocal Scenarios comments.

## Authorization and lifecycle

Every success row uses the nonzero request above. L-01/L-02 establish each caller class; additional gate rows should run each class without testing dual-role accounts.

| ID | Caller | BLC local state | BLC Kernel membership | BL local state | BL Kernel membership | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- |
| L-01 | Admin | Enabled | Active | Enabled | Active | Forward request; pay 19; retain reserve 60 | Covered: [admin forwards rescue][test_givenConfigAndFacilityEnabled_whenAdminForwardsRescue], [rescue forwarded][test_givenPoliciesRestored_whenRescueForwarded] |
| L-02 | Operator | Enabled | Active | Enabled | Active | Forward request; pay 19; retain reserve 60 | Covered: [operator forwards rescue][test_givenConfigAndFacilityEnabled_whenOperatorForwardsRescue] |
| L-06 | Admin; Operator separately | Disabled | Active | Enabled/disabled | Active/inactive | NotEnabled(); no forwarding or payment | Covered: [admin forwards rescue][test_givenConfigDisabled_whenAdminForwardsRescue_reverts], [operator forwards rescue][test_givenConfigDisabled_whenOperatorForwardsRescue_reverts] |
| L-07 | Admin; Operator separately | Enabled | Inactive | Enabled/disabled | Active/inactive | BurnerLoansConfig_PolicyInactive(); Unchanged | Covered: [admin forwards rescue][test_givenConfigInactive_whenAdminForwardsRescue_reverts], [operator forwards rescue][test_givenConfigInactive_whenOperatorForwardsRescue_reverts] |
| L-08 | Admin; Operator separately | Disabled | Inactive | Enabled/disabled | Active/inactive | BurnerLoansConfig_PolicyInactive(); Unchanged | Covered: [admin forwards rescue][test_givenConfigDisabledAndInactive_whenAdminForwardsRescue_reverts], [operator forwards rescue][test_givenConfigDisabledAndInactive_whenOperatorForwardsRescue_reverts] |
| L-09 | Admin; Operator separately | Enabled | Active | Disabled | Active | Forward request; pay 19 | Covered: [admin forwards rescue][test_givenFacilityDisabled_whenAdminForwardsRescue], [operator forwards rescue][test_givenFacilityDisabled_whenOperatorForwardsRescue] |
| L-03 | Fuzz caller outside Admin/Operator | Enabled/disabled | Active/inactive | Enabled/disabled | Active/inactive | BurnerLoansConfig_UnauthorizedConfigOperator(caller); Unchanged | Covered: [fuzzed callers][test_givenLifecycleStates_whenCallerUnauthorized_reverts], [caller identities][test_givenUnauthorizedIdentities_whenSeeded_reverts] |
| L-04 | Admin | Enabled | Active | Enabled/disabled | Inactive | BurnerLoans_PolicyInactive(); Unchanged | Covered: [admin forwards rescue][test_givenFacilityInactive_whenAdminForwardsRescue_reverts] |
| L-05 | Operator | Enabled | Active | Enabled/disabled | Inactive | BurnerLoans_PolicyInactive(); Unchanged | Covered: [operator forwards rescue][test_givenFacilityInactive_whenOperatorForwardsRescue_reverts] |

Cross BLC/BL local disablement in grouped success checks while both policies remain active. Required order: caller authorization → BLC activity → BLC enablement → BL activity → input validation. BL preview remains an input/balance query even when forwarding is rejected.

Both BLC rescue functions require active Kernel membership. [The pending-payout plan](./rescuePendingPayout.md) covers the complete forwarding lifecycle cross-product.

## Forwarding outcomes

| ID | Caller | Request / state | BL preview | Execution / effects | Test |
| --- | --- | --- | --- | --- | --- |
| P-01 | Admin; Operator separately | Fixed positive request; include destination=owed keeper and unrelated destination | 19 | Exact forwarding and shared success assertions | Covered: [caller forwards][test_givenOwedOrUnrelatedDestination_whenEachCallerForwards] |
| P-02 | Admin; Operator separately | BL custody=reserve=60; transfer would reject if called | 0 | No-op; no transfer/rescue event; Unchanged | Covered: [caller forwards][test_givenCustodyAtOrBelowReserve_whenEachCallerForwards] |
| P-03 | Admin; Operator separately | BL custody=59 below reserve=60 | 0 | No-op; preserve custody 59 and reserve 60 | Covered: [caller forwards][test_givenCustodyAtOrBelowReserve_whenEachCallerForwards] |
| AUTH-01 | Admin; current/former Operator | Operator changed/revoked; fixed positive request | 19 | Admin/current nonzero operator pays 19; former operator rejected with BLC UnauthorizedConfigOperator(caller) | Covered: [former operator rejected][test_givenOperatorRotated_whenFormerOperatorRescues_reverts], [current authority][test_givenOperatorRotated_whenCurrentAuthorityRescues], [former operator rejected][test_givenOperatorRevoked_whenFormerOperatorOrZeroCallerRescues_reverts], [admin after revocation][test_givenOperatorRevoked_whenAdminRescues] |
| BIND-01 | Admin; Operator separately | Bound BL selects another Configurator | 19 | NotAuthorised(); Unchanged | Covered: [forwarded][test_givenFacilityConfiguratorChanged_whenForwarded_reverts] |

## Invalid inputs

Representative input failures prove exact forwarding with BLC and BL Kernel-active. The complete invalid-input domain is owned by BL's plan.

| ID | Caller | Input | BL preview / forwarded execution | Test |
| --- | --- | --- | --- | --- |
| I-01 | Admin; Operator separately | token=0 or nonzero address without code; destination valid | BurnerLoans_InvalidAsset(token); Unchanged | Covered: [token has no code][test_givenValidForwarder_whenTokenHasNoCode_reverts] |
| I-02 | Admin; Operator separately | destination=0 or BL; token valid | BurnerLoans_InvalidRescueDestination(destination); Unchanged | Covered: [destination is forbidden][test_givenValidForwarder_whenDestinationIsForbidden_reverts] |
| I-03 | Admin; Operator separately | Controlled balanceOf failure | Exact dependency error in preview and forwarded execution; Unchanged | Covered: [balance query reverts][test_givenValidForwarder_whenBalanceQueryReverts_reverts] |

## Transfers and callbacks

| ID | Caller | Interaction | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| TX-01 | Admin; Operator separately | Positive rescue; transfer reverts | Preview=19; bubble exact token error; Unchanged | Covered: [transfer fails][test_givenPositiveSurplus_whenTransferFails_reverts] |
| CB-01 | Admin; Operator separately | Authorized token reenters BLC rescue; caught/propagated | Nested BL ReentrancyGuardReentrantCall(); one outer payment or exact token CallbackFailed() and Unchanged | Covered: [caught fixtures][test_givenAuthorizedCallback_whenNestedForwardingFailureIsCaught], [propagated fixtures][test_givenAuthorizedCallback_whenNestedForwardingFailureIsPropagated_reverts] |

[test_givenConfigAndFacilityEnabled_whenAdminForwardsRescue]: ./rescue.t.sol#L24
[test_givenPoliciesRestored_whenRescueForwarded]: ./rescue.t.sol#L707
[test_givenConfigAndFacilityEnabled_whenOperatorForwardsRescue]: ./rescue.t.sol#L168
[test_givenConfigDisabled_whenAdminForwardsRescue_reverts]: ./rescue.t.sol#L58
[test_givenConfigDisabled_whenOperatorForwardsRescue_reverts]: ./rescue.t.sol#L202
[test_givenConfigInactive_whenAdminForwardsRescue_reverts]: ./rescue.t.sol#L85
[test_givenConfigInactive_whenOperatorForwardsRescue_reverts]: ./rescue.t.sol#L241
[test_givenConfigDisabledAndInactive_whenAdminForwardsRescue_reverts]: ./rescue.t.sol#L114
[test_givenConfigDisabledAndInactive_whenOperatorForwardsRescue_reverts]: ./rescue.t.sol#L282
[test_givenFacilityDisabled_whenAdminForwardsRescue]: ./rescue.t.sol#L41
[test_givenFacilityDisabled_whenOperatorForwardsRescue]: ./rescue.t.sol#L185
[test_givenLifecycleStates_whenCallerUnauthorized_reverts]: ./rescue.t.sol#L369
[test_givenUnauthorizedIdentities_whenSeeded_reverts]: ./rescue.t.sol#L404
[test_givenFacilityInactive_whenAdminForwardsRescue_reverts]: ./rescue.t.sol#L143
[test_givenFacilityInactive_whenOperatorForwardsRescue_reverts]: ./rescue.t.sol#L323
[test_givenOwedOrUnrelatedDestination_whenEachCallerForwards]: ./rescue.t.sol#L414
[test_givenCustodyAtOrBelowReserve_whenEachCallerForwards]: ./rescue.t.sol#L442
[test_givenOperatorRotated_whenFormerOperatorRescues_reverts]: ./rescue.t.sol#L454
[test_givenOperatorRotated_whenCurrentAuthorityRescues]: ./rescue.t.sol#L471
[test_givenOperatorRevoked_whenFormerOperatorOrZeroCallerRescues_reverts]: ./rescue.t.sol#L484
[test_givenOperatorRevoked_whenAdminRescues]: ./rescue.t.sol#L505
[test_givenFacilityConfiguratorChanged_whenForwarded_reverts]: ./rescue.t.sol#L515
[test_givenValidForwarder_whenTokenHasNoCode_reverts]: ./rescue.t.sol#L538
[test_givenValidForwarder_whenDestinationIsForbidden_reverts]: ./rescue.t.sol#L569
[test_givenValidForwarder_whenBalanceQueryReverts_reverts]: ./rescue.t.sol#L601
[test_givenPositiveSurplus_whenTransferFails_reverts]: ./rescue.t.sol#L617
[test_givenAuthorizedCallback_whenNestedForwardingFailureIsCaught]: ./rescue.t.sol#L636
[test_givenAuthorizedCallback_whenNestedForwardingFailureIsPropagated_reverts]: ./rescue.t.sol#L661
