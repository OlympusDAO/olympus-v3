// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Contracts
import {ERC20Mock} from "@openzeppelin-5.7.0/mocks/token/ERC20Mock.sol";

contract MockERC20NoReturn is ERC20Mock {
    function transfer(address recipient_, uint256 amount_) public override returns (bool) {
        super.transfer(recipient_, amount_);
        // forge-lint: disable-next-line(inline-assembly)
        assembly {
            return(0, 0)
        }
    }

    function transferFrom(
        address sender_,
        address recipient_,
        uint256 amount_
    ) public override returns (bool) {
        super.transferFrom(sender_, recipient_, amount_);
        // forge-lint: disable-next-line(inline-assembly)
        assembly {
            return(0, 0)
        }
    }
}
