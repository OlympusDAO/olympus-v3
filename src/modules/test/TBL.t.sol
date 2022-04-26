// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

/// DEPS
import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "solmate/tokens/ERC20.sol";
import "test-utils/coins.sol";
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
        ohm = ERC20(coins.ohm);
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
            tbl.pullTokens(user, coins.ohm, uint224(deposit), 0);
            assertEq(tbl.unlocked(user, coins.ohm, false), bals[index]);
            assertEq(tbl.locked(user, coins.ohm), 0);
        }

        /// revert
        vm.expectRevert(bytes("TRANSFER_FROM_FAILED"));
        tbl.pullTokens(usrs[0], coins.ohm, 1e24, 0);
    }

    function testPullTokensLocked(uint224 amount, uint32 lockPeriod) public {
        /// Setup
        // vm
        vm.assume(amount > 0);
        vm.assume(lockPeriod > 0);

        // else
        address user1 = usrfac.next();
        address user2 = usrfac.next();
        Kernel(address(this)).approvedPolicies.mock(address(this), true);
        ohm.transferFrom.mock(user1, address(tbl), amount, true);

        // test
        /// passing
        if (uint256(block.timestamp + lockPeriod) > 2**32 - 1) {
            vm.expectRevert(stdError.arithmeticError);
            tbl.pullTokens(user1, coins.ohm, amount, lockPeriod);
        } else {
            tbl.pullTokens(user1, coins.ohm, amount, lockPeriod);
            assertEq(tbl.locked(user1, coins.ohm), amount);
            assertEq(tbl.unlocked(user1, coins.ohm, true), 0);
            assertEq(tbl.unlocked(user1, coins.ohm, false), 0);
        }

        /// revert
        vm.expectRevert(bytes("TRANSFER_FROM_FAILED"));
        tbl.pullTokens(user2, coins.ohm, amount, lockPeriod);
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
        tbl.pullTokens(user1, coins.ohm, amount, 0);
        tbl.pushTokens(user1, coins.ohm, amount, false);
        assertEq(tbl.unlocked(user1, coins.ohm, false), 0);
        assertEq(tbl.locked(user1, coins.ohm), 0);
        assertEq(tbl.unlocked(user1, coins.ohm, true), 0);
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
        tbl.pullTokens(user1, coins.ohm, amount, lockPeriod);

        vm.expectRevert(
            abi.encodeWithSelector(TBL_NotEnoughTokensUnlocked.selector, 0)
        );
        tbl.pushTokens(user1, coins.ohm, amount, true);

        skip(lockPeriod);
        vm.expectRevert(
            abi.encodeWithSelector(TBL_NotEnoughTokensUnlocked.selector, 0)
        );
        tbl.pushTokens(user1, coins.ohm, amount, true);

        skip(1);
        tbl.pushTokens(user1, coins.ohm, amount, true);

        assertEq(tbl.unlocked(user1, coins.ohm, false), 0);
        assertEq(tbl.locked(user1, coins.ohm), 0);
        assertEq(tbl.unlocked(user1, coins.ohm, true), 0);
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
        tbl.pullTokens(user1, coins.ohm, amount, lockPeriod);

        vm.expectRevert(
            abi.encodeWithSelector(TBL_NotEnoughTokensUnlocked.selector, 0)
        );
        tbl.pushTokens(user1, coins.ohm, amount, true);

        skip(lockPeriod);
        vm.expectRevert(
            abi.encodeWithSelector(TBL_NotEnoughTokensUnlocked.selector, 0)
        );
        tbl.pushTokens(user1, coins.ohm, amount, true);

        if (
            uint256(lockExtensionPeriod) + uint256(lockPeriod) + origTimestamp >
            2**32 - 1
        ) {
            vm.expectRevert(stdError.arithmeticError);
            tbl.extendLock(user1, coins.ohm, amount, lockExtensionPeriod);
        } else {
            tbl.extendLock(user1, coins.ohm, amount, lockExtensionPeriod);
            skip(lockExtensionPeriod - 1);
            vm.expectRevert(
                abi.encodeWithSelector(TBL_NotEnoughTokensUnlocked.selector, 0)
            );
            tbl.pushTokens(user1, coins.ohm, amount, true);
        }
    }
}
