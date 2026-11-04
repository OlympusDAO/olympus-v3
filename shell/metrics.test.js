const assert = require("node:assert/strict");
const {spawnSync} = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const {test} = require("node:test");

const script = path.join(__dirname, "metrics.js");

function project(t, files) {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), "olympus-metrics-test-"));
    t.after(() => fs.rmSync(root, {recursive: true, force: true}));
    for (const [name, content] of Object.entries(files)) {
        fs.mkdirSync(path.dirname(path.join(root, name)), {recursive: true});
        fs.writeFileSync(path.join(root, name), content);
    }
    return root;
}

function run(root, args) {
    return spawnSync(process.execPath, [script, ...args], {cwd: root, encoding: "utf8"});
}

test("normalizes real headers without consuming interfaces, strings, or function types", (t) => {
    const source = [
        "// SPDX-License-Identifier: MIT",
        "pragma solidity >=0.8.0;",
        "interface IQuote {",
        "    function quote(",
        "        uint256 amount",
        "    ) external view returns (uint256);",
        "    function rate() external view returns (uint256);",
        "}",
        "contract Example {",
        '    string constant TEXT = ".functions[?(@.name == test)]";',
        '    string constant URL = "https://example.org/*text*/";',
        "    function(uint256) external returns (uint256) callback;",
        "    function deposit(",
        "        uint256 amount",
        "    ) external /* header comment */ returns (uint256) {",
        "        // Function body remains intact.",
        "        return amount;",
        "    }",
        "    function read() external pure returns (uint256 out) {",
        "        assembly { out := 1 }",
        "    }",
        "}",
        "",
    ].join("\n");
    const root = project(t, {"src/Example.sol": source});
    const result = run(root, ["src/Example.sol"]);
    assert.equal(result.status, 0, result.stderr);
    // 22 physical lines minus 2 comments and 4 wrapped header lines = 16.
    // The trailing empty array entry terminates line 22; it adds no blank line.
    assert.match(result.stdout, /1 files, 16 nSLOC/, "Each interface header must count once");
    const html = fs.readFileSync(path.join(root, "solidity-metrics.html"), "utf8");
    assert.match(html, /src\/Example\.sol/, "Report must identify the scoped file");
    assert.match(html, /function headers normalized/, "Report must explain its counting method");
    assert.equal(
        fs.readFileSync(path.join(root, "src/Example.sol"), "utf8"),
        source,
        "Source must stay unchanged",
    );
});

test("uses only scope files, deduplicates glob overlap, and applies exclusions", (t) => {
    const source = "pragma solidity >=0.8.0;\ncontract Example {}\n";
    const root = project(t, {
        "src/One.sol": source,
        "src/Two.sol": source,
        "src/Excluded.sol": source,
        "src/Outside.sol": source,
        "scope.txt": "# Audit scope\nsrc/One.sol\nsrc/Two.sol\nsrc/One.sol\n",
    });
    const result = run(root, [
        "--scope",
        "scope.txt",
        "src/{One,Excluded}.sol",
        "--exclude=src/Excluded.sol",
        "--output",
        "audit/report.html",
    ]);
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /2 files, 4 nSLOC/, "Scope must contain two unique files");
    const html = fs.readFileSync(path.join(root, "audit/report.html"), "utf8");
    assert.match(html, /src\/One\.sol/);
    assert.match(html, /src\/Two\.sol/);
    assert.doesNotMatch(
        html,
        /src\/(Outside|Excluded)\.sol/,
        "Out-of-scope files must not enter the report",
    );
});

test("rejects invalid scope or syntax without replacing an existing report", (t) => {
    const root = project(t, {
        "src/Good.sol": "pragma solidity >=0.8.0;\ncontract Good {}\n",
        "src/Bad.sol": "contract { broken",
        "solidity-metrics.html": "existing report",
    });
    for (const [args, expected] of [
        [[], /Specify Solidity files/],
        [["src/Missing*.sol"], /No Solidity files match/],
        [["../Outside.sol"], /inside the current directory/],
        [["src/Bad.sol"], /src\/Bad\.sol/],
        [["src/Good.sol", "--output", "src/Good.sol"], /HTML/],
    ]) {
        const result = run(root, args);
        assert.notEqual(result.status, 0, "Invalid input must fail: " + JSON.stringify(args));
        assert.match(result.stderr, expected, "Error must explain the failure");
        assert.equal(
            fs.readFileSync(path.join(root, "solidity-metrics.html"), "utf8"),
            "existing report",
            "Failure must preserve the existing report",
        );
    }
});
