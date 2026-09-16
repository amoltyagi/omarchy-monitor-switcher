#!/usr/bin/env python3
"""Per-output Night Light, owned by the plugin's single IPC panel.

Uses wl_output v4 and wlr-gamma-control-v1. No global hyprsunset commands:
only enabled outputs acquire a gamma control; destroying it restores that
output's original gamma. Settings survive panel reloads and output hotplug.
"""
import array
import hashlib
import json
import math
import os
from pathlib import Path
import select
import socket
import stat
import struct
import sys
import tempfile
import time

LIMIT = 1048576
U = lambda *values: struct.pack('=' + 'I' * len(values), *values)


def wire_string(value):
    data = value.encode() + b'\0'
    return U(len(data)) + data + b'\0' * (-len(data) % 4)


def read_string(data, offset=0):
    length = struct.unpack_from('=I', data, offset)[0]
    if length < 1 or offset + 4 + length > len(data):
        raise ValueError('Invalid Wayland string')
    return data[offset + 4:offset + 3 + length].decode(), offset + 4 + ((length + 3) // 4) * 4


def guard_path(path):
    for part in [path, *path.parents]:
        if part.is_symlink():
            raise ValueError('Refusing a symlinked settings path')


def read_json(path, fallback):
    guard_path(path)
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
    except FileNotFoundError:
        return fallback
    with os.fdopen(fd, 'rb') as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_size > LIMIT:
            raise ValueError('Settings must be a regular file smaller than 1 MB')
        data = stream.read(LIMIT + 1)
        if len(data) > LIMIT:
            raise ValueError('Settings exceed 1 MB')
    return json.loads(data)


def write_json(path, value):
    guard_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    guard_path(path)
    data = (json.dumps(value, indent=2) + '\n').encode()
    if len(data) > LIMIT:
        raise ValueError('Night Light settings exceed 1 MB')
    fd, temporary = tempfile.mkstemp(prefix='.night-light-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def validate_preferences(value):
    if not isinstance(value, dict) or len(value) > 64:
        raise ValueError('Invalid Night Light settings')
    for key, item in value.items():
        if not isinstance(key, str) or not isinstance(item, dict) or type(item.get('enabled')) is not bool:
            raise ValueError('Invalid Night Light setting')
        temperature = item.get('temperature')
        if type(temperature) is not int or not 2500 <= temperature <= 5500:
            raise ValueError('Night Light temperature must be between 2500 and 5500 K')
    return value


def monitor_key(monitor):
    identity = monitor.get('identity')
    if isinstance(identity, dict) and identity.get('serial') not in (None, '', '0'):
        return 'edid:' + hashlib.sha256(json.dumps(identity, sort_keys=True).encode()).hexdigest()
    return 'output:' + monitor['output']


def gamma_ramps(size, temperature):
    if not 2 <= size <= 65536 or not 2500 <= temperature <= 5500:
        raise ValueError('Unsupported gamma size or temperature')
    # Planckian approximation used by conventional Kelvin-to-RGB filters.
    t = temperature / 100
    green = max(0, min(255, 99.4708025861 * math.log(t) - 161.1195681661)) / 255
    blue = max(0, min(255, 138.5177312231 * math.log(t - 10) - 305.0447927307)) / 255
    return array.array('H', (round(i * 65535 * gain / (size - 1))
                            for gain in (1, green, blue) for i in range(size))).tobytes()


class Wayland:
    def __init__(self, connection=None):
        self.socket = connection or socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.socket.settimeout(2)
        if connection is None:
            self.socket.connect(os.path.join(os.environ['XDG_RUNTIME_DIR'], os.environ.get('WAYLAND_DISPLAY', 'wayland-1')))
        self.buffer = b''
        self.objects = {1: ('display', None), 2: ('registry', None)}
        self.serial = 2
        self.finished = set()
        self.outputs = {}
        self.manager = None
        self.send(1, 1, U(2))
        self.sync()
        self.sync()

    def new(self, kind, value=None):
        self.serial += 1
        self.objects[self.serial] = (kind, value)
        return self.serial

    def send(self, obj, opcode, data=b'', fd=None):
        packet = U(obj, ((8 + len(data)) << 16) | opcode) + data
        if fd is None:
            self.socket.sendall(packet)
        else:
            count = self.socket.sendmsg([packet], [(socket.SOL_SOCKET, socket.SCM_RIGHTS, array.array('i', [fd]))])
            if count < len(packet):
                self.socket.sendall(packet[count:])

    def receive(self):
        data = self.socket.recv(65536)
        if not data:
            raise ConnectionError('Display connection closed')
        self.buffer += data
        while len(self.buffer) >= 8:
            obj, header = struct.unpack_from('=II', self.buffer)
            length, opcode = header >> 16, header & 65535
            if length < 8 or length % 4:
                raise ValueError('Invalid Wayland event')
            if len(self.buffer) < length:
                break
            payload, self.buffer = self.buffer[8:length], self.buffer[length:]
            kind, value = self.objects.get(obj, ('unknown', None))
            if kind == 'display':
                if opcode == 0:
                    raise RuntimeError('Display server rejected Night Light: ' + read_string(payload, 8)[0])
                if opcode == 1:
                    self.objects.pop(struct.unpack_from('=I', payload)[0], None)
            elif kind == 'callback':
                self.finished.add(obj)
            elif kind == 'registry':
                number = struct.unpack_from('=I', payload)[0]
                if opcode == 0:
                    interface, end = read_string(payload, 4)
                    version = struct.unpack_from('=I', payload, end)[0]
                    if interface == 'wl_output' and version >= 4:
                        output = self.new('output')
                        self.outputs[output] = {'global': number, 'name': '', 'control': None, 'size': 0, 'error': '', 'temperature': None}
                        self.send(2, 0, U(number) + wire_string(interface) + U(4, output))
                    elif interface == 'zwlr_gamma_control_manager_v1':
                        self.manager = self.new('manager')
                        self.send(2, 0, U(number) + wire_string(interface) + U(1, self.manager))
                else:
                    for output, meta in list(self.outputs.items()):
                        if meta['global'] == number:
                            self.release(output)
                            self.send(output, 0)  # wl_output.release
                            del self.outputs[output]
            elif kind == 'output' and opcode == 4 and obj in self.outputs:
                self.outputs[obj]['name'] = read_string(payload)[0]
            elif kind == 'control' and value in self.outputs:
                meta = self.outputs[value]
                if opcode == 0:
                    meta['size'] = struct.unpack_from('=I', payload)[0]
                elif opcode == 1:
                    meta['error'] = 'This display cannot accept Night Light, or another app controls its gamma.'
                    self.release(value)

    def sync(self):
        callback = self.new('callback')
        self.send(1, 0, U(callback))
        deadline = time.monotonic() + 3
        while callback not in self.finished:
            if time.monotonic() >= deadline:
                raise TimeoutError('Display server did not confirm Night Light')
            self.receive()
        self.finished.discard(callback)

    def release(self, output):
        meta = self.outputs[output]
        if meta['control'] is not None:
            self.send(meta['control'], 1)
        meta.update(control=None, size=0, temperature=None)

    def apply(self, output, temperature):
        meta = self.outputs[output]
        if temperature is None:
            self.release(output)
            meta['error'] = ''
            self.sync()
            return
        if not self.manager:
            raise RuntimeError('The display server does not support per-monitor Night Light')
        meta['error'] = ''
        if meta['control'] is None:
            control = self.new('control', output)
            meta['control'] = control
            self.send(self.manager, 0, U(control, output))
            self.sync()
        if meta['error'] or meta['control'] is None:
            raise RuntimeError(meta['error'] or 'Night Light is unavailable on this display')
        data = gamma_ramps(meta['size'], temperature)
        fd = os.memfd_create('monitor-switcher-gamma', os.MFD_CLOEXEC)
        try:
            with os.fdopen(fd, 'wb', closefd=False) as stream:
                stream.write(data)
                stream.flush()
            os.lseek(fd, 0, os.SEEK_SET)
            self.send(meta['control'], 0, fd=fd)
            self.sync()
        finally:
            os.close(fd)
        if meta['error']:
            raise RuntimeError(meta['error'])
        meta['temperature'] = temperature

    def close(self):
        self.socket.close()  # The compositor restores only our acquired outputs.


class NightLight:
    def __init__(self, home, wayland):
        self.path = Path(home) / '.config/monitor-switcher/night-light.json'
        self.config = Path(home) / '.config/monitor-switcher/config.json'
        self.preferences = validate_preferences(read_json(self.path, {}))
        self.wayland = wayland
        self.monitors = []
        self.last_message = ''
        self.error = ''

    def load_monitors(self):
        value = read_json(self.config, [])
        if not isinstance(value, list) or len(value) > 64 or any(not isinstance(m, dict) or not isinstance(m.get('output'), str) for m in value):
            raise ValueError('Invalid monitor configuration')
        self.monitors = value

    def preference(self, name):
        monitor = next((m for m in self.monitors if m['output'] == name), {'output': name})
        key = monitor_key(monitor)
        # Some identical displays report the same serial. Never warm their peers
        # merely because an ambiguous identity was selected on one connector.
        if sum(monitor_key(m) == key for m in self.monitors) > 1:
            key = 'output:' + name
        return key, self.preferences.get(key, {'enabled': False, 'temperature': 4000})

    def reconcile(self):
        self.load_monitors()
        for output, meta in list(self.wayland.outputs.items()):
            _, setting = self.preference(meta['name'])
            target = setting['temperature'] if setting['enabled'] else None
            if target != meta['temperature'] and not meta['error']:
                try:
                    self.wayland.apply(output, target)
                except (RuntimeError, ValueError) as error:
                    meta['error'] = str(error)

    def command(self, request):
        name, value = request.get('output'), request.get('value')
        output = next((o for o, m in self.wayland.outputs.items() if m['name'] == name), None)
        if output is None:
            raise ValueError('Reconnect or enable this display before changing Night Light')
        key, previous = self.preference(name)
        if value == 'off':
            updated = dict(previous, enabled=False)
        else:
            temperature = int(value)
            if str(temperature) != str(value) or not 2500 <= temperature <= 5500:
                raise ValueError('Choose a temperature between 2500 and 5500 K')
            updated = {'enabled': True, 'temperature': temperature}
        self.wayland.apply(output, updated['temperature'] if updated['enabled'] else None)
        candidate = dict(self.preferences, **{key: updated})
        try:
            validate_preferences(candidate)
            write_json(self.path, candidate)
        except Exception:
            self.wayland.apply(output, previous['temperature'] if previous['enabled'] else None)
            raise
        self.preferences = candidate
        self.error = ''

    def publish(self, force=False):
        states = {}
        live = {m['name']: m for m in self.wayland.outputs.values()}
        for name in sorted(set(live) | {m['output'] for m in self.monitors}):
            _, setting = self.preference(name)
            meta = live.get(name, {})
            states[name] = dict(setting, active=meta.get('temperature') is not None,
                                available=bool(self.wayland.manager and name in live), error=meta.get('error', ''))
        message = json.dumps({'ready': True, 'monitors': states, 'error': self.error}, separators=(',', ':'))
        if force or message != self.last_message:
            print(message, flush=True)
            self.last_message = message


def main():
    os.umask(0o077)
    wayland = None
    try:
        wayland = Wayland()
        service = NightLight(os.environ['HOME'], wayland)
        buffer = b''
        while True:
            service.reconcile()
            service.publish()
            ready, _, _ = select.select([wayland.socket, sys.stdin], [], [], 1)
            if wayland.socket in ready:
                wayland.receive()
            if sys.stdin in ready:
                data = os.read(sys.stdin.fileno(), 4096)
                if not data:
                    return
                buffer += data
                if len(buffer) > 8192:
                    raise ValueError('Night Light request is too large')
                while b'\n' in buffer:
                    line, buffer = buffer.split(b'\n', 1)
                    try:
                        request = json.loads(line)
                        if not isinstance(request, dict):
                            raise ValueError('Invalid Night Light request')
                        service.command(request)
                    except (ValueError, TypeError, OSError, RuntimeError) as error:
                        service.error = str(error)[:300]
                    service.publish(force=True)
    except (OSError, RuntimeError, ValueError, KeyError) as error:
        print(json.dumps({'ready': False, 'monitors': {}, 'error': 'Night Light: ' + str(error)[:300]}), flush=True)
    finally:
        if wayland:
            wayland.close()


if __name__ == '__main__':
    main()
