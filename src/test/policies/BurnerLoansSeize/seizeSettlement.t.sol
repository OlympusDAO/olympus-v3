// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/burnerloans/IBurnerLoansInventory.sol";
import {IBurnerLoansPayout} from "src/policies/interfaces/burnerloans/IBurnerLoansPayout.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";

// Libraries
import {SafeCast} from "@openzeppelin-5.7.0/utils/math/SafeCast.sol";

// Contracts
import {BurnerLoansSeizeTestBase} from "src/test/policies/BurnerLoansSeize/fixtures/BurnerLoansSeizeTestBase.sol";

// Literals are independent expected values and boundary seeds.
// Fixture calls and ignored returns are checked through errors and ledger assertions.
// forge-lint: disable-start(literal-instead-of-constant, unused-return)

contract BurnerLoansSeizeSettlementTest is BurnerLoansSeizeTestBase {
    // Scenarios: BLLIQ-SEIZE-T03.
    function test_givenRiskRewardExceedsOutput_whenSeized_reverts() public {
        vm.mockCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.keeperReward.selector),
            abi.encode(uint256(2000e6 + 1))
        );
        _expectRejected(
            abi.encodeWithSelector(IBurnerLoansCore.BurnerLoansCore_InvalidSettlement.selector),
            _borrowers(),
            _recipient
        );
    }

    // Scenarios: BLLIQ-SEIZE-T05.
    function test_givenLateInventoryFailure_whenSeized_thenAllAccountingRollsBack() public {
        vm.mockCallRevert(
            address(_inventory),
            abi.encodeWithSelector(IBurnerLoansInventory.settleDefault.selector),
            abi.encodeWithSelector(DefaultFailed.selector)
        );
        _expectSettlementRevert(abi.encodeWithSelector(DefaultFailed.selector));
    }

    // Scenarios: BLLIQ-SEIZE-T01.
    function test_givenUnexpectedRedemptionToken_whenSeized_thenDefaultRollsBack() public {
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSelector(IDepositManagerV1_1.withdraw.selector),
            abi.encode(address(_ohm), uint256(2000e6))
        );
        _expectSettlementRevert(
            abi.encodeWithSelector(IBurnerLoansCore.BurnerLoansCore_InvalidSettlement.selector)
        );
    }

    // Scenarios: BLLIQ-SEIZE-T02.
    function test_givenOldCustodySurplus_whenNewReceiptShort_thenSurplusCannotMaskIt() public {
        _asset.mint(address(_payout), 2000e6);
        vm.mockCall(
            address(_depositManager),
            abi.encodeWithSelector(IDepositManagerV1_1.withdraw.selector),
            abi.encode(address(_asset), uint256(2000e6))
        );
        _expectSettlementRevert(
            abi.encodeWithSelector(IBurnerLoansCore.BurnerLoansCore_InvalidSettlement.selector)
        );
        assertEq(
            _asset.balanceOf(address(_payout)),
            2000e6,
            "Old surplus preserved and not credited"
        );
    }

    // Scenarios: BLLIQ-SEIZE-T06.
    function test_givenCustodyCreditFailure_whenSeized_thenEverythingRollsBack() public {
        vm.mockCallRevert(
            address(_payout),
            abi.encodeWithSelector(IBurnerLoansPayout.creditSeizure.selector),
            abi.encodeWithSelector(IBurnerLoansCore.BurnerLoansCore_InvalidSettlement.selector)
        );
        _expectSettlementRevert(
            abi.encodeWithSelector(IBurnerLoansCore.BurnerLoansCore_InvalidSettlement.selector)
        );
    }

    // Scenarios: BLLIQ-SEIZE-T04.
    function test_givenInjectedAggregateDebtOverflow_whenSeized_thenTypedFailureAndRollback()
        public
    {
        _asset.mint(_recipient, 20e6);
        vm.startPrank(_recipient);
        _asset.approve(address(_core), type(uint256).max);
        _collateral.depositCollateral(address(_asset), 20e6, _recipient);
        _debt.borrow(address(_asset), 1, _recipient, _recipient, 0, address(0));
        vm.stopPrank();
        address[] memory borrowers = new address[](2);
        borrowers[0] = _borrower;
        borrowers[1] = _recipient;
        vm.mockCall(
            address(_floan),
            abi.encodeWithSelector(IFLOANv1.defaultPosition.selector),
            abi.encode(type(uint128).max, uint256(0), uint128(1))
        );
        vm.mockCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.keeperReward.selector),
            abi.encode(uint256(0))
        );
        uint256 total = uint256(type(uint128).max) * 2;
        bytes32 beforeState = _seizeDigest(_recipient);
        vm.expectRevert(
            abi.encodeWithSelector(SafeCast.SafeCastOverflowedUintDowncast.selector, 128, total)
        );
        vm.prank(_recipient);
        _liquidation.seize(address(_asset), borrowers);
        assertEq(
            _seizeDigest(_recipient),
            beforeState,
            "Typed aggregate failure restores every ledger and custody component"
        );
        assertEq(
            _lens.getPosition(address(_asset), _recipient).debtOhm,
            1,
            "Other position preserved on aggregate failure"
        );
        assertEq(
            _asset.balanceOf(address(_depositManager)),
            2020e6,
            "Synthetic aggregate failure restores redemption"
        );
        assertEq(
            _inventory.activePrincipalOhm(),
            100e9 + 1,
            "Synthetic aggregate failure leaves real principal unchanged"
        );
    }

    function test_givenRedemptionFailure_whenSeized_thenDefaultRollsBack() public {
        vm.mockCallRevert(
            address(_depositManager),
            abi.encodeWithSelector(IDepositManagerV1_1.withdraw.selector),
            abi.encodeWithSelector(DefaultFailed.selector)
        );
        _expectSettlementRevert(abi.encodeWithSelector(DefaultFailed.selector));
    }
}

// forge-lint: disable-end(literal-instead-of-constant, unused-return)
