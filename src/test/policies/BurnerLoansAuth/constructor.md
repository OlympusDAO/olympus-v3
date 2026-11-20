# BurnerLoansAuth constructor

Sources: `src/policies/burnerloans/BurnerLoansAuth.sol` and inherited `OperatorAuth`.

Core is an immutable identity binding and must already advertise IBurnerLoansAuthTarget through ERC165. The independently supplied trusted Kernel must be nonzero and match Core's canonical Kernel getter at construction. Core membership and local enablement are checked when grants are created or used. Auth records Kernel identity but uses no Kernel roles or module permissions, so it needs no Policy installation/activation. Construction grants no custody or permissions and does not require Core activity, enablement or prior selection of this Auth.

ERC165 is probed on Core, not Kernel. The no-code Kernel case mocks Core's getter to match a nonzero
constructor argument; it tests identity binding only. An empty Kernel cannot pass runtime membership checks.

| ID | Caller / domain | Execution and effects | Test |
| --- | --- | --- | --- |
| BLAUTH-CONSTRUCTOR-I01 | Any deployer; Core zero | InvalidCore(0); no contract created | Covered: [test][test_whenCoreIsZero_reverts] |
| BLAUTH-CONSTRUCTOR-P01 | Fuzz any deployer; deployed compatible Core; independently fuzz active/enabled, another Auth selected | Immutable identity recorded without readiness/selection cycle; VERSION 1.0 | Covered: [test][test_whenCoreIsDeployed] |
| BLAUTH-CONSTRUCTOR-P02 | Any viewer; valid deployment | Advertises IERC165, generic grant, lending, Core-bound and version interfaces; rejects 0xffffffff | Covered: [test][test_whenInterfacesQueried] |
| BLAUTH-CONSTRUCTOR-I02 | Any deployer; independently supplied Kernel is zero | InvalidKernel(0); no contract created | Covered: [zero][test_whenKernelIsZero_reverts] |
| BLAUTH-CONSTRUCTOR-P03 | Any deployer; nonzero Kernel has no code and matches Core; fuzz address and enablement, explicit one/MAX160 | Identity binding succeeds without a Kernel code-length requirement | Covered: [no code][test_whenNonzeroKernelHasNoCode], [boundary seeds][test_whenNonzeroKernelBoundarySeeds] |
| BLAUTH-CONSTRUCTOR-I03 | Core has no code; fuzz full address domain, explicit zero/one/MAX160 | InvalidCore(core); no contract created | Covered: [no code][test_whenCoreHasNoCode_reverts], [boundaries][test_whenCoreNoCodeBoundarySeeds_reverts] |
| BLAUTH-CONSTRUCTOR-I04 | Core has code but omits target-interface support, including another Auth contract | InvalidCore(core); no contract created | Covered: [missing target][test_whenCoreOmitsTargetInterface_reverts], [wrong contract][test_whenCoreIsAnotherContract_reverts] |
| BLAUTH-CONSTRUCTOR-I05 | Core rejects the ERC165 positive sentinel | InvalidCore(core); no contract created | Covered: [sentinel][test_whenCoreRejectsErc165_reverts] |
| BLAUTH-CONSTRUCTOR-I06 | Core claims support for invalid 0xffffffff interface | InvalidCore(core); no contract created | Covered: [invalid sentinel][test_whenCoreSupportsInvalidInterface_reverts] |
| BLAUTH-CONSTRUCTOR-I07 | Core target-interface probe reverts | InvalidCore(core); dependency error not bubbled | Covered: [revert][test_whenCoreInterfaceProbeReverts_reverts] |
| BLAUTH-CONSTRUCTOR-I08 | Core target-interface probe returns fewer than 32 bytes | InvalidCore(core); no contract created | Covered: [short response][test_whenCoreInterfaceProbeReturnsShortData_reverts] |
| BLAUTH-CONSTRUCTOR-D01 | Core reports any Kernel except the independently supplied Kernel; fuzz active/enabled; explicit zero/MAX160 reported-address seeds | PolicyDependency_KernelMismatch(core, expected, reported); no contract created | Covered: [mismatch][test_whenCoreReportsOtherKernel_reverts], [boundaries][test_whenReportedKernelBoundarySeeds_reverts] |
| BLAUTH-CONSTRUCTOR-D02 | Core Kernel getter reverts | PolicyDependency_InvalidDependency(core); no contract created | Covered: [unreadable][test_whenCoreKernelGetterReverts_reverts] |
| BLAUTH-CONSTRUCTOR-D03 | Core Kernel getter returns short data or noncanonical address padding | PolicyDependency_InvalidDependency(core); no contract created | Covered: [malformed][test_whenCoreKernelGetterMalformed_reverts] |

[test_whenCoreIsDeployed]: ./constructor.t.sol#L120
[test_whenCoreIsZero_reverts]: ./constructor.t.sol#L109
[test_whenInterfacesQueried]: ./constructor.t.sol#L227

[test_whenKernelIsZero_reverts]: ./constructor.t.sol#L79

[test_whenNonzeroKernelHasNoCode]: ./constructor.t.sol#L90
[test_whenNonzeroKernelBoundarySeeds]: ./constructor.t.sol#L103

[test_whenCoreHasNoCode_reverts]: ./constructor.t.sol#L136
[test_whenCoreNoCodeBoundarySeeds_reverts]: ./constructor.t.sol#L145
[test_whenCoreOmitsTargetInterface_reverts]: ./constructor.t.sol#L152
[test_whenCoreIsAnotherContract_reverts]: ./constructor.t.sol#L163
[test_whenCoreRejectsErc165_reverts]: ./constructor.t.sol#L174
[test_whenCoreSupportsInvalidInterface_reverts]: ./constructor.t.sol#L185
[test_whenCoreInterfaceProbeReverts_reverts]: ./constructor.t.sol#L196
[test_whenCoreInterfaceProbeReturnsShortData_reverts]: ./constructor.t.sol#L207

[test_whenCoreReportsOtherKernel_reverts]: ./constructor.t.sol#L21
[test_whenReportedKernelBoundarySeeds_reverts]: ./constructor.t.sol#L42
[test_whenCoreKernelGetterReverts_reverts]: ./constructor.t.sol#L48
[test_whenCoreKernelGetterMalformed_reverts]: ./constructor.t.sol#L64
