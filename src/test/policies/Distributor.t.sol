// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

/// External Dependencies
import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test/lib/UserFactory.sol";

/// Import Distributor
import {Distributor} from "policies/Distributor.sol";
import "src/Kernel.sol";
import {GoerliMinter} from "modules/MINTR/GoerliMinter.sol";
import {GoerliDaoTreasury} from "modules/TRSRY/GoerliDaoTreasury.sol";
import {GoerliDaoRoles} from "modules/ROLES/GoerliDaoRoles.sol";
import {ROLESv1} from "modules/ROLES/ROLES.v1.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";

/// Import Mocks for non-Bophades contracts
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockXgdao, MockStaking} from "../mocks/GoerliMocks.sol";
import {MockUniV2Pair} from "../mocks/MockUniV2Pair.sol";
import {MockLegacyAuthority} from "../modules/MINTR.t.sol";

contract DistributorTest is Test {
    /// Bophades Systems
    Kernel internal kernel;
    GoerliMinter internal mintr;
    GoerliDaoTreasury internal trsry;
    GoerliDaoRoles internal roles;

    Distributor internal distributor;
    RolesAdmin internal rolesAdmin;

    /// Tokens
    MockERC20 internal gdao;
    MockERC20 internal sgdao;
    MockXgdao internal xgdao;
    MockERC20 internal dai;
    MockERC20 internal weth;

    /// Legacy Contracts
    MockStaking internal staking;

    /// External Contracts
    MockUniV2Pair internal gdaoDai;
    MockUniV2Pair internal gdaoWeth;

    function setUp() public {
        {
            /// Deploy Kernal and tokens
            kernel = new Kernel();
            gdao = new MockERC20("GDAO", "GDAO", 9);
            sgdao = new MockERC20("sGDAO", "sGDAO", 9);
            xgdao = new MockXgdao(100_000_000_000);
            dai = new MockERC20("DAI", "DAI", 18);
            weth = new MockERC20("WETH", "WETH", 18);
        }

        {
            /// Deploy UniV2 Pools
            gdaoDai = new MockUniV2Pair(address(gdao), address(dai));
            gdaoWeth = new MockUniV2Pair(address(gdao), address(weth));
        }

        {
            /// Deploy Bophades Modules
            mintr = new GoerliMinter(kernel, address(gdao));
            trsry = new GoerliDaoTreasury(kernel);
            roles = new GoerliDaoRoles(kernel);
        }

        {
            /// Initialize Modules
            kernel.executeAction(Actions.InstallModule, address(mintr));
            kernel.executeAction(Actions.InstallModule, address(trsry));
            kernel.executeAction(Actions.InstallModule, address(roles));
        }

        {
            /// Deploy Staking, Distributor, and Roles Admin
            staking = new MockStaking(address(gdao), address(sgdao), address(xgdao), 2200, 0, 2200);
            distributor = new Distributor(kernel, address(gdao), address(staking), 1000000); // 0.1%
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
            mintr.increaseMintApproval(address(distributor), type(uint256).max);

            /// Mint GDAO to deployer and staking contract
            mintr.mintGdao(address(staking), 100000 gwei);
            mintr.mintGdao(address(this), 100000 gwei);

            /// Mint DAI and GDAO to GDAO-DAI pool
            mintr.mintGdao(address(gdaoDai), 100000 gwei);
            dai.mint(address(gdaoDai), 100000 * 10**18);
            gdaoDai.sync();

            /// Mint WETH and GDAO to GDAO-WETH pool
            mintr.mintGdao(address(gdaoWeth), 100000 gwei);
            weth.mint(address(gdaoWeth), 100000 * 10**18);
            gdaoWeth.sync();
            vm.stopPrank();

            /// Stake deployer's GDAO
            gdao.approve(address(staking), type(uint256).max);
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

        assertEq(gdao.balanceOf(address(staking)), 100100 gwei);
    }

    /* ========== BASIC TESTS ========== */

    /// [X]  distribute()
    ///     [X]  Can only be called by staking
    ///     [X]  Cannot be called if not unlocked
    function testCorrectness_distributeOnlyStaking() public {
        bytes memory err = abi.encodeWithSelector(Distributor.Distributor_OnlyStaking.selector);
        vm.expectRevert(err);
        distributor.distribute();
    }

    function testCorrectness_distributeNotUnlocked() public {
        bytes memory err = abi.encodeWithSelector(Distributor.Distributor_NotUnlocked.selector);
        vm.expectRevert(err);

        vm.prank(address(staking));
        distributor.distribute();
    }

    /// [X]  retrieveBounty()
    ///     [X]  Can only be called by staking
    ///     [X]  Bounty is zero and no GDAO is minted
    function test_retrieveBountyOnlyStaking() public {
        vm.expectRevert(abi.encodeWithSelector(Distributor.Distributor_OnlyStaking.selector));
        distributor.retrieveBounty();
    }

    function test_retrieveBountyIsZero() public {
        uint256 supplyBefore = gdao.totalSupply();

        vm.prank(address(staking));
        uint256 bounty = distributor.retrieveBounty();

        uint256 supplyAfter = gdao.totalSupply();

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
        newPools[1] = address(xgdao);

        vm.prank(user_);
        distributor.setPools(newPools);
    }

    function testCorrectness_setPools() public {
        address[] memory newPools = new address[](2);
        newPools[0] = address(staking);
        newPools[1] = address(xgdao);

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
        newPools[1] = address(xgdao);
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
        newPools[1] = address(xgdao);
        distributor.setPools(newPools);

        /// Remove Pool (should fail)
        bytes memory err = abi.encodeWithSelector(Distributor.Distributor_SanityCheck.selector);
        vm.expectRevert(err);

        distributor.removePool(0, address(xgdao));
    }

    function testCorrectness_removesPool() public {
        /// Set up
        address[] memory newPools = new address[](2);
        newPools[0] = address(staking);
        newPools[1] = address(xgdao);
        distributor.setPools(newPools);

        /// Remove first pool
        distributor.removePool(0, address(staking));

        /// Verify state after first removal
        assertEq(distributor.pools(0), address(0x0));
        assertEq(distributor.pools(1), address(xgdao));

        /// Remove second pool
        distributor.removePool(1, address(xgdao));

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
        newPools[0] = address(mintr);
        newPools[1] = address(trsry);
        distributor.setPools(newPools);
        distributor.removePool(0, address(mintr));
        distributor.removePool(1, address(trsry));

        distributor.addPool(0, address(staking));
        assertEq(distributor.pools(0), address(staking));
    }

    function testCorrectness_addPoolOccupiedSlot() public {
        /// Set up
        address[] memory newPools = new address[](2);
        newPools[0] = address(mintr);
        newPools[1] = address(trsry);
        distributor.setPools(newPools);
        distributor.removePool(0, address(mintr));
        distributor.removePool(1, address(trsry));
        distributor.addPool(0, address(staking));

        distributor.addPool(0, address(xgdao));
        assertEq(distributor.pools(2), address(xgdao));
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

        uint256 balanceBefore = gdao.balanceOf(address(staking));
        bytes memory err = abi.encodeWithSelector(
            Distributor.Distributor_NoRebaseOccurred.selector
        );
        vm.expectRevert(err);

        distributor.triggerRebase();
        uint256 balanceAfter = gdao.balanceOf(address(staking));
        assertEq(balanceBefore, balanceAfter);
    }

    /// User Story 2: triggerRebase() mints GDAO to the staking contract when epoch is over
    function test_triggerRebaseStory2() public {
        /// Set up
        vm.warp(2200);
        (, , uint256 end, ) = staking.epoch();
        assertLe(end, block.timestamp);

        uint256 balanceBefore = gdao.balanceOf(address(staking));
        distributor.triggerRebase();
        uint256 balanceAfter = gdao.balanceOf(address(staking));

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
            Distributor.Distributor_NoRebaseOccurred.selector
        );
        vm.expectRevert(err);

        distributor.triggerRebase();
    }

    /// User Story 4: triggerRebase() mints GDAO to the staking contract and a single Uniswap V2 pool
    function test_triggerRebaseStory4() public {
        /// Set up
        address[] memory newPools = new address[](1);
        newPools[0] = address(gdaoDai);
        distributor.setPools(newPools);
        vm.warp(2200);

        (uint256 reserve0, uint256 reserve1, ) = gdaoDai.getReserves();
        uint256 priceBefore = reserve1 / (reserve0 * 1000000000);
        uint256 balanceBefore = gdao.balanceOf(address(gdaoDai));
        uint256 expectedBalanceAfter = balanceBefore + (balanceBefore * 1000) / 1_000_000;

        distributor.triggerRebase();

        (uint256 reserve0After, uint256 reserve1After, ) = gdaoDai.getReserves();
        uint256 priceAfter = reserve1After / (reserve0After * 1000000000);
        uint256 balanceAfter = gdao.balanceOf(address(gdaoDai));

        assertGt(balanceAfter, balanceBefore);
        assertEq(balanceAfter, expectedBalanceAfter);
        assertGt(priceBefore, priceAfter);
    }

    /// User Story 5: triggerRebase() mints GDAO to the staking contract and multiple Uniswap V2 pools
    function test_triggerRebaseStory5() public {
        /// Set up
        address[] memory newPools = new address[](3);
        newPools[0] = address(gdaoDai);
        newPools[1] = address(gdaoWeth);
        distributor.setPools(newPools);
        vm.warp(2200);

        (uint256 gdaoDaiReserve0, uint256 gdaoDaiReserve1, ) = gdaoDai.getReserves();
        uint256 gdaoDaiPriceBefore = gdaoDaiReserve1 / (gdaoDaiReserve0 * 1000000000);
        uint256 gdaoDaiBalanceBefore = gdao.balanceOf(address(gdaoDai));
        uint256 expectedGdaoDaiBalanceAfter = gdaoDaiBalanceBefore +
            (gdaoDaiBalanceBefore * 1000) /
            1_000_000;

        (uint256 gdaoWethReserve0, uint256 gdaoWethReserve1, ) = gdaoWeth.getReserves();
        uint256 gdaoWethPriceBefore = gdaoWethReserve1 / (gdaoWethReserve0 * 1000000000);
        uint256 gdaoWethBalanceBefore = gdao.balanceOf(address(gdaoWeth));
        uint256 expectedGdaoWethBalanceAfter = gdaoWethBalanceBefore +
            (gdaoWethBalanceBefore * 1000) /
            1_000_000;

        distributor.triggerRebase();

        (gdaoDaiReserve0, gdaoDaiReserve1, ) = gdaoDai.getReserves();
        uint256 gdaoDaiPriceAfter = gdaoDaiReserve1 / (gdaoDaiReserve0 * 1000000000);
        uint256 gdaoDaiBalanceAfter = gdao.balanceOf(address(gdaoDai));

        (gdaoWethReserve0, gdaoWethReserve1, ) = gdaoWeth.getReserves();
        uint256 gdaoWethPriceAfter = gdaoWethReserve1 / (gdaoWethReserve0 * 1000000000);
        uint256 gdaoWethBalanceAfter = gdao.balanceOf(address(gdaoWeth));

        assertGt(gdaoDaiBalanceAfter, gdaoDaiBalanceBefore);
        assertEq(gdaoDaiBalanceAfter, expectedGdaoDaiBalanceAfter);
        assertGt(gdaoDaiPriceBefore, gdaoDaiPriceAfter);

        assertGt(gdaoWethBalanceAfter, gdaoWethBalanceBefore);
        assertEq(gdaoWethBalanceAfter, expectedGdaoWethBalanceAfter);
        assertGt(gdaoWethPriceBefore, gdaoWethPriceAfter);
    }
}
