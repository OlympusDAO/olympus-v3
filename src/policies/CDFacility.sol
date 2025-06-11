// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.20;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IConvertibleDepositFacility} from "src/policies/interfaces/IConvertibleDepositFacility.sol";
import {IDepositManager} from "src/policies/interfaces/IDepositManager.sol";

// Bophades
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/OlympusRoles.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {CDPOSv1} from "src/modules/CDPOS/CDPOS.v1.sol";
import {BaseDepositRedemptionVault} from "src/bases/BaseDepositRedemptionVault.sol";

/// @title  Convertible Deposit Facility
/// @notice Implementation of the {IConvertibleDepositFacility} interface
///         It is a general-purpose contract that can be used to create, mint, convert, redeem, and reclaim CD tokens
contract CDFacility is Policy, IConvertibleDepositFacility, BaseDepositRedemptionVault {
    // ========== CONSTANTS ========== //

    bytes32 public constant ROLE_AUCTIONEER = "cd_auctioneer";

    // ========== STATE VARIABLES ========== //

    /// @notice The MINTR module.
    MINTRv1 public MINTR;

    /// @notice The CDPOS module.
    CDPOSv1 public CDPOS;

    // ========== SETUP ========== //

    constructor(
        address kernel_,
        address tokenManager_
    ) Policy(Kernel(kernel_)) BaseDepositRedemptionVault(tokenManager_) {
        // Disabled by default by PolicyEnabler
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](5);
        dependencies[0] = toKeycode("TRSRY");
        dependencies[1] = toKeycode("MINTR");
        dependencies[2] = toKeycode("ROLES");
        dependencies[3] = toKeycode("CDPOS");

        TRSRY = TRSRYv1(getModuleAddress(dependencies[0]));
        MINTR = MINTRv1(getModuleAddress(dependencies[1]));
        ROLES = ROLESv1(getModuleAddress(dependencies[2]));
        CDPOS = CDPOSv1(getModuleAddress(dependencies[3]));
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {
        Keycode mintrKeycode = toKeycode("MINTR");
        Keycode cdposKeycode = toKeycode("CDPOS");

        permissions = new Permissions[](5);
        permissions[0] = Permissions(mintrKeycode, MINTR.increaseMintApproval.selector);
        permissions[1] = Permissions(mintrKeycode, MINTR.mintOhm.selector);
        permissions[2] = Permissions(mintrKeycode, MINTR.decreaseMintApproval.selector);
        permissions[3] = Permissions(cdposKeycode, CDPOS.mint.selector);
        permissions[4] = Permissions(cdposKeycode, CDPOS.update.selector);
    }

    function VERSION() external pure returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;

        return (major, minor);
    }

    // ========== MINT ========== //

    /// @inheritdoc IConvertibleDepositFacility
    /// @dev        This function reverts if:
    ///             - The caller does not have the ROLE_AUCTIONEER role
    ///             - The contract is not enabled
    ///             - The asset and period are not supported
    function createPosition(
        IERC20 asset_,
        uint8 periodMonths_,
        address depositor_,
        uint256 amount_,
        uint256 conversionPrice_,
        bool wrapPosition_,
        bool wrapReceipt_
    ) external onlyRole(ROLE_AUCTIONEER) nonReentrant onlyEnabled returns (uint256 positionId) {
        // Deposit the asset into the deposit manager
        // This will validate that the asset is supported, and mint the receipt token
        DEPOSIT_MANAGER.deposit(asset_, periodMonths_, depositor_, amount_, wrapReceipt_);

        // Create a new position in the CDPOS module
        positionId = CDPOS.mint(
            depositor_,
            address(asset_),
            periodMonths_,
            amount_,
            conversionPrice_,
            uint48(block.timestamp + periodMonths_ * 30 days),
            wrapPosition_
        );

        // Emit an event
        emit CreatedDeposit(address(asset_), depositor_, positionId, periodMonths_, amount_);
    }

    // ========== CONVERTIBLE DEPOSIT ACTIONS ========== //

    /// @notice Determines the conversion output
    ///
    /// @param  depositor_            The depositor of the position
    /// @param  positionId_           The ID of the position
    /// @param  amount_               The amount of CD tokens to convert
    /// @param  previousAsset_        Used to validate that the asset is the same across positions (zero if the first position)
    /// @param  previousPeriodMonths_ Used to validate that the period is the same across positions (0 if the first position)
    /// @return convertedTokenOut     The amount of converted tokens
    /// @return currentAsset          The asset of the current position
    /// @return currentPeriodMonths   The period of the current position
    function _previewConvert(
        address depositor_,
        uint256 positionId_,
        uint256 amount_,
        address previousAsset_,
        uint8 previousPeriodMonths_
    )
        internal
        view
        returns (uint256 convertedTokenOut, address currentAsset, uint8 currentPeriodMonths)
    {
        // Validate that the position is valid
        // This will revert if the position is not valid
        CDPOSv1.Position memory position = CDPOS.getPosition(positionId_);

        // Validate that the depositor is the owner of the position
        if (position.owner != depositor_) revert CDF_NotOwner(positionId_);

        // Validate that the position has not expired
        if (block.timestamp >= position.expiry) revert CDF_PositionExpired(positionId_);

        // Validate that the deposit amount is not greater than the remaining deposit
        if (amount_ > position.remainingDeposit) revert CDF_InvalidAmount(positionId_, amount_);

        // Validate that the position supports conversion
        if (position.conversionPrice == type(uint256).max) revert CDF_Unsupported(positionId_);

        // Set the asset, or validate
        currentAsset = position.asset;
        currentPeriodMonths = position.periodMonths;
        if (previousAsset_ == address(0)) {
            // Validate that the asset is supported
            if (!DEPOSIT_MANAGER.isDepositAsset(IERC20(currentAsset), currentPeriodMonths))
                revert CDF_InvalidToken(positionId_, currentAsset, currentPeriodMonths);
        } else if (previousAsset_ != currentAsset || previousPeriodMonths_ != currentPeriodMonths) {
            revert CDF_InvalidArgs("multiple assets");
        }

        // The deposit and CD token have the same decimals, so either can be used
        convertedTokenOut =
            (amount_ * (10 ** IERC20(currentAsset).decimals())) /
            position.conversionPrice;

        return (convertedTokenOut, currentAsset, currentPeriodMonths);
    }

    /// @inheritdoc IConvertibleDepositFacility
    /// @dev        This function reverts if:
    ///             - The contract is not enabled
    ///             - The length of the positionIds_ array does not match the length of the amounts_ array
    ///             - depositor_ is not the owner of all of the positions
    ///             - Any position is not valid
    ///             - Any position is not a supported asset
    ///             - Any position has a different asset or deposit period
    ///             - Any position has reached the conversion expiry
    ///             - Any conversion amount is greater than the remaining deposit
    ///             - The amount of deposits to convert is 0
    ///             - The converted amount is 0
    function previewConvert(
        address depositor_,
        uint256[] memory positionIds_,
        uint256[] memory amounts_
    ) external view onlyEnabled returns (uint256 cdTokenIn, uint256 convertedTokenOut) {
        // Make sure the lengths of the arrays are the same
        if (positionIds_.length != amounts_.length) revert CDF_InvalidArgs("array length");

        address asset;
        uint8 periodMonths;
        for (uint256 i; i < positionIds_.length; ++i) {
            uint256 positionId = positionIds_[i];
            uint256 amount = amounts_[i];

            cdTokenIn += amount;

            (
                uint256 previewConvertOut,
                address currentAsset,
                uint8 currentPeriodMonths
            ) = _previewConvert(depositor_, positionId, amount, asset, periodMonths);
            convertedTokenOut += previewConvertOut;
            asset = currentAsset;
            periodMonths = currentPeriodMonths;
        }

        // If the amount is 0, revert
        if (cdTokenIn == 0) revert CDF_InvalidArgs("amount");

        // If the converted amount is 0, revert
        if (convertedTokenOut == 0) revert CDF_InvalidArgs("converted amount");

        return (cdTokenIn, convertedTokenOut);
    }

    /// @inheritdoc IConvertibleDepositFacility
    /// @dev        This function reverts if:
    ///             - The contract is not enabled
    ///             - The length of the positionIds_ array does not match the length of the amounts_ array
    ///             - The caller is not the owner of all of the positions
    ///             - Any position is not valid
    ///             - Any position is not a supported asset
    ///             - Any position has a different asset or deposit period
    ///             - Any position has reached the conversion expiry
    ///             - Any position has a conversion amount greater than the remaining deposit
    ///             - The amount of deposits to convert is 0
    ///             - The converted amount is 0
    function convert(
        uint256[] memory positionIds_,
        uint256[] memory amounts_
    ) external nonReentrant onlyEnabled returns (uint256 cdTokenIn, uint256 convertedTokenOut) {
        // Make sure the lengths of the arrays are the same
        if (positionIds_.length != amounts_.length) revert CDF_InvalidArgs("array length");

        address asset;
        uint8 periodMonths;
        for (uint256 i; i < positionIds_.length; ++i) {
            uint256 positionId = positionIds_[i];
            uint256 depositAmount = amounts_[i];

            cdTokenIn += depositAmount;

            (
                uint256 previewConvertOut,
                address currentAsset,
                uint8 currentPeriodMonths
            ) = _previewConvert(msg.sender, positionId, depositAmount, asset, periodMonths);
            convertedTokenOut += previewConvertOut;
            asset = currentAsset;
            periodMonths = currentPeriodMonths;

            // Update the position
            CDPOS.update(
                positionId,
                CDPOS.getPosition(positionId).remainingDeposit - depositAmount
            );
        }

        // Withdraw the underlying asset and deposit into the treasury
        DEPOSIT_MANAGER.withdraw(
            IERC20(asset),
            periodMonths,
            msg.sender,
            address(TRSRY),
            cdTokenIn,
            false
        );

        // Mint OHM to the owner/caller
        // No need to check if `convertedTokenOut` is 0, as MINTR will revert
        MINTR.increaseMintApproval(address(this), convertedTokenOut);
        MINTR.mintOhm(msg.sender, convertedTokenOut);

        // Emit event
        emit ConvertedDeposit(asset, msg.sender, periodMonths, cdTokenIn, convertedTokenOut);

        return (cdTokenIn, convertedTokenOut);
    }

    // ========== YIELD ========== //

    /// @inheritdoc IConvertibleDepositFacility
    function previewClaimYield(IERC20 asset_) public view returns (uint256 yieldAssets) {
        // The yield is the difference between the quantity of deposits assets and shares (in terms of assets)
        uint256 depositedAssets = DEPOSIT_MANAGER.getOperatorAssets(asset_, address(this));
        (, uint256 depositedSharesInAssets) = DEPOSIT_MANAGER.getOperatorShares(
            asset_,
            address(this)
        );

        yieldAssets = depositedSharesInAssets - depositedAssets;

        return yieldAssets;
    }

    /// @inheritdoc IConvertibleDepositFacility
    function claimYield(IERC20 asset_) public returns (uint256 yieldAssets) {
        // Determine the yield
        yieldAssets = previewClaimYield(asset_);

        // Skip if there is no yield to claim
        if (yieldAssets == 0) return 0;

        // Claim the yield
        // This will revert if the asset is not supported, or the receipt token becomes insolvent
        DEPOSIT_MANAGER.claimYield(asset_, address(TRSRY), yieldAssets);

        // Emit the event
        emit ClaimedYield(address(asset_), yieldAssets);

        return yieldAssets;
    }

    /// @inheritdoc IConvertibleDepositFacility
    function claimAllYield() external {
        // Get the assets
        IERC20[] memory assets = DEPOSIT_MANAGER.getConfiguredAssets();

        // Iterate over the deposit assets
        for (uint256 i; i < assets.length; ++i) {
            // Claim the yield
            claimYield(assets[i]);
        }
    }

    // ========== VIEW FUNCTIONS ========== //

    /// @inheritdoc IConvertibleDepositFacility
    function convertedToken() external view returns (address) {
        return address(MINTR.ohm());
    }
}
