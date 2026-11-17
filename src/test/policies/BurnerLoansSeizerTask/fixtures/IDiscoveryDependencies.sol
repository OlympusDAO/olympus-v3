// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

// Narrow interfaces let Solidity resolve selectors for overloaded dependency methods.
interface IDiscoveryPrice {
    /// @notice Reads a selected price variant and its associated timestamp.
    /// @param asset_ Asset whose price is requested.
    /// @param variant_ Price variant to read.
    /// @return price Price in the PRICE module's decimal scale.
    /// @return timestamp Timestamp associated with the selected price.
    function getPrice(
        address asset_,
        IPRICEv2.Variant variant_
    ) external view returns (uint256 price, uint48 timestamp);
}

interface IDiscoveryWithdrawal {
    /// @notice Withdraws collateral through the selected custody output path.
    /// @param params_ DepositManager withdrawal request.
    /// @param shares_ Whether to return vault shares instead of underlying assets.
    /// @return token Actual output token.
    /// @return amount Actual output amount in that token's raw units.
    function withdraw(
        IDepositManager.WithdrawParams calldata params_,
        bool shares_
    ) external returns (IERC20 token, uint256 amount);
}

// ROLES exposes this getter through a public mapping, which has no type-level selector.
interface IDiscoveryRoles {
    /// @notice Reports whether a caller holds a role.
    /// @param caller_ Account whose role membership is checked.
    /// @param role_ Role identifier.
    /// @return assigned Whether the role is assigned to the caller.
    function hasRole(address caller_, bytes32 role_) external view returns (bool assigned);
}
