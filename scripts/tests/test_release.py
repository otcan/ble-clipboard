import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
import notarize_candidate
from release_assets import checksums, digest, hashes, payloads


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / "VERSION").write_text("0.5.4\n")
        self.out = self.root / "dist/v0.5.4"
        self.out.mkdir(parents=True)
        for name in payloads("0.5.4"):
            (self.out / name).write_bytes(name.encode())

    def test_complete_canonical_checksums_and_mismatch_guard(self):
        checksums(self.out, "0.5.4")
        checksums(self.out, "0.5.4", verify=True)
        self.assertEqual(
            len((self.out / "SHA256SUMS.txt").read_text().splitlines()), 11
        )
        (self.out / "ble_clipboard.fap").write_bytes(b"different")
        with self.assertRaises(ValueError):
            checksums(self.out, "0.5.4", verify=True)
        (self.out / "ble_clipboard.fap").unlink()
        with self.assertRaises(ValueError):
            hashes(self.out, "0.5.4")

    def test_missing_receipt_after_attempt_never_submits(self):
        logs = self.root / "dist/notary-logs/v0.5.4"
        logs.mkdir(parents=True)
        (logs / "SUBMISSION-STARTED").touch()
        with (
            patch.object(notarize_candidate, "ROOT", self.root),
            patch.object(notarize_candidate, "run", return_value="reviewed") as run,
        ):
            with self.assertRaisesRegex(ValueError, "without candidate metadata"):
                notarize_candidate.main("0.5.4")
        self.assertEqual(
            [call.args[:2] for call in run.call_args_list], [("git", "rev-parse")]
        )

    def test_existing_submission_only_polls_no_build_or_resubmit(self):
        logs = self.root / "dist/notary-logs/v0.5.4"
        logs.mkdir(parents=True)
        archive = "BLE-Clipboard-0.5.4-universal.zip"
        (logs / archive).write_bytes((self.out / archive).read_bytes())
        candidate = {
            "version": "0.5.4",
            "build": "1",
            "team": "TESTTEAM00",
            "revision": "reviewed",
            "submittedSHA256": digest(logs / archive),
            "payloads": hashes(self.out, "0.5.4"),
        }
        (logs / "candidate.json").write_text(json.dumps(candidate))
        (logs / "submission.json").write_text(json.dumps({"id": "already-submitted"}))
        (logs / "SUBMISSION-STARTED").touch()

        def run(*args, **kwargs):
            if args[:2] == ("git", "rev-parse"):
                return "reviewed"
            self.assertEqual(
                args[:4], ("xcrun", "notarytool", "info", "already-submitted")
            )
            return json.dumps({"status": "In Progress"})

        with (
            patch.object(notarize_candidate, "ROOT", self.root),
            patch.object(notarize_candidate, "run", side_effect=run),
            patch.object(notarize_candidate, "verify_app"),
        ):
            self.assertEqual(notarize_candidate.main("0.5.4"), 3)
        self.assertEqual(digest(logs / archive), candidate["submittedSHA256"])
