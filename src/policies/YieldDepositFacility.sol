// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

// Libraries
import {FullMath} from "src/libraries/FullMath.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

// Interfaces
import {IYieldDepositFacility} from "src/policies/interfaces/IYieldDepositFacility.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IConvertibleDepositERC20} from "src/modules/CDEPO/IConvertibleDepositERC20.sol";
import {IPeriodicTask} from "src/policies/interfaces/IPeriodicTask.sol";

// Bophades
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {CDEPOv1} from "src/modules/CDEPO/CDEPO.v1.sol";
import {CDPOSv1} from "src/modules/CDPOS/CDPOS.v1.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";

/// @title YieldDepositFacility
contract YieldDepositFacility is
    Policy,
    PolicyEnabler,
    ReentrancyGuard,
    IYieldDepositFacility,
    IPeriodicTask
{
    using SafeTransferLib for ERC20;

    // ========== STATE VARIABLES ========== //

    /// @notice The treasury module.
    TRSRYv1 public TRSRY;

    /// @notice The CDEPO module.
    CDEPOv1 public CDEPO;

    /// @notice The CDPOS module.
    CDPOSv1 public CDPOS;

    /// @notice The yield fee
    uint16 internal _yieldFee;

    /// @notice The yield fee denominator
    uint16 public constant ONE_HUNDRED_PERCENT = 100e2;

    /// @notice Mapping between a position id and the last conversion rate between a CD token's vault and underlying asset
    /// @dev    This is used to calculate the yield since the last claim. The initial value should be set at the time of minting.
    mapping(uint256 => uint256) public positionLastYieldConversionRate;

    /// @notice Mapping between vault address and timestamp to snapshot data
    /// @dev    This is used to store periodic snapshots of conversion rates for each vault
    mapping(IERC4626 => mapping(uint48 => uint256)) public vaultRateSnapshots;

    /// @notice The interval between snapshots in seconds
    uint48 private constant SNAPSHOT_INTERVAL = 8 hours;

    // ========== SETUP ========== //

    constructor(address kernel_) Policy(Kernel(kernel_)) {
        // Disabled by default by PolicyEnabler
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](4);
        dependencies[0] = toKeycode("ROLES");
        dependencies[1] = toKeycode("CDEPO");
        dependencies[2] = toKeycode("CDPOS");
        dependencies[3] = toKeycode("TRSRY");

        ROLES = ROLESv1(getModuleAddress(dependencies[0]));
        CDEPO = CDEPOv1(getModuleAddress(dependencies[1]));
        CDPOS = CDPOSv1(getModuleAddress(dependencies[2]));
        TRSRY = TRSRYv1(getModuleAddress(dependencies[3]));
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {
        Keycode cdepoKeycode = toKeycode("CDEPO");
        Keycode cdposKeycode = toKeycode("CDPOS");

        permissions = new Permissions[](3);
        permissions[0] = Permissions(cdepoKeycode, CDEPO.create.selector);
        permissions[1] = Permissions(cdepoKeycode, CDEPO.withdraw.selector);
        permissions[2] = Permissions(cdposKeycode, CDPOS.mint.selector);
    }

    function VERSION() external pure returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;

        return (major, minor);
    }

    // ========== MINT ========== //

    /// @inheritdoc IYieldDepositFacility
    /// @dev        This function reverts if:
    ///             - The contract is not enabled
    ///             - The CD token is not supported
    function mint(
        IConvertibleDepositERC20 cdToken_,
        uint256 amount_,
        bool wrap_
    ) external nonReentrant onlyEnabled returns (uint256 positionId) {
        // Mint the CD token to the account
        CDEPO.mintFor(cdToken_, msg.sender, amount_);

        // Create a new term record in the CDPOS module
        positionId = CDPOS.mint(
            msg.sender, // owner
            address(cdToken_), // CD token
            amount_, // amount
            type(uint256).max, // conversion price of max to indicate no conversion price
            uint48(block.timestamp + cdToken_.periodMonths() * 30 days), // expiry
            wrap_ // wrap
        );

        // Set the initial yield conversion rate
        positionLastYieldConversionRate[positionId] = _getConversionRate(cdToken_.vault());

        // Emit an event
        emit CreatedDeposit(address(cdToken_.asset()), msg.sender, positionId, amount_);
    }

    // ========== YIELD FUNCTIONS ========== //

    function _previewHarvest(
        address account_,
        uint256 positionId_,
        address previousCDToken_,
        uint48 timestampHint_
    )
        internal
        view
        returns (uint256 yieldMinusFee, uint256 yieldFee, address currentCDToken, uint256 endRate)
    {
        // Validate that the position is valid
        // This will revert if the position is not valid
        CDPOSv1.Position memory position = CDPOS.getPosition(positionId_);

        // Validate that the caller is the owner of the position
        if (position.owner != account_) revert YDF_NotOwner(positionId_);

        // Validate that the position is not convertible
        if (CDPOS.isConvertible(positionId_)) revert YDF_Unsupported(positionId_);

        // Set the CD token, or validate
        currentCDToken = position.convertibleDepositToken;
        if (previousCDToken_ == address(0)) {
            // Validate that the CD token is supported
            if (!CDEPO.isConvertibleDepositToken(currentCDToken))
                revert YDF_InvalidToken(positionId_, currentCDToken);
        } else if (previousCDToken_ != currentCDToken) {
            revert YDF_InvalidArgs("multiple CD tokens");
        }

        // Get the vault and last snapshot rate
        IERC4626 vault = IConvertibleDepositERC20(currentCDToken).vault();
        uint256 lastSnapshotRate = positionLastYieldConversionRate[positionId_];

        // Calculate the end rate (either current rate or rate at expiry)
        if (block.timestamp <= position.conversionExpiry) {
            // Deposit period hasn't finished, use current rate
            endRate = _getConversionRate(vault);
        } else {
            // Deposit period has finished, find the rate at expiry
            // Validate timestamp hint if provided
            uint48 snapshotTimestamp = position.conversionExpiry;
            if (timestampHint_ > 0) {
                if (timestampHint_ > position.conversionExpiry) {
                    revert YDF_InvalidArgs("timestamp hint");
                }
                snapshotTimestamp = timestampHint_;
            }
            uint48 snapshotKey = _getSnapshotKey(snapshotTimestamp);

            // Get the rate at the snapshot key
            uint256 expiryRate = vaultRateSnapshots[vault][snapshotKey];
            if (expiryRate == 0) {
                revert YDF_NoSnapshotAvailable(address(vault), snapshotKey);
            }

            endRate = expiryRate;
        }

        // Calculate the yield
        uint256 yield = FullMath.mulDiv(
            endRate - lastSnapshotRate,
            position.remainingDeposit,
            10 ** vault.decimals()
        );

        // Calculate fees
        yieldFee = FullMath.mulDiv(yield, _yieldFee, ONE_HUNDRED_PERCENT);
        yieldMinusFee = yield - yieldFee;

        return (yieldMinusFee, yieldFee, currentCDToken, endRate);
    }

    /// @inheritdoc IYieldDepositFacility
    function previewHarvest(
        address account_,
        uint256[] memory positionIds_
    ) external view onlyEnabled returns (uint256 yieldMinusFee, IERC20 asset) {
        return previewHarvest(account_, positionIds_, new uint48[](positionIds_.length));
    }

    /// @inheritdoc IYieldDepositFacility
    function previewHarvest(
        address account_,
        uint256[] memory positionIds_,
        uint48[] memory timestampHints_
    ) public view onlyEnabled returns (uint256 yieldMinusFee, IERC20 asset) {
        if (positionIds_.length != timestampHints_.length) {
            revert YDF_InvalidArgs("array length mismatch");
        }

        address cdToken;
        for (uint256 i; i < positionIds_.length; ++i) {
            uint256 positionId = positionIds_[i];

            (uint256 previewYieldMinusFee, , address currentCDToken, ) = _previewHarvest(
                account_,
                positionId,
                cdToken,
                timestampHints_[i]
            );
            yieldMinusFee += previewYieldMinusFee;
            cdToken = currentCDToken;
        }

        return (yieldMinusFee, IConvertibleDepositERC20(cdToken).asset());
    }

    /// @inheritdoc IYieldDepositFacility
    function harvest(uint256[] memory positionIds_) external returns (uint256 yieldMinusFee) {
        return harvest(positionIds_, new uint48[](positionIds_.length));
    }

    /// @inheritdoc IYieldDepositFacility
    function harvest(
        uint256[] memory positionIds_,
        uint48[] memory timestampHints_
    ) public returns (uint256 yieldMinusFee) {
        if (positionIds_.length != timestampHints_.length) {
            revert YDF_InvalidArgs("array length mismatch");
        }

        IConvertibleDepositERC20 cdToken;
        uint256 yieldFee;
        for (uint256 i; i < positionIds_.length; ++i) {
            uint256 positionId = positionIds_[i];

            (
                uint256 previewYieldMinusFee,
                uint256 previewYieldFee,
                address currentCDToken,
                uint256 endRate
            ) = _previewHarvest(msg.sender, positionId, address(cdToken), timestampHints_[i]);

            yieldMinusFee += previewYieldMinusFee;
            yieldFee += previewYieldFee;
            cdToken = IConvertibleDepositERC20(currentCDToken);

            // If there is yield, update the last yield conversion rate
            if (previewYieldMinusFee > 0) {
                positionLastYieldConversionRate[positionId] = endRate;
            }
        }

        // Withdraw the yield from the CDEPO module in the form of the underlying asset
        CDEPO.withdraw(cdToken, yieldMinusFee + yieldFee);

        // Transfer the yield to the caller
        // msg.sender is ok here as _previewHarvest validates that the caller is the owner of the position
        ERC20 asset = ERC20(address(cdToken.asset()));
        asset.safeTransfer(msg.sender, yieldMinusFee);

        // Transfer the yield fee to the treasury
        asset.safeTransfer(address(TRSRY), yieldFee);

        // Emit event
        emit Harvest(address(cdToken.asset()), msg.sender, yieldMinusFee);

        return yieldMinusFee;
    }

    // ========== ADMIN FUNCTIONS ========== //

    /// @inheritdoc IYieldDepositFacility
    /// @dev        This function reverts if:
    ///             - The contract is not enabled
    ///             - The caller is not an admin
    ///             - CDEPO reverts
    function create(
        IERC4626 vault_,
        uint8 periodMonths_,
        uint16 reclaimRate_
    ) external onlyEnabled onlyAdminRole returns (IConvertibleDepositERC20 cdToken) {
        // Create a new convertible deposit token
        cdToken = CDEPO.create(vault_, periodMonths_, reclaimRate_);

        return cdToken;
    }

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

        // Get all supported vault tokens
        IERC4626[] memory vaultTokens = CDEPO.getVaultTokens();

        // Store snapshots for each vault
        for (uint256 i; i < vaultTokens.length; ++i) {
            IERC4626 vault = vaultTokens[i];

            // Only store if we haven't stored for this interval
            if (vaultRateSnapshots[vault][snapshotKey] == 0) {
                uint256 rate = _getConversionRate(vault);
                vaultRateSnapshots[vault][snapshotKey] = rate;
                emit RateSnapshotTaken(address(vault), snapshotKey, rate);
            }
        }
    }
}
