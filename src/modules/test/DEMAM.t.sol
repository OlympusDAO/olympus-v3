// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

/// DEPS
import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "solmate/tokens/ERC20.sol";
import "test-utils/UserFactory.sol";
import "test-utils/larping.sol";
import "test-utils/convert.sol";

//// LOCAL
// types
import "src/modules/DEMAM.sol";

contract MERC20 is ERC20 {
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC20(_name, _symbol, _decimals) {}
}

contract DEMAMTest is Test {
    using larping for *;
    using convert for *;

    DepositManagementModule demam;
    UserFactory victims;
    ERC20 ohm;

    address ohma;
    address demama;

    function getWritePermissions(bytes5, address) public pure returns (bool) {
        return true;
    }

    function setUp() public {
        demam = new DepositManagementModule(address(this));
        victims = new UserFactory();
        ohm = new MERC20("ohm", "OHM", 9);

        ohma = address(ohm);
        demama = address(demam);
    }

    function testKeycode() public {
        assertEq32("DEMAM", demam.KEYCODE());
    }

    function testTakeTokens(uint224 amount, uint8 nusers) public {
        // setup vm
        vm.assume(nusers < 6);
        vm.assume(0 < nusers);
        vm.assume(amount != 1e19 + 23);

        // setup
        address[] memory usrs = victims.create(nusers);

        for (uint256 i; i < nusers; i++) {
            ohm.transferFrom.larp(usrs[i], demama, amount, true);
            demam.takeTokens(usrs[i], ohma, amount);
            assertEq(demam.freeBalanceOf(usrs[i], ohma), amount);
        }

        vm.expectRevert(bytes("TRANSFER_FROM_FAILED"));
        demam.takeTokens(usrs[0], ohma, 1e19 + 23);
    }

    function testTakeAndLockTokens(uint224 amount, uint32 period) public {
        // setup vm
        vm.assume(amount != 1e19 + 23);

        // setup
        address[] memory usrs = victims.create(3);
        address usr = usrs[0];

        ohm.transferFrom.larp(usr, demama, amount, true);
        uint256 index = demam.takeAndLockTokens(usr, ohma, amount, period);

        uint256 bal1 = demam.getUserLockBalance(usr, ohma, index);
        DepositManagementModule.Lock memory lock = demam.getUserLock(
            usr,
            ohma,
            index
        );

        assertEq(bal1, amount);
        assertEq(bal1, demam.lockedBalanceOf(usr, ohma));
        assertEq(lock.balance, bal1);
        assertEq(lock.end, period);

        uint224 am = amount / 2 + 2;
        uint32 per = period / 2 + 2;

        ohm.transferFrom.larp(usr, demama, am, true);
        index = demam.takeAndLockTokens(usr, ohma, am, per);

        uint256 bal2 = demam.getUserLockBalance(usr, ohma, index);
        lock = demam.getUserLock(usr, ohma, index);

        assertEq(bal2, am);
        assertEq(bal1 + bal2, demam.lockedBalanceOf(usr, ohma));
        assertEq(lock.balance, bal2);
        assertEq(lock.end, per);

        vm.expectRevert(bytes("TRANSFER_FROM_FAILED"));
        demam.takeAndLockTokens(usrs[1], ohma, 1e19 + 23, period);
    }

    function testPayTokens(uint224 amount) public {
        vm.assume(5 < amount);
        vm.assume(amount < type(uint224).max / 10);

        // setup
        address[] memory usrs = victims.create(3);
        address usr = usrs[0];

        uint224 am = amount / 2 + 2;
        uint224 am2 = amount / 3 + 3;

        ohm.transferFrom.larp(usr, demama, amount, true);
        ohm.transferFrom.larp(usr, demama, am, true);

        demam.takeTokens(usr, ohma, amount);
        demam.takeTokens(usr, ohma, am);

        ohm.transfer.larp(usr, amount, true);
        ohm.transfer.larp(usr, am2, true);
        ohm.transfer.larp(usr, am - am2, true);

        demam.payTokens(usr, ohma, am2);

        assertEq(demam.freeBalanceOf(usr, ohma), amount + am - am2);

        demam.payTokens(usr, ohma, am - am2);

        assertEq(demam.freeBalanceOf(usr, ohma), amount);

        demam.payTokens(usr, ohma, amount);

        assertEq(demam.freeBalanceOf(usr, ohma), 0);

        demam.takeTokens(usr, ohma, amount);

        vm.expectRevert(
            abi.encodeWithSelector(
                DEMAM_NotEnoughTokensUnlocked.selector,
                amount
            )
        );

        demam.payTokens(usr, ohma, amount + 1);
    }

    function testPayUnlockedTokens(uint224 amount, uint32 period) public {
        vm.assume(5 < amount);
        vm.assume(amount < type(uint224).max / 10);
        vm.assume(15 < period);
        vm.assume(period < type(uint32).max);

        // setup
        address[] memory usrs = victims.create(3);
        address usr = usrs[0];

        uint224 am = amount / 2 + 2;
        uint224 am2 = amount / 3 + 3;
        uint32 per = period / 2 + 2;

        ohm.transferFrom.larp(usr, demama, amount, true);
        ohm.transferFrom.larp(usr, demama, am, true);

        uint224[] memory amounts = new uint224[](3);
        amounts[0] = amount;
        amounts[1] = am;
        amounts[2] = am;

        uint256[] memory indices = new uint256[](3);
        indices[0] = demam.takeAndLockTokens(usr, ohma, amount, period);
        indices[1] = demam.takeAndLockTokens(usr, ohma, am, per);
        indices[2] = demam.takeAndLockTokens(usr, ohma, am, per);

        ohm.transfer.larp(usr, amount, true);
        ohm.transfer.larp(usr, am, true);

        uint256 balance = demam.freeBalanceOf(usr, ohma);

        vm.warp(1);

        if (period > 0)
            vm.expectRevert(
                abi.encodeWithSelector(
                    DEMAM_LockNotOver.selector,
                    period - uint32(block.timestamp)
                )
            );

        demam.payUnlockedTokens(usr, ohma, amount, indices[0]);

        if (period < 1) {
            indices[0] = 0;
            assertEq(demam.freeBalanceOf(usr, ohma), am * 2);
            balance -= amount;
        }

        if (per > 0)
            vm.expectRevert(
                abi.encodeWithSelector(
                    DEMAM_LockNotOver.selector,
                    per - uint32(block.timestamp)
                )
            );

        demam.payUnlockedTokens(usr, ohma, am, indices[1]);

        if (per < 1) {
            indices[1] = 0;
            assertEq(demam.freeBalanceOf(usr, ohma), am);
            balance -= am;
        }

        vm.warp(per);

        if (per > 0)
            vm.expectRevert(
                abi.encodeWithSelector(
                    DEMAM_LockNotOver.selector,
                    per - uint32(block.timestamp)
                )
            );

        demam.payUnlockedTokens(usr, ohma, am, indices[2]);

        if (per < 1) {
            indices[2] = 0;
            assertEq(demam.freeBalanceOf(usr, ohma), 0);
            balance = 0;
        }

        vm.warp(0);
        if (indices[0] == 0)
            indices[0] = demam.takeAndLockTokens(usr, ohma, amount, period);
        if (indices[1] == 0)
            indices[1] = demam.takeAndLockTokens(usr, ohma, am, per);
        if (indices[2] == 0)
            indices[2] = demam.takeAndLockTokens(usr, ohma, am, per);
        balance = demam.lockedBalanceOf(usr, ohma);
        vm.warp(period + 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                DEMAM_NotEnoughTokensUnlocked.selector,
                demam.getUserLockBalance(usr, ohma, indices[0])
            )
        );
        demam.payUnlockedTokens(usr, ohma, amount + 1, indices[0]);

        ohm.transfer.larp(usr, amount - am2, true);
        demam.payUnlockedTokens(usr, ohma, amount - am2, indices[0]);

        DepositManagementModule.Lock memory lock = demam.getUserLock(
            usr,
            ohma,
            indices[0]
        );
        assertEq(lock.balance, am2);
        assertEq(lock.end, period);

        ohm.transfer.larp(usr, am2, true);
        demam.payUnlockedTokens(usr, ohma, am2, indices[0]);
        assertEq(demam.getUserLockBalance(usr, ohma, indices[0]), 0);

        ohm.transferFrom.larp(usr, ohma, amount, true);

        vm.warp(0);
        demam.takeAndAddToLock(usr, ohma, amount, indices[0]);
        vm.warp(period + 1);

        ohm.transfer.larp(usr, balance, true);

        (uint224[] memory input1, uint256[] memory input2) = demam.findUnlocked(
            usr,
            ohma
        );

        demam.payUnlockedTokens(usr, ohma, input1, input2);

        assertEq(demam.lockedBalanceOf(usr, ohma), 0);
    }

    function testPayAllUnlockedTokens(uint224 amount, uint32 period) public {
        vm.assume(5 < amount);
        vm.assume(amount < type(uint224).max / 10);
        vm.assume(0 < period);
        vm.assume(period < type(uint32).max);

        // setup
        address[] memory usrs = victims.create(3);
        address usr = usrs[0];

        uint224 am = amount / 2 + 2;
        uint224 am2 = amount / 3 + 3;
        uint32 per = period / 2 + 2;

        ohm.transferFrom.larp(usr, demama, amount, true);
        ohm.transferFrom.larp(usr, demama, am, true);
        ohm.transferFrom.larp(usr, demama, am2, true);

        uint224[] memory amounts = new uint224[](3);
        amounts[0] = amount;
        amounts[1] = am;
        amounts[2] = am2;

        uint256[] memory indices = new uint256[](3);
        indices[0] = demam.takeAndLockTokens(usr, ohma, amount, period);
        vm.warp(100000);
        indices[1] = demam.takeAndLockTokens(usr, ohma, am, per);
        vm.warp(200000);
        indices[2] = demam.takeAndLockTokens(usr, ohma, am2, per);

        vm.warp(period + 10000000000);

        ohm.transfer.larp(usr, amount + am + am2, true);

        demam.payAllUnlockedTokens(usr, ohma);

        assertEq(demam.lockedBalanceOf(usr, ohma), 0);
        assertEq(demam.freeBalanceOf(usr, ohma), 0);
    }

    function testLockDeposited(uint224 amount, uint32 period) public {
        vm.assume(5 < amount);
        vm.assume(amount < type(uint224).max / 10);
        vm.assume(15 < period);
        vm.assume(period < type(uint32).max);

        // setup
        address[] memory usrs = victims.create(3);
        address usr = usrs[0];

        uint224 am2 = amount / 3 + 3;

        ohm.transferFrom.larp(usr, demama, amount, true);

        demam.takeTokens(usr, ohma, amount);

        // revert
        vm.expectRevert(
            abi.encodeWithSelector(
                DEMAM_NotEnoughTokensUnlocked.selector,
                demam.freeBalanceOf(usr, ohma)
            )
        );
        demam.lockDepositedByPeriod(usr, ohma, amount + 1, period);

        // pass
        uint256 index = demam.lockDepositedByPeriod(usr, ohma, amount, period);

        assertEq(demam.freeBalanceOf(usr, ohma), 0);
        assertEq(demam.lockedBalanceOf(usr, ohma), amount);
        assertEq(demam.lockedBalanceOf(usr, ohma), amount);
        assertEq(demam.getUserLockBalance(usr, ohma, index), amount);

        demam.takeTokens(usr, ohma, amount);

        vm.expectRevert(
            abi.encodeWithSelector(
                DEMAM_NotEnoughTokensUnlocked.selector,
                demam.freeBalanceOf(usr, ohma)
            )
        );
        demam.lockDepositedByIndex(usr, ohma, amount + 1, index);

        demam.lockDepositedByIndex(usr, ohma, am2, index);

        assertEq(demam.freeBalanceOf(usr, ohma), amount - am2);
        assertEq(demam.lockedBalanceOf(usr, ohma), amount + am2);
        assertEq(demam.presentlyLockedBalanceOf(usr, ohma), amount + am2);
        assertEq(demam.presentlyUnlockedBalanceOf(usr, ohma), 0);
        assertEq(demam.getUserLockBalance(usr, ohma, index), amount + am2);

        uint256 index2 = demam.lockDepositedByPeriod(
            usr,
            ohma,
            amount - am2,
            period
        );

        assertTrue(index != index2);

        assertEq(demam.freeBalanceOf(usr, ohma), 0);
        assertEq(demam.lockedBalanceOf(usr, ohma), amount * 2);
        assertEq(demam.presentlyLockedBalanceOf(usr, ohma), amount * 2);
        assertEq(demam.presentlyUnlockedBalanceOf(usr, ohma), 0);
        assertEq(demam.getUserLockBalance(usr, ohma, index), amount + am2);
        assertEq(demam.getUserLockBalance(usr, ohma, index2), amount - am2);
    }

    function testSlashTokens(uint224 amount) public {
        vm.assume(5 < amount);
        vm.assume(amount < type(uint224).max / 10);

        // setup
        address[] memory usrs = victims.create(2);
        address usr = usrs[0];
        address rec = usrs[1];

        ohm.transferFrom.larp(usr, demama, amount, true);

        demam.takeTokens(usr, ohma, amount);

        vm.expectRevert(
            abi.encodeWithSelector(
                DEMAM_NotEnoughUnlockedForSlashing.selector,
                demam.freeBalanceOf(usr, ohma)
            )
        );
        demam.slashTokens(usr, rec, ohma, amount + 1);

        demam.slashTokens(usr, rec, ohma, amount);

        assertEq(demam.freeBalanceOf(rec, ohma), amount);
        assertEq(demam.freeBalanceOf(usr, ohma), 0);
        assertEq(demam.lockedBalanceOf(usr, ohma), 0);
    }

    function testSlashTokensLocked(uint224 amount, uint32 period) public {
        vm.assume(5 < amount);
        vm.assume(amount < type(uint224).max / 10);
        vm.assume(15 < period);
        vm.assume(period < type(uint32).max);

        // setup
        address[] memory usrs = victims.create(2);
        address usr = usrs[0];
        address rec = usrs[1];

        uint224 am = amount / 2 + 2;
        uint224 am2 = amount / 3 + 3;
        uint32 per = period / 2 + 2;

        ohm.transferFrom.larp(usr, demama, amount, true);
        ohm.transferFrom.larp(usr, demama, am, true);
        ohm.transferFrom.larp(usr, demama, am2, true);

        uint224[] memory amounts = new uint224[](3);
        amounts[0] = amount / 2;
        amounts[1] = am / 2;
        amounts[2] = am2 / 2;
        uint256 sum1 = amount + am + am2;
        uint256 sum2 = amounts[0] + amounts[1] + amounts[2];

        uint256[] memory indices = new uint256[](3);
        indices[0] = demam.takeAndLockTokens(usr, ohma, amount, period);
        vm.warp(100000);
        indices[1] = demam.takeAndLockTokens(usr, ohma, am, per);
        vm.warp(200000);
        indices[2] = demam.takeAndLockTokens(usr, ohma, am2, per);

        vm.warp(period + 10000000000);

        demam.slashLockedTokens(usr, rec, ohma, amounts, indices);

        assertEq(demam.lockedBalanceOf(usr, ohma), sum1 - sum2);
        assertEq(demam.freeBalanceOf(usr, ohma), 0);
        assertEq(demam.presentlyLockedBalanceOf(usr, ohma), 0);
        assertEq(demam.freeBalanceOf(rec, ohma), sum2);

        vm.warp(per + 1);
        assertEq(
            demam.presentlyUnlockedBalanceOf(usr, ohma),
            am - amounts[1] + am2 - amounts[2]
        );
        vm.warp(period + 10000000000);

        amounts[0] = amount - amount / 2;
        amounts[1] = am - am / 2;
        amounts[2] = am2 - am2 / 2;

        demam.slashLockedTokens(usr, rec, ohma, amounts, indices);

        assertEq(demam.lockedBalanceOf(usr, ohma), 0);
        assertEq(demam.freeBalanceOf(usr, ohma), 0);
        assertEq(demam.freeBalanceOf(rec, ohma), sum1);
    }

    function testMergeLocks(uint224 amount, uint32 period) public {
        vm.assume(0 < amount);
        vm.assume(amount < type(uint224).max / 10);
        vm.assume(15 < period);
        vm.assume(period < type(uint32).max);

        // setup
        address[] memory usrs = victims.create(1);
        address usr = usrs[0];

        uint224 am = amount / 2 + 2;
        uint224 am2 = amount / 3 + 3;
        uint32 per = period / 2 + 2;

        ohm.transferFrom.larp(usr, demama, amount, true);
        ohm.transferFrom.larp(usr, demama, am, true);
        ohm.transferFrom.larp(usr, demama, am2, true);

        uint224[] memory amounts = new uint224[](3);
        amounts[0] = amount;
        amounts[1] = am;
        amounts[2] = am2;

        uint256[] memory indices = new uint256[](3);
        indices[0] = demam.takeAndLockTokens(usr, ohma, am2, per);
        indices[1] = demam.takeAndLockTokens(usr, ohma, am, per);
        indices[2] = demam.takeAndLockTokens(usr, ohma, amount, period);

        uint256[] memory indicesWrong = new uint256[](3);
        indicesWrong[0] = 2;
        indicesWrong[1] = 1;
        indicesWrong[2] = 0;

        vm.expectRevert(
            abi.encodeWithSelector(DEMAM_NoMergingToShorterLock.selector)
        );
        demam.mergeLocks(usr, ohma, indicesWrong);

        demam.mergeLocks(usr, ohma, indices);

        assertEq(
            uint224(demam.lockedBalanceOf(usr, ohma)),
            demam.getUserLockBalance(usr, ohma, indices[2])
        );
    }

    function testExtendLock(uint224 amount, uint32 period) public {
        vm.assume(0 < amount);
        vm.assume(amount < type(uint224).max / 10);
        vm.assume(15 < period);
        vm.assume(period < type(uint32).max / 100000);

        // setup
        address[] memory usrs = victims.create(1);
        address usr = usrs[0];

        uint224 am = amount / 2 + 2;
        uint224 am2 = amount / 3 + 3;
        uint32 per = period / 2 + 2;

        ohm.transferFrom.larp(usr, demama, amount, true);
        ohm.transferFrom.larp(usr, demama, am, true);
        ohm.transferFrom.larp(usr, demama, am2, true);

        uint224[] memory amounts = new uint224[](3);
        amounts[0] = amount;
        amounts[1] = am;
        amounts[2] = am2;

        uint256[] memory indices = new uint256[](3);
        indices[0] = demam.takeAndLockTokens(usr, ohma, amount, period);
        indices[1] = demam.takeAndLockTokens(usr, ohma, am, per);
        indices[2] = demam.takeAndLockTokens(usr, ohma, am2, per);

        demam.extendLock(usr, ohma, indices[0], period + 1000);

        assertEq(demam.getUserLockEnd(usr, ohma, indices[0]), period + 1000);

        demam.extendLock(usr, ohma, indices[1], per + 100);

        assertEq(demam.getUserLockEnd(usr, ohma, indices[1]), per + 100);

        demam.extendLock(usr, ohma, indices[2], per + 200);

        assertEq(demam.getUserLockEnd(usr, ohma, indices[2]), per + 200);
    }
}
