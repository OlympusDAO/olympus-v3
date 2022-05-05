// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

/// DEPS
import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "solmate/tokens/ERC20.sol";
import "test-utils/users.sol";
import "test-utils/mocking.sol";
import "test-utils/sorting.sol";

//// LOCAL
// types
import "src/modules/TBL.sol";

contract TransferBalanceLockTest is Test {
    using mocking for *;
    using sorting for uint256[];

    TransferBalanceLock tbl;
    users usrfac;
    ERC20 ohm;

    bool pswitch;

    function approvedPolicies(address) public view returns (bool) {
        return pswitch;
    }

    function setUp() public {
        tbl = new TransferBalanceLock(address(this));
        usrfac = new users();
        ohm = ERC20(
            deployCode("MockERC20.t.sol:MockERC20", abi.encode("ohm", "OHM", 9))
        );
    }

    function testKEYCODE() public {
        assertEq32("TBL", tbl.KEYCODE());
    }

    function testPullTokensNoLock(
        uint224 amount,
        uint8 rounds,
        uint8 nusers
    ) public {
        /// Setup
        // vm
        vm.assume(amount > 0);
        vm.assume(amount < 1e40);
        vm.assume(rounds > 0);
        vm.assume(nusers > 0);
        vm.assume(rounds < 30);
        vm.assume(nusers < 30);

        // else
        address[] memory usrs = usrfac.create(nusers);
        uint256 length = usrs.length;

        uint256[] memory bals = new uint256[](length);

        Kernel(address(this)).approvedPolicies.mock(address(this), true);

        for (uint256 i; i < rounds; i++) {
            uint256 index = uint256(keccak256(abi.encode(i))) % length;
            address user = usrs[index];
            uint256 deposit = uint256(keccak256(abi.encode(amount + i))) % 1e24;
            bals[index] += deposit;

            ohm.transferFrom.mock(user, address(tbl), uint224(deposit), true);

            // test
            /// passing
            tbl.pullTokens(user, address(ohm), uint224(deposit), 0);
            assertEq(tbl.unlocked(user, address(ohm), false), bals[index]);
            assertEq(tbl.locked(user, address(ohm)), 0);
        }
    }

    function testPullTokensLocked(
        uint200 amount,
        uint8 rounds,
        uint8 nusers,
        uint24 lockBound
    ) public {
        /// Setup
        // vm
        vm.assume(amount > 1);
        vm.assume(lockBound > 100);
        vm.assume(amount < 1e40);
        vm.assume(rounds > 0);
        vm.assume(nusers > 0);

        rounds %= 30;
        nusers %= 30;

        if (rounds == 0) rounds = 5;
        if (nusers == 0) nusers = 5;
        if (amount <= 400) amount = 401; // random

        // else
        address[] memory usrs = usrfac.create(nusers);
        uint256 length = usrs.length;

        uint256[][][] memory data = new uint256[][][](length);

        Kernel(address(this)).approvedPolicies.mock(address(this), true);

        uint256 maxtimestamp = block.timestamp;

        for (uint256 i; i < length; i++) {
            data[i] = new uint256[][](2);
            data[i][0] = new uint256[](rounds + 1);
            data[i][1] = new uint256[](rounds + 1);

            address user = usrs[i];

            for (uint256 j; j < rounds; j++) {
                vm.warp(0);

                uint224 deposit = amount;

                uint32 lockPeriod = uint32(
                    uint256(keccak256(abi.encode(i * j + lockBound))) %
                        lockBound
                );

                if (2**32 - 1 < lockPeriod + block.timestamp) {
                    lockPeriod %= 2**32 - 1;
                }

                if (lockPeriod == 0) lockPeriod = 3600 * 24;
                if (deposit == 0) deposit = 1e21;
                if (maxtimestamp < lockPeriod + block.timestamp)
                    maxtimestamp = lockPeriod + block.timestamp;

                ohm.transferFrom.mock(user, address(tbl), deposit, true);

                data[i][0][j] = deposit; // Amount
                data[i][1][j] = lockPeriod + block.timestamp; // ts

                tbl.pullTokens(user, address(ohm), deposit, lockPeriod);
            }
        }

        for (uint256 i; i < nusers; i++) {
            vm.warp(0);

            uint256 step = (maxtimestamp + 1) / 20;
            if (step != 0) {
                for (uint256 j; j < maxtimestamp + 20; j += step) {
                    vm.warp(j);

                    uint256 locked;
                    uint256 unlocked;

                    for (uint256 k; k < data[i][1].length; k++) {
                        if (j <= data[i][1][k]) locked += data[i][0][k];
                        else unlocked += data[i][0][k];
                    }

                    assertEq(tbl.locked(usrs[i], address(ohm)), locked);
                    assertEq(
                        tbl.unlocked(usrs[i], address(ohm), true),
                        unlocked
                    );
                    assertEq(tbl.unlocked(usrs[i], address(ohm), false), 0);
                }
            }
        }
    }

    function testPullReverts() public {
        Kernel(address(this)).approvedPolicies.mock(address(this), true);

        vm.warp(20);
        ohm.transferFrom.mock(address(0), address(tbl), 1e21, true);
        vm.expectRevert(stdError.arithmeticError);
        tbl.pullTokens(address(0), address(ohm), 1e21, 2**32 - 1);

        vm.expectRevert(bytes("TRANSFER_FROM_FAILED"));
        tbl.pullTokens(address(0), address(ohm), 1e24, 0);
    }

    function testSlashTokens(
        uint200 amount,
        uint8 nusers,
        uint24 lockBound,
        bool slashRecent
    ) public {
        // Setup
        vm.assume(amount < 1e40);
        vm.assume(lockBound > 36 * 2400);
        vm.assume(nusers > 0);

        nusers %= 30;
        uint8 rounds = uint8((uint256(nusers) * (amount % 231)) % 30);

        if (nusers == 0) nusers = 5;
        if (rounds == 0) rounds = 5;
        if (amount <= 400) amount = 401; // random

        // else
        address[] memory usrs = usrfac.create(nusers + 1);
        uint256 length = usrs.length - 1;
        usrs[length] = usrfac.next();

        uint256[][][] memory data = new uint256[][][](length);
        uint256[] memory bals = new uint256[](length);

        Kernel(address(this)).approvedPolicies.mock(address(this), true);

        for (uint256 i; i < length; i++) {
            data[i] = new uint256[][](2);
            data[i][0] = new uint256[](rounds + 1);
            data[i][1] = new uint256[](rounds + 1);

            for (uint256 j; j < rounds; j++) {
                uint32 lockPeriod = uint32(
                    uint256(keccak256(abi.encode(i * j + lockBound))) %
                        lockBound
                );

                if (2**32 - 1 < lockPeriod + block.timestamp) {
                    lockPeriod %= 2**32 - 1;
                }

                if (lockPeriod == 0) lockPeriod = 3600 * 24;
                if (amount == 0) amount = 1e21;

                ohm.transferFrom.mock(usrs[i], address(tbl), amount, true);

                data[i][0][j] = amount; // Amount
                data[i][1][j] = lockPeriod + block.timestamp; // ts
                bals[i] += amount;

                tbl.pullTokens(usrs[i], address(ohm), amount, lockPeriod);
            }
        }

        for (uint256 i; i < length; i++) {
            vm.warp(0);
            address receiver = usrfac.next();

            uint224 slashed = uint224(bals[i] / ((amount % 10) + 1));

            tbl.slashTokens(
                usrs[i],
                receiver,
                address(ohm),
                slashed,
                true,
                slashRecent
            );

            assertEq(tbl.locked(usrs[i], address(ohm)), bals[i] - slashed);
            assertEq(tbl.unlocked(receiver, address(ohm), false), slashed);

            vm.warp(data[i][1][data[i][1].length / 2]);

            assertEq(
                tbl.unlocked(usrs[i], address(ohm), true) +
                    tbl.locked(usrs[i], address(ohm)),
                bals[i] - slashed
            );
        }

        ohm.transfer.mock(
            usrs[length],
            uint224(tbl.unlocked(usrs[length], address(ohm), false)),
            true
        );

        tbl.pushTokens(
            usrs[length],
            address(ohm),
            uint224(tbl.unlocked(usrs[length], address(ohm), false)),
            false
        );

        vm.warp(0);

        ohm.transferFrom.mock(usrs[0], address(tbl), 1e21, true);
        tbl.pullTokens(usrs[0], address(ohm), 1e21, 0);

        tbl.slashTokens(
            usrs[0],
            usrs[length],
            address(ohm),
            1e19,
            false,
            false
        );

        assertEq(tbl.unlocked(usrs[length], address(ohm), false), 1e19);
        assertEq(tbl.unlocked(usrs[0], address(ohm), false), 1e21 - 1e19);

        tbl.slashTokens(
            usrs[0],
            usrs[length],
            address(ohm),
            1e21 - 1e19,
            false,
            false
        );

        assertEq(tbl.unlocked(usrs[length], address(ohm), false), 1e21);
        assertEq(tbl.unlocked(usrs[0], address(ohm), false), 0);
    }

    function testSlashTokensRevertAndRest() public {
        Kernel(address(this)).approvedPolicies.mock(address(this), true);
        address usr = usrfac.next();
        address rec = usrfac.next();

        ohm.transferFrom.mock(usr, address(tbl), 1e21, true);
        ohm.transferFrom.mock(usr, address(tbl), 1e22, true);

        tbl.pullTokens(usr, address(ohm), 1e21, 3600 * 24 * 54);
        tbl.pullTokens(usr, address(ohm), 1e22, 3600 * 24 * 32);

        assertEq(tbl.locked(usr, address(ohm)), 1e21 + 1e22);

        tbl.slashTokens(usr, rec, address(ohm), 5e21, true, true);
        tbl.slashTokens(usr, rec, address(ohm), 5e21, true, false);

        assertEq(tbl.locked(usr, address(ohm)), 1e21);
        assertEq(tbl.unlocked(rec, address(ohm), false), 1e22);

        vm.expectRevert(
            abi.encodeWithSelector(
                TBL_NotEnoughLockedForSlashing.selector,
                1e21
            )
        );
        tbl.slashTokens(usr, rec, address(ohm), 3e21, true, false);

        vm.expectRevert(
            abi.encodeWithSelector(TBL_NotEnoughUnlockedForSlashing.selector, 0)
        );
        tbl.slashTokens(usr, rec, address(ohm), 3e21, false, true);
    }

    function testPushTokensUnlocked(uint224 amount) public {
        /// Setup
        // vm
        vm.assume(amount > 0);

        // else
        address user1 = usrfac.next();
        Kernel(address(this)).approvedPolicies.mock(address(this), true);

        ohm.transferFrom.mock(user1, address(tbl), amount, true);
        ohm.transfer.mock(user1, amount, true);

        // test
        tbl.pullTokens(user1, address(ohm), amount, 0);
        tbl.pushTokens(user1, address(ohm), amount, false);

        assertEq(tbl.unlocked(user1, address(ohm), false), 0);
        assertEq(tbl.locked(user1, address(ohm)), 0);
        assertEq(tbl.unlocked(user1, address(ohm), true), 0);
    }

    function testPushTokensLocked(
        uint200 amount,
        uint8 nusers,
        uint24 lockBound
    ) public {
        // Setup
        vm.assume(amount < 1e40);
        vm.assume(lockBound > 36 * 2400);
        vm.assume(nusers > 0);

        nusers %= 30;
        uint8 rounds = uint8((uint256(nusers) * (amount % 231)) % 30);

        if (nusers == 0) nusers = 5;
        if (rounds == 0) rounds = 5;
        if (amount <= 400) amount = 401; // random

        // else
        address[] memory usrs = usrfac.create(nusers);
        uint256 length = usrs.length;

        uint256[][][] memory data = new uint256[][][](length);

        Kernel(address(this)).approvedPolicies.mock(address(this), true);

        for (uint256 i; i < length; i++) {
            data[i] = new uint256[][](2);
            data[i][0] = new uint256[](rounds);
            data[i][1] = new uint256[](rounds);

            for (uint256 j; j < rounds; j++) {
                uint32 lockPeriod = uint32(
                    uint256(keccak256(abi.encode(i * j + lockBound))) %
                        lockBound
                );

                if (2**32 - 1 < lockPeriod + block.timestamp) {
                    lockPeriod %= 2**32 - 1;
                }

                if (lockPeriod == 0) lockPeriod = 3600 * 24;
                if (amount == 0) amount = 1e21;

                ohm.transferFrom.mock(usrs[i], address(tbl), amount, true);

                data[i][0][j] = amount; // Amount
                data[i][1][j] = lockPeriod + block.timestamp; // ts

                tbl.pullTokens(usrs[i], address(ohm), amount, lockPeriod);
            }
        }

        for (uint256 i; i < length; i++) {
            (data[i][1], data[i][0]) = data[i][1].sortPartner(
                data[i][0],
                0,
                int256(data[i][1].length - 1)
            );

            for (uint256 j; j < data[i][1].length; j++) {
                if (data[i][1][j] >= block.timestamp) {
                    vm.warp(data[i][1][j] + 100);

                    uint256 sum;
                    for (uint256 k = j; k < data[i][1].length; k++) {
                        if (data[i][1][k] < block.timestamp) {
                            sum += data[i][0][k];
                            j = k;
                        }
                    }

                    assertEq(
                        tbl.unlocked(usrs[i], address(ohm), true),
                        uint224(sum)
                    );
                    ohm.transfer.mock(usrs[i], uint224(sum), true);
                    tbl.pushTokens(usrs[i], address(ohm), uint224(sum), true);
                }
            }

            vm.warp(0);
            assertEq(tbl.locked(usrs[i], address(ohm)), 0);
        }
    }

    function testPushTokensLockedRevert() public {
        Kernel(address(this)).approvedPolicies.mock(address(this), true);
        address usr = usrfac.next();
        uint256 timestamp = block.timestamp;

        ohm.transferFrom.mock(usr, address(tbl), 1e21, true);
        tbl.pullTokens(usr, address(ohm), 1e21, 86400);

        vm.warp(timestamp + 24000);

        ohm.transfer.mock(usr, 1e21, true);
        vm.expectRevert(
            abi.encodeWithSelector(TBL_NotEnoughTokensUnlocked.selector, 0)
        );
        tbl.pushTokens(usr, address(ohm), 1e21, true);

        vm.expectRevert(
            abi.encodeWithSelector(TBL_NotEnoughTokensUnlocked.selector, 0)
        );
        tbl.pushTokens(usr, address(ohm), 1e21, false);

        vm.warp(timestamp + 86401);

        tbl.pushTokens(usr, address(ohm), 1e21, true);
    }

    function testExtendLock(
        uint224 amount,
        uint32 lockPeriod,
        uint32 lockExtensionPeriod
    ) public {
        /// Setup
        // vm
        vm.assume(amount > 0);
        vm.assume(lockPeriod > 0);
        vm.assume(lockPeriod + block.timestamp <= 2**32 - 1);
        vm.assume(lockExtensionPeriod > 0);

        // else
        uint256 origTimestamp = block.timestamp;
        address user1 = usrfac.next();
        Kernel(address(this)).approvedPolicies.mock(address(this), true);
        ohm.transferFrom.mock(user1, address(tbl), amount, true);
        ohm.transfer.mock(user1, amount, true);

        // test
        tbl.pullTokens(user1, address(ohm), amount, lockPeriod);

        vm.expectRevert(
            abi.encodeWithSelector(TBL_NotEnoughTokensUnlocked.selector, 0)
        );
        tbl.pushTokens(user1, address(ohm), amount, true);

        skip(lockPeriod);
        vm.expectRevert(
            abi.encodeWithSelector(TBL_NotEnoughTokensUnlocked.selector, 0)
        );
        tbl.pushTokens(user1, address(ohm), amount, true);

        if (
            uint256(lockExtensionPeriod) + uint256(lockPeriod) + origTimestamp >
            2**32 - 1
        ) {
            vm.expectRevert(stdError.arithmeticError);
            tbl.extendLock(user1, address(ohm), amount, lockExtensionPeriod);
        } else {
            tbl.extendLock(user1, address(ohm), amount, lockExtensionPeriod);
            skip(lockExtensionPeriod - 1);
            vm.expectRevert(
                abi.encodeWithSelector(TBL_NotEnoughTokensUnlocked.selector, 0)
            );
            tbl.pushTokens(user1, address(ohm), amount, true);
        }
    }
}
