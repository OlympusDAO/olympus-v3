# BurnerLoansRiskConfigTimelock.constructor scenario plan

Source: [constructor](../../../policies/burnerloans/BurnerLoansRiskConfigTimelock.sol#L62).

Source precedents: [directly bound Payout queue](../../../policies/burnerloans/BurnerLoansPayoutConfigTimelock.sol#L67), [paused cancellation](../../../policies/deposits/DepositManagerConfigTimelock.sol#L582), [shared queue](../../../policies/utils/TimelockBatchQueue.sol#L115), [configuration commitments](../../../policies/utils/ConfigTimelockBatchQueue.sol#L162).

BLRCT is implemented with the interface details below. K is this queue's Kernel; T is the immutable Risk target. Risk's Core binding is not a target-discovery route and is not probed by this queue. Proposer classes are ADMIN-only, BLA-only, and their overlap; fuzz independently and guarantee each. Unauthorized proposers exclude all holders of either role. ADMIN target authority remains independent of queue authority. The queue receives no ADMIN grant or FLOAN write permission.

Initial delay D=86400 seconds; supported delay domain 86400..2592000 inclusive; execution window W=259200 seconds. There is no public delay setter. Times Q,E=Q+D,X=E+W are uint48; action IDs are uint64. Default queue and T are active/enabled, same K, T.configOperator()==BLRCT; ROLES initialized. Unchanged means all queue IDs/records/payloads/pre-state hashes/key owners, target configuration, market/position state, earned/pending rewards, balances, allowances and committed logs unchanged.

Product errors in IBurnerLoansRiskConfigTimelock: `BurnerLoansRiskTimelock_InvalidRisk(address risk)`, `BurnerLoansRiskTimelock_NotController()`, `BurnerLoansRiskTimelock_SubActionCallFailed(bytes4 selector)`. Own inactivity reuses `BurnerLoans_PolicyNotActive(BLRCT)`; subject pause uses IEnabler.NotEnabled(). PolicyDependency errors and status-read ABI rules are inherited unchanged: kernel()/isEnabled() require one canonical ABI word; short, trailing, dirty, or reverted responses reject with the shared invalid-dependency error. A canonical disabled status is an availability failure. Ordinary queue guard order is own activity→own enablement→proposer→target compatibility/readiness→operator selection→action validation; execute/cancel retain the shared base's earlier existence/terminal/time checks. Setting-specific errors come from Risk validation or equivalent canonical queue checks as specified per action.

Each global setting has one local key, each referrer one membership key shared by add/remove. Use localKey=keccak256(abi.encode(settingSelector)) for percentage/age, and keccak256(abi.encode(setReferrerAllowed.selector,referrer)) for membership. scopedKey=keccak256(abi.encode(T,localKey)) follows ConfigTimelockKeyLib. Commit destination T and stateHash=keccak256(abi.encode(selectedOperator,currentRelevantValue)), with the value encoded at its declared uint16/bool/uint48 type; never include live debt/custody balances. These exact encodings support independently constructed test expectations. Execution rechecks each sub-action against its committed state immediately before dispatch. Config/old Core may be independently paused/inactive without affecting this direct route. All getters in a function's rows are permissionless and read-only.

Scenario scope: `BLRCT-CONSTRUCTOR`. Constructor accepts Kernel K and Risk T. Initial grace period follows LoanParameters (currently seven days); initial local state is disabled with lastTransitionAt=0 and nextActionId=1. R21,R25; AE28.

Review status: approved for implementation; scenario review completed. Rows are mapped to implemented tests below. Coverage records the stated domains; execution results are reported separately.

Compatibility advertisement uses a bounded 30,000-gas probe with a 33-byte return cap. ERC165 must advertise true, 0xffffffff false, and each consumed interface true; every result must be exactly one canonical boolean word. This target-local check leaves shared libraries and other timelocks unchanged.

## Compatibility and startup

Deployer is unrestricted; constructor does not resolve ROLES or require either Policy to be activated, enabled or selected.

| ID | Caller | Target / metadata | Risk active | Risk enabled | Risk operator | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BLRCT-CONSTRUCTOR-P01 | Fuzz deployer | Deployed T supports consumed Risk, IConfigOperator, IEnabler interfaces; canonical K | Fuzz false/true | Fuzz false/true | Zero, future queue, another operator; seed each | Success | risk()==T immutable; K stored; D=86400,W=259200; disabled,transition0,id1; no module writes | Covered: [test_whenCompatibleTarget][test_whenCompatibleTarget] |
| BLRCT-CONSTRUCTOR-I01 | Fuzz deployer | T=zero, EOA, or contract missing each required interface; seed separately | Not read | Not read | Not read | BurnerLoansRiskTimelock_InvalidRisk(T) | No deployment or external configuration changes | Covered: [test_whenZeroOrEOATarget_reverts][test_whenZeroOrEOATarget_reverts] |
| BLRCT-CONSTRUCTOR-I02 | Fuzz deployer | Required interface metadata reverts/malformed/false; seed each consumed interface | Not read | Not read | Not read | BurnerLoansRiskTimelock_InvalidRisk(T) | No deployment | Covered: [test_whenRequiredInterfaceMissing_reverts][test_whenRequiredInterfaceMissing_reverts], [test_givenDirtyErc165Bool_whenConstructed_reverts][test_givenDirtyErc165Bool_whenConstructed_reverts], [test_givenInterfaceGetterReverts_whenConstructed_reverts][test_givenInterfaceGetterReverts_whenConstructed_reverts], [test_givenInterfaceLengthMalformed_whenConstructed_reverts][test_givenInterfaceLengthMalformed_whenConstructed_reverts], [test_givenInterfaceBoolDirty_whenConstructed_reverts][test_givenInterfaceBoolDirty_whenConstructed_reverts], [test_givenInterfaceMetadataFaultSeeds_whenConstructed_reverts][test_givenInterfaceMetadataFaultSeeds_whenConstructed_reverts], [test_givenErc165PredicatesWrong_whenConstructed_reverts][test_givenErc165PredicatesWrong_whenConstructed_reverts] |
| BLRCT-CONSTRUCTOR-D01 | Fuzz deployer | T.kernel() returns canonical KF≠K | false | false | Zero | PolicyDependency_KernelMismatch(T,K,KF) | No deployment; mismatch not reported as pause | Covered: [test_whenForeignKernel_reverts][test_whenForeignKernel_reverts] |
| BLRCT-CONSTRUCTOR-D02 | Fuzz deployer | T.kernel() reverts, short, or dirty address word | Not read | Not read | Not read | PolicyDependency_InvalidDependency(T) | No deployment | Covered: [test_whenMalformedKernel_reverts][test_whenMalformedKernel_reverts], [test_givenInvalidKernelMetadata_whenConstructed_reverts][test_givenInvalidKernelMetadata_whenConstructed_reverts] |
| BLRCT-CONSTRUCTOR-P02 | Fuzz deployer | Valid T; its isEnabled/operator runtime getters currently revert | Not required | Not required | Not required | Success; no target activity, enabled-state or operator-selection reads when compatibility advertisement and kernel read are valid | No readiness probe until enable; immutable binding preserved | Covered: [test_givenRuntimeGettersFail_whenConstructed][test_givenRuntimeGettersFail_whenConstructed] |

## Complete startup integration

Use real Risk and new queue, with no ADMIN role granted to queue.

| ID | Caller | Sequence | Execution / effects | Test |
| --- | --- | --- | --- | --- |
| BLRCT-CONSTRUCTOR-P03 | Deployer, Kernel executor, ADMIN | Deploy Risk and queue→activate/configure Risk→set Risk operator to disabled queue→enable Risk→activate/configure queue→enable queue | No circular readiness requirement; queue may configure T only after its own activation; Risk requests no FLOAN writes | Covered: [test_whenCompatibleTarget][test_whenCompatibleTarget], [test_whenFreshStartupHasNoCircularReadiness][test_whenFreshStartupHasNoCircularReadiness] |

- [x] Review these expectations.
- [x] Write tests before implementation and map passing evidence.

[test_givenDirtyErc165Bool_whenConstructed_reverts]: constructor.t.sol#L144
[test_givenErc165PredicatesWrong_whenConstructed_reverts]: constructor.t.sol#L247
[test_givenInterfaceBoolDirty_whenConstructed_reverts]: constructor.t.sol#L204
[test_givenInterfaceGetterReverts_whenConstructed_reverts]: constructor.t.sol#L171
[test_givenInterfaceLengthMalformed_whenConstructed_reverts]: constructor.t.sol#L187
[test_givenInterfaceMetadataFaultSeeds_whenConstructed_reverts]: constructor.t.sol#L225
[test_givenInvalidKernelMetadata_whenConstructed_reverts]: constructor.t.sol#L264
[test_givenRuntimeGettersFail_whenConstructed]: constructor.t.sol#L103
[test_whenCompatibleTarget]: constructor.t.sol#L24
[test_whenForeignKernel_reverts]: constructor.t.sol#L73
[test_whenFreshStartupHasNoCircularReadiness]: constructor.t.sol#L120
[test_whenMalformedKernel_reverts]: constructor.t.sol#L87
[test_whenRequiredInterfaceMissing_reverts]: constructor.t.sol#L52
[test_whenZeroOrEOATarget_reverts]: constructor.t.sol#L40
