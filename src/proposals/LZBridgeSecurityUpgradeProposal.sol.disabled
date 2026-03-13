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
import {ILayerZeroEndpointV2} from "@lz-evm-protocol-v2-3.0.142/interfaces/ILayerZeroEndpointV2.sol";
import {SetConfigParam} from "@lz-evm-protocol-v2-3.0.142/interfaces/IMessageLibManager.sol";

// Contracts
import {Kernel, Policy} from "src/Kernel.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {LZBridgeGateway} from "src/policies/bridge/LZBridgeGateway.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

/// @notice OCG proposal for the LayerZero Bridge Security Upgrade.
///         Replaces the old CrossChainBridge with a hardened LZBridgeGateway policy
///         that separates infrastructure from user-facing concerns, caps bridged supply,
///         and pins LayerZero V2 ULN302 configuration (DVNs + Executor).
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
                "- A cap on the supply that can be bridged back to Ethereum, limiting blast radius and protecting against unlimited inbound mints.\n",
                "- Separation into an infrastructure policy (LZBridgeGateway) and a user-facing periphery contract (LZCrossChainBridge), following the pattern established by the CCIP bridge. The infrastructure policy is activated in the Kernel and handles all privileged operations (minting, burning, supply tracking, peer management). The periphery contract provides the user-facing interface and is configured separately by the DAO MS.\n",
                "- Hardened bridge operations: send and receive are blocked while the bridge is disabled, and peers are always verified.\n",
                "- Migration from Endpoint V1 to V2 with ULN302 message libraries. ULN302 uses configurable Decentralized Verifier Networks (DVNs) and a separate Executor, eliminating the proof library substitution attack vector. The send and receive libraries are explicitly set per remote chain, and per-chain ULN and Executor configs are set via endpoint setConfig calls, ensuring the bridge does not rely on LayerZero endpoint defaults. Verification with dual-DVN confirmation.\n",
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
                "2. Configure LayerZero V2 Endpoint settings: set send/receive libraries to ULN302, set ULN verification config (dual-DVN: LayerZero DVN + Google Cloud DVN, with per-chain confirmation requirements) and Executor config per remote chain (Arbitrum, Optimism, Base).\n",
                "3. Set peers for Arbitrum, Optimism, and Base.\n",
                // TODO: Update the value before submission
                "4. Set the bridged supply cap to ... OHM.\n",
                "5. Enable the LZBridgeGateway policy.\n",
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

        // 2. Configure LZ V2 endpoint libraries and per-remote config
        _buildLZConfig(lzBridgeGateway);

        // 3. Set peers (conditional - only if remote addresses are set)
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

        // 5. Enable LZBridgeGateway (Policy, onlyAdminRole)
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

        // 5. Validate LZ V2 libraries are set
        ILayerZeroEndpointV2 endpoint = ILayerZeroEndpointV2(LZConfigLib.LZ_ENDPOINT);
        _validateLZLibraries(endpoint, gw);

        // 6. Validate per-remote LZ config (ULN + Executor) for each remote chain
        _validateLZConfig(endpoint, gw);

        // 7. Validate peers
        _validatePeers(gw);
    }

    /// @dev Validates send/receive libraries are set (not using defaults).
    function _validateLZLibraries(
        ILayerZeroEndpointV2 endpoint_,
        LZBridgeGateway gw
    ) internal view {
        uint32[_REMOTE_CHAIN_COUNT] memory remoteEids = [
            LZConfigLib.ARB_EID,
            LZConfigLib.OPT_EID,
            LZConfigLib.BASE_EID
        ];

        for (uint256 i = 0; i < _REMOTE_CHAIN_COUNT; ++i) {
            address sendLib = endpoint_.getSendLibrary(address(gw), remoteEids[i]);
            require(sendLib != address(0), "Send library not set");
            require(
                !endpoint_.isDefaultSendLibrary(address(gw), remoteEids[i]),
                "Send library is still default"
            );

            (address recvLib, bool isDefault) = endpoint_.getReceiveLibrary(
                address(gw),
                remoteEids[i]
            );
            require(recvLib != address(0), "Receive library not set");
            require(!isDefault, "Receive library is still default");
        }
    }

    /// @dev Validates send ULN, executor, and receive ULN config for each remote chain.
    function _validateLZConfig(ILayerZeroEndpointV2 endpoint_, LZBridgeGateway gw) internal view {
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

        address sendLib = LZConfigLib.ETH_SEND_ULN_302;
        address recvLib = LZConfigLib.ETH_RECEIVE_ULN_302;

        for (uint256 i = 0; i < _REMOTE_CHAIN_COUNT; ++i) {
            // Send ULN config
            bytes memory sendCfg = endpoint_.getConfig(
                address(gw),
                sendLib,
                remoteEids[i],
                LZConfigLib.CONFIG_TYPE_ULN
            );
            require(sendCfg.length > 0, "Send ULN config not set");
            LZConfigLib.UlnConfig memory sendUln = abi.decode(sendCfg, (LZConfigLib.UlnConfig));
            require(
                sendUln.confirmations == LZConfigLib.ETH_OUTBOUND_CONFIRMATIONS,
                "Send ULN confirmations mismatch"
            );
            require(sendUln.requiredDVNCount == 2, "Send ULN should require 2 DVNs");

            // Executor config
            bytes memory execCfg = endpoint_.getConfig(
                address(gw),
                sendLib,
                remoteEids[i],
                LZConfigLib.CONFIG_TYPE_EXECUTOR
            );
            require(execCfg.length > 0, "Executor config not set");
            LZConfigLib.ExecutorConfig memory exec = abi.decode(
                execCfg,
                (LZConfigLib.ExecutorConfig)
            );
            require(exec.executor == LZConfigLib.LZ_EXECUTOR, "Executor address mismatch");
            require(
                exec.maxMessageSize == LZConfigLib.MAX_MESSAGE_SIZE,
                "Executor maxMessageSize mismatch"
            );

            // Receive ULN config
            bytes memory recvCfg = endpoint_.getConfig(
                address(gw),
                recvLib,
                remoteEids[i],
                LZConfigLib.CONFIG_TYPE_ULN
            );
            require(recvCfg.length > 0, "Recv ULN config not set");
            LZConfigLib.UlnConfig memory recvUln = abi.decode(recvCfg, (LZConfigLib.UlnConfig));
            require(recvUln.confirmations == remoteConfs[i], "Recv ULN confirmations mismatch");
            require(recvUln.requiredDVNCount == 2, "Recv ULN should require 2 DVNs");
        }
    }

    /// @dev Validates peers are set for non-zero gateway addresses.
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

    // ========== LZ CONFIG BUILDERS ========== //

    /// @dev Pushes LZ V2 endpoint configuration actions: libraries + per-remote ULN/Executor config.
    function _buildLZConfig(address gateway_) internal {
        address sendLib = LZConfigLib.ETH_SEND_ULN_302;
        address recvLib = LZConfigLib.ETH_RECEIVE_ULN_302;
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

        // Set send and receive libraries per remote chain
        for (uint256 i = 0; i < _REMOTE_CHAIN_COUNT; ++i) {
            _pushAction(
                gateway_,
                abi.encodeWithSelector(
                    LZBridgeGateway.setSendLibrary.selector,
                    remoteEids[i],
                    sendLib
                ),
                "Set LZ send library"
            );
            _pushAction(
                gateway_,
                abi.encodeWithSelector(
                    LZBridgeGateway.setReceiveLibrary.selector,
                    remoteEids[i],
                    recvLib,
                    0
                ),
                "Set LZ receive library"
            );
        }

        // Build send config params (ULN + Executor)
        SetConfigParam[] memory sendParams = new SetConfigParam[](_REMOTE_CHAIN_COUNT * 2);
        for (uint256 i = 0; i < _REMOTE_CHAIN_COUNT; ++i) {
            sendParams[i * 2] = SetConfigParam({
                eid: remoteEids[i],
                configType: LZConfigLib.CONFIG_TYPE_ULN,
                config: LZConfigLib.encodeUlnConfig(LZConfigLib.ETH_OUTBOUND_CONFIRMATIONS, dvns)
            });
            sendParams[i * 2 + 1] = SetConfigParam({
                eid: remoteEids[i],
                configType: LZConfigLib.CONFIG_TYPE_EXECUTOR,
                config: LZConfigLib.encodeExecutorConfig()
            });
        }
        _pushAction(
            gateway_,
            abi.encodeWithSelector(
                LZBridgeGateway.setLZConfig.selector,
                sendLib,
                abi.encode(sendParams)
            ),
            "Set LZ send ULN and executor config"
        );

        // Build receive config params (ULN only)
        SetConfigParam[] memory recvParams = new SetConfigParam[](_REMOTE_CHAIN_COUNT);
        for (uint256 i = 0; i < _REMOTE_CHAIN_COUNT; ++i) {
            recvParams[i] = SetConfigParam({
                eid: remoteEids[i],
                configType: LZConfigLib.CONFIG_TYPE_ULN,
                config: LZConfigLib.encodeUlnConfig(remoteConfs[i], dvns)
            });
        }
        _pushAction(
            gateway_,
            abi.encodeWithSelector(
                LZBridgeGateway.setLZConfig.selector,
                recvLib,
                abi.encode(recvParams)
            ),
            "Set LZ receive ULN config"
        );
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
                abi.encodeWithSelector(
                    LZBridgeGateway.setPeer.selector,
                    remoteEids[i],
                    remoteGateways[i]
                ),
                "Set peer"
            );
        }
    }

    // ========== LZ ENCODING HELPERS ========== //

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
