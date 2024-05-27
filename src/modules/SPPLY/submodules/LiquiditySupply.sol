// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import {Module} from "src/Kernel.sol";
import {Submodule, SubKeycode, toSubKeycode} from "src/Submodules.sol";
import {SupplySubmodule, SPPLYv1} from "src/modules/SPPLY/SPPLY.v1.sol";
import {OlympusERC20Token as OHM} from "src/external/OlympusERC20.sol";
import {IgOHM} from "src/interfaces/IgOHM.sol";

/// @title      LiquiditySupply
/// @author     0xJem
/// @notice     SPPLY submodule representing an admin-defined amount of OHM and/or gOHM in protocol-owned liquidity.
///             This can be used in instances where the OHM and/or gOHM is deployed in liquidity pools,
///             but the LP token or position is not managed by the on-chain accounting system
///             and hence not accounted for.
contract LiquiditySupply is SupplySubmodule {
    // ========== EVENTS ========== //

    event LiquiditySupplyAdded(uint256 amount, address source, bool gOhm);

    event LiquiditySupplyRemoved(uint256 amount, address source, bool gOhm);

    event LiquiditySupplyUpdated(
        bool positive_,
        uint256 adjustment,
        uint256 updatedAmount,
        address source,
        bool gOhm
    );

    // ========== ERRORS ========== //

    /// @notice     Invalid parameters were passed to a function
    error LiquiditySupply_InvalidParams();

    // ========== STATE VARIABLES ========== //

    /// @notice The OHM token
    OHM internal _ohm;

    /// @notice The gOHM token
    IgOHM internal _gOhm;

    /// @notice The amount of OHM in protocol-owned liquidity
    uint256[] public ohmAmounts;

    /// @notice The amount of gOHM in protocol-owned liquidity
    uint256[] public gOhmAmounts;

    /// @notice The total amount of OHM in protocol-owned liquidity
    uint256 internal _polOhmTotalAmount;

    /// @notice The total amount of gOHM in protocol-owned liquidity
    uint256 internal _polGOhmTotalAmount;

    /// @notice The sources of the OHM in protocol-owned liquidity
    address[] public ohmSources;

    /// @notice The sources of the gOHM in protocol-owned liquidity
    address[] public gOhmSources;

    // ========== CONSTRUCTOR ========== //

    constructor(
        Module parent_,
        uint256[] memory ohmAmounts_,
        address[] memory ohmSources_,
        uint256[] memory gOhmAmounts_,
        address[] memory gOhmSources_
    ) Submodule(parent_) {
        // Assert that the arrays have the same length
        if (ohmAmounts_.length != ohmSources_.length) revert LiquiditySupply_InvalidParams();

        if (gOhmAmounts_.length != gOhmSources_.length) revert LiquiditySupply_InvalidParams();

        // Add to the OHM arrays
        for (uint256 i = 0; i < ohmAmounts_.length; i++) {
            // Check that the source is not 0
            if (ohmSources_[i] == address(0)) revert LiquiditySupply_InvalidParams();

            // Check that the source is not already present
            bool found = _inArray(ohmSources_[i], ohmSources);
            if (found) revert LiquiditySupply_InvalidParams();

            ohmAmounts.push(ohmAmounts_[i]);
            ohmSources.push(ohmSources_[i]);

            _polOhmTotalAmount += ohmAmounts_[i];

            emit LiquiditySupplyAdded(ohmAmounts_[i], ohmSources_[i], false);
        }

        // Add to the gOHM arrays
        for (uint256 i = 0; i < gOhmAmounts_.length; i++) {
            // Check that the source is not 0
            if (gOhmSources_[i] == address(0)) revert LiquiditySupply_InvalidParams();

            // Check that the source is not already present
            bool found = _inArray(gOhmSources_[i], gOhmSources);
            if (found) revert LiquiditySupply_InvalidParams();

            gOhmAmounts.push(gOhmAmounts_[i]);
            gOhmSources.push(gOhmSources_[i]);

            _polGOhmTotalAmount += gOhmAmounts_[i];

            emit LiquiditySupplyAdded(gOhmAmounts_[i], gOhmSources_[i], true);
        }

        _ohm = SPPLYv1(address(parent)).ohm();
        _gOhm = SPPLYv1(address(parent)).gohm();
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

    /// @inheritdoc SupplySubmodule
    /// @dev        This function always returns 0.
    function getCollateralizedOhm() external view virtual override returns (uint256) {
        return 0;
    }

    /// @inheritdoc SupplySubmodule
    /// @dev        This function always returns 0.
    function getProtocolOwnedBorrowableOhm() external view virtual override returns (uint256) {
        return 0;
    }

    /// @inheritdoc SupplySubmodule
    /// @dev        This function always returns 0.
    function getProtocolOwnedTreasuryOhm() external view virtual override returns (uint256) {
        return 0;
    }

    /// @inheritdoc SupplySubmodule
    /// @dev        This function returns the total configured amount of OHM in protocol-owned liquidity.
    function getProtocolOwnedLiquidityOhm() external view virtual override returns (uint256) {
        // Get the quantity of gOHM in OHM terms
        uint256 gOhmInOhm = _gOhm.balanceFrom(_polGOhmTotalAmount);

        return _polOhmTotalAmount + gOhmInOhm;
    }

    /// @inheritdoc SupplySubmodule
    function getProtocolOwnedLiquidityReserves()
        external
        view
        virtual
        override
        returns (SPPLYv1.Reserves[] memory reserves)
    {
        address ohm = address(_ohm);
        uint256 ohmLen = ohmSources.length;
        uint256 gOhmLen = gOhmSources.length;
        reserves = new SPPLYv1.Reserves[](ohmLen + gOhmLen);

        for (uint256 i; i < ohmLen; i++) {
            address[] memory tokens = new address[](1);
            tokens[0] = ohm;

            uint256[] memory balances = new uint256[](1);
            balances[0] = ohmAmounts[i];

            reserves[i] = SPPLYv1.Reserves({
                source: ohmSources[i],
                tokens: tokens,
                balances: balances
            });
        }

        // Iterate over all gOHM sources
        for (uint256 i; i < gOhmLen; i++) {
            // Reports the gOHM balance in terms of OHM, for simplicity
            address[] memory tokens = new address[](1);
            tokens[0] = ohm;

            uint256[] memory balances = new uint256[](1);
            balances[0] = _gOhm.balanceFrom(gOhmAmounts[i]);

            reserves[ohmLen + i] = SPPLYv1.Reserves({
                source: gOhmSources[i],
                tokens: tokens,
                balances: balances
            });
        }
    }

    /// @inheritdoc SupplySubmodule
    /// @dev        This function returns the number of configured sources.
    function getSourceCount() external view virtual override returns (uint256) {
        return ohmSources.length + gOhmSources.length;
    }

    // ========== ADMIN FUNCTIONS ========== //

    /// @notice Add a new source of OHM protocol-owned liquidity
    /// @dev    This function reverts if:
    ///         - The caller is not the parent module
    ///         - The source is the zero address
    ///         - The source is already present
    ///
    /// @param  amount_     The amount of OHM in the liquidity
    /// @param  source_     The address of the liquidity source
    function addOhmLiquidity(uint256 amount_, address source_) external onlyParent {
        // Check that the address is not 0
        if (source_ == address(0)) revert LiquiditySupply_InvalidParams();

        // Check that the source is not already present
        bool found = _inArray(source_, ohmSources);
        if (found) revert LiquiditySupply_InvalidParams();

        ohmAmounts.push(amount_);
        ohmSources.push(source_);

        _polOhmTotalAmount += amount_;

        emit LiquiditySupplyAdded(amount_, source_, false);
    }

    /// @notice Add a new source of gOHM protocol-owned liquidity
    /// @dev    This function reverts if:
    ///         - The caller is not the parent module
    ///         - The source is the zero address
    ///         - The source is already present
    ///
    /// @param  amount_     The amount of gOHM in the liquidity
    /// @param  source_     The address of the liquidity source
    function addGOhmLiquidity(uint256 amount_, address source_) external onlyParent {
        // Check that the address is not 0
        if (source_ == address(0)) revert LiquiditySupply_InvalidParams();

        // Check that the source is not already present
        bool found = _inArray(source_, gOhmSources);
        if (found) revert LiquiditySupply_InvalidParams();

        gOhmAmounts.push(amount_);
        gOhmSources.push(source_);

        _polGOhmTotalAmount += amount_;

        emit LiquiditySupplyAdded(amount_, source_, true);
    }

    /// @notice Remove a source of OHM protocol-owned liquidity
    /// @dev    This function reverts if:
    ///         - The caller is not the parent module
    ///         - The source is the zero address
    ///         - The source is not present
    ///
    /// @param  source_     The address of the liquidity source
    function removeOhmLiquidity(address source_) external onlyParent {
        // Check that the address is not 0
        if (source_ == address(0)) revert LiquiditySupply_InvalidParams();

        // Check that the source is present
        bool found = _inArray(source_, ohmSources);
        if (!found) revert LiquiditySupply_InvalidParams();

        // Remove the source
        uint256 foundAmount;
        for (uint256 i = 0; i < ohmSources.length; i++) {
            if (ohmSources[i] == source_) {
                foundAmount = ohmAmounts[i];

                ohmAmounts[i] = ohmAmounts[ohmAmounts.length - 1];
                ohmAmounts.pop();

                ohmSources[i] = ohmSources[ohmSources.length - 1];
                ohmSources.pop();

                break;
            }
        }

        _polOhmTotalAmount -= foundAmount;

        emit LiquiditySupplyRemoved(foundAmount, source_, false);
    }

    /// @notice Remove a source of gOHM protocol-owned liquidity
    /// @dev    This function reverts if:
    ///         - The caller is not the parent module
    ///         - The source is the zero address
    ///         - The source is not present
    ///
    /// @param  source_     The address of the liquidity source
    function removeGOhmLiquidity(address source_) external onlyParent {
        // Check that the address is not 0
        if (source_ == address(0)) revert LiquiditySupply_InvalidParams();

        // Check that the source is present
        bool found = _inArray(source_, gOhmSources);
        if (!found) revert LiquiditySupply_InvalidParams();

        // Remove the source
        uint256 foundAmount;
        for (uint256 i = 0; i < gOhmSources.length; i++) {
            if (gOhmSources[i] == source_) {
                foundAmount = gOhmAmounts[i];

                gOhmAmounts[i] = gOhmAmounts[gOhmAmounts.length - 1];
                gOhmAmounts.pop();

                gOhmSources[i] = gOhmSources[gOhmSources.length - 1];
                gOhmSources.pop();

                break;
            }
        }

        _polGOhmTotalAmount -= foundAmount;

        emit LiquiditySupplyRemoved(foundAmount, source_, true);
    }

    /// @notice Adjust the amount of OHM in protocol-owned liquidity for the specified source
    /// @dev    This function reverts if:
    ///         - The caller is not the parent module
    ///         - The source is the zero address
    ///         - The source is not present
    ///         - The new amount is less than 0 or greater than uint256 max
    ///
    /// @param  amount_     The amount to increase or decrease the OHM liquidity by
    /// @param  add_        True if the adjustment is addition, false if subtraction
    /// @param  source_     The address of the liquidity source
    function adjustOhmLiquidity(uint256 amount_, bool add_, address source_) external onlyParent {
        // Check that the address is not 0
        if (source_ == address(0)) revert LiquiditySupply_InvalidParams();

        // Check that the source is present
        bool found = _inArray(source_, ohmSources);
        if (!found) revert LiquiditySupply_InvalidParams();

        // Find the source
        uint256 updatedAmount;
        for (uint256 i = 0; i < ohmSources.length; i++) {
            if (ohmSources[i] != source_) continue;

            uint256 foundAmount = ohmAmounts[i];

            // If a negative number, ensure it is not greater than the existing amount and would result in an underflow
            if (!add_) {
                if (amount_ > foundAmount) revert LiquiditySupply_InvalidParams();

                ohmAmounts[i] -= amount_;
                _polOhmTotalAmount -= amount_;
            }
            // If a positive number, ensure it would not result in an overflow
            else {
                if (amount_ >= type(uint256).max - foundAmount)
                    revert LiquiditySupply_InvalidParams();

                ohmAmounts[i] += amount_;
                _polOhmTotalAmount += amount_;
            }

            updatedAmount = ohmAmounts[i];

            break;
        }

        emit LiquiditySupplyUpdated(add_, amount_, updatedAmount, source_, false);
    }

    /// @notice Adjust the amount of gOHM in protocol-owned liquidity for the specified source
    /// @dev    This function reverts if:
    ///         - The caller is not the parent module
    ///         - The source is the zero address
    ///         - The source is not present
    ///         - The new amount is less than 0 or greater than uint256 max
    ///
    /// @param  amount_     The amount to increase or decrease the gOHM liquidity by
    /// @param  add_        True if the adjustment is addition, false if subtraction
    /// @param  source_     The address of the liquidity source
    function adjustGOhmLiquidity(uint256 amount_, bool add_, address source_) external onlyParent {
        // Check that the address is not 0
        if (source_ == address(0)) revert LiquiditySupply_InvalidParams();

        // Check that the source is present
        bool found = _inArray(source_, gOhmSources);
        if (!found) revert LiquiditySupply_InvalidParams();

        // Find the source
        uint256 updatedAmount;
        for (uint256 i = 0; i < gOhmSources.length; i++) {
            if (gOhmSources[i] != source_) continue;

            uint256 foundAmount = gOhmAmounts[i];

            // If a negative number, ensure it is not greater than the existing amount and would result in an underflow
            if (!add_) {
                if (amount_ > foundAmount) revert LiquiditySupply_InvalidParams();

                gOhmAmounts[i] -= amount_;
                _polGOhmTotalAmount -= amount_;
            }
            // If a positive number, ensure it would not result in an overflow
            else {
                if (amount_ >= type(uint256).max - foundAmount)
                    revert LiquiditySupply_InvalidParams();

                gOhmAmounts[i] += amount_;
                _polGOhmTotalAmount += amount_;
            }

            updatedAmount = gOhmAmounts[i];

            break;
        }

        emit LiquiditySupplyUpdated(add_, amount_, updatedAmount, source_, true);
    }

    // =========== HELPER FUNCTIONS =========== //

    /// @notice     Determines if `source_` is contained in the `array_` array
    ///
    /// @param      source_  The address of a liquidity source
    /// @return     True if the address is in the array, false otherwise
    function _inArray(address source_, address[] memory array_) internal pure returns (bool) {
        uint256 len = array_.length;
        for (uint256 i; i < len; ) {
            if (source_ == array_[i]) {
                return true;
            }
            unchecked {
                ++i;
            }
        }

        return false;
    }
}
