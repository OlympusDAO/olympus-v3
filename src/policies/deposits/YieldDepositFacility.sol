// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.20;

// Libraries
import {FullMath} from "src/libraries/FullMath.sol";
import {TimestampLinkedList} from "src/libraries/TimestampLinkedList.sol";

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
    using TimestampLinkedList for TimestampLinkedList.List;
    // ========== STATE VARIABLES ========== //

    /// @notice The yield fee
    uint16 internal _yieldFee;

    /// @notice Mapping between a position id and the timestamp of the last yield claim
    /// @dev    This is used to calculate the yield since the last claim. The initial value should be set at the time of minting.
    mapping(uint256 positionId => uint48 lastYieldClaimTimestamp)
        public positionLastYieldClaimTimestamp;

    /// @notice Mapping between vault address and timestamp to snapshot data
    /// @dev    This is used to store periodic snapshots of conversion rates for each vault
    mapping(IERC4626 => mapping(uint48 => uint256)) public vaultRateSnapshots;

    /// @notice Mapping between vault address and linked list of snapshot timestamps
    /// @dev    This is used to efficiently find the most recent snapshot before a given timestamp
    mapping(IERC4626 => TimestampLinkedList.List) public vaultSnapshotTimestamps;

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
        Keycode deposKeycode = toKeycode("DEPOS");

        permissions = new Permissions[](2);
        permissions[0] = Permissions(deposKeycode, DEPOS.mint.selector);
        permissions[1] = Permissions(deposKeycode, DEPOS.split.selector);
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
                remainingDeposit: actualAmount,
                conversionPrice: type(uint256).max,
                expiry: uint48(block.timestamp + uint48(params_.periodMonths) * 30 days),
                wrapPosition: params_.wrapPosition,
                additionalData: ""
            })
        );

        // Take a snapshot at position creation to establish the starting rate
        uint48 snapshotTimestamp = uint48(block.timestamp);
        _takeSnapshot(params_.asset, snapshotTimestamp);

        // Set the initial yield claim timestamp to the snapshot timestamp
        positionLastYieldClaimTimestamp[positionId] = snapshotTimestamp;

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
        uint8 previousPeriodMonths_
    ) internal view returns (uint256 yieldMinusFee, uint256 yieldFee, uint48 newClaimTimestamp) {
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

        // Get the last snapshot rate directly (guaranteed to exist since we take snapshots on position creation)
        uint48 lastClaimTimestamp = positionLastYieldClaimTimestamp[positionId_];
        uint256 lastSnapshotRate = vaultRateSnapshots[assetVault][lastClaimTimestamp];

        // Invariant: lastSnapshotRate should be set
        if (lastSnapshotRate == 0)
            revert YDF_NoRateSnapshot(address(assetVault), lastClaimTimestamp);

        // Calculate the end rate (either current rate or rate at expiry)
        uint256 endRate;
        if (block.timestamp <= position.expiry) {
            // Deposit period hasn't finished, use current rate
            endRate = _getConversionRate(assetVault);
            newClaimTimestamp = uint48(block.timestamp);

            // Ensure we're not claiming from before our last claim
            if (newClaimTimestamp <= lastClaimTimestamp) {
                // No yield available - end snapshot is same or earlier than start
                return (0, 0, lastClaimTimestamp);
            }
        } else {
            // Deposit period has finished, find the most recent rate at or before expiry
            uint48 endSnapshotTimestamp = _findLastSnapshotBefore(assetVault, position.expiry);
            if (endSnapshotTimestamp == 0) {
                // No end snapshot available, return 0 yield
                return (0, 0, lastClaimTimestamp);
            }

            // Ensure we're not claiming from before our last claim
            if (endSnapshotTimestamp <= lastClaimTimestamp) {
                // No yield available - end snapshot is same or earlier than start
                return (0, 0, lastClaimTimestamp);
            }

            endRate = vaultRateSnapshots[assetVault][endSnapshotTimestamp];
            newClaimTimestamp = endSnapshotTimestamp;

            // Invariant: endRate should be set
            if (endRate == 0) revert YDF_NoRateSnapshot(address(assetVault), endSnapshotTimestamp);
        }

        // Calculate the number of shares for the position at the last snapshot rate
        uint256 lastShares = FullMath.mulDiv(
            position.remainingDeposit, // assets
            10 ** assetVault.decimals(), // decimals
            lastSnapshotRate + 1 // assets per share, increased by 1 wei to account for rounding errors and prevent insolvency
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

        return (yieldMinusFee, yieldFee, newClaimTimestamp);
    }

    /// @inheritdoc IYieldDepositFacility
    /// @dev        Yield is calculated in the following manner:
    /// @dev        - If before or at expiry: it will get the current vault rate
    /// @dev        - If after expiry: it will get the last vault rate before or equal to the expiry timestamp
    /// @dev        - The current value is calculated as: share quantity at previous claim * vault rate
    /// @dev        - The yield is calculated as: current value - original deposit
    /// @dev
    /// @dev        Notes:
    /// @dev        - For asset vaults that are not monotonically increasing in value, the yield received by different depositors may differ based on the time of claim.
    /// @dev        - Claiming yield multiple times during a deposit period will likely result in a lower yield than claiming once at/after expiry.
    /// @dev        - The actual amount of yield that can be claimed via `claimYield()` can differ by a few wei, due to rounding behaviour in ERC4626 vaults.
    /// @dev
    /// @dev        This function will revert if:
    /// @dev        - The contract is not enabled
    /// @dev        - The asset in the positions is not supported
    /// @dev        - `account_` is not the owner of all of the positions
    /// @dev        - Any of the positions have a different asset and deposit period combination
    /// @dev        - The position was not created by this contract
    /// @dev        - The asset does not have a vault configured
    /// @dev        - There is no snapshot for the asset at the last yield claim timestamp
    function previewClaimYield(
        address account_,
        uint256[] memory positionIds_
    ) external view onlyEnabled returns (uint256 yieldMinusFee, IERC20 asset) {
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
                periodMonths
            );
            yieldMinusFee += previewYieldMinusFee;
        }

        return (yieldMinusFee, asset);
    }

    /// @inheritdoc IYieldDepositFacility
    /// @dev        See also {previewClaimYield} for more details on the yield calculation.
    function claimYield(
        uint256[] memory positionIds_
    ) external onlyEnabled returns (uint256 yieldMinusFee) {
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
                uint48 newClaimTimestamp
            ) = _previewClaimYield(msg.sender, positionId, address(asset), periodMonths);

            yieldMinusFee += previewYieldMinusFee;
            yieldFee += previewYieldFee;

            // If there is yield, update the last yield claim timestamp
            if (previewYieldMinusFee > 0) {
                positionLastYieldClaimTimestamp[positionId] = newClaimTimestamp;

                // Ensure there is a snapshot for the new claim timestamp
                _takeSnapshot(asset, newClaimTimestamp);
            }
        }

        uint256 actualYieldMinusFee;
        if (yieldMinusFee > 0) {
            // Withdraw the yield from the deposit manager to this contract
            // This will validate that the deposits are still solvent
            // This is also done as one call, to avoid off-by-one rounding errors with ERC4626
            uint256 actualAmount = DEPOSIT_MANAGER.claimYield(
                asset,
                address(this),
                yieldMinusFee + yieldFee
            );
            // Transfer the yield fee to the treasury
            if (yieldFee > 0) IERC20(asset).transfer(address(TRSRY), yieldFee);
            // Transfer the yield (minus fee) to the caller
            // This uses the actual amount, since that may differ from what was calculated earlier
            actualYieldMinusFee = actualAmount - yieldFee;
            IERC20(asset).transfer(msg.sender, actualYieldMinusFee);
        }

        // Emit event
        emit YieldClaimed(address(asset), msg.sender, actualYieldMinusFee);

        return actualYieldMinusFee;
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

    // ========== POSITION MANAGEMENT ========== //

    function _split(
        uint256 oldPositionId_,
        uint256 newPositionId_,
        uint256
    ) internal virtual override {
        // Copy the last yield claim timestamp from the original position to the new one
        // This prevents the new position from claiming yield from before it was created
        positionLastYieldClaimTimestamp[newPositionId_] = positionLastYieldClaimTimestamp[
            oldPositionId_
        ];
    }

    // ========== HELPER FUNCTIONS ========== //

    /// @notice Get the conversion rate between a vault and underlying asset
    function _getConversionRate(IERC4626 vault_) internal view returns (uint256) {
        return vault_.convertToAssets(10 ** vault_.decimals());
    }

    /// @notice Find the most recent snapshot timestamp at or before the target timestamp
    /// @param vault_ The vault to search snapshots for
    /// @param target_ The target timestamp
    /// @return The most recent snapshot timestamp <= target_, or 0 if none found
    function _findLastSnapshotBefore(
        IERC4626 vault_,
        uint48 target_
    ) internal view returns (uint48) {
        return vaultSnapshotTimestamps[vault_].findLastBefore(target_);
    }

    /// @notice Take a snapshot of the vault conversion rate for an asset
    /// @param asset_ The asset to take a snapshot for
    /// @param timestamp_ The timestamp for the snapshot
    /// @return The conversion rate that was stored, or 0 if no vault configured
    function _takeSnapshot(IERC20 asset_, uint48 timestamp_) internal returns (uint256) {
        IERC4626 vault = IERC4626(DEPOSIT_MANAGER.getAssetConfiguration(asset_).vault);

        // Skip if the vault is not set
        if (address(vault) == address(0)) return 0;

        // Even if the snapshot already exists, we still take a new one
        // This is to ensure that the yield calculation is always accurate, regardless of the order in the block
        uint256 rate = _getConversionRate(vault);
        vaultRateSnapshots[vault][timestamp_] = rate;
        vaultSnapshotTimestamps[vault].add(timestamp_);
        emit RateSnapshotTaken(address(vault), timestamp_, rate);

        return rate;
    }

    // ========== PERIODIC TASK ========== //

    /// @notice Stores periodic snapshots of the conversion rate for all supported vaults
    /// @dev    This function is called by the Heart contract periodically
    /// @dev    Uses the current block timestamp for the snapshot
    /// @dev    No cleanup is performed as snapshots are needed for active deposits
    function execute() external override onlyRole(HEART_ROLE) {
        // If the contract is disabled, do not take any snapshots
        if (!isEnabled) return;

        // Use current block timestamp
        uint48 snapshotTimestamp = uint48(block.timestamp);

        // Get all supported assets
        IERC20[] memory assets = DEPOSIT_MANAGER.getConfiguredAssets();

        // Store snapshots for each asset
        for (uint256 i; i < assets.length; ++i) {
            _takeSnapshot(assets[i], snapshotTimestamp);
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
