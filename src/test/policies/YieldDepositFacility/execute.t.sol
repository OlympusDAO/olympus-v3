// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {YieldDepositFacilityTest} from "./YieldDepositFacilityTest.sol";

import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";

contract YieldDepositFacilityExecuteTest is YieldDepositFacilityTest {
    event RateSnapshotTaken(address indexed vault, uint48 timestamp, uint256 rate);

    // given the contract is disabled
    //  [X] it does nothing

    function test_givenDisabled() public {
        // Call the function
        vm.prank(heart);
        yieldDepositFacility.execute();

        // Expect no snapshot to be taken
        assertEq(
            yieldDepositFacility.vaultRateSnapshots(iVault, uint48(block.timestamp)),
            0,
            "Snapshot should not be taken"
        );
    }

    // given the caller is not the heart
    //  [X] it reverts

    function test_givenCallerIsNotHeart_reverts() public givenLocallyActive {
        // Expect revert
        _expectRoleRevert("heart");

        // Call the function
        vm.prank(recipient);
        yieldDepositFacility.execute();
    }

    // given a snapshot has already been taken for the current timestamp
    //  [X] it does nothing

    function test_givenSnapshotAlreadyTaken(uint48 timestamp) public givenLocallyActive {
        // Set the timestamp to be a multiple of 8 hours
        timestamp = uint48(bound(timestamp, INITIAL_BLOCK, INITIAL_BLOCK + 10 days));
        timestamp = (timestamp / 8 hours) * 8 hours;
        assertEq(timestamp % 8 hours, 0, "Timestamp is not a multiple of 8 hours");
        vm.warp(timestamp);

        // Get the current vault conversion rate
        uint256 currentRate = vault.convertToAssets(1e18);

        // Execute and force a snapshot to be taken
        vm.prank(heart);
        yieldDepositFacility.execute();

        // Mint more reserve tokens to the vault, so the conversion rate changes
        reserveToken.mint(address(vault), 1e18);
        assertTrue(
            vault.convertToAssets(1e18) != currentRate,
            "Vault conversion rate is not different"
        );

        // Force another snapshot to be taken
        vm.prank(heart);
        yieldDepositFacility.execute();

        // The snapshot remains unchanged
        assertEq(
            yieldDepositFacility.vaultRateSnapshots(iVault, timestamp),
            currentRate,
            "Snapshot should not change"
        );
    }

    // given an asset is configured without a vault
    //  [X] it does nothing

    function test_givenAssetWithoutVault(uint48 timestamp) public givenLocallyActive {
        // Configure an asset without a vault
        MockERC20 newAsset = new MockERC20("New Asset", "NEW", 18);
        vm.prank(admin);
        depositManager.addAsset(IERC20(address(newAsset)), IERC4626(address(0)), type(uint256).max);

        // Set the timestamp to be anything but a multiple of 8 hours
        timestamp = uint48(bound(timestamp, INITIAL_BLOCK, INITIAL_BLOCK + 16 hours));
        timestamp = (timestamp / 8 hours) * 8 hours;
        assertEq(timestamp % 8 hours, 0, "Timestamp is not a multiple of 8 hours");
        vm.warp(timestamp);

        // Get the current vault conversion rate
        uint256 currentRate = vault.convertToAssets(1e18);
        uint256 currentRateTwo = vaultTwo.convertToAssets(1e18);

        // Expect event to be emitted
        vm.expectEmit(true, true, true, true);
        emit RateSnapshotTaken(address(vault), timestamp, currentRate);
        vm.expectEmit(true, true, true, true);
        emit RateSnapshotTaken(address(vaultTwo), timestamp, currentRateTwo);

        // Call the function
        vm.prank(heart);
        yieldDepositFacility.execute();

        // Expect the snapshot to be taken at the timestamp
        assertEq(
            yieldDepositFacility.vaultRateSnapshots(iVault, timestamp),
            currentRate,
            "Snapshot should be taken at the timestamp"
        );

        // Ensure there was no snapshot taken for the zero address
        assertEq(
            yieldDepositFacility.vaultRateSnapshots(IERC4626(address(0)), timestamp),
            0,
            "Snapshot should not be taken for the zero address"
        );
    }

    // [X] the snapshot timestamp is the current timestamp
    // [X] it stores the rate snapshot for each vault
    // [X] it emits a SnapshotTaken event

    function test_success(uint48 timestamp) public givenLocallyActive {
        timestamp = uint48(bound(timestamp, INITIAL_BLOCK, INITIAL_BLOCK + 16 hours));
        vm.warp(timestamp);

        // Get the current vault conversion rate
        uint256 currentRate = vault.convertToAssets(1e18);

        // Expect event to be emitted
        vm.expectEmit(true, true, true, true);
        emit RateSnapshotTaken(address(vault), timestamp, currentRate);

        // Call the function
        vm.prank(heart);
        yieldDepositFacility.execute();

        // Expect the snapshot to be taken at the timestamp
        assertEq(
            yieldDepositFacility.vaultRateSnapshots(iVault, timestamp),
            currentRate,
            "Snapshot should be taken at the timestamp"
        );
    }
}
