// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "@forge-std-1.16.2/Test.sol";

// Libraries
import {LZConfigLib} from "src/scripts/ops/lib/LZConfigLib.sol";

// Interfaces
import {ExecutorConfig} from "@lz-evm-messagelib-v2-3.0.162/SendLibBase.sol";
import {UlnConfig} from "@lz-evm-messagelib-v2-3.0.162/uln/UlnBase.sol";
import {ILayerZeroEndpointV2} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {IEndpointV2State} from "src/interfaces/layerzero/IEndpointV2State.sol";
import {IUlnConfigState} from "src/interfaces/layerzero/IUlnConfigState.sol";

// Constants
import {ADMIN_ROLE, BRIDGE_ADMIN_ROLE, BRIDGE_CONFIGURATOR_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Kernel, Actions, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {LZEndpointDelegate} from "src/policies/bridge/LZEndpointDelegate.sol";
import {LZBridgeGateway} from "src/policies/bridge/LZBridgeGateway.sol";
import {LZBridgeActivator} from "src/proposals/LZBridgeActivator.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {MockLZEndpointDelegate} from "src/test/policies/bridge/LZEndpointDelegate/MockLZEndpointDelegate.sol";
import {MockLZBridgeGateway} from "src/test/policies/bridge/LZEndpointDelegate/MockLZBridgeGateway.sol";
import {IERC20} from "@openzeppelin-5.3.0/token/ERC20/IERC20.sol";

contract LZBridgeActivatorForkTest is Test {
    // Fork configuration
    uint256 internal constant FORK_BLOCK = 25029000;

    // Grace window passed to the gateway constructor
    uint32 internal constant GRACE_SECONDS = 1 days;

    // Remote chain count
    uint256 internal constant _REMOTE_CHAIN_COUNT = 4;

    // Mainnet addresses (hard-coded for specific fork block)
    address public constant KERNEL = 0x2286d7f9639e8158FaD1169e76d1FbC38247f54b;
    address public constant ROLES_ADMIN = 0xb216d714d91eeC4F7120a732c11428857C659eC8;
    address public constant TIMELOCK = 0x953EA3223d2dd3c1A91E9D6cca1bf7Af162C9c39;
    address public constant DAO_MS = 0x245cc372C84B3645Bf0Ffe6538620B04a217988B;

    // Contracts
    Kernel public kernel;
    ROLESv1 public roles;
    RolesAdmin public rolesAdmin;
    LZBridgeGateway public gateway;
    LZEndpointDelegate public lzDelegate;
    LZBridgeActivator public activator;
    ILayerZeroEndpointV2 public endpoint;

    function setUp() public {
        vm.createSelectFork("mainnet", FORK_BLOCK);

        kernel = Kernel(KERNEL);
        roles = ROLESv1(address(kernel.getModuleForKeycode(toKeycode("ROLES"))));
        rolesAdmin = RolesAdmin(ROLES_ADMIN);
        endpoint = ILayerZeroEndpointV2(LZConfigLib.ETH_LZ_ENDPOINT);

        // Deploy the gateway (canonical on mainnet)
        gateway = new LZBridgeGateway(kernel, LZConfigLib.ETH_LZ_ENDPOINT, true, GRACE_SECONDS);

        // Deploy the delegate policy pointing at this gateway
        lzDelegate = new LZEndpointDelegate(kernel, address(gateway));

        // Deploy the activator (owned by the timelock)
        activator = new LZBridgeActivator(
            TIMELOCK,
            address(gateway),
            address(lzDelegate),
            LZConfigLib.ETH_LZ_ENDPOINT,
            makeAddr("ARB_GATEWAY"),
            makeAddr("OPT_GATEWAY"),
            makeAddr("BASE_GATEWAY"),
            makeAddr("BERA_GATEWAY")
        );

        // Activate the gateway and the delegate policy in the Kernel (as DAO MS, the executor)
        vm.startPrank(DAO_MS);
        kernel.executeAction(Actions.ActivatePolicy, address(gateway));
        kernel.executeAction(Actions.ActivatePolicy, address(lzDelegate));
        vm.stopPrank();
    }

    function _grantRequiredRoles() internal {
        vm.startPrank(TIMELOCK);
        rolesAdmin.grantRole(ADMIN_ROLE, address(activator));
        rolesAdmin.grantRole(BRIDGE_ADMIN_ROLE, address(activator));
        rolesAdmin.grantRole(BRIDGE_CONFIGURATOR_ROLE, address(activator));
        // The OCG proposal enables the delegate as a separate action before invoking the
        // activator. Mirror that here so the activator's OApp-authorized setters pass the
        // delegate's `givenEnabled` gate.
        lzDelegate.enable("");
        vm.stopPrank();
    }

    // ========== CONSTRUCTOR TESTS ========== //

    function test_constructor_setsParametersCorrectly() public {
        assertEq(activator.owner(), TIMELOCK);
        assertEq(activator.GATEWAY(), address(gateway));
        assertEq(activator.DELEGATE(), address(lzDelegate));
        assertEq(activator.ENDPOINT(), LZConfigLib.ETH_LZ_ENDPOINT);
        assertEq(activator.ARB_GATEWAY(), makeAddr("ARB_GATEWAY"));
        assertEq(activator.OPT_GATEWAY(), makeAddr("OPT_GATEWAY"));
        assertEq(activator.BASE_GATEWAY(), makeAddr("BASE_GATEWAY"));
        assertEq(activator.BERA_GATEWAY(), makeAddr("BERA_GATEWAY"));
        assertFalse(activator.isActivated());
    }

    function test_constructor_revertsWhen_zeroGateway() public {
        vm.expectRevert(
            abi.encodeWithSelector(LZBridgeActivator.InvalidParams.selector, "gateway")
        );
        new LZBridgeActivator(
            TIMELOCK,
            address(0),
            address(lzDelegate),
            LZConfigLib.ETH_LZ_ENDPOINT,
            makeAddr("A"),
            makeAddr("O"),
            makeAddr("B"),
            makeAddr("Be")
        );
    }

    function test_constructor_revertsWhen_zeroDelegate() public {
        vm.expectRevert(
            abi.encodeWithSelector(LZBridgeActivator.InvalidParams.selector, "delegate")
        );
        new LZBridgeActivator(
            TIMELOCK,
            address(gateway),
            address(0),
            LZConfigLib.ETH_LZ_ENDPOINT,
            makeAddr("A"),
            makeAddr("O"),
            makeAddr("B"),
            makeAddr("Be")
        );
    }

    function test_constructor_revertsWhen_zeroEndpoint() public {
        vm.expectRevert(
            abi.encodeWithSelector(LZBridgeActivator.InvalidParams.selector, "endpoint")
        );
        new LZBridgeActivator(
            TIMELOCK,
            address(gateway),
            address(lzDelegate),
            address(0),
            makeAddr("A"),
            makeAddr("O"),
            makeAddr("B"),
            makeAddr("Be")
        );
    }

    function test_constructor_revertsWhen_zeroOwner() public {
        vm.expectRevert(abi.encodeWithSelector(LZBridgeActivator.InvalidParams.selector, "owner"));
        new LZBridgeActivator(
            address(0),
            address(gateway),
            address(lzDelegate),
            LZConfigLib.ETH_LZ_ENDPOINT,
            makeAddr("A"),
            makeAddr("O"),
            makeAddr("B"),
            makeAddr("Be")
        );
    }

    function test_constructor_revertsWhen_endpointMismatch() public {
        // The endpoint must match the gateway's LZ_ENDPOINT immutable; passing a fake address
        // exercises the gateway-side check before the delegate-side check runs.
        address wrongEndpoint = makeAddr("WRONG_ENDPOINT");
        vm.expectRevert(
            abi.encodeWithSelector(LZBridgeActivator.InvalidParams.selector, "endpoint")
        );
        new LZBridgeActivator(
            TIMELOCK,
            address(gateway),
            address(lzDelegate),
            wrongEndpoint,
            makeAddr("A"),
            makeAddr("O"),
            makeAddr("B"),
            makeAddr("Be")
        );
    }

    function test_constructor_revertsWhen_delegateGatewayMismatch() public {
        // A delegate whose GATEWAY immutable points at a different contract must be rejected.
        // LZEndpointDelegate reads LZ_ENDPOINT from its gateway at construction, so the foreign
        // gateway must report the same endpoint as the real one.
        MockLZBridgeGateway foreignGateway = new MockLZBridgeGateway(LZConfigLib.ETH_LZ_ENDPOINT);
        LZEndpointDelegate foreignDelegate = new LZEndpointDelegate(
            kernel,
            address(foreignGateway)
        );

        vm.expectRevert(
            abi.encodeWithSelector(LZBridgeActivator.InvalidParams.selector, "delegate")
        );
        new LZBridgeActivator(
            TIMELOCK,
            address(gateway),
            address(foreignDelegate),
            LZConfigLib.ETH_LZ_ENDPOINT,
            makeAddr("A"),
            makeAddr("O"),
            makeAddr("B"),
            makeAddr("Be")
        );
    }

    function test_constructor_revertsWhen_delegateEndpointMismatch() public {
        address wrongEndpoint = makeAddr("wrongEndpoint");
        MockLZEndpointDelegate mismatchedDelegate = new MockLZEndpointDelegate(
            address(gateway),
            wrongEndpoint
        );

        vm.expectRevert(
            abi.encodeWithSelector(LZBridgeActivator.InvalidParams.selector, "delegate")
        );
        new LZBridgeActivator(
            TIMELOCK,
            address(gateway),
            address(mismatchedDelegate),
            LZConfigLib.ETH_LZ_ENDPOINT,
            makeAddr("A"),
            makeAddr("O"),
            makeAddr("B"),
            makeAddr("Be")
        );
    }

    // ========== ACCESS CONTROL TESTS ========== //

    function testFuzz_activate_revertsWhen_notOwner(address caller_) public {
        vm.assume(caller_ != TIMELOCK);
        _grantRequiredRoles();

        vm.expectRevert("UNAUTHORIZED");
        vm.prank(caller_);
        activator.activate();
    }

    function test_activate_revertsWhen_alreadyActivated() public {
        _grantRequiredRoles();

        vm.prank(TIMELOCK);
        activator.activate();

        vm.expectRevert(LZBridgeActivator.AlreadyActivated.selector);
        vm.prank(TIMELOCK);
        activator.activate();
    }

    // ========== ACTIVATION TESTS ========== //

    function test_activate_setsActivatedFlag() public {
        _grantRequiredRoles();

        assertFalse(activator.isActivated());

        vm.prank(TIMELOCK);
        activator.activate();

        assertTrue(activator.isActivated());
    }

    function test_activate_emitsActivatedEvent() public {
        _grantRequiredRoles();

        vm.expectEmit(true, false, false, false);
        emit LZBridgeActivator.Activated(TIMELOCK);

        vm.prank(TIMELOCK);
        activator.activate();
    }

    function test_activate_enablesGateway() public {
        _grantRequiredRoles();

        assertFalse(IEnabler(address(gateway)).isEnabled());

        vm.prank(TIMELOCK);
        activator.activate();

        assertTrue(IEnabler(address(gateway)).isEnabled());
    }

    function test_activate_setsLZEndpointDelegateAsDelegate() public {
        _grantRequiredRoles();

        vm.prank(TIMELOCK);
        activator.activate();

        // Delegate should be the LZEndpointDelegate policy, not revoked.
        assertEq(
            IEndpointV2State(address(endpoint)).delegates(address(gateway)),
            address(lzDelegate),
            "Delegate should be set to LZEndpointDelegate after activation"
        );
    }

    // ========== LZ CONFIG TESTS ========== //

    function test_activate_pinsLibraries() public {
        _grantRequiredRoles();

        vm.prank(TIMELOCK);
        activator.activate();

        uint32[_REMOTE_CHAIN_COUNT] memory remoteEids = [
            LZConfigLib.ARB_EID,
            LZConfigLib.OPT_EID,
            LZConfigLib.BASE_EID,
            LZConfigLib.BERA_EID
        ];

        for (uint256 i = 0; i < _REMOTE_CHAIN_COUNT; ++i) {
            uint32 eid = remoteEids[i];

            assertEq(
                endpoint.getSendLibrary(address(gateway), eid),
                LZConfigLib.ETH_SEND_ULN_302,
                "Send library should be pinned"
            );
            assertFalse(
                endpoint.isDefaultSendLibrary(address(gateway), eid),
                "Send library should not be default"
            );

            (address recvLib, bool isDefault) = endpoint.getReceiveLibrary(address(gateway), eid);
            assertEq(recvLib, LZConfigLib.ETH_RECV_ULN_302, "Receive library should be pinned");
            assertFalse(isDefault, "Receive library should not be default");
        }
    }

    function test_activate_setsSendUlnConfig() public {
        _grantRequiredRoles();

        vm.prank(TIMELOCK);
        activator.activate();

        uint32[_REMOTE_CHAIN_COUNT] memory remoteEids = [
            LZConfigLib.ARB_EID,
            LZConfigLib.OPT_EID,
            LZConfigLib.BASE_EID,
            LZConfigLib.BERA_EID
        ];

        for (uint256 i = 0; i < _REMOTE_CHAIN_COUNT; ++i) {
            uint32 eid = remoteEids[i];
            bytes memory cfg = endpoint.getConfig(
                address(gateway),
                LZConfigLib.ETH_SEND_ULN_302,
                eid,
                LZConfigLib.CONFIG_TYPE_ULN
            );
            UlnConfig memory uln = abi.decode(cfg, (UlnConfig));

            assertEq(
                uln.confirmations,
                LZConfigLib.ETH_OUTBOUND_CONFIRMATIONS,
                "Send confirmations mismatch"
            );
            assertEq(uln.requiredDVNCount, 4, "Should require 4 DVNs");

            // Route-aware DVN verification
            address[] memory expectedDvns = LZConfigLib.dvnsForRoute(LZConfigLib.ETH_EID, eid);
            assertEq(
                uln.requiredDVNCount,
                uint8(expectedDvns.length),
                "Send required DVN count mismatch"
            );
            assertEq(
                uln.requiredDVNs.length,
                expectedDvns.length,
                "Send required DVN array length mismatch"
            );
            for (uint256 d = 0; d < expectedDvns.length; ++d) {
                assertEq(uln.requiredDVNs[d], expectedDvns[d], "Send DVN mismatch");
            }

            // The app-level config must pin optional DVNs to NIL so the app config does not
            // silently inherit LayerZero's EID-level default.
            UlnConfig memory appUln = IUlnConfigState(LZConfigLib.ETH_SEND_ULN_302).getAppUlnConfig(
                address(gateway),
                eid
            );
            assertEq(
                appUln.optionalDVNCount,
                type(uint8).max,
                "Send app optionalDVNCount must be NIL"
            );
            assertEq(appUln.optionalDVNs.length, 0, "Send app optionalDVNs must be empty");
            assertEq(appUln.optionalDVNThreshold, 0, "Send app optional threshold must be 0");
        }
    }

    function test_activate_setsRecvUlnConfig() public {
        _grantRequiredRoles();

        vm.prank(TIMELOCK);
        activator.activate();

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
            bytes memory cfg = endpoint.getConfig(
                address(gateway),
                LZConfigLib.ETH_RECV_ULN_302,
                eid,
                LZConfigLib.CONFIG_TYPE_ULN
            );
            UlnConfig memory uln = abi.decode(cfg, (UlnConfig));

            assertEq(uln.confirmations, remoteConfs[i], "Recv confirmations mismatch");
            assertEq(uln.requiredDVNCount, 4, "Should require 4 DVNs");

            address[] memory expectedDvns = LZConfigLib.dvnsForRoute(LZConfigLib.ETH_EID, eid);
            assertEq(
                uln.requiredDVNCount,
                uint8(expectedDvns.length),
                "Recv required DVN count mismatch"
            );
            assertEq(
                uln.requiredDVNs.length,
                expectedDvns.length,
                "Recv required DVN array length mismatch"
            );
            for (uint256 d = 0; d < expectedDvns.length; ++d) {
                assertEq(uln.requiredDVNs[d], expectedDvns[d], "Recv DVN mismatch");
            }

            UlnConfig memory appUln = IUlnConfigState(LZConfigLib.ETH_RECV_ULN_302).getAppUlnConfig(
                address(gateway),
                eid
            );
            assertEq(
                appUln.optionalDVNCount,
                type(uint8).max,
                "Recv app optionalDVNCount must be NIL"
            );
            assertEq(appUln.optionalDVNs.length, 0, "Recv app optionalDVNs must be empty");
            assertEq(appUln.optionalDVNThreshold, 0, "Recv app optional threshold must be 0");
        }
    }

    function test_activate_setsExecutorConfig() public {
        _grantRequiredRoles();

        vm.prank(TIMELOCK);
        activator.activate();

        uint32[_REMOTE_CHAIN_COUNT] memory remoteEids = [
            LZConfigLib.ARB_EID,
            LZConfigLib.OPT_EID,
            LZConfigLib.BASE_EID,
            LZConfigLib.BERA_EID
        ];

        for (uint256 i = 0; i < _REMOTE_CHAIN_COUNT; ++i) {
            bytes memory cfg = endpoint.getConfig(
                address(gateway),
                LZConfigLib.ETH_SEND_ULN_302,
                remoteEids[i],
                LZConfigLib.CONFIG_TYPE_EXECUTOR
            );
            ExecutorConfig memory exec = abi.decode(cfg, (ExecutorConfig));

            assertEq(exec.executor, LZConfigLib.ETH_LZ_EXECUTOR, "Executor mismatch");
            assertEq(
                exec.maxMessageSize,
                LZConfigLib.MAX_MESSAGE_SIZE,
                "Max message size mismatch"
            );
        }
    }

    // ========== PEERS TESTS ========== //

    function test_activate_setPeers() public {
        _grantRequiredRoles();

        vm.prank(TIMELOCK);
        activator.activate();

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

    // ========== ENFORCED OPTIONS TESTS ========== //

    function test_activate_setsEnforcedOptions() public {
        _grantRequiredRoles();

        vm.prank(TIMELOCK);
        activator.activate();

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
            bytes memory opts = gateway.enforcedOptions(remoteEids[i], gateway.MSG_BRIDGE_OHM());
            assertEq(keccak256(opts), expectedHash, "Enforced options mismatch");
        }
    }

    // ========== RATE LIMITS TESTS ========== //

    function test_activate_setsRateLimits() public {
        _grantRequiredRoles();

        vm.prank(TIMELOCK);
        activator.activate();

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
            (, uint256 outLimit, uint32 outWindow, ) = gateway.outRateLimits(remoteEids[i]);
            assertEq(outLimit, expectedOut, "Outbound limit mismatch");
            assertEq(outWindow, expectedWindow, "Outbound window mismatch");

            (, uint256 inLimit, uint32 inWindow, ) = gateway.inRateLimits(remoteEids[i]);
            assertEq(inLimit, expectedIn, "Inbound limit mismatch");
            assertEq(inWindow, expectedWindow, "Inbound window mismatch");
        }
    }

    // ========== DVN ROUTE VERIFICATION ========== //

    function test_activate_berachainRouteIncludesHorizenAndExcludesGoogleCloud() public {
        _grantRequiredRoles();

        vm.prank(TIMELOCK);
        activator.activate();

        // Verify Berachain route includes the Horizen DVN (since Google Cloud is unavailable
        // there) along with the LayerZero Labs, Canary and Nethermind DVNs.
        bytes memory sendCfg = endpoint.getConfig(
            address(gateway),
            LZConfigLib.ETH_SEND_ULN_302,
            LZConfigLib.BERA_EID,
            LZConfigLib.CONFIG_TYPE_ULN
        );
        UlnConfig memory sendUln = abi.decode(sendCfg, (UlnConfig));

        bool hasHorizen;
        bool hasLz;
        bool hasCanary;
        bool hasNethermind;
        bool hasGoogleCloud;
        for (uint256 d = 0; d < sendUln.requiredDVNs.length; ++d) {
            address dvn = sendUln.requiredDVNs[d];
            if (dvn == LZConfigLib.ETH_HORIZEN_DVN) hasHorizen = true;
            if (dvn == LZConfigLib.ETH_LZ_DVN) hasLz = true;
            if (dvn == LZConfigLib.ETH_CANARY_DVN) hasCanary = true;
            if (dvn == LZConfigLib.ETH_NETHERMIND_DVN) hasNethermind = true;
            if (dvn == LZConfigLib.ETH_GCLOUD_DVN) hasGoogleCloud = true;
        }
        assertTrue(hasLz, "Bera route should include LayerZero Labs DVN");
        assertTrue(hasCanary, "Bera route should include Canary DVN");
        assertTrue(hasNethermind, "Bera route should include Nethermind DVN");
        assertTrue(hasHorizen, "Bera route should include Horizen DVN");
        assertFalse(hasGoogleCloud, "Bera route must not include Google Cloud DVN");
    }

    function test_activate_nonBerachainRoutesIncludeGoogleCloudAndExcludeHorizen() public {
        _grantRequiredRoles();

        vm.prank(TIMELOCK);
        activator.activate();

        uint32[3] memory nonBeraEids = [
            LZConfigLib.ARB_EID,
            LZConfigLib.OPT_EID,
            LZConfigLib.BASE_EID
        ];

        for (uint256 i = 0; i < 3; ++i) {
            bytes memory cfg = endpoint.getConfig(
                address(gateway),
                LZConfigLib.ETH_SEND_ULN_302,
                nonBeraEids[i],
                LZConfigLib.CONFIG_TYPE_ULN
            );
            UlnConfig memory uln = abi.decode(cfg, (UlnConfig));

            bool hasGoogleCloud;
            bool hasHorizen;
            bool hasLz;
            bool hasCanary;
            bool hasNethermind;
            for (uint256 d = 0; d < uln.requiredDVNs.length; ++d) {
                address dvn = uln.requiredDVNs[d];
                if (dvn == LZConfigLib.ETH_GCLOUD_DVN) hasGoogleCloud = true;
                if (dvn == LZConfigLib.ETH_HORIZEN_DVN) hasHorizen = true;
                if (dvn == LZConfigLib.ETH_LZ_DVN) hasLz = true;
                if (dvn == LZConfigLib.ETH_CANARY_DVN) hasCanary = true;
                if (dvn == LZConfigLib.ETH_NETHERMIND_DVN) hasNethermind = true;
            }
            assertTrue(hasLz, "Non-Bera route should include LayerZero Labs DVN");
            assertTrue(hasCanary, "Non-Bera route should include Canary DVN");
            assertTrue(hasNethermind, "Non-Bera route should include Nethermind DVN");
            assertTrue(hasGoogleCloud, "Non-Bera route should include Google Cloud DVN");
            assertFalse(hasHorizen, "Non-Bera route must not include Horizen DVN");
        }
    }
}
