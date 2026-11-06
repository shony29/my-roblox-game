# Slime Showdown 🟢💥

A fast, cheerful free-for-all shooter for Roblox. Everyone is a round **blob**
with googly eyes, running around a colourful arena.

- 🔫 **Five weapons:** Auto Rifle, Buzz SMG, Pump Shotgun, Sniper and Pop Pistol (keys **1–5** or mouse wheel)
- ⚡ **Fast movement:** dash, double jump and slide
- ⏱️ **Rounds:** 5-minute free-for-all, first to 25 eliminations wins, then a short break
- 🔁 **Quick respawns** at the safest spawn pad, with 2 seconds of spawn protection
- 🪙 **Saved progress:** lifetime eliminations, wins, win streak, level, coins and settings
  (1 coin per elimination and 10 for a win: shop items are a real goal)
- 📋 **HUD:** health, ammo, coins, round timer, kill feed and a Tab scoreboard

---

## What you need

| Thing | What it is |
|-------|------------|
| **Roblox Studio** | Where you play-test the game. Download it from <https://create.roblox.com>. |
| **Rojo** | A small program that copies the code files from this folder into Studio and keeps them in sync while you edit. |
| **The Rojo plugin** | The Studio half of Rojo. It adds a **Rojo** button to Studio. |

---

## Step 1: Install Rojo (one time only)

We use **Rokit**, a small helper that installs the exact Rojo version this
project needs (it's listed in `rokit.toml`).

1. Open a terminal. On Windows, open **PowerShell**. On a Mac, open **Terminal**.
2. Paste the line for your computer and press Enter:

   **Windows (PowerShell):**

   ```powershell
   Invoke-RestMethod https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.ps1 | Invoke-Expression
   ```

   **Mac / Linux:**

   ```bash
   curl -sSf https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash
   ```

3. **Close the terminal and open a new one**, so it can find the new command.

> Don't like terminals? The **Rojo** extension for VS Code can do the same
> thing from a button.

## Step 2: Install the Rojo plugin in Studio (one time only)

1. Open Roblox Studio.
2. Open the **Toolbox** (View tab → Toolbox), switch to **Plugins**, search for
   **Rojo**, and install the official one made by **Rojo**.
3. You should now see a **Rojo** button in the **Plugins** tab.

## Step 3: Get the code onto your computer

1. Install **Git** from <https://git-scm.com> (or use GitHub's green
   **Code → Download ZIP** button and unzip it).
2. Download the project:

   ```bash
   git clone https://github.com/shony29/my-roblox-game.git
   ```

3. Go into the folder:

   ```bash
   cd my-roblox-game
   ```

4. Install the project's Rojo version (say **yes** if it asks whether to trust Rojo):

   ```bash
   rokit install
   ```

## Step 4: Start Rojo and connect Studio

1. In the same terminal, start Rojo:

   ```bash
   rojo serve
   ```

   It should say it's listening on `localhost:34872`.
   **Leave this window open** while you work.

2. In Studio, create a new place from the **Baseplate** template.
3. Go to the **Plugins** tab → click **Rojo** → click **Connect**.
4. Check that the code arrived. In the **Explorer** you should see:
   - `ReplicatedStorage → Shared` (code both sides use)
   - `ServerScriptService → Server` (code that runs on Roblox's servers)
   - `StarterPlayer → StarterPlayerScripts → Client` (code that runs on each player's device)

   Rojo also switches off `Players → CharacterAutoLoads`, so players only
   appear after pressing **Play** on the menu. That's expected. It also
   switches off `Workspace → StreamingEnabled`: the maps are small, so every
   player's device loads the whole world and nobody falls through a floor
   that hasn't loaded yet.
5. Press **Play** in Studio. The bottom-left corner of the game's main menu
   shows the version, for example **Slime Showdown v0.6.3**.

## Getting the newest version (every time the game is updated)

Updates are saved to GitHub, not straight into your Studio. Your computer
keeps the copy you downloaded until you fetch the new one:

1. Stop Rojo: click the terminal window that is running `rojo serve` and
   press **Ctrl + C**.
2. In that terminal, inside the `my-roblox-game` folder, download the changes:

   ```bash
   git pull
   ```

   (Used **Download ZIP** instead of Git? Download the ZIP again and use the
   new folder instead of the old one.)
3. Start Rojo again:

   ```bash
   rojo serve
   ```

4. In Studio: **Plugins → Rojo → Disconnect** (if it still says connected),
   then **Connect** again.
5. Press **Play** and check the version in the bottom-left corner of the main
   menu. If it doesn't show the newest version number (or shows no version
   at all), Studio is still running an old copy.

If `git pull` says *"Your local changes would be overwritten"*, a file was
edited on your computer. Run `git stash`, then `git pull` again.
(`git stash pop` brings your own edit back afterwards.)

## If the graphics look blocky or jagged

Roblox picks a graphics quality for your computer, and on "Automatic" a
laptop often gets a low one. That makes the world and the 3D pictures in the
shop look jagged. A game can't change this setting, so turn it up yourself:

1. While playing (also in a Studio test), press **Esc** → **Settings**.
2. Set **Graphics Mode** to **Manual**, then drag **Graphics Quality** all the way up.

## If something isn't working

1. In Studio, open **View → Output** before you press Play.
2. Press **Play**. Near the top of the Output you should see:
   `[Slime Showdown] Server started: all 16 systems OK` and
   `[Slime Showdown] Client started: all systems OK`.
3. If a system failed, that line names it, and the orange text above it says
   why. A red message also appears at the top of the game screen.
4. Copy those orange or red lines into the chat. They point straight at the
   problem.

## Step 5: Try it alone

1. Press **Play** (F5) at the top of Studio.
2. The main menu appears. Click **PLAY**: you appear in the **slime bunker** lobby.
3. Look around: slime tubes, the shop (press **B**, or **SHOP** on the left) and the
   **DAILY SQUISHY** machine (right, press **E**, then tap the squishy until it bursts).
   Prizes can be items (sometimes one you already own) or **gun upgrades**
   (red → orange → yellow → green → blue → purple; upgrades change your gun's colour,
   not its damage).
4. Press the big green **PLAY** button at the bottom: you're put on a queue pad
   (alone in the server, that's **1v1 vs BOT**, so a practice match starts right away).
   Or walk through the round **portal** under the big sign into the hallway and stand on
   any glowing pad (**1v1**, **2v2**, **4v4**); step off to leave. The big screen behind
   each pad shows **0/2** and the faces of everyone waiting.
   At the very end of the hallway is the big **FREE FOR ALL** pad: step on it and you
   jump straight into the free-for-all arena (no waiting, no minimum, up to 25 players).
   Everyone for themselves; you respawn after being eliminated; first to
   **20 eliminations** (or the most after 5 minutes) wins the round, then the next
   round starts in a new arena. Leave any time with **LEAVE** or **L**.
5. **Testing alone?** The **vs BOTS** pads (right side of the hallway) start a practice
   match with bots (no coins or XP from practice). Teams have **blue** and **red** outlines.
6. **Left door: WEAPONS room.** Every gun sits on a table with its price. Press **E** at the
   counter to open the shop's Guns tab. Coins come from eliminations, wins and tasks.
7. **Right door: PRACTICE RANGE.** Step on the glowing pad. You get your guns and endless
   ammo on a floating sky island: a long lane with a coloured stripe every 25 studs and slime
   targets, plus bullseyes floating all around. Shot targets pop and come back. Leave with the
   **BACK TO LOBBY** pad or press **L**.
8. **TASKS** (button on the left, or **T**): beginner tasks (visit the range, pop 5 targets,
   slide 3 times) and daily quests (play matches, get eliminations, win). Each one pays coins
   the moment it's done.
9. **Top right:** three round buttons. The **gear** opens Settings (sound, mouse sensitivity,
   field of view; saved for next time), the **calendar** shows a short list of your tasks,
   and the **bell** lists your notifications (rewards, level ups, win streaks, the Daily
   Squishy being ready). A small number on a button means something new.
10. Above every player's head: their **level** and **win streak** (matches won in a row).

### The maps

Players vote between three maps before each match. Besides **Jelly Arena** and
**Mossy Keep** there are eight themed arenas: **Astro Station**, **Chef's Kitchen**,
**Cozy Fireplace**, **Ant Farm**, **Coral Reef**, **Ice Castle**, **Candy Land** and
**Bounce House**. They all share one fair, mirrored layout (three lanes, raised
platforms with ramps, a big piece in the middle) and **grow with the number of players**:
smallest for 1v1, bigger for 2v2 and 4v4, biggest for Free For All (which also gets
spawn pads all around).

In matches: hits show **damage numbers** (yellow for headshots, red for the final hit),
and your eliminations show **ELIMINATED <name>** at the bottom of the screen.

### The shop

- Every tab has items of all five rarities, in order: **Common, Uncommon, Rare, Epic,
  Legendary**, and exactly **one Legendary** (this month's themed item; for guns, the
  Blob Launcher).
- Prices grow about 3x per rarity: **50, 150, 500, 1,500, 5,000** coins.
- **Gun upgrades:** a gun you own has an **UPGRADE** button. The first upgrade costs
  1.5x the gun's price (the free guns count as 100) and each level costs 1.6x the one before.
- **Skins** follow each gun's own shape. Click a skin's picture to see it on every gun.
- Charm packet toppings burst into little 3D charms. Your topping also flies out of
  your gun with every shot, and the players you eliminate explode into it.
- **ROBUX tab:** coin packs (250 to 5,000 coins) and two bundles: the **Monthly
  Collection** (all four of this month's themed items) and **Coin Rush** (2,000 coins
  plus this month's gun skin and charm packet), both cheaper than buying one by one.
  They need Developer Product ids, see *Selling the monthly themed items for Robux*.

| Control | What it does |
|---------|--------------|
| Mouse | Aim (first person in matches; menus free the mouse while open) |
| Left click | Shoot (hold it with automatic weapons) |
| 1 – 8 or mouse wheel | Your guns: Auto Rifle (free), Buzz SMG, Pump Shotgun, Slimeshot Marksman, Triple Burst, Sniper, Blob Launcher, Pop Pistol (free) |
| R | Reload |
| Space, then Space again in the air | Double jump |
| Shift (hold, moving forward) | Sprint |
| Q | Dash |
| Ctrl or C (while running) | Slide |
| Tab (hold) | Scoreboard |
| B | Shop |
| T | Tasks |
| G | Shop: Guns tab (in the lobby) |
| L | Leave the practice range |

Press **Stop** (Shift+F5) when you're done.

## Step 6: Test with 2 or 3 players

1. Click the **Test** tab at the top of Studio.
2. In the **Clients and Servers** box, choose **Local Server** and set the number to **2**
   (use **4** to try 2v2).
3. Click **Start**. Studio opens a **Server** window and one window per player.
4. In **each player window**: click **PLAY**, walk through the portal and stand on the **1v1 DUEL** pad.
5. Click into a player window to control that player.
6. When you're finished, click **Cleanup** in the Test tab.

Things to check:

- [ ] Both players appear in the arena on opposite sides, frozen, with a 3-2-1 countdown, then **GO!**
- [ ] You can't shoot during the countdown or between rounds, and never your own teammates.
- [ ] Shooting lowers the other player's **health bar**; the **ammo counter** (bottom right) shows magazine / spare bullets.
- [ ] Walk over a glowing green **slime ball** on the map: your spare ammo goes up and the ball comes back 15 seconds later.
- [ ] An elimination shows in the **kill feed** (top right) and the **scoreboard** (Tab); the shooter earns **1 coin**.
- [ ] The eliminated player sits out; the round ends (ROUND WON / ROUND LOST) and both respawn for the next round.
- [ ] First to 5 rounds shows the **results screen** (VICTORY / DEFEAT, MVP, stats, coins).
- [ ] Press **REMATCH** in both windows: a new match starts with the same players. Otherwise both return to the lobby after 10 seconds.
- [ ] Sprint, dash, double jump and slide work; other players see your blob jiggle as it moves.
- [ ] Open the shop (the counter, or **B**). Every card shows its rarity. Try the **Toppings** tab: equip one, then eliminate someone and watch them burst into it.
- [ ] Press **B** for the shop; buying a colour recolours your blob. In the **Guns** tab, buy a gun: it appears in your weapon bar next match (everyone starts with only the Auto Rifle).
- [ ] In the lobby there are no guns, no crosshair, no ammo counter and no weapon bar.
- [ ] PLAY puts you on a pad; the screen behind it shows your face and the count.
- [ ] Shop: Colors and Squishies show the real 3D slime; each gun in the Guns tab has its own toy design (click its picture for the details window); the Skins tab has the Glue, Activator, Foam, Clay and Water guns plus this month's themed gun.
- [ ] The practice range: targets pop when shot, the TASKS list counts them, coins arrive with a message.
- [ ] Stand on the **FREE FOR ALL** pad at the end of the hallway: you're in the free-for-all arena at once. With 2+ player windows everyone can hit everyone, you respawn, and the top shows the timer and the leader. **L** takes you back to the lobby.
- [ ] Eliminated players drop a green **AMMO** crate; walking over one (or the crates on the map) refills spare ammo.

> **About saving:** coins and stats only *save* in a published game. In
> Studio you'll see a yellow warning in the Output that says progress will not
> be saved. That's expected, and the coins still count up while you test. To
> test real saving, publish the place (File → Publish to Roblox), then turn on
> **Game Settings → Security → Enable Studio Access to API Services**.

**Tip:** with `rojo serve` running, any file you save updates Studio straight
away. Stop the test and start it again to try your change.

---

## Selling the monthly themed items for Robux

Every month has a themed set (a blob colour, a squishy, a gun skin and a charm-packet
topping, e.g. **December = Christmas**, **January = Winter Wonderland**). They only show in
the shop during their month and are bought with **Robux**. Until you set them up they show
**SOON**.

1. Publish the game (File → Publish to Roblox).
2. Open the [Creator Dashboard](https://create.roblox.com/dashboard/creations), pick your game,
   then **Monetization → Developer Products → Create a Developer Product**. Make one product per
   themed item (name it like the item, e.g. "Christmas Charm Packet", and set its Robux price).
3. Copy each product's **ID** into `src/shared/Config/ShopConfig.luau`, in `ShopConfig.ProductIds`:

   ```lua
   ShopConfig.ProductIds = {
   	["Theme_Christmas_Topping"] = 1234567890,
   	["Theme_Christmas_Squishy"] = 1234567891,
   }
   ```

   Item names are `Theme_<Theme>_Color`, `_Squishy`, `_Skin` or `_Topping`, where `<Theme>` is
   Winter, Sweetheart, Lucky, Bloom, Berry, Splash, Sparkler, Tropical, School, Spooky, Harvest or
   Christmas.
4. Save (Rojo syncs it) and publish again. In Studio, Roblox shows a *test* purchase window,
   so no real Robux are spent while testing.

Only the server grants Robux items (after Roblox confirms the payment), each purchase is
granted once, and guns are never sold for Robux, only cosmetics.

## Changing the numbers

Every tuning value lives in one file per system:

| File | What it controls |
|------|------------------|
| `src/shared/Config/WeaponConfig.luau` | Damage, fire rate, ammo, reload time, range for each gun |
| `src/shared/Config/MovementConfig.luau` | Walk speed, jump, dash, slide, blob looks |
| `src/shared/Config/RoundConfig.luau` | Round length, eliminations to win, break time, respawn delay, minimum players |
| `src/shared/Data/PlayerDataSchema.luau` | Coins per elimination, what gets saved, settings ranges |
| `src/shared/Config/ShopConfig.luau` | Shop items, rarities and prices (`PRICE`) |
| `src/shared/Config/UpgradeConfig.luau` | Gun upgrade levels and their prices |
| `src/shared/Config/QuestConfig.luau` | Tasks, their coin rewards and the win bonus |
| `src/client/UI/Theme.luau` | UI colours, fonts and the game title |

## How the project is organised

```
default.project.json   Tells Rojo where each folder goes inside Roblox (plus lighting and camera)
DEVELOPMENT.md         Checklist, security audit and performance notes
src/
  shared/    → ReplicatedStorage.Shared
    Config/      All settings: game, camera, movement, weapons, modes, maps, spawns, shop, sounds
    Net/         Every client–server message (Net.luau) and small helpers
    Match/       Match states and team names
    Data/        Save-file shape and XP/levels
    Combat/      What bullets can hit, weapon maths
    Cosmetics/   Hat and weapon-skin builders
  server/    → ServerScriptService.Server (init.server.luau starts everything in order)
    Services/    PlayerData, Menu, Shop, Cosmetics, Movement, Weapon, Spawn,
                 Map, Lobby, Match, Queue, Vote
    Components/  Slime rig, blob, gun model, combat rules, team balancer,
                 rate limiter, practice dummy
    Map/         Jelly Arena, Mossy Keep, the slime bunker lobby and shared map helpers
  client/    → StarterPlayerScripts.Client (init.client.luau starts everything in order)
    Controllers/ Graphics, Shop, UI, Movement, Weapon, Camera, Viewmodel,
                 BlobAnimator, MatchHud, Lobby, Transition, Results, Feedback
    UI/          Menu, HUD, kill feed, scoreboard, weapon HUD, dash badge, shop previews
    Effects/     Tracers, muzzle flashes, impact puffs
```

## How it stays fair

- **The server is the referee.** A player's computer can only say "I fired
  this gun from here, aiming that way". The server checks the values are real,
  that you're alive and holding that gun, that you have ammo and aren't firing
  too fast, and that you aren't shooting from inside a wall. Then it does its
  **own** raycast to decide what you hit. Damage comes only from `WeaponConfig`.
- **Scores, coins and wins are only changed on the server.**
- **Movement is checked.** If someone moves faster or higher than the rules
  allow, the server snaps them back.
- **Saving is careful.** Retries, session locking, autosave, a save when you
  leave and when the server shuts down, and it never saves over data that
  failed to load.
- Every file uses `--!strict` Luau typing.
