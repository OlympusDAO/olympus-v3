// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {ConvertibleDepositClearinghouseTest} from "./ConvertibleDepositClearinghouseTest.sol";

contract LendToCoolerCDClearinghouseTest is ConvertibleDepositClearinghouseTest {
    // given the cooler is not issued by the factory
    //  [ ] it reverts
    // given the cooler collateral is not CDEPO
    //  [ ] it reverts
    // given the cooler debt is not the vault token
    //  [ ] it reverts
    // given the Clearinghouse is not enabled
    //  [ ] it reverts
    // given the user has not approved spending of collateral
    //  [ ] it reverts
    // given the user does not have enough collateral
    //  [ ] it reverts
    // [ ] the user receives vault token
    // [ ] the cooler receives collateral
    // [ ] the debt is recorded on CDEPO
}
