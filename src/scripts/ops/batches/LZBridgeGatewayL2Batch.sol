// SPDX-License-Identifier: AGPL-3.0-or-later
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.30;

import {console2} from "@forge-std-1.9.6/console2.sol";
import {SetConfigParam} from "@lz-evm-protocol-v2-3.0.162/interfaces/IMessageLibManager.sol";
import {EnforcedOptionParam} from "@lz-oapp-evm-0.4.1/oapp/interfaces/IOAppOptionsType3.sol";

import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {IOffsettingRateLimiter} from "src/bases/interfaces/IOffsettingRateLimiter.sol";
import {Kernel, Actions, Policy} from "src/Kernel.sol";
import {LZConfigLib} from "src/libraries/LZConfigLib.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {LZBridgeGateway} from "src/policies/bridge/LZBridgeGateway.sol";
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";
import {ILZEndpointV2Admin} from "src/policies/interfaces/ILZEndpointV2Admin.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {BatchScriptV2} from "src/scripts/ops/lib/BatchScriptV2.sol";
import {ChainUtils} from "src/scripts/ops/lib/ChainUtils.sol";

/// @title LZBridgeGatewayL2Batch
/// @notice L2 MS batch scripts for the LZBridgeGateway policy.
///         The periphery LZCrossChainBridge is configured via LZCrossChainBridgeL2Batch.
///
///         On L2 chains the Kernel executor, RolesAdmin admin, and DAO MS may be
///         different addresses. The batch is split into entry points so each
///         can be run by the correct caller:
///
///         Entry points (run in order):
///         1. `activateGateway`    as Kernel executor               deactivates old bridge and activates new gateway
///         2. `grantRoles`         as RolesAdmin admin              grants bridge_admin & admin roles to DAO MS
///         3. `configureAndEnable` as DAO MS (bridge_admin & admin) configures LZ, peers, enforced options,
///                                                                  rate limits and enables
///         4. `revokeSetupRoles`   as RolesAdmin admin              (optional) revokes admin role granted in step 2
contract LZBridgeGatewayL2Batch is BatchScriptV2 {
    // =========== ERRORS =========== //

    error LZBridgeGatewayL2Batch_CanonicalChain();
    error LZBridgeGatewayL2Batch_UnsupportedChain();

    // =========== CONSTANTS =========== //

    /// @dev Role constants.
    bytes32 internal constant _BRIDGE_ADMIN_ROLE = "bridge_admin";
    bytes32 internal constant _BRIDGE_FACILITATOR_ROLE = "bridge_facilitator";
    bytes32 internal constant _BRIDGE_RATE_LIMITER_ROLE = "bridge_rate_limiter";

    // =========== ENTRY POINTS =========== //

    /// @notice Step 1. Kernel executor actions: deactivate old bridge, activate new gateway.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    /// @param signature_ Optional pre-computed signature for the batch.
    function activateGateway(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        _validateArgsFileEmpty(argsFile_);
        _requireNonCanonical();
        _skipHeartbeatValidation = true;

        address kernel = _envAddressNotZero("olympus.Kernel");
        address oldBridge = _envAddressNotZero("olympus.policies.CrossChainBridge");
        address gatewayAddr = _envAddressNotZero("olympus.policies.LZBridgeGateway");

        console2.log(
            "\n=== [L2] [Step 1] Deactivate Old Gateway & Activate New Gateway:",
            chain,
            "==="
        );

        // 1.1. Deactivate old CrossChainBridge
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.DeactivatePolicy,
                oldBridge
            )
        );

        // 1.2. Activate new LZBridgeGateway
        addToBatch(
            kernel,
            abi.encodeWithSelector(
                Kernel.executeAction.selector,
                Actions.ActivatePolicy,
                gatewayAddr
            )
        );

        _setPostBatchValidateSelector(this._validateActivateGateway.selector);

        proposeBatch();
    }

    /// @notice Step 2. RolesAdmin admin actions: grant bridge_admin, bridge_rate_limiter,
    ///         admin, and bridge_facilitator roles.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    /// @param signature_ Optional pre-computed signature for the batch.
    function grantRoles(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        _validateArgsFileEmpty(argsFile_);
        _requireNonCanonical();
        _skipHeartbeatValidation = true;

        address rolesAdminAddr = _envAddressNotZero("olympus.policies.RolesAdmin");
        address daoMS = _envAddressNotZero("olympus.multisig.dao");
        address bridgeAddr = _envAddressNotZero("olympus.periphery.LZCrossChainBridge");
        ROLESv1 rolesModule = ROLESv1(_envAddressNotZero("olympus.modules.OlympusRoles"));

        console2.log("\n=== [L2] [Step 2] Grant Roles:", chain, "===");

        // 2.1. Grant bridge_admin role to the DAO MS
        /// forge-lint: disable-next-line(unsafe-typecast)
        if (!rolesModule.hasRole(daoMS, _BRIDGE_ADMIN_ROLE)) {
            addToBatch(
                rolesAdminAddr,
                abi.encodeWithSelector(
                    RolesAdmin.grantRole.selector,
                    /// forge-lint: disable-next-line(unsafe-typecast)
                    _BRIDGE_ADMIN_ROLE,
                    daoMS
                )
            );
        }

        // 2.1b. Grant bridge_rate_limiter role to the DAO MS
        /// forge-lint: disable-next-line(unsafe-typecast)
        if (!rolesModule.hasRole(daoMS, _BRIDGE_RATE_LIMITER_ROLE)) {
            addToBatch(
                rolesAdminAddr,
                abi.encodeWithSelector(
                    RolesAdmin.grantRole.selector,
                    /// forge-lint: disable-next-line(unsafe-typecast)
                    _BRIDGE_RATE_LIMITER_ROLE,
                    daoMS
                )
            );
        }

        // 2.2. Grant admin role to the DAO MS (run revokeSetupRoles after migration if granted here)
        /// forge-lint: disable-next-line(unsafe-typecast)
        if (!rolesModule.hasRole(daoMS, ADMIN_ROLE)) {
            addToBatch(
                rolesAdminAddr,
                abi.encodeWithSelector(
                    RolesAdmin.grantRole.selector,
                    /// forge-lint: disable-next-line(unsafe-typecast)
                    ADMIN_ROLE,
                    daoMS
                )
            );
            console2.log("  admin role GRANTED to DAO MS, so run revokeSetupRoles after migration");
        } else {
            console2.log("  admin role already present on DAO MS, so revokeSetupRoles not needed");
        }

        // 2.3. Grant bridge_facilitator role to LZCrossChainBridge
        /// forge-lint: disable-next-line(unsafe-typecast)
        if (!rolesModule.hasRole(bridgeAddr, _BRIDGE_FACILITATOR_ROLE)) {
            addToBatch(
                rolesAdminAddr,
                abi.encodeWithSelector(
                    RolesAdmin.grantRole.selector,
                    /// forge-lint: disable-next-line(unsafe-typecast)
                    _BRIDGE_FACILITATOR_ROLE,
                    bridgeAddr
                )
            );
        }

        _setPostBatchValidateSelector(this._validateGrantRoles.selector);

        proposeBatch();
    }

    /// @notice Step 3. DAO MS actions (requires bridge_admin & admin roles):
    ///         LZ config, peers, enforced options, rate limits, and enable.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    /// @param signature_ Optional pre-computed signature for the batch.
    function configureAndEnable(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        _validateArgsFileEmpty(argsFile_);
        _requireNonCanonical();
        _skipHeartbeatValidation = true;

        address gatewayAddr = _envAddressNotZero("olympus.policies.LZBridgeGateway");
        LZBridgeGateway gateway = LZBridgeGateway(gatewayAddr);

        console2.log("\n=== [L2] [Step 3] Configure & Enable:", chain, "===");

        // 3.1. Configure LZ libraries and ULN/Executor config
        _configureLZ(gateway);

        // 3.2. Set peers
        _setPeers(gateway);

        // 3.3. Set enforced options
        _setEnforcedOptions(gateway);

        // 3.4. Set rate limits
        _setRateLimits(gateway);

        // 3.5. Enable LZBridgeGateway
        addToBatch(gatewayAddr, abi.encodeWithSelector(PolicyEnabler.enable.selector, ""));

        _setPostBatchValidateSelector(this._validateConfigureAndEnable.selector);

        proposeBatch();
    }

    /// @notice Step 4 (optional). Revoke the admin role from the DAO MS.
    ///         Only run on chains where `grantRoles` (step 2) reported that the admin role
    ///         was granted. Skip on chains where the DAO MS already had the role.
    /// @param useDaoMS_ Whether to use the DAO MS as the owner.
    /// @param signOnly_ Whether to only sign the batch without proposing/executing it.
    /// @param argsFile_ Path to the arguments file (unused, must be empty).
    /// @param ledgerDerivationPath_ Derivation path for Ledger signing (if applicable).
    /// @param signature_ Optional pre-computed signature for the batch.
    function revokeSetupRoles(
        bool useDaoMS_,
        bool signOnly_,
        string calldata argsFile_,
        string calldata ledgerDerivationPath_,
        bytes calldata signature_
    ) external setUp(useDaoMS_, signOnly_, argsFile_, ledgerDerivationPath_, signature_) {
        _validateArgsFileEmpty(argsFile_);
        _requireNonCanonical();
        _skipHeartbeatValidation = true;

        address rolesAdminAddr = _envAddressNotZero("olympus.policies.RolesAdmin");
        address daoMS = _envAddressNotZero("olympus.multisig.dao");
        ROLESv1 rolesModule = ROLESv1(_envAddressNotZero("olympus.modules.OlympusRoles"));

        console2.log("\n=== [L2] [Step 4] Revoke Setup Roles:", chain, "===");

        /// forge-lint: disable-next-line(unsafe-typecast)
        if (!rolesModule.hasRole(daoMS, ADMIN_ROLE)) {
            revert("DAO MS does not have admin role - nothing to revoke");
        }

        addToBatch(
            rolesAdminAddr,
            abi.encodeWithSelector(
                RolesAdmin.revokeRole.selector,
                /// forge-lint: disable-next-line(unsafe-typecast)
                ADMIN_ROLE,
                daoMS
            )
        );

        _setPostBatchValidateSelector(this._validateRevokeSetupRoles.selector);

        proposeBatch();
    }

    // =========== VALIDATION =========== //

    /// @notice Validate activateGateway state after batch execution.
    /// @dev Checks that old bridge is deactivated and new gateway is active.
    function _validateActivateGateway() external view {
        address oldBridge = _envAddressNotZero("olympus.policies.CrossChainBridge");
        address gatewayAddr = _envAddressNotZero("olympus.policies.LZBridgeGateway");

        console2.log("\nValidating activateGateway post-batch state");

        if (Policy(oldBridge).isActive()) {
            revert("Old CrossChainBridge is still active in the Kernel");
        }
        console2.log("  Old CrossChainBridge is deactivated");

        if (!LZBridgeGateway(gatewayAddr).isActive()) {
            revert("LZBridgeGateway is not active in the Kernel");
        }
        console2.log("  LZBridgeGateway is active in the Kernel");

        console2.log("activateGateway post-batch validation passed");
    }

    /// @notice Validate grantRoles state after batch execution.
    /// @dev Checks that DAO MS has bridge_admin, bridge_rate_limiter, and admin roles,
    ///      and that the periphery bridge has the facilitator role.
    function _validateGrantRoles() external view {
        address daoMS = _envAddressNotZero("olympus.multisig.dao");
        address bridgeAddr = _envAddressNotZero("olympus.periphery.LZCrossChainBridge");
        ROLESv1 rolesModule = ROLESv1(_envAddressNotZero("olympus.modules.OlympusRoles"));

        console2.log("\nValidating grantRoles post-batch state");

        if (!rolesModule.hasRole(daoMS, _BRIDGE_ADMIN_ROLE)) {
            revert("DAO MS does not have bridge_admin role");
        }
        console2.log("  DAO MS has bridge_admin role");

        if (!rolesModule.hasRole(daoMS, _BRIDGE_RATE_LIMITER_ROLE)) {
            revert("DAO MS does not have bridge_rate_limiter role");
        }
        console2.log("  DAO MS has bridge_rate_limiter role");

        if (!rolesModule.hasRole(daoMS, ADMIN_ROLE)) {
            revert("DAO MS does not have admin role");
        }
        console2.log("  DAO MS has admin role");

        if (!rolesModule.hasRole(bridgeAddr, _BRIDGE_FACILITATOR_ROLE)) {
            revert("LZCrossChainBridge does not have bridge_facilitator role");
        }
        console2.log("  LZCrossChainBridge has bridge_facilitator role");

        console2.log("grantRoles post-batch validation passed");
    }

    /// @notice Validate configureAndEnable state after batch execution.
    /// @dev Checks that gateway is enabled, peers are set, enforced options exist, and rate limits are set.
    function _validateConfigureAndEnable() external view {
        address gatewayAddr = _envAddressNotZero("olympus.policies.LZBridgeGateway");
        LZBridgeGateway gateway = LZBridgeGateway(gatewayAddr);
        uint32 localEid = _getLocalEid();
        uint32[] memory remoteEids = _getRemoteEids();

        console2.log("\nValidating configureAndEnable post-batch state");

        // 1. Gateway must be enabled
        if (!gateway.isEnabled()) {
            revert("LZBridgeGateway is not enabled");
        }
        console2.log("  LZBridgeGateway is enabled");

        // 2. Peers must be set for all remote EIDs
        for (uint256 i = 0; i < remoteEids.length; ++i) {
            bytes32 peer = gateway.peers(remoteEids[i]);
            if (peer == bytes32(0)) {
                revert(string.concat("Peer not set for EID ", vm.toString(uint256(remoteEids[i]))));
            }
            console2.log("  Peer set for EID:", remoteEids[i]);
        }

        // 3. Enforced options must be set for all remote EIDs
        uint8 msgType = gateway.MSG_BRIDGE_OHM();
        for (uint256 i = 0; i < remoteEids.length; ++i) {
            bytes memory opts = gateway.enforcedOptions(remoteEids[i], msgType);
            if (opts.length == 0) {
                revert(
                    string.concat(
                        "Enforced options not set for EID ",
                        vm.toString(uint256(remoteEids[i]))
                    )
                );
            }
            console2.log("  Enforced options set for EID:", remoteEids[i]);
        }

        // 4. Bidirectional rate limits must match for all remote EIDs
        _validateRateLimits(gateway, localEid, remoteEids);

        console2.log("configureAndEnable post-batch validation passed");
    }

    /// @notice Verifies the outbound and inbound rate limit configuration on the gateway.
    function _validateRateLimits(
        LZBridgeGateway gateway_,
        uint32 localEid_,
        uint32[] memory remoteEids_
    ) internal view {
        uint32 expectedWindow = LZConfigLib.RATE_LIMIT_WINDOW;

        for (uint256 i = 0; i < remoteEids_.length; ++i) {
            uint32 remoteEid = remoteEids_[i];
            uint256 expectedOut = LZConfigLib.outRateLimitForRoute(localEid_, remoteEid);
            uint256 expectedIn = LZConfigLib.inRateLimitForRoute(localEid_, remoteEid);
            (, uint256 outLimit, uint32 outWindow, ) = gateway_.outRateLimits(remoteEid);
            if (outLimit != expectedOut) {
                revert(
                    string.concat(
                        "Outbound rate limit mismatch for EID ",
                        vm.toString(uint256(remoteEid))
                    )
                );
            }
            if (outWindow != expectedWindow) {
                revert(
                    string.concat(
                        "Outbound rate window mismatch for EID ",
                        vm.toString(uint256(remoteEid))
                    )
                );
            }
            (, uint256 inLimit, uint32 inWindow, ) = gateway_.inRateLimits(remoteEid);
            if (inLimit != expectedIn) {
                revert(
                    string.concat(
                        "Inbound rate limit mismatch for EID ",
                        vm.toString(uint256(remoteEid))
                    )
                );
            }
            if (inWindow != expectedWindow) {
                revert(
                    string.concat(
                        "Inbound rate window mismatch for EID ",
                        vm.toString(uint256(remoteEid))
                    )
                );
            }
            console2.log("  Rate limits OK for EID:", remoteEid);
        }
    }

    /// @notice Validate revokeSetupRoles state after batch execution.
    /// @dev Checks that DAO MS no longer has the admin role.
    function _validateRevokeSetupRoles() external view {
        address daoMS = _envAddressNotZero("olympus.multisig.dao");
        ROLESv1 rolesModule = ROLESv1(_envAddressNotZero("olympus.modules.OlympusRoles"));

        console2.log("\nValidating revokeSetupRoles post-batch state");

        /// forge-lint: disable-next-line(unsafe-typecast)
        if (rolesModule.hasRole(daoMS, ADMIN_ROLE)) {
            revert("DAO MS still has admin role");
        }
        console2.log("  DAO MS admin role revoked");

        console2.log("revokeSetupRoles post-batch validation passed");
    }

    // =========== LZ CONFIGURATION HELPERS =========== //

    /// @notice Reverts if called on a canonical chain (mainnet/sepolia).
    /// @dev    On canonical chains, LZ config is done via the LZBridgeActivator OCG proposal.
    function _requireNonCanonical() internal view {
        if (ChainUtils._isCanonicalChain(chain)) revert LZBridgeGatewayL2Batch_CanonicalChain();
    }

    /// @notice Configures LZ libraries and ULN/Executor config for all remote chains
    ///         via the gateway's ILZEndpointV2Admin functions.
    /// @dev    Only for non-canonical (L2) chains.
    ///         DVN selection is per-route: Berachain routes use Nethermind DVN instead of
    ///         Google Cloud DVN (which is unavailable on Berachain).
    function _configureLZ(LZBridgeGateway gateway_) internal {
        uint32[] memory remoteEids = _getRemoteEids();
        uint32 localEid = _getLocalEid();
        address sendLib = _getSendUln302();
        address recvLib = _getRecvUln302();
        uint64 localConf = _outboundConfirmations();
        address gatewayAddr = address(gateway_);

        console2.log("\nConfiguring LZ - sendLib:", sendLib, "recvLib:", recvLib);

        for (uint256 i = 0; i < remoteEids.length; ++i) {
            uint32 remoteEid = remoteEids[i];
            // Select DVNs based on route (Nethermind for Berachain routes, Google Cloud otherwise)
            address[] memory dvns = LZConfigLib.dvnsForRoute(localEid, remoteEid);
            console2.log("  Configuring remote EID:", remoteEid);

            // Pin send library via gateway
            addToBatch(
                gatewayAddr,
                abi.encodeCall(ILZEndpointV2Admin.setSendLibrary, (remoteEid, sendLib))
            );

            // Pin receive library via gateway
            addToBatch(
                gatewayAddr,
                abi.encodeCall(ILZEndpointV2Admin.setReceiveLibrary, (remoteEid, recvLib, 0))
            );

            // Send ULN + Executor config
            SetConfigParam[] memory sendParams = new SetConfigParam[](2);
            sendParams[0] = SetConfigParam({
                eid: remoteEid,
                configType: LZConfigLib.CONFIG_TYPE_ULN,
                config: LZConfigLib.encodeUlnConfig(localConf, dvns)
            });
            sendParams[1] = SetConfigParam({
                eid: remoteEid,
                configType: LZConfigLib.CONFIG_TYPE_EXECUTOR,
                config: LZConfigLib.encodeExecutorConfig(localEid)
            });
            addToBatch(
                gatewayAddr,
                abi.encodeCall(ILZEndpointV2Admin.setEndpointConfig, (sendLib, sendParams))
            );

            // Receive ULN config (inbound = remote chain's outbound confirmations)
            uint64 remoteConf = LZConfigLib.outboundConfirmationsForEid(remoteEid);
            SetConfigParam[] memory recvParams = new SetConfigParam[](1);
            recvParams[0] = SetConfigParam({
                eid: remoteEid,
                configType: LZConfigLib.CONFIG_TYPE_ULN,
                config: LZConfigLib.encodeUlnConfig(remoteConf, dvns)
            });
            addToBatch(
                gatewayAddr,
                abi.encodeCall(ILZEndpointV2Admin.setEndpointConfig, (recvLib, recvParams))
            );
        }
    }

    /// @notice Sets peers for all remote chains from env.json addresses.
    function _setPeers(LZBridgeGateway gateway_) internal {
        address gatewayAddr = address(gateway_);
        string[] memory remoteChains = _getRemoteChainNames();
        uint32[] memory remoteEids = _getRemoteEids();

        console2.log("\nSetting peers");

        for (uint256 i = 0; i < remoteChains.length; ++i) {
            address remoteGateway = _envAddressNotZero(
                remoteChains[i],
                "olympus.policies.LZBridgeGateway"
            );
            bytes32 peer = LZConfigLib.addressToBytes32(remoteGateway);
            console2.log("  EID", remoteEids[i], "->", remoteGateway);

            addToBatch(
                gatewayAddr,
                abi.encodeCall(ILZBridgeGateway.setPeer, (remoteEids[i], peer))
            );
        }
    }

    /// @notice Sets bidirectional OHM rate limits for all remote chains.
    /// @dev Outbound limits differ per route: Ethereum gets a tighter ceiling than
    ///      another non-canonical peer. Inbound limits do not differ by remote.
    ///      Values come from `LZConfigLib.outRateLimitForRoute` /
    ///      `inRateLimitForRoute` keyed on the (local, remote) EID pair.
    function _setRateLimits(LZBridgeGateway gateway_) internal {
        address gatewayAddr = address(gateway_);
        uint32[] memory remoteEids = _getRemoteEids();
        uint32 localEid = _getLocalEid();
        uint32 window = LZConfigLib.RATE_LIMIT_WINDOW;

        console2.log("\nSetting rate limits");

        IOffsettingRateLimiter.RateLimitConfig[]
            memory outConfigs = new IOffsettingRateLimiter.RateLimitConfig[](remoteEids.length);
        IOffsettingRateLimiter.RateLimitConfig[]
            memory inConfigs = new IOffsettingRateLimiter.RateLimitConfig[](remoteEids.length);

        for (uint256 i = 0; i < remoteEids.length; ++i) {
            outConfigs[i] = IOffsettingRateLimiter.RateLimitConfig({
                eid: remoteEids[i],
                limit: LZConfigLib.outRateLimitForRoute(localEid, remoteEids[i]),
                window: window
            });
            inConfigs[i] = IOffsettingRateLimiter.RateLimitConfig({
                eid: remoteEids[i],
                limit: LZConfigLib.inRateLimitForRoute(localEid, remoteEids[i]),
                window: window
            });
            console2.log("  Rate limit configured for EID:", remoteEids[i]);
        }

        addToBatch(gatewayAddr, abi.encodeCall(ILZBridgeGateway.setOutRateLimits, (outConfigs)));
        addToBatch(gatewayAddr, abi.encodeCall(ILZBridgeGateway.setInRateLimits, (inConfigs)));
    }

    /// @notice Sets enforced options for all remote chains.
    function _setEnforcedOptions(LZBridgeGateway gateway_) internal {
        address gatewayAddr = address(gateway_);
        uint32[] memory remoteEids = _getRemoteEids();
        uint8 msgBridgeOhm = gateway_.MSG_BRIDGE_OHM();

        console2.log("\nSetting enforced options");

        EnforcedOptionParam[] memory opts = new EnforcedOptionParam[](remoteEids.length);

        for (uint256 i = 0; i < remoteEids.length; ++i) {
            // Type 3 options: WORKER_ID=1, size=17, OPTION_TYPE_LZRECEIVE=1, gas=200k
            bytes memory options = abi.encodePacked(
                uint16(3),
                uint8(1),
                uint16(17),
                uint8(1),
                uint128(200_000)
            );
            opts[i] = EnforcedOptionParam({
                eid: remoteEids[i],
                msgType: msgBridgeOhm,
                options: options
            });
        }

        addToBatch(gatewayAddr, abi.encodeCall(ILZBridgeGateway.setEnforcedOptions, (opts)));
    }

    // =========== CHAIN-SPECIFIC HELPERS =========== //

    /// @notice Returns the local EID for the current chain.
    function _getLocalEid() internal view returns (uint32) {
        if (_isChain("mainnet")) return LZConfigLib.ETH_EID;
        if (_isChain("arbitrum")) return LZConfigLib.ARB_EID;
        if (_isChain("optimism")) return LZConfigLib.OPT_EID;
        if (_isChain("base")) return LZConfigLib.BASE_EID;
        if (_isChain("berachain")) return LZConfigLib.BERA_EID;
        revert LZBridgeGatewayL2Batch_UnsupportedChain();
    }

    /// @notice Returns the remote EIDs for the current chain.
    /// @dev Topology: full mesh, every chain peers with all 4 others.
    function _getRemoteEids() internal view returns (uint32[] memory eids) {
        if (_isChain("mainnet")) {
            eids = new uint32[](4);
            eids[0] = LZConfigLib.ARB_EID;
            eids[1] = LZConfigLib.OPT_EID;
            eids[2] = LZConfigLib.BASE_EID;
            eids[3] = LZConfigLib.BERA_EID;
        } else if (_isChain("arbitrum")) {
            eids = new uint32[](4);
            eids[0] = LZConfigLib.ETH_EID;
            eids[1] = LZConfigLib.OPT_EID;
            eids[2] = LZConfigLib.BASE_EID;
            eids[3] = LZConfigLib.BERA_EID;
        } else if (_isChain("optimism")) {
            eids = new uint32[](4);
            eids[0] = LZConfigLib.ETH_EID;
            eids[1] = LZConfigLib.ARB_EID;
            eids[2] = LZConfigLib.BASE_EID;
            eids[3] = LZConfigLib.BERA_EID;
        } else if (_isChain("base")) {
            eids = new uint32[](4);
            eids[0] = LZConfigLib.ETH_EID;
            eids[1] = LZConfigLib.ARB_EID;
            eids[2] = LZConfigLib.OPT_EID;
            eids[3] = LZConfigLib.BERA_EID;
        } else if (_isChain("berachain")) {
            eids = new uint32[](4);
            eids[0] = LZConfigLib.ETH_EID;
            eids[1] = LZConfigLib.ARB_EID;
            eids[2] = LZConfigLib.OPT_EID;
            eids[3] = LZConfigLib.BASE_EID;
        } else {
            revert LZBridgeGatewayL2Batch_UnsupportedChain();
        }
    }

    /// @notice Returns the remote chain names (env.json keys) for the current chain.
    /// @dev Array length matches _getRemoteEids(). All chains have 4 remotes.
    function _getRemoteChainNames() internal view returns (string[] memory names) {
        if (_isChain("mainnet")) {
            names = new string[](4);
            names[0] = "arbitrum";
            names[1] = "optimism";
            names[2] = "base";
            names[3] = "berachain";
        } else if (_isChain("arbitrum")) {
            names = new string[](4);
            names[0] = "mainnet";
            names[1] = "optimism";
            names[2] = "base";
            names[3] = "berachain";
        } else if (_isChain("optimism")) {
            names = new string[](4);
            names[0] = "mainnet";
            names[1] = "arbitrum";
            names[2] = "base";
            names[3] = "berachain";
        } else if (_isChain("base")) {
            names = new string[](4);
            names[0] = "mainnet";
            names[1] = "arbitrum";
            names[2] = "optimism";
            names[3] = "berachain";
        } else if (_isChain("berachain")) {
            names = new string[](4);
            names[0] = "mainnet";
            names[1] = "arbitrum";
            names[2] = "optimism";
            names[3] = "base";
        } else {
            revert LZBridgeGatewayL2Batch_UnsupportedChain();
        }
    }

    /// @notice Returns the SendUln302 address for the current chain.
    function _getSendUln302() internal view returns (address) {
        return LZConfigLib.sendUln302ForEid(_getLocalEid());
    }

    /// @notice Returns the ReceiveUln302 address for the current chain.
    function _getRecvUln302() internal view returns (address) {
        return LZConfigLib.recvUln302ForEid(_getLocalEid());
    }

    /// @notice Returns the outbound confirmation count for the current chain.
    function _outboundConfirmations() internal view returns (uint64) {
        return LZConfigLib.outboundConfirmationsForEid(_getLocalEid());
    }

    /// @notice Checks if the current chain matches the given name.
    function _isChain(string memory name_) internal view returns (bool) {
        return keccak256(abi.encodePacked(chain)) == keccak256(abi.encodePacked(name_));
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
