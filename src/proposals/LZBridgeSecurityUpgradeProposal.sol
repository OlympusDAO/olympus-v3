// SPDX-License-Identifier: MIT
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
// solhint-disable one-contract-per-file
// solhint-disable custom-errors
pragma solidity >=0.8.30;

// OCG Proposal Simulator
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {GovernorBravoProposal} from "proposal-sim/proposals/OlympusGovernorBravoProposal.sol";

// Script
import {ProposalScript} from "src/proposals/ProposalScript.sol";

// Libraries
import {LZConfigLib} from "src/libraries/LZConfigLib.sol";

// Interfaces
import {ExecutorConfig} from "@lz-evm-messagelib-v2-3.0.162/SendLibBase.sol";
import {UlnConfig} from "@lz-evm-messagelib-v2-3.0.162/uln/UlnBase.sol";
import {ILayerZeroEndpointV2} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {IEndpointV2State} from "src/interfaces/layerzero/IEndpointV2State.sol";
import {IUlnConfigState} from "src/interfaces/layerzero/IUlnConfigState.sol";

// Constants
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Kernel, Policy} from "src/Kernel.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {LZBridgeGateway} from "src/policies/bridge/LZBridgeGateway.sol";
import {LZBridgeActivator} from "src/proposals/LZBridgeActivator.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

/// @notice OCG proposal for the LayerZero Bridge Security Upgrade.
///         Replaces the old CrossChainBridge with a hardened LZBridgeGateway policy
///         that separates infrastructure from user-facing concerns, tracks bridged supply,
///         and migrates to LayerZero V2 with explicit endpoint configuration, eliminating drag-along vulnerability.
///         The periphery LZCrossChainBridge is configured separately by the DAO MS.
///
///         The LZBridgeActivator performs all endpoint configuration,
///         peer setup, enforced options, and enablement in a single proposal action.
///         It is used to work around the governor's 15-action limit,
///
///         Assumes:
///         - LZBridgeGateway, LZCrossChainBridge, LZBridgeActivator have been deployed on Ethereum mainnet.
///         - Remote instances have been deployed on Arbitrum, Optimism, Base, and Berachain.
///         - DAO MS has already activated LZBridgeGateway in the Kernel.
///         - OCG timelock already has the `admin` and `bridge_admin` roles.
contract LZBridgeSecurityUpgradeProposal is GovernorBravoProposal {
    Kernel internal _kernel;

    // ========== CONSTANTS ========== //

    /// @dev Number of remote chains (Arbitrum, Optimism, Base, Berachain).
    uint256 internal constant _REMOTE_CHAIN_COUNT = 4;

    /// @dev Role constants.
    bytes32 internal constant _BRIDGE_ADMIN_ROLE = "bridge_admin";
    bytes32 internal constant _BRIDGE_FACILITATOR_ROLE = "bridge_facilitator";

    // ========== PROPOSAL ========== //

    function id() public pure override returns (uint256) {
        // TODO: Set the proposal ID before submission
        return 15;
    }

    function name() public pure override returns (string memory) {
        return "LZ Bridge Security Upgrade";
    }

    // solhint-disable quotes
    function description() public pure override returns (string memory) {
        return
            string.concat(
                "# LayerZero Bridge Security Upgrade\n",
                "\n",
                "This proposal configures and enables the new LZBridgeGateway policy, hardening the LayerZero OHM bridge infrastructure.\n",
                "\n",
                "## Justification\n",
                "\n",
                "The existing CrossChainBridge contract contains a number of security flaws and limitations, which are addressed in this upgrade by introducing the following:\n",
                "\n",
                "- Bridged supply tracking with underflow checks on inbound receives, preventing unlimited mints from non-canonical chains.\n",
                "- Separation into an infrastructure policy (LZBridgeGateway) that handles privileged operations and a user-facing periphery contract (LZCrossChainBridge), following the pattern established by the CCIP bridge.\n",
                "- Hardened bridge operations: send and receive are blocked while the bridge is disabled; the custom failed-message retry mechanism is removed in favour of native LayerZero V2 message delivery, which enforces peer validation on retry and eliminates the risk of replaying messages from untrusted senders.\n",
                "- Migration from default LayerZero V1 configuration to explicitly pinned V2 endpoint configuration (SendUln302/ReceiveUln302 libraries, DVN and Executor config), eliminating the drag-along vulnerability and the proof library substitution attack vector. Verification with dual-DVN confirmation.\n",
                "- Introduction of per-endpoint rate limiting on both outbound and inbound transfers, providing a time-windowed throttle. Rate limits are left unconfigured by default and configured separately as needed.\n",
                "- Replacement of the LayerZero V1 endpoint's forceResumeReceive with native V2 message recovery primitives (skip, nilify, burn, clear), administered by the bridge_admin role.\n",
                "- Replacement of LayerZero V1 endpoint adapter parameters with enforced Type 3 options that guarantee minimum destination gas per message. The gateway supports combining enforced options with caller-supplied options at send time, enabling future facilitator upgrades; the current LZCrossChainBridge facilitator passes no extra options.\n",
                "- Retained mint/burn model to avoid supply inflation and double-counting.\n",
                "- Berachain bridge now supports routes to Arbitrum, Optimism, and Base in addition to Ethereum.\n",
                "\n",
                "## Resources\n",
                "\n",
                "- TODO: Add link to audit report\n",
                "- TODO: Add link to PR\n",
                "- TODO: Add RFC/OIP reference\n",
                "\n",
                "## Assumptions\n",
                "\n",
                "- LZBridgeGateway, LZCrossChainBridge, LZBridgeActivator have been deployed on Ethereum.\n",
                "- Remote LZBridgeGateway and LZCrossChainBridge instances have been deployed on Arbitrum, Optimism, Base, and Berachain.\n",
                "- The DAO MS has already activated LZBridgeGateway in the Kernel.\n",
                "- The OCG timelock already has the `admin` and `bridge_admin` roles (required for endpoint configuration, peer setup, and enabling).\n",
                "\n",
                "## Proposal Steps\n",
                "\n",
                "1. Grant the `bridge_admin` role to the DAO MS.\n",
                "2. Grant the `bridge_facilitator` role to the LZCrossChainBridge periphery contract.\n",
                "3. Grant temporary `admin` and `bridge_admin` roles to the LZBridgeActivator contract.\n",
                "4. Execute LZBridgeActivator.activate() which:\n",
                "   - Pins SendUln302/ReceiveUln302 libraries and sets ULN/Executor config for all remote chains (Arbitrum, Optimism, Base, Berachain). Dual-DVN verification: LayerZero Labs + Google Cloud for non-Berachain routes, LayerZero Labs + Nethermind for Berachain routes. No optional DVNs (explicit NIL sentinel, so not inherited from LayerZero's default).\n",
                "   - Sets peers for all remote chains.\n",
                "   - Sets enforced options: 200,000 gas minimum for lzReceive on each destination.\n",
                "   - Enables the LZBridgeGateway policy.\n",
                "5. Revoke temporary roles from the LZBridgeActivator contract.\n",
                "\n",
                "At the completion of this proposal, the DAO MS will deactivate the old CrossChainBridge, configure the periphery LZCrossChainBridge, and synchronize the initial bridged supply via batch scripts.\n"
            );
    }

    // solhint-enable quotes

    function _deploy(Addresses addresses, address) internal override {
        _kernel = Kernel(addresses.getAddress("olympus-kernel"));
    }

    function _afterDeploy(Addresses addresses, address) internal override {}

    function _build(Addresses addresses) internal override {
        address rolesAddr = addresses.getAddress("olympus-module-roles");
        address rolesAdmin = addresses.getAddress("olympus-policy-roles-admin");
        address daoMS = addresses.getAddress("olympus-multisig-dao");
        address lzCrossChainBridge = addresses.getAddress(
            "olympus-periphery-lz-cross-chain-bridge"
        );
        address activator = addresses.getAddress("olympus-lz-bridge-activator");

        _requireNonZeroAddress(rolesAddr, "olympus-module-roles");
        _requireNonZeroAddress(rolesAdmin, "olympus-policy-roles-admin");
        _requireNonZeroAddress(daoMS, "olympus-multisig-dao");
        _requireNonZeroAddress(lzCrossChainBridge, "olympus-periphery-lz-cross-chain-bridge");
        _requireNonZeroAddress(activator, "olympus-lz-bridge-activator");

        ROLESv1 roles = ROLESv1(rolesAddr);

        // 1. Grant bridge_admin role to DAO MS (conditional)
        /// forge-lint: disable-next-line(unsafe-typecast)
        if (!roles.hasRole(daoMS, _BRIDGE_ADMIN_ROLE)) {
            _pushAction(
                rolesAdmin,
                abi.encodeWithSelector(
                    RolesAdmin.grantRole.selector,
                    /// forge-lint: disable-next-line(unsafe-typecast)
                    _BRIDGE_ADMIN_ROLE,
                    daoMS
                ),
                "Grant bridge_admin role to DAO MS"
            );
        }

        // 2. Grant bridge_facilitator role to LZCrossChainBridge (conditional)
        /// forge-lint: disable-next-line(unsafe-typecast)
        if (!roles.hasRole(lzCrossChainBridge, _BRIDGE_FACILITATOR_ROLE)) {
            _pushAction(
                rolesAdmin,
                abi.encodeWithSelector(
                    RolesAdmin.grantRole.selector,
                    /// forge-lint: disable-next-line(unsafe-typecast)
                    _BRIDGE_FACILITATOR_ROLE,
                    lzCrossChainBridge
                ),
                "Grant bridge_facilitator role to LZCrossChainBridge"
            );
        }

        // 3. Grant temporary roles to the activator
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                /// forge-lint: disable-next-line(unsafe-typecast)
                ADMIN_ROLE,
                activator
            ),
            "Grant admin role to temporary activator contract"
        );
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.grantRole.selector,
                /// forge-lint: disable-next-line(unsafe-typecast)
                _BRIDGE_ADMIN_ROLE,
                activator
            ),
            "Grant bridge_admin role to temporary activator contract"
        );

        // 4. Execute activator (single action: LZ config + peers + options + enable)
        _pushAction(
            activator,
            abi.encodeWithSelector(LZBridgeActivator.activate.selector),
            "Execute LZBridgeActivator"
        );

        // 5. Revoke temporary roles from the activator
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.revokeRole.selector,
                /// forge-lint: disable-next-line(unsafe-typecast)
                ADMIN_ROLE,
                activator
            ),
            "Revoke admin role from temporary activator contract"
        );
        _pushAction(
            rolesAdmin,
            abi.encodeWithSelector(
                RolesAdmin.revokeRole.selector,
                /// forge-lint: disable-next-line(unsafe-typecast)
                _BRIDGE_ADMIN_ROLE,
                activator
            ),
            "Revoke bridge_admin role from temporary activator contract"
        );
    }

    function _run(Addresses addresses, address) internal override {
        _simulateActions(
            address(_kernel),
            addresses.getAddress("olympus-governor"),
            addresses.getAddress("olympus-legacy-gohm"),
            addresses.getAddress("proposer")
        );
    }

    function _validate(Addresses addresses, address) internal view override {
        ROLESv1 roles = ROLESv1(addresses.getAddress("olympus-module-roles"));
        address daoMS = addresses.getAddress("olympus-multisig-dao");
        LZBridgeGateway gw = LZBridgeGateway(
            addresses.getAddress("olympus-policy-lz-bridge-gateway")
        );
        LZBridgeActivator activator = LZBridgeActivator(
            addresses.getAddress("olympus-lz-bridge-activator")
        );
        ILayerZeroEndpointV2 ep = ILayerZeroEndpointV2(LZConfigLib.ETH_LZ_ENDPOINT);
        address lzCrossChainBridge = addresses.getAddress(
            "olympus-periphery-lz-cross-chain-bridge"
        );

        // 1. Validate LZBridgeGateway is active in the Kernel (activated by MS before OCG)
        require(Policy(address(gw)).isActive(), "LZBridgeGateway policy is not active");

        // 2. Validate LZBridgeGateway is enabled
        require(PolicyEnabler(address(gw)).isEnabled(), "LZBridgeGateway is not enabled");

        // 3. Validate roles
        require(
            /// forge-lint: disable-next-line(unsafe-typecast)
            roles.hasRole(daoMS, _BRIDGE_ADMIN_ROLE),
            "DAO MS does not have bridge_admin role"
        );
        require(
            /// forge-lint: disable-next-line(unsafe-typecast)
            roles.hasRole(lzCrossChainBridge, _BRIDGE_FACILITATOR_ROLE),
            "LZCrossChainBridge does not have bridge_facilitator role"
        );

        // 4. Validate activator roles revoked
        require(
            /// forge-lint: disable-next-line(unsafe-typecast)
            !roles.hasRole(address(activator), ADMIN_ROLE),
            "Activator should not have admin role"
        );
        require(
            /// forge-lint: disable-next-line(unsafe-typecast)
            !roles.hasRole(address(activator), _BRIDGE_ADMIN_ROLE),
            "Activator should not have bridge_admin role"
        );

        // 5. Validate activator is spent
        require(activator.isActivated(), "Activator should be marked as activated");

        // 6. Validate per-remote LZ config
        _validateLZConfig(gw, ep);

        // 7. Validate peers
        _validatePeers(gw, activator);

        // 8. Validate enforced options
        _validateEnforcedOptions(gw);

        // 9. Validate delegate is revoked
        require(
            IEndpointV2State(address(ep)).delegates(address(gw)) == address(0),
            "Delegate should be revoked"
        );
    }

    // ========== VALIDATION HELPERS ========== //

    function _validateLZConfig(LZBridgeGateway gw, ILayerZeroEndpointV2 ep) internal view {
        uint32[_REMOTE_CHAIN_COUNT] memory remoteEids = [
            LZConfigLib.ARB_EID,
            LZConfigLib.OPT_EID,
            LZConfigLib.BASE_EID,
            LZConfigLib.BERA_EID
        ];
        uint64[_REMOTE_CHAIN_COUNT] memory remoteConfs = [
            LZConfigLib.ARB_OUTBOUND_CONFIRMATIONS,
            LZConfigLib.OPT_OUTBOUND_CONFIRMATIONS,
            LZConfigLib.BASE_OUTBOUND_CONFIRMATIONS,
            LZConfigLib.BERA_OUTBOUND_CONFIRMATIONS
        ];

        for (uint256 i = 0; i < _REMOTE_CHAIN_COUNT; ++i) {
            _validateLibraries(gw, ep, remoteEids[i]);
            _validateSendConfig(gw, ep, remoteEids[i]);
            _validateRecvConfig(gw, ep, remoteEids[i], remoteConfs[i]);
        }
    }

    function _validateLibraries(
        LZBridgeGateway gw,
        ILayerZeroEndpointV2 ep,
        uint32 eid
    ) internal view {
        require(
            ep.getSendLibrary(address(gw), eid) == LZConfigLib.ETH_SEND_ULN_302,
            "Send library not pinned correctly"
        );
        require(!ep.isDefaultSendLibrary(address(gw), eid), "Send library is still default");
        (address pinnedRecvLib, bool isDefault) = ep.getReceiveLibrary(address(gw), eid);
        require(pinnedRecvLib == LZConfigLib.ETH_RECV_ULN_302, "Receive library not pinned");
        require(!isDefault, "Receive library is still default");
    }

    function _validateSendConfig(
        LZBridgeGateway gw,
        ILayerZeroEndpointV2 ep,
        uint32 eid
    ) internal view {
        bytes memory sendUlnCfg = ep.getConfig(
            address(gw),
            LZConfigLib.ETH_SEND_ULN_302,
            eid,
            LZConfigLib.CONFIG_TYPE_ULN
        );
        require(sendUlnCfg.length > 0, "Send ULN config not set");
        UlnConfig memory sendUln = abi.decode(sendUlnCfg, (UlnConfig));
        require(
            sendUln.confirmations == LZConfigLib.ETH_OUTBOUND_CONFIRMATIONS,
            "Send ULN confirmations mismatch"
        );
        require(sendUln.requiredDVNCount == 2, "Send ULN should require 2 DVNs");

        // Verify DVNs are route-correct
        address[] memory expectedDvns = LZConfigLib.dvnsForRoute(LZConfigLib.ETH_EID, eid);
        require(sendUln.requiredDVNs[0] == expectedDvns[0], "Send ULN DVN[0] mismatch");
        require(sendUln.requiredDVNs[1] == expectedDvns[1], "Send ULN DVN[1] mismatch");

        // Verify app-level config pins optional DVNs to NIL (not inherited from LZ default).
        // `ep.getConfig` returns the resolved config, so we must read the raw app config
        // directly from the SendUln302 library to check the NIL sentinel.
        UlnConfig memory sendAppUln = IUlnConfigState(LZConfigLib.ETH_SEND_ULN_302).getAppUlnConfig(
            address(gw),
            eid
        );
        require(
            sendAppUln.optionalDVNCount == type(uint8).max,
            "Send ULN optional DVNs must be explicit NIL"
        );
        require(sendAppUln.optionalDVNs.length == 0, "Send ULN optional DVNs must be empty");
        require(sendAppUln.optionalDVNThreshold == 0, "Send ULN optional DVN threshold must be 0");

        // Executor
        bytes memory execCfg = ep.getConfig(
            address(gw),
            LZConfigLib.ETH_SEND_ULN_302,
            eid,
            LZConfigLib.CONFIG_TYPE_EXECUTOR
        );
        require(execCfg.length > 0, "Executor config not set");
        ExecutorConfig memory exec = abi.decode(execCfg, (ExecutorConfig));
        require(exec.executor == LZConfigLib.ETH_LZ_EXECUTOR, "Executor address mismatch");
        require(
            exec.maxMessageSize == LZConfigLib.MAX_MESSAGE_SIZE,
            "Executor maxMessageSize mismatch"
        );
    }

    function _validateRecvConfig(
        LZBridgeGateway gw,
        ILayerZeroEndpointV2 ep,
        uint32 eid,
        uint64 expectedConf
    ) internal view {
        bytes memory recvUlnCfg = ep.getConfig(
            address(gw),
            LZConfigLib.ETH_RECV_ULN_302,
            eid,
            LZConfigLib.CONFIG_TYPE_ULN
        );
        require(recvUlnCfg.length > 0, "Recv ULN config not set");
        UlnConfig memory recvUln = abi.decode(recvUlnCfg, (UlnConfig));
        require(recvUln.confirmations == expectedConf, "Recv ULN confirmations mismatch");
        require(recvUln.requiredDVNCount == 2, "Recv ULN should require 2 DVNs");

        // Verify DVNs are route-correct
        address[] memory expectedDvns = LZConfigLib.dvnsForRoute(LZConfigLib.ETH_EID, eid);
        require(recvUln.requiredDVNs[0] == expectedDvns[0], "Recv ULN DVN[0] mismatch");
        require(recvUln.requiredDVNs[1] == expectedDvns[1], "Recv ULN DVN[1] mismatch");

        // Verify app-level config pins optional DVNs to NIL (not inherited from LZ default)
        UlnConfig memory recvAppUln = IUlnConfigState(LZConfigLib.ETH_RECV_ULN_302).getAppUlnConfig(
            address(gw),
            eid
        );
        require(
            recvAppUln.optionalDVNCount == type(uint8).max,
            "Recv ULN optional DVNs must be explicit NIL"
        );
        require(recvAppUln.optionalDVNs.length == 0, "Recv ULN optional DVNs must be empty");
        require(recvAppUln.optionalDVNThreshold == 0, "Recv ULN optional DVN threshold must be 0");
    }

    function _validatePeers(LZBridgeGateway gw, LZBridgeActivator activator) internal view {
        uint32[_REMOTE_CHAIN_COUNT] memory remoteEids = [
            LZConfigLib.ARB_EID,
            LZConfigLib.OPT_EID,
            LZConfigLib.BASE_EID,
            LZConfigLib.BERA_EID
        ];
        address[_REMOTE_CHAIN_COUNT] memory remoteGateways = [
            activator.ARB_GATEWAY(),
            activator.OPT_GATEWAY(),
            activator.BASE_GATEWAY(),
            activator.BERA_GATEWAY()
        ];

        for (uint256 i = 0; i < _REMOTE_CHAIN_COUNT; ++i) {
            bytes32 peer = gw.peers(remoteEids[i]);
            require(peer == LZConfigLib.addressToBytes32(remoteGateways[i]), "Peer mismatch");
        }
    }

    function _validateEnforcedOptions(LZBridgeGateway gw) internal view {
        uint32[_REMOTE_CHAIN_COUNT] memory remoteEids = [
            LZConfigLib.ARB_EID,
            LZConfigLib.OPT_EID,
            LZConfigLib.BASE_EID,
            LZConfigLib.BERA_EID
        ];

        bytes memory expected = abi.encodePacked(
            uint16(3),
            uint8(1),
            uint16(17),
            uint8(1),
            uint128(200_000)
        );
        bytes32 expectedHash = keccak256(expected);

        for (uint256 i = 0; i < _REMOTE_CHAIN_COUNT; ++i) {
            bytes memory opts = gw.enforcedOptions(remoteEids[i], gw.MSG_BRIDGE_OHM());
            require(keccak256(opts) == expectedHash, "Enforced options mismatch");
        }
    }

    // ========== INTERNAL HELPERS ========== //

    /// @notice Reverts if the address is zero, including the registry key in the message.
    // solhint-disable-next-line custom-errors
    function _requireNonZeroAddress(address addr_, string memory key_) internal pure {
        require(addr_ != address(0), string.concat(key_, " address is zero"));
    }
}

contract LZBridgeSecurityUpgradeProposalScript is ProposalScript {
    constructor() ProposalScript(new LZBridgeSecurityUpgradeProposal()) {}
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
