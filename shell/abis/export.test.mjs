import assert from "node:assert/strict";
import {mkdir, mkdtemp, readdir, readFile, rm, writeFile} from "node:fs/promises";
import {tmpdir} from "node:os";
import {join} from "node:path";
import test from "node:test";
import {generateBundle, renderFiles, saveFiles} from "./export.mjs";
import {abiHash} from "./identity.mjs";
import {applyVerification, lookupVerifiedAbi} from "./verify.mjs";

const address = "0x1111111111111111111111111111111111111111";
const other = "0x2222222222222222222222222222222222222222";
const source = "src/Kernel.sol:Kernel";
const abi = [
    {
        type: "function",
        name: "execute",
        inputs: [{name: "items", type: "tuple[]", components: [{name: "id", type: "uint256"}]}],
        outputs: [],
        stateMutability: "nonpayable",
    },
    {type: "error", name: "Denied", inputs: []},
    {
        type: "function",
        name: "execute",
        inputs: [{name: "id", type: "uint256"}],
        outputs: [],
        stateMutability: "view",
    },
    {type: "event", name: "Changed", inputs: [], anonymous: false},
];
const hash = abiHash(abi);
const evidence = {
    address,
    abiHash: hash,
    contractName: "Kernel",
    sourceUrl: "https://example.test/kernel",
};
const config = {
    chains: {mainnet: 1},
    excludedChains: {solana: "Non-EVM chain"},
    mappings: {Kernel: {source}, "mainnet.Kernel": evidence},
};
const env = (olympus) => ({current: {mainnet: {olympus}}});
const withMappings = (mappings) => ({...config, mappings: {...config.mappings, ...mappings}});

function loaders({committed = {}, sources = {[source]: abi}} = {}) {
    const calls = {committed: 0, source: 0};
    return {
        calls,
        committedAbi: async (file) => {
            calls.committed++;
            return committed[file];
        },
        sourceAbi: async (contract) => {
            calls.source++;
            if (!(contract in sources)) throw new Error(`Compiler failed for ${contract}`);
            return sources[contract];
        },
    };
}
const changedSource = [...abi, {type: "error", name: "New", inputs: []}];

test("PRICE mappings link the deployed implementation separately for mainnet and Sepolia", async () => {
    const actual = JSON.parse(await readFile(new URL("./config.json", import.meta.url)));
    assert.equal(
        actual.mappings["mainnet.modules.OlympusPriceV1"].source,
        "src/modules/PRICE/OlympusPrice.v1_2.sol:OlympusPricev1_2",
    );
    assert.equal(
        actual.mappings["sepolia.modules.OlympusPriceV1"].source,
        "src/modules/PRICE/OlympusPrice.sol:OlympusPrice",
    );
});

test("bridged L2 gOHM tokens do not link to the IgOHM interface", async () => {
    const actual = JSON.parse(await readFile(new URL("./config.json", import.meta.url)));
    for (const chain of ["arbitrum", "optimism"]) {
        const mapping = actual.mappings[`${chain}.legacy.gOHM`];
        assert.equal(mapping.contractName, "SynapseERC20", `${chain} contract name`);
        assert.match(mapping.noSource, /SynapseERC20/, `${chain} link reason`);
        assert.equal(mapping.source, undefined, `${chain} source link`);
    }
});

test("the configuration retires goerli and bartio and keeps only the live legacy contracts", async () => {
    const actual = JSON.parse(await readFile(new URL("./config.json", import.meta.url)));
    assert.equal(actual.allowUnverifiedChains, undefined, "no unverified chains");
    for (const chain of ["goerli", "berachain-bartio"]) {
        assert.match(actual.excludedChains[chain], /Retired/, `${chain} is retired`);
        assert.equal(actual.chains[chain], undefined, `${chain} has no chain ID`);
    }
    assert.deepEqual(
        [...actual.excludedSections.legacy.keep].sort(),
        ["OHM", "OlympusAuthority", "Staking", "gOHM", "sOHM"],
        "legacy allowlist",
    );
});

test("an exact deployment uses the local build and reads no committed file", async () => {
    const counted = loaders();
    const result = await generateBundle(env({Kernel: address}), config, counted);
    assert.equal(result.deployments[0].source.status, "exact");
    assert.equal(result.deployments[0].source.contract, source);
    assert.equal(result.deployments[0].abi, "mainnet/Kernel.json");
    assert.deepEqual(result.abis["mainnet/Kernel.json"], abi);
    assert.deepEqual(counted.calls, {committed: 0, source: 1});
});

test("a source ABI change marks the deployment drifted and keeps the committed ABI", async () => {
    const committed = {"mainnet/Kernel.json": abi};
    const result = await generateBundle(
        env({Kernel: address}),
        config,
        loaders({committed, sources: {[source]: changedSource}}),
    );
    assert.equal(result.deployments[0].source.status, "drifted");
    assert.equal(result.deployments[0].abiHash, hash);
    assert.deepEqual(result.abis["mainnet/Kernel.json"], abi);
});

test("a non-exact deployment fails without a committed file that matches the pinned hash", async () => {
    await assert.rejects(
        generateBundle(
            env({Kernel: address}),
            config,
            loaders({sources: {[source]: changedSource}}),
        ),
        /No committed ABI for mainnet.olympus.Kernel at abis\/mainnet\/Kernel.json.*--write/,
    );
    // The committed file is never replaced with the changed source ABI.
    await assert.rejects(
        generateBundle(
            env({Kernel: address}),
            config,
            loaders({
                committed: {"mainnet/Kernel.json": changedSource},
                sources: {[source]: changedSource},
            }),
        ),
        /abis\/mainnet\/Kernel.json does not match the pinned abiHash of mainnet.olympus.Kernel/,
    );
    await assert.rejects(
        generateBundle(
            env({Kernel: address}),
            config,
            loaders({committed: {"mainnet/Kernel.json": {}}, sources: {[source]: changedSource}}),
        ),
        /Invalid ABI in abis\/mainnet\/Kernel.json/,
    );
    await assert.rejects(
        generateBundle(
            env({Kernel: address}),
            withMappings({"mainnet.Kernel": {...evidence, abiHash: "../manifest"}}),
            loaders(),
        ),
        /Invalid abiHash for mainnet.olympus.Kernel/,
    );
});

test("interface links report interface only when the deployment implements every entry", async () => {
    const iface = "src/interfaces/IKernel.sol:IKernel";
    const custom = withMappings({Kernel: {source: iface, sourceKind: "interface"}});
    const committed = {"mainnet/Kernel.json": abi};
    const subset = await generateBundle(
        env({Kernel: address}),
        custom,
        loaders({committed, sources: {[iface]: abi.slice(0, 2)}}),
    );
    assert.equal(subset.deployments[0].source.status, "interface");
    assert.deepEqual(subset.abis["mainnet/Kernel.json"], abi);
    // An interface link always keeps the committed ABI, also when the interface has every entry.
    const full = await generateBundle(
        env({Kernel: address}),
        custom,
        loaders({committed, sources: {[iface]: abi}}),
    );
    assert.equal(full.deployments[0].source.status, "interface");
    const extra = await generateBundle(
        env({Kernel: address}),
        custom,
        loaders({
            committed,
            sources: {[iface]: [abi[0], {type: "error", name: "Missing", inputs: []}]},
        }),
    );
    assert.equal(extra.deployments[0].source.status, "drifted");
    await assert.rejects(
        generateBundle(
            env({Kernel: address}),
            withMappings({Kernel: {source, sourceKind: "partial"}}),
            loaders(),
        ),
        /Invalid sourceKind for mainnet.olympus.Kernel/,
    );
});

test("a deployment needs exactly one source or noSource link, and a chain link replaces the shared link", async () => {
    const committed = {"mainnet/Kernel.json": abi};
    const none = await generateBundle(
        env({Kernel: address}),
        withMappings({Kernel: {noSource: "Implementation is not in this repository"}}),
        loaders({committed}),
    );
    assert.deepEqual(none.deployments[0].source, {
        reason: "Implementation is not in this repository",
        status: "unavailable",
    });
    assert.deepEqual(none.abis["mainnet/Kernel.json"], abi);
    for (const link of [{}, {source, noSource: "Both"}]) {
        await assert.rejects(
            generateBundle(env({Kernel: address}), withMappings({Kernel: link}), loaders()),
            /Set exactly one of source or noSource for mainnet.olympus.Kernel/,
        );
    }
    const replaced = await generateBundle(
        env({Kernel: address}),
        withMappings({"mainnet.Kernel": {...evidence, noSource: "Bridged token"}}),
        loaders({committed}),
    );
    assert.equal(replaced.deployments[0].source.status, "unavailable");
    await assert.rejects(
        generateBundle(
            env({Kernel: address}),
            withMappings({Kernel: {source: "src/Kernel.sol"}}),
            loaders(),
        ),
        /Invalid source for mainnet.olympus.Kernel/,
    );
});

test("every exported deployment needs a pinned address, ABI hash and explorer evidence", async () => {
    for (const field of ["address", "abiHash"]) {
        const {[field]: omitted, ...partial} = evidence;
        await assert.rejects(
            generateBundle(
                env({Kernel: address}),
                {...config, mappings: {Kernel: {source}, "mainnet.Kernel": partial}},
                loaders(),
            ),
            /No pinned ABI for mainnet.olympus.Kernel.*gen:abis:verify --chain mainnet --write/,
        );
    }
    for (const field of ["contractName", "sourceUrl"]) {
        const {[field]: omitted, ...partial} = evidence;
        await assert.rejects(
            generateBundle(
                env({Kernel: address}),
                {...config, mappings: {Kernel: {source}, "mainnet.Kernel": partial}},
                loaders(),
            ),
            /No verification evidence for mainnet.olympus.Kernel/,
        );
    }
    await assert.rejects(
        generateBundle(env({Kernel: other}), config, loaders()),
        /address has changed for mainnet.olympus.Kernel.*--write/,
    );
    const result = await generateBundle(env({Kernel: address}), config, loaders());
    assert.deepEqual(result.deployments[0].verification, {
        contractName: "Kernel",
        sourceUrl: evidence.sourceUrl,
    });
    assert.equal(result.deployments[0].coverage, undefined);
});

test("the manifest records the explorer implementation hint", async () => {
    const hinted = withMappings({"mainnet.Kernel": {...evidence, implementationHint: other}});
    const result = await generateBundle(env({Kernel: address}), hinted, loaders());
    assert.equal(result.deployments[0].verification.implementationHint, other);
});

test("an excluded section keeps only the paths in its keep list", async () => {
    const custom = {
        ...withMappings({
            "legacy.OHM": {source},
            "mainnet.legacy.OHM": {...evidence, address: other},
        }),
        excludedSections: {legacy: {reason: "Pre-V3", keep: ["OHM"]}},
    };
    const result = await generateBundle(
        env({Kernel: address, legacy: {OHM: other, TreasuryV2: address}}),
        custom,
        loaders(),
    );
    assert.deepEqual(
        result.deployments.map((deployment) => deployment.path),
        ["olympus.Kernel", "olympus.legacy.OHM"],
    );
    assert.equal(result.deployments[1].abi, "mainnet/OHM.json");
    assert.deepEqual(result.exclusions, [
        {keep: ["OHM"], reason: "Pre-V3", section: "olympus.legacy"},
    ]);
    // A mapping for an excluded path is unused and fails.
    await assert.rejects(
        generateBundle(
            env({Kernel: address, legacy: {TreasuryV2: address}}),
            {...custom, mappings: {...custom.mappings, "legacy.TreasuryV2": {source}}},
            loaders(),
        ),
        /Unused mappings in shell\/abis\/config.json: legacy.OHM, mainnet.legacy.OHM, legacy.TreasuryV2/,
    );
});

test("extraDeployments adds current deployments that env.json does not list", async () => {
    const custom = {
        ...withMappings({"mainnet.policies.KernelV1": {...evidence, address: other, source}}),
        extraDeployments: {mainnet: {"policies.KernelV1": other}},
    };
    const result = await generateBundle(env({Kernel: address}), custom, loaders());
    assert.deepEqual(
        result.deployments.map(({path, extra, abi: file}) => [path, extra, file]),
        [
            ["olympus.Kernel", undefined, "mainnet/Kernel.json"],
            ["olympus.policies.KernelV1", true, "mainnet/KernelV1.json"],
        ],
    );
    // An extra deployment without a pin fails like an env.json deployment.
    await assert.rejects(
        generateBundle(
            env({Kernel: address}),
            {
                ...withMappings({"mainnet.policies.KernelV1": {source}}),
                extraDeployments: custom.extraDeployments,
            },
            loaders(),
        ),
        /No pinned ABI for mainnet.olympus.policies.KernelV1.*--write/,
    );
    // A path that env.json also lists, including an excluded path, fails.
    await assert.rejects(
        generateBundle(
            env({Kernel: address, legacy: {Old: other}}),
            {
                ...config,
                excludedSections: {legacy: {reason: "Pre-V3", keep: []}},
                extraDeployments: {mainnet: {"legacy.Old": other}},
            },
            loaders(),
        ),
        /extraDeployments.mainnet.legacy.Old is also in env.json/,
    );
    // A chain that is not exported fails.
    for (const chain of ["base", "solana"]) {
        await assert.rejects(
            generateBundle(
                env({Kernel: address}),
                {...config, extraDeployments: {[chain]: {"policies.X": other}}},
                loaders(),
            ),
            new RegExp(`extraDeployments.${chain} is not an exported chain`),
        );
    }
});

test("each deployment has one file per chain and labels must be unique in a chain", async () => {
    const custom = withMappings({
        "modules.Kernel": {source},
        "mainnet.modules.Kernel": {...evidence, address: other},
    });
    await assert.rejects(
        generateBundle(env({Kernel: address, modules: {Kernel: other}}), custom, loaders()),
        /mainnet.olympus.modules.Kernel and mainnet.olympus.Kernel have the same ABI file mainnet\/Kernel.json/,
    );
    const twoChains = {
        ...config,
        chains: {mainnet: 1, base: 8453},
        mappings: {...config.mappings, "base.Kernel": {...evidence, address: other}},
    };
    const result = await generateBundle(
        {current: {mainnet: {olympus: {Kernel: address}}, base: {olympus: {Kernel: other}}}},
        twoChains,
        loaders(),
    );
    assert.deepEqual(Object.keys(result.abis), ["base/Kernel.json", "mainnet/Kernel.json"]);
    assert.equal(result.deployments[0].chainId, 8453);
});

test("each source compiles once", async () => {
    const custom = withMappings({Other: {source}, "mainnet.Other": {...evidence, address: other}});
    const counted = loaders();
    const result = await generateBundle(
        env({Kernel: address, Other: other, config: {RoleAdmin: address}}),
        custom,
        counted,
    );
    assert.equal(result.deployments.length, 2);
    assert.deepEqual(Object.keys(result.abis), ["mainnet/Kernel.json", "mainnet/Other.json"]);
    assert.deepEqual(counted.calls, {committed: 0, source: 1});
    assert.equal(result.deployments[0].address, address);
});

test("ABI compatibility hashes include outputs, mutability, event indexing and tuple order", () => {
    assert.equal(abiHash(abi), abiHash([...abi].reverse()));
    const variant = structuredClone(abi);
    variant[0].outputs = [{type: "uint256"}];
    assert.notEqual(abiHash(abi), abiHash(variant));
    variant[0].outputs = [];
    variant[0].stateMutability = "payable";
    assert.notEqual(abiHash(abi), abiHash(variant));
    const tuple = [
        {
            type: "function",
            name: "f",
            inputs: [{type: "tuple", components: [{type: "uint256"}, {type: "address"}]}],
            outputs: [],
            stateMutability: "view",
        },
    ];
    const reordered = structuredClone(tuple);
    reordered[0].inputs[0].components.reverse();
    assert.notEqual(abiHash(tuple), abiHash(reordered));
    assert.notEqual(
        abiHash([
            {
                type: "event",
                name: "E",
                inputs: [{type: "address", indexed: true}],
                anonymous: false,
            },
        ]),
        abiHash([
            {
                type: "event",
                name: "E",
                inputs: [{type: "address", indexed: false}],
                anonymous: false,
            },
        ]),
    );
});

test("zero addresses are omitted, unknown nonzero contracts fail closed", async () => {
    const result = await generateBundle(env({Kernel: "0x" + "0".repeat(40)}), config, loaders());
    assert.equal(result.deployments.length, 0);
    await assert.rejects(
        generateBundle(env({Kernel: address, Future: address}), config, loaders()),
        /No ABI mapping for mainnet.olympus.Future.*shell\/abis\/config.json/,
    );
    await assert.rejects(
        generateBundle(env({Kernel: "broken"}), config, loaders()),
        /Invalid address/,
    );
});

test("unknown chains fail and explicitly excluded chains are recorded", async () => {
    await assert.rejects(
        generateBundle({current: {newChain: {olympus: {Kernel: address}}}}, config, loaders()),
        /Unknown chain/,
    );
    const result = await generateBundle(
        {current: {mainnet: {olympus: {Kernel: address}}, solana: {olympus: {OHM: "base58"}}}},
        config,
        loaders(),
    );
    assert.deepEqual(result.exclusions, [{chain: "solana", reason: "Non-EVM chain"}]);
    // The mappings of an excluded chain are unused and fail.
    await assert.rejects(
        generateBundle(
            {current: {mainnet: {olympus: {Kernel: address}}, solana: {olympus: {}}}},
            withMappings({"solana.OHM": {source}}),
            loaders(),
        ),
        /Unused mappings in shell\/abis\/config.json: solana.OHM/,
    );
});

test("a mapped chain without an olympus section fails with the chain name", async () => {
    for (const chainEntry of [{}, {olympus: null}, {olympus: "0x"}]) {
        await assert.rejects(
            generateBundle({current: {mainnet: chainEntry}}, config, loaders()),
            /Missing olympus section for mainnet/,
        );
    }
});

test("explicit exclusions retain their reasons and need no pinned ABI", async () => {
    const custom = {
        ...config,
        mappings: {Kernel: {source}, "mainnet.Kernel": {exclude: "No bytecode at this address"}},
    };
    const counted = loaders();
    const result = await generateBundle(env({Kernel: address}), custom, counted);
    assert.equal(result.deployments.length, 0);
    assert.match(result.exclusions[0].reason, /No bytecode/);
    assert.equal(result.exclusions[0].address, address);
    assert.deepEqual(counted.calls, {committed: 0, source: 0});
});

test("a source that does not compile fails with the deployment path", async () => {
    await assert.rejects(
        generateBundle(env({Kernel: address}), config, loaders({sources: {}})),
        /Could not compile src\/Kernel.sol:Kernel for mainnet.olympus.Kernel.*Compiler failed/,
    );
    await assert.rejects(
        generateBundle(env({Kernel: address}), config, loaders({sources: {[source]: []}})),
        /Invalid ABI/,
    );
});

test("input order does not affect output and ABI overload/tuple order is preserved", async () => {
    const custom = withMappings({Other: {source}, "mainnet.Other": {...evidence, address: other}});
    const first = await generateBundle(env({Kernel: address, Other: other}), custom, loaders());
    const second = await generateBundle(env({Other: other, Kernel: address}), custom, loaders());
    assert.deepEqual(first, second);
    assert.deepEqual(first.abis["mainnet/Kernel.json"], abi);
});

test("writes one standalone ABI array per deployment and a manifest that references it", async () => {
    const bundle = await generateBundle(env({Kernel: address}), config, loaders());
    const files = await renderFiles(bundle, async (value) => JSON.stringify(value));
    const manifest = JSON.parse(files["manifest.json"]);
    assert.deepEqual(JSON.parse(files[manifest.deployments[0].abi]), abi);
    assert.equal(manifest.abis, undefined);
    assert.equal(manifest.schemaVersion, 3);
    assert.deepEqual(Object.keys(files).sort(), ["mainnet/Kernel.json", "manifest.json"]);
});

test("check detects missing, edited and obsolete files without writing; generation removes stale ABIs", async () => {
    const dir = await mkdtemp(join(tmpdir(), "abi-test-"));
    const path = join(dir, "manifest.json");
    const file = "mainnet/Kernel.json";
    const files = {"manifest.json": "expected\n", [file]: "[]\n"};
    try {
        await assert.rejects(saveFiles(dir, files, true), /out of date/);
        await saveFiles(dir, files, false);
        await saveFiles(dir, files, true);
        await writeFile(path, "obsolete\n");
        await assert.rejects(saveFiles(dir, files, true), /manifest.json/);
        assert.equal(await readFile(path, "utf8"), "obsolete\n");
        await saveFiles(dir, files, false);
        const abiPath = join(dir, file);
        await writeFile(abiPath, "edited\n");
        await assert.rejects(saveFiles(dir, files, true), /mainnet\/Kernel.json/);
        assert.equal(await readFile(abiPath, "utf8"), "edited\n");
        await saveFiles(dir, files, false);
        // A stale file in a known chain, and the folder of the old hash store.
        await writeFile(join(dir, "mainnet/Stale.json"), "[]\n");
        await mkdir(join(dir, "deployed"));
        await writeFile(join(dir, `deployed/${hash}.json`), "[]\n");
        await writeFile(join(dir, "README.md"), "keep me\n");
        await assert.rejects(saveFiles(dir, files, true), /deployed\/.*mainnet\/Stale.json/);
        assert.equal(await readFile(join(dir, "mainnet/Stale.json"), "utf8"), "[]\n");
        await saveFiles(dir, files, false);
        await assert.rejects(readFile(join(dir, "mainnet/Stale.json")), {code: "ENOENT"});
        await assert.rejects(readdir(join(dir, "deployed")), {code: "ENOENT"});
        assert.equal(await readFile(join(dir, "README.md"), "utf8"), "keep me\n");
        await rm(abiPath);
        await assert.rejects(saveFiles(dir, files, true), /mainnet\/Kernel.json/);
    } finally {
        await rm(dir, {recursive: true, force: true});
    }
});

test("online verification binds requests to chain/address and rejects unverified sources", async () => {
    const verified = await lookupVerifiedAbi(1, address, "test-key", async (url) => {
        assert.equal(url.searchParams.get("chainid"), "1");
        assert.equal(url.searchParams.get("address"), address);
        return {
            ok: true,
            json: async () => ({
                status: "1",
                result: [
                    {
                        ContractName: "Kernel",
                        SourceCode: "verified source",
                        ABI: JSON.stringify(abi),
                        Implementation: "",
                    },
                ],
            }),
        };
    });
    assert.deepEqual(verified.abi, abi);
    await assert.rejects(
        lookupVerifiedAbi(1, address, "test-key", async () => ({
            ok: true,
            json: async () => ({
                status: "1",
                result: [
                    {ContractName: "", SourceCode: "", ABI: "Contract source code not verified"},
                ],
            }),
        })),
        /Verified source unavailable/,
    );
});

test("verification writes pin new and changed deployments and keep their source link", () => {
    const deployment = {chain: "mainnet", chainId: 1, path: "Kernel", address};
    const verified = {contractName: "Kernel", abi, implementation: null};

    const match = applyVerification(config.mappings, deployment, verified);
    assert.equal(match.status, "match");
    assert.deepEqual(match.mapping, evidence);

    const unmapped = applyVerification({Kernel: {source}}, deployment, verified);
    assert.equal(unmapped.status, "unmapped");
    assert.equal(unmapped.mapping.address, address);
    assert.equal(unmapped.mapping.abiHash, hash);
    assert.equal(unmapped.mapping.contractName, "Kernel");
    assert.match(unmapped.mapping.sourceUrl, /chainid=1&.*address=0x1111/);
    assert.doesNotMatch(unmapped.mapping.sourceUrl, /apikey/);

    const moved = applyVerification(
        {
            ...config.mappings,
            "mainnet.Kernel": {...evidence, address: other, source, implementationHint: other},
        },
        deployment,
        verified,
    );
    assert.equal(moved.status, "changed");
    assert.equal(moved.mapping.address, address);
    assert.equal(moved.mapping.source, source);
    assert.equal(moved.mapping.implementationHint, undefined);

    const upgraded = applyVerification(config.mappings, deployment, {
        contractName: "Kernel",
        abi: abi.slice(1),
        implementation: other,
    });
    assert.equal(upgraded.status, "mismatch");
    assert.equal(upgraded.mapping.abiHash, abiHash(abi.slice(1)));
    assert.equal(upgraded.mapping.implementationHint, other);
});
