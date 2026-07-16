// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IERC165} from "@openzeppelin-5.3.0/interfaces/IERC165.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IEnabler} from "src/periphery/interfaces/IEnabler.sol";
import {IBurnerLoans} from "src/policies/interfaces/IBurnerLoans.sol";
import {IOlympusBackingOracle} from "src/policies/interfaces/IOlympusBackingOracle.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IReceiptTokenManager} from "src/policies/interfaces/deposits/IReceiptTokenManager.sol";

// Libraries
import {ERC20} from "@solmate-6.2.0/tokens/ERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin-5.3.0/utils/ReentrancyGuardTransient.sol";
import {EnumerableSet} from "@openzeppelin-5.3.0/utils/structs/EnumerableSet.sol";
import {FullMath} from "src/libraries/FullMath.sol";
import {TransferHelper} from "src/libraries/TransferHelper.sol";
import {BurnerLoansConstants} from "src/policies/libraries/BurnerLoansConstants.sol";

// Contracts
import {Kernel, Keycode, Module, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {BurnerLoansConfig} from "src/policies/abstracts/BurnerLoansConfig.sol";

/// @title Burner Loans
/// @notice Fixed-term, zero-interest OHM shorting facility skeleton.
/// @dev U0-U3A implement shared enablement, policy wiring, scale-aware math, and configuration.
contract BurnerLoans is BurnerLoansConfig, ReentrancyGuardTransient {
    using EnumerableSet for EnumerableSet.AddressSet;
    using TransferHelper for ERC20;

    // ========== INTERNAL STRUCTS ========== //

    struct RequiredCollateralUsdInputs {
        uint256 debtValueUsd;
        uint256 debtOhm;
        uint256 backingPerOhmUsd;
        uint256 minCollateralRatioBps;
        uint256 backingMultiplierBps;
    }

    struct UtilizationInputs {
        uint256 assetDebtOhm;
        uint256 assetDebtCapOhm;
    }

    struct BorrowQuote {
        uint256 feeCollateral;
        uint256 resultingDebtOhm;
        uint256 resultingHealthFactor;
        uint48 maturity;
    }

    struct BorrowPricing {
        uint256 ohmUsdPrice;
        uint256 backingPerOhmUsd;
        uint256 collateralUsdPrice;
        uint256 riskAdjustedCollateralUsd;
    }

    struct KeeperRewardInputs {
        bool isProtocolSeizureCaller;
        uint256 seizedCollateralAmount;
        uint256 seizedUnrepaidDebtOhm;
        uint256 backingPerOhmUsd;
        uint256 backingMultiplierBps;
        uint256 collateralUsdPrice;
        uint8 collateralDecimals;
        uint256 rewardBps;
        uint256 maxKeeperRewardAsset;
    }

    // ========== CONSTRUCTOR ========== //

    constructor(
        Kernel kernel_,
        IERC20 ohm_,
        IDepositManager depositManager_
    ) BurnerLoansConfig(kernel_, ohm_, depositManager_) {}

    // ========== POLICY SETUP ========== //

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](4);
        dependencies[0] = toKeycode("MINTR");
        dependencies[1] = toKeycode("PRICE");
        dependencies[2] = toKeycode("ROLES");
        dependencies[3] = toKeycode("TRSRY");

        _MINTR = MINTRv1(getModuleAddress(dependencies[0]));
        address priceAddress = getModuleAddress(dependencies[1]);
        ROLES = ROLESv1(getModuleAddress(dependencies[2]));
        _TRSRY = TRSRYv1(getModuleAddress(dependencies[3]));

        if (!IERC165(priceAddress).supportsInterface(type(IPRICEv2).interfaceId)) {
            revert BurnerLoans_InvalidModuleVersion();
        }
        _PRICE = IPRICEv2(priceAddress);

        (uint8 mintrMajor, ) = _MINTR.VERSION();
        (uint8 priceMajor, uint8 priceMinor) = Module(priceAddress).VERSION();
        (uint8 rolesMajor, ) = ROLES.VERSION();
        (uint8 trsryMajor, ) = _TRSRY.VERSION();

        bool priceVersionSupported = priceMajor == 2 || (priceMajor == 1 && priceMinor >= 2);
        if (mintrMajor != 1 || !priceVersionSupported || rolesMajor != 1 || trsryMajor != 1) {
            revert BurnerLoans_InvalidModuleVersion();
        }

        _OHM.approve(address(_MINTR), type(uint256).max);
    }

    /// @inheritdoc Policy
    function requestPermissions() external view override returns (Permissions[] memory requests) {
        requests = new Permissions[](2);
        requests[0] = Permissions({
            keycode: _MINTR.KEYCODE(),
            funcSelector: _MINTR.mintOhm.selector
        });
        requests[1] = Permissions({
            keycode: _MINTR.KEYCODE(),
            funcSelector: _MINTR.burnOhm.selector
        });
    }

    // ========== VIEW FUNCTIONS ========== //

    /// @inheritdoc IBurnerLoans
    function ohm() external view returns (address) {
        return address(_OHM);
    }

    /// @inheritdoc IBurnerLoans
    function depositManager() external view returns (address) {
        return address(_DEPOSIT_MANAGER);
    }

    /// @inheritdoc IBurnerLoans
    function getAssetConfig(address asset_) external view returns (AssetConfig memory) {
        return _assetConfigs[asset_];
    }

    /// @inheritdoc IBurnerLoans
    function getAssetFeeConfig(address asset_) external view returns (AssetFeeConfig memory) {
        return _assetFeeConfigs[asset_];
    }

    /// @inheritdoc IBurnerLoans
    function getPosition(
        address asset_,
        address borrower_
    ) external view returns (Position memory) {
        return _positions[borrower_][asset_];
    }

    /// @inheritdoc IBurnerLoans
    function isSeizable(address, address) external pure returns (bool) {
        revert BurnerLoans_NotImplemented();
    }

    /// @inheritdoc IBurnerLoans
    function getSeizableBorrowers(
        address,
        uint256,
        uint256,
        uint256
    ) external pure returns (address[] memory, uint256, uint256) {
        revert BurnerLoans_NotImplemented();
    }

    /// @inheritdoc IBurnerLoans
    function getActiveBorrowers(address asset_) external view returns (address[] memory borrowers) {
        return _activeBorrowersByAsset[asset_].values();
    }

    /// @inheritdoc IBurnerLoans
    function healthFactor(address, address) external pure returns (uint256) {
        revert BurnerLoans_NotImplemented();
    }

    // ========== PREVIEW FUNCTIONS ========== //

    /// @inheritdoc IBurnerLoans
    /// @notice Returns a current-state quote for a collateral deposit.
    /// @dev For vault custody, the returned credit and total can differ from the actual values
    ///      returned by `depositCollateral`; the write result is authoritative.
    /// @dev Reverts if:
    ///      - Burner Loans, the collateral asset, or DepositManager is disabled.
    ///      - The asset-period custody path is unsupported.
    ///      - `amount_` is zero, below the DepositManager minimum, or exceeds its operator cap.
    ///      - Vault rounding produces zero credit.
    function previewDepositCollateral(
        address asset_,
        uint256 amount_,
        address onBehalfOf_
    ) external view returns (uint256, uint256) {
        _requireEnabled();
        _requireAssetEnabled(asset_);
        if (amount_ == 0) revert BurnerLoans_ZeroAmount();

        IDepositManager.AssetConfiguration
            memory assetConfiguration = _validateDepositCustodySupport(asset_);
        _validateDepositAmount(asset_, assetConfiguration, amount_);

        uint256 depositedCollateral = _previewDepositAmount(assetConfiguration.vault, amount_);
        if (depositedCollateral == 0) revert BurnerLoans_ZeroCollateralCredit();
        return (
            depositedCollateral,
            _positions[onBehalfOf_][asset_].depositedCollateral + depositedCollateral
        );
    }

    /// @inheritdoc IBurnerLoans
    /// @dev Asset disable does not block this exit preview. Reverts if:
    ///      - Burner Loans or DepositManager is disabled.
    ///      - The asset-period custody path is unsupported.
    ///      - `amount_` is zero or exceeds credited collateral.
    ///      - PRICE is unavailable or stale with debt.
    ///      `executable` reports only local amount and health feasibility; external custody execution
    ///      can still revert.
    function previewWithdrawCollateral(
        address asset_,
        uint256 amount_,
        address onBehalfOf_
    ) external view returns (WithdrawPreview memory) {
        _requireEnabled();
        AssetConfig storage config = _requireAssetConfigured(asset_);
        if (amount_ == 0) revert BurnerLoans_ZeroAmount();

        IDepositManager.AssetConfiguration
            memory assetConfiguration = _validateWithdrawCustodySupport(asset_);
        Position storage position = _positions[onBehalfOf_][asset_];
        if (amount_ > position.depositedCollateral) {
            revert BurnerLoans_InsufficientCollateral(amount_, position.depositedCollateral);
        }

        uint256 remainingCollateral = position.depositedCollateral - amount_;
        uint256 resultingHealthFactor = _positionHealthFactor(
            asset_,
            config,
            remainingCollateral,
            position.debtOhm
        );

        uint256 returnAmount = _previewWithdrawAmount(assetConfiguration.vault, amount_);
        return
            WithdrawPreview({
                returnToken: asset_,
                returnAmount: returnAmount,
                remainingDepositedCollateral: remainingCollateral,
                resultingHealthFactor: resultingHealthFactor,
                executable: returnAmount != 0 &&
                    (position.debtOhm == 0 || resultingHealthFactor >= _WAD)
            });
    }

    /// @inheritdoc IBurnerLoans
    /// @notice Quotes a borrow using fresh prices and pre-borrow asset utilization.
    /// @dev Reverts if:
    ///      - Burner Loans or the collateral asset is disabled or unconfigured.
    ///      - `ohmAmount_` is zero or the position has no credited collateral.
    ///      - OHM or collateral PRICE is unsupported, zero, or stale.
    ///      - The resulting global or asset active debt exceeds its cap.
    ///      - The position is seized, matured, currently unhealthy, or unhealthy after borrowing.
    ///      `executable` covers deterministic local protocol eligibility only. This signature has no
    ///      caller, recipient, or `maxFee`, so it cannot promise authorization, fee approval or balance,
    ///      recipient validity, or max-fee acceptance.
    function previewBorrow(
        address asset_,
        uint256 ohmAmount_,
        address onBehalfOf_
    ) external view returns (BorrowPreview memory preview) {
        _requireEnabled();
        AssetConfig storage config = _requireAssetEnabled(asset_);
        if (ohmAmount_ == 0) revert BurnerLoans_ZeroAmount();

        BorrowQuote memory quote = _quoteBorrow(asset_, ohmAmount_, onBehalfOf_, config);
        return
            BorrowPreview({
                fee: quote.feeCollateral,
                resultingDebtOhm: quote.resultingDebtOhm,
                resultingHealthFactor: quote.resultingHealthFactor,
                maturity: quote.maturity,
                executable: true
            });
    }

    /// @inheritdoc IBurnerLoans
    function previewRepay(address, uint256, address) external pure returns (uint256, uint256) {
        revert BurnerLoans_NotImplemented();
    }

    /// @inheritdoc IBurnerLoans
    function previewExtend(address, address, uint256) external pure returns (ExtendPreview memory) {
        revert BurnerLoans_NotImplemented();
    }

    /// @inheritdoc IBurnerLoans
    function previewSeize(address, address[] calldata) external pure returns (SeizePreview memory) {
        revert BurnerLoans_NotImplemented();
    }

    /// @inheritdoc IBurnerLoans
    function previewHarvestYield(address) external pure returns (HarvestPreview memory) {
        revert BurnerLoans_NotImplemented();
    }

    // ========== USER FUNCTIONS ========== //

    /// @inheritdoc IBurnerLoans
    /// @dev Reverts if:
    ///      - Burner Loans, the collateral asset, or DepositManager is disabled.
    ///      - The caller is not the owner or an authorized operator.
    ///      - Custody is unsupported.
    ///      - `amount_` is zero, below the DepositManager minimum, or exceeds its operator cap.
    ///      - Token transfer fails, custody leaves residual collateral, or vault rounding produces
    ///        zero credit.
    function depositCollateral(
        address asset_,
        uint256 amount_,
        address onBehalfOf_
    ) external returns (uint256, uint256) {
        _requireEnabled();
        _requireAssetEnabled(asset_);
        if (amount_ == 0) revert BurnerLoans_ZeroAmount();
        _requireSenderAuthorized(msg.sender, onBehalfOf_);
        IDepositManager.AssetConfiguration
            memory assetConfiguration = _validateDepositCustodySupport(asset_);
        _validateDepositAmount(asset_, assetConfiguration, amount_);

        uint256 depositedCollateral = _depositCollateralToCustody(asset_, amount_);
        if (depositedCollateral == 0) revert BurnerLoans_ZeroCollateralCredit();
        Position storage position = _positions[onBehalfOf_][asset_];
        position.depositedCollateral += depositedCollateral;

        emit CollateralDeposited(msg.sender, asset_, onBehalfOf_, amount_, depositedCollateral);

        return (depositedCollateral, position.depositedCollateral);
    }

    /// @inheritdoc IBurnerLoans
    /// @dev Asset disable does not block this exit. Reverts if:
    ///      - Burner Loans or DepositManager is disabled.
    ///      - The caller is not the owner or an authorized operator.
    ///      - Custody is unsupported.
    ///      - `amount_` is zero, exceeds credited collateral, or rounds to zero output.
    ///      - `recipient_` is zero, PRICE is unavailable or stale with debt, or health falls below
    ///        1e18 after the withdrawal.
    function withdrawCollateral(
        address asset_,
        uint256 amount_,
        address onBehalfOf_,
        address recipient_
    )
        external
        returns (
            address tokenOut,
            uint256 amountOut,
            uint256 remainingDepositedCollateral,
            uint256 healthFactor_
        )
    {
        _requireEnabled();
        _requireAssetConfigured(asset_);
        if (amount_ == 0) revert BurnerLoans_ZeroAmount();
        _requireSenderAuthorized(msg.sender, onBehalfOf_);
        if (recipient_ == address(0)) revert BurnerLoans_ZeroAddress();
        IDepositManager.AssetConfiguration
            memory assetConfiguration = _validateWithdrawCustodySupport(asset_);
        if (_previewWithdrawAmount(assetConfiguration.vault, amount_) == 0)
            revert BurnerLoans_ZeroCollateralWithdrawal();

        (remainingDepositedCollateral, healthFactor_) = _debitCollateral(
            asset_,
            amount_,
            onBehalfOf_
        );
        amountOut = _withdrawCollateralFromCustody(asset_, amount_, recipient_);
        if (amountOut == 0) revert BurnerLoans_ZeroCollateralWithdrawal();

        emit CollateralWithdrawn(msg.sender, asset_, onBehalfOf_, recipient_, amount_);

        tokenOut = asset_;
    }

    /// @inheritdoc IBurnerLoans
    /// @dev Uses pre-borrow asset utilization for the fee curve and charges the fee on the
    ///      incremental required collateral. Reverts if:
    ///      - Burner Loans or the collateral asset is disabled or unconfigured.
    ///      - The caller is not the owner or an authorized operator.
    ///      - `ohmAmount_` or `recipient_` is zero, or the position has no credited collateral.
    ///      - OHM or collateral PRICE is unsupported, zero, or stale.
    ///      - The resulting global or asset active debt exceeds its cap.
    ///      - The position is seized, matured, currently unhealthy, or unhealthy after borrowing.
    ///      - The collateral fee exceeds `maxFee_` or cannot be transferred from the caller.
    ///      - MINTR cannot mint exactly `ohmAmount_` to `recipient_`.
    function borrow(
        address asset_,
        uint256 ohmAmount_,
        address onBehalfOf_,
        address recipient_,
        uint256 maxFee_
    ) external nonReentrant returns (uint256, uint256, uint256, uint48, uint256) {
        BorrowQuote memory quote = _executeBorrow(
            asset_,
            ohmAmount_,
            onBehalfOf_,
            recipient_,
            maxFee_
        );
        return (
            ohmAmount_,
            quote.feeCollateral,
            quote.resultingDebtOhm,
            quote.maturity,
            quote.resultingHealthFactor
        );
    }

    /// @inheritdoc IBurnerLoans
    function repay(address, uint256, address) external pure returns (uint256, uint256) {
        revert BurnerLoans_NotImplemented();
    }

    /// @inheritdoc IBurnerLoans
    function extend(
        address asset_,
        address onBehalfOf_,
        uint256,
        uint256
    ) external view returns (uint48, uint256, uint256) {
        _requireEnabled();
        _requireAssetEnabled(asset_);
        _requireSenderAuthorized(msg.sender, onBehalfOf_);
        revert BurnerLoans_NotImplemented();
    }

    /// @inheritdoc IBurnerLoans
    function seize(
        address,
        address[] calldata
    ) external pure returns (uint256, uint256, uint256, uint256) {
        revert BurnerLoans_NotImplemented();
    }

    /// @inheritdoc IBurnerLoans
    function harvestYield(address) external pure returns (uint256) {
        revert BurnerLoans_NotImplemented();
    }

    // ========== INTERNAL BORROW HELPERS ========== //

    /// @notice Executes a validated borrow with effects before fee collection and OHM minting.
    function _executeBorrow(
        address asset_,
        uint256 ohmAmount_,
        address onBehalfOf_,
        address recipient_,
        uint256 maxFee_
    ) internal returns (BorrowQuote memory quote) {
        _requireEnabled();
        AssetConfig storage config = _requireAssetEnabled(asset_);
        if (ohmAmount_ == 0) revert BurnerLoans_ZeroAmount();
        _requireSenderAuthorized(msg.sender, onBehalfOf_);
        if (recipient_ == address(0)) revert BurnerLoans_ZeroAddress();

        quote = _quoteBorrow(asset_, ohmAmount_, onBehalfOf_, config);
        if (quote.feeCollateral > maxFee_) {
            revert BurnerLoans_FeeExceedsMax(quote.feeCollateral, maxFee_);
        }

        Position storage position = _positions[onBehalfOf_][asset_];
        bool startsDebtEpisode = position.debtOhm == 0;
        position.debtOhm = quote.resultingDebtOhm;
        position.status = PositionStatus.Active;
        position.lastBorrowBlock = uint48(block.number);
        if (startsDebtEpisode) {
            position.maturity = quote.maturity;
            _addActiveBorrower(asset_, onBehalfOf_);
        }
        totalActiveDebtOhm += ohmAmount_;
        assetActiveDebtOhm[asset_] += ohmAmount_;

        if (quote.feeCollateral != 0) {
            ERC20(asset_).safeTransferFrom(msg.sender, address(_TRSRY), quote.feeCollateral);
        }
        _MINTR.mintOhm(recipient_, ohmAmount_);

        emit Borrowed(msg.sender, asset_, onBehalfOf_, recipient_, ohmAmount_, quote.feeCollateral);
    }

    /// @notice Quotes and validates a borrow using current state and fresh prices.
    /// @dev Fee utilization is the asset utilization before adding `ohmAmount_`. Debt and
    ///      collateral amounts use their token-native decimals; prices use PRICE decimals.
    function _quoteBorrow(
        address asset_,
        uint256 ohmAmount_,
        address onBehalfOf_,
        AssetConfig memory config_
    ) internal view returns (BorrowQuote memory quote) {
        Position storage position = _positions[onBehalfOf_][asset_];
        if (position.status == PositionStatus.Seized) revert BurnerLoans_PositionSeized();
        if (position.depositedCollateral == 0) revert BurnerLoans_NoCollateral();
        if (position.debtOhm != 0 && block.timestamp >= position.maturity) {
            revert BurnerLoans_PositionMatured(position.maturity);
        }

        uint256 globalDebtRoom = totalActiveDebtOhm <= globalDebtCapOhm
            ? globalDebtCapOhm - totalActiveDebtOhm
            : 0;
        if (ohmAmount_ > globalDebtRoom) {
            revert BurnerLoans_GlobalDebtCapExceeded(ohmAmount_, globalDebtRoom);
        }
        uint256 assetDebt = assetActiveDebtOhm[asset_];
        uint256 assetDebtRoom = assetDebt <= config_.debtCap ? config_.debtCap - assetDebt : 0;
        if (ohmAmount_ > assetDebtRoom) {
            revert BurnerLoans_AssetDebtCapExceeded(asset_, ohmAmount_, assetDebtRoom);
        }
        quote.resultingDebtOhm = position.debtOhm + ohmAmount_;

        // Each distinct price input is read once and reused for current health, resulting health,
        // and fee calculations so the quote uses one internally consistent price snapshot.
        BorrowPricing memory pricing;
        uint48 observationFrequency = _PRICE.observationFrequency();
        (pricing.ohmUsdPrice, ) = _getFreshPrice(address(_OHM), observationFrequency);
        pricing.backingPerOhmUsd = _getBackingPerOhmUsd();
        (pricing.collateralUsdPrice, ) = _getFreshPrice(asset_, observationFrequency);
        pricing.riskAdjustedCollateralUsd = _riskAdjustedCollateralUsd(
            _collateralValueUsd(
                position.depositedCollateral,
                pricing.collateralUsdPrice,
                config_.collateralDecimals
            ),
            config_.collateralFactorBps
        );

        _validateCurrentBorrowHealth(position.debtOhm, pricing, config_);
        quote.resultingHealthFactor = _validateResultingBorrowHealth(
            quote.resultingDebtOhm,
            pricing,
            config_
        );
        quote.feeCollateral = _quoteBorrowFee(asset_, ohmAmount_, pricing, config_);
        quote.maturity = position.debtOhm == 0
            ? uint48(block.timestamp + config_.termLength)
            : position.maturity;
    }

    /// @notice Validates that an existing debt-bearing position is currently healthy.
    function _validateCurrentBorrowHealth(
        uint256 currentDebtOhm_,
        BorrowPricing memory pricing_,
        AssetConfig memory config_
    ) internal view {
        if (currentDebtOhm_ == 0) return;

        uint256 currentHealthFactor = _borrowHealthFactor(currentDebtOhm_, pricing_, config_);
        if (currentHealthFactor < _WAD) {
            revert BurnerLoans_UnhealthyPosition(currentHealthFactor);
        }
    }

    /// @notice Validates and returns health after applying a proposed borrow.
    function _validateResultingBorrowHealth(
        uint256 resultingDebtOhm_,
        BorrowPricing memory pricing_,
        AssetConfig memory config_
    ) internal view returns (uint256 resultingHealthFactor) {
        resultingHealthFactor = _borrowHealthFactor(resultingDebtOhm_, pricing_, config_);
        if (resultingHealthFactor < _WAD) {
            revert BurnerLoans_UnhealthyBorrow(resultingHealthFactor);
        }
    }

    /// @notice Calculates borrower health for one debt amount from an already-read price snapshot.
    function _borrowHealthFactor(
        uint256 debtOhm_,
        BorrowPricing memory pricing_,
        AssetConfig memory config_
    ) internal view returns (uint256) {
        return
            _healthFactor(
                pricing_.riskAdjustedCollateralUsd,
                _requiredCollateralUsd(
                    _requiredCollateralInputs(
                        debtOhm_,
                        pricing_.ohmUsdPrice,
                        pricing_.backingPerOhmUsd,
                        config_
                    )
                )
            );
    }

    /// @notice Quotes the collateral fee using incremental debt and pre-borrow asset utilization.
    function _quoteBorrowFee(
        address asset_,
        uint256 ohmAmount_,
        BorrowPricing memory pricing_,
        AssetConfig memory config_
    ) internal view returns (uint256) {
        uint256 incrementalRequiredCollateral = _requiredCollateralAsset(
            _requiredCollateralUsd(
                _requiredCollateralInputs(
                    ohmAmount_,
                    pricing_.ohmUsdPrice,
                    pricing_.backingPerOhmUsd,
                    config_
                )
            ),
            pricing_.collateralUsdPrice,
            config_.collateralDecimals
        );
        uint256 feeUtilizationWad = _effectiveUtilizationWad(
            UtilizationInputs({
                assetDebtOhm: assetActiveDebtOhm[asset_],
                assetDebtCapOhm: config_.debtCap
            })
        );
        return
            _borrowFee(
                incrementalRequiredCollateral,
                _feeRateWad(feeUtilizationWad, _assetFeeConfigs[asset_])
            );
    }

    /// @notice Builds scale-explicit collateral requirement inputs for one debt amount.
    function _requiredCollateralInputs(
        uint256 debtOhm_,
        uint256 ohmUsdPrice_,
        uint256 backingPerOhmUsd_,
        AssetConfig memory config_
    ) internal view returns (RequiredCollateralUsdInputs memory) {
        return
            RequiredCollateralUsdInputs({
                debtValueUsd: _debtValueUsd(debtOhm_, ohmUsdPrice_, _OHM_DECIMALS),
                debtOhm: debtOhm_,
                backingPerOhmUsd: backingPerOhmUsd_,
                minCollateralRatioBps: config_.minCollateralRatioBps,
                backingMultiplierBps: config_.backingMultiplierBps
            });
    }

    /// @notice Adds an owner to the asset-scoped active borrower index once.
    function _addActiveBorrower(address asset_, address borrower_) internal {
        _activeBorrowersByAsset[asset_].add(borrower_);
    }

    // ========== INTERNAL CUSTODY HELPERS ========== //

    /// @notice Validates DepositManager asset-period support for Burner Loans custody.
    function _validateDepositCustodySupport(
        address asset_
    ) internal view returns (IDepositManager.AssetConfiguration memory assetConfiguration) {
        _requireDepositManagerEnabled();

        assetConfiguration = _DEPOSIT_MANAGER.getAssetConfiguration(IERC20(asset_));
        if (!assetConfiguration.isConfigured) {
            revert BurnerLoans_InvalidDepositManager(address(_DEPOSIT_MANAGER));
        }

        IDepositManager.AssetPeriodStatus memory assetPeriod = _DEPOSIT_MANAGER.isAssetPeriod(
            IERC20(asset_),
            BurnerLoansConstants.DEPOSIT_PERIOD,
            address(this)
        );
        if (!assetPeriod.isConfigured || !assetPeriod.isEnabled) {
            revert BurnerLoans_InvalidDepositManager(address(_DEPOSIT_MANAGER));
        }

        return assetConfiguration;
    }

    /// @notice Validates DepositManager asset-period support for existing custody exits.
    function _validateWithdrawCustodySupport(
        address asset_
    ) internal view returns (IDepositManager.AssetConfiguration memory assetConfiguration) {
        _requireDepositManagerEnabled();

        assetConfiguration = _DEPOSIT_MANAGER.getAssetConfiguration(IERC20(asset_));
        if (!assetConfiguration.isConfigured) {
            revert BurnerLoans_InvalidDepositManager(address(_DEPOSIT_MANAGER));
        }

        IDepositManager.AssetPeriodStatus memory assetPeriod = _DEPOSIT_MANAGER.isAssetPeriod(
            IERC20(asset_),
            BurnerLoansConstants.DEPOSIT_PERIOD,
            address(this)
        );
        if (!assetPeriod.isConfigured) {
            revert BurnerLoans_InvalidDepositManager(address(_DEPOSIT_MANAGER));
        }

        return assetConfiguration;
    }

    /// @notice Reverts unless the configured DepositManager exposes an enabled custody surface.
    /// @dev DepositManager lifecycle is exposed through `IEnabler`, not `IDepositManager`. A
    ///      missing lifecycle surface is treated as unavailable custody so previews and writes
    ///      fail before quoting or moving collateral.
    /// @dev Reverts if:
    ///      - The manager is disabled.
    ///      - The manager does not implement the `IEnabler.isEnabled()` view.
    ///      Reverts with `BurnerLoans_InvalidDepositManager` in either case.
    function _requireDepositManagerEnabled() internal view {
        try IEnabler(address(_DEPOSIT_MANAGER)).isEnabled() returns (bool enabled) {
            if (!enabled) revert BurnerLoans_InvalidDepositManager(address(_DEPOSIT_MANAGER));
        } catch {
            revert BurnerLoans_InvalidDepositManager(address(_DEPOSIT_MANAGER));
        }
    }

    /// @notice Mirrors DepositManager deposit amount constraints for previews and early write validation.
    function _validateDepositAmount(
        address asset_,
        IDepositManager.AssetConfiguration memory assetConfiguration_,
        uint256 amount_
    ) internal view {
        if (amount_ < assetConfiguration_.minimumDeposit) {
            revert IAssetManager.AssetManager_MinimumDepositNotMet(
                asset_,
                amount_,
                assetConfiguration_.minimumDeposit
            );
        }

        (, uint256 assetAmountBefore) = _DEPOSIT_MANAGER.getOperatorAssets(
            IERC20(asset_),
            address(this)
        );
        if (assetAmountBefore + amount_ > assetConfiguration_.depositCap) {
            revert IAssetManager.AssetManager_DepositCapExceeded(
                asset_,
                assetAmountBefore,
                assetConfiguration_.depositCap
            );
        }
    }

    /// @notice Returns a current-state ERC4626 quote for credited DepositManager collateral.
    /// @dev A generic vault cannot expose its post-deposit share rate in a view call, so this quote
    ///      can differ from the actual credit returned by DepositManager if vault state changes or
    ///      the vault applies different post-deposit accounting.
    function _previewDepositAmount(
        address vault_,
        uint256 amount_
    ) internal view returns (uint256) {
        if (vault_ == address(0)) return amount_;

        IERC4626 vault = IERC4626(vault_);
        uint256 shares = vault.previewDeposit(amount_);
        if (shares == 0) return 0;

        return vault.previewRedeem(shares);
    }

    /// @notice Previews the token amount returned by DepositManager for a collateral withdrawal.
    function _previewWithdrawAmount(
        address vault_,
        uint256 amount_
    ) internal view returns (uint256) {
        if (vault_ == address(0)) return amount_;

        IERC4626 vault = IERC4626(vault_);
        return vault.previewRedeem(vault.convertToShares(amount_));
    }

    /// @notice Pulls collateral from the caller into DepositManager custody.
    function _depositCollateralToCustody(
        address asset_,
        uint256 amount_
    ) internal returns (uint256) {
        ERC20 asset = ERC20(asset_);
        uint256 startingBalance = IERC20(asset_).balanceOf(address(this));
        asset.safeTransferFrom(msg.sender, address(this), amount_);
        asset.safeApprove(address(_DEPOSIT_MANAGER), amount_);

        (, uint256 depositedCollateral) = _DEPOSIT_MANAGER.deposit(
            IDepositManager.DepositParams({
                asset: IERC20(asset_),
                depositPeriod: BurnerLoansConstants.DEPOSIT_PERIOD,
                depositor: address(this),
                amount: amount_,
                shouldWrap: false
            })
        );

        uint256 residualBalance = IERC20(asset_).balanceOf(address(this));
        if (residualBalance > startingBalance)
            revert BurnerLoans_ResidualCollateralBalance(asset_, residualBalance - startingBalance);

        _approveCustodyReceiptBurn(asset_);

        return depositedCollateral;
    }

    /// @notice Allows DepositManager to burn BurnerLoans-held receipt tokens on later withdrawals.
    function _approveCustodyReceiptBurn(address asset_) internal {
        IReceiptTokenManager receiptTokenManager = _DEPOSIT_MANAGER.getReceiptTokenManager();
        if (address(receiptTokenManager) == address(0)) return;

        uint256 receiptTokenId = _DEPOSIT_MANAGER.getReceiptTokenId(
            IERC20(asset_),
            BurnerLoansConstants.DEPOSIT_PERIOD,
            address(this)
        );
        if (
            receiptTokenManager.allowance(
                address(this),
                address(_DEPOSIT_MANAGER),
                receiptTokenId
            ) != type(uint256).max
        ) {
            if (
                !receiptTokenManager.approve(
                    address(_DEPOSIT_MANAGER),
                    receiptTokenId,
                    type(uint256).max
                )
            ) {
                revert BurnerLoans_ReceiptApprovalFailed(address(receiptTokenManager));
            }
        }
    }

    /// @notice Withdraws collateral from DepositManager custody to recipient_.
    function _withdrawCollateralFromCustody(
        address asset_,
        uint256 amount_,
        address recipient_
    ) internal returns (uint256) {
        return
            _DEPOSIT_MANAGER.withdraw(
                IDepositManager.WithdrawParams({
                    asset: IERC20(asset_),
                    depositPeriod: BurnerLoansConstants.DEPOSIT_PERIOD,
                    depositor: address(this),
                    recipient: recipient_,
                    amount: amount_,
                    isWrapped: false
                })
            );
    }

    /// @notice Debits position collateral after validating resulting health.
    function _debitCollateral(
        address asset_,
        uint256 amount_,
        address onBehalfOf_
    ) internal returns (uint256 remainingCollateral, uint256 resultingHealthFactor) {
        Position storage position = _positions[onBehalfOf_][asset_];
        if (amount_ > position.depositedCollateral) {
            revert BurnerLoans_InsufficientCollateral(amount_, position.depositedCollateral);
        }

        remainingCollateral = position.depositedCollateral - amount_;
        resultingHealthFactor = _positionHealthFactor(
            asset_,
            _assetConfigs[asset_],
            remainingCollateral,
            position.debtOhm
        );
        if (position.debtOhm != 0 && resultingHealthFactor < _WAD) {
            revert BurnerLoans_UnhealthyWithdrawal(resultingHealthFactor);
        }

        position.depositedCollateral = remainingCollateral;
        if (remainingCollateral == 0 && position.debtOhm == 0) {
            position.status = PositionStatus.NoDebt;
        }
    }

    /// @notice Calculates health for a prospective position state using fresh PRICE data.
    /// @dev Debt-free positions deliberately do not require PRICE freshness.
    function _positionHealthFactor(
        address asset_,
        AssetConfig memory config_,
        uint256 depositedCollateral_,
        uint256 debtOhm_
    ) internal view returns (uint256) {
        if (debtOhm_ == 0) return type(uint256).max;

        uint48 observationFrequency = _PRICE.observationFrequency();
        (uint256 ohmUsdPrice, ) = _getFreshPrice(address(_OHM), observationFrequency);
        uint256 backingPerOhmUsd = _getBackingPerOhmUsd();
        (uint256 collateralUsdPrice, ) = _getFreshPrice(asset_, observationFrequency);

        uint256 riskAdjustedCollateralUsd = _riskAdjustedCollateralUsd(
            _collateralValueUsd(
                depositedCollateral_,
                collateralUsdPrice,
                config_.collateralDecimals
            ),
            config_.collateralFactorBps
        );
        uint256 requiredCollateralUsd = _requiredCollateralUsd(
            RequiredCollateralUsdInputs({
                debtValueUsd: _debtValueUsd(debtOhm_, ohmUsdPrice, _OHM_DECIMALS),
                debtOhm: debtOhm_,
                backingPerOhmUsd: backingPerOhmUsd,
                minCollateralRatioBps: config_.minCollateralRatioBps,
                backingMultiplierBps: config_.backingMultiplierBps
            })
        );

        return _healthFactor(riskAdjustedCollateralUsd, requiredCollateralUsd);
    }

    /// @notice Reads a non-zero PRICE value whose timestamp is within one observation window.
    function _getFreshPrice(
        address asset_,
        uint48 observationFrequency_
    ) internal view returns (uint256 price, uint48 timestamp) {
        (price, timestamp) = _PRICE.getPrice(asset_, IPRICEv2.Variant.CURRENT);
        if (price == 0 || timestamp == 0) revert BurnerLoans_InvalidPrice();

        if (block.timestamp > uint256(timestamp) + uint256(observationFrequency_)) {
            revert BurnerLoans_InvalidPrice();
        }
    }

    /// @notice Reads canonical OHM backing and converts it from 18 decimals to PRICE decimals.
    /// @dev Conversion rounds up so reducing decimal precision cannot weaken the backing floor.
    function _getBackingPerOhmUsd() internal view returns (uint256 backingPerOhmUsd) {
        address backingOracle_ = backingOracle;
        if (backingOracle_ == address(0)) revert BurnerLoans_ZeroAddress();

        uint256 backing18 = IOlympusBackingOracle(backingOracle_).backing();
        if (backing18 == 0) revert BurnerLoans_InvalidPrice();

        backingPerOhmUsd = FullMath.mulDivUp(backing18, _scale(_PRICE.decimals()), _WAD);
    }

    // ========== INTERNAL MATH HELPERS ========== //

    /// @notice Returns 10 ** decimals_.
    /// @dev Input: decimal count. Output: integer scale.
    function _scale(uint8 decimals_) internal pure returns (uint256) {
        return 10 ** decimals_;
    }

    /// @notice Converts OHM debt to USD value, rounding up.
    /// @dev Inputs: `debtOhm_` in OHM decimals, `ohmUsdPrice_` in PRICE decimals.
    ///      Output: USD value in PRICE decimals.
    function _debtValueUsd(
        uint256 debtOhm_,
        uint256 ohmUsdPrice_,
        uint8 ohmDecimals_
    ) internal pure returns (uint256) {
        if (ohmUsdPrice_ == 0) revert BurnerLoans_InvalidPrice();
        return FullMath.mulDivUp(debtOhm_, ohmUsdPrice_, _scale(ohmDecimals_));
    }

    /// @notice Converts collateral to USD value, rounding down.
    /// @dev Inputs: `collateralAmount_` in collateral token decimals,
    ///      `collateralUsdPrice_` in PRICE decimals. Output: USD value in PRICE decimals.
    function _collateralValueUsd(
        uint256 collateralAmount_,
        uint256 collateralUsdPrice_,
        uint8 collateralDecimals_
    ) internal pure returns (uint256) {
        if (collateralUsdPrice_ == 0) revert BurnerLoans_InvalidPrice();
        return FullMath.mulDiv(collateralAmount_, collateralUsdPrice_, _scale(collateralDecimals_));
    }

    /// @notice Applies the collateral factor to collateral USD value, rounding down.
    /// @dev Inputs and output are PRICE decimals.
    function _riskAdjustedCollateralUsd(
        uint256 collateralValueUsd_,
        uint256 collateralFactorBps_
    ) internal pure returns (uint256) {
        return FullMath.mulDiv(collateralValueUsd_, collateralFactorBps_, _BPS);
    }

    /// @notice Calculates the backing floor for active or seized OHM debt, rounding up.
    /// @dev Inputs: `debtOhm_` in OHM decimals, `backingPerOhmUsd_` in PRICE decimals.
    ///      Output: required backing in PRICE decimals.
    function _requiredBackingUsd(
        uint256 debtOhm_,
        uint256 backingPerOhmUsd_,
        uint8 ohmDecimals_,
        uint256 backingMultiplierBps_
    ) internal pure returns (uint256) {
        if (backingPerOhmUsd_ == 0) revert BurnerLoans_InvalidPrice();

        uint256 backingValueUsd = FullMath.mulDivUp(
            debtOhm_,
            backingPerOhmUsd_,
            _scale(ohmDecimals_)
        );
        return FullMath.mulDivUp(backingValueUsd, backingMultiplierBps_, _BPS);
    }

    /// @notice Calculates the collateral requirement in USD, rounding requirements up.
    /// @dev Inputs and output are PRICE decimals except `debtOhm_`, which is OHM decimals.
    function _requiredCollateralUsd(
        RequiredCollateralUsdInputs memory inputs_
    ) internal view returns (uint256) {
        uint256 marketRequirementUsd = FullMath.mulDivUp(
            inputs_.debtValueUsd,
            inputs_.minCollateralRatioBps,
            _BPS
        );
        uint256 backingRequirementUsd = _requiredBackingUsd(
            inputs_.debtOhm,
            inputs_.backingPerOhmUsd,
            _OHM_DECIMALS,
            inputs_.backingMultiplierBps
        );

        return
            marketRequirementUsd > backingRequirementUsd
                ? marketRequirementUsd
                : backingRequirementUsd;
    }

    /// @notice Converts required USD collateral to collateral token units, rounding up.
    /// @dev Input: USD in PRICE decimals. Output: collateral amount in token-native decimals.
    function _requiredCollateralAsset(
        uint256 requiredCollateralUsd_,
        uint256 collateralUsdPrice_,
        uint8 collateralDecimals_
    ) internal pure returns (uint256) {
        if (collateralUsdPrice_ == 0) revert BurnerLoans_InvalidPrice();
        return
            FullMath.mulDivUp(
                requiredCollateralUsd_,
                _scale(collateralDecimals_),
                collateralUsdPrice_
            );
    }

    /// @notice Calculates borrower health, rounding down.
    /// @dev Inputs: `riskAdjustedCollateralUsd_` and `requiredCollateralUsd_` in PRICE decimals.
    ///      Output: WAD health factor; 1e18 is the seizure boundary.
    function _healthFactor(
        uint256 riskAdjustedCollateralUsd_,
        uint256 requiredCollateralUsd_
    ) internal pure returns (uint256) {
        if (requiredCollateralUsd_ == 0) return type(uint256).max;
        return FullMath.mulDiv(riskAdjustedCollateralUsd_, _WAD, requiredCollateralUsd_);
    }

    /// @notice Calculates utilization, rounding up.
    /// @dev Inputs: debt and cap use the same units. Output: bps.
    function _utilizationBps(uint256 debt_, uint256 cap_) internal pure returns (uint256) {
        if (cap_ == 0) {
            if (debt_ == 0) return 0;
            revert BurnerLoans_InvalidCap();
        }

        return FullMath.mulDivUp(debt_, _BPS, cap_);
    }

    /// @notice Calculates asset utilization, rounding up.
    /// @dev Inputs: debt and cap use the same units. Output: WAD.
    function _assetUtilizationWad(uint256 debt_, uint256 cap_) internal pure returns (uint256) {
        if (cap_ == 0) {
            if (debt_ == 0) return 0;
            revert BurnerLoans_InvalidCap();
        }

        return FullMath.mulDivUp(debt_, _WAD, cap_);
    }

    /// @notice Calculates fee utilization from asset open interest only.
    /// @dev Global utilization is a capacity constraint, not a fee input. Output: WAD.
    function _effectiveUtilizationWad(
        UtilizationInputs memory inputs_
    ) internal pure returns (uint256) {
        return _assetUtilizationWad(inputs_.assetDebtOhm, inputs_.assetDebtCapOhm);
    }

    /// @notice Calculates utilization fee rate from the piecewise linear kink curve.
    /// @dev Uses Aave-style slope semantics. `preKinkSlopeBps` is the full increase from 0 utilization to the
    /// kink. `postKinkSlopeBps` is the additional increase from the kink to 100% utilization. `utilizationWad_`
    /// is WAD. Fee config values are bps. Output is WAD.
    function _feeRateWad(
        uint256 utilizationWad_,
        AssetFeeConfig memory feeConfig_
    ) internal pure override returns (uint256) {
        if (utilizationWad_ > _WAD) revert BurnerLoans_InvalidParam();

        uint256 baseFeeRateWad = uint256(feeConfig_.baseFeeBps) * (_WAD / _BPS);
        if (feeConfig_.kinkBps == 0) {
            return
                baseFeeRateWad + FullMath.mulDiv(utilizationWad_, feeConfig_.preKinkSlopeBps, _BPS);
        }

        uint256 kinkWad = uint256(feeConfig_.kinkBps) * (_WAD / _BPS);

        if (utilizationWad_ <= kinkWad) {
            return
                baseFeeRateWad +
                FullMath.mulDiv(
                    utilizationWad_,
                    uint256(feeConfig_.preKinkSlopeBps) * _WAD,
                    kinkWad * _BPS
                );
        }

        return
            baseFeeRateWad +
            uint256(feeConfig_.preKinkSlopeBps) *
            (_WAD / _BPS) +
            FullMath.mulDiv(
                utilizationWad_ - kinkWad,
                uint256(feeConfig_.postKinkSlopeBps) * _WAD,
                (_WAD - kinkWad) * _BPS
            );
    }

    /// @notice Calculates the borrow fee in collateral units, rounding value transfers up.
    /// @dev Output is in collateral token decimals.
    function _borrowFee(
        uint256 incrementalRequiredCollateral_,
        uint256 feeRateWad_
    ) internal pure returns (uint256) {
        return FullMath.mulDivUp(incrementalRequiredCollateral_, feeRateWad_, _WAD);
    }

    /// @notice Calculates the extension fee in collateral units, rounding the single-term fee up.
    /// @dev Output is in collateral token decimals and scales linearly with `termCount_`.
    function _extensionFee(
        uint256 currentRequiredCollateral_,
        uint256 feeRateWad_,
        uint256 termCount_
    ) internal pure returns (uint256) {
        uint256 singleTermFee = FullMath.mulDivUp(currentRequiredCollateral_, feeRateWad_, _WAD);
        return singleTermFee * termCount_;
    }

    /// @notice Calculates the keeper reward for a seizure batch.
    /// @dev All collateral amounts are token-native decimals. Price and backing inputs use PRICE decimals.
    function _keeperRewardAsset(KeeperRewardInputs memory inputs_) internal view returns (uint256) {
        if (
            inputs_.isProtocolSeizureCaller ||
            inputs_.rewardBps == 0 ||
            inputs_.maxKeeperRewardAsset == 0
        ) {
            return 0;
        }

        uint256 configuredRewardAsset = FullMath.mulDiv(
            inputs_.seizedCollateralAmount,
            inputs_.rewardBps,
            _BPS
        );
        if (configuredRewardAsset > inputs_.maxKeeperRewardAsset) {
            configuredRewardAsset = inputs_.maxKeeperRewardAsset;
        }

        uint256 requiredBackingUsd = _requiredBackingUsd(
            inputs_.seizedUnrepaidDebtOhm,
            inputs_.backingPerOhmUsd,
            _OHM_DECIMALS,
            inputs_.backingMultiplierBps
        );
        uint256 requiredBackingAsset = _requiredCollateralAsset(
            requiredBackingUsd,
            inputs_.collateralUsdPrice,
            inputs_.collateralDecimals
        );

        uint256 surplusAfterBackingAsset = inputs_.seizedCollateralAmount > requiredBackingAsset
            ? inputs_.seizedCollateralAmount - requiredBackingAsset
            : 0;

        return
            configuredRewardAsset < surplusAfterBackingAsset
                ? configuredRewardAsset
                : surplusAfterBackingAsset;
    }
}
