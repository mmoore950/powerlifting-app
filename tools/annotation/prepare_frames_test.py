import unittest
from fractions import Fraction
from prepare_frames import exact_timestamp


class ExactDecodedTimeTests(unittest.TestCase):
    def test_non_unit_time_base(self):
        self.assertEqual(exact_timestamp(1, Fraction(3003, 90000)),
                         {'value': '1001', 'timescale': 30000, 'epoch': 0})

    def test_large_pts_preserves_integer_string(self):
        self.assertEqual(exact_timestamp(9007199254740993, Fraction(1, 600))['value'], '3002399751580331')
        # Reduction is exact (the original numerator is divisible by three).
        t = exact_timestamp(9007199254740993, Fraction(1, 600))
        self.assertEqual(Fraction(int(t['value']), t['timescale']), Fraction(9007199254740993, 600))

    def test_unsupported_contract_range(self):
        with self.assertRaises(ValueError):
            exact_timestamp(2**63, Fraction(1, 1))
        with self.assertRaises(ValueError):
            exact_timestamp(1, Fraction(1, 2147483648))


if __name__ == '__main__':
    unittest.main()
