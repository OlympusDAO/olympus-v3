#!/usr/bin/env node
// SPDX-License-Identifier: Apache-2.0
// Ported and modified from OpenAI's bundled skill-creator/scripts/quick_validate.py.
// Upstream: https://github.com/openai/skills/tree/main/skills/.system/skill-creator
// Bundled source SHA-256: ee6dba90f44d37171c5a6edb8095979c54919ff6822c1a907afca2e78c48738c
// Changes: Node.js filesystem/CLI handling and yaml parsing. See LICENSES/Apache-2.0.txt.
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const {parseDocument} = require("yaml");

function validateSkill(skillPath) {
    const skillFile = path.join(skillPath, "SKILL.md");
    if (!fs.existsSync(skillFile)) return [false, "SKILL.md not found"];

    // Python's read_text() normalizes platform line endings before validation.
    const content = fs.readFileSync(skillFile, "utf8").replace(/\r\n?/g, "\n");
    if (!content.startsWith("---")) return [false, "No YAML frontmatter found"];

    const match = /^---\n([\s\S]*?)\n---/.exec(content);
    if (!match) return [false, "Invalid frontmatter format"];

    let frontmatter;
    try {
        // Match safe_load's YAML 1.1 scalars and last-key-wins duplicate handling.
        const document = parseDocument(match[1], {version: "1.1", uniqueKeys: false});
        const problem = document.errors[0] ?? document.warnings[0];
        if (problem) return [false, `Invalid YAML in frontmatter: ${problem.message}`];
        frontmatter = document.toJS();
    } catch (error) {
        return [false, `Invalid YAML in frontmatter: ${error.message}`];
    }
    if (
        frontmatter === null ||
        typeof frontmatter !== "object" ||
        Object.getPrototypeOf(frontmatter) !== Object.prototype
    ) {
        return [false, "Frontmatter must be a YAML dictionary"];
    }

    const allowed = ["name", "description", "license", "allowed-tools", "metadata"];
    const unexpected = Object.keys(frontmatter).filter((key) => !allowed.includes(key));
    if (unexpected.length) {
        return [
            false,
            `Unexpected key(s) in SKILL.md frontmatter: ${unexpected.sort().join(", ")}. ` +
                `Allowed properties are: ${allowed.sort().join(", ")}`,
        ];
    }
    if (!Object.hasOwn(frontmatter, "name")) return [false, "Missing 'name' in frontmatter"];
    if (!Object.hasOwn(frontmatter, "description")) {
        return [false, "Missing 'description' in frontmatter"];
    }

    if (typeof frontmatter.name !== "string") return [false, "Name must be a string"];
    const name = frontmatter.name.trim();
    if (name) {
        if (!/^[a-z0-9-]+$/.test(name)) {
            return [
                false,
                `Name '${name}' should be hyphen-case (lowercase letters, digits, and hyphens only)`,
            ];
        }
        if (name.startsWith("-") || name.endsWith("-") || name.includes("--")) {
            return [
                false,
                `Name '${name}' cannot start/end with hyphen or contain consecutive hyphens`,
            ];
        }
        if (name.length > 64) {
            return [
                false,
                `Name is too long (${name.length} characters). Maximum is 64 characters.`,
            ];
        }
    }

    if (typeof frontmatter.description !== "string") return [false, "Description must be a string"];
    const description = frontmatter.description.trim();
    if (description.startsWith("[TODO:")) {
        return [false, "Description contains an unfinished TODO placeholder"];
    }
    if (description) {
        if (description.includes("<") || description.includes(">")) {
            return [false, "Description cannot contain angle brackets (< or >)"];
        }
        const length = [...description].length;
        if (length > 1024) {
            return [
                false,
                `Description is too long (${length} characters). Maximum is 1024 characters.`,
            ];
        }
    }

    let fenceMarker = null;
    let fenceLength = 0;
    for (const line of content.slice(match[0].length).split("\n")) {
        const fence = /^[ \t]*(?:(?:[-+*]|\d+[.)])[ \t]+)?(`{3,}|~{3,})(.*)$/.exec(line);
        if (fence) {
            const marker = fence[1];
            if (fenceMarker === null) {
                fenceMarker = marker[0];
                fenceLength = marker.length;
            } else if (
                marker[0] === fenceMarker &&
                marker.length >= fenceLength &&
                !fence[2].trim()
            ) {
                fenceMarker = null;
                fenceLength = 0;
            }
            continue;
        }
        if (fenceMarker === null && /^[ ]{0,3}\[TODO:[^\n]*\][ \t]*$/.test(line)) {
            return [false, "Skill instructions contain an unfinished TODO placeholder"];
        }
    }
    return [true, "Skill is valid!"];
}

if (require.main === module) {
    if (process.argv.length !== 3) {
        console.error("Usage: node shell/validate-skill.js <skill_directory>");
        process.exitCode = 1;
    } else {
        try {
            const [valid, message] = validateSkill(process.argv[2]);
            console.log(message);
            process.exitCode = valid ? 0 : 1;
        } catch (error) {
            console.error(error.message);
            process.exitCode = 1;
        }
    }
}

module.exports = {validateSkill};
