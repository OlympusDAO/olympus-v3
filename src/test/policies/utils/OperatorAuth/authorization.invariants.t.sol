// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;
// Interfaces
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Contracts
import {OperatorAuthSequenceHandler} from "./OperatorAuthSequenceHandler.sol";
import {OperatorAuthTest} from "./OperatorAuthTest.sol";

contract OperatorAuthSequenceInvariantTest is OperatorAuthTest {
    OperatorAuthSequenceHandler internal _handler;

    function setUp() public override {
        super.setUp();
        _handler = new OperatorAuthSequenceHandler(_auth);
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = _handler.accept.selector;
        selectors[1] = _handler.cancelPair.selector;
        selectors[2] = _handler.cancelAll.selector;
        selectors[3] = _handler.changeContext.selector;
        targetSelector(FuzzSelector(address(_handler), selectors));
        targetContract(address(_handler));
    }

    // Scenarios: OAINV-P01.
    // These calls enumerate bounded test actors/assets, including fixture helpers called by the loops.
    // forge-lint: disable-start(calls-loop)
    function invariant_epochsMatchIndependentAccountsAndPairs() public view {
        for (uint8 a; a < 2; a++) {
            assertEq(
                _auth.accountEpochs(_handler.account(a)),
                _handler.modelAccountEpoch(a),
                "Independent account epoch model"
            );
            for (uint8 o; o < 2; o++)
                assertEq(
                    _auth.pairEpochs(_handler.account(a), _handler.operator(o)),
                    _handler.modelPairEpoch(a, o),
                    "Independent shared pair sequence across contexts"
                );
        }
    }

    // forge-lint: disable-end(calls-loop)

    // Scenarios: OAINV-P02.
    // These calls enumerate bounded test actors/assets, including fixture helpers called by the loops.
    // forge-lint: disable-start(calls-loop)
    function invariant_onlyCurrentReusableAuthoritySurvivesTransactions() public view {
        for (uint8 a; a < 2; a++)
            for (uint8 o; o < 2; o++) {
                (bool success, ) = address(_auth).staticcall(
                    abi.encodeCall(
                        IOperatorAuth.captureAuthorization,
                        (_handler.account(a), _handler.operator(o), 1)
                    )
                );
                if (_handler.expectedLive(a, o)) {
                    assertEq(
                        _auth.getGrant(_handler.account(a), _handler.operator(o)).permissions,
                        hex"01",
                        "Getter exposes modeled live reusable permissions"
                    );
                } else {
                    _assertNoGrant(_handler.account(a), _handler.operator(o));
                }
                assertEq(
                    success,
                    _handler.expectedLive(a, o),
                    "Reusable authority matches model; temporary replacement cannot revive history"
                );
            }
    }
    // forge-lint: disable-end(calls-loop)
}
