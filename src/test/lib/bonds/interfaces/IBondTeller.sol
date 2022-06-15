// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";

interface IBondTeller {
    /// @notice                 Exchange quote tokens for a bond in a specified market
    /// @param recipient_       Address of recipient of bond. Allows deposits for other addresses
    /// @param id_              ID of the Market the bond is being purchased from
    /// @param amount_          Amount to deposit in exchange for bond
    /// @param minAmountOut_    Minimum acceptable amount of bond to receive. Prevents frontrunning
    /// @return                 Amount of payout token to be received from the bond
    /// @return                 Timestamp at which the bond token can be redeemed for the underlying token
    function purchase(
        address recipient_,
        uint256 id_,
        uint256 amount_,
        uint256 minAmountOut_
    ) external returns (uint256, uint48);

    /// @notice         Get current fee charged by the teller for a partner's markets
    /// @param partner_ Address of the partner
    /// @return         Fee in basis points (3 decimal places)
    function getFee(address partner_) external view returns (uint48);

    /// @notice         Set fee for a partner tier
    /// @notice         Must be guardian
    /// @param tier_    Tier index for the fee being set (0 is the Default tier)
    /// @param fee_     Protocol fee in basis points (3 decimal places)
    function setFeeTier(uint256 tier_, uint48 fee_) external;

    /// @notice         Set the fee tier applicable to a partner
    /// @notice         Must be guardian
    /// @param partner_ Address of the partner
    /// @param tier_    Tier index to set for the partner (0 is the Default tier)
    function setPartnerFeeTier(address partner_, uint256 tier_) external;

    /// @notice         Claim fees accrued for input tokens and sends to protocol
    /// @notice         Must be guardian
    /// @param tokens_  Array of tokens to claim fees for
    function claimFees(ERC20[] memory tokens_) external;

    /// @notice         Changes a token's status as a protocol-preferred fee token
    /// @notice         Must be policy
    /// @param token_   ERC20 token to set the status for
    /// @param status_  Add preferred fee token (true) or remove preferred fee token (false)
    function changePreferredTokenStatus(ERC20 token_, bool status_) external;
}
