// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {DepositManagerTest} from "./DepositManagerTest.sol";

contract DepositManagerDepositTest is DepositManagerTest {
    // Tests
    // when the caller does not have the deposit operator role
    //  [ ] it reverts
    // when the depositor address is the zero address
    //  [ ] it reverts
    // when the deposit amount is 0
    //  [ ] it reverts
    // given the deposit configuration does not exist
    //  given the asset vault is set
    //   [ ] it reverts
    //  [ ] it reverts
    // given the deposit configuration is disabled
    //  [ ] it reverts
    // given the depositor has not approved the contract to spend the asset
    //  [ ] it reverts
    // given the depositor does not have sufficient asset balance
    //  [ ] it reverts
    // given the asset configuration has the vault set to the zero address
    //  [ ] the returned shares are the deposited amount
    //  [ ] the asset is stored in the contract
    //  [ ] the operator shares are updated with the deposited amount
    //  [ ] the wrapped receipt tokens are not minted to the depositor
    //  [ ] the receipt tokens are minted to the depositor
    // when shouldWrap is true
    //  given the receipt token has not been wrapped
    //   [ ] it creates the wrapped token contract
    //   [ ] the wrapped receipt tokens are minted to the depositor
    //   [ ] the receipt tokens are not minted to the depositor
    //  [ ] the wrapped receipt tokens are minted to the depositor
    //  [ ] the receipt tokens are not minted to the depositor
    // given there is an existing deposit
    //  [ ] the operator shares are correct
    //  [ ] the asset liabilities are correct
    // [ ] the returned shares are the deposited amount (in terms of vault shares)
    // [ ] the asset is deposited into the vault
    // [ ] the operator shares are increased by the deposited amount (in terms of vault shares)
    // [ ] the wrapped receipt tokens are not minted to the depositor
    // [ ] the receipt tokens are minted to the depositor
    // [ ] the asset liabilities are increased by the deposited amount
}
