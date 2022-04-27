// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

/// DEPS
import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "solmate/tokens/ERC20.sol";
import "test-utils/users.sol";
import "test-utils/mocking.sol";

//// LOCAL
// types
import "src/modules/TBL.sol";

contract TransferBalanceLockTest is Test {
    using mocking for *;

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

        /// revert
        vm.expectRevert(bytes("TRANSFER_FROM_FAILED"));
        tbl.pullTokens(usrs[0], address(ohm), 1e24, 0);
    }

    function testPullTokensLocked(
        uint224 amount,
        uint8 rounds,
        uint8 nusers,
        uint32 lockBound
    ) public {
        /// Setup
        // vm
        vm.assume(amount > 1);
        vm.assume(lockBound > 100);
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

        uint256 timestamp = block.timestamp;

        for (uint256 i; i < length; i++) {
            address user = usrs[i];

            for (uint256 j; j < rounds; j++) {
                uint224 deposit = uint224(
                    uint256(keccak256(abi.encode(i * j))) % 1e40
                );
                uint32 lockPeriod = uint32(
                    uint256(keccak256(abi.encode(i * j + lockBound))) %
                        lockBound
                );

                ohm.transferFrom.mock(user, address(tbl), deposit, true);

                if (2**32 - 1 < block.timestamp + lockPeriod) {
                    vm.expectRevert(stdError.arithmeticError);
                    tbl.pullTokens(user, address(ohm), deposit, lockPeriod);
                } else {
                    tbl.pullTokens(user, address(ohm), deposit, lockPeriod);
                    bals[i] += deposit;

                    vm.warp(timestamp);

                    assertEq(tbl.locked(user, address(ohm)), bals[i]);
                    assertEq(tbl.unlocked(user, address(ohm), true), 0);
                    assertEq(tbl.unlocked(user, address(ohm), false), 0);
                }
            }
        }
    }

    function testPushTokensUnlocked(uint224 amount) public {
        /// Setup
        // vm
        vm.assume(amount > 0);

        // else
        address user1 = usrfac.next();
        address user2 = usrfac.next();
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

    function testPushTokensLocked(uint224 amount, uint32 lockPeriod) public {
        /// Setup
        // vm
        vm.assume(amount > 0);
        vm.assume(lockPeriod > 0);
        vm.assume(lockPeriod + block.timestamp <= 2**32 - 1);

        // else
        address user1 = usrfac.next();
        address user2 = usrfac.next();
        Kernel(address(this)).approvedPolicies.mock(address(this), true);
        ohm.transferFrom.mock(user1, address(tbl), amount, true);
        ohm.transferFrom.mock(user2, address(tbl), amount, true);
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

        skip(1);
        tbl.pushTokens(user1, address(ohm), amount, true);

        assertEq(tbl.unlocked(user1, address(ohm), false), 0);
        assertEq(tbl.locked(user1, address(ohm)), 0);
        assertEq(tbl.unlocked(user1, address(ohm), true), 0);
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
        address user2 = usrfac.next();
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
