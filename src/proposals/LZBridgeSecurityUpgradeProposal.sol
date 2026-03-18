// SPDX-License-Identifier: MIT
/// forge-lint: disable-start(mixed-case-function, mixed-case-variable)
// solhint-disable one-contract-per-file
// solhint-disable custom-errors
pragma solidity >=0.8.20;

// OCG Proposal Simulator
import {Addresses} from "proposal-sim/addresses/Addresses.sol";
import {GovernorBravoProposal} from "proposal-sim/proposals/OlympusGovernorBravoProposal.sol";

// Script
import {ProposalScript} from "src/proposals/ProposalScript.sol";

// Libraries
import {LZConfigLib} from "src/libraries/LZConfigLib.sol";

// Interfaces
import {ILayerZeroEndpointV2} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {SetConfigParam} from "@lz-evm-protocol-v2-3.0.162/interfaces/IMessageLibManager.sol";
import {ILZEndpointV2Admin} from "src/policies/interfaces/ILZEndpointV2Admin.sol";

// Contracts
import {Kernel, Policy} from "src/Kernel.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {LZBridgeGateway} from "src/policies/bridge/LZBridgeGateway.sol";
import {ILZBridgeGateway} from "src/policies/interfaces/ILZBridgeGateway.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

/// @notice OCG proposal for the LayerZero Bridge Security Upgrade.
///         Replaces the old CrossChainBridge with a hardened LZBridgeGateway policy
///         that separates infrastructure from user-facing concerns, caps bridged supply,
///         and migrates to LayerZero V2 with explicit endpoint configuration, eliminating drag-along vulnerability.
///         The periphery LZCrossChainBridge is configured separately by the DAO MS.
///
///         Assumes:
///         - LZBridgeGateway has been deployed on Ethereum mainnet.
///         - Remote LZBridgeGateway instances have been deployed on Arbitrum, Optimism, and Base.
///         - DAO MS has already activated LZBridgeGateway in the Kernel.
contract LZBridgeSecurityUpgradeProposal is GovernorBravoProposal {
    Kernel internal _kernel;

    // ========== CONSTANTS ========== //

    // TODO: Set before submission
    uint256 public constant BRIDGED_SUPPLY_CAP = 0;

    // TODO: Set before submission (deployed remote gateway addresses)
    address public constant ARB_GATEWAY = address(0);
    address public constant OPT_GATEWAY = address(0);
    address public constant BASE_GATEWAY = address(0);

    /// @dev Number of remote chains (Arbitrum, Optimism, Base).
    uint256 internal constant _REMOTE_CHAIN_COUNT = 3;

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
                "- A cap on the total supply bridged out from Ethereum, limiting blast radius. Combined with an underflow check on inbound receives, this prevents unlimited mints from non-canonical chains.\n",
                "- Separation into an infrastructure policy (LZBridgeGateway) that handles privileged operations and a user-facing periphery contract (LZCrossChainBridge), following the pattern established by the CCIP bridge.\n",
                "- Hardened bridge operations: send and receive are blocked while the bridge is disabled; the custom failed-message retry mechanism is removed in favour of native LayerZero V2 message delivery, which enforces peer validation on retry and eliminates the risk of replaying messages from untrusted senders.\n",
                "- Migration from default LayerZero V1 configuration to explicitly pinned V2 endpoint configuration (SendUln302/ReceiveUln302 libraries, DVN and Executor config), eliminating the drag-along vulnerability and the proof library substitution attack vector. Verification with dual-DVN confirmation.\n",
                "- Introduction of per-endpoint rate limiting on both outbound and inbound transfers, providing a time-windowed throttle independent of the supply cap. Rate limits are left unconfigured by default and configured separately as needed.\n",
                "- Replacement of the LayerZero V1 endpoint's forceResumeReceive with native V2 message recovery primitives (skip, nilify, burn, clear), administered by the bridge_admin role.\n",
                "- Replacement of LayerZero V1 endpoint adapter parameters with enforced Type 3 options that guarantee minimum destination gas per message. The gateway supports combining enforced options with caller-supplied options at send time, enabling future facilitator upgrades; the current LZCrossChainBridge facilitator passes no extra options.\n",
                "- Retained mint/burn model to avoid supply inflation and double-counting.\n",
                "\n",
                "## Resources\n",
                "\n",
                "- TODO: Add link to audit report\n",
                "- TODO: Add link to PR\n",
                "- TODO: Add RFC/OIP reference\n",
                "\n",
                "## Assumptions\n",
                "\n",
                "- LZBridgeGateway has been deployed on Ethereum.\n",
                "- Remote LZBridgeGateway instances have been deployed on Arbitrum, Optimism, and Base.\n",
                "- The DAO MS has already activated LZBridgeGateway in the Kernel.\n",
                "\n",
                "## Proposal Steps\n",
                "\n",
                "1. Grant the `bridge_admin` role to the DAO MS.\n",
                "2. Configure LayerZero V2 Endpoint: pin send/receive libraries to SendUln302/ReceiveUln302, set ULN verification config (dual-DVN: LayerZero DVN + Google Cloud DVN, with per-chain confirmation requirements) and Executor config per remote chain (Arbitrum, Optimism, Base).\n",
                "3. Set peers for Arbitrum, Optimism, and Base.\n",
                // TODO: Update the value before submission
                "4. Set the bridged supply cap to ... OHM.\n",
                "5. Set enforced options: 200,000 gas minimum for lzReceive execution on each destination chain (Arbitrum, Optimism, Base).\n",
                "6. Enable the LZBridgeGateway policy.\n",
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
        ROLESv1 roles = ROLESv1(addresses.getAddress("olympus-module-roles"));
        address rolesAdmin = addresses.getAddress("olympus-policy-roles-admin");
        address daoMS = addresses.getAddress("olympus-multisig-dao");
        address lzBridgeGateway = addresses.getAddress("olympus-policy-lz-bridge-gateway");

        // 1. Grant bridge_admin role to DAO MS (conditional, saveRole reverts on duplicate)
        /// forge-lint: disable-next-line(unsafe-typecast)
        if (!roles.hasRole(daoMS, bytes32("bridge_admin"))) {
            _pushAction(
                rolesAdmin,
                abi.encodeWithSelector(
                    RolesAdmin.grantRole.selector,
                    /// forge-lint: disable-next-line(unsafe-typecast)
                    bytes32("bridge_admin"),
                    daoMS
                ),
                "Grant bridge_admin role to DAO MS"
            );
        }

        // 2. Configure LZ V2 endpoint (libraries + ULN/Executor config)
        _buildLZConfig(lzBridgeGateway);

        // 3. Set peers
        _buildPeers(lzBridgeGateway);

        // 4. Set bridged supply cap (onlyAdminRole)
        _pushAction(
            lzBridgeGateway,
            abi.encodeWithSelector(
                LZBridgeGateway.setBridgedSupplyCap.selector,
                BRIDGED_SUPPLY_CAP
            ),
            "Set bridged supply cap on LZBridgeGateway"
        );

        // 5. Set enforced options
        _buildEnforcedOptions(lzBridgeGateway);

        // 6. Enable LZBridgeGateway (Policy, onlyAdminRole)
        _pushAction(
            lzBridgeGateway,
            abi.encodeWithSelector(PolicyEnabler.enable.selector, ""),
            "Enable LZBridgeGateway policy"
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
        ILayerZeroEndpointV2 ep = ILayerZeroEndpointV2(LZConfigLib.LZ_ENDPOINT);

        // 1. Validate LZBridgeGateway is active in the Kernel (activated by MS before OCG)
        require(Policy(address(gw)).isActive(), "LZBridgeGateway policy is not active");

        // 2. Validate LZBridgeGateway is enabled
        require(PolicyEnabler(address(gw)).isEnabled(), "LZBridgeGateway is not enabled");

        // 3. Validate DAO MS has bridge_admin role
        require(
            /// forge-lint: disable-next-line(unsafe-typecast)
            roles.hasRole(daoMS, bytes32("bridge_admin")),
            "DAO MS does not have bridge_admin role"
        );

        // 4. Validate bridged supply cap is set
        require(gw.bridgedSupplyCap() == BRIDGED_SUPPLY_CAP, "Bridged supply cap does not match");

        // 5. Validate per-remote LZ config
        _validateLZConfig(gw, ep);

        // 6. Validate peers
        _validatePeers(gw);

        // 7. Validate enforced options set
        _validateEnforcedOptions(gw);
    }

    // ========== LZ CONFIG BUILDERS ========== //

    /// @dev Pushes LZ V2 endpoint configuration actions via the gateway:
    ///      pin libraries + set ULN/Executor config per remote chain.
    function _buildLZConfig(address gateway_) internal {
        address sendLib = LZConfigLib.ETH_SEND_ULN_302;
        address recvLib = LZConfigLib.ETH_RECV_ULN_302;
        address[] memory dvns = _getDVNs();

        uint32[_REMOTE_CHAIN_COUNT] memory remoteEids = [
            LZConfigLib.ARB_EID,
            LZConfigLib.OPT_EID,
            LZConfigLib.BASE_EID
        ];
        uint64[_REMOTE_CHAIN_COUNT] memory remoteConfs = [
            LZConfigLib.ARB_OUTBOUND_CONFIRMATIONS,
            LZConfigLib.OPT_OUTBOUND_CONFIRMATIONS,
            LZConfigLib.BASE_OUTBOUND_CONFIRMATIONS
        ];

        for (uint256 i = 0; i < _REMOTE_CHAIN_COUNT; ++i) {
            uint32 eid = remoteEids[i];

            // Pin send library
            _pushAction(
                gateway_,
                abi.encodeCall(ILZEndpointV2Admin.setSendLibrary, (eid, sendLib)),
                "Pin send library"
            );

            // Pin receive library (gracePeriod = 0 for immediate)
            _pushAction(
                gateway_,
                abi.encodeCall(ILZEndpointV2Admin.setReceiveLibrary, (eid, recvLib, 0)),
                "Pin receive library"
            );

            // Send ULN + Executor config
            SetConfigParam[] memory sendParams = new SetConfigParam[](2);
            sendParams[0] = SetConfigParam({
                eid: eid,
                configType: LZConfigLib.CONFIG_TYPE_ULN,
                config: LZConfigLib.encodeUlnConfig(LZConfigLib.ETH_OUTBOUND_CONFIRMATIONS, dvns)
            });
            sendParams[1] = SetConfigParam({
                eid: eid,
                configType: LZConfigLib.CONFIG_TYPE_EXECUTOR,
                config: LZConfigLib.encodeExecutorConfig()
            });
            _pushAction(
                gateway_,
                abi.encodeCall(ILZEndpointV2Admin.setEndpointConfig, (sendLib, sendParams)),
                "Set send ULN + Executor config"
            );

            // Receive ULN config (inbound = remote chain's outbound confirmations)
            SetConfigParam[] memory recvParams = new SetConfigParam[](1);
            recvParams[0] = SetConfigParam({
                eid: eid,
                configType: LZConfigLib.CONFIG_TYPE_ULN,
                config: LZConfigLib.encodeUlnConfig(remoteConfs[i], dvns)
            });
            _pushAction(
                gateway_,
                abi.encodeCall(ILZEndpointV2Admin.setEndpointConfig, (recvLib, recvParams)),
                "Set receive ULN config"
            );
        }
    }

    /// @dev Pushes setPeer actions for non-zero remote gateway addresses.
    function _buildPeers(address gateway_) internal {
        uint32[_REMOTE_CHAIN_COUNT] memory remoteEids = [
            LZConfigLib.ARB_EID,
            LZConfigLib.OPT_EID,
            LZConfigLib.BASE_EID
        ];
        address[_REMOTE_CHAIN_COUNT] memory remoteGateways = [
            ARB_GATEWAY,
            OPT_GATEWAY,
            BASE_GATEWAY
        ];

        for (uint256 i = 0; i < _REMOTE_CHAIN_COUNT; ++i) {
            if (remoteGateways[i] == address(0)) continue;

            _pushAction(
                gateway_,
                abi.encodeCall(
                    ILZBridgeGateway.setPeer,
                    (remoteEids[i], LZConfigLib.addressToBytes32(remoteGateways[i]))
                ),
                "Set peer"
            );
        }
    }

    /// @dev Pushes setEnforcedOptions action for all remote EIDs.
    function _buildEnforcedOptions(address gateway_) internal {
        uint32[_REMOTE_CHAIN_COUNT] memory remoteEids = [
            LZConfigLib.ARB_EID,
            LZConfigLib.OPT_EID,
            LZConfigLib.BASE_EID
        ];

        ILZBridgeGateway.EnforcedOptionParam[]
            memory opts = new ILZBridgeGateway.EnforcedOptionParam[](_REMOTE_CHAIN_COUNT);

        for (uint256 i = 0; i < _REMOTE_CHAIN_COUNT; ++i) {
            // Type 3 options: WORKER_ID=1, size=17, OPTION_TYPE_LZRECEIVE=1, gas=200k
            opts[i] = ILZBridgeGateway.EnforcedOptionParam({
                eid: remoteEids[i],
                msgType: 1, // MSG_BRIDGE_OHM
                options: abi.encodePacked(
                    uint16(3),
                    uint8(1),
                    uint16(17),
                    uint8(1),
                    uint128(200_000)
                )
            });
        }

        _pushAction(
            gateway_,
            abi.encodeCall(ILZBridgeGateway.setEnforcedOptions, (opts)),
            "Set enforced options"
        );
    }

    // ========== VALIDATION HELPERS ========== //

    function _validateLZConfig(LZBridgeGateway gw, ILayerZeroEndpointV2 ep) internal view {
        uint32[_REMOTE_CHAIN_COUNT] memory remoteEids = [
            LZConfigLib.ARB_EID,
            LZConfigLib.OPT_EID,
            LZConfigLib.BASE_EID
        ];
        uint64[_REMOTE_CHAIN_COUNT] memory remoteConfs = [
            LZConfigLib.ARB_OUTBOUND_CONFIRMATIONS,
            LZConfigLib.OPT_OUTBOUND_CONFIRMATIONS,
            LZConfigLib.BASE_OUTBOUND_CONFIRMATIONS
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
        // Send ULN
        bytes memory sendUlnCfg = ep.getConfig(
            address(gw),
            LZConfigLib.ETH_SEND_ULN_302,
            eid,
            LZConfigLib.CONFIG_TYPE_ULN
        );
        require(sendUlnCfg.length > 0, "Send ULN config not set");
        LZConfigLib.UlnConfig memory sendUln = abi.decode(sendUlnCfg, (LZConfigLib.UlnConfig));
        require(
            sendUln.confirmations == LZConfigLib.ETH_OUTBOUND_CONFIRMATIONS,
            "Send ULN confirmations mismatch"
        );
        require(sendUln.requiredDVNCount == 2, "Send ULN should require 2 DVNs");

        // Executor
        bytes memory execCfg = ep.getConfig(
            address(gw),
            LZConfigLib.ETH_SEND_ULN_302,
            eid,
            LZConfigLib.CONFIG_TYPE_EXECUTOR
        );
        require(execCfg.length > 0, "Executor config not set");
        LZConfigLib.ExecutorConfig memory exec = abi.decode(execCfg, (LZConfigLib.ExecutorConfig));
        require(exec.executor == LZConfigLib.LZ_EXECUTOR, "Executor address mismatch");
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
        LZConfigLib.UlnConfig memory recvUln = abi.decode(recvUlnCfg, (LZConfigLib.UlnConfig));
        require(recvUln.confirmations == expectedConf, "Recv ULN confirmations mismatch");
        require(recvUln.requiredDVNCount == 2, "Recv ULN should require 2 DVNs");
    }

    function _validatePeers(LZBridgeGateway gw) internal view {
        uint32[_REMOTE_CHAIN_COUNT] memory remoteEids = [
            LZConfigLib.ARB_EID,
            LZConfigLib.OPT_EID,
            LZConfigLib.BASE_EID
        ];
        address[_REMOTE_CHAIN_COUNT] memory remoteGateways = [
            ARB_GATEWAY,
            OPT_GATEWAY,
            BASE_GATEWAY
        ];

        for (uint256 i = 0; i < _REMOTE_CHAIN_COUNT; ++i) {
            bytes32 peer = gw.peers(remoteEids[i]);
            if (remoteGateways[i] == address(0)) {
                require(peer == bytes32(0), "Peer should be empty for zero gateway");
            } else {
                require(peer == LZConfigLib.addressToBytes32(remoteGateways[i]), "Peer mismatch");
            }
        }
    }

    function _validateEnforcedOptions(LZBridgeGateway gw) internal view {
        uint32[_REMOTE_CHAIN_COUNT] memory remoteEids = [
            LZConfigLib.ARB_EID,
            LZConfigLib.OPT_EID,
            LZConfigLib.BASE_EID
        ];

        // Expected: Type 3, WORKER_ID=1 (Executor), size=17, OPTION_TYPE_LZRECEIVE=1, gas=200k
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

    // ========== DVN HELPERS ========== //

    /// @dev Returns DVNs sorted ascending: [ETH_LZ_DVN, GCLOUD_DVN].
    function _getDVNs() internal pure returns (address[] memory dvns) {
        dvns = new address[](2);
        // ETH_LZ_DVN (0x589d...) < GCLOUD_DVN (0xD56e...)
        dvns[0] = LZConfigLib.ETH_LZ_DVN;
        dvns[1] = LZConfigLib.GCLOUD_DVN;
    }
}

contract LZBridgeSecurityUpgradeProposalScript is ProposalScript {
    constructor() ProposalScript(new LZBridgeSecurityUpgradeProposal()) {}
}
/// forge-lint: disable-end(mixed-case-function, mixed-case-variable)
