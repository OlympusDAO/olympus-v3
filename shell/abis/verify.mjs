import {existsSync} from "node:fs";
import {mkdir, readFile, writeFile} from "node:fs/promises";
import {dirname, resolve} from "node:path";
import {fileURLToPath} from "node:url";
import {setTimeout} from "node:timers/promises";
import {
    abiFile,
    jsonFormatter,
    olympusEntries,
    resolveMapping,
    runExport,
    stable,
} from "./export.mjs";
import {abiHash, isAbi} from "./identity.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "../..");

export async function lookupVerifiedAbi(chainId, address, apiKey, request = fetch) {
    const url = new URL("https://api.etherscan.io/v2/api");
    url.search = new URLSearchParams({
        chainid: String(chainId),
        module: "contract",
        action: "getsourcecode",
        address,
        apikey: apiKey,
    });
    const response = await request(url, {signal: AbortSignal.timeout(20000)});
    if (!response.ok) throw new Error(`Explorer HTTP ${response.status}`);
    const data = await response.json();
    if (data.status !== "1" || !data.result?.[0]?.ContractName || !data.result[0].SourceCode) {
        throw new Error(
            "Verified source unavailable (unsupported chain, unverified contract, or API error)",
        );
    }
    const record = data.result[0];
    const abi = JSON.parse(record.ABI);
    if (!Array.isArray(abi) || !abi.length) throw new Error("Explorer returned an invalid ABI");
    return {contractName: record.ContractName, abi, implementation: record.Implementation || null};
}

// The recorded evidence URL omits the API key.
function sourceUrl(chainId, address) {
    return `https://api.etherscan.io/v2/api?chainid=${chainId}&module=contract&action=getsourcecode&address=${address}`;
}

// Compare the verified ABI for an address with its chain-level mapping. For any difference,
// return the mapping pinned to the verified ABI. The source link fields stay as they are.
export function applyVerification(mappings, {chain, chainId, path, address}, verified) {
    const existing = mappings[`${chain}.${path}`];
    const hash = abiHash(verified.abi);
    const same = existing?.address?.toLowerCase() === address.toLowerCase();
    if (same && existing.abiHash === hash && existing.contractName === verified.contractName)
        return {status: "match", abiHash: hash, mapping: existing};
    // A new address replaces an excluded deployment and its implementation hint.
    const {exclude, implementationHint, ...rest} = existing || {};
    return {
        status: !existing?.address ? "unmapped" : same ? "mismatch" : "changed",
        abiHash: hash,
        mapping: {
            ...rest,
            address,
            abiHash: hash,
            contractName: verified.contractName,
            sourceUrl: sourceUrl(chainId, address),
            ...(verified.implementation ? {implementationHint: verified.implementation} : {}),
        },
    };
}

// The ABI hash of a committed file, or undefined if the file is missing or is not an ABI.
async function committedHash(file) {
    try {
        const abi = JSON.parse(await readFile(file, "utf8"));
        return isAbi(abi) ? abiHash(abi) : undefined;
    } catch {
        return undefined;
    }
}

async function main() {
    const args = process.argv.slice(2);
    const write = args.includes("--write");
    const rest = args.filter((arg) => arg !== "--write");
    if (rest.length && (rest.length !== 2 || rest[0] !== "--chain")) {
        throw new Error("Usage: node shell/abis/verify.mjs [--chain mainnet] [--write]");
    }
    if (existsSync(resolve(root, ".env"))) process.loadEnvFile(resolve(root, ".env"));
    const key =
        process.env.MCP_ETHERSCAN_API_KEY ||
        process.env.ETHERSCAN_KEY ||
        process.env.ETHERSCAN_API_KEY;
    if (!key)
        throw new Error(
            "Set MCP_ETHERSCAN_API_KEY, ETHERSCAN_KEY, or ETHERSCAN_API_KEY for the online ABI check.",
        );
    const env = JSON.parse(await readFile(resolve(root, "src/scripts/env.json"), "utf8"));
    const configPath = resolve(root, "shell/abis/config.json");
    const config = JSON.parse(await readFile(configPath, "utf8"));
    if (rest[1] && !config.chains[rest[1]]) throw new Error(`Unknown EVM chain: ${rest[1]}`);
    const format = write ? await jsonFormatter() : undefined;
    const counts = {match: 0, unmapped: 0, changed: 0, mismatch: 0, unavailable: 0, excluded: 0};
    let written = 0;
    let unlinked = 0;
    for (const [chain, chainId] of Object.entries(config.chains)) {
        if (rest[1] && chain !== rest[1]) continue;
        const section = env.current[chain]?.olympus;
        if (!section || typeof section !== "object" || Array.isArray(section))
            throw new Error(`Missing olympus section for ${chain}`);
        for (const [path, address] of olympusEntries(section, config, chain)) {
            if (!/^0x[\da-fA-F]{40}$/.test(address) || /^0x0{40}$/.test(address)) continue;
            const label = `${chain}.olympus.${path}`;
            const mapping = resolveMapping(config.mappings, chain, path);
            if (
                mapping?.exclude &&
                (!mapping.address || mapping.address.toLowerCase() === address.toLowerCase())
            ) {
                counts.excluded++;
                console.log(`EXCLUDED ${label}: ${mapping.exclude}`);
                continue;
            }
            let verified;
            try {
                verified = await lookupVerifiedAbi(chainId, address, key);
            } catch {
                // Do not print request URLs or transport errors, which can contain API keys.
                counts.unavailable++;
                console.log(`UNAVAILABLE ${label}: Could not verify deployed ABI`);
                continue;
            } finally {
                await setTimeout(400);
            }
            const result = applyVerification(
                config.mappings,
                {chain, chainId, path, address},
                verified,
            );
            counts[result.status]++;
            console.log(
                `${result.status.toUpperCase()} ${label}: ${verified.contractName}, abiHash=${result.abiHash}${verified.implementation ? `, explorer implementation hint=${verified.implementation} (requires RPC confirmation)` : ""}`,
            );
            if (!write) continue;
            // Write the verified ABI for a new pin, or to restore a missing or mismatched file. A
            // file with the pinned hash stays, because it can be the local build of the same ABI.
            const file = resolve(root, "abis", abiFile(chain, path));
            if (result.status !== "match" || (await committedHash(file)) !== result.abiHash) {
                await mkdir(dirname(file), {recursive: true});
                await writeFile(file, await format(verified.abi));
                written++;
            }
            if (result.status === "match") continue;
            config.mappings[`${chain}.${path}`] = result.mapping;
            const link = resolveMapping(config.mappings, chain, path);
            if (!link.source && !link.noSource) {
                unlinked++;
                console.log(
                    `  Add a source or noSource link for ${label} to shell/abis/config.json. The explorer contract name is ${verified.contractName}.`,
                );
            }
        }
    }
    const pinned = counts.unmapped + counts.changed + counts.mismatch;
    if (write && pinned) {
        await writeFile(configPath, await format(stable(config)));
        console.log(`Pinned ${pinned} deployments.`);
    }
    console.log(JSON.stringify(counts));
    if (counts.unavailable || (!write && pinned)) process.exitCode = 1;
    if (!written) return;
    // Generate the manifest and replace each exact ABI with its local build, so that one command
    // completes a new pin. A deployment without a source link cannot generate yet.
    if (unlinked) {
        console.log(
            "Add the source or noSource links above, then run 'pnpm run gen:abis' and commit the result.",
        );
        process.exitCode = 1;
        return;
    }
    await runExport();
    console.log("Commit shell/abis/config.json and abis/.");
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
    main().catch((error) => {
        console.error(error.message);
        process.exitCode = 1;
    });
}
