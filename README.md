# Jelly Blitz 🟩💥

A fast, cheerful first-person paint shooter for Roblox, inspired by Shell
Shockers, except everyone is a wobbly **low-poly jelly cube** with googly eyes.

- ⚡ **Fast movement:** high run speed, **double jump**, a quick **dash** (Shift or Q) and bouncy launch pads
- 🎨 **Low-poly look:** simple, colorful shapes, so it stays light and runs smoothly
- 🔁 **Instant respawn:** get splatted and you're back right away, with 1.5 s of spawn protection
- 🪙 **Coins and a shop:** earn 10 coins per splat and spend them on jelly colors (saved between visits)

---

## 1. Install Rojo and the Rojo Studio plugin

**Rojo** copies the code files from this folder into Roblox Studio, and keeps
them in sync every time you save. You need two parts: the Rojo program and the
Rojo plugin inside Studio.

### a) Install Rokit (it installs Rojo for you)

Rokit is a small tool installer. Open a terminal (on Windows, open **PowerShell**)
and run:

**Windows (PowerShell):**

```powershell
Invoke-RestMethod https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.ps1 | Invoke-Expression
```

**Mac / Linux:**

```bash
curl -sSf https://raw.githubusercontent.com/rojo-rbx/rokit/main/scripts/install.sh | bash
```

Then **close and reopen** your terminal so it can find the new command.

> Prefer not to use the terminal? You can also install the **Rojo** extension
> for VS Code. It can install Rojo and start it from a button.

### b) Install the Rojo plugin in Roblox Studio

1. Open Roblox Studio.
2. Go to the **Toolbox** (View → Toolbox) → **Plugins**, search for **Rojo**, and
   install the official one by **Rojo** (it has lots of installs).
3. You'll see a **Rojo** button in the **Plugins** tab.

(Alternatively, once Rojo is installed, run `rojo plugin install` in a terminal.)

---

## 2. Get this code onto your computer and run `rojo serve`

1. Install **Git** from <https://git-scm.com> if you don't have it. (Or use
   GitHub's green **Code → Download ZIP** button and unzip it.)
2. Download the project:

   ```bash
   git clone https://github.com/shony29/my-roblox-game.git
   ```

3. Go into the folder:

   ```bash
   cd my-roblox-game
   ```

4. Install the exact Rojo version this project uses (listed in `rokit.toml`).
   Say **yes** if it asks whether to trust Rojo:

   ```bash
   rokit install
   ```

5. Start the Rojo server:

   ```bash
   rojo serve
   ```

   It should say it's listening on `localhost:34872`. **Leave this window open**
   while you work.

---

## 3. Connect from Roblox Studio and test the game

1. In Studio, create a new place from the **Baseplate** template.
2. Open the **Plugins** tab → click **Rojo** → click **Connect**.
   Your scripts now appear in Studio:
   - `ServerScriptService → Server` (server code)
   - `StarterPlayer → StarterPlayerScripts → Client` (player code)
   - `ReplicatedStorage → Shared` (code both use)
3. Press **Play** (F5). A colorful arena is built for you automatically.
   Try it out:
   - **Mouse** to look around, **hold left click** to shoot
   - **Space twice** to double jump, **Shift or Q** to dash
   - **R** to reload, **B** (or the SHOP button) for the shop
   - Step on the glowing yellow pads to bounce up high
4. **Test with other players:** go to the **Test** tab, set the player count to
   **2**, and click **Start** (Clients and Servers). Two windows open, and you can
   splat each other, watch the kill feed and earn coins.
5. **Turn on saving (optional):** coins only save in a *published* game.
   Publish once (File → Publish to Roblox), then go to **Game Settings →
   Security** and turn on **Enable Studio Access to API Services**. Until you
   do this, the HUD shows a red "Progress is not being saved" note. That's
   expected, and nothing is broken.

**Tip:** edit any file (try the numbers in `src/shared/Config.luau`), save it,
and Rojo updates Studio straight away. Stop Play and press Play again to try the
change.

---

## How the project is organised

```
default.project.json   Tells Rojo where each folder goes inside Roblox
rokit.toml             Which Rojo version to install
src/
  shared/              Code both sides use (ReplicatedStorage.Shared)
    Config.luau          ← All the gameplay numbers: speed, damage, rewards...
    ShopCatalog.luau     ← The colors you can buy, and their prices
    Remotes.luau         How the server and clients send messages
    Types.luau           Shapes of the data (for type checking)
  server/              Runs on Roblox's servers (ServerScriptService.Server)
    init.server.luau     Starts everything
    Services/
      PlayerData.luau      Saving and loading progress (DataStores)
      CombatService.luau   Checks every shot and applies damage
      CharacterService.luau Jelly look, speed, instant respawn
      ShopService.luau     Buying and equipping colors
      ArenaBuilder.luau    Builds the map if you haven't made one
    Util/RateLimiter.luau  Stops remote spam
  client/              Runs on each player's device (StarterPlayerScripts.Client)
    init.client.luau     Starts everything
    Controllers/
      WeaponController.luau   Shooting, reloading, tracers, first-person blaster
      MovementController.luau Double jump, dash, launch pads
      HudController.luau      Crosshair, health, ammo, coins, kill feed
      ShopController.luau     The shop window
      DataController.luau     Your latest coins/colors from the server
```

## How it stays safe and solid

- **The server is the referee.** The client only says "I fired from here, this
  way". The server checks the values are real, that you're alive, that you have
  ammo and aren't firing too fast, and that you're not shooting through a wall.
  Then it does its **own** raycast to decide what you hit. Coins, damage and
  purchases are only ever changed on the server.
- **The shop uses server prices.** The client sends just the color's name, and
  the server looks up the real price and checks your coins.
- **Saving is careful.** Every DataStore request is retried with growing waits.
  A session lock stops two servers overwriting each other. If loading fails,
  the game never saves over your real data. It also autosaves every minute,
  saves when you leave, and saves everyone when a server shuts down.
- **Every file uses `--!strict`** Luau typing, and each one has comments
  explaining what it does.

## Ideas for next steps

- Add sounds (shooting, splat, jump) by uploading audio and playing it in `WeaponController`
- Add more weapons: copy the `Weapon` block in `Config.luau` and add a way to switch
- Build your own map in Studio: make a Folder named `Arena` in Workspace with
  some `SpawnLocation`s, and the auto-built arena will step aside
- Add a round timer and a scoreboard of the top players
