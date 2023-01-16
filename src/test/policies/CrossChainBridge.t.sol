// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {console2} from "forge-std/console2.sol";
import {Bytes32AddressLib} from "solmate/utils/Bytes32AddressLib.sol";

import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
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
    address internal receiver;
    address internal guardian;
    MockERC20 internal ohm;

    LZEndpointMock internal endpoint;
    LZEndpointMock internal endpoint_l2;

    uint16 internal constant MAINNET_CHAIN_ID = 1;
    uint16 internal constant L2_CHAIN_ID = 101;

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
        receiver = users[1];
        guardian = users[2];

        ohm = new MockERC20("OHM", "OHM", 9);

        // NOTE: Simplified test setup: Both endpoints are on the same chain in this test, but
        // will test the functionality of a message being sent by having the endpoint lookup
        // tables pointing to eachother.

        // Create mock endpoint for mainnet and arbitrum
        endpoint = new LZEndpointMock(1);
        endpoint_l2 = new LZEndpointMock(101);

        //ethEndpoint.setDestLzEndpoint(address(arbEndpoint)); // TODO

        // Setup mainnet system
        {
            kernel = new Kernel(); // this contract will be the executor

            MINTR = new OlympusMinter(kernel, address(ohm));
            ROLES = new OlympusRoles(kernel);

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

        // mainnet setup 
        bridge.becomeOwner();
        bytes memory otherBridge = abi.encode(address(bridge_l2));
        bridge.setTrustedRemoteAddress(L2_CHAIN_ID, abi.encode(address(bridge_l2)));

        // l2 setup
        bridge_l2.becomeOwner();
        bridge.setTrustedRemoteAddress(MAINNET_CHAIN_ID, abi.encode(address(bridge)));

        vm.stopPrank();

        // Setup user wallet on mainnet
        vm.startPrank(address(bridge)); // Bridge has mintOhm permissions
        MINTR.increaseMintApproval(address(bridge), type(uint256).max);
        MINTR.mintOhm(user, 100000e9); // Give user 100k OHM
        vm.stopPrank();
    }

    // =========  HELPER FUNCTIONS ========= //

    // TODO
    // [ ] sendOhm
    //     [ ] confirm ohm is sent to other chain
    //     [ ] revert on insufficient funds
    //     [ ] revert if endpoint is down
    //     [ ] reproduce fail and retry, confirm balances

    function testCorrectness_SendOhm(uint256 amount_) public {
        vm.assume(amount_ <= ohm.balanceOf(user));

        // Send 10 ohm to myself on arbitrum
        vm.startPrank(user);
        //bridge.sendOhm(user, amount_, 101);

        // Send 20 ohm to someone else

        // Verify ohm balance is correct
    }

    function testRevert_InsufficientAmountOnSend(uint256 amount_) public {
        vm.assume(amount_ > ohm.balanceOf(user));

        //vm.startPrank(user);
        //bridge.sendOhm()

    }

    function testRevert_EndpointDown() public {}
    function testCorrectness_RetryMessage() public {}

    // TODO
    // [ ] lzRecieve
    //     [ ] confirm ohm is recieved from other chain
    function testCorrectness_ReceiveOhm() public {}

    // [ ] becomeOwner - Make sure owners are passed properly
    function testCorrectness_RoleCanBecomeOwner() public {}

    // TODO Use pigeon to simulate messages between forks
    // https://github.com/exp-table/pigeon
}