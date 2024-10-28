// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";
import {UserFactory} from "test/lib/UserFactory.sol";

import {MockERC20, ERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626, ERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";

import {MockDaiUsds} from "test/mocks/MockDaiUsds.sol";

import "src/Kernel.sol";
import {OlympusTreasury} from "modules/TRSRY/OlympusTreasury.sol";
import {OlympusRoles} from "modules/ROLES/OlympusRoles.sol";
import {RolesAdmin} from "policies/RolesAdmin.sol";
import {ReserveMigrator} from "policies/ReserveMigrator.sol";

// solhint-disable-next-line max-states-count
contract ReserveMigratorTest is Test {
    UserFactory public userCreator;
    address internal guardian;
    address internal heart;

    MockERC20 internal from;
    MockERC4626 internal sFrom;
    MockERC20 internal to;
    MockERC4626 internal sTo;

    MockDaiUsds internal daiUsds;

    Kernel internal kernel;
    OlympusTreasury internal TRSRY;
    OlympusRoles internal ROLES;

    ReserveMigrator internal reserveMigrator;
    RolesAdmin internal rolesAdmin;

    // Track balances in state variables to avoid stack too deep
    uint256 public fromBalance;
    uint256 public sFromBalance;
    uint256 public toBalance;
    uint256 public sToBalance;
    uint256 public fromMigratorBalance;
    uint256 public sFromMigratorBalance;
    uint256 public toMigratorBalance;
    uint256 public sToMigratorBalance;

    function setUp() public {
        // Create users
        userCreator = new UserFactory();
        {
            /// Deploy bond system to test against
            address[] memory users = userCreator.create(2);
            guardian = users[0];
            heart = users[1];
        }

        // Deploy mock tokens and converter
        from = new MockERC20("Dai Stablecoin", "DAI", 18);
        sFrom = new MockERC4626(from, "Savings Dai", "sDAI");
        to = new MockERC20("Sky USD", "USDS", 18);
        sTo = new MockERC4626(to, "Savings Sky USD", "sUSDS");
        daiUsds = new MockDaiUsds(from, to);

        // Label the tokens for easier debugging
        vm.label(address(from), "fromReserve");
        vm.label(address(sFrom), "sFromReserve");
        vm.label(address(to), "toReserve");
        vm.label(address(sTo), "sToReserve");

        // Deploy kernel, modules, and policies
        kernel = new Kernel();
        TRSRY = new OlympusTreasury(kernel);
        ROLES = new OlympusRoles(kernel);
        rolesAdmin = new RolesAdmin(kernel);
        reserveMigrator = new ReserveMigrator(
            kernel,
            address(sFrom),
            address(sTo),
            address(daiUsds)
        );

        // Install modules and policies on the kernel
        kernel.executeAction(Actions.InstallModule, address(TRSRY));
        kernel.executeAction(Actions.InstallModule, address(ROLES));
        kernel.executeAction(Actions.ActivatePolicy, address(rolesAdmin));
        kernel.executeAction(Actions.ActivatePolicy, address(reserveMigrator));

        // Grant roles for the migrator
        rolesAdmin.grantRole("heart", heart);
        rolesAdmin.grantRole("reserve_migrator_admin", guardian);

        // Set the conversion rate from from to sFrom and to to sTo as 2:1
        // We use this relatively high value to make the calculations simpler
        // We do this by depositing 1 from into sFrom and then minting another token to it
        // Same thing for to and sTo
        from.mint(address(this), 1e18);
        from.approve(address(sFrom), 1e18);
        sFrom.deposit(1e18, address(this));
        from.mint(address(sFrom), 1e18);

        to.mint(address(this), 1e18);
        to.approve(address(sTo), 1e18);
        sTo.deposit(1e18, address(this));
        to.mint(address(sTo), 1e18);
    }

    // helper functions and modifiers
    modifier givenAmountValid(uint256 amount_) {
        vm.assume(amount_ >= 2 && amount_ <= 1e29); // between 2 and 100 billion
        _;
    }

    function _issueFrom(address receiver_, uint256 amount_) internal {
        from.mint(receiver_, amount_);
    }

    modifier givenTreasuryHasFrom(uint256 amount_) {
        _issueFrom(address(TRSRY), amount_);
        fromBalance += amount_;
        _;
    }

    modifier givenMigratorHasFrom(uint256 amount_) {
        _issueFrom(address(reserveMigrator), amount_);
        fromMigratorBalance += amount_;
        _;
    }

    function _issueWrappedFrom(address receiver_, uint256 amount_) internal {
        from.mint(address(this), 2 * amount_);
        from.approve(address(sFrom), 2 * amount_);
        sFrom.mint(amount_, receiver_);
    }

    modifier givenTreasuryHasWrappedFrom(uint256 amount_) {
        _issueWrappedFrom(address(TRSRY), amount_);
        sFromBalance += amount_;
        _;
    }

    modifier givenMigratorHasWrappedFrom(uint256 amount_) {
        _issueWrappedFrom(address(reserveMigrator), amount_);
        sFromMigratorBalance += amount_;
        _;
    }

    modifier givenInactive() {
        vm.prank(guardian);
        reserveMigrator.deactivate();
        _;
    }

    // Scaffolding for the tests

    function _validateStartBalances() internal {
        assertEq(from.balanceOf(address(TRSRY)), fromBalance);
        assertEq(sFrom.balanceOf(address(TRSRY)), sFromBalance);
        assertEq(from.balanceOf(address(reserveMigrator)), fromMigratorBalance);
        assertEq(sFrom.balanceOf(address(reserveMigrator)), sFromMigratorBalance);
        assertEq(to.balanceOf(address(TRSRY)), toBalance);
        assertEq(sTo.balanceOf(address(TRSRY)), sToBalance);
        assertEq(to.balanceOf(address(reserveMigrator)), toMigratorBalance);
        assertEq(sTo.balanceOf(address(reserveMigrator)), sToMigratorBalance);
    }

    function _validateEndBalances() internal {
        uint256 sToIncrease = sFromBalance +
            sFromMigratorBalance +
            sTo.previewDeposit(fromBalance + fromMigratorBalance);

        assertEq(from.balanceOf(address(TRSRY)), 0);
        assertEq(sFrom.balanceOf(address(TRSRY)), 0);
        assertEq(from.balanceOf(address(reserveMigrator)), 0);
        assertEq(sFrom.balanceOf(address(reserveMigrator)), 0);
        assertEq(to.balanceOf(address(TRSRY)), 0);
        assertEq(sTo.balanceOf(address(TRSRY)), sToBalance + sToIncrease);
        assertEq(to.balanceOf(address(reserveMigrator)), 0);
        assertEq(sTo.balanceOf(address(reserveMigrator)), 0);
    }

    function migrateAndValidate() public {
        _validateStartBalances();

        vm.prank(heart);
        reserveMigrator.migrate();

        _validateEndBalances();
    }

    function migrateAndValidateInactive() public {
        _validateStartBalances();

        vm.prank(heart);
        reserveMigrator.migrate();

        _validateStartBalances();
    }

    // tests
    //
    // migrate
    // [X] when called by an address without the "heart" role
    //    [X] it reverts
    // [X] when called by an address with the "heart" role and when the contract is locally active
    //    [X] when the TRSRY contract has a zero balance of from and sFrom reserves
    //       [X] when the reserve migrator has a zero balance of from and sFrom reserves
    //          [X] it does nothing
    //       [X] when the reserve migrator has a non-zero balance of from reserves
    //          [X] it migrates the from balance of the reserve migrator to the to reserve
    //          [X] it deposits the to reserves into sTo and sends to the TRSRY
    //       [X] when the reserve migrator has a non-zero balance of sFrom reserves
    //          [X] it redeems the sFrom balance of the reserve migrator
    //          [X] it migrates the from balance of the reserve migrator to the to reserve
    //          [X] it deposits the to reserves into sTo and sends to the TRSRY
    //       [X] when the reserve migrator has a non-zero balance of from and sFrom reserves
    //          [X] it redeems the sFrom balance of the reserve migrator
    //          [X] it migrates the combined from balance of the reserve migrator to the to reserve
    //          [ ] it deposits the to reserves into sTo and sends to the TRSRY
    //    [X] when the TRSRY contract has a non-zero balance of from reserves
    //       [X] when the reserve migrator has a zero balance of from and sFrom reserves
    //          [X] it migrates the from balance of the TRSRY to the to reserve
    //          [X] it deposits the to reserves into sTo and sends to the TRSRY
    //       [X] when the reserve migrator has a non-zero balance of from reserves
    //          [X] it migrates the combined from balance of the reserve migrator and the TRSRY to the to reserve
    //          [X] it deposits the to reserves into sTo and sends to the TRSRY
    //       [X] when the reserve migrator has a non-zero balance of sFrom reserves
    //          [X] it redeems the sFrom balance of the reserve migrator
    //          [X] it migrates the combined from balance of the TRSRY and the reserve migrator to the to reserve
    //          [X] it deposits the to reserves into sTo and sends to the TRSRY
    //       [X] when the reserve migrator has a non-zero balance of from and sFrom reserves
    //          [X] it redeems the sFrom balance of the reserve migrator
    //          [X] it migrates the combined from balance of the TRSRY and the reserve migrator to the to reserve
    //          [X] it deposits the to reserves into sTo and sends to the TRSRY
    //    [X] when the TRSRY contract has a non-zero balance of sFrom reserves
    //       [X] when the reserve migrator has a zero balance of from and sFrom reserves
    //          [X] it redeems the sFrom balance of the TRSRY
    //          [X] it migrates the from balance of the TRSRY to the to reserve
    //          [X] it deposits the to reserves into sTo and sends to the TRSRY
    //       [X] when the reserve migrator has a non-zero balance of from reserves
    //          [X] it redeems the sFrom balance of the TRSRY
    //          [X] it migrates the combined from balance of the reserve migrator and the TRSRY to the to reserve
    //          [X] it deposits the to reserves into sTo and sends to the TRSRY
    //       [X] when the reserve migrator has a non-zero balance of sFrom reserves
    //          [X] it redeems the combined sFrom balance of the TRSRY and the reserve migrator
    //          [X] it migrates the combined from balance of the TRSRY and the reserve migrator to the to reserve
    //          [X] it deposits the to reserves into sTo and sends to the TRSRY
    //       [X] when the reserve migrator has a non-zero balance of from and sFrom reserves
    //          [X] it redeems the combined sFrom balance of the TRSRY and the reserve migrator
    //          [X] it migrates the combined from balance of the TRSRY and the reserve migrator to the to reserve
    //          [X] it deposits the to reserves into sTo and sends to the TRSRY
    //    [X] when the TRSRY contract has a non-zero balance of from and sFrom reserves
    //       [X] when the reserve migrator has a zero balance of from and sFrom reserves
    //          [X] it redeems the sFrom balance of the TRSRY
    //          [X] it migrates the from balance of the TRSRY to the to reserve
    //          [X] it deposits the to reserves into sTo and sends to the TRSRY
    //       [X] when the reserve migrator has a non-zero balance of from reserves
    //          [X] it redeems the sFrom balance of the TRSRY
    //          [X] it migrates the combined from balance of the reserve migrator and the TRSRY to the to reserve
    //          [X] it deposits the to reserves into sTo and sends to the TRSRY
    //       [X] when the reserve migrator has a non-zero balance of sFrom reserves
    //          [X] it redeems the combined sFrom balance of the TRSRY and the reserve migrator
    //          [X] it migrates the combined from balance of the TRSRY and the reserve migrator to the to reserve
    //          [X] it deposits the to reserves into sTo and sends to the TRSRY
    //       [X] when the reserve migrator has a non-zero balance of from and sFrom reserves
    //          [X] it redeems the combined sFrom balance of the TRSRY and the reserve migrator
    //          [X] it migrates the combined from balance of the TRSRY and the reserve migrator to the to reserve
    //          [X] it deposits the to reserves into sTo and sends to the TRSRY
    // [X] when called by an address with the "heart" role and when the contract is not locally active
    //    [X] it does nothing (in all the cases listed above)

    // migrate
    // when called by an address without the "heart" role
    // it reverts

    function test_migrate_whenCalledByNonHeartRole_itReverts(address caller_) public {
        vm.assume(caller_ != heart);

        // Call migrate, expect revert
        bytes memory err = abi.encodeWithSignature("ROLES_RequireRole(bytes32)", bytes32("heart"));
        vm.expectRevert(err);
        vm.prank(caller_);
        reserveMigrator.migrate();

        // Call migrate as heart, expect success
        vm.prank(heart);
        reserveMigrator.migrate();
    }

    // migrate
    // when called by an address with the "heart" role and when the contract is locally active
    // when the TRSRY contract has a zero balance of from and sFrom reserves
    // when the reserve migrator has a zero balance of from and sFrom reserves
    // it does nothing
    function test_migrate_whenTreasuryZero_whenMigratorZero_itDoesNothing() public {
        migrateAndValidate();
    }

    // migrate
    // when called by an address with the "heart" role and when the contract is locally active
    // when the TRSRY contract has a zero balance of from and sFrom reserves
    // when the reserve migrator has a non-zero balance of from reserves
    // it migrates the from balance of the reserve migrator to the to reserve
    // it deposits the to reserves into sTo and sends to the TRSRY
    function test_migrate_whenTreasuryZero_whenMigratorNonZeroReserves(
        uint256 amount_
    ) public givenAmountValid(amount_) givenMigratorHasFrom(amount_) {
        migrateAndValidate();
    }

    // migrate
    // when called by an address with the "heart" role and when the contract is locally active
    // when the TRSRY contract has a zero balance of from and sFrom reserves
    // when the reserve migrator has a non-zero balance of sFrom reserves
    // it redeems the sFrom balance of the reserve migrator
    // it migrates the from balance of the reserve migrator to the to reserve
    // it deposits the to reserves into sTo and sends to the TRSRY
    function test_migrate_whenTreasuryZero_whenMigratorNonZeroWrappedReserves(
        uint256 amount_
    ) public givenAmountValid(amount_) givenMigratorHasWrappedFrom(amount_) {
        migrateAndValidate();
    }

    // migrate
    // when called by an address with the "heart" role and when the contract is locally active
    // when the TRSRY contract has a zero balance of from and sFrom reserves
    // when the reserve migrator has a non-zero balance of from reserves and sFrom reserves
    // it redeems the sFrom balance of the reserve migrator
    // it migrates the combined from balance of the reserve migrator to the to reserve
    // it deposits the to reserves into sTo and sends to the TRSRY
    function test_migrate_whenTreasuryZero_whenMigratorNonZeroBoth(
        uint256 amount_
    )
        public
        givenAmountValid(amount_)
        givenMigratorHasFrom(amount_)
        givenMigratorHasWrappedFrom(amount_)
    {
        migrateAndValidate();
    }

    // migrate
    // when called by an address with the "heart" role and when the contract is locally active
    // when the TRSRY contract has a non-zero balance of from reserves
    // when the reserve migrator has a zero balance of from and sFrom reserves
    // it migrates the from balance of the TRSRY to the to reserve
    // it deposits the to reserves into sTo and sends to the TRSRY
    function test_migrate_whenTreasuryNonZeroReserves_whenMigratorZero(
        uint256 amount_
    ) public givenAmountValid(amount_) givenTreasuryHasFrom(amount_) {
        migrateAndValidate();
    }

    // migrate
    // when called by an address with the "heart" role and when the contract is locally active
    // when the TRSRY contract has a non-zero balance of from reserves
    // when the reserve migrator has a non-zero balance of from reserves
    // it migrates the combined from balance of the reserve migrator and the TRSRY to the to reserve
    // it deposits the to reserves into sTo and sends to the TRSRY
    function test_migrate_whenTreasuryNonZeroReserves_whenMigratorNonZeroReserves(
        uint256 amount_
    ) public givenAmountValid(amount_) givenTreasuryHasFrom(amount_) givenMigratorHasFrom(amount_) {
        migrateAndValidate();
    }

    // migrate
    // when called by an address with the "heart" role and when the contract is locally active
    // when the TRSRY contract has a non-zero balance of from reserves
    // when the reserve migrator has a non-zero balance of sFrom reserves
    // it redeems the sFrom balance of the reserve migrator
    // it migrates the combined from balance of the TRSRY and the reserve migrator to the to reserve
    // it deposits the to reserves into sTo and sends to the TRSRY
    function test_migrate_whenTreasuryNonZeroReserves_whenMigratorNonZeroWrappedReserves(
        uint256 amount_
    )
        public
        givenAmountValid(amount_)
        givenTreasuryHasFrom(amount_)
        givenMigratorHasWrappedFrom(amount_)
    {
        migrateAndValidate();
    }

    // migrate
    // when called by an address with the "heart" role and when the contract is locally active
    // when the TRSRY contract has a non-zero balance of from reserves
    // when the reserve migrator has a non-zero balance of from and sFrom reserves
    // it redeems the sFrom balance of the reserve migrator
    // it migrates the combined from balance of the TRSRY and the reserve migrator to the to reserve
    // it deposits the to reserves into sTo and sends to the TRSRY
    function test_migrate_whenTreasuryNonZeroReserves_whenMigratorNonZeroBoth(
        uint256 amount_
    )
        public
        givenAmountValid(amount_)
        givenTreasuryHasFrom(amount_)
        givenMigratorHasFrom(amount_)
        givenMigratorHasWrappedFrom(amount_)
    {
        migrateAndValidate();
    }

    // migrate
    // when called by an address with the "heart" role and when the contract is locally active
    // when the TRSRY contract has a non-zero balance of sFrom reserves
    // when the reserve migrator has a zero balance of from and sFrom reserves
    // it redeems the sFrom balance of the TRSRY
    // it migrates the from balance of the TRSRY to the to reserve
    // it deposits the to reserves into sTo and sends to the TRSRY
    function test_migrate_whenTreasuryNonZeroWrappedReserves_whenMigratorZero(
        uint256 amount_
    ) public givenAmountValid(amount_) givenTreasuryHasWrappedFrom(amount_) {
        migrateAndValidate();
    }

    // migrate
    // when called by an address with the "heart" role and when the contract is locally active
    // when the TRSRY contract has a non-zero balance of sFrom reserves
    // when the reserve migrator has a non-zero balance of from reserves
    // it redeems the sFrom balance of the TRSRY
    // it migrates the combined from balance of the reserve migrator and the TRSRY to the to reserve
    // it deposits the to reserves into sTo and sends to the TRSRY
    function test_migrate_whenTreasuryNonZeroWrappedReserves_whenMigratorNonZeroReserves(
        uint256 amount_
    )
        public
        givenAmountValid(amount_)
        givenTreasuryHasWrappedFrom(amount_)
        givenMigratorHasFrom(amount_)
    {
        migrateAndValidate();
    }

    // migrate
    // when called by an address with the "heart" role and when the contract is locally active
    // when the TRSRY contract has a non-zero balance of sFrom reserves
    // when the reserve migrator has a non-zero balance of sFrom reserves
    // it redeems the combined sFrom balance of the TRSRY and the reserve migrator
    // it migrates the combined from balance of the TRSRY and the reserve migrator to the to reserve
    // it deposits the to reserves into sTo and sends to the TRSRY
    function test_migrate_whenTreasuryNonZeroWrappedReserves_whenMigratorNonZeroWrappedReserves(
        uint256 amount_
    )
        public
        givenAmountValid(amount_)
        givenTreasuryHasWrappedFrom(amount_)
        givenMigratorHasWrappedFrom(amount_)
    {
        migrateAndValidate();
    }

    // migrate
    // when called by an address with the "heart" role and when the contract is locally active
    // when the TRSRY contract has a non-zero balance of sFrom reserves
    // when the reserve migrator has a non-zero balance of from and sFrom reserves
    // it redeems the combined sFrom balance of the TRSRY and the reserve migrator
    // it migrates the combined from balance of the TRSRY and the reserve migrator to the to reserve
    // it deposits the to reserves into sTo and sends to the TRSRY
    function test_migrate_whenTreasuryNonZeroWrappedReserves_whenMigratorNonZeroBoth(
        uint256 amount_
    )
        public
        givenAmountValid(amount_)
        givenTreasuryHasWrappedFrom(amount_)
        givenMigratorHasFrom(amount_)
        givenMigratorHasWrappedFrom(amount_)
    {
        migrateAndValidate();
    }

    // migrate
    // when called by an address with the "heart" role and when the contract is locally active
    // when the TRSRY contract has a non-zero balance of from and sFrom reserves
    // when the reserve migrator has a zero balance of from and sFrom reserves
    // it redeems the sFrom balance of the TRSRY
    // it migrates the from balance of the TRSRY to the to reserve
    // it deposits the to reserves into sTo and sends to the TRSRY
    function test_migrate_whenTreasuryNonZeroBoth_whenMigratorZero(
        uint256 amount_
    )
        public
        givenAmountValid(amount_)
        givenTreasuryHasFrom(amount_)
        givenTreasuryHasWrappedFrom(amount_)
    {
        migrateAndValidate();
    }

    // migrate
    // when called by an address with the "heart" role and when the contract is locally active
    // when the TRSRY contract has a non-zero balance of from and sFrom reserves
    // when the reserve migrator has a non-zero balance of from reserves
    // it redeems the sFrom balance of the TRSRY
    // it migrates the combined from balance of the reserve migrator and the TRSRY to the to reserve
    // it deposits the to reserves into sTo and sends to the TRSRY
    function test_migrate_whenTreasuryNonZeroBoth_whenMigratorNonZeroReserves(
        uint256 amount_
    )
        public
        givenAmountValid(amount_)
        givenTreasuryHasFrom(amount_)
        givenTreasuryHasWrappedFrom(amount_)
        givenMigratorHasFrom(amount_)
    {
        migrateAndValidate();
    }

    // migrate
    // when called by an address with the "heart" role and when the contract is locally active
    // when the TRSRY contract has a non-zero balance of from and sFrom reserves
    // when the reserve migrator has a non-zero balance of sFrom reserves
    // it redeems the combined sFrom balance of the TRSRY and the reserve migrator
    // it migrates the combined from balance of the TRSRY and the reserve migrator to the to reserve
    // it deposits the to reserves into sTo and sends to the TRSRY
    function test_migrate_whenTreasuryNonZeroBoth_whenMigratorNonZeroWrappedReserves(
        uint256 amount_
    )
        public
        givenAmountValid(amount_)
        givenTreasuryHasFrom(amount_)
        givenTreasuryHasWrappedFrom(amount_)
        givenMigratorHasWrappedFrom(amount_)
    {
        migrateAndValidate();
    }

    // migrate
    // when called by an address with the "heart" role and when the contract is locally active
    // when the TRSRY contract has a non-zero balance of from and sFrom reserves
    // when the reserve migrator has a non-zero balance of from and sFrom reserves
    // it redeems the combined sFrom balance of the TRSRY and the reserve migrator
    // it migrates the combined from balance of the TRSRY and the reserve migrator to the to reserve
    // it deposits the to reserves into sTo and sends to the TRSRY
    function test_migrate_whenTreasuryNonZeroBoth_whenMigratorNonZeroBoth(
        uint256 amount_
    )
        public
        givenAmountValid(amount_)
        givenTreasuryHasFrom(amount_)
        givenTreasuryHasWrappedFrom(amount_)
        givenMigratorHasFrom(amount_)
        givenMigratorHasWrappedFrom(amount_)
    {
        migrateAndValidate();
    }

    // migrate
    // when called by an address with the "heart" role and when the contract is NOT locally active
    // when the TRSRY contract has a zero balance of from and sFrom reserves
    // when the reserve migrator has a zero balance of from and sFrom reserves
    // it does nothing
    function test_migrate_whenNotLocallyActive_whenTreasuryZero_whenMigratorZero()
        public
        givenInactive
    {
        migrateAndValidateInactive();
    }

    // migrate
    // when called by an address with the "heart" role and when the contract is NOT locally active
    // when the TRSRY contract has a zero balance of from and sFrom reserves
    // when the reserve migrator has a non-zero balance of from reserves
    // it does nothing
    function test_migrate_whenNotLocallyActive_whenTreasuryZero_whenMigratorNonZeroReserves(
        uint256 amount_
    ) public givenInactive givenAmountValid(amount_) givenMigratorHasFrom(amount_) {
        migrateAndValidateInactive();
    }

    // migrate
    // when called by an address with the "heart" role and when the contract is NOT locally active
    // when the TRSRY contract has a zero balance of from and sFrom reserves
    // when the reserve migrator has a non-zero balance of sFrom reserves
    // it does nothing
    function test_migrate_whenNotLocallyActive_whenTreasuryZero_whenMigratorNonZeroWrappedReserves(
        uint256 amount_
    ) public givenInactive givenAmountValid(amount_) givenMigratorHasWrappedFrom(amount_) {
        migrateAndValidateInactive();
    }

    // migrate
    // when called by an address with the "heart" role and when the contract is NOT locally active
    // when the TRSRY contract has a zero balance of from and sFrom reserves
    // when the reserve migrator has a non-zero balance of from and sFrom reserves
    // it does nothing
    function test_migrate_whenNotLocallyActive_whenTreasuryZero_whenMigratorNonZeroBoth(
        uint256 amount_
    )
        public
        givenInactive
        givenAmountValid(amount_)
        givenMigratorHasFrom(amount_)
        givenMigratorHasWrappedFrom(amount_)
    {
        migrateAndValidateInactive();
    }

    // migrate
    // when called by an address with the "heart" role and when the contract is NOT locally active
    // when the TRSRY contract has a non-zero balance of from reserves
    // when the reserve migrator has a zero balance of from and sFrom reserves
    // it does nothing
    function test_migrate_whenNotLocallyActive_whenTreasuryNonZeroReserves_whenMigratorZero(
        uint256 amount_
    ) public givenInactive givenAmountValid(amount_) givenTreasuryHasFrom(amount_) {
        migrateAndValidateInactive();
    }

    // migrate
    // when called by an address with the "heart" role and when the contract is NOT locally active
    // when the TRSRY contract has a non-zero balance of from reserves
    // when the reserve migrator has a non-zero balance of from reserves
    // it does nothing
    function test_migrate_whenNotLocallyActive_whenTreasuryNonZeroReserves_whenMigratorNonZeroReserves(
        uint256 amount_
    )
        public
        givenInactive
        givenAmountValid(amount_)
        givenTreasuryHasFrom(amount_)
        givenMigratorHasFrom(amount_)
    {
        migrateAndValidateInactive();
    }

    // migrate
    // when called by an address with the "heart" role and when the contract is NOT locally active
    // when the TRSRY contract has a non-zero balance of from reserves
    // when the reserve migrator has a non-zero balance of sFrom reserves
    // it does nothing
    function test_migrate_whenNotLocallyActive_whenTreasuryNonZeroReserves_whenMigratorNonZeroWrappedReserves(
        uint256 amount_
    )
        public
        givenInactive
        givenAmountValid(amount_)
        givenTreasuryHasFrom(amount_)
        givenMigratorHasWrappedFrom(amount_)
    {
        migrateAndValidateInactive();
    }

    // migrate
    // when called by an address with the "heart" role and when the contract is NOT locally active
    // when the TRSRY contract has a non-zero balance of from reserves
    // when the reserve migrator has a non-zero balance of from and sFrom reserves
    // it does nothing
    function test_migrate_whenNotLocallyActive_whenTreasuryNonZeroReserves_whenMigratorNonZeroBoth(
        uint256 amount_
    )
        public
        givenInactive
        givenAmountValid(amount_)
        givenTreasuryHasFrom(amount_)
        givenMigratorHasFrom(amount_)
        givenMigratorHasWrappedFrom(amount_)
    {
        migrateAndValidateInactive();
    }

    // migrate
    // when called by an address with the "heart" role and when the contract is NOT locally active
    // when the TRSRY contract has a non-zero balance of sFrom reserves
    // when the reserve migrator has a zero balance of from and sFrom reserves
    // it does nothing
    function test_migrate_whenNotLocallyActive_whenTreasuryNonZeroWrappedReserves_whenMigratorZero(
        uint256 amount_
    ) public givenInactive givenAmountValid(amount_) givenTreasuryHasWrappedFrom(amount_) {
        migrateAndValidateInactive();
    }

    // migrate
    // when called by an address with the "heart" role and when the contract is NOT locally active
    // when the TRSRY contract has a non-zero balance of sFrom reserves
    // when the reserve migrator has a non-zero balance of from reserves
    // it does nothing
    function test_migrate_whenNotLocallyActive_whenTreasuryNonZeroWrappedReserves_whenMigratorNonZeroReserves(
        uint256 amount_
    )
        public
        givenInactive
        givenAmountValid(amount_)
        givenTreasuryHasWrappedFrom(amount_)
        givenMigratorHasFrom(amount_)
    {
        migrateAndValidateInactive();
    }

    // migrate
    // when called by an address with the "heart" role and when the contract is NOT locally active
    // when the TRSRY contract has a non-zero balance of sFrom reserves
    // when the reserve migrator has a non-zero balance of sFrom reserves
    // it does nothing
    function test_migrate_whenNotLocallyActive_whenTreasuryNonZeroWrappedReserves_whenMigratorNonZeroWrappedReserves(
        uint256 amount_
    )
        public
        givenInactive
        givenAmountValid(amount_)
        givenTreasuryHasWrappedFrom(amount_)
        givenMigratorHasWrappedFrom(amount_)
    {
        migrateAndValidateInactive();
    }

    // migrate
    // when called by an address with the "heart" role and when the contract is NOT locally active
    // when the TRSRY contract has a non-zero balance of sFrom reserves
    // when the reserve migrator has a non-zero balance of from and sFrom reserves
    // it does nothing
    function test_migrate_whenNotLocallyActive_whenTreasuryNonZeroWrappedReserves_whenMigratorNonZeroBoth(
        uint256 amount_
    )
        public
        givenInactive
        givenAmountValid(amount_)
        givenTreasuryHasWrappedFrom(amount_)
        givenMigratorHasFrom(amount_)
        givenMigratorHasWrappedFrom(amount_)
    {
        migrateAndValidateInactive();
    }

    // migrate
    // when called by an address with the "heart" role and when the contract is NOT locally active
    // when the TRSRY contract has a non-zero balance of from and sFrom reserves
    // when the reserve migrator has a zero balance of from and sFrom reserves
    // it does nothing
    function test_migrate_whenNotLocallyActive_whenTreasuryNonZeroBoth_whenMigratorZero(
        uint256 amount_
    )
        public
        givenInactive
        givenAmountValid(amount_)
        givenTreasuryHasFrom(amount_)
        givenTreasuryHasWrappedFrom(amount_)
    {
        migrateAndValidateInactive();
    }

    // migrate
    // when called by an address with the "heart" role and when the contract is NOT locally active
    // when the TRSRY contract has a non-zero balance of from and sFrom reserves
    // when the reserve migrator has a non-zero balance of from reserves
    // it does nothing
    function test_migrate_whenNotLocallyActive_whenTreasuryNonZeroBoth_whenMigratorNonZeroReserves(
        uint256 amount_
    )
        public
        givenInactive
        givenAmountValid(amount_)
        givenTreasuryHasFrom(amount_)
        givenTreasuryHasWrappedFrom(amount_)
        givenMigratorHasFrom(amount_)
    {
        migrateAndValidateInactive();
    }

    // migrate
    // when called by an address with the "heart" role and when the contract is NOT locally active
    // when the TRSRY contract has a non-zero balance of from and sFrom reserves
    // when the reserve migrator has a non-zero balance of sFrom reserves
    // it does nothing
    function test_migrate_whenNotLocallyActive_whenTreasuryNonZeroBoth_whenMigratorNonZeroWrappedReserves(
        uint256 amount_
    )
        public
        givenInactive
        givenAmountValid(amount_)
        givenTreasuryHasFrom(amount_)
        givenTreasuryHasWrappedFrom(amount_)
        givenMigratorHasWrappedFrom(amount_)
    {
        migrateAndValidateInactive();
    }

    // migrate
    // when called by an address with the "heart" role and when the contract is NOT locally active
    // when the TRSRY contract has a non-zero balance of from and sFrom reserves
    // when the reserve migrator has a non-zero balance of from and sFrom reserves
    // it does nothing
    function test_migrate_whenNotLocallyActive_whenTreasuryNonZeroBoth_whenMigratorNonZeroBoth(
        uint256 amount_
    )
        public
        givenInactive
        givenAmountValid(amount_)
        givenTreasuryHasFrom(amount_)
        givenTreasuryHasWrappedFrom(amount_)
        givenMigratorHasFrom(amount_)
        givenMigratorHasWrappedFrom(amount_)
    {
        migrateAndValidateInactive();
    }
}
