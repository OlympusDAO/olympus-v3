const assert = require("node:assert/strict");
const {spawnSync} = require("node:child_process");
const {mkdirSync, mkdtempSync, rmSync, writeFileSync} = require("node:fs");
const {tmpdir} = require("node:os");
const {dirname, join} = require("node:path");
const {test} = require("node:test");

const fixture = "src/test/example/fixtures/Handler.sol";

function runFixtureLint(t, sources) {
    const root = mkdtempSync(join(tmpdir(), "olympus-fixture-counters-"));
    t.after(() => rmSync(root, {recursive: true, force: true}));
    for (const [file, source] of Object.entries(sources)) {
        const destination = join(root, file);
        mkdirSync(dirname(destination), {recursive: true});
        writeFileSync(destination, source);
    }

    const result = spawnSync(process.execPath, [join(__dirname, "lint-fixture-counters.js")], {
        cwd: root,
        encoding: "utf8",
    });
    assert.equal(result.status, 0, result.stderr);
    return result.stderr.trim();
}

test("warns on an unread fixture counter while allowing observed counters and production state", (t) => {
    const sources = {
        [fixture]: `contract Handler {
    uint256 public failedExecutions;
    uint256 public measuredExecutions;
    uint256 public indirectExecutions;
    uint256 internal readInBody;

    function record() external {
        // failedExecutions was intended for an assertion.
        ++failedExecutions;
        failedExecutions += 2;
        measuredExecutions++;
        indirectExecutions = 3;
        ++readInBody;
        require(readInBody < 10);
    }
}`,
        "src/test/example/Handler.t.sol": `import {Handler} from "./fixtures/Handler.sol";
contract HandlerTest {
    function testReadsCounter(Handler handler) external view returns (uint256) {
        return handler.measuredExecutions();
    }
    function testReadsBySignature(Handler handler) external view {
        (bool success,) = address(handler).staticcall(abi.encodeWithSignature("indirectExecutions()"));
        require(success);
    }
}`,
        "src/Production.sol": `contract Production {
    uint256 public actions;
    function record() external { ++actions; }
}`,
    };
    assert.equal(
        runFixtureLint(t, sources),
        fixture + ":2: warning[write-only-fixture-counter]: failedExecutions",
    );
});

test("checks fixture counters when a for loop has no update expression", (t) => {
    const warnings = runFixtureLint(t, {
        [fixture]: `contract Handler {
    uint256 public calls;
    function record() external {
        for (uint256 i; i < 1;) {
            ++calls;
            ++i;
        }
    }
}`,
    });
    assert.equal(warnings, fixture + ":2: warning[write-only-fixture-counter]: calls");
});

test("counts tuple assignment targets as writes and right-hand values as reads", (t) => {
    const warnings = runFixtureLint(t, {
        [fixture]: `contract Handler {
    uint256 public calls;
    uint256 public observed;
    function record() external {
        ++calls;
        ++observed;
        (calls, observed) = (observed, 0);
    }
}`,
    });
    assert.equal(warnings, fixture + ":2: warning[write-only-fixture-counter]: calls");
});

test("counts compound assignment targets as writes and explicit right-hand values as reads", (t) => {
    const warnings = runFixtureLint(t, {
        [fixture]: `contract Handler {
    uint256 public calls;
    uint256 public observed;
    function record() external {
        ++calls;
        calls %= 10;
        ++observed;
        observed = observed % 10;
    }
}`,
    });
    assert.equal(warnings, fixture + ":2: warning[write-only-fixture-counter]: calls");
});

test("counts delete as a write and an explicit return as a read", (t) => {
    const warnings = runFixtureLint(t, {
        [fixture]: `contract Handler {
    uint256 public discarded;
    uint256 public observed;
    function record() external returns (uint256) {
        ++discarded;
        delete discarded;
        ++observed;
        delete observed;
        return observed;
    }
}`,
    });
    assert.equal(warnings, fixture + ":2: warning[write-only-fixture-counter]: discarded");
});

test("ignores unrelated function declarations and recognizes a fixture getter call", (t) => {
    const warnings = runFixtureLint(t, {
        [fixture]: `contract Handler {
    uint256 public discarded;
    uint256 public observed;
    function record() external { ++discarded; ++observed; }
}`,
        "src/test/example/Handler.t.sol": `import {Handler} from "./fixtures/Handler.sol";
contract HandlerTest {
    function discarded() external pure returns (uint256) { return 0; }
    function testCounter(Handler handler) external view returns (uint256) { return handler.observed(); }
}`,
    });
    assert.equal(warnings, fixture + ":2: warning[write-only-fixture-counter]: discarded");
});

test("checks same-named private counters in their declaring contracts", (t) => {
    const warnings = runFixtureLint(t, {
        [fixture]: `contract Handler {
    uint256 private calls;
    function record() external { ++calls; }
}
contract ObservedHandler {
    uint256 private calls;
    function record() external { ++calls; }
    function getCalls() external view returns (uint256) { return calls; }
}`,
        "src/test/example/fixtures/ExternalHandler.sol": `contract ExternalHandler {
    uint256 private calls;
    function record() external { ++calls; }
}`,
    });
    assert.equal(
        warnings,
        [
            "src/test/example/fixtures/ExternalHandler.sol:2: warning[write-only-fixture-counter]: calls",
            fixture + ":2: warning[write-only-fixture-counter]: calls",
        ].join("\n"),
    );
});

test("recognizes parenthesized writes while preserving explicit reads", (t) => {
    const warnings = runFixtureLint(t, {
        [fixture]: `contract Handler {
    uint256 public calls;
    uint256 public observed;
    function record() external returns (uint256) {
        ++calls;
        ((++calls));
        (++observed);
        return observed;
    }
}`,
    });
    assert.equal(warnings, fixture + ":2: warning[write-only-fixture-counter]: calls");
});

test("a private read does not hide a same-named public counter", (t) => {
    const warnings = runFixtureLint(t, {
        [fixture]: `contract Handler {
    uint256 public calls;
    uint256 public observed;
    function record() external { ++calls; ++observed; }
}
contract Other {
    uint256 private calls;
    uint256 private observed;
    function getCalls() external view returns (uint256) { return calls; }
    function readHandler(Handler handler) external view returns (uint256) { return handler.observed(); }
}`,
    });
    assert.equal(warnings, fixture + ":2: warning[write-only-fixture-counter]: calls");
});

test("only the declaring contract owns a private write", (t) => {
    const warnings = runFixtureLint(t, {
        [fixture]: `contract Handler {
    uint256 public calls;
}
contract Other {
    uint256 private calls;
    function record() external { ++calls; }
}`,
    });
    assert.equal(warnings, fixture + ":5: warning[write-only-fixture-counter]: calls");
});

test("attributes writes by derived fixtures to inherited counters", (t) => {
    const warnings = runFixtureLint(t, {
        [fixture]: `contract Handler {
    uint256 public calls;
    uint256 internal observed;
}`,
        "src/test/example/fixtures/Derived.sol": `import {Handler as Base} from "./Handler.sol";
contract Derived is Base {
    function record() external returns (uint256) {
        ++calls;
        ++observed;
        return observed;
    }
}`,
    });
    assert.equal(warnings, fixture + ":2: warning[write-only-fixture-counter]: calls");
});
