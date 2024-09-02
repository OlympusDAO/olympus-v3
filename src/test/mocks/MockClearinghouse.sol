// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";

// mock clearinghouse to use with testing the protocoloop contract
// most functions / variables are omitted
contract MockClearinghouse {
    ERC20 public reserve;
    ERC4626 public wrappedReserve;
    uint256 public principalReceivables;

    constructor(address _reserve, address _wrappedReserve) {
        reserve = ERC20(_reserve);
        wrappedReserve = ERC4626(_wrappedReserve);
    }

    function setPrincipalReceivables(uint256 _principalReceivables) external {
        principalReceivables = _principalReceivables;
    }

    function withdrawReserve(uint256 _amount) external {
        reserve.transfer(msg.sender, _amount);
    }

    function withdrawWrappedReserve(uint256 _amount) external {
        wrappedReserve.transfer(msg.sender, _amount);
    }
}
