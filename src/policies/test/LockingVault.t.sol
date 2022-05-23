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

            carry = carry.clean().add(3e22).add(9e21).add(1e24).add(1e30);
            data[ops.move] = permuteBy(16, carry, true); // 56th

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
            times[ops.again] = permuteBy(20, carry, true);
        }

        // env
        vm.warp(rightnow.ciu32());

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
            delta += step;
            console2.log(
                "----------------------------------- TIME: ",
                (rightnow + delta).ciu(),
                (delta / step).ciu(),
                " -------------------------------"
            );

            vm.warp((rightnow + delta).ciu32());
            vopom.checkpoint(0);
            vopom.checkpoint(1);

            for (uint256 i; i < 4; i++) {
                address token = i % 2 == 0 ? ohma : forka;

                if (times[ops.lock][i] <= delta) {
                    console.log("USER", i, "OPERATION", "LOCK");

                    uint224 amount = data[ops.lock][i].ciu224();
                    uint32 end = (rightnow + delta + period).ciu32();
                    bool reverted;

                    hoax(users[i]);

                    if (
                        ((end.cui() / VOPOM_WEEK) * VOPOM_WEEK).ciu() <
                        (rightnow + delta + VOPOM_WEEK).ciu()
                    ) {
                        VOPOM_LockTooShort.selector.with();
                        reverted = true;
                    }

                    (uint256 lockId, uint256 id) = vault.lockTokens(
                        token,
                        amount,
                        i % 2,
                        end
                    );

                    if (reverted) return;

                    data[ops.lock][i] = id.cui();
                    times[ops.lock][i] = type(int32).max;
                    flag = (i % 2 == 1 || flag == 2) ? 2 : 1;

                    assertEq(
                        demam.getUserLockBalance(users[i], token, lockId),
                        amount
                    );
                } else if (times[ops.add][i] <= delta) {
                    console.log("USER", i, "OPERATION", "ADD");

                    uint224 amount = data[ops.lock][i].ciu224();
                    uint256 id = data[ops.lock][i].ciu();
                    (, uint256 lockId, ) = vault.getDepositDataForUniqueId(id);
                    amount += demam.getUserLockBalance(users[i], token, lockId);

                    hoax(users[i]);
                    vault.addToLock(token, id, data[ops.add][i].ciu224());

                    times[ops.add][i] = type(int32).max;

                    amount += data[ops.add][i].ciu224();

                    assertGe(
                        demam.getUserLockBalance(users[i], token, lockId),
                        amount - 100
                    );
                } else if (times[ops.extend][i] <= delta) {
                    console.log("USER", i, "OPERATION", "EXTEND");

                    int32 newTimeRaw = int32(rightnow + delta + period);
                    uint256 id = data[ops.lock][i].ciu();
                    (, uint256 lockId, ) = vault.getDepositDataForUniqueId(id);

                    hoax(users[i]);

                    times[ops.extend][i] = type(int32).max;

                    assertEq(
                        demam.getUserLockEnd(users[i], token, lockId),
                        ((newTimeRaw / VOPOM_WEEK) * VOPOM_WEEK).ciu()
                    );
                } else if (times[ops.slash][i] <= delta) {
                    console.log("USER", i, "OPERATION", "SLASH");

                    bool reverted;
                    uint256 id = data[ops.lock][i].ciu();
                    (, uint256 lockId, ) = vault.getDepositDataForUniqueId(id);

                    if (times[ops.move][i] == type(int32).max) {
                        uint224[] memory amounts = new uint224[](4);
                        uint224 toSlash = data[ops.add][i].ciu224();

                        amounts[0] = demam.getUserLockBalance(
                            users[i],
                            token,
                            0
                        );
                        amounts[2] = amounts[0];

                        amounts[1] = demam.getUserLockBalance(
                            users[i],
                            token,
                            1
                        );
                        amounts[3] = amounts[1];

                        uint224 sum = amounts[0] + amounts[1];

                        if (sum < toSlash) {
                            vm.expectRevert(stdError.arithmeticError);
                            reverted = true;
                        }

                        amounts[0] = (amounts[0] * toSlash) / sum;
                        amounts[1] = (amounts[1] * toSlash) / sum;

                        {
                            uint256 id2 = data[ops.move][i].ciu();

                            hoax(users[i]);
                            vault.slashLockedTokens(
                                users[i],
                                self,
                                token,
                                amounts,
                                arrays.atomicu256(id, id2)
                            );
                        }

                        if (!reverted) {
                            assertEq(
                                demam.getUserLockBalance(
                                    users[i],
                                    token,
                                    lockId
                                ),
                                amounts[2] - amounts[0]
                            );

                            id = data[ops.move][i].ciu();
                            (, lockId, ) = vault.getDepositDataForUniqueId(id);

                            assertEq(
                                demam.getUserLockBalance(
                                    users[i],
                                    token,
                                    lockId
                                ),
                                amounts[3] - amounts[1]
                            );
                        }
                    } else {
                        uint224 toSlash = data[ops.add][i].ciu224();
                        uint224 balance = demam.getUserLockBalance(
                            users[i],
                            token,
                            0
                        );

                        if (balance < toSlash) {
                            vm.expectRevert(stdError.arithmeticError);
                            reverted = true;
                        }

                        hoax(users[i]);
                        vault.slashLockedTokens(
                            users[i],
                            self,
                            token,
                            arrays.atomicu224(toSlash),
                            arrays.atomicu256(data[ops.lock][i].ciu())
                        );

                        if (!reverted)
                            assertEq(
                                demam.getUserLockBalance(
                                    users[i],
                                    token,
                                    lockId
                                ),
                                balance - toSlash
                            );
                    }

                    times[ops.slash][i] = type(int32).max;
                } else if (times[ops.move][i] <= delta) {
                    console.log("USER", i, "OPERATION", "MOVE");
                    uint256 depositId = data[ops.lock][i].ciu();
                    uint224 toMove = data[ops.move][i].ciu224();
                    uint224 bal = demam.getUserLockBalance(users[i], token, 0);

                    if (bal < toMove) {
                        VOPOM_ZeroLock.selector.with();
                        toMove = 0;
                    }

                    hoax(users[i]);
                    (uint256 lockId, uint256 id) = vault
                        .transferTokensBetweenLocks(
                            token,
                            depositId,
                            i % 2,
                            0,
                            toMove
                        );

                    data[ops.move][i] = id.cui();
                    times[ops.move][i] = type(int32).max;

                    assertEq(
                        demam.getUserLockBalance(users[i], token, 0),
                        bal - toMove
                    );

                    if (toMove != 0)
                        assertEq(
                            demam.getUserLockBalance(users[i], token, lockId),
                            toMove
                        );
                } else if (times[ops.again][i] <= delta) {
                    console.log("USER", i, "OPERATION", "AGAIN");

                    hoax(users[i]);
                    (, uint256 id) = vault.lockTokens(
                        token,
                        data[ops.again][i].ciu224(),
                        i % 2,
                        (rightnow + delta + period / 2).ciu32()
                    );

                    data[ops.again][i] = id.cui();
                    times[ops.again][i] = type(int32).max;
                }
            }

            uint256 totalVotingPower;

            for (uint256 i; i < 4; i++) {
                uint256 idLockOp = (times[ops.lock][i] == type(int32).max)
                    ? data[ops.lock][i].ciu()
                    : 0;
                uint256 idMove = (times[ops.move][i] == type(int32).max)
                    ? data[ops.move][i].ciu()
                    : 0;
                uint256 idAgain = (times[ops.again][i] == type(int32).max)
                    ? data[ops.again][i].ciu()
                    : 0;

                uint256 votingPower = idLockOp == 0
                    ? 0
                    : vopom.getVotingPower(users[i], idLockOp).ciu();
                votingPower += (idMove == 0)
                    ? 0
                    : vopom.getVotingPower(users[i], idMove).ciu();
                votingPower += (idAgain == 0)
                    ? 0
                    : vopom.getVotingPower(users[i], idAgain).ciu();

                console2.log("USER ", i, " VP", votingPower);

                totalVotingPower += votingPower;
            }

            for (uint256 i; i < 4; i++) {
                uint256 idMove = data[ops.move][i].ciu();

                if (times[ops.again][i] == type(int32).max) {
                    if (idMove != 0) {
                        console2.log(
                            "USER ",
                            i,
                            " VPS ",
                            vopom
                                .getVotingPowerShare(
                                    users[i],
                                    arrays.atomicu256(0, 1),
                                    arrays.atomicu256(
                                        data[ops.lock][i].ciu(),
                                        idMove,
                                        data[ops.again][i].ciu()
                                    )
                                )
                                .ciu()
                        );
                    } else {
                        console2.log(
                            "USER ",
                            i,
                            " VPS ",
                            vopom
                                .getVotingPowerShare(
                                    users[i],
                                    arrays.atomicu256(0, 1),
                                    arrays.atomicu256(
                                        data[ops.lock][i].ciu(),
                                        data[ops.again][i].ciu()
                                    )
                                )
                                .ciu()
                        );
                    }
                } else if (
                    times[ops.move][i] == type(int32).max && idMove != 0
                ) {
                    console2.log(
                        "USER ",
                        i,
                        " VPS ",
                        vopom
                            .getVotingPowerShare(
                                users[i],
                                arrays.atomicu256(0, 1),
                                arrays.atomicu256(
                                    data[ops.lock][i].ciu(),
                                    idMove
                                )
                            )
                            .ciu()
                    );
                } else if (times[ops.lock][i] == type(int32).max) {
                    console2.log(
                        "USER ",
                        i,
                        " VPS ",
                        vopom
                            .getVotingPowerShare(
                                users[i],
                                arrays.atomicu256(0, 1),
                                arrays.atomicu256(data[ops.lock][i].ciu())
                            )
                            .ciu()
                    );
                }
            }

            uint256 realGlobalVotingPower = (vopom.getGlobalVotingPower(0) +
                vopom.getGlobalVotingPower(1)).ciu();

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
