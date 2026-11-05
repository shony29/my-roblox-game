# Jelly Blitz 🟢💥

A fast, cheerful free-for-all shooter for Roblox. Everyone is a round **blob**
with googly eyes, running around a colourful arena.

- 🔫 **Three weapons:** Auto Rifle, Pump Shotgun and Sniper (keys **1 / 2 / 3**)
- ⚡ **Fast movement:** dash, double jump and slide
- ⏱️ **Rounds:** 5-minute free-for-all, first to 25 eliminations wins, then a short break
- 🔁 **Quick respawns** at the safest spawn pad, with 2 seconds of spawn protection
- 🪙 **Saved progress:** lifetime eliminations, wins and coins (5 coins per elimination)
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
   appear after pressing **Play** on the menu. That's expected.

## Step 5: Try it alone

1. Press **Play** (F5) at the top of Studio.
2. The arena is built for you, and the main menu appears. Click **PLAY**.
3. After a 10-second break, the round starts ("GO!").

| Control | What it does |
|---------|--------------|
| Mouse | Aim |
| Left click | Shoot (hold it with the Auto Rifle) |
| 1 / 2 / 3 | Auto Rifle / Pump Shotgun / Sniper |
| R | Reload |
| Space, then Space again in the air | Double jump |
| Shift | Dash |
| Ctrl or C (while running) | Slide |
| Tab (hold) | Scoreboard |

Press **Stop** (Shift+F5) when you're done.

## Step 6: Test with 2 or 3 players

Shooting needs someone to shoot at, so Studio can pretend to be several players at once.

1. Click the **Test** tab at the top of Studio.
2. In the **Clients and Servers** box, choose **Local Server**, and set the
   number next to it to **2** (or **3**).
3. Click **Start**. Studio opens extra windows: one **Server** window and one
   window for each player (`Player1`, `Player2`, ...). It can take a little
   while the first time.
4. In **each player window**, click **PLAY** on the menu.
5. Click into one player window to control that player, then click into
   another to switch.
6. When you're finished, click **Cleanup** (in the Test tab, or in the Server window) to close everything.

Things to check:

- [ ] Shooting another player lowers their **health bar**, and the hitmarker appears for the shooter.
- [ ] The **ammo counter** (bottom right) goes down as you shoot, and **R** reloads.
- [ ] When someone is eliminated, the **kill feed** (top right) shows it in every window.
- [ ] Holding **Tab** shows the elimination going up on the scoreboard.
- [ ] The shooter's **coins** (top left) go up by 5.
- [ ] The eliminated player comes back at a spawn pad with a bubble ("Spawn protected").
- [ ] Dash, double jump and slide all work, and other players see your blob move.
- [ ] When the timer runs out, the winner's name is shown and a new round starts.

> **About saving:** coins and stats only *save* in a published game. In
> Studio you'll see a yellow warning in the Output that says progress will not
> be saved. That's expected, and the coins still count up while you test. To
> test real saving, publish the place (File → Publish to Roblox), then turn on
> **Game Settings → Security → Enable Studio Access to API Services**.

**Tip:** with `rojo serve` running, any file you save updates Studio straight
away. Stop the test and start it again to try your change.

---

## Changing the numbers

Every tuning value lives in one file per system:

| File | What it controls |
|------|------------------|
| `src/shared/Weapons/WeaponConfig.luau` | Damage, fire rate, ammo, reload time, range for each gun |
| `src/shared/Movement/MovementConfig.luau` | Walk speed, jump, dash, slide, blob looks |
| `src/shared/Rounds/RoundConfig.luau` | Round length, eliminations to win, break time, respawn delay, minimum players |
| `src/shared/Data/PlayerDataSchema.luau` | Coins per elimination, what gets saved |
| `src/client/UI/Theme.luau` | UI colours, fonts and the game title |

## How the project is organised

```
default.project.json   Tells Rojo where each folder goes inside Roblox
rokit.toml             Which Rojo version to install
INTEGRATION.md         How all the systems connect (and the safety checks)
src/
  shared/    → ReplicatedStorage.Shared
    Combat/     What bullets can hit (blob hitboxes)
    Data/       Shared names for the UI and saving, save-file shape
    Movement/   Movement settings and remotes
    Rounds/     Round settings and shared round state
    Weapons/    Weapon settings, maths and remotes
  server/    → ServerScriptService.Server
    Data/       Saving/loading progress, coins, kill feed, Play button
    Map/        Builds the arena
    Movement/   Blob characters, approves dashes/jumps/slides, anti-speed-cheat
    Rounds/     Round loop, scores, safe spawns, spawn protection
    Weapons/    Checks every shot and deals damage
  client/    → StarterPlayer.StarterPlayerScripts.Client
    Movement/   Dash / double jump / slide controls and the dash badge
    Rounds/     Round caption, winner banner, spawn-protection notice
    UI/         Main menu, HUD, kill feed, scoreboard
    Weapons/    Shooting, tracers, hitmarker, weapon slots
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
