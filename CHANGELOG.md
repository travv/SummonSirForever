# Changelog

## 1.0.0-w23 (2026-11-12): fixes the broken w22

- **w22 shipped with an empty TOC file and does not load. Do not use it.** w23 is w22 with the TOC restored. Nothing else changed.

## 1.0.0-w22 (2026-11-12): one-line status on the clicker page

- The clicker setup page's "hear it in the background" status fits on one line, so step 4 no longer crowds it.

## 1.0.0-w21 (2026-11-12): channel checkboxes, ad text per destination

- **Ad channels are checkboxes.** The Ads tab and the advertiser setup page list every chat channel this character has joined, one checkbox each; tick the ones the ad should go to. The long channel line that wrapped into the text below it is gone. The list is still saved by channel name, so /ssf channels and the settings box keep working, and a channel you listed but have not joined shows in orange.
- **The ad fits the destination.** The default ad is now "WTS summon {dest} {price}. {blurb} PST "inv" [Ritual of Summoning]", where {blurb} is a short line per spot: Scarlet Monastery "Skip the run through Tirisfal.", Booty Bay "Flight path, neutral AH, Stranglethorn quests.", Gadgetzan "Zul'Farrak and the Tanaris quest hub.", Desolace "Flight path and quest turn-ins.", and so on for every preset (fallback "Skip the walk."). Saved copies of the old default ad upgrade once; your own ad text is kept, and {blurb} is available in it.

## 1.0.0-w20 (2026-11-12): shorter messages

- Every customer message is rewritten shorter: "sir" once, no exclamation points, no carriage (the warlock player found the old lines a bit much). The five variants per type are kept, the price / 2 minutes / pay-by-trade facts stay in every first reply, and plain mode is unchanged. The same goes for the group announce, the summon whisper, the click nag and the AFK reply.
- Saved copies of the old stock wording upgrade once; anything you typed yourself is left alone.

## 1.0.0-w19 (2026-11-12): tab screenshots, round one

- The ledger headline, the Ads title and the setup "step n of 3" line start to the right of the portrait circle instead of under it.
- The Ads channel line names each channel once ("Trade - City", or "8 Services" when you listed a number) instead of "Trade Trade".
- The ad text box fits the text instead of filling the tab.

## 1.0.0-w18 (2026-11-12): LookingForGroup is an ad channel

- The default ad channels are **General, Trade, Services, LookingForGroup**. LookingForGroup is the one global channel and players opt in to it, so the ad belongs there (Travis, 2026-11-12). A saved w16 default ("General, Trade, Services") picks it up once; a custom list is kept.

## 1.0.0-w17 (2026-11-12): one window with tabs, /ssf

- **One window, four tabs along the bottom: Queue, Ledger, Ads, Setup.** Every character sees every tab, so a clicker can read the ledger and the advertiser can watch the queue. The tabs are the game's own (the character-frame style). Hover a tab for what it holds; a second press on the current tab closes the window.
  - Queue is the summon window as before (header, buttons, list). The Ledger button left the header; the ledger is a tab.
  - Ledger is the former ledger panel: session headline, scrolling history, open tabs with Paid / Block, Options.
  - Ads is the former ad window: where it posts, sync state, the ad as it will read in its own box, Post ad. An advertiser logs in on this tab.
  - Setup is the walkthrough, inside the window. First run opens the window on this tab; leaving the tab counts as done; it is safe to rerun any time.
- The window is 480 x 400 by default and never smaller than 460 x 340, so every tab fits. Switching tabs is blocked during combat (the queue's cast buttons are locked then).
- **The slash command is /ssf** (SummonSirForever). /sw still works as an alias. Every message, tooltip and doc now says /ssf. New: /ssf tab <queue|ledger|ads|setup>.

## 1.0.0-w16 (2026-11-12): fixes from the first w15 screenshots

- **Ad channels default to names: General, Trade, Services.** Channel numbers belong to one character: on the advertiser, /8 turned out to be LookingForGroup, so the "1, 2, 8" default would have posted the ad there. Names resolve on every character. A saved "1, 2, 8" is migrated once; any other custom list is kept. The ad window and the settings page already show the resolved channel names, so you can see where an ad will land before posting.
- **Ledger headline when empty** reads "No summons yet" in large type with the explanation under it (it was the other way around).
- **Destination line on clickers and advertisers** no longer says "click to summon to where you stand" (they cannot). It shows the warlock's synced destination on the advertiser, or "the warlock sets it" until one is pinned.
- Scroll bars on the queue and the ledger body hide while everything fits, instead of showing arrows over an empty list.

## 1.0.0-w15 (2026-11-12): the side panels read at a glance

- **Ledger panel leads with the number that matters:** a large "12 summons   11g 50s   23g/hr   92% paid" headline under "This session (1h12m)". The history (7 days, weeks) scrolls instead of clipping once there is a week of data; the role / destination / price / shards line moved to the bottom, dimmed.
- **Open tabs replace the never-paid list.** Everyone who arrived and has not paid shows up right away ("Summ Bert  arrived 2m ago, owes 1g") with Paid and Block buttons, so a mail payment or a comp can be marked at once instead of after the 10-minute flag. Past the grace time the row turns red and reads "never paid". Flagged customers stay listed until they pay.
- **Every payment prints one green "paid:" line and plays the coin sound,** on both settle paths (the 2 s timer path printed nothing before). A short payment says by how much; gold with no open summon says "tip".
- **Big Summon Next button:** titled "Next up", shows your keybind on the bottom line, turns green while casting, and has a tooltip. Clickers and the advertiser no longer pay for its half-second refresh.
- **PORTAL UP banner** has a thin green bar that drains over the 30 s the portal can stay up. The no-key hint names the exact menu path.
- **Ad window** reads "Waiting for warlock" and stays disabled until the advertiser has synced (it would have posted "WTS summon ? 1g"); the window grows with a long ad instead of spilling; the button has a tooltip. After a post, chat says "Ad posted to General, Trade, Services" and lists channels you have not joined.
- **Sounds for a four-window operator** (settings group renamed "Alerts and sounds"): a ping on the warlock when someone lands in the queue and the coin sound on payment, both on by default and switchable.
- The Ledger button's tooltip and the Options button (now in the open-tabs row, clear of the close button) explain what they open.

## 1.0.0-w14 (2026-11-12): setup walkthrough and settings page teach the features

- **Setup is three steps, not four.** The welcome text sits on the role page, and clicking a role moves straight on to that role's page. Hover a role for what it does.
- **Warlock page checks your Summon Next key** (green "Bound to F" or an orange line with the menu path), the same way the clicker page checks Interact. Boxes save when you press Enter or click away, not on every keystroke, so a half-typed price is never saved. The sample reply updates live.
- **Prices you type are gold by default:** "1" means 1g, "1g50" means 1g 50s. 1g, 80s and 1g50s still work. Applies to setup, the settings page and /sw price.
- **Clicker page, new step 3: hear the alert in the background.** One button turns on the game's "sound while inactive" setting. Clicker windows streamed from the VM are never the focused window, so without it the PORTAL UP sound was silent. Also a toggle on the settings page.
- **Advertiser page offers Join buttons** for channels you listed by name but have not joined, and explains why a number alone cannot be joined.
- **Done page** names your actual Summon Next key and points at /sw help.
- **/sw help** lists every command (the settings intro and done page now say so; bare /sw opens the ledger, an unknown command prints the list).
- **Settings page gains a "Summon window" group:** show always / while someone is in line / while I am in line / never, and the queue row size. The price help and the Interact key hint use the same wording as setup.
- Setup opens on PLAYER_LOGIN (4 s in) instead of right at addon load, so the per-character flag is keyed by the full two-word name. Building the setup frame no longer counts as finishing it.
- "/sw service" prints "auto-reply and invite: on", matching the settings label.

## 1.0.0-w13 (2026-11-12): the summon window explains itself

A polish pass on the window everyone looks at, so a crew member who never read a doc can tell what each thing means.

- **Plain words in the Status column:** Waiting, Casting, Portal up, Arrived, Declined, Offline, Dead (were the internal names: requested, pending, summoned, accepted).
- **NEXT marker.** The small cell between the name and the status (upstream's raid-priority letter, which meant nothing for a service) now shows a green NEXT on the person the Next button, its key and the big button will summon. Hover it for the explanation.
- **Empty queue says so:** "Nobody in line. People who whisper you for a summon show up here." (clickers see "The warlock's queue shows up here.")
- **Header counts read at a glance:** "Clickers 2   Raid 7/40" on the right of the Location line. Clickers turn green when there are enough to click, the raid count turns orange at 35 and red at 39, since invites fail silently at 40. Ungrouped shows "not grouped".
- **Tooltips on everything:** every header button (Menu, AFK with its on/off state, Ad with the channel list, Summon me), every queue name ("Click: summon them now. Right-click: move, remove, block or whisper.") and every X ("Remove from the queue. No charge, no block.").
- **Summon me is hidden on the warlock running the service.** A misclick queued the warlock itself and posted "123" to the raid. It is still in the Menu.
- **The window stays up for the warlock** even with nobody in line (it holds AFK, Ad, Ledger and Menu). Applied once; the window mode setting still works.
- **Escape closes the window.** Reopen it from the Menu or the minimap button.
- The resize grip no longer sits on the scrollbar's down arrow; the minimum width is 380 so nothing overlaps.
- Chat lines from the addon start with "SummonSir:" (was "Warlock:"), and a whisper from a blocked player prints one dim "ignored Name (blocked: never paid, 3h left)" line per name every 10 minutes instead of vanishing silently.

## 1.0.0-w12 (2026-11-11): layout fixes from the first w11 screenshots, stuck offline customers

- **Header text no longer sits under the portrait circle.** Location and Destination start to the right of it. The ledger and setup windows drop the portrait altogether (it covered their first line).
- **Why "Ur Momsman" was stuck for an hour:** he logged off while queued. The addon kept him as "offline" and only a warlock standing at the destination had an X, so nobody on the team could remove him. Now:
  - every character running the addon in the group sees the X on every row (and always on their own);
  - the warlock drops anyone who left the group right away, and anyone offline for longer than the new **Drop offline customers after** setting (default 5 minutes, 0 keeps them). A chat line says who was dropped and why.
- Ledger shows "Never paid: nobody so far" instead of an empty box.

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
