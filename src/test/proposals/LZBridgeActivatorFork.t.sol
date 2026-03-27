// SPDX-License-Identifier: UNLICENSED
/// forge-lint: disable-start(mixed-case-function,mixed-case-variable)
pragma solidity >=0.8.30;

import {Test} from "@forge-std-1.9.6/Test.sol";

// Libraries
import {LZConfigLib} from "src/libraries/LZConfigLib.sol";

// Interfaces
import {ExecutorConfig} from "@lz-evm-messagelib-v2-3.0.162/SendLibBase.sol";
import {UlnConfig} from "@lz-evm-messagelib-v2-3.0.162/uln/UlnBase.sol";
import {ILayerZeroEndpointV2} from "@lz-evm-protocol-v2-3.0.162/interfaces/ILayerZeroEndpointV2.sol";
import {IEndpointV2State} from "src/interfaces/layerzero/IEndpointV2State.sol";

// Constants
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {Kernel, Actions, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {LZBridgeGateway} from "src/policies/bridge/LZBridgeGateway.sol";
import {LZBridgeActivator} from "src/proposals/LZBridgeActivator.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {IERC20} from "@openzeppelin-5.3.0/token/ERC20/IERC20.sol";

contract LZBridgeActivatorForkTest is Test {
    // Fork configuration
    uint256 internal constant FORK_BLOCK = 24742168;

    // Role constants
    bytes32 internal constant _BRIDGE_ADMIN_ROLE = "bridge_admin";

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
    LZBridgeActivator public activator;
    ILayerZeroEndpointV2 public endpoint;

    function setUp() public {
        vm.createSelectFork("mainnet", FORK_BLOCK);

        kernel = Kernel(KERNEL);
        roles = ROLESv1(address(kernel.getModuleForKeycode(toKeycode("ROLES"))));
        rolesAdmin = RolesAdmin(ROLES_ADMIN);
        endpoint = ILayerZeroEndpointV2(LZConfigLib.ETH_LZ_ENDPOINT);

        // Deploy gateway (canonical on mainnet)
        gateway = new LZBridgeGateway(kernel, LZConfigLib.ETH_LZ_ENDPOINT, true);

        // Deploy activator (owned by timelock)
        activator = new LZBridgeActivator(
            TIMELOCK,
            address(gateway),
            LZConfigLib.ETH_LZ_ENDPOINT,
            makeAddr("ARB_GATEWAY"),
            makeAddr("OPT_GATEWAY"),
            makeAddr("BASE_GATEWAY"),
            makeAddr("BERA_GATEWAY")
        );

        // Activate gateway in kernel (as DAO MS, which is the kernel executor)
        vm.prank(DAO_MS);
        kernel.executeAction(Actions.ActivatePolicy, address(gateway));
    }

    function _grantRequiredRoles() internal {
        vm.startPrank(TIMELOCK);
        rolesAdmin.grantRole(ADMIN_ROLE, address(activator));
        rolesAdmin.grantRole(_BRIDGE_ADMIN_ROLE, address(activator));
        vm.stopPrank();
    }

    // ========== CONSTRUCTOR TESTS ========== //

    function test_constructor_setsParametersCorrectly() public {
        assertEq(activator.owner(), TIMELOCK);
        assertEq(activator.GATEWAY(), address(gateway));
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
            address(0),
            makeAddr("A"),
            makeAddr("O"),
            makeAddr("B"),
            makeAddr("Be")
        );
    }

    // ========== ACCESS CONTROL TESTS ========== //

    function test_activate_revertsWhen_notOwner() public {
        _grantRequiredRoles();

        vm.expectRevert("UNAUTHORIZED");
        vm.prank(DAO_MS);
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

        assertFalse(PolicyEnabler(address(gateway)).isEnabled());

        vm.prank(TIMELOCK);
        activator.activate();

        assertTrue(PolicyEnabler(address(gateway)).isEnabled());
    }

    function test_activate_revokesDelegateAfterExecution() public {
        _grantRequiredRoles();

        vm.prank(TIMELOCK);
        activator.activate();

        // Delegate should be revoked (address(0))
        assertEq(
            IEndpointV2State(address(endpoint)).delegates(address(gateway)),
            address(0),
            "Delegate should be revoked after activation"
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
            assertEq(uln.requiredDVNCount, 2, "Should require 2 DVNs");

            // Route-aware DVN verification
            address[] memory expectedDvns = LZConfigLib.dvnsForRoute(LZConfigLib.ETH_EID, eid);
            assertEq(uln.requiredDVNs[0], expectedDvns[0], "DVN[0] mismatch");
            assertEq(uln.requiredDVNs[1], expectedDvns[1], "DVN[1] mismatch");
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
            assertEq(uln.requiredDVNCount, 2, "Should require 2 DVNs");

            address[] memory expectedDvns = LZConfigLib.dvnsForRoute(LZConfigLib.ETH_EID, eid);
            assertEq(uln.requiredDVNs[0], expectedDvns[0], "DVN[0] mismatch");
            assertEq(uln.requiredDVNs[1], expectedDvns[1], "DVN[1] mismatch");
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

    // ========== DVN ROUTE VERIFICATION ========== //

    function test_activate_berachainRouteUsesNethermindDvn() public {
        _grantRequiredRoles();

        vm.prank(TIMELOCK);
        activator.activate();

        // Verify Berachain route uses Nethermind, not Google Cloud
        bytes memory sendCfg = endpoint.getConfig(
            address(gateway),
            LZConfigLib.ETH_SEND_ULN_302,
            LZConfigLib.BERA_EID,
            LZConfigLib.CONFIG_TYPE_ULN
        );
        UlnConfig memory sendUln = abi.decode(sendCfg, (UlnConfig));

        address[] memory beraDvns = LZConfigLib.dvnsForRoute(
            LZConfigLib.ETH_EID,
            LZConfigLib.BERA_EID
        );
        // Should be ETH_LZ_DVN + ETH_NETHERMIND_DVN (not GCLOUD_DVN)
        assertEq(sendUln.requiredDVNs[0], beraDvns[0], "Bera route DVN[0] should be ETH_LZ_DVN");
        assertEq(
            sendUln.requiredDVNs[1],
            beraDvns[1],
            "Bera route DVN[1] should be ETH_NETHERMIND_DVN"
        );
        assertEq(
            sendUln.requiredDVNs[1],
            LZConfigLib.ETH_NETHERMIND_DVN,
            "Bera route should use Nethermind DVN"
        );
    }

    function test_activate_nonBerachainRoutesUseGoogleCloudDvn() public {
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
            assertEq(
                uln.requiredDVNs[1],
                LZConfigLib.ETH_GCLOUD_DVN,
                "Non-Bera route should use Google Cloud DVN"
            );
        }
    }
}
/// forge-lint: disable-end(mixed-case-function,mixed-case-variable)
