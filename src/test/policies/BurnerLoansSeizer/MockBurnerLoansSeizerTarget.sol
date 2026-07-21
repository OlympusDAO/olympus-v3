// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.24;

contract MockBurnerLoansSeizerTarget {
    error ScanReverted();
    error SeizureReverted();

    mapping(address => address[]) internal _borrowers;
    mapping(address => uint256) internal _nextIndexes;
    mapping(address => uint256) internal _rewards;

    bool public scanReverts;
    bool public seizureReverts;
    uint256 public seizureCalls;
    address public lastSeizedAsset;
    address[] internal _lastSeizedBorrowers;

    function setScanResult(
        address asset_,
        address[] calldata borrowers_,
        uint256 nextIndex_,
        uint256 reward_
    ) external {
        _borrowers[asset_] = borrowers_;
        _nextIndexes[asset_] = nextIndex_;
        _rewards[asset_] = reward_;
    }

    function setScanReverts(bool reverts_) external {
        scanReverts = reverts_;
    }

    function setSeizureReverts(bool reverts_) external {
        seizureReverts = reverts_;
    }

    function getSeizableBorrowers(
        address asset_,
        uint256,
        uint256,
        uint256
    ) external view returns (address[] memory, uint256, uint256) {
        if (scanReverts) revert ScanReverted();
        return (_borrowers[asset_], _nextIndexes[asset_], _rewards[asset_]);
    }

    function seize(
        address asset_,
        address[] calldata borrowers_
    ) external returns (uint256, uint256) {
        if (seizureReverts) revert SeizureReverted();
        ++seizureCalls;
        lastSeizedAsset = asset_;
        _lastSeizedBorrowers = borrowers_;
        return (0, 0);
    }

    function getLastSeizedBorrowers() external view returns (address[] memory) {
        return _lastSeizedBorrowers;
    }
}
