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


def layout(*elements, display="Main"):
    body = " ".join(
        f"<SBSDisplayLayoutElement: 0x1; {element}; frame: {{{{0, 0}}, {{1180, 820}}}}; "
        f"level: {level}; role: {role}>;"
        for element, level, role in elements
    )
    return (
        f"_updateLayout <FBSDisplayLayout: 0x0; displayIdentity: {display}> "
        f"{{ backlightState = 2; elements = {{ {body} }} }} reason: systemgesture"
    )


HOME = ("com.apple.springboard.home-screen", 0, "primary")
DOCK = ("com.apple.springboard.floating-dock", 25, "overlay")
MAIL = ("sceneID:com.apple.mobilemail-639D; bundleID: com.apple.mobilemail", 1, "primary")


class ForegroundLayoutTests(unittest.TestCase):
    """Protect the Home Screen pickup gate in screenshot-capture.md."""

    def test_home_screen_is_not_an_open_app(self):
        self.assertIs(telemetry.app_open(layout(HOME, DOCK)), False)

    def test_open_app_and_swipe_home_transition_count_as_app(self):
        self.assertIs(telemetry.app_open(layout(MAIL)), True)
        self.assertIs(telemetry.app_open(layout(HOME, MAIL, DOCK)), True)

    def test_modal_overlays_do_not_hide_home(self):
        modal = ("ABC-RemoteAlert; bundleID: com.apple.SafariViewService", 1057, "fullScreenModal")
        self.assertIs(telemetry.app_open(layout(HOME, modal)), False)

    def test_sidecar_on_screen_does_not_block_repeat_pickups(self):
        sidecar = ("sceneID:com.apple.sidecar-1; bundleID: com.apple.sidecar", 1, "primary")
        self.assertIs(telemetry.app_open(layout(HOME, sidecar)), False)

    def test_unrelated_or_external_display_lines_are_unknown(self):
        self.assertIsNone(telemetry.app_open("Root folder controller view will appear"))
        self.assertIsNone(telemetry.app_open(layout(MAIL, display="External")))


if __name__ == "__main__":
    unittest.main()
