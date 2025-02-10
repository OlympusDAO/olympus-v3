// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {PolicyEnablerTest} from "./PolicyEnablerTest.sol";

contract PolicyEnablerOnlyDisabledTest is PolicyEnablerTest {
    // given the policy is enabled
    //  [ ] it reverts
    // [ ] it does not revert
}
