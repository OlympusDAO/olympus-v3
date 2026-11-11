// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Contracts
import {ERC20Mock} from "@openzeppelin-5.7.0/mocks/token/ERC20Mock.sol";

contract MockERC20ConfiguredReturnData is ERC20Mock {
    bytes internal _returnData;

    constructor(bytes memory returnData_) {
        _returnData = returnData_;
    }

    function transfer(address recipient_, uint256 amount_) public override returns (bool) {
        super.transfer(recipient_, amount_);
        _returnConfiguredData();
    }

    function transferFrom(
        address sender_,
        address recipient_,
        uint256 amount_
    ) public override returns (bool) {
        super.transferFrom(sender_, recipient_, amount_);
        _returnConfiguredData();
    }

    function _returnConfiguredData() internal view {
        bytes memory returnData = _returnData;
        // forge-lint: disable-next-line(inline-assembly)
        assembly {
            return(add(returnData, 0x20), mload(returnData))
        }
    }
}
