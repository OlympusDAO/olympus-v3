// SPDX-License-Identifier: UNLICENSED
// solhint-disable one-contract-per-file
pragma solidity 0.8.15;

import {CoolerComposites} from "src/policies/cooler/CoolerComposites.sol";
import {IDLGTEv1} from "src/modules/DLGTE/IDLGTE.v1.sol";
import {IMonoCooler} from "src/policies/interfaces/cooler/IMonoCooler.sol";
import {MonoCoolerBaseTest} from "./MonoCoolerBase.t.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

abstract contract CoolerCompositesTest is MonoCoolerBaseTest {
    CoolerComposites internal composites;

    uint48 internal constant START_BLOCK = 1000000;

    address internal constant DELEGATE_RECIPIENT = address(0xDDDD);

    address internal accountOwner;
    uint256 internal accountOwnerPk;

    IDLGTEv1.DelegationRequest[] internal delegationRequests;
    IMonoCooler.Authorization internal authorization;
    IMonoCooler.Signature internal signature;

    bytes32 private constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(uint256 chainId,address verifyingContract)");
    bytes32 private constant AUTHORIZATION_TYPEHASH =
        keccak256(
            "Authorization(address account,address authorized,uint96 authorizationDeadline,uint256 nonce,uint256 signatureDeadline)"
        );

    function buildDomainSeparator() internal view returns (bytes32) {
        return keccak256(abi.encode(DOMAIN_TYPEHASH, block.chainid, address(cooler)));
    }

    function setUp() public override {
        vm.warp(START_BLOCK);

        super.setUp();

        composites = new CoolerComposites(cooler);

        (accountOwner, accountOwnerPk) = makeAddrAndKey("ACCOUNT_OWNER");
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
        vm.prank(accountOwner);
        cooler.setAuthorization(address(composites), uint96(block.timestamp + 1));
        _;
    }

    modifier givenAuthorizationCleared() {
        vm.prank(accountOwner);
        cooler.setAuthorization(address(composites), 0);
        _;
    }

    modifier givenAuthorizationSignatureSet() {
        (authorization, signature) = signedAuth(
            accountOwner,
            accountOwnerPk,
            address(composites),
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

    modifier givenAccountHasCollateralToken(uint128 collateralAmount_) {
        deal(address(gohm), accountOwner, collateralAmount_);
        _;
    }

    modifier givenAccountHasApprovedCollateralToken(uint128 collateralAmount_) {
        vm.prank(accountOwner);
        gohm.approve(address(composites), collateralAmount_);
        _;
    }

    modifier givenAccountHasApprovedDebtToken(uint128 debtAmount_) {
        vm.prank(accountOwner);
        usds.approve(address(composites), debtAmount_);
        _;
    }

    modifier givenAccountHasBorrowed(uint128 collateralAmount_, uint128 borrowAmount_) {
        vm.prank(accountOwner);
        composites.addCollateralAndBorrow(
            authorization,
            signature,
            collateralAmount_,
            borrowAmount_,
            delegationRequests
        );
        _;
    }

    function _assertTokenBalances(
        uint256 accountOwnerCollateralTokenBalance_,
        uint256 accountOwnerDebtTokenBalance_
    ) internal view {
        assertEq(
            gohm.balanceOf(accountOwner),
            accountOwnerCollateralTokenBalance_,
            "accountOwner collateral balance"
        );
        assertEq(gohm.balanceOf(address(composites)), 0, "composites collateral balance");

        assertEq(
            usds.balanceOf(accountOwner),
            accountOwnerDebtTokenBalance_,
            "accountOwner debt balance"
        );
        assertEq(usds.balanceOf(address(composites)), 0, "composites debt balance");
    }

    function _assertAuthorization(uint256 nonce_, uint96 deadline_) internal view {
        assertEq(cooler.authorizationNonces(accountOwner), nonce_, "authorization nonce");
        assertEq(
            cooler.authorizations(accountOwner, address(composites)),
            deadline_,
            "authorization deadline"
        );
    }

    modifier givenDelegationRequestCleared() {
        // Iterate over the array and remove each item
        while (delegationRequests.length > 0) {
            delegationRequests.pop();
        }
        _;
    }

    modifier givenDelegationRequest(int256 amount_) {
        delegationRequests.push(
            IDLGTEv1.DelegationRequest({delegate: DELEGATE_RECIPIENT, amount: amount_})
        );
        _;
    }
}

contract CoolerCompositesAddAndBorrowTest is CoolerCompositesTest {
    // given authorization has not been provided
    //  given an authorization signature has not been provided
    //   [X] it reverts
    //  given an authorization signature has been provided
    //   [X] it sets authorization
    //   [X] it adds collateral and borrows
    // given authorization has been provided
    //  given an authorization signature has been provided
    //   [X] it sets authorization
    //   [X] it adds collateral and borrows
    //  given the caller has not approved the composites contract to spend the collateral
    //   [X] it reverts
    //  given the caller does not have enough collateral
    //   [X] it reverts
    //  given delegation requests are provided
    //   [X] it adds collateral and borrows
    //   [X] it executes the delegation requests
    //  [X] it adds collateral and borrows

    function test_givenNoAuthorization_givenNoSignature_reverts()
        public
        givenAccountHasCollateralToken(2e18)
        givenAccountHasApprovedCollateralToken(2e18)
    {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.UnauthorizedOnBehalfOf.selector));

        // Call function
        vm.prank(accountOwner);
        composites.addCollateralAndBorrow(authorization, signature, 2e18, 1e21, delegationRequests);
    }

    function test_givenNoAuthorization_givenSignature()
        public
        givenAccountHasCollateralToken(2e18)
        givenAccountHasApprovedCollateralToken(2e18)
        givenAuthorizationSignatureSet
    {
        // Call function
        vm.prank(accountOwner);
        composites.addCollateralAndBorrow(authorization, signature, 2e18, 1e21, delegationRequests);

        // Assert token balances
        _assertTokenBalances(0, 1e21);

        // Assert authorization via the signature
        _assertAuthorization(1, uint96(START_BLOCK + 1));
    }

    function test_givenAuthorization_givenSignature()
        public
        givenAccountHasCollateralToken(2e18)
        givenAccountHasApprovedCollateralToken(2e18)
        givenAuthorization
        givenAuthorizationSignatureSet
    {
        // Call function
        vm.prank(accountOwner);
        composites.addCollateralAndBorrow(authorization, signature, 2e18, 1e21, delegationRequests);

        // Assert token balances
        _assertTokenBalances(0, 1e21);

        // Assert authorization via the signature
        _assertAuthorization(1, uint96(START_BLOCK + 1));
    }

    function test_givenAuthorization_insufficientCollateral_reverts()
        public
        givenAccountHasCollateralToken(1e18)
        givenAccountHasApprovedCollateralToken(2e18)
        givenAuthorization
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Call function
        vm.prank(accountOwner);
        composites.addCollateralAndBorrow(authorization, signature, 2e18, 1e21, delegationRequests);
    }

    function test_givenAuthorization_insufficientApproval_reverts()
        public
        givenAccountHasCollateralToken(2e18)
        givenAccountHasApprovedCollateralToken(1e18)
        givenAuthorization
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Call function
        vm.prank(accountOwner);
        composites.addCollateralAndBorrow(authorization, signature, 2e18, 1e21, delegationRequests);
    }

    function test_givenAuthorization()
        public
        givenAccountHasCollateralToken(2e18)
        givenAccountHasApprovedCollateralToken(2e18)
        givenAuthorization
    {
        // Call function
        vm.prank(accountOwner);
        composites.addCollateralAndBorrow(authorization, signature, 2e18, 1e21, delegationRequests);

        // Assert token balances
        _assertTokenBalances(0, 1e21);

        // Assert authorization via the contract call
        _assertAuthorization(0, uint96(START_BLOCK + 1));
    }

    function test_givenAuthorization_givenDelegationRequests()
        public
        givenAccountHasCollateralToken(2e18)
        givenAccountHasApprovedCollateralToken(2e18)
        givenAuthorization
        givenDelegationRequest(2e18)
    {
        // Call function
        vm.prank(accountOwner);
        composites.addCollateralAndBorrow(authorization, signature, 2e18, 1e21, delegationRequests);

        // Assert delegation requests
        expectOneDelegation(cooler, accountOwner, DELEGATE_RECIPIENT, 2e18);
    }
}

contract CoolerCompositesRepayAndRemoveTest is CoolerCompositesTest {
    // given authorization has not been provided
    //  given an authorization signature has not been provided
    //   [X] it reverts
    //  given an authorization signature has been provided
    //   [X] it sets authorization
    //   [X] it repays and removes collateral
    // given authorization has been provided
    //  given an authorization signature has been provided
    //   [X] it sets authorization
    //   [X] it repays and removes collateral
    //  given the caller has not approved the composites contract to spend the debt token
    //   [X] it reverts
    //  given the caller does not have enough debt token
    //   [X] it reverts
    //  given the repay amount is more than the debt
    //   [X] it repays and removes collateral
    //   [X] it returns the excess debt token to the caller
    //  given delegation requests are provided
    //   [X] it repays and removes collateral
    //   [X] it executes the delegation requests
    //  [X] it repays and removes collateral

    function test_givenNoAuthorization_givenNoSignature_reverts()
        public
        givenAccountHasCollateralToken(2e18)
        givenAccountHasApprovedCollateralToken(2e18)
        givenAuthorizationSignatureSet
        givenAccountHasBorrowed(2e18, 1e21)
        givenAccountHasApprovedDebtToken(1e21)
        givenAuthorizationCleared
        givenAuthorizationSignatureCleared
    {
        // Expect revert
        vm.expectRevert(abi.encodeWithSelector(IMonoCooler.UnauthorizedOnBehalfOf.selector));

        // Call function
        vm.prank(accountOwner);
        composites.repayAndRemoveCollateral(
            authorization,
            signature,
            1e21,
            2e18,
            delegationRequests
        );
    }

    function test_givenNoAuthorization_givenSignature()
        public
        givenAccountHasCollateralToken(2e18)
        givenAccountHasApprovedCollateralToken(2e18)
        givenAuthorizationSignatureSet
        givenAccountHasBorrowed(2e18, 1e21)
        givenAccountHasApprovedDebtToken(1e21)
        givenAuthorizationSignatureSet
    {
        // Call function
        vm.prank(accountOwner);
        composites.repayAndRemoveCollateral(
            authorization,
            signature,
            1e21,
            2e18,
            delegationRequests
        );

        // Assert token balances
        _assertTokenBalances(2e18, 0);

        // Assert authorization via the signature
        _assertAuthorization(2, uint96(START_BLOCK + 1));
    }

    function test_givenAuthorization_givenSignature()
        public
        givenAccountHasCollateralToken(2e18)
        givenAccountHasApprovedCollateralToken(2e18)
        givenAuthorization
        givenAuthorizationSignatureSet
        givenAccountHasBorrowed(2e18, 1e21)
        givenAccountHasApprovedDebtToken(1e21)
        givenAuthorizationSignatureSet
    {
        // Call function
        vm.prank(accountOwner);
        composites.repayAndRemoveCollateral(
            authorization,
            signature,
            1e21,
            2e18,
            delegationRequests
        );

        // Assert token balances
        _assertTokenBalances(2e18, 0);

        // Assert authorization via the signature
        _assertAuthorization(2, uint96(START_BLOCK + 1));
    }

    function test_givenAuthorization_insufficientDebtTokenBalance_reverts()
        public
        givenAccountHasCollateralToken(2e18)
        givenAccountHasApprovedCollateralToken(2e18)
        givenAuthorization
        givenAccountHasBorrowed(2e18, 1e21)
        givenAccountHasApprovedDebtToken(1e21)
    {
        // Transfer debt token elsewhere
        vm.prank(accountOwner);
        usds.transfer(address(0x1), 0.5e21);

        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Call function
        vm.prank(accountOwner);
        composites.repayAndRemoveCollateral(
            authorization,
            signature,
            1e21,
            2e18,
            delegationRequests
        );
    }

    function test_givenAuthorization_insufficientDebtTokenApproval_reverts()
        public
        givenAccountHasCollateralToken(2e18)
        givenAccountHasApprovedCollateralToken(2e18)
        givenAuthorization
        givenAccountHasBorrowed(2e18, 1e21)
        givenAccountHasApprovedDebtToken(0.5e21)
    {
        // Expect revert
        vm.expectRevert("TRANSFER_FROM_FAILED");

        // Call function
        vm.prank(accountOwner);
        composites.repayAndRemoveCollateral(
            authorization,
            signature,
            1e21,
            2e18,
            delegationRequests
        );
    }

    function test_givenAuthorization_givenRepaymentExcess()
        public
        givenAccountHasCollateralToken(2e18)
        givenAccountHasApprovedCollateralToken(2e18)
        givenAuthorization
        givenAccountHasBorrowed(2e18, 1e21)
        givenAccountHasApprovedDebtToken(1e21 + 1)
    {
        // Provide more debt token than is owed
        deal(address(usds), accountOwner, 1e21 + 1);

        // Call function
        vm.prank(accountOwner);
        composites.repayAndRemoveCollateral(
            authorization,
            signature,
            1e21 + 1,
            2e18,
            delegationRequests
        );

        // Assert token balances
        // Excess debt token of 1 is returned to the caller
        _assertTokenBalances(2e18, 1);

        // Assert authorization via the contract call
        _assertAuthorization(0, uint96(START_BLOCK + 1));
    }

    function test_givenAuthorization()
        public
        givenAccountHasCollateralToken(2e18)
        givenAccountHasApprovedCollateralToken(2e18)
        givenAuthorization
        givenAccountHasBorrowed(2e18, 1e21)
        givenAccountHasApprovedDebtToken(1e21)
    {
        // Call function
        vm.prank(accountOwner);
        composites.repayAndRemoveCollateral(
            authorization,
            signature,
            1e21,
            2e18,
            delegationRequests
        );

        // Assert token balances
        _assertTokenBalances(2e18, 0);

        // Assert authorization via the contract call
        _assertAuthorization(0, uint96(START_BLOCK + 1));
    }

    function test_givenAuthorization_givenDelegationRequests()
        public
        givenAccountHasCollateralToken(2e18)
        givenAccountHasApprovedCollateralToken(2e18)
        givenAuthorization
        givenDelegationRequest(2e18)
        givenAccountHasBorrowed(2e18, 1e21)
        givenAccountHasApprovedDebtToken(1e21)
        givenDelegationRequestCleared
        givenDelegationRequest(-2e18)
    {
        // Call function
        vm.prank(accountOwner);
        composites.repayAndRemoveCollateral(
            authorization,
            signature,
            1e21,
            2e18,
            delegationRequests
        );

        // Assert delegation requests
        expectNoDelegations(accountOwner);
    }
}
