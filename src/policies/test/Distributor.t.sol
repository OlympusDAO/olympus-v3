/*
// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

/// External Dependencies
import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "solmate/tokens/ERC20.sol";
import "test-utils/UserFactory.sol";
import "test-utils/larping.sol";
import "test-utils/convert.sol";
import "test-utils/errors.sol";

/// Import Distributor
import "src/policies/Distributor.sol";
import "src/Kernel.sol";

/// Import Larps for non-Bophades contracts
import "./larps/LarpStaking.sol";
import "./larps/LarpSOHM.sol";
import "./larps/LarpGOHM.sol";
import "./larps/interfaces/IgOHM.sol";
import "./larps/interfaces/IsOHM.sol";

contract DistributorTest is Test {
    using larping for *;
    using convert for *;
    using errors for *;

    ERC20 internal ohm;
    IsOHM internal sohm;
    IgOHM internal gohm;

    Kernel internal kernel;
    LarpStaking internal larpStaking;
    OlympusMinter internal MINTR;
    OlympusTreasury internal TRSRY;
    Distributor internal distributor;

    function setUp() public {
        kernel = new Kernel();

        ohm = ERC20(
            deployCode("MockERC20.t.sol:MockERC20", abi.encode("ohm", "OHM", 9))
        );

        sohm = new LarpSOHM();
        gohm = new LarpGOHM(address(this), address(sohm));

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

        ohm.mint(address(larpStaking), 100000 gwei);
    }

    function test_defaultState() public {
        assertEq(distributor.pools.length, 0);
        assertEq(distributor.rewardRate, 1000);
        assertEq(distributor.bounty, 0);
        assertEq(distributor.unlockRebase, false);
    }

    function test_setPoolsFuzzed(address[] pools_) public {
        assertEq(distributor.pools.length, 0);
        distributor.setPools(pools_);
        assertEq(distributor.pools, pools_);
    }

    function test_removePool() public {
        assertEq(distributor.pools.length, 0);

        distributor.setPools(
            [address(larpStaking), address(sohm), address(gohm), address(this)]
        );
        assertEq(distributor.pools.length, 4);

        distributor.removePool(0, address(larpStaking));
        assertEq(distributor.pools.length, 4);
        assertEq(distributor.pools[0], address(0));
        assertEq(distributor.pools[1], address(sohm));
        assertEq(distributor.pools[2], address(gohm));
        assertEq(distributor.pools[3], address(this));

        distributor.removePool(1, address(sohm));
        assertEq(distributor.pools.length, 4);
        assertEq(distributor.pools[0], address(0));
        assertEq(distributor.pools[1], address(0));
        assertEq(distributor.pools[2], address(gohm));
        assertEq(distributor.pools[3], address(this));
    }

    function test_addPool() public {
        assertEq(distributor.pools.length, 0);

        /// Test adding to an empty slot
        distributor.addPool(0, address(this));
        assertEq(distributor.pools.length, 1);
        assertEq(distributor.pools[0], address(this));

        /// Test adding to an occupied slot
        distributor.addPool(0, address(sohm));
        assertEq(distributor.pools.length, 2);
        assertEq(distributor.pools[1], address(sohm));
    }
}
*/
