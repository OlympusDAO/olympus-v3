// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {DepositManagerTest} from "./DepositManagerTest.sol";

contract DepositManagerSetDepositReclaimRateTest is DepositManagerTest {
    // Tests
    // when the caller is not the manager or admin
    //  [ ] it reverts
    // given the deposit asset is not configured
    //  [ ] it reverts
    // given the policy is disabled
    //  [ ] it reverts
    // when the reclaim rate is greater than 100%
    //  [ ] it reverts
    // [ ] it sets the reclaim rate for the deposit asset
    // [ ] an event is emitted
}
