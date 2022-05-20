// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

/// LOCAL

// libs

import "solmate/utils/SafeTransferLib.sol";

// types

import {Kernel, Module} from "src/Kernel.sol";

/// INLINED

library DEMAM_Library {
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

    function end(uint256 lock) internal pure returns (uint32) {
        return uint32(lock);
    }

    function c256(uint224 number) internal pure returns (uint256) {
        return uint256(number) << 32;
    }

    function c224(uint256 number) internal pure returns (uint224) {
        return uint224(number >> 32);
    }
}

error DEMAM_NoExtendingToShorterLock();
error DEMAM_NoMergingToShorterLock();
error DEMAM_LockDoesNotExist();
error DEMAM_LockNotOver(uint256 periodRemaining_);
error DEMAM_NotEnoughTokensUnlocked(uint256 unlocked_);
error DEMAM_NotEnoughUnlockedForSlashing(uint256 unlocked_);
error DEMAM_NotEnoughLockedForSlashing(uint256 locked_);
error DEMAM_LockExtensionPeriodIs0();
error DEMAM_TimeTooLarge();

contract DepositManagementModule is Module {
    using SafeTransferLib for ERC20;
    using DEMAM_Library for uint256;
    using DEMAM_Library for uint224;

    mapping(address => mapping(address => uint256)) public freeBalanceOf;
    mapping(address => mapping(address => uint256)) public lockedBalanceOf;
    mapping(address => mapping(address => uint256[])) public userLocks;

    constructor(address kernel_) Module(Kernel(kernel_)) {}

    function KEYCODE() public pure virtual override returns (bytes5) {
        return "DEMAM";
    }

    function takeTokens(
        address owner,
        address token,
        uint224 amount
    ) external onlyPermitted {
        // interaction
        ERC20(token).safeTransferFrom(owner, address(this), amount);

        // effect
        freeBalanceOf[owner][token] += amount;
    }

    function takeAndLockTokens(
        address owner,
        address token,
        uint224 amount,
        uint32 end
    ) external returns (uint256 lockIndex) {
        // interaction
        ERC20(token).safeTransferFrom(owner, address(this), amount);

        // eff
        return createLock(owner, token, amount, end);
    }

    function takeAndAddToLock(
        address owner,
        address token,
        uint224 amount,
        uint256 index
    ) external onlyPermitted {
        // interaction
        ERC20(token).safeTransferFrom(owner, address(this), amount);

        // effects
        mintTokensToLock(owner, token, amount, index);
    }

    function takeAndAddToLock(
        address sender,
        address recipient,
        address token,
        uint224 amount,
        uint256 index
    ) external onlyPermitted {
        // interaction
        ERC20(token).safeTransferFrom(sender, address(this), amount);

        // effects
        mintTokensToLock(recipient, token, amount, index);
    }

    function payTokens(
        address receiver,
        address token,
        uint224 amount
    ) external onlyPermitted {
        if (freeBalanceOf[receiver][token] < amount)
            revert DEMAM_NotEnoughTokensUnlocked(
                freeBalanceOf[receiver][token]
            );

        // eff
        freeBalanceOf[receiver][token] -= amount;

        // interaction
        ERC20(token).safeTransfer(receiver, amount);
    }

    function payAllUnlockedTokens(address receiver, address token) external {
        (uint224[] memory amounts, uint256[] memory indices) = findUnlocked(
            receiver,
            token
        );

        // modifier in public
        payUnlockedTokens(receiver, token, amounts, indices);
    }

    function createLock(
        address owner,
        address token,
        uint224 amount,
        uint32 end
    ) public onlyPermitted returns (uint256 lockIndex) {
        // effects
        lockedBalanceOf[owner][token] += amount;
        userLocks[owner][token].push(DEMAM_Library.pack(amount, end));

        return userLocks[owner][token].length - 1;
    }

    function payUnlockedTokens(
        address receiver,
        address token,
        uint224[] memory amounts,
        uint256[] memory indices
    ) public onlyPermitted {
        assert(amounts.length == indices.length);

        uint256 length = amounts.length;
        uint256 amount;

        for (uint256 i; i < length; i++) {
            uint256 lock = userLocks[receiver][token][indices[i]];

            if (block.timestamp <= lock.end())
                revert DEMAM_LockNotOver(lock.end() - block.timestamp);

            if (lock.c224() < amounts[i])
                revert DEMAM_NotEnoughTokensUnlocked(lock.c224());

            amount += amounts[i];
            userLocks[receiver][token][indices[i]] -= amounts[i].c256();
            lockedBalanceOf[receiver][token] -= amounts[i];
        }

        // interaction
        ERC20(token).safeTransfer(receiver, amount);
    }

    function payUnlockedTokens(
        address receiver,
        address token,
        uint224 amount,
        uint256 index
    ) public onlyPermitted {
        uint256 lock = userLocks[receiver][token][index];

        if (block.timestamp <= lock.end())
            revert DEMAM_LockNotOver(lock.end() - block.timestamp);

        if (lock.c224() < amount)
            revert DEMAM_NotEnoughTokensUnlocked(lock.c224());

        userLocks[receiver][token][index] -= amount.c256();
        lockedBalanceOf[receiver][token] -= amount;

        // interaction
        ERC20(token).safeTransfer(receiver, amount);
    }

    function lockDepositedByPeriod(
        address owner,
        address token,
        uint224 amount,
        uint32 end
    ) external onlyPermitted returns (uint256 lockIndex) {
        if (freeBalanceOf[owner][token] < amount)
            revert DEMAM_NotEnoughTokensUnlocked(freeBalanceOf[owner][token]);

        // effects
        freeBalanceOf[owner][token] -= amount;
        lockedBalanceOf[owner][token] += amount;
        userLocks[owner][token].push(DEMAM_Library.pack(amount, end));

        return userLocks[owner][token].length - 1;
    }

    function lockDepositedByIndex(
        address owner,
        address token,
        uint224 amount,
        uint256 index // modifier in mintTokensToLock
    ) external {
        if (freeBalanceOf[owner][token] < amount)
            revert DEMAM_NotEnoughTokensUnlocked(freeBalanceOf[owner][token]);

        freeBalanceOf[owner][token] -= amount;
        mintTokensToLock(owner, token, amount, index);
    }

    function slashTokens(
        address owner,
        address receiver,
        address token,
        uint224 amount
    ) external onlyPermitted {
        uint256 bal = freeBalanceOf[owner][token];

        if (bal < amount) revert DEMAM_NotEnoughUnlockedForSlashing(bal);

        freeBalanceOf[owner][token] -= amount;
        freeBalanceOf[receiver][token] += amount;
    }

    function slashLockedTokens(
        address owner,
        address receiver,
        address token,
        uint224[] memory amounts,
        uint256[] memory indices
    ) external onlyPermitted {
        assert(amounts.length == indices.length);

        uint256[] storage locks = userLocks[owner][token];
        uint256 amount;

        for (uint256 i; i < amounts.length; i++) {
            // this doesn't have errors since trusted party is
            // going to do it anyways
            locks[indices[i]] -= amounts[i].c256();
            amount += amounts[i];
        }

        lockedBalanceOf[owner][token] -= amount;
        freeBalanceOf[receiver][token] += amount;
    }

    /// @dev locks are merged to last index in indices, which needs to have the most late lock end
    function mergeLocks(
        address owner,
        address token,
        uint256[] memory indices
    ) external onlyPermitted {
        uint256[] storage locks = userLocks[owner][token];
        uint256 length = indices.length;
        uint256 maxLockTime = locks[indices[length - 1]].end();
        uint224 amount;

        for (uint256 i; i < length - 1; i++) {
            uint256 lock = locks[indices[i]];

            if (maxLockTime < lock.end()) revert DEMAM_NoMergingToShorterLock();

            amount += lock.c224();
            locks[indices[i]] = 0 << 32; // only empty amount
        }

        locks[indices[length - 1]] += amount.c256();
    }

    function extendLock(
        address owner,
        address token,
        uint256 index,
        uint32 end
    ) external onlyPermitted {
        uint256 lock = userLocks[owner][token][index];

        if (type(uint32).max < end) revert DEMAM_TimeTooLarge();

        if (end < lock.end()) revert DEMAM_NoExtendingToShorterLock();

        userLocks[owner][token][index] = DEMAM_Library.pack(lock.c224(), end);
    }

    function mintTokens(
        address receiver,
        address token,
        uint224 amount
    ) public onlyPermitted {
        freeBalanceOf[receiver][token] += amount;
    }

    function mintTokensToLock(
        address receiver,
        address token,
        uint224 amount,
        uint256 index
    ) public onlyPermitted {
        if (userLocks[receiver][token][index].end() < block.timestamp)
            revert DEMAM_LockDoesNotExist();

        lockedBalanceOf[receiver][token] += amount;
        userLocks[receiver][token][index] += amount.c256();
    }

    function getUserLocks(address owner, address token)
        external
        view
        returns (uint256[] memory)
    {
        return userLocks[owner][token];
    }

    function getUserLockBalance(
        address owner,
        address token,
        uint256 index
    ) external view returns (uint224) {
        return getUserLock(owner, token, index).c224();
    }

    function getUserLockEnd(
        address owner,
        address token,
        uint256 index
    ) external view returns (uint32) {
        return getUserLock(owner, token, index).end();
    }

    function getUserLock(
        address owner,
        address token,
        uint256 index
    ) public view returns (uint256) {
        return userLocks[owner][token][index];
    }

    function findUnlocked(address owner, address token)
        public
        view
        returns (uint224[] memory amounts, uint256[] memory indices)
    {
        uint256[] memory locks = userLocks[owner][token];
        uint256 length = locks.length;

        uint256[] memory indicesPadded = new uint256[](length);
        uint224[] memory amountsPadded = new uint224[](length);

        uint256 ts = block.timestamp;
        uint256 i;
        uint256 j;

        while (i < length) {
            (uint224 balance, uint32 lockTimestamp) = locks[i].unpack();

            if (lockTimestamp < ts) {
                indicesPadded[j] = i;
                amountsPadded[j] = balance;
                j++;
            }

            i++;
        }

        indices = new uint256[](j);
        amounts = new uint224[](j);

        for (uint256 k; k < j; k++) {
            indices[k] = indicesPadded[k];
            amounts[k] = amountsPadded[k];
        }
    }

    function presentlyUnlockedBalanceOf(address owner, address token)
        public
        view
        returns (uint256)
    {
        uint256[] memory locks = userLocks[owner][token];

        uint256 i;
        uint224 free;
        uint256 length = locks.length;
        uint256 ts = block.timestamp;

        while (i < length) {
            (uint224 balance, uint32 lockTimestamp) = locks[i].unpack();

            if (lockTimestamp < ts) free += balance;

            i++;
        }

        return free;
    }

    function presentlyLockedBalanceOf(address owner, address token)
        public
        view
        returns (uint256)
    {
        // reads
        uint256[] memory locks = userLocks[owner][token];

        uint256 ts = block.timestamp;
        uint256 i = locks.length;
        uint224 locked;

        while (0 < i) {
            i--;

            (uint224 balance, uint32 lockTimestamp) = locks[i].unpack();

            if (ts <= lockTimestamp) locked += balance;
        }

        return locked;
    }
}
