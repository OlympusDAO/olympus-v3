# AGENTS.md

This file provides guidance to LLM tools when working with code in this repository.

## Project Overview

This is Olympus V3 (aka Bophades), a complete rewrite of the Olympus protocol using the Default Framework. It's a modular DeFi protocol built on Solidity that separates concerns through a Kernel-Module-Policy architecture.

## Build and Development Commands

- `pnpm run build` - Refresh dependencies, clean and run a full build (runs `./shell/full_install.sh`). This takes a long time, so use it only on a fresh install or when switching branches.
- `pnpm run test` - Run all tests (runs `./shell/test_all.sh`)
- `pnpm run test:unit` - Run unit tests only (excludes fork tests and proposals)
- `pnpm run test:fork` - Run fork tests (requires `FORK_TEST_RPC_URL` env var)
- `pnpm run test:proposal` - Run proposal tests
- `pnpm run test:coverage` - Generate test coverage report
- `pnpm run lint` - Format and lint code (prettier + solhint + markdownlint)
- `pnpm run lint:check` - Check formatting and linting without fixing
- `pnpm run prettier` - Format code (runs quicker than linting)
- `forge build` - Build all files
- `forge build --contracts path/to/contract.sol` - Build a specific contract
- `forge test` - Test all files. Avoid using this without additional flags, as it will run all tests, many of which require additional parameters to run successfully.
- `forge test -vvv --match-contract ContractTest` - Run a specific test contract

Note: always build, test and lint updated files. Use project-wide build and test commands sparingly.

## Safety and Permissions

Allowed without prompt:

- Read files, list files
- Build single file
- Formatting and linting
- Test single file

Ask first:

- Installing dependencies
- Full build
- Git push
- Deleting files
- Changing file permissions
- Full test suites (`test`, `test:unit`, `test:fork` or `test:proposal`)

## Agent Behaviour

### Communication Style

- Be direct and concise
- Avoid conversational fillers ("Let me...", "I'm going to...", "Now I'll...").
- State what you're doing, not what you're about to do. Example: Instead of "Let me read the file to understand what's happening", simply read the file and report findings.

### Approach

- Make reasonable assumptions based on codebase conventions. Only ask when:
    - Multiple valid approaches exist with significant trade-offs
    - Security implications are unclear
    - The choice affects external integrations
- Document assumptions in comments when you proceed without asking
- When stuck, ask a clarifying question

### Scope Management

- Fix the specific issue, not the surrounding code unless requested
- Don't refactor "just because" - prefer ugly-but-working over clean-but-risky
- Exception: If you spot a critical security bug, flag it immediately

### Information Gathering

- Read the actual implementation before making changes. Never guess.
- For cross-cutting concerns (e.g., "all places that use X"), use grep/glob to find all instances first
- When exploring, cast a wide net initially, then narrow down

### Failure Handling

- If a build/test fails, report the actual error, not a summary
- Include file:line references for all errors
- Attempt to fix before reporting, but explain what you tried

### Context Retention

- Remember user preferences stated earlier in the conversation
- When a pattern is established (e.g., "always use 18 decimals"), apply it consistently
- If the user corrects you, update your mental model and acknowledge

### Tool Selection

- Prefer specialized tools (Read, Grep, Glob) over bash equivalents
- Use Bash only for: git, npm/pnpm, forge commands, or actual terminal operations
- Never use bash for file operations (cat, sed, awk, echo redirections)

### Progress Reporting

- For multi-step tasks, use TodoWrite proactively
- Mark tasks in_progress immediately when starting
- Mark completed after finishing - not in batches
- One task in_progress at a time

### Testing Discipline

- Write or update tests before implementation
- If tests don't exist for a function you're modifying, create them first
- Run the specific test file after changes, not the full suite
- Only run full test suites when explicitly requested or at major milestones

### Commit and Git Hygiene

- Never create commits unless explicitly asked
- Never push unless explicitly asked
- The git commit message should follow the format of: `<type>(<scope>): <description>`
    - `type` may be one of:
        - feat: Introduces a new feature.
        - fix: Patches a bug.
        - docs: Documentation-only changes.
        - style: Changes that do not affect the meaning of the code (white-space, formatting, etc).
        - refactor: A code change that neither fixes a bug nor adds a feature.
        - perf: Improves performance.
        - test: Adds missing tests or corrects existing tests.
        - chore: Changes to the build process or auxiliary tools and libraries such as documentation generation.
    - `scope` can refer to the area of code (such as the feature) where the change has taken place
    - `description` is a concise summary of the changes

### Git Workflow

- When starting work on a new branch or feature, use git worktree instead of switching branches
- List existing worktrees before creating new ones: `git worktree list`
- Create a worktree for a branch: `git worktree add ../olympus-v3-<feature-name> <branch-name>`
- When done with a worktree, remove it: `git worktree remove ../olympus-v3-<feature-name>`
- Be aware of worktree locations when running commands—use absolute paths if the worktree is outside the main repo

## Architecture Overview

### Default Framework Components

The protocol follows the Default Framework pattern with a three major components:

1. **Kernel** (`src/Kernel.sol`) - Central governance and access control system
    - Manages installation/upgrading of modules and activation/deactivation of policies
    - Implements role-based access control with 5-byte keycodes
    - Executes governance actions: InstallModule, UpgradeModule, ActivatePolicy, DeactivatePolicy, ChangeExecutor, MigrateKernel

2. **Modules** (`src/modules/`) - Shared state storage with minimal dependencies
    - Each module has a 5-byte keycode identifier (e.g., TRSRY, MINTR, PRICE)
    - Define roles for policies to access module functions
    - Can be upgraded by installing new versions with same keycode
    - Key modules: TRSRY (Treasury), MINTR (Minter), PRICE (Price Oracle), RANGE (Range-Bound Stability), ROLES (Access Control)

3. **Policies** (`src/policies/`) - User-facing contracts with business logic
    - Request permissions from kernel to call module functions
    - Contain isolated state and handle user interactions
    - Examples: Operator (RBS), Heart (Auction), BondCallback, Cooler lending

### Key Policy Categories

- **Core Protocol**: Operator, Heart, Distributor, Emergency
- **Lending**: Cooler V2 (MonoCooler), LoanConsolidator
- **Cross-Chain**: CCIPBurnMintTokenPool, CrossChainBridge
- **Deposits**: ConvertibleDepositFacility, YieldDepositFacility
- **Boosted Liquidity**: BLVault implementations for Lido and LUSD

## Directory Structure

```ml
src/
├── Kernel.sol                # Central control system
├── modules/                  # Shared state storage
│   ├── TRSRY/                # Treasury management
│   ├── MINTR/                # Token minting
│   ├── PRICE/                # Price oracles
│   ├── RANGE/                # Range-bound stability
│   └── ROLES/                # Access control
├── policies/                 # Business logic contracts
│   ├── cooler/               # Lending protocols
│   ├── deposits/             # Deposit facilities
│   ├── BoostedLiquidity/     # Liquidity mining
│   └── bridge/               # Cross-chain functionality
├── external/                 # External contract dependencies
├── interfaces/               # Standard interfaces
├── libraries/                # Utility libraries
└── test/                     # Test files and mocks
└── scripts/                  # Deployment and configuration scripts
└── proposals/                # On-Chain Governance (OCG) proposals
```

## Development Guidelines

### Testing

- There are a number of different test commands:
    - `pnpm run test` - Run all tests (runs `./shell/test_all.sh`)
    - `pnpm run test:unit` - Run unit tests only (excludes fork tests and proposals)
    - `pnpm run test:fork` - Run fork tests (requires `FORK_TEST_RPC_URL` env var)
    - `pnpm run test:proposal` - Run OCG proposal tests
- Unit tests exclude fork tests and proposals: `--no-match-contract '(Fork)' --no-match-path 'src/test/proposals/*.t.sol'`
- Fork tests require `FORK_TEST_RPC_URL` environment variable
- Proposal tests are in `src/test/proposals/` and require fork environment
- Coverage reports generated in `coverage/` directory
- A specific test contract can be run using: `forge test -vvv --match-contract <contract>`
- Each test file should be focused on a specific contract function
- Within each test file, use the branching tree technique to organise tests according to different parameters and states. For example:

```solidity
contract SomethingTest {
    // given the contract is disabled
    //  [X] it reverts

    function test_givenContractIsDisabled_reverts() {
        // test code here
    }

    // when the amount is 0
    // [X] it reverts

    function test_whenAmountIsZero_reverts() {
        // test code here
    }

    // given the tick step is above 100%
    //  when the amount would result in the capacity being filled
    //    [ ] it moves to a new tick
    //    [ ] it resets capacity for the new tick
    //    [ ] it emits a Bid event

    function test_givenTickStepIsAboveOneHundred_whenCapacityIsFilled() {
        // test code here
    }

    //  when the amount would result in the capacity NOT being filled
    //    [ ] it does not move to the new tick
    //    [ ] it does not reset capacity for the tick
    //    [ ] it emits a Bid event

    function test_givenTickStepIsAboveOneHundred_whenCapacityIsNotFilled() {
        // test code here
    }
}
```

- Pay attention to extreme and boundary values, such as the minimum and maximum, and write tests for these.
- Write fuzz tests for the range of acceptable values.
- Write fuzz tests for the range of unacceptable values.
- Create tests using different values for different parameters, so the interplay between them is heavily tested.
- Each function-focused test file should ideally inherit from a parent test contract for the particular contract being tested, e.g. `DepositRedemptionVaultTest` for `DepositRedemptionVault`. The parent test contract should contain setup functions, common assertions and helper functions.
- Parent test contracts should also define modifiers, e.g. `givenUserHasPosition`, that can establish a particular state that is commonly-used. Tests should utilise these modifiers to keep test code simple and focused.
- Assertions should have an informative message: e.g. `assertEq(true, true, "True should equal true")`

### Deployment

- Chain-specific env files: `.env.[chain]` (copy from `.env.deploy.example`)
- Deployment scripts in `src/scripts/deploy/`
- Saved deployments in `src/scripts/deploy/savedDeployments/`
- See `src/scripts/DEPLOY.md` and `src/scripts/DEPLOY_L2.md` for detailed steps

### Code Standards

- Solidity version: >= 0.8.24 (with some on 0.8.15 for historical reasons)
- Optimizer runs: 10,000 (except for some contracts that require specific runs to meet bytecode limits, see foundry.toml)
- Follow existing patterns for module/policy development
- Use Default Framework conventions for access control and state management
- Dependencies are installed using soldeer (`forge soldeer`) and kept in `dependencies/`
- Follow best-case practices for writing Solidity code, e.g. <https://dev.to/truongpx396/solidity-limitations-solutions-best-practices-and-gas-optimization-27cb>
- Running `forge build` will output the `forge` tool's linting output. Attempt to address those notes, warnings and errors.
- When completing a minor or major milestone and before any git commits, run the formatter: `pnpm run prettier`
- When completing a major milestone, the unit tests should pass: `pnpm run test:unit`
- Between milestones, run a build (`forge build`) and prettier (`pnpm run prettier`)
- Do not use `require()` for assertions. Instead, preference custom errors. Custom errors should be defined in the contract's parent interface (where available), or else in the contract itself.
- Do not revert with a blank message, use a custom error instead.
- Contracts should have a separate interface that is defined in a separate file, to allow for easy integration. All interfaces are MIT-licensed, and should avoid using internal types. Interfaces should also use NatSpec to define functions and types, and any expectations for implementation contracts.
- Contracts that implement interfaces should use the `@inheritdoc` NatSpec tag in function documentation to reference the parent interface's function.
- Function documentation should outline the behaviour of the function, including any conditions that would result in a revert.

### Access Control Pattern

- Policies request permissions via `requestPermissions()` function
- Kernel grants/revokes roles based on governance actions
- Use `onlyRole()` modifiers (or `onlyAdminRole()` etc if using the PolicyAdmin mix-in) for function access control

### Key Contracts to Understand

- `Kernel.sol` - Core governance and module/policy management
- `policies/Operator.sol` - Range-Bound Stability mechanism
- `policies/Heart.sol` - Auction system for stability operations
- `modules/TRSRY/` - Treasury operations and asset management
- `policies/cooler/MonoCooler.sol` - Primary lending protocol

### Common Patterns

- Modules inherit from `Module` base contract with keycode and version
- Policies inherit from `Policy` base contract with dependency/permission requests
- Use the `IVersioned` interface to standardise versioning of Modules and Policies
- Contracts that implement interfaces should implement the `supportsInterface()` function from ERC165
- Policies can use the `PolicyEnabler` mix-in to inherit common functionality around enabling/disabling contracts. Periphery contracts can use `PeripheryEnabler`.
- Error handling with custom errors following naming conventions
- When planning a new feature, to write the plan to disk in Markdown format, and always include a TODO list that can be checked off. When working on that new feature, regularly update the status in the task list of that feature plan.

### Imports

- When importing dependencies, use a versioned import path, e.g. `@solmate-6.2.0` instead of `solmate`. Refer to remappings.txt for the aliases.
- Imports must be at the top of the file, below the license and pragma.
- Imports should be grouped under headings of: interface, libraries, contracts
- Within each grouping, keep the imports sorted by the dependency path
- Do NOT do global imports, `import "src/Kernel.sol"`
- Instead, import individual contracts from a file, e.g. `import {Kernel} from "src/Kernel.sol"`
- The codebase has different approaches to imports. Ignore those and implement the prescribed approach.

### Solidity Math Guidelines

When working with Solidity code involving mathematical operations, follow these principles:

#### Core Principles

1. **No Floating-Point**: Solidity has no floating-point numbers - all numbers are integers.

2. **Decimal Representation**:
    - Decimal numbers are represented as integers with an associated decimal scale
    - Example: 1.0 with 18 decimals = 1000000000000000000 (1e18)
    - Always track and document the decimal scale of each variable

3. **Multiplication & Division Order**:
    - When multiplying/dividing numbers with different scales, order matters
    - General pattern: multiply first, then divide to maintain precision
    - Example: `result = a * scaleB / scaleC` where result has scaleB decimals
    - Always calculate and verify the resulting decimal scale
    - Phantom overflows can occur, where `a * scaleB` (from the example above) overflows the maximum value of `uint256`. For that reason, it is advisable to use the FullMath library in `src/libraries/FullMath.sol`.

4. **Rounding Behavior**:
    - Solidity rounds DOWN by default (floor division)
    - Use `mulDiv()` for standard rounding down
    - Use `mulDivUp()` when rounding up is needed
    - Be explicit about rounding direction in comments
    - Suggested approach: when involving values going to an external user, round down. This favours the protocol.
    - Ask the developer for desired behaviour

5. **Precision Loss**:
    - Be aware of precision loss in division operations
    - Consider the order of operations to maximize precision
    - Document any intentional precision trade-offs

#### When Writing Code

- Always comment the decimal scale of variables involved in calculations
- Show the arithmetic reasoning: input scales → operation → output scale
- Use descriptive variable names that hint at their scale when possible
- Explicitly state rounding behavior when it matters

#### When Writing Tests

- Document the mathematical working in comments above each assertion
- Show step-by-step calculation with decimal scales
- Include the expected value derivation
- Example format:

    ```solidity
    // deposit = 5e18 (18 decimals)
    // ohmScale = 1e9 (9 decimals)
    // price = 2e18 (18 decimals)
    // Expected: (5e18 * 1e9) / 2e18 = 5e27 / 2e18 = 2.5e9 (9 decimals)
    // Rounds down to 2e9
    assertEq(convertibleAmount, 2e9, "Convertible amount does not equal 2e9");
    ```

#### When Reviewing Code

- Verify decimal scale consistency across operations
- Check for potential overflow/underflow
- Validate that the order of operations preserves precision
- Confirm rounding behavior matches requirements
- Look for off-by-one errors due to rounding

#### Common Patterns - Math

**Converting between scales:**

```solidity
// Convert from 18 decimals to 9 decimals
value9 = value18 / 1e9;

// Convert from 9 decimals to 18 decimals
value18 = value9 * 1e9;
```

**Price calculations:**

```solidity
// amount (18 dec) * price (18 dec) / 1e18 = value (18 dec)
value = amount.mulDiv(price, 1e18);
```

**Proportion calculations:**

```solidity
// part (X dec) * total (Y dec) / denominator (Z dec) = result (X+Y-Z dec)
result = part.mulDiv(total, denominator);
```

Always think through the decimal arithmetic step-by-step and make the reasoning explicit in your responses.

## Tools

### Code Reviews with CodeRabbit

If CodeRabbit is installed, run it as a way to review your code. Run the command: `coderabbit -h` for details on commands available.

In general, I want you to run coderabbit with the `--prompt-only` flag.

To review uncommitted changes (this is what we'll use most of the time) run: `coderabbit --prompt-only -t uncommitted`.

It is more useful if the review is performed against a base branch, using the `--base <branchName>` flag.

IMPORTANT: When running CodeRabbit to review code changes, don't run it more than 3 times in a given set of changes.

### Linting

The following command will get a list of linting rules that have errors/warnings/notes:

```bash
forge lint 2>&1 | grep -E "^warning\[|^note\[" | grep -v "src/test" | sed 's/^.*\[\([^]]*\)\].*/\1/' | sort | uniq | cat
```

The following command will report on the linting rules that have errors/warnings/notes and the affected files:

```bash
forge lint 2>&1 | sed -n '
/^note\[/ { s/^note\[\([^]]*\)\].*/NOTE:\1/p; h; d; }
/^warning\[/ { s/^warning\[\([^]]*\)\].*/WARNING:\1/p; h; d; }
/^error\[/ { s/^error\[\([^]]*\)\].*/ERROR:\1/p; h; d; }
/^  --> / { s/^  --> \([^:]*\):.*/\1/p; }
' | awk '
/^(NOTE|WARNING|ERROR):/ { rule = $0; next }
rule { print rule "|" $0 }
' | sort -u | awk -F'|' '
{
    if ($1 != last) {
        if (last) print "";
        print $1;
        last = $1
    }
    print "  " $2
}'
```

### Git Worktrees

Git worktrees allow multiple branches to be checked out simultaneously without stashing or committing changes. This is useful for:

- Working on multiple features concurrently
- Testing code on different branches
- Reviewing PRs while preserving current work

Common commands:

- `git worktree list` - Show all worktrees
- `git worktree add <path> <branch>` - Create new worktree for a branch
- `git worktree remove <path>` - Delete a worktree
