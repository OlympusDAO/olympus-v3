// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {MonoCoolerBaseTest} from "./MonoCoolerBase.t.sol";

import {Actions, Kernel} from "src/Kernel.sol";
import {CoolerV2Migrator} from "src/policies/cooler/CoolerV2Migrator.sol";
import {Clearinghouse} from "src/policies/Clearinghouse.sol";

contract CoolerV2MigratorForkTest is MonoCoolerBaseTest {
    CoolerV2Migrator internal migrator;
    Clearinghouse internal clearinghouseUsds;
    Clearinghouse internal clearinghouseDai;
    string internal RPC_URL = vm.envString("FORK_TEST_RPC_URL");

    function setUp() public virtual override {
        // Fork
        // After activation of the USDS Clearinghouse
        // https://etherscan.io/tx/0x0afa12347eb2bf33b502f12db2db3b2ec261a673b57e51d4b85fd10169629458
        vm.createSelectFork(RPC_URL, 21302624);

        // MonoCooler setup
        super.setUp();

        // Clearinghouse setup
        clearinghouseDai = Clearinghouse(0xE6343ad0675C9b8D3f32679ae6aDbA0766A2ab4c);
        clearinghouseUsds = Clearinghouse(0x1e094fE00E13Fd06D64EeA4FB3cD912893606fE0);

        // CoolerV2Migrator setup
        migrator = new CoolerV2Migrator(address(kernel), address(cooler));

        // Install the policy
        kernel.executeAction(Actions.ActivatePolicy, address(migrator));

        // Enable the policy
        vm.startPrank(OVERSEER);
        migrator.enable(abi.encode(""));
        vm.stopPrank();
    }

    // ========= MODIFIERS ========= //

    modifier givenDisabled() {
        vm.startPrank(OVERSEER);
        migrator.disable(abi.encode(""));
        vm.stopPrank();
        _;
    }

    modifier givenEnabled() {
        vm.startPrank(OVERSEER);
        migrator.enable(abi.encode(""));
        vm.stopPrank();
        _;
    }

    modifier givenWalletHasCollateralToken(address wallet_, uint256 amount_) {
        gohm.mint(wallet_, amount_);
        _;
    }

    modifier givenWalletHasLoan(
        address wallet_,
        bool isUsds_,
        uint256 collateralAmount_
    ) {
        // Create Cooler if needed
        // Create loan
    }

    // ========= TESTS ========= //

    // previewConsolidate
    // given the contract is disabled
    //  [ ] it reverts
    // given there are no loans
    //  [ ] it returns 0 collateral
    //  [ ] it returns 0 borrowed
    // given there is a repaid loan
    //  [ ] it ignores the repaid loan
    // given the flash fee is non-zero
    //  [ ] it returns the total collateral returned
    //  [ ] the total borrowed is the principal + interest + flash fee
    // [ ] it returns the total collateral returned
    // [ ] the total borrowed is the principal + interest

    // consolidate
    // given the contract is disabled
    //  [ ] it reverts
    // given the number of clearinghouses and coolers are not the same
    //  [ ] it reverts
    // given any clearinghouse is not owned by the Olympus protocol
    //  [ ] it reverts
    // given any cooler is not created by the clearinghouse's CoolerFactory
    //  [ ] it reverts
    // given any cooler is not owned by the caller
    //  [ ] it reverts
    // given a cooler is a duplicate
    //  [ ] it reverts
    // given the Cooler debt token is not DAI or USDS
    //  [ ] it reverts
    // given the caller has not approved the CoolerV2Migrator to spend the collateral
    //  [ ] it reverts
    // given MonoCooler authorization has been provided
    //  [ ] it does not set the authorization signature
    //  [ ] it deposits the collateral into MonoCooler
    //  [ ] it borrows the principal + interest from MonoCooler
    //  [ ] the Cooler V1 loans are repaid
    //  [ ] the migrator does not hold any tokens
    // when a MonoCooler authorization signature is not provided
    //  [ ] it reverts
    // when the new owner is different to the existing owner
    //  [ ] it sets the authorization signature
    //  [ ] it deposits the collateral into MonoCooler
    //  [ ] it borrows the principal + interest from MonoCooler
    //  [ ] it sets the new owner as the owner of the Cooler V2 position
    //  [ ] the Cooler V1 loans are repaid
    //  [ ] the migrator does not hold any tokens
    // given the flash fee is non-zero
    //  [ ] it sets the authorization signature
    //  [ ] it deposits the collateral into MonoCooler
    //  [ ] it borrows the principal + interest + flash fee from MonoCooler
    //  [ ] the Cooler V1 loans are repaid
    //  [ ] the migrator does not hold any tokens
    // [ ] it sets the authorization signature
    // [ ] it deposits the collateral into MonoCooler
    // [ ] it borrows the principal + interest from MonoCooler
    // [ ] it sets the existing owner as the owner of the Cooler V2 position
    // [ ] the Cooler V1 loans are repaid
    // [ ] the migrator does not hold any tokens
}
