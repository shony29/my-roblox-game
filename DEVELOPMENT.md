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
| 2 Movement (walk, sprint, jump, air control, slide, FPS camera) | 🟡 in progress: walk 20 ✔, sprint 26 (Shift) ✔, dash moved to Q, jump 52 + coyote time + jump buffer ✔, air control: kept Roblox's full air control (decision, revisit after play-test) ✔, slide 0.65 s / 2 s cooldown ✔, first-person camera + gun view ✔ (all untested in Studio) |
| 3 Slime animations | 🟡 done in code (`Controllers/BlobAnimator`): idle, walk bounce, sprint lean, jump stretch, impact-scaled landing squish, damage ripple + squint, death collapse + particle burst |
| 4 Combat | 🟡 in progress: 18-21 rifle, server-checked shooting, damage, hitmarkers (existing) ✔; 22 reserve ammo ✔; 23 recoil ✔; 24 weapon animations (fire kick, equip raise, reload dip, sprint pose, dry-fire twitch) ✔; 25 switching (1-5, mouse wheel, gamepad Y) ✔; 26 SMG + Pistol ✔ |
| 5 Core match | 🟡 done in code: MatchService state machine (MatchFound → Countdown → InMatch → RoundEnd → MatchResults → Returning), balanced teams, team-side spawns, round timer, sit-out eliminations, fresh round resets, first-to-N victory + forfeits, team scores and per-player elims/deaths/damage. Matches start automatically with 2 players (1v1) until the Phase 6 lobby |
| 6 Lobby | 🟡 done in code: floating lobby island with training dummies (third-person camera), Play panel with 1v1/2v2/4v4, per-mode queues with wait time and cancel (QueueService), match creation, MATCH FOUND pop-up |
| 7 Match transitions | 🟡 done in code: map voting (VoteService + cards; switches on with 2+ maps), loading screen while the server really builds the map (MapService), countdown, round-end, results screen (MVP, stats, coins), automatic return to lobby, rematch when everyone agrees |
| 8 Polish | 🟡 sound framework with volume categories (built-in sounds + marked placeholders), elimination pop-up + sound, team-coloured scoreboard. Weapon/slime animations and UI transitions came with Phases 3, 4 and 7; a further polish pass should follow play-testing |
| 9 Additional content | 🟡 in progress: 56 Mossy Keep map (forest + castle ruins, mirrored for fairness) ✔, map voting now active; 57 2v2/4v4 modes ✔; 58-59 shop colours, hats, weapon skins ✔; 60 XP and levels (saved, server-awarded) ✔. Not yet: eye styles/expressions, trails, challenges, achievements |
| 10 Final optimization | 🟡 partly: automatic Low/Medium/High graphics (64), mobile Fire/Reload/Swap buttons + crosshair aiming (66), security audit (65) and a static performance review below. Profiling (61-62), stress tests (67), bug fixing from play-tests (68) and balancing (69) need Roblox Studio and real play-testing |

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

## Security audit (Feature 65)

Every remote, what a client can send, and what the server checks. All
damage, scores, coins, XP, items, match state and votes are decided on the
server; attributes a client sets on itself never reach the server.

| Remote (Shared/Net/Net.luau) | Direction | Server checks |
|---|---|---|
| WeaponFire | client → server | types, NaN, a round is running and you're alive in it (CombatRules), equipped weapon, fire rate, swap delay, ammo, reload state, origin within 10 studs of your head with no wall between, server's own raycast decides hits, damage from WeaponConfig, no friendly fire |
| WeaponEquip / WeaponReload | client → server | real weapon Id, 0.1 s cooldown, reload needs spare bullets |
| MovementRequest | client → server | known action, 15 requests/s limit, cooldowns, air-jump count; speed/height watched 10×/s with lag allowance, snap-back after 3 strikes |
| PlayPressed | client → server | no data; 1 per second |
| QueueJoin / QueueLeave | client → server | real mode Id, must be in the lobby, 4 per second |
| MapVote | client → server | only the match's players, only offered maps, 4 per second |
| RematchVote | client → server | only the match's players, 2 per second |
| ShopBuyItem / ShopEquipItem | client → server (function) | short real item Id, server price, ownership, coins spent in one step, cooldown |
| KillFeed, WeaponState, WeaponHitConfirm, WeaponShotFx, MovementResult, MatchResults | server → client | clients only display these; text is length-checked and RichText-escaped |

Known limits: aim assistance (aimbots) can't be fully stopped by any
server; the movement checks are deliberately forgiving so laggy players
aren't punished.

## Performance notes (static review, not measured)

Nothing here has been measured yet. Use Studio's MicroProfiler (Ctrl+F6)
and the Developer Console (F9) during a 4–8 player test to confirm.

- Per-frame client work: blob jiggle (only blobs within 160 studs, 64 on
  Low; your own is skipped in first person), the camera and gun view
  (a few CFrame updates), movement (dash/slide/sprint maths) and the dash
  badge. Other HUD loops run 4–10 times a second, not every frame.
- Server: movement checks run 10 times a second (not every frame); matches
  and queues are event-driven with short polling during rounds.
- Network: the busiest messages are shots (at most the weapon's fire rate,
  14/s for the SMG) with one tracer message to other players per shot and an
  ammo update to the shooter. Everything else (scores, timers, queue counts,
  votes) is shared through attributes that change only when something happens.
- Maps: Mossy Keep has roughly 600 anchored parts. Decorations that don't need
  collision have collision and queries switched off.
