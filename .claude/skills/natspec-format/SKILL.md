---
description: Guide for writing and formatting NatSpec documentation in the Olympus V3 codebase
---

# NatSpec Formatting Guide

This guide covers the standards for writing and formatting NatSpec documentation in the Olympus V3 codebase.

## Overview

NatSpec (Ethereum Natural Language Specification) is the format for documenting Solidity code. Proper NatSpec documentation ensures code is self-documenting and improves developer experience.

**When to use this guide:**

- Writing new functions, structs, events, errors, or modifiers
- Reviewing code for documentation completeness
- Formatting existing NatSpec comments to match project standards

## NatSpec Format Standards

### Core Formatting Rules

1. **Blank line separator** - A `///` line between `@notice`/`@dev` and `@param`/`@return` tags
2. **Tab after tag** - The tag name (`@notice`, `@dev`, `@param`, `@return`) is followed by a tab
3. **Tab-aligned descriptions** - Align descriptions at the first tab stop after the longest parameter name in the list
4. **Tab-aligned returns** - For `@return`: `@return<TAB>type<TAB>description`
5. **All parameters documented** - Every parameter must have a `@param` entry
6. **Multi-line `@dev`** - Continue multi-line `@dev` comments on separate `/// @dev` lines
7. **Trailing underscore** - Parameters with trailing underscore (e.g., `params_`)

### Target Format Example

```solidity
/// @notice Returns the average of prices that do not deviate from a benchmark
/// @dev    Calculates benchmark (median for 3+ prices, average for 2), excludes
/// @dev    outliers, and returns average of remaining prices.
///
/// @param  prices_         Array of prices from multiple feeds
/// @param  aLongerParam_   Encoded DeviationParams
/// @return uint256         The resolved price (average of non-deviating prices)
function resolvePrice(
    uint256[] memory prices_,
    bytes calldata aLongerParam_
) external pure returns (uint256) {
    // implementation
}
```

## Function Documentation

Every external and public function must have NatSpec documentation.

### Template

```solidity
/// @notice Brief description of what the function does
/// @dev    Implementation details or caveats
/// @dev    Additional dev notes if needed
///
/// @param  paramOne_    Description of first parameter
/// @param  paramTwo_    Description of second parameter
/// @return bool         Description of return value
function exampleFunction(uint256 paramOne_, address paramTwo_) external returns (bool) {
    // implementation
}
```

### Function Guidelines

- **`@notice`**: User-facing description. Keep it clear and concise. Describe what, not how.
- **`@dev`**: Implementation details, caveats, or technical notes. Use as many lines as needed.
- **`@inheritdoc`**: Use when implementing functions from interfaces or parent contracts. Place as the first tag. This references the parent documentation and reduces duplication.
- **`@param`**: Required for every parameter. Describe what the parameter represents.
- **`@return`**: Required for non-void functions. Format: `@return<TAB>type<TAB>description`

### Implementing Interface Functions

When implementing a function defined in an interface, use `@inheritdoc` to reference the parent documentation:

```solidity
/// @inheritdoc ISimplePriceFeedStrategy
/// @dev        List here any particular details about the implementation
function getAveragePriceExcludingDeviations(
    uint256[] memory prices_,
    bytes memory params_
) public pure returns (uint256 price) {
    // implementation
}
```

**Benefits of `@inheritdoc`:**

- Reduces documentation duplication between interface and implementation
- Ensures consistency - changes to interface docs automatically propagate
- Keeps implementation NatSpec focused on implementation-specific details only
- Tools like Solidity doc generators will merge parent and child documentation

### Function Examples

**GOOD - Well-documented function:**

```solidity
/// @notice Transfers tokens from caller to recipient
/// @dev    Caller must have sufficient allowance. Emits Transfer event.
///
/// @param  to_      Address to receive tokens
/// @param  amount_  Number of tokens to transfer
/// @return bool     True if transfer succeeded
function transfer(address to_, uint256 amount_) external returns (bool) {
    // implementation
}
```

**BAD - Missing documentation:**

```solidity
/// @notice Transfers tokens
function transfer(address to_, uint256 amount_) external returns (bool) {
    // implementation
}
```

**BAD - No blank line separator:**

```solidity
/// @notice Transfers tokens from caller to recipient
/// @param  to_      Address to receive tokens
/// @param  amount_  Number of tokens to transfer
function transfer(address to_, uint256 amount_) external {
    // implementation
}
```

## Struct Documentation

Structs document their fields at the struct level using `@param` tags, not inline.

### Struct Template

```solidity
/// @notice Brief description of the struct
///
/// @param  fieldOne    Description of field one
/// @param  fieldTwo    Description of field two
struct ExampleStruct {
    uint256 fieldOne;
    address fieldTwo;
}
```

### Struct Examples

**GOOD - Struct with field documentation:**

```solidity
/// @notice Represents a position in the deposit facility
///
/// @param  owner              Address that owns the position
/// @param  amount             Deposit amount
/// @param  conversionPrice    Price at conversion
struct DepositPosition {
    address owner;
    uint256 amount;
    uint256 conversionPrice;
}
```

**BAD - Inline field comments:**

```solidity
/// @notice Represents a position in the deposit facility
struct DepositPosition {
    /// @notice Address that owns the position
    address owner;
    /// @notice Deposit amount
    uint256 amount;
}
```

## Event Documentation

Events document when and why they are emitted.

### Event Template

```solidity
/// @notice Description of when this event is emitted
///
/// @param  paramOne_    Description of first indexed parameter
/// @param  paramTwo_    Description of second parameter
event ExampleEvent(address indexed paramOne_, uint256 paramTwo_);
```

### Event Examples

**GOOD - Well-documented event:**

```solidity
/// @notice Emitted when a new position is created
///
/// @param  owner     Address that owns the new position
/// @param  position  ID of the newly created position
event PositionCreated(address indexed owner, uint256 position);
```

## Error Documentation

Custom errors document when and why they are thrown.

### Error Template

```solidity
/// @notice Description of when this error is thrown
///
/// @param  contextParam    Description of the context parameter
error ExampleError(address contextParam);
```

### Error Examples

**GOOD - Well-documented error:**

```solidity
/// @notice Thrown when an invalid price is provided
///
/// @param  price_    The invalid price that caused the revert
error InvalidPrice(uint256 price_);
```

## Modifier Documentation

Modifiers document what they check or enforce.

### Modifier Template

```solidity
/// @notice Description of what the modifier checks
/// @dev    Any important implementation details
///
/// @param  param_    Description of modifier parameter
modifier exampleModifier(uint256 param_) {
    _;
}
```

### Modifier Examples

**GOOD - Well-documented modifier:**

```solidity
/// @notice Ensures the caller is the contract admin
/// @dev    Uses the ROLES module for access control
///
modifier onlyAdmin() {
    _;
}
```

## Common Anti-Patterns

| Issue                     | BAD                                        | GOOD                                             |
| ------------------------- | ------------------------------------------ | ------------------------------------------------ |
| Missing blank line        | `/// @notice ...` followed by `/// @param` | Add `///` separator line                         |
| Missing tabs              | `/// @param prices_ Array...`              | `/// @param<TAB>prices_<TAB>Array...`            |
| Return format incomplete  | `/// @return The resolved price`           | `/// @return<TAB>uint256<TAB>The resolved price` |
| Undocumented parameters   | No `@param` for some parameters            | All parameters documented                        |
| Struct fields inline      | Inline `/// @notice` on each field         | Document fields as `@param` at struct level      |
| Multi-line on single line | Very long `/// @notice` line               | Break across multiple `/// @notice` lines        |
| Missing @inheritdoc       | Duplicating interface docs               | Use `/// @inheritdoc InterfaceName`              |

## GOOD vs BAD Examples

### Function Example

**GOOD:**

```solidity
/// @notice Calculates the average price from multiple feeds
/// @dev    Excludes prices that deviate more than the threshold
/// @dev    from the median. Returns 0 if no valid prices exist.
///
/// @param  prices_       Array of prices from multiple feeds
/// @param  deviationBps_ Maximum allowed deviation in basis points
/// @return uint256       The average of non-deviating prices
function getAveragePrice(
    uint256[] memory prices_,
    uint256 deviationBps_
) external pure returns (uint256) {
    // implementation
}
```

**BAD:**

```solidity
/// @notice Calculates the average price from multiple feeds. Excludes prices that deviate more than the threshold from the median. Returns 0 if no valid prices exist.
/// @param prices_ Array of prices from multiple feeds
/// @param deviationBps_ Maximum allowed deviation in basis points
/// @return The average of non-deviating prices
function getAveragePrice(
    uint256[] memory prices_,
    uint256 deviationBps_
) external pure returns (uint256) {
    // implementation
}
```

### Struct Example

**GOOD:**

```solidity
/// @notice Configuration for deviation-based price resolution
///
/// @param  deviationBps    Maximum deviation threshold in basis points
/// @param  minSources      Minimum number of price sources required
/// @param  maxSources      Maximum number of price sources to use
struct DeviationConfig {
    uint256 deviationBps;
    uint256 minSources;
    uint256 maxSources;
}
```

**BAD:**

```solidity
/// @notice Configuration for deviation-based price resolution
struct DeviationConfig {
    /// @notice Maximum deviation threshold in basis points
    uint256 deviationBps_;
    uint256 minSources_;
    // Missing field documentation
}
```

## Quick Reference

| Element                | Tag             | Required          | Format                                      |
| ---------------------- | --------------- | ----------------- | ------------------------------------------- |
| Function description   | `@notice`       | Yes               | `/// @notice<TAB>description`               |
| Implementation details | `@dev`          | As needed         | `/// @dev<TAB>description`                  |
| Parameters             | `@param`        | Yes (all)         | `/// @param<TAB>paramName_<TAB>description` |
| Return values          | `@return`       | Yes (if non-void) | `/// @return<TAB>type<TAB>description`      |
| Events                 | (use `@notice`) | Yes               | `/// @notice<TAB>when emitted`              |
| Struct fields          | `@param`        | Yes (all)         | `/// @param<TAB>fieldName<TAB>description`  |
| Error params           | `@param`        | Yes (all)         | `/// @param<TAB>paramName_<TAB>description` |

## Checklist

When writing NatSpec documentation:

- [ ] `@notice` tag present with clear user-facing description
- [ ] `@dev` tags for implementation details (if needed)
- [ ] Blank `///` line before `@param`/`@return` tags
- [ ] All parameters documented with `@param`
- [ ] Return values documented with `@return` (format: type + description)
- [ ] Descriptions tab-aligned based on longest parameter name
- [ ] Parameter names use trailing underscore (e.g., `amount_`)
- [ ] Struct fields documented at struct level, not inline

## Running Formatter

After writing or updating NatSpec documentation, run the formatter:

```bash
# Format code (includes NatSpec comments)
pnpm run prettier
```

This will ensure consistent formatting across the codebase.
