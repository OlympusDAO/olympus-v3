// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.0;

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

contract MockBalancerPool is MockERC20 {
    constructor() MockERC20("Mock Balancer Pool", "BPT", 18) {}

    function getPoolId() external pure returns (bytes32) {
        return bytes32(0);
    }
}
