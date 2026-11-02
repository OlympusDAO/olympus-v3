// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Finite seed and invariant loops intentionally call real contracts.
// Literal amounts and endpoints are independent expected test values.
// forge-lint: disable-start(calls-loop, literal-instead-of-constant)

// Libraries
import {ADMIN_ROLE} from "src/policies/utils/RoleDefinitions.sol";

// Contracts
import {BurnerLoansPayoutTest} from "./BurnerLoansPayoutTest.sol";
import {PayoutAccountingHandler} from "./fixtures/PayoutAccountingHandler.sol";
import {MockRevertingTransferToken} from "src/test/mocks/MockRevertingTransferToken.sol";

contract BurnerLoansPayoutAccountingInvariantsTest is BurnerLoansPayoutTest {
    PayoutAccountingHandler internal _handler;

    function setUp() public override {
        super.setUp();
        _bindDistributor();
        _handler = new PayoutAccountingHandler(
            _subject,
            address(_core),
            [_token, _otherToken],
            [_treasury(), address(_distributor), _keeper],
            _destination
        );
        _rolesAdmin.grantRole(ADMIN_ROLE, address(_handler));
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = _handler.creditFee.selector;
        selectors[1] = _handler.creditSeizure.selector;
        selectors[2] = _handler.retry.selector;
        selectors[3] = _handler.setBlocked.selector;
        selectors[4] = _handler.setFeeRoute.selector;
        selectors[5] = _handler.setEnabled.selector;
        selectors[6] = _handler.rescueSurplus.selector;
        selectors[7] = _handler.rescuePending.selector;
        targetSelector(FuzzSelector({addr: address(_handler), selectors: selectors}));
        targetContract(address(_handler));
    }

    function invariant_backingBucketsIndexesAndRoutes() public view {
        assertEq(
            _payout.isEnabled(),
            _handler.enabled(),
            "Only explicit local transitions change admission"
        );
        assertEq(
            _payout.sendFeesToDistributor(),
            _handler.feeRoute() == 1,
            "Routing follows independent model"
        );
        uint256 indexedTokens;
        for (uint256 t; t < 2; ++t) {
            MockRevertingTransferToken token = t == 0 ? _token : _otherToken;
            (uint256 fee, uint256 seized, uint256 total) = _payout.payoutReserves(address(token));
            assertEq(fee, _handler.fee(t), "Raw fee matches model");
            assertEq(seized, _handler.seized(t), "Raw seizure matches model");
            assertEq(total, _handler.total(t), "Aggregate equals independent bucket sum");
            assertEq(
                token.balanceOf(address(_payout)),
                total,
                "Custody exactly backs outstanding obligations"
            );
            assertEq(
                _subject.hasPendingToken(address(token)),
                total != 0,
                "Stored token membership matches obligations"
            );
            if (total != 0) ++indexedTokens;
            uint256 keeperCount;
            uint256 recipientCount;
            uint256 distributed;
            address[3] memory recipients = [_treasury(), address(_distributor), _keeper];
            for (uint256 k; k < 3; ++k) {
                uint256 reward = _handler.reward(t, k);
                assertEq(
                    _subject.keeperReward(address(token), recipients[k]),
                    reward,
                    "Raw keeper claim follows original owner"
                );
                assertEq(
                    _subject.hasPendingKeeper(address(token), recipients[k]),
                    reward != 0,
                    "Stored keeper membership exact"
                );
                if (reward != 0) ++keeperCount;
                uint256 available = _handler.entitlement(t, k);
                assertEq(
                    _payout.pendingPayout(address(token), recipients[k]),
                    available,
                    "Read-back agrees with model and current routing"
                );
                if (available != 0) ++recipientCount;
                uint256 paid = _handler.paid(t, k);
                distributed += paid;
                assertEq(
                    token.balanceOf(recipients[k]),
                    paid,
                    "Each recipient receives exactly its modelled deliveries"
                );
            }
            assertEq(
                _payout.getPendingKeepers(address(token)).length,
                keeperCount,
                "Keeper index has no stale entries"
            );
            assertEq(
                _payout.getPendingPayoutRecipients(address(token)).length,
                recipientCount,
                "Recipient index deduplicates overlapping roles"
            );
            assertEq(
                token.balanceOf(_destination),
                _handler.paid(t, 3),
                "Recovery destination gets exactly redirected amounts"
            );
            assertEq(
                token.totalSupply(),
                total + distributed + _handler.paid(t, 3),
                "Every minted unit is either backing or delivered"
            );
        }
        assertEq(
            _payout.getPendingPayoutTokens().length,
            indexedTokens,
            "Token index has no stale entries"
        );
    }
}

// forge-lint: disable-end(calls-loop, literal-instead-of-constant)
