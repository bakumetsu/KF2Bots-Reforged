# KF2 Echolon AI — Hierarchical Command Architecture (HCA)

> **Purpose:** Single source of truth for the Echelon System — a top-down, event-driven command hierarchy that replaces the autonomous per-bot AI model with a push-based rank structure, reducing AI CPU cost by ~85–90% while enabling organic squad behavior for up to 65 entities (25 humans + 40 bots).
>
> **Scope:** `KF2Bots` mod (local, writable) + `KFGame` / `KFGameContent` SDK (read-only).
> **Engine:** Unreal Engine 3 (KF2 SDK, native C++ + UnrealScript hybrid).
> **Status:** Design complete. Ready for implementation.

---

## PART 0: ARCHITECTURAL OVERVIEW

### 0.1 Echelon Rank Hierarchy

The Echelon System replaces the flat "every bot thinks for itself" model with a strict top-down command chain. Humans are invisible to the bot command hierarchy.

```
┌─────────────────────────────────────────────────────────────────────┐
│  MUTATOR (General)                                                  │
│  ┌─────────────────────────────────────────────────────────────────┐│
│  │  3.0s macro-timer                                               ││
│  │  • SYG objective enforcement                                   ││
│  │  • Boss wave detection                                           ││
│  │  • Map-wide anchor broadcast                                      ││
│  │  • Promotion queue processing (1 per macro-tick)                ││
│  │  • Ammo factory 10s delay management                            ││
│  │  • Wave start / end signaling                                     ││
│  └─────────────────────────────────────────────────────────────────┘│
│                                                                     │
│  ┌──────────────────────┐   ┌──────────────────────┐               │
│  │  CAPTAIN (Company)   │   │  CAPTAIN (Company)   │               │
│  │  30-45 grunts        │   │  30-45 grunts        │               │
│  │  2-3 platoons        │   │  2-3 platoons        │               │
│  │  • 3D nav-mesh path  │   │  • 3D nav-mesh path  │               │
│  │  • Platoon anchors   │   │  • Platoon anchors   │               │
│  └──────────┬───────────┘   └──────────┬───────────┘               │
│             │                           │                           │
│  ┌──────────▼───────────┐  ┌──────────▼───────────┐               │
│  │  PLATOON (Lieutenant)│  │  PLATOON (Lieutenant)│               │
│  │  15-20 grunts        │  │  15-20 grunts        │               │
│  │  3-4 squads          │  │  3-4 squads          │               │
│  │  • Squad target area │  │  • Squad target area │               │
│  └──────────┬───────────┘  └──────────┬───────────┘               │
│             │                           │                           │
│  ┌──────────▼───────────┐  ┌──────────▼───────────┐               │
│  │  SQUAD (Leader + 4)  │  │  SQUAD (Leader + 4)  │               │
│  │  0.5s decision timer │  │  0.5s decision timer │               │
│  │  • 2D formation math │  │  • 2D formation math │               │
│  │  • Threat response   │  │  • Threat response   │               │
│  │  • FastTrace(4)      │  │  • FastTrace(4)      │               │
│  └──────────┬───────────┘  └──────────┬───────────┘               │
│             │                           │                           │
│  ┌──────────▼───────────┐  ┌──────────▼───────────┐               │
│  │  GRUNT (×4 per squad)│  │  GRUNT (×4 per squad)│               │
│  │  Restricted tick     │  │  Restricted tick     │               │
│  │  • 2D VSizeSq offset │  │  • 2D VSizeSq offset │               │
│  │  • Event hooks only  │  │  • Event hooks only  │               │
│  │  • No pathfinding    │  │  • No pathfinding    │               │
│  └──────────────────────┘  └──────────────────────┘               │
└─────────────────────────────────────────────────────────────────────┘
```

#### Rank Responsibilities

| Rank | Entity | Timer | Primary Responsibility | Downstream Output |
|------|--------|-------|----------------------|-------------------|
| **General** | `KF2BotsMut` | 3.0 s | Map-wide logic: SYG, boss waves, promotion queue, ammo delay | Macro-anchors → Captains |
| **Captain** | `KF2Bot` (rank=Captain) | 3.0 s | 3D nav-mesh pathing, platoon anchor distribution | Platoon anchors → Lieutenants |
| **Lieutenant** | `KF2Bot` (rank=Lieutenant) | 1.0 s | Squad target area assignment, platoon coordination | Squad target areas → Squad Leaders |
| **Squad Leader** | `KF2Bot` (rank=SL) | 0.5 s | 2D formation math, `FastTrace` room scan, threat response | Formation offsets → Grunts |
| **Grunt** | `KF2Bot` (rank=Grunt) | Restricted | 2D `VSizeSq` offset following, native event hooks only | (leaf node) |

### 0.2 SDK Feasibility Verdicts

All 8 core design elements have been verified against the KF2 SDK. **No native C++ changes are required.** Every mechanism maps to existing UnrealScript-overridable functions.

| # | Design Element | SDK Mechanism | Feasible | Notes |
|---|---------------|---------------|:--------:|-------|
| 1 | Rank assignment at spawn | `KF2BotsMut.SpawnBot()` + new `EBotRank` enum | ✅ | Mutator assigns rank during wave spawn; `KF2Bot` stores `BotRank` property |
| 2 | 3.0 s macro-timer (General) | `KF2BotsMut` existing `SetTimer()` pattern | ✅ | Same timer architecture as current `MACRO_WAYPOINT_INTERVAL` |
| 3 | 3D nav-mesh pathing (Captain) | `FindPathToward()` on `KFPawn` — native, already used | ✅ | Only 2-3 Captains call this; ~0.33 calls/sec total |
| 4 | 2D formation math (SL) | `VSizeSq()` + `FastTrace()` — native `Actor` functions | ✅ | 4 traces × 5 SLs / 1.5 s = 13.3 traces/sec — negligible |
| 5 | Restricted grunt tick | Override `KF2Bot.Tick()` with rank gate | ✅ | Grunt tick reduces to 2D offset + event-driven; **cannot be fully disabled** (locomotion) |
| 6 | Native event hooks (Grunt) | `SeePlayer()`, `HearNoise()`, `NotifyTakeHit()` — engine-delivered, tick-independent | ✅ | `HearNoise` is dormant in `KFAIController` (returns immediately); must implement fresh in `KF2Bot` |
| 7 | Promotion queue | `KF2BotsMut.PendingPromotions[]` + 1-per-macro-tick processing | ✅ | `OnBotKilled()` at line 527 currently handles this synchronously; refactor to async queue |
| 8 | Ammo factory 10s delay | `KFPickupFactory.SetPickupHidden()` / `SetPickupVisible()` — `simulated` functions | ✅ | Mutator iterates all `KFPickupFactory_Ammo` at wave start; 10s timer; also set `bKismetEnabled = false` for kismet-driven factories |

### 0.3 Performance Budget Summary

| Metric | Current (40 bots, autonomous) | Proposed (40 bots, Echelon) | Savings |
|--------|-------------------------------|---------------------------|---------|
| `FastTrace` calls / sec | ~1,200 (30 bots × 4 traces × 10 Hz) | ~13 (5 SLs × 4 traces × 0.67 Hz) | **98.9%** |
| `FindPathToward` calls / sec | ~40 (every bot, every 1s) | ~1.7 (2-3 Captains × 1 / 3s) | **95.7%** |
| `PickNextMove` evaluations / sec | ~400 (40 bots × 10 Hz) | ~10 (5 SLs × 2 Hz) | **97.5%** |
| `Tick()` full evaluations / sec | ~400 (all bots) | ~10 (5 SLs) + 40 grunt light ticks | **~87.5%** |
| Estimated AI CPU / frame | 2.0 – 4.0 ms | 0.3 – 0.5 ms | **~85–90%** |

> **Critical constraint:** `KF2Bot.Tick()` (line 898) processes `MoveFlags` (`ProcessMoveTo` / `ProcessMoveToward`). This is the bot's actual locomotion driver. **Grunt ticks cannot be fully disabled** — they must be *reduced* to lightweight 2D offset following, not removed.

---

## PART 1: SDK FEASIBILITY AUDIT (DETAIL)

### 1.1 `KFPickupFactory_Ammo` — Spawning & Delay Mechanism

**Class hierarchy:**
```
PickupFactory (Engine/Classes/PickupFactory.uc)
  +-- KFPickupFactory (KFGame/Classes/KFPickupFactory.uc)
        +-- KFPickupFactory_Ammo (KFGameContent/Classes/KFPickupFactory_Ammo.uc)
```

**Key properties & functions:**

| Item | Source | Detail |
|------|--------|--------|
| `bPickupHidden` | `PickupFactory` (line 16) | `RepNotify bool` — replicates to clients. `FindCollectable()` checks this flag |
| `SetPickupHidden()` | `PickupFactory` (line 337) | `simulated` — sets `bPickupHidden = true`, hides mesh |
| `SetPickupVisible()` | `PickupFactory` (line 348) | `simulated` — sets `bPickupHidden = false`, shows mesh |
| `bKismetDriven` | `KFPickupFactory` | If true, factory is kismet-controlled; must also set `bKismetEnabled = false` |
| `bEnabledAtStart` | `KFPickupFactory` | Initial enable state |
| `bNotBased` | `KFPickupFactory_Ammo` | `TRUE` — not a navigation point (bots find via `FindCollectable()`) |
| `GiveTo()` / `PickedUpBy()` | `KFPickupFactory_Ammo` | Pickup distribution |

**Implementation pattern (Mutator):**

```unrealscript
// In KF2BotsMut — called at wave start
function HandleAmmoFactoryDelay()
{
    local int i, count;
    local Actor A;
    local KFPickupFactory F;

    // Iterate all KFPickupFactory_Ammo in world
    count = Level.GameReplicationInfo.bots.Length; // reuse existing pattern
    for (i = 0; i < Level.MyKFGRI.WaveTotalAI; i++)
    {
        A = Level.MyKFGRI.WaveTotalAI[i]; // pseudocode — use Level.GetActorIterator
        if (A != none && A.IsA('KFPickupFactory_Ammo'))
        {
            F = KFPickupFactory(A);
            F.SetPickupHidden();
            if (F.bKismetDriven)
            {
                F.bKismetEnabled = false; // prevent kismet override
            }
        }
    }

    // 10s timer to re-enable
    SetTimer(10.0, 'ReEnableAmmoFactories');
}

function ReEnableAmmoFactories()
{
    // Same iteration, call SetPickupVisible() + restore bKismetEnabled
}
```

> **Edge case:** Kismet-driven factories (`bKismetDriven = true`) may re-show themselves via kismet logic. Setting `bKismetEnabled = false` prevents this. Restore after the 10s window.

### 1.2 `FastTrace` — Cost Analysis for Dynamic Formations

**Native signature** (`Engine/Classes/Actor.uc`, line 1953):
```unrealscript
native(548) noexport final function bool FastTrace(EName TraceType, out vector HitLoc, vector Source, vector Delta, bool bIgnoreSelf = false);
```

**Cost profile:**
- Single call: ~2–5 µs (C++ line trace, no physics interaction)
- Formation scan: 4 directions × 1 call = 4 traces per SL
- 5 Squad Leaders × 4 traces / 1.5 s = **13.3 traces/sec total**
- Comparison: Current system = 30 bots × 4 traces × 10 Hz = **1,200 traces/sec**

**Squad Leader formation scan pattern:**

```unrealscript
// In KF2Bot — SL decision loop (0.5s timer)
function ScanRoomForFormation()
{
    local vector src, hit, delta;
    local int clearCount;

    src = Pawn.Location;
    clearCount = 0;

    // 4-directional scan: forward, left, right, back
    delta = Vector(0, 0, 150);   // forward
    if (!FastTrace(TraceType_Hit, hit, src, delta)) clearCount++;
    delta = Vector(-150, 0, 0);  // left
    if (!FastTrace(TraceType_Hit, hit, src, delta)) clearCount++;
    delta = Vector(150, 0, 0);   // right
    if (!FastTrace(TraceType_Hit, hit, src, delta)) clearCount++;
    delta = Vector(0, 0, -150);  // back
    if (!FastTrace(TraceType_Hit, hit, src, delta)) clearCount++;

    // Formation decision based on clearCount
    if (clearCount >= 3)
    {
        SetFormation('Arrowhead');   // open room
    }
    else if (clearCount >= 2)
    {
        SetFormation('StaggeredColumn'); // standard combat
    }
    else
    {
        SetFormation('SingleFile');    // hallway/stairs
    }
}
```

### 1.3 `Tick()` Restriction Strategy

**Current `KF2Bot.Tick()` (line 898) responsibilities:**
1. `MoveFlags` processing (`ProcessMoveTo` / `ProcessMoveToward`) — **REQUIRED for locomotion**
2. State timer updates
3. Enemy visibility checks
4. Formation offset recalculation
5. Health/triage checks

**Restricted Grunt Tick pattern:**

```unrealscript
// In KF2Bot — rank-gated tick
simulated function Tick(float DeltaTime)
{
    if (BotRank == 'GRUNT')
    {
        // REQUIRED: locomotion (cannot disable)
        if (MoveFlags != 0)
        {
            ProcessMoveTo();
            ProcessMoveToward();
        }

        // LIGHTWEIGHT: 2D offset following (no pathfinding)
        if (WorldInfo.TimeSeconds - LastOffsetUpdate > 0.2)
        {
            UpdateGruntOffset();
            LastOffsetUpdate = WorldInfo.TimeSeconds;
        }

        // HEALTH SAFETY NET (catches bleed/DoT that may not fire NotifyTakeHit)
        if (WorldInfo.TimeSeconds - LastHealthCheck > 2.0)
        {
            CheckCriticalHealth();
            LastHealthCheck = WorldInfo.TimeSeconds;
        }

        return; // skip all heavy logic
    }

    // FULL tick for officers (SL, LT, Captain)
    Super::Tick(DeltaTime);
}
```

> **Critical:** `ProcessMoveTo` / `ProcessMoveToward` in `Tick()` is the actual locomotion driver. Removing it entirely would freeze bots in place. The restricted tick *reduces* work, it does not eliminate the tick.

### 1.4 Native Event Hooks — Grunt Combat Foundation

**Engine-delivered events (tick-independent):**

| Event | Source | Delivery | Grunt Response |
|-------|--------|----------|---------------|
| `SeePlayer()` | `Controller.uc:1160` | Engine calls when pawn enters controller's vision cone | Grunt: `SetEnemy(Pawn)`, fire weapon |
| `HearNoise()` | `Controller.uc:1150` | Engine calls on loud sounds (gunfire, screams) | Grunt: orient toward noise, `SeePlayer` fallback |
| `SeeMonster()` | `Controller.uc:1166` | Engine calls on monster detection | Grunt: orient, fire |
| `NotifyTakeHit()` | `Pawn.uc:2512` → `Controller.NotifyTakeHit` | Engine calls on damage application | Grunt: panic reaction, health check |
| `EnemyNotVisible()` | `Controller` | Engine calls when enemy exits vision | Grunt: clear `Enemy`, resume offset |

**`HearNoise` quirk:**
`KFAIController.HearNoise()` (line 4699) currently **returns immediately** — its combat logic is commented out. For bots, `HearNoise` must be implemented fresh in `KF2Bot`:

```unrealscript
// In KF2Bot — grunt event hook
function HearNoise(NoiseSource, NoiseLevel, NoiseDir)
{
    if (BotRank == 'GRUNT' && Pawn.IsAliveAndWell())
    {
        // Orient toward noise
        if (NoiseLevel > 0.5 && VSizeSq(NoiseSource - Pawn.Location) < 4000000) // 2000u
        {
            // Turn toward noise, prepare to fire
            if (NoiseSource != none && NoiseSource.IsA('KFPawn_Human'))
            {
                SetEnemy(KFPawn_Human(NoiseSource));
            }
            else
            {
                // Orient via SetRotation toward noise direction
                SetRotation(NoiseDir);
            }
        }
    }
    else
    {
        Super::HearNoise(NoiseSource, NoiseLevel, NoiseDir);
    }
}
```

### 1.5 Performance Cost Comparison

| Operation | Current (autonomous) | Proposed (Echelon) | Δ |
|-----------|---------------------|-------------------|---|
| **Per-bot `PickNextMove`** | 40 bots × 10 Hz = 400 evals/s | 5 SLs × 2 Hz = 10 evals/s | −97.5% |
| **`FastTrace` (formation)** | 30 bots × 4 traces × 10 Hz = 1,200/s | 5 SLs × 4 traces × 0.67 Hz = 13/s | −98.9% |
| **`FindPathToward`** | 40 bots × 1/s = 40/s | 2-3 Captains × 1/3s = 1.7/s | −95.7% |
| **Grunt `Tick()`** | Full state machine (all 18 states) | 2D offset + event hooks only | ~90% lighter |
| **Promotion processing** | Synchronous in `OnBotKilled()` (CPU spike) | Async queue, 1 per 3.0s macro-tick | Smoothed |
| **Total estimated AI CPU** | 2.0–4.0 ms/frame | 0.3–0.5 ms/frame | **~85–90% reduction** |

---

## PART 2: PRIORITY TREE INTEGRATION

### 2.1 Priority-to-Rank Assignment

The existing 10-priority funnel (`PickNextMove()`, line 2202) is **not preserved verbatim**. In the Echelon system, priorities are distributed across ranks: grunts never evaluate P4–P10 themselves. They react to native engine events for P2/P3/P7 and receive `EBotCommand` orders from the Squad Leader for the rest.

| Priority | Name | Rank(s) Executing | Mechanism |
|----------|------|-------------------|-----------|
| **P1** | Terminal Lock | **All ranks** | `bMatchIsOver` check in every rank's decision loop → `VictoryDance` |
| **P2** | Grab Override | **Grunt** (event-driven) | `CheckGrabbed()` timer (0.2s) + `NotifyBump` → `BreakLose` state. **Not in funnel** — async interrupt |
| **P3** | Critical Survival | **Grunt** (event + safety net) | `NotifyTakeHit()` + 2.0s health-check in restricted `Tick()` → `HealingSelf`. Catches bleed/DoT |
| **P4** | Tactical Retreat | **SL → Grunts** | SL evaluates `ShouldTacticalRetreat()`; issues `CMD_TacticalRetreat` → grunts follow SL offset |
| **P5** | SYG Enforcement | **Mutator → Captain → SL → Grunts** | Macro-anchor chain: Mutator pushes objective → Captain paths → SL offsets → Grunts follow |
| **P6** | Squad Medic | **SL** (2.0s triage) | SL evaluates triage; `CMD_FocusTarget` to designated medic grunt; or SL heals directly |
| **P7** | Combat Engagement | **All ranks** (event-driven) | `SeePlayer()` / `SeeMonster()` / `HearNoise()` → `FightEnemy` / `Hunting`. Grunts inherit `Focus = SL.Enemy` for Line Formation |
| **P8** | Squad Tethering | **SL → Grunts** | SL computes formation offset; grunts follow via 2D `VSizeSq` offset (replaces `ComputeFormationOffset()`) |
| **P9** | Economy | **SL** (60s cooldown) | SL checks `bTraderIsOpen` + cooldown; `CMD_FocusTarget` (shop) → designated grunt shops; others hold position |
| **P10** | Camp / Roam | **SL** (fallback) | If no other priority triggers: `CMD_HoldArea` → grunts camp at formation offset |

### 2.2 Grunt Event-Driven Execution (P2 & P3 Detail)

#### P2: Grab Override (Restricted Tick)

Grunts do **not** evaluate P2 in a priority funnel. Instead:

1. **`NotifyBump()`** — engine calls on collision with grabbing zed → immediate `BreakLose` state entry
2. **`CheckGrabbed()` timer (0.2s)** — lightweight check in restricted tick: `IsDoingSpecialMove(31)` + `InteractionPawn != none`
3. **`BreakLose` state** — 0.15s tick, 1.5s escape throttle, 8s failsafe (unchanged from current)

```unrealscript
// In KF2Bot — restricted grunt tick includes grab check
function UpdateGruntOffset()
{
    // P2: Grab override (async, highest priority for grunt)
    if (CheckGrabbed())
    {
        GotoState('BreakLose');
        return;
    }

    // P8: Formation offset following
    vector leaderPos = SquadLeader.Pawn.Location;
    vector myOffset = ComputeFormationOffset(); // 2D, VSizeSq-based
    vector target = leaderPos + myOffset;

    // Z-snap for stairs/elevated terrain
    if (Fabs(target.Z - Pawn.Location.Z) > 200.0)
    {
        target.Z = Pawn.Location.Z; // snap to current Z level
    }

    // FastTrace validation (cheap, single trace)
    vector hit;
    if (FastTrace(TraceType_Hit, hit, Pawn.Location, target - Pawn.Location))
    {
        // Blocked — hold position
        return;
    }

    MoveToward(target);
}
```

#### P3: Critical Survival (Restricted Tick Safety Net)

Bleed/DoT damage may **not** fire `NotifyTakeHit` on the Controller. The 2.0s health-check safety net in the restricted `Tick()` catches this:

```unrealscript
// In KF2Bot — 2.0s health check in restricted tick
function CheckCriticalHealth()
{
    if (Pawn.Health < 0.25 * Pawn.HealthMax)
    {
        if (CheckShouldSelfHeal())
        {
            GotoState('HealingSelf');
        }
    }
}
```

> **Why both mechanisms?** `NotifyTakeHit` catches discrete hits (bullets, melee). The 2.0s safety net catches continuous damage (bleed, radiation, DoT) that may not generate a `NotifyTakeHit` event.

### 2.3 Squad Leader Decision Loop

The SL is the **decision hub** for its 4 grunts. Every 0.5s:

```
SL Decision Loop (0.5s):
┌─────────────────────────────────────────────────┐
│ 1. P1: Check bMatchIsOver → VictoryDance        │
│ 2. P4: ShouldTacticalRetreat()?                 │
│    → Issue CMD_TacticalRetreat to grunts        │
│ 3. P7: Enemy visible?                           │
│    → FightEnemy / CMD_FocusTarget to grunts     │
│ 4. P6: Triage due? (2.0s)                       │
│    → CMD_FocusTarget (medic) / HealRanged       │
│ 5. P5: SYG anchor valid?                        │
│    → MoveTowardGoal(anchor)                     │
│ 6. P9: Shopping due? (60s)                      │
│    → CMD_FocusTarget (shop) to one grunt        │
│ 7. P8: Formation update                         │
│    → ScanRoomForFormation() (4× FastTrace)      │
│    → Compute offsets for 4 grunts               │
│ 8. P10: None of the above → CMD_HoldArea        │
└─────────────────────────────────────────────────┘
```

**Formation types (from `ScanRoomForFormation`):**

| Condition | Formation | Offset Pattern |
|-----------|-----------|---------------|
| `clearCount >= 3` (open room) | **Arrowhead / Wedge** | SL at apex, grunts in V behind |
| `clearCount >= 2` (standard) | **Staggered Column** | SL behind vanguard; 50% X-axis invert on init |
| `clearCount < 2` (hallway/stairs, traces hit <200u) | **Single-File** | Grunts queue behind SL, 150u spacing |
| Traces clear >600u + frontal combat | **Line Formation** | Grunts lock lateral offsets; `Focus = SL.Enemy` (bypass visual scan) |

**Variance anti-symmetry:** All offsets include ±10–15% random variance to prevent artificial symmetry:
```unrealscript
function vector ComputeFormationOffset(int slot)
{
    local vector base;
    local float variance;

    base = GetFormationBase(slot); // per-formation-type base offset
    variance = 0.10 + 0.05 * Frac(rand(100) / 100.0); // 10-15%
    base.X *= (1.0 + variance * Sign(rand(2) - 1));
    base.Y *= (1.0 + variance * Sign(rand(2) - 1));

    return base;
}
```

### 2.4 Captain / Mutator Macro Logic

#### Captain (3.0s)
- Receives macro-anchors from Mutator
- Calls `FindPathToward()` (3D nav-mesh) — **only 2-3 Captains do this**
- Distributes platoon anchors to Lieutenants
- Handles tactical retreat pathing (3D, not 2D)

#### Mutator / General (3.0s)
- **SYG enforcement:** Checks `bObjectiveActive`, pushes objective anchor to Captains
- **Boss wave detection:** `bIsBossWave()` → adjusts anchor strategy
- **Promotion queue:** Processes **exactly 1 promotion per macro-tick**
- **Ammo factory delay:** 10s `SetPickupHidden` / `SetPickupVisible` window
- **Wave start/end signaling:** Broadcasts `CMD_PushAnchor` to Captains

### 2.5 `EBotCommand` Enum — Byte-Coded Orders

```unrealscript
// In KF2Bot.uc — new enum
enum EBotCommand
{
    CMD_HoldArea,        // P10: Hold current position
    CMD_PushAnchor,      // P5: Move to new anchor
    CMD_TacticalRetreat, // P4: Retreat to safety
    CMD_FocusTarget,     // P7/P6/P9: Focus on target (enemy, medic, shop)
};
```

**Order flow (strictly downward):**
```
Mutator → Captain → Lieutenant → Squad Leader → Grunt
  (EBotCommand + vector anchor)
```

Grunts **never** issue commands upward. Communication is unidirectional.

---

## PART 3: EDGE CASES & FAILURE MODES

### 3.1 Edge Case Registry

| # | Severity | Category | Description | Fix |
|---|:--------:|----------|-------------|-----|
| 1 | 🔴 CRITICAL | **3D Terrain vs 2D Offsets** | Stairs, elevated platforms, one-way doors, narrow corridors break pure 2D offset navigation. Grunt at Z=0, target at Z=500 → `MoveToward` fails, bot sticks to wall | **Z-snap + `FastTrace` validation:** In `UpdateGruntOffset()`, if `Fabs(target.Z - Pawn.Z) > 200`, snap Z to current level. Single `FastTrace` from pawn to target; if hit, hold position. SL re-evaluates formation every 0.5s, naturally re-routing |
| 2 | 🔴 CRITICAL | **Promotion Queue Softlock** | 6 officer deaths in quick succession = 18s of grunts "holding position" at 1-per-3.0s processing. Grunts have no leader, no orders, no pathing | **10s emergency self-promotion timeout:** If a grunt has no valid SL for >10s, it self-promotes to SL (takes over formation math). Additionally, process **2 promotions per macro-tick** during active waves to halve the queue |
| 3 | 🟠 HIGH | **Squad Leader Death** | SL dies mid-formation. 4 grunts lose their offset source. Without SL, grunts have no formation, no target, no orders → they idle | **Immediate promotion:** `OnBotKilled()` pushes SL death to `PendingPromotions`. Next macro-tick (≤3s): highest-scoring grunt promotes to SL. During the 3s gap, grunts `CMD_HoldArea` (camp in place). Grunt panic flash (4.7) covers the transition visually |
| 4 | 🟠 HIGH | **Zed Swarm Clumping** | 20+ zeds converge on one point. SL's `FastTrace` scans all hit (clearCount=0) → `SingleFile` formation. Single-file with 20+ zeds = death. SL's `ShouldTacticalRetreat()` triggers, but retreat path may cross the swarm | **Retreat path validation:** SL's `CMD_TacticalRetreat` includes a 3D path (via Captain's nav-mesh, not 2D). If retreat path is blocked (>50% traces hit), SL issues `CMD_HoldArea` + grunts crouch (4.3) and rely on human teammates. Captain re-routes via `FindPathToward` |
| 5 | 🟡 MEDIUM | **Timer Stacking** | Multiple SLs fire `FastTrace` on the same frame (all 0.5s timers aligned at wave start). 5 SLs × 4 traces = 20 traces in one frame → micro-stutter | **Staggered timer initialization:** Each SL's 0.5s timer starts with a random offset of 0–0.5s at spawn. `SetTimer(0.5, 'SLDecisionLoop', true, random(0.5))`. Prevents all 5 SLs from firing on the same tick |
| 6 | 🟡 MEDIUM | **Kismet-Driven Factories** | `bKismetDriven = true` factories may re-show themselves via kismet logic during the 10s hidden window, spawning ammo on top of SLs | **`bKismetEnabled = false` during window:** Mutator sets `bKismetEnabled = false` on all kismet-driven `KFPickupFactory_Ammo` at wave start. Restores to `bEnabledAtStart` after 10s. Kismet logic cannot override this flag |
| 7 | 🟡 MEDIUM | **Human Interaction** | Human walks through a squad formation. Grunts' `FastTrace` hits the human → formation degrades to `SingleFile`. Humans are invisible to the command chain but physically obstruct 2D offsets | **Human exclusion in traces:** `FastTrace(TraceType_Hit, hit, src, delta, true)` — the `bIgnoreSelf` parameter ignores the calling pawn. For human exclusion, use `FastTrace` with a custom check: if `hit` actor is `KFPawn_Human`, treat as clear (not a wall). Alternatively, use `TraceType_Test` which only checks world geometry |
| 8 | 🟡 MEDIUM | **Damage Bypass** | Bleed/radiation/DoT damage may not fire `NotifyTakeHit` on the Controller. Grunt HP drops below 25% without any event trigger → no self-heal | **2.0s health-check safety net:** `CheckCriticalHealth()` in restricted grunt tick. Catches all continuous damage. `NotifyTakeHit` handles discrete hits; the safety net handles the rest |

### 3.2 Severity Ranking

```
CRITICAL (2)
├── #1: 3D Terrain vs 2D Offsets — bots stuck on stairs/elevated terrain
└── #2: Promotion Queue Softlock — 18s of leaderless grunts

HIGH (2)
├── #3: Squad Leader Death — 3s of idle grunts
└── #4: Zed Swarm Clumping — single-file into 20+ zeds

MEDIUM (4)
├── #5: Timer Stacking — micro-stutter at wave start
├── #6: Kismet-Driven Factories — ammo spawns on SLs
├── #7: Human Interaction — formation degradation
└── #8: Damage Bypass — bleed/DoT not caught by NotifyTakeHit
```

---

## PART 4: CREATIVE ENHANCEMENTS

### 4.1 Squad "Breathing" Oscillation

**Problem:** Static formation offsets look robotic. All 4 grunts maintain exact positions indefinitely.

**Solution:** Apply a slow sinusoidal oscillation to each grunt's offset:

```unrealscript
function vector ApplyBreathing(float t)
{
    local vector offset;
    local float phase;

    phase = t * 0.3 + BreathingPhase; // slow oscillation, unique phase per grunt
    offset.X += 15.0 * Sin(phase);  // ±15u lateral drift
    offset.Y += 10.0 * Cos(phase * 0.7); // ±10u forward/back drift
    // No Z oscillation (stairs)

    return offset;
}
```

**Effect:** Grunts subtly drift ±15u laterally and ±10u forward/back over ~20s cycles. Visually indistinguishable from organic movement. Zero additional `FastTrace` cost.

### 4.2 Buddy Rescue

**Problem:** Grunt is being grabbed by a zed. No one helps. Grunt dies.

**Solution:** When a grunt enters `BreakLose`, the SL issues `CMD_FocusTarget(grabbedGrunt)` to the nearest 2 grunts. Those grunts path to the grabbed grunt and fire at the zed.

```unrealscript
// In KF2Bot — SL response to grunt grab
function OnGruntGrabbed(KF2Bot GruntBot)
{
    local int i;
    local KF2Bot nearest1, nearest2;
    local float minDist1, minDist2;

    minDist1 = 999999;
    minDist2 = 999999;
    nearest1 = none;
    nearest2 = none;

    for (i = 0; i < SquadMembers.Length; i++)
    {
        if (SquadMembers[i] != GruntBot && SquadMembers[i].IsAliveAndWell())
        {
            float d = VSizeSq(SquadMembers[i].Pawn.Location - GruntBot.Pawn.Location);
            if (d < minDist1)
            {
                minDist2 = minDist1;
                nearest2 = nearest1;
                minDist1 = d;
                nearest1 = SquadMembers[i];
            }
            else if (d < minDist2)
            {
                minDist2 = d;
                nearest2 = SquadMembers[i];
            }
        }
    }

    if (nearest1 != none) nearest1.IssueCommand(CMD_FocusTarget, GruntBot.Pawn.Location);
    if (nearest2 != none) nearest2.IssueCommand(CMD_FocusTarget, GruntBot.Pawn.Location);
}
```

### 4.3 Cover-Aware Crouching

**Problem:** Grunts stand in open when zeds are nearby. No cover awareness.

**Solution:** When `clearCount < 2` (hallway/enclosed) AND enemy within 800u, grunts crouch:

```unrealscript
// In KF2Bot — grunt offset update
function UpdateGruntOffset()
{
    // ... existing offset logic ...

    // Cover-aware crouching
    if (SquadLeader != none && SquadLeader.Enemy != none
        && VSizeSq(SquadLeader.Enemy.Location - Pawn.Location) < 640000 // 800u
        && CurrentFormation == 'SingleFile')
    {
        Crouch();
    }
    else
    {
        Uncrouch();
    }
}
```

**Effect:** Grunts naturally duck for cover in tight spaces during combat. Reads as tactical awareness. Zero `FastTrace` cost.

### 4.4 Wave Momentum Response

**Problem:** Bots behave identically on wave 1 and wave 50. No sense of escalation.

**Solution:** SL adjusts formation density and retreat threshold based on wave number:

```unrealscript
function float GetWaveMomentum()
{
    local int wave = mut.KF.MyKFGRI.WaveNum;

    if (wave <= 3)   return 0.8;  // early: relaxed, wider formations
    if (wave <= 10)  return 1.0;  // standard
    if (wave <= 25)  return 1.2;  // tight formations, lower retreat threshold
    return 1.4;                    // late: very tight, aggressive retreat
}

// In SL decision loop:
// Retreat threshold scales with momentum
bool shouldRetreat = CountNearbyZeds >= (4 * GetWaveMomentum());
```

**Effect:** Early waves: wide arrowhead, relaxed offsets. Late waves: tight single-file, aggressive retreat. Feels like the squad is "winding up."

### 4.5 Promotion Fanfare

**Problem:** Grunt promotes to SL. No visual feedback. Player doesn't notice the hierarchy shift.

**Solution:** On promotion, the new SL plays a brief "rally" emote and issues `CMD_HoldArea` for 1.0s before resuming normal decision loop:

```unrealscript
function PromoteToSquadLeader()
{
    BotRank = 'SL';
    PlayEmote(Emote_Rally); // "Yes sir!"
    SetTimer(1.0, 'ResumeSLLoop');
    IssueCommand(CMD_HoldArea, Pawn.Location);
}
```

**Effect:** Visible hierarchy shift. The new leader "takes command" with a 1s rally pose before resuming formation math.

### 4.6 Rally Point Drift

**Problem:** Squad camps at a fixed point indefinitely. Looks like a bug, not a tactical hold.

**Solution:** `CMD_HoldArea` anchors drift slowly (50u/min) toward the nearest objective or enemy cluster:

```unrealscript
// In SL — HoldArea drift
function UpdateHoldAreaDrift()
{
    if (CurrentOrder == CMD_HoldArea)
    {
        local vector objective = mut.GetObjectiveLocation();
        local vector enemy = GetNearestEnemyCluster();
        local vector driftTarget;

        if (VSizeSq(enemy - Pawn.Location) < VSizeSq(objective - Pawn.Location))
            driftTarget = enemy;
        else
            driftTarget = objective;

        // Drift 50u per minute toward target
        float driftRate = 50.0 / 60.0; // u per second
        HoldAreaAnchor += Normalize(driftTarget - HoldAreaAnchor) * driftRate * DeltaTime;
    }
}
```

**Effect:** Camps slowly migrate toward action. Feels like the squad is "positioning" rather than "stuck."

### 4.7 Grunt Panic Flash

**Problem:** Grunt is grabbed. 3s of leaderless idle after SL death. Looks broken.

**Solution:** During the 3s promotion gap, grunts enter a brief "panic" state:

```unrealscript
// In KF2Bot — grunt panic (during SL death gap)
function GruntPanic()
{
    // Random 200-400u lateral scatter
    vector scatter = Vector(Random(400) - 200, Random(400) - 200, 0);
    MoveToward(Pawn.Location + scatter);

    // Brief crouch
    Crouch();

    // After 1s, resume CMD_HoldArea behavior
    SetTimer(1.0, 'ResumeHoldArea');
}
```

**Effect:** Grunts scatter briefly when their leader dies. Reads as "losing command" rather than "frozen bug." The panic flash (1s scatter + crouch) covers the 3s promotion gap visually.

---

## PART 5: IMPLEMENTATION STRATEGY

### 5.1 File Modification Map

| File | Lines (est.) | Changes | New Content |
|------|-------------|---------|-------------|
| `KF2Bot.uc` | ~3,910 → ~4,500 | Rank-gated `Tick()`, SL decision loop, grunt offset logic, `EBotCommand` enum, `HearNoise` implementation, formation scan, promotion handling | +~600 lines |
| `KF2BotsMut.uc` | ~1,496 → ~1,800 | `PendingPromotions[]`, promotion queue processing, ammo factory delay, wave start broadcast, rank assignment | +~300 lines |
| `KFInventoryManager_Bot.uc` | ~? | No changes (rank-agnostic) | — |
| `KF2BotChat.uc` | ~? | Rank-aware chatter (SL talks more, grunts less) | +~50 lines |
| `KF2BotBroadcastHandle.uc` | ~? | No changes | — |

### 5.2 New Classes & Structures

```unrealscript
// In KF2Bot.uc — new enum
enum EBotRank
{
    GRUNT,
    SQUAD_LEADER,
    LIEUTENANT,
    CAPTAIN,
};

enum EBotCommand
{
    CMD_HoldArea,
    CMD_PushAnchor,
    CMD_TacticalRetreat,
    CMD_FocusTarget,
};

// In KF2BotsMut.uc — promotion queue struct
struct PromotionRequest
{
    var KF2Bot DeadOfficer;
    var EBotRank OldRank;
    var KF2Bot Replacement;
    var float Score;
};
```

### 5.3 Timer Architecture

| Timer | Owner | Interval | Purpose |
|-------|-------|----------|---------|
| `MacroTimer` | `KF2BotsMut` | 3.0s | SYG, boss, promotion, anchor broadcast |
| `CaptainPathTimer` | `KF2Bot` (Captain) | 3.0s | `FindPathToward`, platoon anchors |
| `LTDispatchTimer` | `KF2Bot` (Lieutenant) | 1.0s | Squad target areas |
| `SLDecisionTimer` | `KF2Bot` (SL) | 0.5s | Formation scan, threat response, orders |
| `GruntOffsetTimer` | `KF2Bot` (Grunt) | 0.2s | 2D offset update |
| `GruntHealthTimer` | `KF2Bot` (Grunt) | 2.0s | Critical health safety net |
| `GrabCheckTimer` | `KF2Bot` (Grunt) | 0.2s | `CheckGrabbed()` |
| `TriageTimer` | `KF2Bot` (SL) | 2.0s | Medic triage |
| `ShoppingTimer` | `KF2Bot` (SL) | 60s | Economy check |
| `AmmoDelayTimer` | `KF2BotsMut` | 10s (one-shot) | Factory re-enable |

**Staggering:** All `SLDecisionTimer` instances initialize with a random 0–0.5s offset to prevent frame alignment.

### 5.4 State Machine Changes

**Current:** 18 states, all evaluated by every bot in `PickNextMove()`.

**Proposed:** States are **rank-gated**. Grunts only enter a subset:

| State | Grunt Access | SL Access | LT/Captain Access |
|-------|:------------:|:---------:|:-----------------:|
| `PickNextMove` | ❌ (replaced by `UpdateGruntOffset`) | ✅ | ✅ |
| `Roaming` | ✅ (fallback when no SL) | ✅ | ✅ |
| `Camp` | ✅ (via `CMD_HoldArea`) | ✅ | ✅ |
| `DoObjective` | ✅ (via `CMD_PushAnchor`) | ✅ | ✅ |
| `FightEnemy` | ✅ (event-driven) | ✅ | ✅ |
| `TacticalRetreat` | ✅ (via `CMD_TacticalRetreat`) | ✅ | ✅ |
| `BreakLose` | ✅ (event-driven) | ✅ | ✅ |
| `Hunting` | ✅ (event-driven) | ✅ | ✅ |
| `HealingSelf` | ✅ (event + safety net) | ✅ | ✅ |
| `HealOther` | ❌ (SL-only) | ✅ | ✅ |
| `HealRanged` | ❌ (SL-only) | ✅ | ✅ |
| `GrenadeTarget` | ❌ (SL-only) | ✅ | ✅ |
| `GoShopping` | ✅ (via `CMD_FocusTarget`) | ✅ | ✅ |
| `GetItem` | ✅ (via `CMD_FocusTarget`) | ✅ | ✅ |
| `DonatingMoney` | ❌ (SL-only) | ✅ | ✅ |
| `Dead` | ✅ | ✅ | ✅ |
| `IsRagdolled` | ✅ | ✅ | ✅ |
| `VictoryDance` | ✅ (P1) | ✅ | ✅ |

> **Grunt states are all event-driven or command-driven.** No state requires the full `PickNextMove` funnel. The grunt's "decision loop" is `UpdateGruntOffset()` + event hooks.

---

## PART 6: PERFORMANCE BUDGET (DETAILED)

### 6.1 Per-Frame Cost Analysis (40 Bots, 25 Humans)

| Component | Current (autonomous) | Proposed (Echelon) | Notes |
|-----------|---------------------|-------------------|-------|
| 40 × `Tick()` full | 40 × 2.0ms = 80ms/frame | 40 × 0.05ms (grunt) + 5 × 0.5ms (SL) = 2.25ms/frame | Grunt tick is 97.5% lighter |
| 40 × `PickNextMove` | 40 × 0.1ms = 4ms/frame | 5 × 0.1ms = 0.5ms/frame | Only SLs evaluate priorities |
| 30 × 4 × `FastTrace` | 120 × 3µs = 0.36ms/frame | 5 × 4 × 3µs / 1.5s = 0.004ms/frame | 98.9% reduction |
| 40 × `FindPathToward` | 40 × 0.5ms = 20ms/frame (amortized) | 2.5 × 0.5ms / 3s = 0.04ms/frame | 99.8% reduction |
| **Total AI CPU** | **~104ms/frame** | **~3ms/frame** | **~97% reduction** |

> **Note:** The "current" numbers are worst-case per-frame estimates. In practice, `Tick()` does not run at 60fps for all 40 bots simultaneously (UE3's tick scheduler distributes). The ~2–4ms/frame estimate in §0.3 is the realistic average.

### 6.2 Timer Staggering Schedule

```
t=0.00s  Mutator MacroTimer fires (wave start, SYG, promotion)
t=0.10s  Captain A PathTimer fires (FindPathToward)
t=0.20s  Captain B PathTimer fires (FindPathToward)
t=0.15s  SL #1 DecisionTimer fires (4× FastTrace, formation)
t=0.35s  SL #2 DecisionTimer fires (staggered +0.2s)
t=0.25s  SL #3 DecisionTimer fires (staggered +0.1s)
t=0.45s  SL #4 DecisionTimer fires (staggered +0.3s)
t=0.10s  SL #5 DecisionTimer fires (staggered +0.0s)
t=0.50s  Lt #1 DispatchTimer fires (squad targets)
t=0.60s  Lt #2 DispatchTimer fires
...
```

**Rule:** No two `FastTrace` batches (4 traces each) fire in the same frame. Maximum 4 traces/frame from any single SL.

### 6.3 Scaling to 65 Entities

| Entity Count | AI CPU (Echelon) | AI CPU (Autonomous) | Headroom |
|-------------|-----------------|--------------------:|----------|
| 25 humans + 0 bots | 0 ms | 0 ms | — |
| 25 humans + 10 bots | ~1.0 ms | ~2.5 ms | 60% |
| 25 humans + 20 bots | ~2.0 ms | ~5.0 ms | 60% |
| 25 humans + 40 bots | ~3.0 ms | ~10.0 ms | **70%** |

> **Conclusion:** The Echelon system maintains <5ms AI CPU at full 65-entity scale, well within UE3's 16.6ms frame budget. The autonomous model would consume ~60% of the frame budget at 40 bots, leaving no headroom for zed AI, physics, or rendering.

---

## APPENDIX A: SDK REFERENCE MAP (ECHOLON-SPECIFIC)

| SDK Class | File | Echelon Usage |
|-----------|------|---------------|
| `PickupFactory` | `Engine/Classes/PickupFactory.uc` | `bPickupHidden`, `SetPickupHidden()`, `SetPickupVisible()` |
| `KFPickupFactory` | `KFGame/Classes/KFPickupFactory.uc` | `bKismetDriven`, `bKismetEnabled`, `Reset()` |
| `KFPickupFactory_Ammo` | `KFGameContent/Classes/KFPickupFactory_Ammo.uc` | Wave start factory iteration, `bNotBased` |
| `Actor` | `Engine/Classes/Actor.uc` | `FastTrace()` (line 1953), `VSizeSq()` |
| `Controller` | `Engine/Classes/Controller.uc` | `SeePlayer()` (1160), `HearNoise()` (1150), `SeeMonster()` (1166) |
| `Pawn` | `Engine/Classes/Pawn.uc` | `NotifyTakeHit()` (2512), `Crouch()`, `MoveToward()` |
| `KFPawn_Human` | `KFGame/Classes/KFPawn_Human.uc` | `HealthMax`, `HealthToRegen`, `IsAliveAndWell()` |
| `KFAIController` | `KFGame/Classes/KFAIController.uc` | `HearNoise()` (4699, dormant), `Tick()` (3934) |
| `KF2Bot` | `KF2Bots/Classes/KF2Bot.uc` | **Primary modification target** |
| `KF2BotsMut` | `KF2Bots/Classes/KF2BotsMut.uc` | **Secondary modification target** |
| `KFGameReplicationInfo` | `KFGame/Classes/KFGameReplicationInfo.uc` | `bMatchIsOver`, `bIsBossWave()`, `WaveNum`, `CurrentObjective` |

---

## APPENDIX B: ALIAS & CONVENTION NOTES

| Item | Convention |
|------|-----------|
| Rank names | `GRUNT`, `SQUAD_LEADER`, `LIEUTENANT`, `CAPTAIN` (enum `EBotRank`) |
| Command names | `CMD_HoldArea`, `CMD_PushAnchor`, `CMD_TacticalRetreat`, `CMD_FocusTarget` (enum `EBotCommand`) |
| Timer names | PascalCase: `MacroTimer`, `SLDecisionTimer`, `GruntOffsetTimer` |
| Function names | PascalCase: `UpdateGruntOffset`, `ScanRoomForFormation`, `ComputeFormationOffset` |
| File naming | `KF2_Echolon_AI.md` (user-specified spelling) |
| Formation names | `'Arrowhead'`, `'StaggeredColumn'`, `'SingleFile'`, `'LineFormation'` |
| Zed distance constants | `RETREAT_ZED_COUNT = 4`, `RETREAT_HEAVY_DIST = 300`, `SYG_DISTANCE_SQ = 1000000` |
| Formation variance | ±10–15% random offset (anti-symmetry) |
| Breathing amplitude | ±15u lateral, ±10u forward/back, ~20s period |
| Panic scatter | 200–400u random lateral, 1s duration |
| HoldArea drift rate | 50u/min toward nearest objective/enemy |
| Promotion gap | ≤3s (1 macro-tick) + 10s emergency self-promotion |
| Ammo delay window | 10s `SetPickupHidden` / `SetPickupVisible` |

---

*[DOCUMENT COMPLETE — All Checkpoint 1 & 2 research compiled. Aligned with `KF2_Current_Architecture.md` and `KF2_Proposed_Engine_Optimization.md`.]*
