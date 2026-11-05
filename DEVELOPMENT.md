# Slime Showdown: development checklist

Status key: ✅ verified in Studio · 🟡 code exists, **not yet tested in Studio** · 🔲 not started

Nothing is marked ✅ yet: no feature has been play-tested in Studio so far.

## Phase 1: Foundation

| # | Feature | Status | Notes |
|---|---------|--------|-------|
| 1 | Inspect existing project | ✅ done (code inspection) | Findings below |
| 2 | Architecture and folder structure | 🟡 done in code, needs a Studio play-test | One start-up script per side; 94/94 requires checked |
| 3 | Shared configuration | 🟡 done in code | Added GameConfig, CameraConfig, ModeConfig (1v1/2v2/4v4 rules) | One config file per system (Movement, Weapon, Round, Shop, Schema) |
| 4 | Networking conventions | 🟡 done in code | One list of all remotes in `Shared/Net/Net.luau` (rules at the top), reusable `RateLimiter` |
| 5 | Basic slime character | 🟡 done in code | Same fixed body for everyone (`Components/SlimeRig`), soft jelly blob with face, fixed hitbox, shop colours recolour it |

## Later phases (summary)

| Phase | Status |
|-------|--------|
| 2 Movement (walk, sprint, jump, air control, slide, FPS camera) | 🟡 walk/jump/slide/dash/double jump exist; no sprint; no FPS camera |
| 3 Slime animations | 🟡 breathing, stretch, squish, wobble, blink on `wip/slime-visuals` |
| 4 Combat | 🟡 rifle, shotgun, sniper, server-checked; no pistol/SMG, recoil, viewmodel, reserve ammo |
| 5 Core match | 🟡 free-for-all round loop only; no teams or state machine |
| 6 Lobby | 🔲 (main menu with Play button only) |
| 7 Match transitions | 🔲 |
| 8 Polish | 🔲 |
| 9 Additional content | 🟡 **shop merged**: blob colours, hats, weapon skins (saved, server-checked) |
| 10 Final optimization | 🔲 |

## Findings from the inspection (Feature 1)

- **Project:** Rojo 7.7.1. `src/shared` → ReplicatedStorage.Shared, `src/server` → ServerScriptService.Server, `src/client` → StarterPlayerScripts.Client. About 7,400 lines of `--!strict` Luau. All UI is built in code. No StarterGui, ServerStorage, sounds or animation assets yet. The map is built by code at runtime.
- **Not inspectable from here:** anything made directly in Roblox Studio and not saved into this repo. Tell me if you built anything there.
- **Startup order:** each system starts from its own Script, so the order is random. This already caused one bug (kill feed). Fix in Feature 2: one start-up Script per side that starts services in a fixed order.
- **Networking:** four folders made four different ways (`GameRemotes`, `WeaponRemotes`, `MovementRemotes`, shop `ShopRemotes`, plus `RoundState` attributes). Fix in Feature 4: one `Net` module that lists every remote.
- **Character size:** players keep their own avatar's body scale under the blob, so collision size, camera height and the gun position can differ between players. Fix in Feature 5: a fixed StarterCharacter.
- **Infinite waits:** 11 `WaitForChild` calls on the server and 43 on the client have no timeout. They'll be reviewed during the restructure.
- **Deprecated APIs:** none found (`wait`, `spawn`, `delay`, `:connect`).
- **Plan vs. current numbers:** walk 24 (plan: 20), no sprint (plan: 26), JumpPower 55 (plan: 52), slide 0.7 s / 0.8 s cooldown (plan: 0.65 s / 2 s). There's also an extra dash and double jump that aren't in the plan.
- **Branch `rounds`** has a new commit adding its own `default.project.json`. It is **not merged**, because `main` already has the shared project file.
- **When `wip/slime-visuals` is merged:** shop `Cosmetics` colours the blob piece called `Body`. In the new jelly blob, `Body` is the invisible hitbox, so colouring must target the visible pieces.

## Proposed architecture (Feature 2)

```
src/shared   (ReplicatedStorage.Shared)
  Config/     Game, Movement, Camera, Weapons, Modes, Maps, Shop
  Net/        Net.luau: every RemoteEvent/RemoteFunction in one list
  Match/      match states and shared match types
  Util/       springs, cleanup helper, rate limiter
src/server   (ServerScriptService.Server)
  init.server.luau   starts services in a fixed order
  Services/   PlayerData, Combat, Weapon, Movement, Match, Queue, Team, Spawn, Map, Vote, Shop, Rewards
src/client   (StarterPlayerScripts.Client)
  init.client.luau   starts controllers in a fixed order
  Controllers/ Input, Camera, Movement, SlimeAnimation, Weapon, Viewmodel, Effects, Sound, MatchState, UI
  UI/          screens (menu, HUD, scoreboard, shop, voting, results, settings)
assets/maps   map models saved from Studio (.rbxm), loaded into ServerStorage
```
