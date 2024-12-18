// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {Test} from "forge-std/Test.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ModuleTestFixtureGenerator} from "src/test/lib/ModuleTestFixtureGenerator.sol";

import {Kernel, Actions} from "src/Kernel.sol";
import {OlympusConvertibleDepositPositions} from "src/modules/CDPOS/OlympusConvertibleDepositPositions.sol";

abstract contract CDPOSTest is Test, IERC721Receiver {
    using ModuleTestFixtureGenerator for OlympusConvertibleDepositPositions;

    Kernel public kernel;
    OlympusConvertibleDepositPositions public CDPOS;
    address public godmode;

    uint256[] public positions;

    function setUp() public {
        kernel = new Kernel();
        CDPOS = OlympusConvertibleDepositPositions(address(kernel));

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
}
