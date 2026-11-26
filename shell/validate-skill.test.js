const assert = require("node:assert/strict");
const {spawnSync} = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const {test} = require("node:test");
const {validateSkill} = require("./validate-skill");

const script = path.join(__dirname, "validate-skill.js");

function skill(t, content) {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), "olympus-skill-test-"));
    t.after(() => fs.rmSync(root, {recursive: true, force: true}));
    if (content !== null) fs.writeFileSync(path.join(root, "SKILL.md"), content);
    return root;
}

function document(
    frontmatter = "name: example\ndescription: A useful skill",
    body = "# Example\n",
) {
    return `---\n${frontmatter}\n---\n${body}`;
}

const cases = [
    ["valid metadata", document(), true],
    ["missing file", null, false, "SKILL.md not found"],
    ["missing frontmatter", "# Example", false, "No YAML frontmatter"],
    ["unterminated frontmatter", "---\nname: example", false, "Invalid frontmatter format"],
    ["invalid YAML", document("name: [\ndescription: test"), false, "Invalid YAML"],
    [
        "unknown YAML tag",
        document("name: !custom example\ndescription: test"),
        false,
        "Invalid YAML",
    ],
    ["mapping required", document("- name\n- description"), false, "YAML dictionary"],
    ["empty YAML document", document(""), false, "YAML dictionary"],
    ["scalar required to be mapping", document("example"), false, "YAML dictionary"],
    ["missing name", document("description: test"), false, "Missing 'name'"],
    ["missing description", document("name: example"), false, "Missing 'description'"],
    [
        "unknown property",
        document("name: example\ndescription: test\nextra: true"),
        false,
        "Unexpected key",
    ],
    ["numeric name", document("name: 42\ndescription: test"), false, "Name must be a string"],
    [
        "YAML 1.1 boolean name",
        document("name: yes\ndescription: test"),
        false,
        "Name must be a string",
    ],
    ["quoted boolean name", document('name: "yes"\ndescription: test'), true],
    ["uppercase name", document("name: Example\ndescription: test"), false, "hyphen-case"],
    ["underscore name", document("name: example_skill\ndescription: test"), false, "hyphen-case"],
    [
        "leading hyphen",
        document("name: -example\ndescription: test"),
        false,
        "start/end with hyphen",
    ],
    [
        "trailing hyphen",
        document("name: example-\ndescription: test"),
        false,
        "start/end with hyphen",
    ],
    [
        "consecutive hyphens",
        document("name: example--skill\ndescription: test"),
        false,
        "consecutive hyphens",
    ],
    ["name at maximum", document(`name: ${"a".repeat(64)}\ndescription: test`), true],
    [
        "name above maximum",
        document(`name: ${"a".repeat(65)}\ndescription: test`),
        false,
        "Name is too long",
    ],
    [
        "non-string description",
        document("name: example\ndescription: false"),
        false,
        "Description must be a string",
    ],
    ["description at maximum", document(`name: example\ndescription: ${"a".repeat(1024)}`), true],
    [
        "description above maximum",
        document(`name: example\ndescription: ${"a".repeat(1025)}`),
        false,
        "Description is too long",
    ],
    [
        "Unicode description length",
        document(`name: example\ndescription: ${"😀".repeat(1024)}`),
        true,
    ],
    [
        "angle brackets",
        document('name: example\ndescription: "Use <example>"'),
        false,
        "angle brackets",
    ],
    [
        "unfinished description",
        document('name: example\ndescription: "[TODO: describe]"'),
        false,
        "unfinished TODO",
    ],
    ["unfinished body", document(undefined, "   [TODO: finish this]\n"), false, "unfinished TODO"],
    ["TODO in prose", document(undefined, "Use [TODO: example] to demonstrate a marker.\n"), true],
    ["TODO in code fence", document(undefined, "```text\n[TODO: example]\n```\n"), true],
    [
        "TODO after closed fence",
        document(undefined, "```text\nexample\n```\n[TODO: finish]\n"),
        false,
        "unfinished TODO",
    ],
    [
        "shorter fence stays open",
        document(undefined, "````text\n```\n[TODO: example]\n````\n"),
        true,
    ],
    [
        "different marker stays open",
        document(undefined, "```text\n~~~\n[TODO: example]\n```\n"),
        true,
    ],
    [
        "list fence closes",
        document(undefined, "- ~~~text\n[TODO: example]\n  ~~~\n[TODO: finish]\n"),
        false,
        "unfinished TODO",
    ],
    ["CRLF files", document().replaceAll("\n", "\r\n"), true],
    [
        "optional metadata",
        document(
            "name: example\ndescription: test\nlicense: MIT\nallowed-tools: [Read]\nmetadata:\n  category: test",
        ),
        true,
    ],
    [
        "last duplicate wins like safe_load",
        document("name: INVALID\nname: example\ndescription: test"),
        true,
    ],
    ["present empty strings retain upstream behavior", document('name: ""\ndescription: ""'), true],
];

for (const [name, content, expected, errorText] of cases) {
    test(name, (t) => {
        const [valid, message] = validateSkill(skill(t, content));
        assert.equal(valid, expected, message);
        if (errorText) assert.ok(message.includes(errorText), message);
    });
}

test("CLI reports success and leaves source unchanged", (t) => {
    const content = document();
    const root = skill(t, content);
    const result = spawnSync(process.execPath, [script, root], {encoding: "utf8"});
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /Skill is valid!/);
    assert.equal(fs.readFileSync(path.join(root, "SKILL.md"), "utf8"), content);
});

test("CLI exits unsuccessfully for invalid metadata", (t) => {
    const root = skill(t, document("name: example"));
    const result = spawnSync(process.execPath, [script, root], {encoding: "utf8"});
    assert.equal(result.status, 1);
    assert.match(result.stdout, /Missing 'description'/);
});

test("CLI rejects missing and extra arguments", () => {
    for (const args of [[], ["one", "two"]]) {
        const result = spawnSync(process.execPath, [script, ...args], {encoding: "utf8"});
        assert.equal(result.status, 1);
        assert.match(result.stderr, /Usage:/);
    }
});
