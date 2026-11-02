"""Regression check for tests shared by sibling scenario documents."""

import tempfile
import unittest
from pathlib import Path

from check_mapping import check


class SharedMappingTest(unittest.TestCase):
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
            document.write_text(before + "| FEE-N02 | Unmapped |\n")
            self.assertEqual(
                check(document, update=True),
                (["FEE-N02: missing reciprocal test reference for test_shared"], 0),
                "Local comments must still have reciprocal row references",
            )


if __name__ == "__main__":
    unittest.main()
