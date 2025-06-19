// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {YieldDepositFacilityTest} from "./YieldDepositFacilityTest.sol";

import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

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
            yieldDepositFacility.vaultRateSnapshots(iVault, _getRoundedTimestamp()),
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

    // given a snapshot has already been taken for the current rounded timestamp
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

        // Warp forward in time, but before the next snapshot is due
        vm.warp(timestamp + 1 hours);

        // Force another snapshot to be taken
        vm.prank(heart);
        yieldDepositFacility.execute();

        // The snapshot remains unchanged
        assertEq(
            yieldDepositFacility.vaultRateSnapshots(iVault, _getRoundedTimestamp()),
            currentRate,
            "Snapshot should not change"
        );
    }

    // given the current timestamp is not a multiple of 8 hours
    //  [X] the snapshot timestamp is rounded down to the nearest 8-hour interval

    function test_givenTimestampNotMultipleOf8Hours_roundsDown(
        uint48 timestamp
    ) public givenLocallyActive {
        // Set the timestamp to be anything but a multiple of 8 hours
        timestamp = uint48(bound(timestamp, INITIAL_BLOCK, INITIAL_BLOCK + 10 days));
        vm.assume(timestamp % 8 hours != 0);
        vm.warp(timestamp);

        // Get the current vault conversion rate
        uint256 currentRate = vault.convertToAssets(1e18);

        // Expect event to be emitted
        uint48 roundedTimestamp = _getRoundedTimestamp();
        vm.expectEmit(true, true, true, true);
        emit RateSnapshotTaken(address(vault), roundedTimestamp, currentRate);

        // Call the function
        vm.prank(heart);
        yieldDepositFacility.execute();

        // Expect the rounded timestamp to not equal the current timestamp
        assertFalse(
            roundedTimestamp == timestamp,
            "Rounded timestamp should not equal the current timestamp"
        );

        // Expect the snapshot to be taken at the rounded timestamp
        assertEq(
            yieldDepositFacility.vaultRateSnapshots(iVault, roundedTimestamp),
            currentRate,
            "Snapshot should be taken at the rounded timestamp"
        );
    }

    // given an asset is configured without a vault
    //  [X] it does nothing

    function test_givenAssetWithoutVault(uint48 timestamp) public givenLocallyActive {
        // Configure an asset without a vault
        MockERC20 newAsset = new MockERC20("New Asset", "NEW", 18);
        vm.prank(admin);
        depositManager.configureAssetVault(IERC20(address(newAsset)), IERC4626(address(0)));

        // Set the timestamp to be anything but a multiple of 8 hours
        timestamp = uint48(bound(timestamp, INITIAL_BLOCK, INITIAL_BLOCK + 16 hours));
        timestamp = (timestamp / 8 hours) * 8 hours;
        assertEq(timestamp % 8 hours, 0, "Timestamp is not a multiple of 8 hours");
        vm.warp(timestamp);

        // Get the current vault conversion rate
        uint256 currentRate = vault.convertToAssets(1e18);

        // Expect event to be emitted
        uint48 roundedTimestamp = _getRoundedTimestamp();
        vm.expectEmit(true, true, true, true);
        emit RateSnapshotTaken(address(vault), roundedTimestamp, currentRate);

        // Call the function
        vm.prank(heart);
        yieldDepositFacility.execute();

        // Expect the rounded timestamp to equal the current timestamp
        assertEq(
            roundedTimestamp,
            timestamp,
            "Rounded timestamp should equal the current timestamp"
        );

        // Expect the snapshot to be taken at the rounded timestamp
        assertEq(
            yieldDepositFacility.vaultRateSnapshots(iVault, roundedTimestamp),
            currentRate,
            "Snapshot should be taken at the rounded timestamp"
        );

        // Ensure there was no snapshot taken for the zero address
        assertEq(
            yieldDepositFacility.vaultRateSnapshots(IERC4626(address(0)), roundedTimestamp),
            0,
            "Snapshot should not be taken for the zero address"
        );
    }

    // [X] the snapshot timestamp is rounded down to the nearest 8-hour interval
    // [X] it stores the rate snapshot for each vault
    // [X] it emits a SnapshotTaken event

    function test_givenTimestampMultipleOf8Hours(uint48 timestamp) public givenLocallyActive {
        // Set the timestamp to be anything but a multiple of 8 hours
        timestamp = uint48(bound(timestamp, INITIAL_BLOCK, INITIAL_BLOCK + 16 hours));
        timestamp = (timestamp / 8 hours) * 8 hours;
        assertEq(timestamp % 8 hours, 0, "Timestamp is not a multiple of 8 hours");
        vm.warp(timestamp);

        // Get the current vault conversion rate
        uint256 currentRate = vault.convertToAssets(1e18);

        // Expect event to be emitted
        uint48 roundedTimestamp = _getRoundedTimestamp();
        vm.expectEmit(true, true, true, true);
        emit RateSnapshotTaken(address(vault), roundedTimestamp, currentRate);

        // Call the function
        vm.prank(heart);
        yieldDepositFacility.execute();

        // Expect the rounded timestamp to equal the current timestamp
        assertEq(
            roundedTimestamp,
            timestamp,
            "Rounded timestamp should equal the current timestamp"
        );

        // Expect the snapshot to be taken at the rounded timestamp
        assertEq(
            yieldDepositFacility.vaultRateSnapshots(iVault, roundedTimestamp),
            currentRate,
            "Snapshot should be taken at the rounded timestamp"
        );
    }
}
