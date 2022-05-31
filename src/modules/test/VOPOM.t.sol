// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

/// DEPS
import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "solmate/tokens/ERC20.sol";
import "test-utils/UserFactory.sol";
import "test-utils/larping.sol";
import "test-utils/convert.sol";
import "test-utils/errors.sol";

/// LOCAL
import "src/modules/VOPOM.sol";

int32 constant rightnow = 1652036143;
uint256 constant fourYears = 4 * 365 * 24 * 3600;

contract MERC20 is ERC20 {
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC20(_name, _symbol, _decimals) {}
}

contract VOPOMTest is Test {
    using larping for *;
    using convert for *;
    using errors for *;

    address immutable self = address(this);

    VotingPowerModule vopom;
    UserFactory victims;
    ERC20 ohm;

    address ohma;
    address vopoma;

    function getWritePermissions(bytes5, address) public pure returns (bool) {
        return true;
    }

    function setUp() public {
        vopom = new VotingPowerModule(self);
        victims = new UserFactory();
        ohm = new MERC20("ohm", "OHM", 9);

        vopom.configureUniquely(
            0,
            int128((25 * VOPOM_SCALE) / 10),
            int128(fourYears.cui())
        );

        ohma = address(ohm);
        vopoma = address(vopom);
    }

    function testConfig() public {
        assertEq(vopom.getMultiplier(0), (25 * VOPOM_SCALE) / 10);
        assertEq(vopom.getMaximumLockTime(0), 4 * 365 * 24 * 3600);
        assertEq(vopom.KEYCODE(), "VOPOM");
    }

    function testLockCreation(int128 amount, int32 period) public {
        vm.assume(!(amount == 0 && period == 0));
        vm.assume(VOPOM_WEEK * 2 <= period);
        vm.assume(0 <= amount && 0 <= period);
        vm.assume(period.ciu() + rightnow.ciu() < type(int32).max.ciu());

        // setup
        vm.warp(rightnow.ciu());
        address usr = victims.next();
        int32 epochedUnlockTime = ((period + rightnow) / VOPOM_WEEK) *
            VOPOM_WEEK;

        if (period == 0) VOPOM_LockTooShort.selector.with();
        else if (rightnow + vopom.getMaximumLockTime(0) < epochedUnlockTime)
            VOPOM_LockTooLong.selector.with();
        else if (amount == 0) VOPOM_ZeroLock.selector.with();
        else {
            vopom.noteLockCreation(usr, 0, amount, epochedUnlockTime);
            return;
        }

        vopom.noteLockCreation(usr, 0, amount, epochedUnlockTime);
    }

    function linearity(uint128 amountu, uint32 periodu) public {
        int128 amount = int128(amountu);
        int32 period = int32(periodu);
        vm.assume(24 * 5 * 3600 < period);
        vm.assume(period.ciu() < vopom.getMaximumLockTime(0).ciu());
        vm.assume(1e21 < amount);
        vm.assume(amount < 1e33);

        // setup
        vm.warp(rightnow.ciu());
        int32 delta = 0;
        int32 step = period / 20;
        address[] memory us = victims.create(3);
        int128[] memory ams = new int128[](6);
        int32[] memory tims = new int32[](9);

        ams[0] = amount;
        ams[1] = amount / 2;
        ams[2] = amount / 3;
        ams[3] = amount * 2;
        ams[4] = ams[1] * 3;
        ams[5] = ams[2] * 4;
        tims[0] = 0;
        tims[1] = period / 4;
        tims[2] = period / 2;
        tims[3] = period / 2 + period / 4;
        tims[4] = period;
        tims[5] = period + period / 4;
        tims[6] = period + period / 2;
        tims[7] = period + period / 2 + period / 4;
        tims[8] = period * 2;
        uint256 c;
        uint256 j;

        while (delta <= 3 * period) {
            delta += step;
            vm.warp((rightnow + delta).ciu());
            int32 locktime = ((rightnow + delta + period) / VOPOM_WEEK) *
                VOPOM_WEEK;

            vopom.checkpoint(0);

            _logPoints2(c, us, rightnow + delta, (3 < j) ? 3 : j);

            if (j != 9 && tims[j] <= delta) {
                if (j < 3) {
                    console2.log(
                        "__________________________________________________________lock_creation"
                    );
                    vopom.noteLockCreation(us[j], 0, ams[j], locktime);
                    tims[j] = locktime;
                } else if (j < 6) {
                    console2.log(
                        "_________________________________________________________lock_extension"
                    );
                    vopom.noteLockExtension(
                        us[j - 3],
                        j - 2,
                        ams[j - 3],
                        tims[j - 3],
                        locktime
                    );
                    tims[j] = locktime;
                } else if (j < 9) {
                    console2.log(
                        "_________________________________________________________balance_change"
                    );
                    vopom.noteLockBalanceChange(
                        us[j - 6],
                        j - 5,
                        ams[j - 6],
                        ams[j - 6] + ams[j - 3],
                        tims[j - 3]
                    );
                } else j--;
                j++;
                _logPoints2(c, us, rightnow + delta, (3 < j) ? 3 : j);
            }
            c++;
        }
    }

    function _logUsers(
        address[] memory users,
        int32,
        uint256 bound
    ) internal view {
        for (uint256 i; i < bound; i++) {
            console2.log(
                "###########################USER SLOPE: ",
                vopom.getUserPoint(users[i], 0).slope.ciu()
            );
        }
    }

    function _logPoints2(
        uint256 counter,
        address[] memory users,
        int32 time,
        uint256 bound
    ) internal view {
        console2.log(
            counter,
            "++++++++++++++++++++++",
            time.ciu(),
            "++++++++++++++++++++++"
        );
        for (uint256 i; i < bound; i++) {
            console2.log("USER:", i);
            console2.log("ubias:", vopom.getOpenVotingPower(users[i]).ciu());
            console2.log("------------------------------------");
        }

        uint64[] memory poolIds = new uint64[](1);

        console2.log("glbias:", vopom.getGlobalVotingPower(poolIds).ciu());
        console2.log("------------------------------------");
    }
}
