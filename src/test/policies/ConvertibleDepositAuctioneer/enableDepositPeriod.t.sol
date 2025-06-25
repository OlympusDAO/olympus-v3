// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.20;

import {ConvertibleDepositAuctioneerTest} from "./ConvertibleDepositAuctioneerTest.sol";
import {IConvertibleDepositAuctioneer} from "src/policies/interfaces/IConvertibleDepositAuctioneer.sol";
import {MockERC20} from "@solmate-6.2.0/test/utils/mocks/MockERC20.sol";
import {IERC20} from "src/interfaces/IERC20.sol";
import {IERC4626} from "src/interfaces/IERC4626.sol";

contract ConvertibleDepositAuctioneerEnableDepositPeriodTest is ConvertibleDepositAuctioneerTest {
    event DepositPeriodEnabled(address depositAsset, uint8 depositPeriod);

    // when the caller does not have the "admin" or "manager" role
    //  [X] it reverts

    function test_callerDoesNotHaveAdminOrManagerRole_reverts(address caller_) public {
        // Ensure caller is not admin or manager
        vm.assume(caller_ != admin && caller_ != manager);

        // Expect revert
        _expectRevertNotAuthorised();

        // Call function
        vm.prank(caller_);
        auctioneer.enableDepositPeriod(iReserveToken, PERIOD_MONTHS);
    }

    // given the contract is not enabled
    //  [X] it succeeds

    function test_givenContractNotEnabled() public {
        // Call function
        vm.prank(admin);
        auctioneer.enableDepositPeriod(iReserveToken, PERIOD_MONTHS);

        // Assert state
        _assertDepositAssetAndPeriodEnabled(iReserveToken, PERIOD_MONTHS, 0, 0, 1);

        // Check the tick is populated
        _assertPreviousTick(0, 0, 0, uint48(block.timestamp));
    }

    // given there is another deposit asset and period enabled
    //  [X] the deposit period is added to the deposit asset's periods array
    //  [X] the deposit asset is added to the deposit assets array
    //  [X] the deposit asset and period are enabled
    //  [X] the tick for the deposit asset and period is initialized
    //  [X] an event is emitted

    function test_givenOtherDepositAssetAndPeriodEnabled()
        public
        givenEnabled
        givenDepositAssetAndPeriodEnabled(iReserveToken, PERIOD_MONTHS)
    {
        // Define a new asset and configure it
        IERC20 newAsset = IERC20(address(new MockERC20("New Asset", "NEW", 18)));
        vm.startPrank(admin);
        depositManager.configureAssetVault(newAsset, IERC4626(address(0)));
        depositManager.addAssetPeriod(newAsset, PERIOD_MONTHS, 90e2);
        vm.stopPrank();

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit DepositPeriodEnabled(address(newAsset), PERIOD_MONTHS);

        // Call function
        vm.prank(admin);
        auctioneer.enableDepositPeriod(newAsset, PERIOD_MONTHS);

        // Assert state
        _assertDepositAssetAndPeriodEnabled(newAsset, PERIOD_MONTHS, 1, 0, 2);
    }

    // given the deposit asset is already enabled
    //  given the deposit period is already enabled
    //   [X] it reverts

    function test_givenDepositAssetAndPeriodAlreadyEnabled_reverts()
        public
        givenEnabled
        givenDepositAssetAndPeriodEnabled(iReserveToken, PERIOD_MONTHS)
    {
        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(
                IConvertibleDepositAuctioneer.CDAuctioneer_DepositPeriodAlreadyEnabled.selector,
                address(iReserveToken),
                PERIOD_MONTHS
            )
        );

        // Call function
        vm.prank(admin);
        auctioneer.enableDepositPeriod(iReserveToken, PERIOD_MONTHS);
    }

    //  [X] the deposit period is added to the deposit asset's periods array
    //  [X] the deposit asset is not added to the deposit assets array
    //  [X] the deposit asset and period are enabled
    //  [X] the tick for the deposit asset and period is initialized
    //  [X] an event is emitted

    function test_givenDepositPeriodNotEnabled()
        public
        givenEnabled
        givenDepositAssetAndPeriodEnabled(iReserveToken, PERIOD_MONTHS + 1)
    {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit DepositPeriodEnabled(address(iReserveToken), PERIOD_MONTHS);

        // Call function
        vm.prank(admin);
        auctioneer.enableDepositPeriod(iReserveToken, PERIOD_MONTHS);

        // Assert state
        _assertDepositAssetAndPeriodEnabled(iReserveToken, PERIOD_MONTHS, 0, 1, 2);

        // Check the tick is populated
        _assertPreviousTick(TICK_SIZE, MIN_PRICE, TICK_SIZE, uint48(block.timestamp));
    }

    // given the deposit asset and period were previously enabled
    //  [X] the tick for the deposit asset and period is initialized

    function test_givenDepositAssetAndPeriodPreviouslyEnabled()
        public
        givenEnabled
        givenDepositAssetAndPeriodEnabled(iReserveToken, PERIOD_MONTHS)
        givenDepositAssetAndPeriodDisabled(iReserveToken, PERIOD_MONTHS)
    {
        // Warp forward, so we know the timestamp will be different
        vm.warp(block.timestamp + 1);

        // Expect event
        vm.expectEmit(true, true, true, true);
        emit DepositPeriodEnabled(address(iReserveToken), PERIOD_MONTHS);

        // Call function
        vm.prank(admin);
        auctioneer.enableDepositPeriod(iReserveToken, PERIOD_MONTHS);

        // Assert state
        _assertDepositAssetAndPeriodEnabled(iReserveToken, PERIOD_MONTHS, 0, 0, 1);

        // Check the tick is populated
        _assertPreviousTick(TICK_SIZE, MIN_PRICE, TICK_SIZE, uint48(block.timestamp));
    }

    // [X] the deposit period is added to the deposit asset's periods array
    // [X] the deposit asset is added to the deposit assets array
    // [X] the deposit asset and period are enabled
    // [X] the tick for the deposit asset and period is initialized
    // [X] an event is emitted

    function test_success() public givenEnabled {
        // Expect event
        vm.expectEmit(true, true, true, true);
        emit DepositPeriodEnabled(address(iReserveToken), PERIOD_MONTHS);

        // Call function
        vm.prank(admin);
        auctioneer.enableDepositPeriod(iReserveToken, PERIOD_MONTHS);

        // Assert state
        _assertDepositAssetAndPeriodEnabled(iReserveToken, PERIOD_MONTHS, 0, 0, 1);

        // Check the tick is populated
        _assertPreviousTick(TICK_SIZE, MIN_PRICE, TICK_SIZE, uint48(block.timestamp));
    }
}
