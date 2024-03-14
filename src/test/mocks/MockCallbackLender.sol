// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {CoolerCallback} from "src/external/cooler/CoolerCallback.sol";
import {Cooler} from "src/external/cooler/Cooler.sol";

contract MockLender is CoolerCallback {
    constructor(address coolerFactory_) CoolerCallback(coolerFactory_) {}

    /// @notice Callback function that handles repayments. Override for custom logic.
    function _onRepay(uint256 loanID_, uint256 principle_, uint256 interest_) internal override {
        // callback logic
    }

    /// @notice Callback function that handles defaults.
    function _onDefault(
        uint256 loanID_,
        uint256 principle_,
        uint256 interestDue_,
        uint256 collateral_
    ) internal override {
        // callback logic
    }
}
