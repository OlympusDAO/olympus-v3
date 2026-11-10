// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Interfaces
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";

/// @dev Admitted ADMIN callback rotates twice during public economic preparation.
contract CollateralPreparationAuthRotation {
    function rotate(IBurnerLoansCore core_, address next_) external {
        // Only the selected verifier is needed to rotate back; each selection advances its epoch.
        // forge-lint: disable-next-line(unused-return)
        (address previous, ) = core_.authConfig();
        core_.setAuth(next_);
        core_.setAuth(previous);
    }
}
