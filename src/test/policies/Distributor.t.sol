// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

/// External Dependencies
import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {UserFactory} from "test-utils/UserFactory.sol";

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

/// Import Distributor
import "src/policies/Distributor.sol";
import "src/Kernel.sol";
import {OlympusMinter} from "src/modules/MINTR.sol";
import {OlympusTreasury} from "src/modules/TRSRY.sol";

/// Import Mocks for non-Bophades contracts
import {MockStaking} from "../mocks/MockStaking.sol";
import {MockGOHM} from "../mocks/MockGOHM.sol";
import {MockSOHM} from "../mocks/MockSOHM.sol";
import {MockUniV2Pair} from "../mocks/MockUniV2Pair.sol";
import {OlympusERC20Token as OHM, IOlympusAuthority} from "src/external/OlympusERC20.sol";
import {MockLegacyAuthority} from "../modules/MINTR.t.sol";

contract DistributorTest is Test {
    using larping for *;
    using convert for *;
    using errors for *;

    /// Bophades Systems
    Kernel internal kernel;
    OlympusMinter internal mintr;
    OlympusTreasury internal trsry;
    Distributor internal distributor;

    /// Tokens
    OHM internal ohm;
    MockSOHM internal sohm;
    MockGOHM internal gohm;
    MockERC20 internal dai;
    MockERC20 internal weth;

    /// Legacy Contracts
    MockStaking internal staking;
    IOlympusAuthority internal auth;

    /// External Contracts
    MockUniV2Pair internal ohmDai;
    MockUniV2Pair internal ohmWeth;

    function setUp() public {
        {
            /// Deploy Kernal and tokens
            kernel = new Kernel();
            auth = new MockLegacyAuthority(address(0x0));
            ohm = new OHM(address(auth));
            sohm = new MockSOHM();
            gohm = new MockGOHM(address(this), address(sohm));
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
            mintr = new OlympusMinter(kernel, address(ohm));
            trsry = new OlympusTreasury(kernel);
            authr = new OlympusAuthority(kernel);
        }

        {
            /// Initialize Modules
            kernel.executeAction(Actions.InstallModule, address(mintr));
            kernel.executeAction(Actions.InstallModule, address(trsry));
            kernel.executeAction(Actions.InstallModule, address(authr));

            auth.vault.larp(address(mintr));
        }

        {
            /// Deploy Staking and Distributor
            staking = new MockStaking(
                address(ohm),
                address(sohm),
                address(gohm),
                2200,
                0,
                2200
            );

            distributor = new Distributor(
                address(kernel),
                address(ohm),
                address(staking),
                1000
            );

            staking.setDistributor(address(distributor));

            sohm.setgOHM(address(gohm));
            sohm.initialize(address(staking), address(trsry));
            sohm.setIndex(10 gwei);

            gohm.approved.larp(address(staking));
        }

        {
            /// Initialize Distributor Policy
            kernel.executeAction(Actions.ApprovePolicy, address(distributor));
        }

        {
            /// Mint Tokens
            vm.startPrank(address(distributor));
            /// Mint OHM to deployer and staking contract
            mintr.mintOhm(address(staking), 100000 gwei);
            mintr.mintOhm(address(this), 100000 gwei);

            /// Mint DAI and OHM to OHM-DAI pool
            mintr.mintOhm(address(ohmDai), 100000 gwei);
            dai.mint(address(ohmDai), 100000 * 10**18);
            ohmDai.sync();

            /// Mint WETH and OHM to OHM-WETH pool
            mintr.mintOhm(address(ohmWeth), 100000 gwei);
            weth.mint(address(ohmWeth), 100000 * 10**18);
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
    function test_hasWriteAccess() public {
        Kernel.Role role = mintr.MINTER();
        bool writeAccess = kernel.hasRole(address(distributor), role);
        assertEq(writeAccess, true);
    }

    function test_defaultState() public {
        assertEq(address(distributor.authority()), address(authr));
        assertEq(distributor.rewardRate(), 1000);
        assertEq(distributor.bounty(), 0);

        (bool add, uint256 rate, uint256 target) = distributor.adjustment();
        assertEq(add, false);
        assertEq(rate, 0);
        assertEq(target, 0);

        assertEq(ohm.balanceOf(address(staking)), 100100 gwei);
    }

    /////////////////////////////////////////////////////////////////////////////////
    ///                       Single Function Interactions                        ///
    /////////////////////////////////////////////////////////////////////////////////

    /// distribute() tests
    function test_distributeOnlyStaking() public {
        vm.expectRevert(
            abi.encodeWithSelector(Distributor_OnlyStaking.selector)
        );
        distributor.distribute();
    }

    function test_distributeNotUnlocked() public {
        vm.expectRevert(
            abi.encodeWithSelector(Distributor_NotUnlocked.selector)
        );
        vm.prank(address(staking));
        distributor.distribute();
    }

    /// retrieveBounty() tests
    function test_retrieveBountyOnlyStaking() public {
        vm.expectRevert(
            abi.encodeWithSelector(Distributor_OnlyStaking.selector)
        );
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

    function test_nextRewardFor() public {
        uint256 stakingBalance = 100100 gwei;
        uint256 rewardRate = distributor.rewardRate();
        uint256 denominator = 1_000_000;
        uint256 expected = (stakingBalance * rewardRate) / denominator;

        assertEq(distributor.nextRewardFor(address(staking)), expected);
    }

    /// setBounty() tests
    function testFail_setBountyRequiresAuth() public {
        distributor.setBounty(0);
    }

    function test_setBounty() public {
        vm.prank(address(kernel));
        distributor.setBounty(10);
        assertEq(distributor.bounty(), 10);
    }

    /// setPools() tests
    function testFail_setPoolsRequiresAuth() public {
        address[] memory newPools = new address[](2);
        newPools[0] = address(staking);
        newPools[1] = address(gohm);
        distributor.setPools(newPools);
    }

    function test_setPools() public {
        address[] memory newPools = new address[](2);
        newPools[0] = address(staking);
        newPools[1] = address(gohm);
        vm.prank(address(kernel));
        distributor.setPools(newPools);
    }

    function testFail_removePoolRequiresAuth() public {
        /// Set up
        address[] memory newPools = new address[](2);
        newPools[0] = address(staking);
        newPools[1] = address(gohm);
        vm.prank(address(kernel));
        distributor.setPools(newPools);

        /// Remove Pool (should fail)
        distributor.removePool(0, address(staking));
    }

    function test_removePoolSanityCheck() public {
        /// Set up
        address[] memory newPools = new address[](2);
        newPools[0] = address(staking);
        newPools[1] = address(gohm);
        vm.startPrank(address(kernel));
        distributor.setPools(newPools);

        /// Remove Pool (should fail)
        vm.expectRevert(
            abi.encodeWithSelector(Distributor_SanityCheck.selector)
        );
        distributor.removePool(0, address(gohm));
        vm.stopPrank();
    }

    function test_removePool() public {
        /// Set up
        address[] memory newPools = new address[](2);
        newPools[0] = address(staking);
        newPools[1] = address(gohm);
        vm.startPrank(address(kernel));
        distributor.setPools(newPools);

        /// Remove first pool
        distributor.removePool(0, address(staking));
        assertEq(distributor.pools(0), address(0x0));
        assertEq(distributor.pools(1), address(gohm));

        /// Remove second pool
        distributor.removePool(1, address(gohm));
        assertEq(distributor.pools(0), address(0x0));
        assertEq(distributor.pools(1), address(0x0));
        vm.stopPrank();
    }

    /// addPool() tests
    function testFail_addPoolRequiresAuth() public {
        distributor.addPool(0, address(staking));
    }

    function test_addPoolEmptySlot() public {
        vm.startPrank(address(kernel));
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

    function test_addPoolOccupiedSlot() public {
        vm.startPrank(address(kernel));
        address[] memory newPools = new address[](2);
        newPools[0] = address(mintr);
        newPools[1] = address(trsry);
        distributor.setPools(newPools);
        distributor.removePool(0, address(mintr));
        distributor.removePool(1, address(trsry));
        distributor.addPool(0, address(staking));

        distributor.addPool(0, address(gohm));
        assertEq(distributor.pools(2), address(gohm));
        vm.stopPrank();
    }

    /// setAdjustment() tests
    function testFail_setAdjustmentRequiresAuth() public {
        distributor.setAdjustment(false, 1100, 1100);
    }

    function test_setAdjustmentAdjustmentLimit() public {
        vm.expectRevert(
            abi.encodeWithSelector(Distributor_AdjustmentLimit.selector)
        );
        vm.prank(address(kernel));
        distributor.setAdjustment(true, 50, 1050);
    }

    /* What conditions cause this in reality?
    function test_setAdjustmentAdjustmentUnderflow() public {
        vm.expectRevert(
            abi.encodeWithSelector(Distributor_AdjustmentUnderflow.selector)
        );
        vm.prank(address(kernel));
        distributor.setAdjustment(false, 2000, 2000);
    }
    */

    function test_setAdjustment() public {
        vm.prank(address(kernel));
        distributor.setAdjustment(true, 20, 1500);

        (bool add, uint256 rate, uint256 target) = distributor.adjustment();

        assertEq(add, true);
        assertEq(rate, 20);
        assertEq(target, 1500);
    }

    /////////////////////////////////////////////////////////////////////////////////
    ///                          User Story Interactions                          ///
    /////////////////////////////////////////////////////////////////////////////////

    /// User Story 1: triggerRebase() fails when block timestamp is before epoch end
    function test_triggerRebaseStory1() public {
        (, , uint256 end, ) = staking.epoch();
        assertGt(end, block.timestamp);

        uint256 balanceBefore = ohm.balanceOf(address(staking));
        vm.expectRevert(
            abi.encodeWithSelector(Distributor_NoRebaseOccurred.selector)
        );
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
        vm.expectRevert(
            abi.encodeWithSelector(Distributor_NoRebaseOccurred.selector)
        );
        distributor.triggerRebase();
    }

    /// User Story 4: triggerRebase() mints OHM to the staking contract and a single Uniswap V2 pool
    function test_triggerRebaseStory4() public {
        /// Set up
        address[] memory newPools = new address[](1);
        newPools[0] = address(ohmDai);
        vm.prank(address(kernel));
        distributor.setPools(newPools);
        vm.warp(2200);

        (uint256 reserve0, uint256 reserve1, ) = ohmDai.getReserves();
        uint256 priceBefore = reserve1 / (reserve0 * 1000000000);
        uint256 balanceBefore = ohm.balanceOf(address(ohmDai));
        uint256 expectedBalanceAfter = balanceBefore +
            (balanceBefore * 1000) /
            1_000_000;

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
        vm.prank(address(kernel));
        distributor.setPools(newPools);
        vm.warp(2200);

        (uint256 ohmDaiReserve0, uint256 ohmDaiReserve1, ) = ohmDai
            .getReserves();
        uint256 ohmDaiPriceBefore = ohmDaiReserve1 /
            (ohmDaiReserve0 * 1000000000);
        uint256 ohmDaiBalanceBefore = ohm.balanceOf(address(ohmDai));
        uint256 expectedOhmDaiBalanceAfter = ohmDaiBalanceBefore +
            (ohmDaiBalanceBefore * 1000) /
            1_000_000;

        (uint256 ohmWethReserve0, uint256 ohmWethReserve1, ) = ohmWeth
            .getReserves();
        uint256 ohmWethPriceBefore = ohmWethReserve1 /
            (ohmWethReserve0 * 1000000000);
        uint256 ohmWethBalanceBefore = ohm.balanceOf(address(ohmWeth));
        uint256 expectedOhmWethBalanceAfter = ohmWethBalanceBefore +
            (ohmWethBalanceBefore * 1000) /
            1_000_000;

        distributor.triggerRebase();

        (ohmDaiReserve0, ohmDaiReserve1, ) = ohmDai.getReserves();
        uint256 ohmDaiPriceAfter = ohmDaiReserve1 /
            (ohmDaiReserve0 * 1000000000);
        uint256 ohmDaiBalanceAfter = ohm.balanceOf(address(ohmDai));

        (ohmWethReserve0, ohmWethReserve1, ) = ohmWeth.getReserves();
        uint256 ohmWethPriceAfter = ohmWethReserve1 /
            (ohmWethReserve0 * 1000000000);
        uint256 ohmWethBalanceAfter = ohm.balanceOf(address(ohmWeth));

        assertGt(ohmDaiBalanceAfter, ohmDaiBalanceBefore);
        assertEq(ohmDaiBalanceAfter, expectedOhmDaiBalanceAfter);
        assertGt(ohmDaiPriceBefore, ohmDaiPriceAfter);

        assertGt(ohmWethBalanceAfter, ohmWethBalanceBefore);
        assertEq(ohmWethBalanceAfter, expectedOhmWethBalanceAfter);
        assertGt(ohmWethPriceBefore, ohmWethPriceAfter);
    }
}
