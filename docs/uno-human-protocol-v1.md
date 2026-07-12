# Uno human IRC snapshot protocol v1

This document freezes the status snapshot used by human-protocol Uno clients.
It is deliberately separate from the planned machine protocol. The IRC plugin,
commands, and channel text continue to use the name `uno`.

## Request

A player in the game sends either `.uno status` or the unprefixed short command
`us` in the game channel. The bot sends the response as IRC notices to the
requesting player. It never broadcasts a status response into the channel.

The request succeeds only for a player in that channel's game. Error responses
are also private notices:

```text
UNO_STATUS_V1 error=channel_only
UNO_STATUS_V1 error=no_game
UNO_STATUS_V1 error=not_player
```

`channel_only` means the request was sent outside a channel. `no_game` also
covers a game removed by `.uno stop` or by the normal game-ended callback.

## Snapshot grammar

A successful request returns exactly one private notice with fields in this
order:

```text
UNO_STATUS_V1 phase=<phase> current=<nick-or-dash> top=<card-or-dash> mode=<mode> stacked_cards=<uint> already_picked=<0-or-1> players=<player-list>
```

The stable tokens are:

- `phase`: `waiting`, `active`, or `ended`.
- `current`: the current player's IRC nickname, or `-` when there is no active
  turn.
- `top`: Jedna's canonical card code, including a chosen wild color, or `-`
  before the deal. Examples are `r7`, `r+2`, `wg`, and `wd4y`.
- `mode`: `off`, `normal`, `war_+2`, `war_wd4`, or `unknown` for a future engine
  state not understood by this protocol version.
- `stacked_cards`: the authoritative number of penalty cards currently stacked.
- `already_picked`: `1` after the current player has drawn during this turn,
  otherwise `0`. This field does not disclose which card was drawn.
- `players`: comma-separated `<nick>:<card-count>` entries. Their order is the
  authoritative current player array order after reverse, skip, double-play,
  and pass effects. IRC nicknames cannot contain the `,` or `:` delimiters.

For an active turn, if the requester is the current player, a second private
notice always follows:

```text
UNO_STATUS_PRIVATE_V1 picked_card=<card-or-dash>
```

`picked_card` is the canonical identity of the card drawn on this turn, or `-`
when no card has been drawn. This second line is never sent to another player.
Nonplayers receive no snapshot fields at all.

Examples:

```text
UNO_STATUS_V1 phase=waiting current=- top=- mode=off stacked_cards=0 already_picked=0 players=Alice:0,Bob:0
UNO_STATUS_V1 phase=active current=Alice top=wd4g mode=war_wd4 stacked_cards=8 already_picked=1 players=Alice:8,Bob:4
UNO_STATUS_PRIVATE_V1 picked_card=r5
UNO_STATUS_V1 phase=ended current=- top=r7 mode=off stacked_cards=0 already_picked=0 players=Alice:0,Bob:5
```

Each status is captured under the individual game's monitor, so all fields in
one response describe the same engine state. IRC delivery happens after the
snapshot has been captured and without holding the plugin-wide games monitor.

## Reconnection assumption

A continuously connected client can still derive state from the existing human
messages. A reconnecting client requests status to recover public turn state,
then sends the existing `ca` command to receive its complete hand privately.
Thus resynchronization requires at most these two requests. The client must know
the Uno rules for deriving legal actions; this v1 snapshot does not list them.

## Double wild draw four syntax

Human commands retain the existing compact `pl` syntax. Two identical wild draw
fours can now be played together by repeating the colored card code, for example
`pl wd4rwd4r`. The final color letter is required for each half and both halves
must be identical. Existing single wild (`pl wr`), single wild draw four
(`pl wd4r`), and other double-card commands remain unchanged.
