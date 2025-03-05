// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {CDPOSTest} from "./CDPOSTest.sol";
import {CDPOSv1} from "src/modules/CDPOS/CDPOS.v1.sol";
import {Base64} from "base64-1.1.0/base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {console2} from "forge-std/console2.sol";

function substring(
    string memory str,
    uint256 startIndex,
    uint256 endIndex
) pure returns (string memory) {
    bytes memory strBytes = bytes(str);
    bytes memory result = new bytes(endIndex - startIndex);
    for (uint256 i = startIndex; i < endIndex; i++) {
        result[i - startIndex] = strBytes[i];
    }
    return string(result);
}

function substringFrom(string memory str, uint256 startIndex) pure returns (string memory) {
    return substring(str, startIndex, bytes(str).length);
}

// solhint-disable quotes

contract TokenURICDPOSTest is CDPOSTest {
    uint48 public constant SAMPLE_DATE = 1737014593;
    uint48 public constant SAMPLE_CONVERSION_EXPIRY_DATE = 1737014593 + 1 days;
    uint48 public constant SAMPLE_REDEMPTION_EXPIRY_DATE = 1737014593 + 2 days;
    string public constant CONVERSION_EXPIRY_DATE_STRING = "2025-01-17";

    // when the position does not exist
    //  [X] it reverts
    // when the conversion price has decimal places
    //  [X] it is displayed to 2 decimal places
    // when the remaining deposit has decimal places
    //  [X] it is displayed to 2 decimal places
    // when the remaining deposit is 0
    //  [X] it is displayed as 0
    // [X] the value is Base64 encoded
    // [X] the name value is the name of the contract
    // [X] the symbol value is the symbol of the contract
    // [X] the position ID attribute is the position ID
    // [X] the convertible deposit token attribute is the convertible deposit token address
    // [X] the conversion expiry attribute is the conversion expiry timestamp
    // [ ] the redemption expiry attribute is the redemption expiry timestamp
    // [X] the remaining deposit attribute is the remaining deposit
    // [X] the conversion price attribute is the conversion price
    // [X] the image value is set

    function test_positionDoesNotExist() public {
        vm.expectRevert(abi.encodeWithSelector(CDPOSv1.CDPOS_InvalidPositionId.selector, 1));

        CDPOS.tokenURI(1);
    }

    function test_success()
        public
        givenPositionCreated(
            address(this),
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            SAMPLE_CONVERSION_EXPIRY_DATE,
            SAMPLE_REDEMPTION_EXPIRY_DATE,
            false
        )
    {
        uint256[] memory ownerPositions = CDPOS.getUserPositionIds(address(this));
        uint256 positionId = ownerPositions[0];

        // Call function
        string memory tokenURI = CDPOS.tokenURI(positionId);

        // Check that the string begins with `data:application/json;base64,`
        assertEq(substring(tokenURI, 0, 29), "data:application/json;base64,", "prefix");

        // Strip the `data:application/json;base64,` prefix
        string memory base64EncodedTokenURI = substringFrom(tokenURI, 29);

        // Decode the return value from Base64
        string memory decodedTokenURI = string(Base64.decode(base64EncodedTokenURI));

        // Assert JSON structure
        // Name
        string memory tokenUriName = vm.parseJsonString(decodedTokenURI, ".name");
        assertEq(tokenUriName, "Olympus Convertible Deposit Position", "name");

        // Symbol
        string memory tokenUriSymbol = vm.parseJsonString(decodedTokenURI, ".symbol");
        assertEq(tokenUriSymbol, "OCDP", "symbol");

        // Position ID
        uint256 tokenUriPositionId = vm.parseJsonUint(
            decodedTokenURI,
            '.attributes[?(@.trait_type=="Position ID")].value'
        );
        assertEq(tokenUriPositionId, positionId, "positionId");

        // Convertible Deposit Token
        string memory tokenUriConvertibleDepositToken = vm.parseJsonString(
            decodedTokenURI,
            '.attributes[?(@.trait_type=="Convertible Deposit Token")].value'
        );
        assertEq(
            tokenUriConvertibleDepositToken,
            Strings.toHexString(convertibleDepositToken),
            "convertibleDepositToken"
        );

        // Conversion Expiry
        uint256 tokenUriConversionExpiry = vm.parseJsonUint(
            decodedTokenURI,
            '.attributes[?(@.trait_type=="Conversion Expiry")].value'
        );
        assertEq(tokenUriConversionExpiry, SAMPLE_CONVERSION_EXPIRY_DATE, "conversion expiry");

        // Redemption Expiry
        uint256 tokenUriRedemptionExpiry = vm.parseJsonUint(
            decodedTokenURI,
            '.attributes[?(@.trait_type=="Redemption Expiry")].value'
        );
        assertEq(tokenUriRedemptionExpiry, SAMPLE_REDEMPTION_EXPIRY_DATE, "redemption expiry");

        // Remaining Deposit
        string memory tokenUriRemainingDeposit = vm.parseJsonString(
            decodedTokenURI,
            '.attributes[?(@.trait_type=="Remaining Deposit")].value'
        );
        assertEq(tokenUriRemainingDeposit, "25", "remainingDeposit");

        // Conversion Price
        string memory tokenUriConversionPrice = vm.parseJsonString(
            decodedTokenURI,
            '.attributes[?(@.trait_type=="Conversion Price")].value'
        );
        assertEq(tokenUriConversionPrice, "2", "conversionPrice");

        // Image
        string memory tokenUriImage = vm.parseJsonString(decodedTokenURI, ".image");

        // Check that the string begins with `data:image/svg+xml;base64,`
        assertEq(substring(tokenUriImage, 0, 26), "data:image/svg+xml;base64,", "image prefix");

        // Strip the `data:image/svg+xml;base64,` prefix
        string memory base64EncodedImage = substringFrom(tokenUriImage, 26);

        // Decode the return value from Base64
        string memory decodedImage = string(Base64.decode(base64EncodedImage));

        console2.log("decodedImage", decodedImage);

        // Check that the image starts with the SVG element
        assertEq(substring(decodedImage, 0, 4), "<svg", "image starts with SVG");

        // Check that the image ends with the SVG element
        assertEq(
            substring(decodedImage, bytes(decodedImage).length - 6, bytes(decodedImage).length),
            "</svg>",
            "image ends with SVG"
        );
    }

    function test_remainingDepositHasDecimals()
        public
        givenPositionCreated(
            address(this),
            25123456e14,
            CONVERSION_PRICE,
            SAMPLE_CONVERSION_EXPIRY_DATE,
            SAMPLE_REDEMPTION_EXPIRY_DATE,
            false
        )
    {
        uint256[] memory ownerPositions = CDPOS.getUserPositionIds(address(this));
        uint256 positionId = ownerPositions[0];

        // Call function
        string memory tokenURI = CDPOS.tokenURI(positionId);

        // Check that the string begins with `data:application/json;base64,`
        assertEq(substring(tokenURI, 0, 29), "data:application/json;base64,", "prefix");

        // Strip the `data:application/json;base64,` prefix
        string memory base64EncodedTokenURI = substringFrom(tokenURI, 29);

        // Decode the return value from Base64
        string memory decodedTokenURI = string(Base64.decode(base64EncodedTokenURI));

        // Assert JSON structure
        // Remaining Deposit
        string memory tokenUriRemainingDeposit = vm.parseJsonString(
            decodedTokenURI,
            '.attributes[?(@.trait_type=="Remaining Deposit")].value'
        );
        assertEq(tokenUriRemainingDeposit, "2512.34", "remainingDeposit");
    }

    function test_remainingDepositIsZero()
        public
        givenPositionCreated(
            address(this),
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            SAMPLE_CONVERSION_EXPIRY_DATE,
            SAMPLE_REDEMPTION_EXPIRY_DATE,
            false
        )
    {
        uint256[] memory ownerPositions = CDPOS.getUserPositionIds(address(this));
        uint256 positionId = ownerPositions[0];

        // Update the position remaining deposit to 0
        _updatePosition(positionId, 0);

        // Call function
        string memory tokenURI = CDPOS.tokenURI(positionId);

        // Check that the string begins with `data:application/json;base64,`
        assertEq(substring(tokenURI, 0, 29), "data:application/json;base64,", "prefix");

        // Strip the `data:application/json;base64,` prefix
        string memory base64EncodedTokenURI = substringFrom(tokenURI, 29);

        // Decode the return value from Base64
        string memory decodedTokenURI = string(Base64.decode(base64EncodedTokenURI));

        // Assert JSON structure
        // Remaining Deposit
        string memory tokenUriRemainingDeposit = vm.parseJsonString(
            decodedTokenURI,
            '.attributes[?(@.trait_type=="Remaining Deposit")].value'
        );
        assertEq(tokenUriRemainingDeposit, "0", "remainingDeposit");
    }

    function test_conversionPriceHasDecimals()
        public
        givenPositionCreated(
            address(this),
            REMAINING_DEPOSIT,
            20123456e14,
            SAMPLE_CONVERSION_EXPIRY_DATE,
            SAMPLE_REDEMPTION_EXPIRY_DATE,
            false
        )
    {
        uint256[] memory ownerPositions = CDPOS.getUserPositionIds(address(this));
        uint256 positionId = ownerPositions[0];

        // Call function
        string memory tokenURI = CDPOS.tokenURI(positionId);

        // Check that the string begins with `data:application/json;base64,`
        assertEq(substring(tokenURI, 0, 29), "data:application/json;base64,", "prefix");

        // Strip the `data:application/json;base64,` prefix
        string memory base64EncodedTokenURI = substringFrom(tokenURI, 29);

        // Decode the return value from Base64
        string memory decodedTokenURI = string(Base64.decode(base64EncodedTokenURI));

        // Assert JSON structure
        // Conversion Price
        string memory tokenUriConversionPrice = vm.parseJsonString(
            decodedTokenURI,
            '.attributes[?(@.trait_type=="Conversion Price")].value'
        );
        assertEq(tokenUriConversionPrice, "2012.34", "conversionPrice");
    }

    function test_multiplePositions()
        public
        givenPositionCreated(
            address(this),
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            SAMPLE_CONVERSION_EXPIRY_DATE,
            SAMPLE_REDEMPTION_EXPIRY_DATE,
            false
        )
        givenPositionCreated(
            address(this),
            REMAINING_DEPOSIT,
            CONVERSION_PRICE,
            SAMPLE_CONVERSION_EXPIRY_DATE,
            SAMPLE_REDEMPTION_EXPIRY_DATE,
            false
        )
    {
        uint256[] memory ownerPositions = CDPOS.getUserPositionIds(address(this));
        uint256 positionId = ownerPositions[1];

        // Call function
        string memory tokenURI = CDPOS.tokenURI(positionId);

        // Check that the string begins with `data:application/json;base64,`
        assertEq(substring(tokenURI, 0, 29), "data:application/json;base64,", "prefix");

        // Strip the `data:application/json;base64,` prefix
        string memory base64EncodedTokenURI = substringFrom(tokenURI, 29);

        // Decode the return value from Base64
        string memory decodedTokenURI = string(Base64.decode(base64EncodedTokenURI));

        // Assert JSON structure
        uint256 tokenUriPositionId = vm.parseJsonUint(
            decodedTokenURI,
            '.attributes[?(@.trait_type=="Position ID")].value'
        );
        assertEq(tokenUriPositionId, 1, "positionId");
    }
}
