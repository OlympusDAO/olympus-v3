// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import {Test} from "forge-std/Test.sol";
import "forge-std/console2.sol";
import "solmate/tokens/ERC20.sol";
import "test-utils/users.sol";
import "test-utils/mocking.sol";
import "test-utils/sorting.sol";

import {OlympusMinter} from "src/modules/MINTR.sol";
import {LarpKernel} from "./LarpKernel.sol";
import {OlympusERC20Token} from "../../external/OlympusERC20.sol";

contract STKNGTest is Test {
    using mocking for *;
    using sorting for uint256[];
    using console2 for uint256;

    LarpKernel internal kernel;
    OlympusMinter internal MINTR;
}
