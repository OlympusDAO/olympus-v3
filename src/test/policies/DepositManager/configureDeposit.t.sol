// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {DepositManagerTest} from "./DepositManagerTest.sol";

contract DepositManagerConfigureDepositTest is DepositManagerTest {
    // Tests
    // when the caller is not the manager or admin
    //  [ ] it reverts
    // given the policy is disabled
    //  [ ] it reverts
    // given the asset is already configured
    //  [ ] it reverts
    // when the asset address is the zero address
    //  [ ] it reverts
    // when the deposit period is 0
    //  [ ] it reverts
    // when the vault and asset do not match
    //  [ ] it reverts
    // when the reclaim rate is greater than 100%
    //  [ ] it reverts
    // when the vault is the zero address
    //  [ ] the asset configuration has the vault set to the zero address
    // [ ] the asset configuration has the vault set to the vault address
    // [ ] the asset is recorded as configured
    // [ ] the deposit configuration is recorded with the derived receipt token ID
    // [ ] the deposit configuration has the reclaim rate set
    // [ ] the deposit reclaim rate is set
    // [ ] the receipt token has the name set
    // [ ] the receipt token has the symbol set
    // [ ] the receipt token has the decimals set
    // [ ] the receipt token has the owner set
    // [ ] the receipt token has the asset set
    // [ ] the receipt token has the deposit period set
    // [ ] the returned receipt token ID matches
    // [ ] the deposit configuration is returned for the receipt token ID
    // [ ] the asset and deposit period is recognised as a deposit asset
}
