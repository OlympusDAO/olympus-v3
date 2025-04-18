// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.15;

import {YieldDepositFacilityTest} from "./YieldDepositFacilityTest.sol";
import {IYieldDepositFacility} from "src/policies/interfaces/IYieldDepositFacility.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {CDPOSv1} from "src/modules/CDPOS/CDPOS.v1.sol";
import {CDFacility} from "src/policies/CDFacility.sol";
import {OlympusMinter} from "src/modules/MINTR/OlympusMinter.sol";
import {Actions} from "src/Kernel.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

contract HarvestYDFTest is YieldDepositFacilityTest {
    event Harvest(address indexed depositToken, address indexed user, uint256 yield);

    uint256 public DEPOSIT_AMOUNT = 9e18;
    uint256 public POSITION_ID = 0;

    // given the contract is disabled
    //  [X] it reverts
    // given the position does not exist
    //  [X] it reverts
    // given the position is not a supported CD token
    //  [ ] it reverts
    // given the position is convertible
    //  [ ] it reverts
    // given the position is not the owner of the position
    //  [X] it reverts
    // given any position has a different CD token
    //  [X] it reverts
    // given the owner has never claimed yield
    //  [X] it returns the yield since minting
    //  [X] it transfers the yield to the caller
    //  [X] it transfers the yield fee to the treasury
    //  [X] it updates the last yield conversion rate
    //  [X] it emits a Harvest event
    //  [X] it withdraws the yield from the CDEPO module
    // given the owner has claimed yield
    //  [X] it returns the yield since the last claim
    //  [X] it transfers the yield to the caller
    //  [X] it transfers the yield fee to the treasury
    //  [X] it updates the last yield conversion rate
    //  [X] it emits a Harvest event
    //  [X] it withdraws the yield from the CDEPO module
    // given the position has expired
    //  given a rate snapshot is not available for the expiry timestamp
    //   given there is a rate snapshot available for the previous rounded timestamp
    //    [ ] it returns the yield for the conversion rate before expiry
    //   [ ] it reverts
    //  [X] it returns the yield up to the conversion rate before expiry
    //  [X] it transfers the yield to the caller
    //  [X] it transfers the yield fee to the treasury
    //  [X] it updates the last yield conversion rate
    //  [X] it emits a Harvest event
    //  [X] it withdraws the yield from the CDEPO module
    // given the yield fee is 0
    //  [X] it returns the yield
    //  [X] it updates the last yield conversion rate
    //  [X] it transfers the yield to the caller
    //  [X] it does not transfer the yield fee to the treasury
    //  [X] it emits a Harvest event
    //  [X] it withdraws the yield from the CDEPO module

    function test_whenDisabled_reverts() public {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(PolicyEnabler.NotEnabled.selector));

        // Attempt to harvest
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = POSITION_ID;
        vm.prank(recipient);
        yieldDepositFacility.harvest(positionIds);
    }

    function test_whenPositionDoesNotExist_reverts() public givenLocallyActive {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(CDPOSv1.CDPOS_InvalidPositionId.selector, POSITION_ID)
        );

        // Attempt to harvest non-existent position
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = POSITION_ID;
        vm.prank(recipient);
        yieldDepositFacility.harvest(positionIds);
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

        // Attempt to harvest convertible position
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = positionId;
        vm.prank(recipient);
        yieldDepositFacility.harvest(positionIds);
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

        // Attempt to harvest as non-owner
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = POSITION_ID;
        vm.prank(recipientTwo);
        yieldDepositFacility.harvest(positionIds);
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

        // Attempt to harvest positions with different CD tokens
        uint256[] memory positionIds = new uint256[](2);
        positionIds[0] = POSITION_ID;
        positionIds[1] = 1;
        vm.prank(recipient);
        yieldDepositFacility.harvest(positionIds);
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
        uint256 expectedYield = ((lastConversionRate - currentConversionRate) * DEPOSIT_AMOUNT) /
            1e18;
        assertTrue(expectedYield > 0, "Expected yield is not non-zero");
        uint256 expectedFee = (expectedYield * 1000) / 10000;
        uint256 expectedYieldShares = vault.previewWithdraw(expectedYield);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit Harvest(address(reserveToken), recipient, expectedYield);

        // Harvest yield
        vm.prank(recipient);
        yieldDepositFacility.harvest(positionIds);

        // Assert balances
        _assertHarvestBalances(
            recipient,
            POSITION_ID,
            expectedYield,
            expectedFee,
            expectedFee,
            expectedYieldShares,
            currentConversionRate
        );
    }

    function test_whenClaimed()
        public
        givenLocallyActive
        givenAddressHasYieldDepositPosition(recipient, 1e18)
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
        uint256 expectedYield = ((lastConversionRate - currentConversionRate) * DEPOSIT_AMOUNT) /
            1e18;
        assertTrue(expectedYield > 0, "Expected yield is not non-zero");
        uint256 expectedFee = (expectedYield * 1000) / 10000;
        uint256 expectedYieldShares = vault.previewWithdraw(expectedYield);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit Harvest(address(reserveToken), recipient, expectedYield);

        // Harvest yield
        vm.prank(recipient);
        yieldDepositFacility.harvest(positionIds);

        // Assert balances
        _assertHarvestBalances(
            recipient,
            POSITION_ID,
            expectedYield,
            expectedFee,
            expectedFee,
            expectedYieldShares,
            currentConversionRate
        );
    }

    function test_whenExpired_givenRateSnapshotOnExpiry(
        uint48 elapsed_
    )
        public
        givenLocallyActive
        givenAddressHasYieldDepositPosition(recipient, 1e18)
        givenVaultAccruesYield(iVault, 1e18)
        givenYieldFee(1000)
        givenDepositPeriodEnded(0)
        givenRateSnapshotTaken
        givenVaultAccruesYield(iVault, 1e18)
    {
        // Move beyond the end of the deposit period
        elapsed_ = uint48(bound(elapsed_, 0, 1 days));
        vm.warp(YIELD_EXPIRY + elapsed_);

        // Prepare position IDs
        uint256[] memory positionIds = new uint256[](1);
        positionIds[0] = POSITION_ID;

        // Calculate expected yield and fee
        uint256 lastConversionRate = yieldDepositFacility.positionLastYieldConversionRate(
            POSITION_ID
        );
        uint256 rateSnapshotConversionRate = yieldDepositFacility.vaultRateSnapshots(
            iVault,
            _getRoundedTimestamp(YIELD_EXPIRY)
        );
        uint256 expectedYield = ((lastConversionRate - rateSnapshotConversionRate) *
            DEPOSIT_AMOUNT) / 1e18;
        assertTrue(expectedYield > 0, "Expected yield is not non-zero");
        uint256 expectedFee = (expectedYield * 1000) / 10000;
        uint256 expectedYieldShares = vault.previewWithdraw(expectedYield);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit Harvest(address(reserveToken), recipient, expectedYield);

        // Harvest yield
        vm.prank(recipient);
        yieldDepositFacility.harvest(positionIds);

        // Assert balances
        _assertHarvestBalances(
            recipient,
            POSITION_ID,
            expectedYield,
            expectedFee,
            expectedFee,
            expectedYieldShares,
            rateSnapshotConversionRate
        );
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
        uint256 expectedYield = ((lastConversionRate - currentConversionRate) * DEPOSIT_AMOUNT) /
            1e18;
        assertTrue(expectedYield > 0, "Expected yield is not non-zero");
        uint256 expectedFee = 0;
        uint256 expectedYieldShares = vault.previewWithdraw(expectedYield);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit Harvest(address(reserveToken), recipient, expectedYield);

        // Harvest yield
        vm.prank(recipient);
        yieldDepositFacility.harvest(positionIds);

        // Assert balances
        _assertHarvestBalances(
            recipient,
            POSITION_ID,
            expectedYield,
            expectedFee,
            expectedFee,
            expectedYieldShares,
            currentConversionRate
        );
    }
}
