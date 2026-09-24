# Legacy KF2Bots Codebase — Structural Diagnostic Report

---

## Part 1: File Structure Markdown Summary

### `KF2Bot.uc` — Bot AI Controller (3,321 lines)

| Aspect | Detail |
|---|---|
| **Class** | `class KF2Bot extends AIController` |
| **Role** | The primary bot AI controller. Extends the engine's `AIController` and implements a full state-machine-driven combat AI for KF2. |
| **Key Design Decision** | `bIsPlayer = true` in `defaultproperties` — this is the single most architecturally significant flag in the entire codebase. It causes the engine to treat the bot as a *player* for replication, HUD rendering, and damage scoring purposes. |
| **State Machine** | 16 states: `PickNextMove` (decision hub), `Roaming`, `DoObjective`, `FightEnemy`, `BreakLose`, `Hunting`, `HealingSelf`, `HealOther`, `HealRanged`, `GrenadeTarget`, `GoShopping`, `GetItem`, `DonatingMoney`, `VictoryDance`, `Dead`, `IsRagdolled` |
| **Movement** | Custom movement system with `MoveFlags` (1=position, 2=actor), serpentine strafing (`StrafeTowardPoint`), blocked-path detection (`CheckBlockedPath`), door path management (`MarkDoorPath`, `BuildPathToward`), and wall-bump adjustment (`NotifyBump`, `PickWallAdjust`) |
| **Combat** | `FireWeaponAt` dispatches `StartFire` with fire-mode-specific logic (melee=0, reload=2, melee-range=3, standard=0). Enemy selection via `SetEnemy` with threat scoring (`GetEnemyThreat`). Low-health targeting via `TargetLowHealth` (time-decayed health threshold). |
| **Healing** | Three healing paths: `HealingSelf` (self-syringe, `MedicGun.StartFire(1)`), `HealOther` (melee syringe, `MedicGun.StartFire(0)`), `HealRanged` (range medic, `RangeMedicGun.StartFire(1)`). Each uses a `HealingStage` byte (0=equip, 1=switch back) with a 0.1s repeating timer. |
| **Economy** | `ProcessPurchase` handles trader shopping (weapons, armor, grenades, cash). `SellWeapon` sells surplus weapons. `DonateMoney`/`DropMoney` tosses cash to lower-score teammates. |
| **Weapon Selection** | `SwitchToBestWeapon` delegates to `KFInventoryManager_Bot.GetBestWeapon` which rates weapons by `GroupPriority`, perk compatibility, ammo status, and randomness. |
| **Pathfinding** | Uses `FindPathToward`/`FindPathTo`/`FindRandomDest` (engine navigation) with custom door-blockade tracking (`DoorPaths` array of `FRouteDoorBlockade`) and blocked-route memory (`BotBlockRoutes`). |

### `KF2BotsMut.uc` — Bot System Mutator (966 lines)

| Aspect | Detail |
|---|---|
| **Class** | `class KF2BotsMut extends KFMutator` with `config(BotsMut)` |
| **Role** | The mutator that bootstraps, manages, and configures the entire bot system. Registered as the `BaseMutator` or appended to the existing mutator chain. |
| **Configuration** | `config` vars: `NumBots` (default 6), `MinimumBots`, `BotMinPerkLv`, `BotMaxPerkLv` (default 25), `BotsDamageScale` (default 1.0), `ZedCountScaling` (default 0.2), `bBotsUnlimitedAmmo`, `bBotsUnlimitedCash`, `bNoZerkerBots` |
| **Lifecycle** | `PostBeginPlay` → `AttachHooks()` → register as BaseMutator → `MatchStarting` → spawn bots (standalone) or set 1s timer (listen/dedicated). `Timer` maintains bot count between `MinimumBots` and `NumBots`. |
| **Bot Management** | `AddBot` (spawn + perk assignment + squad ID + `RestartBot`), `RemoveBot` (lowest-score bot), `RestartBot` (full respawn with `SpawnDefaultPawnFor`, `SetPlayerDefaults`, `SeqEvent_PlayerSpawned`), `RespawnBots` (wave-triggered) |
| **Squad System** | `SetSquadID` (max 4 per squad, random playstyle), `SetSquadLeader`, `FreeSquadID`. Squad leaders assigned to bots for group coordination. |
| **Character Customization** | `InitBotCharacter` — randomizes archetype, body variant, skin, head, and cosmetic attachment per bot (see Objective 2 below) |
| **Wave/Objective** | `CheckWave` (0.1s timer) detects wave changes, scales zed count by `ZedCountScaling`, tracks `KFMapObjective_DoshHold` objectives, manages `ValidPoints` for objective navigation |
| **Trader Integration** | `InitTraderList` populates `TraderList` array of `AIWeaponInfo` from `KFGFxObject_TraderItems`. `FindWeaponByClass` for lookup. |
| **Admin Commands** | `Mutate` handles console commands: `-SetNumBots`, `-SetMinBots`, `-SetBotMinLv`, `-SetBotMaxLv`, `-SetBotChat`, `-SetScaleZedCount`, `-SetNoZerker`, `-SetBotsInfAmmo`, `-SetBotInfDosh`, `-SetBotDamageScale`, `-AI`, `-Help`, `-BotTalk` |
| **Damage Scaling** | `NetDamage` — zeroes friendly-fire damage between bots, scales all other damage by `BotsDamageScale` |
| **Emotes** | `InitEmotes` loads `KFEmoteList`, `PickRandEmote` for victory dances, `ShouldDoVictoryDance` (5s cooldown) |

### `AIWeaponInfo.uc` — Weapon Data Structure (58 lines)

| Aspect | Detail |
|---|---|
| **Class** | `class AIWeaponInfo extends Object transient` |
| **Role** | A lightweight data container for weapon economic/strategic information, used by the bot's shopping and weapon-selection logic. |
| **Fields** | `WeaponClass`, `Perk`, `AIRating` (based on `BuyPrice`), `BuyPrice`, `AmmoPricePerMag`, `SecondaryAmmoMagSize`, `SecondaryAmmoMagPrice`, `PricePerBullet[2]` (per-bullet cost for primary/secondary), `bCanSell` |
| **`InitInformation`** | Populates all fields from a `KFWeaponDefinition` by dynamically loading the weapon class and reading its `default` properties. Returns `false` if the class can't be loaded. |
| **Usage** | Populated by `KF2BotsMut.InitTraderList` from the trader's sale items. Queried by `KF2Bot.PickFavorite` (weapon desire scoring) and `KF2Bot.SellWeapon` (sell-value scoring). |

### `FunctionHooks.uc` — Bytecode Injection Framework (864 lines)

| Aspect | Detail |
|---|---|
| **Class** | `class FunctionHooks extends Object abstract` |
| **Role** | The core of the bytecode injection system. Provides hook implementations for 22 native engine functions, and the `AttachHooks()` static method that patches them. |
| **`AttachHooks()`** | Static final function called from `KF2BotsMut.PostBeginPlay`. Replaces the `.H48` bytecode property of 22 native functions with the corresponding hook implementations from `KF2Bots_backup.FunctionHooks`. |
| **Patched Functions** | `KFDialogManager.PlayPlayerDamageDialog`, `PlayDialogEvent`, `StopBreathingDialog`; `KFAfflictionManager.NotifyTakeHit`; `KFGameInfo.ScoreDamage`, `CanSpectate`; `KFVoteCollector.ShouldConcludeSkipTraderVote`, `ConcludeVoteSkipTrader`; `KFPawn_Human.HealDamageForce`, `TakeDamage`, `UpdateActiveSkillsPath`; `KFWeapon.SendToFiringState`, `PlayWeaponAnimation`, `GetMeleeAnimName`, `GetKFProjectileClass`, `PlaySprintLoop`; `KFWeap_HealerBase.PerformReload`, `StartFire`; `KFWeap_MedicBase.StartHealRecharge`; `KFDT_Dart_Toxic.GetMedicToxicDmgType`; `KFWeap_Rifle_RailGun.Tick`; `KFAffliction_Fire.ToggleEffects` |
| **Hook Pattern** | Each hook function replicates the original native function's logic, with targeted modifications inserted at specific points. The modifications are primarily AI-controller-aware branches (e.g., `Instigator.IsLocallyControlled() && !Instigator.IsHumanControlled()`). |
| **Critical Hook: `StartFire`** | Intercepts `KFWeap_HealerBase.StartFire`. For AI controllers (`!IsHumanControlled()`), calls `Bot_GetHealTarget()` to find the best healing target by tracing in front of the bot. This is the mechanism that makes syringe healing work for bots. |
| **Critical Hook: `KFH_TakeDamage`** | Intercepts `KFPawn_Human.TakeDamage`. After the original damage processing, updates `KFPRI.PlayerHealth` and `KFPRI.PlayerHealthPercent` to keep the replicated health in sync with the pawn's actual health. |

### `H0.uc` — KFPawn Payload (71 lines)

| Aspect | Detail |
|---|---|
| **Class** | `class H0 extends KFPawn abstract` |
| **Role** | A shadow/overlay class that mirrors `KFPawn`'s internal state layout. All variables are `private transient` with obfuscated `H*` names. |
| **Purpose** | Provides a script-accessible mirror of `KFPawn`'s internal fields so that hook functions can read/write the pawn's state without needing direct access to the native (potentially `const`/`private`) fields. |
| **Key Fields** | `H39` (PlayerReplicationInfo), `H34` (array of ActiveSkill), `H43` (AkComponent), `H44` (DialogResponseInfo), `H45` (delegate), `H17` (EmitterPool), `H1D/H1E/H1F` (KFPowerUpFxInfo), `H2B/H2C` (PointLightComponent), `H2D` (KFGFxMoviePlayer_PlayerInfo) |
| **Relationship to Hooks** | The `H0` class is the base class that the hook payloads inherit from. The hook functions in `FunctionHooks.uc` operate on `KFPawn` instances, and the `H0` class provides the variable layout that matches the native `KFPawn`'s memory structure. |

### `H4A.uc` — PlayerReplicationInfo Payload (49 lines)

| Aspect | Detail |
|---|---|
| **Class** | `class H4A extends PlayerReplicationInfo abstract` |
| **Role** | A shadow/overlay class that mirrors `KFPlayerReplicationInfo`'s internal state layout. All variables are `private transient` with obfuscated `H*` names. |
| **Purpose** | Provides script-accessible mirrors of the PRI's internal fields, including the `CharacterArchetypes` array and `RepCustomizationInfo` struct fields, which are otherwise inaccessible due to `const`/`native private` restrictions. |
| **Key Fields** | `H67` (array of `KFCharacterInfo_Human` — mirrors `CharacterArchetypes`), `H69` (`CustomizationInfo` — mirrors `RepCustomizationInfo`), `H4F` (int — mirrors the bot's perk level), `H6C` (Class<KFPerk>), `H65` (string — player name), `H77` (KFPlayerController) |
| **Relationship to Hooks** | Used by `InitBotCharacter` to access and modify the PRI's character customization data. The `H4F` field is set to the bot's level (`PRI.H4F = lvl`). |

### `H46.uc` — Bytecode Storage Payload (6 lines)

| Aspect | Detail |
|---|---|
| **Class** | `class H46 extends Object abstract` |
| **Role** | The minimal bytecode storage class. Contains `H47[41]` (a 41-byte array) and `H48` (an `array<byte>`). |
| **Purpose** | `H48` is the actual bytecode array that gets assigned to the `.H48` property of native functions during `AttachHooks()`. The `H47[41]` array is likely a fixed-size header or signature block. |
| **Relationship to Hooks** | This is the delivery mechanism: the hook implementations compiled in `FunctionHooks.uc` are stored as bytecode in `H48`, and `AttachHooks()` copies this bytecode into the target native functions' `.H48` property, effectively replacing their compiled code. |

---

## Part 2: Architectural Diagnostics

---

### Objective 1: The Legacy HUD Implementation

**Question:** Did the original author implement custom HUD overrides, UI hacks, or `bBot` flag manipulations, or did the legacy code purely rely on native `KFPlayerReplicationInfo` health variable updates?

**Finding: The legacy code uses a hybrid approach — `bIsPlayer` flag manipulation + direct PRI health variable updates. No custom HUD class or UI widget manipulation exists.**

#### 1. The `bIsPlayer` Flag (the foundational mechanism)

In `KF2Bot.uc`, the `defaultproperties` block sets:

```
bIsPlayer = true
```

This is the single most architecturally significant decision in the entire codebase. By setting `bIsPlayer = true` on the `AIController`, the engine's replication, HUD, and damage-scoring systems treat the bot as a *player* rather than an NPC. This means:

- The `KFPlayerReplicationInfo` is created and replicated for the bot (it would not be for a standard AI controller)
- The engine's default HUD renders health/armor bars for the bot at **player size** (not the "NPC-sized" bars that would appear for a standard AI)
- Damage scoring, score display, and kill-feed entries treat the bot as a player

#### 2. Direct PRI Health Variable Updates

The code updates `KFPRI.PlayerHealth` and `KFPRI.PlayerHealthPercent` at three points:

| Location | Context | Code |
|---|---|---|
| `KF2Bot.uc:176-177` | `Restart()` — after spawning a bot with Berserker/FieldMedic perk | `KFPRI.PlayerHealthPercent = FloatToByte(float(KPawn.Health) / float(KPawn.HealthMax)); KFPRI.PlayerHealth = KPawn.Health;` |
| `KF2BotsMut.uc:636-637` | `RestartBot()` — after respawning a bot | `KFPlayerReplicationInfo(NewPlayer.PlayerReplicationInfo).PlayerHealthPercent = FloatToByte(float(NewPlayer.Pawn.Health) / float(NewPlayer.Pawn.HealthMax)); KFPlayerReplicationInfo(NewPlayer.PlayerReplicationInfo).PlayerHealth = NewPlayer.Pawn.Health;` |
| `FunctionHooks.uc:571-572` | `KFH_TakeDamage` hook — after every damage event | `KFPRI.PlayerHealth = Health; KFPRI.PlayerHealthPercent = FloatToByte(float(Health) / float(HealthMax));` |

The third point is critical: the `KFH_TakeDamage` hook (which patches `KFPawn_Human.TakeDamage`) ensures that the PRI's health variables are kept in sync with the pawn's actual health after *every* damage event. Without this hook, the PRI health would only be updated at spawn/respawn, and the HUD health bar would be stale.

#### 3. Armor Handling

Armor is managed directly on the pawn (`KPawn.Armor`, `KPawn.MaxArmor`), not on the PRI:

- `KF2Bot.uc:179-183` — `Restart()` sets `KPawn.MaxArmor = byte(100 + Min(CurrentLevel * 2, 150))` and `KPawn.Armor = KPawn.MaxArmor` (level > 20 only)
- `KF2Bot.uc:1419-1428` — `ProcessPurchase` buys armor from the trader

The armor bar display relies entirely on the engine's default behavior for player pawns. There is no PRI armor variable update in the code.

#### 4. HUD Suppression: `ShowAllHUDGroups()` Override

In `KFInventoryManager_Bot.uc:52`, the `ShowAllHUDGroups()` function is overridden to be a **no-op** (empty body). This suppresses the bot's HUD group display (weapon HUD, ammo display, etc.) that would normally appear on the bot's pawn. This is the only HUD-related override in the entire codebase.

#### 5. No `bBot` Flag Manipulation

There is no `bBot` flag set or manipulated anywhere in the codebase. The code relies entirely on `bIsPlayer = true` to make the engine treat the bot as a player.

#### 6. No Custom HUD Class or UI Widget Manipulation

There is no custom HUD class, no `MyGfxHUD` override, no `PlayerStatusContainer` manipulation (except `ShowActiveIndicators` in the `UpdateActiveSkillsPath` hook for active skill icons), and no UI widget creation or modification. The health/armor bars are rendered by the engine's default HUD for player pawns.

#### Architectural Conclusion

The legacy HUD implementation is a **two-part strategy**:

1. **`bIsPlayer = true`** makes the engine treat the bot as a player, which gives it player-sized health/armor bars rendered by the default HUD.
2. **Direct PRI health variable updates** (at spawn, respawn, and after every damage event via the `KFH_TakeDamage` hook) keep the replicated health in sync with the pawn's actual health, so the HUD health bar reflects the bot's true health state.

The `ShowAllHUDGroups()` no-op override suppresses the bot's weapon/ammo HUD groups, but the health/armor bars (which are part of the player status display, not the inventory HUD) are unaffected.

**Risk for Modern Integration:** The `bIsPlayer = true` flag is the linchpin. If the modern engine's HUD system has changed how it determines whether to render health/armor bars (e.g., if it now checks a different flag or uses a different PRI field), this approach may break. The `KFH_TakeDamage` hook is also version-dependent (bytecode injection), so the PRI health sync mechanism would need to be replaced with a non-injection approach (e.g., a post-damage event handler or a timer-based health sync).

---

### Objective 2: Random Character Appearances & Cosmetics

**Question:** How did the author randomize bot appearance using `PRI.CharacterArchetypes`, `BodyVariants`, and `PRI.RepCustomizationInfo`? What engine-level roadblocks caused the direct struct assignments to be commented out?

**Function: `InitBotCharacter` in `KF2BotsMut.uc:377-443`**

#### Intended Algorithm (as shown in the decompiled code)

1. **Level Randomization:**
   ```
   lvl = byte(BotMinPerkLv + Rand((BotMaxPerkLv - BotMinPerkLv) + 1));
   Bot.CurrentLevel = int(lvl);
   PRI = KFPlayerReplicationInfo(Bot.PlayerReplicationInfo);
   PRI.H4F = lvl;  // Set the bot's perk level via the H4A payload mirror
   ```

2. **Archetype/Body/Skin Randomization (with duplicate avoidance):**
   ```
   I = byte(Rand(PRI.CharacterArchetypes.Length));   // Random archetype index
   H = PRI.CharacterArchetypes[int(I)];              // Get the KFCharacterInfo_Human
   J = byte(Rand(H.BodyVariants.Length));            // Random body variant index
   Z = byte(Rand(H.BodyVariants[int(J)].SkinVariations.Length));  // Random skin index
   ```
   Then a loop checks up to 4 times whether any other bot already has the same `(CharacterIndex, BodyMeshIndex, BodySkinIndex)` combination. If a duplicate is found, it retries with a new random selection.

3. **Head Randomization:**
   ```
   C = byte(Rand(H.HeadVariants.Length));
   PRI.RepCustomizationInfo.HeadMeshIndex = int(C);
   PRI.RepCustomizationInfo.HeadSkinIndex = Rand(H.HeadVariants[int(C)].SkinVariations.Length);
   ```

4. **Body Assignment:**
   ```
   PRI.RepCustomizationInfo.CharacterIndex = int(I);
   PRI.RepCustomizationInfo.BodyMeshIndex = int(J);
   PRI.RepCustomizationInfo.BodySkinIndex = int(Z);
   ```

5. **Optional Cosmetic Attachment (66% chance):**
   ```
   if(Rand(3) != 0)
   {
       C = byte(Rand(H.CosmeticVariants.Length));
       PRI.RepCustomizationInfo.AttachmentMeshIndices[0] = int(C);
       PRI.RepCustomizationInfo.AttachmentSkinIndices[0] = Rand(H.CosmeticVariants[int(C)].SkinVariations.Length);
   }
   ```

6. **Player Name:**
   ```
   PRI.SetPlayerName(("[Lv" $ string(lvl)) $ "] ") $ (Localize((string(H.Name) $ ".BodyMesh") $ string(J), "BodySkin" $ string(Z), "KFCharacterInfo")));
   ```

#### Engine-Level Structural Roadblocks

The decompiled code shows the assignments as **active** (not commented out), which means this is the final working state after the hook system was applied. However, the original source code (before bytecode injection) would have encountered the following structural barriers:

| Roadblock | Detail |
|---|---|
| **`const` struct: `RepCustomizationInfo`** | `RepCustomizationInfo` is a `const` struct in the native engine. In UnrealScript, `const` structs cannot be reassigned as a whole, and their fields may have restricted write access. Direct assignment to `PRI.RepCustomizationInfo.CharacterIndex` etc. would be blocked at compile time or runtime. |
| **`native private` setters** | The individual fields of `RepCustomizationInfo` (CharacterIndex, HeadMeshIndex, BodyMeshIndex, etc.) are likely protected by `native private` setters in the engine's C++ layer. This means script code cannot directly write to these fields without going through a native setter function. |
| **`const` array: `CharacterArchetypes`** | `PRI.CharacterArchetypes` is a `const` array of `KFCharacterInfo_Human`. You can read from it (as the code does: `H = PRI.CharacterArchetypes[int(I)]`), but you cannot modify it. The randomization only *reads* from this array, so this is not a blocker for the read path. |
| **`const` nested structs: `BodyVariants`, `SkinVariations`, `HeadVariants`, `CosmeticVariants`** | These are nested `const` structures within `KFCharacterInfo_Human`. Again, readable but not writable. The code only reads from them for randomization, so this is not a blocker. |
| **`H4F` level field** | The bot's perk level is stored in a private field of the PRI. The `H4A` payload class provides a `private transient int H4F` mirror that maps to this field. Without the hook system, `PRI.H4F` would not be accessible from script. |

#### How the Hook System Resolved These Roadblocks

The `H4A` payload class (extending `PlayerReplicationInfo`) provides a script-accessible mirror of the PRI's internal state. The hook system patches the PRI's bytecode (via `H46.uc`'s `H48` array) to allow the script code to directly assign to `RepCustomizationInfo` fields and `H4F`. The decompiled code shows the final working state where these assignments are active.

#### Architectural Conclusion

The original author's approach was correct in principle (randomize archetype → randomize body variant → randomize skin → randomize head → optionally randomize cosmetic), but the engine's `const` struct and `native private` setter restrictions made direct script assignment impossible. The hook system was the workaround: it patched the PRI's bytecode to enable direct field assignment.

**Risk for Modern Integration:** If the modern engine has changed the `RepCustomizationInfo` struct layout, the `CharacterArchetypes` array structure, or the `H4F` field offset, the hook system would need to be re-patched. Alternatively, if the modern engine exposes proper script-accessible setters for `RepCustomizationInfo` fields (e.g., via a `SetCustomization` function), the hook system would be unnecessary for this purpose.

---

### Objective 3: Integrating `FunctionHooks` (Bytecode Injection)

**Question:** What are the structural risks of re-integrating the bytecode injection system into a modern KF2 server environment? Is it viable to restore this system solely to bypass the vanilla syringe limitations?

#### The Syringe Problem

The vanilla `KFWeap_HealerBase.StartFire` fails for AI controllers because it relies on the player's aim direction to determine the healing target. For an AI controller, there is no "player aim" in the traditional sense — the bot's `Rotation` is set by the AI, but the syringe's `StartFire` doesn't use it to find a healing target. The result is that the syringe fires but doesn't heal anyone, because `HealTarget` is `none`.

#### The Hook's Solution

The `StartFire` hook in `FunctionHooks.uc:712-788` intercepts the syringe's `StartFire` and adds an AI-controller-aware branch:

```
if(int(FireModeNum) == 0)
{
    if(Instigator.IsLocallyControlled() && !Instigator.IsHumanControlled())
    {
        Healee = Bot_GetHealTarget();   // AI controller: find best target by tracing
    }
    else
    {
        Healee = HealTarget;            // Human player: use existing target
    }
}
```

`Bot_GetHealTarget()` (lines 760-787) traces in front of the bot (75 units forward, 200 unit radius) and finds the lowest-health teammate that:
- Is on the same team
- Is alive and not at full health
- Can be healed (`KFPawn(P).CanBeHealed()`)
- Has line of sight (`FastTrace`)

It sets `HealTarget = BestTarget`, which the vanilla `StartFire` logic then uses.

#### Architectural Feasibility Analysis

| Risk Factor | Severity | Detail |
|---|---|---|
| **Version Dependency** | 🔴 Critical | The `.H48` bytecode patches are specific to a particular KF2 engine build. The bytecode offsets, function signatures, and internal state layout are tied to the exact engine version. A single engine update (e.g., KF2 patch) can invalidate all 22+ patches simultaneously. The `CUR_CONFIGVER = 1` in `KF2BotsMut` tracks config version but not engine bytecode version. |
| **Crash Risk** | 🔴 Critical | Patching native function bytecode is inherently dangerous. The `KFH_TakeDamage` hook patches `KFPawn_Human.TakeDamage`, which is called on *every* damage event in the game. A single malformed bytecode patch in this function would crash the entire server on the next damage event. Similarly, `ScoreDamage` is called on every damage event. |
| **Scope Creep** | 🟠 High | The hook system patches 22+ functions, most of which are unrelated to the syringe issue (dialog system, vote system, railgun tick, fire affliction, sprint loop, etc.). Re-integrating the full system for a single syringe fix is architecturally disproportionate. |
| **Maintenance Debt** | 🟠 High | Every engine update requires re-patching all hooked functions. The `H0`, `H4A`, and `H46` payload classes must be updated to match the new engine's internal state layout. This is a significant, ongoing maintenance burden. |
| **Security/Anti-Cheat** | 🟡 Medium | In a multiplayer environment, bytecode injection can be detected by anti-cheat systems. It also means the mod has access to core engine internals, which is a security surface. |
| **Isolation** | 🟡 Medium | The hook system is a global, server-wide patch. It affects all players and all bots. There is no way to scope the hook to only the syringe's `StartFire` without also patching the other 21 functions (they are all in the same `AttachHooks()` call). |

#### Targeted Alternative Analysis

The syringe target acquisition issue can potentially be solved **without** bytecode injection, by modifying the bot's healing state machine:

In the `HealOther` state (`KF2Bot.uc:2646-2735`), the bot already does:

```
Focus = PendingHeal;
Target = PendingHeal;
Pawn.StopFiring();
MedicGun.StartFire(0);
```

The bot sets `Focus` and `Target` before calling `StartFire(0)`. The question is whether the vanilla `StartFire` uses these for AI controllers. If it doesn't, the alternative is:

1. **Pre-set `HealTarget` on the syringe** before calling `StartFire(0)`. If the vanilla `StartFire` reads `HealTarget` for the healing target, setting it to `PendingHeal` would make the syringe heal the correct target without needing the hook.

2. **Override `StartFire` in a custom `KFWeap_HealerBase` subclass.** If the engine allows overriding `StartFire` in a weapon subclass, a custom syringe class could implement the `Bot_GetHealTarget()` logic directly, without bytecode injection.

3. **Use the bot's existing `PendingHeal` and `Target` variables** to drive the healing logic outside the weapon's `StartFire`, calling the healing damage directly via `HealDamage` or a similar engine function.

#### Architectural Conclusion

**The architectural cost of re-integrating the full `FunctionHooks` system is too high for the syringe fix alone.** The system is a 22-function global bytecode injection framework with critical version dependency, crash risk, and maintenance debt. Re-integrating it solely to bypass the vanilla syringe limitation is disproportionate.

**The recommended approach is to solve the syringe target acquisition at the bot controller level** (in `KF2Bot`'s healing states) by pre-setting the syringe's `HealTarget` before calling `StartFire`, or by overriding `StartFire` in a custom weapon subclass. This avoids bytecode injection entirely and is version-stable.

**If bytecode injection is absolutely required** (e.g., if the engine does not expose any script-accessible override for `StartFire`), then a **minimal subset** of the hook system should be extracted:
- Only the `KFWeap_HealerBase.StartFire` hook
- Only the `H46.uc` payload class (for bytecode storage)
- Only the `Bot_GetHealTarget()` function

This reduces the attack surface from 22 patched functions to 1, and limits the version dependency to a single function's bytecode. Even so, the version dependency and crash risk remain.
