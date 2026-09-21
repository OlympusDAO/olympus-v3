import {execFile} from "node:child_process";
import {mkdir, mkdtemp, readFile, readdir, rm, rmdir, writeFile} from "node:fs/promises";
import {tmpdir} from "node:os";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {promisify} from "node:util";
import {abiHash, covers, isAbi} from "./identity.mjs";

const exec = promisify(execFile);
const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const zeroAddress = "0x" + "0".repeat(40);

// Sort object keys, but never reorder ABI arrays: tuple components and arguments
// are positional, and changing their order changes how calldata is decoded.
export function stable(value) {
    if (Array.isArray(value)) return value.map(stable);
    if (value && typeof value === "object") {
        return Object.fromEntries(
            Object.keys(value)
                .sort()
                .map((key) => [key, stable(value[key])]),
        );
    }
    return value;
}

function leaves(value, path = "") {
    if (typeof value === "string") return [[path, value]];
    if (!value || typeof value !== "object" || Array.isArray(value)) {
        throw new Error(`Invalid deployment entry: ${path}`);
    }
    return Object.keys(value)
        .sort()
        .flatMap((key) => leaves(value[key], path ? `${path}.${key}` : key));
}

// The deployment entries of one chain, as [path, address, extra] triples, sorted by path.
// They come from the chain's `olympus` section in env.json, without the `config` and `multisig`
// sections. An excluded section, such as the pre-V3 `legacy` section, keeps only the paths in its
// `keep` list. `config.extraDeployments.<chain>` adds current deployments that env.json does not
// list, with `extra` set to true.
export function olympusEntries(section, config, chain) {
    const {config: ignoredConfig, multisig: ignoredMultisig, ...olympus} = section;
    const listed = leaves(olympus);
    const paths = new Set(listed.map(([path]) => path));
    const entries = listed.filter(([path]) => {
        const [name, ...rest] = path.split(".");
        const excluded = config.excludedSections?.[name];
        return !excluded || excluded.keep?.includes(rest.join("."));
    });
    for (const [path, address] of leaves(config.extraDeployments?.[chain] ?? {})) {
        if (paths.has(path))
            throw new Error(
                `extraDeployments.${chain}.${path} is also in env.json. Remove it from shell/abis/config.json.`,
            );
        entries.push([path, address, true]);
    }
    return entries.sort(([first], [second]) => (first < second ? -1 : first > second ? 1 : 0));
}

// Chain-level `source`, `sourceKind` and `noSource` replace the shared link as one unit,
// so a chain can drop a shared source link. Other chain-level fields override one by one.
export function resolveMapping(mappings, chain, path) {
    const shared = mappings[path];
    const override = mappings[`${chain}.${path}`];
    if (!shared && !override) return undefined;
    const link =
        override && ("source" in override || "noSource" in override) ? override : shared || {};
    return {
        ...shared,
        ...override,
        source: link.source,
        sourceKind: link.sourceKind,
        noSource: link.noSource,
    };
}

// The ABI file of a deployment is `<chain>/<label>.json`, where the label is the last part of
// its env.json path.
export function abiFile(chain, path) {
    return `${chain}/${path.split(".").pop()}.json`;
}

// `committedAbi(file)` returns the committed ABI file, or undefined if it does not exist.
// `sourceAbi(contract)` compiles a repository contract and returns its ABI.
export async function generateBundle(env, config, {committedAbi, sourceAbi}) {
    if (!env.current || typeof env.current !== "object") throw new Error("Missing env.current");
    const abis = {};
    const sourceAbis = {};
    const deployments = [];
    const exclusions = [];
    const used = new Set();
    for (const [name, {reason, keep = []}] of Object.entries(config.excludedSections ?? {}))
        exclusions.push({section: `olympus.${name}`, reason, keep});
    for (const chain of Object.keys(env.current).sort()) {
        if (config.excludedChains[chain]) {
            exclusions.push({chain, reason: config.excludedChains[chain]});
            continue;
        }
        const chainId = config.chains[chain];
        if (!Number.isSafeInteger(chainId) || chainId <= 0)
            throw new Error(`Unknown chain: ${chain}`);
        const section = env.current[chain]?.olympus;
        if (!section || typeof section !== "object" || Array.isArray(section))
            throw new Error(`Missing olympus section for ${chain}`);
        const files = {};
        for (const [path, address, extra] of olympusEntries(section, config, chain)) {
            const label = `${chain}.olympus.${path}`;
            if (!/^0x[\da-fA-F]{40}$/.test(address))
                throw new Error(`Invalid address at ${label}: ${address}`);
            used.add(path).add(`${chain}.${path}`);
            if (address === zeroAddress) continue;
            const mapping = resolveMapping(config.mappings, chain, path);
            if (!mapping)
                throw new Error(
                    `No ABI mapping for ${label}. Add its source or noSource link to shell/abis/config.json, then run 'pnpm run gen:abis:verify --chain ${chain} --write'.`,
                );
            if (mapping.address && mapping.address.toLowerCase() !== address.toLowerCase()) {
                throw new Error(
                    `Deployment address has changed for ${label}. Run 'pnpm run gen:abis:verify --chain ${chain} --write' to pin the ABI of the new deployment.`,
                );
            }
            if (mapping.exclude) {
                exclusions.push({
                    chain,
                    chainId,
                    path: `olympus.${path}`,
                    address,
                    reason: mapping.exclude,
                });
                continue;
            }
            if (!mapping.address || !mapping.abiHash)
                throw new Error(
                    `No pinned ABI for ${label}. Run 'pnpm run gen:abis:verify --chain ${chain} --write' to pin its verified ABI.`,
                );
            const hash = mapping.abiHash;
            if (!/^[\da-f]{64}$/.test(hash)) throw new Error(`Invalid abiHash for ${label}`);
            if (!mapping.contractName || !mapping.sourceUrl)
                throw new Error(
                    `No verification evidence for ${label}. Run 'pnpm run gen:abis:verify --chain ${chain} --write'.`,
                );
            if (!mapping.source === !mapping.noSource)
                throw new Error(`Set exactly one of source or noSource for ${label}`);
            if (mapping.source && !/^[\w@./-]+\.sol:\w+$/.test(mapping.source))
                throw new Error(`Invalid source for ${label}`);
            const kind = mapping.sourceKind ?? "implementation";
            if (!["implementation", "interface"].includes(kind))
                throw new Error(`Invalid sourceKind for ${label}`);
            const file = abiFile(chain, path);
            if (!/^[\w-]+\/\w+\.json$/.test(file)) throw new Error(`Invalid ABI file for ${label}`);
            if (files[file])
                throw new Error(`${label} and ${files[file]} have the same ABI file ${file}`);
            files[file] = label;

            let current;
            if (mapping.source) {
                if (!sourceAbis[mapping.source]) {
                    let abi;
                    try {
                        abi = await sourceAbi(mapping.source);
                    } catch (error) {
                        throw new Error(
                            `Could not compile ${mapping.source} for ${label}. Correct its source link in shell/abis/config.json. ${error.message}`,
                        );
                    }
                    if (!isAbi(abi)) throw new Error(`Invalid ABI for ${mapping.source}`);
                    sourceAbis[mapping.source] = abi;
                }
                current = sourceAbis[mapping.source];
            }
            let link;
            if (kind === "implementation" && current && abiHash(current) === hash) {
                // The current source is the deployed ABI, so the local build is the file.
                abis[file] = current;
                link = {contract: mapping.source, status: "exact"};
            } else {
                // The committed file is the only record of this deployed ABI. Keep it, and never
                // replace it with content that does not match the pinned hash.
                const committed = await committedAbi(file);
                if (committed === undefined)
                    throw new Error(
                        `No committed ABI for ${label} at abis/${file}. Restore it from git, or run 'pnpm run gen:abis:verify --chain ${chain} --write'.`,
                    );
                if (!isAbi(committed)) throw new Error(`Invalid ABI in abis/${file}`);
                if (abiHash(committed) !== hash)
                    throw new Error(
                        `abis/${file} does not match the pinned abiHash of ${label}. Restore it from git, or run 'pnpm run gen:abis:verify --chain ${chain} --write'.`,
                    );
                abis[file] = committed;
                link = !current
                    ? {status: "unavailable", reason: mapping.noSource}
                    : {
                          contract: mapping.source,
                          status:
                              kind === "interface" && covers(committed, current)
                                  ? "interface"
                                  : "drifted",
                      };
            }
            deployments.push({
                chain,
                chainId,
                path: `olympus.${path}`,
                ...(extra ? {extra: true} : {}),
                address,
                abi: file,
                abiHash: hash,
                source: link,
                verification: {
                    contractName: mapping.contractName,
                    sourceUrl: mapping.sourceUrl,
                    ...(mapping.implementationHint
                        ? {implementationHint: mapping.implementationHint}
                        : {}),
                },
            });
        }
    }
    for (const chain of Object.keys(config.extraDeployments ?? {}))
        if (!config.chains[chain] || !env.current[chain] || config.excludedChains[chain])
            throw new Error(
                `extraDeployments.${chain} is not an exported chain. Remove it from shell/abis/config.json.`,
            );
    const unused = Object.keys(config.mappings).filter((key) => !used.has(key));
    if (unused.length)
        throw new Error(
            `Unused mappings in shell/abis/config.json: ${unused.join(", ")}. Remove them.`,
        );
    return stable({
        schemaVersion: 3,
        source: "src/scripts/env.json#current",
        provenance:
            "Each deployment is pinned to the hash of the ABI that was verified for its address. The ABI hash compares callable types, not bytecode or current proxy implementations. The source link names the codebase contract and reports if its current ABI still matches. Pin the same Git revision for the manifest and ABI files.",
        scope: "Current Olympus EVM entries; excludes external protocols, config, multisigs, env.last and the excluded sections and chains. See exclusions.",
        abis,
        deployments,
        exclusions,
    });
}

export async function renderFiles({abis, ...manifest}, format) {
    const files = {};
    for (const [file, abi] of Object.entries(abis)) files[file] = await format(abi);
    files["manifest.json"] = await format(manifest);
    return files;
}

// The JSON files in the subdirectories of `directory`. Top-level files other than the
// manifest, such as README.md, are not owned by the exporter.
async function abiFiles(directory, prefix = "") {
    let entries;
    try {
        entries = await readdir(resolve(directory, prefix), {withFileTypes: true});
    } catch (error) {
        if (error.code === "ENOENT") return [];
        throw error;
    }
    const files = [];
    for (const entry of entries) {
        const path = prefix ? `${prefix}/${entry.name}` : entry.name;
        if (entry.isDirectory()) files.push(...(await abiFiles(directory, path)));
        else if (prefix && entry.name.endsWith(".json")) files.push(path);
    }
    return files.sort();
}

export async function saveFiles(directory, files, check) {
    const obsolete = (await abiFiles(directory)).filter((file) => !(file in files));
    const differences = [...obsolete];
    for (const [file, content] of Object.entries(files)) {
        let existing;
        try {
            existing = await readFile(resolve(directory, file), "utf8");
        } catch (error) {
            if (error.code !== "ENOENT") throw error;
        }
        if (existing !== content) differences.push(file);
    }
    if (check) {
        if (differences.length)
            throw new Error(
                `ABI export is out of date (${differences.join(", ")}). Run 'pnpm run gen:abis' and commit the result.`,
            );
    } else {
        for (const [file, content] of Object.entries(files)) {
            const path = resolve(directory, file);
            await mkdir(dirname(path), {recursive: true});
            await writeFile(path, content);
        }
        // This script owns only the manifest and the ABI files in subdirectories; retain documentation.
        for (const file of obsolete) {
            await rm(resolve(directory, file));
            // Remove the folder of a removed chain, such as a retired or excluded chain.
            await rmdir(dirname(resolve(directory, file))).catch((error) => {
                if (!["ENOTEMPTY", "ENOENT"].includes(error.code)) throw error;
            });
        }
    }
}

// Format JSON as the repository's Prettier configuration does, so checks compare bytes.
export async function jsonFormatter() {
    const prettier = await import("prettier");
    const options = await prettier.resolveConfig(resolve(root, "package.json"));
    return (value) =>
        prettier.format(JSON.stringify(value), {
            ...options,
            parser: "json",
            filepath: resolve(root, "abis/manifest.json"),
        });
}

// Generate the ABI files and the manifest. With `check`, compare them and write nothing.
export async function runExport({check = false} = {}) {
    const env = JSON.parse(await readFile(resolve(root, "src/scripts/env.json"), "utf8"));
    const config = JSON.parse(await readFile(resolve(root, "shell/abis/config.json"), "utf8"));
    const temporary = await mkdtemp(resolve(tmpdir(), "olympus-abis-"));
    let bundle;
    try {
        bundle = await generateBundle(env, config, {
            committedAbi: async (file) => {
                let content;
                try {
                    content = await readFile(resolve(root, "abis", file), "utf8");
                } catch (error) {
                    if (error.code === "ENOENT") return undefined;
                    throw error;
                }
                try {
                    return JSON.parse(content);
                } catch (error) {
                    throw new Error(`Invalid JSON in abis/${file}: ${error.message}`);
                }
            },
            sourceAbi: async (contract) => {
                console.log(`Compiling ${contract}`);
                // Inspect the exact source/contract, not arbitrary cached out/ entries.
                // Forge compiles the target and its imports as needed; no RPC is required.
                // Separate, fresh artifacts avoid stale removed contracts and preserve
                // the full build artifacts used by CI tests and its shared build cache.
                const {stdout} = await exec(
                    "forge",
                    [
                        "inspect",
                        "--json",
                        contract,
                        "abi",
                        "--contracts",
                        contract.split(":")[0],
                        "--out",
                        resolve(temporary, "out"),
                        "--cache-path",
                        resolve(temporary, "cache"),
                    ],
                    {cwd: root, maxBuffer: 16 * 1024 * 1024},
                );
                return JSON.parse(stdout);
            },
        });
    } finally {
        await rm(temporary, {recursive: true, force: true});
    }
    const files = await renderFiles(bundle, await jsonFormatter());
    await saveFiles(resolve(root, "abis"), files, check);
    const links = {};
    for (const {source} of bundle.deployments)
        links[source.status] = (links[source.status] || 0) + 1;
    console.log(
        `${check ? "Verified" : "Wrote"} ${Object.keys(bundle.abis).length} ABIs for ${bundle.deployments.length} deployments. Source links: ${JSON.stringify(links)}.`,
    );
}

async function main() {
    const args = process.argv.slice(2);
    if (args.some((arg) => arg !== "--check") || args.length > 1)
        throw new Error("Usage: node shell/abis/export.mjs [--check]");
    await runExport({check: args.includes("--check")});
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
    main().catch((error) => {
        console.error(error.message);
        process.exitCode = 1;
    });
}
