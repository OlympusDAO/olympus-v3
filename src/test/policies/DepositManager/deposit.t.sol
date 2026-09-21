// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

// Vault variants exercise the same deposit action and are intentionally co-located.
// Scenario-specific literals and ignored revert-path return values remain explicit.
// forge-lint: disable-start(literal-instead-of-constant, unused-return)

// Interfaces
import {IERC20 as OZIERC20} from "@openzeppelin-5.7.0/token/ERC20/IERC20.sol";
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IAssetManagerV1_1} from "src/bases/interfaces/IAssetManagerV1_1.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

// Libraries
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {TransferHelper} from "src/libraries/TransferHelper.sol";

// Contracts
import {MockERC20FeeOnTransfer} from "src/test/mocks/MockERC20FeeOnTransfer.sol";
import {ERC7540SyncDepositAsyncRedeemVault} from "src/test/policies/DepositManager/fixtures/ERC7540SyncDepositAsyncRedeemVault.sol";
import {MockERC7540ExternalShareVault} from "src/test/policies/DepositManager/fixtures/MockERC7540ExternalShareVault.sol";
import {MockERC7575Vault} from "src/test/policies/DepositManager/fixtures/MockERC7575Vault.sol";

// Test contracts
import {DepositManagerTest} from "src/test/policies/DepositManager/DepositManagerTest.sol";

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
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: 1e18,
                shouldWrap: false
            })
        );
    }

    // when the caller does not have the deposit operator role
    //  [X] it reverts

    function test_whenCallerIsNotDepositOperator_reverts(
        address caller_
    ) public givenIsEnabled givenFacilityNameIsSetDefault {
        vm.assume(caller_ != DEPOSIT_OPERATOR);

        _expectRevertNotDepositOperator();

        vm.prank(caller_);
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: 1e18,
                shouldWrap: false
            })
        );
    }

    // given the asset period does not exist
    //  given the asset vault is set
    //   [X] it reverts
    //  [X] it reverts

    function test_givenAssetPeriodDoesNotExist_givenAssetVaultIsSet_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
    {
        _expectRevertInvalidConfiguration(iAsset, DEPOSIT_PERIOD);

        vm.prank(DEPOSIT_OPERATOR);
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: 1e18,
                shouldWrap: false
            })
        );
    }

    function test_givenAssetPeriodDoesNotExist_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
    {
        _expectRevertInvalidConfiguration(iAsset, DEPOSIT_PERIOD);

        vm.prank(DEPOSIT_OPERATOR);
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: 1e18,
                shouldWrap: false
            })
        );
    }

    // given the asset period is disabled
    //  [X] it reverts

    function test_givenAssetPeriodIsDisabled_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenAssetPeriodIsDisabled
    {
        _expectRevertAssetPeriodDisabled(iAsset, DEPOSIT_PERIOD);

        vm.prank(DEPOSIT_OPERATOR);
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: 1e18,
                shouldWrap: false
            })
        );
    }

    // when the depositor address is the zero address
    //  [X] it reverts

    function test_whenDepositorAddressIsZeroAddress_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
    {
        vm.expectRevert("TRANSFER_FROM_FAILED");

        vm.prank(DEPOSIT_OPERATOR);
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: address(0),
                amount: 1e18,
                shouldWrap: false
            })
        );
    }

    // when the deposit amount is 0
    //  [X] it reverts

    function test_whenDepositAmountIsZero_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
    {
        vm.expectRevert("ZERO_SHARES");

        vm.prank(DEPOSIT_OPERATOR);
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: 0,
                shouldWrap: false
            })
        );
    }

    // when the deposit amount is below the minimum deposit
    //  [X] it reverts

    function test_whenDepositAmountIsBelowMinimum_reverts(
        uint256 minimumDeposit_,
        uint256 depositAmount_
    ) public givenIsEnabled givenFacilityNameIsSetDefault {
        minimumDeposit_ = bound(minimumDeposit_, 2, type(uint128).max);
        depositAmount_ = bound(depositAmount_, 1, minimumDeposit_ - 1);

        // Add asset with minimum deposit requirement
        vm.prank(ADMIN);
        depositManager.addAsset(iAsset, iVault, type(uint256).max, minimumDeposit_);

        // Add asset period
        vm.prank(ADMIN);
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManager.AssetManager_MinimumDepositNotMet.selector,
                address(iAsset),
                depositAmount_,
                minimumDeposit_
            )
        );

        vm.prank(DEPOSIT_OPERATOR);
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: depositAmount_,
                shouldWrap: false
            })
        );
    }

    // given the depositor has not approved the contract to spend the asset
    //  [X] it reverts

    function test_givenDepositorHasNotApprovedSpendingAsset_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
    {
        // Expect revert
        _expectRevertERC20InsufficientAllowance();

        vm.prank(DEPOSIT_OPERATOR);
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: 1e18,
                shouldWrap: false
            })
        );
    }

    // given the depositor does not have sufficient asset balance
    //  [X] it reverts

    function test_givenDepositorDoesNotHaveSufficientAssetBalance_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT + 1)
    {
        // Expect revert
        _expectRevertERC20InsufficientBalance();

        vm.prank(DEPOSIT_OPERATOR);
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: MINT_AMOUNT + 1,
                shouldWrap: false
            })
        );
    }

    // given the asset is fee-on-transfer
    //  [X] it reverts

    function test_givenAssetIsFeeOnTransfer_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
    {
        // Create a fee-on-transfer asset
        address feeRecipient = makeAddr("feeRecipient");
        MockERC20FeeOnTransfer asset = new MockERC20FeeOnTransfer(
            "Fee On Transfer",
            "FOT",
            feeRecipient
        );

        // Configure the asset vault
        vm.prank(ADMIN);
        depositManager.addAsset(IERC20(address(asset)), IERC4626(address(0)), type(uint256).max, 0);

        // Configure deposit
        vm.prank(ADMIN);
        depositManager.addAssetPeriod(IERC20(address(asset)), DEPOSIT_PERIOD, DEPOSIT_OPERATOR);

        // Mint the asset to the depositor
        vm.prank(ADMIN);
        asset.mint(DEPOSITOR, MINT_AMOUNT);

        // Approve spending of the asset
        vm.prank(DEPOSITOR);
        asset.approve(address(depositManager), MINT_AMOUNT);

        uint256 fee = (MINT_AMOUNT * asset.FEE()) / asset.FEE_DENOMINATOR();

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                TransferHelper.TransferHelper_InexactTransferFrom.selector,
                address(asset),
                address(depositManager),
                MINT_AMOUNT,
                MINT_AMOUNT - fee
            )
        );

        // Deposit
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: IERC20(address(asset)),
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: MINT_AMOUNT,
                shouldWrap: false
            })
        );
    }

    // given the asset's deposit cap is zero
    //  [X] it reverts

    function test_givenAssetDepositCapIsZero_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenAssetDepositCapIsSet(0)
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
    {
        // Expect revert
        _expectRevertDepositCapExceeded(0, 0);

        // Deposit
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: MINT_AMOUNT,
                shouldWrap: false
            })
        );
    }

    // given another operator has consumed the shared asset cap
    //  when a second operator deposits above the remaining headroom
    //   [X] it reverts with the aggregate credited principal

    function test_givenAnotherOperatorConsumedAssetCap_whenDepositExceedsHeadroom_reverts()
        public
        givenIsEnabled
        givenAssetIsAddedWithZeroAddress
    {
        address secondOperator = makeAddr("SECOND_OPERATOR");
        uint256 firstAmount = 60e18;
        uint256 secondAmount = 40e18;

        vm.startPrank(ADMIN);
        rolesAdmin.grantRole("deposit_operator", secondOperator);
        depositManager.setOperatorName(DEPOSIT_OPERATOR, "cd1");
        depositManager.setOperatorName(secondOperator, "cd2");
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, secondOperator);
        depositManager.setAssetDepositCap(iAsset, firstAmount + secondAmount);
        vm.stopPrank();

        _approveSpendingAsset(DEPOSITOR, firstAmount + secondAmount + 1);
        asset.mint(DEPOSITOR, 1);

        vm.prank(DEPOSIT_OPERATOR);
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: firstAmount,
                shouldWrap: false
            })
        );

        vm.prank(secondOperator);
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: secondAmount,
                shouldWrap: false
            })
        );

        assertEq(
            _assetDepositCapUtilization(iAsset),
            firstAmount + secondAmount,
            "aggregate utilization should include both operators"
        );

        _expectRevertDepositCapExceeded(firstAmount + secondAmount, firstAmount + secondAmount);
        vm.prank(secondOperator);
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: 1,
                shouldWrap: false
            })
        );
    }

    // given all cap utilization has been lent out
    //  when the operator deposits one more unit
    //   [X] borrowing does not reopen headroom

    function test_givenCapUtilizationIsBorrowed_whenDepositingOneMore_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAddedWithZeroAddress
        givenAssetPeriodIsAdded
    {
        uint256 cap = MINT_AMOUNT;
        _setAssetDepositCap(cap);
        _approveSpendingAsset(DEPOSITOR, cap + 1);
        asset.mint(DEPOSITOR, 1);

        vm.prank(DEPOSIT_OPERATOR);
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: cap,
                shouldWrap: false
            })
        );

        _setAssetDepositCap(cap - 1);

        vm.prank(DEPOSIT_OPERATOR);
        depositManager.borrowingWithdraw(
            IDepositManager.BorrowingWithdrawParams({
                asset: iAsset,
                recipient: RECIPIENT,
                amount: cap / 2
            })
        );

        assertEq(
            _assetDepositCapUtilization(iAsset),
            cap,
            "borrowing should preserve aggregate utilization"
        );

        _expectRevertDepositCapExceeded(cap, cap - 1);
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: 1,
                shouldWrap: false
            })
        );
    }

    function test_givenTwoDepositPeriods_whenDepositingAtExactSharedCap() public givenIsEnabled {
        uint8 secondPeriod = DEPOSIT_PERIOD + 1;
        uint256 firstAmount = 40e18;
        uint256 secondAmount = 60e18;

        vm.startPrank(ADMIN);
        depositManager.addAsset(iAsset, IERC4626(address(0)), firstAmount + secondAmount, 0);
        depositManager.setOperatorName(DEPOSIT_OPERATOR, "cd1");
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        depositManager.addAssetPeriod(iAsset, secondPeriod, DEPOSIT_OPERATOR);
        vm.stopPrank();
        _approveSpendingAsset(DEPOSITOR, firstAmount + secondAmount);

        vm.startPrank(DEPOSIT_OPERATOR);
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: firstAmount,
                shouldWrap: false
            })
        );
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: secondPeriod,
                depositor: DEPOSITOR,
                amount: secondAmount,
                shouldWrap: false
            })
        );
        vm.stopPrank();

        assertEq(
            _assetDepositCapUtilization(iAsset),
            firstAmount + secondAmount,
            "aggregate utilization should include both periods"
        );
    }

    function test_givenTwoAssets_whenDepositing_utilizationIsIndependent() public givenIsEnabled {
        MockERC20 secondAsset = new MockERC20("Second Asset", "ASSET2", 18);
        IERC20 secondIAsset = IERC20(address(secondAsset));
        uint256 firstAmount = 10e18;
        uint256 secondAmount = 20e18;

        vm.startPrank(ADMIN);
        depositManager.addAsset(iAsset, IERC4626(address(0)), firstAmount, 0);
        depositManager.addAsset(secondIAsset, IERC4626(address(0)), secondAmount, 0);
        depositManager.setOperatorName(DEPOSIT_OPERATOR, "cd1");
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        depositManager.addAssetPeriod(secondIAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        vm.stopPrank();

        _approveSpendingAsset(DEPOSITOR, firstAmount);
        secondAsset.mint(DEPOSITOR, secondAmount);
        vm.prank(DEPOSITOR);
        secondAsset.approve(address(depositManager), secondAmount);

        vm.startPrank(DEPOSIT_OPERATOR);
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: firstAmount,
                shouldWrap: false
            })
        );
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: secondIAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: secondAmount,
                shouldWrap: false
            })
        );
        vm.stopPrank();

        assertEq(_assetDepositCapUtilization(iAsset), firstAmount, "first asset utilization");
        assertEq(
            _assetDepositCapUtilization(secondIAsset),
            secondAmount,
            "second asset utilization"
        );
    }

    function test_whenMaximumCapIsFilled_doesNotOverflow() public givenIsEnabled {
        MockERC20 maxAsset = new MockERC20("Maximum Asset", "MAX", 18);
        IERC20 maxIAsset = IERC20(address(maxAsset));

        vm.startPrank(ADMIN);
        depositManager.addAsset(maxIAsset, IERC4626(address(0)), type(uint256).max, 0);
        depositManager.setOperatorName(DEPOSIT_OPERATOR, "cd1");
        depositManager.addAssetPeriod(maxIAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        vm.stopPrank();
        maxAsset.mint(DEPOSITOR, type(uint256).max);
        vm.prank(DEPOSITOR);
        maxAsset.approve(address(depositManager), type(uint256).max);

        vm.startPrank(DEPOSIT_OPERATOR);
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: maxIAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: 1,
                shouldWrap: false
            })
        );
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: maxIAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: type(uint256).max - 1,
                shouldWrap: false
            })
        );
        vm.stopPrank();

        assertEq(
            _assetDepositCapUtilization(maxIAsset),
            type(uint256).max,
            "maximum cap should be exactly utilized"
        );
    }

    function test_whenDepositCapStatusCallerIsFuzzed(address caller_) public givenIsEnabled {
        assertEq(
            depositManager.getAssetDepositCapStatus(iAsset).depositCap,
            0,
            "unconfigured asset cap should be zero"
        );
        assertEq(
            _assetDepositCapUtilization(iAsset),
            0,
            "unconfigured asset utilization should be zero"
        );

        vm.startPrank(ADMIN);
        depositManager.addAsset(iAsset, IERC4626(address(0)), MINT_AMOUNT, 0);
        depositManager.setOperatorName(DEPOSIT_OPERATOR, "cd1");
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        vm.stopPrank();
        _approveSpendingAsset(DEPOSITOR, MINT_AMOUNT);
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: MINT_AMOUNT,
                shouldWrap: false
            })
        );

        vm.prank(caller_);
        assertEq(
            depositManager.getAssetDepositCapStatus(iAsset).depositCap,
            MINT_AMOUNT,
            "getter should return cap while enabled"
        );
        assertEq(
            _assetDepositCapUtilization(iAsset),
            MINT_AMOUNT,
            "getter should be permissionless while enabled"
        );

        vm.prank(EMERGENCY);
        depositManager.disable("");
        vm.prank(caller_);
        assertEq(
            depositManager.getAssetDepositCapStatus(iAsset).depositCap,
            MINT_AMOUNT,
            "getter should return cap while disabled"
        );
        assertEq(
            _assetDepositCapUtilization(iAsset),
            MINT_AMOUNT,
            "getter should be available while disabled"
        );

        vm.prank(ADMIN);
        depositManager.reEnable();
        vm.prank(caller_);
        assertEq(
            _assetDepositCapUtilization(iAsset),
            MINT_AMOUNT,
            "getter should be available after re-enable"
        );
    }

    // given the asset configuration has the vault set to the zero address
    //  given the existing deposit amount is greater than the deposit cap
    //   [X] it reverts

    function test_givenAssetIsAddedWithZeroAddress_givenTotalAssetsAreGreaterThanDepositCap_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAddedWithZeroAddress
        givenAssetDepositCapIsSet(101e18)
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenDepositorHasAsset(MINT_AMOUNT)
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
    {
        // Expect revert
        _expectRevertDepositCapExceeded(previousAssetLiabilities, 101e18);

        // Deposit
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: MINT_AMOUNT,
                shouldWrap: false
            })
        );
    }

    //  [X] the returned shares are the deposited amount
    //  [X] the asset is stored in the contract
    //  [X] the operator shares are updated with the deposited amount
    //  [X] the wrapped receipt tokens are not minted to the depositor
    //  [X] the receipt tokens are minted to the depositor

    function test_givenAssetIsAddedWithZeroAddress(
        uint256 amount_
    )
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAddedWithZeroAddress
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
    {
        amount_ = bound(amount_, 1e18, MINT_AMOUNT);

        uint256 expectedReceiptTokenId = depositManager.getReceiptTokenId(
            iAsset,
            DEPOSIT_PERIOD,
            DEPOSIT_OPERATOR
        );

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit AssetDeposited(address(iAsset), DEPOSITOR, DEPOSIT_OPERATOR, amount_, amount_);

        // Deposit
        vm.prank(DEPOSIT_OPERATOR);
        (uint256 receiptTokenId, uint256 actualAmount) = depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: amount_,
                shouldWrap: false
            })
        );

        // Assert
        _assertReceiptTokenId(expectedReceiptTokenId, receiptTokenId);
        _assertAssetBalance(amount_, amount_, actualAmount, true);
        _assertReceiptToken(amount_, 0, true, true);
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
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
    {
        uint256 amount = 1e18;
        uint256 expectedShares = vault.previewDeposit(amount);
        uint256 expectedAssets = _getExpectedActualAssets(amount);

        uint256 expectedReceiptTokenId = depositManager.getReceiptTokenId(
            iAsset,
            DEPOSIT_PERIOD,
            DEPOSIT_OPERATOR
        );

        // Deposit
        vm.prank(DEPOSIT_OPERATOR);
        (uint256 receiptTokenId, uint256 actualAmount) = depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: amount,
                shouldWrap: true
            })
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
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(10e18, true)
    {
        uint256 amount = 1e18;
        uint256 expectedShares = vault.previewDeposit(amount);
        uint256 expectedAssets = _getExpectedActualAssets(amount);

        uint256 expectedReceiptTokenId = depositManager.getReceiptTokenId(
            iAsset,
            DEPOSIT_PERIOD,
            DEPOSIT_OPERATOR
        );

        // Deposit
        vm.prank(DEPOSIT_OPERATOR);
        (uint256 receiptTokenId, uint256 actualAmount) = depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: amount,
                shouldWrap: true
            })
        );

        // Assert
        _assertReceiptTokenId(expectedReceiptTokenId, receiptTokenId);
        _assertAssetBalance(expectedShares, expectedAssets, actualAmount, true);
        _assertReceiptToken(0, expectedAssets, true, true);
        _assertDepositAssetBalance(DEPOSITOR, MINT_AMOUNT - 10e18 - expectedAssets);
    }

    // given the existing deposit amount is greater than the deposit cap
    //  [X] it reverts

    function test_givenTotalAssetsAreGreaterThanDepositCap_reverts()
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetDepositCapIsSet(101e18)
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
        givenDeposit(MINT_AMOUNT, false)
        givenDepositorHasAsset(MINT_AMOUNT)
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
    {
        // Expect revert
        _expectRevertDepositCapExceeded(previousAssetLiabilities, 101e18);

        // Deposit
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: MINT_AMOUNT,
                shouldWrap: false
            })
        );
    }

    // when the amount is less than one share
    //  [X] it reverts

    function test_whenAmountLessThanOneShare_reverts(
        uint256 amount_
    )
        public
        givenIsEnabled
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
    {
        // Earn yield
        asset.mint(address(vault), 10e18);

        // Calculate amount
        uint256 oneShareInAssets = vault.previewMint(1);
        amount_ = bound(amount_, 1, oneShareInAssets - 1);

        // Expect revert
        vm.expectRevert("ZERO_SHARES");

        // Deposit
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: amount_,
                shouldWrap: false
            })
        );
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
        givenFacilityNameIsSetDefault
        givenAssetIsAdded
        givenAssetPeriodIsAdded
        givenDepositorHasApprovedSpendingAsset(MINT_AMOUNT)
    {
        amount_ = bound(amount_, 1e18, MINT_AMOUNT);

        // Determine expected amounts
        uint256 expectedShares = vault.previewDeposit(amount_);
        uint256 expectedAssets = _getExpectedActualAssets(amount_);

        uint256 expectedReceiptTokenId = depositManager.getReceiptTokenId(
            iAsset,
            DEPOSIT_PERIOD,
            DEPOSIT_OPERATOR
        );

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
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: amount_,
                shouldWrap: false
            })
        );

        // Assert
        _assertReceiptTokenId(expectedReceiptTokenId, receiptTokenId);
        _assertAssetBalance(expectedShares, expectedAssets, actualAmount, true);
        _assertReceiptToken(expectedAssets, 0, true, true);
        _assertDepositAssetBalance(DEPOSITOR, MINT_AMOUNT - expectedAssets);
    }

    // ========== ERC-7540 AND ERC-7575 TESTS ========== //

    uint256 internal constant _ASSETS_PER_SHARE = 1e12;
    uint256 internal constant _DEPOSIT_AMOUNT = 10e18;

    MockERC7540ExternalShareVault internal _externalVault;
    IERC20 internal _externalShare;

    function _configureExternalVault(bool asyncRedeem_) internal {
        _externalVault = new MockERC7540ExternalShareVault(asset, false, asyncRedeem_, true);
        _externalShare = IERC20(_externalVault.share());

        vm.startPrank(ADMIN);
        depositManager.enable("");
        depositManager.addAsset(iAsset, IERC4626(address(_externalVault)), type(uint256).max, 0);
        depositManager.setOperatorName(DEPOSIT_OPERATOR, "cd1");
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        vm.stopPrank();
    }

    function _deposit(uint256 amount_) internal returns (uint256 actualAmount) {
        _approveSpendingAsset(DEPOSITOR, amount_);
        return _executeDeposit(amount_);
    }

    function _executeDeposit(uint256 amount_) internal returns (uint256 actualAmount) {
        vm.prank(DEPOSIT_OPERATOR);
        (, actualAmount) = depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: amount_,
                shouldWrap: false
            })
        );
    }

    function _expectInexactShares(uint256 expectedShares_, uint256 receivedShares_) internal {
        _approveSpendingAsset(DEPOSITOR, _DEPOSIT_AMOUNT);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManagerV1_1.AssetManager_InexactSharesReceived.selector,
                address(iAsset),
                address(_externalShare),
                expectedShares_,
                receivedShares_
            )
        );
    }

    function test_givenAsyncRedeem_whenPreviewDeposit() public {
        _configureExternalVault(true);

        (uint256 creditedAssets, uint256 custodyShares) = depositManager.previewDeposit(
            iAsset,
            _DEPOSIT_AMOUNT
        );

        assertEq(custodyShares, 10e6, "preview should return raw six-decimal shares");
        assertEq(creditedAssets, _DEPOSIT_AMOUNT, "async preview should use convertToAssets");
    }

    function test_givenSynchronousRedeem_whenPreviewRedeemDiffersFromConvertToAssets() public {
        _configureExternalVault(false);
        _externalVault.setPreviewRedeemDiscount(1);

        (uint256 creditedAssets, uint256 custodyShares) = depositManager.previewDeposit(
            iAsset,
            _DEPOSIT_AMOUNT
        );

        assertEq(custodyShares, 10e6, "preview should return raw six-decimal shares");
        assertEq(
            creditedAssets,
            _DEPOSIT_AMOUNT - 1,
            "synchronous preview should use previewRedeem"
        );
    }

    function test_givenAsyncRedeem_whenDepositing(uint256 amount_) public {
        _configureExternalVault(true);
        amount_ = bound(amount_, _ASSETS_PER_SHARE, MINT_AMOUNT);
        uint256 expectedShares = amount_ / _ASSETS_PER_SHARE;

        uint256 actualAmount = _deposit(amount_);
        uint256 expectedCredit = _externalVault.convertToAssets(expectedShares);
        (uint256 operatorShares, uint256 operatorAssets) = depositManager.getOperatorAssets(
            iAsset,
            DEPOSIT_OPERATOR
        );

        assertEq(actualAmount, expectedCredit, "deposit credit should use convertToAssets");
        assertEq(asset.decimals(), 18, "underlying should use eighteen decimals");
        assertEq(
            ERC20(address(_externalShare)).decimals(),
            6,
            "external shares should use six decimals"
        );
        assertEq(operatorShares, expectedShares, "operator accounting should use raw shares");
        assertEq(operatorAssets, expectedCredit, "operator value should use convertToAssets");
        assertEq(
            _externalShare.balanceOf(address(depositManager)),
            expectedShares,
            "physical external-share custody should equal operator shares"
        );
    }

    function test_givenSynchronousRedeemExternalShareToken_whenDepositing(uint256 amount_) public {
        _configureExternalVault(false);
        amount_ = bound(amount_, _ASSETS_PER_SHARE, MINT_AMOUNT);
        uint256 expectedShares = amount_ / _ASSETS_PER_SHARE;

        uint256 actualAmount = _deposit(amount_);
        (uint256 operatorShares, uint256 operatorAssets) = depositManager.getOperatorAssets(
            iAsset,
            DEPOSIT_OPERATOR
        );

        assertEq(actualAmount, amount_, "deposit credit");
        assertEq(asset.decimals(), 18, "underlying decimals");
        assertEq(ERC20(address(_externalShare)).decimals(), 6, "external share decimals");
        assertEq(operatorShares, expectedShares, "raw external shares");
        assertEq(operatorAssets, amount_, "operator assets");
        assertEq(
            _externalShare.balanceOf(address(depositManager)),
            expectedShares,
            "external share custody"
        );
    }

    function test_givenAsyncRedeemSelfShareToken_whenDepositing() public {
        ERC7540SyncDepositAsyncRedeemVault selfShareVault = new ERC7540SyncDepositAsyncRedeemVault(
            OZIERC20(address(asset))
        );
        vm.startPrank(ADMIN);
        depositManager.enable("");
        depositManager.addAsset(iAsset, IERC4626(address(selfShareVault)), type(uint256).max, 0);
        depositManager.setOperatorName(DEPOSIT_OPERATOR, "cd1");
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        vm.stopPrank();

        uint256 actualAmount = _deposit(_DEPOSIT_AMOUNT);
        (uint256 operatorShares, uint256 operatorAssets) = depositManager.getOperatorAssets(
            iAsset,
            DEPOSIT_OPERATOR
        );

        assertEq(actualAmount, _DEPOSIT_AMOUNT, "deposit credit");
        assertEq(operatorShares, _DEPOSIT_AMOUNT, "self-share accounting");
        assertEq(operatorAssets, _DEPOSIT_AMOUNT, "self-share assets");
        assertEq(
            selfShareVault.balanceOf(address(depositManager)),
            _DEPOSIT_AMOUNT,
            "self-share custody"
        );
    }

    function test_givenSynchronousRedeemSelfShareToken_whenDepositing() public {
        MockERC7575Vault selfShareVault = new MockERC7575Vault(asset, false);
        vm.startPrank(ADMIN);
        depositManager.enable("");
        depositManager.addAsset(iAsset, IERC4626(address(selfShareVault)), type(uint256).max, 0);
        depositManager.setOperatorName(DEPOSIT_OPERATOR, "cd1");
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, DEPOSIT_OPERATOR);
        vm.stopPrank();

        uint256 actualAmount = _deposit(_DEPOSIT_AMOUNT);

        assertEq(actualAmount, _DEPOSIT_AMOUNT, "deposit credit");
        assertEq(
            selfShareVault.balanceOf(address(depositManager)),
            _DEPOSIT_AMOUNT,
            "self-share custody"
        );
    }

    function test_givenAsyncRedeem_whenYieldAccrues() public {
        _configureExternalVault(true);
        _deposit(_DEPOSIT_AMOUNT);
        _externalVault.setAssetsPerShare(2e12);

        (, uint256 operatorAssets) = depositManager.getOperatorAssets(iAsset, DEPOSIT_OPERATOR);
        uint256 maxYield = depositManager.maxClaimYield(iAsset, DEPOSIT_OPERATOR);

        assertEq(operatorAssets, 20e18, "operator value should follow live convertToAssets");
        assertEq(maxYield, 10e18 - 1, "yield capacity should use async share valuation");
    }

    function test_givenAsyncDepositEnabled_whenPreviewing_reverts() public {
        _configureExternalVault(false);
        _externalVault.setCapabilities(true, false, true, true);

        vm.expectRevert(MockERC7540ExternalShareVault.AsyncDeposit.selector);
        depositManager.previewDeposit(iAsset, _DEPOSIT_AMOUNT);
    }

    function test_givenAsyncDepositEnabled_whenDepositing_revertsAndRollsBackTransfer() public {
        _configureExternalVault(false);
        _externalVault.setCapabilities(true, false, true, true);
        uint256 depositorBalanceBefore = asset.balanceOf(DEPOSITOR);
        vm.prank(DEPOSITOR);
        asset.approve(address(depositManager), _DEPOSIT_AMOUNT);

        vm.expectRevert(MockERC7540ExternalShareVault.AsyncDeposit.selector);
        vm.prank(DEPOSIT_OPERATOR);
        depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: _DEPOSIT_AMOUNT,
                shouldWrap: false
            })
        );

        assertEq(asset.balanceOf(DEPOSITOR), depositorBalanceBefore, "depositor balance rollback");
        assertEq(asset.balanceOf(address(depositManager)), 0, "manager balance rollback");
        assertEq(asset.balanceOf(address(_externalVault)), 0, "vault balance unchanged");
    }

    function test_givenVaultReturnsMoreSharesThanReceived_reverts() public {
        _configureExternalVault(false);
        _externalVault.setDepositResults(9e6, 10e6);
        _expectInexactShares(10e6, 9e6);

        _executeDeposit(_DEPOSIT_AMOUNT);
    }

    function test_givenVaultReturnsFewerSharesThanReceived_reverts() public {
        _configureExternalVault(false);
        _externalVault.setDepositResults(10e6, 9e6);
        _expectInexactShares(9e6, 10e6);

        _executeDeposit(_DEPOSIT_AMOUNT);
    }

    function test_givenVaultReturnsSharesWithoutMinting_reverts() public {
        _configureExternalVault(false);
        _externalVault.setDepositResults(0, 10e6);
        _expectInexactShares(10e6, 0);

        _executeDeposit(_DEPOSIT_AMOUNT);
    }

    function test_givenVaultReturnsZeroShares_revertsAndRollsBackMint() public {
        _configureExternalVault(false);
        _externalVault.setDepositResults(1, 0);

        vm.prank(DEPOSITOR);
        asset.approve(address(depositManager), _DEPOSIT_AMOUNT);

        vm.expectRevert(IAssetManager.AssetManager_ZeroAmount.selector);
        _executeDeposit(_DEPOSIT_AMOUNT);

        assertEq(
            _externalShare.balanceOf(address(depositManager)),
            0,
            "zero-return deposit should roll back share mint"
        );
    }

    function test_whenPreviewingMaximumAmount() public {
        _configureExternalVault(true);

        (uint256 creditedAssets, uint256 custodyShares) = depositManager.previewDeposit(
            iAsset,
            type(uint256).max
        );

        assertEq(
            custodyShares,
            type(uint256).max / _ASSETS_PER_SHARE,
            "maximum preview should preserve vault share scaling"
        );
        assertEq(
            creditedAssets,
            custodyShares * _ASSETS_PER_SHARE,
            "maximum preview credit should round down through vault conversion"
        );
    }
}

// forge-lint: disable-end(literal-instead-of-constant, unused-return)
