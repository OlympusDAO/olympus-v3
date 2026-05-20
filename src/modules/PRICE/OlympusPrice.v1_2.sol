// SPDX-License-Identifier: AGPL-3.0
// solhint-disable contract-name-camelcase
/// forge-lint: disable-start(mixed-case-function)
pragma solidity >=0.8.15;

// Interfaces
import {IERC165} from "@openzeppelin-4.8.0/interfaces/IERC165.sol";
import {IVersioned} from "src/interfaces/IVersioned.sol";
import {IPRICEv1} from "src/modules/PRICE/IPRICE.v1.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";

// Bophades
import {Kernel, Module} from "src/Kernel.sol";
import {PRICEv2} from "src/modules/PRICE/PRICE.v2.sol";
import {OlympusPricev2} from "src/modules/PRICE/OlympusPrice.v2.sol";

/// @notice     Backward compatibility layer for PRICEv1
/// @dev        Provides PRICEv1-compatible functions while using PRICEv2 implementation underneath
/// @dev        All PRICEv1 functions map to a default asset (OHM)
contract OlympusPricev1_2 is OlympusPricev2, IPRICEv1 {
    // ========== ERRORS ========== //

    /// @notice         Function is deprecated in PRICEv1_2
    error PRICE_Deprecated();

    /// @notice         OHM address is invalid
    error PRICE_InvalidOHM();

    // ========== STATE ========== //

    /// @notice         Number of decimals in the price values provided by the contract.
    /// @dev            This is 18 for backwards-compatibility with PRICEv1.
    uint8 internal constant _DECIMALS = 18;

    /// @notice The address of the OHM token
    address internal immutable _OHM;

    /// @notice         OHM-specific minimum target price (PRICEv1 style), scaled to 18 decimals.
    /// @dev            Value is represented as `targetPrice * 10**18`, matching PRICEv1-compatible output units.
    uint256 public minimumTargetPrice;

    // ========== CONSTRUCTOR ========== //

    /// @notice                         Constructor for PRICEv1_2 compatibility layer
    /// @dev                            The constructor reverts if:
    /// @dev                            - `observationFrequency_` is invalid (from `OlympusPricev2`)
    /// @dev                            - `ohm_ == address(0)` (`PRICE_InvalidOHM`)
    ///
    /// @param kernel_                  Kernel address
    /// @param ohm_                     The address of the OHM token
    /// @param observationFrequency_    Frequency at which prices are stored for moving average
    /// @param minimumTargetPrice_      Initial minimum target OHM price in 18 decimals (`price * 10**18`)
    constructor(
        Kernel kernel_,
        address ohm_,
        uint32 observationFrequency_,
        uint256 minimumTargetPrice_
    ) OlympusPricev2(kernel_, _DECIMALS, observationFrequency_) {
        if (ohm_ == address(0)) revert PRICE_InvalidOHM();

        _OHM = ohm_;
        minimumTargetPrice = minimumTargetPrice_;
        emit MinimumTargetPriceChanged(minimumTargetPrice_);
    }

    // ========== KERNEL FUNCTIONS ========== //

    /// @inheritdoc Module
    function VERSION() external pure virtual override returns (uint8 major_, uint8 minor_) {
        return (1, 2);
    }

    /// @notice                 Returns an OHM price variant from PRICEv2
    /// @param variant_         Price variant to fetch
    /// @return price_          The requested OHM price
    function _getOhmPrice(IPRICEv2.Variant variant_) internal view returns (uint256 price_) {
        (price_, ) = getPrice(_OHM, variant_);
    }

    /// @inheritdoc OlympusPricev2
    /// @dev        PRICEv1 compatibility always uses 18 decimals, so the unit price is constant.
    function _unitPrice() internal pure override returns (uint256) {
        return 1e18;
    }

    // ========== PRICEv1 VIEW FUNCTIONS ========== //

    /// @inheritdoc IPRICEv1
    /// @dev        Returns the current price of OHM.
    /// @dev        Compatibility function for PRICEv1.
    /// @dev        Reverts if:
    /// @dev        - OHM is not approved in PRICE
    /// @dev        - A current OHM price cannot be determined
    function getCurrentPrice() external view returns (uint256) {
        return _getOhmPrice(IPRICEv2.Variant.CURRENT);
    }

    /// @inheritdoc IPRICEv1
    /// @dev        Returns the last price of OHM.
    /// @dev        Compatibility function for PRICEv1.
    /// @dev        Reverts if:
    /// @dev        - OHM is not approved in PRICE
    /// @dev        - OHM does not store moving-average observations
    function getLastPrice() external view returns (uint256) {
        return _getOhmPrice(IPRICEv2.Variant.LAST);
    }

    /// @inheritdoc IPRICEv1
    /// @dev        Returns the moving average of OHM.
    /// @dev        Compatibility function for PRICEv1.
    /// @dev        Returns the raw stored moving average, which may be stale.
    /// @dev        Reverts if:
    /// @dev        - OHM is not approved in PRICE
    /// @dev        - OHM does not store moving-average observations
    function getMovingAverage() external view returns (uint256) {
        return _getOhmPrice(IPRICEv2.Variant.MOVINGAVERAGE);
    }

    /// @inheritdoc IPRICEv1
    /// @dev        Returns the target price of OHM.
    /// @dev        Compatibility function for PRICEv1.
    /// @dev        Reverts if:
    /// @dev        - OHM is not approved in PRICE
    /// @dev        - OHM does not store moving-average observations
    /// @dev        - OHM moving average is stale relative to `observationFrequency()`
    function getTargetPrice() external view returns (uint256) {
        (uint256 movingAvg, uint48 lastObsTime) = getPrice(_OHM, IPRICEv2.Variant.MOVINGAVERAGE);
        _revertIfMovingAverageStale(_OHM, lastObsTime);

        if (movingAvg < minimumTargetPrice) return minimumTargetPrice;
        return movingAvg;
    }

    /// @inheritdoc IPRICEv1
    /// @dev        Returns the last observation time for OHM.
    /// @dev        Compatibility function for PRICEv1.
    /// @dev        Reverts if:
    /// @dev        - OHM is not approved in PRICE
    /// @dev        - OHM does not store moving-average observations
    function lastObservationTime() external view override returns (uint48) {
        (, uint48 lastTimestamp) = getPrice(_OHM, IPRICEv2.Variant.LAST);
        return lastTimestamp;
    }

    /// @notice Returns the OHM token address used by PRICEv1-compatible functions.
    function OHM() external view returns (address) {
        return _OHM;
    }

    // ========== PRICEv1 FUNCTIONS ========== //

    /// @inheritdoc IPRICEv1
    /// @dev        Updates the moving average for all assets.
    /// @dev        Provided as a compatibility function for PRICEv1.
    /// @dev        Reverts if:
    /// @dev        - The caller is not permissioned by the Kernel
    /// @dev        - Any configured moving-average asset fails observation storage
    /// @dev        Reentrancy note: delegates to `storeObservations()`, whose feed/strategy lookups
    /// @dev        are resolved via `staticcall`.
    function updateMovingAverage() external permissioned {
        // Update all assets that track moving averages
        storeObservations();
    }

    /// @inheritdoc IPRICEv1
    /// @dev        Deprecated.
    /// @dev        Reverts with `PRICE_Deprecated`.
    function initialize(uint256[] memory, uint48) external pure {
        // Equivalent to `revert PRICE_Deprecated()`; hand-encoded to keep PRICEv1_2 under EIP-170.
        assembly {
            mstore(0x00, 0xf4a45f99)
            revert(0x1c, 0x04)
        }
    }

    /// @inheritdoc IPRICEv1
    /// @dev        Changes the minimum target price for OHM.
    /// @dev        Provided as a compatibility function for PRICEv1.
    /// @dev        Reverts if the caller is not permissioned by the Kernel.
    /// @dev        Reentrancy note: this function does not make external calls.
    ///
    /// @param minimumTargetPrice_ New minimum target OHM price in 18 decimals (`price * 10**18`)
    function changeMinimumTargetPrice(uint256 minimumTargetPrice_) external permissioned {
        minimumTargetPrice = minimumTargetPrice_;
        emit MinimumTargetPriceChanged(minimumTargetPrice_);
    }

    /// @inheritdoc IPRICEv1
    /// @dev        Deprecated.
    /// @dev        Reverts with `PRICE_Deprecated`.
    function changeUpdateThresholds(uint48, uint48) external pure {
        // Equivalent to `revert PRICE_Deprecated()`; hand-encoded to keep PRICEv1_2 under EIP-170.
        assembly {
            mstore(0x00, 0xf4a45f99)
            revert(0x1c, 0x04)
        }
    }

    /// @inheritdoc IPRICEv1
    /// @dev        Deprecated.
    /// @dev        Reverts with `PRICE_Deprecated`.
    function changeMovingAverageDuration(uint48) external pure {
        // Equivalent to `revert PRICE_Deprecated()`; hand-encoded to keep PRICEv1_2 under EIP-170.
        assembly {
            mstore(0x00, 0xf4a45f99)
            revert(0x1c, 0x04)
        }
    }

    /// @inheritdoc IPRICEv1
    /// @dev        Deprecated.
    /// @dev        Reverts with `PRICE_Deprecated`.
    function changeObservationFrequency(uint48) external pure {
        // Equivalent to `revert PRICE_Deprecated()`; hand-encoded to keep PRICEv1_2 under EIP-170.
        assembly {
            mstore(0x00, 0xf4a45f99)
            revert(0x1c, 0x04)
        }
    }

    /// @inheritdoc IPRICEv2
    /// @dev        Does not revert.
    function decimals() external pure virtual override(IPRICEv1, PRICEv2) returns (uint8) {
        return _DECIMALS;
    }

    /// @inheritdoc IPRICEv2
    /// @dev        Does not revert.
    function observationFrequency()
        external
        view
        virtual
        override(IPRICEv1, PRICEv2)
        returns (uint48)
    {
        return _observationFrequency;
    }

    // ========== ERC165 FUNCTIONS ========== //

    /// @inheritdoc OlympusPricev2
    /// @dev        Does not revert.
    function supportsInterface(bytes4 interfaceId_) public pure virtual override returns (bool) {
        uint32 interfaceId = uint32(interfaceId_);
        return
            interfaceId == uint32(type(IPRICEv1).interfaceId) ||
            interfaceId == uint32(type(IPRICEv2).interfaceId) ||
            interfaceId == uint32(type(IVersioned).interfaceId) ||
            interfaceId == uint32(type(IERC165).interfaceId);
    }
}
/// forge-lint: disable-end(mixed-case-function)
