// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

/// @notice The BACKING contract provides the Emission Manager with a passable representation of OHM backing.
///         Note that this contract should not be used for other purposes without significant thought. It's
///         returned backing value is unlikely to be perfect. However, for the purposes of the emission manager,
///         which uses backing solely for the purpose of computing premium and daily emissions as a result, this
///         approach should work fine (the snapshot time for market price in that calculation creates similar noise).
///         Backing price should be adjusted by governance should it diverge excessively from reality.
contract BACKING {
    address public immutable manager;

    uint256 public price;

    uint256 private constant RESERVE_DECIMALS = 1e18;
    uint256 private constant SUPPLY_DECIMALS = 1e9;

    constructor() {}

    /// @notice allow emission manager to update backing price based on new supply and reserves added
    /// @param supplyAdded number of new OHM minted
    /// @param reservesAdded number of new DAI added
    function update(uint256 supplyAdded, uint256 reservesAdded) external {
        if (msg.sender != manager) revert("Only Manager");

        uint256 previousReserves = _getReserves() - reservesAdded;
        uint256 previousSupply = _getSupply() - minted;

        uint256 percentIncreaseReserves = (reservesAdded * RESERVE_DECIMALS) / previousReserves;
        uint256 percentIncreaseSupply = ((minted * SUPPLY_DECIMALS) / previousSupply) * DECIMALS;

        price =
            (price * percentIncreaseReserves) /
            percentIncreaseSupply /
            (RESERVE_DECIMALS - SUPPLY_DECIMALS);
    }

    /// @notice return reserves, measured as clearinghouse receivables and sdai balances, in DAI denomination
    function _getReserves() public view returns (uint256 reserves) {
        reserves += clearinghouse1.principalReceivables();
        reserves += clearinghouse2.principalReceivables();
        reserves += sdai.previewRedeem(sdai.balanceOf(TRSRY));
        reserves += sdai.previewRedeem(sdai.balanceOf(address(clearinghouse2)));
    }

    /// @notice return supply, measured as supply of gOHM in OHM denomination
    function _getSupply() public view returns (uint256 supply) {
        return (gohm.totalSupply() * staking.index()) / RESERVE_DECIMALS;
    }

    /// @notice allow governance to adjust backing price if deviated from reality
    /// @dev note if adjustment is more than 33% down, contract should be redeployed
    /// @param newPrice to adjust to
    function adjustPrice(uint256 newPrice) external {
        if (msg.sender != governor) revert("Only Governor");
        if (newPrice < (price * 2) / 3) revert("Change too significant");
        price = newPrice;
    }
}
