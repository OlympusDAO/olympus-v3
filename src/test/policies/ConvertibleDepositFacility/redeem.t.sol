// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {ConvertibleDepositFacilityTest} from "./ConvertibleDepositFacilityTest.sol";
import {IConvertibleDepositFacility} from "src/policies/interfaces/IConvertibleDepositFacility.sol";
import {CDPOSv1} from "src/modules/CDPOS/CDPOS.v1.sol";
import {IConvertibleDepository} from "src/modules/CDEPO/IConvertibleDepository.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {stdError} from "forge-std/StdError.sol";

contract RedeemCDFTest is ConvertibleDepositFacilityTest {
    // given the contract is disabled
    //  [ ] it reverts
    // given the commitment ID does not exist
    //  [ ] it reverts
    // given the commitment ID exists for a different user
    //  [ ] it reverts
    // given it is before the redeemable timestamp
    //  [ ] it reverts
    // [ ] it burns the CD tokens
    // [ ] it transfers the underlying asset to the caller
    // [ ] it sets the commitment amount to 0
    // [ ] it emits a Redeemed event
}
