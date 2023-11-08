// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {console2} from "forge-std/console2.sol";
import {Bytes32AddressLib} from "solmate/utils/Bytes32AddressLib.sol";

//import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockOhm} from "test/mocks/MockOhm.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {MINTRv1} from "modules/MINTR/MINTR.v1.sol";

import {FullMath} from "libraries/FullMath.sol";

import "src/Kernel.sol";

import {CrossChainBridge, ILayerZeroEndpoint} from "policies/CrossChainBridge.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {LZEndpointMock} from "layer-zero/mocks/LZEndpointMock.sol";

contract CrossChainBridgeTest is Test {
    using FullMath for uint256;
    using Bytes32AddressLib for address;

    address internal user;
    address internal user2;
    address internal guardian;
    MockOhm internal ohm;

    LZEndpointMock internal endpoint;
    LZEndpointMock internal endpoint_l2;

    uint16 internal constant MAINNET_CHAIN_ID = 1;
    uint16 internal constant L2_CHAIN_ID = 101;

    uint256 internal constant INITIAL_AMOUNT = 100000e9;

    // Mainnet contracts
    Kernel internal kernel;
    OlympusMinter internal MINTR;
    OlympusRoles internal ROLES;
    RolesAdmin internal rolesAdmin;
    CrossChainBridge internal bridge;

    // L2 contracts
    Kernel internal kernel_l2;
    OlympusMinter internal MINTR_l2;
    OlympusRoles internal ROLES_l2;
    RolesAdmin internal rolesAdmin_l2;
    CrossChainBridge internal bridge_l2;

    function setUp() public {
        address[] memory users = (new UserFactory()).create(3);
        user = users[0];
        user2 = users[1];
        guardian = users[2];

        vm.deal(user, 100 ether);

        ohm = new MockOhm("OHM", "OHM", 9);

        // NOTE: Simplified test setup: Both endpoints are on the same chain in this test, but
        // will test the functionality of a message being sent by having the endpoint lookup
        // tables pointing to eachother.

        // Create mock endpoint for mainnet and arbitrum
        endpoint = new LZEndpointMock(1);
        endpoint_l2 = new LZEndpointMock(101);

        // Setup mainnet system
        {
            kernel = new Kernel(); // this contract will be the executor

            MINTR = new OlympusMinter(kernel, address(ohm));
            ROLES = new OlympusRoles(kernel);

            // Enable counter
            bridge = new CrossChainBridge(kernel, address(endpoint));
            rolesAdmin = new RolesAdmin(kernel);

            kernel.executeAction(Actions.InstallModule, address(MINTR));
            kernel.executeAction(Actions.InstallModule, address(ROLES));

            kernel.executeAction(Actions.ActivatePolicy, address(bridge));
            kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        }

        // Setup L2 system
        {
            kernel_l2 = new Kernel(); // this contract will be the executor

            MINTR_l2 = new OlympusMinter(kernel_l2, address(ohm));
            ROLES_l2 = new OlympusRoles(kernel_l2);

            // No counter necessary since this is L2
            bridge_l2 = new CrossChainBridge(kernel_l2, address(endpoint_l2));
            rolesAdmin_l2 = new RolesAdmin(kernel_l2);

            kernel_l2.executeAction(Actions.InstallModule, address(MINTR_l2));
            kernel_l2.executeAction(Actions.InstallModule, address(ROLES_l2));

            kernel_l2.executeAction(Actions.ActivatePolicy, address(bridge_l2));
            kernel_l2.executeAction(Actions.ActivatePolicy, address(rolesAdmin_l2));
        }

        // Configure access control
        rolesAdmin.grantRole("bridge_admin", guardian);
        rolesAdmin_l2.grantRole("bridge_admin", guardian);

        // Set guardian to the bridge owner for both endpoints and set trusted remote addresses
        vm.startPrank(guardian);

        // Mainnet setup
        bytes memory path1 = abi.encodePacked(address(bridge_l2), address(bridge));
        bridge.setTrustedRemote(L2_CHAIN_ID, path1);
        endpoint.setDestLzEndpoint(address(bridge_l2), address(endpoint_l2));

        // L2 setup
        bytes memory path2 = abi.encodePacked(address(bridge), address(bridge_l2));
        bridge_l2.setTrustedRemote(MAINNET_CHAIN_ID, path2);
        endpoint_l2.setDestLzEndpoint(address(bridge), address(endpoint));

        vm.stopPrank();

        // Setup user wallet on mainnet
        vm.startPrank(address(bridge)); // Bridge has mintOhm permissions
        MINTR.increaseMintApproval(address(bridge), type(uint256).max);
        MINTR.mintOhm(user, INITIAL_AMOUNT); // Give user 100k OHM
        vm.stopPrank();
    }

    // ======== SETUP DEPENDENCIES ======= //

    function test_configureDependencies() public {
        Keycode[] memory expectedDeps = new Keycode[](2);
        expectedDeps[0] = toKeycode("MINTR");
        expectedDeps[1] = toKeycode("ROLES");

        Keycode[] memory deps = bridge.configureDependencies();
        // Check: configured dependencies storage
        assertEq(deps.length, expectedDeps.length);
        assertEq(fromKeycode(deps[0]), fromKeycode(expectedDeps[0]));
        assertEq(fromKeycode(deps[1]), fromKeycode(expectedDeps[1]));
    }

    function test_requestPermissions() public {
        Permissions[] memory expectedPerms = new Permissions[](3);
        Keycode MINTR_KEYCODE = toKeycode("MINTR");
        expectedPerms[0] = Permissions(MINTR_KEYCODE, MINTR.mintOhm.selector);
        expectedPerms[1] = Permissions(MINTR_KEYCODE, MINTR.burnOhm.selector);
        expectedPerms[2] = Permissions(MINTR_KEYCODE, MINTR.increaseMintApproval.selector);

        Permissions[] memory perms = bridge.requestPermissions();
        // Check: permission storage
        assertEq(perms.length, expectedPerms.length);
        for (uint256 i = 0; i < perms.length; i++) {
            assertEq(fromKeycode(perms[i].keycode), fromKeycode(expectedPerms[i].keycode));
            assertEq(perms[i].funcSelector, expectedPerms[i].funcSelector);
        }
    }

    // =========  HELPER FUNCTIONS ========= //

    // TODO
    // [ ] sendOhm
    //     [x] confirm ohm is sent to other chain
    //     [x] revert on insufficient funds
    //     [ ] revert if endpoint is down
    //     [ ] reproduce fail and retry, confirm balances
    //     [x] make sure offchain ohm count is accurate

    function testCorrectness_SendOhm(uint256 amount_) public {
        vm.assume(amount_ > 0);
        vm.assume(amount_ < ohm.balanceOf(user));

        (uint256 fee, ) = bridge.estimateSendFee(L2_CHAIN_ID, user2, amount_, bytes(""));

        // Send ohm to user2 on L2
        vm.startPrank(user);
        ohm.approve(address(bridge), amount_);
        bridge.sendOhm{value: fee}(L2_CHAIN_ID, user2, amount_);

        // Verify ohm balance is correct
        assertEq(ohm.balanceOf(user2), amount_);
    }

    function testRevert_InsufficientAmountOnSend(uint256 amount_) public {
        vm.assume(amount_ > ohm.balanceOf(user));

        (uint256 fee, ) = bridge.estimateSendFee(L2_CHAIN_ID, user2, amount_, bytes(""));

        vm.startPrank(user);
        ohm.approve(address(bridge), amount_);

        vm.expectRevert(CrossChainBridge.Bridge_InsufficientAmount.selector);
        bridge.sendOhm{value: fee}(L2_CHAIN_ID, user2, amount_);
    }

    // TODO don't think this is needed. Cannot make bridge fail
    // if a message has been received already
    /*
    function testCorrectness_RetryMessage() public {
        uint256 amount = 100;

        // Block next message, then attempt sending OHM crosschain
        endpoint_l2.blockNextMsg();

        vm.startPrank(user);
        ohm.approve(address(bridge), amount);
        bridge.sendOhm{value: 1e17}(user2, amount, L2_CHAIN_ID);

        assertEq(ohm.balanceOf(user2), 0);

        // Retry blocked message on L2
        bytes memory payload = abi.encode(user2, amount);

        endpoint_l2.retryPayload(
            MAINNET_CHAIN_ID,
            abi.encode(address(bridge)),
            payload
        );

        assertEq(ohm.balanceOf(user2), amount);
    }
    */

    //function testCorrectness_RoleCanBecomeOwner() public {
    //    rolesAdmin.grantRole("bridge_admin", user2);
    //    vm.prank(user2);
    //    bridge.becomeOwner();
    //    assertEq(user2, bridge.owner());
    //}

    // TODO Use pigeon to simulate messages between forks
    // https://github.com/exp-table/pigeon
}
