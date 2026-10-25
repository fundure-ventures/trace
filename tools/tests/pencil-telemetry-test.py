import importlib.util
from pathlib import Path
import unittest


spec = importlib.util.spec_from_file_location(
    "pencil_telemetry", Path(__file__).resolve().parents[1] / "pencil-telemetry.py"
)
telemetry = importlib.util.module_from_spec(spec)
spec.loader.exec_module(telemetry)


class PencilTelemetryTests(unittest.TestCase):
    """Protect the experimental Pencil capture scenarios in screenshot-capture.md."""

    def test_pickup_and_return_at_full_charge(self):
        prefix = "SpringBoard(BatteryCenter): name = Apple Pencil; percentCharge = 100;"
        self.assertEqual(telemetry.pencil_state(prefix + " charging = NO;"), (False, False))
        self.assertEqual(telemetry.pencil_state(prefix + " charging = YES;"), (True, False))

    def test_explicit_attachment_events(self):
        self.assertEqual(
            telemetry.pencil_state("searchpartyd: Unsupported pencil detached."),
            (False, True),
        )
        self.assertEqual(
            telemetry.pencil_state("BTLEServer: Pencil2 received HID charger notification: attached"),
            (True, True),
        )

    def test_unrelated_battery_or_pencil_activity_does_not_trigger(self):
        for line in [
            "SpringBoard(BatteryCenter): name = iPad; charging = NO;",
            "Pencil2 received pairing info",
            "SpringBoard(BatteryCenter): name = Apple Pencil; connected = NO;",
        ]:
            self.assertIsNone(telemetry.pencil_state(line))

    def test_startup_is_baseline_and_duplicate_events_do_not_capture(self):
        tracker = telemetry.PencilStateTracker()
        attached = "SpringBoard(BatteryCenter): name = Apple Pencil; charging = YES;"
        detached = "SpringBoard(BatteryCenter): name = Apple Pencil; charging = NO;"
        self.assertEqual(tracker.update(attached), {"charging": True, "baseline": True})
        self.assertIsNone(tracker.update(attached))
        self.assertEqual(tracker.update(detached), {"charging": False, "baseline": False})
        self.assertIsNone(tracker.update("searchpartyd: Unsupported pencil detached."))
        self.assertEqual(tracker.update(attached), {"charging": True, "baseline": False})

    def test_reconnection_while_pencil_is_away_does_not_capture(self):
        detached = "SpringBoard(BatteryCenter): name = Apple Pencil; charging = NO;"
        self.assertEqual(
            telemetry.PencilStateTracker().update(detached),
            {"charging": False, "baseline": True},
        )
        self.assertEqual(
            telemetry.PencilStateTracker().update("searchpartyd: Unsupported pencil detached."),
            {"charging": False, "baseline": False},
        )


if __name__ == "__main__":
    unittest.main()
