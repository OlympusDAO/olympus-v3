// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoansCollateral} from "src/policies/interfaces/burnerloans/IBurnerLoansCollateral.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";

// Contracts
import {Actions, Policy} from "src/Kernel.sol";
import {MockERC20} from "src/test/mocks/MockERC20.sol";
import {BurnerLoansModularTest} from "src/test/policies/BurnerLoansCore/fixtures/BurnerLoansModularTest.sol";

// Fixed boundary values, bound-checked casts and unused revert-path returns are intentional.
// Fixture/seed loops call real dependencies; sequential setup calls are completed before reuse.
// forge-lint: disable-start(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)

abstract contract BurnerLoansCollateralActionTest is BurnerLoansModularTest {
    address internal constant _OTHER_BORROWER = address(0xC011A7);

    modifier givenDebtFreeCollateral() {
        _depositAsset(_asset, 100e6, _borrower);
        _;
    }

    function _depositAsset(MockERC20 asset_, uint128 amount_, address borrower_) internal {
        asset_.mint(borrower_, amount_);
        vm.startPrank(borrower_);
        asset_.approve(address(_core), type(uint256).max);
        _collateral.depositCollateral(address(asset_), amount_, borrower_);
        vm.stopPrank();
    }

    function _setPolicyState(Policy subject_, bool active_, bool enabled_) internal {
        // Fixtures start active/enabled; lifecycle axes vary independently.
        if (!enabled_) IEnabler(address(subject_)).disable("");
        if (!active_) _kernel.executeAction(Actions.DeactivatePolicy, address(subject_));
    }

    function _grantOperator(uint48 deadline_) internal {
        vm.warp(1);
        vm.prank(_borrower);
        _core.setAuthorization(_recipient, deadline_);
    }

    function _accountingDigest(address asset_) internal view returns (bytes32) {
        IERC20 token = IERC20(asset_);
        bytes32 positions = keccak256(
            abi.encode(
                _lens.getPosition(asset_, _borrower),
                _lens.getPosition(asset_, _OTHER_BORROWER),
                _floan.getActiveBorrowerCount(_core.marketId(asset_)),
                _inventory.activePrincipalOhm()
            )
        );
        bytes32 wallets = keccak256(
            abi.encode(
                token.balanceOf(_borrower),
                token.balanceOf(_recipient),
                token.balanceOf(address(_core)),
                token.balanceOf(address(_depositManager)),
                token.balanceOf(_OTHER_BORROWER),
                token.allowance(_borrower, address(_core)),
                token.allowance(_recipient, address(_core)),
                token.allowance(address(_core), address(_depositManager))
            )
        );
        uint256 id = _depositManager.getReceiptTokenId(token, 1, address(_core));
        (uint256 shares, uint256 assets) = _depositManager.getOperatorAssets(token, address(_core));
        return
            keccak256(
                abi.encode(
                    positions,
                    wallets,
                    shares,
                    assets,
                    _depositManager.getBorrowedAmount(token, address(_core)),
                    _depositManager.getOperatorLiabilities(token, address(_core)),
                    _depositManager.getReceiptTokenManager().balanceOf(address(_core), id),
                    _depositManager.getReceiptTokenManager().allowance(
                        address(_core),
                        address(_depositManager),
                        id
                    )
                )
            );
    }

    function _expectDepositRevert(bytes memory reason_, address caller_, uint128 amount_) internal {
        bytes32 beforeState = _accountingDigest(address(_asset));
        vm.expectRevert(reason_);
        vm.prank(caller_);
        _collateral.previewDepositCollateral(address(_asset), amount_, _borrower);
        assertEq(
            _accountingDigest(address(_asset)),
            beforeState,
            "Rejected quote preserves accounting"
        );
        _expectDepositExecutionRevert(reason_, caller_, amount_);
    }

    function _expectWithdrawRevert(
        bytes memory reason_,
        address caller_,
        uint128 amount_
    ) internal {
        bytes32 beforeState = _accountingDigest(address(_asset));
        vm.expectRevert(reason_);
        vm.prank(caller_);
        _collateral.previewWithdrawCollateral(address(_asset), amount_, _borrower, _recipient);
        assertEq(
            _accountingDigest(address(_asset)),
            beforeState,
            "Rejected quote preserves accounting"
        );
        _expectWithdrawExecutionRevert(reason_, caller_, amount_);
    }

    function _assertDirectCollateral(uint128 collateral_) internal view {
        assertEq(
            _lens.getPosition(address(_asset), _borrower).depositedCollateral,
            collateral_,
            "FLOAN collateral matches actual credit/debit"
        );
        assertEq(
            _depositManager.getOperatorLiabilities(IERC20(address(_asset)), address(_core)),
            collateral_,
            "DM liability matches collateral"
        );
        uint256 id = _depositManager.getReceiptTokenId(IERC20(address(_asset)), 1, address(_core));
        assertEq(
            _depositManager.getReceiptTokenManager().balanceOf(address(_core), id),
            collateral_,
            "Core receipts match liability"
        );
        assertEq(
            _asset.balanceOf(address(_depositManager)),
            collateral_,
            "Underlying backs collateral"
        );
        assertEq(_asset.balanceOf(address(_core)), 0, "Core retains no transient asset");
    }

    function _assertWithdrawal(
        IBurnerLoansCollateral.WithdrawPreview memory result_,
        address token_,
        uint256 output_,
        uint128 remaining_,
        uint256 health_
    ) internal pure {
        assertEq(result_.returnToken, token_, "Exact output token");
        assertEq(result_.returnAmount, output_, "Exact output amount");
        assertEq(result_.remainingDepositedCollateral, remaining_, "Exact remaining collateral");
        assertEq(result_.resultingHealthFactor, health_, "Exact resulting health");
    }

    function _assertDirectDeposit(address caller_, uint128 amount_, uint128 prior_) internal {
        _asset.mint(caller_, amount_);
        vm.prank(caller_);
        _asset.approve(address(_core), type(uint256).max);
        uint256 beforeWallet = _asset.balanceOf(caller_);
        bytes32 beforeQuote = _accountingDigest(address(_asset));
        IBurnerLoansCore.Position memory position = _lens.getPosition(address(_asset), _borrower);
        vm.prank(caller_);
        (uint256 q, uint256 c, uint256 h) = _collateral.previewDepositCollateral(
            address(_asset),
            amount_,
            _borrower
        );
        assertEq(q, amount_, "Direct preview credit equals requested units");
        assertEq(c, uint256(prior_) + amount_, "Independent preview total");
        assertEq(h, type(uint256).max, "Debt-free preview health");
        assertEq(
            _accountingDigest(address(_asset)),
            beforeQuote,
            "Preview makes no accounting changes"
        );
        vm.expectEmit(address(_collateral));
        emit IBurnerLoansCollateral.CollateralDeposited(
            caller_,
            address(_asset),
            _borrower,
            amount_,
            amount_
        );
        vm.prank(caller_);
        (uint128 credit, uint128 total, uint256 health) = _collateral.depositCollateral(
            address(_asset),
            amount_,
            _borrower
        );
        assertEq(credit, amount_, "Exact direct credit");
        assertEq(total, c, "Returned total agrees with independently checked quote");
        assertEq(health, type(uint256).max, "Debt-free returned health");
        assertEq(
            _asset.balanceOf(caller_),
            beforeWallet - amount_,
            "Only actual payer funds the deposit"
        );
        _assertDirectCollateral(total);
        IBurnerLoansCore.Position memory afterPosition = _lens.getPosition(
            address(_asset),
            _borrower
        );
        assertEq(afterPosition.debtOhm, position.debtOhm, "Deposit preserves debt");
        assertEq(afterPosition.maturity, position.maturity, "Deposit preserves debt expiry");
        assertEq(
            afterPosition.lastBorrowBlock,
            position.lastBorrowBlock,
            "Deposit preserves debt episode"
        );
    }

    function _assertDirectWithdrawal(address caller_, uint128 amount_, uint128 prior_) internal {
        bytes32 beforeQuote = _accountingDigest(address(_asset));
        uint256 beforeRecipient = _asset.balanceOf(_recipient);
        IBurnerLoansCore.Position memory position = _lens.getPosition(address(_asset), _borrower);
        vm.prank(caller_);
        IBurnerLoansCollateral.WithdrawPreview memory quote = _collateral.previewWithdrawCollateral(
            address(_asset),
            amount_,
            _borrower,
            _recipient
        );
        _assertWithdrawal(quote, address(_asset), amount_, prior_ - amount_, type(uint256).max);
        assertEq(
            _accountingDigest(address(_asset)),
            beforeQuote,
            "Withdrawal quote makes no accounting changes"
        );
        vm.expectEmit(address(_collateral));
        emit IBurnerLoansCollateral.CollateralWithdrawn(
            caller_,
            address(_asset),
            _borrower,
            _recipient,
            amount_,
            address(_asset),
            amount_
        );
        vm.prank(caller_);
        IBurnerLoansCollateral.WithdrawPreview memory actual = _collateral.withdrawCollateral(
            address(_asset),
            amount_,
            _borrower,
            _recipient
        );
        _assertWithdrawal(actual, address(_asset), amount_, prior_ - amount_, type(uint256).max);
        _assertDirectCollateral(prior_ - amount_);
        assertEq(
            _asset.balanceOf(_recipient),
            beforeRecipient + amount_,
            "Specified recipient receives actual output"
        );
        IBurnerLoansCore.Position memory afterPosition = _lens.getPosition(
            address(_asset),
            _borrower
        );
        assertEq(afterPosition.debtOhm, position.debtOhm, "Withdrawal preserves debt");
        assertEq(afterPosition.maturity, position.maturity, "Withdrawal preserves expiry");
        assertEq(
            afterPosition.lastBorrowBlock,
            position.lastBorrowBlock,
            "Withdrawal preserves debt episode"
        );
    }

    function _assertInitialDepositQuote(
        address asset_,
        uint128 amount_,
        uint256 expectedCredit_
    ) internal {
        bytes32 beforeState = _accountingDigest(asset_);
        vm.prank(_borrower);
        (uint256 credit, uint256 collateral, uint256 health) = _collateral.previewDepositCollateral(
            asset_,
            amount_,
            _borrower
        );
        assertEq(credit, expectedCredit_, "Independent initial credit quote");
        assertEq(collateral, expectedCredit_, "Independent new-position collateral quote");
        assertEq(health, type(uint256).max, "New-position quote is debt-free");
        assertEq(
            _accountingDigest(asset_),
            beforeState,
            "Quote performs no real delivery, approval or settlement"
        );
    }

    function _expectDepositExecutionRevert(
        bytes memory reason_,
        address caller_,
        uint128 amount_
    ) internal {
        bytes32 beforeState = _accountingDigest(address(_asset));
        vm.expectRevert(reason_);
        vm.prank(caller_);
        _collateral.depositCollateral(address(_asset), amount_, _borrower);
        assertEq(
            _accountingDigest(address(_asset)),
            beforeState,
            "Rejected deposit restores accounting"
        );
    }

    function _expectWithdrawExecutionRevert(
        bytes memory reason_,
        address caller_,
        uint128 amount_
    ) internal {
        bytes32 beforeState = _accountingDigest(address(_asset));
        vm.expectRevert(reason_);
        vm.prank(caller_);
        _collateral.withdrawCollateral(address(_asset), amount_, _borrower, _recipient);
        assertEq(
            _accountingDigest(address(_asset)),
            beforeState,
            "Rejected withdrawal restores accounting"
        );
    }
}

// forge-lint: disable-end(literal-instead-of-constant,unsafe-typecast,unused-return,calls-loop,reentrancy-no-eth)
