// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "modules/SPPLY/SPPLY.v1.sol";

/// @title      CustomSupply
/// @author     0xJem
/// @notice     Abstract SPPLY submodule with configurable supply values
/// @dev        This submodule can be used when there are contract interactions that are
///             unable to be supported by a standard SPPLY submodule.
///
///             For example:
///             - OHM supply in non-Ethereum mainnet lending markets (as cross-chain supply is not categorized)
///             - OHM supply in non-Ethereum mainnet AMMs (as cross-chain supply is not categorized)
///
///             This submodule is intended to be used as a parent contract for a custom submodule. This is mainly
///             due to the value returned by the `SUBKEYCODE()` function needs to be unique for each submodule,
///             but as it is a pure function, it cannot read from the state of the contract.
abstract contract CustomSupply is SupplySubmodule {

    // ========== EVENTS ========== //

    event CollateralizedValueUpdated(uint256 value);
    event ProtocolOwnedBorrowableValueUpdated(uint256 value);
    event ProtocolOwnedLiquidityValueUpdated(uint256 value);

    // ========== STATE VARIABLES ========== //

    /// @notice     The custom value for collateralized OHM
    uint256 private _collateralizedOhm;

    /// @notice     The custom value for protocol-owned borrowable OHM
    uint256 private _protocolOwnedBorrowableOhm;

    /// @notice     The custom value for protocol-owned liquidity OHM
    uint256 private _protocolOwnedLiquidityOhm;

    // ========== CONSTRUCTOR ========== //

    constructor(Module parent_, uint256 collateralizedOhm_, uint256 protocolOwnedBorrowableOhm_, uint256 protocolOwnedLiquidityOhm_) Submodule(parent_) {
        _collateralizedOhm = collateralizedOhm_;
        _protocolOwnedBorrowableOhm = protocolOwnedBorrowableOhm_;
        _protocolOwnedLiquidityOhm = protocolOwnedLiquidityOhm_;

        emit CollateralizedValueUpdated(collateralizedOhm_);
        emit ProtocolOwnedBorrowableValueUpdated(protocolOwnedBorrowableOhm_);
        emit ProtocolOwnedLiquidityValueUpdated(protocolOwnedLiquidityOhm_);
    }

    // ========== DATA FUNCTIONS ========== //

    function getCollateralizedOhm() external view virtual override returns (uint256) {
        return _collateralizedOhm;
    }

    function getProtocolOwnedBorrowableOhm() external view virtual override returns (uint256) {
        return _protocolOwnedBorrowableOhm;
    }

    function getProtocolOwnedLiquidityOhm() external view virtual override returns (uint256) {
        return _protocolOwnedLiquidityOhm;
    }

    // =========== ADMIN FUNCTIONS =========== //

    function setCollateralizedOhm(uint256 value_) external onlyParent {
        _collateralizedOhm = value_;

        emit CollateralizedValueUpdated(value_);
    }

    function setProtocolOwnedBorrowableOhm(uint256 value_) external onlyParent {
        _protocolOwnedBorrowableOhm = value_;

        emit ProtocolOwnedBorrowableValueUpdated(value_);
    }

    function setProtocolOwnedLiquidityOhm(uint256 value_) external onlyParent {
        _protocolOwnedLiquidityOhm = value_;

        emit ProtocolOwnedLiquidityValueUpdated(value_);
    }
}