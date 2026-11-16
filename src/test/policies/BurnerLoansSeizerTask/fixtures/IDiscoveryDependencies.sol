// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

// Narrow interfaces let Solidity resolve selectors for overloaded dependency methods.
interface IDiscoveryPrice {
    function getPrice(
        address asset_,
        IPRICEv2.Variant variant_
    ) external view returns (uint256, uint48);
}

interface IDiscoveryWithdrawal {
    function withdraw(
        IDepositManager.WithdrawParams calldata params_,
        bool shares_
    ) external returns (IERC20, uint256);
}

// ROLES exposes this getter through a public mapping, which has no type-level selector.
interface IDiscoveryRoles {
    function hasRole(address caller_, bytes32 role_) external view returns (bool);
}
