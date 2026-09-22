// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

// Shared domain values use constants; scenario-specific literals remain inline for auditability.
// Calls whose effects are asserted directly intentionally ignore return values, and test cheatcode
// calls do not model production reentrancy.
// forge-lint: disable-start(literal-instead-of-constant, reentrancy-no-eth, unused-return)

import {DepositManagerTest} from "src/test/policies/DepositManager/DepositManagerTest.sol";

import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {MockERC7540ExternalShareVault} from "src/test/policies/DepositManager/fixtures/MockERC7540ExternalShareVault.sol";

contract DepositManagerBorrowingRepayTest is DepositManagerTest {
    struct RejectedRepaymentState {
        uint256 payerBalance;
        uint256 payerAllowance;
        uint256 vaultAssetBalance;
        uint256 managerShareBalance;
        uint256 operatorShares;
        uint256 operatorAssets;
        uint256 borrowedAmount;
        uint256 borrowingCapacity;
    }

    event BorrowingRepayment(
        address indexed asset,
        address indexed operator,
        address indexed payer,
        uint256 amount
    );

    uint256 public _expectedDepositedShares;
    uint256 public _depositManagerSharesBefore;
    uint256 public _operatorSharesBefore;
    uint256 public _operatorSharesInAssetsBefore;
    uint256 public _recipientAssetBalanceBefore;

    uint256 public constant BORROW_AMOUNT = 1e18;

    function _takeSnapshot(uint256 amount_) internal {
        _expectedDepositedShares = vault.previewDeposit(amount_);

        _depositManagerSharesBefore = vault.balanceOf(address(depositManager));

        (_operatorSharesBefore, _operatorSharesInAssetsBefore) = depositManager.getOperatorAssets(
            iAsset,
            DEPOSIT_OPERATOR
        );
        _recipientAssetBalanceBefore = iAsset.balanceOf(RECIPIENT);
    }

    function _snapshotRejectedRepayment(
        address payer_,
        address operator_
    ) internal view returns (RejectedRepaymentState memory state) {
        state.payerBalance = asset.balanceOf(payer_);
        state.payerAllowance = asset.allowance(payer_, address(depositManager));
        state.vaultAssetBalance = asset.balanceOf(address(vault));
        state.managerShareBalance = vault.balanceOf(address(depositManager));
        (state.operatorShares, state.operatorAssets) = depositManager.getOperatorAssets(
            iAsset,
            operator_
        );
        state.borrowedAmount = depositManager.getBorrowedAmount(iAsset, operator_);
        state.borrowingCapacity = depositManager.getBorrowingCapacity(iAsset, operator_);
    }

    function _assertRejectedRepayment(
        address payer_,
        address operator_,
        RejectedRepaymentState memory state_
    ) internal view {
        assertEq(asset.balanceOf(payer_), state_.payerBalance, "payer balance should roll back");
        assertEq(
            asset.allowance(payer_, address(depositManager)),
            state_.payerAllowance,
            "payer allowance should remain unchanged"
        );
        assertEq(
            asset.balanceOf(address(vault)),
            state_.vaultAssetBalance,
            "vault asset custody should remain unchanged"
        );
        assertEq(
            vault.balanceOf(address(depositManager)),
            state_.managerShareBalance,
            "manager share custody should remain unchanged"
        );
        (uint256 operatorShares, uint256 operatorAssets) = depositManager.getOperatorAssets(
            iAsset,
            operator_
        );
        assertEq(operatorShares, state_.operatorShares, "operator shares should remain unchanged");
        assertEq(operatorAssets, state_.operatorAssets, "operator assets should remain unchanged");
        assertEq(
            depositManager.getBorrowedAmount(iAsset, operator_),
            state_.borrowedAmount,
            "operator debt should remain unchanged"
        );
        assertEq(
            depositManager.getBorrowingCapacity(iAsset, operator_),
            state_.borrowingCapacity,
            "operator borrowing capacity should remain unchanged"
        );
    }

    function _assertRepaymentRevertsAndRollsBack(
        address operator_,
        address payer_,
        uint256 amount_,
        uint256 maxAmount_,
        bytes memory expectedRevert_
    ) internal {
        RejectedRepaymentState memory state = _snapshotRejectedRepayment(payer_, operator_);

        vm.expectRevert(expectedRevert_);
        vm.prank(operator_);
        depositManager.borrowingRepay(
            IDepositManager.BorrowingRepayParams({
                asset: iAsset,
                payer: payer_,
                amount: amount_,
                maxAmount: maxAmount_
            })
        );

        _assertRejectedRepayment(payer_, operator_, state);
    }

    // ========== TESTS ========== //

    // given the contract is disabled
    //  [X] it reverts

    function test_givenDisabled_reverts() public {
        // Expect revert
        _expectRevertNotEnabled();

        // Call function
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.borrowingRepay(
            IDepositManager.BorrowingRepayParams({
                asset: iAsset,
                payer: RECIPIENT,
                amount: BORROW_AMOUNT,
                maxAmount: BORROW_AMOUNT
            })
        );
    }

    // given the caller is not a deposit operator
    //  [X] it reverts

    function test_givenNotDepositOperator_reverts(
        address caller_
    ) public givenIsEnabled givenFacilityNameIsSetDefault {
        vm.assume(caller_ != DEPOSIT_OPERATOR);

        // Expect revert
        _expectRevertNotDepositOperator();

        // Call function
        vm.prank(caller_);
        depositManager.borrowingRepay(
            IDepositManager.BorrowingRepayParams({
                asset: iAsset,
                payer: RECIPIENT,
                amount: BORROW_AMOUNT,
                maxAmount: BORROW_AMOUNT
            })
        );
    }

    // given the asset is not configured
    //  [X] it reverts

    function test_givenAssetNotConfigured_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
    {
        // Expect revert
        _expectRevertNotConfiguredAsset();

        // Call function
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.borrowingRepay(
            IDepositManager.BorrowingRepayParams({
                asset: iAsset,
                payer: RECIPIENT,
                amount: BORROW_AMOUNT,
                maxAmount: BORROW_AMOUNT
            })
        );
    }

    // given the caller has no outstanding debt
    //  when max amount is zero
    //   [X] it reverts and rolls back the payer's balance and allowance

    function test_givenNoBorrow_whenMaxAmountIsZero_reverts()
        public
        givenIsEnabled
        givenAssetIsAdded
    {
        asset.mint(RECIPIENT, BORROW_AMOUNT);
        vm.prank(RECIPIENT);
        asset.approve(address(depositManager), BORROW_AMOUNT);
        _assertRepaymentRevertsAndRollsBack(
            DEPOSIT_OPERATOR,
            RECIPIENT,
            BORROW_AMOUNT,
            0,
            abi.encodeWithSelector(IAssetManager.AssetManager_ZeroAmount.selector)
        );
    }

    // given the caller has outstanding debt
    //  when max amount is zero
    //   [X] it reverts and rolls back the payer's balance and allowance

    function test_givenExistingBorrow_whenMaxAmountIsZero_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenBorrow(BORROW_AMOUNT)
        givenRecipientHasApprovedSpendingAsset(previousRecipientBorrowActualAmount)
    {
        _assertRepaymentRevertsAndRollsBack(
            DEPOSIT_OPERATOR,
            RECIPIENT,
            previousRecipientBorrowActualAmount,
            0,
            abi.encodeWithSelector(IAssetManager.AssetManager_ZeroAmount.selector)
        );
    }

    // given the vault credits less than one underlying unit per share
    //  when a positive repayment mints shares but credits zero assets
    //   [X] it rejects the repayment and rolls back payer funds and operator shares

    function test_givenNoBorrow_givenBelowOneAssetPerShare_whenActualCreditIsZero_reverts()
        public
        givenIsEnabled
        givenThreeFifthsAssetPerShare
        givenAssetIsAdded
    {
        asset.mint(RECIPIENT, 1);
        vm.prank(RECIPIENT);
        asset.approve(address(depositManager), 1);

        uint256 shares = vault.previewDeposit(1);
        assertGt(shares, 0, "one underlying unit should mint a share");
        assertEq(vault.convertToAssets(shares), 0, "minted share should credit zero assets");
        _assertRepaymentRevertsAndRollsBack(
            DEPOSIT_OPERATOR,
            RECIPIENT,
            1,
            1,
            abi.encodeWithSelector(IAssetManager.AssetManager_ZeroAmount.selector)
        );
    }

    // given another operator has outstanding debt
    //  when the debt-free caller submits a positive max amount
    //   [X] it reverts against the calling operator's namespace and rolls back payer funds

    function test_givenOtherOperatorHasDebt_whenCallerHasNoDebt_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenBorrow(BORROW_AMOUNT)
        givenRecipientHasApprovedSpendingAsset(previousRecipientBorrowActualAmount)
    {
        address debtFreeOperator = makeAddr("debtFreeOperator");
        vm.prank(ADMIN);
        rolesAdmin.grantRole("deposit_operator", debtFreeOperator);
        uint256 indebtedOperatorDebt = depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR);
        uint256 expectedPrincipalReduction = vault.convertToAssets(
            vault.previewDeposit(previousRecipientBorrowActualAmount)
        );

        _assertRepaymentRevertsAndRollsBack(
            debtFreeOperator,
            RECIPIENT,
            previousRecipientBorrowActualAmount,
            BORROW_AMOUNT,
            abi.encodeWithSelector(
                IDepositManager.DepositManager_BorrowedAmountExceeded.selector,
                address(iAsset),
                debtFreeOperator,
                expectedPrincipalReduction,
                0
            )
        );
        assertEq(
            depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
            indebtedOperatorDebt,
            "other operator debt should remain unchanged"
        );
    }

    function _setUpOtherOperatorStandingAllowance()
        internal
        returns (address otherOperator, address unrelatedPayer)
    {
        otherOperator = makeAddr("otherOperator");
        unrelatedPayer = makeAddr("unrelatedPayer");
        vm.startPrank(ADMIN);
        rolesAdmin.grantRole("deposit_operator", otherOperator);
        depositManager.setOperatorName(otherOperator, "cd2");
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, otherOperator);
        vm.stopPrank();

        asset.mint(unrelatedPayer, 20e18);
        vm.prank(unrelatedPayer);
        asset.approve(address(depositManager), 20e18);
        vm.prank(otherOperator);
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: unrelatedPayer,
                amount: 1e18,
                shouldWrap: false
            })
        );
    }

    // Current design limitation, not an authorization acceptance test: DepositManager is the
    // shared ERC-20 spender, but a payer's allowance is not scoped to the operator receiving the
    // credit. This test shows an indebted operator using allowance left after a deposit through
    // another operator, then claiming the resulting surplus.
    //
    // Exploitation requires a deposit_operator, an enabled/configured asset, and an unrelated payer
    // with both a token balance and unused allowance to DepositManager. The production redemption
    // vault narrows one exposure: it checks the loan/facility, approves only that repayment, and
    // clears the allowance afterward. Those checks do not bind other standing payer approvals to
    // an operator; a newly granted, compromised, or incorrectly exposed operator can bypass them.
    // Once zero maxAmount is rejected, the calling operator needs outstanding debt, but any
    // positive repayment can still consume an unrelated payer's standing allowance.
    //
    // A possible redesign would check revocable, amount-bounded payer consent for each
    // (operator, asset, action) in DepositManager before pulling tokens. Tokens could still move
    // directly from payer to DepositManager, but depositors and custody contracts such as the
    // redemption vault would need to authorize their intended operator. Repayment must still allow
    // actual vault credit above maxAmount for ERC-4626 rounding, with only principal capped.
    function test_givenBorrow_whenOtherOperatorDepositorHasStandingAllowance_canClaimPayerFunds()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenBorrow(BORROW_AMOUNT)
    {
        (address otherOperator, address unrelatedPayer) = _setUpOtherOperatorStandingAllowance();
        uint256 repaymentAmount = 10e18;

        uint256 payerBalanceBefore = asset.balanceOf(unrelatedPayer);
        uint256 payerAllowanceBefore = asset.allowance(unrelatedPayer, address(depositManager));
        uint256 otherOperatorLiabilitiesBefore = depositManager.getOperatorLiabilities(
            iAsset,
            otherOperator
        );
        uint256 callerDebtBefore = depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR);
        uint256 callerClaimableBefore = depositManager.maxClaimYield(iAsset, DEPOSIT_OPERATOR);
        assertGt(payerAllowanceBefore, repaymentAmount, "payer should retain standing allowance");
        assertGt(callerDebtBefore, 0, "calling operator should have its own debt");
        assertLt(callerClaimableBefore, 1e18, "caller should not be able to claim 1e18 yet");

        vm.prank(DEPOSIT_OPERATOR);
        uint256 actualAmount = depositManager.borrowingRepay(
            IDepositManager.BorrowingRepayParams({
                asset: iAsset,
                payer: unrelatedPayer,
                amount: repaymentAmount,
                maxAmount: callerDebtBefore
            })
        );

        assertEq(
            asset.balanceOf(unrelatedPayer),
            payerBalanceBefore - repaymentAmount,
            "unrelated payer should lose the transferred tokens"
        );
        assertEq(
            asset.allowance(unrelatedPayer, address(depositManager)),
            payerAllowanceBefore - repaymentAmount,
            "shared spender allowance should be consumed"
        );
        assertEq(
            depositManager.getOperatorLiabilities(iAsset, otherOperator),
            otherOperatorLiabilitiesBefore,
            "payer's deposit operator liabilities should remain unchanged"
        );
        assertEq(
            depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
            0,
            "calling operator debt should be reduced"
        );
        assertGt(actualAmount, callerDebtBefore, "repayment should create caller surplus");
        assertGt(
            depositManager.maxClaimYield(iAsset, DEPOSIT_OPERATOR),
            callerClaimableBefore,
            "unrelated payer funds should increase caller claimable yield"
        );
        assertGe(
            depositManager.maxClaimYield(iAsset, DEPOSIT_OPERATOR),
            1e18,
            "unrelated payer funds should enable the 1e18 claim"
        );

        uint256 operatorBalanceBefore = asset.balanceOf(DEPOSIT_OPERATOR);
        vm.prank(DEPOSIT_OPERATOR);
        uint256 claimedAmount = depositManager.claimYield(iAsset, DEPOSIT_OPERATOR, 1e18);
        assertGt(claimedAmount, 0, "calling operator should extract positive surplus");
        assertEq(
            asset.balanceOf(DEPOSIT_OPERATOR),
            operatorBalanceBefore + claimedAmount,
            "yield claim should transfer unrelated payer value to caller"
        );
    }

    // Security characterization: no overpayment is needed to consume another operator's payer
    // allowance. Repaying the caller's own debt restores borrowing capacity that it can withdraw.
    function test_givenBorrow_whenOtherOperatorDepositorHasStandingAllowance_canReborrowPayerFunds()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenBorrow(BORROW_AMOUNT)
    {
        (address otherOperator, address unrelatedPayer) = _setUpOtherOperatorStandingAllowance();
        uint256 callerDebtBefore = depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR);
        uint256 callerCapacityBefore = depositManager.getBorrowingCapacity(
            iAsset,
            DEPOSIT_OPERATOR
        );
        uint256 payerBalanceBefore = asset.balanceOf(unrelatedPayer);
        uint256 payerAllowanceBefore = asset.allowance(unrelatedPayer, address(depositManager));
        uint256 otherOperatorLiabilitiesBefore = depositManager.getOperatorLiabilities(
            iAsset,
            otherOperator
        );
        uint256 withdrawalRequest = callerCapacityBefore + BORROW_AMOUNT / 2;

        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_BorrowingLimitExceeded.selector,
                address(iAsset),
                DEPOSIT_OPERATOR,
                withdrawalRequest,
                callerCapacityBefore
            )
        );
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.borrowingWithdraw(
            IDepositManager.BorrowingWithdrawParams({
                asset: iAsset,
                recipient: DEPOSIT_OPERATOR,
                amount: withdrawalRequest
            })
        );

        vm.prank(DEPOSIT_OPERATOR);
        uint256 actualAmount = depositManager.borrowingRepay(
            IDepositManager.BorrowingRepayParams({
                asset: iAsset,
                payer: unrelatedPayer,
                amount: BORROW_AMOUNT,
                maxAmount: callerDebtBefore
            })
        );

        assertLe(actualAmount, callerDebtBefore, "payment should not exceed caller debt");
        assertEq(
            asset.balanceOf(unrelatedPayer),
            payerBalanceBefore - BORROW_AMOUNT,
            "unrelated payer should lose the transferred tokens"
        );
        assertEq(
            asset.allowance(unrelatedPayer, address(depositManager)),
            payerAllowanceBefore - BORROW_AMOUNT,
            "shared spender allowance should be consumed"
        );
        assertEq(
            depositManager.getOperatorLiabilities(iAsset, otherOperator),
            otherOperatorLiabilitiesBefore,
            "payer's deposit operator liabilities should remain unchanged"
        );
        assertEq(
            depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
            callerDebtBefore - actualAmount,
            "unrelated payer funds should reduce caller debt"
        );
        assertGt(
            depositManager.getBorrowingCapacity(iAsset, DEPOSIT_OPERATOR),
            callerCapacityBefore,
            "unrelated payer funds should restore caller borrowing capacity"
        );
        assertGe(
            depositManager.getBorrowingCapacity(iAsset, DEPOSIT_OPERATOR),
            withdrawalRequest,
            "unrelated payer funds should enable the previously rejected withdrawal"
        );

        uint256 operatorBalanceBefore = asset.balanceOf(DEPOSIT_OPERATOR);
        vm.prank(DEPOSIT_OPERATOR);
        uint256 withdrawnAmount = depositManager.borrowingWithdraw(
            IDepositManager.BorrowingWithdrawParams({
                asset: iAsset,
                recipient: DEPOSIT_OPERATOR,
                amount: withdrawalRequest
            })
        );
        assertGt(withdrawnAmount, 0, "caller should withdraw restored borrowing capacity");
        assertEq(
            asset.balanceOf(DEPOSIT_OPERATOR),
            operatorBalanceBefore + withdrawnAmount,
            "withdrawal should transfer value funded by unrelated payer to caller"
        );
    }

    // given the caller has outstanding debt
    //  when max amount exceeds that debt
    //   [X] it repays by the actual amount when the actual amount remains within the debt

    function test_givenExistingBorrow_whenMaxAmountExceedsDebt(
        uint256 maxAmount_
    )
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenBorrow(BORROW_AMOUNT)
        givenRecipientHasApprovedSpendingAsset(previousRecipientBorrowActualAmount)
    {
        uint256 currentDebt = depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR);
        maxAmount_ = bound(maxAmount_, currentDebt + 1, type(uint256).max);
        uint256 payerBalanceBefore = asset.balanceOf(RECIPIENT);

        vm.prank(DEPOSIT_OPERATOR);
        uint256 actualAmount = depositManager.borrowingRepay(
            IDepositManager.BorrowingRepayParams({
                asset: iAsset,
                payer: RECIPIENT,
                amount: previousRecipientBorrowActualAmount,
                maxAmount: maxAmount_
            })
        );

        assertLe(actualAmount, currentDebt, "actual repayment should remain within caller debt");
        assertEq(
            asset.balanceOf(RECIPIENT),
            payerBalanceBefore - previousRecipientBorrowActualAmount,
            "payer should fund the requested token amount"
        );
        assertEq(
            depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
            currentDebt - actualAmount,
            "loose maximum should not prevent a valid repayment"
        );
    }

    // given the caller has outstanding debt
    //  when max amount is the uint256 maximum
    //   [X] it repays without overflowing when the actual amount remains within the debt

    function test_givenExistingBorrow_whenMaxAmountIsTypeMax()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenBorrow(BORROW_AMOUNT)
        givenRecipientHasApprovedSpendingAsset(previousRecipientBorrowActualAmount)
    {
        uint256 currentDebt = depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR);
        uint256 payerBalanceBefore = asset.balanceOf(RECIPIENT);

        vm.prank(DEPOSIT_OPERATOR);
        uint256 actualAmount = depositManager.borrowingRepay(
            IDepositManager.BorrowingRepayParams({
                asset: iAsset,
                payer: RECIPIENT,
                amount: previousRecipientBorrowActualAmount,
                maxAmount: type(uint256).max
            })
        );

        assertLe(actualAmount, currentDebt, "actual repayment should remain within caller debt");
        assertEq(
            asset.balanceOf(RECIPIENT),
            payerBalanceBefore - previousRecipientBorrowActualAmount,
            "payer should fund the requested token amount"
        );
        assertEq(
            depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
            currentDebt - actualAmount,
            "uint256 maximum should act as a loose cap"
        );
    }

    // given the caller has outstanding debt
    //  when the principal reduction exceeds that debt
    //   [X] it reverts and rolls back token custody and operator accounting

    function test_givenExistingBorrow_whenPrincipalReductionExceedsDebt_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenBorrow(BORROW_AMOUNT)
    {
        uint256 currentDebt = depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR);
        uint256 maxAmount = currentDebt + 1;
        uint256 repaymentAmount = currentDebt + BORROW_AMOUNT;
        asset.mint(RECIPIENT, repaymentAmount);
        vm.prank(RECIPIENT);
        asset.approve(address(depositManager), repaymentAmount);

        _assertRepaymentRevertsAndRollsBack(
            DEPOSIT_OPERATOR,
            RECIPIENT,
            repaymentAmount,
            maxAmount,
            abi.encodeWithSelector(
                IDepositManager.DepositManager_BorrowedAmountExceeded.selector,
                address(iAsset),
                DEPOSIT_OPERATOR,
                maxAmount,
                currentDebt
            )
        );
    }

    // given the caller has outstanding debt
    //  when actual credit exceeds the debt but remains below max amount
    //   [X] it reports the actual principal reduction and rolls back the payer's funds

    function test_givenExistingBorrow_whenActualCreditExceedsDebtBelowMax_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenBorrow(BORROW_AMOUNT)
    {
        uint256 currentDebt = depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR);
        uint256 repaymentAmount = currentDebt + BORROW_AMOUNT;
        uint256 actualCredit = vault.convertToAssets(vault.previewDeposit(repaymentAmount));
        uint256 maxAmount = repaymentAmount + BORROW_AMOUNT;
        asset.mint(RECIPIENT, repaymentAmount);
        vm.prank(RECIPIENT);
        asset.approve(address(depositManager), repaymentAmount);

        assertGt(actualCredit, currentDebt, "actual credit should exceed caller debt");
        assertLt(actualCredit, maxAmount, "actual credit should remain below max amount");
        _assertRepaymentRevertsAndRollsBack(
            DEPOSIT_OPERATOR,
            RECIPIENT,
            repaymentAmount,
            maxAmount,
            abi.encodeWithSelector(
                IDepositManager.DepositManager_BorrowedAmountExceeded.selector,
                address(iAsset),
                DEPOSIT_OPERATOR,
                actualCredit,
                currentDebt
            )
        );
    }

    // given the caller has outstanding debt
    //  when max amount is the minimum positive value
    //   [X] it reduces only the calling operator's debt by that value

    function test_givenExistingBorrow_whenMaxAmountIsOne()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenBorrow(BORROW_AMOUNT)
    {
        uint256 repaymentAmount = vault.previewMint(1);
        vm.prank(RECIPIENT);
        asset.approve(address(depositManager), repaymentAmount);
        uint256 payerBalanceBefore = asset.balanceOf(RECIPIENT);
        uint256 debtBefore = depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR);

        vm.prank(DEPOSIT_OPERATOR);
        uint256 actualAmount = depositManager.borrowingRepay(
            IDepositManager.BorrowingRepayParams({
                asset: iAsset,
                payer: RECIPIENT,
                amount: repaymentAmount,
                maxAmount: 1
            })
        );

        assertGt(actualAmount, 0, "repayment should credit a positive asset amount");
        assertEq(
            asset.balanceOf(RECIPIENT),
            payerBalanceBefore - repaymentAmount,
            "payer should fund the requested token amount"
        );
        assertEq(
            depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
            debtBefore - 1,
            "minimum positive max amount should reduce caller debt by one"
        );
    }

    // given an existing borrow and disabled asset period
    //  [X] repayment remains available for servicing the liability

    function test_givenAssetPeriodIsDisabled_repaysExistingBorrow()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenBorrow(BORROW_AMOUNT)
        givenRecipientHasApprovedSpendingAsset(BORROW_AMOUNT)
        givenAssetPeriodIsDisabled
    {
        asset.mint(RECIPIENT, BORROW_AMOUNT);
        _setAssetDepositCap(0);

        vm.prank(DEPOSIT_OPERATOR);
        uint256 actualAmount = depositManager.borrowingRepay(
            IDepositManager.BorrowingRepayParams({
                asset: iAsset,
                payer: RECIPIENT,
                amount: BORROW_AMOUNT,
                maxAmount: BORROW_AMOUNT
            })
        );

        // The vault credits the assets represented by deposited shares, so the received amount
        // can round down by one underlying unit. Debt must fall by that authoritative amount.
        assertGt(actualAmount, 0, "repayment should transfer a positive amount");
        assertEq(
            depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
            BORROW_AMOUNT - actualAmount,
            "disabled period should not prevent debt repayment"
        );
    }

    // when the repayment amount exceeds the first loan's principal
    //  given there is second loan
    //   [X] it accepts the requested overpayment even if vault rounding removes one wei
    //   [X] it reduces debt by the first loan's principal without affecting the second loan

    function test_whenAmountExceedsBorrowed_givenSecondLoan(
        uint256 amount_
    )
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenBorrow(BORROW_AMOUNT)
        givenDepositorHasAsset(MINT_AMOUNT)
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenBorrow(BORROW_AMOUNT)
        givenRecipientHasApprovedSpendingAsset(100e18)
    {
        amount_ = bound(amount_, BORROW_AMOUNT + 1, 100e18);

        // Mint the repayment amount to the recipient
        asset.mint(RECIPIENT, amount_);

        _takeSnapshot(amount_);

        // Call function
        vm.prank(DEPOSIT_OPERATOR);
        uint256 actualAmount = depositManager.borrowingRepay(
            IDepositManager.BorrowingRepayParams({
                asset: iAsset,
                payer: RECIPIENT,
                amount: amount_,
                maxAmount: BORROW_AMOUNT
            })
        );

        // Assert token balance
        assertEq(
            iAsset.balanceOf(address(RECIPIENT)),
            _recipientAssetBalanceBefore - amount_,
            "payer balance"
        );
        assertGe(
            actualAmount,
            BORROW_AMOUNT,
            "credited repayment should cover the first loan after rounding"
        );

        // Borrowed amounts
        assertEq(
            depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
            BORROW_AMOUNT,
            "borrowed amount" // Does not go below the principal amount of the second loan
        );
        assertEq(
            depositManager.getBorrowingCapacity(iAsset, DEPOSIT_OPERATOR),
            previousDepositorReceiptTokenBalance - BORROW_AMOUNT, // Repaid amount is available for borrowing
            "borrowing capacity"
        );

        // Operator assets should be increased
        (uint256 operatorShares, uint256 operatorSharesInAssets) = depositManager.getOperatorAssets(
            iAsset,
            DEPOSIT_OPERATOR
        );

        assertEq(
            operatorShares,
            _operatorSharesBefore + _expectedDepositedShares,
            "operator shares"
        );

        assertApproxEqAbs(
            operatorSharesInAssets,
            _operatorSharesInAssetsBefore + amount_,
            1,
            "operator shares in assets"
        );

        assertEq(
            vault.balanceOf(address(depositManager)),
            _depositManagerSharesBefore + _expectedDepositedShares,
            "vault balance"
        );
        assertEq(
            _assetDepositCapUtilization(iAsset),
            previousDepositorReceiptTokenBalance,
            "borrowing repayment should preserve utilization"
        );
    }

    // given two loans of 1e18 each
    //  when 2e18 is paid with a 1e18 principal cap
    //   [X] credited assets exceed the first loan's principal
    //   [X] only the first loan's principal is removed from aggregate debt

    function test_givenSecondLoan_whenCreditedRepaymentExceedsFirstPrincipal()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenBorrow(BORROW_AMOUNT)
        givenDepositorHasAsset(MINT_AMOUNT)
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenBorrow(BORROW_AMOUNT)
    {
        // Asset and debt amounts use 18 decimals. A whole additional loan principal is well
        // above the vault's one-wei rounding loss, unlike a requested +1 wei overpayment.
        uint256 repaymentAmount = BORROW_AMOUNT * 2;
        asset.mint(RECIPIENT, repaymentAmount);
        vm.prank(RECIPIENT);
        asset.approve(address(depositManager), repaymentAmount);
        _takeSnapshot(repaymentAmount);

        vm.prank(DEPOSIT_OPERATOR);
        uint256 actualAmount = depositManager.borrowingRepay(
            IDepositManager.BorrowingRepayParams({
                asset: iAsset,
                payer: RECIPIENT,
                amount: repaymentAmount,
                maxAmount: BORROW_AMOUNT
            })
        );

        assertGt(actualAmount, BORROW_AMOUNT, "credited assets should exceed first principal");
        assertEq(
            iAsset.balanceOf(RECIPIENT),
            _recipientAssetBalanceBefore - repaymentAmount,
            "payer should fund the full requested amount"
        );
        assertEq(
            depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
            BORROW_AMOUNT,
            "second loan principal should remain outstanding"
        );
        (, uint256 operatorAssetsAfter) = depositManager.getOperatorAssets(
            iAsset,
            DEPOSIT_OPERATOR
        );
        assertApproxEqAbs(
            operatorAssetsAfter,
            _operatorSharesInAssetsBefore + actualAmount,
            1,
            "operator assets should include the credited excess"
        );
    }

    // when the repayment amount exceeds the loan principal
    //  [X] it accepts the requested overpayment even if vault rounding removes one wei
    //  [X] it caps the debt reduction and borrowing-capacity restoration at the loan principal

    function test_whenAmountExceedsBorrowed(
        uint256 amount_
    )
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenBorrow(BORROW_AMOUNT)
        givenRecipientHasApprovedSpendingAsset(100e18)
    {
        amount_ = bound(amount_, BORROW_AMOUNT + 1, 100e18);

        // Mint the repayment amount to the recipient
        asset.mint(RECIPIENT, amount_);

        _takeSnapshot(amount_);

        // Call function
        vm.prank(DEPOSIT_OPERATOR);
        uint256 actualAmount = depositManager.borrowingRepay(
            IDepositManager.BorrowingRepayParams({
                asset: iAsset,
                payer: RECIPIENT,
                amount: amount_,
                maxAmount: BORROW_AMOUNT
            })
        );

        // Assert token balance
        assertEq(
            iAsset.balanceOf(address(RECIPIENT)),
            _recipientAssetBalanceBefore - amount_,
            "payer balance"
        );
        assertGe(
            actualAmount,
            BORROW_AMOUNT,
            "credited repayment should cover the loan after rounding"
        );

        // Borrowed amounts
        assertEq(
            depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
            0,
            "borrowed amount" // No underflow
        );
        assertEq(
            depositManager.getBorrowingCapacity(iAsset, DEPOSIT_OPERATOR),
            previousDepositorDepositActualAmount, // Full deposit
            "borrowing capacity"
        );

        // Operator assets should be increased
        (uint256 operatorShares, uint256 operatorSharesInAssets) = depositManager.getOperatorAssets(
            iAsset,
            DEPOSIT_OPERATOR
        );

        assertEq(
            operatorShares,
            _operatorSharesBefore + _expectedDepositedShares,
            "operator shares"
        );

        assertApproxEqAbs(
            operatorSharesInAssets,
            _operatorSharesInAssetsBefore + amount_,
            1,
            "operator shares in assets"
        );

        assertEq(
            vault.balanceOf(address(depositManager)),
            _depositManagerSharesBefore + _expectedDepositedShares,
            "vault balance"
        );
    }

    // given the payer has not approved spending of the asset
    //  [X] it reverts

    function test_givenAssetSpendingNotApproved_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenBorrow(BORROW_AMOUNT)
    {
        // Expect revert
        _expectRevertERC20InsufficientAllowance();

        // Call function
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.borrowingRepay(
            IDepositManager.BorrowingRepayParams({
                asset: iAsset,
                payer: RECIPIENT,
                amount: previousRecipientBorrowActualAmount,
                maxAmount: BORROW_AMOUNT
            })
        );
    }

    // given the amount is less than one share
    //  [X] it reverts

    function test_whenAmountLessThanOneShare(
        uint256 amount_
    )
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenBorrow(BORROW_AMOUNT)
        givenRecipientHasApprovedSpendingAsset(previousRecipientBorrowActualAmount)
    {
        // Calculate amount
        uint256 oneShareInAssets = vault.previewMint(1);
        amount_ = bound(amount_, 1, oneShareInAssets - 1);

        // Expect revert
        vm.expectRevert("ZERO_SHARES");

        // Call function
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.borrowingRepay(
            IDepositManager.BorrowingRepayParams({
                asset: iAsset,
                payer: RECIPIENT,
                amount: amount_,
                maxAmount: BORROW_AMOUNT
            })
        );
    }

    // [X] it transfers the assets from the payer to the deposit manager
    // [X] it emits an event
    // [X] it returns the actual amount of transferred assets
    // [X] it reduces the borrowed amount by the actual amount repaid
    // [X] it increases the borrowing capacity by the actual amount repaid
    // [X] it increases the operator shares by the actual amount (in terms of shares) repaid

    function test_success(
        uint256 amount_,
        uint256 yieldAmount_
    )
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenBorrow(BORROW_AMOUNT)
        givenRecipientHasApprovedSpendingAsset(previousRecipientBorrowActualAmount)
    {
        // Calculate amount
        uint256 oneShareInAssets = vault.previewMint(1);
        amount_ = bound(amount_, oneShareInAssets, previousRecipientBorrowActualAmount);
        yieldAmount_ = bound(yieldAmount_, 1e16, 50e18);

        uint256 firstDepositActualAmount = previousDepositorDepositActualAmount;

        // Make another deposit
        // This reduces rounding issues with conversion between shares and assets
        {
            asset.mint(DEPOSITOR, MINT_AMOUNT);
            _approveSpendingAsset(DEPOSITOR, MINT_AMOUNT);
            _deposit(MINT_AMOUNT, false);
        }

        // Accrue yield
        _accrueYield(yieldAmount_);

        _takeSnapshot(amount_);

        // Expect event
        // The amount can be off by a few wei, so don't assert that
        vm.expectEmit(true, true, true, false);
        emit BorrowingRepayment(address(iAsset), DEPOSIT_OPERATOR, RECIPIENT, amount_);

        // Call function
        vm.prank(DEPOSIT_OPERATOR);
        uint256 actualAmount = depositManager.borrowingRepay(
            IDepositManager.BorrowingRepayParams({
                asset: iAsset,
                payer: RECIPIENT,
                amount: amount_,
                maxAmount: BORROW_AMOUNT
            })
        );

        // Assert tokens
        assertApproxEqAbs(actualAmount, amount_, 5, "actual amount");
        assertEq(
            iAsset.balanceOf(RECIPIENT),
            previousRecipientBorrowActualAmount - amount_,
            "recipient balance"
        );

        // Borrowed amounts
        assertEq(
            depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
            BORROW_AMOUNT - actualAmount,
            "borrowed amount"
        );
        assertEq(
            depositManager.getBorrowingCapacity(iAsset, DEPOSIT_OPERATOR),
            firstDepositActualAmount +
                previousDepositorDepositActualAmount -
                BORROW_AMOUNT +
                actualAmount,
            "borrowing capacity"
        );

        // Operator assets should be increased
        (uint256 operatorShares, uint256 operatorSharesInAssets) = depositManager.getOperatorAssets(
            iAsset,
            DEPOSIT_OPERATOR
        );

        assertEq(
            operatorShares,
            _operatorSharesBefore + _expectedDepositedShares,
            "operator shares"
        );

        assertApproxEqAbs(
            operatorSharesInAssets,
            _operatorSharesInAssetsBefore + actualAmount,
            5,
            "operator shares in assets"
        );

        assertEq(
            vault.balanceOf(address(depositManager)),
            _depositManagerSharesBefore + _expectedDepositedShares,
            "vault balance"
        );
        assertEq(
            _assetDepositCapUtilization(iAsset),
            firstDepositActualAmount + previousDepositorDepositActualAmount,
            "borrowing repayment should preserve utilization"
        );
    }

    function test_givenAsyncDepositBecomesEnabled_revertsAndRollsBackTransfer() public {
        MockERC7540ExternalShareVault externalVault = new MockERC7540ExternalShareVault(
            asset,
            false,
            false,
            true
        );
        vm.startPrank(ADMIN);
        depositManager.enable("");
        depositManager.addAsset(iAsset, IERC4626(address(externalVault)), type(uint256).max, 0);
        depositManager.setOperatorName(DEPOSIT_OPERATOR, "cd1");
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        vm.stopPrank();

        asset.mint(DEPOSITOR, 10e18);
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
        depositManager.borrowingWithdraw(
            IDepositManager.BorrowingWithdrawParams({
                asset: iAsset,
                recipient: RECIPIENT,
                amount: 10e18
            })
        );

        externalVault.setCapabilities(true, false, true, true);
        uint256 payerBalanceBefore = asset.balanceOf(RECIPIENT);
        vm.prank(RECIPIENT);
        asset.approve(address(depositManager), 10e18);

        vm.expectRevert(MockERC7540ExternalShareVault.AsyncDeposit.selector);
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.borrowingRepay(
            IDepositManager.BorrowingRepayParams({
                asset: iAsset,
                payer: RECIPIENT,
                amount: 10e18,
                maxAmount: 10e18
            })
        );

        assertEq(asset.balanceOf(RECIPIENT), payerBalanceBefore, "payer balance rollback");
        assertEq(asset.balanceOf(address(depositManager)), 0, "manager balance rollback");
        assertEq(asset.balanceOf(address(externalVault)), 0, "vault balance unchanged");
        assertEq(
            depositManager.getBorrowedAmount(iAsset, DEPOSIT_OPERATOR),
            10e18,
            "borrowed amount rollback"
        );
    }

    function test_givenExternalShareToken_whenRedeemModeIsFuzzed(bool asyncRedeem_) public {
        MockERC7540ExternalShareVault externalVault = new MockERC7540ExternalShareVault(
            asset,
            false,
            false,
            true
        );
        vm.startPrank(ADMIN);
        depositManager.enable("");
        depositManager.addAsset(iAsset, IERC4626(address(externalVault)), type(uint256).max, 0);
        depositManager.setOperatorName(DEPOSIT_OPERATOR, "cd1");
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        vm.stopPrank();

        asset.mint(DEPOSITOR, 10e18);
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
        depositManager.borrowingWithdraw(
            IDepositManager.BorrowingWithdrawParams({
                asset: iAsset,
                recipient: RECIPIENT,
                amount: 10e18
            })
        );

        externalVault.setCapabilities(false, asyncRedeem_, true, true);
        vm.prank(RECIPIENT);
        asset.approve(address(depositManager), 10e18);

        vm.prank(DEPOSIT_OPERATOR);
        uint256 actualAmount = depositManager.borrowingRepay(
            IDepositManager.BorrowingRepayParams({
                asset: iAsset,
                payer: RECIPIENT,
                amount: 10e18,
                maxAmount: 10e18
            })
        );

        (uint256 operatorShares, uint256 operatorAssets) = depositManager.getOperatorAssets(
            iAsset,
            DEPOSIT_OPERATOR
        );
        assertEq(actualAmount, 10e18, "repayment credit");
        assertEq(operatorShares, 10e6, "raw external shares");
        assertEq(operatorAssets, 10e18, "external shares in assets");
        assertEq(
            IERC20(externalVault.share()).balanceOf(address(depositManager)),
            10e6,
            "external share custody"
        );
    }
}

// forge-lint: disable-end(literal-instead-of-constant, reentrancy-no-eth, unused-return)
