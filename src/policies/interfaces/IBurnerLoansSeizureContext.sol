// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IERC20} from "src/interfaces/IERC20.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IFLOANv1} from "src/modules/FLOAN/IFLOAN.v1.sol";
import {ROLESv1} from "src/modules/ROLES/ROLES.v1.sol";
import {IBurnerLoansInventory} from "src/policies/interfaces/IBurnerLoansInventory.sol";
import {IDepositManager} from "src/policies/interfaces/deposits/IDepositManager.sol";

struct BurnerLoansContext {
    IERC20 ohm;
    uint8 ohmDecimals;
    IDepositManager depositManager;
    address facility;
    IBurnerLoansInventory inventory;
    address backingOracle;
    IFLOANv1 floan;
    IPRICEv2 price;
    address treasury;
    ROLESv1 roles;
}

/// @title Burner Loans Seizure Context
/// @notice Exposes one dependency snapshot shared by the linked lifecycle libraries.
interface IBurnerLoansSeizureContext {
    /// @notice Returns the policy's current module, token, custody, and risk dependencies.
    /// @return BurnerLoansContext The current Burner Loans dependency snapshot.
    function context() external view returns (BurnerLoansContext memory);
}
