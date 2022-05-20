// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

/// DEPS

import "test-utils/convert.sol";

/// LOCAL

// libs

import "prb-math/PRBMathSD59x18.sol";

// types

import {Kernel, Module} from "src/Kernel.sol";

// INLINED

int256 constant VOPOM_SCALE = 1e18;
int32 constant VOPOM_WEEK = 7 * 24 * 3600;

library VOPOM_Library {
    function epochify(int32 time) internal pure returns (int32 epoched) {
        return (time / VOPOM_WEEK) * VOPOM_WEEK;
    }
}

struct Point {
    int256 bias;
    int256 slope;
    int128 period;
    int128 tst;
}

struct VoteConfig {
    int128 multiplier;
    int128 maxlock;
}

struct Lock {
    int256 balance;
    int256 end;
}

error VOPOM_ZeroLock();
error VOPOM_NoLockFound();
error VOPOM_LockExpired();
error VOPOM_LockTooLong();
error VOPOM_LockTooShort();
error VOPOM_ValueScaleLow();
error VOPOM_OnlyLockExtensions();
error VOPOM_UnlockTimeNotEpoched();
error VOPOM_UnlockCouldNotHaveHappened();
error VOPOM_AlreadyConfiguredFor(uint256 poolId_);
error VOPOM_VotingNotConfiguredFor(uint256 poolId_);

contract VotingPowerModule is Module {
    using VOPOM_Library for int32;
    using PRBMathSD59x18 for int256;
    using PRBMath for int256;
    using convert for *;

    mapping(uint256 => VoteConfig) public configurations;

    mapping(uint256 => Point) public globalPointSet;

    mapping(uint256 => mapping(int256 => int256)) public slopeChanges;

    mapping(address => mapping(uint256 => Point)) public userPointSets;

    uint256 public nextUniquePointId;

    constructor(address kernel_) Module(Kernel(kernel_)) {
        nextUniquePointId = 1;
    }

    function KEYCODE() public pure virtual override returns (bytes5) {
        return "VOPOM";
    }

    function configureUniquely(
        uint256 poolId,
        int128 multiplier,
        int128 maxLock
    ) external onlyPermitted {
        VoteConfig memory config = configurations[poolId];

        if (0 < config.maxlock + config.multiplier)
            revert VOPOM_AlreadyConfiguredFor(poolId);

        if (multiplier < VOPOM_SCALE) revert VOPOM_ValueScaleLow();

        configurations[poolId] = VoteConfig(multiplier, maxLock);
    }

    function checkpoint(uint256 poolId) external {
        _checkpoint(address(0), poolId, 0, Lock(0, 0), Lock(0, 0));
    }

    function noteLockCreation(
        address user,
        uint256 poolId,
        int256 balance,
        int32 epochedUnlockTime
    ) external onlyPermitted returns (uint256 uniquePointId) {
        uniquePointId = nextUniquePointId;
        int256 timestamp = block.timestamp.cui();

        if (epochedUnlockTime % VOPOM_WEEK != 0)
            revert VOPOM_UnlockTimeNotEpoched();

        if (epochedUnlockTime < timestamp + VOPOM_WEEK)
            revert VOPOM_LockTooShort();

        if (timestamp + configurations[poolId].maxlock < epochedUnlockTime)
            revert VOPOM_LockTooLong();

        if (balance == 0) revert VOPOM_ZeroLock();

        _noteLock(
            user,
            poolId,
            uniquePointId,
            0,
            balance,
            0,
            epochedUnlockTime
        );

        nextUniquePointId++;
    }

    function noteLockBalanceChange(
        address user,
        uint256 poolId,
        uint256 pointId,
        int256 oldBalance,
        int256 newBalance,
        int32 epochedUnlockTime
    ) external onlyPermitted {
        if (userPointSets[user][pointId].tst == 0) revert VOPOM_NoLockFound();

        if (epochedUnlockTime <= block.timestamp.cui())
            revert VOPOM_LockExpired();

        _noteLock(
            user,
            poolId,
            pointId,
            oldBalance,
            newBalance,
            epochedUnlockTime,
            epochedUnlockTime
        );
    }

    function noteLockExtension(
        address user,
        uint256 poolId,
        uint256 pointId,
        int256 balance,
        int32 oldEpochedUnlockTime,
        int32 newEpochedUnlockTime
    ) external onlyPermitted {
        int256 timestamp = block.timestamp.cui();

        if (newEpochedUnlockTime % VOPOM_WEEK != 0)
            revert VOPOM_UnlockTimeNotEpoched();

        if (newEpochedUnlockTime < timestamp) revert VOPOM_LockTooShort();

        if (newEpochedUnlockTime < oldEpochedUnlockTime)
            revert VOPOM_OnlyLockExtensions();

        if (timestamp + configurations[poolId].maxlock < newEpochedUnlockTime)
            revert VOPOM_LockTooLong();

        _noteLock(
            user,
            poolId,
            pointId,
            balance,
            balance,
            oldEpochedUnlockTime,
            newEpochedUnlockTime
        );
    }

    function getVotingPowerShare(
        address user,
        uint256 poolId,
        uint256 pointId
    ) public view returns (int256 fixedPointSharePercent) {
        int256 glvp = getGlobalVotingPower(poolId);
        if (glvp > 0) return getVotingPower(user, pointId).div(glvp);
        else return 0;
    }

    function getVotingPowerShare(
        address user,
        uint256[] memory poolIds,
        uint256[] memory pointIds
    ) public view returns (int256 fixedPointSharePercent) {
        uint256 length = poolIds.length;
        int256 glvp;
        int256 vp;

        for (uint256 i; i < length; i++) {
            glvp += getGlobalVotingPower(poolIds[i]);
        }

        length = pointIds.length;

        for (uint256 i; i < length; i++) {
            vp += getVotingPower(user, pointIds[i]);
        }

        if (glvp > 0) return vp.div(glvp);
        else return 0;
    }

    function getVotingPower(address user, uint256 pointId)
        public
        view
        returns (int256 votingPower)
    {
        // get user point
        Point memory upoint = userPointSets[user][pointId];
        // check if exists
        if (upoint.tst == 0) revert VOPOM_NoLockFound();
        // decrement bias passed on time passing and slope
        upoint.bias -= upoint.slope * (block.timestamp.cui() - upoint.tst);
        // if neg passed, so 0
        if (upoint.bias < 0) return 0;
        // return
        return upoint.bias;
    }

    function getGlobalVotingPower(uint256 poolId)
        public
        view
        returns (int256 globalVotingPower)
    {
        // get point
        Point memory glpoint = globalPointSet[poolId];
        // decrement bias passed on time passing and slope
        glpoint.bias -= glpoint.slope * (block.timestamp.cui() - glpoint.tst);
        // if neg passed, so 0
        if (glpoint.bias < 0) return 0;
        // return
        return glpoint.bias;
    }

    function isOpenPool(uint256 poolId) public view returns (bool) {
        return getGlobalPoint(poolId).tst != 0;
    }

    function isOnceNotedPoint(address user, uint256 pointId)
        public
        view
        returns (bool)
    {
        return getUserPoint(user, pointId).tst != 0;
    }

    function getMaximumLockTime(uint256 poolId) public view returns (int128) {
        return configurations[poolId].maxlock;
    }

    function getMultiplier(uint256 poolId) public view returns (int128) {
        return configurations[poolId].multiplier;
    }

    function getGlobalPoint(uint256 poolId)
        public
        view
        returns (Point memory point)
    {
        return globalPointSet[poolId];
    }

    function getUserPoint(address user, uint256 pointId)
        public
        view
        returns (Point memory userPoint)
    {
        return userPointSets[user][pointId];
    }

    function getEpochTime() public view returns (int256) {
        return block.timestamp.cui32().epochify();
    }

    function _noteLock(
        address user,
        uint256 poolId,
        uint256 pointId,
        int256 oldAmount,
        int256 newAmount,
        int32 oldUnlockTime,
        int32 newUnlockTime
    ) internal {
        Lock memory oldLocked = Lock(oldAmount, oldUnlockTime);
        Lock memory newLocked = Lock(newAmount, newUnlockTime);

        if (configurations[poolId].maxlock == 0)
            revert VOPOM_VotingNotConfiguredFor(poolId);

        _checkpoint(user, poolId, pointId, oldLocked, newLocked);
    }

    function _checkpoint(
        address user,
        uint256 poolId,
        uint256 pointId,
        Lock memory oldLocked,
        Lock memory newLocked
    ) internal {
        int128 timestamp = int128(block.timestamp.cui());

        Point memory pointOld;
        Point memory pointNew;

        int256 dSlopeOld;
        int256 dSlopeNew;

        // The following calculates the new + old user slopes
        // new slopes are used for indicating total slope change
        // and calculating biases
        // biases are actual voting power
        {
            if (user != address(0)) {
                VoteConfig memory config = configurations[poolId];
                int128 period = userPointSets[user][pointId].period;

                if (oldLocked.end > timestamp && oldLocked.balance > 0) {
                    // slope basic
                    pointOld.slope = oldLocked.balance / config.maxlock;

                    // then multiplier calcs
                    // always use period
                    pointOld.slope =
                        pointOld.slope.mul(config.multiplier * period) /
                        config.maxlock;

                    // then bias
                    pointOld.bias =
                        pointOld.slope *
                        (oldLocked.end - timestamp);
                }

                if (newLocked.end > timestamp && newLocked.balance > 0) {
                    // slope basic
                    pointNew.slope = newLocked.balance / config.maxlock;

                    // check if stored period should be calculated
                    if (period == 0)
                        pointNew.period = int128(newLocked.end - timestamp);
                    else pointNew.period = period;

                    // then multiplier calcs
                    pointNew.slope =
                        pointNew.slope.mul(
                            config.multiplier * pointNew.period
                        ) /
                        config.maxlock;

                    // then bias
                    pointNew.bias =
                        pointNew.slope *
                        (newLocked.end - timestamp);

                    // add timestamp
                    pointNew.tst = timestamp;
                }

                dSlopeOld = slopeChanges[poolId][oldLocked.end];

                if (newLocked.end != 0)
                    if (newLocked.end == oldLocked.end) dSlopeNew = dSlopeOld;
                    else dSlopeNew = slopeChanges[poolId][newLocked.end];
            }
        }

        Point memory pointLast;

        if (globalPointSet[poolId].tst != 0) pointLast = globalPointSet[poolId];
        else pointLast = Point({bias: 0, slope: 0, period: 0, tst: timestamp});

        int256 lastEpochTime = pointLast.tst;
        int256 rollingEpochTime = int32(lastEpochTime).epochify();

        for (uint256 i; i < 64; i++) {
            int256 dSlope = 0;

            rollingEpochTime += VOPOM_WEEK;

            if (timestamp < rollingEpochTime) rollingEpochTime = timestamp;
            else dSlope = slopeChanges[poolId][rollingEpochTime];

            pointLast.bias -=
                pointLast.slope *
                (rollingEpochTime - lastEpochTime);

            pointLast.slope += dSlope;

            if (pointLast.bias < 0) pointLast.bias = 0;

            if (pointLast.slope < 0) pointLast.slope = 0;

            lastEpochTime = rollingEpochTime;

            if (rollingEpochTime == timestamp) break;
        }

        if (user != address(0)) {
            // calculate slopes and biases for the global point,
            // those are the differences of the new and old user point
            pointLast.slope += pointNew.slope - pointOld.slope;
            pointLast.bias += pointNew.bias - pointOld.bias;

            // check for underflow
            if (pointLast.slope < 0) pointLast.slope = 0;
            if (pointLast.bias < 0) pointLast.bias = 0;
        }

        pointLast.tst = timestamp;

        globalPointSet[poolId] = pointLast;

        if (user != address(0)) {
            if (timestamp < oldLocked.end) {
                dSlopeOld += pointOld.slope;

                if (newLocked.end == oldLocked.end) dSlopeOld -= pointNew.slope;

                slopeChanges[poolId][oldLocked.end] = dSlopeOld;
            }

            if (timestamp < newLocked.end) {
                if (oldLocked.end < newLocked.end) {
                    dSlopeNew -= pointNew.slope;
                    slopeChanges[poolId][newLocked.end] = dSlopeNew;
                }
            }

            userPointSets[user][pointId] = pointNew;
        }
    }
}
