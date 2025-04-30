// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.8.15;

import {WithEnvironment} from "src/scripts/WithEnvironment.s.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";
import {MockDaiUsds} from "src/test/mocks/MockDaiUsds.sol";
import {MockFlashloanLender} from "src/test/mocks/MockFlashloanLender.sol";
import {console2} from "forge-std/console2.sol";

contract DeployUsdsMocks is WithEnvironment {
    function deploy(string calldata chain_) public {
        _loadEnv(chain_);

        vm.startBroadcast();

        address deployer = msg.sender;
        if (deployer == address(0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38)) {
            revert("Cannot use the default foundry deployer address, specify using --sender");
        } else {
            console2.log("Deployer", deployer);
        }

        // DAI
        MockERC20 dai = new MockERC20("DAI", "DAI", 18);
        console2.log("DAI", address(dai));

        // sDAI
        MockERC4626 sDai = new MockERC4626(dai, "sDAI", "sDAI");
        console2.log("sDAI", address(sDai));

        // USDS
        MockERC20 usds = new MockERC20("USDS", "USDS", 18);
        console2.log("USDS", address(usds));

        // sUSDS
        MockERC4626 sUsds = new MockERC4626(usds, "sUSDS", "sUSDS");
        console2.log("sUSDS", address(sUsds));

        // DAI-USDS migrator
        MockDaiUsds daiUsds = new MockDaiUsds(dai, usds);
        console2.log("DAI-USDS migrator", address(daiUsds));

        // Flash lender
        MockFlashloanLender flashLender = new MockFlashloanLender(0, address(dai));
        console2.log("Flash lender", address(flashLender));

        vm.stopBroadcast();
    }

    function mint(string calldata chain_) public {
        _loadEnv(chain_);

        address treasury = _envAddress("olympus.modules.OlympusTreasury");
        MockERC20 dai = MockERC20(_envAddress("external.tokens.DAI"));
        MockERC20 usds = MockERC20(_envAddress("external.tokens.USDS"));
        MockERC4626 sDai = MockERC4626(_envAddress("external.tokens.sDAI"));
        MockERC4626 sUsds = MockERC4626(_envAddress("external.tokens.sUSDS"));

        vm.startBroadcast();

        address deployer = msg.sender;
        if (deployer == address(0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38)) {
            revert("Cannot use the default foundry deployer address, specify using --sender");
        } else {
            console2.log("Deployer", deployer);
        }

        // Mint DAI to the deployer
        dai.mint(deployer, 200000000e18);

        // Mint USDS to the deployer
        usds.mint(deployer, 200000000e18);

        // Mint sDAI to the deployer
        dai.approve(address(sDai), 20000000e18);
        sDai.deposit(20000000e18, deployer);
        console2.log("Deposited 20000000 DAI for sDAI");

        // Mint sDAI to the treasury
        dai.approve(address(sDai), 20000000e18);
        sDai.deposit(20000000e18, treasury);
        console2.log("Deposited 20000000 DAI for sDAI to treasury");

        // Mint sUSDS to the deployer
        usds.approve(address(sUsds), 20000000e18);
        sUsds.deposit(20000000e18, deployer);
        console2.log("Deposited 20000000 USDS for sUSDS");

        // Mint sUSDS to the treasury
        usds.approve(address(sUsds), 20000000e18);
        sUsds.deposit(20000000e18, treasury);
        console2.log("Deposited 20000000 USDS for sUSDS to treasury");

        vm.stopBroadcast();
    }
}
