# Current desktop lifecycle: static inspection — 2026-11-15

No official launcher was installed or executed. No account/browser files,
process memory or private logs were inspected. No live authentication/session
request was made by this static research step.

## Source acquisition

Blizzard's public bna versions/CDN tables identify production 2.53.8.17986:

- https://us.version.battle.net/v2/products/bna/versions
- https://us.version.battle.net/v2/products/bna/cdns
- Build config: 4b9c77d7485667dd03c1582a0ff2bc20
- CDN config: 437350dabc4e4e39b09adc1ebaf4b9ac
- Product CDN path: tpr/bnt002
- File: Battle.net.17986/battle.net-core.framework/battle.net-core
- Install-manifest content key: 535be3a2549f8702e4a876b4c5dd2e78
- Decoded size: 43,451,520 bytes
- Decoded SHA256: f3fa202e517128d3c524cbc0e2b1baea4caf8bcbf31b08ec206261191187004c

A small local Swift inspector used WaypointCore's public VersionService,
InstallManifest, EncodingTable and BLTE/CDN decoding. Only the core file was
selected from the public manifest; decoded length and MD5 content key were
verified before saving inert data in /private/tmp. No app bundle was installed,
executable permission added, or official code launched. No binary or disassembly
is included in the repository.

## Narrow static finding

The core contains Phoenix BattleNetLogin CreateSession callback RTTI. Its
callback type-name reference resolves to typeinfo 0x26c25c0 / vtable0x26c2578;
that vtable's callable entry0x711ae0 logs session-created result and checks the
returned error. Its sole non-constructor vtable reference at0x70a479 occurs in
the function starting0x70a3c0.

That function constructs a CreateSessionRequest at0x169f010 (constructor's
vtable0x278bd28 resolves to that protobuf RTTI), sets its field1 presence bit,
constructs a GameAccountHandle at0x16e8c10 (vtable0x278fba8 resolves to that
protobuf RTTI), copies a handle, and passes the populated request to0x73cc30.
The saved schema maps CreateSessionRequest.field1 to game_account.

This supports a concrete difference from an empty creation request: the
inspected desktop login path supplies a game-account handle. It does NOT by
itself prove the runtime handle's title/region, identify the sender client ID,
establish server permissions, show which sessions may be replaced, or prove
that session creation will fix our presence refusal. Do not copy handles or
fingerprints from the official app.

Additional static names show dedicated BattleNetSessions CreateSession,
DestroySession and GetSessionState paths, and BattleNetLogin presence-publication
paths. GetSessionState is referenced by a GetIGRInfo callback. Names alone do not
establish ordering, lifetime or a generic session-existence contract.

## Next non-mutating check

Classify game_account2 metadata on our own owner-verified App LogonRecord:
explicit nonzero ID, title App (0x417070), region1. Report only fixed availability
states (matching/other/missing/ambiguous/unrecognized) and callback-context
presence. No identifiers leave the backend and no request follows App login.
Optional metadata failure must not be relabeled as failed authentication.

Before any future creation experiment: establish usable own-login handle,
source/target context mapping, response/callback owner/binding verification,
exact lifetime/cleanup semantics and interruption behavior. Agree the concrete
server-side test and relevant closed-client conditions first. None of that is
implemented or demonstrated by this auth-only control.
