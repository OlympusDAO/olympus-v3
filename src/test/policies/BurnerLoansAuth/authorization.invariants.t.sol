// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Contracts
import {BurnerLoansAuth} from "src/policies/burnerloans/BurnerLoansAuth.sol";
import {BurnerLoansAuthTest} from "src/test/policies/BurnerLoansAuth/BurnerLoansAuthTest.sol";
import {BurnerLoansAuthSequenceHandler} from "src/test/policies/BurnerLoansAuth/fixtures/BurnerLoansAuthSequenceHandler.sol";

contract BurnerLoansAuthInvariantTest is BurnerLoansAuthTest {
    BurnerLoansAuthSequenceHandler internal _handler;

    function setUp() public override {
        super.setUp();
        _handler = new BurnerLoansAuthSequenceHandler(
            _core,
            _auth,
            new BurnerLoansAuth(address(_kernel), address(_core)),
            _asset
        );
        targetContract(address(_handler));
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = _handler.approve.selector;
        selectors[1] = _handler.cancelPair.selector;
        selectors[2] = _handler.cancelAccount.selector;
        selectors[3] = _handler.rotate.selector;
        targetSelector(FuzzSelector(address(_handler), selectors));
    }

    // Scenarios: BLAUTH-ROTATE-P05.
    function invariant_authorityMatchesIndependentInstanceAndEpochModel() public view {
        _handler.assertModel();
    }
}
