// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {UserFactory} from "test/lib/UserFactory.sol";
import {console2} from "forge-std/console2.sol";

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

    address internal randomWallet;
    address internal guardian;
    MockERC20 internal ohm;
    LZEndpointMock internal endpoint;

    Kernel internal kernel;

    OlympusMinter internal MINTR;
    OlympusRoles internal ROLES;

    CrossChainBridge internal bridge;
    RolesAdmin internal rolesAdmin;

    function setUp() public {
        address[] memory users = (new UserFactory()).create(2);
        randomWallet = users[0];
        guardian = users[1];

        ohm = new MockERC20("OHM", "OHM", 9);

        // Create endpoint for mainnet
        endpoint = new LZEndpointMock(1);

        kernel = new Kernel(); // this contract will be the executor

        MINTR = new OlympusMinter(kernel, address(ohm));
        ROLES = new OlympusRoles(kernel);

        bridge = new CrossChainBridge(kernel, address(endpoint));
        rolesAdmin = new RolesAdmin(kernel);

        kernel.executeAction(Actions.InstallModule, address(MINTR));
        kernel.executeAction(Actions.InstallModule, address(ROLES));

        kernel.executeAction(Actions.ActivatePolicy, address(bridge));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));

        /// Configure access control
        rolesAdmin.grantRole("bridge_admin", guardian);
    }

    // =========  HELPER FUNCTIONS ========= //

    // TODO
    // [ ] sendOhm
    //     [ ] confirm ohm is sent to other chain
    //     [ ] revert on insufficient funds
    //     [ ] revert if endpoint is down
    //     [ ] reproduce fail and retry, confirm balances

    function testCorrectness_SendOhm() public {}
    function testRevert_InsufficientFundsSent() public {}
    function testRevert_EndpointDown() public {}
    function testCorrectness_RetryMessage() public {}

    // TODO
    // [ ] lzRecieve
    //     [ ] confirm ohm is recieved from other chain
    function testCorrectness_ReceiveOhm() public {}

    // [ ] becomeOwner - Make sure owners are passed properly
    function testCorrectness_RoleCanBecomeOwner() public {}
}