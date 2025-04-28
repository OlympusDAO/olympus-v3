// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

// Interfaces
import {IConvertibleDepositERC20} from "src/modules/CDEPO/IConvertibleDepositERC20.sol";
import {IConvertibleDepository} from "src/modules/CDEPO/IConvertibleDepository.sol";
import {IConvertibleDepositFacility} from "src/policies/interfaces/IConvertibleDepositFacility.sol";

// Bophades
import {Kernel, Keycode, Permissions, Policy, toKeycode} from "src/Kernel.sol";
import {ROLESv1} from "src/modules/ROLES/OlympusRoles.sol";
import {MINTRv1} from "src/modules/MINTR/MINTR.v1.sol";
import {TRSRYv1} from "src/modules/TRSRY/TRSRY.v1.sol";
import {CDEPOv1} from "src/modules/CDEPO/CDEPO.v1.sol";
import {CDPOSv1} from "src/modules/CDPOS/CDPOS.v1.sol";
import {CDTokenManager} from "src/policies/CDTokenManager.sol";

/// @title  Convertible Deposit Facility
/// @notice Implementation of the {IConvertibleDepositFacility} interface
///         It is a general-purpose contract that can be used to create, mint, convert, redeem, and reclaim CD tokens
contract CDFacility is Policy, IConvertibleDepositFacility {
    // ========== CONSTANTS ========== //

    bytes32 public constant ROLE_AUCTIONEER = "cd_auctioneer";

    // ========== STATE VARIABLES ========== //

    /// @notice The CD token manager
    CDTokenManager public CD_TOKEN_MANAGER;

    /// @notice The MINTR module.
    MINTRv1 public MINTR;

    /// @notice The CDPOS module.
    CDPOSv1 public CDPOS;

    // ========== SETUP ========== //

    constructor(address kernel_, address cdTokenManager_) Policy(Kernel(kernel_)) {
        // Validate that the CD token manager is not the zero address
        if (cdTokenManager_ == address(0)) revert CDF_InvalidArgs("cdTokenManager");

        // Set the CD token manager
        CD_TOKEN_MANAGER = CDTokenManager(cdTokenManager_);

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
    ///             - The CD token is not supported
    function mint(
        IConvertibleDepositERC20 cdToken_,
        address account_,
        uint256 amount_,
        uint256 conversionPrice_,
        bool wrap_
    ) external onlyRole(ROLE_AUCTIONEER) nonReentrant onlyEnabled returns (uint256 positionId) {
        // Mint the CD token to the account
        // This will validate that the CD token is supported, and transfer the deposit token
        CD_TOKEN_MANAGER.mintFor(cdToken_, account_, amount_);

        // Create a new term record in the CDPOS module
        positionId = CDPOS.mint(
            account_,
            address(cdToken_),
            amount_,
            conversionPrice_,
            uint48(block.timestamp + cdToken_.periodMonths() * 30 days),
            wrap_
        );

        // Emit an event
        emit CreatedDeposit(address(cdToken_.asset()), account_, positionId, amount_);
    }

    // ========== CONVERTIBLE DEPOSIT ACTIONS ========== //

    function _previewConvert(
        address account_,
        uint256 positionId_,
        uint256 amount_,
        address previousCDToken_
    ) internal view returns (uint256 convertedTokenOut, address currentCDToken) {
        // Validate that the position is valid
        // This will revert if the position is not valid
        CDPOSv1.Position memory position = CDPOS.getPosition(positionId_);

        // Validate that the caller is the owner of the position
        if (position.owner != account_) revert CDF_NotOwner(positionId_);

        // Validate that the position has not expired
        if (block.timestamp >= position.expiry) revert CDF_PositionExpired(positionId_);

        // Validate that the deposit amount is not greater than the remaining deposit
        if (amount_ > position.remainingDeposit) revert CDF_InvalidAmount(positionId_, amount_);

        // Validate that the position supports conversion
        if (position.conversionPrice == type(uint256).max) revert CDF_Unsupported(positionId_);

        // Set the CD token, or validate
        currentCDToken = position.convertibleDepositToken;
        if (previousCDToken_ == address(0)) {
            // Validate that the CD token is supported
            if (!CDEPO.isConvertibleDepositToken(currentCDToken))
                revert CDF_InvalidToken(positionId_, currentCDToken);
        } else if (previousCDToken_ != currentCDToken) {
            revert CDF_InvalidArgs("multiple CD tokens");
        }

        // The deposit and CD token have the same decimals, so either can be used
        convertedTokenOut =
            (amount_ * (10 ** IConvertibleDepositERC20(currentCDToken).decimals())) /
            position.conversionPrice;

        return (convertedTokenOut, currentCDToken);
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

        address cdToken;
        for (uint256 i; i < positionIds_.length; ++i) {
            uint256 positionId = positionIds_[i];
            uint256 amount = amounts_[i];

            cdTokenIn += amount;

            (uint256 previewConvertOut, address currentCDToken) = _previewConvert(
                account_,
                positionId,
                amount,
                cdToken
            );
            convertedTokenOut += previewConvertOut;
            cdToken = currentCDToken;
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

            (uint256 previewConvertOut, address currentCDToken) = _previewConvert(
                msg.sender,
                positionId,
                depositAmount,
                address(cdToken)
            );
            convertedTokenOut += previewConvertOut;
            cdToken = IConvertibleDepositERC20(currentCDToken);

            // Update the position
            CDPOS.update(
                positionId,
                CDPOS.getPosition(positionId).remainingDeposit - depositAmount
            );
        }

        // Burn the CD tokens from the caller
        // This will revert if cdTokenIn is 0
        CD_TOKEN_MANAGER.burnFrom(cdToken, msg.sender, cdTokenIn);

        // TODO integrate with CDTokenManager

        // Transfer the vault shares to the TRSRY
        cdToken.vault().transfer(address(TRSRY), cdToken.vault().previewWithdraw(cdTokenIn));

        // Mint OHM to the owner/caller
        // No need to check if `convertedTokenOut` is 0, as MINTR will revert
        MINTR.increaseMintApproval(address(this), convertedTokenOut);
        MINTR.mintOhm(msg.sender, convertedTokenOut);

        // Emit event
        emit ConvertedDeposit(address(cdToken.asset()), msg.sender, cdTokenIn, convertedTokenOut);

        return (cdTokenIn, convertedTokenOut);
    }

    // ========== VIEW FUNCTIONS ========== //

    /// @inheritdoc IConvertibleDepositFacility
    function getDepositTokens()
        external
        view
        returns (IConvertibleDepository.DepositToken[] memory)
    {
        return CDEPO.getDepositTokens();
    }

    /// @inheritdoc IConvertibleDepositFacility
    function getConvertibleDepositTokens()
        external
        view
        returns (IConvertibleDepositERC20[] memory)
    {
        return CDEPO.getConvertibleDepositTokens();
    }

    /// @inheritdoc IConvertibleDepositFacility
    function convertedToken() external view returns (address) {
        return address(MINTR.ohm());
    }

    // ========== PERIODIC TASK ========== //

    /// @inheritdoc IPeriodicTask
    function execute() external override onlyRole(HEART_ROLE) {
        // Performs enabled check and sweeps yield
        _execute();
    }
}
