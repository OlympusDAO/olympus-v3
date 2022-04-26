// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

// interfaces (enums events errors)
import "src/OlympusErrors.sol";

// libs
import "src/libraries/TransferHelper.sol";

// types
import {Kernel, Module} from "src/Kernel.sol";

library locklib {
    function pack(uint224 amount, uint32 timestamp)
        internal
        pure
        returns (uint256)
    {
        return (uint256(amount) << 32) + uint256(timestamp);
    }

    function unpack(uint256 lock) internal pure returns (uint224, uint32) {
        return (uint224(lock >> 32), uint32(lock));
    }

    function sub(uint256 lock, uint256 toSub) internal pure returns (uint256) {
        return lock - (toSub << 32);
    }

    function suicide(uint256 lock)
        internal
        pure
        returns (uint256 dead, uint224 head)
    {
        head = uint224(lock >> 32);
        dead = uint256(head) << 32;
        assert(dead < lock);
    }
}

contract TransferBalanceLock is Module {
    using TransferHelper for IERC20;
    using locklib for uint256;

    mapping(address => mapping(address => uint256)) public unlockedBalances;
    mapping(address => mapping(address => uint256[])) public lockedBalances;

    constructor(address kernel_) Module(Kernel(kernel_)) {}

    function KEYCODE() external pure virtual override returns (bytes3) {
        return "TBL";
    }

    function unlockAll(address receiver, address token) external {
        // modifier in public
        pushTokens(
            receiver,
            token,
            uint224(unlocked(receiver, token, true)),
            true
        );
    }

    function pullTokens(
        address owner,
        address token,
        uint224 amount,
        uint32 lockPeriod
    ) external onlyPolicy {
        // interaction
        IERC20(token).safeTransferFrom(owner, address(this), amount);

        // then effect
        if (lockPeriod == 0) unlockedBalances[owner][token] += amount;
        else
            lockedBalances[owner][token].push(
                locklib.pack(amount, uint32(block.timestamp) + lockPeriod)
            );
    }

    function slashTokens(
        address owner,
        address receiver,
        address token,
        uint224 amount,
        bool isLocked,
        bool slashRecent
    ) external onlyPolicy {
        if (isLocked) {
            uint256[] memory locks = lockedBalances[owner][token];
            uint224 progress = amount;

            if (!slashRecent) {
                uint256 i = locks.length;

                while (i > 0) {
                    i--;

                    uint224 bal;
                    uint256 lock;

                    (lock, bal) = locks[i].suicide();

                    if (progress <= bal) {
                        locks[i] = lock.sub(bal - progress);
                        i = 0;
                    } else {
                        progress -= bal;
                        locks[i] = lock;
                    }
                }
            } else {
                uint256 i = 0;
                uint256 length = locks.length;

                while (i < length) {
                    uint224 bal;
                    uint256 lock;

                    (lock, bal) = locks[i].suicide();

                    if (progress <= bal) {
                        locks[i] = lock.sub(bal - progress);
                        i = length;
                    } else {
                        progress -= bal;
                        locks[i] = lock;
                    }

                    i++;
                }
            }

            if (progress != 0)
                revert TBL_NotEnoughLockedForSlashing(amount, progress);

            lockedBalances[owner][token] = locks;
        } else {
            uint256 bal = unlockedBalances[owner][token];

            if (bal < amount)
                revert TBL_NotEnoughTokensUnlockedForSlashing(bal);
            else unlockedBalances[owner][token] -= amount;
        }

        unlockedBalances[receiver][token] += amount;
    }

    function extendLock(
        address owner,
        address token,
        uint224 amount,
        uint32 lockExtensionPeriod
    ) external onlyPolicy {
        if (lockExtensionPeriod != 0) {
            // reads
            uint256[] memory locks = lockedBalances[owner][token];

            uint256 i = locks.length;
            uint224 origAmount = amount;

            // this extends locks on last tokens top down, to keep it logical and ordered
            while (i > 0) {
                i--;

                (uint224 balance, uint32 lockTimestamp) = locks[i].unpack();

                // will revert on fuckery
                lockTimestamp = lockTimestamp + lockExtensionPeriod;

                // no need to explicitly add period since its packed in first 32
                locks[i] += lockExtensionPeriod;

                if (amount <= balance) i = 0;
                amount -= balance;
            }

            // checks
            if (amount != 0)
                revert TBL_CouldNotExtendLockForAmount(origAmount, amount);

            // effects
            lockedBalances[owner][token] = locks;
        } else revert TBL_LockExtensionPeriodIs0();
    }

    function pushTokens(
        address receiver,
        address token,
        uint224 amount,
        bool fromLocked
    ) public onlyPolicy {
        // logic
        // the assumption is never so many locks that linear complexity
        // will bust block size, you know it won't happen
        if (fromLocked) {
            // reads
            uint256 i;
            uint256 ts = block.timestamp;

            uint256[] memory locks = lockedBalances[receiver][token];
            uint256 length = locks.length;

            uint224 pushable;

            // block
            while (pushable < amount) {
                // reads
                uint256 lock = locks[i];
                (uint224 balance, uint32 lockTimestamp) = lock.unpack();

                // check and read
                if (ts > lockTimestamp) {
                    if (balance + pushable > amount) {
                        locks[i] = lock.sub(amount - pushable);
                        pushable = amount; // flag
                    } else {
                        pushable += balance;
                        length--;
                    }
                } else revert TBL_NotEnoughTokensUnlocked(pushable);

                i++;
            }

            uint256 removed = locks.length - length;

            uint256[] memory newLocks = new uint256[](length);

            i = 0;

            while (i < length) {
                // say we remove 2, then you want to skip 2 slots, in index this translates to index 1 for starters, so we use
                // removed which is index + 1
                newLocks[i] = locks[removed + i];
                i++;
            }

            // effects
            lockedBalances[receiver][token] = newLocks;
        } else {
            uint256 balance = unlockedBalances[receiver][token];

            // not locked / not enough tokens
            if (amount > balance) revert TBL_NotEnoughTokensUnlocked(balance);
            // not locked / enough tokens
            else unlockedBalances[receiver][token] -= amount;
        }

        // interaction
        IERC20(token).safeTransfer(receiver, amount);
    }

    function unlocked(
        address owner,
        address token,
        bool fromLocks
    ) public view returns (uint256) {
        if (fromLocks) {
            uint256[] memory locks = lockedBalances[owner][token];

            uint256 ts = block.timestamp;
            uint256 pushable;
            uint256 length = locks.length;
            uint256 i;

            while (i < length) {
                (uint224 balance, uint32 lockTimestamp) = locks[i].unpack();

                if (ts > lockTimestamp) pushable += balance;
                else return pushable;

                i++;
            }

            return pushable;
        }

        return unlockedBalances[owner][token];
    }

    function locked(address owner, address token)
        public
        view
        returns (uint256)
    {
        // reads
        uint256[] memory locks = lockedBalances[owner][token];

        uint256 ts = block.timestamp;
        uint256 i = locks.length;
        uint256 unpushable;

        while (i > 0) {
            i--;

            (uint224 balance, uint32 lockTimestamp) = locks[i].unpack();

            if (ts <= lockTimestamp) unpushable += balance;
            else return unpushable;
        }

        return unpushable;
    }
}