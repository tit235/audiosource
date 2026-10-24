# audiosource

`audiosource` is a Swift command-line tool for inspecting and changing the default
macOS audio devices. It is a Swift reimplementation of
[switchaudio-osx](https://github.com/deweller/switchaudio-osx), intended as a drop-in
replacement for the original binary.

It can:

- list all input and output devices
- show the current input, output, or system output device
- switch the default device by name, numeric ID, or UID substring
- cycle to the next device
- mute, unmute, or toggle mute on input and output devices
- emit human-readable, CLI (CSV), or JSON output

## Build

Requires macOS 12 or later and Xcode command-line tools.

```bash
swift build -c release
```

The binary is written to:

```text
.build/release/audiosource
```

Or use the helper script:

```bash
./build.sh
```

## Install

```bash
cp .build/release/audiosource /usr/local/bin/
```

## Usage

```text
audiosource [options]
```

| Short         | Long                | Description                                                           |
| ------------- | ------------------- | --------------------------------------------------------------------- |
| `-a`          | `--all`             | Show all audio devices                                                |
| `-c`          | `--current`         | Show the current audio device                                         |
| `-f <format>` | `--format <format>` | Output format: `human`, `cli`, or `json`. Default: `human`            |
| `-t <type>`   | `--type <type>`     | Device type: `input`, `output`, `system`, or `all`. Default: `output` |
| `-m <mode>`   | `--mute <mode>`     | Set mute state: `mute`, `unmute`, or `toggle`                         |
| `-n`          | `--next`            | Cycle to the next audio device                                        |
| `-i <id>`     | `--id <id>`         | Set the device by numeric ID                                          |
| `-u <uid>`    | `--uid <uid>`       | Set the device by UID or UID substring                                |
| `-s <name>`   | `--name <name>`     | Set the device by name                                                |
| `-h`          | `--help`            | Show help                                                             |
| `-v`          | `--version`         | Show the version                                                      |

Long options accept both `--format json` and `--format=json`. Short options may be
grouped (`-ac`) and values may be attached (`-fjson`).

## Output formats

### `human` (default)

Matches the original switchaudio-osx output:

```text
AirPods
output audio device set to "MacBook Pro Speakers"
Setting device AirPods to muted
```

### `cli`

Comma-separated fields:

```text
name,type,id,uid
```

Muting appends the resulting state as a fifth field:

```text
name,type,id,uid,muted
```

Examples:

```bash
audiosource -a -f cli
audiosource -c -t input -f cli
audiosource -m mute -s "MacBook Pro Speakers" -f cli
```

```text
MacBook Pro Speakers,output,93,BuiltInSpeakerDevice,true
```

### `json`

`--all` emits one JSON object per line, matching the original tool. `--current` emits a
single device object. Switching, cycling, and muting emit a single operation result.

Device object:

```json
{
  "id": "93",
  "name": "MacBook Pro Speakers",
  "type": "output",
  "uid": "BuiltInSpeakerDevice"
}
```

Operation result:

```json
{
  "action": "set",
  "devices": [
    {
      "id": "93",
      "name": "MacBook Pro Speakers",
      "type": "output",
      "uid": "BuiltInSpeakerDevice"
    }
  ],
  "status": "success"
}
```

Muting includes the resulting `muted` state:

```json
{
  "action": "mute",
  "devices": [
    {
      "id": "93",
      "muted": true,
      "name": "MacBook Pro Speakers",
      "type": "output",
      "uid": "BuiltInSpeakerDevice"
    }
  ],
  "status": "success"
}
```

Errors are reported as an operation result with `"status":"error"` and an `error` field.
The process exit code is `1`.

## Examples

List every input and output device:

```bash
audiosource --all
```

List only output devices:

```bash
audiosource -a -t output
```

Show the current output device as JSON:

```bash
audiosource -c -f json
```

Switch the output device by name:

```bash
audiosource -s "MacBook Pro Speakers"
```

Switch the output device by UID substring:

```bash
audiosource -u "BuiltInSpeaker"
```

Switch by numeric ID:

```bash
audiosource -i 93
```

Cycle to the next output device:

```bash
audiosource -n
```

Cycle all device types (input, output, system):

```bash
audiosource -n -t all
```

Mute the current output device:

```bash
audiosource -m mute
```

Toggle the current input (microphone) mute state:

```bash
audiosource -m toggle -t input
```

Mute a specific output device and return JSON:

```bash
audiosource -m mute -s "MacBook Pro Speakers" -f json
```

Set a device as input, output, and system output at once:

```bash
audiosource -s "AirPods" -t all
```

## Behavior notes

- When `--type` is omitted, switching and cycling default to `output`.
- For muting, if `--type` is omitted, the type is inferred from the device selected with
  `--name`, `--uid`, or `--id`. With no device selector, the current output device is
  muted.
- `--type system` cannot be muted; macOS does not expose a mute control for the system
  output device.
- `--type all` with `--name` or `--uid` applies the matching device to input, output, and
  system output where applicable.
- `--type all` with `--id` applies the device to every type it supports.
- Setting a device by ID validates that the ID exists and that the device supports the
  requested direction.
- Errors are written to standard error in `human` and `cli` formats. In `json` format,
  errors are emitted as a JSON operation result on standard output.

## License

MIT. See [license.txt](license.txt). The CLI behavior is based on switchaudio-osx by
Devon Weller and contributors.
