# Integration notes (project manager)

> **Historical:** these notes describe the first merge of the five branches.
> The current architecture, checklist, security audit and performance notes
> live in `DEVELOPMENT.md`.

This file tracks how the five branches fit together, the problems found when
reading them, and how each one was fixed during the merge into `main`.

Branches read (latest commit on each):

| Branch     | Commit    | What it adds |
|------------|-----------|--------------|
| `main`     | `3d092f9` | Rojo project, plus a complete older "Jelly Blitz" prototype (its own weapons, movement, HUD, shop, saving) |
| `weapons`  | `9cb3711` | Rifle / shotgun / sniper, server-checked shooting, tracers, hitmarker, weapon slots |
| `movement` | `4d9f54b` | Blob characters, dash, double jump, slide, server movement checks, dash badge |
| `rounds`   | `5b2a14f` | Arena map, round loop, scores, safe spawn points, spawn protection, round HUD |
| `ui-data`  | `7bd6d33` | Main menu, HUD (health/ammo/timer/crosshair), kill feed, Tab scoreboard, DataStore saving |

---

## 1. How the parts connect

```
 Player clicks  ──► WeaponController (client) ──Fire──► WeaponService (server)
                                                         │  checks everything,
                                                         │  does its own raycast,
                                                         │  tags "creator", TakeDamage
                                                         ▼
                                        Humanoid dies ──► RoundService (server)
                                                         │  reads "creator" tag
                                                         ├─► round score (+1, win check)
                                                         └─► PlayerDataService.recordElimination
                                                               ├─► RoundEliminations / RoundDeaths attributes (scoreboard)
                                                               ├─► lifetime eliminations + coins (saved)
                                                               └─► KillFeed remote ──► KillFeed UI (all clients)
                                         then ──► SpawnService respawns at a safe arena spawn pad
                                                    + ForceField spawn protection

 Main menu "Play" ──PlayPressed──► DataBootstrap sets PressedPlay ──► RoundService spawns that player
 RoundService phase/timer ──► GameContract.setRoundTimeRemaining ──► HUD round timer
 WeaponService ammo ──► Ammo / MaxAmmo attributes on the character ──► HUD ammo counter
 Humanoid health ──► HUD health bar (read directly on the client)
 Round winner ──► PlayerDataService.recordWin (saved "Wins")
```

All remotes now live in one folder, `ReplicatedStorage.Remotes`, created from the single list in
`src/shared/Net/Net.luau` (which also documents the networking rules). Round state is shared through
attributes on `ReplicatedStorage.RoundState`.

---

## 2. Problems found, and what was done

| # | Problem | Fix during the merge |
|---|---------|----------------------|
| 1 | None of the feature branches started from `main` (separate histories) and none had `default.project.json`. | Merged with `--allow-unrelated-histories`; `main` keeps the one project file. |
| 2 | `main` already contained a whole older game (CombatService, CharacterService, PlayerData, ShopService, old HUD, old Remotes). Running it next to the new systems would mean two gun systems, two respawn systems and two save files. | Removed the old prototype code. It is still in git history (commit `3d092f9`) if you want the colour shop back later. |
| 3 | Two kill feeds (rounds and ui-data), two round timers, two leaderboards. | ui-data owns the kill feed, timer and scoreboard. The rounds HUD now shows only the round caption, "GO!" / winner banner and spawn-protection notice. |
| 4 | Two elimination remotes: rounds `RoundState.Eliminated` and ui-data `GameRemotes.KillFeed`. | Only `KillFeed` is used, fired from `PlayerDataService.recordElimination`. |
| 5 | Nothing called `PlayerDataService.recordElimination / recordWin / resetRoundStats`, so coins and the scoreboard never changed. | RoundService now calls all three. |
| 6 | Round timer: rounds wrote `RoundState.EndsAt`, the HUD reads `ReplicatedStorage.RoundEndsAt`. | RoundService also calls `GameContract.setRoundTimeRemaining`. |
| 7 | Players spawned (and could be shot) while still sitting in the main menu. | RoundService spawns a player only after they press Play. |
| 8 | Characters could auto-load before RoundService turned auto-loading off. | `Players.CharacterAutoLoads = false` is set in `default.project.json`. |
| 9 | Blob bodies did not take hits: the visible blob had `CanQuery = false` and the invisible Roblox body (including a head floating above the blob) took the bullets. | New `Shared/Combat/HitGroups`: hidden body parts go in a collision group that weapon raycasts ignore, and the blob body is now the hitbox (top of the blob counts as a headshot). |
| 10 | Shots were rejected while dashing: allowed muzzle offset (6 studs) is smaller than a dash covers in 100 ms of lag. | `MaxOriginOffset` raised to 10. |
| 11 | `Equip` and `Reload` remotes had no spam limit (each Equip rebuilds the gun model). | Server-side cooldown added. |
| 12 | HUD overlap: dash badge, weapon slots and "Reloading" text all sat in the same bottom spots as the ui-data ammo box. | Moved the dash badge and reload text up. |
| 13 | Two game titles ("Jelly Blitz" on main, "SHELL PARTY" placeholder on ui-data). | Menu title is now "JELLY BLITZ". |
| 14 | Different config styles (one `Config.luau`, `MovementConfig`, `WeaponConfig`, `RoundConfig`, `PlayerDataSchema`). | Kept one config file per system, each in its own `Shared/<System>` folder. This table is the map. |
| 15 | PlayerDataService only fetched the KillFeed remote inside `start()`. Separate Scripts run in any order, so an early elimination could miss the kill feed. | It now fetches the remote on first use. |
| 16 | Coins were only shown on the main menu, which is hidden during play. | Added a small coin counter to the HUD (top left). |
| 17 | `getPhase()` in the rounds HUD returned an `unknown` value as a `Phase`, which `--!strict` rejects. | Returns the exact phase words instead. |

## 3. Safety rules check (server is in charge)

| Area | Status |
|------|--------|
| Damage | Server only. Client sends weapon id + origin + direction. Server checks types, NaN, alive, equipped weapon, fire rate, swap delay, ammo, origin near head, no wall between head and origin, then raycasts itself. Damage comes from `WeaponConfig`. |
| Scores | Server only (RoundService). Killer comes from the server-made `creator` tag. Clients cannot add instances the server sees. |
| Coins / saves | Server only (PlayerDataService). Session locking, retries, autosave, BindToClose, never saves over data that failed to load. |
| Movement | Client moves itself (Roblox rule), server checks speed/height and snaps cheaters back; action requests are rate-limited and validated. |
| Play button | Sends no data; rate-limited. |
| Kill feed text | Client escapes RichText, so player names can't inject formatting. |

## 4. Still to test in Studio

These could not be run here (no Roblox Studio in the cloud, and the type
checker could not be downloaded), so they were checked by reading the code:

- A full 2–3 player "Start" test (see README, Step 6 checklist).
- Run luau-lsp / Studio's Script Analysis once to confirm there are no `--!strict` warnings.
- Blob hitbox and headshots feel right (tune `BLOB_HEADSHOT_FRACTION` in `Shared/Combat/HitGroups`).

## 5. Rojo layout (`default.project.json`)

```
src/shared  → ReplicatedStorage.Shared          (Data, Combat, Movement, Rounds, Weapons)
src/server  → ServerScriptService.Server        (Data, Map, Movement, Rounds, Weapons)
src/client  → StarterPlayer.StarterPlayerScripts.Client  (Movement, Rounds, UI, Weapons)
Players.CharacterAutoLoads = false
```

`Server` and `Client` are plain folders. Each system starts itself with its
own `init.server.luau` / `init.client.luau` (or `*.server.luau` /
`*.client.luau`) file, so there is no single start file to keep in sync.
