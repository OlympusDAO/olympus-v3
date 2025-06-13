// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {DepositManagerTest} from "./DepositManagerTest.sol";

contract DepositManagerWithdrawTest is DepositManagerTest {
    // Tests
    // given the caller does not have the deposit operator role
    //  [ ] it reverts
    // given the deposit asset configuration does not exist
    //  [ ] it reverts
    // given wrapped is true
    //  given the depositor has not approved the contract to spend the wrapped receipt token
    //   [ ] it reverts
    //  given the depositor's wrapped receipt token balance is less than the amount to withdraw
    //   [ ] it reverts
    //  [ ] the wrapped receipt token is burned
    //  [ ] the receipt token is not burned
    // given the depositor has not approved the contract to spend the receipt token
    //  [ ] it reverts
    // given the depositor's receipt token balance is less than the amount to withdraw
    //  [ ] it reverts
    // given the asset configuration has the vault set to the zero address
    //  given there has been a deposit
    //   [ ] the operator shares are correct
    //   [ ] the asset liabilities are correct
    //  [ ] the wrapped receipt token is not burned
    //  [ ] the receipt token is burned
    //  [ ] the asset liabilities are decreased by the withdrawn amount
    //  [ ] the asset is sent to the depositor
    //  [ ] the operator shares are decreased by the withdrawn amount
    // given the deposit configuration is disabled
    //  [ ] the asset is withdrawn from the vault and sent to the depositor
    // given there has been anothera deposit
    //  [ ] the operator shares are correct
    //  [ ] the asset liabilities are correct
    // [ ] the wrapped receipt token is not burned
    // [ ] the receipt token is burned
    // [ ] the asset liabilities are decreased by the withdrawn amount
    // [ ] the asset is withdrawn from the vault and sent to the depositor
    // [ ] the operator shares are decreased by the withdrawn amount
}
