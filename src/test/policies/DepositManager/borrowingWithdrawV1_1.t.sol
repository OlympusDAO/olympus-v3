// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

// Scenario-specific literals remain inline for auditability. Revert-path calls and tuple
// destructuring intentionally ignore return values that the corresponding assertions do not use.
// forge-lint: disable-start(literal-instead-of-constant, unused-return)

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IERC20 as OZIERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IAssetManagerV1_1} from "src/bases/interfaces/IAssetManagerV1_1.sol";

// Libraries
import {FullMath} from "src/libraries/FullMath.sol";

// Test contracts
import {DepositManagerTest} from "src/test/policies/DepositManager/DepositManagerTest.sol";
import {MockERC7540ExternalShareToken, MockERC7540ExternalShareVault} from "src/test/policies/DepositManager/fixtures/MockERC7540ExternalShareVault.sol";
import {ERC7540SyncDepositAsyncRedeemVault} from "src/test/policies/DepositManager/fixtures/ERC7540SyncDepositAsyncRedeemVault.sol";

contract DepositManagerBorrowingWithdrawV1_1Test is DepositManagerTest {
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
        IDepositManager.BorrowingWithdrawParams memory params = IDepositManager
            .BorrowingWithdrawParams({asset: iAsset, recipient: RECIPIENT, amount: requested_});
        IERC20 tokenOut = iAsset;
        uint256 amountOut;
        bool shouldRevert = !legacy_ && expectedOutput_ == 0;
        if (shouldRevert) vm.expectRevert(IDepositManagerV1_1.DepositManager_ZeroOutput.selector);
        vm.recordLogs();
        vm.prank(DEPOSIT_OPERATOR);
        if (legacy_) amountOut = depositManager.borrowingWithdraw(params);
        else
            (tokenOut, amountOut) = IDepositManagerV1_1(address(depositManager)).borrowingWithdraw(
                params,
                asShares_
            );
        if (!shouldRevert) {
            assertEq(address(tokenOut), address(previewToken), "fractional execution token");
            assertEq(amountOut, expectedOutput_, "literal fractional execution output");
        }
        // recordLogs observes even reverted EVM log instructions. The exact revert above and
        // the balance/accounting assertions below establish atomic rollback instead.
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
            beforeState.liabilitiesBefore,
            "liability accounting"
        );
        assertEq(
            receiptTokenManager.balanceOf(DEPOSITOR, beforeState.receiptId),
            beforeState.receiptsBefore,
            "receipt accounting"
        );
        assertEq(
            depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
            beforeState.borrowedBefore + (shouldRevert ? 0 : requested_),
            "borrowed accounting"
        );
        assertTrue(vm.revertToState(beforeState.snapshot), "restore isolated rounding case");
    }

    function test_givenContractIsDisabled_reverts() public {
        _expectRevertNotEnabled();
        vm.prank(DEPOSIT_OPERATOR);
        IDepositManagerV1_1(address(depositManager)).borrowingWithdraw(
            IDepositManager.BorrowingWithdrawParams({
                asset: iAsset,
                recipient: RECIPIENT,
                amount: 1
            }),
            true
        );
    }

    function test_givenCallerDoesNotHaveDepositOperatorRole_reverts(
        address caller_
    ) public givenIsEnabled {
        vm.assume(caller_ != DEPOSIT_OPERATOR);
        _expectRevertNotDepositOperator();
        vm.prank(caller_);
        IDepositManagerV1_1(address(depositManager)).borrowingWithdraw(
            IDepositManager.BorrowingWithdrawParams({
                asset: iAsset,
                recipient: RECIPIENT,
                amount: 1
            }),
            true
        );
    }

    function test_whenAmountIsZero_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
    {
        vm.expectRevert(abi.encodeWithSelector(IAssetManager.AssetManager_ZeroAmount.selector));
        vm.prank(DEPOSIT_OPERATOR);
        IDepositManagerV1_1(address(depositManager)).borrowingWithdraw(
            IDepositManager.BorrowingWithdrawParams({
                asset: iAsset,
                recipient: RECIPIENT,
                amount: 0
            }),
            true
        );
    }

    function test_givenVault_whenShareOutput()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
    {
        uint256 requestedAssets = previousDepositorDepositActualAmount / 2;
        // requestedAssets and totalAssets use 18 asset decimals; totalSupply uses 18 share
        // decimals. The floor division independently derives the raw share-token output.
        // mulDiv preserves floor rounding without risking intermediate-product overflow.
        uint256 expectedShares = FullMath.mulDiv(
            requestedAssets,
            vault.totalSupply(),
            asset.balanceOf(address(vault))
        );

        vm.prank(DEPOSIT_OPERATOR);
        (IERC20 tokenOut, uint256 amountOut) = IDepositManagerV1_1(address(depositManager))
            .borrowingWithdraw(
                IDepositManager.BorrowingWithdrawParams({
                    asset: iAsset,
                    recipient: RECIPIENT,
                    amount: requestedAssets
                }),
                true
            );

        assertEq(address(tokenOut), address(iVault), "tokenOut should be the vault share token");
        assertEq(amountOut, expectedShares, "amountOut should equal rounded-down shares");
        assertEq(iVault.balanceOf(RECIPIENT), expectedShares, "recipient share balance mismatch");
        assertEq(
            depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
            requestedAssets,
            "borrowed accounting should use requested underlying assets"
        );
    }

    function test_givenExplicitShareWithdrawalRequirement_whenBorrowingUnderlying_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
    {
        _setConfigOperator(CONFIG_OPERATOR);
        vm.prank(CONFIG_OPERATOR);
        depositManager.setAssetShareWithdrawalRequired(iAsset, true);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_RequiresWithdrawAsShares.selector,
                address(iAsset),
                address(iVault)
            )
        );
        vm.prank(DEPOSIT_OPERATOR);
        IDepositManagerV1_1(address(depositManager)).borrowingWithdraw(
            IDepositManager.BorrowingWithdrawParams({
                asset: iAsset,
                recipient: RECIPIENT,
                amount: 1e18
            }),
            false
        );

        assertEq(
            depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
            0,
            "borrowed accounting rollback"
        );
        assertEq(iAsset.balanceOf(RECIPIENT), 0, "recipient underlying unchanged");
    }

    function test_givenContractIsReEnabled_whenShareOutput()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
    {
        vm.prank(ADMIN);
        depositManager.disable("");
        vm.prank(ADMIN);
        depositManager.enable("");

        uint256 requestedAssets = previousDepositorDepositActualAmount / 2;
        vm.prank(DEPOSIT_OPERATOR);
        (IERC20 tokenOut, uint256 amountOut) = IDepositManagerV1_1(address(depositManager))
            .borrowingWithdraw(
                IDepositManager.BorrowingWithdrawParams({
                    asset: iAsset,
                    recipient: RECIPIENT,
                    amount: requestedAssets
                }),
                true
            );

        assertEq(address(tokenOut), address(iVault), "token out after re-enable");
        assertGt(amountOut, 0, "share output after re-enable");
    }

    function test_givenVault_whenOutputRoundsToZero_reverts(
        bool withdrawAsShares_
    )
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
    {
        _accrueYield(1000e18);
        assertEq(vault.convertToShares(1), 0, "one asset unit should round to zero shares");

        vm.expectRevert(
            abi.encodeWithSelector(IDepositManagerV1_1.DepositManager_ZeroOutput.selector)
        );
        vm.prank(DEPOSIT_OPERATOR);
        IDepositManagerV1_1(address(depositManager)).borrowingWithdraw(
            IDepositManager.BorrowingWithdrawParams({
                asset: iAsset,
                recipient: RECIPIENT,
                amount: 1
            }),
            withdrawAsShares_
        );

        assertEq(
            depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
            0,
            "zero-output borrow should not change borrowed accounting"
        );
    }

    function test_givenAsyncRedeemExternalShareToken_whenWithdrawAsSharesIsTrue() public {
        (
            MockERC7540ExternalShareVault externalVault,
            MockERC7540ExternalShareToken shareToken
        ) = _configureAsyncExternalShareVault();

        vm.prank(DEPOSIT_OPERATOR);
        (IERC20 tokenOut, uint256 amountOut) = depositManager.borrowingWithdraw(
            IDepositManager.BorrowingWithdrawParams({
                asset: iAsset,
                recipient: RECIPIENT,
                amount: 2e18
            }),
            true
        );

        assertEq(address(tokenOut), address(shareToken), "external share token");
        assertEq(amountOut, 2e6, "six-decimal shares out");
        assertEq(shareToken.balanceOf(RECIPIENT), 2e6, "recipient external shares");
        assertEq(externalVault.convertToAssets(amountOut), 2e18, "shares in assets");
    }

    function test_givenAsyncRedeemSelfShareToken_whenWithdrawAsSharesIsTrue() public {
        ERC7540SyncDepositAsyncRedeemVault selfShareVault = new ERC7540SyncDepositAsyncRedeemVault(
            OZIERC20(address(asset))
        );
        vm.startPrank(ADMIN);
        depositManager.enable("");
        depositManager.addAsset(iAsset, IERC4626(address(selfShareVault)), type(uint256).max, 0);
        depositManager.setOperatorName(DEPOSIT_OPERATOR, "cd1");
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        vm.stopPrank();
        _approveSpendingAsset(DEPOSITOR, 10e18);
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: 10e18,
                shouldWrap: false
            })
        );

        vm.prank(DEPOSIT_OPERATOR);
        (IERC20 tokenOut, uint256 amountOut) = depositManager.borrowingWithdraw(
            IDepositManager.BorrowingWithdrawParams({
                asset: iAsset,
                recipient: RECIPIENT,
                amount: 2e18
            }),
            true
        );

        assertEq(address(tokenOut), address(selfShareVault), "self-share token");
        assertEq(amountOut, 2e18, "self-shares out");
        assertEq(selfShareVault.balanceOf(RECIPIENT), 2e18, "recipient self-shares");
    }

    function test_givenAsyncRedeemExternalShareToken_whenWithdrawAsSharesIsFalse_reverts() public {
        (MockERC7540ExternalShareVault externalVault, ) = _configureAsyncExternalShareVault();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_RequiresWithdrawAsShares.selector,
                address(iAsset),
                address(externalVault)
            )
        );
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.borrowingWithdraw(
            IDepositManager.BorrowingWithdrawParams({
                asset: iAsset,
                recipient: RECIPIENT,
                amount: 2e18
            }),
            false
        );

        assertEq(
            depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
            0,
            "failed borrow should roll back debt"
        );
    }

    function _configureAsyncExternalShareVault()
        internal
        returns (
            MockERC7540ExternalShareVault externalVault,
            MockERC7540ExternalShareToken shareToken
        )
    {
        externalVault = new MockERC7540ExternalShareVault(asset, false, true, true);
        shareToken = MockERC7540ExternalShareToken(externalVault.share());
        vm.startPrank(ADMIN);
        depositManager.enable("");
        depositManager.addAsset(iAsset, IERC4626(address(externalVault)), type(uint256).max, 0);
        depositManager.setOperatorName(DEPOSIT_OPERATOR, "cd1");
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        vm.stopPrank();

        _approveSpendingAsset(DEPOSITOR, 10e18);
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: 10e18,
                shouldWrap: false
            })
        );
    }
}

// forge-lint: disable-end(literal-instead-of-constant, unused-return)
