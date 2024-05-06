// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {Module} from "src/Kernel.sol";
import {Submodule, SubKeycode, toSubKeycode} from "src/Submodules.sol";
import {SupplySubmodule, SPPLYv1} from "src/modules/SPPLY/SPPLY.v1.sol";

/// @title      LiquiditySupply
/// @author     0xJem
/// @notice     SPPLY submodule representing an admin-defined amount of OHM in protocol-owned liquidity.
///             This can be used in instances where the OHM is deployed in liquidity pools,
///             but the LP token or position is not managed by the on-chain accounting system
///             and hence not accounted for.
contract LiquiditySupply is SupplySubmodule {
    // ========== EVENTS ========== //

    event LiquiditySupplyAdded(uint256 amount, address source);

    event LiquiditySupplyRemoved(uint256 amount, address source);

    // ========== ERRORS ========== //

    /// @notice     Invalid parameters were passed to a function
    error LiquiditySupply_InvalidParams();

    // ========== STATE VARIABLES ========== //

    /// @notice The amount of OHM in protocol-owned liquidity
    uint256[] public protocolOwnedLiquidityAmounts;

    /// @notice The total amount of OHM in protocol-owned liquidity
    uint256 internal _polOhmTotalAmount;

    /// @notice The sources of the OHM in protocol-owned liquidity
    address[] public protocolOwnedLiquiditySources;

    // ========== CONSTRUCTOR ========== //

    constructor(
        Module parent_,
        uint256[] memory polOhmAmounts_,
        address[] memory polSources_
    ) Submodule(parent_) {
        // Assert that the arrays have the same length
        if (polOhmAmounts_.length != polSources_.length) revert LiquiditySupply_InvalidParams();

        // Add to the arrays
        for (uint256 i = 0; i < polOhmAmounts_.length; i++) {
            // Check that the source is not 0
            if (polSources_[i] == address(0)) revert LiquiditySupply_InvalidParams();

            // Check that the source is not already present
            bool found = _inArray(polSources_[i]);
            if (found) revert LiquiditySupply_InvalidParams();

            protocolOwnedLiquidityAmounts.push(polOhmAmounts_[i]);
            protocolOwnedLiquiditySources.push(polSources_[i]);

            _polOhmTotalAmount += polOhmAmounts_[i];

            emit LiquiditySupplyAdded(polOhmAmounts_[i], polSources_[i]);
        }
    }

    // ========== SUBMODULE SETUP ========== //

    /// @inheritdoc Submodule
    function SUBKEYCODE() public pure override returns (SubKeycode) {
        return toSubKeycode("SPPLY.LIQSPPLY");
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
    function storeObservations() external virtual override {
        // Nothing to do
    }

    function getCollateralizedOhm() external view virtual override returns (uint256) {
        return 0;
    }

    function getProtocolOwnedBorrowableOhm() external view virtual override returns (uint256) {
        return 0;
    }

    function getProtocolOwnedTreasuryOhm() external view virtual override returns (uint256) {
        return 0;
    }

    function getProtocolOwnedLiquidityOhm() external view virtual override returns (uint256) {
        return _polOhmTotalAmount;
    }

    function getProtocolOwnedLiquidityReserves()
        external
        view
        virtual
        override
        returns (SPPLYv1.Reserves[] memory reserves)
    {
        address ohm = address(SPPLYv1(address(parent)).ohm());
        uint256 len = protocolOwnedLiquiditySources.length;
        reserves = new SPPLYv1.Reserves[](len);

        for (uint256 i; i < len; ) {
            address[] memory tokens = new address[](1);
            tokens[0] = ohm;

            uint256[] memory balances = new uint256[](1);
            balances[0] = protocolOwnedLiquidityAmounts[i];

            reserves[i] = SPPLYv1.Reserves({
                source: protocolOwnedLiquiditySources[i],
                tokens: tokens,
                balances: balances
            });
        }
    }

    function getSourceCount() external view virtual override returns (uint256) {
        return protocolOwnedLiquiditySources.length;
    }

    // ========== ADMIN FUNCTIONS ========== //

    function addLiquiditySupply(uint256 amount_, address source_) external onlyParent {
        // Check that the address is not 0
        if (source_ == address(0)) revert LiquiditySupply_InvalidParams();

        // Check that the source is not already present
        bool found = _inArray(source_);
        if (found) revert LiquiditySupply_InvalidParams();

        protocolOwnedLiquidityAmounts.push(amount_);
        protocolOwnedLiquiditySources.push(source_);

        _polOhmTotalAmount += amount_;

        emit LiquiditySupplyAdded(amount_, source_);
    }

    function removeLiquiditySupply(uint256 amount_, address source_) external onlyParent {
        // Check that the address is not 0
        if (source_ == address(0)) revert LiquiditySupply_InvalidParams();

        // Check that the source is present
        bool found = _inArray(source_);
        if (!found) revert LiquiditySupply_InvalidParams();

        // Remove the source
        for (uint256 i = 0; i < protocolOwnedLiquiditySources.length; i++) {
            if (protocolOwnedLiquiditySources[i] == source_) {
                protocolOwnedLiquidityAmounts[i] = protocolOwnedLiquidityAmounts[
                    protocolOwnedLiquidityAmounts.length - 1
                ];
                protocolOwnedLiquidityAmounts.pop();

                protocolOwnedLiquiditySources[i] = protocolOwnedLiquiditySources[
                    protocolOwnedLiquiditySources.length - 1
                ];
                protocolOwnedLiquiditySources.pop();

                break;
            }
        }

        _polOhmTotalAmount -= amount_;

        emit LiquiditySupplyRemoved(amount_, source_);
    }

    // =========== HELPER FUNCTIONS =========== //

    /// @notice     Determines if `source_` is contained in the `_polSources` array
    ///
    /// @param      source_  The address of a liquidity source
    /// @return     True if the address is in the array, false otherwise
    function _inArray(address source_) internal view returns (bool) {
        uint256 len = protocolOwnedLiquiditySources.length;
        for (uint256 i; i < len; ) {
            if (source_ == address(protocolOwnedLiquiditySources[i])) {
                return true;
            }
            unchecked {
                ++i;
            }
        }

        return false;
    }
}
