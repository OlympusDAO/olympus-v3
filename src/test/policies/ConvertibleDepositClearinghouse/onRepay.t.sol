// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {ConvertibleDepositClearinghouseTest} from "./ConvertibleDepositClearinghouseTest.sol";

contract OnRepayCDClearinghouseTest is ConvertibleDepositClearinghouseTest {
    // given the user has not approved spending of debt token
    //  [ ] it reverts
    // given the user does not have enough debt token
    //  [ ] it reverts
    // given the Clearinghouse is not enabled
    //  [ ] it succeeds
    // [ ] principal receivables are decremented
    // [ ] interest receivables are decremented
    // [ ] the debt token is transferred from the user to the Clearinghouse
    // [ ] the collateral is transferred from the Clearinghouse to the user
    // [ ] the debt is repaid on CDEPO
    // [ ] the yield is swept to the TRSRY
}
