// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {Test} from "@forge-std-1.9.6/Test.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {OlympusRoles} from "src/modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "src/policies/RolesAdmin.sol";
import {DepositManager} from "src/policies/DepositManager.sol";

import {IDepositManager} from "src/policies/interfaces/IDepositManager.sol";
import {IPolicyAdmin} from "src/policies/interfaces/utils/IPolicyAdmin.sol";
import {IPolicyEnabler} from "src/policies/interfaces/utils/IPolicyEnabler.sol";
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";

import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";
import {ERC6909} from "@openzeppelin-5.3.0/token/ERC6909/draft-ERC6909.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IERC6909Wrappable} from "src/interfaces/IERC6909Wrappable.sol";
import {stdError} from "@forge-std-1.9.6/StdError.sol";

// solhint-disable max-states-count
contract DepositManagerTest is Test {
    address public ADMIN;
    address public MANAGER;
    address public DEPOSIT_OPERATOR;
    address public DEPOSITOR;

    Kernel public kernel;
    OlympusRoles public roles;
    RolesAdmin public rolesAdmin;
    DepositManager public depositManager;

    MockERC20 public asset;
    MockERC4626 public vault;
    IERC20 public iAsset;
    IERC4626 public iVault;

    uint256 public previousDepositManagerAssetBalance;
    uint256 public previousDepositManagerSharesBalance;
    uint256 public previousDepositManagerOperatorSharesBalance;
    uint256 public previousDepositorDepositActualAmount;
    uint256 public previousDepositorReceiptTokenBalance;
    uint256 public previousDepositorWrappedTokenBalance;
    uint256 public previousAssetLiabilities;

    uint8 public constant DEPOSIT_PERIOD = 1;
    uint256 public constant MINT_AMOUNT = 100e18;
    uint16 public constant RECLAIM_RATE = 90e2;

    function setUp() public {
        ADMIN = makeAddr("ADMIN");
        MANAGER = makeAddr("MANAGER");
        DEPOSIT_OPERATOR = makeAddr("DEPOSIT_OPERATOR");
        DEPOSITOR = makeAddr("DEPOSITOR");

        // Kernel
        vm.startPrank(ADMIN);
        kernel = new Kernel();

        // Create modules and policies
        roles = new OlympusRoles(kernel);
        rolesAdmin = new RolesAdmin(kernel);
        depositManager = new DepositManager(address(kernel));
        vm.stopPrank();

        // Install modules and policies
        vm.startPrank(ADMIN);
        kernel.executeAction(Actions.InstallModule, address(roles));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(depositManager));
        vm.stopPrank();

        // Grant roles
        vm.startPrank(ADMIN);
        rolesAdmin.grantRole("admin", ADMIN);
        rolesAdmin.grantRole("manager", MANAGER);
        rolesAdmin.grantRole("deposit_operator", DEPOSIT_OPERATOR);
        vm.stopPrank();

        // Configure asset
        asset = new MockERC20("Asset", "ASSET", 18);
        vault = new MockERC4626(ERC20(address(asset)), "Vault", "VAULT");
        iAsset = IERC20(address(asset));
        iVault = IERC4626(address(vault));

        // Simulate the asset vault having earnt yield
        {
            // Deposit into the vault
            asset.mint(address(this), 100e18);
            asset.approve(address(vault), 100e18);
            vault.deposit(100e18, address(this));

            // Earn yield
            asset.mint(address(vault), 10e18);

            // Validate
            assertFalse(
                vault.convertToAssets(1e18) == 1e18,
                "convertToAssets should not be equal to 1e18"
            );
        }

        // Mint balance to the depositor
        asset.mint(DEPOSITOR, MINT_AMOUNT);

        // Deposit manager is disabled by default
    }

    // ========== MODIFIERS ========== //

    modifier givenIsEnabled() {
        vm.prank(ADMIN);
        depositManager.enable("");
        _;
    }

    modifier givenIsDisabled() {
        vm.prank(ADMIN);
        depositManager.disable("");
        _;
    }

    modifier givenAssetVaultIsConfigured() {
        vm.prank(ADMIN);
        depositManager.addAsset(iAsset, iVault, type(uint256).max);
        _;
    }

    modifier givenAssetVaultIsConfiguredWithZeroAddress() {
        vm.prank(ADMIN);
        depositManager.addAsset(iAsset, IERC4626(address(0)), type(uint256).max);
        _;
    }

    modifier givenDepositIsConfigured() {
        vm.prank(ADMIN);
        depositManager.addAssetPeriod(iAsset, DEPOSIT_PERIOD, RECLAIM_RATE);
        _;
    }

    modifier givenAssetPeriodIsDisabled() {
        vm.prank(ADMIN);
        depositManager.disableAssetPeriod(iAsset, DEPOSIT_PERIOD);
        _;
    }

    modifier givenDepositorHasApprovedSpendingAsset(uint256 amount_) {
        vm.prank(DEPOSITOR);
        asset.approve(address(depositManager), amount_);
        _;
    }

    modifier givenDepositorHasAsset(uint256 amount_) {
        asset.mint(DEPOSITOR, amount_);
        _;
    }

    modifier givenDeposit(uint256 amount_, bool shouldWrap_) {
        vm.prank(DEPOSIT_OPERATOR);
        (, previousDepositorDepositActualAmount) = depositManager.deposit(
            IDepositManager.DepositParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                amount: amount_,
                shouldWrap: shouldWrap_
            })
        );

        // Update the previous balances
        uint256 receiptTokenId = depositManager.getReceiptTokenId(iAsset, DEPOSIT_PERIOD);
        previousDepositorReceiptTokenBalance = depositManager.balanceOf(DEPOSITOR, receiptTokenId);
        if (depositManager.getWrappedToken(receiptTokenId) != address(0)) {
            previousDepositorWrappedTokenBalance = IERC20(
                depositManager.getWrappedToken(receiptTokenId)
            ).balanceOf(DEPOSITOR);
        }

        previousDepositManagerAssetBalance = asset.balanceOf(address(depositManager));
        previousDepositManagerSharesBalance = vault.balanceOf(address(depositManager));

        (uint256 shares, uint256 sharesInAssets) = depositManager.getOperatorAssets(
            iAsset,
            DEPOSIT_OPERATOR
        );
        previousDepositManagerOperatorSharesBalance = shares;

        previousAssetLiabilities = depositManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR);
        _;
    }

    modifier givenDepositorHasApprovedSpendingWrappedReceiptToken(uint256 amount_) {
        uint256 receiptTokenId = depositManager.getReceiptTokenId(iAsset, DEPOSIT_PERIOD);
        address wrappedToken = depositManager.getWrappedToken(receiptTokenId);

        vm.prank(DEPOSITOR);
        IERC20(wrappedToken).approve(address(depositManager), amount_);
        _;
    }

    modifier givenDepositorHasApprovedSpendingReceiptToken(uint256 amount_) {
        uint256 receiptTokenId = depositManager.getReceiptTokenId(iAsset, DEPOSIT_PERIOD);

        vm.prank(DEPOSITOR);
        depositManager.approve(address(depositManager), receiptTokenId, amount_);
        _;
    }

    function _withdraw(
        address recipient_,
        uint256 amount_,
        bool wrapped_
    ) internal returns (uint256 actualAmount) {
        vm.prank(DEPOSIT_OPERATOR);
        actualAmount = depositManager.withdraw(
            IDepositManager.WithdrawParams({
                asset: iAsset,
                depositPeriod: DEPOSIT_PERIOD,
                depositor: DEPOSITOR,
                recipient: recipient_,
                amount: amount_,
                isWrapped: wrapped_
            })
        );
    }

    function _withdraw(uint256 amount_, bool wrapped_) internal returns (uint256 actualAmount) {
        return _withdraw(DEPOSITOR, amount_, wrapped_);
    }

    function _setAssetDepositCap(uint256 depositCap_) internal {
        vm.prank(ADMIN);
        depositManager.setAssetDepositCap(iAsset, depositCap_);
    }

    modifier givenAssetDepositCapIsSet(uint256 depositCap_) {
        _setAssetDepositCap(depositCap_);
        _;
    }

    // ========== REVERT HELPERS ========== //

    function _expectRevertNotEnabled() internal {
        vm.expectRevert(abi.encodeWithSelector(IPolicyEnabler.NotEnabled.selector));
    }

    function _expectRevertNotManagerOrAdmin() internal {
        vm.expectRevert(abi.encodeWithSelector(IPolicyAdmin.NotAuthorised.selector));
    }

    function _expectRevertNotDepositOperator() internal {
        vm.expectRevert(
            abi.encodeWithSelector(ROLESv1.ROLES_RequireRole.selector, bytes32("deposit_operator"))
        );
    }

    function _expectRevertNotConfiguredAsset(IERC20 asset_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManager.AssetManager_NotConfigured.selector,
                address(asset_)
            )
        );
    }

    function _expectRevertInvalidReceiptTokenId(IERC20 asset_, uint8 depositPeriod_) internal {
        uint256 receiptTokenId = depositManager.getReceiptTokenId(asset_, depositPeriod_);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC6909Wrappable.ERC6909Wrappable_InvalidTokenId.selector,
                receiptTokenId
            )
        );
    }

    function _expectRevertInvalidConfiguration(IERC20 asset_, uint8 depositPeriod_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_InvalidAssetPeriod.selector,
                address(asset_),
                depositPeriod_
            )
        );
    }

    function _expectRevertConfigurationEnabled(IERC20 asset_, uint8 depositPeriod_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_AssetPeriodEnabled.selector,
                address(asset_),
                depositPeriod_
            )
        );
    }

    function _expectRevertConfigurationDisabled(IERC20 asset_, uint8 depositPeriod_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_AssetPeriodDisabled.selector,
                address(asset_),
                depositPeriod_
            )
        );
    }

    function _expectRevertZeroAddress() internal {
        vm.expectRevert(
            abi.encodeWithSelector(IDepositManager.DepositManager_ZeroAddress.selector)
        );
    }

    function _expectRevertZeroAmount() internal {
        vm.expectRevert(abi.encodeWithSelector(IAssetManager.AssetManager_ZeroAmount.selector));
    }

    function _expectRevertERC20InsufficientAllowance() internal {
        vm.expectRevert("TRANSFER_FROM_FAILED");
    }

    function _expectRevertERC20InsufficientBalance() internal {
        vm.expectRevert("TRANSFER_FROM_FAILED");
    }

    function _expectRevertERC20CloneInsufficientAllowance() internal {
        vm.expectRevert(stdError.arithmeticError);
    }

    function _expectRevertERC20CloneInsufficientBalance() internal {
        vm.expectRevert(stdError.arithmeticError);
    }

    function _expectRevertReceiptTokenInsufficientAllowance(
        uint256 currentAllowance_,
        uint256 amount_
    ) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC6909.ERC6909InsufficientAllowance.selector,
                address(depositManager),
                currentAllowance_,
                amount_,
                depositManager.getReceiptTokenId(iAsset, DEPOSIT_PERIOD)
            )
        );
    }

    function _expectRevertReceiptTokenInsufficientBalance(
        uint256 currentBalance_,
        uint256 amount_
    ) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC6909.ERC6909InsufficientBalance.selector,
                DEPOSITOR,
                currentBalance_,
                amount_,
                depositManager.getReceiptTokenId(iAsset, DEPOSIT_PERIOD)
            )
        );
    }

    function _expectRevertInsolvent(uint256 liabilities_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IDepositManager.DepositManager_Insolvent.selector,
                address(iAsset),
                liabilities_
            )
        );
    }

    function _expectRevertDepositCapExceeded(uint256 balance_, uint256 depositCap_) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAssetManager.AssetManager_DepositCapExceeded.selector,
                address(iAsset),
                balance_,
                depositCap_
            )
        );
    }

    // ========== ASSERTIONS ========== //

    function _assertAssetBalance(
        uint256 expectedSharesAmount_,
        uint256 expectedAssetAmount_,
        uint256 actualAssetAmount_,
        bool isDeposit_
    ) internal view {
        // Asset amount
        assertEq(actualAssetAmount_, expectedAssetAmount_, "Asset amount mismatch");

        DepositManager.AssetConfiguration memory assetConfiguration = depositManager
            .getAssetConfiguration(iAsset);

        // If the vault is not set
        if (address(assetConfiguration.vault) == address(0)) {
            // Assets = shares
            assertEq(
                actualAssetAmount_,
                expectedSharesAmount_,
                "No vault: Assets and shares mismatch"
            );

            // The assets should be in the deposit manager
            if (isDeposit_) {
                assertEq(
                    asset.balanceOf(address(depositManager)),
                    previousDepositManagerAssetBalance + actualAssetAmount_,
                    "No vault: DepositManager asset balance mismatch"
                );
            } else {
                assertEq(
                    asset.balanceOf(address(depositManager)),
                    previousDepositManagerAssetBalance - actualAssetAmount_,
                    "No vault: DepositManager asset balance mismatch"
                );
            }

            // There should be no vault shares in the deposit manager
            assertEq(
                vault.balanceOf(address(depositManager)),
                0,
                "No vault: DepositManager vault shares balance mismatch"
            );

            // The operator assets should be updated with the deposited amount
            (uint256 shares, uint256 sharesInAssets) = depositManager.getOperatorAssets(
                iAsset,
                DEPOSIT_OPERATOR
            );

            if (isDeposit_) {
                assertEq(
                    sharesInAssets,
                    previousDepositManagerAssetBalance + actualAssetAmount_,
                    "No vault: Operator shares in assets balance mismatch"
                );
            } else {
                assertEq(
                    sharesInAssets,
                    previousDepositManagerAssetBalance - actualAssetAmount_,
                    "No vault: Operator shares in assets balance mismatch"
                );
            }

            if (isDeposit_) {
                assertEq(
                    shares,
                    previousDepositManagerAssetBalance + actualAssetAmount_,
                    "No vault: Operator shares balance mismatch"
                );
            } else {
                assertEq(
                    shares,
                    previousDepositManagerAssetBalance - actualAssetAmount_,
                    "No vault: Operator shares balance mismatch"
                );
            }
        }
        // Vault is set
        else {
            // Assets != shares
            assertFalse(
                actualAssetAmount_ == expectedSharesAmount_,
                "Vault: Assets and shares mismatch"
            );

            if (isDeposit_) {
                // The vault shares should be in the deposit manager
                assertEq(
                    vault.balanceOf(address(depositManager)),
                    previousDepositManagerSharesBalance + expectedSharesAmount_,
                    "Vault: DepositManager vault shares balance mismatch"
                );
            } else {
                assertEq(
                    vault.balanceOf(address(depositManager)),
                    previousDepositManagerSharesBalance - expectedSharesAmount_,
                    "Vault: DepositManager vault shares balance mismatch"
                );
            }

            // There should be no assets in the deposit manager
            assertEq(
                asset.balanceOf(address(depositManager)),
                0,
                "Vault: DepositManager asset balance mismatch"
            );

            // The operator assets should be updated with the deposited amount
            (uint256 shares, uint256 sharesInAssets) = depositManager.getOperatorAssets(
                iAsset,
                DEPOSIT_OPERATOR
            );

            assertEq(
                sharesInAssets,
                vault.previewRedeem(shares),
                "Vault: Operator shares in assets balance mismatch"
            );
            if (isDeposit_) {
                assertEq(
                    shares,
                    previousDepositManagerOperatorSharesBalance + expectedSharesAmount_,
                    "Vault: Operator shares balance mismatch"
                );
            } else {
                assertEq(
                    shares,
                    previousDepositManagerOperatorSharesBalance - expectedSharesAmount_,
                    "Vault: Operator shares balance mismatch"
                );
            }
        }

        // Liabilities is the deposit amount
        if (isDeposit_) {
            assertEq(
                depositManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR),
                previousAssetLiabilities + actualAssetAmount_,
                "Liabilities mismatch"
            );
        } else {
            assertEq(
                depositManager.getOperatorLiabilities(iAsset, DEPOSIT_OPERATOR),
                previousAssetLiabilities - actualAssetAmount_,
                "Liabilities mismatch"
            );
        }
    }

    function _assertReceiptTokenId(
        uint256 expectedReceiptTokenId_,
        uint256 actualReceiptTokenId_
    ) internal pure {
        assertEq(actualReceiptTokenId_, expectedReceiptTokenId_, "receipt token id mismatch");
    }

    function _assertReceiptToken(
        uint256 unwrappedAmount_,
        uint256 wrappedAmount_,
        bool wrappedTokenExists_,
        bool isDeposit_
    ) internal view {
        uint256 receiptTokenId = depositManager.getReceiptTokenId(iAsset, DEPOSIT_PERIOD);

        // Unwrapped amount
        if (isDeposit_) {
            assertEq(
                depositManager.balanceOf(DEPOSITOR, receiptTokenId),
                previousDepositorReceiptTokenBalance + unwrappedAmount_,
                "Receipt token balance mismatch"
            );
        } else {
            assertEq(
                depositManager.balanceOf(DEPOSITOR, receiptTokenId),
                previousDepositorReceiptTokenBalance - unwrappedAmount_,
                "Receipt token balance mismatch"
            );
        }

        address wrappedToken = depositManager.getWrappedToken(receiptTokenId);

        // Wrapped token exists
        if (wrappedTokenExists_) {
            assertTrue(wrappedToken != address(0), "Wrapped receipt token should exist");
        } else {
            assertTrue(wrappedToken == address(0), "Wrapped receipt token should not exist");
        }

        // Wrapped amount
        if (wrappedTokenExists_) {
            if (isDeposit_) {
                assertEq(
                    IERC20(wrappedToken).balanceOf(DEPOSITOR),
                    previousDepositorWrappedTokenBalance + wrappedAmount_,
                    "Wrapped receipt token: depositor balance mismatch"
                );
            } else {
                assertEq(
                    IERC20(wrappedToken).balanceOf(DEPOSITOR),
                    previousDepositorWrappedTokenBalance - wrappedAmount_,
                    "Wrapped receipt token: depositor balance mismatch"
                );
            }
        }
    }

    function _assertDepositAssetBalance(
        address account_,
        uint256 depositAssetBalance_
    ) internal view {
        // Use approx here as the returned asset amount can be 1 wei off
        assertApproxEqAbs(
            asset.balanceOf(account_),
            depositAssetBalance_,
            1,
            "Asset balance mismatch"
        );
    }

    function _getExpectedActualAssets(uint256 depositAmount_) internal view returns (uint256) {
        uint256 shares = vault.previewDeposit(depositAmount_);
        uint256 currentSupply = vault.totalSupply();
        uint256 currentAssets = vault.totalAssets();

        // Calculate if we'll lose 1 wei due to rounding in mulDivDown
        // If there's any remainder in the division, we'll lose 1 wei
        uint256 remainder = (shares * (currentAssets + depositAmount_)) % (currentSupply + shares);
        return depositAmount_ - (remainder > 0 ? 1 : 0);
    }
}
