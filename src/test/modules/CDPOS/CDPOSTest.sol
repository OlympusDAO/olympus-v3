// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {Test} from "@forge-std-1.9.6/Test.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ModuleTestFixtureGenerator} from "src/test/lib/ModuleTestFixtureGenerator.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {ERC721ReceiverMock} from "@openzeppelin/contracts/mocks/ERC721ReceiverMock.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/interfaces/IERC721Receiver.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {OlympusConvertibleDepositPositionManager} from "src/modules/CDPOS/OlympusConvertibleDepositPositionManager.sol";
import {CDPOSv1} from "src/modules/CDPOS/CDPOS.v1.sol";

abstract contract CDPOSTest is Test, IERC721Receiver {
    using ModuleTestFixtureGenerator for OlympusConvertibleDepositPositionManager;

    uint256 public constant REMAINING_DEPOSIT = 25e18;
    uint256 public constant CONVERSION_PRICE = 2e18;
    uint48 public constant CONVERSION_EXPIRY_DELAY = 1 days;
    uint48 public constant INITIAL_BLOCK = 100000000;
    uint48 public constant CONVERSION_EXPIRY = uint48(INITIAL_BLOCK + CONVERSION_EXPIRY_DELAY);
    uint8 public constant DEPOSIT_PERIOD = 9;

    Kernel public kernel;
    OlympusConvertibleDepositPositionManager public CDPOS;
    ERC721ReceiverMock public mockERC721Receiver;
    address public godmode;
    address public convertibleDepositToken;
    uint8 public convertibleDepositTokenDecimals = 18;

    uint256[] public positions;

    function setUp() public {
        vm.warp(INITIAL_BLOCK);

        kernel = new Kernel();
        CDPOS = new OlympusConvertibleDepositPositionManager(address(kernel));
        mockERC721Receiver = new ERC721ReceiverMock(
            IERC721Receiver.onERC721Received.selector,
            ERC721ReceiverMock.Error.None
        );

        // Set up the convertible deposit token
        MockERC20 mockERC20 = new MockERC20(
            "Convertible Deposit Token",
            "CDT",
            convertibleDepositTokenDecimals
        );
        convertibleDepositToken = address(mockERC20);

        // Generate fixtures
        godmode = CDPOS.generateGodmodeFixture(type(OlympusConvertibleDepositPositionManager).name);

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

    // ========== ASSERTIONS ========== //

    function _assertPosition(
        uint256 positionId_,
        address owner_,
        uint256 remainingDeposit_,
        uint256 conversionPrice_,
        uint48 conversionExpiry_,
        bool wrap_
    ) internal view {
        CDPOSv1.Position memory position = CDPOS.getPosition(positionId_);
        assertEq(position.owner, owner_, "position.owner");
        assertEq(position.asset, convertibleDepositToken, "position.asset");
        assertEq(position.periodMonths, DEPOSIT_PERIOD, "position.periodMonths");
        assertEq(position.remainingDeposit, remainingDeposit_, "position.remainingDeposit");
        assertEq(position.conversionPrice, conversionPrice_, "position.conversionPrice");
        assertEq(position.expiry, conversionExpiry_, "position.expiry");
        assertEq(position.wrapped, wrap_, "position.wrapped");
    }

    function _assertUserPosition(
        address owner_,
        uint256 positionId_,
        uint256 total_
    ) internal view {
        uint256[] memory userPositions = CDPOS.getUserPositionIds(owner_);
        assertEq(userPositions.length, total_, "userPositions.length");

        // Iterate over the positions and assert that the positionId_ is in the array
        bool found = false;
        for (uint256 i = 0; i < userPositions.length; i++) {
            if (userPositions[i] == positionId_) {
                found = true;
                break;
            }
        }
        assertTrue(found, "positionId_ not found in getUserPositionIds");
    }

    function _assertERC721Owner(uint256 positionId_, address owner_, bool minted_) internal {
        if (minted_) {
            assertEq(CDPOS.ownerOf(positionId_), owner_, "ownerOf");
        } else {
            vm.expectRevert("NOT_MINTED");
            CDPOS.ownerOf(positionId_);
        }
    }

    function _assertERC721Balance(address owner_, uint256 balance_) internal view {
        assertEq(CDPOS.balanceOf(owner_), balance_, "balanceOf");
    }

    function _assertERC721PositionReceived(
        uint256 positionId_,
        uint256 total_,
        bool received_
    ) internal view {
        assertEq(positions.length, total_, "positions.length");

        // Iterate over the positions and assert that the positionId_ is in the array
        bool found = false;
        for (uint256 i = 0; i < positions.length; i++) {
            if (positions[i] == positionId_) {
                found = true;
                break;
            }
        }

        if (received_) {
            assertTrue(found, "positionId_ not found in positions");
        } else {
            assertFalse(found, "positionId_ found in positions");
        }
    }

    // ========== MODIFIERS ========== //

    modifier givenConvertibleDepositTokenDecimals(uint8 decimals_) {
        // Create a new token with the given decimals
        MockERC20 mockERC20 = new MockERC20("Convertible Deposit Token", "CDT", decimals_);
        convertibleDepositToken = address(mockERC20);
        _;
    }

    function _createPosition(
        address owner_,
        uint256 remainingDeposit_,
        uint256 conversionPrice_,
        uint48 conversionExpiry_,
        bool wrap_
    ) internal {
        vm.prank(godmode);
        CDPOS.mint(
            owner_,
            convertibleDepositToken,
            DEPOSIT_PERIOD,
            remainingDeposit_,
            conversionPrice_,
            conversionExpiry_,
            wrap_
        );
    }

    modifier givenPositionCreated(
        address owner_,
        uint256 remainingDeposit_,
        uint256 conversionPrice_,
        uint48 conversionExpiry_,
        bool wrap_
    ) {
        // Create a new position
        _createPosition(owner_, remainingDeposit_, conversionPrice_, conversionExpiry_, wrap_);
        _;
    }

    function _updatePosition(uint256 positionId_, uint256 remainingDeposit_) internal {
        vm.prank(godmode);
        CDPOS.update(positionId_, remainingDeposit_);
    }

    function _splitPosition(
        address owner_,
        uint256 positionId_,
        uint256 amount_,
        address to_,
        bool wrap_
    ) internal {
        vm.prank(owner_);
        CDPOS.split(positionId_, amount_, to_, wrap_);
    }

    function _wrapPosition(address owner_, uint256 positionId_) internal {
        vm.prank(owner_);
        CDPOS.wrap(positionId_);
    }

    modifier givenPositionWrapped(address owner_, uint256 positionId_) {
        _wrapPosition(owner_, positionId_);
        _;
    }

    function _unwrapPosition(address owner_, uint256 positionId_) internal {
        vm.prank(owner_);
        CDPOS.unwrap(positionId_);
    }

    modifier givenPositionUnwrapped(address owner_, uint256 positionId_) {
        _unwrapPosition(owner_, positionId_);
        _;
    }
}
