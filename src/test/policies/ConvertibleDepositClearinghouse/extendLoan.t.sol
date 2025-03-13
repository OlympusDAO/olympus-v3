// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {ConvertibleDepositClearinghouseTest} from "./ConvertibleDepositClearinghouseTest.sol";

contract ExtendLoanCDClearinghouseTest is ConvertibleDepositClearinghouseTest {
    // given the cooler is not issued by the factory
    //  [ ] it reverts
    // given the cooler loan was not issued by the Clearinghouse
    //  [ ] it reverts
    // given the user has not approved spending of debt token
    //  [ ] it reverts
    // given the user does not have enough debt token
    //  [ ] it reverts
    // given the Clearinghouse is not enabled
    //  [ ] it succeeds
    // [ ] the interest is transferred from the user to the Clearinghouse
    // [ ] the loan is extended
    // [ ] the event is emitted
    // [ ] the yield is swept to the TRSRY
}
