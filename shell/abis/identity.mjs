import {createHash} from "node:crypto";

function parameterType(parameter) {
    return parameter.type.startsWith("tuple")
        ? `(${parameter.components.map(parameterType).join(",")})${parameter.type.slice(5)}`
        : parameter.type;
}

// Compare the callable ABI, not compiler-specific internalType descriptions,
// declaration order, argument names, or deployment constructor arguments.
export function canonicalAbi(abi) {
    return [
        ...new Set(
            abi
                .filter((entry) => entry.type !== "constructor")
                .map((entry) =>
                    JSON.stringify({
                        type: entry.type,
                        name: entry.name,
                        inputs: entry.inputs?.map((parameter) => ({
                            type: parameterType(parameter),
                            ...(entry.type === "event" ? {indexed: parameter.indexed} : {}),
                        })),
                        outputs: entry.outputs?.map(parameterType),
                        ...(entry.type === "event" ? {anonymous: entry.anonymous} : {}),
                        ...(["function", "fallback", "receive"].includes(entry.type)
                            ? {
                                  mutability:
                                      entry.stateMutability ||
                                      (entry.constant
                                          ? "view"
                                          : entry.payable
                                            ? "payable"
                                            : "nonpayable"),
                              }
                            : {}),
                    }),
                ),
        ),
    ].sort();
}

export function abiHash(abi) {
    return createHash("sha256")
        .update(JSON.stringify(canonicalAbi(abi)))
        .digest("hex");
}

// True when every callable entry of `subset` is also in `abi`, such as an interface
// that a deployed contract implements.
export function covers(abi, subset) {
    const entries = new Set(canonicalAbi(abi));
    return canonicalAbi(subset).every((entry) => entries.has(entry));
}

export function isAbi(value) {
    return (
        Array.isArray(value) &&
        value.length > 0 &&
        value.every((entry) => entry && typeof entry.type === "string")
    );
}
