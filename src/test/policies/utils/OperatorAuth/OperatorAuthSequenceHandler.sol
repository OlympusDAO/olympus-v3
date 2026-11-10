// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Test calls may target exact reverts or canonical state rather than their return values.
// forge-lint: disable-start(unused-return)
// Interfaces
import {IOperatorAuth} from "src/policies/interfaces/utils/IOperatorAuth.sol";

// Contracts
import {OperatorAuthHarness} from "src/test/policies/utils/OperatorAuth/OperatorAuthHarness.sol";
import {OperatorAuthSequenceAccount} from "src/test/policies/utils/OperatorAuth/fixtures/OperatorAuthSequenceAccount.sol";

contract OperatorAuthSequenceHandler {
    error InvalidTemporaryAuthority();
    struct ModelGrant {
        bool exists;
        uint256 accountEpoch;
        uint256 pairEpoch;
    }
    OperatorAuthHarness internal immutable _auth;
    OperatorAuthSequenceAccount[2] internal _accounts;
    address[2] internal _operators = [address(0xB0B), address(0xCAFE)];
    mapping(uint8 => uint256) public modelAccountEpoch;
    mapping(uint8 => mapping(uint8 => uint256)) public modelPairEpoch;
    mapping(uint8 => mapping(uint8 => mapping(bytes32 => ModelGrant))) internal _persistent;
    bytes32 public modelContext;

    constructor(OperatorAuthHarness auth_) {
        _auth = auth_;
        _accounts[0] = new OperatorAuthSequenceAccount(auth_);
        _accounts[1] = new OperatorAuthSequenceAccount(auth_);
    }

    function account(uint8 index_) external view returns (address) {
        return address(_accounts[index_]);
    }

    function operator(uint8 index_) external view returns (address) {
        return _operators[index_];
    }

    function expectedLive(uint8 account_, uint8 operator_) external view returns (bool) {
        ModelGrant memory record = _persistent[account_][operator_][modelContext];
        return
            record.exists &&
            record.accountEpoch == modelAccountEpoch[account_] &&
            record.pairEpoch + 1 == modelPairEpoch[account_][operator_];
    }

    // Fixture/cheatcode calls deliberately interleave effects to exercise callbacks and model transitions.
    // forge-lint: disable-start(reentrancy-no-eth)
    function accept(
        uint8 accountSeed_,
        uint8 operatorSeed_,
        uint8 contextSeed_,
        bool reusable_
    ) external {
        uint8 a = accountSeed_ % 2;
        uint8 o = operatorSeed_ % 2;
        _changeContext(contextSeed_);
        uint256 oldPair = modelPairEpoch[a][o];
        IOperatorAuth.Grant memory grant = IOperatorAuth.Grant(
            address(_accounts[a]),
            _operators[o],
            modelAccountEpoch[a],
            oldPair,
            type(uint48).max,
            reusable_,
            15,
            modelContext,
            hex"01"
        );
        if (reusable_) _accounts[a].approve(grant);
        else _accounts[a].approveTemporary(grant);
        modelPairEpoch[a][o] = oldPair + 1;
        if (reusable_)
            _persistent[a][o][modelContext] = ModelGrant(true, modelAccountEpoch[a], oldPair);
    }

    // forge-lint: disable-end(reentrancy-no-eth)

    // Kept outside invariant target selectors: Forge isolates actor CALLs differently in campaigns.
    function acceptAcrossReturnedActor() external {
        IOperatorAuth.Grant memory grant = IOperatorAuth.Grant(
            address(_accounts[0]),
            _operators[1],
            0,
            0,
            type(uint48).max,
            false,
            15,
            modelContext,
            hex"01"
        );
        _accounts[0].approve(grant);
        bytes32 stamp = _auth.captureAuthorization(grant.account, grant.operator, 1);
        _auth.validateAuthorization(grant.account, grant.operator, 2, stamp);
    }

    function cancelPair(uint8 accountSeed_, uint8 operatorSeed_) external {
        uint8 a = accountSeed_ % 2;
        uint8 o = operatorSeed_ % 2;
        _accounts[a].cancelPair(_operators[o]);
        modelPairEpoch[a][o]++;
    }

    function cancelAll(uint8 accountSeed_) external {
        uint8 a = accountSeed_ % 2;
        _accounts[a].cancelAll();
        modelAccountEpoch[a]++;
    }

    function changeContext(uint8 contextSeed_) external {
        _changeContext(contextSeed_);
    }

    function _changeContext(uint8 contextSeed_) internal {
        modelContext = bytes32(uint256(contextSeed_ % 3));
        _auth.setContext(modelContext);
    }
}
// forge-lint: disable-end(unused-return)
