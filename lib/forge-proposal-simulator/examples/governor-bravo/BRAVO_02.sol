pragma solidity ^0.8.0;

import {GovernorBravoProposal} from "@proposals/GovernorBravoProposal.sol";
import {Addresses} from "@addresses/Addresses.sol";
import {Vault} from "@examples/Vault.sol";
import {MockToken} from "@examples/MockToken.sol";

// Mock proposal that deposits MockToken into Vault.
contract BRAVO_02 is GovernorBravoProposal {
    // Returns the name of the proposal.
    function name() public pure override returns (string memory) {
        return "BRAVO_02";
    }

    // Provides a brief description of the proposal.
    function description() public pure override returns (string memory) {
        return "Deposit MockToken into Vault";
    }

    // Sets up actions for the proposal, in this case, depositing MockToken into Vault.
    function _build(Addresses addresses) internal override {
        address timelock = addresses.getAddress("PROTOCOL_TIMELOCK");
        address timelockVault = addresses.getAddress("VAULT");
        address token = addresses.getAddress("TOKEN_1");
        uint256 balance = MockToken(token).balanceOf(address(timelock));
        _pushAction(
            token,
            abi.encodeWithSignature(
                "approve(address,uint256)",
                timelockVault,
                balance
            ),
            "Approve MockToken for Vault"
        );
        _pushAction(
            timelockVault,
            abi.encodeWithSignature("deposit(address,uint256)", token, balance),
            "Deposit MockToken into Vault"
        );
    }

    // Executes the proposal actions.
    function _run(Addresses addresses, address) internal override {
        // Call parent _run function to check if there are actions to execute
        super._run(addresses, address(0));

        address governor = addresses.getAddress("PROTOCOL_GOVERNOR");
        address govToken = addresses.getAddress("PROTOCOL_GOVERNANCE_TOKEN");
        address proposer = addresses.getAddress("BRAVO_PROPOSER");

        _simulateActions(governor, govToken, proposer);
    }

    // Validates the post-execution state
    function _validate(Addresses addresses, address) internal override {
        address timelock = addresses.getAddress("PROTOCOL_TIMELOCK");
        Vault timelockVault = Vault(addresses.getAddress("VAULT"));
        MockToken token = MockToken(addresses.getAddress("TOKEN_1"));

        uint256 balance = token.balanceOf(address(timelockVault));
        (uint256 amount, ) = timelockVault.deposits(address(token), timelock);
        assertEq(amount, balance);

        assertEq(timelockVault.owner(), timelock);
        assertTrue(timelockVault.tokenWhitelist(address(token)));
        assertFalse(timelockVault.paused());

        assertEq(token.owner(), timelock);
        assertEq(token.balanceOf(address(timelockVault)), token.totalSupply());
    }
}
