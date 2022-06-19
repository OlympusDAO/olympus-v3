// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

/// DEPS

import "solmate/auth/Auth.sol";

/// LOCAL

// types

import "src/Kernel.sol";
import "src/modules/DEMAM.sol";
import "src/modules/VOPOM.sol";

/// INLINED

enum PoolType {
    CLOSED,
    OPEN,
    DARK
}

error LockingVault_PoolClosed(uint256 pool_);
error LockingVault_TokenNotAccepted(uint256 pool_, address token_);
error LockingVault_LockExpired(uint32 timestamp_, uint32 unlockTime_);
error LockingVault_NotAllowedForPool(uint256 pool_, address sender_);
error LockingVault_NoMovingToShorterLock();

contract LockingVault is Auth, Policy {
    using VOPOM_Library for int32;
    using convert for *;

    DepositManagementModule public demam;
    VotingPowerModule public vopom;

    // either does not exist, open or dark
    mapping(uint256 => PoolType) public getTypeForPool;

    // whether pool allows address
    mapping(uint256 => mapping(address => bool)) public mayDepositForPool;

    // whether pools allows token
    mapping(uint256 => mapping(address => bool)) public isPoolToken;

    constructor(address kernel_)
        Auth(kernel_, Authority(address(0)))
        Policy(Kernel(kernel_))
    {}

    function configureReads() external virtual override onlyKernel {
        setAuthority(Authority(getModuleAddress("AUTHR")));
        demam = DepositManagementModule(getModuleAddress("DEMAM"));
        vopom = VotingPowerModule(getModuleAddress("VOPOM"));
    }

    function requestRoles()
        external
        view
        virtual
        override
        returns (Kernel.Role[] memory roles)
    {
        roles = new Kernel.Role[](2);
        roles[0] = demam.EDITOR();
        roles[1] = demam.SENDER();
        roles[2] = demam.GODMODE();
        roles[3] = vopom.REPORTER();
    }

    function lockTokens(
        address token,
        uint128 amount,
        uint64 poolId,
        uint32 unlock
    ) external virtual returns (uint256 lockId) {
        int32 epochedUnlock = calcEpochedTime(unlock);
        uint256 comparisonId;

        /// token interactions
        /// will revert on stuff
        lockId = demam.takeAndLockTokens(
            msg.sender,
            token,
            amount,
            epochedUnlock.c32i32u()
        );

        //// only now handle pool
        //// will also revert etc.
        comparisonId = _notifyLockCreation(
            token,
            poolId,
            amount.cu128i(),
            epochedUnlock
        );

        assert(comparisonId == lockId);
    }

    function transferTokensToNewLock(
        address token,
        uint256 lockId,
        uint64 poolId,
        uint128 amount,
        uint32 newUnlock
    ) external virtual returns (uint256 newLockId) {
        // reads
        DepositManagementModule.Lock memory lock = demam.getUserLock(
            msg.sender,
            token,
            lockId
        );

        uint128 balance = lock.balance.cu128u();
        uint32 unlock = lock.end;
        uint32 timestamp = block.timestamp.cu32u();
        int32 newEpochedUnlock = calcEpochedTime(newUnlock);

        // checks
        // balance is checked in move
        // new lock time is checked in VOPOM

        // effects

        // first note change greedily
        // but if lock has passed then irrelevant
        if (timestamp <= unlock)
            vopom.noteLockBalanceChange(
                msg.sender,
                lockId,
                balance.cu128i(),
                (balance - amount).cu128i(),
                unlock.cu32i()
            );

        // then move balance into _new_ lock
        newLockId = _moveSomeToNewLock(
            token,
            lockId,
            amount,
            newEpochedUnlock.c32i32u()
        );

        // then notify lock creation
        lockId = _notifyLockCreation(
            token,
            poolId,
            amount.cu128i(),
            newEpochedUnlock
        );

        assert(newLockId == lockId);
    }

    function transferTokensToExistingLock(
        address token,
        uint256 reducedLockId,
        uint256 increasedLockId,
        uint128 amount
    ) external virtual {
        /////// reads
        DepositManagementModule.Lock memory lock = demam.getUserLock(
            msg.sender,
            token,
            reducedLockId
        );

        uint128 balance = lock.balance.cu128u();
        uint32 unlock = lock.end;
        uint32 timestamp = block.timestamp.cu32u();

        /////// checks

        // balance check is in demam on slashing

        /////// effects

        // first note change greedily
        // if, again, it needs to be noted
        // we can transfer from expired into existing lock
        if (timestamp <= unlock)
            vopom.noteLockBalanceChange(
                msg.sender,
                reducedLockId,
                balance.cu128i(),
                (balance - amount).cu128i(),
                unlock.cu32i()
            );

        /////// reads
        // get all data again

        lock = demam.getUserLock(msg.sender, token, increasedLockId);
        balance = lock.balance.cu128u();
        uint32 secondUnlock = lock.end;

        /////// checks

        if (secondUnlock < timestamp)
            revert LockingVault_LockExpired(secondUnlock, timestamp);

        if (secondUnlock < unlock) revert LockingVault_NoMovingToShorterLock();

        /////// effects

        // move
        _moveSomeToLock(token, reducedLockId, increasedLockId, amount);

        // notify balance change
        vopom.noteLockBalanceChange(
            msg.sender,
            increasedLockId,
            balance.cu128i(), // old bal
            (balance + amount).cu128i(), // new bal
            secondUnlock.cu32i()
        );
    }

    function addToLock(
        address beneficiary,
        address token,
        uint256 lockId,
        uint128 amount
    ) external virtual {
        // reads
        DepositManagementModule.Lock memory lock = demam.getUserLock(
            beneficiary,
            token,
            lockId
        );

        uint128 oldAmount = lock.balance.cu128u();
        uint32 end = lock.end;
        uint32 timestamp = block.timestamp.cu32u();

        // checks
        if (end < timestamp) revert LockingVault_LockExpired(timestamp, end);

        // logic
        demam.takeAndAddToLock(msg.sender, beneficiary, token, amount, lockId);

        vopom.noteLockBalanceChange(
            beneficiary,
            lockId,
            oldAmount.cu128i(),
            (oldAmount + amount).cu128i(),
            end.c32u32i()
        );
    }

    function extendLock(
        address token,
        uint256 lockId,
        uint32 newUnlock
    ) external virtual returns (int32 newEpochedUnlock) {
        // Reads
        newEpochedUnlock = calcEpochedTime(newUnlock);
        DepositManagementModule.Lock memory lock = demam.getUserLock(
            msg.sender,
            token,
            lockId
        );

        // checks

        // TODO: think

        // effects
        demam.extendLock(msg.sender, token, lockId, newEpochedUnlock.c32i32u());

        vopom.noteLockExtension(
            msg.sender,
            lockId,
            lock.balance.cu128i(),
            lock.end.cu32i(),
            newEpochedUnlock
        );
    }

    function unlockTokens(
        address token,
        uint256 lockId,
        uint128 amount
    ) external virtual {
        // revert for token amount and for lock end is inside
        // balances are first decremented before transfer happens
        // it is not necessary to inform vopom since voting power
        // naturally dissipates
        demam.payUnlockedTokens(msg.sender, token, amount, lockId);
    }

    function slashLockedTokens(
        address owner,
        address receiver,
        address token,
        uint224[] memory amounts,
        uint256[] memory lockIds
    ) external virtual requiresAuth {
        uint256 l = lockIds.length;

        DepositManagementModule.Lock[]
            memory locksBeforeSlash = new DepositManagementModule.Lock[](l);

        for (uint256 i; i < l; i++) {
            locksBeforeSlash[i] = demam.getUserLock(owner, token, lockIds[i]);
        }

        demam.slashLockedTokens(owner, receiver, token, amounts, lockIds);

        for (uint256 i; i < l; i++) {
            DepositManagementModule.Lock memory lockBefore = locksBeforeSlash[
                i
            ];
            int128 balBefore = lockBefore.balance.cu128i();

            vopom.noteLockBalanceChange(
                owner,
                lockIds[i],
                balBefore,
                balBefore - amounts[i].cu128i(),
                lockBefore.end.cu32i()
            );
        }
    }

    function openPool(uint256 pool, bool dark) external virtual requiresAuth {
        getTypeForPool[pool] = dark ? PoolType.DARK : PoolType.OPEN;
    }

    function closePool(uint256 pool) external virtual requiresAuth {
        getTypeForPool[pool] = PoolType.CLOSED;
    }

    function makePoolToken(uint256 pool, address token)
        external
        virtual
        requiresAuth
    {
        isPoolToken[pool][token] = true;
    }

    function grantDarkPoolEntry(address user, uint256 darkPool)
        external
        virtual
        requiresAuth
    {
        mayDepositForPool[darkPool][user] = true;
    }

    function revokeDarkPoolEntry(address user, uint256 darkPool)
        external
        virtual
        requiresAuth
    {
        mayDepositForPool[darkPool][user] = false;
    }

    // kill fn
    function setOwner(address) public virtual override {}

    function getPoolIdForLock(address user, uint256 lockId)
        public
        view
        returns (uint64 idPool)
    {
        return vopom.getUserPointPoolId(user, lockId);
    }

    function calcEpochedTime(uint32 intendedUnlock)
        public
        pure
        virtual
        returns (int32 epochedUnlock)
    {
        return intendedUnlock.c32u32i().epochify();
    }

    function _moveSomeToNewLock(
        address token,
        uint256 slashLockId,
        uint128 amount,
        uint32 unlock
    ) internal returns (uint256 newLockId) {
        _slashLockedTokens(token, slashLockId, amount);
        return demam.createLock(msg.sender, token, amount, unlock);
    }

    function _moveSomeToLock(
        address token,
        uint256 slashLockId,
        uint256 addLockId,
        uint128 amount
    ) internal {
        _slashLockedTokens(token, slashLockId, amount);
        demam.mintTokensToLock(msg.sender, token, amount, addLockId);
    }

    function _slashLockedTokens(
        address token,
        uint256 slashLockId,
        uint224 amount
    ) internal {
        // reads
        uint224[] memory amounts = new uint224[](1);
        uint256[] memory ids = new uint256[](1);
        amounts[0] = amount;
        ids[0] = slashLockId;

        // eff
        // a burn is just an addr 0 slash
        demam.slashLockedTokens(msg.sender, address(0), token, amounts, ids);
    }

    function _notifyLockCreation(
        address token,
        uint64 pool,
        int128 amount,
        int32 epochedUnlock
    ) internal returns (uint256 lockId) {
        /// Reads
        PoolType ptype = getTypeForPool[pool];
        bool isDark = ptype == PoolType.DARK;

        /// Checks
        if (ptype == PoolType.CLOSED) revert LockingVault_PoolClosed(pool);
        else if (isDark)
            if (!mayDepositForPool[pool][msg.sender])
                revert LockingVault_NotAllowedForPool(pool, msg.sender);

        if (!isPoolToken[pool][token])
            revert LockingVault_TokenNotAccepted(pool, token);

        lockId = vopom.noteLockCreation(
            msg.sender,
            pool,
            amount,
            epochedUnlock
        );

        if (!isDark) vopom.noteOpenPoolPointAddition(msg.sender, lockId);
    }
}
