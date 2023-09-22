// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

interface IAuthority {
    function governor() external view returns (address);

    function policy() external view returns (address);
}

contract MockLegacyInverseBondDepo {
    error Unauthorized();

    IAuthority public authority;
    MockERC20 public ohm;

    constructor(address authority_, address ohm_) {
        authority = IAuthority(authority_);
        ohm = MockERC20(ohm_);
    }

    function burn() external {
        if (msg.sender != authority.policy()) revert Unauthorized();

        uint256 ohmBalance = ohm.balanceOf(address(this));
        ohm.transfer(address(1), ohmBalance);
    }

    function setAuthority(address authority_) external {
        if (msg.sender != authority.governor()) revert Unauthorized();
        authority = IAuthority(authority_);
    }
}