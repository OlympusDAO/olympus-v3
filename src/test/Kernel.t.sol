// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import {Test} from "forge-std/Test.sol";
import "test-utils/users.sol";
import "test-utils/mocking.sol";
import "test-utils/sorting.sol";

import {Kernel} from "../Kernel.sol";

contract KernelTest is Test {
    using mocking for *;

    Kernel internal kernel;
    users userCreator;
    address[] usrs;

    function setUp() public {
        kernel = new Kernel();
        //userCreater = new users(1);
    }
}
