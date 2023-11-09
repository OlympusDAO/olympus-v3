// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

/// External Dependencies
import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test/lib/UserFactory.sol";

/// Import Distributor
import {Distributor} from "policies/Distributor/Distributor.sol";
import {IDistributor} from "policies/RBS/interfaces/IDistributor.sol";

import "src/Kernel.sol";
import {OlympusMinter} from "modules/MINTR/OlympusMinter.sol";
import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";

/// Import Mocks for non-Bophades contracts
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockGohm, MockStaking} from "test/mocks/OlympusMocks.sol";
import {MockUniV2Pair} from "test/mocks/MockUniV2Pair.sol";
import {MockLegacyAuthority} from "test/modules/MINTR.t.sol";

contract DistributorTest is Test {
    /// Bophades Systems
    Kernel internal kernel;
    OlympusMinter internal MINTR;
    OlympusTreasury internal TRSRY;
    OlympusRoles internal ROLES;

    Distributor internal distributor;
    RolesAdmin internal rolesAdmin;

    /// Tokens
    MockERC20 internal ohm;
    MockERC20 internal sohm;
    MockGohm internal gohm;
    MockERC20 internal dai;
    MockERC20 internal weth;

    /// Legacy Contracts
    MockStaking internal staking;

    /// External Contracts
    MockUniV2Pair internal ohmDai;
    MockUniV2Pair internal ohmWeth;

    function setUp() public {
        {
            /// Deploy Kernal and tokens
            kernel = new Kernel();
            ohm = new MockERC20("OHM", "OHM", 9);
            sohm = new MockERC20("sOHM", "sOHM", 9);
            gohm = new MockGohm(100_000_000_000);
            dai = new MockERC20("DAI", "DAI", 18);
            weth = new MockERC20("WETH", "WETH", 18);
        }

        {
            /// Deploy UniV2 Pools
            ohmDai = new MockUniV2Pair(address(ohm), address(dai));
            ohmWeth = new MockUniV2Pair(address(ohm), address(weth));
        }

        {
            /// Deploy Bophades Modules
            MINTR = new OlympusMinter(kernel, address(ohm));
            TRSRY = new OlympusTreasury(kernel);
            ROLES = new OlympusRoles(kernel);
        }

        {
            /// Initialize Modules
            kernel.executeAction(Actions.InstallModule, address(MINTR));
            kernel.executeAction(Actions.InstallModule, address(TRSRY));
            kernel.executeAction(Actions.InstallModule, address(ROLES));
        }

        {
            /// Deploy Staking, Distributor, and Roles Admin
            staking = new MockStaking(address(ohm), address(sohm), address(gohm), 2200, 0, 2200);
            distributor = new Distributor(kernel, address(ohm), address(staking), 1000000); // 0.1%
            rolesAdmin = new RolesAdmin(kernel);

            staking.setDistributor(address(distributor));
        }

        {
            /// Initialize Distributor Policy
            kernel.executeAction(Actions.ActivatePolicy, address(distributor));
            kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));

            rolesAdmin.grantRole("distributor_admin", address(this));
        }

        {
            /// Mint Tokens
            vm.startPrank(address(distributor));
            MINTR.increaseMintApproval(address(distributor), type(uint256).max);

            /// Mint OHM to deployer and staking contract
            MINTR.mintOhm(address(staking), 100000 gwei);
            MINTR.mintOhm(address(this), 100000 gwei);

            /// Mint DAI and OHM to OHM-DAI pool
            MINTR.mintOhm(address(ohmDai), 100000 gwei);
            dai.mint(address(ohmDai), 100000 * 10 ** 18);
            ohmDai.sync();

            /// Mint WETH and OHM to OHM-WETH pool
            MINTR.mintOhm(address(ohmWeth), 100000 gwei);
            weth.mint(address(ohmWeth), 100000 * 10 ** 18);
            ohmWeth.sync();
            vm.stopPrank();

            /// Stake deployer's OHM
            ohm.approve(address(staking), type(uint256).max);
            staking.stake(address(this), 100 gwei, true, true);
        }

        {
            /// Initialize block.timestamp
            vm.warp(0);
        }
    }

    /// Basic post-setup functionality tests
    function test_defaultState() public {
        assertEq(distributor.rewardRate(), 1000000);
        assertEq(distributor.bounty(), 0);

        assertEq(ohm.balanceOf(address(staking)), 100100 gwei);
    }

    // ======== SETUP DEPENDENCIES ======= //

    function test_configureDependencies() public {
        Keycode[] memory expectedDeps = new Keycode[](3);
        expectedDeps[0] = toKeycode("MINTR");
        expectedDeps[1] = toKeycode("TRSRY");
        expectedDeps[2] = toKeycode("ROLES");

        Keycode[] memory deps = distributor.configureDependencies();
        // Check: configured dependencies storage
        assertEq(deps.length, expectedDeps.length);
        assertEq(fromKeycode(deps[0]), fromKeycode(expectedDeps[0]));
        assertEq(fromKeycode(deps[1]), fromKeycode(expectedDeps[1]));
        assertEq(fromKeycode(deps[2]), fromKeycode(expectedDeps[2]));
    }

    function test_requestPermissions() public {
        Permissions[] memory expectedPerms = new Permissions[](3);
        Keycode MINTR_KEYCODE = toKeycode("MINTR");
        expectedPerms[0] = Permissions(MINTR_KEYCODE, MINTR.mintOhm.selector);
        expectedPerms[1] = Permissions(MINTR_KEYCODE, MINTR.increaseMintApproval.selector);
        expectedPerms[2] = Permissions(MINTR_KEYCODE, MINTR.decreaseMintApproval.selector);

        Permissions[] memory perms = distributor.requestPermissions();
        // Check: permission storage
        assertEq(perms.length, expectedPerms.length);
        for (uint256 i = 0; i < perms.length; i++) {
            assertEq(fromKeycode(perms[i].keycode), fromKeycode(expectedPerms[i].keycode));
            assertEq(perms[i].funcSelector, expectedPerms[i].funcSelector);
        }
    }

    /* ========== BASIC TESTS ========== */

    /// [X]  distribute()
    ///     [X]  Can only be called by staking
    ///     [X]  Cannot be called if not unlocked
    function testCorrectness_distributeOnlyStaking() public {
        bytes memory err = abi.encodeWithSelector(IDistributor.Distributor_OnlyStaking.selector);
        vm.expectRevert(err);
        distributor.distribute();
    }

    function testCorrectness_distributeNotUnlocked() public {
        bytes memory err = abi.encodeWithSelector(IDistributor.Distributor_NotUnlocked.selector);
        vm.expectRevert(err);

        vm.prank(address(staking));
        distributor.distribute();
    }

    /// [X]  retrieveBounty()
    ///     [X]  Can only be called by staking
    ///     [X]  Bounty is zero and no OHM is minted
    function test_retrieveBountyOnlyStaking() public {
        vm.expectRevert(abi.encodeWithSelector(IDistributor.Distributor_OnlyStaking.selector));
        distributor.retrieveBounty();
    }

    function test_retrieveBountyIsZero() public {
        uint256 supplyBefore = ohm.totalSupply();

        vm.prank(address(staking));
        uint256 bounty = distributor.retrieveBounty();

        uint256 supplyAfter = ohm.totalSupply();

        assertEq(bounty, 0);
        assertEq(supplyAfter, supplyBefore);
    }

    /// [X] nextRewardFor()
    ///     [X]  Next reward for the staking contract matches the expected calculation
    function testCorrectness_nextRewardFor() public {
        uint256 stakingBalance = 100100 gwei;
        uint256 rewardRate = distributor.rewardRate();
        uint256 denominator = 1e9;
        uint256 expected = (stakingBalance * rewardRate) / denominator;

        assertEq(distributor.nextRewardFor(address(staking)), expected);
    }

    /* ========== POLICY FUNCTION TESTS ========== */

    /// [X]  setBounty()
    ///     [X]  Can only be called by an address with the distributor_admin role
    ///     [X]  Sets bounty correctly
    function testCorrectness_setBountyRequiresRole(address user_) public {
        vm.assume(user_ != address(this));

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("distributor_admin")
        );
        vm.expectRevert(err);

        vm.prank(user_);
        distributor.setBounty(0);
    }

    function testCorrectness_setBounty(uint256 newBounty_) public {
        distributor.setBounty(newBounty_);
        assertEq(distributor.bounty(), newBounty_);
    }

    /// [X] setPools()
    ///     [X]  Can only be called by an address with the distributor_admin role
    ///     [X]  Sets pools correctly
    function testCorrectness_setPoolsRequiresRole(address user_) public {
        vm.assume(user_ != address(this));

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("distributor_admin")
        );
        vm.expectRevert(err);

        address[] memory newPools = new address[](2);
        newPools[0] = address(staking);
        newPools[1] = address(gohm);

        vm.prank(user_);
        distributor.setPools(newPools);
    }

    function testCorrectness_setPools() public {
        address[] memory newPools = new address[](2);
        newPools[0] = address(staking);
        newPools[1] = address(gohm);

        distributor.setPools(newPools);
    }

    /// [X]  removePool()
    ///     [X]  Can only be called by an address with the distributor_admin role
    ///     [X]  Fails on sanity check when parameters are invalid
    ///     [X]  Correctly removes pool

    function testCorrectness_removePoolRequiresRole(address user_) public {
        vm.assume(user_ != address(this));

        /// Set up
        address[] memory newPools = new address[](2);
        newPools[0] = address(staking);
        newPools[1] = address(gohm);
        distributor.setPools(newPools);

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("distributor_admin")
        );
        vm.expectRevert(err);

        /// Remove Pool (should fail)
        vm.prank(user_);
        distributor.removePool(0, address(staking));
    }

    function testCorrectness_removePoolFailsOnSanityCheck() public {
        /// Set up
        address[] memory newPools = new address[](2);
        newPools[0] = address(staking);
        newPools[1] = address(gohm);
        distributor.setPools(newPools);

        /// Remove Pool (should fail)
        bytes memory err = abi.encodeWithSelector(Distributor.Distributor_SanityCheck.selector);
        vm.expectRevert(err);

        distributor.removePool(0, address(gohm));
    }

    function testCorrectness_removesPool() public {
        /// Set up
        address[] memory newPools = new address[](2);
        newPools[0] = address(staking);
        newPools[1] = address(gohm);
        distributor.setPools(newPools);

        /// Remove first pool
        distributor.removePool(0, address(staking));

        /// Verify state after first removal
        assertEq(distributor.pools(0), address(0x0));
        assertEq(distributor.pools(1), address(gohm));

        /// Remove second pool
        distributor.removePool(1, address(gohm));

        /// Verify end state
        assertEq(distributor.pools(0), address(0x0));
        assertEq(distributor.pools(1), address(0x0));
    }

    /// [X]  addPool()
    ///     [X]  Can only be called by an address with the distributor_admin role
    ///     [X]  Correctly adds pool to an empty slot
    ///     [X]  Pushes pool to end of list when trying to add to an occupied slot
    function testCorrectness_addPoolRequiresRole(address user_) public {
        vm.assume(user_ != address(this));

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("distributor_admin")
        );
        vm.expectRevert(err);

        vm.prank(user_);
        distributor.addPool(0, address(staking));
    }

    function testCorrectness_addPoolEmptySlot() public {
        /// Set up
        address[] memory newPools = new address[](2);
        newPools[0] = address(MINTR);
        newPools[1] = address(TRSRY);
        distributor.setPools(newPools);
        distributor.removePool(0, address(MINTR));
        distributor.removePool(1, address(TRSRY));

        distributor.addPool(0, address(staking));
        assertEq(distributor.pools(0), address(staking));
    }

    function testCorrectness_addPoolOccupiedSlot() public {
        /// Set up
        address[] memory newPools = new address[](2);
        newPools[0] = address(MINTR);
        newPools[1] = address(TRSRY);
        distributor.setPools(newPools);
        distributor.removePool(0, address(MINTR));
        distributor.removePool(1, address(TRSRY));
        distributor.addPool(0, address(staking));

        distributor.addPool(0, address(gohm));
        assertEq(distributor.pools(2), address(gohm));
    }

    /// [X]  setRewardRate
    ///     [X]  Can only be called by an address with the distributor_admin role
    ///     [X]  Correctly sets reward rate

    function testCorrectness_setRewardRateRequiresRole(address user_) public {
        vm.assume(user_ != address(this));

        bytes memory err = abi.encodeWithSelector(
            ROLESv1.ROLES_RequireRole.selector,
            bytes32("distributor_admin")
        );
        vm.expectRevert(err);

        vm.prank(user_);
        distributor.setRewardRate(0);
    }

    function testCorrectness_setsRewardRate(uint256 amount_) public {
        distributor.setRewardRate(amount_);
        assertEq(distributor.rewardRate(), amount_);
    }

    /* ========== USER STORY TESTS ========== */

    /// User Story 1: triggerRebase() fails when block timestamp is before epoch end
    function test_triggerRebaseStory1() public {
        (, , uint256 end, ) = staking.epoch();
        assertGt(end, block.timestamp);

        uint256 balanceBefore = ohm.balanceOf(address(staking));
        bytes memory err = abi.encodeWithSelector(
            IDistributor.Distributor_NoRebaseOccurred.selector
        );
        vm.expectRevert(err);

        distributor.triggerRebase();
        uint256 balanceAfter = ohm.balanceOf(address(staking));
        assertEq(balanceBefore, balanceAfter);
    }

    /// User Story 2: triggerRebase() mints OHM to the staking contract when epoch is over
    function test_triggerRebaseStory2() public {
        /// Set up
        vm.warp(2200);
        (, , uint256 end, ) = staking.epoch();
        assertLe(end, block.timestamp);

        uint256 balanceBefore = ohm.balanceOf(address(staking));
        distributor.triggerRebase();
        uint256 balanceAfter = ohm.balanceOf(address(staking));

        uint256 expected = (balanceBefore * 1000) / 1_000_000;
        assertEq(balanceAfter - balanceBefore, expected);
    }

    /// User Story 3: triggerRebase() reverts when attempted to call twice in same epoch
    function test_triggerRebaseStory3() public {
        /// Set up
        vm.warp(2200);
        distributor.triggerRebase();

        /// Move forward a little bit
        vm.warp(2500);
        bytes memory err = abi.encodeWithSelector(
            IDistributor.Distributor_NoRebaseOccurred.selector
        );
        vm.expectRevert(err);

        distributor.triggerRebase();
    }

    /// User Story 4: triggerRebase() mints OHM to the staking contract and a single Uniswap V2 pool
    function test_triggerRebaseStory4() public {
        /// Set up
        address[] memory newPools = new address[](1);
        newPools[0] = address(ohmDai);
        distributor.setPools(newPools);
        vm.warp(2200);

        (uint256 reserve0, uint256 reserve1, ) = ohmDai.getReserves();
        uint256 priceBefore = reserve1 / (reserve0 * 1000000000);
        uint256 balanceBefore = ohm.balanceOf(address(ohmDai));
        uint256 expectedBalanceAfter = balanceBefore + (balanceBefore * 1000) / 1_000_000;

        distributor.triggerRebase();

        (uint256 reserve0After, uint256 reserve1After, ) = ohmDai.getReserves();
        uint256 priceAfter = reserve1After / (reserve0After * 1000000000);
        uint256 balanceAfter = ohm.balanceOf(address(ohmDai));

        assertGt(balanceAfter, balanceBefore);
        assertEq(balanceAfter, expectedBalanceAfter);
        assertGt(priceBefore, priceAfter);
    }

    /// User Story 5: triggerRebase() mints OHM to the staking contract and multiple Uniswap V2 pools
    function test_triggerRebaseStory5() public {
        /// Set up
        address[] memory newPools = new address[](3);
        newPools[0] = address(ohmDai);
        newPools[1] = address(ohmWeth);
        distributor.setPools(newPools);
        vm.warp(2200);

        (uint256 ohmDaiReserve0, uint256 ohmDaiReserve1, ) = ohmDai.getReserves();
        uint256 ohmDaiPriceBefore = ohmDaiReserve1 / (ohmDaiReserve0 * 1000000000);
        uint256 ohmDaiBalanceBefore = ohm.balanceOf(address(ohmDai));
        uint256 expectedOhmDaiBalanceAfter = ohmDaiBalanceBefore +
            (ohmDaiBalanceBefore * 1000) /
            1_000_000;

        (uint256 ohmWethReserve0, uint256 ohmWethReserve1, ) = ohmWeth.getReserves();
        uint256 ohmWethPriceBefore = ohmWethReserve1 / (ohmWethReserve0 * 1000000000);
        uint256 ohmWethBalanceBefore = ohm.balanceOf(address(ohmWeth));
        uint256 expectedOhmWethBalanceAfter = ohmWethBalanceBefore +
            (ohmWethBalanceBefore * 1000) /
            1_000_000;

        distributor.triggerRebase();

        (ohmDaiReserve0, ohmDaiReserve1, ) = ohmDai.getReserves();
        uint256 ohmDaiPriceAfter = ohmDaiReserve1 / (ohmDaiReserve0 * 1000000000);
        uint256 ohmDaiBalanceAfter = ohm.balanceOf(address(ohmDai));

        (ohmWethReserve0, ohmWethReserve1, ) = ohmWeth.getReserves();
        uint256 ohmWethPriceAfter = ohmWethReserve1 / (ohmWethReserve0 * 1000000000);
        uint256 ohmWethBalanceAfter = ohm.balanceOf(address(ohmWeth));

        assertGt(ohmDaiBalanceAfter, ohmDaiBalanceBefore);
        assertEq(ohmDaiBalanceAfter, expectedOhmDaiBalanceAfter);
        assertGt(ohmDaiPriceBefore, ohmDaiPriceAfter);

        assertGt(ohmWethBalanceAfter, ohmWethBalanceBefore);
        assertEq(ohmWethBalanceAfter, expectedOhmWethBalanceAfter);
        assertGt(ohmWethPriceBefore, ohmWethPriceAfter);
    }
}
