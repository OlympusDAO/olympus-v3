// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {DepositManagerTest} from "./DepositManagerTest.sol";
import {MockERC20FeeOnTransfer} from "src/test/mocks/MockERC20FeeOnTransfer.sol";
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";

contract DepositManagerDepositTest is DepositManagerTest {
    // ========== EVENTS ========== //

    event AssetDeposited(
        address indexed asset,
        address indexed depositor,
        address indexed operator,
        uint256 amount,
        uint256 shares
    );

    // ========== TESTS ========== //

    // given the contract is disabled
    //  [X] it reverts

    function test_givenPolicyIsDisabled_reverts() public {
        _expectRevertNotEnabled();

        vm.prank(ADMIN);
        depositManager.deposit(iAsset, DEPOSIT_PERIOD, DEPOSITOR, 1e18, false);
    }

    // when the caller does not have the deposit operator role
    //  [X] it reverts

    function test_whenCallerIsNotDepositOperator_reverts(address caller_) public givenIsEnabled {
        vm.assume(caller_ != DEPOSIT_OPERATOR);

        _expectRevertNotDepositOperator();

        vm.prank(caller_);
        depositManager.deposit(iAsset, DEPOSIT_PERIOD, DEPOSITOR, 1e18, false);
    }

    // given the asset period does not exist
    //  given the asset vault is set
    //   [X] it reverts
    //  [X] it reverts

    function test_givenAssetPeriodDoesNotExist_givenAssetVaultIsSet_reverts()
        public
        givenIsEnabled
        givenAssetVaultIsConfigured
    {
        _expectRevertInvalidConfiguration(iAsset, DEPOSIT_PERIOD);

        vm.prank(DEPOSIT_OPERATOR);
        depositManager.deposit(iAsset, DEPOSIT_PERIOD, DEPOSITOR, 1e18, false);
    }

    function test_givenAssetPeriodDoesNotExist_reverts()
        public
        givenIsEnabled
        givenAssetVaultIsConfigured
    {
        _expectRevertInvalidConfiguration(iAsset, DEPOSIT_PERIOD);

        vm.prank(DEPOSIT_OPERATOR);
        depositManager.deposit(iAsset, DEPOSIT_PERIOD, DEPOSITOR, 1e18, false);
    }

    // given the asset period is disabled
    //  [X] it reverts

    function test_givenAssetPeriodIsDisabled_reverts()
        public
        givenIsEnabled
        givenAssetVaultIsConfigured
        givenDepositIsConfigured
        givenAssetPeriodIsDisabled
    {
        _expectRevertConfigurationDisabled(iAsset, DEPOSIT_PERIOD);

        vm.prank(DEPOSIT_OPERATOR);
        depositManager.deposit(iAsset, DEPOSIT_PERIOD, DEPOSITOR, 1e18, false);
    }

    // when the depositor address is the zero address
    //  [X] it reverts

    function test_whenDepositorAddressIsZeroAddress_reverts()
        public
        givenIsEnabled
        givenAssetVaultIsConfigured
        givenDepositIsConfigured
    {
        vm.expectRevert("TRANSFER_FROM_FAILED");

        vm.prank(DEPOSIT_OPERATOR);
        depositManager.deposit(iAsset, DEPOSIT_PERIOD, address(0), 1e18, false);
    }

    // when the deposit amount is 0
    //  [X] it reverts

    function test_whenDepositAmountIsZero_reverts()
        public
        givenIsEnabled
        givenAssetVaultIsConfigured
        givenDepositIsConfigured
    {
        vm.expectRevert("ZERO_SHARES");

        vm.prank(DEPOSIT_OPERATOR);
        depositManager.deposit(iAsset, DEPOSIT_PERIOD, DEPOSITOR, 0, false);
    }

    // given the depositor has not approved the contract to spend the asset
    //  [X] it reverts

    function test_givenDepositorHasNotApprovedSpendingAsset_reverts()
        public
        givenIsEnabled
        givenAssetVaultIsConfigured
        givenDepositIsConfigured
    {
        // Expect revert
        _expectRevertERC20InsufficientAllowance();

        vm.prank(DEPOSIT_OPERATOR);
        depositManager.deposit(iAsset, DEPOSIT_PERIOD, DEPOSITOR, 1e18, false);
    }

    // given the depositor does not have sufficient asset balance
    //  [X] it reverts

    function test_givenDepositorDoesNotHaveSufficientAssetBalance_reverts()
        public
        givenIsEnabled
        givenAssetVaultIsConfigured
        givenDepositIsConfigured
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT + 1)
    {
        // Expect revert
        _expectRevertERC20InsufficientBalance();

        vm.prank(DEPOSIT_OPERATOR);
        depositManager.deposit(iAsset, DEPOSIT_PERIOD, DEPOSITOR, MINT_AMOUNT + 1, false);
    }

    // given the asset is fee-on-transfer
    //  [X] it reverts

    function test_givenAssetIsFeeOnTransfer_reverts() public givenIsEnabled {
        // Create a fee-on-transfer asset
        address feeRecipient = makeAddr("feeRecipient");
        MockERC20FeeOnTransfer asset = new MockERC20FeeOnTransfer(
            "Fee On Transfer",
            "FOT",
            feeRecipient
        );

        // Configure the asset vault
        vm.prank(ADMIN);
        depositManager.configureAssetVault(IERC20(address(asset)), IERC4626(address(0)));

        // Configure deposit
        vm.prank(ADMIN);
        depositManager.addAssetPeriod(IERC20(address(asset)), DEPOSIT_PERIOD, RECLAIM_RATE);

        // Mint the asset to the depositor
        vm.prank(ADMIN);
        asset.mint(DEPOSITOR, MINT_AMOUNT);

        // Approve spending of the asset
        vm.prank(DEPOSITOR);
        asset.approve(address(depositManager), MINT_AMOUNT);

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(IAssetManager.AssetManager_InvalidAsset.selector));

        // Deposit
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.deposit(
            IERC20(address(asset)),
            DEPOSIT_PERIOD,
            DEPOSITOR,
            MINT_AMOUNT,
            false
        );
    }

    // given the asset configuration has the vault set to the zero address
    //  [X] the returned shares are the deposited amount
    //  [X] the asset is stored in the contract
    //  [X] the operator shares are updated with the deposited amount
    //  [X] the wrapped receipt tokens are not minted to the depositor
    //  [X] the receipt tokens are minted to the depositor

    function test_givenAssetVaultIsConfiguredWithZeroAddress(
        uint256 amount_
    )
        public
        givenIsEnabled
        givenAssetVaultIsConfiguredWithZeroAddress
        givenDepositIsConfigured
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
    {
        amount_ = bound(amount_, 1e18, MINT_AMOUNT);

        uint256 expectedReceiptTokenId = depositManager.getReceiptTokenId(iAsset, DEPOSIT_PERIOD);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit AssetDeposited(address(iAsset), DEPOSITOR, DEPOSIT_OPERATOR, amount_, amount_);

        // Deposit
        vm.prank(DEPOSIT_OPERATOR);
        (uint256 receiptTokenId, uint256 actualAmount) = depositManager.deposit(
            iAsset,
            DEPOSIT_PERIOD,
            DEPOSITOR,
            amount_,
            false
        );

        // Assert
        _assertReceiptTokenId(expectedReceiptTokenId, receiptTokenId);
        _assertAssetBalance(amount_, amount_, actualAmount, true);
        _assertReceiptToken(amount_, 0, false, true);
        _assertDepositAssetBalance(DEPOSITOR, MINT_AMOUNT - amount_);
    }

    // when shouldWrap is true
    //  given the receipt token has not been wrapped
    //   [X] it creates the wrapped token contract
    //   [X] the wrapped receipt tokens are minted to the depositor
    //   [X] the receipt tokens are not minted to the depositor

    function test_whenShouldWrapIsTrue_givenReceiptTokenHasNotBeenWrapped()
        public
        givenIsEnabled
        givenAssetVaultIsConfigured
        givenDepositIsConfigured
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
    {
        uint256 amount = 1e18;
        uint256 expectedShares = vault.previewDeposit(amount);
        uint256 expectedAssets = _getExpectedActualAssets(amount);

        uint256 expectedReceiptTokenId = depositManager.getReceiptTokenId(iAsset, DEPOSIT_PERIOD);

        // Deposit
        vm.prank(DEPOSIT_OPERATOR);
        (uint256 receiptTokenId, uint256 actualAmount) = depositManager.deposit(
            iAsset,
            DEPOSIT_PERIOD,
            DEPOSITOR,
            amount,
            true
        );

        // Assert
        _assertReceiptTokenId(expectedReceiptTokenId, receiptTokenId);
        _assertAssetBalance(expectedShares, expectedAssets, actualAmount, true);
        _assertReceiptToken(0, expectedAssets, true, true);
        _assertDepositAssetBalance(DEPOSITOR, MINT_AMOUNT - expectedAssets);
    }

    //  [X] the wrapped receipt tokens are minted to the depositor
    //  [X] the receipt tokens are not minted to the depositor
    // given there is an existing deposit
    //  [X] the operator shares are correct
    //  [X] the asset liabilities are correct

    function test_whenShouldWrapIsTrue_givenReceiptTokenHasBeenWrapped()
        public
        givenIsEnabled
        givenAssetVaultIsConfigured
        givenDepositIsConfigured
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(10e18, true)
    {
        uint256 amount = 1e18;
        uint256 expectedShares = vault.previewDeposit(amount);
        uint256 expectedAssets = _getExpectedActualAssets(amount);

        uint256 expectedReceiptTokenId = depositManager.getReceiptTokenId(iAsset, DEPOSIT_PERIOD);

        // Deposit
        vm.prank(DEPOSIT_OPERATOR);
        (uint256 receiptTokenId, uint256 actualAmount) = depositManager.deposit(
            iAsset,
            DEPOSIT_PERIOD,
            DEPOSITOR,
            amount,
            true
        );

        // Assert
        _assertReceiptTokenId(expectedReceiptTokenId, receiptTokenId);
        _assertAssetBalance(expectedShares, expectedAssets, actualAmount, true);
        _assertReceiptToken(0, expectedAssets, true, true);
        _assertDepositAssetBalance(DEPOSITOR, MINT_AMOUNT - 10e18 - expectedAssets);
    }

    // [X] the returned shares are the deposited amount (in terms of vault shares)
    // [X] the asset is deposited into the vault
    // [X] the operator shares are increased by the deposited amount (in terms of vault shares)
    // [X] the wrapped receipt tokens are not minted to the depositor
    // [X] the receipt tokens are minted to the depositor
    // [X] the asset liabilities are increased by the deposited amount

    function test_success(
        uint256 amount_
    )
        public
        givenIsEnabled
        givenAssetVaultIsConfigured
        givenDepositIsConfigured
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
    {
        amount_ = bound(amount_, 1e18, MINT_AMOUNT);

        // Determine expected amounts
        uint256 expectedShares = vault.previewDeposit(amount_);
        uint256 expectedAssets = _getExpectedActualAssets(amount_);

        uint256 expectedReceiptTokenId = depositManager.getReceiptTokenId(iAsset, DEPOSIT_PERIOD);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit AssetDeposited(
            address(iAsset),
            DEPOSITOR,
            DEPOSIT_OPERATOR,
            expectedAssets,
            expectedShares
        );

        // Deposit
        vm.prank(DEPOSIT_OPERATOR);
        (uint256 receiptTokenId, uint256 actualAmount) = depositManager.deposit(
            iAsset,
            DEPOSIT_PERIOD,
            DEPOSITOR,
            amount_,
            false
        );

        // Assert
        _assertReceiptTokenId(expectedReceiptTokenId, receiptTokenId);
        _assertAssetBalance(expectedShares, expectedAssets, actualAmount, true);
        _assertReceiptToken(expectedAssets, 0, false, true);
        _assertDepositAssetBalance(DEPOSITOR, MINT_AMOUNT - expectedAssets);
    }
}
