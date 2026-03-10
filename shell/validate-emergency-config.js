#!/usr/bin/env node

/**
 * Emergency Config Validation Script
 *
 * Validates the emergency-config.json against:
 * 1. JSON Schema validation
 * 2. All contracts in contractRegistry have component definitions
 * 3. All ABI references in calls exist in the ABIs file
 * 4. All chains in availableOn exist in chains
 * 5. No duplicate component IDs
 * 6. Ethereum address format validation
 *
 * Usage: node shell/validate-emergency-config.js
 *
 * Exit codes:
 *   0 - All validations passed
 *   1 - Validation errors found
 */

const fs = require("fs");
const path = require("path");
const Ajv = require("ajv");

// ANSI colors for terminal output
const colors = {
  reset: "\x1b[0m",
  red: "\x1b[31m",
  green: "\x1b[32m",
  yellow: "\x1b[33m",
  blue: "\x1b[34m",
};

const log = {
  error: (msg) => console.error(`${colors.red}ERROR:${colors.reset} ${msg}`),
  warn: (msg) => console.warn(`${colors.yellow}WARN:${colors.reset} ${msg}`),
  success: (msg) => console.log(`${colors.green}OK:${colors.reset} ${msg}`),
  info: (msg) => console.log(`${colors.blue}INFO:${colors.reset} ${msg}`),
};

// Paths
const CONFIG_DIR = path.join(
  __dirname,
  "..",
  "documentation",
  "emergency"
);
const CONFIG_PATH = path.join(CONFIG_DIR, "emergency-config.json");
const SCHEMA_PATH = path.join(CONFIG_DIR, "emergency-config.schema.json");
const ABIS_PATH = path.join(CONFIG_DIR, "emergency-abis.json");

// Ethereum address regex
const ETH_ADDRESS_REGEX = /^0x[a-fA-F0-9]{40}$/;

// Validation results
let errors = [];
let warnings = [];

/**
 * Load and parse JSON file
 */
function loadJson(filePath, name) {
  try {
    const content = fs.readFileSync(filePath, "utf8");
    return JSON.parse(content);
  } catch (err) {
    if (err.code === "ENOENT") {
      errors.push(`${name} file not found: ${filePath}`);
    } else if (err instanceof SyntaxError) {
      errors.push(`${name} contains invalid JSON: ${err.message}`);
    } else {
      errors.push(`Failed to load ${name}: ${err.message}`);
    }
    return null;
  }
}

/**
 * Validate Ethereum address format
 */
function isValidAddress(address) {
  return ETH_ADDRESS_REGEX.test(address);
}

/**
 * Validate semver format
 */
function isValidSemver(version) {
  return /^\d+\.\d+\.\d+$/.test(version);
}

/**
 * Validate ISO 8601 date format
 */
function isValidISODate(dateStr) {
  const date = new Date(dateStr);
  return !isNaN(date.getTime());
}

/**
 * Main validation function
 */
function validate() {
  console.log("\n=== Emergency Config Validation ===\n");

  // Load files
  const config = loadJson(CONFIG_PATH, "emergency-config.json");
  const schema = loadJson(SCHEMA_PATH, "emergency-config.schema.json");
  const abis = loadJson(ABIS_PATH, "emergency-abis.json");

  if (!config || !schema || !abis) {
    return false;
  }

  log.info("All required files loaded successfully");

  // 0. Validate against JSON schema
  // Remove $schema property to avoid meta-schema validation issues
  const { "$schema": _schema, ...schemaWithoutMeta } = schema;
  const ajv = new Ajv({ validateFormats: false });
  const validate = ajv.compile(schemaWithoutMeta);
  const valid = validate(config);

  if (!valid) {
    errors.push("JSON Schema validation failed:");
    validate.errors.forEach((err) => {
      errors.push(`  - ${err.instancePath} ${err.message}`);
    });
    return false;
  }

  log.success("JSON Schema validation passed");

  // 1. Validate version format
  if (!isValidSemver(config.version)) {
    errors.push(`Invalid version format: "${config.version}" (expected semver like "1.0.0")`);
  } else {
    log.success(`Version format valid: ${config.version}`);
  }

  // 2. Validate lastUpdated date
  if (!isValidISODate(config.lastUpdated)) {
    errors.push(`Invalid lastUpdated date: "${config.lastUpdated}"`);
  } else {
    log.success(`Last updated date valid: ${config.lastUpdated}`);
  }

  // 3. Validate chains exist
  const chainNames = Object.keys(config.chains);
  if (chainNames.length === 0) {
    errors.push("No chains defined in configuration");
  } else {
    log.success(`Found ${chainNames.length} chains: ${chainNames.join(", ")}`);
  }

  // 4. Validate multisig addresses in each chain
  const errorsBeforeAddressValidation = errors.length;

  for (const [chainName, chainConfig] of Object.entries(config.chains)) {
    const { multisigs, contracts } = chainConfig;

    // Check multisig addresses
    if (multisigs) {
      for (const [msName, msAddr] of Object.entries(multisigs)) {
        if (!isValidAddress(msAddr)) {
          errors.push(`Invalid ${msName} multisig address in ${chainName}: "${msAddr}"`);
        }
      }
    }

    // Check contract addresses
    if (contracts) {
      for (const [contractName, contractAddr] of Object.entries(contracts)) {
        if (!isValidAddress(contractAddr)) {
          errors.push(`Invalid ${contractName} address in ${chainName}: "${contractAddr}"`);
        }
      }
    }
  }
  // 4b. Validate that chains with emergency-owned components have a non-zero emergency multisig
  const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
  for (const [chainName, chainConfig] of Object.entries(config.chains)) {
    const emergencyAddr = chainConfig.multisigs && chainConfig.multisigs.emergency;
    const hasEmergencyComponent = config.components.some(
      (c) => c.owner === "emergency" && c.availableOn.includes(chainName)
    );
    if (hasEmergencyComponent && (!emergencyAddr || emergencyAddr === ZERO_ADDRESS)) {
      errors.push(
        `Chain "${chainName}" has emergency-owned components but no valid emergency multisig address`
      );
    }
    if (emergencyAddr && emergencyAddr === ZERO_ADDRESS) {
      warnings.push(
        `Chain "${chainName}" has a zero-address emergency multisig — remove or replace it`
      );
    }
  }

  // Only log success if no address validation errors occurred
  if (errors.length === errorsBeforeAddressValidation) {
    log.success("All addresses validated");
  }

  // 5. Check for duplicate component IDs
  const componentIds = config.components.map((c) => c.id);
  const duplicateIds = componentIds.filter(
    (id, index) => componentIds.indexOf(id) !== index
  );
  if (duplicateIds.length > 0) {
    errors.push(`Duplicate component IDs found: ${duplicateIds.join(", ")}`);
  } else {
    log.success(`No duplicate component IDs (${componentIds.length} components)`);
  }

  // 6. Validate each component
  const abiKeys = Object.keys(abis);
  const contractsWithComponents = new Set();
  const errorsBeforeComponentValidation = errors.length;

  for (const component of config.components) {
    // Check availableOn chains exist
    for (const chainName of component.availableOn) {
      if (!config.chains[chainName]) {
        errors.push(
          `Component "${component.id}" references unknown chain: "${chainName}"`
        );
      }
    }

    // Check ABI references
    for (const call of component.calls) {
      if (!abiKeys.includes(call.abi)) {
        errors.push(
          `Component "${component.id}" references unknown ABI: "${call.abi}"`
        );
      }

      // Track which contracts have components
      const contractName = call.contractKey.split(".").pop();
      contractsWithComponents.add(contractName);
    }

    // Check owner is valid
    if (!["emergency", "dao"].includes(component.owner)) {
      errors.push(
        `Component "${component.id}" has invalid owner: "${component.owner}"`
      );
    }

    // Check severity is valid
    if (!["critical", "high", "medium", "low"].includes(component.severity)) {
      errors.push(
        `Component "${component.id}" has invalid severity: "${component.severity}"`
      );
    }

    // Check batchScript path exists if specified.
    // Note: batchScript is intentionally absent for contracts using IEnabler patterns
    // (PolicyEnabler, PeripheryEnabler, direct IEnabler) — these are disabled via
    // disable(bytes) directly and do not need a batch script.
    if (component.batchScript) {
      const scriptPath = path.join(__dirname, "..", component.batchScript);
      if (!fs.existsSync(scriptPath)) {
        errors.push(
          `Component "${component.id}" references non-existent batchScript: "${component.batchScript}"`
        );
      }
    }

    // Check for recommended fields (shutdownCriteria, postShutdownSteps)
    if (
      !component.shutdownCriteria ||
      !Array.isArray(component.shutdownCriteria) ||
      component.shutdownCriteria.length === 0
    ) {
      warnings.push(
        `Component "${component.id}" is missing shutdownCriteria — all other components include this field`
      );
    }
    if (
      !component.postShutdownSteps ||
      !Array.isArray(component.postShutdownSteps) ||
      component.postShutdownSteps.length === 0
    ) {
      warnings.push(
        `Component "${component.id}" is missing postShutdownSteps — all other components include this field`
      );
    }
  }

  // Only log success if no component validation errors occurred
  if (errors.length === errorsBeforeComponentValidation) {
    log.success("All component validations passed");
  }

  // 7. Check contractRegistry coverage
  const registryContracts = new Set(config.contractRegistry);

  for (const contractName of registryContracts) {
    if (!contractsWithComponents.has(contractName)) {
      // Some contracts may be covered indirectly via env key patterns
      // This is a warning, not an error
      warnings.push(
        `Contract "${contractName}" in registry has no direct component definition`
      );
    }
  }

  // 8. Check for contracts with components not in registry
  for (const contractName of contractsWithComponents) {
    if (!registryContracts.has(contractName)) {
      warnings.push(
        `Contract "${contractName}" has component but is not in contractRegistry`
      );
    }
  }

  // Print summary
  console.log("\n=== Validation Summary ===\n");

  if (warnings.length > 0) {
    console.log(`${colors.yellow}Warnings (${warnings.length}):${colors.reset}`);
    warnings.forEach((w) => console.log(`  - ${w}`));
    console.log("");
  }

  if (errors.length > 0) {
    console.log(`${colors.red}Errors (${errors.length}):${colors.reset}`);
    errors.forEach((e) => console.log(`  - ${e}`));
    console.log("");
    log.error("Validation FAILED");
    return false;
  }

  log.success("Validation PASSED");
  return true;
}

// Run validation
const success = validate();
process.exit(success ? 0 : 1);
