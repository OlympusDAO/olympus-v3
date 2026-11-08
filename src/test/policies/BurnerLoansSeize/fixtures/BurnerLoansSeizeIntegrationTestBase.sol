// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansRisk} from "src/policies/interfaces/burnerloans/IBurnerLoansRisk.sol";

// Libraries
import {LoanParameters} from "src/policies/burnerloans/libraries/LoanParameters.sol";

// Contracts
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {BurnerLoansDebtTest} from "src/test/policies/BurnerLoansDebt/BurnerLoansDebtTest.sol";

// Literals are independent expected values and boundary seeds.
// Fixture casts are bounded; seed loops intentionally call external contracts.
// Fixture calls and ignored returns are checked through errors and ledger assertions.
// forge-lint: disable-start(literal-instead-of-constant, reentrancy-no-eth, unsafe-typecast, unused-return)

abstract contract BurnerLoansSeizeIntegrationTestBase is BurnerLoansDebtTest {
    address internal _keeper = address(0xfee);

    function _open(
        address asset_,
        address borrower_,
        uint128 collateral_,
        uint128 principal_
    ) internal {
        vm.mockCall(
            address(_risk),
            abi.encodeWithSelector(IBurnerLoansRisk.fee.selector),
            abi.encode(uint256(0), uint256(0))
        );
        MockERC20(asset_).mint(borrower_, collateral_);
        vm.startPrank(borrower_);
        assertTrue(
            MockERC20(asset_).approve(address(_core), type(uint256).max),
            "Borrower approves Core"
        );
        _collateral.depositCollateral(asset_, collateral_, borrower_);
        _debt.borrow(asset_, principal_, borrower_, borrower_, 0, address(0));
        vm.stopPrank();
    }

    function _admitVault(
        address asset_,
        address vault_,
        IBurnerLoansRisk.AssetRiskConfigInput memory risk_,
        bool shares_
    ) internal {
        _price.setPrice(asset_, 1e18);
        _depositManager.addAsset(IERC20(asset_), IERC4626(vault_), type(uint256).max, 0);
        _depositManager.addAssetPeriod(
            IERC20(asset_),
            LoanParameters._DEPOSIT_PERIOD,
            address(_core)
        );
        _config.addAsset(
            asset_,
            100_000e9,
            risk_,
            IBurnerLoansRisk.AssetFeeConfig(0, 0, 0, 0),
            shares_
        );
    }

    function _configure(address asset_, uint16 rewardBps_) internal {
        _config.setAssetRiskConfig(
            asset_,
            IBurnerLoansRisk.AssetRiskConfigInput(10000, 10000, rewardBps_, 30 days, 90 days, 1000)
        );
    }

    function _assertSeizure(
        address asset_,
        address token_,
        uint256 expectedReward_,
        uint256 expectedTreasury_
    ) internal {
        address[] memory borrowers = _single(_borrower);
        uint256 keeperBefore = IERC20(token_).balanceOf(_keeper);
        uint256 treasuryBefore = IERC20(token_).balanceOf(_payout.treasury());
        bytes32 beforeState = _stateDigestFor(asset_, _keeper);
        IBurnerLoansCore.SeizePreview memory quote = _liquidation.previewSeizeFor(
            _keeper,
            asset_,
            borrowers
        );
        assertEq(
            _stateDigestFor(asset_, _keeper),
            beforeState,
            "Preview preserves every ledger and custody component"
        );
        assertEq(quote.tokenOut, token_, "Quote uses actual output token");
        assertEq(
            quote.seizedDebtOhm,
            _lens.getPosition(asset_, _borrower).debtOhm,
            "Quote includes complete debt"
        );
        assertEq(
            quote.seizedCollateral,
            _lens.getPosition(asset_, _borrower).depositedCollateral,
            "Quote includes complete collateral"
        );
        assertEq(quote.keeperReward, expectedReward_, "Independent fixed reward");
        assertEq(quote.collateralToTreasury, expectedTreasury_, "Independent integer remainder");
        vm.prank(_keeper);
        (address output, uint256 reward, uint256 treasury) = _liquidation.seize(asset_, borrowers);
        assertEq(output, token_, "Underlying/share output identity");
        assertEq(reward, expectedReward_, "Settled fixed reward");
        assertEq(treasury, expectedTreasury_, "Settled fixed Treasury remainder");
        assertEq(
            IERC20(token_).balanceOf(_keeper),
            keeperBefore + reward + (_keeper == _payout.treasury() ? treasury : 0),
            "Exact keeper payment"
        );
        assertEq(
            IERC20(token_).balanceOf(_payout.treasury()),
            treasuryBefore + treasury + (_keeper == _payout.treasury() ? reward : 0),
            "Exact Treasury payment"
        );
        assertEq(
            _payout.pendingRecipientAmount(token_, _keeper),
            0,
            "No zero or paid keeper obligation"
        );
        _assertDefaulted(asset_, token_, quote.seizedDebtOhm);
    }

    function _single(address borrower_) internal pure returns (address[] memory borrowers) {
        borrowers = new address[](1);
        borrowers[0] = borrower_;
    }

    function _expire() internal {
        vm.warp(vm.getBlockTimestamp() + 30 days);
        _price.setTimestamp(uint48(vm.getBlockTimestamp()));
        _price.setPrice(address(_ohm), 1e18);
    }

    function _assertDefaulted(address asset_, address token_, uint256 debt_) internal view {
        assertEq(_inventory.activePrincipalOhm(), 0, "Default reconciles principal once");
        assertEq(_core.totalActiveDebtOhm(), 0, "Core aggregate debt cleared");
        assertEq(_lens.getPosition(asset_, _borrower).debtOhm, 0, "Position debt cleared");
        assertEq(
            _lens.getPosition(asset_, _borrower).depositedCollateral,
            0,
            "Position collateral cleared"
        );
        assertEq(
            _floan.getMarketPrincipalDefaulted(_core.marketId(asset_)),
            debt_,
            "Default booked exactly once"
        );
        assertEq(_floan.getActiveBorrowerCount(_core.marketId(asset_)), 0, "Active index cleared");
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(asset_), address(_core)),
            0,
            "DM liabilities cleared"
        );
        (uint256 fee, , uint256 seized, , uint256 total) = _payout.pendingAmounts(token_);
        assertEq(fee, 0, "No fee created by default");
        assertEq(seized, 0, "No paid Treasury reserve");
        assertEq(total, 0, "No paid reserve remains");
        assertEq(IERC20(token_).balanceOf(address(_payout)), 0, "No retained output");
    }
}

// forge-lint: disable-end(literal-instead-of-constant, reentrancy-no-eth, unsafe-typecast, unused-return)
