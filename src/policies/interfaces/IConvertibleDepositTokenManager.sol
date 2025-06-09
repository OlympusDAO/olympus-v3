// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IConvertibleDepositERC20} from "src/modules/CDEPO/IConvertibleDepositERC20.sol";
import {IConvertibleDepository} from "src/modules/CDEPO/IConvertibleDepository.sol";

/// @title Convertible Deposit Token Manager
/// @notice Defines an interface for a policy that manages convertible deposit ("CD") tokens on behalf of deposit facilities. It is meant to be used by the facilities, and is not an end-user policy. It also assumes that deposited tokens are ERC20 tokens belonging to an ERC4626 vault.
interface IConvertibleDepositTokenManager {
    // ========== EVENTS ========== //

    event Mint(address indexed account, address indexed cdToken, uint256 amount, uint256 shares);

    event Burn(address indexed account, address indexed cdToken, uint256 amount, uint256 shares);

    event Withdraw(
        address indexed account,
        address indexed cdToken,
        uint256 amount,
        uint256 shares
    );

    // ========== ERRORS ========== //

    error ConvertibleDepositTokenManager_Insolvent(
        address cdToken,
        uint256 sharesRequired,
        uint256 sharesDeposited
    );

    error ConvertibleDepositTokenManager_ZeroAmount();

    // ========== MINT/BURN FUNCTIONS ========== //

    /// @notice Mints the given amount of the CD token in exchange for the underlying asset
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller has the correct role
    ///         - Transferring the deposit token from the caller to the contract
    ///         - Minting the CD token to the caller
    ///         - Updating the amount of deposited funds
    ///
    /// @param  cdToken_      The CD token to mint
    /// @param  amount_       The amount to mint
    /// @return shares        The number of vault shares equivalent to the deposited amount
    function mint(
        IConvertibleDepositERC20 cdToken_,
        uint256 amount_
    ) external returns (uint256 shares);

    /// @notice Withdraws the given amount of the underlying asset
    ///         This does not burn CD tokens, but should reduce the amount of shares the caller has in the vault.
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller has the correct role
    ///         - Transferring the underlying asset from the contract to the caller
    ///         - Updating the amount of deposited funds
    ///
    /// @param  cdToken_      The CD token to withdraw from
    /// @param  amount_       The amount to withdraw
    /// @return shares        The number of vault shares equivalent to the withdrawn amount
    function withdraw(
        IConvertibleDepositERC20 cdToken_,
        uint256 amount_
    ) external returns (uint256 shares);

    /// @notice Burns the given amount of the CD token and returns the underlying asset
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller has the correct role
    ///         - Transferring the CD tokens from the caller to the contract
    ///         - Burning the CD tokens
    ///         - Transferring the deposit token from the contract to the caller
    ///         - Updating the amount of deposited funds
    ///
    /// @param  cdToken_      The CD token to burn
    /// @param  amount_       The amount to burn
    /// @return shares        The number of vault shares equivalent to the burnt amount
    function burn(
        IConvertibleDepositERC20 cdToken_,
        uint256 amount_
    ) external returns (uint256 shares);

    // ========== TOKEN FUNCTIONS ========== //

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
    function createToken(
        IERC4626 vault_,
        uint8 periodMonths_,
        uint16 reclaimRate_
    ) external returns (IConvertibleDepositERC20 cdToken);

    /// @notice Sets the reclaim rate for a CD token
    /// @dev    The implementing contract is expected to handle the following:
    ///         - Validating that the caller has the correct role
    ///         - Setting the reclaim rate for the CD token
    ///
    /// @param  cdToken_      The address of the CD token
    /// @param  reclaimRate_  The reclaim rate to set
    function setTokenReclaimRate(IConvertibleDepositERC20 cdToken_, uint16 reclaimRate_) external;

    /// @notice Returns the reclaim rate for a CD token
    ///
    /// @param  cdToken_      The address of the CD token
    /// @return reclaimRate   The reclaim rate for the CD token
    function getTokenReclaimRate(
        IConvertibleDepositERC20 cdToken_
    ) external view returns (uint16 reclaimRate);

    /// @notice The addresses of deposit tokens accepted by the facility
    function getDepositTokens()
        external
        view
        returns (IConvertibleDepository.DepositToken[] memory);

    /// @notice The addresses of the CD tokens that are minted by the facility
    function getConvertibleDepositTokens()
        external
        view
        returns (IConvertibleDepositERC20[] memory);

    /// @notice Returns whether the given address is a convertible deposit token
    ///
    /// @param  cdToken_      The address of the CD token
    /// @return isConvertible Whether the address is a convertible deposit token
    function isConvertibleDepositToken(address cdToken_) external view returns (bool isConvertible);
}
