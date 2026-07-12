# Uno machine IRC protocol v1

`UNO_MACHINE_V1` is a private, versioned transport for automated players in
the IRC plugin still named `uno`. It does not change or replace the frozen
human protocol in `uno-human-protocol-v1.md`.

## Authorization and registration

The operator allowlists machine nicks with the comma-separated
`UNO_MACHINE_ALLOWLIST` environment variable, or the
`CONFIG['uno_machine_allowlist']` array/string. The environment variable takes
precedence. An absent or empty value denies every registration.

An allowlisted player joins a channel game normally and usually sends this in
that channel before the game is dealt:

```text
.uno machine register
```

The bot privately confirms registration:

```text
UNO_MACHINE_V1 REGISTERED game=<game-id> channel=<base64url-channel>
```

Registration is bound to that player object, normalized IRC nick, channel,
and game ID. `.uno machine unregister` removes it. Nick changes, part/quit/kick,
game stop/end, disconnection, and plugin unload also remove it. A nick change
requires joining/renaming in the ordinary game flow and registering again.

## Tokens and framing

`game`, `decision`, `code`, `event`, and `action` tokens use 1--64 ASCII
letters, digits, `_`, or `-`. The standalone `-` means no decision exists.
Machine output is always sent by private IRC NOTICE to the bound nick.

An action-required state is zlib-compressed JSON, URL-safe Base64 without
padding, then split into 280-character chunks:

```text
UNO_MACHINE_V1 STATE game=<game-id> decision=<decision-id> part=<n>/<total> data=<chunk>
```

The decompressed object is:

```json
{
  "protocol": "UNO_MACHINE_V1",
  "protocol_version": 1,
  "type": "request_action",
  "game_id": "...",
  "decision_id": "...",
  "reason": "turn_started|card_drawn|registration_sync",
  "request": { "type": "request_action", "protocol_version": 1, "state": {} }
}
```

The `request` value is authoritative `Jedna::GameStateSerializer` output.
Parts can be reassembled in any arrival order. Identical duplicate parts are
safe to ignore; missing, conflicting, corrupt, or mixed-correlation parts must
discard the whole frame.

Registration before deal receives its first request from `turn_started`.
Registration or re-registration while that player is already current emits a
fresh `registration_sync` decision and invalidates the prior pending decision;
this permits controlled client recovery without reconstructing human text.

Lifecycle events use the same compression and chunking:

```text
UNO_MACHINE_V1 EVENT game=<game-id> decision=<decision-id-or-dash> event=<event> part=<n>/<total> data=<chunk>
```

Defined events are `game_ended`, `stopped`, `unregistered`, `nick_changed`,
`parted`, `quit`, `kicked`, `disconnected`, and `plugin_unloaded`.

## Actions, acknowledgements, and retries

The bot accepts actions only as private messages:

```text
UNO_MACHINE_V1 ACTION game=<game-id> decision=<decision-id> data=<base64url-json>
```

The JSON is not compressed and must encode this envelope:

```json
{
  "protocol": "UNO_MACHINE_V1",
  "protocol_version": 1,
  "game_id": "...",
  "decision_id": "...",
  "action": { "action": "draw" }
}
```

The inner and outer IDs must match. The canonical action is passed unchanged
to `Jedna::ActionExecutor`; play supports `card`, `wild_color`, and
`double_play`, including double wild draw fours.

Success and failure are private single-line frames:

```text
UNO_MACHINE_V1 ACK game=<game-id> decision=<decision-id> status=ok action=<play|draw|pass>
UNO_MACHINE_V1 ERROR game=<game-id-or-dash> decision=<decision-id-or-dash> code=<code> retry=<0|1>
```

A decision is claimed atomically. Concurrent duplicates cannot both execute.
Malformed envelopes, unauthorized senders, stale/consumed decisions, wrong
games, and out-of-turn actions do not mutate the game. `retry=1` means the
same pending decision remains valid after a canonical executor validation
failure; all protocol, authorization, correlation, lifecycle, stale, and
duplicate errors use `retry=0`. A successful draw consumes its decision and
causes a new `card_drawn` decision. Play/pass proceeds through the engine and
either creates the next turn decision or ends the game.

## Host concurrency contract

`on_action_required` captures serializer state and registers a decision inline
under the game monitor. It only performs a nonblocking enqueue afterward. A
single bounded worker performs NOTICE delivery without the game monitor,
global games monitor, or per-channel lifecycle monitor. The host never waits
for inference or an action. Worker exceptions are isolated. Disconnect clears
registrations while keeping delivery available for a later reconnect; plugin
unload drains or terminates the managed worker deterministically.
