// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {DepositManagerTest} from "./DepositManagerTest.sol";

contract DepositManagerClaimYieldTest is DepositManagerTest {
    // Tests
    // given the caller is not the deposit operator
    //  [ ] it reverts
    // given the deposit asset is not configured
    //  [ ] it reverts
    // when the amount is greater than the deposited amount
    //  [ ] it reverts
    // when the claimed yield reduces the deposited assets below the liabilities
    //  [ ] it reverts
    // [ ] the asset is transferred to the recipient
    // [ ] the operator shares are decreased by the claimed yield
    // [ ] the asset liabilities are not decreased
    // [ ] the receipt token supply is not decreased
}
