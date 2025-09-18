// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {Test} from "@forge-std-1.9.6/Test.sol";

import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "@solmate-6.2.0/test/utils/mocks/MockERC4626.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";

import {IReserveWrapper} from "src/policies/interfaces/IReserveWrapper.sol";
import {ReserveWrapper} from "src/policies/ReserveWrapper.sol";

contract ReserveWrapperTest is Test {
    event ReserveWrapped(address indexed reserve, address indexed sReserve, uint256 amount);

    address internal ADMIN;
    address internal EMERGENCY;
    address internal HEART;

    MockERC20 internal reserve;
    MockERC4626 internal sReserve;

    Kernel internal kernel;
    OlympusTreasury internal TRSRY;
    OlympusRoles internal ROLES;

    RolesAdmin internal rolesAdmin;
    ReserveWrapper internal reserveWrapper;

    function setUp() public {
        // Create users
        ADMIN = makeAddr("ADMIN");
        EMERGENCY = makeAddr("EMERGENCY");
        HEART = makeAddr("HEART");

        // Deploy mock tokens and converter
        reserve = new MockERC20("Dai Stablecoin", "DAI", 18);
        sReserve = new MockERC4626(reserve, "Savings Dai", "sDAI");

        // Deploy kernel
        kernel = new Kernel();

        // Deploy modules
        TRSRY = new OlympusTreasury(kernel);
        ROLES = new OlympusRoles(kernel);

        // Deploy policies
        rolesAdmin = new RolesAdmin(kernel);
        reserveWrapper = new ReserveWrapper(address(kernel), address(reserve), address(sReserve));

        // Label the tokens for easier debugging
        vm.label(address(reserve), "reserve");
        vm.label(address(sReserve), "sReserve");

        // Activate modules and policies
        kernel.executeAction(Actions.InstallModule, address(TRSRY));
        kernel.executeAction(Actions.InstallModule, address(ROLES));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(reserveWrapper));

        // Grant the roles
        rolesAdmin.grantRole("admin", ADMIN);
        rolesAdmin.grantRole("emergency", EMERGENCY);
        rolesAdmin.grantRole("heart", HEART);

        // Create sReserve supply
        address otherUser = makeAddr("otherUser");
        reserve.mint(otherUser, 100e18);
        vm.startPrank(otherUser);
        reserve.approve(address(sReserve), 100e18);
        sReserve.deposit(100e18, otherUser);
        vm.stopPrank();

        // Accrue yield to the ERC4626
        reserve.mint(address(sReserve), 30e18);
    }

    modifier givenEnabled() {
        vm.prank(ADMIN);
        reserveWrapper.enable("");
        _;
    }

    modifier givenAddressHasReserveTokens(address account_, uint256 amount_) {
        reserve.mint(account_, amount_);
        _;
    }

    // ========== TESTS ========== //

    // constructor
    // when the reserve address is null
    //  [X] it reverts

    function test_constructor_whenReserveIsZeroAddress_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IReserveWrapper.ReserveWrapper_ZeroAddress.selector)
        );

        // Deploy the contract
        new ReserveWrapper(address(kernel), address(0), address(sReserve));
    }

    // given the sReserve asset is not the same as the reserve
    //  [X] it reverts

    function test_constructor_whenSReserveAssetIsNotTheSameAsTheReserve_reverts() public {
        // Deploy a different sReserve
        MockERC20 reserve2 = new MockERC20("Dai Stablecoin", "DAI", 18);
        MockERC4626 sReserve2 = new MockERC4626(reserve2, "Savings Dai", "sDAI");

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IReserveWrapper.ReserveWrapper_AssetMismatch.selector)
        );

        // Deploy the contract
        new ReserveWrapper(address(kernel), address(reserve), address(sReserve2));
    }

    // [X] it sets the reserve and sReserve addresses

    function test_constructor() public view {
        assertEq(reserveWrapper.getReserve(), address(reserve), "Reserve address mismatch");
        assertEq(reserveWrapper.getSReserve(), address(sReserve), "sReserve address mismatch");
    }

    // execute
    // given the caller does not have the heart role
    //  [X] it reverts

    function test_execute_givenCallerDoesNotHaveHeartRole_reverts(address caller_) public {
        vm.assume(caller_ != HEART);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, bytes32("heart"))
        );

        // Execute
        vm.prank(caller_);
        reserveWrapper.execute();
    }

    // given the contract is disabled
    //  [X] it does nothing

    function test_execute_givenContractIsDisabled()
        public
        givenAddressHasReserveTokens(address(TRSRY), 1e18)
    {
        // Execute
        vm.prank(HEART);
        reserveWrapper.execute();

        // Assert balances
        assertEq(reserve.balanceOf(address(TRSRY)), 1e18, "Reserve balance mismatch");
        assertEq(sReserve.balanceOf(address(TRSRY)), 0, "sReserve balance mismatch");
    }

    // given the reserve balance is 0
    //  [X] it does nothing

    function test_execute_givenReserveBalanceIsZero() public givenEnabled {
        // Execute
        vm.prank(HEART);
        reserveWrapper.execute();

        // Assert balances
        assertEq(reserve.balanceOf(address(TRSRY)), 0, "Reserve balance mismatch");
        assertEq(sReserve.balanceOf(address(TRSRY)), 0, "sReserve balance mismatch");
    }

    // given the previewDeposit would result in zero shares
    //  [X] it does nothing

    function test_execute_givenPreviewDepositWouldResultInZeroShares(
        uint256 amount_
    ) public givenEnabled {
        // Calculate amount
        uint256 oneShareInAssets = sReserve.previewMint(1);
        amount_ = bound(amount_, 1, oneShareInAssets - 1);

        // Mint this amount to the TRSRY
        reserve.mint(address(TRSRY), amount_);

        // Call function
        vm.prank(HEART);
        reserveWrapper.execute();

        // Assert balances
        assertEq(reserve.balanceOf(address(TRSRY)), amount_, "Reserve balance mismatch");
        assertEq(sReserve.balanceOf(address(TRSRY)), 0, "sReserve balance mismatch");
    }

    // [X] it withdraws the reserve from the TRSRY
    // [X] it wraps the reserve into the sReserve
    // [X] the TRSRY's sReserve balance is increased by the sReserve shares
    // [X] an event is emitted

    function test_execute(uint256 amount_) public givenEnabled {
        amount_ = bound(amount_, 1e18, 100e18);

        // Mint this amount to the TRSRY
        reserve.mint(address(TRSRY), amount_);

        // Calculate expected shares
        uint256 expectedShares = sReserve.previewDeposit(amount_);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit ReserveWrapped(address(reserve), address(sReserve), amount_);

        // Call function
        vm.prank(HEART);
        reserveWrapper.execute();

        // Assert balances
        assertEq(reserve.balanceOf(address(TRSRY)), 0, "Reserve balance mismatch");
        assertEq(sReserve.balanceOf(address(TRSRY)), expectedShares, "sReserve balance mismatch");
    }
}
