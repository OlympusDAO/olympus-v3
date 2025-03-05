// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";

import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";

import {IConvertibleDepositFacility} from "src/policies/interfaces/IConvertibleDepositFacility.sol";
import {RolesConsumer, ROLESv1} from "src/modules/ROLES/OlympusRoles.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {CDEPOv1} from "src/modules/CDEPO/CDEPO.v1.sol";
import {CDPOSv1} from "src/modules/CDPOS/CDPOS.v1.sol";

import {FullMath} from "src/libraries/FullMath.sol";

contract CDFacility is Policy, RolesConsumer, IConvertibleDepositFacility, ReentrancyGuard {
    using FullMath for uint256;

    // ========== STATE VARIABLES ========== //

    // Constants

    /// @notice The scale of the convertible deposit token
    /// @dev    This will typically be 10 ** decimals, and is set by the `configureDependencies()` function
    uint256 public SCALE;

    // Modules
    TRSRYv1 public TRSRY;
    MINTRv1 public MINTR;
    CDEPOv1 public CDEPO;
    CDPOSv1 public CDPOS;

    /// @notice Whether the contract functionality has been activated
    bool public locallyActive;

    bytes32 public constant ROLE_EMERGENCY_SHUTDOWN = "emergency_shutdown";

    bytes32 public constant ROLE_ADMIN = "cd_admin";

    bytes32 public constant ROLE_AUCTIONEER = "cd_auctioneer";

    // ========== ERRORS ========== //

    /// @notice An error that is thrown when the parameters are invalid
    error CDFacility_InvalidParams(string reason);

    // ========== SETUP ========== //

    constructor(address kernel_) Policy(Kernel(kernel_)) {
        // Disable functionality until initialized
        locallyActive = false;
    }

    /// @inheritdoc Policy
    function configureDependencies() external override returns (Keycode[] memory dependencies) {
        dependencies = new Keycode[](5);
        dependencies[0] = toKeycode("TRSRY");
        dependencies[1] = toKeycode("MINTR");
        dependencies[2] = toKeycode("ROLES");
        dependencies[3] = toKeycode("CDEPO");
        dependencies[4] = toKeycode("CDPOS");

        TRSRY = TRSRYv1(getModuleAddress(dependencies[0]));
        MINTR = MINTRv1(getModuleAddress(dependencies[1]));
        ROLES = ROLESv1(getModuleAddress(dependencies[2]));
        CDEPO = CDEPOv1(getModuleAddress(dependencies[3]));
        CDPOS = CDPOSv1(getModuleAddress(dependencies[4]));

        SCALE = 10 ** CDEPO.decimals();
    }

    /// @inheritdoc Policy
    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {
        Keycode mintrKeycode = toKeycode("MINTR");
        Keycode cdepoKeycode = toKeycode("CDEPO");
        Keycode cdposKeycode = toKeycode("CDPOS");

        permissions = new Permissions[](8);
        permissions[0] = Permissions(mintrKeycode, MINTR.increaseMintApproval.selector);
        permissions[1] = Permissions(mintrKeycode, MINTR.mintOhm.selector);
        permissions[2] = Permissions(mintrKeycode, MINTR.decreaseMintApproval.selector);
        permissions[3] = Permissions(cdepoKeycode, CDEPO.redeemFor.selector);
        permissions[4] = Permissions(cdepoKeycode, CDEPO.reclaimFor.selector);
        permissions[5] = Permissions(cdepoKeycode, CDEPO.setReclaimRate.selector);
        permissions[6] = Permissions(cdposKeycode, CDPOS.create.selector);
        permissions[7] = Permissions(cdposKeycode, CDPOS.update.selector);
    }

    function VERSION() external pure returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;

        return (major, minor);
    }

    // ========== CONVERTIBLE DEPOSIT ACTIONS ========== //

    /// @inheritdoc IConvertibleDepositFacility
    /// @dev        This function reverts if:
    ///             - The caller does not have the ROLE_AUCTIONEER role
    ///             - The contract is not active
    function create(
        address account_,
        uint256 amount_,
        uint256 conversionPrice_,
        uint48 conversionExpiry_,
        uint48 redemptionExpiry_,
        bool wrap_
    ) external onlyRole(ROLE_AUCTIONEER) nonReentrant onlyActive returns (uint256 positionId) {
        // Mint the CD token to the account
        // This will also transfer the reserve token
        CDEPO.mintFor(account_, amount_);

        // Create a new term record in the CDPOS module
        positionId = CDPOS.create(
            account_,
            address(CDEPO),
            amount_,
            conversionPrice_,
            conversionExpiry_,
            redemptionExpiry_,
            wrap_
        );

        // Calculate the expected OHM amount
        uint256 expectedOhmAmount = (amount_ * SCALE) / conversionPrice_;

        // Pre-emptively increase the OHM mint approval
        MINTR.increaseMintApproval(address(this), expectedOhmAmount);

        // Emit an event
        emit CreatedDeposit(account_, positionId, amount_);
    }

    function _previewConvert(
        address account_,
        uint256 positionId_,
        uint256 amount_
    ) internal view returns (uint256 convertedTokenOut) {
        // Validate that the position is valid
        // This will revert if the position is not valid
        CDPOSv1.Position memory position = CDPOS.getPosition(positionId_);

        // Validate that the caller is the owner of the position
        if (position.owner != account_) revert CDF_NotOwner(positionId_);

        // Validate that the position is CDEPO
        if (position.convertibleDepositToken != address(CDEPO))
            revert CDF_InvalidToken(positionId_, position.convertibleDepositToken);

        // Validate that the position has not expired
        if (block.timestamp >= position.conversionExpiry) revert CDF_PositionExpired(positionId_);

        // Validate that the deposit amount is not greater than the remaining deposit
        if (amount_ > position.remainingDeposit) revert CDF_InvalidAmount(positionId_, amount_);

        convertedTokenOut = (amount_ * SCALE) / position.conversionPrice;

        return convertedTokenOut;
    }

    /// @inheritdoc IConvertibleDepositFacility
    /// @dev        This function reverts if:
    ///             - The contract is not active
    ///             - The length of the positionIds_ array does not match the length of the amounts_ array
    ///             - account_ is not the owner of all of the positions
    ///             - The position is not valid
    ///             - The position is not CDEPO
    ///             - The position has expired
    ///             - The deposit amount is greater than the remaining deposit
    ///             - The deposit amount is 0
    ///             - The converted amount is 0
    function previewConvert(
        address account_,
        uint256[] memory positionIds_,
        uint256[] memory amounts_
    )
        external
        view
        onlyActive
        returns (uint256 cdTokenIn, uint256 convertedTokenOut, address cdTokenSpender)
    {
        // Make sure the lengths of the arrays are the same
        if (positionIds_.length != amounts_.length) revert CDF_InvalidArgs("array length");

        for (uint256 i; i < positionIds_.length; ++i) {
            uint256 positionId = positionIds_[i];
            uint256 amount = amounts_[i];
            cdTokenIn += amount;
            convertedTokenOut += _previewConvert(account_, positionId, amount);
        }

        // If the amount is 0, revert
        if (cdTokenIn == 0) revert CDF_InvalidArgs("amount");

        // If the converted amount is 0, revert
        if (convertedTokenOut == 0) revert CDF_InvalidArgs("converted amount");

        return (cdTokenIn, convertedTokenOut, address(CDEPO));
    }

    /// @inheritdoc IConvertibleDepositFacility
    /// @dev        This function reverts if:
    ///             - The contract is not active
    ///             - The length of the positionIds_ array does not match the length of the amounts_ array
    ///             - The caller is not the owner of all of the positions
    ///             - The position is not valid
    ///             - The position is not CDEPO
    ///             - The position has expired
    ///             - The deposit amount is greater than the remaining deposit
    ///             - The deposit amount is 0
    ///             - The converted amount is 0
    function convert(
        uint256[] memory positionIds_,
        uint256[] memory amounts_
    ) external nonReentrant onlyActive returns (uint256 cdTokenIn, uint256 convertedTokenOut) {
        // Make sure the lengths of the arrays are the same
        if (positionIds_.length != amounts_.length) revert CDF_InvalidArgs("array length");

        // Iterate over all positions
        for (uint256 i; i < positionIds_.length; ++i) {
            uint256 positionId = positionIds_[i];
            uint256 depositAmount = amounts_[i];

            cdTokenIn += depositAmount;
            convertedTokenOut += _previewConvert(msg.sender, positionId, depositAmount);

            // Update the position
            CDPOS.update(
                positionId,
                CDPOS.getPosition(positionId).remainingDeposit - depositAmount
            );
        }

        // Redeem the CD deposits in bulk
        // This will revert if cdTokenIn is 0
        uint256 tokensOut = CDEPO.redeemFor(msg.sender, cdTokenIn);

        // Wrap the tokens and transfer to the TRSRY
        ERC4626 vault = CDEPO.VAULT();
        CDEPO.ASSET().approve(address(vault), tokensOut);
        vault.deposit(tokensOut, address(TRSRY));

        // Mint OHM to the owner/caller
        // No need to check if `convertedTokenOut` is 0, as MINTR will revert
        MINTR.mintOhm(msg.sender, convertedTokenOut);

        // Emit event
        emit ConvertedDeposit(msg.sender, cdTokenIn, convertedTokenOut);

        return (cdTokenIn, convertedTokenOut);
    }

    function _previewRedeem(
        address account_,
        uint256 positionId_,
        uint256 amount_
    ) internal view returns (uint256 redeemed) {
        // Validate that the position is valid
        // This will revert if the position is not valid
        CDPOSv1.Position memory position = CDPOS.getPosition(positionId_);

        // Validate that the caller is the owner of the position
        if (position.owner != account_) revert CDF_NotOwner(positionId_);

        // Validate that the position is CDEPO
        if (position.convertibleDepositToken != address(CDEPO))
            revert CDF_InvalidToken(positionId_, position.convertibleDepositToken);

        // Validate that the position has expired
        if (block.timestamp < position.conversionExpiry) revert CDF_PositionNotExpired(positionId_);

        // Validate that the deposit amount is not greater than the remaining deposit
        if (amount_ > position.remainingDeposit) revert CDF_InvalidAmount(positionId_, amount_);

        redeemed = amount_;
        return redeemed;
    }

    /// @inheritdoc IConvertibleDepositFacility
    /// @dev        This function reverts if:
    ///             - The contract is not active
    ///             - The length of the positionIds_ array does not match the length of the amounts_ array
    ///             - The caller is not the owner of all of the positions
    ///             - The position is not valid
    ///             - The position is not CDEPO
    ///             - The position has not expired
    ///             - The deposit amount is greater than the remaining deposit
    ///             - The deposit amount is 0
    function previewRedeem(
        address account_,
        uint256[] memory positionIds_,
        uint256[] memory amounts_
    ) external view onlyActive returns (uint256 redeemed, address cdTokenSpender) {
        // Make sure the lengths of the arrays are the same
        if (positionIds_.length != amounts_.length) revert CDF_InvalidArgs("array length");

        uint256 totalDeposit;

        for (uint256 i; i < positionIds_.length; ++i) {
            uint256 positionId = positionIds_[i];
            uint256 amount = amounts_[i];
            totalDeposit += amount;

            // Validate
            _previewRedeem(account_, positionId, amount);
        }

        // Preview redeeming the deposits in bulk
        redeemed = CDEPO.previewRedeem(totalDeposit);

        // If the redeemed amount is 0, revert
        if (redeemed == 0) revert CDF_InvalidArgs("amount");

        return (redeemed, address(CDEPO));
    }

    /// @inheritdoc IConvertibleDepositFacility
    /// @dev        This function reverts if:
    ///             - The contract is not active
    ///             - The length of the positionIds_ array does not match the length of the amounts_ array
    ///             - The caller is not the owner of all of the positions
    ///             - The position is not valid
    ///             - The position is not CDEPO
    ///             - The position has not expired
    ///             - The deposit amount is greater than the remaining deposit
    ///             - The deposit amount is 0
    function redeem(
        uint256[] memory positionIds_,
        uint256[] memory amounts_
    ) external nonReentrant onlyActive returns (uint256 redeemed) {
        // Make sure the lengths of the arrays are the same
        if (positionIds_.length != amounts_.length) revert CDF_InvalidArgs("array length");

        uint256 unconverted;
        uint256 totalDeposit;

        // Iterate over all positions
        for (uint256 i; i < positionIds_.length; ++i) {
            uint256 positionId = positionIds_[i];
            uint256 depositAmount = amounts_[i];
            totalDeposit += depositAmount;

            // Validate
            _previewRedeem(msg.sender, positionId, depositAmount);

            // Unconverted must be calculated for each position, as the conversion price can differ
            unconverted += (depositAmount * SCALE) / CDPOS.getPosition(positionId).conversionPrice;

            // Update the position
            CDPOS.update(
                positionId,
                CDPOS.getPosition(positionId).remainingDeposit - depositAmount
            );
        }

        // Redeem the CD deposits in bulk
        // This will revert if the redeemed amount is 0
        redeemed = CDEPO.redeemFor(msg.sender, totalDeposit);

        // Transfer the tokens to the caller
        ERC20 cdepoAsset = CDEPO.ASSET();
        cdepoAsset.transfer(msg.sender, redeemed);

        // Wrap any remaining tokens and transfer to the TRSRY
        uint256 remainingTokens = cdepoAsset.balanceOf(address(this));
        if (remainingTokens > 0) {
            ERC4626 vault = CDEPO.VAULT();
            cdepoAsset.approve(address(vault), remainingTokens);
            vault.deposit(remainingTokens, address(TRSRY));
        }

        // Decrease the mint approval
        MINTR.decreaseMintApproval(address(this), unconverted);

        // Emit event
        emit RedeemedDeposit(msg.sender, redeemed);

        return redeemed;
    }

    function _previewReclaim(
        address account_,
        uint256 positionId_,
        uint256 amount_
    ) internal view returns (uint256 reclaimed) {
        // Validate that the position is valid
        // This will revert if the position is not valid
        CDPOSv1.Position memory position = CDPOS.getPosition(positionId_);

        // Validate that the caller is the owner of the position
        if (position.owner != account_) revert CDF_NotOwner(positionId_);

        // Validate that the position is CDEPO
        if (position.convertibleDepositToken != address(CDEPO))
            revert CDF_InvalidToken(positionId_, position.convertibleDepositToken);

        // Validate that the position has not expired
        if (block.timestamp >= position.conversionExpiry) revert CDF_PositionExpired(positionId_);

        // Validate that the deposit amount is not greater than the remaining deposit
        if (amount_ > position.remainingDeposit) revert CDF_InvalidAmount(positionId_, amount_);

        reclaimed = CDEPO.previewReclaim(amount_);
        return reclaimed;
    }

    /// @inheritdoc IConvertibleDepositFacility
    /// @dev        This function reverts if:
    ///             - The contract is not active
    ///             - The length of the positionIds_ array does not match the length of the amounts_ array
    ///             - The caller is not the owner of all of the positions
    ///             - The position is not valid
    ///             - The position is not CDEPO
    ///             - The position has expired
    ///             - The deposit amount is greater than the remaining deposit
    ///             - The deposit amount is 0
    function previewReclaim(
        address account_,
        uint256[] memory positionIds_,
        uint256[] memory amounts_
    ) external view onlyActive returns (uint256 reclaimed, address cdTokenSpender) {
        // Make sure the lengths of the arrays are the same
        if (positionIds_.length != amounts_.length) revert CDF_InvalidArgs("array length");

        uint256 totalDeposit;

        for (uint256 i; i < positionIds_.length; ++i) {
            uint256 positionId = positionIds_[i];
            uint256 amount = amounts_[i];
            totalDeposit += amount;

            // Validate
            _previewReclaim(account_, positionId, amount);
        }

        // Preview reclaiming the deposits in bulk
        reclaimed = CDEPO.previewReclaim(totalDeposit);

        // If the reclaimed amount is 0, revert
        if (reclaimed == 0) revert CDF_InvalidArgs("amount");

        return (reclaimed, address(CDEPO));
    }

    /// @inheritdoc IConvertibleDepositFacility
    /// @dev        This function reverts if:
    ///             - The contract is not active
    ///             - The length of the positionIds_ array does not match the length of the amounts_ array
    ///             - The caller is not the owner of all of the positions
    ///             - The position is not valid
    ///             - The position is not CDEPO
    ///             - The position has expired
    ///             - The deposit amount is greater than the remaining deposit
    ///             - The deposit amount is 0
    function reclaim(
        uint256[] memory positionIds_,
        uint256[] memory amounts_
    ) external nonReentrant onlyActive returns (uint256 reclaimed) {
        // Make sure the lengths of the arrays are the same
        if (positionIds_.length != amounts_.length) revert CDF_InvalidArgs("array length");

        uint256 unconverted;
        uint256 totalDeposit;

        // Iterate over all positions
        for (uint256 i; i < positionIds_.length; ++i) {
            uint256 positionId = positionIds_[i];
            uint256 depositAmount = amounts_[i];
            totalDeposit += depositAmount;

            // Validate
            _previewReclaim(msg.sender, positionId, depositAmount);

            // Unconverted must be calculated for each position, as the conversion price can differ
            unconverted += (depositAmount * SCALE) / CDPOS.getPosition(positionId).conversionPrice;

            // Update the position
            CDPOS.update(
                positionId,
                CDPOS.getPosition(positionId).remainingDeposit - depositAmount
            );
        }

        // Redeem the CD deposits in bulk
        // This will revert if the reclaimed amount is 0
        reclaimed = CDEPO.reclaimFor(msg.sender, totalDeposit);

        // Transfer the tokens to the caller
        ERC20 cdepoAsset = CDEPO.ASSET();
        cdepoAsset.transfer(msg.sender, reclaimed);

        // Wrap any remaining tokens and transfer to the TRSRY
        uint256 remainingTokens = cdepoAsset.balanceOf(address(this));
        if (remainingTokens > 0) {
            ERC4626 vault = CDEPO.VAULT();
            cdepoAsset.approve(address(vault), remainingTokens);
            vault.deposit(remainingTokens, address(TRSRY));
        }

        // Decrease the mint approval
        MINTR.decreaseMintApproval(address(this), unconverted);

        // Emit event
        emit ReclaimedDeposit(msg.sender, reclaimed, totalDeposit - reclaimed);

        return reclaimed;
    }

    // ========== VIEW FUNCTIONS ========== //

    function depositToken() external view returns (address) {
        return address(CDEPO.ASSET());
    }

    function convertibleDepositToken() external view returns (address) {
        return address(CDEPO);
    }

    function convertedToken() external view returns (address) {
        return address(MINTR.ohm());
    }

    // ========== ADMIN FUNCTIONS ========== //

    /// @notice Activate the contract functionality
    /// @dev    This function will revert if:
    ///         - The caller does not have the ROLE_EMERGENCY_SHUTDOWN role
    ///
    ///         Note that if the contract is already active, this function will do nothing.
    function activate() external onlyRole(ROLE_EMERGENCY_SHUTDOWN) {
        // If the contract is already active, do nothing
        if (locallyActive) return;

        // Set the contract to active
        locallyActive = true;

        // Emit event
        emit Activated();
    }

    /// @notice Deactivate the contract functionality
    /// @dev    This function will revert if:
    ///         - The caller does not have the ROLE_EMERGENCY_SHUTDOWN role
    ///
    ///         Note that if the contract is already inactive, this function will do nothing.
    function deactivate() external onlyRole(ROLE_EMERGENCY_SHUTDOWN) {
        // If the contract is already inactive, do nothing
        if (!locallyActive) return;

        // Set the contract to inactive
        locallyActive = false;

        // Emit event
        emit Deactivated();
    }

    /// @notice Set the reclaim rate for CDEPO
    /// @dev    This function will revert if:
    ///         - The caller is not permissioned
    ///         - CDEPO reverts
    ///
    /// @param  reclaimRate_  The new reclaim rate to set
    function setReclaimRate(uint16 reclaimRate_) external onlyRole(ROLE_ADMIN) {
        // CDEPO will handle validation
        CDEPO.setReclaimRate(reclaimRate_);
    }

    // ========== MODIFIERS ========== //

    modifier onlyActive() {
        if (!locallyActive) revert CDF_NotActive();
        _;
    }
}
