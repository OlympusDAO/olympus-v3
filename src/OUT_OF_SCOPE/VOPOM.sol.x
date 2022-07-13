// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.13;

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

error VOPOM_ZeroLock();
error VOPOM_NoLockFound();
error VOPOM_LockExpired();
error VOPOM_LockTooLong();
error VOPOM_LockTooShort();
error VOPOM_ValueScaleLow();
error VOPOM_OnlyLockExtensions();
error VOPOM_UnlockTimeNotEpoched();
error VOPOM_UnlockCouldNotHaveHappened();
error VOPOM_AlreadyConfiguredFor(uint64 poolId_);
error VOPOM_VotingNotConfiguredFor(uint64 poolId_);
error VOPOM_InvalidBiasPercentForDelegation(
    int128 biasPercent_,
    int128 totalPercentDelegated_
);

contract VotingPowerModule is Module {
    using VOPOM_Library for int32;
    using PRBMathSD59x18 for *;
    using PRBMath for *;
    using convert for *;

    struct Point {
        int128 bias;
        int128 slope;
        uint64 poolId;
        int64 period;
        int128 tst;
    }

    struct VoteConfig {
        int128 multiplier;
        int128 maxlock;
    }

    struct Lock {
        int128 balance;
        int128 end;
    }

    Kernel.Role public constant REPORTER = Kernel.Role.wrap("VOPOM_Reporter");
    Kernel.Role public constant MODIFIER = Kernel.Role.wrap("VOPOM_Modifier");
    Kernel.Role public constant CONFIGURATOR =
        Kernel.Role.wrap("VOPOM_Configurator");

    // ######################## ~ MATH ~ ########################

    mapping(uint256 => VoteConfig) public configurations;

    mapping(uint256 => mapping(int128 => int128)) public slopeChanges;

    // ######################## ~ POINTS ~ ########################

    mapping(uint256 => Point) public globalPointSet;

    mapping(address => Point[]) public userPointSets;

    mapping(address => uint256[]) public userOpenPoolPointIds;

    // ######################## ~ DELEGATIONS ~ ########################

    mapping(address => mapping(address => int128))
        public biasPercentDelegations;

    mapping(address => address[]) public userDelegators;

    // ###############################################################
    // ######################## ~ MAIN BODY ~ ########################
    // ###############################################################

    constructor(address kernel_) Module(Kernel(kernel_)) {}

    function KEYCODE() public pure virtual override returns (Kernel.Keycode) {
        return Kernel.Keycode.wrap("VOPOM");
    }

    function ROLES() public pure override returns (Kernel.Role[] memory roles) {
        roles = new Kernel.Role[](3);
        roles[0] = REPORTER;
        roles[1] = MODIFIER;
        roles[2] = CONFIGURATOR;
    }

    // ######################## ~ SETTERS ~ ########################

    function configureUniquely(
        uint64 poolId,
        int128 multiplier,
        int128 maxLock
    ) external onlyRole(CONFIGURATOR) {
        VoteConfig memory config = configurations[poolId];

        if (0 < config.maxlock + config.multiplier)
            revert VOPOM_AlreadyConfiguredFor(poolId);

        if (multiplier < VOPOM_SCALE) revert VOPOM_ValueScaleLow();

        configurations[poolId] = VoteConfig(multiplier, maxLock);
    }

    function checkpoint(uint64 poolId) external {
        _checkpoint(address(0), poolId, 0, Lock(0, 0), Lock(0, 0));
    }

    function noteLockCreation(
        address user,
        uint64 poolId,
        int128 balance,
        int32 epochedUnlockTime
    ) external onlyRole(REPORTER) returns (uint256 pointId) {
        int256 timestamp = block.timestamp.cui();
        pointId = userPointSets[user].length;

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
            userPointSets[user].length,
            0,
            balance,
            0,
            epochedUnlockTime
        );
    }

    function noteLockBalanceChange(
        address user,
        uint256 pointId,
        int128 oldBalance,
        int128 newBalance,
        int32 epochedUnlockTime
    ) external onlyRole(REPORTER) {
        if (userPointSets[user][pointId].tst == 0) revert VOPOM_NoLockFound();

        if (epochedUnlockTime <= block.timestamp.cui())
            revert VOPOM_LockExpired();

        _noteLock(
            user,
            userPointSets[user][pointId].poolId,
            pointId,
            oldBalance,
            newBalance,
            epochedUnlockTime,
            epochedUnlockTime
        );
    }

    function noteLockExtension(
        address user,
        uint256 pointId,
        int128 balance,
        int32 oldEpochedUnlockTime,
        int32 newEpochedUnlockTime
    ) external onlyRole(REPORTER) {
        int256 timestamp = block.timestamp.cui();
        uint64 poolId = userPointSets[user][pointId].poolId;

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

    function noteVotingPowerDelegation(
        address from,
        address to,
        int128 biasPercent
    ) external onlyRole(REPORTER) {
        // reads
        int128 totalPercentDelegated = biasPercentDelegations[from][from];
        int128 newPercentDelegated = biasPercent + totalPercentDelegated;

        // checks
        if (0 <= newPercentDelegated && newPercentDelegated <= VOPOM_SCALE)
            revert VOPOM_InvalidBiasPercentForDelegation(
                biasPercent,
                totalPercentDelegated
            );

        // TODO: think

        // effects
        // += so it can be decremented
        biasPercentDelegations[from][to] += biasPercent;

        // total percent delegated
        biasPercentDelegations[from][from] = newPercentDelegated;
    }

    function noteDelegators(address user, address[] calldata delegators)
        external
        onlyRole(MODIFIER)
    {
        userDelegators[user] = delegators;
    }

    function noteOpenPoolPointAddition(address user, uint256 pointId)
        external
        onlyRole(MODIFIER)
    {
        userOpenPoolPointIds[user].push(pointId);
    }

    // ######################## ~ ALMIGHTY GETTERS ~ ########################

    function getVotingPower(
        address user,
        int128 timestamp,
        uint256[] memory pointIds
    ) public view returns (int256 votingPower) {
        uint256 l = pointIds.length;

        for (uint256 i; i < l; ) {
            Point memory upoint = userPointSets[user][pointIds[i]];

            if (upoint.tst == 0) revert VOPOM_NoLockFound();

            upoint.bias -= upoint.slope * (timestamp - upoint.tst);

            if (upoint.bias < 0) upoint.bias = 0;

            votingPower += upoint.bias;

            unchecked {
                ++i;
            }
        }
    }

    function getVotingPower(address user, uint256[] memory pointIds)
        public
        view
        returns (int256 globalVotingPower)
    {
        return getVotingPower(user, block.timestamp.cu128i(), pointIds);
    }

    function getGlobalVotingPower(int128 timestamp, uint64[] memory poolIds)
        public
        view
        returns (int256 globalVotingPower)
    {
        uint256 l = poolIds.length;

        for (uint256 i; i < l; ) {
            Point memory glpoint = globalPointSet[poolIds[i]];

            glpoint.bias -= glpoint.slope * (timestamp - glpoint.tst);

            if (glpoint.bias < 0) return 0;

            globalVotingPower += glpoint.bias;

            unchecked {
                ++i;
            }
        }
    }

    function getGlobalVotingPower(uint64[] memory poolIds)
        public
        view
        returns (int256 globalVotingPower)
    {
        return getGlobalVotingPower(block.timestamp.cu128i(), poolIds);
    }

    function getOpenVotingPower(address user, int128 timestamp)
        public
        view
        returns (int256 votingPower)
    {
        return
            getVotingPower(user, timestamp, userOpenPoolPointIds[user]).mul(
                VOPOM_SCALE - biasPercentDelegations[user][user]
            );
    }

    function getOpenVotingPower(address user)
        public
        view
        returns (int256 votingPower)
    {
        return getOpenVotingPower(user, block.timestamp.cu128i());
    }

    function getDelegatedVotingPower(address user, int128 timestamp)
        public
        view
        returns (int256 votingPower)
    {
        address[] memory delegators = userDelegators[user];
        uint256 l = delegators.length;

        for (uint256 i; i < l; ) {
            address delegator = delegators[i];

            votingPower += getVotingPower(
                delegator,
                timestamp,
                userOpenPoolPointIds[delegator]
            ).mul(biasPercentDelegations[delegator][user]);

            unchecked {
                ++i;
            }
        }
    }

    function getDelegatedVotingPower(address user)
        public
        view
        returns (int256 votingPower)
    {
        return getDelegatedVotingPower(user, block.timestamp.cu128i());
    }

    // ######################## ~ SPECIFIC GETTERS ~ ########################

    function userOpenPoolPointIdsContain(address user, uint256 poolId)
        public
        view
        returns (bool)
    {
        uint256[] memory openPoolPointIds = getUserOpenPoolPointIds(user);
        uint256 l = openPoolPointIds.length;

        for (uint256 i; i < l; ) {
            if (openPoolPointIds[i] == poolId) return true;

            unchecked {
                ++i;
            }
        }

        return false;
    }

    function getUserOpenPoolPointIds(address user)
        public
        view
        returns (uint256[] memory)
    {
        return userOpenPoolPointIds[user];
    }

    function getUserPoints(address user) public view returns (Point[] memory) {
        return userPointSets[user];
    }

    function isOpenPool(uint64 poolId) public view returns (bool) {
        return getGlobalPoint(poolId).tst != 0;
    }

    function isOnceNotedPoint(address user, uint256 pointId)
        public
        view
        returns (bool)
    {
        return getUserPoint(user, pointId).tst != 0;
    }

    function getMaximumLockTime(uint64 poolId) public view returns (int128) {
        return configurations[poolId].maxlock;
    }

    function getMultiplier(uint64 poolId) public view returns (int128) {
        return configurations[poolId].multiplier;
    }

    function getGlobalPoint(uint64 poolId)
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

    function getUserPointPoolId(address user, uint256 pointId)
        public
        view
        returns (uint64 poolId)
    {
        return userPointSets[user][pointId].poolId;
    }

    function getEpochTime() public view returns (int256) {
        return block.timestamp.cu32i().epochify();
    }

    // ######################## ~ INTERNAL LOGIC ~ ########################

    function _noteLock(
        address user,
        uint64 poolId,
        uint256 pointId,
        int128 oldAmount,
        int128 newAmount,
        int32 oldUnlockTime,
        int32 newUnlockTime
    ) internal {
        Lock memory oldLocked = Lock(oldAmount, oldUnlockTime);
        Lock memory newLocked = Lock(newAmount, newUnlockTime);

        if (configurations[poolId].maxlock == 0)
            revert VOPOM_VotingNotConfiguredFor(poolId);

        if (pointId == userPointSets[user].length)
            userPointSets[user].push(Point(0, 0, 0, 0, 0));

        _checkpoint(user, poolId, pointId, oldLocked, newLocked);
    }

    function _checkpoint(
        address user,
        uint64 poolId,
        uint256 pointId,
        Lock memory oldLocked,
        Lock memory newLocked
    ) internal {
        int128 timestamp = int128(block.timestamp.cui());

        Point memory pointOld;
        Point memory pointNew;

        int128 dSlopeOld;
        int128 dSlopeNew;

        pointNew.poolId = poolId;

        // The following calculates the new + old user slopes
        // new slopes are used for indicating total slope change
        // and calculating biases
        // biases are actual voting power
        {
            if (user != address(0)) {
                VoteConfig memory config = configurations[poolId];
                int64 period = userPointSets[user][pointId].period;

                if (oldLocked.end > timestamp && oldLocked.balance > 0) {
                    // slope basic
                    pointOld.slope = oldLocked.balance / config.maxlock;

                    // then multiplier calcs
                    // always use period
                    pointOld.slope =
                        pointOld
                            .slope
                            .mul(config.multiplier * period)
                            .ci128i() /
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
                        pointNew.period = int64(newLocked.end - timestamp);
                    else pointNew.period = period;

                    // then multiplier calcs
                    pointNew.slope =
                        pointNew
                            .slope
                            .mul(config.multiplier * pointNew.period)
                            .ci128i() /
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
        else
            pointLast = Point({
                bias: 0,
                slope: 0,
                poolId: poolId,
                period: 0,
                tst: timestamp
            });

        int128 lastEpochTime = pointLast.tst;
        int128 rollingEpochTime = int32(lastEpochTime).epochify();

        for (uint256 i; i < 64; ) {
            int128 dSlope = 0;

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

            unchecked {
                ++i;
            }
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
