// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {CDEPOTest} from "./CDEPOTest.sol";

import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IConvertibleDepository} from "src/modules/CDEPO/IConvertibleDepository.sol";
import {ConvertibleDepositTokenClone} from "src/modules/CDEPO/ConvertibleDepositTokenClone.sol";

contract CreateTokenCDEPOTest is CDEPOTest {
    // when the caller is not permissioned
    //  [X] it reverts
    // given the token is already supported
    //  [X] it reverts
    // given the reclaim rate is greater than 100%
    //  [X] it reverts
    // given the name is longer than 32 characters
    //  [ ] it truncates the name
    // given the symbol is longer than 32 characters
    //  [ ] it truncates the symbol
    // given the vault is not an ERC4626
    //  [ ] it reverts
    // given the decimals are not 18
    //  [ ] the CD token has the correct decimals
    // [X] the CD token is registered
    // [X] the reclaim rate is set
    // [X] the name is set
    // [X] the symbol is set
    // [X] the decimals are set
    // [X] the owner is CDEPO
    // [X] the asset is set
    // [X] the vault is set
    // [X] the CD token is returned

    function test_notPermissioned_reverts(address caller_) public {
        vm.assume(caller_ != address(godmode));

        // Expect revert
        _expectRevertPolicyNotPermitted(caller_);

        // Call function
        vm.prank(caller_);
        CDEPO.createToken(iReserveTokenTwoVault, 90e2);
    }

    function test_alreadySupported_reverts() public {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(IConvertibleDepository.CDEPO_InvalidArgs.selector, "exists"));

        // Call function
        vm.prank(godmode);
        CDEPO.createToken(IERC4626(address(vault)), 90e2);
    }

    function test_reclaimRateGreaterThan100_reverts(uint16 reclaimRate_) public {
        vm.assume(reclaimRate_ > 100e2);

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(IConvertibleDepository.CDEPO_InvalidArgs.selector, "reclaimRate"));

        // Call function
        vm.prank(godmode);
        CDEPO.createToken(iReserveTokenTwoVault, reclaimRate_);
    }

    function test_success() public {
        // Call function
        vm.prank(godmode);
        address cdToken = CDEPO.createToken(iReserveTokenTwoVault, 90e2);

        // Assert values
        assertEq(CDEPO.getToken(iReserveTokenTwo), cdToken, "cdToken");
        assertEq(CDEPO.isSupported(iReserveTokenTwo), true, "isSupported");
        assertEq(CDEPO.reclaimRate(iReserveTokenTwo), 90e2, "reclaimRate");

        ConvertibleDepositTokenClone cdTokenContract = ConvertibleDepositTokenClone(cdToken);
        assertEq(cdTokenContract.name(), "Convertible Deposit USDS", "name");
        assertEq(cdTokenContract.symbol(), "cdUSDS", "symbol");
        assertEq(cdTokenContract.decimals(), 18, "decimals");
        assertEq(cdTokenContract.owner(), address(CDEPO), "owner");
        assertEq(address(cdTokenContract.asset()), address(iReserveTokenTwo), "asset");
        assertEq(address(cdTokenContract.vault()), address(iReserveTokenTwoVault), "vault");
    }
}
