// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.20;

// Libraries
import {FullMath} from "src/libraries/FullMath.sol";

// Interfaces
import {IYieldDepositFacility} from "src/policies/interfaces/IYieldDepositFacility.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IPeriodicTask} from "src/policies/interfaces/IPeriodicTask.sol";
import {IAssetManager} from "src/bases/interfaces/IAssetManager.sol";

// Bophades
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {CDPOSv1} from "src/modules/CDPOS/CDPOS.v1.sol";
import {HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {BaseDepositRedemptionVault} from "src/bases/BaseDepositRedemptionVault.sol";

/// @title YieldDepositFacility
contract YieldDepositFacility is
    Policy,
    IYieldDepositFacility,
    IPeriodicTask,
    BaseDepositRedemptionVault
{
    // ========== STATE VARIABLES ========== //

    /// @notice The CDPOS module.
    CDPOSv1 public CDPOS;

    /// @notice The yield fee
    uint16 internal _yieldFee;

    /// @notice Mapping between a position id and the last conversion rate between a CD token's vault and underlying asset
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
    ) Policy(Kernel(kernel_)) BaseDepositRedemptionVault(depositManager_) {
        // Disabled by default by PolicyEnabler
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](4);
        dependencies[0] = toKeycode("ROLES");
        dependencies[1] = toKeycode("CDPOS");
        dependencies[2] = toKeycode("TRSRY");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
        CDPOS = CDPOSv1(getModuleAddress(dependencies[1]));
        TRSRY = TRSRYv1(getModuleAddress(dependencies[2]));
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {
        Keycode cdposKeycode = toKeycode("CDPOS");

        permissions = new Permissions[](1);
        permissions[0] = Permissions(cdposKeycode, CDPOS.mint.selector);
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
        IERC20 asset_,
        uint8 periodMonths_,
        uint256 amount_,
        bool wrapPosition_,
        bool wrapReceipt_
    )
        external
        nonReentrant
        onlyEnabled
        onlyYieldBearingAsset(asset_, periodMonths_)
        returns (uint256 positionId)
    {
        // Deposit the asset into the deposit manager (and mint the receipt token)
        // This will validate that the asset is supported, and mint the receipt token
        DEPOSIT_MANAGER.deposit(asset_, periodMonths_, msg.sender, amount_, wrapReceipt_);

        // Create a new term record in the CDPOS module
        positionId = CDPOS.mint(
            msg.sender, // owner
            address(asset_), // asset
            periodMonths_, // period months
            amount_, // amount
            type(uint256).max, // conversion price of max to indicate no conversion price
            uint48(block.timestamp + uint48(periodMonths_) * 30 days), // expiry
            wrapPosition_ // wrap
        );

        // Set the initial yield conversion rate
        positionLastYieldConversionRate[positionId] = _getConversionRate(
            DEPOSIT_MANAGER.getAssetConfiguration(asset_).vault
        );

        // Emit an event
        emit CreatedDeposit(address(asset_), msg.sender, positionId, periodMonths_, amount_);
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
        CDPOSv1.Position memory position = CDPOS.getPosition(positionId_);

        // Validate that the caller is the owner of the position
        if (position.owner != account_) revert YDF_NotOwner(positionId_);

        // Validate that the asset and period are the same as the previous asset and period
        if (
            previousAsset_ == address(0) ||
            previousPeriodMonths_ == 0 ||
            previousAsset_ != position.asset ||
            previousPeriodMonths_ != position.periodMonths
        ) revert YDF_InvalidArgs("multiple tokens");

        // Validate that the position is not convertible
        if (CDPOS.isConvertible(positionId_)) revert YDF_Unsupported(positionId_);

        // Validate that the asset has a yield bearing vault
        IERC4626 assetVault = DEPOSIT_MANAGER.getAssetConfiguration(IERC20(position.asset)).vault;
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

        // Calculate the yield
        uint256 yield = FullMath.mulDiv(
            endRate - lastSnapshotRate,
            position.remainingDeposit,
            10 ** assetVault.decimals()
        );

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
            CDPOSv1.Position memory position = CDPOS.getPosition(positionIds_[0]);
            asset = IERC20(position.asset);
            periodMonths = position.periodMonths;

            // Validate that the asset is supported
            if (!DEPOSIT_MANAGER.isConfiguredDeposit(asset, periodMonths))
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
            CDPOSv1.Position memory position = CDPOS.getPosition(positionIds_[0]);
            asset = IERC20(position.asset);
            periodMonths = position.periodMonths;

            // Validate that the asset is supported
            if (!DEPOSIT_MANAGER.isConfiguredDeposit(asset, periodMonths))
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
            if (previewYieldMinusFee > 0) {
                positionLastYieldConversionRate[positionId] = endRate;
            }
        }

        // Withdraw the yield from the deposit manager to the caller
        // This will validate that the deposits are still solvent
        DEPOSIT_MANAGER.claimYield(asset, msg.sender, yieldMinusFee);
        // Claim the yield fee
        DEPOSIT_MANAGER.claimYield(asset, address(TRSRY), yieldFee);

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
            IERC4626 vault = DEPOSIT_MANAGER.getAssetConfiguration(assets[i]).vault;

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
}
