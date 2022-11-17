// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {VOTESv1} from "src/modules/VOTES/VOTES.v1.sol";
import "src/Kernel.sol";

/// @notice Votes module is the ERC20 token that represents voting power in the network.
contract OlympusVotes is VOTESv1 {
    //============================================================================================//
    //                                      MODULE SETUP                                          //
    //============================================================================================//

    constructor(Kernel kernel_, ERC20 gOhm_)
        Module(kernel_)
        ERC4626(gOhm_, "Olympus Votes", "vOHM")
    {
        gOHM = gOhm_;
    }

    /// @inheritdoc Module
    function KEYCODE() public pure override returns (Keycode) {
        return toKeycode("VOTES");
    }

    /// @inheritdoc Module
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        major = 1;
        minor = 0;
    }

    //============================================================================================//
    //                                       CORE FUNCTIONS                                       //
    //============================================================================================//

    function deposit(uint256 assets_, address receiver_)
        public
        override
        permissioned
        returns (uint256)
    {
        lastDepositTimestamp[receiver_] = block.timestamp;
        return super.deposit(assets_, receiver_);
    }

    function mint(uint256 shares_, address receiver_)
        public
        override
        permissioned
        returns (uint256)
    {
        lastDepositTimestamp[receiver_] = block.timestamp;
        return super.mint(shares_, receiver_);
    }

    function withdraw(
        uint256 assets_,
        address receiver_,
        address owner_
    ) public override permissioned returns (uint256) {
        return super.withdraw(assets_, receiver_, owner_);
    }

    function redeem(
        uint256 shares_,
        address receiver_,
        address owner_
    ) public override permissioned returns (uint256) {
        return super.redeem(shares_, receiver_, owner_);
    }

    /// @notice Transfers are locked for this token.
    function transfer(address to_, uint256 amt_) public override permissioned returns (bool) {
        return super.transfer(to_, amt_);
    }

    /// @notice TransferFrom is only allowed by permissioned policies.
    function transferFrom(
        address from_,
        address to_,
        uint256 amount_
    ) public override permissioned returns (bool) {
        lastDepositTimestamp[to_] = block.timestamp;
        return super.transferFrom(from_, to_, amount_);
    }

    function resetActionTimestamp(address _wallet) external override permissioned {
        lastActionTimestamp[_wallet] = block.timestamp;
    }

    //============================================================================================//
    //                                       VIEW FUNCTIONS                                       //
    //============================================================================================//

    function totalAssets() public view override returns (uint256) {
        return asset.balanceOf(address(this));
    }
}
