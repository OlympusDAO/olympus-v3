"""Regression check for tests shared by sibling scenario documents."""

import tempfile
import unittest
from pathlib import Path

from check_mapping import check


class SharedMappingTest(unittest.TestCase):
    def test_reference_definitions_must_follow_all_content(self):
        for trailing_content in ("## More cases", "| More | table content |"):
            with self.subTest(content=trailing_content), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                (root / "fee.t.sol").write_text(
                    "// Scenarios: FEE-P01.\nfunction test_fee() public {}\n"
                )
                document = root / "fee.md"
                document.write_text(
                    "| FEE-P01 | Covered: [test][test_fee] |\n\n"
                    "[test_fee]: fee.t.sol#L1\n\n" + trailing_content + "\n"
                )
                original = document.read_text()
                self.assertEqual(
                    check(document, update=True),
                    (["line 5: reference definitions must be at the end of the file"], 0),
                    "Tables and other content must precede every reference definition",
                )
                self.assertEqual(document.read_text(), original, "Invalid placement prevents rewrites")

    def test_final_reference_footer_allows_blank_lines(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "fee.t.sol").write_text(
                "// Scenarios: FEE-P01.\nfunction test_fee() public {}\n"
            )
            document = root / "fee.md"
            document.write_text(
                "| FEE-P01 | Covered: [test][test_fee] |\n\n"
                "[context]: ../context.md\n\n"
                "[test_fee]: fee.t.sol#L2\n\n"
            )
            self.assertEqual(check(document), ([], 0), "Blank lines do not break a final footer")

    def test_shared_ids_can_belong_to_another_suite(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "src" / "test" / "policies"
            left, right = root / "Left", root / "Right"
            left.mkdir(parents=True)
            right.mkdir()
            source = right / "shared.t.sol"
            source.write_text(
                "// Scenarios: LEFT-P01, RIGHT-P01.\nfunction test_shared() public {}\n"
            )
            (right / "action.md").write_text("| RIGHT-P01 | Covered: shared proof |\n")
            document = left / "action.md"
            document.write_text(
                "| LEFT-P01 | Covered: [test][test_shared] |\n\n"
                "[test_shared]: ../Right/shared.t.sol#L2\n"
            )
            self.assertEqual(check(document), ([], 0), "Existing cross-suite IDs are valid")
            source.write_text(
                "// Scenarios: LEFT-P01, RIGHT-TYPO.\nfunction test_shared() public {}\n"
            )
            self.assertEqual(
                check(document),
                (["test_shared: unknown scenario ID in Scenarios comment: RIGHT-TYPO"], 0),
                "Cross-suite lookup must still reject IDs absent from every scenario document",
            )

    def test_inline_table_links_are_rejected_when_named_links_are_also_present(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "fee.t.sol").write_text(
                "// Scenarios: FEE-P01.\nfunction test_fee() public {}\n"
            )
            document = root / "fee.md"
            document.write_text(
                "| FEE-P01 | Covered: [test][test_fee], [duplicate](fee.t.sol#L2) |\n\n"
                "[test_fee]: fee.t.sol#L1\n"
            )
            original = document.read_text()
            errors, changed = check(document, update=True)
            self.assertEqual(
                errors,
                ["line 1: inline test links must use named references"],
                "Mixed table styles must be rejected before updating anchors",
            )
            self.assertEqual(changed, 0, "Invalid table style must not rewrite the document")
            self.assertEqual(document.read_text(), original, "Invalid mappings remain unchanged")

    def test_file_qualified_references_disambiguate_same_named_tests(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for filename, scenario in (("cap", "FEE-A01"), ("minimum", "FEE-A02")):
                (root / f"{filename}.t.sol").write_text(
                    f"// Scenarios: {scenario}.\nfunction test_shared() public {{}}\n"
                )
            document = root / "fee.md"
            document.write_text(
                "| FEE-A01 | Covered: [cap][test_shared--cap] |\n"
                "| FEE-A02 | Covered: [minimum][test_shared--minimum] |\n\n"
                "[test_shared--cap]: cap.t.sol#L1\n"
                "[test_shared--minimum]: minimum.t.sol#L1\n"
            )
            self.assertEqual(
                check(document, update=True),
                ([], 2),
                "Each reference must resolve its own file, function and reciprocal scenario",
            )
            updated = document.read_text()
            self.assertIn("[test_shared--cap]: cap.t.sol#L2", updated)
            self.assertIn("[test_shared--minimum]: minimum.t.sol#L2", updated)
            self.assertEqual(check(document), ([], 0), "Qualified mappings remain valid")

    def test_inline_links_outside_tables_are_allowed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "fee.t.sol").write_text(
                "// Scenarios: FEE-P01.\nfunction test_fee() public {}\n"
            )
            document = root / "fee.md"
            document.write_text(
                "Context: [fee test](fee.t.sol#L2).\n\n"
                "| FEE-P01 | Covered: [test][test_fee] |\n\n"
                "[test_fee]: fee.t.sol#L2\n"
            )
            self.assertEqual(check(document), ([], 0), "Only table links need indirection")

    def test_invariant_references_are_checked(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "invariant.t.sol"
            source.write_text("// Scenarios: FEE-S01.\nfunction invariant_accounting() public {}\n")
            document = root / "fee.md"
            document.write_text(
                "| FEE-S01 | Covered: [test][invariant_accounting] |\n\n"
                "[invariant_accounting]: invariant.t.sol#L2\n"
            )
            self.assertEqual(check(document), ([], 0), "Named invariants should be valid")
            source.write_text("\nfunction invariant_accounting() public {}\n")
            self.assertEqual(
                check(document),
                (["FEE-S01: missing reciprocal Scenarios comment on invariant_accounting"], 0),
                "Invariants must also have reciprocal comments",
            )

    def test_shared_ids_and_anchor_updates_preserve_validation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "shared.t.sol"
            original = "// Scenarios: FEE-N01, HEALTH-N01.\nfunction test_shared() public {}\n"
            source.write_text(original)
            documents = []
            for name in ("fee", "health"):
                document = root / f"{name}.md"
                document.write_text(
                    f"| {name.upper()}-N01 | Covered: [test][test_shared] |\n\n"
                    "[test_shared]: shared.t.sol#L2\n"
                )
                documents.append(document)

            for document in documents:
                self.assertEqual(check(document), ([], 0), "Shared IDs should be valid")
                document.write_text(document.read_text().replace("#L2", "#L1"))
                self.assertEqual(check(document, update=True), ([], 1), "Refresh stale anchors")
                self.assertIn("#L2", document.read_text(), "Anchor should point to the function")

            document = documents[0]
            document.write_text(document.read_text().replace("#L2", "#L1"))
            before = document.read_text()
            source.write_text(original.replace("HEALTH-N01", "HEALTH-TYPO"))
            self.assertEqual(
                check(document, update=True),
                (["test_shared: unknown scenario ID in Scenarios comment: HEALTH-TYPO"], 0),
                "Unknown IDs should still fail",
            )
            self.assertEqual(document.read_text(), before, "Invalid mappings must not be rewritten")

            source.write_text(original.replace("FEE-N01, ", ""))
            self.assertEqual(
                check(document, update=True),
                (["FEE-N01: missing reciprocal Scenarios comment on test_shared"], 0),
                "Local rows must still have reciprocal comments",
            )

            source.write_text(original.replace("HEALTH-N01", "HEALTH-N01, FEE-N02"))
            document.write_text("| FEE-N02 | Unmapped |\n" + before)
            self.assertEqual(
                check(document, update=True),
                (["FEE-N02: missing reciprocal test reference for test_shared"], 0),
                "Local comments must still have reciprocal row references",
            )


if __name__ == "__main__":
    unittest.main()
