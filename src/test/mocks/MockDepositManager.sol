// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

// missing-zero-check: Test fixtures accept zero addresses to model unset, cleared, and invalid states.
// empty-block: Unsupported interface hooks are intentional no-ops in this focused test mock.
// forge-lint: disable-start(missing-zero-check, empty-block)

import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";

import {Kernel, Keycode, Permissions} from "src/Kernel.sol";
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IAssetManagerV1_1} from "src/bases/interfaces/IAssetManagerV1_1.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {TransferHelper} from "src/libraries/TransferHelper.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositManagerV1_1} from "src/policies/interfaces/deposits/IDepositManagerV1_1.sol";
import {IReceiptTokenManager} from "src/policies/interfaces/deposits/IReceiptTokenManager.sol";

contract MockDepositManager is IDepositManagerV1_1, IAssetManagerV1_1, IERC165 {
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
    mapping(IERC20 asset => uint256 utilization) internal _assetDepositCapUtilization;
    mapping(bytes32 periodKey => uint256 indexPlusOne) internal _assetPeriodIndexPlusOne;
    mapping(bytes32 periodKey => uint256 receiptTokenId) internal _receiptTokenIdsByPeriod;
    mapping(IERC20 asset => IERC20 shareToken) internal _assetShareTokens;
    mapping(IERC20 asset => bool asyncRedeem) internal _assetAsyncRedeem;
    mapping(IERC20 asset => bool required) internal _assetShareWithdrawalRequired;

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

        // The depositor authorizes this operator-initiated pull through ERC-20 allowance.
        TransferHelper.safeTransferFromExact(
            ERC20(address(params.asset)),
            params.depositor,
            address(this),
            params.amount
        );

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

        uint256 utilization = _assetDepositCapUtilization[params.asset];
        uint256 depositCap = _assetConfigurations[params.asset].depositCap;
        if (
            actualAmount != 0 &&
            (utilization > depositCap || actualAmount > depositCap - utilization)
        ) {
            revert IAssetManager.AssetManager_DepositCapExceeded(
                address(params.asset),
                utilization,
                depositCap
            );
        }

        _operatorShares[_getOperatorKey(params.asset, msg.sender)] += shares;
        _operatorLiabilities[_getOperatorKey(params.asset, msg.sender)] += actualAmount;
        _assetDepositCapUtilization[params.asset] += actualAmount;
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
            if (isAssetShareWithdrawalRequired(params.asset)) {
                revert IAssetManagerV1_1.AssetManager_RequiresWithdrawAsShares(
                    address(params.asset),
                    configuration.vault
                );
            }
            uint256 shares = IERC4626(configuration.vault).convertToShares(params.amount);
            if (shares != 0 && IERC4626(configuration.vault).previewRedeem(shares) != 0) {
                _operatorShares[operatorKey] -= shares;
                actualAmount = IERC4626(configuration.vault).redeem(
                    shares,
                    params.recipient,
                    address(this)
                );
            }
        }
        _operatorLiabilities[operatorKey] -= params.amount;
        _assetDepositCapUtilization[params.asset] -= params.amount;
        return actualAmount;
    }

    function withdraw(
        WithdrawParams calldata params,
        bool withdrawAsShares_
    ) external override returns (IERC20 tokenOut, uint256 amountOut) {
        if (withdrawReverts) revert MockDepositManager_TransferFailed();
        _requireConfiguredPeriod(params.asset, params.depositPeriod, msg.sender);

        AssetConfiguration memory configuration = _assetConfigurations[params.asset];
        tokenOut = getAssetWithdrawalToken(params.asset, withdrawAsShares_);
        bytes32 operatorKey = _getOperatorKey(params.asset, msg.sender);
        if (withdrawAsShares_) {
            uint256 shares = IERC4626(configuration.vault).convertToShares(params.amount);
            amountOut = shares;
            if (shares != 0) {
                _operatorShares[operatorKey] -= shares;
                if (!tokenOut.transfer(params.recipient, shares)) {
                    revert MockDepositManager_TransferFailed();
                }
            }
        } else {
            if (configuration.vault == address(0)) {
                _operatorShares[operatorKey] -= params.amount;
                amountOut = params.amount;
                if (!params.asset.transfer(params.recipient, params.amount)) {
                    revert MockDepositManager_TransferFailed();
                }
            } else {
                if (isAssetShareWithdrawalRequired(params.asset)) {
                    revert IAssetManagerV1_1.AssetManager_RequiresWithdrawAsShares(
                        address(params.asset),
                        configuration.vault
                    );
                }
                uint256 shares = IERC4626(configuration.vault).convertToShares(params.amount);
                if (shares != 0 && IERC4626(configuration.vault).previewRedeem(shares) != 0) {
                    _operatorShares[operatorKey] -= shares;
                    amountOut = IERC4626(configuration.vault).redeem(
                        shares,
                        params.recipient,
                        address(this)
                    );
                }
            }
        }
        _operatorLiabilities[operatorKey] -= params.amount;
        _assetDepositCapUtilization[params.asset] -= params.amount;
    }

    function maxClaimYield(IERC20, address) external view override returns (uint256) {
        return claimableYield;
    }

    function claimYield(
        IERC20 asset_,
        address recipient_,
        uint256 amount_
    ) external override returns (uint256 actualAmount) {
        return _claimYield(asset_, recipient_, amount_);
    }

    function claimYield(
        IERC20 asset_,
        address recipient_,
        uint256 amount_,
        bool withdrawAsShares_
    ) external override returns (IERC20 tokenOut, uint256 amountOut) {
        AssetConfiguration memory configuration = _assetConfigurations[asset_];
        tokenOut = getAssetWithdrawalToken(asset_, withdrawAsShares_);
        if (withdrawAsShares_) {
            claimYieldCalls++;
            if (claimYieldCallbackTarget != address(0)) {
                // The fixture records callback failure without reverting the claim.
                // forge-lint: disable-start(low-level-calls)
                (claimYieldCallbackSucceeded, ) = claimYieldCallbackTarget.call(
                    claimYieldCallbackData
                );
                // forge-lint: disable-end(low-level-calls)
            }
            uint256 actualAssetAmount = amount_ > claimableYield ? claimableYield : amount_;
            if (claimActualAmountOverrideEnabled && actualAssetAmount > claimActualAmountOverride) {
                actualAssetAmount = claimActualAmountOverride;
            }
            amountOut = IERC4626(configuration.vault).convertToShares(actualAssetAmount);
            if (amountOut == 0) return (tokenOut, 0);
            // Accounting intentionally follows external calls so tests can exercise caller guards.
            // forge-lint: disable-next-line(reentrancy-no-eth)
            if (amountOut != 0 && !tokenOut.transfer(recipient_, amountOut)) {
                revert MockDepositManager_TransferFailed();
            }
            claimableYield -= actualAssetAmount;
            return (tokenOut, amountOut);
        }
        amountOut = _claimYield(asset_, recipient_, amount_);
    }

    function _claimYield(
        IERC20 asset_,
        address recipient_,
        uint256 amount_
    ) internal returns (uint256 actualAmount) {
        claimYieldCalls++;
        if (claimYieldCallbackTarget != address(0)) {
            // The fixture records callback failure without reverting the claim.
            // forge-lint: disable-next-line(low-level-calls)
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

    function getAssetDepositCapStatus(
        IERC20 asset_
    ) external view override returns (AssetDepositCapStatus memory status) {
        status.depositCap = _assetConfigurations[asset_].depositCap;
        status.utilization = _assetDepositCapUtilization[asset_];
        return status;
    }

    // ========== BORROWING FUNCTIONS ========== //

    function borrowingWithdraw(
        BorrowingWithdrawParams calldata
    ) external pure override returns (uint256) {
        return 0;
    }

    function borrowingWithdraw(
        BorrowingWithdrawParams calldata params_,
        bool withdrawAsShares_
    ) external view override returns (IERC20 tokenOut, uint256 amountOut) {
        AssetConfiguration memory configuration = _assetConfigurations[params_.asset];
        tokenOut = getAssetWithdrawalToken(params_.asset, withdrawAsShares_);
        if (withdrawAsShares_) {
            return (tokenOut, IERC4626(configuration.vault).convertToShares(params_.amount));
        }
        if (isAssetShareWithdrawalRequired(params_.asset)) {
            revert IAssetManagerV1_1.AssetManager_RequiresWithdrawAsShares(
                address(params_.asset),
                configuration.vault
            );
        }
        return (tokenOut, params_.amount);
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
        _configureAsset(asset_, vault_, depositCap_, minimumDeposit_);
    }

    function addAsset(
        IERC20 asset_,
        IERC4626 vault_,
        uint256 depositCap_,
        uint256 minimumDeposit_,
        bool requiresShareWithdrawal_
    ) external override {
        _configureAsset(asset_, vault_, depositCap_, minimumDeposit_);
        _assetShareWithdrawalRequired[asset_] = requiresShareWithdrawal_;
    }

    function _configureAsset(
        IERC20 asset_,
        IERC4626 vault_,
        uint256 depositCap_,
        uint256 minimumDeposit_
    ) internal {
        AssetConfiguration storage configuration = _assetConfigurations[asset_];
        if (!configuration.isConfigured) {
            _configuredAssets.push(asset_);
        }

        configuration.isConfigured = true;
        configuration.depositCap = depositCap_;
        configuration.minimumDeposit = minimumDeposit_;
        configuration.vault = address(vault_);
        _assetShareTokens[asset_] = address(vault_) == address(0)
            ? asset_
            : IERC20(address(vault_));
    }

    function setAssetShareWithdrawalRequired(IERC20 asset_, bool required_) external override {
        validateAssetShareWithdrawalRequired(asset_, required_);
        _assetShareWithdrawalRequired[asset_] = required_;
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
        sharesInAssets = configuration.vault == address(0) ? shares : _assetAsyncRedeem[asset_]
            ? IERC4626(configuration.vault).convertToAssets(shares)
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

    function getAssetWithdrawalToken(
        IERC20 asset_,
        bool withdrawAsShares_
    ) public view override returns (IERC20 tokenOut) {
        AssetConfiguration memory configuration = _assetConfigurations[asset_];
        if (!configuration.isConfigured) revert AssetManager_NotConfigured();
        if (!withdrawAsShares_) return asset_;
        if (configuration.vault == address(0)) {
            revert IAssetManagerV1_1.AssetManager_VaultRequired(address(asset_));
        }
        return _assetShareTokens[asset_];
    }

    function isAssetShareWithdrawalRequired(
        IERC20 asset_
    ) public view override returns (bool required) {
        if (!_assetConfigurations[asset_].isConfigured) revert AssetManager_NotConfigured();
        return _assetShareWithdrawalRequired[asset_] || _assetAsyncRedeem[asset_];
    }

    function validateAssetShareWithdrawalRequired(
        IERC20 asset_,
        bool required_
    ) public view override {
        AssetConfiguration memory configuration = _assetConfigurations[asset_];
        if (!configuration.isConfigured) revert AssetManager_NotConfigured();
        if (required_ && configuration.vault == address(0)) {
            revert IAssetManagerV1_1.AssetManager_VaultRequired(address(asset_));
        }
        if (!required_ && _assetAsyncRedeem[asset_]) {
            revert IAssetManagerV1_1.AssetManager_RequiresWithdrawAsShares(
                address(asset_),
                configuration.vault
            );
        }
    }

    function validateAssetWithdrawAsShares(
        IERC20 asset_,
        bool withdrawAsShares_
    ) external view override {
        getAssetWithdrawalToken(asset_, withdrawAsShares_);
        AssetConfiguration memory configuration = _assetConfigurations[asset_];
        if (!withdrawAsShares_ && isAssetShareWithdrawalRequired(asset_)) {
            revert IAssetManagerV1_1.AssetManager_RequiresWithdrawAsShares(
                address(asset_),
                configuration.vault
            );
        }
    }

    function previewDeposit(
        IERC20 asset_,
        uint256 assetAmount_
    ) external view override returns (uint256 estimatedCreditedAssets, uint256 shares) {
        AssetConfiguration memory configuration = _assetConfigurations[asset_];
        if (!configuration.isConfigured) revert IAssetManager.AssetManager_NotConfigured();
        if (configuration.vault == address(0)) {
            estimatedCreditedAssets = assetAmount_;
            shares = assetAmount_;
        } else {
            shares = IERC4626(configuration.vault).previewDeposit(assetAmount_);
            estimatedCreditedAssets = _assetAsyncRedeem[asset_]
                ? IERC4626(configuration.vault).convertToAssets(shares)
                : IERC4626(configuration.vault).previewRedeem(shares);
        }

        uint256 utilization = _assetDepositCapUtilization[asset_];
        uint256 depositCap = _assetConfigurations[asset_].depositCap;
        if (
            estimatedCreditedAssets != 0 &&
            (utilization > depositCap || estimatedCreditedAssets > depositCap - utilization)
        ) {
            revert IAssetManager.AssetManager_DepositCapExceeded(
                address(asset_),
                utilization,
                depositCap
            );
        }
    }

    function previewWithdraw(
        IERC20 asset_,
        uint256 assetAmount_,
        bool withdrawAsShares_
    ) external view override returns (IERC20 tokenOut, uint256 amountOut) {
        AssetConfiguration memory configuration = _assetConfigurations[asset_];
        if (!withdrawAsShares_ && isAssetShareWithdrawalRequired(asset_)) {
            revert IAssetManagerV1_1.AssetManager_RequiresWithdrawAsShares(
                address(asset_),
                configuration.vault
            );
        }
        tokenOut = getAssetWithdrawalToken(asset_, withdrawAsShares_);
        if (configuration.vault == address(0)) {
            return (tokenOut, assetAmount_);
        }
        uint256 shares = IERC4626(configuration.vault).convertToShares(assetAmount_);
        if (withdrawAsShares_) return (tokenOut, shares);
        amountOut = _assetAsyncRedeem[asset_]
            ? IERC4626(configuration.vault).convertToAssets(shares)
            : IERC4626(configuration.vault).previewRedeem(shares);
    }

    function supportsInterface(bytes4 interfaceId_) external pure override returns (bool) {
        return
            interfaceId_ == type(IERC165).interfaceId ||
            interfaceId_ == type(IAssetManager).interfaceId ||
            interfaceId_ == type(IAssetManagerV1_1).interfaceId ||
            interfaceId_ == type(IDepositManager).interfaceId ||
            interfaceId_ == type(IDepositManagerV1_1).interfaceId;
    }

    function setDepositReverts(bool depositReverts_) external {
        depositReverts = depositReverts_;
    }

    function setWithdrawReverts(bool withdrawReverts_) external {
        withdrawReverts = withdrawReverts_;
    }

    function setAssetShareToken(IERC20 asset_, IERC20 shareToken_) external {
        _assetShareTokens[asset_] = shareToken_;
    }

    function setAssetAsyncRedeem(IERC20 asset_, bool asyncRedeem_) external {
        _assetAsyncRedeem[asset_] = asyncRedeem_;
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

// forge-lint: disable-end(missing-zero-check, empty-block)
