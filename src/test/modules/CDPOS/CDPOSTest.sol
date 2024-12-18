// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ModuleTestFixtureGenerator} from "src/test/lib/ModuleTestFixtureGenerator.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {OlympusConvertibleDepositPositions} from "src/modules/CDPOS/OlympusConvertibleDepositPositions.sol";

abstract contract CDPOSTest is Test, IERC721Receiver {
    using ModuleTestFixtureGenerator for OlympusConvertibleDepositPositions;

    uint256 public constant REMAINING_DEPOSIT = 25e18;
    uint256 public constant CONVERSION_PRICE = 2e18;
    uint48 public constant EXPIRY_DELAY = 1 days;
    uint48 public constant INITIAL_BLOCK = 100000000;

    Kernel public kernel;
    OlympusConvertibleDepositPositions public CDPOS;
    address public godmode;
    address public convertibleDepositToken;

    uint256[] public positions;

    function setUp() public {
        vm.warp(INITIAL_BLOCK);

        kernel = new Kernel();
        CDPOS = new OlympusConvertibleDepositPositions(address(kernel));

        // Set up the convertible deposit token
        MockERC20 mockERC20 = new MockERC20();
        mockERC20.initialize("Convertible Deposit Token", "CDT", 18);
        convertibleDepositToken = address(mockERC20);

        // Generate fixtures
        godmode = CDPOS.generateGodmodeFixture(type(OlympusConvertibleDepositPositions).name);

        // Install modules and policies on Kernel
        kernel.executeAction(Actions.InstallModule, address(CDPOS));
        kernel.executeAction(Actions.ActivatePolicy, godmode);
    }

    function onERC721Received(
        address,
        address,
        uint256 tokenId,
        bytes calldata
    ) external override returns (bytes4) {
        positions.push(tokenId);

        return this.onERC721Received.selector;
    }

    // ========== MODIFIERS ========== //

    modifier givenConvertibleDepositTokenDecimals(uint8 decimals_) {
        // Create a new token with the given decimals
        MockERC20 mockERC20 = new MockERC20();
        mockERC20.initialize("Convertible Deposit Token", "CDT", decimals_);
        convertibleDepositToken = address(mockERC20);
        _;
    }

    function _createPosition(
        address owner_,
        uint256 remainingDeposit_,
        uint256 conversionPrice_,
        uint48 expiry_,
        bool wrap_
    ) internal {
        vm.prank(godmode);
        CDPOS.create(
            owner_,
            convertibleDepositToken,
            remainingDeposit_,
            conversionPrice_,
            expiry_,
            wrap_
        );
    }

    modifier givenPositionCreated(
        address owner_,
        uint256 remainingDeposit_,
        uint256 conversionPrice_,
        uint48 expiry_,
        bool wrap_
    ) {
        // Create a new position
        _createPosition(owner_, remainingDeposit_, conversionPrice_, expiry_, wrap_);
        _;
    }
}
