// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {YieldDepositFacilityTest} from "./YieldDepositFacilityTest.sol";
import {IYieldDepositFacility} from "src/policies/interfaces/IYieldDepositFacility.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {CDPOSv1} from "src/modules/CDPOS/CDPOS.v1.sol";
import {CDFacility} from "src/policies/CDFacility.sol";
import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {Actions} from "src/Kernel.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {IERC20} from "src/interfaces/IERC20.sol";

contract PreviewHarvestYDFTest is YieldDepositFacilityTest {
    uint256 public DEPOSIT_AMOUNT = 9e18;
    uint256 public POSITION_ID = 0;

    // given the contract is disabled
    //  [X] it reverts
    // given the position does not exist
    //  [X] it reverts
    // when timestamp hints are provided
    //  when the number of hints is not the same as the number of positions
    //   [X] it reverts
    // given the position is convertible
    //  [X] it reverts
    // given the provided recipient is not the owner of the position
    //  [X] it reverts
    // given any position has a different CD token
    //  [X] it reverts
    // given the owner has never claimed yield
    //  [X] it returns the yield since minting, with a fee deduction
    // given the owner has claimed yield
    //  [X] it returns the yield since the last claim, with a fee deduction
    // given the position has expired
    //   given a timestamp hint is provided
    //    given the timestamp hint is not before the expiry
    //     [X] it reverts
    //    given the rounded timestamp hint does not have a rate snapshot
    //     [X] it reverts
    //    [X] it returns the yield for the conversion rate at the rounded timestamp hint
    //   [X] it reverts
    // given the yield fee is 0
    //  [X] it returns the yield without any fee deduction

    function test_whenDisabled_reverts() public {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(PolicyEnabler.NotEnabled.selector));

        // Attempt to preview harvest
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = POSITION_ID;
        yieldDepositFacility.previewHarvest(recipient, positionIds);
    }

    function test_whenPositionDoesNotExist_reverts() public givenLocallyActive {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(CDPOSv1.CDPOS_InvalidPositionId.selector, POSITION_ID)
        );

        // Attempt to preview harvest non-existent position
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = POSITION_ID;
        yieldDepositFacility.previewHarvest(recipient, positionIds);
    }

    function test_withTimestampHints_incorrectLength_reverts()
        public
        givenLocallyActive
        givenAddressHasYieldDepositPosition(recipient, DEPOSIT_AMOUNT)
    {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldDepositFacility.YDF_InvalidArgs.selector,
                "array length mismatch"
            )
        );

        // Prepare inputs
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = POSITION_ID;
        uint48[] memory positionTimestampHints = new uint48[](2);
        positionTimestampHints[0] = 1;
        positionTimestampHints[1] = 2;

        // Attempt to preview harvest
        yieldDepositFacility.previewHarvest(recipient, positionIds, positionTimestampHints);
    }

    function test_whenConvertible_reverts()
        public
        givenLocallyActive
        givenAddressHasYieldDepositPosition(recipient, DEPOSIT_AMOUNT)
    {
        // Set up the MINTR module
        MockERC20 ohm = new MockERC20("Olympus", "OHM", 9);
        OlympusMinter minter = new OlympusMinter(kernel, address(ohm));
        kernel.executeAction(Actions.InstallModule, address(minter));

        // Set up the CD Facility
        CDFacility cdFacility = new CDFacility(address(kernel));
        address auctioneer = address(0xAAAA);
        kernel.executeAction(Actions.ActivatePolicy, address(cdFacility));
        rolesAdmin.grantRole("cd_auctioneer", auctioneer);
        vm.prank(admin);
        cdFacility.enable("");

        // Mint a CD position
        reserveToken.mint(recipient, 1e18);
        vm.startPrank(recipient);
        reserveToken.approve(address(convertibleDepository), 1e18);
        vm.stopPrank();
        vm.startPrank(auctioneer);
        uint256 positionId = cdFacility.mint(cdToken, recipient, 1e18, 2e18, false);
        vm.stopPrank();

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IYieldDepositFacility.YDF_Unsupported.selector, positionId)
        );

        // Attempt to preview harvest convertible position
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = positionId;
        yieldDepositFacility.previewHarvest(recipient, positionIds);
    }

    function test_whenNotOwner_reverts()
        public
        givenLocallyActive
        givenAddressHasYieldDepositPosition(recipient, DEPOSIT_AMOUNT)
    {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IYieldDepositFacility.YDF_NotOwner.selector, POSITION_ID)
        );

        // Attempt to preview harvest as non-owner
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = POSITION_ID;
        yieldDepositFacility.previewHarvest(recipientTwo, positionIds);
    }

    function test_whenDifferentCDToken_reverts()
        public
        givenLocallyActive
        givenAddressHasYieldDepositPosition(recipient, DEPOSIT_AMOUNT)
    {
        // Create a yield position for the second CD token
        reserveTokenTwo.mint(recipient, 1e18);
        vm.startPrank(recipient);
        reserveTokenTwo.approve(address(convertibleDepository), 1e18);
        yieldDepositFacility.mint(cdTokenTwo, 1e18, false);
        vm.stopPrank();

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldDepositFacility.YDF_InvalidArgs.selector,
                "multiple CD tokens"
            )
        );

        // Attempt to preview harvest positions with different CD tokens
        uint256[] memory positionIds = new uint256[](2);
        positionIds[0] = POSITION_ID;
        positionIds[1] = 1;
        yieldDepositFacility.previewHarvest(recipient, positionIds);
    }

    function test_whenNeverClaimed()
        public
        givenLocallyActive
        givenAddressHasYieldDepositPosition(recipient, DEPOSIT_AMOUNT)
        givenVaultAccruesYield(iVault, 1e18)
        givenYieldFee(1000) // 10%
    {
        // Prepare position IDs
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = POSITION_ID;

        // Calculate expected yield and fee
        uint256 lastConversionRate = yieldDepositFacility.positionLastYieldConversionRate(
            POSITION_ID
        );
        uint256 currentConversionRate = iVault.convertToAssets(1e18);
        uint256 expectedYield = ((currentConversionRate - lastConversionRate) * DEPOSIT_AMOUNT) /
            1e18;
        assertTrue(expectedYield > 0, "Expected yield is not non-zero");
        uint256 expectedFee = (expectedYield * 1000) / 10000;

        // Preview harvest yield
        (uint256 previewedYield, IERC20 previewedAsset) = yieldDepositFacility.previewHarvest(
            recipient,
            positionIds
        );

        // Assert preview matches expected
        assertEq(previewedYield, expectedYield - expectedFee);
        assertEq(address(previewedAsset), address(reserveToken));
    }

    function test_whenClaimed()
        public
        givenLocallyActive
        givenAddressHasYieldDepositPosition(recipient, DEPOSIT_AMOUNT)
        givenVaultAccruesYield(iVault, 1e18)
        givenYieldFee(1000)
        givenHarvest(recipient, POSITION_ID)
        givenWarpForward(1 days)
        givenVaultAccruesYield(iVault, 1e18)
    {
        // Prepare position IDs
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = POSITION_ID;

        // Calculate expected yield and fee
        uint256 lastConversionRate = yieldDepositFacility.positionLastYieldConversionRate(
            POSITION_ID
        );
        uint256 currentConversionRate = iVault.convertToAssets(1e18);
        uint256 expectedYield = ((currentConversionRate - lastConversionRate) * DEPOSIT_AMOUNT) /
            1e18;
        assertTrue(expectedYield > 0, "Expected yield is not non-zero");
        uint256 expectedFee = (expectedYield * 1000) / 10000;

        // Preview harvest yield
        (uint256 previewedYield, IERC20 previewedAsset) = yieldDepositFacility.previewHarvest(
            recipient,
            positionIds
        );

        // Assert preview matches expected
        assertEq(previewedYield, expectedYield - expectedFee);
        assertEq(address(previewedAsset), address(reserveToken));
    }

    function test_withTimestampHints_whenExpired_timestampHintAfterExpiry_reverts(
        uint48 timestampHint_
    )
        public
        givenLocallyActive
        givenAddressHasYieldDepositPosition(recipient, DEPOSIT_AMOUNT)
        givenVaultAccruesYield(iVault, 1e18)
        givenYieldFee(1000)
    {
        uint48 harvestTimestamp = YIELD_EXPIRY + 1 days;

        // Timestamp hint after expiry
        timestampHint_ = uint48(bound(timestampHint_, YIELD_EXPIRY + 1, harvestTimestamp));

        // Warp to beyond expiry
        vm.warp(harvestTimestamp);

        // Prepare position IDs
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = POSITION_ID;

        uint48[] memory positionTimestampHints = new uint48[](1);
        positionTimestampHints[0] = timestampHint_;

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(IYieldDepositFacility.YDF_InvalidArgs.selector, "timestamp hint")
        );

        // Preview harvest yield
        yieldDepositFacility.previewHarvest(recipient, positionIds, positionTimestampHints);
    }

    function test_withTimestampHints_whenExpired_noRateSnapshot_reverts(
        uint48 before_,
        uint48 timestampHint_
    )
        public
        givenLocallyActive
        givenAddressHasYieldDepositPosition(recipient, DEPOSIT_AMOUNT)
        givenVaultAccruesYield(iVault, 1e18)
        givenYieldFee(1000)
    {
        uint48 harvestTimestamp = YIELD_EXPIRY + 1 days;

        // Last snapshot up to 2 days before expiry
        before_ = uint48(bound(before_, 8 hours, 2 days));
        uint48 snapshotTimestampRounded = _getRoundedTimestamp(YIELD_EXPIRY - before_);

        // Timestamp hint does not overlap with the rounded snapshot timestamp
        timestampHint_ = uint48(
            bound(timestampHint_, snapshotTimestampRounded + 8 hours, YIELD_EXPIRY)
        );

        // Move to before the end of the deposit period
        vm.warp(YIELD_EXPIRY - before_);

        // Take a rate snapshot
        _takeRateSnapshot();

        // Accrue yield (which would change the rate snapshot)
        _accrueYield(iVault, 1e18);

        // Warp to beyond expiry
        vm.warp(harvestTimestamp);

        // Prepare position IDs
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = POSITION_ID;

        uint48[] memory positionTimestampHints = new uint48[](1);
        positionTimestampHints[0] = timestampHint_;

        uint48 timestampHintRounded = _getRoundedTimestamp(timestampHint_);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldDepositFacility.YDF_NoSnapshotAvailable.selector,
                address(iVault),
                timestampHintRounded
            )
        );

        // Preview harvest yield
        yieldDepositFacility.previewHarvest(recipient, positionIds, positionTimestampHints);
    }

    function test_withTimestampHints_whenExpired_noTimestampHint_reverts(
        uint48 before_
    )
        public
        givenLocallyActive
        givenAddressHasYieldDepositPosition(recipient, DEPOSIT_AMOUNT)
        givenVaultAccruesYield(iVault, 1e18)
        givenYieldFee(1000)
    {
        uint48 harvestTimestamp = YIELD_EXPIRY + 1 days;

        // Last snapshot up to 2 days before expiry
        before_ = uint48(bound(before_, 8 hours, 2 days));

        // Move to before the end of the deposit period
        vm.warp(YIELD_EXPIRY - before_);

        // Take a rate snapshot
        _takeRateSnapshot();

        // Accrue yield (which would change the rate snapshot)
        _accrueYield(iVault, 1e18);

        // Warp to beyond expiry
        vm.warp(harvestTimestamp);

        // Prepare position IDs
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = POSITION_ID;

        uint48[] memory positionTimestampHints = new uint48[](1);
        positionTimestampHints[0] = 0;

        uint48 roundedExpiry = _getRoundedTimestamp(YIELD_EXPIRY);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IYieldDepositFacility.YDF_NoSnapshotAvailable.selector,
                address(iVault),
                roundedExpiry
            )
        );

        // Harvest yield
        yieldDepositFacility.previewHarvest(recipient, positionIds, positionTimestampHints);
    }

    function test_whenZeroFee()
        public
        givenLocallyActive
        givenAddressHasYieldDepositPosition(recipient, DEPOSIT_AMOUNT)
        givenVaultAccruesYield(iVault, 1e18)
        givenYieldFee(0)
    {
        // Prepare position IDs
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = POSITION_ID;

        // Calculate expected yield and fee
        uint256 lastConversionRate = yieldDepositFacility.positionLastYieldConversionRate(
            POSITION_ID
        );
        uint256 currentConversionRate = iVault.convertToAssets(1e18);
        uint256 expectedYield = ((currentConversionRate - lastConversionRate) * DEPOSIT_AMOUNT) /
            1e18;
        assertTrue(expectedYield > 0, "Expected yield is not non-zero");
        uint256 expectedFee = 0;

        // Preview harvest yield
        (uint256 previewedYield, IERC20 previewedAsset) = yieldDepositFacility.previewHarvest(
            recipient,
            positionIds
        );

        // Assert preview matches expected
        assertEq(previewedYield, expectedYield - expectedFee);
        assertEq(address(previewedAsset), address(reserveToken));
    }
}
