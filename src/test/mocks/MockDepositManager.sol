// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";

import {Kernel, Keycode, Permissions} from "src/Kernel.sol";
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
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
    bool public isEnabled = true;
    bool public depositReverts;
    bool public withdrawReverts;
    bool public depositActualAmountOverrideEnabled;
    uint256 public depositActualAmountOverride;
    bool public claimActualAmountOverrideEnabled;
    uint256 public claimActualAmountOverride;
    uint256 public claimableYield;
    uint256 public claimYieldCalls;
    address public claimYieldCallbackTarget;
    bytes public claimYieldCallbackData;
    bool public claimYieldCallbackSucceeded;

    mapping(IERC20 asset => AssetConfiguration config) internal _assetConfigurations;
    mapping(bytes32 operatorKey => uint256 shares) internal _operatorShares;
    mapping(bytes32 liabilitiesKey => uint256 liabilities) internal _operatorLiabilities;
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
        if (depositReverts) revert MockDepositManager_TransferFailed();
        _requireEnabledPeriod(params.asset, params.depositPeriod, msg.sender);

        AssetConfiguration memory configuration = _assetConfigurations[params.asset];
        if (params.amount < configuration.minimumDeposit) {
            revert IAssetManager.AssetManager_MinimumDepositNotMet(
                address(params.asset),
                params.amount,
                configuration.minimumDeposit
            );
        }

        (, uint256 assetAmountBefore) = this.getOperatorAssets(params.asset, msg.sender);
        if (assetAmountBefore + params.amount > configuration.depositCap) {
            revert IAssetManager.AssetManager_DepositCapExceeded(
                address(params.asset),
                assetAmountBefore,
                configuration.depositCap
            );
        }

        if (!params.asset.transferFrom(params.depositor, address(this), params.amount)) {
            revert MockDepositManager_TransferFailed();
        }

        uint256 shares;
        if (configuration.vault == address(0)) {
            shares = params.amount;
            actualAmount = params.amount;
        } else {
            params.asset.approve(configuration.vault, params.amount);
            shares = IERC4626(configuration.vault).deposit(params.amount, address(this));
            actualAmount = IERC4626(configuration.vault).previewRedeem(shares);
        }
        if (depositActualAmountOverrideEnabled) {
            actualAmount = depositActualAmountOverride;
        }

        _operatorShares[_getOperatorKey(params.asset, msg.sender)] += shares;
        _operatorLiabilities[_getOperatorKey(params.asset, msg.sender)] += actualAmount;
        receiptTokenId = _receiptTokenIdsByPeriod[
            _assetPeriodKey(params.asset, params.depositPeriod, msg.sender)
        ];
        return (receiptTokenId, actualAmount);
    }

    function withdraw(
        WithdrawParams calldata params
    ) external override returns (uint256 actualAmount) {
        if (withdrawReverts) revert MockDepositManager_TransferFailed();
        _requireConfiguredPeriod(params.asset, params.depositPeriod, msg.sender);

        AssetConfiguration memory configuration = _assetConfigurations[params.asset];
        bytes32 operatorKey = _getOperatorKey(params.asset, msg.sender);
        if (configuration.vault == address(0)) {
            _operatorShares[operatorKey] -= params.amount;
            actualAmount = params.amount;
            if (!params.asset.transfer(params.recipient, params.amount)) {
                revert MockDepositManager_TransferFailed();
            }
        } else {
            uint256 shares = IERC4626(configuration.vault).convertToShares(params.amount);
            if (shares == 0 || IERC4626(configuration.vault).previewRedeem(shares) == 0) {
                return 0;
            }
            _operatorShares[operatorKey] -= shares;
            actualAmount = IERC4626(configuration.vault).redeem(
                shares,
                params.recipient,
                address(this)
            );
        }
        _operatorLiabilities[operatorKey] -= actualAmount;
        return actualAmount;
    }

    function maxClaimYield(IERC20, address) external view override returns (uint256) {
        return claimableYield;
    }

    function claimYield(
        IERC20 asset_,
        address recipient_,
        uint256 amount_
    ) external override returns (uint256 actualAmount) {
        claimYieldCalls++;
        if (claimYieldCallbackTarget != address(0)) {
            (claimYieldCallbackSucceeded, ) = claimYieldCallbackTarget.call(claimYieldCallbackData);
        }

        actualAmount = amount_ > claimableYield ? claimableYield : amount_;
        if (claimActualAmountOverrideEnabled && actualAmount > claimActualAmountOverride) {
            actualAmount = claimActualAmountOverride;
        }
        claimableYield -= actualAmount;
        if (!asset_.transfer(recipient_, actualAmount)) {
            revert MockDepositManager_TransferFailed();
        }
    }

    function setClaimActualAmountOverride(bool enabled_, uint256 amount_) external {
        claimActualAmountOverrideEnabled = enabled_;
        claimActualAmountOverride = amount_;
    }

    function getOperatorLiabilities(
        IERC20 asset_,
        address operator_
    ) external view override returns (uint256) {
        return _operatorLiabilities[_getOperatorKey(asset_, operator_)];
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

    function removeAssetPeriod(IERC20 asset_, uint8 depositPeriod_, address operator_) external {
        bytes32 periodKey = _assetPeriodKey(asset_, depositPeriod_, operator_);
        delete _assetPeriodIndexPlusOne[periodKey];
        delete _receiptTokenIdsByPeriod[periodKey];
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

    function getOperatorAssets(
        IERC20 asset_,
        address operator_
    ) external view override returns (uint256 shares, uint256 sharesInAssets) {
        shares = _operatorShares[_getOperatorKey(asset_, operator_)];
        AssetConfiguration memory configuration = _assetConfigurations[asset_];
        sharesInAssets = configuration.vault == address(0)
            ? shares
            : IERC4626(configuration.vault).previewRedeem(shares);
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

    function setDepositReverts(bool depositReverts_) external {
        depositReverts = depositReverts_;
    }

    function setWithdrawReverts(bool withdrawReverts_) external {
        withdrawReverts = withdrawReverts_;
    }

    function setDepositActualAmountOverride(bool enabled_, uint256 amount_) external {
        depositActualAmountOverrideEnabled = enabled_;
        depositActualAmountOverride = amount_;
    }

    function setClaimableYield(uint256 claimableYield_) external {
        claimableYield = claimableYield_;
    }

    function setClaimYieldCallback(address target_, bytes calldata data_) external {
        claimYieldCallbackTarget = target_;
        claimYieldCallbackData = data_;
    }

    function _requireConfiguredPeriod(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    ) internal view {
        if (_assetPeriodIndexPlusOne[_assetPeriodKey(asset_, depositPeriod_, operator_)] == 0) {
            revert DepositManager_InvalidAssetPeriod(address(asset_), depositPeriod_, operator_);
        }
    }

    function _requireEnabledPeriod(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    ) internal view {
        uint256 indexPlusOne = _assetPeriodIndexPlusOne[
            _assetPeriodKey(asset_, depositPeriod_, operator_)
        ];
        if (indexPlusOne == 0) {
            revert DepositManager_InvalidAssetPeriod(address(asset_), depositPeriod_, operator_);
        }
        if (!_assetPeriods[indexPlusOne - 1].isEnabled) {
            revert DepositManager_AssetPeriodDisabled(address(asset_), depositPeriod_, operator_);
        }
    }

    function _assetPeriodKey(
        IERC20 asset_,
        uint8 depositPeriod_,
        address operator_
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(asset_, depositPeriod_, operator_));
    }

    function _getOperatorKey(IERC20 asset_, address operator_) internal pure returns (bytes32) {
        return keccak256(abi.encode(address(asset_), operator_));
    }
}
