// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IYieldRepurchaseRecipient} from "src/policies/interfaces/IYieldRepurchaseRecipient.sol";

// Contracts
import {Test} from "@forge-std-1.16.2/Test.sol";
import {Kernel} from "src/Kernel.sol";
import {MockYieldRepurchaseRecipient} from "./MockYieldRepurchaseRecipient.sol";

contract MockYieldRepurchaseRecipientTest is Test {
    MockYieldRepurchaseRecipient internal _recipient;

    function setUp() public {
        _recipient = new MockYieldRepurchaseRecipient(new Kernel());
    }

    function test_whenInterfaceSelectorsCombined_matchesInterfaceId() public view {
        bytes4 expected = IYieldRepurchaseRecipient.getVaults.selector ^
            IYieldRepurchaseRecipient.getVaultConfig.selector ^
            IYieldRepurchaseRecipient.getAssetVault.selector;
        assertEq(type(IYieldRepurchaseRecipient).interfaceId, expected, "recipient interface ID");
        assertTrue(_recipient.supportsInterface(expected), "mock advertises recipient interface");
    }

    function test_whenAssetUnknown_returnsZero(address asset_) public view {
        assertEq(_recipient.getAssetVault(asset_), address(0), "unknown asset has no vault");
    }

    function test_givenVaultRegistered_whenRemoved_clearsAssetLookup() public {
        address vault = makeAddr("vault");
        address asset = makeAddr("asset");
        _recipient.setVaultConfig(vault, asset, true);
        assertEq(_recipient.getAssetVault(asset), vault, "registered asset resolves to vault");
        assertEq(_recipient.getVaultConfig(vault).shareToken, vault, "ERC4626 vault is shares");

        _recipient.removeVaultConfig(vault);

        assertEq(_recipient.getAssetVault(asset), address(0), "removed vault clears lookup");
        assertEq(_recipient.getVaults().length, 0, "removed vault is not enumerated");
    }

    function test_givenVaultRegistered_whenAssetChanges_clearsFormerAssetLookup() public {
        address vault = makeAddr("vault");
        address former = makeAddr("former asset");
        address current = makeAddr("current asset");
        _recipient.setVaultConfig(vault, former, true);

        _recipient.setVaultConfig(vault, current, true);

        assertEq(_recipient.getAssetVault(former), address(0), "former asset has no vault");
        assertEq(_recipient.getAssetVault(current), vault, "current asset resolves to vault");
    }
}
