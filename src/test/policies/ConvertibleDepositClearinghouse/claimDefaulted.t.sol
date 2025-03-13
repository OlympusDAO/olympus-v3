// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.15;

import {ConvertibleDepositClearinghouseTest} from "./ConvertibleDepositClearinghouseTest.sol";

contract ClaimDefaultedCDClearinghouseTest is ConvertibleDepositClearinghouseTest {
    // when the cooler and loans arrays are of different lengths
    //  [ ] it reverts
    // given any cooler was not issued by the factory
    //  [ ] it reverts
    // given any loan was not issued by the Clearinghouse
    //  [ ] it reverts
    // given the Clearinghouse is not enabled
    //  [ ] it succeeds
    // given the keeper reward for a loan is greater than maxRewardPerLoan
    //  [ ] it caps the keeper reward for a loan to maxRewardPerLoan
    // given the time since expiry is less than 7 days
    //  [ ] the keeper reward is proportional to the time since expiry
    // [ ] the loans are repaid
    // [ ] the collateral is burned
    // [ ] the debt on CDEPO is manually reduced
    // [ ] the keeper receives 5% of the collateral
}
