// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.0;

import "src/Kernel.sol";

/// @notice Mock policy to allow testing gated module functions
contract ModuleTestFixture is Policy {
    Module internal _module;
    Permissions[] internal _requests;

    constructor(
        Kernel kernel_,
        Module module_,
        Permissions[] memory requests_
    ) Policy(kernel_) {
        _module = module_;
        uint256 len = requests_.length;
        for (uint256 i; i < len; i++) {
            _requests.push(requests_[i]);
        }
    }

    /* ========== FRAMEWORK CONFIFURATION ========== */
    function configureDependencies()
        external
        view
        override
        returns (Keycode[] memory dependencies)
    {
        dependencies = new Keycode[](1);
        dependencies[0] = _module.KEYCODE();
    }

    function requestPermissions() external view override returns (Permissions[] memory requests) {
        uint256 len = _requests.length;
        requests = new Permissions[](len);
        for (uint256 i; i < len; i++) {
            requests[i] = _requests[i];
        }
    }
}

// Generate an UNACTIVATED test fixture policy for a module. Must be activated separately.
library ModuleTestFixtureGenerator {
    // Generate a test fixture policy for a module with all permissions passed in
    function generateFixture(Module module_, Permissions[] memory requests_)
        public
        returns (address)
    {
        return address(new ModuleTestFixture(module_.kernel(), module_, requests_));
    }

    // Generate a test fixture policy authorized for a single module function
    function generateFunctionFixture(Module module_, bytes4 funcSelector_)
        public
        returns (address)
    {
        Permissions[] memory requests = new Permissions[](1);
        requests[0] = Permissions(module_.KEYCODE(), funcSelector_);
        return generateFixture(module_, requests);
    }

    // Generate a test fixture policy with NO permissions
    function generateDummyFixture(Module module_) public returns (address) {
        Permissions[] memory requests = new Permissions[](0);
        return generateFixture(module_, requests);
    }
}
