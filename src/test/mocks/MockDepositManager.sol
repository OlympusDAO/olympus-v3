// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";

import {Kernel, Keycode, Permissions} from "src/Kernel.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IReceiptTokenManager} from "src/policies/interfaces/deposits/IReceiptTokenManager.sol";

contract MockDepositManager is IDepositManager {
    error MockDepositManager_TransferFailed();

    Kernel public kernel;

    IERC20 public asset;
    IERC20[] internal _configuredAssets;
    AssetPeriod[] internal _assetPeriods;
    uint256[] internal _receiptTokenIds;
    uint256 internal _nextReceiptTokenId = 1;

    mapping(IERC20 asset => AssetConfiguration config) internal _assetConfigurations;
    mapping(bytes32 periodKey => uint256 indexPlusOne) internal _assetPeriodIndexPlusOne;
    mapping(bytes32 periodKey => uint256 receiptTokenId) internal _receiptTokenIdsByPeriod;

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
        if (!asset.transferFrom(params.depositor, address(this), params.amount)) {
            revert MockDepositManager_TransferFailed();
        }
        return (1, params.amount);
    }

    function withdraw(
        WithdrawParams calldata params
    ) external override returns (uint256 actualAmount) {
        if (!asset.transfer(params.recipient, params.amount)) {
            revert MockDepositManager_TransferFailed();
        }
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

    function addAsset(
        IERC20 asset_,
        IERC4626 vault_,
        uint256 depositCap_,
        uint256 minimumDeposit_
    ) external override {
        AssetConfiguration storage configuration = _assetConfigurations[asset_];
        if (!configuration.isConfigured) {
            _configuredAssets.push(asset_);
        }

        configuration.isConfigured = true;
        configuration.depositCap = depositCap_;
        configuration.minimumDeposit = minimumDeposit_;
        configuration.vault = address(vault_);
    }

    function setAssetDepositCap(IERC20 asset_, uint256 depositCap_) external override {
        _assetConfigurations[asset_].depositCap = depositCap_;
    }

    function setAssetMinimumDeposit(IERC20 asset_, uint256 minimumDeposit_) external override {
        _assetConfigurations[asset_].minimumDeposit = minimumDeposit_;
    }

    function addAssetPeriod(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    ) external override returns (uint256) {
        bytes32 periodKey = _assetPeriodKey(asset_, depositPeriod_, operator_);
        uint256 indexPlusOne = _assetPeriodIndexPlusOne[periodKey];
        if (indexPlusOne != 0) {
            return _receiptTokenIdsByPeriod[periodKey];
        }

        uint256 receiptTokenId = _nextReceiptTokenId++;
        _assetPeriodIndexPlusOne[periodKey] = _assetPeriods.length + 1;
        _receiptTokenIdsByPeriod[periodKey] = receiptTokenId;
        _receiptTokenIds.push(receiptTokenId);
        _assetPeriods.push(
            AssetPeriod({
                isEnabled: false,
                depositPeriod: depositPeriod_,
                asset: address(asset_),
                operator: operator_
            })
        );

        return receiptTokenId;
    }

    function disableAssetPeriod(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    ) external override {
        uint256 indexPlusOne = _assetPeriodIndexPlusOne[
            _assetPeriodKey(asset_, depositPeriod_, operator_)
        ];
        if (indexPlusOne != 0) {
            _assetPeriods[indexPlusOne - 1].isEnabled = false;
        }
    }

    function enableAssetPeriod(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    ) external override {
        uint256 indexPlusOne = _assetPeriodIndexPlusOne[
            _assetPeriodKey(asset_, depositPeriod_, operator_)
        ];
        if (indexPlusOne != 0) {
            _assetPeriods[indexPlusOne - 1].isEnabled = true;
        }
    }

    function getAssetPeriod(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    ) external view override returns (AssetPeriod memory) {
        uint256 indexPlusOne = _assetPeriodIndexPlusOne[
            _assetPeriodKey(asset_, depositPeriod_, operator_)
        ];
        if (indexPlusOne == 0) {
            return
                AssetPeriod({
                    isEnabled: false,
                    depositPeriod: 0,
                    asset: address(0),
                    operator: address(0)
                });
        }
        return _assetPeriods[indexPlusOne - 1];
    }

    function getAssetPeriod(uint256 tokenId_) external view override returns (AssetPeriod memory) {
        uint256 len = _receiptTokenIds.length;
        for (uint256 i; i < len; ++i) {
            if (_receiptTokenIds[i] == tokenId_) return _assetPeriods[i];
        }

        return
            AssetPeriod({
                isEnabled: false,
                depositPeriod: 0,
                asset: address(0),
                operator: address(0)
            });
    }

    function isAssetPeriod(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    ) external view override returns (AssetPeriodStatus memory) {
        uint256 indexPlusOne = _assetPeriodIndexPlusOne[
            _assetPeriodKey(asset_, depositPeriod_, operator_)
        ];
        return
            AssetPeriodStatus({
                isConfigured: indexPlusOne != 0,
                isEnabled: indexPlusOne != 0 && _assetPeriods[indexPlusOne - 1].isEnabled
            });
    }

    function getAssetPeriods() external view override returns (AssetPeriod[] memory) {
        return _assetPeriods;
    }

    // ========== RECEIPT TOKEN FUNCTIONS ========== //

    function getReceiptTokenId(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    ) external view override returns (uint256) {
        return _receiptTokenIdsByPeriod[_assetPeriodKey(asset_, depositPeriod_, operator_)];
    }

    function getReceiptToken(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    ) external view override returns (uint256, address) {
        return (
            _receiptTokenIdsByPeriod[_assetPeriodKey(asset_, depositPeriod_, operator_)],
            address(0)
        );
    }

    function getReceiptTokenManager() external pure override returns (IReceiptTokenManager) {
        return IReceiptTokenManager(address(0));
    }

    function getReceiptTokenIds() external view override returns (uint256[] memory) {
        return _receiptTokenIds;
    }

    // ========== IAssetManager FUNCTIONS ========== //

    function getOperatorAssets(IERC20, address) external pure override returns (uint256, uint256) {
        return (0, 0);
    }

    function getAssetConfiguration(
        IERC20 asset_
    ) external view override returns (AssetConfiguration memory) {
        return _assetConfigurations[asset_];
    }

    function getConfiguredAssets() external view override returns (IERC20[] memory) {
        return _configuredAssets;
    }

    function supportsInterface(bytes4 interfaceId_) external pure returns (bool) {
        return
            interfaceId_ == type(IERC165).interfaceId ||
            interfaceId_ == type(IDepositManager).interfaceId;
    }

    function _assetPeriodKey(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(asset_, depositPeriod_, operator_));
    }
}
