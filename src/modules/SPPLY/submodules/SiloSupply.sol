// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.15;

import "modules/SPPLY/SPPLY.v1.sol";
import {ISiloLens} from "interfaces/Silo/ISiloLens.sol";
import {IBaseSilo} from "interfaces/Silo/IBaseSilo.sol";

/// @title      SiloSupply
/// @author     Oighty
/// @notice     A SPPLY submodule that provides data on OHM deployed into the specified Silo
contract SiloSupply is SupplySubmodule {
    // Requirements
    // [X] Get amount of OHM in Silo pools that is protocol-owned (still borrowable)
    // [X] Get amount of circulating OHM minted against collateral from pool
    // Math:
    // AMO mints X amount of OHM into pool.
    // Other users deposit Y amount of OHM into pool.
    // Z amount of OHM is borrowed from pool.
    // We assume that any OHM borrowed from the pool, up to X amount, is protocol-owned since it will the last to withdraw in the event of a run.
    // Any OHM that is minted into the pool but not borrowed is collateralized OHM.
    // At all times, collateralized OHM + protocol-owned borrowable OHM = X OHM (minted).
    //
    // Therefore, of the X OHM minted into the pool, we have:
    // Protocol-owned Borrowable OHM = Max(X - Z, 0)
    // Collateralized OHM = Min(X, Z)
    // Protocol-owned Liquidity OHM = 0

    // ========== ERRORS ========== //

    // ========== EVENTS ========== //

    /// @notice         Emitted when the addresses of the Silo contracts are updated
    ///
    /// @param amo_     The address of the Olympus Silo AMO Policy / silo OHM token holder
    /// @param lens_    The address of the SiloLens contract
    /// @param silo_    The address of the Silo market
    event SourcesUpdated(address amo_, address lens_, address silo_);

    // ========== STATE VARIABLES ========== //

    /// @notice         The address of the SiloLens contract
    ISiloLens public lens;

    /// @notice         The address of the Olympus Silo AMO Policy / silo OHM token holder
    address public amo;

    /// @notice         The address of the Silo market
    IBaseSilo public silo;

    /// @notice         The address of the OHM token
    /// @dev            Set at the time of contract creation
    address internal immutable ohm;

    // ========== CONSTRUCTOR ========== //

    /// @notice         Initialize the SiloSupply submodule
    ///
    /// @param parent_  The parent module (SPPLY)
    /// @param amo_     The address of the Olympus Silo AMO Policy / silo OHM token holder
    /// @param lens_    The address of the SiloLens contract
    /// @param silo_    The address of the Silo market
    constructor(Module parent_, address amo_, address lens_, address silo_) Submodule(parent_) {
        amo = amo_;
        lens = ISiloLens(lens_);
        silo = IBaseSilo(silo_);
        ohm = address(SPPLYv1(address(parent_)).ohm());

        // Emit an event with the latest values for each source
        emit SourcesUpdated(amo_, lens_, silo_);
    }

    // ========== SUBMODULE SETUP ========== //

    /// @inheritdoc Submodule
    function SUBKEYCODE() public pure override returns (SubKeycode) {
        return toSubKeycode("SPPLY.SILO");
    }

    /// @inheritdoc Submodule
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    /// @inheritdoc Submodule
    function INIT() external override onlyParent {}

    // ========== DATA FUNCTIONS ========== //

    /// @inheritdoc     SupplySubmodule
    /// @dev            Collateralized OHM is calculated as the minimum of:
    /// @dev            - OHM supplied/minted into the Silo market
    /// @dev            - OHM borrowed from the Silo market
    ///
    /// @dev            This is also equal to the remainder of OHM minted into the Silo market - protocol-owned borrowable OHM.
    ///
    /// @dev            This function assumes that the protocol provided OHM is borrowable.
    function getCollateralizedOhm() external view override returns (uint256) {
        // Get OHM collateral token for this silo
        address ohmCollateralToken = silo.assetStorage(ohm).collateralToken;

        // Get amount of OHM supplied to market by lending facility
        uint256 totalDeposits = lens.totalDepositsWithInterest(silo, ohm);
        uint256 supplied = lens.balanceOfUnderlying(totalDeposits, ohmCollateralToken, amo);

        // Get amount of OHM borrowed from silo
        uint256 borrowed = lens.totalBorrowAmountWithInterest(silo, ohm);

        // If supplied > borrowed, then borrowed is collateralized supply
        // Otherwise, supplied is collateralized supply
        return supplied > borrowed ? borrowed : supplied;
    }

    /// @inheritdoc     SupplySubmodule
    /// @dev            Protocol-owned borrowable OHM is calculated as the maximum of:
    /// @dev                - The difference between the OHM supplied/minted into the Silo market and the OHM borrowed from the Silo market
    /// @dev                - 0
    ///
    /// @dev            We assume that any OHM borrowed from the pool, up to the minted amount, is protocol-owned since it will the last to withdraw in the event of a run.
    ///
    /// @dev            This function assumes that the protocol provided OHM is borrowable.
    function getProtocolOwnedBorrowableOhm() external view override returns (uint256) {
        // Get OHM collateral token for this silo
        /// @dev note: this assumes that the protocol provided OHM is borrowable. if not, this token is not correct.
        address ohmCollateralToken = silo.assetStorage(ohm).collateralToken;

        // Get amount of OHM supplied to market by lending facility
        uint256 totalDeposits = lens.totalDepositsWithInterest(silo, ohm);
        uint256 supplied = lens.balanceOfUnderlying(totalDeposits, ohmCollateralToken, amo);

        // Get amount of OHM borrowed from silo
        uint256 borrowed = lens.totalBorrowAmountWithInterest(silo, ohm);

        // If supplied > borrowed, then the difference is protocol-owned borrowable ohm
        // Otherwise, there is no protocol-owned borrowable ohm
        return supplied > borrowed ? supplied - borrowed : 0;
    }

    /// @inheritdoc     SupplySubmodule
    /// @dev            Protocol-owned liquidity OHM is always zero for lending facilities
    function getProtocolOwnedLiquidityOhm() external pure override returns (uint256) {
        // POLO is always zero for lending facilities
        return 0;
    }

    /// @inheritdoc     SupplySubmodule
    /// @dev            Protocol-owned treasury OHM is always zero for lending facilities
    function getProtocolOwnedTreasuryOhm() external pure override returns (uint256) {
        // POTO is always zero for lending facilities
        return 0;
    }

    /// @inheritdoc     SupplySubmodule
    /// @dev            Protocol-owned liquidity OHM is always zero for lending facilities.
    ///
    /// @dev            This function returns an array with the same length as `getSourceCount()`, but with empty values.
    function getProtocolOwnedLiquidityReserves()
        external
        view
        override
        returns (SPPLYv1.Reserves[] memory)
    {
        SPPLYv1.Reserves[] memory reserves = new SPPLYv1.Reserves[](1);
        reserves[0] = SPPLYv1.Reserves({
            source: address(silo),
            tokens: new address[](0),
            balances: new uint256[](0)
        });

        return reserves;
    }

    /// @inheritdoc     SupplySubmodule
    /// @dev            This always returns a value of one, as there is a 1:1 mapping between a Silo and the Submodule
    function getSourceCount() external pure override returns (uint256) {
        return 1;
    }

    // =========== ADMIN FUNCTIONS =========== //

    /// @notice         Set the source addresses for Silo lending data
    /// @dev            All params are optional and will keep existing values if omitted
    ///
    /// @dev            Will revert if:
    /// @dev            - The caller is not the parent module
    ///
    /// @param amo_     The address of the Olympus Silo AMO Policy / silo OHM token holder
    /// @param lens_    The address of the SiloLens contract
    /// @param silo_    The address of the Silo market
    function setSources(address amo_, address lens_, address silo_) external onlyParent {
        if (amo_ != address(0)) amo = amo_;
        if (lens_ != address(0)) lens = ISiloLens(lens_);
        if (silo_ != address(0)) silo = IBaseSilo(silo_);

        // Emit an event with the latest values for each source
        emit SourcesUpdated(amo, address(lens), address(silo));
    }
}
