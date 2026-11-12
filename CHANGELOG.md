# Changelog

## 1.0.0-w11 (2026-11-11): stock Forever look, usability pass

Travis's call after seeing w10 in game: drop the custom palette and use the game's own styling. Every window now sits on the stock templates.

### Summon window
- Built on the standard window template: title bar ("SummonSir"), Ritual of Summoning icon in the portrait circle, close button, inset for the queue, resize grip. Default size 400 x 340, never smaller than 360 x 180.
- Header is three fixed rows that no longer run into the queue: **Location** with the warlock/clicker counts on the right, **Destination** (click the line to set it to where you stand, click again to clear; shows "not set" with a hint until then) with the shard count on the right, then a button row.
- Button row: **Next** (the keybound cast button, with its key in the tooltip), **Summon me** (replaces the floating portrait button; shows for anyone grouped who is not at the destination, and reads "Reset Summon" once you are in line), then **AFK**, **Ad**, **Ledger** (was `$`) and **Menu** (was `>`), all standard buttons with tooltips.
- Queue rows are no longer pre-shrunk to half size. The list scale setting resets to 1.0 once; the name column is wider and the X no longer overlaps it.
- Removed from the window: the tiny raid-info and raid-lead icons (both stay in the Menu and on the keybind).

### Other windows
- Ledger, setup: standard windows with title bar, portrait icon and inset.
- Big Summon Next, portal banner, advertiser window: the standard tooltip-style backdrop; the big button uses the normal button art.
- Setup role choice uses standard buttons; the chosen one stays lit.
- Color names in the code now map to the game's standard font colors (gold labels, white text, gray hints, green/red/orange status, Warlock class color for headings).

## 1.0.0-w10 (2026-11-11): X and Clear work from the warlock, summon window restyled

### Fixes
- **The X next to a name and Clear queue did nothing from the warlock.** Root cause found in the wire format: the network removal message is `a <player> true`, and the receiver split it on spaces. With Forever's two-word names, `a Summ Bert true` read the player as "Summ" and the flag as "Bert", so the leader never found anyone to remove. The parser now takes the last word as the flag and everything before it as the name.
- **Removals and status changes no longer depend on the network leader.** Every client applies them locally and tells the whole group (the leader relays once, no echo loop). Before, a non-leader warlock only whispered the leader, which is usually a clicker or the advertiser, and a lost whisper meant nothing happened.
- **Summon whisper could name the wrong person.** The Next button announced a name captured at the last redraw while its cast macro could be re-aimed through a stale list index mid-cast, and the big button copied that macro on a half-second timer. Next, the row buttons and the big button now pick the person at click time, aim the macro at them and announce the same name.
- Comm senders arrive as `Name-Realm` on modern clients; they are normalized so own echoes are dropped and leader checks compare equal.
- `ct` (chat-this) relays keep two-word target names.
- Record removal checks the real list length and resyncs the cached count.

### New
- `/sw queuedebug` prints me, role, leader state, netList, the waiting list, the last removal and the last comm message. Paste it when a removal fails.
- **Summon window restyle (Dracula):** solid #282a36 background with a purple border, 12pt location and destination text under the button row (destination in cyan), warlock/clicker counts inside the frame, and a flat top bar `[$] [AFK] [Ad] [>]` with 20px buttons. AFK turns red while on; Ad is purple and dims during its cooldown.

## 1.0.0-w9 (2026-11-11): advertiser works like Travis's macro

- **One Post ad click posts the ad once to each listed channel.** The default list is `1, 2, 8`, as numbers or names (`/sw channels`). There is still one cooldown per round and nothing on a timer.
- **New default ad** with a `{spell}` link: `WTS summon {dest} {price}. Come get your flight path or quest turn-ins! PST "inv" [Ritual of Summoning]`. The old default ads upgrade automatically, and a customized single channel carries over.
- **The ad follows the main warlock's position.** The warlock sends its destination name and price (preset, else the summon window's destination, else its zone) on every change, zone change and group change. The advertiser asks every 30s, by whisper if ungrouped. The advertiser never advertises its own city.
- **The advertiser invites and queues** "inv" whispers when it has invite rights (`C_PartyInfo.CanInvite`). The customer joins the warlock's queue. The warlock auto-promotes known advertisers to assist and converts a party to a raid. Without rights, the advertiser falls back to the redirect reply.

## 1.0.0-w8 (2026-11-11): no addon tag on messages

- Messages no longer start with `[SummonSir]`. Whispers, raid/say notices and nags go out exactly as written.
- Tagged phrases from other SteaSummon users ("[SteaSummon] 123") are still recognized as summon requests.

## 1.0.0-w7 (2026-11-11): removal fixes, big Summon Next button

### Fixes
- **The X next to a player, and Clear Summon List, did nothing.** There were two causes:
  - The X waited for a "released inside the button" flag that modern clients don't pass. It's now a normal click.
  - Every removal is routed through the queue leader. On Forever the leader list was built from `GetPlayerInfoByGUID` names, which can be first-name-only ("Summ" instead of "Summ Bert"), so nobody was ever leader and removals were whispered to nobody. The list now uses full roster names. When no reachable leader exists (solo, mid-handshake, or a leader not in the group), removals and status changes apply locally and are sent to the group directly.
- The minimap's Clear Summon List always asks first.
- The Next button and keybind announced twice per press (PreClick fires on both mouse-down and mouse-up). They now act once, on the same half of the press as the cast.

### New
- **Big Summon Next button** for the warlock, with a Clear button. `/sw big`, `/sw clear`, and options under Settings > Summon service.
- "Clear whole queue..." in the right-click menu on queue names.

## 1.0.0-w6 (2026-11-11): Lazy Summoner parity, first-run setup

Covers what The Lazy Summoner does, as our own code.
- **One-time setup panel** on each character's first login (role, then role-specific setup). `/sw setup` runs it again.
- **Place in line:** sent when someone joins the queue, and again when they ask.
- **Queue cap** (default 30, `/sw cap`), with a "queue is full" reply.
- **Already here:** a reply for people standing at the destination, instead of queueing them.
- **Summon complete:** a payment reminder when an unpaid customer arrives.
- **Out of soul shards:** an alert and sound for you, plus a one-time whisper to the next in line. Shards are now counted straight from your bags.
- **Messages:**
  - 8 types with 5 SummonSir lines each.
  - Each can be random, a fixed line, custom text, or off.
  - Plain mode (`/sw plain`).
  - All of it is on the settings page.
  - Edited texts from earlier versions carry over as custom text.
- **Right-click menu on queue names:**
  - move to front or back (queue leader only; it syncs to every warlock)
  - mark summoned, remove, block
  - whisper any message

## 1.0.0-w5 (2026-11-11): SummonSir house style

- New default messages, with "sir" and exclamation points. For example:
  - summon whisper: "Sit back and relax! The summon is on the way, sir :)"
  - first reply: "Right away, sir! Summon to {dest} is {price}. ..."
  - ad: "Summons to {dest} for {price}, sir! /w {lock} 123, then sit back and relax!"
- Covers the raid, say and whisper notices, the raid info and clicker nags, the alt whispers, the AFK reply, our three customer replies and the ad.
- Saved messages still on the old stock wording are upgraded at login. Anything you wrote yourself is kept.
- Outgoing chat is tagged `[SummonSir]` instead of `[SteaSummon]` (tag removed in w8). Summon phrases with either tag are still recognized.

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
