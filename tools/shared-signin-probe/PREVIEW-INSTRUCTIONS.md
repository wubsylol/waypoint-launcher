# Shared Sign-In Preview — Apple silicon, revision 3

This experimental build supports WoW → Hearthstone (native macOS) and WoW →
Diablo IV (Windows/Wine). It is ad-hoc signed, not notarized; stable Waypoint
remains separate. The preview shares the stable bundle identity so your saved
accounts/preferences remain available. Quit one Waypoint before opening another.

1. Start with a working saved WoW login in Waypoint (Americas). If necessary,
   sign in to WoW once on Blizzard’s page and verify that account works.
2. Install Hearthstone through Available Games. Downloading it does not start
   experimental native authentication. Diablo IV remains an alternative test.
3. Before clicking Play, close all Blizzard games on all devices. Downloads
   can stay running. Remote games cannot be detected automatically.
4. Click Play for Hearthstone using the same Battle.net identity. The preview
   requests fresh Hearthstone authorization using the saved WoW login. It
   bypasses any cached Hearthstone ticket and stops if the exchange fails.
5. Report whether Hearthstone reaches its main menu without a Blizzard
   sign-in page. Do not send tickets, return URLs or credentials.

The WoW Keychain token and account browser session are not replaced. Generated
credentials are not cached in Waypoint’s token vault: their lifetime is unmeasured,
so the preview obtains a fresh one on each launch. The game receives the credential
through its normal existing launch handoff: encrypted net.battle preferences for
native Hearthstone, or the existing Windows/Wine handoff for Diablo IV. Those
handoffs can persist game launch data; this is not a promise of zero disk writes.

Explicit Sign In Again bypasses the experiment and is not a successful shared
sign-in test. Hearthstone tests cross-game login, not paid-game ownership or an
active WoW subscription. Entitlement filtering remains a separate investigation.
No friend functionality is included. Real game acceptance must be tested beyond
server authentication. Mainline Waypoint remains unchanged.

Revision 3 also fixes an AppKit exception that prevented uninstall confirmation
from appearing for games without install-folder user files, including Hearthstone.
The confirmation and existing move-to-Trash behavior are retained.
