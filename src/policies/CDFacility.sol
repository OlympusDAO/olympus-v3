// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

// Libraries
import {FullMath} from "src/libraries/FullMath.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

// Interfaces
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IConvertibleDepositERC20} from "src/modules/CDEPO/IConvertibleDepositERC20.sol";
import {IConvertibleDepositFacility} from "src/policies/interfaces/IConvertibleDepositFacility.sol";

// Bophades
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/OlympusRoles.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {CDEPOv1} from "src/modules/CDEPO/CDEPO.v1.sol";
import {CDPOSv1} from "src/modules/CDPOS/CDPOS.v1.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";

contract CDFacility is Policy, PolicyEnabler, IConvertibleDepositFacility, ReentrancyGuard {
    using FullMath for uint256;
    using SafeTransferLib for ERC20;

    // ========== STATE VARIABLES ========== //

    // Modules
    TRSRYv1 public TRSRY;
    MINTRv1 public MINTR;
    CDEPOv1 public CDEPO;
    CDPOSv1 public CDPOS;

    bytes32 public constant ROLE_AUCTIONEER = "cd_auctioneer";

    // ========== SETUP ========== //

    constructor(address kernel_) Policy(Kernel(kernel_)) {
        // Disabled by default by PolicyEnabler
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

        permissions = new Permissions[](9);
        permissions[0] = Permissions(mintrKeycode, MINTR.increaseMintApproval.selector);
        permissions[1] = Permissions(mintrKeycode, MINTR.mintOhm.selector);
        permissions[2] = Permissions(mintrKeycode, MINTR.decreaseMintApproval.selector);
        permissions[3] = Permissions(cdepoKeycode, CDEPO.redeemFor.selector);
        permissions[4] = Permissions(cdepoKeycode, CDEPO.reclaimFor.selector);
        permissions[5] = Permissions(cdepoKeycode, CDEPO.setReclaimRate.selector);
        permissions[6] = Permissions(cdepoKeycode, CDEPO.create.selector);
        permissions[7] = Permissions(cdposKeycode, CDPOS.mint.selector);
        permissions[8] = Permissions(cdposKeycode, CDPOS.update.selector);
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
    ///             - The contract is not enabled
    ///             - The CD token is not supported
    function mint(
        IConvertibleDepositERC20 cdToken_,
        address account_,
        uint256 amount_,
        uint256 conversionPrice_,
        uint48 conversionExpiry_,
        uint48 redemptionExpiry_,
        bool wrap_
    ) external onlyRole(ROLE_AUCTIONEER) nonReentrant onlyEnabled returns (uint256 positionId) {
        // Mint the CD token to the account
        // This will validate that the CD token is supported, and transfer the deposit token
        CDEPO.mintFor(cdToken_, account_, amount_);

        // Create a new term record in the CDPOS module
        positionId = CDPOS.mint(
            account_,
            address(cdToken_),
            amount_,
            conversionPrice_,
            conversionExpiry_,
            redemptionExpiry_,
            wrap_
        );

        // Calculate the expected OHM amount
        // The deposit and CD token have the same decimals, so either can be used
        uint256 expectedOhmAmount = (amount_ * (10 ** cdToken_.decimals())) / conversionPrice_;

        // Pre-emptively increase the OHM mint approval
        MINTR.increaseMintApproval(address(this), expectedOhmAmount);

        // Emit an event
        emit CreatedDeposit(address(cdToken_.asset()), account_, positionId, amount_);
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

        // Validate that the position has not expired
        if (block.timestamp >= position.conversionExpiry) revert CDF_PositionExpired(positionId_);

        // Validate that the deposit amount is not greater than the remaining deposit
        if (amount_ > position.remainingDeposit) revert CDF_InvalidAmount(positionId_, amount_);

        // The deposit and CD token have the same decimals, so either can be used
        convertedTokenOut =
            (amount_ *
                (10 ** IConvertibleDepositERC20(position.convertibleDepositToken).decimals())) /
            position.conversionPrice;

        return convertedTokenOut;
    }

    /// @inheritdoc IConvertibleDepositFacility
    /// @dev        This function reverts if:
    ///             - The contract is not enabled
    ///             - The length of the positionIds_ array does not match the length of the amounts_ array
    ///             - account_ is not the owner of all of the positions
    ///             - Any position is not valid
    ///             - Any position is not a supported CD token
    ///             - Any position has a different CD token
    ///             - Any position has reached the conversion expiry
    ///             - Any conversion amount is greater than the remaining deposit
    ///             - The amount of CD tokens to convert is 0
    ///             - The converted amount is 0
    function previewConvert(
        address account_,
        uint256[] memory positionIds_,
        uint256[] memory amounts_
    )
        external
        view
        onlyEnabled
        returns (uint256 cdTokenIn, uint256 convertedTokenOut, address cdTokenSpender)
    {
        // Make sure the lengths of the arrays are the same
        if (positionIds_.length != amounts_.length) revert CDF_InvalidArgs("array length");

        IConvertibleDepositERC20 cdToken;
        for (uint256 i; i < positionIds_.length; ++i) {
            uint256 positionId = positionIds_[i];
            uint256 amount = amounts_[i];
            cdTokenIn += amount;
            convertedTokenOut += _previewConvert(account_, positionId, amount);

            // Set the CD token, or validate
            address positionCDToken = CDPOS.getPosition(positionId).convertibleDepositToken;
            if (address(cdToken) == address(0)) {
                cdToken = IConvertibleDepositERC20(positionCDToken);

                // Validate that the CD token is supported
                if (!CDEPO.isConvertibleDepositToken(positionCDToken))
                    revert CDF_InvalidToken(positionId, positionCDToken);
            } else if (address(cdToken) != positionCDToken) {
                revert CDF_InvalidArgs("multiple CD tokens");
            }
        }

        // If the amount is 0, revert
        if (cdTokenIn == 0) revert CDF_InvalidArgs("amount");

        // If the converted amount is 0, revert
        if (convertedTokenOut == 0) revert CDF_InvalidArgs("converted amount");

        return (cdTokenIn, convertedTokenOut, address(CDEPO));
    }

    /// @inheritdoc IConvertibleDepositFacility
    /// @dev        This function reverts if:
    ///             - The contract is not enabled
    ///             - The length of the positionIds_ array does not match the length of the amounts_ array
    ///             - The caller is not the owner of all of the positions
    ///             - Any position is not valid
    ///             - Any position is not a supported CD token
    ///             - Any position has a different CD token
    ///             - Any position has reached the conversion expiry
    ///             - Any position has a conversion amount greater than the remaining deposit
    ///             - The amount of CD tokens to convert is 0
    ///             - The converted amount is 0
    function convert(
        uint256[] memory positionIds_,
        uint256[] memory amounts_
    ) external nonReentrant onlyEnabled returns (uint256 cdTokenIn, uint256 convertedTokenOut) {
        // Make sure the lengths of the arrays are the same
        if (positionIds_.length != amounts_.length) revert CDF_InvalidArgs("array length");

        IConvertibleDepositERC20 cdToken;
        for (uint256 i; i < positionIds_.length; ++i) {
            uint256 positionId = positionIds_[i];
            uint256 depositAmount = amounts_[i];

            cdTokenIn += depositAmount;
            convertedTokenOut += _previewConvert(msg.sender, positionId, depositAmount);

            CDPOSv1.Position memory position = CDPOS.getPosition(positionId);

            // Set the CD token, or validate
            if (address(cdToken) == address(0)) {
                cdToken = IConvertibleDepositERC20(position.convertibleDepositToken);

                // Validate that the CD token is supported
                if (!CDEPO.isConvertibleDepositToken(position.convertibleDepositToken))
                    revert CDF_InvalidToken(positionId, position.convertibleDepositToken);
            } else if (address(cdToken) != position.convertibleDepositToken) {
                revert CDF_InvalidArgs("multiple CD tokens");
            }

            // Update the position
            CDPOS.update(positionId, position.remainingDeposit - depositAmount);
        }

        // Redeem the CD deposit
        // This will revert if cdTokenIn is 0
        uint256 tokensOut = CDEPO.redeemFor(cdToken, msg.sender, cdTokenIn);

        // Wrap the tokens and transfer to the TRSRY
        IERC4626 vault = cdToken.vault();
        cdToken.asset().approve(address(vault), tokensOut);
        vault.deposit(tokensOut, address(TRSRY));

        // Mint OHM to the owner/caller
        // No need to check if `convertedTokenOut` is 0, as MINTR will revert
        MINTR.mintOhm(msg.sender, convertedTokenOut);

        // Emit event
        emit ConvertedDeposit(address(cdToken.asset()), msg.sender, cdTokenIn, convertedTokenOut);

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

        // Validate that the position has expired
        if (block.timestamp < position.conversionExpiry) revert CDF_PositionNotExpired(positionId_);

        // Validate that the position has not reached the redemption expiry
        if (block.timestamp >= position.redemptionExpiry) revert CDF_PositionExpired(positionId_);

        // Validate that the deposit amount is not greater than the remaining deposit
        if (amount_ > position.remainingDeposit) revert CDF_InvalidAmount(positionId_, amount_);

        redeemed = amount_;
        return redeemed;
    }

    /// @inheritdoc IConvertibleDepositFacility
    /// @dev        This function reverts if:
    ///             - The contract is not enabled
    ///             - The length of the positionIds_ array does not match the length of the amounts_ array
    ///             - The caller is not the owner of all of the positions
    ///             - Any position is not valid
    ///             - Any position is not CDEPO
    ///             - Any position has not reached the conversion expiry
    ///             - Any position has reached the redemption expiry
    ///             - Any redemption amount is greater than the remaining deposit
    ///             - The amount of CD tokens to redeem is 0
    function previewRedeem(
        address account_,
        uint256[] memory positionIds_,
        uint256[] memory amounts_
    ) external view onlyEnabled returns (uint256 redeemed, address cdTokenSpender) {
        // Make sure the lengths of the arrays are the same
        if (positionIds_.length != amounts_.length) revert CDF_InvalidArgs("array length");

        uint256 totalDeposit;

        IConvertibleDepositERC20 cdToken;
        for (uint256 i; i < positionIds_.length; ++i) {
            uint256 positionId = positionIds_[i];
            uint256 amount = amounts_[i];
            totalDeposit += amount;

            // Validate
            _previewRedeem(account_, positionId, amount);

            // Set the CD token, or validate
            address positionCDToken = CDPOS.getPosition(positionId).convertibleDepositToken;
            if (address(cdToken) == address(0)) {
                cdToken = IConvertibleDepositERC20(positionCDToken);

                // Validate that the CD token is supported
                if (!CDEPO.isConvertibleDepositToken(positionCDToken))
                    revert CDF_InvalidToken(positionId, positionCDToken);
            } else if (address(cdToken) != positionCDToken) {
                revert CDF_InvalidArgs("multiple CD tokens");
            }
        }

        // Preview redeeming the deposits in bulk
        redeemed = CDEPO.previewRedeem(cdToken, totalDeposit);

        // If the redeemed amount is 0, revert
        if (redeemed == 0) revert CDF_InvalidArgs("amount");

        return (redeemed, address(CDEPO));
    }

    /// @inheritdoc IConvertibleDepositFacility
    /// @dev        This function reverts if:
    ///             - The contract is not enabled
    ///             - The length of the positionIds_ array does not match the length of the amounts_ array
    ///             - The caller is not the owner of all of the positions
    ///             - Any position is not valid
    ///             - Any position is not CDEPO
    ///             - Any position has not reached the conversion expiry
    ///             - Any position has reached the redemption expiry
    ///             - Any redemption amount is greater than the remaining deposit
    ///             - The amount of CD tokens to redeem is 0
    function redeem(
        uint256[] memory positionIds_,
        uint256[] memory amounts_
    ) external nonReentrant onlyEnabled returns (uint256 redeemed) {
        // Make sure the lengths of the arrays are the same
        if (positionIds_.length != amounts_.length) revert CDF_InvalidArgs("array length");

        uint256 unconverted;
        uint256 totalDeposit;

        // Iterate over all positions
        IConvertibleDepositERC20 cdToken;
        for (uint256 i; i < positionIds_.length; ++i) {
            uint256 positionId = positionIds_[i];
            uint256 depositAmount = amounts_[i];
            totalDeposit += depositAmount;

            // Validate
            _previewRedeem(msg.sender, positionId, depositAmount);

            CDPOSv1.Position memory position = CDPOS.getPosition(positionId);

            // Set the CD token, or validate
            if (address(cdToken) == address(0)) {
                cdToken = IConvertibleDepositERC20(position.convertibleDepositToken);

                // Validate that the CD token is supported
                if (!CDEPO.isConvertibleDepositToken(position.convertibleDepositToken))
                    revert CDF_InvalidToken(positionId, position.convertibleDepositToken);
            } else if (address(cdToken) != position.convertibleDepositToken) {
                revert CDF_InvalidArgs("multiple CD tokens");
            }

            // Unconverted must be calculated for each position, as the conversion price can differ
            unconverted += (depositAmount * (10 ** cdToken.decimals())) / position.conversionPrice;

            // Update the position
            CDPOS.update(positionId, position.remainingDeposit - depositAmount);
        }

        // Redeem the CD deposits in bulk
        // This will revert if the redeemed amount is 0
        redeemed = CDEPO.redeemFor(cdToken, msg.sender, totalDeposit);

        // Transfer the tokens to the caller
        ERC20 depositToken = ERC20(address(cdToken.asset()));
        depositToken.safeTransfer(msg.sender, redeemed);

        // Wrap any remaining tokens and transfer to the TRSRY
        uint256 remainingTokens = depositToken.balanceOf(address(this));
        if (remainingTokens > 0) {
            IERC4626 vault = cdToken.vault();
            depositToken.safeApprove(address(vault), remainingTokens);
            vault.deposit(remainingTokens, address(TRSRY));
        }

        // Decrease the mint approval
        MINTR.decreaseMintApproval(address(this), unconverted);

        // Emit event
        emit RedeemedDeposit(address(depositToken), msg.sender, redeemed);

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

        // Validate that the position has not expired
        if (block.timestamp >= position.conversionExpiry) revert CDF_PositionExpired(positionId_);

        // Validate that the deposit amount is not greater than the remaining deposit
        if (amount_ > position.remainingDeposit) revert CDF_InvalidAmount(positionId_, amount_);

        // reclaimed = CDEPO.previewReclaim(amount_);
        return reclaimed;
    }

    /// @inheritdoc IConvertibleDepositFacility
    /// @dev        This function reverts if:
    ///             - The contract is not enabled
    ///             - The amount of CD tokens to reclaim is 0
    ///             - The reclaimed amount is 0
    function previewReclaim(
        IConvertibleDepositERC20 cdToken_,
        uint256 amount_
    ) external view onlyEnabled returns (uint256 reclaimed, address cdTokenSpender) {
        // Preview reclaiming the amount
        // This will revert if the amount or reclaimed amount is 0
        reclaimed = CDEPO.previewReclaim(cdToken_, amount_);

        return (reclaimed, address(CDEPO));
    }

    /// @inheritdoc IConvertibleDepositFacility
    /// @dev        This function reverts if:
    ///             - The contract is not enabled
    ///             - The amount of CD tokens to reclaim is 0
    ///             - The reclaimed amount is 0
    function reclaim(
        IConvertibleDepositERC20 cdToken_,
        uint256 amount_
    ) external nonReentrant onlyEnabled returns (uint256 reclaimed) {
        // Reclaim the CD deposit
        // This will revert if the amount or reclaimed amount is 0
        // It will return the discount quantity of underlying asset to this contract
        reclaimed = CDEPO.reclaimFor(cdToken_, msg.sender, amount_);

        // Transfer the tokens to the caller
        ERC20 depositToken = ERC20(address(cdToken_.asset()));
        depositToken.safeTransfer(msg.sender, reclaimed);

        // Wrap any remaining tokens and transfer to the TRSRY
        uint256 remainingTokens = depositToken.balanceOf(address(this));
        if (remainingTokens > 0) {
            IERC4626 vault = cdToken_.vault();
            depositToken.safeApprove(address(vault), remainingTokens);
            vault.deposit(remainingTokens, address(TRSRY));
        }

        // Emit event
        emit ReclaimedDeposit(address(depositToken), msg.sender, reclaimed, amount_ - reclaimed);

        return reclaimed;
    }

    // ========== ADMIN FUNCTIONS ========== //

    /// @inheritdoc IConvertibleDepositFacility
    function create(
        IERC4626 vault_,
        uint16 reclaimRate_
    ) external onlyEnabled onlyAdminRole returns (IConvertibleDepositERC20 cdToken) {
        // Create a new convertible deposit token
        cdToken = CDEPO.create(vault_, reclaimRate_);

        return cdToken;
    }

    // ========== VIEW FUNCTIONS ========== //

    function depositToken() external view returns (address) {
        // return address(CDEPO.ASSET());
    }

    function convertibleDepositToken() external view returns (address) {
        // return address(CDEPO);
    }

    function convertedToken() external view returns (address) {
        return address(MINTR.ohm());
    }

    /// @notice Set the reclaim rate for CDEPO
    /// @dev    This function will revert if:
    ///         - The caller is not permissioned
    ///         - CDEPO reverts
    ///
    /// @param  cdToken_      The address of the CD token
    /// @param  reclaimRate_  The new reclaim rate to set
    function setReclaimRate(
        IConvertibleDepositERC20 cdToken_,
        uint16 reclaimRate_
    ) external onlyAdminRole {
        // CDEPO will handle validation
        CDEPO.setReclaimRate(cdToken_, reclaimRate_);
    }
}
