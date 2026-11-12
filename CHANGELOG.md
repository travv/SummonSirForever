# Changelog

## 1.0.0-w4 (2026-11-11): settings fix

- **Fix: the Options button closed the ledger and opened nothing.** The bundled Ace3 (AceConfigDialog r81, from around 2020) registers settings pages through `InterfaceOptions_AddCategory`, which the Forever client doesn't have. The page was never added, and the original options likely errored at login.
- Updated the bundled Ace3 to **Release-r1403** (AceConfigDialog r92), which uses Forever's `Settings` / `C_SettingsUtil` API.
- The Options button now checks that the Settings page actually opened. If it didn't, it opens a standalone options window, and the ledger panel only closes once something has opened.

## 1.0.0-w3 (2026-11-11): settings page

- New **Summon service** page in Settings > AddOns > SummonSirForever. It holds every `/sw` setting:
  - role and destination
  - prices, including per-destination ones
  - the three reply texts and the auto-reply switch
  - never-paid timing, auto-block and block length
  - block, unblock and mark-paid
  - ad channel, ad text, ad cooldown and the warlock name for ads, with a live preview of the ad text
  - clicker sound, a test banner and an Interact key check
  - erasing the ledger history
- Open it with `/sw options` or the Options button on the ledger panel.
- The settings category is now named "SummonSirForever (character)". The old Trade-ad text and cooldown fields are hidden, since ads are set on the new page.

## 1.0.0-w2 (2026-11-11): renamed to SummonSirForever

- The addon folder, TOC and title are now **SummonSirForever** (repo: github.com/travv/SummonSirForever). Delete any old `SteaSummonForever` folder: the two can't be installed together.
- Saved-data names and the `SteaSummon` sync channel are unchanged, so queues still sync with SteaSummon users.
- Settings from the old folder don't carry over, because WoW stores them by folder name.

## 1.0.0-w1 (2026-11-11), travv fork: summon service

Adds a summoning-service layer in `warlock/` (all new files, MIT). Type `/sw` for the commands.

### New
- **Payment ledger.** Trades are logged once our gold actually goes up by what the other side offered. Forever has no TRADE_COMPLETE, so cancelled trades log nothing. Each payment links to that customer's latest summon from the last 30 minutes.
- **Stats panel** (`/sw`, or the `$` button on the summon window): this session's gold/hr and paid %, plus the last 7 days and weeks starting Monday.
- **Never-paid list.** A customer who arrived and hasn't paid 10 minutes later lands here. The row has Paid and Block buttons.
- **Timed blocklist.** Never-paid customers are blocked for 24h automatically, and paying later lifts the block. Use `/sw block <name> 7d` and `/sw unblock`. Blocked players get no reply, no invite and no queue spot.
- **Destinations and typo-tolerant requests.** "wtb sumon tb" and "orgrimar?" both work. A request for a different place gets a polite reply instead of an invite.
- **Whisper flow (warlock role).** Anyone who whispers a request gets the price once, an invite, and a queue spot when they join. A full party becomes a raid first.
- **Stable queue rows.** Rows stay in place while the mouse is over the window. A row stuck on "pending" with no cast for 15s goes back to "requested".
- **Clicker alert (clicker role).** When the portal goes up, clicker windows show a banner with your Interact With Target key, play a sound and flash the taskbar. You still press the key yourself.
- **Services-channel ads.** The ad goes to Services (`/sw channel`) using a template (`/sw adtext`), one post per click. The advertiser role gets a standalone Post ad button, and the warlock keeps its destination, price and name in sync.

### Fixes
- The Next keybind now marks the row pending and announces it. The CLICK binding never fired OnMouseDown, so the handler moved to PreClick.
- `addWaiting` called `IsInGroup(player)`, which is the wrong argument on modern clients.
- `rummage()` now uses C_Container/C_Item.
- `tonumber(string)`, an always-false dead check, and an undefined `null` are fixed. A stray print and global leaks are removed.
- Chat sends use `C_ChatInfo.SendChatMessage` when it exists (Forever's API list has only that form).
- Summon phrases ignore case and surrounding punctuation ("123!", "Summon Plz").

## 1.0.0 (2026-11-08)

First release for World of Warcraft: Forever, ported from
[SteaSummonSOD](https://github.com/edualve/SteaSummonSOD) v1.07.

### New

- **Trade chat advertising**: an Ad button on the summon window sends a
  configurable advertisement to the Trade channel (cities only), with a
  hard cooldown (default 5 minutes, configurable 1-30) that survives
  relogs. The button shows a live countdown while on cooldown.
  Configure the text and cooldown under Options -> Messages.

### Ported to the Forever client

- Interface 16001; all classic-era APIs the modern engine removed are
  shimmed (metadata, auras, spells, items, container, party management,
  options panel, menus, frame templates, font flags).
- Full support for Forever's first/last character names throughout the
  summon list, chat scanning, and network identity.
- Range, position, mana, connection, and death checks handle the modern
  client's secret values gracefully.
- Secure summon buttons work with the modern cast-on-keydown behavior.
- Soul shard counting works by item ID and includes a soul bag in the
  extra (reagent) bag slot.
- City whispers no longer read "to Thunder Bluff in Thunder Bluff".

### Fixed (pre-existing)

- "invite" auto-invite trigger never matched (only "inv" worked).
- Version display queried the wrong addon name.
- Debug toggle accidentally stored a table and could stick on.
