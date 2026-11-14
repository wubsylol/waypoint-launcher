import unittest
from inspect_protocol import MAX_BYTES, fields, inspect, numeric_options, varint, message, enumeration


def v(n):
    result = bytearray()
    while n >= 128:
        result.append((n & 127) | 128)
        n >>= 7
    result.append(n)
    return bytes(result)


def b(number, value):
    return v(number << 3 | 2) + v(len(value)) + value


class DescriptorTests(unittest.TestCase):
    def test_varint_bounds(self):
        self.assertEqual(varint(v(2**64 - 1), 0)[0], 2**64 - 1)
        for malformed in (b'\x80', b'\xff' * 10, b'\x80' * 11):
            with self.assertRaises(ValueError):
                varint(malformed, 0)

    def test_rejects_truncated_fixed_and_lengths(self):
        for malformed in (b'\x09\x00', b'\x0d\x00', b'\x0a\x09short', b'\x0f', b'\x00'):
            with self.assertRaises(ValueError):
                fields(malformed)

    def test_fixed_width_and_embedded_zero(self):
        self.assertEqual(fields(b'\x09' + (42).to_bytes(8, 'little'))[0], {1: [42]})
        self.assertEqual(fields(b(1, b'\x00x'))[0], {1: [b'\x00x']})

    def test_requires_real_terminator_and_size_limit(self):
        with self.assertRaises(ValueError):
            fields(b(1, b'name'), terminated=True)
        with self.assertRaises(ValueError):
            fields(b'x' * (MAX_BYTES + 1))

    def test_extracts_only_allowlisted_static_metadata(self):
        filename = 'bgs/low/pb/client/test.proto'
        descriptor = b(1, filename.encode()) + b(2, b'bgs.protocol.test')
        blob = b'ignored private text' + descriptor + b'\x00extra data'
        result = inspect(blob, files=(filename,))
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]['package'], 'bgs.protocol.test')
        self.assertNotIn('private', str(result))
        self.assertEqual(inspect(blob, files=('bgs/low/pb/client/absent.proto',)), [])

    def test_rejects_wrong_package_and_duplicate_file_name(self):
        filename = 'bgs/low/pb/client/test.proto'
        for extra in (b(2, b'other.package'), b(1, filename.encode())):
            with self.assertRaises(ValueError):
                inspect(b(1, filename.encode()) + extra + b'\x00', files=(filename,))

    def test_options_never_emit_arbitrary_strings_or_opaque_values(self):
        options = b(90000, b'\x08\x05') + b(90000, b(4, b'opaque-private-value'))
        result = numeric_options({4: [options]}, 4)
        self.assertEqual(result[0]['numericFields'], {'1': [5]})
        self.assertNotIn('private', str(result))
        self.assertNotIn('opaque', str(result))

    def test_message_rejects_nonnumeric_or_out_of_range_fields(self):
        def number(n, value):
            return v(n << 3) + v(value)
        for invalid_number, label, kind in [(b(3, b'private'), 1, 9), (number(3, 0), 1, 9),
                                            (number(3, 1), 99, 9), (number(3, 1), 1, 99)]:
            entry = b(1, b'field') + invalid_number + number(4, label) + number(5, kind)
            with self.assertRaises(ValueError):
                message(b(1, b'Message') + b(2, entry))

    def test_enum_validates_signed_int32(self):
        negative = b(1, b'NEGATIVE') + v(2 << 3) + v(2**64 - 1)
        result = enumeration(b(1, b'Enum') + b(2, negative))
        self.assertEqual(result['values'][0]['number'], -1)
        oversized = b(1, b'OVERSIZED') + v(2 << 3) + v(2**31)
        with self.assertRaises(ValueError):
            enumeration(b(1, b'Enum') + b(2, oversized))


if __name__ == '__main__':
    unittest.main()
