"use strict";

const {globSync, readFileSync} = require("node:fs");
const {dirname, join, normalize} = require("node:path");
const parser = require("@solidity-parser/parser");

const ASSIGNMENTS = new Set(["=", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "<<=", ">>="]);

function containsOffset([start, end], offset) {
    return offset >= start && offset <= end;
}

function observationTokens(source) {
    const tokens = parser.tokenize(source, {range: true});
    return tokens.flatMap((token, index) => {
        const preceding = tokens[index - 1]?.value;
        return preceding === "function" ? [] : [{...token, memberAccess: preceding === "."}];
    });
}

function indexFixture(fixture) {
    const ast = parser.parse(fixture.source, {loc: true, range: true});
    fixture.imports = ast.children.filter((node) => node.type === "ImportDirective");
    for (const definition of ast.children) {
        if (definition.type !== "ContractDefinition") continue;
        const declarations = new Map();
        for (const node of definition.subNodes) {
            if (node.type !== "StateVariableDeclaration") continue;
            for (const variable of node.variables) {
                if (
                    variable.typeName.type !== "ElementaryTypeName" ||
                    !/^uint\d*$/.test(variable.typeName.name) ||
                    variable.isDeclaredConst ||
                    variable.isImmutable
                )
                    continue;
                const {name, loc, range} = variable.identifier;
                const isPrivate = variable.visibility === "private";
                fixture.ignoredOffsets.add(range[0]);
                declarations.set(name, {
                    file: fixture.file,
                    name,
                    line: loc.start.line,
                    isPrivate,
                    written: false,
                });
                if (isPrivate) {
                    if (!fixture.privateRanges.has(name)) fixture.privateRanges.set(name, []);
                    fixture.privateRanges.get(name).push(definition.range);
                }
            }
        }
        fixture.contracts.set(definition.name, {definition, declarations, fixture});
    }
}

function findBase(fixture, name) {
    const local = fixture.contracts.get(name);
    if (local) return local;
    for (const {path, unitAlias, symbolAliases} of fixture.imports) {
        const imported = fixtures.get(
            path.startsWith(".") ? join(dirname(fixture.file), path) : normalize(path),
        );
        if (!imported) continue;
        if (unitAlias) {
            if (name.startsWith(unitAlias + "."))
                return imported.contracts.get(name.slice(unitAlias.length + 1));
        } else if (symbolAliases) {
            const symbol = symbolAliases.find(([original, alias]) => (alias ?? original) === name);
            if (symbol) return imported.contracts.get(symbol[0]);
        } else if (imported.contracts.has(name)) {
            return imported.contracts.get(name);
        }
    }
    return undefined;
}

function resolveCounter(contract, name, seen = new Set()) {
    if (seen.has(contract)) return undefined;
    seen.add(contract);
    const declared = contract.declarations.get(name);
    if (declared) return declared;

    for (const {baseName} of contract.definition.baseContracts) {
        const base = findBase(contract.fixture, baseName.namePath);
        if (!base) continue;
        const inherited = resolveCounter(base, name, seen);
        if (inherited && !inherited.isPrivate) return inherited;
    }
    return undefined;
}

function unwrapParentheses(expression) {
    while (
        expression?.type === "TupleExpression" &&
        !expression.isArray &&
        expression.components.length === 1
    ) {
        expression = expression.components[0];
    }
    return expression;
}

function recordWrites(contract) {
    parser.visit(contract.definition, {
        ExpressionStatement(statement) {
            const expression = unwrapParentheses(statement.expression);
            if (!expression) return;
            let target;
            if (
                expression.type === "UnaryOperation" &&
                ["++", "--", "delete"].includes(expression.operator)
            ) {
                target = expression.subExpression;
            }
            if (expression.type === "BinaryOperation" && ASSIGNMENTS.has(expression.operator)) {
                target = expression.left;
            }
            const targets = target?.type === "TupleExpression" ? target.components : [target];
            for (const component of targets) {
                const item = unwrapParentheses(component);
                if (item?.type !== "Identifier") continue;
                const counter = resolveCounter(contract, item.name);
                if (!counter) continue;
                counter.written = true;
                contract.fixture.ignoredOffsets.add(item.range[0]);
            }
        },
    });
}

const fixtures = new Map();
for (const file of globSync("src/test/**/fixtures/**/*.sol").sort()) {
    const fixture = {
        file,
        source: readFileSync(file, "utf8"),
        contracts: new Map(),
        ignoredOffsets: new Set(),
        privateRanges: new Map(),
    };
    try {
        indexFixture(fixture);
        fixtures.set(file, fixture);
    } catch (error) {
        console.warn(file + ": warning[fixture-counters]: " + error.message);
    }
}

const fixtureContracts = [...fixtures.values()].flatMap((fixture) => [
    ...fixture.contracts.values(),
]);
for (const contract of fixtureContracts) recordWrites(contract);

const counters = [];
for (const {definition, declarations, fixture} of fixtureContracts) {
    for (const counter of declarations.values()) {
        if (!counter.written) continue;
        let unreadInContract;
        if (counter.isPrivate) {
            fixture.tokens ??= observationTokens(fixture.source);
            unreadInContract = !fixture.tokens.some(
                ({value, range: [offset], memberAccess}) =>
                    value === counter.name &&
                    !memberAccess &&
                    containsOffset(definition.range, offset) &&
                    !fixture.ignoredOffsets.has(offset),
            );
        }
        counters.push({...counter, unreadInContract});
    }
}

// Private counters are already checked. Keep other counters if any contract may read them.
const unreadNames = new Set(
    counters.filter(({unreadInContract}) => unreadInContract === undefined).map(({name}) => name),
);
const files = unreadNames.size > 0 ? globSync("src/**/*.sol").sort() : [];
let candidatePattern;
for (const file of files) {
    if (unreadNames.size === 0) break;
    candidatePattern ??= new RegExp([...unreadNames].map(RegExp.escape).join("|"));
    const fixture = fixtures.get(file);
    const source = fixture?.source ?? readFileSync(file, "utf8");
    if (!candidatePattern.test(source)) continue;

    const before = unreadNames.size;
    for (const token of fixture?.tokens ?? observationTokens(source)) {
        // Low-level getter calls may use a literal selector signature.
        const signature = /^["']([\w$]+)\(\)["']$/.exec(token.value);
        if (signature) unreadNames.delete(signature[1]);
        const offset = token.range[0];
        if (fixture?.ignoredOffsets.has(offset)) continue;
        const privateRanges = fixture?.privateRanges.get(token.value);
        if (!token.memberAccess && privateRanges?.some((range) => containsOffset(range, offset)))
            continue;
        unreadNames.delete(token.value);
    }
    if (unreadNames.size !== before) candidatePattern = undefined;
}

for (const {file, line, name, unreadInContract} of counters) {
    if (unreadInContract ?? unreadNames.has(name)) {
        console.warn(file + ":" + line + ": warning[write-only-fixture-counter]: " + name);
    }
}
