// SPDX-License-Identifier: UNLICENSED
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.30;

import {ProposalTest} from "./ProposalTest.sol";
import {console2} from "forge-std/console2.sol";

// Libraries
import {LZConfigLib} from "src/libraries/LZConfigLib.sol";

// Interfaces
import {ExecutorConfig} from "@lz-evm-messagelib-v2-3.0.162/SendLibBase.sol";
import {UlnConfig} from "@lz-evm-messagelib-v2-3.0.162/uln/UlnBase.sol";
import {ILayerZeroEndpointV2} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";

// Constants
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Kernel, Actions, Policy} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {LZBridgeGateway} from "src/policies/bridge/LZBridgeGateway.sol";
import {LZCrossChainBridge} from "src/periphery/bridge/LZCrossChainBridge.sol";
import {LZBridgeActivator} from "src/proposals/LZBridgeActivator.sol";
import {IERC20} from "@openzeppelin-5.3.0/token/ERC20/IERC20.sol";

// Proposal
import {LZBridgeSecurityUpgradeProposal} from "src/proposals/LZBridgeSecurityUpgradeProposal.sol";

contract LZBridgeSecurityUpgradeProposalTest is ProposalTest {
    /// @dev Block where timelock already has `admin` + `bridge_admin` roles.
    ///      Update this once the contracts are deployed on mainnet.
    uint256 public constant BLOCK = 25010000;

    /// @dev Number of remote chains (Arbitrum, Optimism, Base, Berachain).
    uint256 internal constant _REMOTE_CHAIN_COUNT = 4;

    /// @dev Role constants.
    bytes32 internal constant _BRIDGE_ADMIN_ROLE = "bridge_admin";
    bytes32 internal constant _BRIDGE_FACILITATOR_ROLE = "bridge_facilitator";
    bytes32 internal constant _BRIDGE_RATE_LIMITER_ROLE = "bridge_rate_limiter";

    // ========== DEPLOYMENT TOGGLES ==========

    /// @dev Set to true once contracts have been deployed on Ethereum.
    ///      When false, setUp() deploys them locally and registers in
    ///      the address registry before proposal simulation.
    bool public constant IS_CONTRACTS_DEPLOYED = false;

    // ========== CONTRACTS ==========

    Kernel public kernel;
    LZBridgeGateway public gateway;
    LZBridgeActivator public activator;
    LZBridgeSecurityUpgradeProposal public proposal;
    ROLESv1 public roles;
    IERC20 public ohm;

    // ========== ADDRESSES ==========

    address public daoMS;
    address public timelock;
    address public oldCrossChainBridge;
    address public lzCrossChainBridge;

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
            activator = LZBridgeActivator(addresses.getAddress("olympus-lz-bridge-activator"));
            lzCrossChainBridge = addresses.getAddress("olympus-periphery-lz-cross-chain-bridge");
            console2.log("Contracts already deployed on mainnet");
        } else {
            // Deploy LZBridgeGateway (policy, canonical on mainnet)
            gateway = new LZBridgeGateway(
                kernel,
                LZConfigLib.ETH_LZ_ENDPOINT,
                true // isCanonical
            );
            vm.label(address(gateway), "LZBridgeGateway");

            // Deploy LZCrossChainBridge (periphery, owned by DAO MS)
            LZCrossChainBridge bridge = new LZCrossChainBridge(
                address(ohm),
                daoMS,
                address(gateway)
            );
            vm.label(address(bridge), "LZCrossChainBridge");
            lzCrossChainBridge = address(bridge);

            // Deploy LZBridgeActivator (single-use, owned by timelock)
            activator = new LZBridgeActivator(
                timelock,
                address(gateway),
                LZConfigLib.ETH_LZ_ENDPOINT,
                makeAddr("ARB_GATEWAY"),
                makeAddr("OPT_GATEWAY"),
                makeAddr("BASE_GATEWAY"),
                makeAddr("BERA_GATEWAY")
            );
            vm.label(address(activator), "LZBridgeActivator");

            // Register in the address registry
            addresses.addAddress(
                "olympus-policy-lz-bridge-gateway",
                address(gateway),
                block.chainid
            );
            addresses.addAddress(
                "olympus-periphery-lz-cross-chain-bridge",
                address(bridge),
                block.chainid
            );
            addresses.addAddress("olympus-lz-bridge-activator", address(activator), block.chainid);
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

    /// @dev Verifies Send ULN config for a remote EID, with route-aware DVN checks.
    function _verifySendUlnConfig(uint32 remoteEid_) internal view {
        ILayerZeroEndpointV2 ep = ILayerZeroEndpointV2(LZConfigLib.ETH_LZ_ENDPOINT);
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

        // Route-aware DVN verification
        address[] memory expectedDvns = LZConfigLib.dvnsForRoute(LZConfigLib.ETH_EID, remoteEid_);
        assertEq(uln.requiredDVNs[0], expectedDvns[0], "Send ULN DVN[0] mismatch");
        assertEq(uln.requiredDVNs[1], expectedDvns[1], "Send ULN DVN[1] mismatch");
        assertEq(uln.optionalDVNCount, 0, "Send ULN should have 0 optional DVNs");
    }

    /// @dev Verifies Recv ULN config for a remote EID, with route-aware DVN checks.
    function _verifyRecvUlnConfig(uint32 remoteEid_, uint64 expectedConfirmations_) internal view {
        ILayerZeroEndpointV2 ep = ILayerZeroEndpointV2(LZConfigLib.ETH_LZ_ENDPOINT);
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

        // Route-aware DVN verification
        address[] memory expectedDvns = LZConfigLib.dvnsForRoute(LZConfigLib.ETH_EID, remoteEid_);
        assertEq(uln.requiredDVNs[0], expectedDvns[0], "Recv ULN DVN[0] mismatch");
        assertEq(uln.requiredDVNs[1], expectedDvns[1], "Recv ULN DVN[1] mismatch");
        assertEq(uln.optionalDVNCount, 0, "Recv ULN should have 0 optional DVNs");
    }

    function _verifyExecutorConfig(uint32 remoteEid_) internal view {
        ILayerZeroEndpointV2 ep = ILayerZeroEndpointV2(LZConfigLib.ETH_LZ_ENDPOINT);
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
        assertEq(exec.executor, LZConfigLib.ETH_LZ_EXECUTOR, "Executor address mismatch");
    }

    function _verifyPeers() internal view {
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
            bytes32 peer = gateway.peers(remoteEids[i]);
            assertEq(peer, LZConfigLib.addressToBytes32(remoteGateways[i]), "Peer mismatch");
        }
    }

    /// @dev Verifies that the activator applied the canonical bidirectional rate limits
    ///      from `LZConfigLib` to every remote endpoint.
    function _verifyRateLimits() internal view {
        uint32[_REMOTE_CHAIN_COUNT] memory remoteEids = [
            LZConfigLib.ARB_EID,
            LZConfigLib.OPT_EID,
            LZConfigLib.BASE_EID,
            LZConfigLib.BERA_EID
        ];
        uint32 expectedWindow = LZConfigLib.RATE_LIMIT_WINDOW;

        for (uint256 i = 0; i < _REMOTE_CHAIN_COUNT; ++i) {
            uint256 expectedOut = LZConfigLib.outRateLimitForRoute(
                LZConfigLib.ETH_EID,
                remoteEids[i]
            );
            uint256 expectedIn = LZConfigLib.inRateLimitForRoute(
                LZConfigLib.ETH_EID,
                remoteEids[i]
            );
            (uint256 outInFlight, uint256 outLimit, uint32 outWindow, ) = gateway.outRateLimits(
                remoteEids[i]
            );
            assertEq(outLimit, expectedOut, "Outbound rate limit mismatch");
            assertEq(outWindow, expectedWindow, "Outbound rate window mismatch");
            assertEq(outInFlight, 0, "Outbound in-flight should start at zero");

            (uint256 inInFlight, uint256 inLimit, uint32 inWindow, ) = gateway.inRateLimits(
                remoteEids[i]
            );
            assertEq(inLimit, expectedIn, "Inbound rate limit mismatch");
            assertEq(inWindow, expectedWindow, "Inbound rate window mismatch");
            assertEq(inInFlight, 0, "Inbound in-flight should start at zero");
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
            roles.hasRole(daoMS, _BRIDGE_ADMIN_ROLE),
            "DAO MS should have bridge_admin role"
        );

        // 2b. DAO MS has bridge_rate_limiter role
        assertTrue(
            /// forge-lint: disable-next-line(unsafe-typecast)
            roles.hasRole(daoMS, _BRIDGE_RATE_LIMITER_ROLE),
            "DAO MS should have bridge_rate_limiter role"
        );

        // 3. LZCrossChainBridge has bridge_facilitator role
        assertTrue(
            /// forge-lint: disable-next-line(unsafe-typecast)
            roles.hasRole(lzCrossChainBridge, _BRIDGE_FACILITATOR_ROLE),
            "LZCrossChainBridge should have bridge_facilitator role"
        );

        // 4. Activator roles revoked and spent
        assertFalse(
            /// forge-lint: disable-next-line(unsafe-typecast)
            roles.hasRole(address(activator), ADMIN_ROLE),
            "Activator should not have admin role"
        );
        assertFalse(
            /// forge-lint: disable-next-line(unsafe-typecast)
            roles.hasRole(address(activator), _BRIDGE_ADMIN_ROLE),
            "Activator should not have bridge_admin role"
        );
        assertTrue(activator.isActivated(), "Activator should be marked as activated");

        // 5. Gateway immutables
        assertEq(gateway.LZ_ENDPOINT(), LZConfigLib.ETH_LZ_ENDPOINT, "Endpoint should match");
        assertTrue(gateway.IS_CANONICAL(), "Gateway should be canonical on mainnet");
        assertEq(gateway.ohm(), address(ohm), "OHM should match");

        // 6. Per-remote LZ config
        ILayerZeroEndpointV2 ep = ILayerZeroEndpointV2(LZConfigLib.ETH_LZ_ENDPOINT);
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

        // 8. Peers
        _verifyPeers();

        // 9. Enforced options
        for (uint256 i = 0; i < _REMOTE_CHAIN_COUNT; ++i) {
            bytes memory opts = gateway.enforcedOptions(remoteEids[i], gateway.MSG_BRIDGE_OHM());
            assertGt(opts.length, 0, "Enforced options should be set");
        }

        // 10. Bidirectional rate limits
        _verifyRateLimits();
    }
}

/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
