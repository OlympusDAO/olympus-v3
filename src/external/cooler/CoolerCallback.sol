// SPDX-License-Identifier: MIT
/// forge-lint: disable-start(screaming-snake-case-immutable)
pragma solidity >=0.8.0;

import {CoolerFactory} from "./CoolerFactory.sol";

/// @notice Allows for debt issuers to execute logic when a loan is repaid, rolled, or defaulted.
/// @dev    The three callback functions must be implemented if `isCoolerCallback()` is set to true.
abstract contract CoolerCallback {
    // --- ERRORS ----------------------------------------------------

    error OnlyFromFactory();

    // --- INITIALIZATION --------------------------------------------

    CoolerFactory public immutable factory;

    constructor(address coolerFactory_) {
        factory = CoolerFactory(coolerFactory_);
    }

    // --- EXTERNAL FUNCTIONS ------------------------------------------------

    /// @notice Informs to Cooler that this contract can handle its callbacks.
    function isCoolerCallback() external pure returns (bool) {
        return true;
    }

    /// @notice Callback function that handles repayments.
    function onRepay(uint256 loanID_, uint256 principlePaid_, uint256 interestPaid_) external {
        if (!factory.created(msg.sender)) revert OnlyFromFactory();
        _onRepay(loanID_, principlePaid_, interestPaid_);
    }

    /// @notice Callback function that handles defaults.
    function onDefault(
        uint256 loanID_,
        uint256 principle,
        uint256 interest,
        uint256 collateral
    ) external {
        if (!factory.created(msg.sender)) revert OnlyFromFactory();
        _onDefault(loanID_, principle, interest, collateral);
    }

    // --- INTERNAL FUNCTIONS ------------------------------------------------

    /// @notice Callback function that handles repayments. Override for custom logic.
    function _onRepay(
        uint256 loanID_,
        uint256 principlePaid_,
        uint256 interestPaid_
    ) internal virtual;

    /// @notice Callback function that handles defaults.
    function _onDefault(
        uint256 loanID_,
        uint256 principle_,
        uint256 interestDue_,
        uint256 collateral
    ) internal virtual;
}
/// forge-lint: disable-end(screaming-snake-case-immutable)
