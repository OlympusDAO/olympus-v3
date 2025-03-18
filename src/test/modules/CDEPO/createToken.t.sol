// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {CDEPOTest} from "./CDEPOTest.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";

import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IConvertibleDepository} from "src/modules/CDEPO/IConvertibleDepository.sol";
import {IConvertibleDepositERC20} from "src/modules/CDEPO/IConvertibleDepositERC20.sol";

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
        CDEPO.create(iReserveTokenTwoVault, 90e2);
    }

    function test_alreadySupported_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepository.CDEPO_InvalidArgs.selector, "exists")
        );

        // Call function
        vm.prank(godmode);
        CDEPO.create(IERC4626(address(vault)), 90e2);
    }

    function test_reclaimRateGreaterThan100_reverts(uint16 reclaimRate_) public {
        vm.assume(reclaimRate_ > 100e2);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepository.CDEPO_InvalidArgs.selector, "reclaimRate")
        );

        // Call function
        vm.prank(godmode);
        CDEPO.create(iReserveTokenTwoVault, reclaimRate_);
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
        IConvertibleDepositERC20 cdToken = CDEPO.create(IERC4626(address(newTokenVault)), 90e2);

        // Assert values
        assertEq(cdToken.name(), "Convertible AVeryLongTokenNameTh", "name");
        assertEq(bytes(cdToken.name()).length, 32, "name length");
        assertEq(_getSubstring(cdToken.symbol(), 6), "cdLONG", "symbol");
        assertEq(bytes(cdToken.symbol()).length, 32, "symbol length");
    }

    function test_symbolTooLong() public {
        // Create a token with a symbol that is too long
        MockERC20 newToken = new MockERC20("New Token", "AVERYLONGTOKENSYMBOLTHATISWAYTOOLONG", 18);
        MockERC4626 newTokenVault = new MockERC4626(newToken, "Savings New Token", "sNEW");

        // Call function
        vm.prank(godmode);
        IConvertibleDepositERC20 cdToken = CDEPO.create(IERC4626(address(newTokenVault)), 90e2);

        // Assert values
        assertEq(_getSubstring(cdToken.name(), 21), "Convertible New Token", "name");
        assertEq(bytes(cdToken.name()).length, 32, "name length");
        assertEq(cdToken.symbol(), "cdAVERYLONGTOKENSYMBOLTHATISWAYT", "symbol");
        assertEq(bytes(cdToken.symbol()).length, 32, "symbol length");
    }

    function test_differentDecimals() public {
        // Create a token with different decimals
        MockERC20 newToken = new MockERC20("New Token", "NEW", 6);
        MockERC4626 newTokenVault = new MockERC4626(newToken, "Savings New Token", "sNEW");

        // Call function
        vm.prank(godmode);
        IConvertibleDepositERC20 cdToken = CDEPO.create(IERC4626(address(newTokenVault)), 90e2);

        assertEq(cdToken.decimals(), 6, "decimals");
    }

    function test_notERC4626_reverts() public {
        // Create a token with a non-ERC4626 vault
        MockERC20 newToken = new MockERC20("New Token", "NEW", 18);

        // Expect revert
        vm.expectRevert();

        // Call function
        vm.prank(godmode);
        CDEPO.create(IERC4626(address(newToken)), 90e2);
    }

    function test_success() public {
        // Call function
        vm.prank(godmode);
        IConvertibleDepositERC20 cdToken = CDEPO.create(iReserveTokenTwoVault, 90e2);

        // Assert values
        assertEq(
            address(CDEPO.getConvertibleToken(address(iReserveTokenTwo))),
            address(cdToken),
            "getConvertibleToken: iReserveTokenTwo"
        );
        assertEq(
            address(CDEPO.getConvertibleToken(address(cdToken))),
            address(0),
            "getConvertibleToken: cdToken"
        );

        assertEq(
            address(CDEPO.getDepositToken(address(cdToken))),
            address(iReserveTokenTwo),
            "getDepositToken: cdToken"
        );
        assertEq(
            address(CDEPO.getDepositToken(address(iReserveTokenTwo))),
            address(0),
            "getDepositToken: iReserveTokenTwo"
        );

        assertEq(
            CDEPO.isDepositToken(address(iReserveTokenTwo)),
            true,
            "isDepositToken: iReserveTokenTwo"
        );
        assertEq(CDEPO.isDepositToken(address(cdToken)), false, "isDepositToken: cdToken");

        assertEq(
            CDEPO.isConvertibleDepositToken(address(iReserveTokenTwo)),
            true,
            "isConvertibleDepositToken: iReserveTokenTwo"
        );
        assertEq(
            CDEPO.isConvertibleDepositToken(address(cdToken)),
            false,
            "isConvertibleDepositToken: cdToken"
        );

        assertEq(CDEPO.reclaimRate(address(iReserveTokenTwo)), 90e2, "reclaimRate");

        // Substring is required for the name and symbol, as they are padded with null characters
        assertEq(_getSubstring(cdToken.name(), 16), "Convertible USDS", "name");
        assertEq(bytes(cdToken.name()).length, 32, "name length");
        assertEq(_getSubstring(cdToken.symbol(), 6), "cdUSDS", "symbol");
        assertEq(bytes(cdToken.symbol()).length, 32, "symbol length");
        assertEq(cdToken.decimals(), 18, "decimals");
        assertEq(cdToken.owner(), address(CDEPO), "owner");
        assertEq(address(cdToken.asset()), address(iReserveTokenTwo), "asset");
        assertEq(address(cdToken.vault()), address(iReserveTokenTwoVault), "vault");
    }
}
