// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.30;

import {ProposalTest} from "./ProposalTest.sol";
import {console2} from "forge-std/console2.sol";

// Libraries
import {LZConfigLib} from "src/scripts/ops/lib/LZConfigLib.sol";

// Interfaces
import {ExecutorConfig} from "@lz-evm-messagelib-v2-3.0.162/SendLibBase.sol";
import {UlnConfig} from "@lz-evm-messagelib-v2-3.0.162/uln/UlnBase.sol";
import {ILayerZeroEndpointV2} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {IUlnConfigState} from "src/interfaces/layerzero/IUlnConfigState.sol";

// Constants
import {ADMIN_ROLE, MANAGER_ROLE, BRIDGE_ADMIN_ROLE, BRIDGE_CONFIGURATOR_ROLE, BRIDGE_FACILITATOR_ROLE, BRIDGE_RATE_LIMITER_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Kernel, Actions, Policy} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {LZEndpointDelegate} from "src/policies/bridge/LZEndpointDelegate.sol";
import {LZBridgeGateway} from "src/policies/bridge/LZBridgeGateway.sol";
import {LZBridgeAndDelegateConfig} from "src/policies/bridge/LZBridgeAndDelegateConfig.sol";
import {LZCrossChainBridge} from "src/periphery/bridge/LZCrossChainBridge.sol";
import {LZBridgeActivator} from "src/proposals/LZBridgeActivator.sol";
import {IEndpointV2State} from "src/interfaces/layerzero/IEndpointV2State.sol";
import {IERC20} from "@openzeppelin-5.3.0/token/ERC20/IERC20.sol";

// Proposal
import {LZBridgeSecurityUpgradeProposal} from "src/proposals/LZBridgeSecurityUpgradeProposal.sol";

contract LZBridgeSecurityUpgradeProposalTest is ProposalTest {
    /// @dev OCG proposal ID (OIP-197). Must match `LZBridgeSecurityUpgradeProposal.id()`.
    uint256 internal constant _PROPOSAL_ID = 16;

    /// @dev Block where timelock already has `admin` + `bridge_admin` roles.
    ///      Update this once the contracts are deployed on mainnet.
    uint256 public constant BLOCK = 25029000;

    /// @dev Grace window passed to the gateway constructor in the local-deploy branch.
    uint32 internal constant _GRACE_SECONDS = 1 days;

    /// @dev Number of remote chains (Arbitrum, Optimism, Base, Berachain).
    uint256 internal constant _REMOTE_CHAIN_COUNT = 4;

    // ========== DEPLOYMENT TOGGLES ==========

    /// @dev Set to true once contracts have been deployed on Ethereum.
    ///      When false, setUp() deploys them locally and registers in
    ///      the address registry before proposal simulation.
    bool public constant IS_CONTRACTS_DEPLOYED = false;

    // ========== CONTRACTS ==========

    Kernel public kernel;
    LZBridgeGateway public gateway;
    LZEndpointDelegate public lzDelegate;
    LZBridgeAndDelegateConfig public lzConfig;
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
            lzDelegate = LZEndpointDelegate(
                addresses.getAddress("olympus-policy-lz-endpoint-delegate")
            );
            activator = LZBridgeActivator(addresses.getAddress("olympus-lz-bridge-activator"));
            lzCrossChainBridge = addresses.getAddress("olympus-periphery-lz-cross-chain-bridge");
            lzConfig = LZBridgeAndDelegateConfig(
                addresses.getAddress("olympus-policy-lz-bridge-and-delegate-config")
            );
            console2.log("Contracts already deployed on mainnet");
        } else {
            // Deploy LZBridgeGateway (policy, canonical on mainnet)
            gateway = new LZBridgeGateway(
                kernel,
                LZConfigLib.ETH_LZ_ENDPOINT,
                true, // isCanonical
                _GRACE_SECONDS
            );
            vm.label(address(gateway), "LZBridgeGateway");

            // Deploy LZEndpointDelegate (policy)
            lzDelegate = new LZEndpointDelegate(kernel, address(gateway));
            vm.label(address(lzDelegate), "LZEndpointDelegate");

            // Deploy LZCrossChainBridge (periphery, owned by the DAO MS, the DAO MS as re-enabler)
            LZCrossChainBridge bridge = new LZCrossChainBridge(
                address(ohm),
                daoMS,
                address(gateway),
                daoMS,
                _GRACE_SECONDS
            );
            vm.label(address(bridge), "LZCrossChainBridge");
            lzCrossChainBridge = address(bridge);

            // Deploy LZBridgeAndDelegateConfig (timelock policy)
            lzConfig = new LZBridgeAndDelegateConfig(
                kernel,
                address(gateway),
                address(lzDelegate),
                address(bridge),
                1 days
            );
            vm.label(address(lzConfig), "LZBridgeAndDelegateConfig");

            // Deploy LZBridgeActivator (single-use, owned by timelock)
            activator = new LZBridgeActivator(
                timelock,
                address(gateway),
                address(lzDelegate),
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
                "olympus-policy-lz-endpoint-delegate",
                address(lzDelegate),
                block.chainid
            );
            addresses.addAddress(
                "olympus-periphery-lz-cross-chain-bridge",
                address(bridge),
                block.chainid
            );
            addresses.addAddress(
                "olympus-policy-lz-bridge-and-delegate-config",
                address(lzConfig),
                block.chainid
            );
            addresses.addAddress("olympus-lz-bridge-activator", address(activator), block.chainid);
            console2.log("Contracts deployed locally");
        }

        // ========== PRE-OCG: MS BATCH 1 ==========

        // Simulate what the DAO MS does before the OCG proposal: activate the new
        // LZBridgeGateway, LZEndpointDelegate, and LZBridgeAndDelegateConfig policies.
        vm.startPrank(daoMS);
        kernel.executeAction(Actions.ActivatePolicy, address(gateway));
        kernel.executeAction(Actions.ActivatePolicy, address(lzDelegate));
        kernel.executeAction(Actions.ActivatePolicy, address(lzConfig));
        vm.stopPrank();

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
        assertEq(uln.requiredDVNCount, 4, "Send ULN should require 4 DVNs");
        assertEq(uln.requiredDVNs.length, 4, "Send ULN should have 4 required DVNs");

        // Route-aware DVN verification
        address[] memory expectedDvns = LZConfigLib.dvnsForRoute(LZConfigLib.ETH_EID, remoteEid_);
        assertEq(
            uln.requiredDVNCount,
            uint8(expectedDvns.length),
            "Send ULN required DVN count mismatch"
        );
        assertEq(
            uln.requiredDVNs.length,
            expectedDvns.length,
            "Send ULN required DVN array length mismatch"
        );
        for (uint256 d = 0; d < expectedDvns.length; ++d) {
            assertEq(uln.requiredDVNs[d], expectedDvns[d], "Send ULN DVN mismatch");
        }
        // Resolved config reports 0 because no optional DVNs are configured at either layer.
        assertEq(uln.optionalDVNCount, 0, "Send ULN resolved optionalDVNCount should be 0");

        // Verify the *raw* app config pins optional DVNs via the NIL sentinel so the app-level
        // config does NOT inherit LayerZero's EID-level default.
        UlnConfig memory appUln = IUlnConfigState(LZConfigLib.ETH_SEND_ULN_302).getAppUlnConfig(
            address(gateway),
            remoteEid_
        );
        assertEq(
            appUln.optionalDVNCount,
            type(uint8).max,
            "Send ULN app optionalDVNCount must be NIL"
        );
        assertEq(appUln.optionalDVNs.length, 0, "Send ULN app optionalDVNs must be empty");
        assertEq(appUln.optionalDVNThreshold, 0, "Send ULN app optional threshold must be 0");
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
        assertEq(uln.requiredDVNCount, 4, "Recv ULN should require 4 DVNs");
        assertEq(uln.requiredDVNs.length, 4, "Recv ULN should have 4 required DVNs");

        // Route-aware DVN verification
        address[] memory expectedDvns = LZConfigLib.dvnsForRoute(LZConfigLib.ETH_EID, remoteEid_);
        assertEq(
            uln.requiredDVNCount,
            uint8(expectedDvns.length),
            "Recv ULN required DVN count mismatch"
        );
        assertEq(
            uln.requiredDVNs.length,
            expectedDvns.length,
            "Recv ULN required DVN array length mismatch"
        );
        for (uint256 d = 0; d < expectedDvns.length; ++d) {
            assertEq(uln.requiredDVNs[d], expectedDvns[d], "Recv ULN DVN mismatch");
        }
        // Resolved config reports 0 because no optional DVNs are configured at either layer.
        assertEq(uln.optionalDVNCount, 0, "Recv ULN resolved optionalDVNCount should be 0");

        // Verify the *raw* app config pins optional DVNs via the NIL sentinel.
        UlnConfig memory appUln = IUlnConfigState(LZConfigLib.ETH_RECV_ULN_302).getAppUlnConfig(
            address(gateway),
            remoteEid_
        );
        assertEq(
            appUln.optionalDVNCount,
            type(uint8).max,
            "Recv ULN app optionalDVNCount must be NIL"
        );
        assertEq(appUln.optionalDVNs.length, 0, "Recv ULN app optionalDVNs must be empty");
        assertEq(appUln.optionalDVNThreshold, 0, "Recv ULN app optional threshold must be 0");
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

    /// @notice Validates the configured OCG proposal ID matches OIP-197.
    function test_proposalId() public {
        assertEq(proposal.id(), _PROPOSAL_ID, "Proposal ID should match OIP-197");
    }

    /// @notice Validates that the proposal leaves the system in the correct end state.
    function test_proposalEndState() public view {
        // 1. Policy active and enabled
        assertTrue(Policy(address(gateway)).isActive(), "LZBridgeGateway should be active");
        assertTrue(gateway.isEnabled(), "LZBridgeGateway should be enabled");
        assertTrue(
            Policy(address(lzConfig)).isActive(),
            "LZBridgeAndDelegateConfig should be active"
        );
        assertTrue(lzConfig.isEnabled(), "LZBridgeAndDelegateConfig should be enabled");

        // 2. The DAO MS has bridge_admin role
        assertTrue(
            roles.hasRole(daoMS, BRIDGE_ADMIN_ROLE),
            "The DAO MS should have bridge_admin role"
        );

        // 2b. The DAO MS has bridge_rate_limiter role
        assertTrue(
            roles.hasRole(daoMS, BRIDGE_RATE_LIMITER_ROLE),
            "The DAO MS should have bridge_rate_limiter role"
        );

        // 2c. The DAO MS has manager role (gates the gateway's reEnable())
        assertTrue(roles.hasRole(daoMS, MANAGER_ROLE), "The DAO MS should have manager role");

        // 3. LZCrossChainBridge has bridge_facilitator role
        assertTrue(
            roles.hasRole(lzCrossChainBridge, BRIDGE_FACILITATOR_ROLE),
            "LZCrossChainBridge should have bridge_facilitator role"
        );

        // 4. Activator roles revoked and spent
        assertFalse(
            roles.hasRole(address(activator), ADMIN_ROLE),
            "Activator should not have admin role"
        );
        assertFalse(
            roles.hasRole(address(activator), BRIDGE_ADMIN_ROLE),
            "Activator should not have bridge_admin role"
        );
        assertFalse(
            roles.hasRole(address(activator), BRIDGE_CONFIGURATOR_ROLE),
            "Activator should not have bridge_configurator role"
        );
        assertTrue(activator.isActivated(), "Activator should be marked as activated");

        // 4b. The permanent bridge_configurator role lives on the config policy.
        assertTrue(
            roles.hasRole(address(lzConfig), BRIDGE_CONFIGURATOR_ROLE),
            "LZBridgeAndDelegateConfig should hold bridge_configurator role"
        );
        assertFalse(
            roles.hasRole(daoMS, BRIDGE_CONFIGURATOR_ROLE),
            "DAO MS should not hold bridge_configurator role"
        );

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

        // 11. LZEndpointDelegate is the LZ endpoint delegate for the gateway
        assertTrue(Policy(address(lzDelegate)).isActive(), "LZEndpointDelegate should be active");
        assertTrue(lzDelegate.isEnabled(), "LZEndpointDelegate should be enabled");
        assertEq(
            IEndpointV2State(address(ep)).delegates(address(gateway)),
            address(lzDelegate),
            "LZ endpoint delegate should be LZEndpointDelegate"
        );
        assertEq(lzDelegate.GATEWAY(), address(gateway), "LZEndpointDelegate.GATEWAY mismatch");
        assertEq(
            lzDelegate.LZ_ENDPOINT(),
            LZConfigLib.ETH_LZ_ENDPOINT,
            "LZEndpointDelegate.LZ_ENDPOINT mismatch"
        );
    }
}
