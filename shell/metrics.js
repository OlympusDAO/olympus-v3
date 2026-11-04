#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const {execFileSync} = require("node:child_process");
const {parseArgs} = require("node:util");
const parser = require("@solidity-parser/parser");

const sccVersion = "scc version 4.1.0";
const sccFlags = ["--no-config", "--no-gitignore", "--no-ignore", "--no-scc-ignore"];

// Only function declarations are normalized. Constructors and modifiers stay unchanged.
function normalizeHeaders(content) {
    const ast = parser.parse(content, {range: true});
    const headers = [];
    parser.visit(ast, {
        FunctionDefinition(node) {
            if (content.slice(node.range[0], node.range[0] + 8) !== "function") return;
            headers.push({
                start: node.range[0],
                end: node.body ? node.body.range[0] : node.range[1] + 1,
                replacement: node.body ? "function " : "function;",
            });
        },
    });
    for (const header of headers.sort((a, b) => b.start - a.start)) {
        content = content.slice(0, header.start) + header.replacement + content.slice(header.end);
    }
    return content;
}

function main() {
    const {values, positionals} = parseArgs({
        allowPositionals: true,
        options: {
            scope: {type: "string"},
            exclude: {type: "string", multiple: true, default: []},
            output: {type: "string", default: "solidity-metrics.html"},
            help: {type: "boolean", short: "h"},
        },
    });
    if (values.help) {
        console.log(
            "Usage: pnpm metrics [files or globs] [--scope scope.txt] [--exclude glob] [--output report.html]",
        );
        return;
    }
    const cwd = process.cwd();
    const patterns = [...positionals];
    if (values.scope) {
        patterns.push(
            ...fs
                .readFileSync(values.scope, "utf8")
                .split(/\r?\n/)
                .map((line) => line.trim())
                .filter((line) => line && !line.startsWith("#")),
        );
    }
    if (!patterns.length) throw new Error("Specify Solidity files, globs, or --scope scope.txt.");
    const output = path.resolve(values.output);
    if (path.extname(output).toLowerCase() !== ".html")
        throw new Error("The output must be an HTML file.");

    const files = new Set();
    for (const pattern of patterns) {
        const relative = path.relative(cwd, path.resolve(cwd, pattern));
        if (relative === ".." || relative.startsWith(".." + path.sep)) {
            throw new Error("Scope files must stay inside the current directory: " + pattern);
        }
        const matches = fs.globSync(pattern, {cwd});
        if (!matches.length) throw new Error("No Solidity files match: " + pattern);
        for (const file of matches) {
            if (path.extname(file) !== ".sol" || !fs.statSync(file).isFile()) {
                throw new Error("Scope entries must select Solidity files: " + file);
            }
            const name = path.relative(cwd, path.resolve(cwd, file));
            const actual = path.relative(fs.realpathSync(cwd), fs.realpathSync(file));
            if (actual === ".." || actual.startsWith(".." + path.sep)) {
                throw new Error("Scope files must stay inside the current directory: " + file);
            }
            if (!values.exclude.some((exclude) => path.matchesGlob(name, exclude))) files.add(name);
        }
    }
    if (!files.size) throw new Error("No Solidity files match after exclusions.");
    let version;
    try {
        version = execFileSync("scc", ["--version"], {encoding: "utf8"}).trim();
    } catch {
        throw new Error(
            "SCC 4.1.0 is required on PATH. Install it separately; see documentation/METRICS.md.",
        );
    }
    if (version !== sccVersion) throw new Error("Expected SCC 4.1.0, received " + version + ".");

    const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "olympus-nsloc-"));
    try {
        const staged = path.join(temporary, "source");
        fs.mkdirSync(staged);
        for (const file of [...files].sort()) {
            let normalized;
            try {
                normalized = normalizeHeaders(fs.readFileSync(file, "utf8"));
            } catch (error) {
                throw new Error(file + ": " + error.message);
            }
            const destination = path.join(staged, file);
            fs.mkdirSync(path.dirname(destination), {recursive: true});
            fs.writeFileSync(destination, normalized);
        }
        const run = (args) =>
            execFileSync("scc", [...sccFlags, ...args, "."], {
                cwd: staged,
                encoding: "utf8",
                maxBuffer: 20_000_000,
            });
        const counts = JSON.parse(run(["--by-file", "--format", "json"])).flatMap(
            (language) => language.Files || [],
        );
        const resolved = counts.map((file) => file.Location.replace(/^\.\//, "")).sort();
        if (JSON.stringify(resolved) !== JSON.stringify([...files].sort())) {
            throw new Error("SCC did not count exactly the requested scope.");
        }
        const report = path.join(temporary, "report.html");
        run([
            "--by-file",
            "--no-cocomo",
            "--report=" + report,
            "--report-title",
            "Scoped Solidity nSLOC - function headers normalized",
            "--report-skip",
            "cocomo,locomo,hotspots,coupling,authors,timeline,uloc,linelength,card",
        ]);
        fs.mkdirSync(path.dirname(output), {recursive: true});
        fs.copyFileSync(report, output);
        const total = counts.reduce((sum, file) => sum + file.Code, 0);
        console.log(
            "Wrote " +
                path.relative(cwd, output) +
                ": " +
                files.size +
                " files, " +
                total +
                " nSLOC.",
        );
    } finally {
        fs.rmSync(temporary, {recursive: true, force: true});
    }
}

try {
    main();
} catch (error) {
    console.error(error.message);
    process.exitCode = 1;
}
