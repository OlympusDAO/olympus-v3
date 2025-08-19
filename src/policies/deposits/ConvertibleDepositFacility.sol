// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.20;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IConvertibleDepositFacility} from "src/policies/interfaces/deposits/IConvertibleDepositFacility.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";
import {IDepositPositionManager} from "src/modules/DEPOS/IDepositPositionManager.sol";
import {IPeriodicTask} from "src/interfaces/IPeriodicTask.sol";

// Libraries
import {FullMath} from "src/libraries/FullMath.sol";

// Bophades
import {Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {DEPOSv1} from "src/modules/DEPOS/DEPOS.v1.sol";
import {HEART_ROLE} from "src/policies/utils/RoleDefinitions.sol";
import {BaseDepositFacility} from "src/policies/deposits/BaseDepositFacility.sol";

/// @title  Convertible Deposit Facility
/// @notice Implementation of the {IConvertibleDepositFacility} interface
///         It is a general-purpose contract that can be used to create, mint, convert, redeem, and reclaim receipt tokens
contract ConvertibleDepositFacility is
    BaseDepositFacility,
    IConvertibleDepositFacility,
    IPeriodicTask
{
    // ========== CONSTANTS ========== //

    bytes32 public constant ROLE_AUCTIONEER = "cd_auctioneer";

    // ========== STATE VARIABLES ========== //

    /// @notice The MINTR module.
    MINTRv1 public MINTR;

    uint256 internal constant _OHM_SCALE = 1e9;

    // ========== SETUP ========== //

    constructor(
        address kernel_,
        address depositManager_
    ) BaseDepositFacility(kernel_, depositManager_) {
        // Disabled by default by PolicyEnabler
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](4);
        dependencies[0] = toKeycode("TRSRY");
        dependencies[1] = toKeycode("MINTR");
        dependencies[2] = toKeycode("ROLES");
        dependencies[3] = toKeycode("DEPOS");

        TRSRY = TRSRYv1(getModuleAddress(dependencies[0]));
        MINTR = MINTRv1(getModuleAddress(dependencies[1]));
        ROLES = ROLESv1(getModuleAddress(dependencies[2]));
        DEPOS = DEPOSv1(getModuleAddress(dependencies[3]));

        // Validate that the OHM scale is the same
        uint256 ohmScale = 10 ** uint256(MINTR.ohm().decimals());
        if (ohmScale != _OHM_SCALE) revert CDF_InvalidArgs("OHM decimals");
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {
        Keycode mintrKeycode = toKeycode("MINTR");
        Keycode deposKeycode = toKeycode("DEPOS");

        permissions = new Permissions[](6);
        permissions[0] = Permissions(mintrKeycode, MINTR.increaseMintApproval.selector);
        permissions[1] = Permissions(mintrKeycode, MINTR.mintOhm.selector);
        permissions[2] = Permissions(mintrKeycode, MINTR.decreaseMintApproval.selector);
        permissions[3] = Permissions(deposKeycode, DEPOS.mint.selector);
        permissions[4] = Permissions(deposKeycode, DEPOS.setRemainingDeposit.selector);
        permissions[5] = Permissions(deposKeycode, DEPOS.split.selector);
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
        CreatePositionParams calldata params_
    )
        external
        onlyRole(ROLE_AUCTIONEER)
        nonReentrant
        onlyEnabled
        returns (uint256 positionId, uint256 receiptTokenId, uint256 actualAmount)
    {
        // Deposit the asset into the deposit manager
        // This will validate that the asset is supported, and mint the receipt token
        (receiptTokenId, actualAmount) = DEPOSIT_MANAGER.deposit(
            IDepositManager.DepositParams({
                asset: params_.asset,
                depositPeriod: params_.periodMonths,
                depositor: params_.depositor,
                amount: params_.amount,
                shouldWrap: params_.wrapReceipt
            })
        );

        // Create a new position in the DEPOS module
        positionId = DEPOS.mint(
            IDepositPositionManager.MintParams({
                owner: params_.depositor,
                asset: address(params_.asset),
                periodMonths: params_.periodMonths,
                remainingDeposit: actualAmount,
                conversionPrice: params_.conversionPrice,
                expiry: uint48(block.timestamp + uint48(params_.periodMonths) * 30 days),
                wrapPosition: params_.wrapPosition,
                additionalData: ""
            })
        );

        // Emit an event
        emit CreatedDeposit(
            address(params_.asset),
            params_.depositor,
            positionId,
            params_.periodMonths,
            actualAmount
        );

        return (positionId, receiptTokenId, actualAmount);
    }

    /// @inheritdoc IConvertibleDepositFacility
    function deposit(
        IERC20 asset_,
        uint8 periodMonths_,
        uint256 amount_,
        bool wrapReceipt_
    ) external nonReentrant onlyEnabled returns (uint256 receiptTokenId, uint256 actualAmount) {
        // Deposit the asset into the deposit manager and get the receipt token back
        // This will revert if the asset is not supported
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

    // ========== CONVERTIBLE DEPOSIT ACTIONS ========== //

    /// @notice Determines the conversion output
    ///
    /// @param  depositor_            The depositor of the position
    /// @param  positionId_           The ID of the position
    /// @param  amount_               The amount of receipt tokens to convert
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
        DEPOSv1.Position memory position = DEPOS.getPosition(positionId_);

        // Validate that the depositor is the owner of the position
        if (position.owner != depositor_) revert CDF_NotOwner(positionId_);

        // Validate that the position has not expired
        if (block.timestamp >= position.expiry) revert CDF_PositionExpired(positionId_);

        // Validate that the deposit amount is not greater than the remaining deposit
        if (amount_ > position.remainingDeposit) revert CDF_InvalidAmount(positionId_, amount_);

        // Validate that the position supports conversion
        if (position.operator != address(this)) revert CDF_Unsupported(positionId_);

        // Set the asset, or validate
        currentAsset = position.asset;
        currentPeriodMonths = position.periodMonths;
        if (previousAsset_ == address(0)) {
            // Validate that the asset is supported
            if (
                !DEPOSIT_MANAGER
                    .isAssetPeriod(IERC20(currentAsset), currentPeriodMonths, address(this))
                    .isConfigured
            ) revert CDF_InvalidToken(positionId_, currentAsset, currentPeriodMonths);
        } else if (previousAsset_ != currentAsset || previousPeriodMonths_ != currentPeriodMonths) {
            revert CDF_InvalidArgs("multiple assets");
        }

        // The deposit and receipt token have the same decimals, so either can be used
        convertedTokenOut = FullMath.mulDiv(
            amount_, // Scale: deposit token
            _OHM_SCALE,
            position.conversionPrice // Scale: deposit token
        );

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
    ) external view onlyEnabled returns (uint256 receiptTokenIn, uint256 convertedTokenOut) {
        // Make sure the lengths of the arrays are the same
        if (positionIds_.length != amounts_.length) revert CDF_InvalidArgs("array length");

        address asset;
        uint8 periodMonths;
        for (uint256 i; i < positionIds_.length; ++i) {
            uint256 positionId = positionIds_[i];
            uint256 amount = amounts_[i];

            receiptTokenIn += amount;

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
        if (receiptTokenIn == 0) revert CDF_InvalidArgs("amount");

        // If the converted amount is 0, revert
        if (convertedTokenOut == 0) revert CDF_InvalidArgs("converted amount");

        return (receiptTokenIn, convertedTokenOut);
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
        uint256[] memory amounts_,
        bool wrappedReceipt_
    )
        external
        nonReentrant
        onlyEnabled
        returns (uint256 receiptTokenIn, uint256 convertedTokenOut)
    {
        // Make sure the lengths of the arrays are the same
        if (positionIds_.length != amounts_.length) revert CDF_InvalidArgs("array length");

        address asset;
        uint8 periodMonths;
        for (uint256 i; i < positionIds_.length; ++i) {
            uint256 positionId = positionIds_[i];
            uint256 depositAmount = amounts_[i];

            receiptTokenIn += depositAmount;

            (
                uint256 previewConvertOut,
                address currentAsset,
                uint8 currentPeriodMonths
            ) = _previewConvert(msg.sender, positionId, depositAmount, asset, periodMonths);
            convertedTokenOut += previewConvertOut;
            asset = currentAsset;
            periodMonths = currentPeriodMonths;

            // Update the position
            DEPOS.setRemainingDeposit(
                positionId,
                DEPOS.getPosition(positionId).remainingDeposit - depositAmount
            );
        }

        // Withdraw the underlying asset and deposit into the treasury
        // The actual amount withdrawn may differ from `receiptTokenIn` by a few wei,
        // but will not materially affect the amount of OHM that is minted when converting.
        // Additionally, given that the amount is composed of multiple positions
        // (each with potentially different conversion prices), it is not trivial to
        // re-calculate `convertedTokenOut` with the actual amount.
        DEPOSIT_MANAGER.withdraw(
            IDepositManager.WithdrawParams({
                asset: IERC20(asset),
                depositPeriod: periodMonths,
                depositor: msg.sender,
                recipient: address(TRSRY),
                amount: receiptTokenIn,
                isWrapped: wrappedReceipt_
            })
        );

        // Mint OHM to the owner/caller
        // No need to check if `convertedTokenOut` is 0, as MINTR will revert
        MINTR.increaseMintApproval(address(this), convertedTokenOut);
        MINTR.mintOhm(msg.sender, convertedTokenOut);

        // Emit event
        emit ConvertedDeposit(asset, msg.sender, periodMonths, receiptTokenIn, convertedTokenOut);

        return (receiptTokenIn, convertedTokenOut);
    }

    // ========== YIELD ========== //

    /// @inheritdoc IConvertibleDepositFacility
    /// @dev        This returns the value from DepositManager.maxClaimYield(), which is a theoretical value.
    function previewClaimYield(IERC20 asset_) public view returns (uint256 yieldAssets) {
        yieldAssets = DEPOSIT_MANAGER.maxClaimYield(asset_, address(this));
        return yieldAssets;
    }

    /// @inheritdoc IConvertibleDepositFacility
    function claimYield(IERC20 asset_) public returns (uint256) {
        // Determine the yield
        uint256 previewedYield = previewClaimYield(asset_);

        return claimYield(asset_, previewedYield);
    }

    /// @inheritdoc IConvertibleDepositFacility
    /// @dev        This function mainly serves as a backup for claiming protocol yield, in case the max yield cannot be claimed.
    function claimYield(IERC20 asset_, uint256 amount_) public returns (uint256) {
        // If disabled, don't do anything
        if (!isEnabled) return 0;

        // Skip if there is no yield to claim
        if (amount_ == 0) return 0;

        // Claim the yield
        // This will revert if the asset is not supported, or the receipt token becomes insolvent
        uint256 actualYield = DEPOSIT_MANAGER.claimYield(asset_, address(TRSRY), amount_);

        // Emit the event
        emit ClaimedYield(address(asset_), actualYield);

        return actualYield;
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

    // ========== PERIODIC TASKS ========== //

    /// @inheritdoc IPeriodicTask
    function execute() external onlyRole(HEART_ROLE) {
        // Don't do anything if disabled
        if (!isEnabled) return;

        try this.claimAllYield() {
            // Do nothing
        } catch {
            // This avoids the periodic task from failing loudly, as the claimAllYield function is not critical to the system
            revert CDF_ClaimAllYieldFailed();
        }
    }

    // ========== ERC165 ========== //

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(BaseDepositFacility, IPeriodicTask) returns (bool) {
        return
            interfaceId == type(IConvertibleDepositFacility).interfaceId ||
            interfaceId == type(IPeriodicTask).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
