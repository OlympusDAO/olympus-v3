// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.24;

import {Test} from "forge-std/Test.sol";

contract CCIPCrossChainBridgeTest is Test {
    // ============ TESTS ============ //
    // constructor
    // when the OHM address is the zero address
    //  [ ] it reverts
    // when the CCIP router address is the zero address
    //  [ ] it reverts
    // when the owner address is the zero address
    //  [ ] it reverts
    // [ ] it sets the OHM address
    // [ ] it sets the CCIP router address
    // [ ] it sets the owner address
    // enable
    // given the contract is already enabled
    //  [ ] it reverts
    // when the caller is not the owner
    //  [ ] it reverts
    // [ ] it emits an Enabled event
    // [ ] it sets the isEnabled flag to true
    // disable
    // given the contract is not enabled
    //  [ ] it reverts
    // when the caller is not the owner
    //  [ ] it reverts
    // [ ] it emits a Disabled event
    // [ ] it sets the isEnabled flag to false
    // sendToSVM
    // given the contract is not enabled
    //  [ ] it reverts
    // when the sender has not provided enough native token to cover fees
    //  [ ] it reverts
    // when the amount is zero
    //  [ ] it reverts
    // given the sender has insufficient OHM
    //  [ ] it reverts
    // given the sender has not approved the contract to spend OHM
    //  [ ] it reverts
    // [ ] the recipient address is the default public key
    // [ ] the SVM extra args compute units are the default compute units
    // [ ] the SVM extra args writeable bitmap is 0
    // [ ] the SVM extra args allow out of order execution is true
    // [ ] the SVM extra args recipient is the recipient address
    // [ ] the SVM extra args accounts is an empty array
    // [ ] the contract transfers the OHM from the sender to itself
    // [ ] the CCIP router is called with the correct parameters
    // [ ] the CCIP router transfers the OHM to itself
    // [ ] a Bridged event is emitted
    // sendToEVM
    // given the contract is not enabled
    //  [ ] it reverts
    // when the sender has not provided enough native token to cover fees
    //  [ ] it reverts
    // when the amount is zero
    //  [ ] it reverts
    // given the sender has insufficient OHM
    //  [ ] it reverts
    // given the sender has not approved the contract to spend OHM
    //  [ ] it reverts
    // [ ] the recipient address is the recipient address
    // [ ] the EVM extra args gas limit is the default gas limit
    // [ ] the EVM extra args allow out of order execution is true
    // [ ] the contract transfers the OHM from the sender to itself
    // [ ] the CCIP router is called with the correct parameters
    // [ ] the CCIP router transfers the OHM to itself
    // [ ] a Bridged event is emitted
    // withdraw
    // when the caller is not the owner
    //  [ ] it reverts
    // given the balance is zero
    //  [ ] it reverts
    // given the recipient is the zero address
    //  [ ] it reverts
    // given the contract is not enabled
    //  [ ] the contract transfers the native token to the recipient
    //  [ ] a Withdrawn event is emitted
    // [ ] the contract transfers the native token to the recipient
    // [ ] a Withdrawn event is emitted
}
