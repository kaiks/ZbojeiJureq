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

Every machine-protocol message is at most 400 bytes before the IRC command and
target prefix. `game`, `decision`, `code`, `event`, and `action` tokens use 1--64 ASCII
letters, digits, `_`, or `-`. The standalone `-` means no decision exists.
Machine output is always sent by private IRC NOTICE to the bound nick.

An action-required state is zlib-compressed JSON, URL-safe Base64 without
padding, then split into 128-character chunks, with at most 999 parts:

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
  "correlation": "...",
  "action": { "action": "draw" }
}
```

`correlation` is the unpadded Base64url encoding of the first 12 bytes of
`SHA-256(game_id + NUL + decision_id)`. It detects an action payload copied to
different outer IDs without repeating two potentially long tokens inside the
one-line payload. `data` is limited to 220 Base64url characters, and the whole
ACTION line is limited to 400 bytes. The host rejects an oversized line before
decoding it.

The correlation must match the outer IDs. The canonical action is passed
unchanged to `Jedna::ActionExecutor`; play supports `card`, `wild_color`, and
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

Stable host error codes are `private_only`, `channel_only`, `no_game`,
`not_allowlisted`, `not_player`, `game_changed`, `registration_taken`,
`not_registered`, `unknown_game`, `game_ended`, `unauthorized`,
`stale_decision`, `duplicate_decision`, `out_of_turn`, `transport_unavailable`,
and `internal_error`.
Protocol parsing can additionally return `malformed_action`, `invalid_game_id`,
`invalid_decision_id`, `action_too_large`, `invalid_base64`, `malformed_json`,
`unsupported_protocol`, or `correlation_mismatch`. Canonical executor failures
use Jedna's versioned action result `code` (for example `action_unavailable` or
`card_not_playable`) and are the retryable class. Clients must treat an unknown
future code according to its explicit `retry` field rather than guessing.

## Host concurrency contract

`on_action_required` captures serializer state and registers a decision inline
under the game monitor. It only performs a nonblocking enqueue afterward. A
single bounded worker exclusively performs NOTICE delivery; the producer
thread never performs network I/O and does not wait for a blocked NOTICE even
when it currently owns a game or channel monitor. The worker itself owns none
of the game monitor, global games monitor, or per-channel lifecycle monitor.
Delivery may run concurrently while another thread still owns one of those
monitors; the guarantee is thread separation and nonblocking production, not a
post-lock scheduling barrier.

ACK and any resulting STATE/EVENT frames are one dispatcher job, preserving
their order and accepting or rejecting the batch atomically at enqueue time.
If a STATE or successful-action batch cannot be enqueued because the bounded
queue is full, the host invalidates the pending decision and clears machine
registration. No undelivered decision remains actionable. Once delivery has
drained, the client recovers with `.uno machine register`, which returns an
authoritative `registration_sync` decision when it is current. Cleanup remains
logically successful if its best-effort terminal EVENT cannot be queued; its
registration and decisions stay cleared.

Worker exceptions are isolated. Disconnect clears registrations while keeping
delivery available for a later reconnect. Plugin unload stops new producers,
allows already queued jobs to drain within a bounded timeout, and force-stops
a blocked worker at the deadline without clearing the queue merely to insert a
stop marker.
