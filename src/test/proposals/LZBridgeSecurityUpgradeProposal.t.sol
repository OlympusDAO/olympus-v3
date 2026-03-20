// SPDX-License-Identifier: UNLICENSED
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity ^0.8.0;

import {ProposalTest} from "./ProposalTest.sol";
import {console2} from "forge-std/console2.sol";

// Libraries
import {LZConfigLib} from "src/libraries/LZConfigLib.sol";

// Interfaces
import {ExecutorConfig} from "@lz-evm-messagelib-v2-3.0.162/SendLibBase.sol";
import {UlnConfig} from "@lz-evm-messagelib-v2-3.0.162/uln/UlnBase.sol";
import {ILayerZeroEndpointV2} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";

// Contracts
import {Kernel, Actions, Policy} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {LZBridgeGateway} from "src/policies/bridge/LZBridgeGateway.sol";
import {LZCrossChainBridge} from "src/periphery/bridge/LZCrossChainBridge.sol";
import {IERC20} from "@openzeppelin-5.3.0/token/ERC20/IERC20.sol";

// Proposal
import {LZBridgeSecurityUpgradeProposal} from "src/proposals/LZBridgeSecurityUpgradeProposal.sol";

contract LZBridgeSecurityUpgradeProposalTest is ProposalTest {
    /// @dev Block where timelock already has `admin` + `bridge_admin` roles.
    ///      Update this once the contracts are deployed on mainnet.
    uint256 public constant BLOCK = 24685696;

    /// @dev Number of remote chains (Arbitrum, Optimism, Base).
    uint256 internal constant _REMOTE_CHAIN_COUNT = 3;

    // ========== DEPLOYMENT TOGGLES ==========

    /// @dev Set to true once LZBridgeGateway has been deployed on Ethereum.
    ///      When false, setUp() deploys it locally and registers it in
    ///      the address registry before proposal simulation.
    bool public constant IS_CONTRACTS_DEPLOYED = false;

    // ========== CONTRACTS ==========

    Kernel public kernel;
    LZBridgeGateway public gateway;
    LZBridgeSecurityUpgradeProposal public proposal;
    ROLESv1 public roles;
    IERC20 public ohm;

    // ========== ADDRESSES ==========

    address public daoMS;
    address public timelock;
    address public oldCrossChainBridge;

    function setUp() public virtual {
        // Mainnet fork at a fixed block
        vm.createSelectFork(_RPC_ALIAS, BLOCK);

        // ========== PROPOSAL SETUP ==========

        proposal = new LZBridgeSecurityUpgradeProposal();

        // Set to true once the proposal has been submitted on-chain
        hasBeenSubmitted = false;

        // Initialize test suite and addresses
        _setupSuite(address(proposal));

        // ========== LOAD COMMON ADDRESSES ==========

        kernel = Kernel(addresses.getAddress("olympus-kernel"));
        roles = ROLESv1(addresses.getAddress("olympus-module-roles"));
        ohm = IERC20(addresses.getAddress("olympus-legacy-ohm"));
        daoMS = addresses.getAddress("olympus-multisig-dao");
        timelock = addresses.getAddress("olympus-timelock");
        oldCrossChainBridge = addresses.getAddress("olympus-policy-cross-chain-bridge");

        // ========== CONDITIONAL DEPLOYMENT ==========

        if (IS_CONTRACTS_DEPLOYED) {
            gateway = LZBridgeGateway(addresses.getAddress("olympus-policy-lz-bridge-gateway"));
            console2.log("Contracts already deployed on mainnet");
        } else {
            // Deploy LZCrossChainBridge (periphery, owned by DAO MS - configured via MS batch)
            LZCrossChainBridge bridge = new LZCrossChainBridge(address(ohm), daoMS);
            vm.label(address(bridge), "LZCrossChainBridge");

            // Deploy LZBridgeGateway (policy, canonical on mainnet)
            gateway = new LZBridgeGateway(
                kernel,
                LZConfigLib.LZ_ENDPOINT,
                true, // isCanonical
                address(bridge) // facilitator
            );
            vm.label(address(gateway), "LZBridgeGateway");

            // Register in the address registry
            addresses.addAddress(
                "olympus-policy-lz-bridge-gateway",
                address(gateway),
                block.chainid
            );
            console2.log("Contracts deployed locally");
        }

        // ========== PRE-OCG: MS BATCH 1 ==========

        // Simulate what the DAO MS does before the OCG proposal: activate new LZBridgeGateway
        vm.prank(daoMS);
        kernel.executeAction(Actions.ActivatePolicy, address(gateway));

        // ========== SIMULATE PROPOSAL ==========

        suite.setDebug(true);
        _simulateProposal();

        // Re-read addresses in case simulation updated them
        addresses = suite.addresses();
    }

    // ========== LZ CONFIG VERIFICATION HELPERS ==========

    function _verifySendUlnConfig(uint32 remoteEid_) internal view {
        ILayerZeroEndpointV2 ep = ILayerZeroEndpointV2(LZConfigLib.LZ_ENDPOINT);
        bytes memory cfg = ep.getConfig(
            address(gateway),
            LZConfigLib.ETH_SEND_ULN_302,
            remoteEid_,
            LZConfigLib.CONFIG_TYPE_ULN
        );
        assertGt(cfg.length, 0, "Send ULN config should be set");

        UlnConfig memory uln = abi.decode(cfg, (UlnConfig));
        assertEq(
            uln.confirmations,
            LZConfigLib.ETH_OUTBOUND_CONFIRMATIONS,
            "Send ULN confirmations mismatch"
        );
        assertEq(uln.requiredDVNCount, 2, "Send ULN should require 2 DVNs");
        assertEq(uln.requiredDVNs.length, 2, "Send ULN should have 2 required DVNs");
        // DVNs sorted ascending: ETH_LZ_DVN (0x589d...) < GCLOUD_DVN (0xD56e...)
        assertEq(
            uln.requiredDVNs[0],
            LZConfigLib.ETH_LZ_DVN,
            "Send ULN DVN[0] should be ETH_LZ_DVN"
        );
        assertEq(
            uln.requiredDVNs[1],
            LZConfigLib.GCLOUD_DVN,
            "Send ULN DVN[1] should be GCLOUD_DVN"
        );
        assertEq(uln.optionalDVNCount, 0, "Send ULN should have 0 optional DVNs");
    }

    function _verifyRecvUlnConfig(uint32 remoteEid_, uint64 expectedConfirmations_) internal view {
        ILayerZeroEndpointV2 ep = ILayerZeroEndpointV2(LZConfigLib.LZ_ENDPOINT);
        bytes memory cfg = ep.getConfig(
            address(gateway),
            LZConfigLib.ETH_RECV_ULN_302,
            remoteEid_,
            LZConfigLib.CONFIG_TYPE_ULN
        );
        assertGt(cfg.length, 0, "Recv ULN config should be set");

        UlnConfig memory uln = abi.decode(cfg, (UlnConfig));
        assertEq(uln.confirmations, expectedConfirmations_, "Recv ULN confirmations mismatch");
        assertEq(uln.requiredDVNCount, 2, "Recv ULN should require 2 DVNs");
        assertEq(uln.requiredDVNs.length, 2, "Recv ULN should have 2 required DVNs");
        assertEq(
            uln.requiredDVNs[0],
            LZConfigLib.ETH_LZ_DVN,
            "Recv ULN DVN[0] should be ETH_LZ_DVN"
        );
        assertEq(
            uln.requiredDVNs[1],
            LZConfigLib.GCLOUD_DVN,
            "Recv ULN DVN[1] should be GCLOUD_DVN"
        );
        assertEq(uln.optionalDVNCount, 0, "Recv ULN should have 0 optional DVNs");
    }

    function _verifyExecutorConfig(uint32 remoteEid_) internal view {
        ILayerZeroEndpointV2 ep = ILayerZeroEndpointV2(LZConfigLib.LZ_ENDPOINT);
        bytes memory cfg = ep.getConfig(
            address(gateway),
            LZConfigLib.ETH_SEND_ULN_302,
            remoteEid_,
            LZConfigLib.CONFIG_TYPE_EXECUTOR
        );
        assertGt(cfg.length, 0, "Executor config should be set");

        ExecutorConfig memory exec = abi.decode(cfg, (ExecutorConfig));
        assertEq(
            exec.maxMessageSize,
            LZConfigLib.MAX_MESSAGE_SIZE,
            "Executor maxMessageSize mismatch"
        );
        assertEq(exec.executor, LZConfigLib.LZ_EXECUTOR, "Executor address mismatch");
    }

    function _verifyPeers() internal view {
        uint32[_REMOTE_CHAIN_COUNT] memory remoteEids = [
            LZConfigLib.ARB_EID,
            LZConfigLib.OPT_EID,
            LZConfigLib.BASE_EID
        ];
        address[_REMOTE_CHAIN_COUNT] memory remoteGateways = [
            proposal.ARB_GATEWAY(),
            proposal.OPT_GATEWAY(),
            proposal.BASE_GATEWAY()
        ];

        for (uint256 i = 0; i < _REMOTE_CHAIN_COUNT; ++i) {
            bytes32 peer = gateway.peers(remoteEids[i]);
            if (remoteGateways[i] == address(0)) {
                assertEq(peer, bytes32(0), "Peer should be empty for zero gateway");
            } else {
                assertEq(peer, LZConfigLib.addressToBytes32(remoteGateways[i]), "Peer mismatch");
            }
        }
    }

    // ========================================================================
    // End State Tests
    // ========================================================================

    /// @notice Validates that the proposal leaves the system in the correct end state.
    function test_proposalEndState() public view {
        // 1. Policy active and enabled
        assertTrue(Policy(address(gateway)).isActive(), "LZBridgeGateway should be active");
        assertTrue(gateway.isEnabled(), "LZBridgeGateway should be enabled");

        // 2. DAO MS has bridge_admin role
        assertTrue(
            /// forge-lint: disable-next-line(unsafe-typecast)
            roles.hasRole(daoMS, bytes32("bridge_admin")),
            "DAO MS should have bridge_admin role"
        );

        // 3. Gateway immutables
        assertEq(gateway.LZ_ENDPOINT(), LZConfigLib.LZ_ENDPOINT, "Endpoint should match");
        assertTrue(gateway.IS_CANONICAL(), "Gateway should be canonical on mainnet");
        assertEq(gateway.ohm(), address(ohm), "OHM should match");

        // 4. Bridged supply cap
        assertEq(
            gateway.bridgedSupplyCap(),
            proposal.BRIDGED_SUPPLY_CAP(),
            "Bridged supply cap should match proposal constant"
        );

        // 5. Per-remote LZ config (send library pinned, receive library pinned, ULN + Executor config)
        ILayerZeroEndpointV2 ep = ILayerZeroEndpointV2(LZConfigLib.LZ_ENDPOINT);
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

            // Libraries pinned
            assertEq(
                ep.getSendLibrary(address(gateway), eid),
                LZConfigLib.ETH_SEND_ULN_302,
                "Send library should be pinned"
            );
            assertFalse(
                ep.isDefaultSendLibrary(address(gateway), eid),
                "Send library should not be default"
            );
            (address recvLib, bool isDefault) = ep.getReceiveLibrary(address(gateway), eid);
            assertEq(recvLib, LZConfigLib.ETH_RECV_ULN_302, "Receive library should be pinned");
            assertFalse(isDefault, "Receive library should not be default");

            // Config
            _verifySendUlnConfig(eid);
            _verifyExecutorConfig(eid);
            _verifyRecvUlnConfig(eid, remoteConfs[i]);
        }

        // 6. Peers
        _verifyPeers();

        // 7. Enforced options
        for (uint256 i = 0; i < _REMOTE_CHAIN_COUNT; ++i) {
            bytes memory opts = gateway.enforcedOptions(remoteEids[i], gateway.MSG_BRIDGE_OHM());
            assertGt(opts.length, 0, "Enforced options should be set");
        }
    }
}

/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
