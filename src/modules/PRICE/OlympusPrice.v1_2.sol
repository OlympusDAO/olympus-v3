// SPDX-License-Identifier: AGPL-3.0
// solhint-disable contract-name-camelcase
/// forge-lint: disable-start(mixed-case-function)
pragma solidity >=0.8.15;

// Interfaces
import {IPRICEv1} from "src/modules/PRICE/IPRICE.v1.sol";
import {IPRICEv2} from "src/modules/PRICE/IPRICE.v2.sol";
import {IERC165} from "@openzeppelin-4.8.0/interfaces/IERC165.sol";

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
    address public immutable OHM;

    /// @notice         OHM-specific minimum target price (PRICEv1 style)
    uint256 public minimumTargetPrice;

    // ========== CONSTRUCTOR ========== //

    /// @notice                         Constructor for PRICEv1_2 compatibility layer
    /// @param kernel_                  Kernel address
    /// @param ohm_                     The address of the OHM token
    /// @param observationFrequency_    Frequency at which prices are stored for moving average
    /// @param minimumTargetPrice_      Initial minimum target price for OHM
    constructor(
        Kernel kernel_,
        address ohm_,
        uint32 observationFrequency_,
        uint256 minimumTargetPrice_
    ) OlympusPricev2(kernel_, _DECIMALS, observationFrequency_) {
        if (ohm_ == address(0)) revert PRICE_InvalidOHM();

        OHM = ohm_;
        minimumTargetPrice = minimumTargetPrice_;
        emit MinimumTargetPriceChanged(minimumTargetPrice_);
    }

    // ========== KERNEL FUNCTIONS ========== //

    /// @inheritdoc Module
    function VERSION() external pure virtual override returns (uint8 major_, uint8 minor_) {
        return (1, 2);
    }

    // ========== PRICEv1 VIEW FUNCTIONS ========== //

    /// @inheritdoc IPRICEv1
    /// @dev        Returns the current price of OHM.
    ///             Compatibility function for PRICEv1.
    function getCurrentPrice() external view returns (uint256) {
        (uint256 price, ) = getPrice(OHM, IPRICEv2.Variant.CURRENT);
        return price;
    }

    /// @inheritdoc IPRICEv1
    /// @dev        Returns the last price of OHM.
    ///             Compatibility function for PRICEv1.
    function getLastPrice() external view returns (uint256) {
        (uint256 price, ) = getPrice(OHM, IPRICEv2.Variant.LAST);
        return price;
    }

    /// @inheritdoc IPRICEv1
    /// @dev        Returns the moving average of OHM.
    ///             Compatibility function for PRICEv1.
    function getMovingAverage() external view returns (uint256) {
        (uint256 price, ) = getPrice(OHM, IPRICEv2.Variant.MOVINGAVERAGE);
        return price;
    }

    /// @inheritdoc IPRICEv1
    /// @dev        Returns the target price of OHM.
    ///             Compatibility function for PRICEv1.
    function getTargetPrice() external view returns (uint256) {
        (uint256 movingAvg, ) = getPrice(OHM, IPRICEv2.Variant.MOVINGAVERAGE);
        uint256 min = minimumTargetPrice;
        return movingAvg > min ? movingAvg : min;
    }

    /// @inheritdoc IPRICEv1
    /// @dev        Returns the last observation time for OHM.
    ///             Compatibility function for PRICEv1.
    function lastObservationTime() external view override returns (uint48) {
        (, uint48 lastTimestamp) = getPrice(OHM, IPRICEv2.Variant.LAST);
        return lastTimestamp;
    }

    // ========== PRICEv1 FUNCTIONS ========== //

    /// @inheritdoc IPRICEv1
    /// @dev        Updates the moving average for all assets.
    ///             Provided as a compatibility function for PRICEv1.
    function updateMovingAverage() external permissioned {
        // Update all assets that track moving averages
        storeObservations();
    }

    /// @inheritdoc IPRICEv1
    /// @dev        Deprecated. Reverts.
    function initialize(uint256[] memory, uint48) external pure {
        revert PRICE_Deprecated();
    }

    /// @inheritdoc IPRICEv1
    /// @dev        Changes the minimum target price for OHM.
    ///             Provided as a compatibility function for PRICEv1.
    function changeMinimumTargetPrice(uint256 minimumTargetPrice_) external permissioned {
        minimumTargetPrice = minimumTargetPrice_;
        emit MinimumTargetPriceChanged(minimumTargetPrice_);
    }

    /// @inheritdoc IPRICEv1
    /// @dev        Deprecated. Reverts.
    function changeUpdateThresholds(uint48, uint48) external pure {
        revert PRICE_Deprecated();
    }

    /// @inheritdoc IPRICEv1
    /// @dev        Deprecated. Reverts.
    function changeMovingAverageDuration(uint48) external pure {
        revert PRICE_Deprecated();
    }

    /// @inheritdoc IPRICEv1
    /// @dev        Deprecated. Reverts.
    function changeObservationFrequency(uint48) external pure {
        revert PRICE_Deprecated();
    }

    /// @inheritdoc IPRICEv2
    function decimals() external view virtual override(IPRICEv1, PRICEv2) returns (uint8) {
        return _DECIMALS;
    }

    /// @inheritdoc IPRICEv2
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

    function supportsInterface(bytes4 interfaceId_) public view virtual override returns (bool) {
        return interfaceId_ == type(IPRICEv1).interfaceId || super.supportsInterface(interfaceId_);
    }
}
/// forge-lint: disable-end(mixed-case-function)
