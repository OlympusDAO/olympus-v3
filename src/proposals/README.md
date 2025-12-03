# Overview

Before creating a new proposal, it's essential to understand Olympus' On-Chain Governance (OCG) system. Please review the details in the [OCG Implementation Document](./OCG.md).

## The Importance of Community Reviews

The lifecycle of a proposal begins with a crucial step: the **Review Phase**. This is where the Olympus community plays a pivotal role in assessing and verifying the proposed on-chain actions. The community ensures that these actions align with the protocol's goals, the proposal intent, and the discussions held in the forums.

### Key Objectives During the Review Phase

1. **Security Assurance:** This phase is critical for safeguarding the protocol against malicious proposals.
2. **Community Engagement:** Active community participation is vital in evaluating the proposal's feasibility and impact.

## Challenges presented by OCG

OCG's trustless nature is one of its greatest strengths, but it also presents a challenge: the inability to mandate specific frameworks or best practices at the smart contract level. As a result, any proposal with sufficient community backing can be executed, regardless of code quality and clarity.

## Adopting an Open-Source Framework for Proposal Structure and Verifiability

To address this challenge, the DAO has decided to adopt [forge-proposal-simulator](https://solidity-labs.gitbook.io/forge-proposal-simulator/), an open-source framework designed to:

- Simplify the verifiability process of a proposal.
- Effectively structure proposals.

This framework allows anyone to execute proposals in a forked environment and develop integration tests to examine the new system's behavior in a controlled sandbox.

### Social Veto on Proposals Not Using the Framework

Due to the importance of this framework in ensuring transparency and security, **the DAO will "socially veto" any proposals not adopting it**. This stance is based on the belief that **omitting the framework could indicate an attempt to pass a harmful proposal** by obfuscating its verification process.

## Creating a New Proposal

To create a new simulatable proposal, follow these steps:

1. **Fork the Olympus V3 Repository**

    - Fork the [Olympus V3](https://github.com/OlympusDAO/olympus-v3) GitHub repository.

2. **Update the Address Registry**

    - Update the [address registry](./addresses.json) and declare all necessary dependencies.
    - Follow this naming convention:
        - 2.1. Use lowercase.
        - 2.2. Separate words with dashes.
        - 2.3. Start with the source: `"olympus"` or `"external"`.
        - 2.4. Indicate the address/contract type: e.g., `"token"`, `"multisig"`, `"policy"`.
        - 2.5. Include the address/contract name.
        - 2.6. Exceptions: `"proposer"`, `"olympus-governor"`, `"olympus-kernel"`.
        - 2.7. Examples:

            - **Olympus modules**: Use the following pattern instead of importing module addresses:

                ```solidity
                Kernel kernel = Kernel(addresses.getAddress("olympus-kernel"));
                address TRSRY = address(kernel.getModuleForKeycode(toKeycode(bytes5("TRSRY"))));
                ```

            - **Olympus policies**: `"olympus-policy-xxx"`
            - **Olympus legacy contracts (OHM, gOHM, staking)**: `"olympus-legacy-xxx"`
            - **Olympus multisigs**: `olympus-multisig-dao` or `olympus-multisig-emergency`
            - **External tokens (DAI, sDAI, etc)**: `external-tokens-xxx`
            - **External contracts**: `external-coolers-factory`

3. **Create a New Proposal Contract**

    - Create a new contract in [src/proposals/](./) named after its corresponding OIP (e.g., `OIP_XXX.sol`).
    - Use [OIP_XXX.sol](./OIP_XXX.sol) as a template.
    - The contract should inherit `GovernorBravoProposal`.
    - Override the following functions:

        - `name()`: Name it after the OIP.
        - `description()`: Brief explanation of the OIP.
        - `_deploy()`: Deploy the smart contracts for OlympusV3. If already deployed, import addresses from [address registry](./addresses.json).
        - `_afterDeploy()`: If necessary, configure the contracts before pluggin them into OlympusV3. Cache initial TRSRY reserves and other values for post-execution checks.
        - `_build()`: Add proposal actions one by one. Use the following functions:

            ```solidity
            // @dev push an action to the proposal
            function _pushAction(
                uint256 value,
                address target,
                bytes memory data,
                string memory _description
            ) internal {
                actions.push(
                    Action({
                        value: value,
                        target: target,
                        arguments: data,
                        description: _description
                    })
                );
            }

            // @dev push an action to the proposal with a value of 0
            function _pushAction(
                address target,
                bytes memory data,
                string memory _description
            ) internal {
                _pushAction(0, target, data, _description);
            }
            ```

        - `_run()`: Simulate the proposal execution. Use the provided code.

            ```solidity
            // Executes the proposal actions.
            function _run(Addresses addresses, address) internal override {
                // Simulates actions on TimelockController
                _simulateActions(
                    addresses.getAddress("olympus-governor"),
                    addresses.getAddress("olympus-legacy-gohm"),
                    addresses.getAddress("proposer")
                );
            }
            ```

        - `_validate_()`: Perform validations and assertions to ensure proposal integrity. Demonstrate to the community that the proposal is secure and achieves the intended outcomes without putting the Treasury funds at risk.

4. **Create a New Test for the Proposal**

    - Create a test in [src/test/proposals/](../test/proposals) named after the OIP (e.g., `OIP_XXX.t.sol`).
    - Use [OIP_XXX.t.sol](../test/proposals/OIP_XXX.t.sol) as a template.
    - Import your proposal, and its dependencies, from step #3.
    - Modify `setUp()` to deploy your OIP rather than `OIP_XXX`.
    - Include this test to ensure `setUp` execution:

    ```solidity
    // [DO NOT DELETE] Dummy test to ensure that `setUp` is executed
    function testProposal() public {
        assertTrue(true);
    }
    ```

    - Optionally, feel free to include integration tests. Integration tests should be named `testProposal_xxx`.

5. **Submit a Pull Request**
    - Do a PR to the [Olympus V3](https://github.com/OlympusDAO/olympus-v3) repository.
    - Name the PR `OIP-XXX: proposal simulation`.

## Local Fork Testing

OCG proposals should be tested before submission on mainnet. To do so, perform the following:

1. Launch an Anvil fork: `anvil --fork-url $FORK_TEST_RPC_URL --port 8545 --auto-impersonate`
    - This requires `FORK_TEST_RPC_URL` to be set as an environment variable beforehand.
2. Deploy the required contracts as normal, but provide `--rpc-url http://localhost:8545` as an argument.
3. Perform any DAO MS batches as normal, but provide `--rpc-url http://localhost:8545` as an argument.
4. Submit the proposal using the following command, e.g. `forge script src/proposals/ConvertibleDepositProposal.sol:ConvertibleDepositProposalScript --rpc-url http://localhost:8545 --account <castAccount> -vvv --slow`
    - This will run the proposal as a part of simulating submission. If there are any issues, it will revert.
