// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "src/Kernel.sol";

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

contract CDFacility is Policy, RolesConsumer, IConvertibleDepositFacility {
    using FullMath for uint256;

    // ========== STATE VARIABLES ========== //

    // Constants
    uint256 public constant DECIMALS = 1e18;

    // Modules
    TRSRYv1 public TRSRY;
    MINTRv1 public MINTR;
    CDEPOv1 public CDEPO;
    CDPOSv1 public CDPOS;

    // ========== ERRORS ========== //

    error CDFacility_InvalidParams(string reason);

    error Misconfigured();

    // ========== SETUP ========== //

    constructor(address kernel_) Policy(Kernel(kernel_)) {}

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

    function requestPermissions()
        external
        view
        override
        returns (Permissions[] memory permissions)
    {
        Keycode mintrKeycode = toKeycode("MINTR");
        Keycode cdepoKeycode = toKeycode("CDEPO");
        Keycode cdposKeycode = toKeycode("CDPOS");

        permissions = new Permissions[](7);
        permissions[0] = Permissions(mintrKeycode, MINTR.increaseMintApproval.selector);
        permissions[1] = Permissions(mintrKeycode, MINTR.mintOhm.selector);
        permissions[2] = Permissions(mintrKeycode, MINTR.decreaseMintApproval.selector);
        permissions[3] = Permissions(cdepoKeycode, CDEPO.redeem.selector);
        permissions[4] = Permissions(cdepoKeycode, CDEPO.sweepYield.selector);
        permissions[5] = Permissions(cdposKeycode, CDPOS.create.selector);
        permissions[6] = Permissions(cdposKeycode, CDPOS.update.selector);
    }

    // ========== CONVERTIBLE DEPOSIT ACTIONS ========== //

    /// @inheritdoc IConvertibleDepositFacility
    function create(
        address account_,
        uint256 amount_,
        uint256 conversionPrice_,
        uint48 expiry_,
        bool wrap_
    ) external onlyRole("CD_Auctioneer") returns (uint256 positionId) {
        // Mint the CD token to the account
        // This will also transfer the reserve token
        CDEPO.mintFor(account_, amount_);

        // Create a new term record in the CDPOS module
        positionId = CDPOS.create(
            account_,
            address(CDEPO),
            amount_,
            conversionPrice_,
            expiry_,
            wrap_
        );

        // Pre-emptively increase the OHM mint approval
        MINTR.increaseMintApproval(address(this), amount_);

        // Emit an event
        emit CreatedDeposit(account_, positionId, amount_);
    }

    /// @inheritdoc IConvertibleDepositFacility
    /// @dev        This function reverts if:
    ///             - The length of the positionIds_ array does not match the length of the amounts_ array
    ///             - The caller is not the owner of all of the positions
    ///             - The position is not valid
    ///             - The position is not CDEPO
    ///             - The position has expired
    ///             - The deposit amount is greater than the remaining deposit
    function convert(
        uint256[] memory positionIds_,
        uint256[] memory amounts_
    ) external returns (uint256 totalDeposit, uint256 converted) {
        // Make sure the lengths of the arrays are the same
        if (positionIds_.length != amounts_.length)
            revert CDF_InvalidArgs("array lengths must match");

        uint256 totalDeposits;

        // Iterate over all positions
        for (uint256 i; i < positionIds_.length; ++i) {
            uint256 positionId = positionIds_[i];
            uint256 depositAmount = amounts_[i];

            // Validate that the caller is the owner of the position
            if (CDPOS.ownerOf(positionId) != msg.sender) revert CDF_NotOwner(positionId);

            // Validate that the position is valid
            // This will revert if the position is not valid
            CDPOSv1.Position memory position = CDPOS.getPosition(positionId);

            // Validate that the position is CDEPO
            if (position.convertibleDepositToken != address(CDEPO))
                revert CDF_InvalidToken(positionId, position.convertibleDepositToken);

            // Validate that the position has not expired
            if (block.timestamp >= position.expiry) revert CDF_PositionExpired(positionId);

            // Validate that the deposit amount is not greater than the remaining deposit
            if (depositAmount > position.remainingDeposit)
                revert CDF_InvalidAmount(positionId, depositAmount);

            uint256 convertedAmount = (depositAmount * DECIMALS) / position.conversionPrice; // TODO check decimals, rounding

            // Increment running totals
            totalDeposits += depositAmount;
            converted += convertedAmount;

            // Update the position
            CDPOS.update(positionId, position.remainingDeposit - depositAmount);
        }

        // Redeem the CD deposits in bulk
        uint256 sharesOut = CDEPO.redeem(totalDeposits);

        // Transfer the redeemed assets to the TRSRY
        CDEPO.vault().transfer(address(TRSRY), sharesOut);

        // Mint OHM to the owner/caller
        MINTR.mintOhm(msg.sender, converted);

        // Emit event
        emit ConvertedDeposit(msg.sender, totalDeposits, converted);

        return (totalDeposits, converted);
    }

    /// @inheritdoc IConvertibleDepositFacility
    function reclaim(
        uint256[] memory positionIds_,
        uint256[] memory amounts_
    ) external override returns (uint256 reclaimed) {
        // Make sure the lengths of the arrays are the same
        if (positionIds_.length != amounts_.length)
            revert CDF_InvalidArgs("array lengths must match");

        uint256 unconverted;

        // Iterate over all positions
        for (uint256 i; i < positionIds_.length; ++i) {
            uint256 positionId = positionIds_[i];
            uint256 depositAmount = amounts_[i];

            // Validate that the caller is the owner of the position
            if (CDPOS.ownerOf(positionId) != msg.sender) revert CDF_NotOwner(positionId);

            // Validate that the position is valid
            // This will revert if the position is not valid
            CDPOSv1.Position memory position = CDPOS.getPosition(positionId);

            // Validate that the position is CDEPO
            if (position.convertibleDepositToken != address(CDEPO))
                revert CDF_InvalidToken(positionId, position.convertibleDepositToken);

            // Validate that the position has expired
            if (block.timestamp < position.expiry) revert CDF_PositionNotExpired(positionId);

            // Validate that the deposit amount is not greater than the remaining deposit
            if (depositAmount > position.remainingDeposit)
                revert CDF_InvalidAmount(positionId, depositAmount);

            uint256 convertedAmount = (depositAmount * DECIMALS) / position.conversionPrice; // TODO check decimals, rounding

            // Increment running totals
            reclaimed += depositAmount;
            unconverted += convertedAmount;

            // Update the position
            CDPOS.update(positionId, position.remainingDeposit - depositAmount);
        }

        // Redeem the CD deposits in bulk
        uint256 sharesOut = CDEPO.redeem(unconverted);

        // Transfer the underlying assets to the caller
        CDEPO.vault().redeem(sharesOut, msg.sender, address(this));

        // Decrease the mint approval
        MINTR.decreaseMintApproval(address(this), unconverted);

        // Emit event
        emit ReclaimedDeposit(msg.sender, reclaimed);

        return reclaimed;
    }
}
