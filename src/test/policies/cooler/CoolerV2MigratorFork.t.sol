// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {MonoCoolerBaseTest} from "./MonoCoolerBase.t.sol";

import {Actions, Kernel} from "src/Kernel.sol";
import {PolicyEnabler} from "src/policies/utils/PolicyEnabler.sol";
import {CoolerV2Migrator} from "src/policies/cooler/CoolerV2Migrator.sol";
import {Clearinghouse} from "src/policies/Clearinghouse.sol";
import {Cooler} from "src/external/cooler/Cooler.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";
import {MockDaiUsds} from "src/test/mocks/MockDaiUsds.sol";
import {MockFlashloanLender} from "src/test/mocks/MockFlashloanLender.sol";
import {OlympusClearinghouseRegistry} from "src/modules/CHREG/OlympusClearinghouseRegistry.sol";
import {OlympusContractRegistry} from "src/modules/RGSTY/OlympusContractRegistry.sol";
import {ContractRegistryAdmin} from "src/policies/ContractRegistryAdmin.sol";
import {CoolerFactory} from "src/external/cooler/CoolerFactory.sol";

contract CoolerV2MigratorTest is MonoCoolerBaseTest {
    CoolerV2Migrator internal migrator;
    CoolerFactory internal coolerFactory;
    Clearinghouse internal clearinghouseUsds;
    Clearinghouse internal clearinghouseDai;

    MockERC20 internal dai;
    MockERC4626 internal sDai;
    MockDaiUsds internal daiMigrator;
    MockFlashloanLender internal flashLender;

    OlympusClearinghouseRegistry internal clearinghouseRegistry;
    OlympusContractRegistry internal contractRegistry;
    ContractRegistryAdmin internal contractRegistryAdmin;

    address internal USER = makeAddr("user");

    mapping(address => address) internal clearinghouseToCooler;

    function setUp() public virtual override {
        // MonoCooler setup
        super.setUp();

        // Tokens
        dai = new MockERC20("DAI", "DAI", 18);
        sDai = new MockERC4626(dai, "sDAI", "sDAI");

        // Set up a mock DAI-USDS migrator
        daiMigrator = new MockDaiUsds(dai, usds);

        // Set up a mock flash loan lender
        flashLender = new MockFlashloanLender(0, address(dai));

        // Grant roles
        rolesAdmin.grantRole("cooler_overseer", OVERSEER);
        rolesAdmin.grantRole("emergency_shutdown", OVERSEER);
        rolesAdmin.grantRole("contract_registry_admin", OVERSEER);

        // Install additional modules
        clearinghouseRegistry = new OlympusClearinghouseRegistry(
            kernel,
            address(0),
            new address[](0)
        );
        contractRegistry = new OlympusContractRegistry(address(kernel));

        vm.startPrank(EXECUTOR);
        kernel.executeAction(Actions.InstallModule, address(clearinghouseRegistry));
        kernel.executeAction(Actions.InstallModule, address(contractRegistry));
        vm.stopPrank();

        // Install ContractRegistryAdmin
        contractRegistryAdmin = new ContractRegistryAdmin(address(kernel));

        vm.startPrank(EXECUTOR);
        kernel.executeAction(Actions.ActivatePolicy, address(contractRegistryAdmin));
        vm.stopPrank();

        // Install Clearinghouses
        coolerFactory = new CoolerFactory();
        clearinghouseDai = new Clearinghouse(
            address(ohm),
            address(gohm),
            address(staking),
            address(sDai),
            address(coolerFactory),
            address(kernel)
        );
        clearinghouseUsds = new Clearinghouse(
            address(ohm),
            address(gohm),
            address(staking),
            address(susds),
            address(coolerFactory),
            address(kernel)
        );

        vm.startPrank(EXECUTOR);
        kernel.executeAction(Actions.ActivatePolicy, address(clearinghouseDai));
        kernel.executeAction(Actions.ActivatePolicy, address(clearinghouseUsds));
        vm.stopPrank();

        // Activate & deactivate DAI clearinghouse
        vm.startPrank(OVERSEER);
        clearinghouseDai.activate();
        clearinghouseDai.emergencyShutdown();
        vm.stopPrank();

        // Activate USDS clearinghouse
        vm.startPrank(OVERSEER);
        clearinghouseUsds.activate();
        vm.stopPrank();

        // Register contracts
        vm.startPrank(OVERSEER);
        contractRegistryAdmin.registerImmutableContract("dai", address(dai));
        contractRegistryAdmin.registerImmutableContract("usds", address(usds));
        contractRegistryAdmin.registerImmutableContract("gohm", address(gohm));
        contractRegistryAdmin.registerContract("flash", address(flashLender));
        contractRegistryAdmin.registerContract("dmgtr", address(daiMigrator));
        vm.stopPrank();

        // CoolerV2Migrator setup
        migrator = new CoolerV2Migrator(address(kernel), address(cooler));

        // Install the policy
        vm.prank(EXECUTOR);
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
        Clearinghouse clearinghouse;
        if (isUsds_) {
            clearinghouse = clearinghouseUsds;
        } else {
            clearinghouse = clearinghouseDai;
        }

        // Create Cooler if needed
        vm.prank(wallet_);
        address cooler = clearinghouse.factory().generateCooler(gohm, isUsds_ ? usds : dai);

        // Store the relationship
        clearinghouseToCooler[address(clearinghouse)] = cooler;

        // Approve spending of collateral
        vm.prank(wallet_);
        gohm.approve(address(clearinghouse), collateralAmount_);

        // Create loan
        vm.prank(wallet_);
        clearinghouse.lendToCooler(Cooler(cooler), collateralAmount_);
        _;
    }

    modifier givenWalletHasApprovedMigratorSpendingCollateral(address wallet_, uint256 amount_) {
        vm.prank(wallet_);
        gohm.approve(address(migrator), amount_);
        _;
    }

    // ========= ASSERTIONS ========= //

    function _expectRevert_disabled() internal {
        vm.expectRevert(abi.encodeWithSelector(PolicyEnabler.NotEnabled.selector));
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

    function test_previewConsolidate_givenDisabled_reverts()
        public
        givenWalletHasCollateralToken(USER, 1e18)
        givenWalletHasLoan(USER, true, 1e18)
        givenDisabled
    {
        // Prepare input data
        address[] memory coolers = new address[](1);
        coolers[0] = clearinghouseToCooler[address(clearinghouseUsds)];

        // Expect revert
        _expectRevert_disabled();

        // Function
        migrator.previewConsolidate(coolers);
    }

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
