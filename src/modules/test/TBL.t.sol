// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

/// DEPS
import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "solmate/tokens/ERC20.sol";
import "test-utils/coins.sol";
import "test-utils/token.sol";
import "test-utils/users.sol";

//// LOCAL
// types
import "src/modules/TBL.sol";

contract TransferBalanceLockTest is Test {
    TransferBalanceLock tbl;
    token mock;
    users usrfac;

    bool pswitch;

    function approvedPolicies(address) public view returns (bool) {
        return pswitch;
    }

    function setUp() public {
        tbl = new TransferBalanceLock(address(this));
        mock = new token(coins.ohm);
        usrfac = new users();
    }

    function testKEYCODE() public {
        assertEq32("TBL", tbl.KEYCODE());
    }

    function testPullTokensNoLock(uint224 amount) public {
        /// Setup
        // vm
        vm.assume(amount > 0);
        vm.mockCall(
            address(this),
            abi.encodeWithSignature("approvedPolicies(address)", address(this)),
            abi.encode(true)
        );

        // else
        address user1 = usrfac.next();
        address user2 = usrfac.next();
        mock.transferFrom(user1, address(tbl), amount);

        // test
        /// passing
        tbl.pullTokens(user1, coins.ohm, amount, 0);
        assertEq(tbl.unlocked(user1, coins.ohm, false), amount);
        assertEq(tbl.locked(user1, coins.ohm), 0);

        /// revert
        vm.expectRevert(bytes("TRANSFER_FROM_FAILED"));
        tbl.pullTokens(user2, coins.ohm, amount, 0);
    }

    function testPullTokensLocked(uint224 amount, uint32 lockPeriod) public {
        /// Setup
        // vm
        vm.assume(amount > 0);
        vm.assume(lockPeriod > 0);
        vm.mockCall(
            address(this),
            abi.encodeWithSignature("approvedPolicies(address)", address(this)),
            abi.encode(true)
        );

        // else
        address user1 = usrfac.next();
        address user2 = usrfac.next();
        mock.transferFrom(user1, address(tbl), amount);

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
        vm.mockCall(
            address(this),
            abi.encodeWithSignature("approvedPolicies(address)", address(this)),
            abi.encode(true)
        );

        // else
        address user1 = usrfac.next();
        address user2 = usrfac.next();
        mock.transferFrom(user1, address(tbl), amount);
        mock.transfer(user1, amount);

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
        vm.mockCall(
            address(this),
            abi.encodeWithSignature("approvedPolicies(address)", address(this)),
            abi.encode(true)
        );

        // else
        address user1 = usrfac.next();
        address user2 = usrfac.next();
        mock.transferFrom(user1, address(tbl), amount);
        mock.transferFrom(user2, address(tbl), amount);
        mock.transfer(user1, amount);

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
        vm.mockCall(
            address(this),
            abi.encodeWithSignature("approvedPolicies(address)", address(this)),
            abi.encode(true)
        );
        uint256 origTimestamp = block.timestamp;

        // else
        address user1 = usrfac.next();
        address user2 = usrfac.next();
        mock.transferFrom(user1, address(tbl), amount);
        mock.transfer(user1, amount);

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
