// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

/// DEPS

import "solmate/auth/Auth.sol";

/// LOCAL

// types

import {Kernel, Policy} from "src/Kernel.sol";
import "src/modules/DEMAM.sol";
import "src/modules/VOPOM.sol";

/// INLINED

enum PoolType {
    CLOSED,
    OPEN,
    DARK
}

struct DepositData {
    address user;
    uint48 idLock;
    uint48 idPool;
}

error LockingVault_PoolClosed(uint256 pool_);
error LockingVault_TokenNotAccepted(uint256 pool_, address token_);
error LockingVault_LockNotExpired(uint256 lockEnd_);
error LockingVault_LockExpired(uint32 timestamp_, uint32 unlockTime_);
error LockingVault_UnlockTimeNotAccepted(uint32 lockTime_);
error LockingVault_NotAllowedForPool(uint256 pool_, address sender_);
error LockingVault_InvalidPoolDataId(uint256 depositId_);
error LockingVault_LockDoesNotExist(uint256 depositId_);
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

    // user unique id -> user lock deposit
    // demam is linear and vopom is constant on purpose
    // because it is expected if you want to withdraw that you
    // do not want to cuck your own deposit, but you might want to
    // cuck voting, so it makes sense from a design perspective to do above
    mapping(uint256 => DepositData) public getDepositDataForUniqueId;

    constructor(address kernel_)
        Auth(kernel_, Authority(address(0)))
        Policy(Kernel(kernel_))
    {}

    function configureReads() external virtual override onlyKernel {
        setAuthority(Authority(getModuleAddress("AUTHZ")));
        demam = DepositManagementModule(getModuleAddress("DEMAM"));
        vopom = VotingPowerModule(getModuleAddress("VOPOM"));
    }

    function requestWrites()
        external
        pure
        virtual
        override
        returns (bytes5[] memory permissions)
    {
        permissions = new bytes5[](2);
        permissions[0] = "DEMAM";
        permissions[1] = "VOPOM";
    }

    function lockTokens(
        address token,
        uint224 amount,
        uint256 poolId,
        uint32 unlockTime
    ) external virtual returns (uint256 tokenLockId, uint256 depositId) {
        int32 epochedUnlockTime = calcEpochedTime(unlockTime);

        /// token interactions
        /// will revert on stuff
        tokenLockId = demam.takeAndLockTokens(
            msg.sender,
            token,
            amount,
            epochedUnlockTime.c32i32u()
        );

        //// only now handle pool
        //// will also revert etc.
        depositId = _notifyLockCreation(
            token,
            poolId,
            amount.cui(),
            epochedUnlockTime
        );

        // effects
        getDepositDataForUniqueId[depositId] = DepositData(
            msg.sender,
            tokenLockId.cu48u(),
            poolId.cu48u()
        );
    }

    function transferTokensBetweenLocks(
        address token,
        uint256 reducedDepositId,
        uint256 targetPoolId,
        uint256 increasedDepositId,
        uint224 amount
    ) external virtual returns (uint256 newTokenLockId, uint256 newDepositId) {
        // reads
        DepositData memory deposit = getDepositDataForUniqueId[
            reducedDepositId
        ];

        uint256 lock = demam.getUserLock(msg.sender, token, deposit.idLock);
        uint224 balance = lock.cu224ushr(32);
        uint32 unlockTime = lock.cu32u();

        uint32 timestamp = block.timestamp.cu32u();

        // checks
        if (deposit.user != msg.sender)
            revert LockingVault_InvalidPoolDataId(reducedDepositId);

        if (unlockTime < timestamp)
            revert LockingVault_LockExpired(timestamp, unlockTime);

        // balance check is in demam on slashing

        // effects

        // first note change greedily
        vopom.noteLockBalanceChange(
            msg.sender,
            deposit.idPool,
            reducedDepositId,
            balance.cui(),
            (balance - amount).cui(),
            unlockTime.cu32i()
        );

        if (increasedDepositId == 0) {
            // then move balance into _new_ lock
            newTokenLockId = _moveSomeToNewLock(
                token,
                deposit.idLock,
                amount,
                unlockTime
            );

            // then notify lock creation
            newDepositId = _notifyLockCreation(
                token,
                targetPoolId,
                amount.cui(),
                unlockTime.cu32i()
            );

            // effects
            getDepositDataForUniqueId[newDepositId] = DepositData(
                msg.sender,
                newTokenLockId.cu48u(),
                targetPoolId.cu48u()
            );
        } else {
            // we will need current data
            // update lock so we can keep old data
            // yes, lock has diff meaning now
            lock = deposit.idLock;
            deposit = getDepositDataForUniqueId[increasedDepositId];
            balance = demam.getUserLockBalance(
                msg.sender,
                token,
                deposit.idLock
            );

            // check
            if (deposit.user != msg.sender || targetPoolId != deposit.idPool)
                revert LockingVault_InvalidPoolDataId(increasedDepositId);

            // update returns
            newDepositId = increasedDepositId;
            newTokenLockId = lock;

            // now move
            _moveSomeToLock(token, lock, deposit.idLock, amount, unlockTime);

            // and finally notify balance change
            vopom.noteLockBalanceChange(
                msg.sender,
                targetPoolId,
                increasedDepositId,
                balance.cui(), // old bal
                (balance + amount).cui(), // new bal
                unlockTime.cu32i()
            );
        }
    }

    function addToLock(
        address token,
        uint256 depositId,
        uint224 amount
    ) external virtual {
        DepositData memory deposit = getDepositDataForUniqueId[depositId];
        uint256 lock = demam.getUserLock(msg.sender, token, deposit.idLock);
        uint32 timestamp = block.timestamp.cu32u();
        uint32 end = lock.cu32u();
        uint224 oldAmount = lock.cu224ushr(32);

        // checks
        // we don't require depositor is owner
        // but does need to exist
        if (deposit.user == address(0))
            revert LockingVault_LockDoesNotExist(depositId);

        if (end < timestamp) revert LockingVault_LockExpired(timestamp, end);

        // logic
        demam.takeAndAddToLock(
            msg.sender,
            deposit.user,
            token,
            amount,
            deposit.idLock
        );

        vopom.noteLockBalanceChange(
            deposit.user,
            deposit.idPool,
            depositId,
            oldAmount.cui(),
            (oldAmount + amount).cui(),
            end.c32u32i()
        );
    }

    function extendLock(
        address token,
        uint256 depositId,
        uint32 newUnlockTime
    ) external virtual returns (int32 newEpochedUnlockTime) {
        // Reads
        newEpochedUnlockTime = calcEpochedTime(newUnlockTime);
        DepositData memory deposit = getDepositDataForUniqueId[depositId];
        uint256 lock = demam.getUserLock(msg.sender, token, deposit.idLock);

        // checks

        if (deposit.user != msg.sender)
            revert LockingVault_InvalidPoolDataId(depositId);

        // effects

        demam.extendLock(
            msg.sender,
            token,
            deposit.idLock,
            newEpochedUnlockTime.c32i32u()
        );

        vopom.noteLockExtension(
            msg.sender,
            deposit.idPool,
            depositId,
            lock.cuishr(32),
            lock.cu32i(),
            newEpochedUnlockTime
        );
    }

    function unlockTokens(
        address token,
        uint256 lockId,
        uint224 amount
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
        uint256[] memory depositIds
    ) external virtual requiresAuth {
        uint256 l = depositIds.length;

        DepositData[] memory deposits = new DepositData[](l);
        uint256[] memory locksBeforeSlash = new uint256[](l);
        uint256[] memory lockIds = new uint256[](l);

        for (uint256 i; i < l; i++) {
            deposits[i] = getDepositDataForUniqueId[depositIds[i]];

            locksBeforeSlash[i] = demam.getUserLock(
                owner,
                token,
                deposits[i].idLock
            );

            lockIds[i] = deposits[i].idLock;
        }

        demam.slashLockedTokens(owner, receiver, token, amounts, lockIds);

        for (uint256 i; i < l; i++) {
            int256 balance = demam
                .getUserLockBalance(owner, token, deposits[i].idLock)
                .cui();

            vopom.noteLockBalanceChange(
                owner,
                deposits[i].idPool,
                depositIds[i],
                locksBeforeSlash[i].cuishr(32),
                balance,
                locksBeforeSlash[i].cu32i()
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

    function getDepositDataForId(uint256 idDeposit)
        public
        view
        returns (DepositData memory)
    {
        return getDepositDataForUniqueId[idDeposit];
    }

    function getLockIdForDepositId(uint256 idDeposit)
        public
        view
        returns (uint48 idLock)
    {
        return getDepositDataForUniqueId[idDeposit].idLock;
    }

    function getPoolIdForDepositId(uint256 idDeposit)
        public
        view
        returns (uint48 idPool)
    {
        return getDepositDataForUniqueId[idDeposit].idPool;
    }

    function calcEpochedTime(uint32 intendedUnlockTime)
        public
        pure
        virtual
        returns (int32 epochedUnlockTime)
    {
        return intendedUnlockTime.c32u32i().epochify();
    }

    function _moveSomeToNewLock(
        address token,
        uint256 slashLockId,
        uint224 amount,
        uint32 unlockTime
    ) internal returns (uint256 newLockId) {
        uint224[] memory amounts = new uint224[](1);
        uint256[] memory ids = new uint256[](1);
        amounts[0] = amount;
        ids[0] = slashLockId;

        // a burn is just an addr 0 slash
        demam.slashLockedTokens(msg.sender, address(0), token, amounts, ids);
        return demam.createLock(msg.sender, token, amount, unlockTime);
    }

    function _moveSomeToLock(
        address token,
        uint256 slashLockId,
        uint256 addLockId,
        uint224 amount,
        uint32 unlockTime
    ) internal {
        // reads
        uint224[] memory amounts = new uint224[](1);
        uint256[] memory ids = new uint256[](1);
        amounts[0] = amount;
        ids[0] = slashLockId;

        // checks
        if (demam.getUserLockEnd(msg.sender, token, addLockId) <= unlockTime)
            revert LockingVault_NoMovingToShorterLock();

        // eff
        // a burn is just an addr 0 slash
        demam.slashLockedTokens(msg.sender, address(0), token, amounts, ids);
        demam.mintTokensToLock(msg.sender, token, amount, addLockId);
    }

    function _notifyLockCreation(
        address token,
        uint256 pool,
        int256 amount,
        int32 epochedUnlockTime
    ) internal returns (uint256 depositId) {
        /// Reads
        PoolType ptype = getTypeForPool[pool];

        /// Checks
        if (ptype == PoolType.CLOSED) revert LockingVault_PoolClosed(pool);
        else if (ptype == PoolType.DARK)
            if (!mayDepositForPool[pool][msg.sender])
                revert LockingVault_NotAllowedForPool(pool, msg.sender);

        if (!isPoolToken[pool][token])
            revert LockingVault_TokenNotAccepted(pool, token);

        depositId = vopom.noteLockCreation(
            msg.sender,
            pool,
            amount,
            epochedUnlockTime
        );
    }
}
