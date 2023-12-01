// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "modules/SPPLY/SPPLY.v1.sol";

// Example contract: https://etherscan.io/address/0xd9d87586774fb9d036fa95a5991474513ff6c96e#readContract
interface IIncurDebt {
    function totalOutstandingGlobalDebt() external view returns (uint256);
}

/// @title  IncurDebtSupply
/// @author 0xJem
/// @notice Calculates the amount of OHM in the IncurDebt contract(s)
contract IncurDebtSupply is SupplySubmodule {
    // IncurDebt involves gOHM being deposited into the contract, and then being used to mint OHM.
    // That OHM is combined with another token to form a liquidity pair.
    //
    // No OHM is borrowable
    // All OHM is collateralized
    // No OHM is liquidity
    // Therefore:
    // Protocol-owned Borrowable OHM = 0
    // Collateralized OHM = OHM minted by the contract
    // Protocol-owned Liquidity OHM = 0

    // ========== ERRORS ========== //

    /// @notice     Invalid parameters were passed to a function
    error IncurDebtSupply_InvalidParams();

    // ========== EVENTS ========== //

    /// @notice     Emitted when the address of the IncurDebt contract is updated
    event IncurDebtUpdated(address incurDebt_);

    // ========== STATE VARIABLES ========== //

    IIncurDebt internal _incurDebt;

    // ========== CONSTRUCTOR ========== //

    /// @notice             Constructor for the IncurDebtSupply submodule
    /// @dev                Will revert if:
    /// @dev                - Calling the `Submodule` constructor fails
    /// @dev                - The `incurDebt_` address is the zero address
    ///
    /// @dev                Emits the IncurDebtUpdated event
    ///
    /// @param parent_      The address of the parent SPPLY module
    /// @param incurDebt_   The address of the IncurDebt contract
    constructor(Module parent_, address incurDebt_) Submodule(parent_) {
        // Check for zero address
        if (incurDebt_ == address(0)) revert IncurDebtSupply_InvalidParams();

        _incurDebt = IIncurDebt(incurDebt_);

        emit IncurDebtUpdated(incurDebt_);
    }

    // ========== SUBMODULE SETUP ========== //

    /// @inheritdoc Submodule
    function SUBKEYCODE() public pure override returns (SubKeycode) {
        return toSubKeycode("SPPLY.INCURDEBT");
    }

    /// @inheritdoc Submodule
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    /// @inheritdoc Submodule
    function INIT() external override onlyParent {}

    // ========== DATA FUNCTIONS ========== //

    /// @inheritdoc SupplySubmodule
    /// @dev        The value of IncurDebt.totalOutstandingGlobalDebt() is returned, as
    ///             the OHM minted against gOHM collateral is fully-collateralized.
    function getCollateralizedOhm() external view override returns (uint256) {
        return _incurDebt.totalOutstandingGlobalDebt();
    }

    /// @inheritdoc SupplySubmodule
    /// @dev        Not applicable to IncurDebt
    function getProtocolOwnedBorrowableOhm() external pure override returns (uint256) {
        return 0;
    }

    /// @inheritdoc SupplySubmodule
    /// @dev        Not applicable to IncurDebt
    function getProtocolOwnedLiquidityOhm() external pure override returns (uint256) {
        return 0;
    }

    /// @inheritdoc SupplySubmodule
    /// @dev        Not applicable to IncurDebt
    function getProtocolOwnedTreasuryOhm() external pure override returns (uint256) {
        return 0;
    }

    /// @inheritdoc     SupplySubmodule
    /// @dev            Protocol-owned liquidity OHM is always zero for lending facilities.
    /// @dev
    ///                 This function returns an array with the same length as `getSourceCount()`, but with empty values.
    function getProtocolOwnedLiquidityReserves()
        external
        view
        override
        returns (SPPLYv1.Reserves[] memory)
    {
        SPPLYv1.Reserves[] memory reserves = new SPPLYv1.Reserves[](1);
        reserves[0] = SPPLYv1.Reserves({
            source: address(_incurDebt),
            tokens: new address[](0),
            balances: new uint256[](0)
        });

        return reserves;
    }

    /// @inheritdoc     SupplySubmodule
    /// @dev            This always returns a value of one, as there is a 1:1 mapping between an IncurDebt contract and the Submodule
    function getSourceCount() external pure override returns (uint256) {
        return 1;
    }

    // ========== ADMIN FUNCTIONS ========== //

    /// @notice             Set the address of the IncurDebt contract
    /// @dev                Will revert if:
    /// @dev                - The address is the zero address
    /// @dev                - The caller is not the parent module
    ///
    /// @dev                Emits the IncurDebtUpdated event
    ///
    /// @param incurDebt_   The address of the IncurDebt contract
    function setIncurDebt(address incurDebt_) external onlyParent {
        // Check for zero address
        if (incurDebt_ == address(0)) revert IncurDebtSupply_InvalidParams();

        _incurDebt = IIncurDebt(incurDebt_);

        emit IncurDebtUpdated(incurDebt_);
    }

    // ========== VIEWS ========== //

    /// @notice     Get the address of the IncurDebt contract
    ///
    /// @return     The address of the IncurDebt contract
    function getIncurDebt() external view returns (address) {
        return address(_incurDebt);
    }
}
