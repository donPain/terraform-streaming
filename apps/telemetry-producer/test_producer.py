import unittest

from producer import generate_event


class ProducerTest(unittest.TestCase):
    def test_valid_and_malformed_events(self):
        event = generate_event()
        self.assertEqual(
            set(event),
            {"machineId", "timestamp", "latitude", "longitude", "speed", "temperature", "fuelLevel"},
        )
        self.assertNotIn("machineId", generate_event(malformed=True))


if __name__ == "__main__":
    unittest.main()
