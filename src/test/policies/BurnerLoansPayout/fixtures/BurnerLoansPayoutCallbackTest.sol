// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Literal amounts and endpoints are independent expected test values.
// Expected-revert calls and repeat-configuration probes discard their return values.
// forge-lint: disable-start(literal-instead-of-constant, unused-return)

// Contracts
import {BurnerLoansPayoutTest} from "../BurnerLoansPayoutTest.sol";
import {PayoutCallbackToken} from "./PayoutCallbackToken.sol";
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";

abstract contract BurnerLoansPayoutCallbackTest is BurnerLoansPayoutTest {
    PayoutCallbackToken internal _callbackToken;

    function setUp() public virtual override {
        super.setUp();
        _callbackToken = new PayoutCallbackToken();
    }

    function _deferCallbackFee(uint256 amount_) internal {
        _callbackToken.setTransferBlocked(_treasury(), true);
        _callbackToken.mint(address(_payout), amount_);
        vm.prank(address(_core));
        _payout.creditFee(address(_callbackToken), amount_);
    }

    function _deferCallbackSeizure(uint256 reward_, uint256 seized_) internal {
        _callbackToken.setTransferBlocked(_keeper, true);
        _callbackToken.setTransferBlocked(_treasury(), true);
        _callbackToken.mint(address(_payout), reward_ + seized_);
        vm.prank(address(_core));
        _payout.creditSeizure(address(_callbackToken), _keeper, reward_, seized_);
    }

    function _prepareIncoming(bytes memory callback_, bool propagate_) internal {
        _price.setPrice(address(_callbackToken), 1e18);
        _admit(address(_callbackToken));
        _callbackToken.mint(_borrower, 100e18);
        vm.prank(_borrower);
        _callbackToken.approve(address(_core), type(uint256).max);
        _callbackToken.armIncoming(address(_core), address(_payout), callback_, propagate_);
    }

    function _assertCallbackRejected() internal view {
        assertEq(_callbackToken.callbackAttempts(), 1, "Exactly one meaningful nested attempt");
        assertEq(
            _callbackToken.callbackError(),
            abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector),
            "Authorized callback reaches the settlement/recovery guard"
        );
    }

    function _callbackDigest() internal view returns (bytes32) {
        (uint256 fee, uint256 seized, uint256 total) = _payout.payoutReserves(
            address(_callbackToken)
        );
        return
            keccak256(
                abi.encode(
                    fee,
                    seized,
                    total,
                    _subject.keeperReward(address(_callbackToken), _keeper),
                    _payout.getPendingKeepers(address(_callbackToken)),
                    _subject.hasPendingToken(address(_callbackToken)),
                    _callbackToken.balanceOf(address(_payout)),
                    _callbackToken.balanceOf(_treasury()),
                    _callbackToken.balanceOf(_keeper),
                    _callbackToken.balanceOf(_destination),
                    _callbackToken.totalSupply()
                )
            );
    }

    function _seedUnrelatedClaims() internal {
        _deferFee(_otherToken, 13);
        _token.setTransferReverts(_treasury(), true);
        _token.mint(address(_otherPayout), 17);
        vm.prank(address(_core));
        _otherPayout.creditFee(address(_token), 17);
    }
}

// forge-lint: disable-end(literal-instead-of-constant, unused-return)
