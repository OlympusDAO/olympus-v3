// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;
// Libraries
import {OperatorAuthTest as ScopedOperatorAuthTest} from "./OperatorAuth/OperatorAuthTest.sol";

/// @dev Shared scoped-authorization fixture; legacy implementation fixtures are retired.
abstract contract OperatorAuthTest is ScopedOperatorAuthTest {

}
