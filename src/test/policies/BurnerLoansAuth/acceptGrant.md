# BurnerLoansAuth.acceptGrant

Sources: `src/policies/burnerloans/BurnerLoansAuth.sol` and inherited `OperatorAuth`.

Core is active/enabled, Auth selected, all four canonical records selected, inclusive deadline MAX48. Domain is chain plus Auth address. Inherited tests own malformed signatures, generic epochs and extension behavior. Gas excludes intrinsic transaction/calldata fees; mock wallet gas is not a Safe execution estimate.

| ID | Caller / domain | Execution and effects | Test |
| --- | --- | --- | --- |
| BLAUTH-ACCEPT-I03 | Designated operator; genuine EOA signature; selected asset unregistered after signing | InvalidAsset(asset); no grant or epoch changes | Covered: [test][test_givenSignedGrant_whenAssetUnregisteredBeforeAcceptance_reverts] |
| BLAUTH-ACCEPT-P01 | Designated operator submits independent EOA signature | Accept once; pair epoch advances; grant live | Covered: [test][test_whenOperatorSubmitsEoaSignature] |
| BLAUTH-ACCEPT-A01 | Fuzz submitter excluding only operator; seed the account | InvalidIdentity before signature consumption; unchanged | Covered: [range][test_whenUnrelatedSubmitterForwardsSignature_reverts], [account][test_whenAccountSubmitsSignature_reverts] |
| BLAUTH-ACCEPT-I01 | Operator; permission bytes changed after signing | InvalidSignature; unchanged | Covered: [test][test_whenSignedPermissionAltered_reverts] |
| BLAUTH-ACCEPT-I02 | Operator; unsupported nonempty signature-only data | UnsupportedSignatureData before installation | Covered: [test][test_whenExtraSignatureDataSupplied_reverts] |
| BLAUTH-ACCEPT-C01 | ERC1271 wallet probes epoch and attempts cancellation during verification | Static mutation fails; no preinstallation epoch consumption; accepted grant survives later wallet policy change | Covered: [test][test_whenContractWalletValidates_staticCallPrecedesInstallation] |
| BLAUTH-ACCEPT-P02 | Accepted grant; chain ID changes | Existing namespace/stamp remains live; signature verification is acceptance-only | Covered: [test][test_givenAcceptedGrant_whenChainChanges] |
| BLAUTH-ACCEPT-P03 | EOA / malicious ERC1271 mock; canonical320 bytes | Execution gas recorded; expected one pair consumption | Covered: [test][test_whenEoaSignatureAccepted_reportsGas], [test][test_whenContractSignatureAccepted_reportsGas] |
| BLAUTH-ACCEPT-D01 | Designated operator; valid EOA signature; Core reports foreign Kernel | PolicyDependency_KernelMismatch(Core, trusted, foreign); no grant or epoch consumption | Covered: [mismatch][test_givenForeignKernelReportsActive_whenSignedGrantAccepted_reverts] |

## Integration with real Core

The following cases call `BurnerLoansAuth.acceptGrant`, with real active/enabled Core and canonical
lending permissions. The designated operator submits; the signed account owns the grant. Core has
no signed-acceptance entry point. Invalid acceptance installs no authority and commits no epoch change.

| ID | Caller / input | Execution and effects | Test |
| --- | --- | --- | --- |
| BLAUTH-ACCEPT-P04 | Designated operator; genuine EOA signature | Success; pair epoch becomes one and lending authority is usable | Covered: [test][test_whenSignedGrantAcceptedByOperator] |
| BLAUTH-ACCEPT-A02 | Signed account submits | OperatorAuth_InvalidIdentity; pair remains unused and authority absent | Covered: [test][test_whenSignedGrantSubmittedByAccount_reverts] |
| BLAUTH-ACCEPT-A03 | Fuzz caller excluding designated operator | OperatorAuth_InvalidIdentity; pair epoch remains zero | Covered: [test][test_whenUnrelatedCallerForwardsSignature_reverts] |
| BLAUTH-ACCEPT-I04 | Operator; tampered account/operator, deadline, mode, action or permission bytes | OperatorAuth_InvalidSignature; no pair epoch consumed | Covered: [test][test_whenSignedFieldsTampered_reverts] |
| BLAUTH-ACCEPT-I05 | Operator; wrong chain or domain | OperatorAuth_InvalidSignature | Covered: [test][test_whenWrongSigningDomain_reverts] |
| BLAUTH-ACCEPT-I06 | Operator; wrong signing key | OperatorAuth_InvalidSignature | Covered: [test][test_whenWrongSigner_reverts] |
| BLAUTH-ACCEPT-I07 | Operator replays accepted signature | OperatorAuth_InvalidEpoch; pair stays at one | Covered: [test][test_whenSignatureReplayed_reverts] |
| BLAUTH-ACCEPT-I08 | Operator; pair or account cancelled after signing | OperatorAuth_InvalidEpoch | Covered: [test][test_whenCancelledSignature_reverts] |
| BLAUTH-ACCEPT-I09 | Operator; grant deadline one second before acceptance | OperatorAuth_ExpiredGrant(deadline) | Covered: [test][test_whenExpiredSignedGrant_reverts] |

[test_givenAcceptedGrant_whenChainChanges]: ./acceptGrant.t.sol#L139
[test_whenContractSignatureAccepted_reportsGas]: ./gas.t.sol#L56
[test_whenContractWalletValidates_staticCallPrecedesInstallation]: ./acceptGrant.t.sol#L114
[test_whenEoaSignatureAccepted_reportsGas]: ./gas.t.sol#L41
[test_givenSignedGrant_whenAssetUnregisteredBeforeAcceptance_reverts]: ./acceptGrant.t.sol#L18
[test_whenSignedGrantAcceptedByOperator]: ./acceptGrantCoreIntegration.t.sol#L14
[test_whenSignedGrantSubmittedByAccount_reverts]: ./acceptGrantCoreIntegration.t.sol#L26
[test_whenUnrelatedCallerForwardsSignature_reverts]: ./acceptGrantCoreIntegration.t.sol#L39
[test_whenSignedFieldsTampered_reverts]: ./acceptGrantCoreIntegration.t.sol#L55
[test_whenWrongSigningDomain_reverts]: ./acceptGrantCoreIntegration.t.sol#L77
[test_whenWrongSigner_reverts]: ./acceptGrantCoreIntegration.t.sol#L89
[test_whenSignatureReplayed_reverts]: ./acceptGrantCoreIntegration.t.sol#L98
[test_whenCancelledSignature_reverts]: ./acceptGrantCoreIntegration.t.sol#L113
[test_whenExpiredSignedGrant_reverts]: ./acceptGrantCoreIntegration.t.sol#L126
[test_whenExtraSignatureDataSupplied_reverts]: ./acceptGrant.t.sol#L106
[test_whenOperatorSubmitsEoaSignature]: ./acceptGrant.t.sol#L61
[test_whenSignedPermissionAltered_reverts]: ./acceptGrant.t.sol#L96
[test_whenUnrelatedSubmitterForwardsSignature_reverts]: ./acceptGrant.t.sol#L78

[test_givenForeignKernelReportsActive_whenSignedGrantAccepted_reverts]: ./acceptGrant.t.sol#L33

[test_whenAccountSubmitsSignature_reverts]: ./acceptGrant.t.sol#L88
