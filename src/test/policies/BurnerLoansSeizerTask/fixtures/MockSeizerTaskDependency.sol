// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

// Interfaces
import {IERC165} from "@openzeppelin-5.7.0/utils/introspection/IERC165.sol";
import {IBurnerLoansCore} from "src/policies/interfaces/burnerloans/IBurnerLoansCore.sol";
import {IBurnerLoansLens} from "src/policies/interfaces/burnerloans/IBurnerLoansLens.sol";
import {IBurnerLoansSeize} from "src/policies/interfaces/burnerloans/IBurnerLoansSeize.sol";

// Contracts
import {Kernel, Keycode, Permissions, Policy} from "src/Kernel.sol";

/// @dev Separate instances model Core, Seize and Lens without deploying lending contracts.
contract MockSeizerTaskDependency is Policy, IERC165 {
    address public core;
    bool public isEnabled = true;
    mapping(address => bool) public isAssetRegistered;
    mapping(address => uint256) internal _populations;
    mapping(address => address[]) internal _borrowers;
    mapping(address => uint256) internal _nextIndexes;

    constructor(Kernel kernel_, address core_) Policy(kernel_) {
        core = core_;
    }

    function configureDependencies() external pure override returns (Keycode[] memory) {
        return new Keycode[](0);
    }

    function requestPermissions() external pure override returns (Permissions[] memory) {
        return new Permissions[](0);
    }

    function enable(bytes calldata) external {
        isEnabled = true;
    }

    function disable(bytes calldata) external {
        isEnabled = false;
    }

    function setAssetRegistered(address asset_, bool registered_) external {
        isAssetRegistered[asset_] = registered_;
    }

    function setPopulation(address asset_, uint256 population_) external {
        _populations[asset_] = population_;
    }

    function setScanResult(
        address asset_,
        address[] calldata borrowers_,
        uint256 nextIndex_
    ) external {
        _borrowers[asset_] = borrowers_;
        _nextIndexes[asset_] = nextIndex_;
    }

    function getActiveBorrowerCount(address asset_) external view returns (uint256) {
        return _populations[asset_];
    }

    function getSeizableBorrowersBoundedFor(
        address,
        address asset_,
        uint256 start_,
        uint256 checks_,
        uint256
    ) external view returns (address[] memory, uint256, uint256) {
        // Model Lens bounds responses; real pagination is exercised by integration tests.
        if (checks_ == 0 && start_ != 0 && start_ >= _populations[asset_]) {
            revert IBurnerLoansLens.BurnerLoansLens_InvalidStart(start_, _populations[asset_]);
        }
        return (_borrowers[asset_], _nextIndexes[asset_], 0);
    }

    function seize(
        address asset_,
        address[] calldata
    ) external pure returns (address, uint256, uint256) {
        return (asset_, 0, 0);
    }

    function supportsInterface(bytes4 interfaceId_) external pure returns (bool) {
        return
            interfaceId_ == type(IERC165).interfaceId ||
            interfaceId_ == type(IBurnerLoansCore).interfaceId ||
            interfaceId_ == type(IBurnerLoansSeize).interfaceId;
    }
}
