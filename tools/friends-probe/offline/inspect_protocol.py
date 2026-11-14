#!/usr/bin/env python3
"""Inspect only allowlisted static BGS schema metadata. No network/auth imports."""
import argparse
import hashlib
import json
from pathlib import Path

MAX_BYTES = 1_048_576
MAX_FIELDS = 4096
PREFIX = 'bgs/low/pb/client/'
FILES = tuple(PREFIX + name for name in (
    'rpc_types.proto', 'connection_service.proto',
    'global_extensions/method_options.proto', 'global_extensions/service_options.proto',
    'global_extensions/routing.proto', 'global_extensions/register_method_types.proto',
    'api/client/v2/authentication_service.proto', 'api/client/v2/authentication_types.proto',
    'api/client/v2/authentication_listener.proto', 'api/client/v2/session_service.proto',
    'api/client/v2/session_types.proto', 'api/client/v2/session_listener.proto',
    'api/client/v2/friends_service.proto', 'api/client/v2/friends_types.proto',
    'api/client/v2/friends_listener.proto', 'api/client/v2/presence_service.proto',
    'api/client/v2/whisper_service.proto',
))


def varint(data, index):
    value = 0
    for shift in range(0, 70, 7):
        if index >= len(data):
            raise ValueError('Truncated varint')
        byte = data[index]
        index += 1
        if shift == 63 and byte > 1:
            raise ValueError('Varint overflow')
        value |= (byte & 127) << shift
        if byte < 128:
            return value, index
    raise ValueError('Varint overflow')


def fields(data, terminated=False):
    """Decode bounded protobuf fields; a top-level C string requires its terminator."""
    if not isinstance(data, bytes):
        raise ValueError('Expected descriptor bytes')
    if len(data) > MAX_BYTES:
        raise ValueError('Descriptor too large')
    result, index, count = {}, 0, 0
    while index < len(data):
        start = index
        tag, index = varint(data, index)
        if tag == 0 and terminated:
            return result, start
        number, wire = tag >> 3, tag & 7
        count += 1
        if not 0 < number <= 536_870_911 or count > MAX_FIELDS:
            raise ValueError('Invalid field or field limit exceeded')
        if terminated and (number > 12 or number == 1 and 1 in result):
            raise ValueError('Unexpected FileDescriptor field')
        if wire == 0:
            value, index = varint(data, index)
        elif wire in (1, 5):
            width = 8 if wire == 1 else 4
            if index + width > len(data):
                raise ValueError('Truncated fixed-width field')
            value = int.from_bytes(data[index:index + width], 'little')
            index += width
        elif wire == 2:
            size, index = varint(data, index)
            if size > MAX_BYTES or index + size > len(data):
                raise ValueError('Invalid field size')
            value = data[index:index + size]
            index += size
        else:
            raise ValueError('Unsupported wire type')
        result.setdefault(number, []).append(value)
    if terminated:
        raise ValueError('Missing descriptor terminator')
    return result, index


def one(record, number):
    values = record.get(number, [])
    if len(values) != 1:
        raise ValueError('Missing or repeated singular field')
    return values[0]


def text(record, number, required=False):
    if number not in record and not required:
        return None
    value = one(record, number)
    if not isinstance(value, bytes) or len(value) > 512:
        raise ValueError('Invalid metadata string')
    value = value.decode('utf-8')
    if any(ord(c) < 32 or ord(c) == 127 for c in value):
        raise ValueError('Invalid metadata characters')
    return value


def integer(record, number, minimum, maximum, signed=False):
    value = one(record, number)
    if not isinstance(value, int):
        raise ValueError('Expected numeric metadata field')
    if signed and value >= 2**63:
        value -= 2**64
    if not minimum <= value <= maximum:
        raise ValueError('Numeric metadata field outside range')
    return value


def numeric_options(record, number):
    # Do not emit arbitrary option strings, defaults or opaque bytes.
    result = []
    for raw in record.get(number, []):
        outer, _ = fields(raw)
        for extension, values in outer.items():
            if extension not in (90000, 90001):
                continue
            for value in values:
                inner, _ = fields(value)
                numeric = {str(k): v for k, v in inner.items()
                           if all(isinstance(item, int) for item in v)}
                result.append({'extension': extension, 'numericFields': numeric})
    return result


def message(raw):
    record, _ = fields(raw)
    result = []
    for raw_field in record.get(2, []):
        item, _ = fields(raw_field)
        result.append({'name': text(item, 1, True), 'number': integer(item, 3, 1, 536_870_911),
                       'label': integer(item, 4, 1, 3), 'type': integer(item, 5, 1, 18),
                       'typeName': text(item, 6)})
    return {'name': text(record, 1, True), 'fields': result}


def service(raw):
    record, _ = fields(raw)
    methods = []
    for raw_method in record.get(2, []):
        item, _ = fields(raw_method)
        methods.append({'name': text(item, 1, True), 'input': text(item, 2, True),
                        'output': text(item, 3, True), 'options': numeric_options(item, 4)})
    return {'name': text(record, 1, True), 'options': numeric_options(record, 3), 'methods': methods}


def enumeration(raw):
    record, _ = fields(raw)
    values = []
    for raw_value in record.get(2, []):
        item, _ = fields(raw_value)
        values.append({'name': text(item, 1, True), 'number': integer(item, 2, -(2**31), 2**31 - 1, signed=True)})
    return {'name': text(record, 1, True), 'values': values}


def inspect(data, files=FILES):
    result = []
    for filename in files:
        encoded = filename.encode('ascii')
        if len(encoded) >= 128:
            raise ValueError('Filename length outside fixed allowlist')
        needle = b'\x0a' + bytes([len(encoded)]) + encoded
        start = data.find(needle)
        if start < 0:
            continue
        record, size = fields(data[start:start + MAX_BYTES], terminated=True)
        if text(record, 1, True) != filename:
            raise ValueError('Descriptor identity mismatch')
        package = text(record, 2, True)
        if not package.startswith('bgs.protocol'):
            raise ValueError('Unexpected package')
        result.append({'file': filename, 'offset': hex(start), 'bytes': size,
                       'package': package, 'messages': [message(v) for v in record.get(4, [])],
                       'enums': [enumeration(v) for v in record.get(5, [])],
                       'services': [service(v) for v in record.get(6, [])]})
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', type=Path, required=True, help='Installed static battle.net-core binary; not account files')
    parser.add_argument('--output', type=Path, help='Optional metadata-only JSON output')
    args = parser.parse_args()
    size = args.binary.stat().st_size
    if not 0 < size <= 512 * MAX_BYTES:
        parser.error('Binary size outside limit')
    data = args.binary.read_bytes()
    if data[:4] != b'\xcf\xfa\xed\xfe':
        parser.error('Expected a 64-bit little-endian Mach-O binary')
    result = inspect(data)
    if not result:
        parser.error('No allowlisted protocol descriptors found')
    payload = {'binary': args.binary.name, 'binarySHA256': hashlib.sha256(data).hexdigest(),
               'binaryBytes': len(data), 'files': result}
    encoded = json.dumps(payload, indent=2) + '\n'
    if args.output:
        # Exclusive creation also prevents replacing the input via a symlink or
        # hard link, and avoids overwriting existing application/user files.
        try:
            with args.output.open('x') as output:
                output.write(encoded)
        except FileExistsError:
            parser.error('Output already exists; choose a new metadata file')
        print(f'Wrote {len(result)} allowlisted static descriptors to {args.output}')
    else:
        print(encoded, end='')


if __name__ == '__main__':
    main()
