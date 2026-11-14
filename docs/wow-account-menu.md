# WoW account menu

The developer branch feat/wow-account-selection (reviewed at 167ede2) keeps
owner/region-scoped lists, checks the selected licence in a submenu and offers
explicit refresh. This release adopts that interaction while retaining the
personal native authorization path. No automatic network discovery happens
when opening a menu or starting the app.

- New Americas WoW identities choose a default after sign-in. Cancelling keeps
  the Battle.net identity signed in, without choosing or launching a game.
- Existing per-edition choices take precedence over the new owner/region
  default. Existing gameAccountSelections data needs no destructive migration;
  the reserved edition key * stores new defaults in the existing format.
- Lists live in separate gameAccountCatalogs preferences. Missing and successful
  empty lists differ; malformed/failed updates do not replace a good list.
- All list and choice operations bind to the owner and region snapshot. Menu
  actions discard a stale owner or region instead of applying it elsewhere.
- A refreshed-out choice stays remembered and is shown unavailable in the menu;
  Play requires another explicit choice. Refresh does not silently change it.
- Duplicate licence names include IDs in the menu for disambiguation.
- Row state observes the saved licence and effective region so metadata updates
  immediately when a title selection or active identity changes.
- First-time setup without WoW authorization is deferred to the first WoW
  sign-in/launch. No reverse exchange from other titles is assumed.

Validation includes persistence, default/override precedence, owner/region
isolation, malformed/duplicate catalog rejection, and clearing a stale shared
GAME_ACCOUNT on an unselected launch. New-identity interactive signup requires
user acceptance beyond these synthetic state tests; no saved identity is removed
just to simulate onboarding.
