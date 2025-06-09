// SPDX-License-Identifier: MIT
pragma solidity >=0.8.15;

interface IPolicyEnabler {
    // ===== ERRORS ===== //

    error NotDisabled();
    error NotEnabled();

    // ===== EVENTS ===== //

    event Disabled();
    event Enabled();

    // ===== FUNCTIONS ===== //

    function isEnabled() external view returns (bool);

    function enable(bytes calldata) external;

    function disable(bytes calldata) external;
}
