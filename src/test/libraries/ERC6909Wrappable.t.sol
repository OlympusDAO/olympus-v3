// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.20;

import {Test} from "@forge-std-1.9.6/Test.sol";

contract ERC6909WrappableTest is Test {
    // Mint
    // when the amount is 0
    //  [ ] it reverts
    // when shouldWrap is true
    //  given the ERC20 token has not been created
    //   [ ] it creates the ERC20 token contract
    //   [ ] the ERC20 token is minted to the recipient
    //   [ ] the ERC6909 token is not minted to the recipient
    //   [ ] the wrappedToken address is set correctly
    //  [ ] the ERC20 token is minted to the recipient
    //  [ ] the ERC20 token total supply is increased
    //  [ ] the ERC6909 token is not minted to the recipient
    //  [ ] the ERC6909 token total supply is unchanged
    // [ ] the wrappedToken address is 0
    // [ ] the ERC20 token is not minted to the recipient
    // [ ] the ERC6909 token is minted to the recipient
    // [ ] the ERC20 token total supply is unchanged
    // [ ] the ERC6909 token total supply is increased

    // Burn
    // when the amount is 0
    //  [ ] it reverts
    // when wrapped is true
    //  given the recipient has not approved the contract to spend the ERC20 token
    //   [ ] it reverts
    //  [ ] the ERC20 token is burned from the recipient
    //  [ ] the ERC6909 token is not burned from the recipient
    //  [ ] the ERC20 token total supply is decreased
    //  [ ] the ERC6909 token total supply is unchanged
    // given the recipient has not approved the contract to spend the ERC6909 token
    //  [ ] it reverts
    // [ ] the ERC20 token is not burned from the recipient
    // [ ] the ERC6909 token is burned from the recipient
    // [ ] the ERC20 token total supply is unchanged
    // [ ] the ERC6909 token total supply is decreased

    // Wrap
    // when the amount is 0
    //  [ ] it reverts
    // when the tokenId is invalid
    //  [ ] it reverts
    // when the recipient is the zero address
    //  [ ] it reverts
    // when the recipient has not approved the contract to spend the ERC6909 token
    //  [ ] it reverts
    // given the ERC20 token has not been created
    //  [ ] it creates the ERC20 token contract
    //  [ ] the wrappedToken address is set correctly
    //  [ ] the ERC6909 token is burned from the recipient
    //  [ ] the ERC20 token is minted to the recipient
    //  [ ] the ERC6909 token supply is reduced
    //  [ ] the ERC20 token supply is increased
    // [ ] the ERC6909 token is burned from the recipient
    // [ ] the ERC20 token is minted to the recipient
    // [ ] the ERC6909 token supply is reduced
    // [ ] the ERC20 token supply is increased

    // Unwrap
    // when the amount is 0
    //  [ ] it reverts
    // when the tokenId is invalid
    //  [ ] it reverts
    // when the recipient is the zero address
    //  [ ] it reverts
    // when the recipient has not approved the contract to spend the ERC20 token
    //  [ ] it reverts
    // [ ] the ERC6909 token is minted to the recipient
    // [ ] the ERC20 token is burned from the recipient
    // [ ] the ERC6909 token supply is increased
    // [ ] the ERC20 token supply is decreased
}
