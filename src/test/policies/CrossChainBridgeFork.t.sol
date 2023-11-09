// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test, Vm} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {Bytes32AddressLib} from "solmate/utils/Bytes32AddressLib.sol";

import {UserFactory} from "test/lib/UserFactory.sol";
import {FullMath} from "libraries/FullMath.sol";

//import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockOhm} from "test/mocks/MockOhm.sol";
import {MockGohm} from "test/mocks/OlympusMocks.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {MINTRv1} from "modules/MINTR/MINTR.v1.sol";
import {OlympusSupply} from "modules/SPPLY/OlympusSupply.sol";

import {CrossChainBridge, ILayerZeroEndpoint} from "policies/CrossChainBridge.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";

import {LayerZeroHelper} from "test/lib/pigeon/layerzero/LayerZeroHelper.sol";

import "src/Kernel.sol";

contract CrossChainBridgeForkTest is Test {
    using FullMath for uint256;
    using Bytes32AddressLib for address;

    address internal user1;
    address internal user2;
    address internal guardian1;
    address internal guardian2;
    MockOhm internal ohm1;
    MockOhm internal ohm2;
    MockGohm internal gOhm;

    LayerZeroHelper lzHelper;
    uint256 L1_FORK_ID;
    uint256 L2_FORK_ID;
    uint16 constant L1_ID = 101;
    uint16 constant L2_ID = 109;
    address constant L1_lzEndpoint = 0x66A71Dcef29A0fFBDBE3c6a460a3B5BC225Cd675;
    address constant L2_lzEndpoint = 0x3c2269811836af69497E5F486A85D7316753cf62;

    uint16 internal constant MAINNET_CHAIN_ID = 1;
    uint16 internal constant L2_CHAIN_ID = 137;

    uint256 internal constant INITIAL_AMOUNT = 100000e9;
    uint256 internal constant GOHM_INDEX = 267951435389; // From sOHM, 9 decimals

    string RPC_ETH_MAINNET = vm.envString("ETH_MAINNET_RPC_URL");
    string RPC_POLYGON_MAINNET = vm.envString("POLYGON_MAINNET_RPC_URL");

    // Mainnet contracts
    Kernel internal kernel;
    OlympusMinter internal MINTR;
    OlympusRoles internal ROLES;
    OlympusSupply internal SPPLY;
    RolesAdmin internal rolesAdmin;
    CrossChainBridge internal bridge;

    // L2 contracts
    Kernel internal kernel_l2;
    OlympusMinter internal MINTR_l2;
    OlympusRoles internal ROLES_l2;
    RolesAdmin internal rolesAdmin_l2;
    CrossChainBridge internal bridge_l2;

    function setUp() public {
        // Setup mainnet system
        {
            L1_FORK_ID = vm.createSelectFork(RPC_ETH_MAINNET);
            lzHelper = new LayerZeroHelper();

            address[] memory users1 = (new UserFactory()).create(2);
            user1 = users1[0];
            guardian1 = users1[1];

            vm.deal(user1, 100 ether);

            ohm1 = new MockOhm("OHM", "OHM", 9);
            ohm1.mint(user1, INITIAL_AMOUNT);

            gOhm = new MockGohm(GOHM_INDEX);

            address[2] memory tokens = [address(ohm1), address(gOhm)];

            kernel = new Kernel(); // this contract will be the executor

            MINTR = new OlympusMinter(kernel, address(ohm1));
            ROLES = new OlympusRoles(kernel);
            SPPLY = new OlympusSupply(kernel, tokens, 0);

            // Enable counter
            bridge = new CrossChainBridge(kernel, L1_lzEndpoint);
            rolesAdmin = new RolesAdmin(kernel);

            kernel.executeAction(Actions.InstallModule, address(MINTR));
            kernel.executeAction(Actions.InstallModule, address(ROLES));
            kernel.executeAction(Actions.InstallModule, address(SPPLY));

            kernel.executeAction(Actions.ActivatePolicy, address(bridge));
            kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));

            // Configure access control
            rolesAdmin.grantRole("bridge_admin", guardian1);
        }

        // Setup L2 system
        {
            L2_FORK_ID = vm.createSelectFork(RPC_POLYGON_MAINNET);

            address[] memory users2 = (new UserFactory()).create(2);
            user2 = users2[0];
            guardian2 = users2[1];

            ohm2 = new MockOhm("OHM", "OHM", 9);

            kernel_l2 = new Kernel(); // this contract will be the executor

            MINTR_l2 = new OlympusMinter(kernel_l2, address(ohm2));
            ROLES_l2 = new OlympusRoles(kernel_l2);

            // No counter necessary since this is L2
            bridge_l2 = new CrossChainBridge(kernel_l2, L2_lzEndpoint);
            rolesAdmin_l2 = new RolesAdmin(kernel_l2);

            kernel_l2.executeAction(Actions.InstallModule, address(MINTR_l2));
            kernel_l2.executeAction(Actions.InstallModule, address(ROLES_l2));

            kernel_l2.executeAction(Actions.ActivatePolicy, address(bridge_l2));
            kernel_l2.executeAction(Actions.ActivatePolicy, address(rolesAdmin_l2));

            // Configure access control
            rolesAdmin_l2.grantRole("bridge_admin", guardian2);
        }

        // Mainnet setup
        vm.selectFork(L1_FORK_ID);
        vm.startPrank(guardian1);
        //bridge.becomeOwner();
        bytes memory path1 = abi.encodePacked(address(bridge_l2), address(bridge));
        bridge.setTrustedRemote(L2_ID, path1);
        vm.stopPrank();

        // L2 setup
        vm.selectFork(L2_FORK_ID);
        vm.startPrank(guardian2);
        //bridge_l2.becomeOwner();
        bytes memory path2 = abi.encodePacked(address(bridge), address(bridge_l2));
        bridge_l2.setTrustedRemote(L1_ID, path2);
        vm.stopPrank();
    }

    function testCorrectness_SendOhm(uint256 amount_) public {
        vm.assume(amount_ > 0);
        vm.assume(amount_ < INITIAL_AMOUNT);

        // L1 transfer
        vm.selectFork(L1_FORK_ID);
        vm.recordLogs();

        // get fee
        (uint256 fee, ) = bridge.estimateSendFee(L2_ID, user2, amount_, bytes(""));

        // Send ohm to user2 on L2
        vm.startPrank(user1);
        ohm1.approve(address(bridge), amount_);
        bridge.sendOhm{value: fee}(L2_ID, user2, amount_);
        vm.stopPrank();

        // pigeon stuff
        Vm.Log[] memory logs = vm.getRecordedLogs();
        lzHelper.help(L2_lzEndpoint, 1e17, L2_FORK_ID, logs);

        // Verify ohm balance on L2 is correct
        vm.selectFork(L2_FORK_ID);
        assertEq(ohm2.balanceOf(user2), amount_);
    }

    /*
    function testCorrectness_RetryMessage() public {
        uint256 amount = 100;

        // Block next message, then attempt sending OHM crosschain
        vm.selectFork(L2_FORK_ID);
        endpoint_l2.blockNextMsg();

        vm.startPrank(user);
        ohm.approve(address(bridge), amount);
        bridge.sendOhm{value: 1e17}(L2_ID, user2, amount);

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
}
