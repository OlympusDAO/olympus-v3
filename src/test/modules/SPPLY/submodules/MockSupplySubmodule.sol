// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import "modules/SPPLY/SPPLY.v1.sol";

contract MockSupplySubmodule is SupplySubmodule {
    constructor(Module parent_) Submodule(parent_) {}

    event Observation();

    // ========= SUBMODULE SETUP ========= //

    /// @inheritdoc Submodule
    function SUBKEYCODE() public pure override returns (SubKeycode) {
        return toSubKeycode("SPPLY.MOCK");
    }

    /// @inheritdoc Submodule
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    /// @inheritdoc Submodule
    function INIT() external override onlyParent {}

    // ========= DATA FUNCTIONS ========= //

    function getCollateralizedOhm() external view virtual override returns (uint256) {}

    function getProtocolOwnedBorrowableOhm() external view virtual override returns (uint256) {}

    function getProtocolOwnedLiquidityOhm() external view virtual override returns (uint256) {}

    function getProtocolOwnedTreasuryOhm() external view virtual override returns (uint256) {}

    function getProtocolOwnedLiquidityReserves()
        external
        view
        virtual
        override
        returns (SPPLYv1.Reserves[] memory)
    {}

    function getSourceCount() external view virtual override returns (uint256) {}

    function storeObservations() external virtual override {
        emit Observation();
    }
}
