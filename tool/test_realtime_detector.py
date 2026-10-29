"""Dependency-free tests for the detector's bounded frame handoff.

Run: python -m unittest discover -s tool -p test_realtime_detector.py
"""

from queue import Queue
import unittest

from realtime_detector import LatestFrame, offer_latest


class FrameHandoffTests(unittest.TestCase):
    def test_pending_frame_is_replaced_with_newest(self):
        frames = Queue(maxsize=1)
        offer_latest(frames, "old")
        offer_latest(frames, "new")
        self.assertEqual(frames.get_nowait(), "new")
        self.assertTrue(frames.empty())

    def test_slow_consumer_does_not_build_a_backlog(self):
        frames = Queue(maxsize=1)
        for sequence in range(1000):
            offer_latest(frames, sequence)
        self.assertEqual(frames.qsize(), 1)
        self.assertEqual(frames.get_nowait(), 999)

    def test_latest_capture_is_available_without_waiting_for_inference(self):
        latest = LatestFrame()
        self.assertIsNone(latest.read())
        latest.publish((1, "first"))
        latest.publish((2, "second"))
        self.assertEqual(latest.read(), (2, "second"))


if __name__ == "__main__":
    unittest.main()
