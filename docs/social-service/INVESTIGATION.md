# Battle.net social service: offline findings and next live controls

2026-11-14. Experimental branch only. No new authentication, social request,
Keychain access, client launch or changes to running applications were performed
during this research pass. `main` remains unchanged. The user is away; new live
experiments are deferred until their return.

## What is actually established

The selected saved WoW ticket authenticated with an owner-verified native logon.
Each of these correlated social requests then returned status 3025:

| Service | Method | Initial request | Result |
| --- | --- | --- | --- |
| Friends v2, original hash `0x5869BE8C` | GetFriends, `5` | Empty | RPC method disabled |
| Friends v1, original hash `0xA3DDB1BD` | GetFriendList, `13` | Empty | RPC method disabled |
| Friends v1, original hash `0xA3DDB1BD` | Subscribe, `1` | Listener object `1` | RPC method disabled |

The first result was user-reported and stage-isolated by diagnostics 2. The
legacy result was user-reported and observed in the version-3 window. The
subscription result was observed after one probe-button invocation. There was
no list returned. No friend mutation or message transmission was requested.
These results do not establish that the other Mac caused a conflict. Its
ongoing game download was not stopped.

The public error enum maps `0xBD1` (3025) to `ERROR_RPC_METHOD_DISABLED`.
`ERROR_SESSION_DUPLICATE` is a different code (`0x3C`). A method refusal does
not, by itself, identify the missing authorization or prove that all routes
are unavailable.

Source: [WowPacketParser error metadata](https://github.com/TrinityCore/WowPacketParser/blob/master/WowPacketParser/Enums/BattlenetRpcErrorCode.cs).

## The current client supplies a much better reference

Static inspection of the installed **2.53.8 / 17987 beta** client’s
`battle.net-core` found these protocol families:

- `bgs.protocol.authentication.v2.client`
- `bgs.protocol.session.v2.client`
- `bgs.protocol.friends.v2.client`
- `bgs.protocol.presence.v2.client`
- `bgs.protocol.whisper.v2.client`

The exact inspected binary is x86_64 Mach-O, 43,451,520 bytes, SHA-256:
`37a9047c1dc85337f62c7143a50c8dc7ff67ccc428b7484766542c3bac48c9ed`.
Its location was the installed application’s versioned framework, not a cache,
log, account database, browser store or process-memory dump. No official binary
or raw serialized descriptor is included in this repository.

`client-17987-metadata.json` is a metadata-only inventory extracted from 17
allowlisted embedded schema descriptions. It records protocol/field/method
names, field numbers and types, public enum values, numeric options, offsets
and the binary hash. It excludes default values, arbitrary option strings,
opaque bytes and any user/runtime data. A repository-authored offline tool
reproduces it; see the reproduction section below.

This is evidence about an installed build, not proof of current production
server behavior, feature entitlement or successful third-party access.

### Concrete differences from our probe

| Area | Current static schema/client evidence | Existing probe |
| --- | --- | --- |
| Social family | Friends **v2**, GetFriends method 5 | v2 method 5 tested; legacy controls also refused |
| Stub routing key | `0x5869BE8C40000005` appears in client method-registration code | Sends method field `5`, without upper routing bits |
| Initial connection | ConnectRequest has client SDK info field 5; reply has bindless result field 7 and `ciid` field 9 | Sends bindless flag and checks response status, ignoring reply metadata |
| Request identity | RPC Header has string `client_id` field 13 and additional routing fields | No client identity header is sent |
| Method options | Friends methods have `client_identity_routing = BATTLE_NET_ACCOUNT` | No explicit social identity/session setup |
| Application session | Separate SessionService exposes CreateSession/RestoreSession and session-created/destroyed listeners | Authentication is followed immediately by social RPC; no session creation |
| Runtime lifetime | SessionVariables includes recommended/max alive intervals; SDK exposes keepalive/echo | Short bounded connection; not a durable social client |

**Important qualification:** a 64-bit stub routing key is not proof that those
upper bits are serialized unchanged in Header.method_id. The client’s auth and
session stubs also contain client-call registration keys ending `0x40000001`.
Our unflagged authentication already works. Header serialization must be traced
or compared in a controlled live test before blaming the missing bits.

The generated method-options schema uses field 2 for
`client_identity_routing`, with public enum values disabled=0, Battle.net
account=1, game account=2, instance ID=3. These are RPC routing semantics,
**not OAuth permission scopes**. Do not conflate them or assume that
ConnectResponse.ciid can simply be copied into Header.client_id without
establishing the SDK’s actual mapping.

The v2 original friends hash has 35 byte occurrences in the inspected binary;
the schema name hash `0x9D059A2F` has none, and the legacy original hash has none.
Byte counts alone are weak evidence, but the actual v2 registration constant
at file offset `0x178104B` corroborates the original-hash family we used. The
legacy controls therefore do not assess the modern client’s main social path.

### Relevant authentication and session fields

The installed authentication schema agrees with the shape of our existing
logon: title_id1, platform2, locale3, application_version4, logon_options10.
LogonOptions contains auth_token1, user_agent2, device_id3 and optional account
entry fields. Our probe supplies the token but does not model the full client
lifecycle. These field declarations do not prove any optional field is required
for social access; do not manufacture device identifiers or copy an official
client’s private credentials to fill them.

The successful logon record schema includes account_id1, game_account2,
**battle_tag3**, session_key5 and login_ticket7. Our discovery code validates
the owner and ignores the other fields. This suggests a possible future way to
obtain the user’s own BattleTag from an already-validated logon, without the
account portal. Availability was not measured; no live values were read here.
That improvement should stay separate from the social experiment.

CreateSessionRequest has optional game_account1 and options2; its response
contains session_id1 and variables2. SessionId contains account_id1,
game_account2, instance_id3 and region4. A SessionCreated listener supplies
status, session_key and session_id. A persistent client must validate owner,
region and any game-account binding before adopting these and must handle
session destruction, cancellation, reconnects and heartbeat deadlines.

**Creating an application session is a consequential next experiment:** it
may replace or disturb another session. We have not tested coexistence with
WoW or another launcher. Do not create one unattended, or interpret an empty
schema-valid request as automatically safe for an existing live session.

## Other sources and what they do not prove

### Historical independent desktop-chat implementation

[EionRobb/purple-battlenet](https://github.com/EionRobb/purple-battlenet)
(commit `d2113e28cdad24317e34886c50e8a6fceaeff53d`) is a GPLv3+ plugin,
last pushed in 2020 according to its repository metadata. Its source uses an
application-oriented `App` logon, imported/exported service binding, an external
browser game-ticket return, then friends and presence subscriptions. That is a
useful historical distinction from our WoW-oriented minimal connection. No
implementation or schemas from the plugin were copied into Waypoint.

Its own [issue 4](https://github.com/EionRobb/purple-battlenet/issues/4) reports
successful login, an official-client disconnect, and no populated friends.
[Issue 7](https://github.com/EionRobb/purple-battlenet/issues/7) contains unresolved
connection reports through 2025. These are historical user reports, not tests
we performed and not proof of current behavior. Do not install the plugin or
borrow its hardcoded version/user agent as a presumed modern solution.

The README’s referenced HearthSim/python-bnet source was not retrievable via
the connected repository fetcher during this pass. It is not used as evidence.
Classic BNCS/PvPGN chat clients concern a different service and are not evidence
of modern Battle.net friends access. Search results promising a ready-made
social tool without inspectable matching code were not used or executed.

### Modern emulation research is context, not Blizzard’s contract

[Tavern’s protocol overview](https://github.com/wowemulation-dev/tavern/blob/main/docs/protocol-overview.md)
distinguishes game, browser and desktop authentication and describes a desktop
BGS/token-exchange path. Its [protocol-version notes](https://github.com/wowemulation-dev/tavern/blob/main/docs/bgs-protocol-versions.md)
explicitly label that work research and list social services as unimplemented.
It reimplements retired-client services on its own backend; it does not prove
the same token exchange or social privileges are available to Waypoint on
Blizzard’s production backend.

### Public developer OAuth remains a separate authorization system

Our earlier own-client browser OAuth test established basic account identity,
not game or social access. See `../browser-signin-investigation.md`. No refresh
token was observed in that test. Advertised discovery grants do not establish
that a third-party client may use an internal grant or request a social scope.

The [official Blizzard OAuth sample](https://github.com/Blizzard/oauth-client-sample)
and [Blizzard’s Passport strategy](https://github.com/Blizzard/passport-bnet)
provide ordinary developer-client login examples. They do not demonstrate a
friends/messaging capability for our registered client. A client secret must
not be embedded in a distributable native app. This pass did not use, read or
request any secret, developer portal access or new token.

## Messaging and presence are separate pieces

The installed current schema has WhisperService methods for subscription,
history retrieval, sending, read/clear advancement and typing indicators.
PresenceService separately has query, batch subscription and update methods.
Their presence in the client establishes protocol surface, not permission for
our login. A friend snapshot does not prove messaging, presence, message
history, multi-device delivery or game coexistence.

No send/history/read-receipt/typing/presence-update experiment was implemented
or performed. An eventual UI should keep social activity opt-in, make the
active account clear, avoid sending read/typing signals just by opening a
view, and never mix caches across accounts. Network errors must retain saved
game authorization and never force a new login merely because social is down.

## Ordered live plan for when the user returns

1. **Smallest routing control first:** keep endpoint, title, saved token and
   request body unchanged. Compare the modern v2 GetFriends request with the
   SDK client-call flag set in the method field (`0x40000005` instead of `5`).
   This is a hypothesis test of a concrete static difference, not a claimed
   fix. Make it an explicit mode, one request, with the same deadline and no
   fallback loop. Do not change both routing and login identity together.
2. **Connection metadata diagnostics:** record only booleans and safe status
   categories for returned bindless support/CIID and session callback presence.
   Retain any actual identifiers in memory only. Determine actual SDK identity
   mapping before adding Header.client_id; do not guess a value or log it.
3. **Session setup, only with the user present:** agree the account/region and
   close games before an isolated CreateSession experiment. Validate server
   owner/region, reserve a separate in-memory social context, handle callbacks
   and implement cleanup. Stop if it would replace another active session;
   investigate coexistence explicitly before making it a background feature.
4. **Separate application login only if evidence requires it:** identify the
   current application title and supported browser/auth flow from the actual
   SDK/protocol. Keep a candidate social credential separate from the working
   game ticket until owner, lifetime and rights are verified. Never reuse an
   official client secret or assume a title-specific ticket can change scope.
5. Only after a nonempty expected friend list is confirmed, test names and
   presence, then later messaging with an explicitly chosen willing recipient.

Stop conditions: unexpected challenge, account mismatch, running game, revoked
access, unknown session side effect, rate limit, parser bound or cancellation.
Do not keep trying method IDs after a refusal. Keep the MacBook download alone.

## Reproducing the offline inspection

Use the exact installed static framework executable as `--binary`, not any
account configuration, log, browser cache or process-memory dump:

```sh
python3 tools/friends-probe/offline/inspect_protocol.py \
  --binary '/path/to/battle.net-core.framework/battle.net-core' \
  --output /private/tmp/bgs-metadata-new.json
python3 -m unittest discover -s tools/friends-probe/offline -v
```

The tool has no network, browser, Keychain or subprocess APIs. It requires a
bounded 64-bit little-endian Mach-O input, finds only fixed allowlisted schema
filenames, bounds protobuf fields/lengths, requires descriptor termination,
and emits a schema-only summary. Output creation is exclusive to avoid
replacing the binary, following an output symlink or overwriting an existing
file. The binary hash ties observations to this inspected build. Missing or
changed descriptors fail or remain absent; the tool does not invent metadata.

Nine offline decoder tests pass, covering bounded/truncated varints and
fields, fixed64, embedded zero bytes, terminators, filename/package checks and
suppression of arbitrary option strings, plus numeric field/enum type bounds. The previous 19 native/probe tests
remain the last native results; runtime behavior was not changed this pass.

## Change boundary

Only documentation, a static metadata inventory and an offline inspector/tests
were added in this research pass. No live probe was run or reopened. No official
launcher was launched or terminated. No user-account/credential files were read,
no packet capture was started, and no network authentication was attempted.
No requests for user approval were issued. Source-document retrievals were
public read-only fetches. Completed work is committed and pushed only to
`experiment/battlenet-friends`, never `main`, after independent review.
