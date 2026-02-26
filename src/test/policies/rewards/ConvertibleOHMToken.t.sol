// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.30;

import {Test, stdError} from "forge-std/Test.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {Kernel, Actions, toKeycode, Keycode, Policy} from "src/Kernel.sol";
import {OlympusTreasury} from "src/modules/TRSRY/OlympusTreasury.sol";
import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {ConvertibleOHMTeller} from "src/policies/rewards/convertible/ConvertibleOHMTeller.sol";
import {ConvertibleOHMToken} from "src/policies/rewards/convertible/ConvertibleOHMToken.sol";
import {IConvertibleOHMTeller} from "src/policies/rewards/convertible/interfaces/IConvertibleOHMTeller.sol";
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {MockOhm} from "src/test/mocks/MockOhm.sol";

contract ConvertibleOHMTokenTestBase is Test {
    // Contracts
    Kernel kernel;
    OlympusTreasury trsry;
    OlympusMinter mintr;
    OlympusRoles roles;

    MockOhm ohm;
    MockERC20 usds;

    ConvertibleOHMTeller teller;

    // Constants
    uint256 internal constant _DEFAULT_MINT_CAP = 1000e9;

    // Test accounts
    address rewardDistributor = makeAddr("rewardDistributor");
    address admin = makeAddr("admin");
    address user0 = makeAddr("user0");
    address user1 = makeAddr("user1");

    // Test parameters
    uint256 constant STRIKE_PRICE = 15e18; // 15 USDS per OHM
    uint48 eligibleTimestamp;
    uint48 expiryTimestamp;

    function setUp() public virtual {
        // Deploy mock tokens
        ohm = new MockOhm("Olympus", "OHM", 9);
        usds = new MockERC20("USDS", "USDS", 18);
        // Deploy the kernel
        kernel = new Kernel();
        // Deploy the required modules
        trsry = new OlympusTreasury(kernel);
        mintr = new OlympusMinter(kernel, address(ohm));
        roles = new OlympusRoles(kernel);
        // Install the modules
        kernel.executeAction(Actions.InstallModule, address(trsry));
        kernel.executeAction(Actions.InstallModule, address(mintr));
        kernel.executeAction(Actions.InstallModule, address(roles));

        // Deploy the teller policy
        teller = new ConvertibleOHMTeller(address(kernel), address(ohm));
        // Activate the policy
        kernel.executeAction(Actions.ActivatePolicy, address(teller));

        // Grant the permission to this test contract to call saveRole
        _grantModulePermission(toKeycode("ROLES"), ROLESv1.saveRole.selector);
        // Setup roles
        roles.saveRole(teller.ROLE_TELLER_ADMIN(), admin);
        roles.saveRole(ADMIN_ROLE, address(this));

        // Enable the teller policy with infinite minting cap
        teller.enable(abi.encode(type(uint256).max));

        // Grant the reward distributor role (required for the functions deploy and create)
        roles.saveRole(teller.ROLE_REWARD_DISTRIBUTOR(), rewardDistributor);

        // Fund users with USDS for exercise tests
        usds.mint(user0, 1_000_000e18);
        usds.mint(user1, 1_000_000e18);

        // Prepare test parameters
        uint48 startTimestamp = uint48(vm.getBlockTimestamp());
        // Set the eligible time to 3 months from now (rounded to the nearest day)
        eligibleTimestamp = _roundToDay(startTimestamp + 90 days);
        // Set the expiry time to 6 months from now (rounded to the nearest day)
        expiryTimestamp = _roundToDay(startTimestamp + 180 days);
    }

    function _grantModulePermission(Keycode keycode, bytes4 selector) internal {
        // modulePermissions is at slot 6 in Kernel
        bytes32 slot = keccak256(
            abi.encode(
                selector,
                keccak256(abi.encode(address(this), keccak256(abi.encode(keycode, 6))))
            )
        );
        vm.store(address(kernel), slot, bytes32(uint256(1)));
        // Validate that the hardcoded slot matches the actual storage layout
        require(
            kernel.modulePermissions(keycode, Policy(address(this)), selector),
            "Storage slot mismatch: modulePermissions slot may have changed"
        );
    }

    function _deployConvertibleToken() internal returns (ConvertibleOHMToken token) {
        vm.prank(rewardDistributor);
        token = ConvertibleOHMToken(
            teller.deploy(address(usds), eligibleTimestamp, expiryTimestamp, STRIKE_PRICE)
        );
    }

    // Calculates the exact exercise cost using the teller
    function _exerciseCost(
        ConvertibleOHMToken token,
        uint256 amount
    ) internal view returns (uint256) {
        (, uint256 cost) = teller.exerciseCost(address(token), amount);
        return cost;
    }

    function _roundToDay(uint48 timestamp) internal pure returns (uint48) {
        return uint48(timestamp / 1 days) * 1 days;
    }
}

contract ConvertibleOHMTokenTests is ConvertibleOHMTokenTestBase {
    ConvertibleOHMToken token;

    uint256 user0InitialBal = 100e9;

    function setUp() public override {
        super.setUp();

        // Deploy the convertible token
        token = _deployConvertibleToken();

        // Mint convertible tokens to User0
        vm.prank(rewardDistributor);
        teller.create(address(token), user0, user0InitialBal);
    }

    function test_transfer() external {
        // User0 transfers to User1
        uint256 value = (user0InitialBal * 4) / 10;
        vm.prank(user0);
        bool success = token.transfer(user1, value);

        // Verify
        assertTrue(success, "The transfer should be successful");
        assertEq(token.balanceOf(user0), user0InitialBal - value, "User0 should transfer tokens");
        assertEq(token.balanceOf(user1), value, "User1 should receive tokens");
    }

    function test_approve() external {
        // User0 approves User1
        uint256 value = user0InitialBal / 2;
        vm.prank(user0);
        bool success = token.approve(user1, value);

        // Verify
        assertTrue(success, "The approval should be successful");
        assertEq(token.allowance(user0, user1), value, "The allowance should be set");
    }

    function test_transferFrom() external {
        // 1. Preparation: User0 approves User1
        uint256 approvedValue = user0InitialBal / 2;
        vm.prank(user0);
        token.approve(user1, approvedValue);

        // 2. Test
        // User1 transfers from User0
        uint256 value = approvedValue / 2;
        vm.prank(user1);
        bool success = token.transferFrom(user0, user1, value);

        // Verify
        assertTrue(success, "The transfer should be successful");
        assertEq(
            token.balanceOf(user0),
            user0InitialBal - value,
            "User0 should transfer convertible tokens"
        );
        assertEq(token.balanceOf(user1), value, "User1 should receive convertible tokens");
        assertEq(
            token.allowance(user0, user1),
            approvedValue - value,
            "The allowance should be reduced"
        );
    }

    function test_parameters() external view {
        (
            address quoteToken,
            address creator_,
            uint48 eligible_,
            uint48 expiry_,
            uint256 strike_
        ) = token.parameters();

        assertEq(quoteToken, address(usds), "Quote token should be USDS");
        assertEq(creator_, rewardDistributor, "Creator should be reward distributor");
        assertEq(eligible_, _roundToDay(eligibleTimestamp), "Eligible should match");
        assertEq(expiry_, _roundToDay(expiryTimestamp), "Expiry should match");
        assertEq(strike_, STRIKE_PRICE, "Strike price should match");
    }

    function test_quote() external view {
        assertEq(token.quote(), address(usds), "Quote token should be USDS");
    }

    function test_eligible() external view {
        assertEq(
            token.eligible(),
            _roundToDay(eligibleTimestamp),
            "Eligible timestamp should match"
        );
    }

    function test_expiry() external view {
        assertEq(token.expiry(), _roundToDay(expiryTimestamp), "Expiry timestamp should match");
    }

    function test_teller() external view {
        assertEq(token.teller(), address(teller), "Teller should match");
    }

    function test_creator() external view {
        assertEq(token.creator(), rewardDistributor, "Creator should be reward distributor");
    }

    function test_strike() external view {
        assertEq(token.strike(), STRIKE_PRICE, "Strike price should match");
    }

    function test_mintFor_updatesTotalSupplyAndBalance() external {
        // Mint additional tokens to User1
        uint256 mintAmount = 50e9;
        uint256 totalSupplyBefore = token.totalSupply();

        vm.prank(rewardDistributor);
        teller.create(address(token), user1, mintAmount);

        // Verify
        assertEq(token.balanceOf(user1), mintAmount, "User1 should receive minted tokens");
        assertEq(
            token.totalSupply(),
            totalSupplyBefore + mintAmount,
            "Total supply should increase by minted amount"
        );
    }

    function test_mintFor_revertsIfNotTeller() external {
        vm.expectRevert(ConvertibleOHMToken.ConvertibleOHMToken_OnlyTeller.selector);
        vm.prank(user0);
        token.mintFor(user0, 100e9);
    }

    function test_burnFrom_revertsIfNotTeller() external {
        vm.expectRevert(ConvertibleOHMToken.ConvertibleOHMToken_OnlyTeller.selector);
        vm.prank(user0);
        token.burnFrom(user0, user0InitialBal);
    }

    function test_burnFrom_revertsIfInsufficientAllowance() external {
        // 1. Preparation: User0 approves less than the burn amount
        uint256 approvedAmount = user0InitialBal / 2;
        vm.prank(user0);
        token.approve(address(teller), approvedAmount);

        // 2. Test: teller tries to burn more than approved (via exercise)
        vm.warp(eligibleTimestamp);
        uint256 exerciseCost = _exerciseCost(token, user0InitialBal);
        vm.startPrank(user0);
        usds.approve(address(teller), exerciseCost);
        vm.expectRevert(stdError.arithmeticError);
        teller.exercise(address(token), user0InitialBal);
        vm.stopPrank();
    }

    function test_burnFrom_revertsIfNoAllowance() external {
        // 1. Preparation: warp to eligible, no token approval given
        vm.warp(eligibleTimestamp);

        // 2. Test: exercise without approving the teller for convertible tokens
        uint256 exerciseCost = _exerciseCost(token, user0InitialBal);
        vm.startPrank(user0);
        usds.approve(address(teller), exerciseCost);
        vm.expectRevert(stdError.arithmeticError);
        teller.exercise(address(token), user0InitialBal);
        vm.stopPrank();
    }

    function test_burnFrom_succeedsWithExactAllowance() external {
        // 1. Preparation: User0 approves exact amount
        vm.warp(eligibleTimestamp);
        uint256 exerciseCost = _exerciseCost(token, user0InitialBal);

        // 2. Test
        vm.startPrank(user0);
        token.approve(address(teller), user0InitialBal);
        usds.approve(address(teller), exerciseCost);
        teller.exercise(address(token), user0InitialBal);
        vm.stopPrank();

        // Verify: allowance should be fully consumed
        assertEq(
            token.allowance(user0, address(teller)),
            0,
            "Allowance should be zero after exact burn"
        );
        assertEq(token.balanceOf(user0), 0, "All tokens should be burned");
    }

    function test_burnFrom_succeedsWithMaxAllowance() external {
        // 1. Preparation: User0 approves max (infinite approval)
        vm.warp(eligibleTimestamp);
        uint256 exerciseCost = _exerciseCost(token, user0InitialBal);

        // 2. Test
        vm.startPrank(user0);
        token.approve(address(teller), type(uint256).max);
        usds.approve(address(teller), exerciseCost);
        teller.exercise(address(token), user0InitialBal);
        vm.stopPrank();

        // Verify: max allowance should not be decremented
        assertEq(
            token.allowance(user0, address(teller)),
            type(uint256).max,
            "Max allowance should not be decremented"
        );
        assertEq(token.balanceOf(user0), 0, "All tokens should be burned");
    }
}
