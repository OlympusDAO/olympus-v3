// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.24;

// Contracts
import {MockERC20} from "src/test/mocks/MockERC20.sol";

contract NoReturnPayoutToken is MockERC20 {
    constructor() MockERC20("No return", "NRT", 6) {}

    function transfer(address recipient_, uint256 amount_) public override returns (bool) {
        super.transfer(recipient_, amount_);
        // Model successful ERC-20 delivery with exactly empty returndata.
        // forge-lint: disable-next-line(inline-assembly)
        assembly ("memory-safe") {
            return(0, 0)
        }
    }
}
