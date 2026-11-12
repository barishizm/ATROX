import unittest

import convert


def last_point(commands):
    letter, nums = commands[-1]
    return tuple(nums[-2:]) if nums else None


class NormalizePathTests(unittest.TestCase):
    def test_relative_commands_become_absolute(self):
        cmds = convert.normalize_path("M10 10 l5 0 h5 v5 z")
        self.assertEqual([c[0] for c in cmds], ["M", "L", "L", "L", "Z"])
        self.assertEqual(cmds[3][1], [20.0, 15.0])

    def test_implicit_lineto_after_moveto(self):
        cmds = convert.normalize_path("m1 1 2 2 3 3")
        self.assertEqual(cmds, [("M", [1.0, 1.0]), ("L", [3.0, 3.0]), ("L", [6.0, 6.0])])

    def test_packed_arc_flags(self):
        # '0 012.89 1.12' = rotation 0, large=0, sweep=1, x=2.89, y=1.12 (as in the upstream data)
        cmds = convert.normalize_path("M0 0a1.71 1.71 0 012.89 1.12")
        self.assertTrue(all(c[0] in "MC" for c in cmds))
        self.assertAlmostEqual(last_point(cmds)[0], 2.89, places=6)
        self.assertAlmostEqual(last_point(cmds)[1], 1.12, places=6)

    def test_smooth_curves_and_quad_shortcuts_expand(self):
        cmds = convert.normalize_path("M0 0 C1 1 2 1 3 0 S5 -1 6 0 Q7 1 8 0 T10 0")
        self.assertEqual([c[0] for c in cmds], ["M", "C", "C", "Q", "Q"])
        self.assertEqual(cmds[2][1][:2], [4.0, -1.0])  # reflected control point
        self.assertEqual(cmds[4][1][:2], [9.0, -1.0])

    def test_offset_shifts_x_only(self):
        cmds = convert.normalize_path("M800 10 L810 20", dx=724)
        self.assertEqual(cmds, [("M", [76.0, 10.0]), ("L", [86.0, 20.0])])

    def test_serialization_is_compact(self):
        self.assertEqual(convert.serialize([("M", [1.0, 2.25]), ("Z", [])]), "M 1 2.2 Z")


class MappingTests(unittest.TestCase):
    def test_every_catalog_muscle_has_a_region(self):
        self.assertEqual(len(convert.MUSCLES), 17)
        for muscle in convert.MUSCLES:
            self.assertTrue(convert.MUSCLE_REGIONS[muscle], muscle)

    def test_camel_case(self):
        self.assertEqual(convert.camel("lower_back"), "lowerBack")
        self.assertEqual(convert.camel("biceps"), "biceps")

    def test_shared_region_lists_both_muscles(self):
        self.assertEqual(convert.region_muscles("back", "upper-back"), ["lats", "middle_back"])
        self.assertEqual(convert.region_muscles("front", "head"), [])


if __name__ == "__main__":
    unittest.main()
