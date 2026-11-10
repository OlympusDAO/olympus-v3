// SPDX-License-Identifier: MIT
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/interfaces/IERC165.sol";

/// @notice One-use governance launcher for an already deployed and Kernel-prepared Burner Loans stack.
interface IBurnerLoansActivator is IERC165 {
    /// @notice A fixed deployment graph and its external dependencies.
    /// @dev Assets and vaults are supplied explicitly so the reviewed graph can be reproduced in tests.
    struct Deployment {
        address kernel;
        address ohm;
        address floan;
        address depositManager;
        address core;
        address auth;
        address config;
        address inventory;
        address payout;
        address risk;
        address collateral;
        address debt;
        address seize;
        address lens;
        address seizerTask;
        address yieldClaimerTask;
        address configTimelock;
        address riskTimelock;
        address payoutTimelock;
        address inventoryTimelock;
        address priceConfig;
        address priceCache;
        address revenueDistributor;
        address revenueDistributorTimelock;
        address revenueDistributorTask;
        address heart;
        address usds;
        address usde;
        address susds;
        address susde;
        address backingOracle;
    }

    /// @notice The caller is not the constructor-bound governance timelock.
    error BurnerLoansActivator_NotTimelock(address caller);
    /// @notice The one-use activation has already completed.
    error BurnerLoansActivator_AlreadyActivated();
    /// @notice A supplied address or binding is invalid.
    error BurnerLoansActivator_InvalidDeployment(address target);
    /// @notice An installation, activation or fresh-state prerequisite is not satisfied.
    error BurnerLoansActivator_InvalidPrerequisite(address target);

    /// @notice Emitted after the whole activation completes successfully.
    event Activated(address indexed caller);

    /// @notice Returns the sole account allowed to execute activation.
    function timelock() external view returns (address);

    /// @notice Returns whether activation has completed.
    function isActivated() external view returns (bool);

    /// @notice Enables and configures the prepared system once, atomically.
    function activate() external;
}
