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
import {ILayerZeroEndpoint} from "@layer-zero-endpoint-v1-1.1.0/lzApp/interfaces/ILayerZeroEndpoint.sol";

// Contracts
import {Kernel, Policy} from "src/Kernel.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {LZBridgeGateway} from "src/policies/bridge/LZBridgeGateway.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

/// @notice OCG proposal for the LayerZero Bridge Security Upgrade.
///         Replaces the old CrossChainBridge with a hardened LZBridgeGateway policy
///         that separates infrastructure from user-facing concerns, caps bridged supply,
///         and pins LayerZero ULN301 configuration (DVNs + Executor).
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
                "- Separation into an infrastructure policy (LZBridgeGateway) and a user-facing periphery contract (LZCrossChainBridge), following the pattern established by the CCIP bridge. The infrastructure policy is activated in the Kernel and handles all privileged operations (minting, burning, supply tracking, trusted remote management). The periphery contract provides the user-facing interface and is configured separately by the DAO MS.\n",
                "- Hardened bridge operations: send and receive are blocked while the bridge is disabled, and trusted remotes are always respected (including for failed message retries).\n",
                "- Migration from the default ULNv2 messaging library to ULN301, a v2-compatible MessageLib registered on Endpoint V1. ULN301 replaces the Oracle + Relayer model with a configurable set of Decentralized Verifier Networks (DVNs) and a separate Executor, architecturally eliminating the proof library substitution attack vector to protect against drag-along attacks. The send and receive library versions are explicitly pinned, and per-chain ULN and Executor configs are set via on-chain `setConfig` calls, ensuring the bridge does not rely on LayerZero endpoint defaults. Verification with dual-DVN confirmation.\n",
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
                "2. Configure LayerZero Endpoint V1 settings: pin send/receive messaging library versions to ULN301, set ULN verification config (dual-DVN: LayerZero DVN + Google Cloud DVN, with per-chain confirmation requirements) and Executor config per remote chain (Arbitrum, Optimism, Base).\n",
                "3. Set trusted remotes for Arbitrum, Optimism, and Base.\n",
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

        // 2. Configure LZ endpoint versions and per-remote config
        _buildLZConfig(lzBridgeGateway);

        // 3. Set trusted remotes (conditional - only if remote addresses are set)
        _buildTrustedRemotes(lzBridgeGateway);

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

        // 5. Validate LZ versions are pinned
        ILayerZeroEndpoint endpoint = ILayerZeroEndpoint(LZConfigLib.LZ_ENDPOINT);
        uint16 sendVer = endpoint.getSendVersion(address(gw));
        uint16 recvVer = endpoint.getReceiveVersion(address(gw));
        require(sendVer > 0, "LZ send version is not pinned");
        require(recvVer > 0, "LZ receive version is not pinned");
        require(recvVer == sendVer + 1, "LZ receive version should be send version + 1");

        // 6. Validate per-remote LZ config (ULN + Executor) for each remote chain
        _validateLZConfig(gw, sendVer, recvVer);

        // 7. Validate trusted remotes
        _validateTrustedRemotes(gw);
    }

    /// @dev Validates send ULN, executor, and receive ULN config for each remote chain.
    function _validateLZConfig(LZBridgeGateway gw, uint16 sendVer_, uint16 recvVer_) internal view {
        uint16[_REMOTE_CHAIN_COUNT] memory remoteIds = [
            LZConfigLib.ARB_CHAIN_ID,
            LZConfigLib.OPT_CHAIN_ID,
            LZConfigLib.BASE_CHAIN_ID
        ];
        uint64[_REMOTE_CHAIN_COUNT] memory remoteConfs = [
            LZConfigLib.ARB_OUTBOUND_CONFIRMATIONS,
            LZConfigLib.OPT_OUTBOUND_CONFIRMATIONS,
            LZConfigLib.BASE_OUTBOUND_CONFIRMATIONS
        ];

        for (uint256 i = 0; i < _REMOTE_CHAIN_COUNT; ++i) {
            // Send ULN config
            bytes memory sendCfg = gw.getConfig(
                sendVer_,
                remoteIds[i],
                address(gw),
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
            bytes memory execCfg = gw.getConfig(
                sendVer_,
                remoteIds[i],
                address(gw),
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
            bytes memory recvCfg = gw.getConfig(
                recvVer_,
                remoteIds[i],
                address(gw),
                LZConfigLib.CONFIG_TYPE_ULN
            );
            require(recvCfg.length > 0, "Recv ULN config not set");
            LZConfigLib.UlnConfig memory recvUln = abi.decode(recvCfg, (LZConfigLib.UlnConfig));
            require(recvUln.confirmations == remoteConfs[i], "Recv ULN confirmations mismatch");
            require(recvUln.requiredDVNCount == 2, "Recv ULN should require 2 DVNs");
        }
    }

    /// @dev Validates trusted remotes are set for non-zero gateway addresses.
    function _validateTrustedRemotes(LZBridgeGateway gw) internal view {
        uint16[_REMOTE_CHAIN_COUNT] memory remoteIds = [
            LZConfigLib.ARB_CHAIN_ID,
            LZConfigLib.OPT_CHAIN_ID,
            LZConfigLib.BASE_CHAIN_ID
        ];
        address[_REMOTE_CHAIN_COUNT] memory remoteGateways = [
            ARB_GATEWAY,
            OPT_GATEWAY,
            BASE_GATEWAY
        ];

        for (uint256 i = 0; i < _REMOTE_CHAIN_COUNT; ++i) {
            bytes memory path = gw.trustedRemoteLookup(remoteIds[i]);
            if (remoteGateways[i] == address(0)) {
                require(path.length == 0, "Trusted remote should be empty for zero gateway");
            } else {
                require(
                    path.length == LZConfigLib.TRUSTED_REMOTE_PATH_LENGTH,
                    "Trusted remote path should be 40 bytes"
                );
                require(
                    keccak256(path) == keccak256(abi.encodePacked(remoteGateways[i], address(gw))),
                    "Trusted remote path mismatch"
                );
            }
        }
    }

    // ========== LZ CONFIG BUILDERS ========== //

    /// @dev Pushes LZ endpoint configuration actions: versions + per-remote ULN/Executor config.
    function _buildLZConfig(address gateway_) internal {
        (uint16 sendVer, uint16 recvVer) = LZConfigLib.getUln301Versions(LZConfigLib.LZ_ENDPOINT);
        address[] memory dvns = _getDVNs();
        bytes memory ulnSendConfig = LZConfigLib.encodeUlnConfig(
            LZConfigLib.ETH_OUTBOUND_CONFIRMATIONS,
            dvns
        );
        bytes memory executorConfig = LZConfigLib.encodeExecutorConfig();

        // Pin send and receive versions
        _pushAction(
            gateway_,
            abi.encodeWithSelector(LZBridgeGateway.setSendVersion.selector, sendVer),
            "Set LZ send version"
        );
        _pushAction(
            gateway_,
            abi.encodeWithSelector(LZBridgeGateway.setReceiveVersion.selector, recvVer),
            "Set LZ receive version"
        );

        // Per-remote chain config
        uint16[_REMOTE_CHAIN_COUNT] memory remoteIds = [
            LZConfigLib.ARB_CHAIN_ID,
            LZConfigLib.OPT_CHAIN_ID,
            LZConfigLib.BASE_CHAIN_ID
        ];
        uint64[_REMOTE_CHAIN_COUNT] memory remoteConfs = [
            LZConfigLib.ARB_OUTBOUND_CONFIRMATIONS,
            LZConfigLib.OPT_OUTBOUND_CONFIRMATIONS,
            LZConfigLib.BASE_OUTBOUND_CONFIRMATIONS
        ];

        for (uint256 i = 0; i < _REMOTE_CHAIN_COUNT; ++i) {
            // Send ULN config (Ethereum outbound confirmations)
            _pushAction(
                gateway_,
                abi.encodeWithSelector(
                    LZBridgeGateway.setConfig.selector,
                    sendVer,
                    remoteIds[i],
                    LZConfigLib.CONFIG_TYPE_ULN,
                    ulnSendConfig
                ),
                "Set LZ send ULN config"
            );

            // Executor config (send side only)
            _pushAction(
                gateway_,
                abi.encodeWithSelector(
                    LZBridgeGateway.setConfig.selector,
                    sendVer,
                    remoteIds[i],
                    LZConfigLib.CONFIG_TYPE_EXECUTOR,
                    executorConfig
                ),
                "Set LZ executor config"
            );

            // Receive ULN config (inbound = remote chain's outbound confirmations)
            _pushAction(
                gateway_,
                abi.encodeWithSelector(
                    LZBridgeGateway.setConfig.selector,
                    recvVer,
                    remoteIds[i],
                    LZConfigLib.CONFIG_TYPE_ULN,
                    LZConfigLib.encodeUlnConfig(remoteConfs[i], dvns)
                ),
                "Set LZ receive ULN config"
            );
        }
    }

    /// @dev Pushes setTrustedRemote actions for non-zero remote gateway addresses.
    function _buildTrustedRemotes(address gateway_) internal {
        uint16[_REMOTE_CHAIN_COUNT] memory remoteIds = [
            LZConfigLib.ARB_CHAIN_ID,
            LZConfigLib.OPT_CHAIN_ID,
            LZConfigLib.BASE_CHAIN_ID
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
                    LZBridgeGateway.setTrustedRemote.selector,
                    remoteIds[i],
                    remoteGateways[i]
                ),
                "Set trusted remote"
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
