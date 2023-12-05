// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "modules/SPPLY/SPPLY.v1.sol";

/// @title      CustomSupply
/// @author     0xJem
/// @notice     Abstract SPPLY submodule with configurable supply values
/// @dev        This submodule can be used when there are contract interactions that are
/// @dev        unable to be supported by a standard SPPLY submodule.
///
/// @dev        For example:
/// @dev        - OHM supply in non-Ethereum mainnet lending markets (as cross-chain supply is not categorized)
/// @dev        - OHM supply in non-Ethereum mainnet AMMs (as cross-chain supply is not categorized)
///
/// @dev        This submodule is intended to be used as a parent contract for a custom submodule. This is mainly
/// @dev        due to the value returned by the `SUBKEYCODE()` function needs to be unique for each submodule,
/// @dev        but as it is a pure function, it cannot read from the state of the contract.
abstract contract CustomSupply is SupplySubmodule {
    // ========== EVENTS ========== //

    event CollateralizedValueUpdated(uint256 value);
    event ProtocolOwnedBorrowableValueUpdated(uint256 value);
    event ProtocolOwnedLiquidityValueUpdated(uint256 value);
    event SourceValueUpdated(address value);

    // ========== STATE VARIABLES ========== //

    /// @notice     The custom value for collateralized OHM
    uint256 private _collateralizedOhm;

    /// @notice     The custom value for protocol-owned borrowable OHM
    uint256 private _protocolOwnedBorrowableOhm;

    /// @notice     The custom value for protocol-owned liquidity OHM
    uint256 private _protocolOwnedLiquidityOhm;

    /// @notice     The custom value for protocol-owned treasury OHM
    uint256 private _protocolOwnedTreasuryOhm;

    /// @notice     The custom value for the source
    address private _source;

    // ========== CONSTRUCTOR ========== //

    constructor(
        Module parent_,
        uint256 collateralizedOhm_,
        uint256 protocolOwnedBorrowableOhm_,
        uint256 protocolOwnedLiquidityOhm_,
        uint256 protocolOwnedTreasuryOhm_,
        address source_
    ) Submodule(parent_) {
        _collateralizedOhm = collateralizedOhm_;
        _protocolOwnedBorrowableOhm = protocolOwnedBorrowableOhm_;
        _protocolOwnedLiquidityOhm = protocolOwnedLiquidityOhm_;
        _protocolOwnedTreasuryOhm = protocolOwnedTreasuryOhm_;
        _source = source_;

        emit CollateralizedValueUpdated(collateralizedOhm_);
        emit ProtocolOwnedBorrowableValueUpdated(protocolOwnedBorrowableOhm_);
        emit ProtocolOwnedLiquidityValueUpdated(protocolOwnedLiquidityOhm_);
        emit SourceValueUpdated(source_);
    }

    // ========== DATA FUNCTIONS ========== //

    /// @inheritdoc SupplySubmodule
    function getCollateralizedOhm() external view virtual override returns (uint256) {
        return _collateralizedOhm;
    }

    /// @inheritdoc SupplySubmodule
    function getProtocolOwnedBorrowableOhm() external view virtual override returns (uint256) {
        return _protocolOwnedBorrowableOhm;
    }

    /// @inheritdoc SupplySubmodule
    function getProtocolOwnedLiquidityOhm() external view virtual override returns (uint256) {
        return _protocolOwnedLiquidityOhm;
    }

    function getProtocolOwnedTreasuryOhm() external view virtual override returns (uint256) {
        return _protocolOwnedTreasuryOhm;
    }

    /// @inheritdoc SupplySubmodule
    function getProtocolOwnedLiquidityReserves()
        external
        view
        virtual
        override
        returns (SPPLYv1.Reserves[] memory)
    {
        address[] memory tokens = new address[](1);
        tokens[0] = address(SPPLYv1(address(parent)).ohm());
        uint256[] memory balances = new uint256[](1);
        balances[0] = _protocolOwnedLiquidityOhm;

        SPPLYv1.Reserves[] memory reserves = new SPPLYv1.Reserves[](1);
        reserves[0] = SPPLYv1.Reserves({source: _source, tokens: tokens, balances: balances});

        return reserves;
    }

    /// @inheritdoc SupplySubmodule
    function getSourceCount() external pure virtual override returns (uint256) {
        return 1;
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

    function setSource(address source_) external onlyParent {
        _source = source_;

        emit SourceValueUpdated(source_);
    }
}
