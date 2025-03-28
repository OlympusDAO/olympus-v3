// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IConvertibleDepositERC20} from "src/modules/CDEPO/IConvertibleDepositERC20.sol";

/// @title IYieldDepositFacility
/// @notice Interface for the Yield Facility that can be used to mint yield-bearing deposits
interface IYieldDepositFacility {
    // ========== EVENTS ========== //

    event CreatedDeposit(
        address indexed depositToken,
        address indexed user,
        uint256 indexed positionId,
        uint256 depositAmount
    );

    event ClaimedYield(address indexed depositToken, address indexed user, uint256 yield);

    event YieldFeeSet(uint16 yieldFee);

    // ========== ERRORS ========== //

    error YDF_InvalidArgs(string reason_);

    error YDF_NotOwner(uint256 positionId_);

    error YDF_InvalidToken(uint256 positionId_, address token_);

    error YDF_Unsupported(uint256 positionId_);

    // ========== MINT ========== //

    /// @notice Mints a position for a yield-bearing deposit
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the CD token is supported
    ///         - Depositing the token into the CDEPO module and minting the CD token
    ///         - Creating a new position in the CDPOS module
    ///
    /// @param  cdToken_            The address of the CD token
    /// @param  amount_             The amount of token to deposit
    /// @param  wrap_               Whether the position should be wrapped
    /// @return positionId          The ID of the new position
    function mint(
        IConvertibleDepositERC20 cdToken_,
        uint256 amount_,
        bool wrap_
    ) external returns (uint256 positionId);

    // ========== YIELD ========== //

    /// @notice Preview the amount of yield that would be claimed for the given positions
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that `account_` is the owner of all of the positions
    ///         - Validating that token in the position is a supported CD token
    ///         - Validating that all of the positions are valid
    ///         - Returning the total amount of yield that would be claimed
    ///
    /// @param  account_        The address to preview the yield for
    /// @param  positionIds_    An array of position ids that will be claimed
    /// @return yield           The amount of yield that would be claimed
    /// @return asset           The address of the asset that will be received
    function previewClaimYield(
        address account_,
        uint256[] memory positionIds_
    ) external view returns (uint256 yield, IERC20 asset);

    /// @notice Claims the yield for the given positions
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller is the owner of all of the positions
    ///         - Validating that token in the position is a supported CD token
    ///         - Validating that all of the positions are valid
    ///         - Burning the CD tokens
    ///         - Transferring the yield to the caller
    ///         - Emitting an event
    ///
    /// @param  positionIds_    An array of position ids that will be claimed
    /// @return yield           The amount of yield that was claimed
    function claimYield(uint256[] memory positionIds_) external returns (uint256 yield);

    // ========== ADMIN FUNCTIONS ========== //

    /// @notice Creates a new CD token
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller has the correct role
    ///         - Creating a new CD token
    ///         - Emitting an event
    ///
    /// @param  vault_          The address of the vault to use for the CD token
    /// @param  periodMonths_   The period of the CD token
    /// @param  reclaimRate_    The reclaim rate to set for the CD token
    /// @return cdToken         The address of the new CD token
    function create(
        IERC4626 vault_,
        uint8 periodMonths_,
        uint16 reclaimRate_
    ) external returns (IConvertibleDepositERC20 cdToken);

    /// @notice Sets the percentage of yield that will be taken as a fee
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller has the correct role
    ///         - Setting the yield fee
    ///
    /// @param  yieldFee_       The percentage of yield that will be taken as a fee, in terms of 100e2
    function setYieldFee(uint16 yieldFee_) external;

    /// @notice Returns the percentage of yield that will be taken as a fee
    ///
    /// @return yieldFee The percentage of yield that will be taken as a fee, in terms of 100e2
    function getYieldFee() external view returns (uint16 yieldFee);
}
