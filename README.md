# SummonSirForever

A warlock summon-service addon for WoW: Forever, forked from [SteaSummonForever](https://github.com/edualve/SteaSummonForever) (MIT).

## Summon service features

SummonSirForever turns SteaSummonForever into a tool for running a **warlock summoning service**, with one warlock, a couple of clickers and an advertiser. Everything new lives in `warlock/` and is controlled with `/ssf` in game. All the original features below still work.

> Not tested in game yet (v1.0.0-w9). Turn on `/console scriptErrors 1` and open an issue with any error text.

### Install (3 min)
1. Download the zip from the [latest release](https://github.com/travv/SummonSirForever/releases/latest).
2. Extract it into `_forever_\Interface\AddOns\`. You should end up with `AddOns\SummonSirForever\SummonSirForever.toc`.
3. Fully restart WoW. A `/reload` is not enough for a new addon.
4. Had SteaSummonForever installed? Delete that folder. The two can't run side by side.

### First run
A one-time **setup panel** opens on each character's first login. It asks you to pick a role, then walks you through that role:
- **Warlock:** destination, price, auto-reply, and plain or "sir" messages.
- **Clicker:** one click turns on soft interact, then it checks your Interact key binding and shows a test banner.
- **Advertiser:** ad channel and warlock name, with a preview of the ad.

Run it again any time with `/ssf setup`.

### Roles
Each window gets one role. Set it with `/ssf role <role>`.

| Role | Who | What it does |
|---|---|---|
| `warlock` | the summoner (default for warlocks) | Replies to customers, invites them, queues them, and keeps the ledger |
| `clicker` | portal clickers (default for everyone else) | Shows a big alert when the portal is up |
| `advertiser` | a character in a city | Shows a one-click **Post ad** button for the Services channel |

### Features
**Payment ledger**
- A trade counts as a payment only when your gold actually goes up by what the customer offered. Forever has no "trade complete" event, so this is how it knows.
- A cancelled trade, or one with items only, logs nothing.
- Each payment links to that customer's latest summon from the last 30 minutes.

**Stats panel**
- Open it with `/ssf` or the `$` button on the summon window.
- It shows this session's summons, gold, gold per hour and % paid.
- It also shows the last 7 days and weeks starting Monday.
- `/ssf today` prints today hour by hour in chat.

**Never-paid list and timed blocklist**
- A customer who arrived and still hasn't paid after 10 minutes goes on the Never paid list, which has **Paid** and **Block** buttons.
- They are also blocked for 24h automatically. If they pay later, the block lifts.
- Blocked players get no reply, no invite and no queue spot.
- Manual control: `/ssf block <name> 7d`, `/ssf unblock <name>`, `/ssf blocklist`.

**Destinations and typo-tolerant requests**
- About 50 presets: capitals, dungeons, raids and towns.
- "wtb sumon tb", "orgrimar?" and "summon to thunder bluf" are all understood.
- If someone asks for a different place than yours, they get a polite reply instead of an invite.

**Whisper flow (warlock role)**
- Anyone who whispers a request gets your price once, plus an invite.
- They're added to the queue as soon as they join, and get their **place in line**. Asking again tells them where they stand.
- **Queue cap** (default 30): past it, new customers get a polite "queue is full".
- People **already standing at the destination** get told so instead of being queued.
- A full party turns into a raid automatically.
- "Thanks for the summon" is never treated as a new order.
- **Summon complete:** when they arrive unpaid, they get a friendly payment reminder.
- **Out of soul shards:** you get an alert and a sound, and the next person in line gets a one-time "hang tight" whisper.

**Messages**
- 8 message types: first reply, place in line, queue full, already here, wrong destination, summon complete, out of shards, advertiser reply.
- Each has 5 lines in the SummonSir voice.
- Each type can be set to a random line, a fixed line, your own custom text, or off.
- **Plain mode** swaps them all for short, serious lines.

**Right-click a name in the queue**
- Move them to the front or back.
- Mark them summoned or remove them.
- Block them and remove them.
- Whisper them any message.

**Big Summon Next button (warlock)**
- A big button showing who's next, how many are queued and your shard count. Clicking it does exactly what your Summon Next keybind does.
- It switches to "Life Tap" when you're low on mana and turns red when you're out of shards.
- Drag its top strip to move it. Its **Clear** button empties the queue (it asks first).
- Size, show or hide, and reset position are in settings, or use `/ssf big on|off|reset`.

**Stable queue rows**
- Rows don't shift while your mouse is over the list, so you don't click the wrong person.
- A row stuck on "pending" with no cast going returns to "requested" after 15 seconds.

**Clicker alert**
- When the portal goes up, clicker windows show **PORTAL UP: press [your Interact key]**, play a sound and flash the taskbar.
- You still press the key yourself.

**Ads (advertiser role)**
- **One click on Post ad posts the ad once to each channel in your list.** The default list is `1, 2, 8`; numbers or names both work (`General, Trade, Services`). There is a cooldown between rounds, and nothing posts on its own.
- Default ad: `WTS summon {dest} {price}. Come get your flight path or quest turn-ins! PST "inv" {spell}`. `{spell}` becomes a clickable **[Ritual of Summoning]** link.
- **The ad follows the main warlock.** The warlock's addon sends its destination and price to the advertiser: the preset it picked, else the destination set on the summon window, else the zone it's standing in. It updates when the warlock moves. If they aren't grouped, typing the warlock's name lets them sync by whisper.
- **"PST inv" works.** With assist in the warlock's raid, the advertiser replies, invites, and puts the customer in the warlock's queue once they join. The warlock gives the advertiser assist automatically (it converts a party to a raid if needed). Without invite rights, the advertiser points people at the warlock instead.

**Fixes to the original**
- The Next keybind now marks the row pending and announces the summon.
- Several Forever API fixes: bag APIs, chat sends, group checks.
- Summon phrases ignore case and punctuation ("123!", "Summon Plz").

### Settings page
Every setting below is also on a **Summon service** page in **Settings > AddOns > SummonSirForever**. Open it with `/ssf options` or the **Options** button on the ledger panel. The slash commands are there for when you'd rather type.

### Quick setup
**Warlock (2 min)**
1. `/ssf dest tb` sets where you summon to (`/ssf dest list` shows all presets).
2. `/ssf price 1g` sets the default. `/ssf price 80s org` sets a price for one destination.

**Clickers (1 min each)**
1. Run `/console SoftTargetInteract 3`.
2. Bind **Interact With Target** in Key Bindings > Targeting.
3. Run `/ssf testportal` to check the banner shows your key.

**Advertiser (1 min)**
1. Join your ad channels (the default list is 1, 2, 8; see `/ssf channels`).
2. Group with the main warlock. You get assist, and the ad follows the warlock's destination and price. Not grouped? Run `/ssf lock <warlock name>`.
3. Click **Post ad** once per round: it posts once to each channel.

### Commands
| Command | Does |
|---|---|
| `/ssf` | Ledger panel |
| `/ssf options` | Summon service settings page |
| `/ssf role warlock\|clicker\|advertiser` | Set this window's role |
| `/ssf dest <name>` / `dest list` / `dest clear` | Destination for ads and replies |
| `/ssf price <amount> [dest]` | Price, e.g. `80s`, `1g`, `1g50s` |
| `/ssf block <name> [30m\|24h\|7d\|perm]` / `unblock` / `blocklist` | Blocklist |
| `/ssf paid <name> [amount]` | Mark a summon paid by hand |
| `/ssf today` | Today's summons and gold by hour |
| `/ssf service on\|off` | Turn the warlock's auto-reply and invites on or off |
| `/ssf cap <n>` | Queue cap for new customers (0 = none) |
| `/ssf plain on\|off` | Plain messages instead of the SummonSir lines |
| `/ssf say <type>` | Print a sample message of one type |
| `/ssf setup` | Run the first-time setup again |
| `/ssf big on\|off\|reset` | Big Summon Next button |
| `/ssf clear` | Clear the whole queue (asks first) |
| `/ssf adtext <template>` / `channels <1, 2, 8>` / `lock <name>` | Ad text, ad channels, main warlock's name |
| `/ssf testportal` | Preview the clicker banner |

### Ground rules
- Nothing here presses keys, clicks, or keeps you online.
- Ads go out only when you click.
- The addon only whispers people who whispered you first.
- Data is saved per WoW account in `SteaWarlockDB`. The original per-character settings are untouched.

---

## Original SteaSummonForever README

<p align="center"><img src="./img/logo-256.png" alt="SteaSummonForever logo" width="200"/></p>

***FAN UPDATE FOR WORLD OF WARCRAFT: FOREVER***

WoW: Forever (Classic+) addon for warlock raid summoning

I am not the original author of this addon but was a huge fan so wanted to bring it to WoW: Forever. This is a continuation of my Season of Discovery fork ([SteaSummonSOD](https://github.com/edualve/SteaSummonSOD)), which itself built on the Wrath update by TheGeneticsGuy:
[Fan Update for Wrath by TheGeneticsGuy](https://github.com/TheGeneticsGuy/Unofficial_SteaSummon)

## Installing
(For this fork, use the install steps at the top: the folder is `SummonSirForever`.)

## New

Manage your raid while summoning, relinquish raid lead when done summoning and leave the raid with raid roles in preferred state

Alt management: allows raiders to be on an alt so their buffs are not ticking, whispers when they are near the top of the list

Auto life tap: the Next button becomes a life tap button when out of mana for summon

## One button summoning, shared summoning list...

<img src="./img/button.png" alt="This Button" height="150"/>

Click one button to summon the next raider on the priority based list. **That** button. No other buttons.
Just keep clicking **that** button. Nothing to read, nothing else to do. If you want to summon further down the list,
you can do that too. If you don't like to click, make a key bind. List all done? The button goes away, or the whole
window depending on your config. Not a Warlock? Make your warlocks get **that button** too, and you can start the summon list before they ever log on.

<img src="./img/buttonwithgrab.png" alt="It gets pretty minimal" height="150"/>

Features a minimal interface that gets out of your way while providing simple, easy, summoning for your whole raid.
Warlocks who have the addon share the same summon list with status updates to drive the one button summoning. Raiders
also have the benefit of seeing their place on the summon list while helping to keep the list alive.

<img src="./img/mainwindow.png" alt="It really does have a list" height="300"/>

Constant status updates distributed to the raid keeps the list current and informative. Know at a glance which raiders
have requested summons, which have a summon on its way, which have a successful summon awaiting acceptance, who's dead,
who's offline, who has world buffs... Strong, durable network code ensures that all raiders have the current list, the
*same* list, in the *same* order, with the *same* people on it. Logged on half way through the raid summon? Your list
is the *raid* list, with all the status intact.

## Raider self management

When your raiders type a summon phrase e.g. 123, they get added to the global summoning list shared by everyone in
your raid using the addon. When they type -123, they remove themselves, and if they have the addon they can just click
the x next to their name. If they didn't accept a summon they can reset their status by typing the summon phrase again,
without losing their place in the list. Players are removed from the summon list when they actually show up at the
destination, even if on foot.

Your raid can't learn 123? That's fine, you get to configure a list of all the dumbest summon requests you can think of.
That is, if you can think of something not already on the default list. Don't worry, your raid will help with that.

## Alt Support

Your summon list is long and the buffs are ticking. SteaSummon will whisper your raid members who are a ways down the list and tell them to whisper back an alt name and log off. The alts get whispered when the player's main gets near the top of the summon list.

## Raid Management

Warlocks often end up starting the raid to get it moving to the raid location. You can configure SteaSummon to manage the raid until the raid lead turns up or summons are over (whichever is configured). When handing over lead you can have Steasummon set up the raid the way your raid leader likes it, with assists and ML already set.

## Configuration

Most things are configurable

* summon trigger phrases
* summon communications through raid, whisper, and say
* summon list priorities (warlock, world buffs, named players)
* window scaling
* summon list save time (for relogging as the last add-on user in raid)
* key binds (Main Menu / Key Bindings / AddOns), never take your eyes off the movie
* alt management
* raid management
* turn off summon list sync (but who would want to do that? Really, who? I want their names and addresses.)

## Resources

If you can help translate this addon into other languages, create a localization file like the one in ./Locale and send me a pull request on GitHub. I like those.

For issues, feature requests, and straight up bugs, please use GitHub issues on this repository.

## More Pictures

<img src="./img/altsupport.png" alt="Alt support" height="300"/>
<img src="./img/raidmgmt.png" alt="Raid support" height="300"/>
<img src="./img/triggers.png" alt="Triggers" height="300"/>
