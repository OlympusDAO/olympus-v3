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
import {IMonoCooler} from "src/policies/interfaces/cooler/IMonoCooler.sol";
import {IDLGTEv1} from "src/modules/DLGTE/IDLGTE.v1.sol";
import {ICoolerV2Migrator} from "src/policies/interfaces/cooler/ICoolerV2Migrator.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

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

    address internal USER;
    address internal USER2;
    uint256 internal USER_PK;
    uint256 internal USER2_PK;

    IMonoCooler.Authorization internal authorization;
    IMonoCooler.Signature internal signature;
    IDLGTEv1.DelegationRequest[] internal delegationRequests;

    bytes32 private constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");
    bytes32 private constant AUTHORIZATION_TYPEHASH =
        keccak256(
            "Authorization(address account,address authorized,uint96 authorizationDeadline,uint256 nonce,uint256 signatureDeadline)"
        );

    function buildDomainSeparator() internal view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, block.chainid, address(cooler)));
    }

    mapping(address => address) internal clearinghouseToCooler;

    function setUp() public virtual override {
        // MonoCooler setup
        super.setUp();

        (USER, USER_PK) = makeAddrAndKey("user");
        (USER2, USER2_PK) = makeAddrAndKey("user2");

        // Tokens
        dai = new MockERC20("DAI", "DAI", 18);
        sDai = new MockERC4626(dai, "sDAI", "sDAI");

        // Set up a mock DAI-USDS migrator
        daiMigrator = new MockDaiUsds(dai, usds);

        // Set up a mock flash loan lender
        flashLender = new MockFlashloanLender(0, address(dai));
        dai.mint(address(flashLender), 1000000e18);

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

    function _getClearinghouse(bool isUsds_) internal view returns (Clearinghouse clearinghouse) {
        if (isUsds_) {
            return Clearinghouse(address(clearinghouseUsds));
        }

        return Clearinghouse(address(clearinghouseDai));
    }

    function _createCooler(
        address wallet_,
        bool isUsds_
    ) internal returns (address clearinghouse_, address cooler_) {
        clearinghouse_ = address(_getClearinghouse(isUsds_));

        // Create Cooler if needed
        vm.startPrank(wallet_);
        cooler_ = Clearinghouse(clearinghouse_).factory().generateCooler(
            gohm,
            isUsds_ ? usds : dai
        );
        vm.stopPrank();

        // Store the relationship
        clearinghouseToCooler[clearinghouse_] = cooler_;

        return (clearinghouse_, cooler_);
    }

    function _getCoolerArrays(
        bool includeUsds_,
        bool includeDai_
    ) internal view returns (address[] memory coolers, address[] memory clearinghouses) {
        uint256 length;
        if (includeUsds_) {
            length++;
        }
        if (includeDai_) {
            length++;
        }

        coolers = new address[](length);
        clearinghouses = new address[](length);
        uint256 index;

        if (includeUsds_) {
            coolers[index] = clearinghouseToCooler[address(clearinghouseUsds)];
            clearinghouses[index] = address(clearinghouseUsds);
            index++;
        }
        if (includeDai_) {
            coolers[index] = clearinghouseToCooler[address(clearinghouseDai)];
            clearinghouses[index] = address(clearinghouseDai);
            index++;
        }

        return (coolers, clearinghouses);
    }

    modifier givenWalletHasLoan(
        address wallet_,
        bool isUsds_,
        uint256 collateralAmount_
    ) {
        (address clearinghouse_, address cooler_) = _createCooler(wallet_, isUsds_);

        // Approve spending of collateral
        vm.prank(wallet_);
        gohm.approve(clearinghouse_, collateralAmount_);

        // Determine the loan amount
        (uint256 principal, uint256 interest) = Clearinghouse(clearinghouse_).getLoanForCollateral(
            collateralAmount_
        );

        // Create loan
        vm.startPrank(wallet_);
        Clearinghouse(clearinghouse_).lendToCooler(Cooler(cooler_), principal);
        vm.stopPrank();
        _;
    }

    modifier givenWalletHasRepaidLoan(
        address wallet_,
        bool isUsds_,
        uint256 loanId_
    ) {
        Cooler walletCooler = _getCooler(isUsds_);
        Cooler.Loan memory loan = walletCooler.getLoan(loanId_);
        uint256 payableAmount = loan.principal + loan.interestDue;

        // Mint debt token to the wallet and approve spending
        if (isUsds_) {
            usds.mint(wallet_, payableAmount);
            vm.prank(wallet_);
            usds.approve(address(walletCooler), payableAmount);
        } else {
            dai.mint(wallet_, payableAmount);
            vm.prank(wallet_);
            dai.approve(address(walletCooler), payableAmount);
        }

        // Repay the loan
        vm.prank(wallet_);
        walletCooler.repayLoan(loanId_, payableAmount);
        _;
    }

    modifier givenWalletHasApprovedMigratorSpendingCollateral(address wallet_, uint256 amount_) {
        vm.prank(wallet_);
        gohm.approve(address(migrator), amount_);
        _;
    }

    function _getCooler(bool isUsds_) internal view returns (Cooler cooler_) {
        Clearinghouse clearinghouse = _getClearinghouse(isUsds_);
        cooler_ = Cooler(clearinghouseToCooler[address(clearinghouse)]);

        return cooler_;
    }

    function _getLoan(
        bool isUsds_,
        uint256 loanId_
    ) internal view returns (Cooler.Loan memory loan) {
        Cooler existingCooler = _getCooler(isUsds_);
        loan = existingCooler.getLoan(loanId_);

        return loan;
    }

    modifier givenFlashFee(uint16 flashFee_) {
        flashLender.setFeePercent(flashFee_);
        _;
    }

    function signedAuth(
        address account,
        uint256 accountPk,
        address authorized,
        uint96 authorizationDeadline,
        uint256 signatureDeadline
    )
        internal
        view
        returns (IMonoCooler.Authorization memory auth, IMonoCooler.Signature memory sig)
    {
        bytes32 domainSeparator = buildDomainSeparator();
        auth = IMonoCooler.Authorization({
            account: account,
            authorized: authorized,
            authorizationDeadline: authorizationDeadline,
            nonce: cooler.authorizationNonces(account),
            signatureDeadline: signatureDeadline
        });
        bytes32 structHash = keccak256(abi.encode(AUTHORIZATION_TYPEHASH, auth));
        bytes32 typedDataHash = ECDSA.toTypedDataHash(domainSeparator, structHash);
        (sig.v, sig.r, sig.s) = vm.sign(accountPk, typedDataHash);
    }

    modifier givenAuthorization() {
        vm.prank(USER);
        cooler.setAuthorization(address(migrator), uint96(block.timestamp + 1));
        _;
    }

    modifier givenAuthorizationCleared() {
        vm.prank(USER);
        cooler.setAuthorization(address(migrator), 0);
        _;
    }

    modifier givenAuthorizationSignatureSet() {
        (authorization, signature) = signedAuth(
            USER,
            USER_PK,
            address(migrator),
            uint96(block.timestamp + 1),
            uint96(block.timestamp + 1)
        );
        _;
    }

    modifier givenAuthorizationSignatureCleared() {
        authorization = IMonoCooler.Authorization({
            account: address(0),
            authorized: address(0),
            authorizationDeadline: 0,
            nonce: 0,
            signatureDeadline: 0
        });
        signature = IMonoCooler.Signature({v: 0, r: bytes32(0), s: bytes32(0)});
        _;
    }

    // ========= ASSERTIONS ========= //

    function _expectRevert_disabled() internal {
        vm.expectRevert(abi.encodeWithSelector(PolicyEnabler.NotEnabled.selector));
    }

    function _assertTokenBalances(
        address wallet_,
        uint256 collateralTokenBalance_,
        uint256 usdsBalance_,
        uint256 daiBalance_
    ) internal view {
        assertEq(
            gohm.balanceOf(wallet_),
            collateralTokenBalance_,
            string.concat(Strings.toHexString(wallet_), ": wallet collateral token balance")
        );
        assertEq(
            usds.balanceOf(wallet_),
            usdsBalance_,
            string.concat(Strings.toHexString(wallet_), ": wallet USDS balance")
        );
        assertEq(
            dai.balanceOf(wallet_),
            daiBalance_,
            string.concat(Strings.toHexString(wallet_), ": wallet DAI balance")
        );
    }

    function _assertCoolerV2Loan(
        address wallet_,
        uint256 collateralBalance_,
        uint256 debtBalance_
    ) internal view {
        // MonoCooler should have a collateral token balance and debt token balance
        IMonoCooler.AccountPosition memory position = cooler.accountPosition(wallet_);
        assertEq(position.collateral, collateralBalance_, "account position collateral");
        assertEq(position.currentDebt, debtBalance_, "account position debt");
    }

    function _assertAuthorization(uint256 nonce_, uint96 deadline_) internal view {
        assertEq(cooler.authorizationNonces(USER), nonce_, "authorization nonce");
        assertEq(
            cooler.authorizations(USER, address(migrator)),
            deadline_,
            "authorization deadline"
        );
    }

    function _assertCoolerV1Loans(bool isUsds_, uint256 numLoans_) internal view {
        Cooler coolerV1 = _getCooler(isUsds_);

        for (uint256 i; i < numLoans_; i++) {
            Cooler.Loan memory loan = coolerV1.getLoan(i);
            assertEq(loan.principal, 0, "loan principal");
            assertEq(loan.interestDue, 0, "loan interest due");
        }
    }

    // ========= TESTS ========= //

    // previewConsolidate
    // given the contract is disabled
    //  [X] it reverts
    // given there are no loans
    //  [X] it returns 0 collateral
    //  [X] it returns 0 borrowed
    // given there is a repaid loan
    //  [X] it ignores the repaid loan
    // given the flash fee is non-zero
    //  [X] it returns the total collateral returned
    //  [X] the total borrowed is the principal + interest + flash fee
    // [X] it returns the total collateral returned
    // [X] the total borrowed is the principal + interest

    function test_previewConsolidate_givenDisabled_reverts()
        public
        givenWalletHasCollateralToken(USER, 1e18)
        givenWalletHasLoan(USER, true, 1e18)
        givenDisabled
    {
        // Prepare input data
        (address[] memory coolers, ) = _getCoolerArrays(true, false);

        // Expect revert
        _expectRevert_disabled();

        // Function
        migrator.previewConsolidate(coolers);
    }

    function test_previewConsolidate_givenNoLoans() public {
        // Create a Cooler, but no loan
        _createCooler(USER, true);

        // Prepare input data
        (address[] memory coolers, ) = _getCoolerArrays(true, false);

        // Function
        (uint256 collateralAmount, uint256 borrowedAmount) = migrator.previewConsolidate(coolers);

        // Assertions
        assertEq(collateralAmount, 0, "collateralAmount");
        assertEq(borrowedAmount, 0, "borrowedAmount");
    }

    function test_previewConsolidate_givenRepaidLoan()
        public
        givenWalletHasCollateralToken(USER, 2e18)
        givenWalletHasLoan(USER, true, 1e18)
        givenWalletHasLoan(USER, true, 1e18)
        givenWalletHasRepaidLoan(USER, true, 0)
    {
        // Prepare input data
        (address[] memory coolers, ) = _getCoolerArrays(true, false);

        Cooler.Loan memory loanOne = _getLoan(true, 1);
        uint256 loanOnePayable = loanOne.principal + loanOne.interestDue;

        // Function
        (uint256 collateralAmount, uint256 borrowedAmount) = migrator.previewConsolidate(coolers);

        // Assertions
        assertEq(collateralAmount, 1e18, "collateralAmount");
        assertEq(borrowedAmount, loanOnePayable, "borrowedAmount");
    }

    function test_previewConsolidate_givenFlashFee()
        public
        givenWalletHasCollateralToken(USER, 3e18)
        givenWalletHasLoan(USER, true, 1e18)
        givenWalletHasLoan(USER, true, 2e18)
        givenFlashFee(1e2)
    {
        // Prepare input data
        (address[] memory coolers, ) = _getCoolerArrays(true, false);

        Cooler.Loan memory loanZero = _getLoan(true, 0);
        uint256 loanZeroPayable = loanZero.principal + loanZero.interestDue;

        Cooler.Loan memory loanOne = _getLoan(true, 1);
        uint256 loanOnePayable = loanOne.principal + loanOne.interestDue;

        uint256 flashFee = ((loanZeroPayable + loanOnePayable) * 1e2) / 100e2;

        // Function
        (uint256 collateralAmount, uint256 borrowedAmount) = migrator.previewConsolidate(coolers);

        // Assertions
        assertEq(collateralAmount, 3e18, "collateralAmount");
        assertEq(borrowedAmount, loanZeroPayable + loanOnePayable + flashFee, "borrowedAmount");
    }

    function test_previewConsolidate()
        public
        givenWalletHasCollateralToken(USER, 3e18)
        givenWalletHasLoan(USER, true, 1e18)
        givenWalletHasLoan(USER, true, 2e18)
    {
        // Prepare input data
        (address[] memory coolers, ) = _getCoolerArrays(true, false);

        Cooler.Loan memory loanZero = _getLoan(true, 0);
        uint256 loanZeroPayable = loanZero.principal + loanZero.interestDue;

        Cooler.Loan memory loanOne = _getLoan(true, 1);
        uint256 loanOnePayable = loanOne.principal + loanOne.interestDue;

        // Function
        (uint256 collateralAmount, uint256 borrowedAmount) = migrator.previewConsolidate(coolers);

        // Assertions
        assertEq(collateralAmount, 3e18, "collateralAmount");
        assertEq(borrowedAmount, loanZeroPayable + loanOnePayable, "borrowedAmount");
    }

    // consolidate
    // given the contract is disabled
    //  [X] it reverts
    // given the number of clearinghouses and coolers are not the same
    //  [X] it reverts
    // given any clearinghouse is not owned by the Olympus protocol
    //  [X] it reverts
    // given any cooler is not created by the clearinghouse's CoolerFactory
    //  [X] it reverts
    // given any cooler is not owned by the caller
    //  [X] it reverts
    // given a cooler is a duplicate
    //  [X] it reverts
    // given the Cooler debt token is not DAI or USDS
    //  [X] it reverts
    // given the caller has not approved the CoolerV2Migrator to spend the collateral
    //  [X] it reverts
    // given MonoCooler authorization has been provided
    //  [X] it does not set the authorization signature
    //  [X] it deposits the collateral into MonoCooler
    //  [X] it borrows the principal + interest from MonoCooler
    //  [X] the Cooler V1 loans are repaid
    //  [X] the migrator does not hold any tokens
    // when a MonoCooler authorization signature is not provided
    //  [X] it reverts
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

    function test_consolidate_givenDisabled_reverts()
        public
        givenWalletHasCollateralToken(USER, 1e18)
        givenWalletHasLoan(USER, true, 1e18)
        givenWalletHasApprovedMigratorSpendingCollateral(USER, 1e18)
        givenDisabled
    {
        // Prepare input data
        (address[] memory coolers, address[] memory clearinghouses) = _getCoolerArrays(true, false);

        // Expect revert
        _expectRevert_disabled();

        // Call function
        vm.prank(USER);
        migrator.consolidate(
            coolers,
            clearinghouses,
            USER,
            authorization,
            signature,
            delegationRequests
        );
    }

    function test_consolidate_givenClearinghouseCountGreater_reverts()
        public
        givenWalletHasCollateralToken(USER, 1e18)
        givenWalletHasLoan(USER, true, 1e18)
    {
        // Prepare input data
        (address[] memory coolers, address[] memory clearinghouses) = _getCoolerArrays(true, false);

        address[] memory clearinghousesWithExtra = new address[](2);
        clearinghousesWithExtra[0] = clearinghouses[0];
        clearinghousesWithExtra[1] = address(clearinghouseDai);

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(ICoolerV2Migrator.Params_InvalidArrays.selector));

        // Call function
        vm.prank(USER);
        migrator.consolidate(
            coolers,
            clearinghousesWithExtra,
            USER,
            authorization,
            signature,
            delegationRequests
        );
    }

    function test_consolidate_givenClearinghouseCountLess_reverts()
        public
        givenWalletHasCollateralToken(USER, 1e18)
        givenWalletHasLoan(USER, true, 1e18)
    {
        // Create a DAI cooler, but no loan
        _createCooler(USER, false);

        // Prepare input data
        (address[] memory coolers, address[] memory clearinghouses) = _getCoolerArrays(true, true);

        address[] memory clearinghousesWithLess = new address[](1);
        clearinghousesWithLess[0] = clearinghouses[0];

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(ICoolerV2Migrator.Params_InvalidArrays.selector));

        // Call function
        vm.prank(USER);
        migrator.consolidate(
            coolers,
            clearinghousesWithLess,
            USER,
            authorization,
            signature,
            delegationRequests
        );
    }

    function test_consolidate_givenClearinghouseCountZero_reverts()
        public
        givenWalletHasCollateralToken(USER, 1e18)
        givenWalletHasLoan(USER, true, 1e18)
    {
        // Prepare input data
        (address[] memory coolers, ) = _getCoolerArrays(true, false);

        address[] memory clearinghousesWithLess = new address[](0);

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(ICoolerV2Migrator.Params_InvalidArrays.selector));

        // Call function
        vm.prank(USER);
        migrator.consolidate(
            coolers,
            clearinghousesWithLess,
            USER,
            authorization,
            signature,
            delegationRequests
        );
    }

    function test_consolidate_givenClearinghouseNotOwned_reverts()
        public
        givenWalletHasCollateralToken(USER, 1e18)
        givenWalletHasLoan(USER, true, 1e18)
    {
        // Create a new Clearinghouse, not owned by the Olympus protocol
        Clearinghouse newClearinghouse = new Clearinghouse(
            address(ohm),
            address(gohm),
            address(staking),
            address(susds),
            address(coolerFactory),
            address(kernel)
        );
        vm.startPrank(USER);
        address newCooler = Clearinghouse(newClearinghouse).factory().generateCooler(gohm, usds);
        vm.stopPrank();

        // Prepare input data
        (address[] memory coolers, address[] memory clearinghouses) = _getCoolerArrays(true, false);

        address[] memory coolersWithNew = new address[](2);
        coolersWithNew[0] = coolers[0];
        coolersWithNew[1] = newCooler;

        address[] memory clearinghousesWithNew = new address[](2);
        clearinghousesWithNew[0] = clearinghouses[0];
        clearinghousesWithNew[1] = address(newClearinghouse);

        // Expect revert
        vm.expectRevert(
            abi.encodeWithSelector(ICoolerV2Migrator.Params_InvalidClearinghouse.selector)
        );

        // Call function
        vm.prank(USER);
        migrator.consolidate(
            coolersWithNew,
            clearinghousesWithNew,
            USER,
            authorization,
            signature,
            delegationRequests
        );
    }

    function test_consolidate_givenCoolerNotOwned_reverts()
        public
        givenWalletHasCollateralToken(USER, 1e18)
        givenWalletHasLoan(USER, true, 1e18)
    {
        // Create a new Cooler from a different CoolerFactory
        CoolerFactory newCoolerFactory = new CoolerFactory();
        vm.startPrank(USER);
        address newCooler = CoolerFactory(newCoolerFactory).generateCooler(gohm, usds);
        vm.stopPrank();

        // Prepare input data
        (address[] memory coolers, address[] memory clearinghouses) = _getCoolerArrays(true, false);

        address[] memory coolersWithNew = new address[](2);
        coolersWithNew[0] = coolers[0];
        coolersWithNew[1] = newCooler;

        address[] memory clearinghousesWithNew = new address[](2);
        clearinghousesWithNew[0] = clearinghouses[0];
        clearinghousesWithNew[1] = address(clearinghouseUsds);

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(ICoolerV2Migrator.Params_InvalidCooler.selector));

        // Call function
        vm.prank(USER);
        migrator.consolidate(
            coolersWithNew,
            clearinghousesWithNew,
            USER,
            authorization,
            signature,
            delegationRequests
        );
    }

    function test_consolidate_givenDifferentOwner_reverts()
        public
        givenWalletHasCollateralToken(USER, 1e18)
        givenWalletHasLoan(USER, true, 1e18)
        givenWalletHasCollateralToken(address(this), 1e18)
        givenWalletHasLoan(address(this), true, 1e18)
    {
        // Prepare input data
        (address[] memory coolers, address[] memory clearinghouses) = _getCoolerArrays(true, false);

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(ICoolerV2Migrator.Only_CoolerOwner.selector));

        // Call function
        vm.prank(USER);
        migrator.consolidate(
            coolers,
            clearinghouses,
            USER,
            authorization,
            signature,
            delegationRequests
        );
    }

    function test_consolidate_whenDuplicateCooler_reverts()
        public
        givenWalletHasCollateralToken(USER, 1e18)
        givenWalletHasLoan(USER, true, 1e18)
    {
        // Prepare input data
        (address[] memory coolers, address[] memory clearinghouses) = _getCoolerArrays(true, false);

        // Add duplicate entries
        address[] memory coolersWithDuplicate = new address[](2);
        coolersWithDuplicate[0] = coolers[0];
        coolersWithDuplicate[1] = coolers[0];

        address[] memory clearinghousesWithDuplicate = new address[](2);
        clearinghousesWithDuplicate[0] = clearinghouses[0];
        clearinghousesWithDuplicate[1] = clearinghouses[0];

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(ICoolerV2Migrator.Params_DuplicateCooler.selector));

        // Call function
        vm.prank(USER);
        migrator.consolidate(
            coolersWithDuplicate,
            clearinghousesWithDuplicate,
            USER,
            authorization,
            signature,
            delegationRequests
        );
    }

    function test_consolidate_givenDebtTokenDifferent_reverts() public {
        // Create a new Clearinghouse with a different debt token
        MockERC20 newDebtToken = new MockERC20("New Debt Token", "NDT", 18);
        MockERC4626 newDebtTokenVault = new MockERC4626(
            newDebtToken,
            "New Debt Token Vault",
            "NDTV"
        );
        Clearinghouse newClearinghouse = new Clearinghouse(
            address(ohm),
            address(gohm),
            address(staking),
            address(newDebtTokenVault),
            address(coolerFactory),
            address(kernel)
        );
        vm.startPrank(EXECUTOR);
        kernel.executeAction(Actions.ActivatePolicy, address(newClearinghouse));
        vm.stopPrank();
        vm.startPrank(OVERSEER);
        newClearinghouse.activate();
        vm.stopPrank();

        // Create a Cooler in the new Clearinghouse
        vm.startPrank(USER);
        address newCooler = coolerFactory.generateCooler(gohm, newDebtToken);
        vm.stopPrank();

        // Prepare input data
        (address[] memory coolers, address[] memory clearinghouses) = _getCoolerArrays(true, false);

        address[] memory coolersWithNew = new address[](2);
        coolersWithNew[0] = coolers[0];
        coolersWithNew[1] = newCooler;

        address[] memory clearinghousesWithNew = new address[](2);
        clearinghousesWithNew[0] = clearinghouses[0];
        clearinghousesWithNew[1] = address(newClearinghouse);

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(ICoolerV2Migrator.Params_InvalidCooler.selector));

        // Call function
        vm.prank(USER);
        migrator.consolidate(
            coolersWithNew,
            clearinghousesWithNew,
            USER,
            authorization,
            signature,
            delegationRequests
        );
    }

    function test_consolidate_givenSpendingCollateralNotApproved_reverts()
        public
        givenWalletHasCollateralToken(USER, 1e18)
        givenWalletHasLoan(USER, true, 1e18)
    {
        // Prepare input data
        (address[] memory coolers, address[] memory clearinghouses) = _getCoolerArrays(true, false);

        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Call function
        vm.prank(USER);
        migrator.consolidate(
            coolers,
            clearinghouses,
            USER,
            authorization,
            signature,
            delegationRequests
        );
    }

    function test_consolidate_givenAuthorization()
        public
        givenWalletHasCollateralToken(USER, 1e18)
        givenWalletHasLoan(USER, true, 1e18)
        givenWalletHasApprovedMigratorSpendingCollateral(USER, 1e18)
        givenAuthorization
    {
        // Prepare input data
        (address[] memory coolers, address[] memory clearinghouses) = _getCoolerArrays(true, false);

        // Get loan details
        Cooler.Loan memory loan = _getLoan(true, 0);
        uint256 totalPayable = loan.principal + loan.interestDue;
        uint256 userUsdsBalance = usds.balanceOf(USER);
        uint256 userDaiBalance = dai.balanceOf(USER);

        // Call function
        vm.prank(USER);
        migrator.consolidate(
            coolers,
            clearinghouses,
            USER,
            authorization,
            signature,
            delegationRequests
        );

        // Assert token balances
        _assertTokenBalances(USER, 0, userUsdsBalance, userDaiBalance);
        _assertTokenBalances(address(migrator), 0, 0, 0);

        // Assert authorization via the contract call
        _assertAuthorization(0, uint96(START_TIMESTAMP + 1));

        // Assert cooler V1 loans are zeroed out
        _assertCoolerV1Loans(true, 1);

        // Assert cooler V2 loans are created
        _assertCoolerV2Loan(USER, 1e18, totalPayable);
        _assertCoolerV2Loan(USER2, 0, 0);
    }

    function test_consolidate_givenNoAuthorization()
        public
        givenWalletHasCollateralToken(USER, 1e18)
        givenWalletHasLoan(USER, true, 1e18)
        givenWalletHasApprovedMigratorSpendingCollateral(USER, 1e18)
    {
        // Prepare input data
        (address[] memory coolers, address[] memory clearinghouses) = _getCoolerArrays(true, false);

        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.UnauthorizedOnBehalfOf.selector));

        // Call function
        vm.prank(USER);
        migrator.consolidate(
            coolers,
            clearinghouses,
            USER,
            authorization,
            signature,
            delegationRequests
        );
    }
}
