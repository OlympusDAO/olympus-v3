# BurnerLoansLens.constructor coverage plan

Source: [constructor](../../../policies/burnerloans/BurnerLoansLens.sol#L36).

## Domains and notation

Scenario scope: `BLLENS-CONSTRUCTOR`. Lens stays a plain read-only helper without Kernel membership or IEnabler. SeizerTask owns operational control; Core is its immutable read dependency. All cases assert no state writes or committed events. `MAXn=2**n-1`.

Lens implements `IBurnerLoansLens` and `IVersioned` separately and inherits ERC165 support from `ERC165`. `IBurnerLoansLens` has no inherited interfaces and declares only Lens-specific functions. `VERSION()` returns named values `major=1,minor=0`; ERC165 advertises both interfaces.

Constructor takes one already-deployed Core. It verifies IBurnerLoansCore through ERC165 and stores an immutable typed binding. No Kernel, role grant or Enabler is added to Lens. A Core may be linked before its operational dependencies are ready.

## Invalid Core bindings

Each failed deployment commits no Lens or logs. Only ERC165 compatibility is checked here; activation and a Kernel match are not Lens constructor requirements.

| ID | Caller | Candidate Core | Expected error | Test |
| --- | --- | --- | --- | --- |
| BLLENS-CONSTRUCTOR-I01 | Fuzz deployer | Zero | IBurnerLoansCoreBound.BurnerLoansAction_InvalidCore(0) | Covered: [test_givenZeroCore_whenDeployed_reverts][test_givenZeroCore_whenDeployed_reverts] |
| BLLENS-CONSTRUCTOR-I02 | Fuzz deployer | Nonzero EOA | IBurnerLoansCoreBound.BurnerLoansAction_InvalidCore(candidate) | Covered: [test_givenEoaCore_whenDeployed_reverts][test_givenEoaCore_whenDeployed_reverts] |
| BLLENS-CONSTRUCTOR-I05 | Fuzz deployer | Contract with code, without required Core ERC165 interface | IBurnerLoansCoreBound.BurnerLoansAction_InvalidCore(candidate) | Covered: [test_givenIncompatibleCore_whenDeployed_reverts][test_givenIncompatibleCore_whenDeployed_reverts] |
| BLLENS-CONSTRUCTOR-I03 | Fuzz deployer | supportsInterface reverts | IBurnerLoansCoreBound.BurnerLoansAction_InvalidCore(candidate) | Covered: [test_givenRevertingInterface_whenDeployed_reverts][test_givenRevertingInterface_whenDeployed_reverts] |
| BLLENS-CONSTRUCTOR-I04 | Fuzz deployer | supportsInterface returns malformed short data | IBurnerLoansCoreBound.BurnerLoansAction_InvalidCore(candidate) | Covered: [test_givenMalformedInterface_whenDeployed_reverts][test_givenMalformedInterface_whenDeployed_reverts] |

## Core deployment lifecycle

No role assumptions on deployer. core() must equal the exact constructor input and work without external reads afterward.

| ID | Caller | Core active | Core enabled | Execution | Effects | Test |
| --- | --- | --- | --- | --- | --- | --- |
| BLLENS-CONSTRUCTOR-P02 | Fuzz deployer | true | true | Success | Immutable core; no token approvals, roles or local lifecycle | Covered: [test_givenActiveEnabledCore_whenDeployed][test_givenActiveEnabledCore_whenDeployed] |
| BLLENS-CONSTRUCTOR-L01 | Fuzz deployer | true | false | Success | Same binding; no readiness requirement | Covered: [test_givenActiveDisabledCore_whenDeployed][test_givenActiveDisabledCore_whenDeployed] |
| BLLENS-CONSTRUCTOR-L02 | Fuzz deployer | false | true | Success | Same binding; no readiness requirement | Covered: [test_givenInactiveEnabledCore_whenDeployed][test_givenInactiveEnabledCore_whenDeployed] |
| BLLENS-CONSTRUCTOR-L03 | Fuzz deployer | false | false | Success | Same binding; no readiness requirement | Covered: [test_givenInactiveDisabledCore_whenDeployed][test_givenInactiveDisabledCore_whenDeployed] |

No legacy BurnerLoans constructor test proves this smaller constructor. Use an ERC165-capable Core fixture and isolated interface-failure mocks.

- [x] Review these expectations.
- [x] Implement focused tests and update Test mappings.

[test_givenActiveDisabledCore_whenDeployed]: ./constructor.t.sol#L106
[test_givenActiveEnabledCore_whenDeployed]: ./constructor.t.sol#L93
[test_givenEoaCore_whenDeployed_reverts]: ./constructor.t.sol#L35
[test_givenInactiveDisabledCore_whenDeployed]: ./constructor.t.sol#L132
[test_givenInactiveEnabledCore_whenDeployed]: ./constructor.t.sol#L119
[test_givenIncompatibleCore_whenDeployed_reverts]: ./constructor.t.sol#L48
[test_givenMalformedInterface_whenDeployed_reverts]: ./constructor.t.sol#L79
[test_givenRevertingInterface_whenDeployed_reverts]: ./constructor.t.sol#L61
[test_givenZeroCore_whenDeployed_reverts]: ./constructor.t.sol#L23
