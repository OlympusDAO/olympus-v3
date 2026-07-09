// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {Kernel, Keycode, Permissions} from "src/Kernel.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IReceiptTokenManager} from "src/policies/interfaces/deposits/IReceiptTokenManager.sol";

contract MockDepositManager is IDepositManager {
    Kernel public kernel;

    IERC20 public asset;

    constructor(Kernel kernel_, address asset_) {
        kernel = kernel_;
        asset = IERC20(asset_);
    }

    function configureDependencies() external returns (Keycode[] memory dependencies) {}

    function requestPermissions() external returns (Permissions[] memory permissions) {}

    // ========== DEPOSIT/WITHDRAW FUNCTIONS ========== //

    function deposit(
        DepositParams calldata params
    ) external override returns (uint256 receiptTokenId, uint256 actualAmount) {
        asset.transferFrom(params.depositor, address(this), params.amount);
        return (1, params.amount);
    }

    function withdraw(
        WithdrawParams calldata params
    ) external override returns (uint256 actualAmount) {
        asset.transfer(params.recipient, params.amount);
        return params.amount;
    }

    function maxClaimYield(IERC20, address) external pure override returns (uint256) {
        return 0;
    }

    function claimYield(IERC20, address, uint256) external pure override returns (uint256) {
        return 0;
    }

    function getOperatorLiabilities(IERC20, address) external pure override returns (uint256) {
        return 0;
    }

    // ========== BORROWING FUNCTIONS ========== //

    function borrowingWithdraw(
        BorrowingWithdrawParams calldata
    ) external pure override returns (uint256) {
        return 0;
    }

    function borrowingRepay(
        BorrowingRepayParams calldata
    ) external pure override returns (uint256) {
        return 0;
    }

    function borrowingDefault(BorrowingDefaultParams calldata) external pure override {}

    function getBorrowedAmount(IERC20, address) external pure override returns (uint256) {
        return 0;
    }

    function getBorrowingCapacity(IERC20, address) external pure override returns (uint256) {
        return 0;
    }

    // ========== OPERATOR NAMES ========== //

    function setOperatorName(address, string calldata) external pure override {}

    function getOperatorName(address) external pure override returns (string memory) {
        return "";
    }

    // ========== DEPOSIT CONFIGURATIONS ========== //

    function addAsset(IERC20, IERC4626, uint256, uint256) external pure override {}

    function setAssetDepositCap(IERC20, uint256) external pure override {}

    function setAssetMinimumDeposit(IERC20, uint256) external pure override {}

    function addAssetPeriod(IERC20, uint8, address) external pure override returns (uint256) {
        return 0;
    }

    function disableAssetPeriod(IERC20, uint8, address) external pure override {}

    function enableAssetPeriod(IERC20, uint8, address) external pure override {}

    function getAssetPeriod(
        IERC20,
        uint8,
        address
    ) external pure override returns (AssetPeriod memory) {
        return AssetPeriod(false, 0, address(0), address(0));
    }

    function getAssetPeriod(uint256) external pure override returns (AssetPeriod memory) {
        return AssetPeriod(false, 0, address(0), address(0));
    }

    function isAssetPeriod(
        IERC20,
        uint8,
        address
    ) external pure override returns (AssetPeriodStatus memory) {
        return AssetPeriodStatus(false, false);
    }

    function getAssetPeriods() external pure override returns (AssetPeriod[] memory) {
        return new AssetPeriod[](0);
    }

    // ========== RECEIPT TOKEN FUNCTIONS ========== //

    function getReceiptTokenId(IERC20, uint8, address) external pure override returns (uint256) {
        return 0;
    }

    function getReceiptToken(
        IERC20,
        uint8,
        address
    ) external pure override returns (uint256, address) {
        return (0, address(0));
    }

    function getReceiptTokenManager() external pure override returns (IReceiptTokenManager) {
        return IReceiptTokenManager(address(0));
    }

    function getReceiptTokenIds() external pure override returns (uint256[] memory) {
        return new uint256[](0);
    }

    // ========== IAssetManager FUNCTIONS ========== //

    function getOperatorAssets(IERC20, address) external pure override returns (uint256, uint256) {
        return (0, 0);
    }

    function getAssetConfiguration(
        IERC20
    ) external pure override returns (AssetConfiguration memory) {
        return AssetConfiguration(false, 0, 0, address(0));
    }

    function getConfiguredAssets() external pure override returns (IERC20[] memory) {
        return new IERC20[](0);
    }
}
