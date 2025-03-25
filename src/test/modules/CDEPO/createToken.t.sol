// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {CDEPOTest} from "./CDEPOTest.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";

import {IERC4626} from "src/interfaces/IERC4626.sol";
import {IConvertibleDepository} from "src/modules/CDEPO/IConvertibleDepository.sol";
import {IConvertibleDepositERC20} from "src/modules/CDEPO/IConvertibleDepositERC20.sol";

contract CreateTokenCDEPOTest is CDEPOTest {
    event TokenCreated(address indexed depositToken, uint8 periodMonths, address indexed cdToken);

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
    // given a CD token for the deposit token and period months is already created
    //  [X] it reverts
    // given the period months is 0
    //  [X] it reverts
    // given the reclaim rate is greater than 100%
    //  [X] it reverts
    // given the name is longer than 32 characters
    //  [X] it truncates the name
    // given the symbol is longer than 32 characters
    //  [X] it truncates the symbol
    // given the vault is not an ERC4626
    //  [X] it reverts
    // given a CD token for the deposit token and period months is not created
    //  [X] it creates a new CD token
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
    // [X] the period months is set
    // [X] the CD token is returned

    function test_notPermissioned_reverts(address caller_) public {
        vm.assume(caller_ != address(godmode));

        // Expect revert
        _expectRevertPolicyNotPermitted(caller_);

        // Call function
        vm.prank(caller_);
        CDEPO.create(iReserveTokenTwoVault, PERIOD_MONTHS, reclaimRate);
    }

    function test_alreadySupported_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepository.CDEPO_InvalidArgs.selector, "exists")
        );

        // Call function
        vm.prank(godmode);
        CDEPO.create(IERC4626(address(vault)), PERIOD_MONTHS, reclaimRate);
    }

    function test_periodMonthsZero_reverts() public {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepository.CDEPO_InvalidArgs.selector,
                "periodMonths"
            )
        );

        // Call function
        vm.prank(godmode);
        CDEPO.create(iReserveTokenTwoVault, 0, reclaimRate);
    }

    function test_reclaimRateGreaterThan100_reverts(uint16 reclaimRate_) public {
        vm.assume(reclaimRate_ > 100e2);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IConvertibleDepository.CDEPO_InvalidArgs.selector, "reclaimRate")
        );

        // Call function
        vm.prank(godmode);
        CDEPO.create(iReserveTokenTwoVault, PERIOD_MONTHS, reclaimRate_);
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
        IConvertibleDepositERC20 cdToken = CDEPO.create(
            IERC4626(address(newTokenVault)),
            PERIOD_MONTHS,
            reclaimRate
        );

        // Assert values
        assertEq(cdToken.name(), "Convertible AVeryLongTokenNameTh", "name");
        assertEq(bytes(cdToken.name()).length, 32, "name length");
        assertEq(_getSubstring(cdToken.symbol(), 9), "cdLONG-6m", "symbol");
        assertEq(bytes(cdToken.symbol()).length, 32, "symbol length");
    }

    function test_symbolTooLong() public {
        // Create a token with a symbol that is too long
        MockERC20 newToken = new MockERC20("New Token", "AVERYLONGTOKENSYMBOLTHATISWAYTOOLONG", 18);
        MockERC4626 newTokenVault = new MockERC4626(newToken, "Savings New Token", "sNEW");

        // Call function
        vm.prank(godmode);
        IConvertibleDepositERC20 cdToken = CDEPO.create(
            IERC4626(address(newTokenVault)),
            PERIOD_MONTHS,
            reclaimRate
        );

        // Assert values
        assertEq(_getSubstring(cdToken.name(), 32), "Convertible New Token - 6 months", "name");
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
        IConvertibleDepositERC20 cdToken = CDEPO.create(
            IERC4626(address(newTokenVault)),
            PERIOD_MONTHS,
            reclaimRate
        );

        assertEq(cdToken.decimals(), 6, "decimals");
    }

    function test_notERC4626_reverts() public {
        // Create a token with a non-ERC4626 vault
        MockERC20 newToken = new MockERC20("New Token", "NEW", 18);

        // Expect revert
        vm.expectRevert();

        // Call function
        vm.prank(godmode);
        CDEPO.create(IERC4626(address(newToken)), PERIOD_MONTHS, reclaimRate);
    }

    function test_success() public {
        // Expect event
        vm.expectEmit(true, false, false, false);
        emit TokenCreated(address(iReserveTokenTwo), PERIOD_MONTHS, address(0));

        // Call function
        vm.prank(godmode);
        IConvertibleDepositERC20 cdTokenTwo = CDEPO.create(
            iReserveTokenTwoVault,
            PERIOD_MONTHS,
            reclaimRate
        );

        // Assert values
        assertEq(
            address(CDEPO.getConvertibleDepositToken(address(iReserveTokenTwo), PERIOD_MONTHS)),
            address(cdTokenTwo),
            "getConvertibleToken: iReserveTokenTwo"
        );
        assertEq(
            address(CDEPO.getConvertibleDepositToken(address(cdTokenTwo), PERIOD_MONTHS)),
            address(0),
            "getConvertibleToken: cdTokenTwo"
        );

        assertEq(
            address(CDEPO.getDepositToken(address(cdTokenTwo))),
            address(iReserveTokenTwo),
            "getDepositToken: cdTokenTwo"
        );
        assertEq(
            address(CDEPO.getDepositToken(address(iReserveTokenTwo))),
            address(0),
            "getDepositToken: iReserveTokenTwo"
        );

        assertEq(
            CDEPO.isDepositToken(address(iReserveTokenTwo), PERIOD_MONTHS),
            true,
            "isDepositToken: iReserveTokenTwo"
        );
        assertEq(
            CDEPO.isDepositToken(address(cdTokenTwo), PERIOD_MONTHS),
            false,
            "isDepositToken: cdTokenTwo"
        );

        assertEq(
            CDEPO.isConvertibleDepositToken(address(iReserveTokenTwo)),
            false,
            "isConvertibleDepositToken: iReserveTokenTwo"
        );
        assertEq(
            CDEPO.isConvertibleDepositToken(address(cdTokenTwo)),
            true,
            "isConvertibleDepositToken: cdTokenTwo"
        );

        assertEq(CDEPO.reclaimRate(address(cdTokenTwo)), reclaimRate, "reclaimRate");

        // Substring is required for the name and symbol, as they are padded with null characters
        assertEq(_getSubstring(cdTokenTwo.name(), 27), "Convertible USDS - 6 months", "name");
        assertEq(bytes(cdTokenTwo.name()).length, 32, "name length");
        assertEq(_getSubstring(cdTokenTwo.symbol(), 9), "cdUSDS-6m", "symbol");
        assertEq(bytes(cdTokenTwo.symbol()).length, 32, "symbol length");
        assertEq(cdTokenTwo.decimals(), 18, "decimals");
        assertEq(cdTokenTwo.owner(), address(CDEPO), "owner");
        assertEq(address(cdTokenTwo.asset()), address(iReserveTokenTwo), "asset");
        assertEq(address(cdTokenTwo.vault()), address(iReserveTokenTwoVault), "vault");
        assertEq(cdTokenTwo.periodMonths(), PERIOD_MONTHS, "periodMonths");
    }

    function test_sameDepositToken_differentPeriodMonths() public {
        uint8 periodMonths = PERIOD_MONTHS + 1;
        uint16 newReclaimRate = 80e2;

        // Call function
        vm.prank(godmode);
        IConvertibleDepositERC20 cdTokenTwo = CDEPO.create(
            iReserveTokenVault,
            periodMonths,
            newReclaimRate
        );

        // Assert values
        assertEq(
            address(CDEPO.getConvertibleDepositToken(address(iReserveToken), PERIOD_MONTHS)),
            address(cdToken),
            "getConvertibleToken: iReserveToken 6m"
        );
        assertEq(
            address(CDEPO.getConvertibleDepositToken(address(iReserveToken), periodMonths)),
            address(cdTokenTwo),
            "getConvertibleToken: iReserveToken 7m"
        );
        assertEq(
            address(CDEPO.getDepositToken(address(cdToken))),
            address(iReserveToken),
            "getDepositToken: cdToken"
        );
        assertEq(
            address(CDEPO.getDepositToken(address(cdTokenTwo))),
            address(iReserveToken),
            "getDepositToken: cdTokenTwo"
        );
        assertEq(
            CDEPO.isDepositToken(address(iReserveToken), PERIOD_MONTHS),
            true,
            "isDepositToken: iReserveToken 6m"
        );
        assertEq(
            CDEPO.isDepositToken(address(iReserveToken), periodMonths),
            true,
            "isDepositToken: iReserveToken 7m"
        );
        assertEq(
            CDEPO.isConvertibleDepositToken(address(cdToken)),
            true,
            "isConvertibleDepositToken: cdToken"
        );
        assertEq(
            CDEPO.isConvertibleDepositToken(address(cdTokenTwo)),
            true,
            "isConvertibleDepositToken: cdTokenTwo"
        );

        assertEq(CDEPO.reclaimRate(address(cdToken)), reclaimRate, "cdToken reclaimRate");
        assertEq(CDEPO.reclaimRate(address(cdTokenTwo)), newReclaimRate, "cdTokenTwo reclaimRate");

        // Substring is required for the name and symbol, as they are padded with null characters
        assertEq(_getSubstring(cdTokenTwo.name(), 30), "Convertible Reserve - 7 months", "name");
        assertEq(bytes(cdTokenTwo.name()).length, 32, "name length");
        assertEq(_getSubstring(cdTokenTwo.symbol(), 8), "cdRST-7m", "symbol");
        assertEq(bytes(cdTokenTwo.symbol()).length, 32, "symbol length");
        assertEq(cdTokenTwo.decimals(), 18, "decimals");
        assertEq(cdTokenTwo.owner(), address(CDEPO), "owner");
        assertEq(address(cdTokenTwo.asset()), address(iReserveToken), "asset");
        assertEq(address(cdTokenTwo.vault()), address(iReserveTokenVault), "vault");
        assertEq(cdTokenTwo.periodMonths(), 7, "periodMonths");
    }
}
