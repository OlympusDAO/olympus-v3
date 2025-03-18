// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {CDEPOTest} from "./CDEPOTest.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";

import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IConvertibleDepository} from "src/modules/CDEPO/IConvertibleDepository.sol";
import {ConvertibleDepositTokenClone} from "src/modules/CDEPO/ConvertibleDepositTokenClone.sol";

contract CreateTokenCDEPOTest is CDEPOTest {
    function _getSubstring(string memory str_, uint256 end_) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str_);
        bytes memory result = new bytes(end_);
        for (uint256 i = 0; i < end_; i++) {
            result[i] = strBytes[i];
        }

        return string(result);
    }

    // when the caller is not permissioned
    //  [X] it reverts
    // given the token is already supported
    //  [X] it reverts
    // given the reclaim rate is greater than 100%
    //  [X] it reverts
    // given the name is longer than 32 characters
    //  [X] it truncates the name
    // given the symbol is longer than 32 characters
    //  [X] it truncates the symbol
    // given the vault is not an ERC4626
    //  [X] it reverts
    // given the decimals are not 18
    //  [X] the CD token has the correct decimals
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
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepository.CDEPO_InvalidArgs.selector, "exists")
        );

        // Call function
        vm.prank(godmode);
        CDEPO.createToken(IERC4626(address(vault)), 90e2);
    }

    function test_reclaimRateGreaterThan100_reverts(uint16 reclaimRate_) public {
        vm.assume(reclaimRate_ > 100e2);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepository.CDEPO_InvalidArgs.selector, "reclaimRate")
        );

        // Call function
        vm.prank(godmode);
        CDEPO.createToken(iReserveTokenTwoVault, reclaimRate_);
    }

    function test_nameTooLong() public {
        // Create a token with a name that is too long
        MockERC20 newToken = new MockERC20("AVeryLongTokenNameThatIsTooLong", "LONG", 18);
        MockERC4626 newTokenVault = new MockERC4626(
            newToken,
            "Savings AVeryLongTokenNameThatIsTooLong",
            "sLONG"
        );

        // Call function
        vm.prank(godmode);
        address cdToken = CDEPO.createToken(IERC4626(address(newTokenVault)), 90e2);

        ConvertibleDepositTokenClone cdTokenContract = ConvertibleDepositTokenClone(cdToken);

        // Assert values
        assertEq(cdTokenContract.name(), "Convertible AVeryLongTokenNameTh", "name");
        assertEq(bytes(cdTokenContract.name()).length, 32, "name length");
        assertEq(_getSubstring(cdTokenContract.symbol(), 6), "cdLONG", "symbol");
        assertEq(bytes(cdTokenContract.symbol()).length, 32, "symbol length");
    }

    function test_symbolTooLong() public {
        // Create a token with a symbol that is too long
        MockERC20 newToken = new MockERC20("New Token", "AVERYLONGTOKENSYMBOLTHATISWAYTOOLONG", 18);
        MockERC4626 newTokenVault = new MockERC4626(newToken, "Savings New Token", "sNEW");

        // Call function
        vm.prank(godmode);
        address cdToken = CDEPO.createToken(IERC4626(address(newTokenVault)), 90e2);

        ConvertibleDepositTokenClone cdTokenContract = ConvertibleDepositTokenClone(cdToken);

        // Assert values
        assertEq(_getSubstring(cdTokenContract.name(), 21), "Convertible New Token", "name");
        assertEq(bytes(cdTokenContract.name()).length, 32, "name length");
        assertEq(cdTokenContract.symbol(), "cdAVERYLONGTOKENSYMBOLTHATISWAYT", "symbol");
        assertEq(bytes(cdTokenContract.symbol()).length, 32, "symbol length");
    }

    function test_differentDecimals() public {
        // Create a token with different decimals
        MockERC20 newToken = new MockERC20("New Token", "NEW", 6);
        MockERC4626 newTokenVault = new MockERC4626(newToken, "Savings New Token", "sNEW");

        // Call function
        vm.prank(godmode);
        address cdToken = CDEPO.createToken(IERC4626(address(newTokenVault)), 90e2);

        ConvertibleDepositTokenClone cdTokenContract = ConvertibleDepositTokenClone(cdToken);

        assertEq(cdTokenContract.decimals(), 6, "decimals");
    }

    function test_notERC4626_reverts() public {
        // Create a token with a non-ERC4626 vault
        MockERC20 newToken = new MockERC20("New Token", "NEW", 18);

        // Expect revert
        vm.expectRevert();

        // Call function
        vm.prank(godmode);
        CDEPO.createToken(IERC4626(address(newToken)), 90e2);
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
        // Substring is required for the name and symbol, as they are padded with null characters
        assertEq(_getSubstring(cdTokenContract.name(), 16), "Convertible USDS", "name");
        assertEq(bytes(cdTokenContract.name()).length, 32, "name length");
        assertEq(_getSubstring(cdTokenContract.symbol(), 6), "cdUSDS", "symbol");
        assertEq(bytes(cdTokenContract.symbol()).length, 32, "symbol length");
        assertEq(cdTokenContract.decimals(), 18, "decimals");
        assertEq(cdTokenContract.owner(), address(CDEPO), "owner");
        assertEq(address(cdTokenContract.asset()), address(iReserveTokenTwo), "asset");
        assertEq(address(cdTokenContract.vault()), address(iReserveTokenTwoVault), "vault");
    }
}
