// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansAuth} from "src/policies/interfaces/burnerloans/IBurnerLoansAuth.sol";
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Contracts
import {Test} from "@forge-std-1.16.2/Test.sol";
import {BurnerLoansAuth} from "src/policies/burnerloans/BurnerLoansAuth.sol";
import {AuthCoreMock} from "src/test/policies/BurnerLoansAuth/fixtures/AuthCoreMock.sol";

contract BurnerLoansAuthSequenceHandler is Test {
    AuthCoreMock internal _core;
    BurnerLoansAuth[2] internal _auths;
    address internal _asset;
    uint256 internal _selected;
    uint256 internal _global = 1;
    uint256[2] internal _accounts;
    uint256[2][2] internal _pairs;
    uint256[2][2] internal _acceptedPairs;
    uint256[2][2] internal _acceptedAccounts;
    uint256[2][2] internal _acceptedGlobals;
    bool[2][2] internal _accepted;

    // Controlled test bindings/callers intentionally retain zero-address cases where applicable.
    // forge-lint: disable-start(missing-zero-check)
    constructor(
        AuthCoreMock core_,
        BurnerLoansAuth first_,
        BurnerLoansAuth second_,
        address asset_
    ) {
        _core = core_;
        _auths[0] = first_;
        _auths[1] = second_;
        _asset = asset_;
    }

    // forge-lint: disable-end(missing-zero-check)

    // Fixture/cheatcode calls deliberately interleave effects to exercise callbacks and model transitions.
    // forge-lint: disable-start(reentrancy-no-eth)
    function approve(uint8 operatorIndex_) external {
        uint256 o = operatorIndex_ % 2;
        IBurnerLoansAuth.Permissions memory p;
        p.depositAsset = _asset;
        p.maxCollateral = type(uint128).max;
        IOperatorAuth.Grant memory g = IOperatorAuth.Grant(
            address(this),
            _operator(o),
            _accounts[_selected],
            _pairs[_selected][o],
            type(uint48).max,
            true,
            1,
            keccak256(abi.encode(address(_core), _global)),
            abi.encode(p)
        );
        _auths[_selected].approveGrant(g);
        _accepted[_selected][o] = true;
        _acceptedPairs[_selected][o] = _pairs[_selected][o];
        _acceptedAccounts[_selected][o] = _accounts[_selected];
        _acceptedGlobals[_selected][o] = _global;
        ++_pairs[_selected][o];
    }

    // forge-lint: disable-end(reentrancy-no-eth)

    function cancelPair(uint8 authIndex_, uint8 operatorIndex_) external {
        uint256 a = authIndex_ % 2;
        uint256 o = operatorIndex_ % 2;
        _auths[a].cancelGrant(_operator(o));
        ++_pairs[a][o];
    }

    function cancelAccount(uint8 authIndex_) external {
        uint256 a = authIndex_ % 2;
        _auths[a].cancelAllGrants();
        ++_accounts[a];
    }

    function rotate() external {
        _selected = 1 - _selected;
        ++_global;
        _core.select(address(_auths[_selected]));
    }

    // These calls enumerate bounded test actors/assets, including fixture helpers called by the loops.
    // forge-lint: disable-start(calls-loop)
    function assertModel() external view {
        (address selected, uint256 epoch) = _core.authConfig();
        assertEq(epoch, _global, "Core rotation epoch follows independent model");
        assertEq(
            selected,
            address(_auths[_selected]),
            "Core selected identity follows independent model"
        );
        for (uint256 a; a < 2; ++a) {
            assertEq(
                _auths[a].accountEpochs(address(this)),
                _accounts[a],
                "Each Auth retains its local account epoch"
            );
            for (uint256 o; o < 2; ++o) {
                assertEq(
                    _auths[a].pairEpochs(address(this), _operator(o)),
                    _pairs[a][o],
                    "Each Auth/operator retains its pair sequence"
                );
                bool expected = a == _selected &&
                    _accepted[a][o] &&
                    _acceptedGlobals[a][o] == _global &&
                    _acceptedAccounts[a][o] == _accounts[a] &&
                    _acceptedPairs[a][o] + 1 == _pairs[a][o];
                (bool live, ) = address(_auths[a]).staticcall(
                    abi.encodeCall(
                        _auths[a].captureAuthorization,
                        (address(this), _operator(o), uint8(1))
                    )
                );
                assertEq(
                    live,
                    expected,
                    "Only the current global/account/pair record is operative"
                );
            }
        }
    }

    // forge-lint: disable-end(calls-loop)

    function _operator(uint256 index_) private pure returns (address) {
        return index_ == 0 ? address(0xB0B) : address(0xC0D);
    }
}
