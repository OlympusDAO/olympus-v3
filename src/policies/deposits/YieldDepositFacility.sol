// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.20;

// Libraries
import {FullMath} from "src/libraries/FullMath.sol";

// Interfaces
import {IYieldDepositFacility} from "src/policies/interfaces/deposits/IYieldDepositFacility.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IPeriodicTask} from "src/interfaces/IPeriodicTask.sol";
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositPositionManager} from "src/modules/DEPOS/IDepositPositionManager.sol";

// Bophades
import {Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {DEPOSv1} from "src/modules/DEPOS/DEPOS.v1.sol";
import {HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {BaseDepositFacility} from "src/policies/deposits/BaseDepositFacility.sol";

/// @title YieldDepositFacility
contract YieldDepositFacility is BaseDepositFacility, IYieldDepositFacility, IPeriodicTask {
    // ========== STATE VARIABLES ========== //

    /// @notice The DEPOS module.
    DEPOSv1 public DEPOS;

    /// @notice The yield fee
    uint16 internal _yieldFee;

    /// @notice Mapping between a position id and the last conversion rate between a vault and underlying asset
    /// @dev    This is used to calculate the yield since the last claim. The initial value should be set at the time of minting.
    mapping(uint256 => uint256) public positionLastYieldConversionRate;

    /// @notice Mapping between vault address and timestamp to snapshot data
    /// @dev    This is used to store periodic snapshots of conversion rates for each vault
    mapping(IERC4626 => mapping(uint48 => uint256)) public vaultRateSnapshots;

    /// @notice The interval between snapshots in seconds
    uint48 private constant SNAPSHOT_INTERVAL = 8 hours;

    // ========== SETUP ========== //

    constructor(
        address kernel_,
        address depositManager_
    ) BaseDepositFacility(kernel_, depositManager_) {
        // Disabled by default by PolicyEnabler
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](3);
        dependencies[0] = toKeycode("ROLES");
        dependencies[1] = toKeycode("DEPOS");
        dependencies[2] = toKeycode("TRSRY");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
        DEPOS = DEPOSv1(getModuleAddress(dependencies[1]));
        TRSRY = TRSRYv1(getModuleAddress(dependencies[2]));
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {
        Keycode cdposKeycode = toKeycode("DEPOS");

        permissions = new Permissions[](1);
        permissions[0] = Permissions(cdposKeycode, DEPOS.mint.selector);
    }

    function VERSION() external pure returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;

        return (major, minor);
    }

    // ========== MINT ========== //

    modifier onlyYieldBearingAsset(IERC20 asset_, uint8 periodMonths_) {
        // Validate that the asset has a yield bearing vault
        IAssetManager.AssetConfiguration memory assetConfiguration = DEPOSIT_MANAGER
            .getAssetConfiguration(asset_);
        if (!assetConfiguration.isConfigured || address(assetConfiguration.vault) == address(0))
            revert YDF_InvalidToken(address(asset_), periodMonths_);
        _;
    }

    /// @inheritdoc IYieldDepositFacility
    /// @dev        This function reverts if:
    ///             - The contract is not enabled
    ///             - The asset token is not supported
    function createPosition(
        CreatePositionParams calldata params_
    )
        external
        nonReentrant
        onlyEnabled
        onlyYieldBearingAsset(params_.asset, params_.periodMonths)
        returns (uint256 positionId, uint256 receiptTokenId, uint256 actualAmount)
    {
        address depositor = msg.sender;

        // Deposit the asset into the deposit manager (and mint the receipt token)
        // This will validate that the asset is supported, and mint the receipt token
        (receiptTokenId, actualAmount) = DEPOSIT_MANAGER.deposit(
            IDepositManager.DepositParams({
                asset: params_.asset,
                depositPeriod: params_.periodMonths,
                depositor: depositor,
                amount: params_.amount,
                shouldWrap: params_.wrapReceipt
            })
        );

        // Create a new term record in the DEPOS module
        positionId = DEPOS.mint(
            IDepositPositionManager.MintParams({
                owner: depositor,
                asset: address(params_.asset),
                periodMonths: params_.periodMonths,
                remainingDeposit: params_.amount,
                conversionPrice: type(uint256).max,
                expiry: uint48(block.timestamp + uint48(params_.periodMonths) * 30 days),
                wrapPosition: params_.wrapPosition,
                additionalData: ""
            })
        );

        // Set the initial yield conversion rate
        // We add 1 to account for ERC4626 rounding errors, otherwise the DepositManager will be left insolvent
        positionLastYieldConversionRate[positionId] =
            _getConversionRate(
                IERC4626(DEPOSIT_MANAGER.getAssetConfiguration(params_.asset).vault)
            ) +
            1;

        // Emit an event
        emit CreatedDeposit(
            address(params_.asset),
            depositor,
            positionId,
            params_.periodMonths,
            params_.amount
        );

        return (positionId, receiptTokenId, actualAmount);
    }

    /// @inheritdoc IYieldDepositFacility
    function deposit(
        IERC20 asset_,
        uint8 periodMonths_,
        uint256 amount_,
        bool wrapReceipt_
    )
        external
        nonReentrant
        onlyEnabled
        onlyYieldBearingAsset(asset_, periodMonths_)
        returns (uint256 receiptTokenId, uint256 actualAmount)
    {
        // Deposit the asset into the deposit manager (and mint the receipt token)
        // This will validate that the asset is supported, and mint the receipt token
        (receiptTokenId, actualAmount) = DEPOSIT_MANAGER.deposit(
            IDepositManager.DepositParams({
                asset: asset_,
                depositPeriod: periodMonths_,
                depositor: msg.sender,
                amount: amount_,
                shouldWrap: wrapReceipt_
            })
        );

        return (receiptTokenId, actualAmount);
    }

    // ========== YIELD FUNCTIONS ========== //

    function _previewClaimYield(
        address account_,
        uint256 positionId_,
        address previousAsset_,
        uint8 previousPeriodMonths_,
        uint48 timestampHint_
    ) internal view returns (uint256 yieldMinusFee, uint256 yieldFee, uint256 endRate) {
        // Validate that the position is valid
        // This will revert if the position is not valid
        DEPOSv1.Position memory position = DEPOS.getPosition(positionId_);

        // Validate that the caller is the owner of the position
        if (position.owner != account_) revert YDF_NotOwner(positionId_);

        // Validate that the asset and period are the same as the previous asset and period
        if (
            previousAsset_ == address(0) ||
            previousPeriodMonths_ == 0 ||
            previousAsset_ != position.asset ||
            previousPeriodMonths_ != position.periodMonths
        ) revert YDF_InvalidArgs("multiple tokens");

        // Validate that the position is created by the YDF
        if (position.operator != address(this)) revert YDF_Unsupported(positionId_);

        // Validate that the asset has a yield bearing vault
        // This is validated in the createPosition function, but is checked to be safe
        IERC4626 assetVault = IERC4626(
            DEPOSIT_MANAGER.getAssetConfiguration(IERC20(position.asset)).vault
        );
        if (address(assetVault) == address(0)) revert YDF_Unsupported(positionId_);

        // Get the last snapshot rate
        uint256 lastSnapshotRate = positionLastYieldConversionRate[positionId_];

        // Calculate the end rate (either current rate or rate at expiry)
        if (block.timestamp <= position.expiry) {
            // Deposit period hasn't finished, use current rate
            endRate = _getConversionRate(assetVault);
        } else {
            // Deposit period has finished, find the rate at expiry
            // Validate timestamp hint if provided
            uint48 snapshotTimestamp = position.expiry;
            if (timestampHint_ > 0) {
                if (timestampHint_ > position.expiry) {
                    revert YDF_InvalidArgs("timestamp hint");
                }
                snapshotTimestamp = timestampHint_;
            }
            uint48 snapshotKey = _getSnapshotKey(snapshotTimestamp);

            // Get the rate at the snapshot key
            uint256 expiryRate = vaultRateSnapshots[assetVault][snapshotKey];
            if (expiryRate == 0) {
                revert YDF_NoSnapshotAvailable(address(assetVault), snapshotKey);
            }

            endRate = expiryRate;
        }

        // Calculate the number of shares for the position at the last snapshot rate
        uint256 lastShares = FullMath.mulDiv(
            position.remainingDeposit, // assets
            10 ** assetVault.decimals(), // decimals
            lastSnapshotRate // assets per share
        );

        // Calculate what the position would be worth at the current rate
        uint256 currentValue = FullMath.mulDiv(
            lastShares, // shares
            endRate, // assets per share
            10 ** assetVault.decimals() // decimals
        );

        // Calculate the yield as the difference between current value and original deposit
        uint256 yield = currentValue > position.remainingDeposit
            ? currentValue - position.remainingDeposit
            : 0;

        // Calculate fees
        yieldFee = FullMath.mulDiv(yield, _yieldFee, ONE_HUNDRED_PERCENT);
        yieldMinusFee = yield - yieldFee;

        return (yieldMinusFee, yieldFee, endRate);
    }

    /// @inheritdoc IYieldDepositFacility
    function previewClaimYield(
        address account_,
        uint256[] memory positionIds_
    ) external view onlyEnabled returns (uint256 yieldMinusFee, IERC20 asset) {
        return previewClaimYield(account_, positionIds_, new uint48[](positionIds_.length));
    }

    /// @inheritdoc IYieldDepositFacility
    function previewClaimYield(
        address account_,
        uint256[] memory positionIds_,
        uint48[] memory timestampHints_
    ) public view onlyEnabled returns (uint256 yieldMinusFee, IERC20 asset) {
        if (positionIds_.length != timestampHints_.length)
            revert YDF_InvalidArgs("array length mismatch");
        if (positionIds_.length == 0) revert YDF_InvalidArgs("no positions");

        // Get the asset and period months
        uint8 periodMonths;
        {
            DEPOSv1.Position memory position = DEPOS.getPosition(positionIds_[0]);
            asset = IERC20(position.asset);
            periodMonths = position.periodMonths;

            // Validate that the asset is supported
            if (!DEPOSIT_MANAGER.isAssetPeriod(asset, periodMonths).isConfigured)
                revert YDF_Unsupported(positionIds_[0]);
        }

        for (uint256 i; i < positionIds_.length; ++i) {
            uint256 positionId = positionIds_[i];

            (uint256 previewYieldMinusFee, , ) = _previewClaimYield(
                account_,
                positionId,
                address(asset),
                periodMonths,
                timestampHints_[i]
            );
            yieldMinusFee += previewYieldMinusFee;
        }

        return (yieldMinusFee, asset);
    }

    /// @inheritdoc IYieldDepositFacility
    function claimYield(uint256[] memory positionIds_) external returns (uint256 yieldMinusFee) {
        return claimYield(positionIds_, new uint48[](positionIds_.length));
    }

    /// @inheritdoc IYieldDepositFacility
    function claimYield(
        uint256[] memory positionIds_,
        uint48[] memory timestampHints_
    ) public onlyEnabled returns (uint256 yieldMinusFee) {
        if (positionIds_.length != timestampHints_.length)
            revert YDF_InvalidArgs("array length mismatch");
        if (positionIds_.length == 0) revert YDF_InvalidArgs("no positions");

        // Get the asset and period months
        IERC20 asset;
        uint8 periodMonths;
        {
            DEPOSv1.Position memory position = DEPOS.getPosition(positionIds_[0]);
            asset = IERC20(position.asset);
            periodMonths = position.periodMonths;

            // Validate that the asset is supported
            if (!DEPOSIT_MANAGER.isAssetPeriod(asset, periodMonths).isConfigured)
                revert YDF_Unsupported(positionIds_[0]);
        }

        uint256 yieldFee;
        for (uint256 i; i < positionIds_.length; ++i) {
            uint256 positionId = positionIds_[i];

            (
                uint256 previewYieldMinusFee,
                uint256 previewYieldFee,
                uint256 endRate
            ) = _previewClaimYield(
                    msg.sender,
                    positionId,
                    address(asset),
                    periodMonths,
                    timestampHints_[i]
                );

            yieldMinusFee += previewYieldMinusFee;
            yieldFee += previewYieldFee;

            // If there is yield, update the last yield conversion rate
            // We add 1 to account for ERC4626 rounding errors, otherwise the DepositManager will be left insolvent
            if (previewYieldMinusFee > 0) {
                positionLastYieldConversionRate[positionId] = endRate + 1;
            }
        }

        if (yieldMinusFee > 0) {
            // Withdraw the yield from the deposit manager to this contract
            // This will validate that the deposits are still solvent
            // This is also done as one call, to avoid off-by-one rounding errors with ERC4626
            DEPOSIT_MANAGER.claimYield(asset, address(this), yieldMinusFee + yieldFee);
            // Transfer the yield (minus fee) to the caller
            IERC20(asset).transfer(msg.sender, yieldMinusFee);
            // Transfer the yield fee to the treasury
            if (yieldFee > 0) IERC20(asset).transfer(address(TRSRY), yieldFee);
        }

        // Emit event
        emit YieldClaimed(address(asset), msg.sender, yieldMinusFee);

        return yieldMinusFee;
    }

    // ========== ADMIN FUNCTIONS ========== //

    /// @inheritdoc IYieldDepositFacility
    /// @dev        This function reverts if:
    ///             - The contract is not enabled
    ///             - The caller is not an admin
    ///             - The yield fee is greater than 100e2
    function setYieldFee(uint16 yieldFee_) external onlyEnabled onlyAdminRole {
        // Validate that the yield fee is not greater than 100e2
        if (yieldFee_ > 100e2) revert YDF_InvalidArgs("yield fee");

        // Set the yield fee
        _yieldFee = yieldFee_;

        // Emit event
        emit YieldFeeSet(yieldFee_);
    }

    /// @inheritdoc IYieldDepositFacility
    function getYieldFee() external view returns (uint16) {
        return _yieldFee;
    }

    // ========== HELPER FUNCTIONS ========== //

    /// @notice Get the snapshot key for a given timestamp
    /// @dev    Rounds down to the nearest 8-hour interval
    function _getSnapshotKey(uint48 timestamp_) internal pure returns (uint48) {
        return (timestamp_ / SNAPSHOT_INTERVAL) * SNAPSHOT_INTERVAL;
    }

    /// @notice Get the conversion rate between a vault and underlying asset
    function _getConversionRate(IERC4626 vault_) internal view returns (uint256) {
        return vault_.convertToAssets(1e18);
    }

    // ========== PERIODIC TASK ========== //

    /// @notice Stores periodic snapshots of the conversion rate for all supported vaults
    /// @dev    This function is called by the Heart contract every 8 hours
    /// @dev    The timestamp is rounded down to the nearest 8-hour interval
    /// @dev    No cleanup is performed as snapshots are needed for active deposits
    function execute() external override onlyRole(HEART_ROLE) {
        // If the contract is disabled, do not take any snapshots
        if (!isEnabled) return;

        // Get the rounded timestamp
        uint48 snapshotKey = _getSnapshotKey(uint48(block.timestamp));

        // Get all supported assets
        IERC20[] memory assets = DEPOSIT_MANAGER.getConfiguredAssets();

        // Store snapshots for each vault
        for (uint256 i; i < assets.length; ++i) {
            IERC4626 vault = IERC4626(DEPOSIT_MANAGER.getAssetConfiguration(assets[i]).vault);

            // Skip if the vault is not set
            if (address(vault) == address(0)) continue;

            // Only store if we haven't stored for this interval
            if (vaultRateSnapshots[vault][snapshotKey] == 0) {
                uint256 rate = _getConversionRate(vault);
                vaultRateSnapshots[vault][snapshotKey] = rate;
                emit RateSnapshotTaken(address(vault), snapshotKey, rate);
            }
        }
    }

    // ========== ERC165 ========== //

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(BaseDepositFacility, IPeriodicTask) returns (bool) {
        return
            interfaceId == type(IYieldDepositFacility).interfaceId ||
            interfaceId == type(IPeriodicTask).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
