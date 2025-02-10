// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {PolicyEnablerTest} from "./PolicyEnablerTest.sol";

contract PolicyEnablerOnlyEnabledTest is PolicyEnablerTest {
    // given the policy is disabled
    //  [ ] it reverts
    // [ ] it does not revert
}
