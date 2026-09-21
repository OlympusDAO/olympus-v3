// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

// Vault variants exercise the same withdrawal action and are intentionally co-located.
// Scenario-specific literals and ignored setup or revert-path return values remain explicit.
// forge-lint: disable-start(literal-instead-of-constant, unused-return)

// Interfaces
import {IERC20 as OZIERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IAssetManagerV1_1} from "src/bases/interfaces/IAssetManagerV1_1.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";

// Libraries
import {FullMath} from "src/libraries/FullMath.sol";

// Contracts
import {ReentrancyGuardTransient} from "@openzeppelin-5.7.0/utils/ReentrancyGuardTransient.sol";
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {ERC7540SyncDepositAsyncRedeemVault} from "src/test/policies/DepositManager/fixtures/ERC7540SyncDepositAsyncRedeemVault.sol";
import {MockERC7540ExternalShareVault} from "src/test/policies/DepositManager/fixtures/MockERC7540ExternalShareVault.sol";
import {MockERC7575Vault} from "src/test/policies/DepositManager/fixtures/MockERC7575Vault.sol";
import {ReentrantShareVault} from "src/test/policies/DepositManager/fixtures/ReentrantShareVault.sol";

// Test contracts
import {DepositManagerTest} from "src/test/policies/DepositManager/DepositManagerTest.sol";

contract DepositManagerWithdrawV1_1Test is DepositManagerTest {
    function test_givenThreeAssetsPerShare_whenSharesFractionalRounding()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenThreeAssetsPerShare
        givenDepositorHasAsset(300e18)
        givenDepositorHasApprovedSpendingAsset(300e18)
        givenDeposit(300e18, false)
        givenDepositorHasApprovedSpendingReceiptToken(300e18)
    {
        // 3 assets/share: floor(request / 3) shares, then shares * 3 underlying.
        // 1e18 and 2e18 requests leave one and two raw asset units respectively.
        _assertFractionalRounding(1, true, false, 0, 0);
        _assertFractionalRounding(2, true, false, 0, 0);
        _assertFractionalRounding(3, true, false, 1, 1);
        _assertFractionalRounding(4, true, false, 1, 1);
        _assertFractionalRounding(
            1e18,
            true,
            false,
            333_333_333_333_333_333,
            333_333_333_333_333_333
        );
        _assertFractionalRounding(
            2e18,
            true,
            false,
            666_666_666_666_666_666,
            666_666_666_666_666_666
        );
        _assertFractionalRounding(3e18, true, false, 1e18, 1e18);
    }

    function test_givenThreeAssetsPerShare_whenUnderlyingFractionalRounding()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenThreeAssetsPerShare
        givenDepositorHasAsset(300e18)
        givenDepositorHasApprovedSpendingAsset(300e18)
        givenDeposit(300e18, false)
        givenDepositorHasApprovedSpendingReceiptToken(300e18)
    {
        // 3 assets/share: floor(request / 3) shares, then shares * 3 underlying.
        // 1e18 and 2e18 requests leave one and two raw asset units respectively.
        _assertFractionalRounding(1, false, false, 0, 0);
        _assertFractionalRounding(2, false, false, 0, 0);
        _assertFractionalRounding(3, false, false, 3, 1);
        _assertFractionalRounding(4, false, false, 3, 1);
        _assertFractionalRounding(
            1e18,
            false,
            false,
            999_999_999_999_999_999,
            333_333_333_333_333_333
        );
        _assertFractionalRounding(
            2e18,
            false,
            false,
            1_999_999_999_999_999_998,
            666_666_666_666_666_666
        );
        _assertFractionalRounding(3e18, false, false, 3e18, 1e18);
    }

    function test_givenThreeAssetsPerShare_whenLegacyUnderlyingFractionalRounding()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenThreeAssetsPerShare
        givenDepositorHasAsset(300e18)
        givenDepositorHasApprovedSpendingAsset(300e18)
        givenDeposit(300e18, false)
        givenDepositorHasApprovedSpendingReceiptToken(300e18)
    {
        // 3 assets/share: floor(request / 3) shares, then shares * 3 underlying.
        // 1e18 and 2e18 requests leave one and two raw asset units respectively.
        _assertFractionalRounding(1, false, true, 0, 0);
        _assertFractionalRounding(2, false, true, 0, 0);
        _assertFractionalRounding(3, false, true, 3, 1);
        _assertFractionalRounding(4, false, true, 3, 1);
        _assertFractionalRounding(
            1e18,
            false,
            true,
            999_999_999_999_999_999,
            333_333_333_333_333_333
        );
        _assertFractionalRounding(
            2e18,
            false,
            true,
            1_999_999_999_999_999_998,
            666_666_666_666_666_666
        );
        _assertFractionalRounding(3e18, false, true, 3e18, 1e18);
    }

    function test_givenThreeFifthsAssetPerShare_whenSharesFractionalRounding()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenThreeFifthsAssetPerShare
        givenDepositorHasAsset(60e18)
        givenDepositorHasApprovedSpendingAsset(60e18)
        givenDeposit(60e18, false)
        givenDepositorHasApprovedSpendingReceiptToken(60e18)
    {
        // 0.6 assets/share: floor(request * 5 / 3) shares, then floor(shares * 3 / 5).
        // One raw share has zero underlying output; whole-token requests round at both steps.
        _assertFractionalRounding(1, true, false, 1, 1);
        _assertFractionalRounding(2, true, false, 3, 3);
        _assertFractionalRounding(3, true, false, 5, 5);
        _assertFractionalRounding(4, true, false, 6, 6);
        _assertFractionalRounding(
            1e18,
            true,
            false,
            1_666_666_666_666_666_666,
            1_666_666_666_666_666_666
        );
        _assertFractionalRounding(
            2e18,
            true,
            false,
            3_333_333_333_333_333_333,
            3_333_333_333_333_333_333
        );
        _assertFractionalRounding(3e18, true, false, 5e18, 5e18);
    }

    function test_givenThreeFifthsAssetPerShare_whenUnderlyingFractionalRounding()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenThreeFifthsAssetPerShare
        givenDepositorHasAsset(60e18)
        givenDepositorHasApprovedSpendingAsset(60e18)
        givenDeposit(60e18, false)
        givenDepositorHasApprovedSpendingReceiptToken(60e18)
    {
        // 0.6 assets/share: floor(request * 5 / 3) shares, then floor(shares * 3 / 5).
        // One raw share has zero underlying output; whole-token requests round at both steps.
        _assertFractionalRounding(1, false, false, 0, 0);
        _assertFractionalRounding(2, false, false, 1, 3);
        _assertFractionalRounding(3, false, false, 3, 5);
        _assertFractionalRounding(4, false, false, 3, 6);
        _assertFractionalRounding(
            1e18,
            false,
            false,
            999_999_999_999_999_999,
            1_666_666_666_666_666_666
        );
        _assertFractionalRounding(
            2e18,
            false,
            false,
            1_999_999_999_999_999_999,
            3_333_333_333_333_333_333
        );
        _assertFractionalRounding(3e18, false, false, 3e18, 5e18);
    }

    function test_givenThreeFifthsAssetPerShare_whenLegacyUnderlyingFractionalRounding()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenThreeFifthsAssetPerShare
        givenDepositorHasAsset(60e18)
        givenDepositorHasApprovedSpendingAsset(60e18)
        givenDeposit(60e18, false)
        givenDepositorHasApprovedSpendingReceiptToken(60e18)
    {
        // 0.6 assets/share: floor(request * 5 / 3) shares, then floor(shares * 3 / 5).
        // One raw share has zero underlying output; whole-token requests round at both steps.
        _assertFractionalRounding(1, false, true, 0, 0);
        _assertFractionalRounding(2, false, true, 1, 3);
        _assertFractionalRounding(3, false, true, 3, 5);
        _assertFractionalRounding(4, false, true, 3, 6);
        _assertFractionalRounding(
            1e18,
            false,
            true,
            999_999_999_999_999_999,
            1_666_666_666_666_666_666
        );
        _assertFractionalRounding(
            2e18,
            false,
            true,
            1_999_999_999_999_999_999,
            3_333_333_333_333_333_333
        );
        _assertFractionalRounding(3e18, false, true, 3e18, 5e18);
    }

    function _assertFractionalRounding(
        uint256 requested_,
        bool asShares_,
        bool legacy_,
        uint256 expectedOutput_,
        uint256 expectedSharesMoved_
    ) internal {
        // Snapshot isolates each declared boundary from earlier redemptions and rate changes.
        RoundingState memory beforeState = _snapshotRoundingState();
        (IERC20 previewToken, uint256 previewOutput) = IDepositManagerV1_1(address(depositManager))
            .previewWithdraw(iAsset, requested_, asShares_);
        assertEq(
            address(previewToken),
            asShares_ ? address(iVault) : address(iAsset),
            "fractional preview token"
        );
        assertEq(previewOutput, expectedOutput_, "literal fractional preview output");
        IDepositManager.WithdrawParams memory params = IDepositManager.WithdrawParams({
            asset: iAsset,
            depositPeriod: DEPOSIT_PERIOD,
            depositor: DEPOSITOR,
            recipient: RECIPIENT,
            amount: requested_,
            isWrapped: false
        });
        IERC20 tokenOut = iAsset;
        uint256 amountOut;
        vm.recordLogs();
        vm.prank(DEPOSIT_OPERATOR);
        if (legacy_) amountOut = depositManager.withdraw(params);
        else
            (tokenOut, amountOut) = IDepositManagerV1_1(address(depositManager)).withdraw(
                params,
                asShares_
            );
        assertEq(address(tokenOut), address(previewToken), "fractional execution token");
        assertEq(amountOut, expectedOutput_, "literal fractional execution output");
        assertEq(
            iAsset.balanceOf(RECIPIENT),
            asShares_ ? 0 : expectedOutput_,
            "actual recipient underlying"
        );
        assertEq(
            iVault.balanceOf(RECIPIENT),
            asShares_ ? expectedOutput_ : 0,
            "actual recipient shares"
        );
        (uint256 sharesAfter, ) = depositManager.getOperatorAssets(iAsset, DEPOSIT_OPERATOR);
        assertEq(
            sharesAfter,
            beforeState.sharesBefore - expectedSharesMoved_,
            "operator custody debit"
        );
        assertEq(vault.balanceOf(address(depositManager)), sharesAfter, "custody reconciles");
        assertEq(
            vault.totalSupply(),
            beforeState.vaultSupplyBefore - (asShares_ ? 0 : expectedSharesMoved_),
            "only underlying output burns shares"
        );
        assertEq(
            asset.balanceOf(address(vault)),
            beforeState.vaultAssetsBefore - (asShares_ ? 0 : expectedOutput_),
            "vault underlying delta"
        );
        assertEq(
            depositManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR),
            beforeState.liabilitiesBefore - requested_,
            "liability accounting"
        );
        assertEq(
            receiptTokenManager.balanceOf(DEPOSITOR, beforeState.receiptId),
            beforeState.receiptsBefore - requested_,
            "receipt accounting"
        );
        assertEq(
            depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
            beforeState.borrowedBefore,
            "borrowed accounting"
        );
        assertTrue(vm.revertToState(beforeState.snapshot), "restore isolated rounding case");
    }

    function _withdrawUnderlying(uint256 amount_) internal returns (IERC20, uint256) {
        vm.prank(DEPOSIT_OPERATOR);
        return
            IDepositManagerV1_1(address(depositManager)).withdraw(
                IDepositManager.WithdrawParams({
                    asset: iAsset,
                    depositPeriod: DEPOSIT_PERIOD,
                    depositor: DEPOSITOR,
                    recipient: RECIPIENT,
                    amount: amount_,
                    isWrapped: false
                }),
                false
            );
    }

    function test_givenVault_whenUnderlyingOutput(
        uint96 amount_
    )
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenDepositorHasApprovedSpendingReceiptToken(MINT_AMOUNT)
    {
        uint256 amount = bound(uint256(amount_), 1, previousDepositorDepositActualAmount);
        uint256 supply = vault.totalSupply();
        uint256 assets = asset.balanceOf(address(vault));
        // Raw 18-decimal units: floor assets->shares, then floor shares->assets.
        // mulDiv prevents phantom overflow in both intermediate products.
        uint256 shares = FullMath.mulDiv(amount, supply, assets);
        uint256 expected = FullMath.mulDiv(shares, assets, supply);
        (uint256 custodyBefore, ) = depositManager.getOperatorAssets(iAsset, DEPOSIT_OPERATOR);
        uint256 liabilityBefore = depositManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR);
        if (shares != 0) {
            vm.expectEmit(true, true, true, true);
            emit IAssetManager.AssetWithdrawn(
                address(iAsset),
                RECIPIENT,
                DEPOSIT_OPERATOR,
                expected,
                shares
            );
        }
        (IERC20 token, uint256 output) = _withdrawUnderlying(amount);
        assertEq(address(token), address(iAsset), "underlying token returned");
        assertEq(output, expected, "underlying output rounds down");
        assertEq(iAsset.balanceOf(RECIPIENT), expected, "actual underlying received");
        assertEq(iVault.balanceOf(RECIPIENT), 0, "recipient receives no shares");
        (uint256 custodyAfter, ) = depositManager.getOperatorAssets(iAsset, DEPOSIT_OPERATOR);
        assertEq(custodyAfter, custodyBefore - shares, "exact redeemed share debit");
        assertEq(
            depositManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR),
            liabilityBefore - amount,
            "requested liability debit"
        );
    }

    function test_givenExplicitShareWithdrawalRequirement_whenUnderlyingOutput_revertsAndRollsBack()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenDepositorHasApprovedSpendingReceiptToken(MINT_AMOUNT)
    {
        _setConfigOperator(CONFIG_OPERATOR);
        vm.prank(CONFIG_OPERATOR);
        depositManager.setAssetShareWithdrawalRequired(iAsset, true);
        uint256 receiptTokenId = depositManager.getReceiptTokenId(
            iAsset,
            DEPOSIT_PERIOD,
            DEPOSIT_OPERATOR
        );
        uint256 receiptsBefore = receiptTokenManager.balanceOf(DEPOSITOR, receiptTokenId);
        uint256 liabilitiesBefore = depositManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_RequiresWithdrawAsShares.selector,
                address(iAsset),
                address(iVault)
            )
        );
        _withdrawUnderlying(1e18);

        assertEq(
            receiptTokenManager.balanceOf(DEPOSITOR, receiptTokenId),
            receiptsBefore,
            "receipt balance rollback"
        );
        assertEq(
            depositManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR),
            liabilitiesBefore,
            "liability rollback"
        );
    }

    function test_givenIdleAsset_whenUnderlyingOutput()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAddedWithZeroAddress
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenDepositorHasApprovedSpendingReceiptToken(MINT_AMOUNT)
    {
        (IERC20 token, uint256 output) = _withdrawUnderlying(MINT_AMOUNT);
        assertEq(address(token), address(iAsset), "idle underlying token");
        assertEq(output, MINT_AMOUNT, "full idle output");
        assertEq(iAsset.balanceOf(RECIPIENT), MINT_AMOUNT, "idle recipient balance");
        assertEq(
            depositManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR),
            0,
            "idle liabilities cleared"
        );
    }

    function test_givenDisabled_whenUnderlyingOutput_reverts() public {
        _expectRevertNotEnabled();
        _withdrawUnderlying(1);
    }

    function test_whenUnderlyingAmountIsZero_reverts() public givenIsEnabled {
        vm.expectRevert(IAssetManager.AssetManager_ZeroAmount.selector);
        _withdrawUnderlying(0);
    }

    function test_givenUnauthorizedCaller_whenUnderlyingOutput_reverts(
        address caller_
    ) public givenIsEnabled {
        vm.assume(caller_ != DEPOSIT_OPERATOR);
        _expectRevertNotDepositOperator();
        vm.prank(caller_);
        IDepositManagerV1_1(address(depositManager)).withdraw(
            IDepositManager.WithdrawParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                recipient: RECIPIENT,
                amount: 1,
                isWrapped: false
            }),
            false
        );
    }

    function test_givenOutgoingShareCallback_cannotEnterBorrowingWithdrawal() public {
        MockERC20 underlying = new MockERC20("Share Asset", "sASSET", 18);
        ReentrantShareVault callbackVault = new ReentrantShareVault(ERC20(address(underlying)));
        IERC20 callbackAsset = IERC20(address(underlying));

        vm.startPrank(ADMIN);
        depositManager.enable("");
        depositManager.setOperatorName(DEPOSIT_OPERATOR, "shr");
        depositManager.addAsset(
            callbackAsset,
            IERC4626(address(callbackVault)),
            type(uint256).max,
            0
        );
        depositManager.addAssetPeriod(callbackAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        vm.stopPrank();

        uint256 depositAmount = 100e18;
        underlying.mint(DEPOSITOR, depositAmount);
        vm.prank(DEPOSITOR);
        underlying.approve(address(depositManager), depositAmount);
        vm.prank(DEPOSIT_OPERATOR);
        (uint256 receiptTokenId, ) = depositManager.deposit(
            IDepositManager.DepositParams({
                asset: callbackAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: depositAmount,
                shouldWrap: false
            })
        );
        vm.prank(DEPOSITOR);
        receiptTokenManager.approve(address(depositManager), receiptTokenId, depositAmount);

        IDepositManager.BorrowingWithdrawParams memory nestedParams = IDepositManager
            .BorrowingWithdrawParams({asset: callbackAsset, recipient: RECIPIENT, amount: 1});
        // The literal explicitly selects share output for the nested callback attempt.
        // forge-lint: disable-start(boolean-cst)
        callbackVault.setCallbackFrom(
            address(depositManager),
            address(depositManager),
            abi.encodeCall(IDepositManagerV1_1.borrowingWithdraw, (nestedParams, true))
        );
        // forge-lint: disable-end(boolean-cst)

        vm.prank(DEPOSIT_OPERATOR);
        (IERC20 tokenOut, uint256 amountOut) = IDepositManagerV1_1(address(depositManager))
            .withdraw(
                IDepositManager.WithdrawParams({
                    asset: callbackAsset,
                    depositPeriod: DEPOSIT_PERIOD,
                    depositor: DEPOSITOR,
                    recipient: RECIPIENT,
                    amount: 40e18,
                    isWrapped: false
                }),
                true
            );

        assertEq(address(tokenOut), address(callbackVault), "share token out");
        assertEq(amountOut, 40e18, "outer share amount");
        assertFalse(callbackVault.callbackSucceeded(), "nested borrowing withdrawal succeeded");
        assertEq(
            callbackVault.callbackRevertSelector(),
            ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector,
            "nested borrowing withdrawal revert"
        );
        assertEq(callbackVault.balanceOf(RECIPIENT), 40e18, "recipient share balance");
        assertEq(
            depositManager.getOperatorLiabilities(callbackAsset, DEPOSIT_OPERATOR),
            60e18,
            "liabilities debited once"
        );
        assertEq(
            depositManager.getBorrowedAmount(callbackAsset, DEPOSIT_OPERATOR),
            0,
            "nested borrowing accounting unchanged"
        );
    }

    function _withdrawAsSharesFrom(
        address caller_,
        address recipient_,
        uint256 amount_
    ) internal returns (IERC20 tokenOut, uint256 amountOut) {
        vm.prank(caller_);
        return
            IDepositManagerV1_1(address(depositManager)).withdraw(
                IDepositManager.WithdrawParams({
                    asset: iAsset,
                    depositPeriod: DEPOSIT_PERIOD,
                    depositor: DEPOSITOR,
                    recipient: recipient_,
                    amount: amount_,
                    isWrapped: false
                }),
                true
            );
    }

    function _withdrawAsShares(
        address recipient_,
        uint256 amount_
    ) internal returns (IERC20 tokenOut, uint256 amountOut) {
        return _withdrawAsSharesFrom(DEPOSIT_OPERATOR, recipient_, amount_);
    }

    function test_givenContractIsDisabled_reverts() public {
        _expectRevertNotEnabled();
        _withdrawAsShares(RECIPIENT, 1);
    }

    function test_givenCallerDoesNotHaveDepositOperatorRole_reverts(
        address caller_
    ) public givenIsEnabled {
        vm.assume(caller_ != DEPOSIT_OPERATOR);
        _expectRevertNotDepositOperator();
        _withdrawAsSharesFrom(caller_, RECIPIENT, 1);
    }

    function test_whenAmountIsZero_reverts() public givenIsEnabled givenFacilityNameIsSetDefault {
        vm.expectRevert(abi.encodeWithSelector(IAssetManager.AssetManager_ZeroAmount.selector));
        _withdrawAsShares(RECIPIENT, 0);
    }

    function test_whenRecipientIsDepositManager_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManagerV1_1.DepositManager_InvalidRecipient.selector,
                address(depositManager)
            )
        );
        _withdrawAsShares(address(depositManager), 1);
    }

    function test_givenIdleAsset_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAddedWithZeroAddress
    {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_VaultRequired.selector,
                address(iAsset)
            )
        );
        _withdrawAsShares(RECIPIENT, 1);
    }

    function test_givenVault_whenShareOutput()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenDepositorHasApprovedSpendingReceiptToken(MINT_AMOUNT)
    {
        uint256 requestedAssets = previousDepositorDepositActualAmount / 2;
        // requestedAssets and totalAssets use 18 asset decimals; totalSupply uses 18 share
        // decimals. floor(requestedAssets * totalSupply / totalAssets) therefore returns raw
        // 18-decimal shares and independently models the ERC-4626 conversion requirement.
        // mulDiv preserves floor rounding without risking intermediate-product overflow.
        uint256 expectedShares = FullMath.mulDiv(
            requestedAssets,
            vault.totalSupply(),
            asset.balanceOf(address(vault))
        );
        (uint256 operatorSharesBefore, ) = depositManager.getOperatorAssets(
            iAsset,
            DEPOSIT_OPERATOR
        );
        uint256 liabilitiesBefore = depositManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR);

        vm.expectEmit(true, true, true, true);
        emit IDepositManagerV1_1.AssetWithdrawn(
            address(iAsset),
            RECIPIENT,
            DEPOSIT_OPERATOR,
            requestedAssets,
            address(iVault),
            expectedShares
        );

        (IERC20 tokenOut, uint256 amountOut) = _withdrawAsShares(RECIPIENT, requestedAssets);

        assertEq(address(tokenOut), address(iVault), "tokenOut should be the vault share token");
        assertEq(amountOut, expectedShares, "amountOut should equal rounded-down shares");
        assertEq(iVault.balanceOf(RECIPIENT), expectedShares, "recipient share balance mismatch");
        assertEq(iAsset.balanceOf(RECIPIENT), 0, "recipient should not receive underlying assets");
        (uint256 operatorSharesAfter, ) = depositManager.getOperatorAssets(
            iAsset,
            DEPOSIT_OPERATOR
        );
        assertEq(
            operatorSharesAfter,
            operatorSharesBefore - expectedShares,
            "operator shares should decrease by exact shares transferred"
        );
        assertEq(
            depositManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR),
            liabilitiesBefore - requestedAssets,
            "liabilities should decrease by requested underlying assets"
        );
    }

    function test_givenContractIsReEnabled_whenShareOutput()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenDepositorHasApprovedSpendingReceiptToken(MINT_AMOUNT)
    {
        vm.prank(ADMIN);
        depositManager.disable("");
        vm.prank(ADMIN);
        depositManager.enable("");

        uint256 requestedAssets = previousDepositorDepositActualAmount / 2;
        (IERC20 tokenOut, uint256 amountOut) = _withdrawAsShares(RECIPIENT, requestedAssets);

        assertEq(address(tokenOut), address(iVault), "token out after re-enable");
        assertGt(amountOut, 0, "share output after re-enable");
    }

    function test_givenVault_whenShareOutputRoundsToZero()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenDepositorHasApprovedSpendingReceiptToken(MINT_AMOUNT)
    {
        _accrueYield(1000e18);
        assertEq(vault.convertToShares(1), 0, "one asset unit should round to zero shares");
        (uint256 sharesBefore, ) = depositManager.getOperatorAssets(iAsset, DEPOSIT_OPERATOR);
        uint256 liabilitiesBefore = depositManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR);

        vm.expectEmit(true, true, true, true, address(depositManager));
        emit IDepositManagerV1_1.AssetWithdrawn(
            address(iAsset),
            RECIPIENT,
            DEPOSIT_OPERATOR,
            1,
            address(iVault),
            0
        );
        vm.recordLogs();
        (IERC20 tokenOut, uint256 amountOut) = _withdrawAsShares(RECIPIENT, 1);

        (uint256 sharesAfter, ) = depositManager.getOperatorAssets(iAsset, DEPOSIT_OPERATOR);
        assertEq(address(tokenOut), address(iVault), "token out");
        assertEq(amountOut, 0, "zero output");
        assertEq(sharesAfter, sharesBefore, "operator shares unchanged");
        assertEq(iVault.balanceOf(RECIPIENT), 0, "recipient shares unchanged");
        assertEq(
            depositManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR),
            liabilitiesBefore - 1,
            "liability should decrease by the requested asset amount"
        );
        assertEq(vm.getRecordedLogs().length, 2, "receipt burn and withdrawal event count");
    }

    // ========== ERC-7540 ASYNC-REDEEM TESTS ========== //

    uint256 internal constant _ASSETS_PER_SHARE = 1e12;
    uint256 internal constant _DEPOSIT_AMOUNT = 10e18;

    MockERC7540ExternalShareVault internal _externalVault;
    IERC20 internal _externalShare;
    uint256 internal _receiptTokenId;

    function _configureAndDeposit() internal {
        _externalVault = new MockERC7540ExternalShareVault(asset, false, true, true);
        _externalShare = IERC20(_externalVault.share());

        vm.startPrank(ADMIN);
        depositManager.enable("");
        depositManager.addAsset(iAsset, IERC4626(address(_externalVault)), type(uint256).max, 0);
        depositManager.setOperatorName(DEPOSIT_OPERATOR, "cd1");
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        vm.stopPrank();

        _approveSpendingAsset(DEPOSITOR, _DEPOSIT_AMOUNT);
        vm.prank(DEPOSIT_OPERATOR);
        (_receiptTokenId, ) = depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: _DEPOSIT_AMOUNT,
                shouldWrap: false
            })
        );
    }

    function _withdrawOutput(uint256 amount_, bool asShares_) internal returns (IERC20, uint256) {
        vm.prank(DEPOSITOR);
        receiptTokenManager.approve(address(depositManager), _receiptTokenId, amount_);
        vm.prank(DEPOSIT_OPERATOR);
        return
            depositManager.withdraw(
                IDepositManager.WithdrawParams({
                    asset: iAsset,
                    depositPeriod: DEPOSIT_PERIOD,
                    depositor: DEPOSITOR,
                    recipient: RECIPIENT,
                    amount: amount_,
                    isWrapped: false
                }),
                asShares_
            );
    }

    function _expectAsyncUnderlyingRevert() internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_RequiresWithdrawAsShares.selector,
                address(iAsset),
                address(_externalVault)
            )
        );
    }

    function test_givenAsyncRedeem_whenPreviewingShareOutput() public {
        _configureAndDeposit();

        (IERC20 tokenOut, uint256 amountOut) = depositManager.previewWithdraw(iAsset, 3e18, true);

        assertEq(
            address(tokenOut),
            address(_externalShare),
            "preview should return external token"
        );
        assertEq(amountOut, 3e6, "preview should return raw six-decimal shares");
    }

    function test_givenAsyncRedeem_whenPreviewingUnderlyingOutput_reverts() public {
        _configureAndDeposit();

        _expectAsyncUnderlyingRevert();
        depositManager.previewWithdraw(iAsset, 3e18, false);
    }

    function test_givenAsyncRedeem_whenWithdrawingShares() public {
        _configureAndDeposit();

        (IERC20 tokenOut, uint256 amountOut) = _withdrawOutput(3e18, true);

        assertEq(
            address(tokenOut),
            address(_externalShare),
            "withdraw should return external token"
        );
        assertEq(amountOut, 3e6, "withdraw should return raw six-decimal shares");
        assertEq(_externalShare.balanceOf(RECIPIENT), 3e6, "recipient should receive shares");
        (uint256 operatorShares, ) = depositManager.getOperatorAssets(iAsset, DEPOSIT_OPERATOR);
        assertEq(operatorShares, 7e6, "operator shares should decrease by transferred shares");
    }

    function test_givenAsyncRedeemSelfShareToken_whenWithdrawingShares() public {
        ERC7540SyncDepositAsyncRedeemVault selfShareVault = new ERC7540SyncDepositAsyncRedeemVault(
            OZIERC20(address(asset))
        );
        vm.startPrank(ADMIN);
        depositManager.enable("");
        depositManager.addAsset(iAsset, IERC4626(address(selfShareVault)), type(uint256).max, 0);
        depositManager.setOperatorName(DEPOSIT_OPERATOR, "cd1");
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        vm.stopPrank();
        _approveSpendingAsset(DEPOSITOR, _DEPOSIT_AMOUNT);
        vm.prank(DEPOSIT_OPERATOR);
        (uint256 receiptTokenId, ) = depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: _DEPOSIT_AMOUNT,
                shouldWrap: false
            })
        );
        vm.prank(DEPOSITOR);
        receiptTokenManager.approve(address(depositManager), receiptTokenId, 3e18);

        (IERC20 previewToken, uint256 previewAmount) = depositManager.previewWithdraw(
            iAsset,
            3e18,
            true
        );
        vm.prank(DEPOSIT_OPERATOR);
        (IERC20 tokenOut, uint256 amountOut) = depositManager.withdraw(
            IDepositManager.WithdrawParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                recipient: RECIPIENT,
                amount: 3e18,
                isWrapped: false
            }),
            true
        );

        assertEq(address(previewToken), address(selfShareVault), "preview self-share token");
        assertEq(previewAmount, 3e18, "preview self-share amount");
        assertEq(address(tokenOut), address(selfShareVault), "self-share token out");
        assertEq(amountOut, 3e18, "self-shares out");
        assertEq(selfShareVault.balanceOf(RECIPIENT), 3e18, "recipient self-shares");
    }

    function test_givenAsyncRedeem_whenWithdrawingUnderlying_revertsAndRollsBackReceipts() public {
        _configureAndDeposit();
        uint256 receiptBalanceBefore = receiptTokenManager.balanceOf(DEPOSITOR, _receiptTokenId);

        vm.prank(DEPOSITOR);
        receiptTokenManager.approve(address(depositManager), _receiptTokenId, 3e18);
        _expectAsyncUnderlyingRevert();
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.withdraw(
            IDepositManager.WithdrawParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                recipient: RECIPIENT,
                amount: 3e18,
                isWrapped: false
            }),
            false
        );

        assertEq(
            receiptTokenManager.balanceOf(DEPOSITOR, _receiptTokenId),
            receiptBalanceBefore,
            "failed underlying exit should retain receipts"
        );
    }

    function test_givenAsyncRedeemBecomesSynchronous_whenWithdrawingUnderlying_succeeds() public {
        _configureAndDeposit();
        _externalVault.setCapabilities(false, false, true, true);

        (IERC20 previewToken, uint256 previewAmount) = depositManager.previewWithdraw(
            iAsset,
            3e18,
            false
        );
        (IERC20 tokenOut, uint256 amountOut) = _withdrawOutput(3e18, false);

        assertEq(address(previewToken), address(iAsset), "preview should return underlying");
        assertEq(previewAmount, 3e18, "preview underlying amount");
        assertEq(address(tokenOut), address(iAsset), "withdraw should return underlying");
        assertEq(amountOut, 3e18, "withdraw underlying amount");
        assertEq(asset.balanceOf(RECIPIENT), 3e18, "recipient should receive underlying");
        assertEq(_externalShare.balanceOf(address(depositManager)), 7e6, "custody shares");
    }

    function test_givenAsyncRedeemBecomesSynchronous_whenWithdrawingShares_succeeds() public {
        _configureAndDeposit();
        _externalVault.setCapabilities(false, false, true, true);

        (IERC20 previewToken, uint256 previewAmount) = depositManager.previewWithdraw(
            iAsset,
            3e18,
            true
        );
        (IERC20 tokenOut, uint256 amountOut) = _withdrawOutput(3e18, true);

        assertEq(address(previewToken), address(_externalShare), "preview should return shares");
        assertEq(previewAmount, 3e6, "preview share amount");
        assertEq(address(tokenOut), address(_externalShare), "withdraw should return shares");
        assertEq(amountOut, 3e6, "withdraw share amount");
        assertEq(_externalShare.balanceOf(RECIPIENT), 3e6, "recipient should receive shares");
        assertEq(_externalShare.balanceOf(address(depositManager)), 7e6, "custody shares");
    }

    function test_givenAsyncDepositBecomesEnabled_whenWithdrawingExistingShares_succeeds() public {
        _configureAndDeposit();
        _externalVault.setCapabilities(true, true, true, true);

        (uint256 operatorShares, uint256 operatorAssets) = depositManager.getOperatorAssets(
            iAsset,
            DEPOSIT_OPERATOR
        );
        (IERC20 previewToken, uint256 previewAmount) = depositManager.previewWithdraw(
            iAsset,
            3e18,
            true
        );

        (IERC20 tokenOut, uint256 amountOut) = _withdrawOutput(3e18, true);

        assertEq(operatorShares, 10e6, "existing custody shares");
        assertEq(operatorAssets, _DEPOSIT_AMOUNT, "existing custody assets");
        assertEq(address(previewToken), address(_externalShare), "preview output token");
        assertEq(previewAmount, 3e6, "preview output amount");
        assertEq(
            address(tokenOut),
            address(_externalShare),
            "withdraw should return external token"
        );
        assertEq(amountOut, 3e6, "withdraw should return raw shares");
        assertEq(_externalShare.balanceOf(RECIPIENT), 3e6, "recipient should receive shares");
    }

    function test_givenPositiveRequestBelowOneShare_whenWithdrawing_emitsZeroOutput() public {
        _configureAndDeposit();

        (IERC20 tokenOut, uint256 amountOut) = _withdrawOutput(_ASSETS_PER_SHARE - 1, true);

        assertEq(
            address(tokenOut),
            address(_externalShare),
            "zero output should report external token"
        );
        assertEq(amountOut, 0, "sub-share request should round to zero output");
        assertEq(_externalShare.balanceOf(RECIPIENT), 0, "zero output should transfer no shares");
    }

    // ========== ERC-7575 SYNC-REDEEM TESTS ========== //

    uint256 internal constant _WITHDRAW_AMOUNT = 3e18;

    function test_givenSynchronousERC7575SelfShare_whenWithdrawingUnderlying() public {
        _assertWithdrawal(false, false);
    }

    function test_givenSynchronousERC7575SelfShare_whenWithdrawingShares() public {
        _assertWithdrawal(false, true);
    }

    function test_givenSynchronousExternalShareTokenWithSameDecimals_whenWithdrawingUnderlying()
        public
    {
        _assertWithdrawal(true, false);
    }

    function test_givenSynchronousExternalShareTokenWithSameDecimals_whenWithdrawingShares()
        public
    {
        _assertWithdrawal(true, true);
    }

    function test_givenSynchronousExternalShareTokenWithDifferentDecimals_whenWithdrawingUnderlying()
        public
    {
        _assertDifferentDecimalExternalWithdrawal(false);
    }

    function test_givenSynchronousExternalShareTokenWithDifferentDecimals_whenWithdrawingShares()
        public
    {
        _assertDifferentDecimalExternalWithdrawal(true);
    }

    function _assertWithdrawal(bool externalShare_, bool withdrawAsShares_) internal {
        MockERC7575Vault erc7575Vault = new MockERC7575Vault(asset, externalShare_);
        IERC20 shareToken = IERC20(erc7575Vault.share());
        if (externalShare_) {
            assertNotEq(
                address(shareToken),
                address(erc7575Vault),
                "external share token should differ from vault"
            );
        }

        vm.startPrank(ADMIN);
        depositManager.enable("");
        depositManager.addAsset(iAsset, IERC4626(address(erc7575Vault)), type(uint256).max, 0);
        depositManager.setOperatorName(DEPOSIT_OPERATOR, "cd1");
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        vm.stopPrank();

        _approveSpendingAsset(DEPOSITOR, _DEPOSIT_AMOUNT);
        vm.prank(DEPOSIT_OPERATOR);
        (uint256 receiptTokenId, uint256 creditedAssets) = depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: _DEPOSIT_AMOUNT,
                shouldWrap: false
            })
        );
        vm.prank(DEPOSITOR);
        receiptTokenManager.approve(address(depositManager), receiptTokenId, _WITHDRAW_AMOUNT);
        vm.prank(DEPOSIT_OPERATOR);
        (IERC20 tokenOut, uint256 amountOut) = depositManager.withdraw(
            IDepositManager.WithdrawParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                recipient: RECIPIENT,
                amount: _WITHDRAW_AMOUNT,
                isWrapped: false
            }),
            withdrawAsShares_
        );

        IERC20 expectedToken = withdrawAsShares_ ? shareToken : iAsset;
        assertEq(creditedAssets, _DEPOSIT_AMOUNT, "deposit credit");
        assertEq(address(tokenOut), address(expectedToken), "output token");
        assertEq(amountOut, _WITHDRAW_AMOUNT, "output amount");
        assertEq(expectedToken.balanceOf(RECIPIENT), _WITHDRAW_AMOUNT, "recipient output");
        assertEq(shareToken.balanceOf(address(depositManager)), 7e18, "remaining shares");
    }

    function _assertDifferentDecimalExternalWithdrawal(bool withdrawAsShares_) internal {
        MockERC7540ExternalShareVault externalVault = new MockERC7540ExternalShareVault(
            asset,
            false,
            false,
            true
        );
        IERC20 shareToken = IERC20(externalVault.share());
        assertNotEq(address(shareToken), address(externalVault), "external token should differ");

        vm.startPrank(ADMIN);
        depositManager.enable("");
        depositManager.addAsset(iAsset, IERC4626(address(externalVault)), type(uint256).max, 0);
        depositManager.setOperatorName(DEPOSIT_OPERATOR, "cd1");
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        vm.stopPrank();

        _approveSpendingAsset(DEPOSITOR, _DEPOSIT_AMOUNT);
        vm.prank(DEPOSIT_OPERATOR);
        (uint256 receiptTokenId, ) = depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: _DEPOSIT_AMOUNT,
                shouldWrap: false
            })
        );
        vm.prank(DEPOSITOR);
        receiptTokenManager.approve(address(depositManager), receiptTokenId, _WITHDRAW_AMOUNT);

        (IERC20 previewToken, uint256 previewAmount) = depositManager.previewWithdraw(
            iAsset,
            _WITHDRAW_AMOUNT,
            withdrawAsShares_
        );
        vm.prank(DEPOSIT_OPERATOR);
        (IERC20 tokenOut, uint256 amountOut) = depositManager.withdraw(
            IDepositManager.WithdrawParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                recipient: RECIPIENT,
                amount: _WITHDRAW_AMOUNT,
                isWrapped: false
            }),
            withdrawAsShares_
        );

        IERC20 expectedToken = withdrawAsShares_ ? shareToken : iAsset;
        uint256 expectedAmount = withdrawAsShares_ ? 3e6 : _WITHDRAW_AMOUNT;
        assertEq(asset.decimals(), 18, "underlying decimals");
        assertEq(shareToken.decimals(), 6, "share decimals");
        assertEq(address(previewToken), address(expectedToken), "preview token");
        assertEq(previewAmount, expectedAmount, "preview amount");
        assertEq(address(tokenOut), address(expectedToken), "output token");
        assertEq(amountOut, expectedAmount, "output amount");
        assertEq(expectedToken.balanceOf(RECIPIENT), expectedAmount, "recipient output");
    }
}

// forge-lint: disable-end(literal-instead-of-constant, unused-return)
