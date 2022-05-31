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
import "src/policies/LockingVault.sol";

int32 constant rightnow = 1652036143;
int256 constant fourYears = 4 * 365 * 24 * 3600;
uint256 constant umax = type(uint256).max;

library arrays {
    function atomici256(int256 amount)
        internal
        pure
        returns (int256[] memory result)
    {
        result = new int256[](1);
        result[0] = amount;
    }

    function atomicu224(uint224 amount)
        internal
        pure
        returns (uint224[] memory result)
    {
        result = new uint224[](1);
        result[0] = amount;
    }

    function atomicu256(uint256 amount)
        internal
        pure
        returns (uint256[] memory result)
    {
        result = new uint256[](1);
        result[0] = amount;
    }

    function atomicu256(uint256 amount1, uint256 amount2)
        internal
        pure
        returns (uint256[] memory result)
    {
        result = new uint256[](2);
        result[0] = amount1;
        result[1] = amount2;
    }

    function atomicu256(
        uint256 amount1,
        uint256 amount2,
        uint256 amount3
    ) internal pure returns (uint256[] memory result) {
        result = new uint256[](3);
        result[0] = amount1;
        result[1] = amount2;
        result[2] = amount3;
    }

    function atomicu64(uint64 amount)
        internal
        pure
        returns (uint64[] memory result)
    {
        result = new uint64[](1);
        result[0] = amount;
    }

    function atomicu64(uint64 amount1, uint64 amount2)
        internal
        pure
        returns (uint64[] memory result)
    {
        result = new uint64[](2);
        result[0] = amount1;
        result[1] = amount2;
    }

    function atomicu64(
        uint64 amount1,
        uint64 amount2,
        uint64 amount3
    ) internal pure returns (uint64[] memory result) {
        result = new uint64[](3);
        result[0] = amount1;
        result[1] = amount2;
        result[2] = amount3;
    }

    // chain this for memory arrays
    function add(int256[] memory array, int256 element)
        internal
        pure
        returns (int256[] memory)
    {
        uint256 i;
        while (element != 0) {
            if (array[i] == 0) {
                array[i] = element;
                element = 0;
            }
            i++;
        }
        return array;
    }

    function inflate(int256[] memory arr, int256 by)
        internal
        pure
        returns (int256[] memory)
    {
        uint256 l = arr.length;
        for (uint256 i; i < l; i++) {
            arr[i] += by;
        }
        return arr;
    }

    function clean(int256[] memory array)
        internal
        pure
        returns (int256[] memory)
    {
        return new int256[](array.length);
    }
}

contract LockingVaultTest is Test {
    using larping for *;
    using convert for *;
    using errors for *;
    using arrays for *;

    address immutable self = address(this);

    UserFactory victims;
    ERC20 ohm;
    ERC20 fork;

    VotingPowerModule vopom;
    DepositManagementModule demam;
    LockingVault vault;

    address ohma;
    address forka;
    address vopoma;
    address vaulta;
    address demama;

    function getWritePermissions(bytes5, address) public pure returns (bool) {
        return true;
    }

    function getModuleForKeycode(bytes5 keycode) public view returns (address) {
        if (keycode == "DEMAM") return demama;
        else if (keycode == "VOPOM") return vopoma;
        else if (keycode == "AUTHZ") return address(this);
        else return address(0);
    }

    function canCall(
        address,
        address,
        bytes4
    ) public view virtual returns (bool) {
        return true;
    }

    function setUp() public {
        vault = new LockingVault(self);
        vopom = new VotingPowerModule(self);
        demam = new DepositManagementModule(self);
        victims = new UserFactory();

        ohm = ERC20(
            deployCode(
                "MockERC20.t.sol:MockERC20",
                abi.encode("ohm", "OHM", "9")
            )
        );

        fork = ERC20(
            deployCode(
                "MockERC20.t.sol:MockERC20",
                abi.encode("fork", "FORK", "18")
            )
        );

        vopom.configureUniquely(
            0,
            int128((25 * VOPOM_SCALE) / 10),
            int128(fourYears)
        );

        vopom.configureUniquely(1, int128(4 * VOPOM_SCALE), int128(fourYears));

        ohma = address(ohm);
        forka = address(fork);
        vopoma = address(vopom);
        demama = address(demam);

        vault.configureReads();

        vaulta = address(vault);

        vault.makePoolToken(0, ohma);
        vault.makePoolToken(1, forka);

        vault.openPool(0, false);
        vault.openPool(1, false);

        seed = uint256(keccak256(abi.encode("test")));
    }

    enum ops {
        lock,
        move,
        movex,
        extend,
        add,
        slash,
        again,
        length
    }

    mapping(ops => int256[]) public data;
    mapping(ops => int256[]) public times;

    function Integrative1(int32 period) public {
        ////////// assumptions
        vm.assume(VOPOM_WEEK < period);
        vm.assume(period < vopom.getMaximumLockTime(0));
        vm.assume(period < vopom.getMaximumLockTime(1));

        ////////// data
        address[] memory users = victims.create(4);
        int256 step = period / 40;

        {
            int256[] memory carry = new int256[](4);

            // now lets define for each
            // i want locks to be in first fourth
            carry = carry.add(1e24).add(9e23).add(5e22).add(1e20);
            data[ops.lock] = permuteBy(13, carry, false); // choose 13th permutation -_(*~*)_-, there is 24
            data[ops.add] = permutation(18, false);
            data[ops.again] = permutation(6, true);

            carry = carry.clean().add(6e21).add(9e21).add(1e22).add(1e30);
            data[ops.move] = permuteBy(16, carry, false); // 56th
            data[ops.movex] = permutation(9, true);

            carry = carry
                .clean()
                .add(period / 2)
                .add(period)
                .add(period / 3)
                .add(period + period / 3);
            data[ops.extend] = permuteBy(11, carry, true);

            carry = carry.clean().add(4e22).add(1e19).add(800000000000000).add(
                5e24
            );
            data[ops.slash] = permuteBy(2, carry, true);

            // times
            carry = carry
                .clean()
                .add(period / 5)
                .add(period / 3)
                .add(period / 4 - 500)
                .add(period / 3 + period / 9); // < 1/4 * period
            times[ops.lock] = permuteBy(7, carry, true);

            carry = carry.inflate(period / 2);
            times[ops.add] = permuteBy(14, carry, true);

            carry = carry.inflate(period / 4);
            times[ops.extend] = permuteBy(16, carry, false);
            times[ops.slash] = permutation(14, true);

            carry = carry.inflate(period / 4);
            times[ops.move] = permuteBy(4, carry, true);

            carry = carry.inflate((period * 4) / 5);
            times[ops.again] = permuteBy(20, carry, false);
            times[ops.movex] = permutation(13, true);
        }

        // env
        vm.warp(rightnow.ci32u());

        for (uint256 i; i < 4; i++) {
            ohm.transferFrom.larp(
                users[i],
                demama,
                data[ops.lock][i].ciu(),
                true
            );
            fork.transferFrom.larp(
                users[i],
                demama,
                data[ops.lock][i].ciu(),
                true
            );
            ohm.transferFrom.larp(
                users[i],
                demama,
                data[ops.add][i].ciu(),
                true
            );
            fork.transferFrom.larp(
                users[i],
                demama,
                data[ops.add][i].ciu(),
                true
            );
            ohm.transferFrom.larp(
                users[i],
                demama,
                data[ops.again][i].ciu(),
                true
            );
            fork.transferFrom.larp(
                users[i],
                demama,
                data[ops.again][i].ciu(),
                true
            );
        }

        // logic
        int256 delta;
        uint8 flag;

        while (delta < period * 3) {
            // Increase time.
            delta += step;

            _logTime(rightnow, delta, step);

            vm.warp((rightnow + delta).ci32u());

            // Checkpoint all pools
            vopom.checkpoint(0);
            vopom.checkpoint(1);

            for (uint64 i; i < 4; i++) {
                // select token based on parity
                address token = i % 2 == 0 ? ohma : forka;

                // is it time to add lock?
                if (times[ops.lock][i] <= delta) {
                    // log op
                    console.log("USER", i, "OPERATION", "LOCK");

                    // set up data
                    uint128 amount = data[ops.lock][i].ci128u();
                    uint32 end = (rightnow + delta + period).ci32u();
                    bool reverted;

                    // impersonate
                    hoax(users[i]);

                    // check whether will be too short
                    if (
                        ((end.cui() / VOPOM_WEEK) * VOPOM_WEEK).ciu() <
                        (rightnow + delta + VOPOM_WEEK).ciu()
                    ) {
                        VOPOM_LockTooShort.selector.with();
                        reverted = true;
                    }

                    // lock
                    uint256 lockId = vault.lockTokens(
                        token,
                        amount,
                        i % 2, // either pool 0 or 1
                        end
                    );

                    // this is in the case of forge test, not forge run
                    if (reverted) return;

                    // store lock id
                    data[ops.lock][i] = lockId.cui();

                    // store that operation completed
                    times[ops.lock][i] = type(int32).max;

                    // set flag for logs
                    flag = (i % 2 == 1 || flag == 2) ? 2 : 1;

                    // check that lock completed succesfully
                    assertEq(
                        demam.getUserLockBalance(users[i], token, lockId),
                        amount
                    );

                    // is it time to add?
                } else if (times[ops.add][i] <= delta) {
                    // log op
                    console.log("USER", i, "OPERATION", "ADD");

                    // which lockId?
                    uint256 lockId = data[ops.lock][i].ciu();

                    // get balance before
                    uint128 balbef = demam
                        .getUserLockBalance(users[i], token, lockId)
                        .cu128u();
                    uint128 toAdd = data[ops.add][i].ci128u();

                    // impersonate
                    hoax(users[i]);

                    // now add
                    vault.addToLock(
                        users[i],
                        token,
                        lockId,
                        toAdd // add this much
                    );

                    // note that we added succesfully
                    times[ops.add][i] = type(int32).max;

                    // increase former balance by amount added
                    balbef += toAdd;

                    // assert that the amount added is good
                    assertGe(
                        demam.getUserLockBalance(users[i], token, lockId),
                        balbef - 100
                    );
                    // is it time to extend?
                } else if (times[ops.extend][i] <= delta) {
                    // log op
                    console.log("USER", i, "OPERATION", "EXTEND");

                    // time to extend to
                    int32 newTimeRaw = int32(rightnow + delta + period);

                    // get the lockId
                    uint256 lockId = data[ops.lock][i].ciu();

                    // to assert that bias shall increase
                    uint256[] memory lockIds = new uint256[](1);
                    lockIds[0] = lockId;
                    int256 biasBefore = vopom.getVotingPower(users[i], lockIds);

                    // impersonate
                    hoax(users[i]);

                    // extend
                    vault.extendLock(token, lockId, uint32(newTimeRaw));

                    // extend
                    times[ops.extend][i] = type(int32).max;

                    // assertions
                    assertEq(
                        demam.getUserLockEnd(users[i], token, lockId),
                        ((newTimeRaw / VOPOM_WEEK) * VOPOM_WEEK).ciu()
                    );

                    assertTrue(
                        biasBefore < vopom.getVotingPower(users[i], lockIds),
                        "Bias did not increase!"
                    );
                    // is it time to slash?
                } else if (times[ops.slash][i] <= delta) {
                    // log op
                    console.log(
                        "USER",
                        i,
                        "OPERATION SLASH",
                        data[ops.slash][i].ci128u()
                    );

                    // flag if reverts
                    bool reverted;

                    // depending on whether we moved,
                    // we might have to split slash up
                    bool movedOnce = times[ops.move][i] == type(int32).max ||
                        times[ops.movex][i] == type(int32).max;

                    if (movedOnce) {
                        // if moved first prepare memory
                        uint224[] memory amounts = new uint224[](4);
                        // get toSlash amount
                        uint128 toSlash = data[ops.slash][i].ci128u();

                        // now get balance in both locks and assign so we can store too
                        amounts[0] = demam
                            .getUserLockBalance(users[i], token, 0)
                            .cu128u();
                        amounts[2] = amounts[0];

                        amounts[1] = demam
                            .getUserLockBalance(users[i], token, 1)
                            .cu128u();
                        amounts[3] = amounts[1];

                        // take the sum so we can get percent
                        uint224 sum = amounts[0] + amounts[1];

                        // if sum not large enough expect revert
                        if (sum < toSlash) {
                            vm.expectRevert(stdError.arithmeticError);
                            reverted = true;
                        }

                        // calc to slash amounts per lock
                        amounts[0] = (amounts[0] * toSlash) / sum;
                        amounts[1] = (amounts[1] * toSlash) / sum;

                        // impersonate
                        hoax(users[i]);

                        // slash
                        vault.slashLockedTokens(
                            users[i],
                            token,
                            0
                        );

                        // if did not revert do asserts
                        if (!reverted) {
                            // assert new balance on 0
                            assertEq(
                                demam.getUserLockBalance(users[i], token, 0),
                                amounts[2] - amounts[0]
                            );

                            // assert new balance on 1
                            assertEq(
                                demam.getUserLockBalance(users[i], token, 1),
                                amounts[3] - amounts[1]
                            );
                        }
                        // otherwise
                    } else {
                        // get toSlash and balance
                        uint224 toSlash = data[ops.add][i].ci224u();
                        uint224 balance = demam.getUserLockBalance(
                            users[i],
                            token,
                            0
                        );

                        // expect revert if not enough
                        if (balance < toSlash) {
                            vm.expectRevert(stdError.arithmeticError);
                            reverted = true;
                        }

                        // impersonate
                        hoax(users[i]);

                        // slash
                        vault.slashLockedTokens(
                            users[i],
                            self,
                            token,
                            arrays.atomicu224(toSlash),
                            arrays.atomicu256(data[ops.lock][i].ciu())
                        );

                        // if did not expect exact balance
                        if (!reverted)
                            assertEq(
                                demam.getUserLockBalance(users[i], token, 0),
                                balance - toSlash
                            );
                    }

                    // indicate slash happened
                    times[ops.slash][i] = type(int32).max;

                    // if time for moving...
                } else if (times[ops.move][i] <= delta) {
                    // how much to move
                    uint128 toMove = data[ops.move][i].ci128u();

                    // log operation
                    console.log("USER", i, "OPERATION MOVE", toMove);

                    // current state
                    uint224 bal = demam.getUserLockBalance(users[i], token, 0);
                    uint32 end = demam.getUserLockEnd(users[i], token, 0);

                    // if not enough
                    if (bal < toMove) {
                        VOPOM_ZeroLock.selector.with();
                        toMove = 0;
                    }

                    // impersonate
                    hoax(users[i]);

                    // move
                    uint256 lockId = vault.transferTokensToNewLock(
                        token,
                        0,
                        i % 2,
                        toMove,
                        end
                    );

                    // store data
                    data[ops.move][i] = lockId.cui();
                    times[ops.move][i] = type(int32).max;

                    // in both cases expect correct state
                    assertEq(
                        demam.getUserLockBalance(users[i], token, 0),
                        bal - toMove
                    );

                    // and if it was actually moved expect also something in second case
                    if (toMove != 0)
                        assertEq(
                            demam.getUserLockBalance(users[i], token, lockId),
                            toMove
                        );
                    // is it time to lock again?
                } else if (times[ops.again][i] <= delta) {
                    // log op
                    console.log("USER", i, "OPERATION", "AGAIN");

                    // impersonate
                    hoax(users[i]);

                    // lock tokens again and get new lockId
                    uint256 lockId = vault.lockTokens(
                        token,
                        data[ops.again][i].ci128u(),
                        i % 2,
                        (rightnow + delta + period / 2).ci32u()
                    );

                    // store data
                    data[ops.again][i] = lockId.cui();
                    times[ops.again][i] = type(int32).max;
                }
            }

            // var to sum all voting power
            uint256 totalVotingPower;

            for (uint256 i; i < 4; i++) {
                uint256 votingPower = vopom
                    .getVotingPower(
                        users[i],
                        vopom.getUserOpenPoolPointIds(users[i])
                    )
                    .ciu();

                console2.log("USER ", i, " VP", votingPower);

                totalVotingPower += votingPower;
            }

            uint64[] memory poolIds = new uint64[](2);
            poolIds[0] = 0;
            poolIds[1] = 1;

            uint256 realGlobalVotingPower = vopom
                .getGlobalVotingPower(poolIds)
                .ciu();

            console2.log("GLOBAL BIAS: ", realGlobalVotingPower, flag);

            if (
                totalVotingPower < realGlobalVotingPower ||
                realGlobalVotingPower < totalVotingPower
            )
                console2.log(
                    "TVP STARTS DEVIATING FROM GVP HERE",
                    totalVotingPower,
                    flag,
                    totalVotingPower < realGlobalVotingPower
                        ? realGlobalVotingPower - totalVotingPower
                        : totalVotingPower - realGlobalVotingPower
                );
        }
    }

    function _logTime(
        int256 rn,
        int256 delta,
        int256 step
    ) internal view {
        console2.log(
            "----------------------------------- TIME: ",
            (rn + delta).ciu(),
            (delta / step).ciu(),
            " -------------------------------"
        );
    }

    uint256 seed;

    function rand() public view returns (uint256 next) {
        return uint256(keccak256(abi.encode(seed)));
    }

    int256[][] permutations;
    int256[] permuted;

    function permutation(uint256 i, bool del)
        public
        returns (int256[] memory result)
    {
        result = permutations[i];
        if (del) delete permutations;
    }

    function permuteBy(
        uint256 i,
        int256[] memory input,
        bool del
    ) public returns (int256[] memory result) {
        permuted = input;
        heaps(input.length, permuted); // permute
        result = permutations[i]; // return ith permutation
        if (del) delete permutations; // clean
    }

    function heaps(uint256 k, int256[] storage arr) internal {
        if (k == 1) {
            permutations.push(arr);
        } else {
            heaps(k - 1, arr);

            for (uint256 i; i < k - 1; i++) {
                if (k % 2 == 0) (arr[i], arr[k - 1]) = (arr[k - 1], arr[i]);
                else (arr[0], arr[k - 1]) = (arr[k - 1], arr[0]);
                heaps(k - 1, arr);
            }
        }
    }

    function log4(int256[] memory arr) internal view {
        console2.log(arr[0].ciu(), arr[1].ciu(), arr[2].ciu(), arr[3].ciu());
    }
}
