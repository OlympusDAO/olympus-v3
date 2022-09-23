# Bophades Coding Standard

The following establishes a coding standard for the Olympus v3/Bophades repo.

- External/public functions and variables are `lowerCamelCase`
    - ex. function `deposit()`
    - ex. variable `totalDebt`
- Internal/private functions and variables are `_prefixed` and `lowerCamelCase`
    - ex. `_checkApproval()`
- Contract names are `UpperCamelCase`
    - ex. `OlympusTreasury`
- Function arguments are `suffixed_`
    - `_issueReward(address to_)`
- Module-specific functions are always `UPPERCASE`
    - ex. `KEYCODE()`
- Regular Comments use `//`
    - `// Regular comment hurr durr`
- NatSpec comments use `///`
    - `/// @notice Natspec comment`
- Custom errors defined outside of contract (makes it referable for testing)
- Errors defined in modules must be suffixed by module's respective keycode
    - ex. `TRSRY_NotApproved(...)`
    - Policies have no such restriction


## Principles (NOT HARD RULES)
- Aim for clear and succinct code
- Explicit over implicit
- Write code PRIMARILY for humans, not machines
- Comment on WHY, not WHAT. Code should be able to explain "what".
- Aim to write code that is self-documenting
- Meaning clear function names and variables
- Aim for gas-efficiency with above constraints