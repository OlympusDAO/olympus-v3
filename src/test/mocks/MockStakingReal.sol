// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IgOHM} from "src/interfaces/IgOHM.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockStakingReal {
    using SafeERC20 for IERC20;

    IERC20 public immutable OHM;
    IgOHM public immutable gOHM;

    constructor(
        address ohm_,
        address gohm_
    ) {
        OHM = IERC20(ohm_);
        gOHM = IgOHM(gohm_);
    }

    /**
     * @notice redeem sOHM for OHMs
     * @param _to address
     * @param _amount uint
     * @param _trigger bool
     * @param _rebasing bool
     * @return amount_ uint
     */
    function unstake(
        address _to,
        uint256 _amount,
        bool _trigger,
        bool _rebasing
    ) external returns (uint256 amount_) {
        require(!_trigger && !_rebasing, "MockStaking can't handle trigger or rebasing") ;

        amount_ = _amount;
        gOHM.burn(msg.sender, _amount); // amount was given in gOHM terms
        amount_ = gOHM.balanceFrom(amount_); // convert amount to OHM terms

        require(amount_ <= OHM.balanceOf(address(this)), "Insufficient OHM balance in contract");
        OHM.safeTransfer(_to, amount_);
    }
}
