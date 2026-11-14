# Shared Sign-In Preview — Apple silicon

This is an experimental build, not the stable release. It is ad-hoc signed,
not notarized. Its stable bundle identity preserves your existing Waypoint
accounts, games and preferences. It includes normal installers and Wine support.
Keep the stable ZIP so you can return to it. Quit Waypoint before replacing
its installed application with this preview; keep only one deployed copy.

1. Start with a working saved WoW login in Waypoint (Americas). If necessary,
   sign in to WoW once using the usual Blizzard page and verify it works.
2. Install Diablo IV through Available Games. Downloading it does not run the
   experimental native authentication check.
3. Before clicking Play, close all Blizzard games on every Mac. Downloads can
   keep running. Local WoW is checked, but remote games cannot be detected.
4. Click Play for Diablo IV using the same Battle.net identity. This preview
   must obtain a new Diablo IV ticket using the saved WoW login. It deliberately
   bypasses any cached Diablo IV token, and stops with a clear message if the
   exchange fails. It does not silently fall back to an old login.
5. Report whether Diablo IV reaches account/character selection without a
   Blizzard sign-in page. Do not send tickets, return URLs or credentials.

The source WoW Keychain token and account web session are not replaced. Generated
Diablo credentials are used for that launch only, through Waypoint's existing
Windows launch handoff. Their expiry/reusability is unmeasured, so they are not
saved to the token vault. A new native issuance occurs on each preview launch.

The normal explicit Sign In Again command bypasses the experiment. Using that
command is not a successful shared-sign-in test. No friends functionality or
entitlement filtering is included. Server authentication passed in the isolated
probe, but actual Diablo IV launch/gameplay remains unverified.
