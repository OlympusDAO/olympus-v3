// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";

// Contracts
import {ReentrancyGuard} from "@openzeppelin-5.7.0/utils/ReentrancyGuard.sol";
import {ReentrantFeeToken} from "src/test/mocks/ReentrantFeeToken.sol";
import {BurnerLoansSeizeIntegrationTestBase} from "src/test/policies/BurnerLoansSeize/fixtures/BurnerLoansSeizeIntegrationTestBase.sol";

// Literals are independent expected values and boundary seeds.
// Fixture calls and ignored returns are checked through errors and ledger assertions.
// forge-lint: disable-start(literal-instead-of-constant, unused-return)

contract BurnerLoansSeizeCallbackTest is BurnerLoansSeizeIntegrationTestBase {
    ReentrantFeeToken internal _token;

    function setUp() public override {
        super.setUp();
        _token = new ReentrantFeeToken();
        _price.setPrice(address(_token), 1e18);
        _admit(address(_token));
        _open(address(_token), _borrower, 2000e18, 100e9);
        _open(address(_token), _recipient, 2000e18, 100e9);
        _expire();
        _price.setPrice(address(_token), 1e18);
        _token.setCallbackFrom(
            address(_depositManager),
            address(_liquidation),
            abi.encodeCall(_liquidation.seize, (address(_token), _single(_recipient)))
        );
    }

    function test_givenCaughtCollateralCallback_whenSeized_thenOnlyOuterDebtDefaults() public {
        vm.prank(_keeper);
        _liquidation.seize(address(_token), _single(_borrower));
        assertEq(
            _token.callbackRevertSelector(),
            ReentrancyGuard.ReentrancyGuardReentrantCall.selector,
            "Eligible nested seizure reaches Core guard"
        );
        assertEq(
            _lens.getPosition(address(_token), _borrower).debtOhm,
            0,
            "Outer debt defaulted once"
        );
        assertEq(
            _lens.getPosition(address(_token), _recipient).debtOhm,
            100e9,
            "Nested debt unchanged"
        );
        assertEq(
            _lens.getPosition(address(_token), _recipient).depositedCollateral,
            2000e18,
            "Nested collateral unchanged"
        );
        assertEq(_inventory.activePrincipalOhm(), 100e9, "Only outer principal defaulted");
        assertEq(
            _token.balanceOf(address(_depositManager)),
            2000e18,
            "Only outer custody redeemed"
        );
        assertEq(
            _floan.getMarketPrincipalDefaulted(_core.marketId(address(_token))),
            100e9,
            "Default counted once"
        );
    }

    // Scenarios: BLLIQ-SEIZE-C02.
    function test_givenPropagatedCollateralCallback_whenSeized_thenMandatoryTransferRollsBack()
        public
    {
        // Quotes do not execute token callbacks; the same eligible batch quotes before transfer.
        IBurnerLoansCore.SeizePreview memory quote = _liquidation.previewSeizeFor(
            _keeper,
            address(_token),
            _single(_borrower)
        );
        assertEq(
            quote.seizedDebtOhm,
            100e9,
            "Eligible outer batch quotes independently of token delivery"
        );
        _token.setBubbleCallbackFailure(true);
        bytes32 beforeState = _stateDigestFor(address(_token), _keeper);
        vm.expectRevert(ReentrantFeeToken.CallbackFailed.selector);
        vm.prank(_keeper);
        _liquidation.seize(address(_token), _single(_borrower));
        assertEq(
            _stateDigestFor(address(_token), _keeper),
            beforeState,
            "All ledgers, receipts, custody and allowances restored"
        );
        assertEq(
            _lens.getPosition(address(_token), _recipient).debtOhm,
            100e9,
            "Nested position untouched"
        );
        assertEq(
            _floan.getMarketPrincipalDefaulted(_core.marketId(address(_token))),
            0,
            "No default committed"
        );
    }
}

// forge-lint: disable-end(literal-instead-of-constant, unused-return)
