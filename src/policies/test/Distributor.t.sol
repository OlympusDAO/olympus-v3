// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

/// External Dependencies
import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "test-utils/UserFactory.sol";
import "test-utils/larping.sol";
import "test-utils/convert.sol";
import "test-utils/errors.sol";

/// Import Distributor
import "src/policies/Distributor.sol";
import "src/Kernel.sol";
import "src/modules/AUTHR.sol";

/// Import Larps for non-Bophades contracts
import "./larps/LarpStaking.sol";
import "./larps/LarpOHM.sol";
import "./larps/LarpSOHM.sol";
import "./larps/LarpGOHM.sol";
import {OlympusERC20Token as OHM, IOlympusAuthority} from "src/external/OlympusERC20.sol";
import {MockLegacyAuthority} from "src/modules/test/MINTR.t.sol";

contract DistributorTest is Test {
    using larping for *;
    using convert for *;
    using errors for *;

    /// Bophades Systems
    Kernel internal kernel;
    OlympusMinter internal mintr;
    OlympusTreasury internal trsry;
    AUTHR internal authr;
    Distributor internal distributor;

    /// Tokens
    OHM internal ohm;
    LarpSOHM internal sohm;
    LarpGOHM internal gohm;

    /// Legacy Contracts
    LarpStaking internal larpStaking;
    IOlympusAuthority internal auth;

    function setUp() public {
        {
            /// Deploy Kernal and tokens
            kernel = new Kernel();
            auth = new MockLegacyAuthority(address(0x0));
            ohm = new OHM(address(auth));
            sohm = new LarpSOHM();
            gohm = new LarpGOHM(address(this), address(sohm));
        }

        {
            /// Deploy Bophades Modules
            mintr = new OlympusMinter(kernel, ohm);
            trsry = new OlympusTreasury(kernel);
            authr = new AUTHR(address(kernel));
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
            larpStaking = new LarpStaking(
                address(ohm),
                address(sohm),
                address(gohm),
                0,
                0,
                0,
                address(this)
            );

            distributor = new Distributor(
                address(kernel),
                address(ohm),
                address(larpStaking),
                1000
            );
        }

        {
            /// Initialize Distributor Policy
            kernel.executeAction(Actions.ApprovePolicy, address(distributor));
        }

        {
            /// Mint OHM to Staking Contract
            vm.prank(address(distributor));
            mintr.mintOhm(address(larpStaking), 100000 gwei);
        }
    }

    /// Basic post-setup functionality tests
    function test_hasWriteAccess() public {
        bool writeAccess = kernel.getWritePermissions(
            "MINTR",
            address(distributor)
        );
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

        assertEq(ohm.balanceOf(address(larpStaking)), 100000 gwei);
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
        vm.prank(address(larpStaking));
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

        vm.prank(address(larpStaking));
        uint256 bounty = distributor.retrieveBounty();

        uint256 supplyAfter = ohm.totalSupply();

        assertEq(bounty, 0);
        assertEq(supplyAfter, supplyBefore);
    }

    function test_nextRewardFor() public {
        uint256 larpStakingBalance = 100000 gwei;
        uint256 rewardRate = distributor.rewardRate();
        uint256 denominator = 1_000_000;
        uint256 expected = (larpStakingBalance * rewardRate) / denominator;

        assertEq(distributor.nextRewardFor(address(larpStaking)), expected);
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
        newPools[0] = address(larpStaking);
        newPools[1] = address(gohm);
        distributor.setPools(newPools);
    }

    function test_setPools() public {
        address[] memory newPools = new address[](2);
        newPools[0] = address(larpStaking);
        newPools[1] = address(gohm);
        vm.prank(address(kernel));
        distributor.setPools(newPools);
    }

    function testFail_removePoolRequiresAuth() public {
        /// Set up
        address[] memory newPools = new address[](2);
        newPools[0] = address(larpStaking);
        newPools[1] = address(gohm);
        vm.prank(address(kernel));
        distributor.setPools(newPools);

        /// Remove Pool (should fail)
        distributor.removePool(0, address(larpStaking));
    }

    function test_removePoolSanityCheck() public {
        /// Set up
        address[] memory newPools = new address[](2);
        newPools[0] = address(larpStaking);
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
        newPools[0] = address(larpStaking);
        newPools[1] = address(gohm);
        vm.startPrank(address(kernel));
        distributor.setPools(newPools);

        /// Remove first pool
        distributor.removePool(0, address(larpStaking));
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
        distributor.addPool(0, address(larpStaking));
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

        distributor.addPool(0, address(larpStaking));
        assertEq(distributor.pools(0), address(larpStaking));
    }

    function test_addPoolOccupiedSlot() public {
        vm.startPrank(address(kernel));
        address[] memory newPools = new address[](2);
        newPools[0] = address(mintr);
        newPools[1] = address(trsry);
        distributor.setPools(newPools);
        distributor.removePool(0, address(mintr));
        distributor.removePool(1, address(trsry));
        distributor.addPool(0, address(larpStaking));

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
}
