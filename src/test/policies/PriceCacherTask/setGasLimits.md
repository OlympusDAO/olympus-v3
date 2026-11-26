# PriceCacherTask.setGasLimits coverage plan

Source [PriceCacherTask](../../../policies/PriceCacherTask.sol). Scope `PCACHER-GAS`.

An admin or price admin can update both gas limits. The task must be Kernel-active. Local pause does
not affect configuration, and the setter makes no cache calls. The limits cap the gas
forwarded to the task body and to each pair refresh, respectively. See [execute](execute.md)
for the behavior when an execution runs short of gas.

| ID | Caller | Local active | Local enabled | Input or condition | Outcome | Test |
| --- | --- | --- | --- | --- | --- | --- |
| PCACHER-GAS-A01 | Fuzz admins | true | true | Valid changed limits | Update and emit for both limits | Covered: [test][test_whenAdminSetsValidLimits_thenUpdatesBoth] |
| PCACHER-GAS-A02 | Fuzz callers with neither role | true | true | Valid limits | Reject with NotAuthorised and preserve both limits | Covered: [test][test_whenCallerLacksBothRoles_reverts] |
| PCACHER-GAS-A03 | Fuzz price admins who lack admin | true | true | Valid changed limits | Update and emit for both limits | Covered: [test][test_whenPriceAdminSetsValidLimits_thenUpdatesBoth] |
| PCACHER-GAS-L01 | Admin or price admin | true | false or re-enabled | Valid changed limits | Update both, preserve lifecycle | Covered: [paused admin][test_givenDisabled_whenAdminSetsLimits_thenUpdatesBoth], [paused price admin][test_givenDisabled_whenPriceAdminSetsLimits_thenUpdatesBoth], [re-enabled admin][test_givenReEnabled_whenAdminSetsLimits_thenUpdatesBoth], [re-enabled price admin][test_givenReEnabled_whenPriceAdminSetsLimits_thenUpdatesBoth] |
| PCACHER-GAS-L02 | Admin | false | both | Valid limits | Reject with PriceCacherTask_PolicyInactive and preserve both limits | Covered: [test][test_givenKernelInactive_whenSettingLimits_reverts], [both states][test_givenKernelInactive_whenSettingLimits_revertsInBothLocalStates] |
| PCACHER-GAS-L03 | Admin | reactivated | true | Valid changed limits | Update both | Covered: [test][test_givenKernelReactivated_whenAdminSetsLimits_thenUpdatesBoth] |
| PCACHER-GAS-N01 | Admin | true | true | Zero pair limit and otherwise valid execution limit | Reject with PriceCacherTask_InvalidGasLimits and preserve both limits | Covered: [test][test_whenLimitsLeaveInsufficientGasForAPair_revertsForBoundaries] |
| PCACHER-GAS-N02 | Admin | true | true | Execution limit at or below the pair limit plus the reserve | Reject with PriceCacherTask_InvalidGasLimits and preserve both limits | Covered: [fuzz][test_whenLimitsLeaveInsufficientGasForAPair_reverts], [boundaries][test_whenLimitsLeaveInsufficientGasForAPair_revertsForBoundaries] |
| PCACHER-GAS-P02 | Admin or price admin | true | true | Valid changes, including the smallest valid limits and maximum valid pair and execution limits | Getters report the supplied limits. GasLimitsSet reports both values | Covered: [admin][test_whenAdminSetsValidLimits_thenUpdatesBoth], [price admin][test_whenPriceAdminSetsValidLimits_thenUpdatesBoth], [boundaries][test_whenAdminSetsBoundaryLimits_thenUpdatesBoth] |
| PCACHER-GAS-P03 | Admin | true | true | Both limits unchanged | Same values and no events | Covered: [test][test_whenLimitsAreUnchanged_thenNoEvent] |

[test_givenDisabled_whenAdminSetsLimits_thenUpdatesBoth]: setGasLimits.t.sol#L71
[test_givenDisabled_whenPriceAdminSetsLimits_thenUpdatesBoth]: setGasLimits.t.sol#L78
[test_givenKernelInactive_whenSettingLimits_reverts]: setGasLimits.t.sol#L101
[test_givenKernelInactive_whenSettingLimits_revertsInBothLocalStates]: setGasLimits.t.sol#L117
[test_givenKernelReactivated_whenAdminSetsLimits_thenUpdatesBoth]: setGasLimits.t.sol#L123
[test_givenReEnabled_whenAdminSetsLimits_thenUpdatesBoth]: setGasLimits.t.sol#L85
[test_givenReEnabled_whenPriceAdminSetsLimits_thenUpdatesBoth]: setGasLimits.t.sol#L93
[test_whenAdminSetsBoundaryLimits_thenUpdatesBoth]: setGasLimits.t.sol#L50
[test_whenAdminSetsValidLimits_thenUpdatesBoth]: setGasLimits.t.sol#L16
[test_whenCallerLacksBothRoles_reverts]: setGasLimits.t.sol#L60
[test_whenLimitsAreUnchanged_thenNoEvent]: setGasLimits.t.sol#L152
[test_whenLimitsLeaveInsufficientGasForAPair_reverts]: setGasLimits.t.sol#L140
[test_whenLimitsLeaveInsufficientGasForAPair_revertsForBoundaries]: setGasLimits.t.sol#L130
[test_whenPriceAdminSetsValidLimits_thenUpdatesBoth]: setGasLimits.t.sol#L26
