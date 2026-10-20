# KF2Bots Current Architecture

Revision: v2.0 -- fully re-verified rewrite (replaces KF2_Current_Architecture_OLD.md, whose line numbers are invalid and must not be cited)
Date: 2026-02-09

## Verified against

| File | Lines | SHA-256 (first 8) | Role |
|---|---|---|---|
| KF2BotsMut.uc | 3037 | 607a3e67 | Mod mutator: waves, fireteam hierarchy, squad orders, perks |
| KF2BotsFollowNavBase.uc | 1552 | d543db64 | Abstract follow-navigation locomotion (Plan B, KFAIController-free) |
| KF2BotBase.uc | 4615 | 82491dfb | Bot base: ranks, combat, formations, pathing, audit |
| KF2BotLogic.uc | 1377 | ffc4906a | Bot logic: healing, watchdogs, move evaluation, grunt control |
| KF2Bot.uc | 2075 | 17aad4ee | Final bot: PickNextMove hub + 18 states |

Inheritance: `KFMutator -> KF2BotsMut`; `AIController -> KF2BotsFollowNavBase (abstract) -> KF2BotBase -> KF2BotLogic -> KF2Bot`.

Citation style: `[123]` or `[123-140]` = this section's **Primary file** (each system section names it). `[Mut:1953]` `[Nav:727]` `[Base:812]` `[Logic:2410]` `[Bot:3573]` = the five files above. `[SDK Engine/Classes/Controller.uc:812]` = native SDK source. Line ranges point at real, re-verified code lines (see Appendix C for the correction log, Appendix D for open questions).

---

# PART 0 -- Navigation Index

## 0.1 How to use this document

- To find a system: read the tree in 0.3, or search for the `@SYS-` tag.
- To find a state: 0.4 lists every state, who enters it, who exits to it, and its FLOW tag.
- To find "where do I change X": 0.5 has a lookup table.
- To find a symbol (function/event/const/var): 0.7 is the complete A-Z symbol index (943 symbols extracted from source; ground truth file `_arch_work/symbols.json`).
- To find ownership rules (single-writer boundaries, cross-file call matrix): PART 6 (search for the `@SYS-P6-BOUNDARY` tag).
- Every system section has 7 subsections: 1. plain-english summary, 2. explanation, 3. logic pipeline, 4. inputs/outputs (single-writer notes), 5. FLOW (plain-English walkthrough with line citations), 6. technical reference (symbols, constants, variables, timers, edge cases, SDK facts), 7. where to fix.
- Sections 1-3 are written for a non-developer reader. Code identifiers always follow the English explanation.
- Facts marked `(INFERRED)` or `(UNVERIFIED)` are not taken from code/SDK and must not be relied on as verified.
- "SDK behaviour not verified" = the native function/class was not located in the local SDK tree; usage sites in the mod are cited, but the native behaviour is unknown.
- Line ranges are BODY-ONLY (start line to the closing-brace line of the function/state); substates (Begin/Dispatch/WaitStep/HoldStep/DirectMove/PathMove/EscapeStep/YieldStep/GiveUpStep) are listed separately by their label line; where source, symbols.json and the doc disagree, source wins over json, json over doc.

## 0.2 File map

```
KFMutator (SDK, class file absent from local SDK -- "SDK behaviour not verified")
  +-- KF2BotsMut.uc            3037 lines   (mod mutator, non-Actor: wave/squad hub)
        +-- (creates) KF2Bot pawns via Mutate [Mut:2590-2719]

AIController (SDK)
  +-- KF2BotsFollowNavBase.uc   1552 lines  abstract [Nav:29] (follow-locomotion engine)
        +-- KF2BotBase.uc        4615 lines  (bot base: combat, ranks, formations, pathing)
              +-- KF2BotLogic.uc  1377 lines  (healing decisions, watchdogs, move eval)
                    +-- KF2Bot.uc     2075 lines  (final class: PickNextMove hub + 18 states)
```

Role split (single-writer boundaries, detailed in PART 6):

- **Mut** writes: wave data, squad orders, slot table, zed-blacklist (node blocks), promo queue. It does NOT move bots directly.
- **FollowNav (Nav)** owns: one bot's follow-path episode, dispatch decisions, status; writes back to the hub only through `FollowNotifyHub` [Nav:1209-1212] (override in [Base:1287-1312]).
- **BotBase** owns: combat style, weapon, formation offsets, rank timers, audit log.
- **BotLogic** owns: heal pacing stamps, grunt movement intents, watchdog escalation.
- **Bot** owns: state machine (18 states) and the `PickNextMove` decision hub [Bot:17-253].

## 0.3 System tree

Every system appears below with its functions/states and doc tag. "All functions of file X" lists are exhaustive per `symbols.json` (943 symbols; verify check b/c).

### KF2BotsMut.uc (Primary: Mut) -- tag prefix `@SYS-MUT-`

| # | System | Functions (each with line refs) | Tag | Doc |
|---|---|---|---|---|
| M1 | Boot & config | PostBeginPlay [170-269], AddMutator [271-287], MatchStarting [289-309], Timer [311-332], defaultproperties [3031-3037], InitEmotes [2745-2752], PickRandEmote [2754-2763], ShouldDoVictoryDance [2765-2775] | @SYS-MUT-BOOT | P3.1 |
| M2 | Bot lifecycle & spawn | Mutate [2590-2719], AddBot [2358-2396], RemoveBot [2398-2431], RestartBot [2433-2533], RegisterBot [334-341], UnregisterBot [343-350], RespawnBots [2107-2125], InitBotCharacter [2160-2246], SetupSquadSpawns [2853-2897], SpawnSquadAt [2963-2977], PickSquadSpawnPoint [2980-2991], SpawnBotWithRank [2994-3005], RelocateBotsToAmmoCrates [2904-2960], HideAllPickups [3008-3017], ReEnableAmmoFactories [3019-3027], NetDamage [2721-2743], PickCustomBotName [2135-2152] | @SYS-MUT-SPAWN | P3.2 |
| M3 | Perk gacha | PickBotPerk [2325-2356], PickFallbackPerk [2252-2265], ResolvePerkByName [2272-2286], ResetPerkPool [2292-2314] | @SYS-MUT-PERK | P3.3 |
| M4 | Platoon & macro waypoints | InitializePlatoon [368-460], DetermineGroupCount [544-551], SyncSquadLeaders [471-516], ShuffleActiveBots [518-529], PruneInvalidBots [531-542], UpdateMacroWaypoints [553-659], PropagateAnchorToFollowers [661-676], FindNearestNavPoint [678-686], FindNearestChokepoint [688-703], RebuildHierarchy [2780-2797] (stub), GetVIPController [705-726], FindBossPawn [728-749], GetActiveBoss [2808-2813] (stub), CacheHumans [2799-2803], CacheHumanPositions [2820-2836] | @SYS-MUT-PLATOON | P3.4 |
| M5 | Succession & promotion | OnBotKilled [751-774], ComputeCommandScore [776-781], FindBestCandidate [783-796], FindExpendableMember [798-813], ProcessPromotionQueue [820-888], PromoteBot [891-895], HandleVIPSuccession [956-971], HandleFireteamCasualty [973-1016], DemoteGroupLeader [1018-1051], RequestLeaderDemotion [1053-1056], ConsolidateFireteams [1058-1073], PullBotFromNearestGroup [1075-1109], DissolveGroup [1111-1127], FindNearestEligibleGroup [1129-1152], ReassignBotToGroup [1154-1179], GetGroupLeader [1181-1187], GetGroupSize [1189-1195], GetFollowerIndex [1197-1214], GetFollowerBySlot [1614-1629] | @SYS-MUT-SUCCESSION | P3.5 |
| M6 | Wave & objective | PollWaveStart [352-366], CheckWave [1244-1295], SetHoldObjective [1297-1352], EndObjective [1354-1391], GetObjectiveLocation [2839-2850], NearestValidPoint [1394-1414] | @SYS-MUT-WAVE | P3.6 |
| M7 | Squad orders & slots | EnsureSquadOrderTable [1423-1437], InheritSquadOrder [1443-1482], SampleSquadSlots [1487-1587], ReleaseSquadSlots [1591-1610], GetSlotLocation [1657-1667], GetSquadPhase [1632-1640], IsSquadInObjectivePhase [1645-1653], EvaluateSquadPhase [1672-1729], HasSquadGoal [1734-1744], ReissueSquadOrder [1748-1763], GetBotObjective [1953-2004] | @SYS-MUT-ORDERS | P3.7 |
| M8 | Regroup | EvaluateRegroupEntries [1838-1902], GetSquadStartTime [1905-1913], MoveSquadMembers [1919-1951], FindNearestActiveLeader [1768-1811], CountZedsInRadius [1814-1828] | @SYS-MUT-REGROUP | P3.8 |
| M9 | Nav node blacklist | IsNodeBlocked [2011-2029], AddNodeBlock [2031-2065] | @SYS-MUT-NODEBLOCK | P3.9 |
| M10 | Ranged-heal cooldown bookkeeping | RegisterRangedHealTarget [900-920], IsRangedHealTargetOnCooldown [922-938], CleanupRangedHealCooldowns [940-954] | @SYS-MUT-HEALCOOL | P3.10 |
| M11 | Utilities | BroadcastSpottedEnemy [1220-1239], InitTraderList [2067-2088], FindWeaponByClass [2090-2105], CoordStr [1416-1419], DebugMessage [2535-2546], PMsg [2548-2557], DebugAI [2559-2588], EchelonLog [159-168] | @SYS-MUT-UTIL | P3.11 |

Structs in Mut: `FireteamData` [Mut:7-12], `NavNodeBlock` [Mut:16-21], `SquadOrder` [Mut:25-39], `PromotionRequest` [Mut:100-106], `CachedHumanInfo` [Mut:112-117]. Consts: 21 (P2 registry). Vars: 63.

### KF2BotsFollowNavBase.uc (Primary: Nav) -- tag prefix `@SYS-NAV-`

| # | System | Functions/states (each with line refs) | Tag | Doc |
|---|---|---|---|---|
| N1 | Episode control | FollowStart [198-210], FollowSetLeader [212-219], FollowSetSlot [223-227], FollowGetOrderAnchor [232-236], FollowResetEpisode [238-261], FollowInvalidateRoute [263-271], FollowSlotPhase [280-283], FollowScheduleWatchdog [285-295], FollowWatchdogBegin [297-301] | @SYS-NAV-EPISODE | P5.1 |
| N2 | Watchdog & dispatch | FollowCheckExit [308-311] (overridden [Logic:839-873]), FollowWatchdog [318-410], FollowRequestDispatch [416-434], FollowOnGaveUp [1216-1219], GiveUpStep (substate label of FollowingLeader [Nav:1411], body [Nav:1411-1417]) | @SYS-NAV-WATCHDOG | P5.2 |
| N3 | Leader tracking & reachability | FollowRefreshLeader [442-507], FollowGetArrivalRadius [517-527], FollowEvalArrived [531-580], FollowCheckReachable [587-640] | @SYS-NAV-LEADER | P5.3 |
| N4 | Path build & node walking | FollowBuildPath [645-688], FollowGetNextNode [692-721], FollowOnMoveBegin [813-835], FollowOnMoveEnd [837-853], FollowOnNodeMoveEnd [855-890] | @SYS-NAV-PATH | P5.4 |
| N5 | Decision engine | FollowDecide [727-807] | @SYS-NAV-DECIDE | P5.5 |
| N6 | Stuck & wall escape | FollowGuessStuckCause [896-910], FollowOnStuck [915-959], FollowTryBlockNode [965-968], FollowSetWallEscape [1032-1049] | @SYS-NAV-STUCK | P5.6 |
| N7 | Bump/yield/fail handling | FollowOwnsEvents [974-977], FollowHandleHitWall [981-1025], FollowIsFriendly [1051-1066], FollowShouldYieldTo [1071-1089], FollowHandleBump [1092-1121], FollowHandleMoveUnreachable [1123-1146], FollowComputeYieldPoint [1148-1192], NotifyHitWall [1225-1232], NotifyBump [1234-1241], MoveUnreachable [1243-1251] | @SYS-NAV-HANDLE | P5.7 |
| N8 | Status & hub reporting | FollowSetStatus [1198-1206], FollowNotifyHub [1209-1212] (override [Base:1287-1312]) | @SYS-NAV-STATUS | P5.8 |
| N9 | States | FollowingLeader [1257-1418] (substates: WaitStep [1342-1344], HoldStep [1346-1352], DirectMove [1354-1371], PathMove [1373-1384], EscapeStep [1386-1396], YieldStep [1398-1409], GiveUpStep [1411-1417]), FollowingLeaderBasic [1427-1491] | @SYS-NAV-STATE | P5.9 |
| N10 | Enums & config | EFollowAction [35-44], EFollowStatus [46-54], defaultproperties [1494-1552] (97 vars; bEnableAdvancedLocomotion [59], default true [1496]) | @SYS-NAV-CONFIG | P5.10 |

### KF2BotBase.uc (Primary: Base) -- tag prefix `@SYS-BASE-`

| # | System | Functions (each with line refs) | Tag | Doc |
|---|---|---|---|---|
| B1 | Bot boot & restart | PreBeginPlay [405-460], Destroyed [462-471], InitPlayerReplicationInfo [473-514], GiveWeaponDef [516-532], Restart [534-625], ValidateAndNudgeSpawn [2165-2182], IsOnWalkableFloor [2184-2189], EchelonLog [2484-2495] | @SYS-BASE-BOOT | P4.1 |
| B2 | Perception & enemy selection | SeePlayer [637-643], SeeMonster [645-651], EyeSightCheck [761-777], TargetLowHealth [727-759], PickNextEnemy [779-803], SetEnemy [805-856], GetEnemyThreat [858-876], NotifyTakeHit [627-635], NotifyBump [653], NotifyHitWall [1749], HearNoise [4141-4170], IsHostileZed [3628-3633] | @SYS-BASE-PERCEPT | P4.2 |
| B3 | Combat firing & aim | FireWeaponAt [881-932], GetAdjustedAimFor [1055-1080], GetPlayerViewPoint [1082-1096], NeedToTurn [1740-1747], StopAdjusting [1733-1738], IsMeleeOnly [2309-2313], ApplyBreathing [4580-4583], SimulateBashHit [1002-1033] | @SYS-BASE-FIRE | P4.3 |
| B4 | Move abstraction (intent layer) | MoveToX [1098-1115], MoveTowardX [1117-1144], StrafeTowardPoint [1146-1174], GetMoveDirection [1176-1192], ProcessMoveTo [1194-1217], ProcessMoveToward [1219-1247], AbortMove [1249-1256], CheckBlockedPath [1258-1280], FollowNotifyHub [1287-1312], FollowOnGaveUp [1317-1320], Tick [1322-1461], FinishedMove [1811-1814], PickFavorite [1816-1838], PickCombatStyle [2123-2159] | @SYS-BASE-MOVE | P4.4 |
| B5 | Path building (legacy non-nav) | BuildPathToward [1496-1573], BuildPathTo [1575-1652], BuildRandomPath [1654-1731], MarkDoorPath [1463-1494] | @SYS-BASE-PATH | P4.5 |
| B6 | Shopping & economy | SwitchToBestWeapon [1045-1053], SellWeapon [1840-1882], GetBestBuy [1884-1937], ProcessPurchase [1939-2111], NotifyAddInventory [2113-2121], DonateMoney [1040-1043] | @SYS-BASE-SHOP | P4.6 |
| B7 | Objective & hazard | CheckObjectiveHazard [2318-2361], GetObjectiveLocation [2440-2461], IsBossWaveActive [2463-2474], GetActiveBoss [2476-2479], TryBreakFree [945-996], ForceBreakGrapple [2375-2412] | @SYS-BASE-OBJ | P4.7 |
| B8 | Zed counting & retreat gates | CountNearbyZeds [2226-2245], CountNearbyZedsCached [3565-3581], RefreshSquadZedCache [3584-3608], AreZedsNear [2255-2270], HeavyZedWithin [2275-2291], ShouldTacticalRetreat [2293-2307], GetWaveMomentum [4566-4572], ExceedsRetreatZedCount [4574-4578], UpdateHoldAreaDrift [4585-4597], IsHeavyZedPawn [4181-4186], IsRetreatSafe [3004-3021] | @SYS-BASE-ZEDS | P4.8 |
| B9 | Rank/role system (SL/LT/Captain) | EBotRank [14-20], SetBotRank [3223-3227], GetRankName [3086-3100], UpdateRoleNameTag [3104-3124], RefreshRoleNameTag [3132-3176], SeedGruntGates [3178-3183], ArmRankTimers [3185-3203], ClearRankTimers [3066-3083], SLDecisionLoop [2627-2680], LTDispatchLoop [2684-2687] (stub), CaptainPathLoop [2691-2694] (stub), StartSLLoop [3205-3209], StartLTLoop [3211-3215], StartCaptainLoop [3217-3221], IssueCommand [2617-2622] | @SYS-BASE-RANK | P4.9 |
| B10 | Formation & slot math | ScanRoomForFormation [2702-2803], DeferredFormationScan [2805-2809], GetFormationBase [2813-2840], ComputeSlotOffset [2842-2889], ComputeFormationOffset [2191-2219], ValidateOffsetTarget [2955-2971], AssignSquadSlots [3667-3677], IsDirClearCached [2981-3002], RequestRerouteWithBlock [2973-2979] | @SYS-BASE-FORM | P4.10 |
| B11 | Line focus & overwatch | SyncLineFocus [2893-2936], HasOwnFireLine [2938-2951], NotifyBlockedShooter [3234-3256], ToggleOverwatchPhase [3638-3651], BroadcastOverwatchState [3654-3664], ReceiveOverwatchState [3762-3769], UpdateOverwatchTimer [3680-3714], CheckOverwatchStall [3717-3759], IsOverwatchStuck [3772-3775], UpdateOverwatchMovement [3778-3856], OnBreakLoseComplete [3859-3868], UpdateSectorWatch [3873-3914] | @SYS-BASE-OVERWATCH | P4.11 |
| B12 | CQB & cover crouch | HandleCQBProximity [3919-3970], SetSquadCrouchHold [3023-3027], ClearSquadCrouchHold [3029-3032], HoldAndCrouch [3034-3038], TryIssueSafeAnchor [3040-3050], ApplySquadCrouchHold [3052-3062], ApplyCrouch [3620-3626], UpdateCoverCrouch [4043-4059] | @SYS-BASE-CQB | P4.12 |
| B13 | Grunt rescue & combat lock | OnGruntGrabbed [3977-4018], BeginRescue [4023-4036], IsGruntCombatLocked [4066-4071], GruntOnSight [4076-4086], GruntEnterCombat [4091-4103], GruntPickCombatStyle [4108-4135] | @SYS-BASE-GRUNT | P4.13 |
| B14 | Panic broadcast | UpdatePanicBroadcast [4188-4203], ReceivePanic [4205-4210], ApplyPanicVariance [4212-4225] | @SYS-BASE-PANIC | P4.14 |
| B15 | Reload drift | IsReloading [4229-4235], HandleReloadDrift [4237-4285], ReceiveReloadDrift [4287-4309], OnReloadDriftAnchor [4311-4316], OnReloadComplete [4318-4322], TrackReloadState [4324-4333] | @SYS-BASE-RELOAD | P4.15 |
| B16 | Lt human bounding | StartLtHumanBounding [4337-4340], BeginLtHumanBounding [4342-4348], LtHumanBoundLoop [4350-4415] | @SYS-BASE-LTBOUND | P4.16 |
| B17 | Wedge | ReceiveWedgeOrder [4417-4434], UpdateWedgeMode [4436-4443], ClearWedge [4445-4460], ComputeWedgeOffset [4462-4486], ApplyWedgeTarget [4488-4497] | @SYS-BASE-WEDGE | P4.17 |
| B18 | Emote echo | StartEmoteEchoTimer [4501-4504], BeginEmoteEcho [4506-4509], CheckEmoteEcho [4511-4543], PlayBotEmote [4545-4557], ClearEmoteFlag [4559-4562] | @SYS-BASE-EMOTE | P4.18 |
| B19 | Weapon & grenade | ShouldReload [3259-3270], GetWeaponEffectiveRangeUU [3276-3297], IsInEffectiveRange [3299-3320], CloseToEffectiveRange [3322-3340], CheckWeaponReequip [3343-3375], ShouldThrowGrenade [3378-3420], TryThrowGrenade [3422-3454], SLGrenadeCheck [3456-3476], SLGrenadeLOSPhase [3478-3516], ClearGrenadeSignal [3518-3523], HandleWeaponManagement [3526-3562] | @SYS-BASE-WEAPON | P4.19 |
| B20 | Audit (rate-limited logging) | AuditRateLimit [2499-2524], AuditStateEntry [2557-2566], AuditStateExit [2568-2586], AuditGoalLog [2591-2609], FollowGetOrderAnchor [2530-2550] (override of [Nav:232-236]) | @SYS-BASE-AUDIT | P4.20 |
| B21 | Heal capability queries | CanHealOthers [2425-2428], IsHealLockedOut [2430-2433], ShouldAbortRetreat [2435-2438], IsBotAlive [2420-2423], EnemyChanged [1035-1038] | @SYS-BASE-HEALQ | P4.21 |

Struct: `FRouteDoorBlockade` [Base:4-8]. Enum: `EBotRank` [14-20]. Consts: 91 (P2 registry). Vars: 217. Events: NotifyBump [653], NotifyHitWall [1749], HearNoise [4141-4170]. defaultproperties [4601-4615].

### KF2BotLogic.uc (Primary: Logic) -- tag prefix `@SYS-LOGIC-`

| # | System | Functions/events (each with line refs) | Tag | Doc |
|---|---|---|---|---|
| L1 | Healing decisions & pacing | CheckShouldHealMate [4-115], CheckMedicGunHeal [117-200], CheckShouldSelfHeal [202-259], CanAffordHeal [521-528], HealFail [532-537], HealSuccess [541-548], VerifyWeapon [553-567], HealTimeOut [569-572] (legacy stub) | @SYS-LOGIC-HEAL | P4.22 |
| L2 | Watchdogs | IdleWatchdogTimer [639-643], IdleWatchdog [645-805], PromotionGapTimer [508-516], GruntDecisionTimer [595-629], CaptainPathTimer [809-816] (placeholder), ProcessOverwatchPhase [821-832] | @SYS-LOGIC-WATCHDOG | P4.23 |
| L3 | Grunt movement intents | CheckGrabbed [304-318], UpdateGruntOffset [327-465], ApplyZStep [476-496], RequestReroute [499-502], ConsumePathToken [577-590] | @SYS-LOGIC-GRUNTMOVE | P4.24 |
| L4 | Move evaluation (leader/follower) | EvaluateLeaderMove [1205-1211], EvaluateFollowerMove [1213-1267], EvaluateSquadTether [1169-1194], IsAnchorValid [1196-1203], MoveTowardGoal [1269-1286], UpdateCQBFormation [1288-1308], UpdatePillarOfSaltTracking [1310-1363], ExecuteCampState [1365-1371], ResetStuckState [1373-1377], FollowCheckExit [839-873] (override of [Nav:308-311]) | @SYS-LOGIC-MOVEVAL | P4.25 |
| L5 | Death & damage | PawnDied [875-914], ActivatePlayerDiedSequenceEvents [916-952], NotifyKilled [1156-1167], ReplicatedEvent [1057-1082], FinishObjective [1084-1092] | @SYS-LOGIC-DEATH | P4.26 |
| L6 | Utility | ShouldNadeEnemies [261-302], FindCollectable [1004-1043], GetPointNear [1094-1154], PickRetreatMove [954-1002], NotifyJumpApex [1045-1049], GetAIInfo [1051-1055] | @SYS-LOGIC-UTIL | P4.27 |

Events: `ReplicatedEvent` [1057-1082], `PawnDied` [875-914]. 38 functions total.

### KF2Bot.uc (Primary: Bot) -- tag prefix `@SYS-BOT-`

| # | System | States (each with line refs) | Tag | Doc |
|---|---|---|---|---|
| K1 | Decision hub | state PickNextMove [4-259] (P1-P10 pipeline) | @SYS-BOT-HUB | P4.28 |
| K2 | Movement states | state Roaming [261-450] (embedded: EnemyChanged [419-423], DonateMoney [425-434], substate Camp [444-449]); state Camp [452-483]; state DonatingMoney [1778-1911] (substate MoneyToss); state GetItem [1718-1776] | @SYS-BOT-MOVE | P4.29 |
| K3 | Combat states | state DoObjective [485-603] (extends Roaming), state FightEnemy [605-886] (events BeginState [607-615], EndState [617-629], Timer [633-682], NotifyBump [855-875]), state TacticalRetreat [888-952], state BreakLose [954-1062], state Hunting [1064-1190], state GrenadeTarget [1538-1576] (unreachable from hub -- see Appendix C) | @SYS-BOT-COMBAT | P4.30 |
| K4 | Healing states | state HealingSelf [1192-1294], state HealOther [1295-1413], state HealRanged [1415-1537] | @SYS-BOT-HEAL | P4.31 |
| K5 | Economy & objective states | state GoShopping [1578-1716] (events incl. NotifyBump [1697-1706]) | @SYS-BOT-SHOP | P4.32 |
| K6 | Terminal & cosmetic states | state Dead [1913-1946], state IsRagdolled [1948-1970], state VictoryDance [1972-2075] | @SYS-BOT-TERM | P4.33 |

41 functions, 37 events, 18 states (state index in 0.4; all events listed in P4.28-P4.33 technical references and in 0.7).

### PART 6 -- Cross-file boundaries -- tag `@SYS-P6-BOUNDARY`

| # | Section | Content | Tag | Doc |
|---|---|---|---|---|
| 6.1 | Cross-file call matrix | Verified boundary call chains across all 5 mod files (FollowStart, FollowSetSlot, FollowNotifyHub, FollowCheckExit, RegisterBot, ...) | @SYS-P6-BOUNDARY | PART 6 |
| 6.2 | Single-writer rules | Owner/writer + readers + rule for every piece of shared state (FollowStatus, FollowLeaderCtrl, FollowSlotIndex/Count, hub intent fields, SquadOrders/Fireteams/ActiveBots, hub-contact stamps, NextShoppingTime, bEnableAdvancedLocomotion) | @SYS-P6-BOUNDARY | PART 6 |
| 6.3 | Intent channel (hub to locomotion) | Command calls, hub intent fields (the only mailbox), and the status callback path | @SYS-P6-BOUNDARY | PART 6 |
| 6.4 | Hub re-evaluation funnel | PickCombatStyle funnel, terminal lock, follower-state early-return, and why the hub never yanks a following bot back | @SYS-P6-BOUNDARY | PART 6 |

## 0.4 State index (20 states + 8 substates)

Enter/exit facts are from verified `GotoState` call sites (all single-quoted in this codebase) and state declarations.

| State | Declared | Entered via (verified call sites) | Exits to (verified) | FLOW |
|---|---|---|---|---|
| PickNextMove (hub) | [Bot:4-259] | GotoState('PickNextMove') from PickCombatStyle [Base:2157]; IdleWatchdog escalation [Logic:799]; ReplicatedEvent EndRagdollMove [Logic:1074] | GotoState('VictoryDance') [Bot:30,35]; 'HealingSelf' [Bot:49]; 'TacticalRetreat' [Bot:59]; 'GoShopping' [Bot:80,247]; 'Hunting' [Bot:89,227,240]; 'DoObjective' [Bot:188]; 'HealRanged' [Bot:200]; 'HealOther' [Bot:205]; 'FightEnemy' [Bot:222]; ExecuteCampState->'Camp' [Logic:1369] (via P10 [Bot:251-252]) | @FLOW-HUB |
| Roaming | [Bot:261-450] | Default AIController start state (Restart ends in 'Roaming' via [Base:596] GotoState('Roaming')); states with no explicit GotoState fall back here via PickCombatStyle fallback [Base:2157] -> hub -> P10 | PickCombatStyle [Base:2123-2159] -> GotoState('PickNextMove') [Base:2157]; embedded DonateMoney -> 'DonatingMoney' [Bot:431] | @FLOW-ROAMING |
| Camp (substate of Roaming) | [Bot:444-449] (the Camp: label block inside Roaming [Bot:444-450], not the standalone state Camp [Bot:452-483]) | Camp: label in Roaming (PickStyle picks camp when slot phase holds) | Sleep loop, re-PickCombatStyle [Bot:448] | @FLOW-ROAMING |
| Camp (standalone) | [Bot:452-483] | ExecuteCampState [Logic:1365-1371] GotoState('Camp') [Logic:1369] | Sleep(1.0+FRand) then PickCombatStyle [Bot:469-481] -> hub | @FLOW-CAMP |
| DoObjective (extends Roaming) | [Bot:485-603] | Hub P5 [Bot:188]; FollowCheckExit sets FollowExitState='DoObjective' [Logic:864] then GotoState(FollowExitState) [Nav:1311,1443] | PickCombatStyle -> hub | @FLOW-DOOBJ |
| FightEnemy | [Bot:605-886] | Hub P7 [Bot:222]; Tick auto-combat [Base:1349]; CheckObjectiveHazard [Base:2333,2351]; SyncLineFocus [Base:2913]; GruntEnterCombat [Base:4103] | GotoState('VictoryDance') [Bot:691,705]; PickCombatStyle -> hub | @FLOW-FIGHT |
| TacticalRetreat | [Bot:888-952] | Hub P4 [Bot:59] | PickCombatStyle -> hub (P4 re-checks) | @FLOW-RETREAT |
| BreakLose | [Bot:954-1062] | CheckGrabbed [Logic:309,339] | PickCombatStyle -> hub | @FLOW-BREAKLOSE |
| Hunting | [Bot:1064-1190] | Hub P7 no-LOS [Bot:227], P8.5 [Bot:240], P4.5 B2 [Bot:89]; Tick [Base:1354] | PickCombatStyle -> hub; sets Enemy -> FightEnemy via hub | @FLOW-HUNT |
| HealingSelf | [Bot:1192-1294] | Hub P3 [Bot:49] | EndState -> hub via PickCombatStyle | @FLOW-HEALSELF |
| HealOther | [Bot:1295-1413] | Hub P6 [Bot:205] | EndState -> hub | @FLOW-HEALOTHER |
| HealRanged | [Bot:1415-1537] | Hub P6 [Bot:200] | EndState -> hub | @FLOW-HEALRANGED |
| GrenadeTarget | [Bot:1538-1576] | No verified hub/state call site found (Appendix D open question) | None verified | (no FLOW) |
| GoShopping | [Bot:1578-1716] | Hub P9 [Bot:247], P4.5 B1 [Bot:80]; FollowCheckExit sets FollowExitState='GoShopping' [Logic:848] then GotoState(FollowExitState) [Nav:1311,1443] | GotoState('VictoryDance','MoveTaunt') [Bot:1688]; PickCombatStyle -> hub | @FLOW-SHOP |
| GetItem | [Bot:1718-1776] | No explicit GotoState found in 5 files; entered via native pickup path (SDK behaviour not verified -- see Appendix D) | PickCombatStyle -> hub | @FLOW-GETITEM |
| DonatingMoney | [Bot:1778-1911] | Roaming DonateMoney [Bot:431]; GotoState('DonatingMoney','MoneyToss') [Bot:1819] | PickCombatStyle -> hub | @FLOW-DOSHDROP |
| Dead | [Bot:1913-1946] | Mut RestartBot [Mut:2475]; PawnDied [Logic:912] | None (terminal) | (no FLOW) |
| IsRagdolled | [Bot:1948-1970] | ReplicatedEvent [Logic:1063] | 'VictoryDance' [Logic:1070] or 'PickNextMove' [Logic:1074] | (no FLOW) |
| VictoryDance | [Bot:1972-2075] | Hub P1 [Bot:30,35]; FightEnemy boss/dance [Bot:691,705]; PickCombatStyle terminal lock [Base:2140]; GoShopping taunt [Bot:1688]; NotifyKilled boss [Logic:1163]; ReplicatedEvent [Logic:1070]; re-dance GotoState('VictoryDance','Begin') [Bot:2019] | Terminal (self-reentry at [Bot:2019]) | (no FLOW) |
| FollowingLeader (Nav) | [Nav:1257-1418] | FollowStart [Nav:204]; FollowWatchdog re-entry [Nav:344,433]; EvaluateFollowerMove (flag on) [Logic:1213-1267] | FollowCheckExit override -> 'GoShopping'/'DoObjective' [Logic:839-873]; GotoState('FollowingLeaderBasic') [Nav:208] (flag off) | @FLOW-FOLLOW |
| FollowingLeaderBasic (Nav) | [Nav:1427-1491] | FollowStart flag-off path [Nav:208] | FollowCheckExit | @FLOW-FOLLOW |

Substates of FollowingLeader (labels, by label line): Begin [Nav:1285], Dispatch [Nav:1288], WaitStep [Nav:1342], HoldStep [Nav:1346], DirectMove [Nav:1354], PathMove [Nav:1373], EscapeStep [Nav:1386], YieldStep [Nav:1398], GiveUpStep [Nav:1411].

## 0.5 Lookup table -- "I want to change X, where do I go?"

| # | I want to change... | Go to | Citation |
|---|---|---|---|
| 1 | Bot count at spawn | `PostBeginPlay` (NumBots default 7) + `defaultproperties` comment says 6 -- see Appendix C | [Mut:170-269], [Mut:3031-3037] |
| 2 | Bot perk level cap | `PostBeginPlay` (`BotMaxPerkLv = 25`) | [Mut:170-269] |
| 3 | Bot damage scale | `PostBeginPlay` (`BotsDamageScale = 1.0`) | [Mut:170-269] |
| 4 | Zed spawn scaling | `PostBeginPlay` (`ZedCountScaling = 0.2`) | [Mut:170-269] |
| 5 | BreakLose failsafe (zed cap / delay) | `PostBeginPlay` (`MaxZedsForFailsafe = 3`, `FailsafeActivationDelay = 3.0`) + `BreakLose` state | [Mut:170-269], [Bot:954-1062] |
| 6 | Cylinder-heal gate (radius / height / min health) | `PostBeginPlay` (`HealCylinderRadius = 400.0`, `HealCylinderHeight = 300.0`, `HealMinHealthPct = 60.0`) + `CheckShouldHealMate` | [Mut:170-269], [Logic:4-115] |
| 7 | Perk gacha cap (bots per perk) | `PostBeginPlay` (`MaxBotsPerPerk = 2`) + `PickBotPerk` | [Mut:170-269], [Mut:2325-2356] |
| 8 | Allowed perk pool | `PickBotPerk` reads `AllowedPerks`; empty pool --> `ResetPerkPool` / `PickFallbackPerk` | [Mut:2325-2356], [Mut:2292-2314] |
| 9 | Exclude Berserker/Zerker from fallback pool | `PickFallbackPerk` (`bNoZerkerBots` skip) | [Mut:2252-2265] |
| 10 | Wave poll / wave check cadence | `SetTimer(1.0, true, 'PollWaveStart')` [Mut:262]; `SetTimer(0.1, true, 'CheckWave')` in `MatchStarting` | [Mut:307] |
| 11 | Hierarchy rebuild / human cache cadence | `SetTimer(3.0, true, 'RebuildHierarchy')`, `SetTimer(3.0, true, 'CacheHumans')` | [Mut:266-267] |
| 12 | Group sizing policy | consts `MIN_GROUPS [Mut:64]`, `MAX_GROUPS [Mut:65]`, `BOTS_PER_GROUP_TARGET [Mut:66]` + `DetermineGroupCount` | [Mut:544-551] |
| 13 | VIP escort min size / group dissolve size | `VIP_ESCORT_MIN_SIZE [Mut:67]`, `GROUP_DISSOLVE_SIZE [Mut:68]` | [Mut:956-1016] |
| 14 | Macro waypoint geometry (vanguard/rearguard/chokepoint offsets, search radius) | consts [Mut:69-72] + `UpdateMacroWaypoints` | [Mut:553-659] |
| 15 | Waypoint update interval | `MACRO_WAYPOINT_INTERVAL [Mut:73]` (3.0s) | [Mut:553-659] |
| 16 | Squad slot ring (N cap, R0, z filter) | `SampleSquadSlots` (N capped 4, R0 = 96.0, dz < 50u) | [Mut:1487-1587] |
| 17 | Squad phase goal radius / phase transitions | `EvaluateSquadPhase` (`GoalRadiusSq = 9216.0`), `GetSquadPhase`, `HasSquadGoal`, `ReissueSquadOrder` | [Mut:1672-1729] |
| 18 | Regroup entry gates (duration / hard timeout / scan radius) | `EvaluateRegroupEntries` + consts `REGROUP_DURATION [Mut:82]`, `REGROUP_HARD_TIMEOUT [Mut:83]`, `REGROUP_SCAN_RADIUS [Mut:86]` | [Mut:1838-1902] |
| 19 | Squad regroup movement | `MoveSquadMembers` | [Mut:1919-1951] |
| 20 | Objective bail cooldown (hub P5 / DoObjective) | `OBJ_BAIL_COOLDOWN [Mut:75]` / `[Base:69]` (both 8.0) | [Bot:181-189], [Bot:485-603] |
| 21 | Door node blocking (8s blocks) | `AddNodeBlock` / `IsNodeBlocked` | [Mut:2031-2065], [Mut:2011-2029] |
| 22 | Ranged-heal per-target cooldown (25s) | `RegisterRangedHealTarget` (25.0s window) / `IsRangedHealTargetOnCooldown` / `CleanupRangedHealCooldowns` | [Mut:900-938] |
| 23 | Promotion policy (max per tick, wave>5 boost) | `ProcessPromotionQueue` (1 per tick, 2 if `WaveNum > 5`) | [Mut:820-888] |
| 24 | Boss detection threshold | `FindBossPawn` (`Health > 5000`) | [Mut:728-749] |
| 25 | Bot name pool | `PickCustomBotName` | [Mut:2135-2152] |
| 26 | Bot character/architecture assignment | `InitBotCharacter` + `RestartBot` (`SetCharacterArch` after `SetTeam`) | [Mut:2160-2246], [Mut:2433-2533] |
| 27 | Emote pool | `InitEmotes`, `PickRandEmote`, `MaxEmoteCount = -1` | [Mut:2745-2763], [Mut:3036] |
| 28 | Victory-dance gate (mutator side) | `ShouldDoVictoryDance` (bot-side roll in `FightEnemy` `NotifyKilled`) | [Mut:2765-2775], [Bot:691-705] |
| 29 | Follow episode start / flag | `FollowStart` + `bEnableAdvancedLocomotion` (flag default true) | [Nav:198-210], [Nav:58], [Nav:1496] |
| 30 | Follow grace time | `GraceTime = 2.0` | [Nav:1494-1552] |
| 31 | Leader teleport detection | `TeleportDist = 1200.0`, `TeleportSpeed = 4000.0` + `FollowRefreshLeader` | [Nav:442-507] |
| 32 | Slot geometry (ring base / step) | `BaseOffset = 96.0`, `RingStep = 64.0` + `FollowSlotPhase` | [Nav:280-282], [Nav:1494-1552] |
| 33 | Follow watchdog cadence | `WatchdogPeriod = 0.25` + `FollowScheduleWatchdog` / `FollowWatchdog` | [Nav:285-294], [Nav:318-410] |
| 34 | Arrival test (margin / z tolerance) | `FollowEvalArrived` + `ResumeMargin = 96.0`, `ZTolerance = 128.0` | [Nav:531-580] |
| 35 | Path build + token budget | `FollowBuildPath` (token spent before call) + `ConsumePathToken` (10 paths/sec) | [Nav:645-688], [Logic:577-590] |
| 36 | Stuck detection (same-node limit, window) | `FollowOnNodeMoveEnd` + `SameNodeLimit = 20`, `StuckWindow = 1.5`, `StuckMinMove = 32.0` | [Nav:855-890] |
| 37 | Wall escape (hit threshold, escape duration) | `FollowHandleHitWall` + `WallHitThreshold = 5`, `EscapeDuration = 0.8` | [Nav:981-1030] |
| 38 | Yield-to-friend behaviour (dist / hold / timeout) | `FollowComputeYieldPoint` + `YieldDist = 64.0`, `YieldHold = 0.3`, `YieldTimeout = 0.75` | [Nav:1148-1196] |
| 39 | Retry / give-up limits | `RetriesBlockAt = 5`, `RetriesGiveUpAt = 10` + `FollowDecide` steps 4/5 | [Nav:727-811] |
| 40 | Follow exit states (trader open / SYG far) | `FollowCheckExit` (BotLogic override); default `FollowExitState = "PickNextMove"` | [Logic:839-873], [Nav:1497] |
| 41 | Hub heal triage interval | `TRIAGE_INTERVAL [Base:76]` (2.0s) in hub P6 | [Bot:193-208] |
| 42 | Combat leash (drop distance) | `LEASH_DROP_DIST_SQ [Base:90]` in hub P7 | [Bot:210-229] |
| 43 | Hunt threshold / scan radius / global zed radius | `HUNT_ZED_THRESHOLD [Base:71]`, `HUNT_SCAN_RADIUS [Base:72]`, `GLOBAL_ZED_RADIUS [Base:73]` | [Bot:1064-1190], [Bot:235-241] |
| 44 | Retreat hysteresis (radius / trigger / clear) | `RETREAT_ZED_RADIUS [Base:64]`, `RETREAT_ZED_TRIGGER_COUNT [Base:65]`, `RETREAT_ZED_CLEAR_COUNT [Base:66]` + `TacticalRetreat` state | [Bot:888-952] |
| 45 | Self-heal pacing (15s syringe / 30s heal) | `CheckShouldSelfHeal` | [Logic:202-259] |
| 46 | Heal pacing stamps (write-on-success) | `HealSuccess` (only writer) | [Logic:541-548] |
| 47 | Mate-heal need % / VIP triage gate | `HEAL_MAX_NEED_PCT [Base:84]`, `VIP_TRIAGE_GATE_PCT [Base:77]` | [Logic:4-115] |
| 48 | Medic-gun heal (1800u scan, 25s cooldown) | `CheckMedicGunHeal` | [Logic:117-200] |
| 49 | Trader retry backoff / give-up | `TRADER_MAX_RETRIES [Base:99]`, `TRADER_GIVEUP_COOLDOWN [Base:100]` + `GoShopping` (Loophole 6) | [Bot:1578-1716] |
| 50 | SYG (objective) distance | `SYG_DISTANCE_SQ [Base:61]` (1000000.0) | [Bot:181-189], [Logic:839-873] |
| 51 | Follower tether radius | `FOLLOWER_DRIFT_SQ [Base:68]` (2500000) | [Bot:232-233] |
| 52 | Ghost-door / welded-door detection | `UpdatePillarOfSaltTracking` + `STUCK_SAMPLE_INTERVAL [Base:49]`, `DOOR_CHECK_RADIUS [Base:51]` | [Logic:1310-1363] |
| 53 | Idle watchdog (softlock escalation) | `IdleWatchdog` + `AUDIT_WD_PERIOD [Base:107]`, armed [Base:437] | [Logic:645-805] |
| 54 | Grunt decision cadence (1.5s) | `GruntDecisionTimer` (armed [Base:452]) | [Logic:595-629] |
| 55 | Panic variance (multiplier / scatter) | `PANIC_MULT [Base:360]` etc. + `UpdatePanicBroadcast` | [Base:4188-4203] |
| 56 | Emote echo (chance / cooldown) | `EMOTE_CHANCE [Base:372]`, `EMOTE_ROLL_COOLDOWN [Base:373]` + `CheckEmoteEcho` | [Base:4511-4543] |
| 57 | Dosh money drop (toss velocity / amount cap) | `DropMoney` (`TossVel * 1.6`, `Amount = Min(50, int(Score))`) + `MoneyToss` | [Bot:1778-1911] |
| 58 | Victory-dance cap (25s) | `VictoryDance` state `Begin` | [Bot:1972-2075] |
| 59 | Death handling (seq events, scoreboard) | `PawnDied` + `Dead` state (`ReassertScoreboardFlags` after 1.0s) | [Logic:875-914], [Bot:1913-1946] |
| 60 | Bot rank assignment | `SetBotRank` + `EBotRank` enum | [Base:3223-3227], [Base:14-20] |
| 61 | Squad-leader decision loop (SL) | `SLDecisionLoop`, started via `StartSLLoop` | [Base:2627-2680], [Base:3205-3209] |
| 62 | Formation scan | `ScanRoomForFormation` + `FORM_SCAN_DIST [Base:262]`, `FORM_LINE_DIST [Base:263]` | [Base:2702-2803] |
| 63 | Weapon effective ranges (shotgun / flamethrower / default) | `defaultproperties` (`ShotgunEffectiveRangeUU = 1100.0`, `FlamethrowerEffectiveRangeUU = 700.0`, `DefaultWeaponEffectiveRangeUU = 5000.0`) | [Base:4601-4615] |
| 64 | Grenade throwing policy | `ShouldThrowGrenade` / `TryThrowGrenade` / `SLGrenadeCheck` | [Base:3378-3454] |
| 65 | Overwatch phase toggle | `ToggleOverwatchPhase` (bot side) + `ProcessOverwatchPhase` (5.0s timer, CAPTAIN only) | [Base:3638-3651], [Logic:821-832] |

## 0.6 Cross-reference index (who calls whom, across files)

| # | Producer (file) | Consumer (file) | Mechanism | Citation |
|---|---|---|---|---|
| 1 | Mut (platoon) | Nav (episode) | `SyncSquadLeaders` calls `FollowSetSlot` per follower | [Mut:511] --> [Nav:223-227] |
| 2 | Mut (boot) | Bot (state) | `RestartBot` sends new players to `Dead` | [Mut:2475] --> [Bot:1913-1946] |
| 3 | Nav (status) | BotBase (hub mailbox) | `FollowSetStatus` --> `FollowNotifyHub`; BotBase overrides `FollowNotifyHub` to route into hub | [Nav:1198-1207] --> [Nav:1209-1212] --> [Base:1287-1312] |
| 4 | Nav (gave-up) | BotBase | `FollowOnGaveUp` override | [Nav:1216-1219] --> [Base:1317-1320] |
| 5 | Nav (decide step 3) | BotBase | `FollowDecide` refreshes order anchor via `FollowGetOrderAnchor` override | [Nav:727-811] --> [Base:2530-2550] |
| 6 | BotLogic (exit) | Nav (states) | `FollowCheckExit` sets `FollowExitState` ('GoShopping' / 'DoObjective'); `FollowingLeader` / `FollowingLeaderBasic` call `GotoState(FollowExitState)` | [Logic:839-873] --> [Nav:1311], [Nav:1443] |
| 7 | Bot (hub P4.5) | BotLogic | leader camp --> `ExecuteCampState` --> `GotoState('Camp')` | [Bot:157-160] --> [Logic:1365-1371] |
| 8 | Mut (wave) | Bot (hub P5) + BotLogic (exit) | `bObjectiveActive` / objective data read by hub P5 and `FollowCheckExit` | [Mut:1244-1295] --> [Bot:181-189], [Logic:839-873] |
| 9 | Mut (node blocks) | Bot (DoObjective) | gate `mut.IsNodeBlocked`; blocks via `AddNodeBlock` | [Mut:2011-2029], [Mut:2031-2065] --> [Bot:485-603] |
| 10 | Mut (heal cooldowns) | BotLogic (triage) | `CheckMedicGunHeal` reads `IsRangedHealTargetOnCooldown`; `HealRanged` writes via `RegisterRangedHealTarget` | [Mut:900-938] --> [Logic:117-200], [Bot:1415-1537] |
| 11 | Mut (regroup) | Bot (hub P4.5) + BotLogic (watchdog) | `FindNearestActiveLeader` used by hub B3 branch and IdleWatchdog escalation; `ReassignBotToGroup` used by watchdog | [Mut:1768-1811], [Mut:1154-1179] --> [Bot:108], [Logic:645-805] |
| 12 | BotLogic (ghost door) | Mut (succession) | `UpdatePillarOfSaltTracking` calls `RequestLeaderDemotion` on real welded door | [Logic:1310-1363] --> [Mut:1053-1056] |
| 13 | BotBase (tick) | Bot (states) | `Tick` routes to `FightEnemy` / `Hunting` | [Base:1349], [Base:1354] --> [Bot:605-886], [Bot:1064-1190] |
| 14 | BotBase (combat entry) | Bot (FightEnemy) | `GruntEnterCombat` and `CheckObjectiveHazard` `GotoState('FightEnemy')` | [Base:4103], [Base:2333], [Base:2351] --> [Bot:605-886] |
| 15 | BotBase (fire line) | Bot (FightEnemy) | `SyncLineFocus` `GotoState('FightEnemy')` | [Base:2913] --> [Bot:605-886] |
| 16 | BotBase (combat style) | Bot (hub / terminal) | `PickCombatStyle`: terminal lock `GotoState('VictoryDance')` [Base:2140], fallback `GotoState('PickNextMove')` [Base:2157] | --> [Bot:1972-2075], [Bot:4-259] |
| 17 | BotBase (restart) | Bot (Roaming) | `Restart` `GotoState('Roaming')` | [Base:596] --> [Bot:261-450] |
| 18 | BotLogic (death) | Bot (Dead) | `PawnDied` `GotoState('Dead')` | [Logic:912] --> [Bot:1913-1946] |
| 19 | BotLogic (ragdoll) | Bot (IsRagdolled / VictoryDance / PickNextMove) | `ReplicatedEvent`: RagdollMove [Logic:1063], EndRagdollMove [Logic:1070], else [Logic:1074] | --> [Bot:1948-1970], [Bot:1972-2075], [Bot:4-259] |
| 20 | BotLogic (boss kill) | Bot (VictoryDance) | `NotifyKilled` boss --> `GotoState('VictoryDance')` | [Logic:1163] --> [Bot:1972-2075] |
| 21 | Bot (fight, boss kill) | Bot (VictoryDance) | `NotifyKilled` boss --> `GotoState('VictoryDance')` (state-internal) | [Bot:691], [Bot:705] |
| 22 | BotLogic (grapple) | Bot (BreakLose) | `CheckGrabbed` --> `GotoState('BreakLose')` | [Logic:309], [Logic:339] --> [Bot:954-1062] |
| 23 | BotLogic (watchdog) | Bot (hub) | IdleWatchdog escalation --> `GotoState('PickNextMove')` | [Logic:799] --> [Bot:4-259] |
| 24 | Bot (Roaming) | Bot (DonatingMoney) | embedded `DonateMoney` --> `GotoState('DonatingMoney')` | [Bot:431] --> [Bot:1778-1911] |
| 25 | Bot (DonatingMoney) | Bot (state re-entry) | `GotoState('DonatingMoney','MoneyToss')` | [Bot:1819] |
| 26 | Bot (GoShopping) | Bot (VictoryDance) | `GotoState('VictoryDance','MoveTaunt')` (rand roll) | [Bot:1688] |
| 27 | Mut (emote) | Bot (VictoryDance) | `PlayDance` uses `mut.PickRandEmote()` | [Bot:1972-2075] --> [Mut:2754-2763] |
| 28 | Nav (episode) | Nav (states) | `FollowStart` --> `FollowingLeader` (flag on) / `FollowingLeaderBasic` (flag off) | [Nav:204], [Nav:208] --> [Nav:1257-1424], [Nav:1427-1491] |
| 29 | Nav (dispatch) | Nav (states) | `FollowRequestDispatch` re-enters `FollowingLeader`/`Dispatch` | [Nav:344], [Nav:433] |
| 30 | Bot (hub P9 / P4.5) | Bot (GoShopping) | `GotoState('GoShopping')` from economy [Bot:247] and trader branch [Bot:80] | --> [Bot:1578-1716] |
| 31 | Bot (hub P1 terminal) | Bot (VictoryDance) | `bMatchIsOver` --> `GotoState('VictoryDance')` | [Bot:32-35] --> [Bot:1972-2075] |
| 32 | BotBase (audit) | Bot (all states) | `AuditStateEntry` / `AuditStateExit` called at every BeginState/EndState | [Base:2557-2586] --> all states in 0.4 |
| 33 | Bot (FinishedMove) | Bot (VictoryDance) | re-entrancy: `GotoState('VictoryDance','Begin')` -- see Appendix C/D | [Bot:2019] |
| 34 | Bot (HealRanged) | Mut (cooldown) | `mut.RegisterRangedHealTarget` after dart shot | [Bot:1415-1537] --> [Mut:900-920] |
| 35 | Mut (InitTraderList) | Bot (GoShopping / hub) | trader pawn list used by shopping gates | [Mut:2067-2088] --> [Bot:1578-1716] |
| 36 | BotLogic (self-promotion) | Mut (promotion) | `PromotionGapTimer` 10s failsafe | [Logic:508-516] --> [Mut:820-888] |
| 37 | Bot (Roaming) | BotBase (style) | embedded `EnemyChanged` --> `PickCombatStyle` | [Bot:419-423] --> [Base:2123-2159] |
| 38 | Bot (DonatingMoney) | BotBase (tick) | only state calling `global.Tick(Delta)` | [Bot:1796-1832] --> [Base:1322-1461] |

## 0.7 A-Z symbol index (complete: 943 symbols)

Generated from `_arch_work/symbols.json` (extracted from source; verify checks b/c). `file:line` points at the declaration line. `doc tag` = Part 0.3 system tag + part section.

| symbol | kind | file:line | doc section tag |
|---|---|---|---|
| _Separator1 | var | Mut:43 | P2 |
| _Separator2 | var | Mut:47 | P2 |
| _Separator3 | var | Mut:50 | P2 |
| _Separator4 | var | Mut:123 | P2 |
| _Separator5 | var | Mut:126 | P2 |
| _Separator6 | var | Mut:138 | P2 |
| _Separator7 | var | Mut:142 | P2 |
| AbortMove | function | Base:1249 | @SYS-BASE-MOVE / P4.4 |
| ActivatePlayerDiedSequenceEvents | function | Logic:916 | @SYS-LOGIC-DEATH / P4.26 |
| ActiveBots | var | Mut:54 | P2 |
| ActiveChat | var | Mut:53 | P2 |
| AddBot | function | Mut:2358 | @SYS-MUT-SPAWN / P3.2 |
| AddMutator | function | Mut:271 | @SYS-MUT-BOOT / P3.1 |
| AddNodeBlock | function | Mut:2031 | @SYS-MUT-NODEBLOCK / P3.9 |
| AlphaCommander | var | Mut:60 | P2 |
| Anchor | var | Mut:11 | P2 |
| ApplyBreathing | function | Base:4580 | @SYS-BASE-FIRE / P4.3 |
| ApplyCrouch | function | Base:3620 | @SYS-BASE-CQB / P4.12 |
| ApplyPanicVariance | function | Base:4212 | @SYS-BASE-PANIC / P4.14 |
| ApplySquadCrouchHold | function | Base:3052 | @SYS-BASE-CQB / P4.12 |
| ApplyWedgeTarget | function | Base:4488 | @SYS-BASE-WEDGE / P4.17 |
| ApplyZStep | function | Logic:476 | @SYS-LOGIC-GRUNTMOVE / P4.24 |
| AreZedsNear | function | Base:2255 | @SYS-BASE-ZEDS / P4.8 |
| ArmRankTimers | function | Base:3185 | @SYS-BASE-RANK / P4.9 |
| AssignedAnchor | var | Base:25 | P2 |
| AssignSquadSlots | function | Base:3667 | @SYS-BASE-FORM / P4.10 |
| AUDIT_ATTACH_RADIUS | const | Base:106 | P2 |
| AUDIT_HUB_TIMEOUT | const | Base:104 | P2 |
| AUDIT_IDLE_STUCK_DELTA | const | Base:105 | P2 |
| AUDIT_INTENT_TIMEOUT | const | Base:103 | P2 |
| AUDIT_WD_PERIOD | const | Base:107 | P2 |
| AUDIT_WD_STEP_COOLDOWN | const | Base:108 | P2 |
| AuditDwellTotal | var | Base:195 | P2 |
| AuditGoalLog | function | Base:2591 | @SYS-BASE-AUDIT / P4.20 |
| AuditLastLog_DWELLTOT | var | Base:200 | P2 |
| AuditLastLog_FOLLOWGATE | var | Base:198 | P2 |
| AuditLastLog_GEN | var | Base:199 | P2 |
| AuditLastLog_GOAL | var | Base:197 | P2 |
| AuditLastLog_STATE_EXIT | var | Base:196 | P2 |
| AuditRateLimit | function | Base:2499 | @SYS-BASE-AUDIT / P4.20 |
| AuditStateEntry | function | Base:2557 | @SYS-BASE-AUDIT / P4.20 |
| AuditStateEntryName | var | Base:194 | P2 |
| AuditStateEntryTime | var | Base:193 | P2 |
| AuditStateExit | function | Base:2568 | @SYS-BASE-AUDIT / P4.20 |
| AvailableBotNames | var | Mut:152 | P2 |
| BasePlayerName | var | Base:225 | P2 |
| bAttemptingUnweld | var | Base:40 | P2 |
| bBossKillVictory | var | Base:174 | P2 |
| bCachedHeavyZed | var | Base:183 | P2 |
| bChatterInit | var | Mut:122 | P2 |
| BeginEmoteEcho | function | Base:4506 | @SYS-BASE-EMOTE / P4.18 |
| BeginLtHumanBounding | function | Base:4342 | @SYS-BASE-LTBOUND / P4.16 |
| BeginRescue | function | Base:4023 | @SYS-BASE-GRUNT / P4.13 |
| BeginState | event | Bot:1066 | @SYS-BOT-COMBAT / P4.30 |
| BeginState | event | Bot:1196 | @SYS-BOT-COMBAT / P4.30 |
| BeginState | event | Bot:1299 | @SYS-BOT-COMBAT / P4.30 |
| BeginState | event | Bot:1419 | @SYS-BOT-COMBAT / P4.30 |
| BeginState | event | Bot:1540 | @SYS-BOT-COMBAT / P4.30 |
| BeginState | event | Bot:1580 | @SYS-BOT-COMBAT / P4.30 |
| BeginState | event | Bot:1720 | @SYS-BOT-COMBAT / P4.30 |
| BeginState | event | Bot:1780 | @SYS-BOT-COMBAT / P4.30 |
| BeginState | event | Bot:1918 | @SYS-BOT-COMBAT / P4.30 |
| BeginState | event | Bot:1953 | @SYS-BOT-COMBAT / P4.30 |
| BeginState | event | Bot:1976 | @SYS-BOT-COMBAT / P4.30 |
| BeginState | event | Bot:263 | @SYS-BOT-COMBAT / P4.30 |
| BeginState | event | Bot:454 | @SYS-BOT-COMBAT / P4.30 |
| BeginState | event | Bot:6 | @SYS-BOT-COMBAT / P4.30 |
| BeginState | event | Bot:607 | @SYS-BOT-COMBAT / P4.30 |
| BeginState | event | Bot:890 | @SYS-BOT-COMBAT / P4.30 |
| BeginState | event | Bot:958 | @SYS-BOT-COMBAT / P4.30 |
| BeginState | event | Nav:1259 | @SYS-NAV-STATE / P5.9 |
| bEnableAdvancedLocomotion | var | Nav:59 | @SYS-NAV-CONFIG / P5.10 |
| bEngageActive | var | Base:242 | P2 |
| bFallbackHadSpare | var | Base:310 | P2 |
| bFallbackWeapon | var | Base:309 | P2 |
| bFireLineClear | var | Base:280 | P2 |
| bFollowArrived | var | Nav:85 | P2 |
| bFollowDirectActive | var | Nav:133 | P2 |
| bFollowDispatchPending | var | Nav:107 | P2 |
| bFollowEscaping | var | Nav:165 | P2 |
| bFollowExitPending | var | Nav:80 | P2 |
| bFollowLeaderJumped | var | Nav:72 | P2 |
| bFollowMoveActive | var | Nav:132 | P2 |
| bFollowOrderAnchorActive | var | Nav:89 | P2 |
| bFollowReachKnown | var | Nav:101 | P2 |
| bFollowReachStable | var | Nav:100 | P2 |
| bFollowRouteStale | var | Nav:127 | P2 |
| bFollowYielding | var | Nav:162 | P2 |
| bFollowYieldPending | var | Nav:161 | P2 |
| bFormationScanDeferred | var | Base:277 | P2 |
| bGrappleFailsafeTriggered | var | Base:164 | P2 |
| bGruntMeleeStyle | var | Base:346 | P2 |
| bHasHoldPosition | var | Base:203 | P2 |
| bHasStuckBaseline | var | Base:41 | P2 |
| bHealFired | var | Base:143 | P2 |
| bHoldCrouching | var | Base:275 | P2 |
| bInTerminalState | var | Base:177 | P2 |
| bIsAlphaCommander | var | Base:34 | P2 |
| bIsGroupLeader | var | Base:33 | P2 |
| bIsRetreating | var | Base:180 | P2 |
| bIsStuck | var | Base:39 | P2 |
| bJustSpawned | var | Base:221 | P2 |
| BlockedCounter | var | Base:30 | P2 |
| BlockedShooterCount | var | Base:311 | P2 |
| BlockedShooterWindowStart | var | Base:312 | P2 |
| bNewWave | var | Mut:94 | P2 |
| bObjectiveActive | var | Mut:95 | P2 |
| bOffsetCached | var | Base:282 | P2 |
| BOSS_HEALTH_THRESHOLD | const | Base:62 | P2 |
| BotBlockRoutes | var | Base:23 | P2 |
| BOTFM_BASH | const | Base:294 | P2 |
| BOTFM_GRENADE | const | Base:295 | P2 |
| BOTFM_PRIMARY | const | Base:292 | P2 |
| BOTFM_RELOAD | const | Base:293 | P2 |
| BotRank | var | Base:26 | P2 |
| BOTS_PER_GROUP_TARGET | const | Mut:66 | P2 |
| bOutOfEffectiveRange | var | Base:308 | P2 |
| bOverwatchAllMove | var | Base:346 | P2 |
| bOverwatchLOS | var | Base:346 | P2 |
| bOverwatchMoving | var | Base:346 | P2 |
| bOverwatchPhase | var | Base:237 | P2 |
| bPlayingEmote | var | Base:390 | P2 |
| bPromotionGapTimerActive | var | Base:31 | P2 |
| BreakFreeAttempts | var | Base:162 | P2 |
| BreakLose | state | Bot:954 | @SYS-BOT-COMBAT / P4.30 |
| BREATH_OMEGA | const | Base:374 | P2 |
| BreathingPhase | var | Base:394 | P2 |
| bReloadDriftMove | var | Base:382 | P2 |
| bReloadPullClear | var | Base:382 | P2 |
| bRerouteRequested | var | Base:273 | P2 |
| BroadcastOverwatchState | function | Base:3654 | @SYS-BASE-OVERWATCH / P4.11 |
| BroadcastSpottedEnemy | function | Mut:1220 | @SYS-MUT-UTIL / P3.11 |
| bSerpentineMove | var | Base:172 | P2 |
| bSerpentLeft | var | Base:173 | P2 |
| bSingleFileFormation | var | Base:36 | P2 |
| bSLLoopSuspended | var | Base:393 | P2 |
| bSquadCrouchHold | var | Base:274 | P2 |
| bTraderListInit | var | Mut:96 | P2 |
| BuildPathTo | function | Base:1575 | @SYS-BASE-PATH / P4.5 |
| BuildPathToward | function | Base:1496 | @SYS-BASE-PATH / P4.5 |
| BuildRandomPath | function | Base:1654 | @SYS-BASE-PATH / P4.5 |
| bWasReloading | var | Base:382 | P2 |
| bWdEscalating | var | Base:397 | P2 |
| bWedgeActive | var | Base:386 | P2 |
| CachedBossPawn | var | Mut:61 | P2 |
| CachedHumanInfo | struct | Mut:112 | @SYS-MUT-PLATOON / P3.4 (structs) |
| CachedHumans | var | Mut:118 | P2 |
| CachedLocalOffset | var | Base:283 | P2 |
| CachedOffsetEpoch | var | Base:284 | P2 |
| CachedOffsetFormation | var | Base:286 | P2 |
| CachedOffsetSlot | var | Base:285 | P2 |
| CachedRoutePoint | var | Base:250 | P2 |
| CachedZedCount | var | Base:182 | P2 |
| CacheHumanPositions | function | Mut:2820 | @SYS-MUT-PLATOON / P3.4 |
| CacheHumans | function | Mut:2799 | @SYS-MUT-PLATOON / P3.4 |
| CallStack | var | Base:125 | P2 |
| Camp | state | Bot:452 | @SYS-BOT-MOVE / P4.29 |
| CanAffordHeal | function | Logic:521 | @SYS-LOGIC-HEAL / P4.22 |
| CanHealOthers | function | Base:2425 | @SYS-BASE-HEALQ / P4.21 |
| CaptainPathLoop | function | Base:2691 | @SYS-BASE-RANK / P4.9 |
| CaptainPathTimer | function | Logic:809 | @SYS-LOGIC-WATCHDOG / P4.23 |
| CharacterArch | var | Base:134 | P2 |
| CheckBlockedPath | function | Base:1258 | @SYS-BASE-MOVE / P4.4 |
| CheckEmoteEcho | function | Base:4511 | @SYS-BASE-EMOTE / P4.18 |
| CheckGrabbed | function | Logic:304 | @SYS-LOGIC-GRUNTMOVE / P4.24 |
| CheckMedicGunHeal | function | Logic:117 | @SYS-LOGIC-HEAL / P4.22 |
| CheckObjectiveHazard | function | Base:2318 | @SYS-BASE-OBJ / P4.7 |
| CheckOverwatchStall | function | Base:3717 | @SYS-BASE-OVERWATCH / P4.11 |
| CheckRetreatStatus | function | Bot:913 | @SYS-BOT-COMBAT / P4.30 |
| CheckShouldHealMate | function | Logic:4 | @SYS-LOGIC-HEAL / P4.22 |
| CheckShouldSelfHeal | function | Logic:202 | @SYS-LOGIC-HEAL / P4.22 |
| CheckWave | function | Mut:1244 | @SYS-MUT-WAVE / P3.6 |
| CheckWeaponReequip | function | Base:3343 | @SYS-BASE-WEAPON / P4.19 |
| CHOKEPOINT_LATERAL_OFFSET | const | Mut:71 | P2 |
| CleanupRangedHealCooldowns | function | Mut:940 | @SYS-MUT-HEALCOOL / P3.10 |
| ClearEmoteFlag | function | Base:4559 | @SYS-BASE-EMOTE / P4.18 |
| ClearGrenadeSignal | function | Base:3518 | @SYS-BASE-WEAPON / P4.19 |
| ClearRankTimers | function | Base:3066 | @SYS-BASE-RANK / P4.9 |
| ClearSquadCrouchHold | function | Base:3029 | @SYS-BASE-CQB / P4.12 |
| ClearWedge | function | Base:4445 | @SYS-BASE-WEDGE / P4.17 |
| CloseToEffectiveRange | function | Base:3322 | @SYS-BASE-WEAPON / P4.19 |
| ComputeCommandScore | function | Mut:776 | @SYS-MUT-SUCCESSION / P3.5 |
| ComputeFormationOffset | function | Base:2191 | @SYS-BASE-FORM / P4.10 |
| ComputeSlotOffset | function | Base:2842 | @SYS-BASE-FORM / P4.10 |
| ComputeWedgeOffset | function | Base:4462 | @SYS-BASE-WEDGE / P4.17 |
| ConfigVer | var | Mut:42 | P2 |
| ConsolidateFireteams | function | Mut:1058 | @SYS-MUT-SUCCESSION / P3.5 |
| ConsumePathToken | function | Logic:577 | @SYS-LOGIC-GRUNTMOVE / P4.24 |
| CoordStr | function | Mut:1416 | @SYS-MUT-UTIL / P3.11 |
| CountNearbyZeds | function | Base:2226 | @SYS-BASE-ZEDS / P4.8 |
| CountNearbyZedsCached | function | Base:3565 | @SYS-BASE-ZEDS / P4.8 |
| CountZedsInRadius | function | Mut:1814 | @SYS-MUT-REGROUP / P3.8 |
| COVER_RANGE_SQ | const | Base:339 | P2 |
| CQB_BASH_INTERVAL | const | Base:337 | P2 |
| CQB_BASH_SQ | const | Base:335 | P2 |
| CQB_MID_SQ | const | Base:336 | P2 |
| CQB_PROBE_DIST | const | Base:48 | P2 |
| CQB_STEPBACK_SPEED | const | Base:338 | P2 |
| CQB_TRACE_INTERVAL | const | Base:47 | P2 |
| CQB_TRACE_RADIUS_SQ | const | Base:46 | P2 |
| CUR_CONFIGVER | const | Mut:5 | P2 |
| CurrentFormation | var | Base:265 | P2 |
| CurrentLevel | var | Base:130 | P2 |
| CurrentOrder | var | Base:354 | P2 |
| Dead | state | Bot:1913 | @SYS-BOT-TERM / P4.33 |
| DeadOfficer | var | Mut:102 | P2 |
| DebugAI | function | Mut:2559 | @SYS-MUT-UTIL / P3.11 |
| DebugMessage | function | Mut:2535 | @SYS-MUT-UTIL / P3.11 |
| defaultproperties | defaultproperties | Base:4601 | P2 |
| defaultproperties | defaultproperties | Mut:3031 | @SYS-MUT-BOOT / P3.1 |
| defaultproperties | defaultproperties | Nav:1494 | @SYS-NAV-CONFIG / P5.10 |
| DefaultWeaponEffectiveRangeUU | var | Base:318 | P2 |
| DeferredFormationScan | function | Base:2805 | @SYS-BASE-FORM / P4.10 |
| DEG_TO_RAD | const | Base:54 | P2 |
| DemoteGroupLeader | function | Mut:1018 | @SYS-MUT-SUCCESSION / P3.5 |
| Destroyed | function | Base:462 | @SYS-BASE-BOOT / P4.1 |
| DetermineGroupCount | function | Mut:544 | @SYS-MUT-PLATOON / P3.4 |
| DissolveGroup | function | Mut:1111 | @SYS-MUT-SUCCESSION / P3.5 |
| DonateHuman | var | Base:138 | P2 |
| DonateMoney | function | Base:1040 | @SYS-BASE-SHOP / P4.6 |
| DonateMoney | function | Bot:425 | @SYS-BOT-MOVE / P4.29 |
| DonatingMoney | state | Bot:1778 | @SYS-BOT-MOVE / P4.29 |
| DoObjective | state | Bot:485 | @SYS-BOT-COMBAT / P4.30 |
| door | var | Base:6 | P2 |
| DOOR_CHECK_RADIUS | const | Base:51 | P2 |
| DoorPaths | var | Base:22 | P2 |
| DoshDropCounter | var | Base:129 | P2 |
| DoTrading | function | Bot:1676 | @SYS-BOT-SHOP / P4.32 |
| DRIFT_MAX_TOTAL | const | Base:377 | P2 |
| DRIFT_MIN_DIST_SQ | const | Base:376 | P2 |
| DRIFT_RATE | const | Base:375 | P2 |
| DropMoney | function | Bot:1840 | @SYS-BOT-MOVE / P4.29 |
| EBotRank | enum | Base:14 | @SYS-BASE-RANK / P4.9 |
| EchelonLog | function | Base:2484 | @SYS-BASE-BOOT / P4.1 |
| EchelonLog | function | Mut:159 | @SYS-MUT-UTIL / P3.11 |
| EFollowAction | enum | Nav:35 | @SYS-NAV-CONFIG / P5.10 |
| EFollowStatus | enum | Nav:46 | @SYS-NAV-CONFIG / P5.10 |
| EMOTE_CHANCE | const | Base:372 | P2 |
| EMOTE_RADIUS_SQ | const | Base:371 | P2 |
| EMOTE_ROLL_COOLDOWN | const | Base:373 | P2 |
| EndMoveTime | var | Base:146 | P2 |
| EndObjective | function | Mut:1354 | @SYS-MUT-WAVE / P3.6 |
| EndState | event | Bot:1079 | @SYS-BOT-COMBAT / P4.30 |
| EndState | event | Bot:12 | @SYS-BOT-COMBAT / P4.30 |
| EndState | event | Bot:1202 | @SYS-BOT-COMBAT / P4.30 |
| EndState | event | Bot:1305 | @SYS-BOT-COMBAT / P4.30 |
| EndState | event | Bot:1425 | @SYS-BOT-COMBAT / P4.30 |
| EndState | event | Bot:1547 | @SYS-BOT-COMBAT / P4.30 |
| EndState | event | Bot:1592 | @SYS-BOT-COMBAT / P4.30 |
| EndState | event | Bot:1733 | @SYS-BOT-COMBAT / P4.30 |
| EndState | event | Bot:1791 | @SYS-BOT-COMBAT / P4.30 |
| EndState | event | Bot:1924 | @SYS-BOT-COMBAT / P4.30 |
| EndState | event | Bot:1965 | @SYS-BOT-COMBAT / P4.30 |
| EndState | event | Bot:1997 | @SYS-BOT-COMBAT / P4.30 |
| EndState | event | Bot:289 | @SYS-BOT-COMBAT / P4.30 |
| EndState | event | Bot:464 | @SYS-BOT-COMBAT / P4.30 |
| EndState | event | Bot:617 | @SYS-BOT-COMBAT / P4.30 |
| EndState | event | Bot:902 | @SYS-BOT-COMBAT / P4.30 |
| EndState | event | Bot:988 | @SYS-BOT-COMBAT / P4.30 |
| EndState | event | Nav:1275 | @SYS-NAV-STATE / P5.9 |
| ENEMY_SCAN_INTERVAL | const | Base:87 | P2 |
| ENEMY_SCAN_RADIUS | const | Base:88 | P2 |
| EnemyChanged | function | Base:1035 | @SYS-BASE-HEALQ / P4.21 |
| EnemyChanged | function | Bot:1133 | @SYS-BOT-MOVE / P4.29 |
| EnemyChanged | function | Bot:1605 | @SYS-BOT-MOVE / P4.29 |
| EnemyChanged | function | Bot:2045 | @SYS-BOT-MOVE / P4.29 |
| EnemyChanged | function | Bot:419 | @SYS-BOT-MOVE / P4.29 |
| EnemyChanged | function | Bot:469 | @SYS-BOT-MOVE / P4.29 |
| EnemyChanged | function | Bot:940 | @SYS-BOT-MOVE / P4.29 |
| EnemyEncounterTime | var | Base:149 | P2 |
| EngageAnchor | var | Base:241 | P2 |
| EngageExpireTime | var | Base:243 | P2 |
| EnsureSquadOrderTable | function | Mut:1423 | @SYS-MUT-ORDERS / P3.7 |
| equipDeadline | var | Base:217 | P2 |
| EvaluateFollowerMove | function | Logic:1213 | @SYS-LOGIC-MOVEVAL / P4.25 |
| EvaluateLeaderMove | function | Logic:1205 | @SYS-LOGIC-MOVEVAL / P4.25 |
| EvaluateRegroupEntries | function | Mut:1838 | @SYS-MUT-REGROUP / P3.8 |
| EvaluateSquadPhase | function | Mut:1672 | @SYS-MUT-ORDERS / P3.7 |
| EvaluateSquadTether | function | Logic:1169 | @SYS-LOGIC-MOVEVAL / P4.25 |
| ExceedsRetreatZedCount | function | Base:4574 | @SYS-BASE-ZEDS / P4.8 |
| ExecuteCampState | function | Logic:1365 | @SYS-LOGIC-MOVEVAL / P4.25 |
| ExpiresAt | var | Mut:20 | P2 |
| EyeSightCheck | function | Base:761 | @SYS-BASE-PERCEPT / P4.2 |
| FailedMoveCount | var | Base:128 | P2 |
| FailStreak | var | Base:215 | P2 |
| FallbackPrimary | var | Base:322 | P2 |
| FallbackSince | var | Base:323 | P2 |
| FavoriteWeapon | var | Base:132 | P2 |
| FightEnemy | state | Bot:605 | @SYS-BOT-COMBAT / P4.30 |
| FindBestCandidate | function | Mut:783 | @SYS-MUT-SUCCESSION / P3.5 |
| FindBossPawn | function | Mut:728 | @SYS-MUT-PLATOON / P3.4 |
| FindCollectable | function | Logic:1004 | @SYS-LOGIC-UTIL / P4.27 |
| FindExpendableMember | function | Mut:798 | @SYS-MUT-SUCCESSION / P3.5 |
| FindNearestActiveLeader | function | Mut:1768 | @SYS-MUT-REGROUP / P3.8 |
| FindNearestChokepoint | function | Mut:688 | @SYS-MUT-PLATOON / P3.4 |
| FindNearestEligibleGroup | function | Mut:1129 | @SYS-MUT-SUCCESSION / P3.5 |
| FindNearestNavPoint | function | Mut:678 | @SYS-MUT-PLATOON / P3.4 |
| FindWeaponByClass | function | Mut:2090 | @SYS-MUT-UTIL / P3.11 |
| FinishedMove | function | Base:1811 | @SYS-BASE-MOVE / P4.4 |
| FinishedMove | function | Bot:1127 | @SYS-BOT-COMBAT / P4.30 |
| FinishedMove | function | Bot:1557 | @SYS-BOT-COMBAT / P4.30 |
| FinishedMove | function | Bot:1670 | @SYS-BOT-SHOP / P4.32 |
| FinishedMove | function | Bot:1762 | @SYS-BOT-MOVE / P4.29 |
| FinishedMove | function | Bot:1834 | @SYS-BOT-MOVE / P4.29 |
| FinishedMove | function | Bot:2011 | @SYS-BOT-TERM / P4.33 |
| FinishedMove | function | Bot:413 | @SYS-BOT-MOVE / P4.29 |
| FinishedMove | function | Bot:719 | @SYS-BOT-COMBAT / P4.30 |
| FinishedMove | function | Bot:930 | @SYS-BOT-COMBAT / P4.30 |
| FinishObjective | function | Bot:487 | @SYS-BOT-COMBAT / P4.30 |
| FinishObjective | function | Logic:1084 | @SYS-LOGIC-DEATH / P4.26 |
| FireLineTarget | var | Base:281 | P2 |
| FireteamData | struct | Mut:7 | @SYS-MUT-PLATOON / P3.4 (structs) |
| Fireteams | var | Mut:55 | P2 |
| FireWeaponAt | function | Base:881 | @SYS-BASE-FIRE / P4.3 |
| FlamethrowerEffectiveRangeUU | var | Base:317 | P2 |
| FOLLOW_ESCAPE_COOLDOWN | const | Base:70 | P2 |
| FollowAction | var | Nav:187 | P2 |
| FollowBaseOffset | var | Nav:81 | P2 |
| FollowBlockMinGap | var | Nav:181 | P2 |
| FollowBlocksThisEpisode | var | Nav:178 | P2 |
| FollowBuildPath | function | Nav:645 | @SYS-NAV-PATH / P5.4 |
| FollowBumpCooldown | var | Nav:156 | P2 |
| FollowCheckExit | function | Logic:839 | @SYS-LOGIC-MOVEVAL / P4.25 |
| FollowCheckExit | function | Nav:308 | @SYS-NAV-WATCHDOG / P5.2 |
| FollowCheckReachable | function | Nav:587 | @SYS-NAV-LEADER / P5.3 |
| FollowComputeYieldPoint | function | Nav:1148 | @SYS-NAV-HANDLE / P5.7 |
| FollowDecide | function | Nav:727 | @SYS-NAV-DECIDE / P5.5 |
| FOLLOWER_DRIFT_SQ | const | Base:68 | P2 |
| FollowEscapeDuration | var | Nav:168 | P2 |
| FollowEscapeNormal | var | Nav:166 | P2 |
| FollowEscapeUntil | var | Nav:167 | P2 |
| FollowEvalArrived | function | Nav:531 | @SYS-NAV-LEADER / P5.3 |
| FollowExitState | var | Nav:79 | P2 |
| FollowForcePathDuration | var | Nav:119 | P2 |
| FollowForcePathUntil | var | Nav:120 | P2 |
| FollowGetArrivalRadius | function | Nav:517 | @SYS-NAV-LEADER / P5.3 |
| FollowGetNextNode | function | Nav:692 | @SYS-NAV-PATH / P5.4 |
| FollowGetOrderAnchor | function | Base:2530 | @SYS-BASE-AUDIT / P4.20 |
| FollowGetOrderAnchor | function | Nav:232 | @SYS-NAV-EPISODE / P5.1 |
| FollowGiveUpHold | var | Nav:182 | P2 |
| FollowGuessStuckCause | function | Nav:896 | @SYS-NAV-STUCK / P5.6 |
| FollowHandleBump | function | Nav:1092 | @SYS-NAV-HANDLE / P5.7 |
| FollowHandleHitWall | function | Nav:981 | @SYS-NAV-HANDLE / P5.7 |
| FollowHandleMoveUnreachable | function | Nav:1123 | @SYS-NAV-HANDLE / P5.7 |
| FollowingHuman | var | Base:137 | P2 |
| FollowingLeader | state | Nav:1257 | @SYS-NAV-STATE / P5.9 |
| FollowingLeaderBasic | state | Nav:1427 | @SYS-NAV-STATE / P5.9 |
| FollowInterruptMinGap | var | Nav:105 | P2 |
| FollowInvalidateRoute | function | Nav:263 | @SYS-NAV-EPISODE / P5.1 |
| FollowIsFriendly | function | Nav:1051 | @SYS-NAV-HANDLE / P5.7 |
| FollowLastBumpTime | var | Nav:154 | P2 |
| FollowLastLeaderPathLoc | var | Nav:122 | P2 |
| FollowLastPawnTargetPathLoc | var | Nav:123 | P2 |
| FollowLastWall | var | Nav:147 | P2 |
| FollowLastWallTime | var | Nav:148 | P2 |
| FollowLeaderCtrl | var | Nav:64 | P2 |
| FollowLeaderGraceTime | var | Nav:69 | P2 |
| FollowLeaderInvalidSince | var | Nav:68 | P2 |
| FollowLeaderLastSampleLoc | var | Nav:66 | P2 |
| FollowLeaderLastSampleTime | var | Nav:67 | P2 |
| FollowLeaderPawn | var | Nav:65 | P2 |
| FollowLeaderTeleportDist | var | Nav:70 | P2 |
| FollowLeaderTeleportSpeed | var | Nav:71 | P2 |
| FollowLegTimeout | var | Nav:135 | P2 |
| FollowMaxBlocksPerEpisode | var | Nav:179 | P2 |
| FollowMaxRouteNodes | var | Nav:126 | P2 |
| FollowMinLoopSleep | var | Nav:104 | P2 |
| FollowMoveStartTime | var | Nav:134 | P2 |
| FollowNextBlockTime | var | Nav:180 | P2 |
| FollowNextBumpReactTime | var | Nav:155 | P2 |
| FollowNextInterruptTime | var | Nav:106 | P2 |
| FollowNextPathTime | var | Nav:113 | P2 |
| FollowNextReachCheckTime | var | Nav:99 | P2 |
| FollowNode | var | Nav:188 | P2 |
| FollowNodeLast | var | Nav:140 | P2 |
| FollowNodeRepathDistSq | var | Nav:118 | P2 |
| FollowNotifyHub | function | Base:1287 | @SYS-BASE-MOVE / P4.4 |
| FollowNotifyHub | function | Nav:1209 | @SYS-NAV-STATUS / P5.8 |
| FollowOnGaveUp | function | Base:1317 | @SYS-BASE-MOVE / P4.4 |
| FollowOnGaveUp | function | Nav:1216 | @SYS-NAV-WATCHDOG / P5.2 |
| FollowOnMoveBegin | function | Nav:813 | @SYS-NAV-PATH / P5.4 |
| FollowOnMoveEnd | function | Nav:837 | @SYS-NAV-PATH / P5.4 |
| FollowOnNodeMoveEnd | function | Nav:855 | @SYS-NAV-PATH / P5.4 |
| FollowOnStuck | function | Nav:915 | @SYS-NAV-STUCK / P5.6 |
| FollowOrderAnchorLoc | var | Nav:90 | P2 |
| FollowOwnsEvents | function | Nav:974 | @SYS-NAV-HANDLE / P5.7 |
| FollowPathFailBackoff | var | Nav:114 | P2 |
| FollowPathFailBackoffMax | var | Nav:116 | P2 |
| FollowPathFailBackoffMin | var | Nav:115 | P2 |
| FollowPathMinInterval | var | Nav:112 | P2 |
| FollowPhaseJitter | var | Nav:96 | P2 |
| FollowReachFailsToPath | var | Nav:103 | P2 |
| FollowReachFailStreak | var | Nav:102 | P2 |
| FollowReachIntervalDirect | var | Nav:97 | P2 |
| FollowReachIntervalPath | var | Nav:98 | P2 |
| FollowRefreshLeader | function | Nav:442 | @SYS-NAV-LEADER / P5.3 |
| FollowRepathDistance | var | Nav:117 | P2 |
| FollowRepathPauseUntil | var | Nav:121 | P2 |
| FollowRequestDispatch | function | Nav:416 | @SYS-NAV-WATCHDOG / P5.2 |
| FollowResetEpisode | function | Nav:238 | @SYS-NAV-EPISODE / P5.1 |
| FollowResumeMargin | var | Nav:83 | P2 |
| FollowRetries | var | Nav:173 | P2 |
| FollowRetriesBlockAt | var | Nav:174 | P2 |
| FollowRetriesGiveUpAt | var | Nav:175 | P2 |
| FollowRetryAnchorLoc | var | Nav:176 | P2 |
| FollowRetryResetDist | var | Nav:177 | P2 |
| FollowRoute | var | Nav:124 | P2 |
| FollowRouteIdx | var | Nav:125 | P2 |
| FollowSameNodeCount | var | Nav:141 | P2 |
| FollowSameNodeLimit | var | Nav:142 | P2 |
| FollowScheduleWatchdog | function | Nav:285 | @SYS-NAV-EPISODE / P5.1 |
| FollowSetLeader | function | Nav:212 | @SYS-NAV-EPISODE / P5.1 |
| FollowSetSlot | function | Nav:223 | @SYS-NAV-EPISODE / P5.1 |
| FollowSetStatus | function | Nav:1198 | @SYS-NAV-STATUS / P5.8 |
| FollowSetWallEscape | function | Nav:1032 | @SYS-NAV-STUCK / P5.6 |
| FollowShouldYieldTo | function | Nav:1071 | @SYS-NAV-HANDLE / P5.7 |
| FollowSlotCount | var | Nav:78 | P2 |
| FollowSlotIndex | var | Nav:77 | P2 |
| FollowSlotPhase | function | Nav:280 | @SYS-NAV-EPISODE / P5.1 |
| FollowSlotRingStep | var | Nav:82 | P2 |
| FollowStart | function | Nav:198 | @SYS-NAV-EPISODE / P5.1 |
| FollowStatus | var | Nav:190 | P2 |
| FollowStuckMinMove | var | Nav:139 | P2 |
| FollowStuckRefLoc | var | Nav:136 | P2 |
| FollowStuckRefTime | var | Nav:137 | P2 |
| FollowStuckWindow | var | Nav:138 | P2 |
| FollowTryBlockNode | function | Nav:965 | @SYS-NAV-STUCK / P5.6 |
| FollowWaitTime | var | Nav:189 | P2 |
| FollowWallDebounce | var | Nav:153 | P2 |
| FollowWallHitCount | var | Nav:150 | P2 |
| FollowWallHitThreshold | var | Nav:151 | P2 |
| FollowWallWindow | var | Nav:152 | P2 |
| FollowWallWindowStart | var | Nav:149 | P2 |
| FollowWatchdog | function | Nav:318 | @SYS-NAV-WATCHDOG / P5.2 |
| FollowWatchdogBegin | function | Nav:297 | @SYS-NAV-EPISODE / P5.1 |
| FollowWatchdogPeriod | var | Nav:95 | P2 |
| FollowYieldAway | var | Nav:163 | P2 |
| FollowYieldDist | var | Nav:157 | P2 |
| FollowYieldEndTime | var | Nav:160 | P2 |
| FollowYieldHold | var | Nav:158 | P2 |
| FollowYieldPoint | var | Nav:164 | P2 |
| FollowYieldTimeout | var | Nav:159 | P2 |
| FollowZTolerance | var | Nav:84 | P2 |
| ForceBreakGrapple | function | Base:2375 | @SYS-BASE-OBJ / P4.7 |
| FORM_LINE_DIST | const | Base:263 | P2 |
| FORM_SCAN_DIST | const | Base:262 | P2 |
| FormationEpoch | var | Base:269 | P2 |
| FormationHoldUntil | var | Base:271 | P2 |
| FormationYaw | var | Base:270 | P2 |
| FRouteDoorBlockade | struct | Base:4 | @SYS-BASE-PATH / P4.5 (FRouteDoorBlockade) |
| GetActiveBoss | function | Base:2476 | @SYS-BASE-OBJ / P4.7 |
| GetActiveBoss | function | Mut:2808 | @SYS-MUT-PLATOON / P3.4 |
| GetAdjustedAimFor | function | Base:1055 | @SYS-BASE-FIRE / P4.3 |
| GetAIInfo | function | Logic:1051 | @SYS-LOGIC-UTIL / P4.27 |
| GetBestBuy | function | Base:1884 | @SYS-BASE-SHOP / P4.6 |
| GetBotObjective | function | Mut:1953 | @SYS-MUT-ORDERS / P3.7 |
| GetEnemyThreat | function | Base:858 | @SYS-BASE-PERCEPT / P4.2 |
| GetFollowerBySlot | function | Mut:1614 | @SYS-MUT-SUCCESSION / P3.5 |
| GetFollowerIndex | function | Mut:1197 | @SYS-MUT-SUCCESSION / P3.5 |
| GetFormationBase | function | Base:2813 | @SYS-BASE-FORM / P4.10 |
| GetGroupLeader | function | Mut:1181 | @SYS-MUT-SUCCESSION / P3.5 |
| GetGroupSize | function | Mut:1189 | @SYS-MUT-SUCCESSION / P3.5 |
| GetItem | state | Bot:1718 | @SYS-BOT-MOVE / P4.29 |
| GetMoveDirection | function | Base:1176 | @SYS-BASE-MOVE / P4.4 |
| GetObjectiveLocation | function | Base:2440 | @SYS-BASE-OBJ / P4.7 |
| GetObjectiveLocation | function | Mut:2839 | @SYS-MUT-WAVE / P3.6 |
| GetPlayerViewPoint | function | Base:1082 | @SYS-BASE-FIRE / P4.3 |
| GetPointNear | function | Logic:1094 | @SYS-LOGIC-UTIL / P4.27 |
| GetRandMove | function | Bot:2023 | @SYS-BOT-TERM / P4.33 |
| GetRankName | function | Base:3086 | @SYS-BASE-RANK / P4.9 |
| GetSlotLocation | function | Mut:1657 | @SYS-MUT-ORDERS / P3.7 |
| GetSquadPhase | function | Mut:1632 | @SYS-MUT-ORDERS / P3.7 |
| GetSquadStartTime | function | Mut:1905 | @SYS-MUT-REGROUP / P3.8 |
| GetVIPController | function | Mut:705 | @SYS-MUT-PLATOON / P3.4 |
| GetWaveMomentum | function | Base:4566 | @SYS-BASE-ZEDS / P4.8 |
| GetWeaponEffectiveRangeUU | function | Base:3276 | @SYS-BASE-WEAPON / P4.19 |
| GiveWeaponDef | function | Base:516 | @SYS-BASE-BOOT / P4.1 |
| GLOBAL_ZED_COUNT_INTERVAL | const | Base:74 | P2 |
| GLOBAL_ZED_RADIUS | const | Base:73 | P2 |
| GlobalZedCount | var | Base:189 | P2 |
| GoalNav | var | Mut:31 | P2 |
| GoalPoint | var | Mut:30 | P2 |
| GoShopping | state | Bot:1578 | @SYS-BOT-SHOP / P4.32 |
| GrabStartTime | var | Base:161 | P2 |
| GrenadeAimTicks | var | Base:324 | P2 |
| GrenadeSignal | var | Base:300 | P2 |
| GrenadeTarget | state | Bot:1538 | @SYS-BOT-COMBAT / P4.30 |
| GrenadeTargetPawn | var | Base:302 | P2 |
| GrenadeThrowsLeft | var | Base:301 | P2 |
| GROUP_DISSOLVE_SIZE | const | Mut:68 | P2 |
| GroupID | var | Base:32 | P2 |
| GruntDecisionTimer | function | Logic:595 | @SYS-LOGIC-WATCHDOG / P4.23 |
| GruntEnterCombat | function | Base:4091 | @SYS-BASE-GRUNT / P4.13 |
| GruntOnSight | function | Base:4076 | @SYS-BASE-GRUNT / P4.13 |
| GruntOverwatchPhase | var | Base:346 | P2 |
| GruntPickCombatStyle | function | Base:4108 | @SYS-BASE-GRUNT / P4.13 |
| GruntSlot | var | Base:290 | P2 |
| HandleCQBProximity | function | Base:3919 | @SYS-BASE-CQB / P4.12 |
| HandleFireteamCasualty | function | Mut:973 | @SYS-MUT-SUCCESSION / P3.5 |
| HandleReloadDrift | function | Base:4237 | @SYS-BASE-RELOAD / P4.15 |
| HandleVIPSuccession | function | Mut:956 | @SYS-MUT-SUCCESSION / P3.5 |
| HandleWeaponManagement | function | Base:3526 | @SYS-BASE-WEAPON / P4.19 |
| HasOwnFireLine | function | Base:2938 | @SYS-BASE-OVERWATCH / P4.11 |
| HasSquadGoal | function | Mut:1734 | @SYS-MUT-ORDERS / P3.7 |
| HEAL_MAX_NEED_PCT | const | Base:84 | P2 |
| HEAL_MIN_NEED_PCT | const | Base:85 | P2 |
| HealFail | function | Logic:532 | @SYS-LOGIC-HEAL / P4.22 |
| HealFailsafe | function | Bot:1228 | @SYS-BOT-HEAL / P4.31 |
| HealFailsafe | function | Bot:1328 | @SYS-BOT-HEAL / P4.31 |
| HealFailsafe | function | Bot:1448 | @SYS-BOT-HEAL / P4.31 |
| HealingSelf | state | Bot:1192 | @SYS-BOT-HEAL / P4.31 |
| HealingStage | var | Base:127 | P2 |
| HealOther | state | Bot:1295 | @SYS-BOT-HEAL / P4.31 |
| HealPacingEnd | var | Base:213 | P2 |
| HealRanged | state | Bot:1415 | @SYS-BOT-HEAL / P4.31 |
| HealRetryAfter | var | Base:214 | P2 |
| HealSuccess | function | Logic:541 | @SYS-LOGIC-HEAL / P4.22 |
| HealTimeOut | function | Logic:569 | @SYS-LOGIC-HEAL / P4.22 |
| HEAR_RANGE_SQ | const | Base:342 | P2 |
| HearNoise | event | Base:4141 | @SYS-BASE-PERCEPT / P4.2 |
| HearNoiseExpireTime | var | Base:306 | P2 |
| HearNoiseZedCount | var | Base:305 | P2 |
| HeavyZedWithin | function | Base:2275 | @SYS-BASE-ZEDS / P4.8 |
| HideAllPickups | function | Mut:3008 | @SYS-MUT-SPAWN / P3.2 |
| HoldAndCrouch | function | Base:3034 | @SYS-BASE-CQB / P4.12 |
| HoldAreaAnchor | var | Base:384 | P2 |
| HoldDriftDist | var | Base:394 | P2 |
| HoldPosition | var | Base:204 | P2 |
| HoldVolume | var | Mut:91 | P2 |
| HUMAN_BOUND_INTERVAL | const | Base:365 | P2 |
| HUMAN_LT_RANGE_SQ | const | Base:368 | P2 |
| HUMAN_MIN_SPEED_SQ | const | Base:367 | P2 |
| HUMAN_PUSH_DOT | const | Base:366 | P2 |
| HumanPawn | var | Mut:114 | P2 |
| HUNT_SCAN_RADIUS | const | Base:72 | P2 |
| HUNT_ZED_THRESHOLD | const | Base:71 | P2 |
| Hunting | state | Bot:1064 | @SYS-BOT-COMBAT / P4.30 |
| IdleWatchdog | function | Logic:645 | @SYS-LOGIC-WATCHDOG / P4.23 |
| IdleWatchdogTimer | function | Logic:639 | @SYS-LOGIC-WATCHDOG / P4.23 |
| InheritedEnemy | var | Base:276 | P2 |
| InheritSquadOrder | function | Mut:1443 | @SYS-MUT-ORDERS / P3.7 |
| InitBotCharacter | function | Mut:2160 | @SYS-MUT-SPAWN / P3.2 |
| InitEmotes | function | Mut:2745 | @SYS-MUT-BOOT / P3.1 |
| InitializePlatoon | function | Mut:368 | @SYS-MUT-PLATOON / P3.4 |
| InitPlayerReplicationInfo | function | Base:473 | @SYS-BASE-BOOT / P4.1 |
| InitTraderList | function | Mut:2067 | @SYS-MUT-UTIL / P3.11 |
| IsAnchorValid | function | Logic:1196 | @SYS-LOGIC-MOVEVAL / P4.25 |
| IsBossWaveActive | function | Base:2463 | @SYS-BASE-OBJ / P4.7 |
| IsBotAlive | function | Base:2420 | @SYS-BASE-HEALQ / P4.21 |
| IsDirClearCached | function | Base:2981 | @SYS-BASE-FORM / P4.10 |
| IsGruntCombatLocked | function | Base:4066 | @SYS-BASE-GRUNT / P4.13 |
| IsHealLockedOut | function | Base:2430 | @SYS-BASE-HEALQ / P4.21 |
| IsHeavyZedPawn | function | Base:4181 | @SYS-BASE-ZEDS / P4.8 |
| IsHostileZed | function | Base:3628 | @SYS-BASE-PERCEPT / P4.2 |
| IsInEffectiveRange | function | Base:3299 | @SYS-BASE-WEAPON / P4.19 |
| IsMeleeOnly | function | Base:2309 | @SYS-BASE-FIRE / P4.3 |
| IsNodeBlocked | function | Mut:2011 | @SYS-MUT-NODEBLOCK / P3.9 |
| IsOnWalkableFloor | function | Base:2184 | @SYS-BASE-BOOT / P4.1 |
| IsOverwatchStuck | function | Base:3772 | @SYS-BASE-OVERWATCH / P4.11 |
| IsRagdolled | state | Bot:1948 | @SYS-BOT-TERM / P4.33 |
| IsRangedHealTargetOnCooldown | function | Mut:922 | @SYS-MUT-HEALCOOL / P3.10 |
| IsReloading | function | Base:4229 | @SYS-BASE-RELOAD / P4.15 |
| IsRetreatSafe | function | Base:3004 | @SYS-BASE-ZEDS / P4.8 |
| IsSquadInObjectivePhase | function | Mut:1645 | @SYS-MUT-ORDERS / P3.7 |
| IssueCommand | function | Base:2617 | @SYS-BASE-RANK / P4.9 |
| KF | var | Mut:88 | P2 |
| KF2Bot | class | Bot:1 | 0.2 |
| KF2BotBase | class | Base:1 | 0.2 |
| KF2BotLogic | class | Logic:1 | 0.2 |
| KF2BotsFollowNavBase | class | Nav:29 | 0.2 |
| KF2BotsMut | class | Mut:1 | 0.2 |
| KFGRI | var | Base:140 | P2 |
| KFInvManager | var | Base:139 | P2 |
| KPawn | var | Base:135 | P2 |
| landingDeadline | var | Base:216 | P2 |
| LastAuditLogTime | var | Mut:156 | P2 |
| LastCallTimer | var | Base:145 | P2 |
| LastCQBCheckTime | var | Base:37 | P2 |
| LastDriftTime | var | Base:394 | P2 |
| LastEnemyScanTime | var | Base:228 | P2 |
| LastFactory | var | Base:165 | P2 |
| LastFailedMove | var | Base:169 | P2 |
| LastFollowEscapeTime | var | Base:186 | P2 |
| LastFormationScanTime | var | Base:278 | P2 |
| LastFormationYaw | var | Base:287 | P2 |
| LastGlobalZedCountTime | var | Base:190 | P2 |
| LastHealFireTime | var | Base:144 | P2 |
| LastHealthCheck | var | Base:289 | P2 |
| LastLeashDropTime | var | Base:229 | P2 |
| LastNodeBlockTime | var | Base:154 | P2 |
| LastNoiseLoc | var | Base:307 | P2 |
| LastOffsetUpdate | var | Base:288 | P2 |
| LastPolledWaveNum | var | Mut:62 | P2 |
| LastRerouteTime | var | Base:272 | P2 |
| LastRouteDist | var | Base:44 | P2 |
| LastStuckSampleTime | var | Base:43 | P2 |
| LastTriageTime | var | Base:207 | P2 |
| LastValidSLTime | var | Base:29 | P2 |
| LastValidSquadLeaderPos | var | Base:28 | P2 |
| LastValidSquadLeaderYaw | var | Base:351 | P2 |
| LastZedCountTime | var | Base:181 | P2 |
| Leader | var | Mut:10 | P2 |
| Leader | var | Mut:28 | P2 |
| LeaderLocation3SecAgo | var | Base:42 | P2 |
| LEASH_COOLDOWN | const | Base:91 | P2 |
| LEASH_DROP_DIST_SQ | const | Base:90 | P2 |
| LineSuppressUntil | var | Base:313 | P2 |
| Loc | var | Mut:115 | P2 |
| LTDispatchLoop | function | Base:2684 | @SYS-BASE-RANK / P4.9 |
| LtHumanBoundLoop | function | Base:4350 | @SYS-BASE-LTBOUND / P4.16 |
| MACRO_WAYPOINT_INTERVAL | const | Mut:73 | P2 |
| MarkDoorPath | function | Base:1463 | @SYS-BASE-PATH / P4.5 |
| MatchStarting | function | Mut:289 | @SYS-MUT-BOOT / P3.1 |
| MAX_GROUPS | const | Mut:65 | P2 |
| MaxEmoteCount | var | Mut:92 | P2 |
| MedicGun | var | Base:141 | P2 |
| Members | var | Mut:9 | P2 |
| MIN_GROUPS | const | Mut:64 | P2 |
| MoveFlags | var | Base:126 | P2 |
| MovePauseTime | var | Base:157 | P2 |
| MoveSquadMembers | function | Mut:1919 | @SYS-MUT-REGROUP / P3.8 |
| MoveTowardGoal | function | Logic:1269 | @SYS-LOGIC-MOVEVAL / P4.25 |
| MoveTowardX | function | Base:1117 | @SYS-BASE-MOVE / P4.4 |
| MoveToX | function | Base:1098 | @SYS-BASE-MOVE / P4.4 |
| MoveUnreachable | event | Nav:1243 | @SYS-NAV-HANDLE / P5.7 |
| mut | var | Base:133 | P2 |
| Mutate | function | Mut:2590 | @SYS-MUT-SPAWN / P3.2 |
| NAV_SEARCH_RADIUS | const | Mut:72 | P2 |
| NavNodeBlock | struct | Mut:16 | @SYS-MUT-PLATOON / P3.4 (structs) |
| NearestValidPoint | function | Mut:1394 | @SYS-MUT-WAVE / P3.6 |
| NeedToTurn | function | Base:1740 | @SYS-BASE-FIRE / P4.3 |
| NetDamage | function | Mut:2721 | @SYS-MUT-SPAWN / P3.2 |
| NextAdjustTime | var | Base:156 | P2 |
| NextBashTime | var | Base:350 | P2 |
| NextDoshShareTime | var | Base:160 | P2 |
| NextEmoteRollTime | var | Base:391 | P2 |
| NextEscapeAttempt | var | Base:163 | P2 |
| NextFallbackPoll | var | Base:321 | P2 |
| NextFireLineCheck | var | Base:279 | P2 |
| NextGrenadeSignalTime | var | Base:303 | P2 |
| NextGrenadeTimer | var | Base:148 | P2 |
| NextOverwatchLOSTime | var | Base:349 | P2 |
| NextReloadAttempt | var | Base:319 | P2 |
| NextShoppingTime | var | Base:150 | P2 |
| NextVictoryDance | var | Base:159 | P2 |
| NextVictoryDance | var | Mut:93 | P2 |
| NextWeaponSwitchTime | var | Base:320 | P2 |
| Node | var | Mut:18 | P2 |
| NodeBlacklist | var | Mut:36 | P2 |
| NodeBlockCount | var | Base:155 | P2 |
| NoiseGlanceUntil | var | Base:350 | P2 |
| NotifyAddInventory | function | Base:2113 | @SYS-BASE-SHOP / P4.6 |
| NotifyBlockedShooter | function | Base:3234 | @SYS-BASE-OVERWATCH / P4.11 |
| NotifyBump | event | Base:653 | @SYS-BASE-PERCEPT / P4.2 |
| NotifyBump | event | Bot:1697 | @SYS-BOT-SHOP / P4.32 |
| NotifyBump | event | Bot:855 | @SYS-BOT-SHOP / P4.32 |
| NotifyBump | event | Nav:1234 | @SYS-NAV-HANDLE / P5.7 |
| NotifyHitWall | event | Base:1749 | @SYS-BASE-PERCEPT / P4.2 |
| NotifyHitWall | event | Nav:1225 | @SYS-NAV-HANDLE / P5.7 |
| NotifyJumpApex | event | Logic:1045 | @SYS-LOGIC-UTIL / P4.27 |
| NotifyKilled | function | Bot:684 | @SYS-BOT-COMBAT / P4.30 |
| NotifyKilled | function | Logic:1156 | @SYS-LOGIC-DEATH / P4.26 |
| NotifyTakeHit | function | Base:627 | @SYS-BASE-PERCEPT / P4.2 |
| NumGroups | var | Mut:57 | P2 |
| OBJ_BAIL_COOLDOWN | const | Base:69 | P2 |
| OBJ_BAIL_COOLDOWN | const | Mut:75 | P2 |
| OBJECTIVE_HAZARD_RADIUS | const | Base:95 | P2 |
| OBJECTIVE_HAZARD_ZED_COUNT | const | Base:96 | P2 |
| ObjectiveBailUntil | var | Base:151 | P2 |
| ObjectiveBailUntil | var | Mut:35 | P2 |
| ObjectiveGoal | var | Base:168 | P2 |
| OldRank | var | Mut:104 | P2 |
| OldWaveNum | var | Mut:46 | P2 |
| OnBotKilled | function | Mut:751 | @SYS-MUT-SUCCESSION / P3.5 |
| OnBreakLoseComplete | function | Base:3859 | @SYS-BASE-OVERWATCH / P4.11 |
| OnGruntGrabbed | function | Base:3977 | @SYS-BASE-GRUNT / P4.13 |
| OnReloadComplete | function | Base:4318 | @SYS-BASE-RELOAD / P4.15 |
| OnReloadDriftAnchor | function | Base:4311 | @SYS-BASE-RELOAD / P4.15 |
| OrderAnchor | var | Base:355 | P2 |
| OverwatchOffset | var | Base:348 | P2 |
| OverwatchResetUntil | var | Base:344 | P2 |
| OverwatchSamplePos | var | Base:348 | P2 |
| OverwatchSampleTime | var | Base:349 | P2 |
| OverwatchSlot | var | Base:347 | P2 |
| OverwatchStuckTime | var | Base:349 | P2 |
| OW_STUCK_MIN_DIST_SQ | const | Base:328 | P2 |
| OW_STUCK_MOVE_SQ | const | Base:329 | P2 |
| OW_STUCK_TIME | const | Base:327 | P2 |
| OW_TOGGLE_INTERVAL | const | Base:326 | P2 |
| Owner | var | Mut:19 | P2 |
| PANIC_MULT | const | Base:360 | P2 |
| PANIC_SCATTER_MAX | const | Base:362 | P2 |
| PANIC_SCATTER_MIN | const | Base:361 | P2 |
| PanicActive | var | Base:247 | P2 |
| PanicFlashLoc | var | Base:395 | P2 |
| PanicFlashUntil | var | Base:394 | P2 |
| PanicScanSpeedMultiplier | var | Base:380 | P2 |
| PanicVarianceMultiplier | var | Base:380 | P2 |
| Path | var | Base:7 | P2 |
| PathTokenResetTime | var | Base:259 | P2 |
| PathTokensUsed | var | Base:258 | P2 |
| PawnDied | function | Logic:875 | @SYS-LOGIC-DEATH / P4.26 |
| PendingFormation | var | Base:266 | P2 |
| PendingFormationCount | var | Base:267 | P2 |
| PendingHeal | var | Base:136 | P2 |
| PendingPromotions | var | Mut:107 | P2 |
| PERIMETER_RADIUS | const | Base:53 | P2 |
| Perk | var | Base:131 | P2 |
| PerkPool | var | Mut:153 | P2 |
| PerkPoolCounts | var | Mut:154 | P2 |
| Phase | var | Mut:33 | P2 |
| PHASE_ENROUTE | const | Mut:77 | P2 |
| PHASE_HOLDING | const | Mut:78 | P2 |
| PHASE_IDLE | const | Mut:76 | P2 |
| PHASE_REGROUP | const | Mut:79 | P2 |
| PHASE_SHOPPING | const | Mut:80 | P2 |
| PickBotPerk | function | Mut:2325 | @SYS-MUT-PERK / P3.3 |
| PickCombatStyle | function | Base:2123 | @SYS-BASE-MOVE / P4.4 |
| PickCustomBotName | function | Mut:2135 | @SYS-MUT-SPAWN / P3.2 |
| PickFallbackPerk | function | Mut:2252 | @SYS-MUT-PERK / P3.3 |
| PickFavorite | function | Base:1816 | @SYS-BASE-MOVE / P4.4 |
| PickMove | function | Bot:17 | @SYS-BOT-HUB / P4.28 |
| PickNextEnemy | function | Base:779 | @SYS-BASE-PERCEPT / P4.2 |
| PickNextMove | state | Bot:4 | @SYS-BOT-HUB / P4.28 |
| PickRandEmote | function | Mut:2754 | @SYS-MUT-BOOT / P3.1 |
| PickRetreatMove | function | Logic:954 | @SYS-LOGIC-UTIL / P4.27 |
| PickSquadSpawnPoint | function | Mut:2980 | @SYS-MUT-SPAWN / P3.2 |
| PickStyle | function | Bot:1091 | @SYS-BOT-COMBAT / P4.30 |
| PickStyle | function | Bot:1611 | @SYS-BOT-SHOP / P4.32 |
| PickStyle | function | Bot:300 | @SYS-BOT-MOVE / P4.29 |
| PickStyle | function | Bot:494 | @SYS-BOT-COMBAT / P4.30 |
| PickStyle | function | Bot:726 | @SYS-BOT-COMBAT / P4.30 |
| PlayBotEmote | function | Base:4545 | @SYS-BASE-EMOTE / P4.18 |
| PlayDance | function | Bot:2004 | @SYS-BOT-TERM / P4.33 |
| PlayStyle | var | Base:24 | P2 |
| PMsg | function | Mut:2548 | @SYS-MUT-UTIL / P3.11 |
| PollWaveStart | function | Mut:352 | @SYS-MUT-WAVE / P3.6 |
| PostBeginPlay | function | Mut:170 | @SYS-MUT-BOOT / P3.1 |
| PreBeginPlay | function | Base:405 | @SYS-BASE-BOOT / P4.1 |
| PrevMovePos | var | Base:166 | P2 |
| PrevObjective | var | Mut:89 | P2 |
| ProcessMoveTo | function | Base:1194 | @SYS-BASE-MOVE / P4.4 |
| ProcessMoveToward | function | Base:1219 | @SYS-BASE-MOVE / P4.4 |
| ProcessOverwatchPhase | function | Logic:821 | @SYS-LOGIC-WATCHDOG / P4.23 |
| ProcessPromotionQueue | function | Mut:820 | @SYS-MUT-SUCCESSION / P3.5 |
| ProcessPurchase | function | Base:1939 | @SYS-BASE-SHOP / P4.6 |
| PromoteBot | function | Mut:891 | @SYS-MUT-SUCCESSION / P3.5 |
| PromotionGapTimer | function | Logic:508 | @SYS-LOGIC-WATCHDOG / P4.23 |
| PromotionRequest | struct | Mut:100 | @SYS-MUT-PLATOON / P3.4 (structs) |
| PropagateAnchorToFollowers | function | Mut:661 | @SYS-MUT-PLATOON / P3.4 |
| PruneInvalidBots | function | Mut:531 | @SYS-MUT-PLATOON / P3.4 |
| PullBotFromNearestGroup | function | Mut:1075 | @SYS-MUT-SUCCESSION / P3.5 |
| RandGoal | var | Base:167 | P2 |
| RangeCacheSq | var | Base:315 | P2 |
| RangeCacheWeapon | var | Base:314 | P2 |
| RangedHealCooldownEnds | var | Mut:151 | P2 |
| RangedHealTargets | var | Mut:150 | P2 |
| RangeMedicGun | var | Base:142 | P2 |
| REARGUARD_OFFSET | const | Mut:70 | P2 |
| ReassertScoreboardFlags | function | Bot:1930 | @SYS-BOT-TERM / P4.33 |
| ReassignBotToGroup | function | Mut:1154 | @SYS-MUT-SUCCESSION / P3.5 |
| RebuildHierarchy | function | Mut:2780 | @SYS-MUT-PLATOON / P3.4 |
| ReceiveOverwatchState | function | Base:3762 | @SYS-BASE-OVERWATCH / P4.11 |
| ReceivePanic | function | Base:4205 | @SYS-BASE-PANIC / P4.14 |
| ReceiveReloadDrift | function | Base:4287 | @SYS-BASE-RELOAD / P4.15 |
| ReceiveWedgeOrder | function | Base:4417 | @SYS-BASE-WEDGE / P4.17 |
| ReEnableAmmoFactories | function | Mut:3019 | @SYS-MUT-SPAWN / P3.2 |
| RefreshRoleNameTag | function | Base:3132 | @SYS-BASE-RANK / P4.9 |
| RefreshSquadZedCache | function | Base:3584 | @SYS-BASE-ZEDS / P4.8 |
| RegisterBot | function | Mut:334 | @SYS-MUT-SPAWN / P3.2 |
| RegisterRangedHealTarget | function | Mut:900 | @SYS-MUT-HEALCOOL / P3.10 |
| REGROUP_DURATION | const | Base:113 | P2 |
| REGROUP_DURATION | const | Mut:82 | P2 |
| REGROUP_HARD_TIMEOUT | const | Base:114 | P2 |
| REGROUP_HARD_TIMEOUT | const | Mut:83 | P2 |
| REGROUP_HOLD_DIST_SQ | const | Base:115 | P2 |
| REGROUP_SCAN_RADIUS | const | Mut:86 | P2 |
| ReissueSquadOrder | function | Mut:1748 | @SYS-MUT-ORDERS / P3.7 |
| ReleaseSquadSlots | function | Mut:1591 | @SYS-MUT-ORDERS / P3.7 |
| RELOAD_DRIFT_DIST | const | Base:363 | P2 |
| RELOAD_DRIFT_LEASE | const | Base:364 | P2 |
| ReloadDriftLoc | var | Base:384 | P2 |
| ReloadDriftOffset | var | Base:384 | P2 |
| ReloadDriftUntil | var | Base:383 | P2 |
| ReloadPullAnchor | var | Base:384 | P2 |
| ReloadPullStamp | var | Base:383 | P2 |
| RelocateBotsToAmmoCrates | function | Mut:2904 | @SYS-MUT-SPAWN / P3.2 |
| RemoveBot | function | Mut:2398 | @SYS-MUT-SPAWN / P3.2 |
| Replacement | var | Mut:103 | P2 |
| ReplicatedEvent | event | Logic:1057 | @SYS-LOGIC-DEATH / P4.26 |
| RequestLeaderDemotion | function | Mut:1053 | @SYS-MUT-SUCCESSION / P3.5 |
| RequestReroute | function | Logic:499 | @SYS-LOGIC-GRUNTMOVE / P4.24 |
| RequestRerouteWithBlock | function | Base:2973 | @SYS-BASE-FORM / P4.10 |
| RESCUE_DURATION | const | Base:341 | P2 |
| RESCUE_RANGE_SQ | const | Base:340 | P2 |
| RescueLoc | var | Base:348 | P2 |
| RescueUntil | var | Base:350 | P2 |
| ResetPerkPool | function | Mut:2292 | @SYS-MUT-PERK / P3.3 |
| ResetStuckState | function | Logic:1373 | @SYS-LOGIC-MOVEVAL / P4.25 |
| ResolvePerkByName | function | Mut:2272 | @SYS-MUT-PERK / P3.3 |
| RespawnBots | function | Mut:2107 | @SYS-MUT-SPAWN / P3.2 |
| Restart | function | Base:534 | @SYS-BASE-BOOT / P4.1 |
| RestartBot | function | Mut:2433 | @SYS-MUT-SPAWN / P3.2 |
| RETREAT_HEAVY_RADIUS | const | Base:67 | P2 |
| RETREAT_ZED_CLEAR_COUNT | const | Base:66 | P2 |
| RETREAT_ZED_RADIUS | const | Base:64 | P2 |
| RETREAT_ZED_TRIGGER_COUNT | const | Base:65 | P2 |
| Roaming | state | Bot:261 | @SYS-BOT-MOVE / P4.29 |
| SampleSquadSlots | function | Mut:1487 | @SYS-MUT-ORDERS / P3.7 |
| ScanMask | var | Base:268 | P2 |
| ScanRoomForFormation | function | Base:2702 | @SYS-BASE-FORM / P4.10 |
| Score | var | Mut:105 | P2 |
| SectorLastTime | var | Base:350 | P2 |
| SectorScanPhase | var | Base:350 | P2 |
| SeedGruntGates | function | Base:3178 | @SYS-BASE-RANK / P4.9 |
| SeeMonster | function | Base:645 | @SYS-BASE-PERCEPT / P4.2 |
| SeePlayer | function | Base:637 | @SYS-BASE-PERCEPT / P4.2 |
| SellWeapon | function | Base:1840 | @SYS-BASE-SHOP / P4.6 |
| SerpentineTime | var | Base:147 | P2 |
| SetBotRank | function | Base:3223 | @SYS-BASE-RANK / P4.9 |
| SetEnemy | function | Base:805 | @SYS-BASE-PERCEPT / P4.2 |
| SetHoldObjective | function | Mut:1297 | @SYS-MUT-WAVE / P3.6 |
| SetSquadCrouchHold | function | Base:3023 | @SYS-BASE-CQB / P4.12 |
| SetupSquadSpawns | function | Mut:2853 | @SYS-MUT-SPAWN / P3.2 |
| ShotgunEffectiveRangeUU | var | Base:316 | P2 |
| ShouldAbortRetreat | function | Base:2435 | @SYS-BASE-HEALQ / P4.21 |
| ShouldDoVictoryDance | function | Mut:2765 | @SYS-MUT-BOOT / P3.1 |
| ShouldNadeEnemies | function | Logic:261 | @SYS-LOGIC-UTIL / P4.27 |
| ShouldReload | function | Base:3259 | @SYS-BASE-WEAPON / P4.19 |
| ShouldTacticalRetreat | function | Base:2293 | @SYS-BASE-ZEDS / P4.8 |
| ShouldThrowGrenade | function | Base:3378 | @SYS-BASE-WEAPON / P4.19 |
| ShuffleActiveBots | function | Mut:518 | @SYS-MUT-PLATOON / P3.4 |
| SimulateBashHit | function | Base:1002 | @SYS-BASE-FIRE / P4.3 |
| SINGLE_FILE_SPACING | const | Base:52 | P2 |
| SIREN_CHECK_RADIUS | const | Base:97 | P2 |
| SLDecisionLoop | function | Base:2627 | @SYS-BASE-RANK / P4.9 |
| SLGrenadeCheck | function | Base:3456 | @SYS-BASE-WEAPON / P4.19 |
| SLGrenadeLOSPhase | function | Base:3478 | @SYS-BASE-WEAPON / P4.19 |
| SlotLocs | var | Mut:37 | P2 |
| Slots | var | Mut:32 | P2 |
| SpawnBotWithRank | function | Mut:2994 | @SYS-MUT-SPAWN / P3.2 |
| SpawnSquadAt | function | Mut:2963 | @SYS-MUT-SPAWN / P3.2 |
| SPOT_RADIUS_SQ | const | Base:89 | P2 |
| SquadID | var | Mut:27 | P2 |
| SquadIdleStamp | var | Mut:120 | P2 |
| SquadLeader | var | Base:27 | P2 |
| SquadLeaders | var | Base:357 | P2 |
| SquadMembers | var | Base:353 | P2 |
| SquadOrder | struct | Mut:25 | @SYS-MUT-PLATOON / P3.4 (structs) |
| SquadOrders | var | Mut:56 | P2 |
| SquadSeedAngle | var | Mut:38 | P2 |
| SquadZedCache | var | Base:297 | P2 |
| SquadZedCount | var | Base:298 | P2 |
| StartCaptainLoop | function | Base:3217 | @SYS-BASE-RANK / P4.9 |
| StartEmoteEchoTimer | function | Base:4501 | @SYS-BASE-EMOTE / P4.18 |
| StartLtHumanBounding | function | Base:4337 | @SYS-BASE-LTBOUND / P4.16 |
| StartLTLoop | function | Base:3211 | @SYS-BASE-RANK / P4.9 |
| StartSLLoop | function | Base:3205 | @SYS-BASE-RANK / P4.9 |
| StartTime | var | Mut:34 | P2 |
| StopAdjusting | function | Base:1733 | @SYS-BASE-FIRE / P4.3 |
| StrafeTowardPoint | function | Base:1146 | @SYS-BASE-MOVE / P4.4 |
| STUCK_DIST_SQ | const | Base:50 | P2 |
| STUCK_SAMPLE_INTERVAL | const | Base:49 | P2 |
| StuckCounter | var | Base:345 | P2 |
| StyleCrouchUntil | var | Base:350 | P2 |
| Subordinates | var | Base:253 | P2 |
| Supervisor | var | Base:254 | P2 |
| SW_ARRIVE_SQ | const | Base:330 | P2 |
| SW_DEG_TO_URU | const | Base:334 | P2 |
| SW_SCAN_AMP_DEG | const | Base:331 | P2 |
| SW_SCAN_OMEGA | const | Base:332 | P2 |
| SW_TWO_PI | const | Base:333 | P2 |
| SwitchToBestWeapon | function | Base:1045 | @SYS-BASE-SHOP / P4.6 |
| SYG_DISTANCE_SQ | const | Base:61 | P2 |
| SyncLineFocus | function | Base:2893 | @SYS-BASE-OVERWATCH / P4.11 |
| SyncSquadLeaders | function | Mut:471 | @SYS-MUT-PLATOON / P3.4 |
| SyringeRechargeEnd | var | Base:212 | P2 |
| TacticalRetreat | state | Bot:888 | @SYS-BOT-COMBAT / P4.30 |
| Target | var | Base:171 | P2 |
| TargetLowHealth | function | Base:727 | @SYS-BASE-PERCEPT / P4.2 |
| TempBlockPath | var | Base:170 | P2 |
| TempBlockTime | var | Base:158 | P2 |
| Tick | function | Base:1322 | @SYS-BASE-MOVE / P4.4 |
| Tick | function | Bot:1796 | @SYS-BOT-MOVE / P4.29 |
| TimeOut | function | Bot:1222 | @SYS-BOT-HEAL / P4.31 |
| TimeOut | function | Bot:1322 | @SYS-BOT-HEAL / P4.31 |
| TimeOut | function | Bot:1442 | @SYS-BOT-HEAL / P4.31 |
| Timer | event | Bot:633 | @SYS-BOT-COMBAT / P4.30 |
| Timer | function | Bot:1010 | @SYS-BOT-COMBAT / P4.30 |
| Timer | function | Bot:1139 | @SYS-BOT-COMBAT / P4.30 |
| Timer | function | Bot:1650 | @SYS-BOT-COMBAT / P4.30 |
| Timer | function | Bot:1750 | @SYS-BOT-COMBAT / P4.30 |
| Timer | function | Mut:311 | @SYS-MUT-BOOT / P3.1 |
| ToggleOverwatchPhase | function | Base:3638 | @SYS-BASE-OVERWATCH / P4.11 |
| TrackReloadState | function | Base:4324 | @SYS-BASE-RELOAD / P4.15 |
| TRADER_GIVEUP_COOLDOWN | const | Base:100 | P2 |
| TRADER_MAX_RETRIES | const | Base:99 | P2 |
| TRADER_REFORM_REMAINING | const | Base:123 | P2 |
| TRADER_ROAM_RADIUS | const | Base:121 | P2 |
| TRADER_ROAM_RADIUS_SQ | const | Base:122 | P2 |
| TraderList | var | Mut:41 | P2 |
| TraderRetryCount | var | Base:232 | P2 |
| TRIAGE_INTERVAL | const | Base:76 | P2 |
| TryBreakFree | function | Base:945 | @SYS-BASE-OBJ / P4.7 |
| TryIssueSafeAnchor | function | Base:3040 | @SYS-BASE-CQB / P4.12 |
| TryThrowGrenade | function | Base:3422 | @SYS-BASE-WEAPON / P4.19 |
| UnregisterBot | function | Mut:343 | @SYS-MUT-SPAWN / P3.2 |
| UpdateCoverCrouch | function | Base:4043 | @SYS-BASE-CQB / P4.12 |
| UpdateCQBFormation | function | Logic:1288 | @SYS-LOGIC-MOVEVAL / P4.25 |
| UpdateGruntOffset | function | Logic:327 | @SYS-LOGIC-GRUNTMOVE / P4.24 |
| UpdateHoldAreaDrift | function | Base:4585 | @SYS-BASE-ZEDS / P4.8 |
| UpdateMacroWaypoints | function | Mut:553 | @SYS-MUT-PLATOON / P3.4 |
| UpdateOverwatchMovement | function | Base:3778 | @SYS-BASE-OVERWATCH / P4.11 |
| UpdateOverwatchTimer | function | Base:3680 | @SYS-BASE-OVERWATCH / P4.11 |
| UpdatePanicBroadcast | function | Base:4188 | @SYS-BASE-PANIC / P4.14 |
| UpdatePillarOfSaltTracking | function | Logic:1310 | @SYS-LOGIC-MOVEVAL / P4.25 |
| UpdateRoleNameTag | function | Base:3104 | @SYS-BASE-RANK / P4.9 |
| UpdateSectorWatch | function | Base:3873 | @SYS-BASE-OVERWATCH / P4.11 |
| UpdateWedgeMode | function | Base:4436 | @SYS-BASE-WEDGE / P4.17 |
| ValidateAndNudgeSpawn | function | Base:2165 | @SYS-BASE-BOOT / P4.1 |
| ValidateOffsetTarget | function | Base:2955 | @SYS-BASE-FORM / P4.10 |
| ValidPoints | var | Mut:90 | P2 |
| VANGUARD_OFFSET | const | Mut:69 | P2 |
| Vel | var | Mut:116 | P2 |
| VerifyWeapon | function | Logic:553 | @SYS-LOGIC-HEAL / P4.22 |
| VictoryDance | state | Bot:1972 | @SYS-BOT-TERM / P4.33 |
| VIP_ESCORT_MIN_SIZE | const | Mut:67 | P2 |
| VIP_TRIAGE_BONUS_PCT | const | Base:78 | P2 |
| VIP_TRIAGE_GATE_PCT | const | Base:77 | P2 |
| VIPController | var | Mut:59 | P2 |
| WAVE_POLL_INTERVAL | const | Mut:87 | P2 |
| WdEscStep | var | Base:398 | P2 |
| WdIdleStartLoc | var | Base:403 | P2 |
| WdLastHubContactTime | var | Base:400 | P2 |
| WdLastMoveIntentTime | var | Base:399 | P2 |
| WdLastStepTime | var | Base:401 | P2 |
| WdProgressGoalD2 | var | Base:402 | P2 |
| WEDGE_LEASE | const | Base:370 | P2 |
| WEDGE_REAR_OFFSET | const | Base:369 | P2 |
| WedgeExpireTime | var | Base:388 | P2 |
| WedgeHuman | var | Base:387 | P2 |
| ZED_COUNT_INTERVAL | const | Base:93 | P2 |
| Zone | var | Mut:29 | P2 |

# PART 1 -- SDK Manifest

Two tables: **1.1 VERIFIED** -- every SDK symbol the mod calls, grep-confirmed against `D:\SteamLibrary\steamapps\common\killingfloor2\Development\Src` (4050 `.uc` files, recursive). **1.2 NOT FOUND** -- symbols the mod uses that were NOT found anywhere in the SDK tree. These are either compiled into C++ (native) or defined in a file outside the searched tree; their runtime behaviour is **SDK behaviour not verified**. Do not change call sites based on assumptions about them.

## 1.1 VERIFIED (grep-confirmed, cite as `[SDK <relpath>:<line>]`)

| SDK symbol | Kind | Location | Notes |
|---|---|---|---|
| `MoveTo` | native latent | [SDK Engine/Classes/Controller.uc:1193] | Only usable inside states of Controller derivatives. |
| `MoveToDirectNonPathPos` | native latent | [SDK Engine/Classes/Controller.uc:1208] | |
| `MoveToward` | native latent | [SDK Engine/Classes/Controller.uc:1220] | |
| `WaitForLanding` | native latent | [SDK Engine/Classes/Controller.uc:1344] | |
| `FindPathToward` | function | [SDK Engine/Classes/AIController.uc:248] | Returns `(bool bPathFound, float PathLength)`. Mod's only call site: [Nav:645-688]. |
| `ActorReachable` | function | [SDK Engine/Classes/AIController.uc:240] | Mod's only call site: [Nav:587-640]. |
| `SetTimer` | function | [SDK Engine/Classes/Actor.uc:2036] | `SetTimer(interval, bLoop, 'TimerName')`. |
| `VisibleCollidingActors` | native iterator | [SDK Engine/Classes/Actor.uc:2365] | Valid UE3 iterator. `foreach VisibleCollidingActors(Class, Arr, Radius)`. |
| `LatentActions` | property | [SDK Engine/Classes/Actor.uc:3335] | `LatentActions.Abort()` called in [Logic:875-914] on death. |
| `RadiusNavigationPoints` | function | [SDK Engine/Classes/WorldInfo.uc:1636] | Mod calls at [Mut:678-686], [Mut:688-703], [Logic:954-1002]. Returns navigation points; FIRST hit used, not nearest (see Appendix C). |
| `AllPawns` | property | [SDK Engine/Classes/WorldInfo.uc:1663] | Iterated in [Bot:1064-1190]. |
| `AddDefaultInventory` | function | [SDK Engine/Classes/Pawn.uc:3209], [SDK KFGame/Classes/KFPawn.uc:1789], [SDK KFGame/Classes/KFPawn_Human.uc:458], [SDK KFGame/Classes/KFPerk.uc:1102] | |
| `PlayHeal` | function | [SDK KFGame/Classes/KFPawn.uc:3725] | Called in HealingSelf state [Bot:1192-1294]. |
| `SetCharacterArch` | function | [SDK KFGame/Classes/KFPawn.uc:1260] | Called in RestartBot [Mut:2433-2533] (after SetTeam). |
| `SetPlayerDefaults` | function | [SDK KFGame/Classes/KFGameInfo.uc:1667] | |
| `bOnePlayerAtStart` | property | [SDK KFGame/Classes/KFGameInfo.uc:49] | |
| `CreateTemporaryBlockedPath` | event (bool) | [SDK KFGame/Classes/KFAIController.uc:984] | Plan B: mod overrides as no-op [Nav:965-972]; SDK side not relied upon. |
| `CreateTemporaryBlockedReach` | function (bool) | [SDK KFGame/Classes/KFAIController.uc:1016] | Same as above. |
| `Action_Idle` | state | [SDK KFGame/Classes/KFAIController.uc:6934] | |
| `bIsHeadless` | property | [SDK KFGame/Classes/KFPawn_Monster.uc:77] | Hub P7 combat gate [Bot:210-229]. |
| `bHasSpawnedIn` | property | [SDK KFGame/Classes/KFPlayerReplicationInfo.uc:30] | Reasserted in Dead state [Bot:1913-1946]. |
| `KFPerk` | class | [SDK KFGame/Classes/KFPerk.uc:10] | Perk gacha target type. |
| `KFPickupFactory` | class | [SDK KFGame/Classes/KFPickupFactory.uc:9] | FindCollectable target [Logic:1004-1043]. |
| `KFDoorMarker` | class | [SDK KFGame/Classes/KFDoorMarker.uc:9] | Ghost-Door detection [Logic:1310-1363]. |
| `KFDoorActor` | class | [SDK KFGame/Classes/KFDoorActor.uc:11] | Same system. |
| `KFGfxObject_TraderItems` | class | [SDK KFGame/Classes/KFGfxObject_TraderItems.uc:11] | |
| `KFWeap_HealerBase` | class | [SDK KFGame/Classes/KFWeap_HealerBase.uc:10] | HealingSelf/HealOther equip check. |
| `KFWeap_MedicBase` | class | [SDK KFGame/Classes/KFWeap_MedicBase.uc:10] | Used in HealRanged EndState (see Appendix C item 6). |
| `KFDroppedPickup_Cash` | class | [SDK KFGame/Classes/KFDroppedPickup_Cash.uc:10] | DonatingMoney DropMoney. |
| `KFMapObjective_DoshHold` | class | [SDK KFGameContent/Classes/KFMapObjective_DoshHold.uc:12] | |
| `KFSeqEvent_PlayerDied` | class | [SDK KFGame/Classes/KFSeqEvent_PlayerDied.uc:9] | ActivatePlayerDiedSequenceEvents [Logic:916-952]. |
| `SeqEvent_Death` | class | [SDK Engine/Classes/SeqEvent_Death.uc:7] | |
| `SeqEvent_PlayerSpawned` | class | [SDK Engine/Classes/SeqEvent_PlayerSpawned.uc:7] | |
| `SequenceEvent` | class | [SDK Engine/Classes/SequenceEvent.uc:9] | |
| `FindSeqObjectsByClass` | function | [SDK Engine/Classes/Sequence.uc:335] | |
| `KFWeapon` | class | [SDK KFGame/Classes/KFWeapon.uc:10] | |

## 1.2 NOT FOUND in SDK tree (SDK behaviour not verified)

Used by the mod, but no definition found in any of the 4050 SDK `.uc` files. Most are likely native C++ properties/functions (compiled into the binaries). Call sites are documented in the system sections; treat these as **opaque** for logic reasoning.

| Symbol | Used in (mod) | Note |
|---|---|---|
| `HealthToRegen` | [Bot:1192-1294] (+=20 in HealingSelf) | Native KFPawn property (inferred). |
| `HealthRegenRate` | [Bot:1192-1294] (GiveHealthOverTime) | Native KFPawn property (inferred). |
| `DoSpecialMove` | [Bot:1972-2075] (PlayDance) | Native Pawn property. |
| `GetAnimInterruptTime` | [Bot:1192-1294] | Native. |
| `GetTotalAmmoAmount` | [Bot:41-51] (P5 SYG `bHasAmmo`) | Native KFWeapon/KFPawn (inferred). |
| `GetEmoteArray` | [Mut:2745-2763] (InitEmotes/PickRandEmote) | Native. |
| `FastTrace` | [Logic:202-259], [Bot:1064-1190], [Bot:1972-2075] | Native Pawn trace. |
| `TimeSeconds` | various (all hub gates) | Native `time`-family alias (inferred). |
| `GetAdjustedRespawnCash` | [Bot:1778-1911] (DonatingMoney) | Native KFPlayerReplicationInfo (inferred). |
| `GetLivingPlayerCount` | [Logic:916-952] | Native. |
| `GetNextPlayerID` | [Mut:2433-2533] (RestartBot) | Native. |
| `IsBossWave` | [Base:2463-2474] (IsBossWaveActive) | Native KFGameInfo (inferred). |
| `SpawnDefaultPawnFor` | [Mut:2433-2533] (RestartBot) | Native KFGameInfo/Pawn. |
| `NextMutator` | [Mut:170-269] (PostBeginPlay) | Native. |
| `CurrentObjective` | [Mut:1244-1295] (CheckWave) | Native. |
| `bPickupHidden` | [Logic:1004-1043] (FindCollectable skip) | Native KFPickupFactory property (inferred). |
| `Encompasses` | [Mut:2107-2125] (RespawnBots) | Vector math helper. |
| `bDisableTeamCollision` | [Mut:2433-2533] (RestartBot) | Native Pawn property. |
| `GameSeq` | [Logic:916-952] | Class file not found; `Sequence` base found. |
| `KFMutator` | [Mut:1-159] (super class) | File absent from SDK tree; class is native or in a non-`.uc` source. |
| `KFGameInfoReplicationInfo` | [Mut:170-269] | File not found. |
| `KFMapObjective` | [Mut:1244-1295] (base type) | Base class file not found; `KFMapObjective_DoshHold` IS found. |
| `KFPickup_Cash` | [Mut:3008-3017] (HideAllPickups) | File not found; `KFDroppedPickup_Cash` IS found. |
| `KFSeqEvent` | [Logic:916-952] (base type) | Base class file not found; `KFSeqEvent_PlayerDied` IS found. |

# PART 2 -- File Metrics & Master Constants Registry

## 2.1 File Metrics

Source of truth: `symbols.json` (built by `build_symbols.py` from the 5 source files). Line counts verified against `[System.IO.File]::ReadAllLines().Count`.

| File | Lines | SHA-256 (8) | Extends | Functions | Events | States | Structs | Enums | Vars | Consts | DefaultProps |
|---|---|---|---|---|---|---|---|---|---|---|---|
| KF2BotsMut.uc | 3037 | 607a3e67 | KFMutator | 97 | 0 | 0 | 5 | 0 | 63 | 21 | 1 |
| KF2BotsFollowNavBase.uc | 1552 | d543db64 | AIController (`abstract` [Nav:29]) | 36 | 5 | 2 | 0 | 2 | 97 | 0 | 1 |
| KF2BotBase.uc | 4615 | 82491dfb | KF2BotsFollowNavBase | 158 | 3 | 0 | 1 | 1 | 217 | 91 | 1 |
| KF2BotLogic.uc | 1377 | ffc4906a | KF2BotBase | 38 | 2 | 0 | 0 | 0 | 0 | 0 | 0 |
| KF2Bot.uc | 2075 | 17aad4ee | KF2BotLogic | 41 | 37 | 18 | 0 | 0 | 0 | 0 | 0 |

Inheritance chain: KFMutator --> (Mut) ; AIController --> FollowNavBase --> BotBase --> BotLogic --> Bot. Total symbols: 943 (see 0.7 index).

## 2.2 Master Constants Registry

All `const` symbols across the codebase (112 total: Mut 21 + BotBase 91; BotLogic/Nav/Bot have none -- all numbers there are inline literals or config vars). Values are exact from source.

### 2.2.1 KF2BotsMut.uc (21)

| Const | Line | Value |
|---|---|---|
| `CUR_CONFIGVER` | [5] | 3 |
| `MIN_GROUPS` | [64] | 2 |
| `MAX_GROUPS` | [65] | 4 |
| `BOTS_PER_GROUP_TARGET` | [66] | 3 |
| `VIP_ESCORT_MIN_SIZE` | [67] | 2 |
| `GROUP_DISSOLVE_SIZE` | [68] | 1 |
| `VANGUARD_OFFSET` | [69] | 2000.0 |
| `REARGUARD_OFFSET` | [70] | 2000.0 |
| `CHOKEPOINT_LATERAL_OFFSET` | [71] | 1000.0 |
| `NAV_SEARCH_RADIUS` | [72] | 1500.0 |
| `MACRO_WAYPOINT_INTERVAL` | [73] | 3.0 |
| `OBJ_BAIL_COOLDOWN` | [75] | 8.0 |
| `PHASE_IDLE` | [76] | 0 |
| `PHASE_ENROUTE` | [77] | 1 |
| `PHASE_HOLDING` | [78] | 2 |
| `PHASE_REGROUP` | [79] | 3 |
| `PHASE_SHOPPING` | [80] | 4 |
| `REGROUP_DURATION` | [82] | 5.0 |
| `REGROUP_HARD_TIMEOUT` | [83] | 6.0 |
| `REGROUP_SCAN_RADIUS` | [86] | 5000.0 |
| `WAVE_POLL_INTERVAL` | [87] | 1.0 |

### 2.2.2 KF2BotBase.uc (91)

| Const | Line | Value |
|---|---|---|
| `CQB_TRACE_RADIUS_SQ` | [46] | 90000.0 |
| `CQB_TRACE_INTERVAL` | [47] | 1.0 |
| `CQB_PROBE_DIST` | [48] | 150.0 |
| `STUCK_SAMPLE_INTERVAL` | [49] | 3.0 |
| `STUCK_DIST_SQ` | [50] | 10000.0 |
| `DOOR_CHECK_RADIUS` | [51] | 200.0 |
| `SINGLE_FILE_SPACING` | [52] | 130.0 |
| `PERIMETER_RADIUS` | [53] | 220.0 |
| `DEG_TO_RAD` | [54] | 0.0174532925 |
| `SYG_DISTANCE_SQ` | [61] | 1000000.0 |
| `BOSS_HEALTH_THRESHOLD` | [62] | 5000 |
| `RETREAT_ZED_RADIUS` | [64] | 500.0 |
| `RETREAT_ZED_TRIGGER_COUNT` | [65] | 4 |
| `RETREAT_ZED_CLEAR_COUNT` | [66] | 2 |
| `RETREAT_HEAVY_RADIUS` | [67] | 300.0 |
| `FOLLOWER_DRIFT_SQ` | [68] | 250000.0 |
| `OBJ_BAIL_COOLDOWN` | [69] | 8.0 |
| `FOLLOW_ESCAPE_COOLDOWN` | [70] | 1.5 |
| `HUNT_ZED_THRESHOLD` | [71] | 15 |
| `HUNT_SCAN_RADIUS` | [72] | 5000.0 |
| `GLOBAL_ZED_RADIUS` | [73] | 8000.0 |
| `GLOBAL_ZED_COUNT_INTERVAL` | [74] | 3.0 |
| `TRIAGE_INTERVAL` | [76] | 2.0 |
| `VIP_TRIAGE_GATE_PCT` | [77] | 50.0 |
| `VIP_TRIAGE_BONUS_PCT` | [78] | 15.0 |
| `HEAL_MAX_NEED_PCT` | [84] | 80.0 |
| `HEAL_MIN_NEED_PCT` | [85] | 60.0 |
| `ENEMY_SCAN_INTERVAL` | [87] | 0.5 |
| `ENEMY_SCAN_RADIUS` | [88] | 1500.0 |
| `SPOT_RADIUS_SQ` | [89] | 4000000.0 |
| `LEASH_DROP_DIST_SQ` | [90] | 5760000.0 |
| `LEASH_COOLDOWN` | [91] | 2.0 |
| `ZED_COUNT_INTERVAL` | [93] | 1.0 |
| `OBJECTIVE_HAZARD_RADIUS` | [95] | 800.0 |
| `OBJECTIVE_HAZARD_ZED_COUNT` | [96] | 3 |
| `SIREN_CHECK_RADIUS` | [97] | 1200.0 |
| `TRADER_MAX_RETRIES` | [99] | 3 |
| `TRADER_GIVEUP_COOLDOWN` | [100] | 10.0 |
| `AUDIT_INTENT_TIMEOUT` | [103] | 10.0 |
| `AUDIT_HUB_TIMEOUT` | [104] | 20.0 |
| `AUDIT_IDLE_STUCK_DELTA` | [105] | 50.0 |
| `AUDIT_ATTACH_RADIUS` | [106] | 3000.0 |
| `AUDIT_WD_PERIOD` | [107] | 1.5 |
| `AUDIT_WD_STEP_COOLDOWN` | [108] | 5.0 |
| `REGROUP_DURATION` | [113] | 5.0 |
| `REGROUP_HARD_TIMEOUT` | [114] | 6.0 |
| `REGROUP_HOLD_DIST_SQ` | [115] | 10000.0 |
| `TRADER_ROAM_RADIUS` | [121] | 3000.0 |
| `TRADER_ROAM_RADIUS_SQ` | [122] | 9000000.0 |
| `TRADER_REFORM_REMAINING` | [123] | 5.0 |
| `FORM_SCAN_DIST` | [262] | 150.0 |
| `FORM_LINE_DIST` | [263] | 650.0 |
| `BOTFM_PRIMARY` | [292] | 0 |
| `BOTFM_RELOAD` | [293] | 2 |
| `BOTFM_BASH` | [294] | 3 |
| `BOTFM_GRENADE` | [295] | 4 |
| `OW_TOGGLE_INTERVAL` | [326] | 1.5 |
| `OW_STUCK_TIME` | [327] | 1.0 |
| `OW_STUCK_MIN_DIST_SQ` | [328] | 10000.0 |
| `OW_STUCK_MOVE_SQ` | [329] | 900.0 |
| `SW_ARRIVE_SQ` | [330] | 22500.0 |
| `SW_SCAN_AMP_DEG` | [331] | 15.0 |
| `SW_SCAN_OMEGA` | [332] | 1.5707963 |
| `SW_TWO_PI` | [333] | 6.2831853 |
| `SW_DEG_TO_URU` | [334] | 182.0444 |
| `CQB_BASH_SQ` | [335] | 14400.0 |
| `CQB_MID_SQ` | [336] | 32400.0 |
| `CQB_BASH_INTERVAL` | [337] | 0.8 |
| `CQB_STEPBACK_SPEED` | [338] | 100.0 |
| `COVER_RANGE_SQ` | [339] | 640000.0 |
| `RESCUE_RANGE_SQ` | [340] | 1000000.0 |
| `RESCUE_DURATION` | [341] | 5.0 |
| `HEAR_RANGE_SQ` | [342] | 4000000.0 |
| `PANIC_MULT` | [360] | 2.0 |
| `PANIC_SCATTER_MIN` | [361] | 200.0 |
| `PANIC_SCATTER_MAX` | [362] | 400.0 |
| `RELOAD_DRIFT_DIST` | [363] | 100.0 |
| `RELOAD_DRIFT_LEASE` | [364] | 1.0 |
| `HUMAN_BOUND_INTERVAL` | [365] | 1.5 |
| `HUMAN_PUSH_DOT` | [366] | 0.5 |
| `HUMAN_MIN_SPEED_SQ` | [367] | 10000.0 |
| `HUMAN_LT_RANGE_SQ` | [368] | 250000.0 |
| `WEDGE_REAR_OFFSET` | [369] | 150.0 |
| `WEDGE_LEASE` | [370] | 2.5 |
| `EMOTE_RADIUS_SQ` | [371] | 22500.0 |
| `EMOTE_CHANCE` | [372] | 0.30 |
| `EMOTE_ROLL_COOLDOWN` | [373] | 6.0 |
| `BREATH_OMEGA` | [374] | 0.3 |
| `DRIFT_RATE` | [375] | 0.8333333 |
| `DRIFT_MIN_DIST_SQ` | [376] | 10000.0 |
| `DRIFT_MAX_TOTAL` | [377] | 300.0 |

Note: `BOTFM_*` values are 0/2/3/4 (value 1 is skipped -- reserved/unassigned in [Base:292-295]), NOT a contiguous 0--3 range.

### 2.2.3 KF2BotLogic.uc / KF2BotsFollowNavBase.uc / KF2Bot.uc (0)

No `const` symbols. Numeric thresholds in these files are either inline literals (e.g. hub gates in [Bot:17-253]) or **config vars** (see 0.5 lookup table rows referencing defaultproperties, e.g. [Nav:1494-1552]).

# PART 3 -- KF2BotsMut.uc Systems (M1--M11)

Primary file: KF2BotsMut.uc (3037 lines, `607a3e67`), class `KF2BotsMut` extends `KFMutator`, `config(BotsMut)`. Citations `[123]` = KF2BotsMut.uc line.

---

### M1 Boot & config   @SYS-MUT-BOOT      Primary file: KF2BotsMut.uc
#### 1. PLAIN-ENGLISH SUMMARY
This is the mod's power switch. When the map loads, the mutator grabs the game's survival mode object, fills in any settings the player never configured, and starts three clocks: a 1-second wave watcher, a 3-second hierarchy refresh, and a 3-second human-position cache. In standalone play it also spawns the initial bots.
#### 2. EXPLANATION
`PostBeginPlay` [170-269] links into the mutator chain via `NextMutator`, resolves `KF = KFGameInfo_Survival(WorldInfo.GetGameInfo())`, applies config defaults **only when unset** (NumBots=7, BotMaxPerkLv=25, BotsDamageScale=1.0, ZedCountScaling=0.2, MaxZedsForFailsafe=3, FailsafeActivationDelay=3.0, HealCylinderRadius=400.0, HealCylinderHeight=300.0, HealMinHealthPct=60.0, MaxBotsPerPerk=2), spawns the KF2BotChat actor, and arms the three timers: [262] `SetTimer(WAVE_POLL_INTERVAL, true, 'PollWaveStart')`, [266] `SetTimer(3.0, true, 'RebuildHierarchy')`, [267] `SetTimer(3.0, true, 'CacheHumans')`. `MatchStarting` [289-309] is standalone-mode entry: it calls `AddBot()` NumBots times, then arms an unnamed 1.0s looping timer [305] (drives `Timer()`) and `SetTimer(0.1, true, 'CheckWave')` [307]. `Timer` [311-332] trims/adds bots toward NumBots/MinimumBots as player count changes. `defaultproperties` [3031-3037] holds `MaxEmoteCount=-1` [3036] and a comment claiming NumBots=6 -- the real PostBeginPlay default is 7 (see Appendix C).
#### 3. LOGIC PIPELINE
Map load --> PostBeginPlay (defaults + 3 timers) --> PollWaveStart (1s) --> wave change --> platoon init. Standalone: MatchStarting --> NxAddBot --> Timer + CheckWave loops.
#### 4. INPUTS / OUTPUTS
Input: GameInfo, config (config(BotsMut)), PlayerStarts. Output: all Mut state (KF, HoldVolume, ActiveBots, TraderList), timers. The mutator owns `defaultproperties` [3031-3037].
#### 5. FLOW   @FLOW-MUT-BOOT
```
POSTBEGINPLAY [170]
|--> NextMutator chain + KF = GameInfo_Survival
|--> apply config defaults ONLY if unset [170-269]
|--> spawn KF2BotChat
|--> SetTimer 1.0s 'PollWaveStart' [262]
|--> SetTimer 3.0s 'RebuildHierarchy' [266]   (STUB, see M4)
|--> SetTimer 3.0s 'CacheHumans' [267]
MATCHSTARTING (standalone) [289]
|--> loop AddBot() x NumBots [289-309]
|--> SetTimer 1.0s (unnamed -> Timer) [305]
|--> SetTimer 0.1s 'CheckWave' [307]
TIMER [311]  (1s)
?+ ActiveBots < target --> AddBot()
?+ ActiveBots > MinimumBots --> RemoveBot()
```
#### 6. TECHNICAL REFERENCE
- Functions: `PostBeginPlay` [170-269], `AddMutator` [271-287], `MatchStarting` [289-309], `Timer` [311-332], `InitEmotes` [2745-2752], `PickRandEmote` [2754-2763], `ShouldDoVictoryDance` [2765-2775].
- Timers: PollWaveStart 1.0s [262]; RebuildHierarchy 3.0s [266]; CacheHumans 3.0s [267]; standalone 1.0s [305]; CheckWave 0.1s [307].
- Edge cases: defaultproperties comment says NumBots=6 but PostBeginPlay sets 7 (Appendix C). `RebuildHierarchy` is a declared stub [2780-2797].
- SDK facts: `KFMutator` base file not in SDK tree -- SDK behaviour not verified (PART 1.2). `NextMutator` not found in SDK (PART 1.2).
#### 7. WHERE TO FIX
- Change bot count / perk level / damage defaults: PostBeginPlay config block [170-269].
- Change timer cadence: [262]/[266]/[267].
- Console commands: `Mutate` (M2, [2590-2719]).
- Emote pool: InitEmotes [2745-2752] / PickRandEmote [2754-2763] (note `GetEmoteArray` is SDK-not-found, PART 1.2).

---

### M2 Bot lifecycle & spawn   @SYS-MUT-SPAWN      Primary file: KF2BotsMut.uc
#### 1. PLAIN-ENGLISH SUMMARY
This system creates and re-creates bot players: it spawns them at player starts or ammo crates, gives them perk, name, level, and archetype, respawns them after death, and removes them when there are too many. It also softens damage between friendly bots.
#### 2. EXPLANATION
`AddBot` [2358-2396]: `PS = KF.FindPlayerStart(none, 0)`; `Spawn(Class'KF2Bots.KF2Bot',,, PS.Location)`; `B.Perk = PickBotPerk()` (M3); `PRI.CurrentPerkClass = B.Perk`; `PRI.PlayerID = KF.GetNextPlayerID()`; `KF.GenericPlayerInitialization(B)`; `RestartBot(B)`; starting cash adjusted; `KF.bOnePlayerAtStart = false`. `RestartBot` [2433-2533] is the spawn routine: guards `bRestartLevel`, resolves a StartSpot (NewPlayer --> `KF.FindPlayerStart(NewPlayer, 0)` --> `NewPlayer.StartSpot`, warn+return if none), spawns a pawn via `KF.SpawnDefaultPawnFor` when Pawn==None, then either `GotoState('Dead')` [2475] (pawn still None) or `SetAnchor(StartSpot)` --> `Possess(pawn,false)` --> `PlayTeleportEffect` --> `ClientSetRotation` --> `KF.AddDefaultInventory` --> `KF.SetPlayerDefaults` --> `KF.SetTeam(NewPlayer, KF.Teams[0])`, and **`SetCharacterArch` after SetTeam** (SetTeam fires NotifyTeamChanged which would snap the archetype back to Mr. Foster). `RegisterBot` [334-341] sets `NewBot.mut`, `WdLastHubContactTime = WorldInfo.TimeSeconds`, appends to ActiveBots (called from KF2Bot.PreBeginPlay). `UnregisterBot` [343-350] removes from ActiveBots and routes through `HandleFireteamCasualty`. `RespawnBots` [2107-2125]: per bot `NextShoppingTime = now - 1`; dead --> `RestartBot(B)`; alive --> `PRI.Score += 500`. `InitBotCharacter` [2160-2246]: level = BotMinPerkLv + Rand(range); random CharacterArchetype with up to 4 retries to avoid duplicates (fallback index 0); name via `PickCustomBotName` [2135-2152] (no-replacement deck from CustomBotNames); `[Lv X] `/`[Rank] ` prefixes per bShowBotLevel/bShowBotRole. Squad spawns: `SetupSquadSpawns` [2853-2897] (ammo factories only, partial Fisher-Yates over first Min(NumFactories,NumSquads), fallback FindPlayerStart), `SpawnSquadAt` [2963-2977] (SL at 60-90u + 3 grunts at 90-150u), `PickSquadSpawnPoint` [2980-2991] (R = MinR + FRand()*(MaxR-MinR), Ang = FRand()*360), `SpawnBotWithRank` [2994-3005], `RelocateBotsToAmmoCrates` [2904-2960] (teleports already-spawned bots to shuffled crate anchors, only if `bJustSpawned`), `HideAllPickups` [3008-3017] (`bPickupHidden=true` on all factories + `SetTimer(10.0,false,'ReEnableAmmoFactories')`), `ReEnableAmmoFactories` [3019-3027]. `NetDamage` [2721-2743]: KF2Bot victim + same-team instigator --> Damage=0, Momentumx0.25; else Damagex=BotsDamageScale; chains NextMutator.
#### 3. LOGIC PIPELINE
AddBot --> PickBotPerk --> Spawn --> RestartBot (pawn+possess+inventory+team+arch) --> RegisterBot (self, from PreBeginPlay). Death --> RestartBot. Wave respawn --> RespawnBots.
#### 4. INPUTS / OUTPUTS
Input: PlayerStarts, KFPickupFactory_Ammo list, PlayerController IDs. Output: KF2Bot controllers, Pawns, PRI state. Single-writer: ActiveBots membership is written here (RegisterBot/UnregisterBot/InitializePlatoon); `NextShoppingTime` written by RespawnBots and by GoShopping state (Bot).
#### 5. FLOW   @FLOW-MUT-SPAWN
```
ADDBOT [2358]
|--> PS = FindPlayerStart(none,0)
|--> Spawn KF2Bot at PS.Location
|--> Perk = PickBotPerk()        (M3)
|--> PlayerID = GetNextPlayerID()
|--> GenericPlayerInitialization
|--> RestartBot(B)               [2433]
|--> Score = adjusted cash; bOnePlayerAtStart=false
RESTARTBOT [2433]
?+ bRestartLevel --> abort (non-server)
?+ StartSpot none --> FindPlayerStart -> NewPlayer.StartSpot -> warn+return
?+ Pawn None --> SpawnDefaultPawnFor
?+ Pawn still None --> GotoState('Dead') [2475]
|--> SetAnchor, Possess, PlayTeleportEffect, ClientSetRotation
|--> AddDefaultInventory; SetPlayerDefaults; SetTeam
|--> SetCharacterArch AFTER SetTeam (arch snap-back guard)
|--> PRI health sync; Score = max(Score, GetAdjustedRespawnCash)
```
#### 6. TECHNICAL REFERENCE
- Functions: `Mutate` [2590-2719], `AddBot` [2358-2396], `RemoveBot` [2398-2431], `RestartBot` [2433-2533], `RegisterBot` [334-341], `UnregisterBot` [343-350], `RespawnBots` [2107-2125], `InitBotCharacter` [2160-2246], `SetupSquadSpawns` [2853-2897], `SpawnSquadAt` [2963-2977], `PickSquadSpawnPoint` [2980-2991], `SpawnBotWithRank` [2994-3005], `RelocateBotsToAmmoCrates` [2904-2960], `HideAllPickups` [3008-3017], `ReEnableAmmoFactories` [3019-3027], `NetDamage` [2721-2743], `PickCustomBotName` [2135-2152].
- Timers: ReEnableAmmoFactories 10.0s one-shot [3008-3017].
- Edge cases: SetCharacterArch ordering (Appendix C/D); `bPickupHidden` SDK-not-found (PART 1.2); RelocateBotsToAmmoCrates gated on `bJustSpawned` (Obs 2).
- SDK facts: `SpawnDefaultPawnFor`, `GetNextPlayerID`, `AddDefaultInventory`, `SetPlayerDefaults`, `bOnePlayerAtStart`, `bHasSpawnedIn`, `bDisableTeamCollision`, `GetAdjustedRespawnCash` -- see PART 1.1/1.2.
#### 7. WHERE TO FIX
- Starting cash / Score formulas: AddBot [2358-2396] / RestartBot [2433-2533].
- Spawn placement: SetupSquadSpawns [2853-2897] / PickSquadSpawnPoint [2980-2991].
- Friendly damage: NetDamage [2721-2743].
- Console: Mutate [2590-2719].

---

### M3 Perk gacha   @SYS-MUT-PERK      Primary file: KF2BotsMut.uc
#### 1. PLAIN-ENGLISH SUMMARY
Every bot rolls a perk from a pool. The pool is drawn without replacement, so two bots never share the same perk (unless the per-perk cap allows), and if the pool empties it refills from the configured allowed list.
#### 2. EXPLANATION
`PickBotPerk` [2325-2356] is the gacha: empty `AllowedPerks` --> `PickFallbackPerk()` [2252-2265] (random live `PerkList` entry, skipping Berserker when `bNoZerkerBots`); empty pool --> `ResetPerkPool()` [2292-2314] (refill PerkPool + PerkPoolCounts from AllowedPerks via `ResolvePerkByName` [2272-2286], `~=` name match, unmatched names skipped); otherwise random draw -- if `MaxBotsPerPerk > 0`, increment `PerkPoolCounts` and, once the cap is reached, `Remove(Idx,1)` from both arrays so that perk cannot be drawn again this cycle; `MaxBotsPerPerk <= 0` --> uniform draws forever.
#### 3. LOGIC PIPELINE
AddBot --> PickBotPerk --> (pool empty? ResetPerkPool) --> random draw --> cap check --> return Class<KFPerk>.
#### 4. INPUTS / OUTPUTS
Input: `AllowedPerks` (config array<string>), `MaxBotsPerPerk` (config), `bNoZerkerBots`, live `PerkList`. Output: `Class<KFPerk>` assigned to `B.Perk` (M2) --> `PRI.CurrentPerkClass`. Single-writer: PerkPool/PerkPoolCounts written only here.
#### 5. FLOW   @FLOW-MUT-PERK
```
PICKBOTPERK [2325]
?+ AllowedPerks empty --> PickFallbackPerk [2252] (skip Berserker if bNoZerkerBots)
?+ PerkPool empty --> ResetPerkPool [2292] (ResolvePerkByName ~= match)
|--> Rand draw Idx
?+ MaxBotsPerPerk > 0 --> ++PerkPoolCounts; >= cap --> Remove(Idx,1) both arrays
|--> return PerkPool[Idx]
```
#### 6. TECHNICAL REFERENCE
- Functions: `PickBotPerk` [2325-2356], `PickFallbackPerk` [2252-2265] (`function Class<KFPerk>`), `ResolvePerkByName` [2272-2286] (`function Class<KFPerk>(string PerkName)`), `ResetPerkPool` [2292-2314].
- Edge cases: degenerate case (only Berserker + bNoZerkerBots) --> PickFallbackPerk; unknown names in AllowedPerks silently skipped by ResolvePerkByName.
- SDK facts: `KFPerk` [SDK KFGame/Classes/KFPerk.uc:10].
#### 7. WHERE TO FIX
- Perks per bot / cap: PostBeginPlay (MaxBotsPerPer default 2) + PickBotPerk [2325-2356].
- Allowed list: config `AllowedPerks`.

---

### M4 Platoon & macro waypoints   @SYS-MUT-PLATOON      Primary file: KF2BotsMut.uc
#### 1. PLAIN-ENGLISH SUMMARY
Every 3 seconds the mod decides what each fireteam should be walking toward. Group 0 escorts the human VIP (or roams free during trader rounds), group 1 goes 2000u ahead of the VIP (vanguard), group 2 goes 2000u behind (rearguard), and group 3 guards a lateral chokepoint. On boss waves everyone targets the boss instead.
#### 2. EXPLANATION
`InitializePlatoon` [368-460] builds `Fireteams` from `DetermineGroupCount` [544-551] (`BotCount / BOTS_PER_GROUP_TARGET` clamped to [MIN_GROUPS=2, MAX_GROUPS=4]); assigns ranks (SQUAD_LEADER leaders, GRUNTs), 1-based GroupID, `bIsGroupLeader`, `bIsAlphaCommander` for the group-0 leader, then calls `SyncSquadLeaders` [471-516]. `SyncSquadLeaders` is the **single authority for every bot's SquadLeader pointer**: leader --> `SquadLeader = None`; followers --> `SquadLeader = leader`; slot assignment via `FollowSetSlot(FollowerSlot, FollowerTotal)` [511] (0-based member-array order, leader skipped). `UpdateMacroWaypoints` [553-659] is the 3 s macro tick itself: a repeating timer armed once by `InitializePlatoon` (`SetTimer(MACRO_WAYPOINT_INTERVAL, true, 'UpdateMacroWaypoints')` [457-459]); `OnBotKilled` forces an extra run when the VIP dies [770]. The macro sequence per source [553-659] is: `PruneInvalidBots()` [563] --> `ProcessPromotionQueue()` [566] --> `CleanupRangedHealCooldowns()` [569] --> VIP death check --> `HandleVIPSuccession()` [571-574] --> early return if no bots/groups [576] --> `EvaluateRegroupEntries()` [579] --> boss wave check (`KFGRI.IsBossWave()`, [583-598]: `FindBossPawn` [585], all groups Anchor=None + AssignedAnchor=BossPawn + Propagate, return) --> `GetVIPController()` [600] --> per-group switch [612-656]: case 0 (trader open --> anchor None; else AssignedAnchor = VIP.Pawn), case 1 (Vanguard: `VIP.Loc + rot*VANGUARD_OFFSET` --> `FindNearestNavPoint(NAV_SEARCH_RADIUS)`), case 2 (Rearguard: minus REARGUARD_OFFSET), case 3 (`FindNearestChokepoint(VIP)`), then `PropagateAnchorToFollowers(GroupIdx)` [658]. `PropagateAnchorToFollowers` [661-676] gives followers the leader's `AssignedAnchor`. `FindNearestNavPoint` [678-686] and `FindNearestChokepoint` [688-703] use `foreach WorldInfo.RadiusNavigationPoints(...)` -- they return the **first hit, not the nearest** (naming vs behaviour mismatch; Appendix D). `GetVIPController` [705-726] returns cached VIPController if alive, else first PlayerController with alive Pawn via `WorldInfo.AllControllers`. `FindBossPawn` [728-749] scans AllPawns for KFPawn_Monster `Health > 5000`, picks highest, caches. `RebuildHierarchy` [2780-2797] clears Subordinates/Supervisor links -- declared **STUB** ("full implementation later"). `GetActiveBoss` [2808-2813] STUB (returns none). `CacheHumans` [2799-2803] delegates to `CacheHumanPositions` [2820-2836] (alive KFPawn_Human with PlayerController --> {HumanPawn, Loc, Vel}).
#### 3. LOGIC PIPELINE
Wave start --> InitializePlatoon --> SyncSquadLeaders. Every macro tick --> UpdateMacroWaypoints (prune --> promotions --> heal-cooldown cleanup --> VIP succession --> regroup entry --> boss override --> per-group anchors).
#### 4. INPUTS / OUTPUTS
Input: ActiveBots, Fireteams, WorldInfo (AllControllers/AllPawns/RadiusNavigationPoints), KFGRI (IsBossWave, bTraderIsOpen). Output: `Fireteams[i].Anchor`, `Bot.AssignedAnchor`, `Bot.SquadLeader`, `Bot.FollowSlotIndex/SlotCount` (via FollowSetSlot), CachedHumans, VIPController, AlphaCommander, BossPawn cache. Single-writer: Anchor/AssignedAnchor written only here; SquadLeader only in SyncSquadLeaders.
#### 5. FLOW   @FLOW-MUT-PLATOON
```
UPDATEMACROWAYPOINTS [553]  (3s macro tick)
|--> PruneInvalidBots [563]
|--> ProcessPromotionQueue [566]      (M5)
|--> CleanupRangedHealCooldowns [569] (M10)
?+ VIP dead --> HandleVIPSuccession [571-574]
?+ no bots / NumGroups<=0 --> return [576]
|--> EvaluateRegroupEntries [579]     (M8)
?+ IsBossWave --> FindBossPawn [585]; all groups Anchor=BossPawn; Propagate; return [583-598]
VIP = GetVIPController [600]
for each group:
  case 0: ?+ trader open --> anchor None (roam)
          else VIP.Pawn != None --> AssignedAnchor = VIP.Pawn   [614-626]
  case 1: anchor = FindNearestNavPoint(VIP + rot*2000)           [628-638]
  case 2: anchor = FindNearestNavPoint(VIP - rot*2000)           [640-650]
  case 3: anchor = FindNearestChokepoint(VIP)                    [651-656]
  |--> PropagateAnchorToFollowers [658] -> [661]
```
#### 6. TECHNICAL REFERENCE
- Functions: `InitializePlatoon` [368-460], `DetermineGroupCount` [544-551], `SyncSquadLeaders` [471-516], `ShuffleActiveBots` [518-529], `PruneInvalidBots` [531-542], `UpdateMacroWaypoints` [553-659], `PropagateAnchorToFollowers` [661-676], `FindNearestNavPoint` [678-686], `FindNearestChokepoint` [688-703], `GetVIPController` [705-726], `FindBossPawn` [728-749], `RebuildHierarchy` [2780-2797] (STUB), `GetActiveBoss` [2808-2813] (STUB), `CacheHumans` [2799-2803], `CacheHumanPositions` [2820-2836].
- Constants: VANGUARD_OFFSET 2000.0 [69], REARGUARD_OFFSET 2000.0 [70], CHOKEPOINT_LATERAL_OFFSET 1000.0 [71], NAV_SEARCH_RADIUS 1500.0 [72], MIN_GROUPS 2 [64], MAX_GROUPS 4 [65], BOTS_PER_GROUP_TARGET 3 [66].
- Edge cases: RadiusNavigationPoints first-hit-not-nearest (Appendix D); FindBossPawn threshold `Health > 5000` matches BOSS_HEALTH_THRESHOLD value in BotBase.
- SDK facts: `RadiusNavigationPoints` [SDK Engine/Classes/WorldInfo.uc:1636]; `AllPawns` [SDK Engine/Classes/WorldInfo.uc:1663].
#### 7. WHERE TO FIX
- Anchor offsets / radii: consts [69-72].
- Group sizing: BOTS_PER_GROUP_TARGET / MIN_GROUPS / MAX_GROUPS [64-66].
- VIP selection: GetVIPController [705-726].
- Hierarchy (unimplemented): RebuildHierarchy [2780-2797].

---

### M5 Succession & promotion   @SYS-MUT-SUCCESSION      Primary file: KF2BotsMut.uc
#### 1. PLAIN-ENGLISH SUMMARY
When a bot officer dies, someone else must take the post. This system scores every living grunt by (kills x 10 + health), promotes the best one, inherits the dead officer's squad orders, and reshuffles groups so no fireteam is left alone.
#### 2. EXPLANATION
`OnBotKilled` [751-774]: officer death (SL/LT/CAPTAIN) queues a `PromotionRequest` (struct [100-106]) in PendingPromotions; if the dead bot is the VIP --> `HandleVIPSuccession()` + `UpdateMacroWaypoints()`; then `UnregisterBot(DeadBot)`. `ComputeCommandScore` [776-781] = `PRI.Kills * 10 + Pawn.Health` (-1 invalid). `FindBestCandidate` [783-796] = max score among living. `FindExpendableMember` [798-813] = min score, skips `bIsGroupLeader`. `ProcessPromotionQueue` [820-888] runs each macro tick: MaxPerTick=1 (2 if `KFGRI.WaveNum > 5`); candidates = living GRUNTs; pops from end of PendingPromotions; divergence fix -- if OldRank==SQUAD_LEADER and the dead officer's group already has a live `bIsGroupLeader` leader --> skip; `PromoteBot` [891-895] sets `Bot.BotRank`; removes promoted from candidates. `HandleVIPSuccession` [956-971]: `VIPController = FindBestCandidate(ActiveBots)`; AlphaCommander = same; `bIsAlphaCommander = true`; if new VIP is a group leader --> `DemoteGroupLeader(Best)` (a VIP must not be a squad leader). `HandleFireteamCasualty` [973-1016]: removes DeadBot from Members; if it was leader --> `NewLeader = FindBestCandidate(Members)`, sets bIsGroupLeader, `BotRank = SQUAD_LEADER`, `ResetStuckState`, `InheritSquadOrder`; else Leader=None + `ObjectiveBailUntil = 0`; then `ConsolidateFireteams()` + `SampleSquadSlots(GroupIdx)`. `DemoteGroupLeader` [1018-1051]: old leader bIsGroupLeader=false; best surviving member becomes new leader (bIsGroupLeader, ResetStuckState, InheritSquadOrder); ConsolidateFireteams. `RequestLeaderDemotion` [1053-1056] (called by Logic's Ghost-Door fix) = just `DemoteGroupLeader(StuckLeader)`. `ConsolidateFireteams` [1058-1073]: Fireteams[0].Members < VIP_ESCORT_MIN_SIZE --> `PullBotFromNearestGroup(0)`; any group with Members==GROUP_DISSOLVE_SIZE(1) --> `DissolveGroup`; ends with `SyncSquadLeaders()`. `PullBotFromNearestGroup` [1075-1109]: nearest source group with Members>2 and live leader; Puller = FindExpendableMember; ReassignBotToGroup. `DissolveGroup` [1111-1127]: single member reassigned via `FindNearestEligibleGroup` [1129-1152] (nearest group with Members>=2 and live leader). `ReassignBotToGroup` [1154-1179]: remove from old Members, bIsGroupLeader=false, GroupID=NewGroupIdx+1, ResetStuckState, Members.AddItem, inherit leader's AssignedAnchor. Readers: `GetGroupLeader` [1181-1187], `GetGroupSize` [1189-1195], `GetFollowerIndex` [1197-1214] (1-based position, leader skipped), `GetFollowerBySlot` [1614-1629].
#### 3. LOGIC PIPELINE
Bot dies --> OnBotKilled --> queue/consolidate --> (macro tick) ProcessPromotionQueue --> PromoteBot. Group empties --> DissolveGroup --> ReassignBotToGroup.
#### 4. INPUTS / OUTPUTS
Input: ActiveBots, Fireteams, PendingPromotions. Output: BotRank, bIsGroupLeader, bIsAlphaCommander, SquadLeader, VIPController, AlphaCommander, Members arrays. Single-writer: BotRank written by PromoteBot + HandleFireteamCasualty + InitializePlatoon (all here); VIPController/AlphaCommander only here.
#### 5. FLOW   @FLOW-MUT-SUCCESSION
```
OnBotKilled [751]
|--> officer? --> PendingPromotions.AddItem(PromotionRequest)
?+ == VIPController --> HandleVIPSuccession [956]
|                        --> VIP = FindBestCandidate; AlphaCommander
|                        ?+ VIP is group leader --> DemoteGroupLeader
|--> UnregisterBot [751-774]
MACRO TICK: ProcessPromotionQueue [820]
|--> budget = 1 (2 if WaveNum>5)
|--> candidates = living GRUNTs
|--> pop PendingPromotions (from end)
?+ SL request but group already has live leader --> skip (divergence fix)
|--> PromoteBot: Bot.BotRank = NewRank [891]
CONSOLIDATEFIRETEAMS [1058] (after any casualty)
?+ Fireteams[0].Members < 2 --> PullBotFromNearestGroup(0) [1075]
?+ group size == 1 --> DissolveGroup [1111] --> FindNearestEligibleGroup [1129]
|--> ReassignBotToGroup [1154] (inherit anchor)
|--> SyncSquadLeaders (end)
```
#### 6. TECHNICAL REFERENCE
- Functions: `OnBotKilled` [751-774], `ComputeCommandScore` [776-781], `FindBestCandidate` [783-796], `FindExpendableMember` [798-813], `ProcessPromotionQueue` [820-888], `PromoteBot` [891-895], `HandleVIPSuccession` [956-971], `HandleFireteamCasualty` [973-1016], `DemoteGroupLeader` [1018-1051], `RequestLeaderDemotion` [1053-1056], `ConsolidateFireteams` [1058-1073], `PullBotFromNearestGroup` [1075-1109], `DissolveGroup` [1111-1127], `FindNearestEligibleGroup` [1129-1152], `ReassignBotToGroup` [1154-1179], `GetGroupLeader` [1181-1187], `GetGroupSize` [1189-1195], `GetFollowerIndex` [1197-1214], `GetFollowerBySlot` [1614-1629].
- Struct: `PromotionRequest` [100-106].
- Constants: VIP_ESCORT_MIN_SIZE 2 [67], GROUP_DISSOLVE_SIZE 1 [68].
- Edge cases: dead leader stays in Members (controller persists Possess-->Restart) -- R8 note.
#### 7. WHERE TO FIX
- Promotion scoring: ComputeCommandScore [776-781].
- Promotion budget: ProcessPromotionQueue [820-888].
- VIP choice: HandleVIPSuccession [956-971].

---

### M6 Wave & objective   @SYS-MUT-WAVE      Primary file: KF2BotsMut.uc
#### 1. PLAIN-ENGLISH SUMMARY
A fast 0.1-second poller watches the game for new waves and a new hold-objective. When the wave counter changes it rescales zed counts; when the objective volume changes it opens or closes the squad-order table; when the objective progress hits 99.9% it ends it.
#### 2. EXPLANATION
`PollWaveStart` [352-366] (1s, timer [262]) detects wave change --> `InitializePlatoon()` + `RelocateBotsToAmmoCrates()`. `CheckWave` [1244-1295] (0.1s, timer [307]): (1) `bNewWave && KF.GetStateName()=='TraderOpen'` --> bNewWave=false, `RespawnBots()`; (2) `KF.WaveNum != OldWaveNum` --> `OldWaveNum = byte(KF.WaveNum)`, bNewWave=true; if `ZedCountScaling > 0 && WaveTotalAI > 4` --> `WaveTotalAI *= (1 + NumBots*ZedCountScaling)` and update AIRemaining/WaveTotalAICount; (3) `PrevObjective != KF.MyKFGRI.CurrentObjective` --> `PrevObjective = ...`, `HoldVolume = KFMapObjective_DoshHold(PrevObjective)`; HoldVolume!=none --> `SetHoldObjective`; (4) else-if `bObjectiveActive && HoldVolume != none` && `HoldVolume.GetProgress() >= 0.999` --> `EndObjective()`; (5) `EvaluateSquadPhase()` (M7). `SetHoldObjective` [1297-1352] (signature `final function SetHoldObjective(Volume V)` -- V is a **parameter**, not a var): `ValidPoints.Length = 0` **before** re-append (stale-point fix); `foreach WorldInfo.AllNavigationPoints(Class'Engine.NavigationPoint', N)` --> `V.Encompasses(N)` --> `ValidPoints.AddItem` [1307-1314]; `bObjectiveActive = ValidPoints.Length != 0`; if active: `EnsureSquadOrderTable()`, per squad: Zone=HoldVolume, SquadID=i+1, NodeBlacklist cleared, ObjectiveBailUntil=0, if Leader alive --> `GP = NearestValidPoint(leader loc)`, GoalNav=GP, GoalPoint=GP.Location, Phase=PHASE_ENROUTE, StartTime=now, SquadSeedAngle=FRand()*6.2831855, ORDER_CREATED log, `SampleSquadSlots(i)`; else GoalNav=none, Phase=PHASE_IDLE. `EndObjective` [1354-1391]: bObjectiveActive=false; ValidPoints cleared; per squad: `ReleaseSquadSlots(i,"EndObjective")`, Leader/Zone/GoalNav/GoalPoint/Slots/NodeBlacklist/ObjectiveBailUntil cleared; if `Fireteams[i].Members.Length > 0` --> Phase=PHASE_REGROUP + StartTime; else PHASE_IDLE; `foreach AllControllers(Class'KF2Bots.KF2Bot', B): B.FinishObjective()`. `NearestValidPoint` [1394-1414] = min VSizeSq over ValidPoints. `GetObjectiveLocation` [2839-2850] = PrevObjective.Location if active, else HoldVolume.Location, else vect(0,0,0).
#### 3. LOGIC PIPELINE
CheckWave 0.1s --> wave change / objective change --> SetHoldObjective or EndObjective --> squad table (M7).
#### 4. INPUTS / OUTPUTS
Input: KF (WaveNum, CurrentObjective, GetStateName), KFGRI, NavMesh. Output: ValidPoints, HoldVolume, bObjectiveActive, OldWaveNum, WaveTotalAI, SquadOrders (via M7), FinishObjective to all bots. Single-writer: ValidPoints/bObjectiveActive written only here.
#### 5. FLOW   @FLOW-MUT-WAVE
```
CHECKWAVE [1244]  (0.1s)
?+ bNewWave && state=='TraderOpen' --> bNewWave=false; RespawnBots [1244-1250]
?+ WaveNum != OldWaveNum -->
|   OldWaveNum = WaveNum; bNewWave = true
|   ?+ ZedCountScaling>0 && WaveTotalAI>4 --> WaveTotalAI *= (1+NumBots*ZedCountScaling)
?+ PrevObjective != CurrentObjective -->
|   HoldVolume = KFMapObjective_DoshHold(PrevObjective)
|   ?+ HoldVolume != none --> SetHoldObjective [1297]
|     |--> ValidPoints = 0 THEN re-append (stale fix)
|     |--> bObjectiveActive = (ValidPoints.Length != 0)
|     ?+ active --> EnsureSquadOrderTable; per squad ENROUTE + SampleSquadSlots
|   else bObjectiveActive --> EndObjective [1354]
?+ bObjectiveActive && GetProgress() >= 0.999 --> EndObjective
|--> EvaluateSquadPhase [1244-1295]
POLLWAVESTART [352]  (1s)
?+ wave changed --> InitializePlatoon + RelocateBotsToAmmoCrates
```
#### 6. TECHNICAL REFERENCE
- Functions: `PollWaveStart` [352-366], `CheckWave` [1244-1295], `SetHoldObjective` [1297-1352], `EndObjective` [1354-1391], `GetObjectiveLocation` [2839-2850], `NearestValidPoint` [1394-1414].
- Constants: OBJ_BAIL_COOLDOWN 8.0 [75], PHASE_* [76-80], WAVE_POLL_INTERVAL 1.0 [87].
- Edge cases: `V.Encompasses(N)` -- V is the Volume parameter (not a bug, resolved); `CurrentObjective` SDK-not-found (PART 1.2); `Encompasses` SDK-not-found (PART 1.2).
- SDK facts: `KFMapObjective_DoshHold` [SDK KFGameContent/Classes/KFMapObjective_DoshHold.uc:12].
#### 7. WHERE TO FIX
- Zed scaling: CheckWave [1244-1295] (`ZedCountScaling` config).
- Objective open/close: SetHoldObjective/EndObjective.
- Progress completion threshold: 0.999 in CheckWave [1244-1295].

---

### M7 Squad orders & slots   @SYS-MUT-ORDERS      Primary file: KF2BotsMut.uc
#### 1. PLAIN-ENGLISH SUMMARY
Each squad owns one goal point inside the objective volume and a ring of 4 possible slot positions around it. Bots are assigned to slots by a farthest-point algorithm so they spread out. A 1-second phase poller flips squads between ENROUTE (walking in) and HOLDING (defending).
#### 2. EXPLANATION
`EnsureSquadOrderTable` [1423-1437] size-locks SquadOrders to Fireteams.Length (UE3 arrays grow on indexed access). `InheritSquadOrder` [1443-1482]: succession keeps Zone/GoalPoint/Slots/Phase, resets ObjectiveBailUntil; if GoalNav==none --> Leader=NewLeader, Phase=PHASE_IDLE, return; if `Zone != none && !Zone.EncompassesPoint(GoalPoint)` --> re-sample goal at new leader (GoalKept=0); `SampleSquadSlots` if GoalNav!=none; ORDER_INHERIT log. `SampleSquadSlots` [1487-1587] (the slot sampler): N = follower count (member order, leader skipped), **capped N>4 --> 4**; N<=0 return; `ReleaseSquadSlots(GroupIdx,"Resample")`; R0=96.0; candidates at angle `SquadSeedAngle + i*2pi/N`, radius 96 around GoalPoint; filters: `Zone.EncompassesPoint` && |dz| vs leader < 50u; farthest-point iteration -- `while(true)` pick candidate maximizing DMin (min distance to GoalPoint and existing SlotLocs), assign `SlotLocs[BestIdx]`, `Slots.AddItem(BestIdx)`, repeat until all dead candidates exhausted; SLOT_CLAIM log per occupant (angle in degrees via Atan2*57.2957795). `ReleaseSquadSlots` [1591-1610]: SLOT_RELEASE logs; clears Slots/SlotLocs. `GetFollowerBySlot` [1614-1629] mirrors SyncSquadLeaders order. `GetSquadPhase` [1632-1640]; `IsSquadInObjectivePhase` [1645-1653] (ENROUTE||HOLDING --> ring anchors to GoalPoint slot, "model b"). `GetSlotLocation` [1657-1667] = `SlotLocs[B.FollowSlotIndex]` or vect(0,0,0). `EvaluateSquadPhase` [1672-1729] (1s poll, called from CheckWave): `GoalRadiusSq = 9216.0` (962); for each squad in ENROUTE/HOLDING: `LeaderInside` = `Zone.Encompasses(leader pawn)` or dist<96u; `MemberInside` = any member inside; ENROUTE && LeaderInside && MemberInside --> HOLDING; HOLDING && !LeaderInside --> ENROUTE. `HasSquadGoal` [1734-1744] = GoalNav!=None && GoalPoint != vect(0,0,0). `ReissueSquadOrder` [1748-1763] (idle-watchdog escalation 1): reset ObjectiveBailUntil, `SampleSquadSlots`, ORDER_REISSUE log. `GetBotObjective` [1953-2004]: !bObjectiveActive --> none; B/Pawn None --> `ValidPoints[Rand]`; squad GoalNav if squad leader alive (shared squad goal); fallback: nearest active squad goal; else `ValidPoints[Rand]` (legacy leaderless).
#### 3. LOGIC PIPELINE
SetHoldObjective --> EnsureSquadOrderTable --> per-squad ENROUTE + SampleSquadSlots --> EvaluateSquadPhase (1s) ENROUTE-->HOLDING-->ENROUTE. Succession --> InheritSquadOrder. Watchdog --> ReissueSquadOrder.
#### 4. INPUTS / OUTPUTS
Input: Fireteams, HoldVolume, NavigationPoints. Output: `SquadOrders` struct (SquadOrder [25-39]) -- Zone, GoalPoint, GoalNav, Slots, Phase, StartTime, ObjectiveBailUntil, NodeBlacklist, SlotLocs, SquadSeedAngle. Single-writer: SquadOrders written here + M5 (inherit) + M9 (NodeBlacklist via AddNodeBlock).
#### 5. FLOW   @FLOW-MUT-SLOTS
```
SAMPLESQUADSLOTS [1487]
|--> N = followers (leader skipped); N>4 --> N=4; N<=0 --> return
|--> ReleaseSquadSlots [1591]
|--> candidates: angle = Seed + i*2pi/N, r=96, around GoalPoint
|--> filter: Zone.EncompassesPoint && |dz| vs leader < 50
|--> while(true): pick candidate with max DMin (farthest from GoalPoint+chosen)
|     ?+ all dead --> break
|     |--> SlotLocs[BestIdx] = candidate; Slots.AddItem(BestIdx)
|--> SLOT_CLAIM per occupant
EVALUATESQUADPHASE [1672]  (1s)
for squad ENROUTE/HOLDING:
  LeaderInside = Zone.Encompasses(leader) || dist < 96u
  MemberInside = any member inside
  ENROUTE  && LeaderInside && MemberInside --> HOLDING
  HOLDING  && !LeaderInside              --> ENROUTE
```
#### 6. TECHNICAL REFERENCE
- Functions: `EnsureSquadOrderTable` [1423-1437], `InheritSquadOrder` [1443-1482], `SampleSquadSlots` [1487-1587], `ReleaseSquadSlots` [1591-1610], `GetFollowerBySlot` [1614-1629], `GetSquadPhase` [1632-1640], `IsSquadInObjectivePhase` [1645-1653], `GetSlotLocation` [1657-1667], `EvaluateSquadPhase` [1672-1729], `HasSquadGoal` [1734-1744], `ReissueSquadOrder` [1748-1763], `GetBotObjective` [1953-2004].
- Struct: `SquadOrder` [25-39].
- Constants: PHASE_IDLE/ENROUTE/HOLDING/REGROUP/SHOPPING [76-80].
- Edge cases: slot cap 4 vs group size 3 (BOTS_PER_GROUP_TARGET) -- cap is defensive; `EncompassesPoint` SDK behaviour not verified (PART 1.2 lists `Encompasses`; EncompassesPoint not separately verified).
#### 7. WHERE TO FIX
- Slot radius (96.0): inline R0 in SampleSquadSlots [1487-1587].
- Phase transitions: EvaluateSquadPhase [1672-1729].
- Slot-->bot mapping: GetFollowerBySlot [1614-1629] / GetSlotLocation [1657-1667].

---

### M8 Regroup   @SYS-MUT-REGROUP      Primary file: KF2BotsMut.uc
#### 1. PLAIN-ENGLISH SUMMARY
If a squad leader dies or idles for 3 seconds with no goal and no zeds nearby, the squad enters a 5-second regroup phase: the bot hub uses this to re-attach stragglers to the nearest live leader.
#### 2. EXPLANATION
`EvaluateRegroupEntries` [1838-1902] runs each 3s macro tick (called from UpdateMacroWaypoints [579]). Two entry triggers: (1) **leader dead** + members>0 --> promote replacement: `bIsGroupLeader`, `BotRank = SQUAD_LEADER`, `ResetStuckState`, `InheritSquadOrder`, `SampleSquadSlots`, Phase=PHASE_REGROUP, REGROUP_ENTER log, `SyncSquadLeaders`; (2) **idle leader**: `bNoGoal` && state in {PickNextMove, Camp, Roaming} && `SquadIdleStamp` set; idle >= 3.0s && `CountZedsInRadius(loc, REGROUP_SCAN_RADIUS) == 0` --> Phase=PHASE_REGROUP. (R8 note: the dead leader stays in Members -- the controller persists through Possess-->Restart.) `GetSquadStartTime` [1905-1913] reads `SquadOrders[i].StartTime`. `MoveSquadMembers` [1919-1951] (inter-squad attach/merge, called by the bot hub's P4.5 branch 3): source squad ghosted (Leader None, 0 members); stamps `WdLastHubContactTime`; `ConsolidateFireteams`. `FindNearestActiveLeader` [1768-1811] (watchdog escalation 2): nearest live group leader **or** live human with PlayerController within MaxDist, using CachedHumans. `CountZedsInRadius` [1814-1828]: `foreach DynamicActors(class'KFPawn_Monster', Zed)` alive within radius.
#### 3. LOGIC PIPELINE
Macro tick --> EvaluateRegroupEntries (dead/idle leader --> REGROUP). Hub P4.5 (Bot) reads phase --> MoveSquadMembers on attach.
#### 4. INPUTS / OUTPUTS
Input: Fireteams, SquadOrders, SquadIdleStamp, CachedHumans, NavMesh. Output: Phase=PHASE_REGROUP, replacement leaders, WdLastHubContactTime stamps. Single-writer: PHASE_REGROUP written here + EndObjective (M6); MoveSquadMembers mutates Members (writer: hub via this function -- the mutator remains the sole Members writer).
#### 5. FLOW   @FLOW-MUT-REGROUP
```
EVALUATEREGROUPENTRIES [1838]  (3s macro tick)
for each squad:
?+ leader dead && members > 0 -->
|   NewLeader = best member; bIsGroupLeader; BotRank=SQUAD_LEADER
|   ResetStuckState; InheritSquadOrder; SampleSquadSlots
|   Phase = PHASE_REGROUP; REGROUP_ENTER; SyncSquadLeaders
?+ leader idle (bNoGoal && state in {PickNextMove,Camp,Roaming}) &&
|   SquadIdleStamp set && idle >= 3.0s &&
|   CountZedsInRadius(REGROUP_SCAN_RADIUS=5000) == 0 -->
|   Phase = PHASE_REGROUP
MOVE... MoveSquadMembers [1919]  (hub P4.5 attach)
|--> source squad ghosted (Leader None, 0 members)
|--> move members to target squad
|--> stamp WdLastHubContactTime
|--> ConsolidateFireteams
```
#### 6. TECHNICAL REFERENCE
- Functions: `EvaluateRegroupEntries` [1838-1902], `GetSquadStartTime` [1905-1913], `MoveSquadMembers` [1919-1951], `FindNearestActiveLeader` [1768-1811], `CountZedsInRadius` [1814-1828].
- Constants: REGROUP_DURATION 5.0 [82], REGROUP_HARD_TIMEOUT 6.0 [83], REGROUP_SCAN_RADIUS 5000.0 [86], PHASE_REGROUP 3 [79].
- Edge cases: dead leader in Members (R8); idle window 3.0s is inline.
#### 7. WHERE TO FIX
- Regroup duration/timeout: consts [82-83] + Bot hub P4.5 (K1, Bot:157-160).
- Scan radius: REGROUP_SCAN_RADIUS [86].

---

### M9 Nav node blacklist   @SYS-MUT-NODEBLOCK      Primary file: KF2BotsMut.uc
#### 1. PLAIN-ENGLISH SUMMARY
When a bot gives up on a navigation node (bail objective), that node is blacklisted for 8 seconds for that bot only, so the pathfinder won't immediately send it back to the same dead end.
#### 2. EXPLANATION
`IsNodeBlocked` [2011-2029]: owner-only -- compares `Block.Owner == B` by Name and `Block.ExpiresAt > now` over `SquadOrder.NodeBlacklist` (struct `NavNodeBlock` [16-21]: Node:Name, Owner:KF2Bot, ExpiresAt:float). `AddNodeBlock` [2031-2065]: prunes expired entries first; if an unexpired entry already exists for (owner,node) --> refresh expiry only (one entry per pair); else `AddItem` with `ExpiresAt = now + OBJ_BAIL_COOLDOWN` (8.0s). Called from the Bot's DoObjective state bail path (Loophole 7, [Bot:485-603]).
#### 3. LOGIC PIPELINE
DoObjective bail (Bot) --> AddNodeBlock --> next path attempt consults IsNodeBlocked.
#### 4. INPUTS / OUTPUTS
Input: (Bot bail events). Output: `SquadOrders[i].NodeBlacklist`. Single-writer: NodeBlacklist written only here (+ cleared by SetHoldObjective/EndObjective).
#### 5. FLOW   @FLOW-MUT-NODEBLOCK
```
ADDNODEBLOCK [2031]
|--> prune expired entries
?+ unexpired (owner,node) exists --> refresh ExpiresAt
?+ none --> AddItem(ExpiresAt = now + 8.0)
ISNODEBLOCKED [2011]
?+ owner==B && Node match && ExpiresAt > now --> true
```
#### 6. TECHNICAL REFERENCE
- Functions: `IsNodeBlocked` [2011-2029], `AddNodeBlock` [2031-2065].
- Struct: `NavNodeBlock` [16-21].
- Constants: OBJ_BAIL_COOLDOWN 8.0 [75].
#### 7. WHERE TO FIX
- Block duration: OBJ_BAIL_COOLDOWN [75] (+ BotBase const [69], same value 8.0).

---

### M10 Ranged-heal cooldown bookkeeping   @SYS-MUT-HEALCOOL      Primary file: KF2BotsMut.uc
#### 1. PLAIN-ENGLISH SUMMARY
A bot medic darts at a human; this system makes sure no bot darts the same human again for 25 seconds.
#### 2. EXPLANATION
`RegisterRangedHealTarget` [900-920] (called by HealRanged state [Bot:1415-1537] on successful dart): appends `{target, now + 25.0}` to RangedHealTargets/RangedHealCooldownEnds (25.0s window); refreshes existing entry (updates expiry, no duplicate). `IsRangedHealTargetOnCooldown` [922-938]: true if the target has an unexpired entry -- consulted by `CheckMedicGunHeal` [Logic:117-200]. `CleanupRangedHealCooldowns` [940-954]: prunes expired entries; runs each macro tick ([569]).
#### 3. LOGIC PIPELINE
HealRanged dart --> RegisterRangedHealTarget. CheckMedicGunHeal --> IsRangedHealTargetOnCooldown (skip). Macro tick --> Cleanup.
#### 4. INPUTS / OUTPUTS
Input: (HealRanged success events). Output: RangedHealTargets/RangedHealCooldownEnds. Single-writer: arrays written only here.
#### 5. FLOW   @FLOW-MUT-HEALCOOL
```
REGISTER [900]  (from HealRanged)
?+ existing target --> refresh expiry
?+ new --> AddItem(target, now+25.0)
ISONCOOLDOWN [922]  (from CheckMedicGunHeal)
?+ unexpired entry for target --> true (skip)
CLEANUP [940]  (macro tick)
|--> prune expired
```
#### 6. TECHNICAL REFERENCE
- Functions: `RegisterRangedHealTarget` [900-920], `IsRangedHealTargetOnCooldown` [922-938], `CleanupRangedHealCooldowns` [940-954].
- Edge cases: 25.0s window is inline; parallel arrays (index-aligned).
#### 7. WHERE TO FIX
- Cooldown window: inline 25.0 in RegisterRangedHealTarget [900-920].

---

### M11 Utilities   @SYS-MUT-UTIL      Primary file: KF2BotsMut.uc
#### 1. PLAIN-ENGLISH SUMMARY
Small shared helpers: the ECH: logger with rate limiting, enemy-spotting broadcast to squadmates, the trader weapon list, coordinate formatting, and debug console messages.
#### 2. EXPLANATION
`EchelonLog` [159-168]: backtick `` `log `` with "ECH:" prefix; rate-limits "ORDER_"-prefixed messages to 5s via LastAuditLogTime. `BroadcastSpottedEnemy` [1220-1239] (P7 Spotter): leader's `SetEnemy` pushes to followers without a live Enemy; `Member.SetEnemy(Spotted, true)`. `InitTraderList` [2067-2088]: builds `TraderList` of AIWeaponInfo from `L.SaleItems`; `bTraderListInit = true`. `FindWeaponByClass` [2090-2105]. `CoordStr` [1416-1419]: floor(x/100) comma-joined. `DebugMessage` [2535-2546]: static final, "[BOT] " prefix, all PlayerControllers ClientMessage. `PMsg` [2548-2557]: TeamMessage + LocalPlayer viewport OutputText. `DebugAI` [2559-2588]: nearest bot to Sender -- **`BestScore` is never initialized** (pre-existing; Appendix C/D).
#### 3. LOGIC PIPELINE
Leaf helpers; no own timers.
#### 4. INPUTS / OUTPUTS
Input: (callers). Output: logs, TraderList, follower Enemy fields. Single-writer: TraderList written by InitTraderList only.
#### 5. FLOW   @FLOW-MUT-UTIL
```
EchelonLog [159]:  `log("ECH: ...")  (ORDER_ rate-limited 5s)
Broadcast [1220]: leader SetEnemy --> followers w/o live Enemy --> SetEnemy(Spotted,true)
DebugAI [2559]:   nearest bot to Sender; report (BestScore bug - Appendix C)
```
#### 6. TECHNICAL REFERENCE
- Functions: `BroadcastSpottedEnemy` [1220-1239], `InitTraderList` [2067-2088], `FindWeaponByClass` [2090-2105], `CoordStr` [1416-1419], `DebugMessage` [2535-2546], `PMsg` [2548-2557], `DebugAI` [2559-2588], `EchelonLog` [159-168].
- Edge cases: DebugAI BestScore uninitialized (Appendix C).
#### 7. WHERE TO FIX
- Log rate limit: LastAuditLogTime / 5s in EchelonLog [159-168].
- Trader list: InitTraderList [2067-2088].

# PART 4 (B) -- KF2BotBase.uc Subsystems (B1--B21, P4.1--P4.21)

Primary file: KF2BotBase.uc (4615 lines, `82491dfb`). Class `KF2BotBase` extends `KF2BotsFollowNavBase` [1], `hidecategories(Navigation)` [2]. The "Brain/Perception/Body" layer of the HCA: rank hierarchy (`EBotRank`), formation engine, overwatch/watch sectors, CQB, rescue, reload-drift, wedge, emote echo, panic broadcast, and the Squad-Leader decision loop. **Defines no state-machine states** (those are in KF2Bot.uc) and **no `PickMove` hub** (KF2Bot.uc). Timer callbacks are armed here but several are *defined* in KF2BotLogic. `defaultproperties` [4601-4615]: bIsPlayer=true, bNotifyApex=true, CurrentFormation=StaggeredColumn, ScanMask=15, PanicVarianceMultiplier=1.0, PanicScanSpeedMultiplier=1.0, ShotgunEffectiveRangeUU=1100.0, FlamethrowerEffectiveRangeUU=700.0, DefaultWeaponEffectiveRangeUU=5000.0. Citations `[123]` = KF2BotBase.uc line; `[Logic:123]` = KF2BotLogic.uc; `[Bot:123]` = KF2Bot.uc; `[Mut:123]` = KF2BotsMut.uc; `[Nav:123]` = KF2BotsFollowNavBase.uc.

---

### P4.1 (B1) Boot & restart   @SYS-BASE-BOOT      Primary file: KF2BotBase.uc
#### 1. PLAIN-ENGLISH SUMMARY
Bot birth and respawn plumbing: pre-spawn timer arming, destruction cleanup, replication-info init, weapon-def assignment, the full `Restart` respawn routine, spawn nudge, and the `EchelonLog` diagnostic logger used across the mod.
#### 2. EXPLANATION
- `PreBeginPlay()` [405-460] -- arms the rank/cadence timers: `IdleWatchdogTimer` [437] (0.5+Max(GroupID,0)*0.1, self-rearming), `ProcessOverwatchPhase` [444] (5.0s looping), `CaptainPathTimer` [448] (2.0s looping), `GruntDecisionTimer` [452] (1.5s looping) -- all four *defined* in KF2BotLogic.
- `Destroyed()` [462-471] -- destruction cleanup (timer clears, squad slots released).
- `InitPlayerReplicationInfo()` [473-514] -- replication-info setup (name tag seed, group id).
- `GiveWeaponDef()` [516-532] -- weapon-definition assignment on spawn.
- `Restart()` [534-625] -- the full respawn routine (pawn re-attach, state reset, rank re-arm, hub re-entry).
- `ValidateAndNudgeSpawn()` [2165-2182] -- post-spawn walkable-floor validation and nudge.
- `IsOnWalkableFloor()` [2184-2189] -- floor probe used by the spawn nudge.
- `EchelonLog()` [2484-2495] -- the mod's diagnostic logger (rate-limited, tagged) used by every other subsystem.
#### 3. LOGIC PIPELINE
`PreBeginPlay` arms the cadence timers that drive the Logic-layer loops (watchdog, overwatch, path, grunt decision). `Restart` is the respawn sink called by the native controller; it re-arms rank timers and funnels back into the hub. `EchelonLog` is the single logging path shared by all subsystems.
#### 4. INPUTS / OUTPUTS
Input: native controller/pawn lifecycle, `GroupID`, `BotRank`, `mut` flags. Output: armed timers, respawn state reset, rank re-arm, diagnostic log lines.
#### 5. FLOW   @FLOW-BASE-BOOT
```
PreBeginPlay [405] --> arm IdleWatchdogTimer[437], ProcessOverwatchPhase[444],
                        CaptainPathTimer[448], GruntDecisionTimer[452]
Restart [534] --> pawn re-attach, state reset, rank re-arm, hub re-entry [Bot:17]
Destroyed [462] --> cleanup (timers, squad slots)
InitPlayerReplicationInfo [473] | GiveWeaponDef [516]
ValidateAndNudgeSpawn [2165] --> IsOnWalkableFloor [2184] --> nudge
EchelonLog [2484] --> rate-limited tagged log (shared)
```
#### 6. TECHNICAL REFERENCE
- Ranges: PreBeginPlay [405-460], Destroyed [462-471], InitPlayerReplicationInfo [473-514], GiveWeaponDef [516-532], Restart [534-625], ValidateAndNudgeSpawn [2165-2182], IsOnWalkableFloor [2184-2189], EchelonLog [2484-2495].
- Cross-file: timer *definitions* in KF2BotLogic (L2); rank re-arm --> `ArmRankTimers` [3185]; hub re-entry [Bot:17].
#### 7. WHERE TO FIX
Timer arming (stagger/periods) --> `PreBeginPlay` [405-460]. Respawn correctness --> `Restart` [534-625]. Spawn nudging --> `ValidateAndNudgeSpawn` [2165-2182]. Diagnostic output --> `EchelonLog` [2484-2495].

### P4.2 (B2) Perception   @SYS-BASE-PERCEPT      Primary file: KF2BotBase.uc
#### 1. PLAIN-ENGLISH SUMMARY
Enemy and threat sensing: player/monster sight, eye-sight check, low-health targeting, next-enemy pick, `SetEnemy` with leash, threat scoring, and the hit/bump/wall/noise notifications that feed the combat pipeline.
#### 2. EXPLANATION
- `SeePlayer()` [637-643] / `SeeMonster()` [645-651] -- sight callbacks into `SetEnemy`.
- `EyeSightCheck()` [761-777] -- vision/LOS validity before committing an enemy.
- `TargetLowHealth()` [727-759] -- low-health target bias (shared with heal triage).
- `PickNextEnemy()` [779-803] -- selects the next enemy candidate.
- `SetEnemy()` [805-856] -- commits `Enemy` with leash bookkeeping (`LastLeashDropTime`, `LEASH_COOLDOWN`).
- `GetEnemyThreat()` [858-876] -- threat score for a candidate.
- `NotifyTakeHit()` [627-635] -- being hit (alert/retarget).
- `NotifyBump` (event [653], body through [725]) / `NotifyHitWall` (event [1749], body [1751-1809]) -- impact feedback.
- `HearNoise` (event) [4141-4170] -- `exec event HearNoise(NoiseTag, Location, Volume, Attacker)`; uses `HEAR_RANGE_SQ`, sets `HearNoiseZedCount`/`HearNoiseExpireTime`/`LastNoiseLoc`/`NoiseGlanceUntil`.
- `IsHostileZed()` [3628-3633] -- hostility predicate.
#### 3. LOGIC PIPELINE
Sight (`SeePlayer`/`SeeMonster`) --> `EyeSightCheck` --> `SetEnemy` (with leash). `PickNextEnemy`/`GetEnemyThreat`/`TargetLowHealth` score candidates. `HearNoise` seeds the grunt's zed-count that `ShouldThrowGrenade` (B19) reads. `IsHostileZed` gates zed scanning in the zed-count cache (B8).
#### 4. INPUTS / OUTPUTS
Input: sight/replicated hit/bump/wall/noise events, `Enemy`, world pawns. Output: `Enemy`, `LastLeashDropTime`, threat/low-health flags, `HearNoiseZedCount`/`LastNoiseLoc`, `NoiseGlanceUntil`.
#### 5. FLOW   @FLOW-BASE-PERCEPT
```
SeePlayer[637]/SeeMonster[645] --> EyeSightCheck[761] --> SetEnemy[805] (leash)
PickNextEnemy[779] | GetEnemyThreat[858] | TargetLowHealth[727]
NotifyTakeHit[627] | NotifyBump[653] | NotifyHitWall[1749]
HearNoise[4141] --> HearNoiseZedCount/LastNoiseLoc/NoiseGlanceUntil (range HEAR_RANGE_SQ)
IsHostileZed[3628] --> zed-scan gate (B8)
```
#### 6. TECHNICAL REFERENCE
- Ranges: SeePlayer [637-643], SeeMonster [645-651], EyeSightCheck [761-777], TargetLowHealth [727-759], PickNextEnemy [779-803], SetEnemy [805-856], GetEnemyThreat [858-876], NotifyTakeHit [627-635], NotifyBump (event [653]/body-->[725]), NotifyHitWall (event [1749]/body [1751-1809]), HearNoise [4141-4170], IsHostileZed [3628-3633].
- Constants: HEAR_RANGE_SQ 4000000.0, LEASH_COOLDOWN 2.0 [Base:91,342].
#### 7. WHERE TO FIX
Enemy commit/leash --> `SetEnemy` [805-856]. Threat/low-health scoring --> `PickNextEnemy` [779-803]/`GetEnemyThreat` [858-876]/`TargetLowHealth` [727-759]. Noise seeding (grenade feed) --> `HearNoise` [4141-4170].

### P4.3 (B3) Combat firing   @SYS-BASE-FIRE      Primary file: KF2BotBase.uc
#### 1. PLAIN-ENGLISH SUMMARY
The gun: aim adjustment, fire-at, view-point, turn/stop, melee-only detection, breathing wobble, and simulated bash hits.
#### 2. EXPLANATION
- `FireWeaponAt()` [881-932] -- fires the primary/bash/grenade form at a target.
- `GetAdjustedAimFor()` [1055-1080] -- aim lead/offset adjustment.
- `GetPlayerViewPoint()` [1082-1096] -- viewpoint sampling for aim.
- `NeedToTurn()` [1740-1747] / `StopAdjusting()` [1733-1738] -- turn-needed and adjustment-stop.
- `IsMeleeOnly()` [2309-2313] -- melee-only weapon predicate.
- `ApplyBreathing()` [4580-4583] -- `BREATH_OMEGA` (0.3) breathing wobble.
- `SimulateBashHit()` [1002-1033] -- melee bash hit simulation.
#### 3. LOGIC PIPELINE
Combat states (`FightEnemy` [Bot:605], CQB [B12]) call `FireWeaponAt` with a fire form (`BOTFM_PRIMARY`=0 / `BOTFM_RELOAD`=2 / `BOTFM_BASH`=3 / `BOTFM_GRENADE`=4). `GetAdjustedAimFor`/`GetPlayerViewPoint` feed the aim; `IsMeleeOnly` routes to bash; `ApplyBreathing` adds the wobble; `SimulateBashHit` resolves melee.
#### 4. INPUTS / OUTPUTS
Input: `Enemy`, weapon form, aim targets. Output: fire events, adjusted aim, melee hits, breathing offset.
#### 5. FLOW   @FLOW-BASE-FIRE
```
FireWeaponAt[881] (form BOTFM_*) | GetAdjustedAimFor[1055] | GetPlayerViewPoint[1082]
NeedToTurn[1740] | StopAdjusting[1733]
IsMeleeOnly[2309] --> bash (SimulateBashHit[1002])
ApplyBreathing[4580] (BREATH_OMEGA 0.3)
```
#### 6. TECHNICAL REFERENCE
- Ranges: FireWeaponAt [881-932], GetAdjustedAimFor [1055-1080], GetPlayerViewPoint [1082-1096], NeedToTurn [1740-1747], StopAdjusting [1733-1738], IsMeleeOnly [2309-2313], ApplyBreathing [4580-4583], SimulateBashHit [1002-1033].
- Constants: BOTFM_PRIMARY 0, BOTFM_RELOAD 2, BOTFM_BASH 3, BOTFM_GRENADE 4, BREATH_OMEGA 0.3 [Base:292,293,294,295,374].
#### 7. WHERE TO FIX
Aim/lead --> `GetAdjustedAimFor` [1055-1080]. Fire-form routing --> `FireWeaponAt` [881-932]. Melee/bash --> `IsMeleeOnly` [2309-2313] + `SimulateBashHit` [1002-1033]. Wobble --> `ApplyBreathing` [4580-4583].

### P4.4 (B4) Move abstraction   @SYS-BASE-MOVE      Primary file: KF2BotBase.uc
#### 1. PLAIN-ENGLISH SUMMARY
The movement API the rest of the mod calls: `MoveToX`/`MoveTowardX` (intent emission), strafe, direction, the process/abort path, blocked-path check, the FollowNav hub/gave-up hooks, the per-tick mover, finished-move, favorite-pick, and the `PickCombatStyle` state-exit hub.
#### 2. EXPLANATION
- `MoveToX()` [1098-1115] / `MoveTowardX()` [1117-1144] -- emit a move intent (single-writer: they *request*, the tick *executes*).
- `StrafeTowardPoint()` [1146-1174] -- strafe around a point.
- `GetMoveDirection()` [1176-1192] -- resolve the move direction vector.
- `ProcessMoveTo()` [1194-1217] / `ProcessMoveToward()` [1219-1247] -- execute the pending intent each tick.
- `AbortMove()` [1249-1256] -- cancel the intent.
- `CheckBlockedPath()` [1258-1280] -- blocked-path detection (feeds stuck/B11).
- `FollowNotifyHub()` [1287-1312] -- override of the FollowNavBase hook: notifies the hub of a follow event.
- `FollowOnGaveUp()` [1317-1320] -- override: follow gave-up handling.
- `Tick()` [1322-1461] -- the per-tick mover (executes intents, drives the follow layer).
- `FinishedMove()` [1811-1814] -- move-complete hook.
- `PickFavorite()` [1816-1838] -- favorite-weapon/target pick.
- `PickCombatStyle()` [2123-2159] -- the **state-exit hub**: P1 terminal lock `if (bInTerminalState) GotoState('VictoryDance')`; HCA follow-flap crash fix `if (mut.bEnableAdvancedLocomotion && (IsInState('FollowingLeader') || IsInState('FollowingLeaderBasic'))) return;` (no `GotoState`); else `GotoState('PickNextMove')` [Bot:17].
#### 3. LOGIC PIPELINE
Every state's exit path --> `PickCombatStyle` [2123] --> hub [Bot:17]. Move intents are set by `MoveToX`/`MoveTowardX` and executed by `Tick` via `ProcessMoveTo`/`ProcessMoveToward`. `CheckBlockedPath` and `FinishedMove` close the loop; the FollowNav hooks bridge the follow layer back to the hub.
#### 4. INPUTS / OUTPUTS
Input: move intents, `Enemy`/goal, follow-layer state, `mut.bEnableAdvancedLocomotion`. Output: executed movement, follow-notify, state exit --> hub, `bInTerminalState` lock.
#### 5. FLOW   @FLOW-BASE-MOVE
```
PickCombatStyle[2123] (state exit)
?  bInTerminalState --> VictoryDance
?  advLoco && (FollowingLeader|FollowingLeaderBasic) --> return (no hop, crash fix)
?  else --> GotoState('PickNextMove') [Bot:17]
MoveToX[1098]/MoveTowardX[1117] --> intent
Tick[1322] --> ProcessMoveTo[1194]/ProcessMoveToward[1219]
StrafeTowardPoint[1146] | GetMoveDirection[1176] | AbortMove[1249]
CheckBlockedPath[1258] | FinishedMove[1811] | PickFavorite[1816]
FollowNotifyHub[1287] | FollowOnGaveUp[1317]
```
#### 6. TECHNICAL REFERENCE
- Ranges: MoveToX [1098-1115], MoveTowardX [1117-1144], StrafeTowardPoint [1146-1174], GetMoveDirection [1176-1192], ProcessMoveTo [1194-1217], ProcessMoveToward [1219-1247], AbortMove [1249-1256], CheckBlockedPath [1258-1280], FollowNotifyHub [1287-1312], FollowOnGaveUp [1317-1320], Tick [1322-1461], FinishedMove [1811-1814], PickFavorite [1816-1838], PickCombatStyle [2123-2159].
- Cross-file: hub [Bot:17]; FollowNavBase hooks [Nav]; terminal state [Bot:1972].
#### 7. WHERE TO FIX
State-exit hub / terminal lock / follow-flap crash fix --> `PickCombatStyle` [2123-2159]. Intent execution --> `Tick` [1322-1461] + `ProcessMoveTo`/`ProcessMoveToward`. Blocked/stuck --> `CheckBlockedPath` [1258-1280].

### P4.5 (B5) Path building   @SYS-BASE-PATH      Primary file: KF2BotBase.uc
#### 1. PLAIN-ENGLISH SUMMARY
Navigation-path construction: build a path toward a point/actor, build a random roam path, and mark door-path blockades.
#### 2. EXPLANATION
- `MarkDoorPath()` [1463-1494] -- records a `FRouteDoorBlockade` (door + path point, struct [4-8]) when a route passes a door.
- `BuildPathToward()` [1496-1573] -- path toward a point.
- `BuildPathTo()` [1575-1652] -- path to an actor.
- `BuildRandomPath()` [1654-1731] -- random roam path (Roaming [Bot:261]).
#### 3. LOGIC PIPELINE
Move intents (`MoveToX`) drive these builders; the path token budget (`ConsumePathToken` [Logic:577]) meters native path calls. `MarkDoorPath` latches door blockades that the follow layer and stuck tracking (L4) consume.
#### 4. INPUTS / OUTPUTS
Input: target point/actor, door actors, path budget. Output: navigation paths, `DoorPaths` (FRouteDoorBlockade) entries.
#### 5. FLOW   @FLOW-BASE-PATH
```
BuildPathToward[1496] | BuildPathTo[1575] | BuildRandomPath[1654]
MarkDoorPath[1463] --> DoorPaths (FRouteDoorBlockade [4-8])
(metered by ConsumePathToken [Logic:577])
```
#### 6. TECHNICAL REFERENCE
- Ranges: MarkDoorPath [1463-1494], BuildPathToward [1496-1573], BuildPathTo [1575-1652], BuildRandomPath [1654-1731].
- Struct: FRouteDoorBlockade [4-8] (`door` [6], `Path` [7]).
- Cross-file: budget [Logic:577]; roam consumer [Bot:261].
#### 7. WHERE TO FIX
Path construction --> `BuildPathToward`/`BuildPathTo`/`BuildRandomPath`. Door blockade latching --> `MarkDoorPath` [1463-1494].

### P4.6 (B6) Shopping & economy   @SYS-BASE-SHOP      Primary file: KF2BotBase.uc
#### 1. PLAIN-ENGLISH SUMMARY
Trader logic: best-weapon switch, sell, best-buy, the full purchase routine, inventory-add notification, and money donation.
#### 2. EXPLANATION
- `SwitchToBestWeapon()` [1045-1053] -- post-purchase best-weapon switch.
- `SellWeapon()` [1840-1882] -- sell a weapon.
- `GetBestBuy()` [1884-1937] -- pick the best purchase.
- `ProcessPurchase()` [1939-2111] -- the full purchase routine (the GoShopping state [Bot:1578] drives this).
- `NotifyAddInventory()` [2113-2121] -- inventory-add callback.
- `DonateMoney()` [1040-1043] -- money donation (DonatingMoney [Bot:1778]).
#### 3. LOGIC PIPELINE
Hub P9 --> `GoShopping` [Bot:1578] --> `ProcessPurchase` --> `GetBestBuy`/`SellWeapon`/`SwitchToBestWeapon`. `NotifyAddInventory` and `DonateMoney` close the loop.
#### 4. INPUTS / OUTPUTS
Input: `KFGRI.bTraderIsOpen`/`OpenedTrader`, inventory, weapon defs. Output: purchases/sells, best-weapon switch, inventory updates, donations.
#### 5. FLOW   @FLOW-BASE-SHOP
```
GoShopping [Bot:1578] --> ProcessPurchase[1939] --> GetBestBuy[1884]/SellWeapon[1840]
SwitchToBestWeapon[1045] | NotifyAddInventory[2113] | DonateMoney[1040]
```
#### 6. TECHNICAL REFERENCE
- Ranges: SwitchToBestWeapon [1045-1053], SellWeapon [1840-1882], GetBestBuy [1884-1937], ProcessPurchase [1939-2111], NotifyAddInventory [2113-2121], DonateMoney [1040-1043].
- Cross-file: `GoShopping` [Bot:1578], `DonatingMoney` [Bot:1778]; trader flags from `mut.KF.MyKFGRI`.
#### 7. WHERE TO FIX
Purchase correctness --> `ProcessPurchase` [1939-2111]. Buy/sell selection --> `GetBestBuy` [1884-1937]/`SellWeapon` [1840-1882]. Weapon restore --> `SwitchToBestWeapon` [1045-1053].

### P4.7 (B7) Objective & hazard   @SYS-BASE-OBJ      Primary file: KF2BotBase.uc
#### 1. PLAIN-ENGLISH SUMMARY
Objective work and hazards: objective-hazard check, objective location, boss-wave detection/active-boss, break-free and force-break-grapple (escaping a hold).
#### 2. EXPLANATION
- `CheckObjectiveHazard()` [2318-2361] -- `OBJECTIVE_HAZARD_RADIUS` (800.0) / `OBJECTIVE_HAZARD_ZED_COUNT` (3) hazard gate before committing to the objective.
- `GetObjectiveLocation()` [2440-2461] -- resolve the objective location.
- `IsBossWaveActive()` [2463-2474] / `GetActiveBoss()` [2476-2479] -- boss-wave detection and active-boss reference.
- `TryBreakFree()` [945-996] -- attempt to break a grapple (BreakLose [Bot:954]).
- `ForceBreakGrapple()` [2375-2412] -- force a grapple break (the tail of the break-free path).
#### 3. LOGIC PIPELINE
Hub P5 --> `DoObjective` [Bot:485] uses `GetObjectiveLocation`/`CheckObjectiveHazard`/`IsBossWaveActive`. Grab detection (`CheckGrabbed` [Logic:304]) --> `BreakLose` [Bot:954] --> `TryBreakFree`/`ForceBreakGrapple`.
#### 4. INPUTS / OUTPUTS
Input: objective state, boss pawns, grapple (`IsDoingSpecialMove(31)`, `InteractionPawn`). Output: objective location/goal, hazard flag, break-free progress, active-boss reference.
#### 5. FLOW   @FLOW-BASE-OBJ
```
DoObjective [Bot:485] --> GetObjectiveLocation[2440] | CheckObjectiveHazard[2318]
                       | IsBossWaveActive[2463]/GetActiveBoss[2476]
CheckGrabbed [Logic:304] --> BreakLose [Bot:954] --> TryBreakFree[945]/ForceBreakGrapple[2375]
```
#### 6. TECHNICAL REFERENCE
- Ranges: CheckObjectiveHazard [2318-2361], GetObjectiveLocation [2440-2461], IsBossWaveActive [2463-2474], GetActiveBoss [2476-2479], TryBreakFree [945-996], ForceBreakGrapple [2375-2412].
- Constants: OBJECTIVE_HAZARD_RADIUS 800.0, OBJECTIVE_HAZARD_ZED_COUNT 3, SIREN_CHECK_RADIUS 1200.0 [Base:95,96,97].
#### 7. WHERE TO FIX
Objective location/hazard --> `GetObjectiveLocation` [2440-2461]/`CheckObjectiveHazard` [2318-2361]. Boss handling --> `IsBossWaveActive` [2463-2474]/`GetActiveBoss` [2476-2479]. Grapple escape --> `TryBreakFree` [945-996]/`ForceBreakGrapple` [2375-2412].

---

### P4.8 (B8) Zed counting & retreat gating   @SYS-BASE-ZEDS      Primary file: KF2BotBase.uc
#### 1. PLAIN-ENGLISH SUMMARY
Zed density and retreat decisions: raw and cached nearby-zed counts, heavy-zed detection, the tactical-retreat predicate and its "is it safe to run" check, wave momentum, the retreat-count gate, hold-area drift, and heavy-zed-pawn test.
#### 2. EXPLANATION
- `CountNearbyZeds()` [2226-2245] -- raw zed count in a radius.
- `CountNearbyZedsCached()` [3565-3581] -- cached zed count (throttled by `ZED_COUNT_INTERVAL`).
- `RefreshSquadZedCache()` [3584-3608] -- refreshes `SquadZedCache[16]`/`SquadZedCount` (300u scan, cap 16).
- `AreZedsNear()` [2255-2270] -- near-zed predicate.
- `HeavyZedWithin()` [2275-2291] -- heavy zed within `RETREAT_HEAVY_RADIUS` (300.0).
- `ShouldTacticalRetreat()` [2293-2307] -- the retreat predicate: zed trigger/clear counts (`RETREAT_ZED_TRIGGER_COUNT` 4 / `RETREAT_ZED_CLEAR_COUNT` 2) + heavy zed, gated by `CachedZedCount`/`bCachedHeavyZed`.
- `GetWaveMomentum()` [4566-4572] -- `Max(1.0, WaveNum*0.15 + 1.0)`.
- `ExceedsRetreatZedCount()` [4574-4578] -- `CachedZedCount >= int(RETREAT_ZED_TRIGGER_COUNT / GetWaveMomentum())` (later waves tolerate more zeds before retreating).
- `UpdateHoldAreaDrift()` [4585-4597] -- slow hold-area drift (60s window, `DRIFT_RATE`*60, capped `DRIFT_MAX_TOTAL` 300u).
- `IsHeavyZedPawn()` [4181-4186] -- heavy-zed predicate.
- `IsRetreatSafe()` [3004-3021] -- `IsDirClearCached` + `VisibleCollidingActors` zed check (500.0) -- whether the retreat direction is actually open.
#### 3. LOGIC PIPELINE
Hub P4 (leader) and `SLDecisionLoop` (B9) both call `ShouldTacticalRetreat`/`ExceedsRetreatZedCount`. Before issuing a retreat, `IsRetreatSafe` confirms the direction is clear (else the loop holds/crouches instead). Zed caches are refreshed by `RefreshSquadZedCache`/`CountNearbyZedsCached` so tick loops stay budgeted.
#### 4. INPUTS / OUTPUTS
Input: world zed pawns, `CachedZedCount`/`bCachedHeavyZed`/`LastZedCountTime`, `WaveNum`, `mut`. Output: retreat decision, `SquadZedCache`/`SquadZedCount`, hold-area drift, retreat-safety flag.
#### 5. FLOW   @FLOW-BASE-ZEDS
```
ShouldTacticalRetreat[2293] (trigger 4 / clear 2, heavy zed 300u)
ExceedsRetreatZedCount[4574] = CachedZedCount >= int(TRIGGER/Momentum)
GetWaveMomentum[4566] = Max(1.0, WaveNum*0.15+1.0)
IsRetreatSafe[3004] = IsDirClearCached + zed<500u
CountNearbyZeds[2226]/Cached[3565] | AreZedsNear[2255] | HeavyZedWithin[2275]
RefreshSquadZedCache[3584] (300u, cap16) | UpdateHoldAreaDrift[4585] | IsHeavyZedPawn[4181]
```
#### 6. TECHNICAL REFERENCE
- Ranges: CountNearbyZeds [2226-2245], CountNearbyZedsCached [3565-3581], RefreshSquadZedCache [3584-3608], AreZedsNear [2255-2270], HeavyZedWithin [2275-2291], ShouldTacticalRetreat [2293-2307], GetWaveMomentum [4566-4572], ExceedsRetreatZedCount [4574-4578], UpdateHoldAreaDrift [4585-4597], IsHeavyZedPawn [4181-4186], IsRetreatSafe [3004-3021].
- Constants: RETREAT_ZED_RADIUS 500.0, RETREAT_ZED_TRIGGER_COUNT 4, RETREAT_ZED_CLEAR_COUNT 2, RETREAT_HEAVY_RADIUS 300.0, ZED_COUNT_INTERVAL 1.0, DRIFT_RATE 0.8333333, DRIFT_MAX_TOTAL 300.0 [Base:64,65,66,67,93,375,377].
#### 7. WHERE TO FIX
Retreat predicate/thresholds --> `ShouldTacticalRetreat` [2293-2307]/`ExceedsRetreatZedCount` [4574-4578]. Wave scaling --> `GetWaveMomentum` [4566-4572]. Retreat-direction safety --> `IsRetreatSafe` [3004-3021]. Zed cache --> `RefreshSquadZedCache` [3584-3608]/`CountNearbyZedsCached` [3565-3581].

### P4.9 (B9) Rank, role & Echelon loops   @SYS-BASE-RANK      Primary file: KF2BotBase.uc
#### 1. PLAIN-ENGLISH SUMMARY
The Echelon hierarchy: the `EBotRank` enum, rank set/name, role-name tagging, grunt gates, rank-timer arming/clearing, the three rank loops (Squad-Leader decision loop, Lieutenant dispatch stub, Captain path stub), and the command issuer.
#### 2. EXPLANATION
- `EBotRank` [14-20] -- GRUNT, SQUAD_LEADER, LIEUTENANT, CAPTAIN.
- `SetBotRank()` [3223-3227] -- assign rank (and arm/clear timers).
- `GetRankName()` [3086-3100] -- rank --> name string.
- `UpdateRoleNameTag()` [3104-3124] / `RefreshRoleNameTag()` [3132-3176] -- player-visible role tag.
- `SeedGruntGates()` [3178-3183] -- seed the grunt's initial gates.
- `ArmRankTimers()` [3185-3203] -- SQUAD_LEADER-->`StartSLLoop` (0.5s loop), LIEUTENANT-->`StartLTLoop` (1.0s), CAPTAIN-->`StartCaptainLoop` (3.0s), GRUNT-->`SeedGruntGates`.
- `ClearRankTimers()` [3066-3083] -- clear all rank timers (death/rank change).
- `SLDecisionLoop()` [2627-2680] -- 0.5s; gates on `bSLLoopSuspended`; calls `ScanRoomForFormation`, `RefreshSquadZedCache`, `SLGrenadeCheck`, `CheckWeaponReequip`, `UpdateOverwatchTimer`, `CheckOverwatchStall`, `UpdatePanicBroadcast`, `HandleReloadDrift`, `UpdateWedgeMode`, `UpdateHoldAreaDrift`, and `ShouldTacticalRetreat`/`ExceedsRetreatZedCount` --> `IssueCommand('CMD_TacticalRetreat')`.
- `LTDispatchLoop()` [2684-2687] -- placeholder stub.
- `CaptainPathLoop()` [2691-2694] -- placeholder stub.
- `StartSLLoop()` [3205-3209] / `StartLTLoop()` [3211-3215] / `StartCaptainLoop()` [3217-3221] -- loop starters.
- `IssueCommand()` [2617-2622] -- issue a squad command (`CMD_TacticalRetreat` etc.).
#### 3. LOGIC PIPELINE
`ArmRankTimers` (from `SetBotRank`/`Restart`) starts the rank loop for the bot's rank. `SLDecisionLoop` is the squad-leader's periodic brain: it refreshes formation/zed/grenade/weapon/overwatch/panic/reload/wedge/hold state and, when `ShouldTacticalRetreat`/`ExceedsRetreatZedCount` fire, calls `IssueCommand('CMD_TacticalRetreat')`. Lt/Captain loops are currently stubs.
#### 4. INPUTS / OUTPUTS
Input: `BotRank`, `bSLLoopSuspended`, squad state, `mut`. Output: armed loops, squad commands, formation/zed/grenade/overwatch/panic/reload/wedge/hold updates, rank name tag.
#### 5. FLOW   @FLOW-BASE-RANK
```
ArmRankTimers[3185] (from SetBotRank[3223]/Restart[534])
?  SQUAD_LEADER --> StartSLLoop[3205] (0.5s)
?  LIEUTENANT  --> StartLTLoop[3211] (1.0s, stub [2684])
?  CAPTAIN     --> StartCaptainLoop[3217] (3.0s, stub [2691])
?  GRUNT       --> SeedGruntGates[3178]
SLDecisionLoop[2627] (0.5s, gate bSLLoopSuspended)
?  ScanRoomForFormation | RefreshSquadZedCache | SLGrenadeCheck
?  CheckWeaponReequip | UpdateOverwatchTimer | CheckOverwatchStall
?  UpdatePanicBroadcast | HandleReloadDrift | UpdateWedgeMode | UpdateHoldAreaDrift
?  ShouldTacticalRetreat/ExceedsRetreatZedCount --> IssueCommand('CMD_TacticalRetreat')[2617]
ClearRankTimers[3066] (death/rank change)
```
#### 6. TECHNICAL REFERENCE
- Ranges: EBotRank [14-20], SetBotRank [3223-3227], GetRankName [3086-3100], UpdateRoleNameTag [3104-3124], RefreshRoleNameTag [3132-3176], SeedGruntGates [3178-3183], ArmRankTimers [3185-3203], ClearRankTimers [3066-3083], SLDecisionLoop [2627-2680], LTDispatchLoop [2684-2687], CaptainPathLoop [2691-2694], StartSLLoop [3205-3209], StartLTLoop [3211-3215], StartCaptainLoop [3217-3221], IssueCommand [2617-2622].
- Cross-file: all `SLDecisionLoop` callees are in this file (B8/B10/B11/B14/B15/B17/B19); hub P4 retreat [Bot:57].
#### 7. WHERE TO FIX
SL periodic brain --> `SLDecisionLoop` [2627-2680]. Rank loop wiring --> `ArmRankTimers` [3185-3203]/`ClearRankTimers` [3066-3083]. Lt/Captain stubs --> `LTDispatchLoop` [2684-2687]/`CaptainPathLoop` [2691-2694]. Squad command issue --> `IssueCommand` [2617-2622].

### P4.10 (B10) Formation engine   @SYS-BASE-FORM      Primary file: KF2BotBase.uc
#### 1. PLAIN-ENGLISH SUMMARY
Squad formation: the 4-way room scan that picks Arrowhead/StaggeredColumn/SingleFile, formation base/slot offsets, offset caching and validation, reroute requests, direction-clear cache, and squad-slot assignment.
#### 2. EXPLANATION
- `ScanRoomForFormation()` [2702-2803] -- 4-way trace (fwd/left/right/back) into `ScanMask` bits; `ClearCount>=3`-->Arrowhead, `>=2`-->StaggeredColumn, else SingleFile; LineFormation when `FwdDistSq>=360000`, `bLeft`, `bRight`, `Enemy>0` and LOS>0.5, `LineSuppressUntil>=now`; 2-call debounce via `PendingFormationCount`.
- `DeferredFormationScan()` [2805-2809] -- deferred (budgeted) scan trigger.
- `GetFormationBase()` [2813-2840] -- formation base offset (Arrowhead X=-150*Tier, Y=+/-150*Tier; Line X=-40, Y=+/-120*Tier; SingleFile X=-150*(Slot+1); default StaggeredColumn X=-130*(Slot+1), Y=+/-70).
- `ComputeSlotOffset()` [2842-2889] -- per-slot offset with jitter (0.10-0.15).
- `ComputeFormationOffset()` [2191-2219] -- formation offset from base + slot.
- `ValidateOffsetTarget()` [2955-2971] -- `FastTrace` the offset target; `BlockedCounter>=3` --> `RequestRerouteWithBlock`.
- `RequestRerouteWithBlock()` [2973-2979] -- SL only sets `bRerouteRequested`.
- `IsDirClearCached()` [2981-3002] -- direction-clear cache (uses `ScanMask` bits).
- `AssignSquadSlots()` [3667-3677] -- assign `SquadMembers[4]` slots.
#### 3. LOGIC PIPELINE
`SLDecisionLoop` (B9) calls `ScanRoomForFormation` each 0.5s; the result feeds `GetFormationBase`/`ComputeSlotOffset`/`ComputeFormationOffset` which the grunt tick (L3 step 14) applies as `GruntTarget`. `ValidateOffsetTarget` guards the target and can request a reroute. `IsDirClearCached` is also used by `IsRetreatSafe` (B8).
#### 4. INPUTS / OUTPUTS
Input: `ScanMask`, `CurrentFormation`/`PendingFormation`, `Enemy`, LOS, `SquadMembers`. Output: formation choice, base/slot offsets, `bRerouteRequested`, dir-clear cache, squad slots.
#### 5. FLOW   @FLOW-BASE-FORM
```
ScanRoomForFormation[2702] (4-way trace -> ScanMask)
?  ClearCount>=3 --> Arrowhead; >=2 --> StaggeredColumn; else SingleFile
?  LineFormation (Fwd>=360000 && L && R && Enemy && LOS>0.5 && !LineSuppress)
GetFormationBase[2813] --> ComputeSlotOffset[2842] --> ComputeFormationOffset[2191]
ValidateOffsetTarget[2955] (FastTrace; Blocked>=3 --> RequestRerouteWithBlock[2973])
IsDirClearCached[2981] | AssignSquadSlots[3667] | DeferredFormationScan[2805]
```
#### 6. TECHNICAL REFERENCE
- Ranges: ScanRoomForFormation [2702-2803], DeferredFormationScan [2805-2809], GetFormationBase [2813-2840], ComputeSlotOffset [2842-2889], ComputeFormationOffset [2191-2219], ValidateOffsetTarget [2955-2971], RequestRerouteWithBlock [2973-2979], IsDirClearCached [2981-3002], AssignSquadSlots [3667-3677].
- Constants: FORM_SCAN_DIST 150.0, FORM_LINE_DIST 650.0, SINGLE_FILE_SPACING 130.0 [Base:52,262,263].
- Cross-file: consumer is the grunt tick [Logic:327] step 14; `IsDirClearCached` used by `IsRetreatSafe` [3004].
#### 7. WHERE TO FIX
Formation choice --> `ScanRoomForFormation` [2702-2803]. Offsets --> `GetFormationBase` [2813-2840]/`ComputeSlotOffset` [2842-2889]. Target validation/reroute --> `ValidateOffsetTarget` [2955-2971]/`RequestRerouteWithBlock` [2973-2979].

### P4.11 (B11) Line focus & overwatch   @SYS-BASE-OVERWATCH      Primary file: KF2BotBase.uc
#### 1. PLAIN-ENGLISH SUMMARY
The overwatch/hold-advance system: line-focus sync, own-fire-line check, blocked-shooter reporting, overwatch phase toggle/broadcast/receive, overwatch timer and stall check, overwatch-stuck test, overwatch movement, break-lose completion, and sector watch.
#### 2. EXPLANATION
- `SyncLineFocus()` [2893-2936] -- grunt inherits the SL's enemy in line formation.
- `HasOwnFireLine()` [2938-2951] -- `FastTrace` from eye height, 0.5s cache (`bFireLineClear`).
- `NotifyBlockedShooter()` [3234-3256] -- SL; 1.5s window; count>=2 --> `LineSuppressUntil`+4.0, LineFormation-->StaggeredColumn.
- `ToggleOverwatchPhase()` [3638-3651] -- toggle `bOverwatchPhase` (HOLD/ADVANCE).
- `BroadcastOverwatchState()` [3654-3664] -- broadcast overwatch phase to squad.
- `ReceiveOverwatchState()` [3762-3769] -- receive a phase update.
- `UpdateOverwatchTimer()` [3680-3714] -- overwatch cadence (engage expire, toggle).
- `CheckOverwatchStall()` [3717-3759] -- stall check (`StuckCounter>=2` --> `bOverwatchAllMove`, new anchor `VRand*150`).
- `IsOverwatchStuck()` [3772-3775] -- stuck predicate.
- `UpdateOverwatchMovement()` [3778-3856] -- overwatch movement to the move target.
- `OnBreakLoseComplete()` [3859-3868] -- break-lose completion hook.
- `UpdateSectorWatch()` [3873-3914] -- sector watch (CMD_HoldArea, no enemy).
#### 3. LOGIC PIPELINE
Captain cadence (`ProcessOverwatchPhase` [Logic:821]) + `SLDecisionLoop` (B9) drive the overwatch: toggle phase, broadcast/receive, update timer, check stall, and move. Line focus and fire-line support the hold/advance posture; blocked-shooter reports suppress line formation.
#### 4. INPUTS / OUTPUTS
Input: `bOverwatchPhase`, `EngageExpireTime`, `StuckCounter`, `bOverwatchAllMove`, squad members, `Enemy`, LOS. Output: overwatch phase/anchors, movement, line-suppress, sector watch.
#### 5. FLOW   @FLOW-BASE-OVERWATCH
```
UpdateOverwatchTimer[3680] --> ToggleOverwatchPhase[3638] --> BroadcastOverwatchState[3654]
ReceiveOverwatchState[3762] | CheckOverwatchStall[3717] (Stuck>=2 --> bOverwatchAllMove, VRand*150)
IsOverwatchStuck[3772] | UpdateOverwatchMovement[3778]
SyncLineFocus[2893] | HasOwnFireLine[2938] (0.5s cache)
NotifyBlockedShooter[3234] (SL, 1.5s, count>=2 --> LineSuppress+4.0, Line-->Staggered)
OnBreakLoseComplete[3859] | UpdateSectorWatch[3873]
```
#### 6. TECHNICAL REFERENCE
- Ranges: SyncLineFocus [2893-2936], HasOwnFireLine [2938-2951], NotifyBlockedShooter [3234-3256], ToggleOverwatchPhase [3638-3651], BroadcastOverwatchState [3654-3664], ReceiveOverwatchState [3762-3769], UpdateOverwatchTimer [3680-3714], CheckOverwatchStall [3717-3759], IsOverwatchStuck [3772-3775], UpdateOverwatchMovement [3778-3856], OnBreakLoseComplete [3859-3868], UpdateSectorWatch [3873-3914].
- Constants: OW_TOGGLE_INTERVAL 1.5, OW_STUCK_TIME 1.0, OW_STUCK_MIN_DIST_SQ 10000.0, OW_STUCK_MOVE_SQ 900.0 [Base:326,327,328,329].
- Cross-file: captain cadence [Logic:821]; grunt tick steps 3/7/8 [Logic:327].
#### 7. WHERE TO FIX
Overwatch phase/timer --> `UpdateOverwatchTimer` [3680-3714]/`ToggleOverwatchPhase` [3638-3651]. Stall --> `CheckOverwatchStall` [3717-3759]. Line suppress --> `NotifyBlockedShooter` [3234-3256]. Sector watch --> `UpdateSectorWatch` [3873-3914].

### P4.12 (B12) CQB & crouch/hold   @SYS-BASE-CQB      Primary file: KF2BotBase.uc
#### 1. PLAIN-ENGLISH SUMMARY
Close-quarters handling and the squad crouch/hold primitives: proximity bash/stepback, crouch apply, squad crouch-hold set/clear/apply, hold-and-crouch, safe-anchor issue, and cover crouch.
#### 2. EXPLANATION
- `HandleCQBProximity()` [3919-3970] -- bash at `CQB_BASH_SQ` (120u2; `StartFire` `BOTFM_BASH`=3, melee `StartFire(0)`) every `CQB_BASH_INTERVAL` (0.8), stepback `CQB_STEPBACK_SPEED` (100), flashlight toggle; `CQB_MID_SQ` (180u2) flashlight ON.
- `SetSquadCrouchHold()` [3023-3027] / `ClearSquadCrouchHold()` [3029-3032] -- squad crouch-hold set/clear.
- `HoldAndCrouch()` [3034-3038] -- hold-and-crouch (unsafe retreat fallback, B8/B9).
- `TryIssueSafeAnchor()` [3040-3050] -- issue a safe anchor.
- `ApplySquadCrouchHold()` [3052-3062] -- apply the squad crouch hold (grunt tick step 4).
- `ApplyCrouch()` [3620-3626] -- apply crouch.
- `UpdateCoverCrouch()` [4043-4059] -- cover crouch (grunt tick step 11).
#### 3. LOGIC PIPELINE
The grunt tick (L3) calls `ApplySquadCrouchHold` (step 4), `HandleCQBProximity` (step 9), and `UpdateCoverCrouch` (step 11). `HoldAndCrouch` is the retreat-fallback when `IsRetreatSafe` (B8) is false. CQB bash fires via `FireWeaponAt`/`StartFire` (B3).
#### 4. INPUTS / OUTPUTS
Input: enemy distance (CQB squares), `bSquadCrouchHold`/`bHoldCrouching`, cover. Output: bash/stepback, crouch state, safe anchor, cover crouch.
#### 5. FLOW   @FLOW-BASE-CQB
```
HandleCQBProximity[3919]
?  dist<=CQB_MID_SQ (180u) --> flashlight ON
?  dist<=CQB_BASH_SQ (120u) --> StartFire(BASH/0) every 0.8s + stepback(100)
SetSquadCrouchHold[3023]/Clear[3029] | ApplySquadCrouchHold[3052] (grunt step4)
HoldAndCrouch[3034] | TryIssueSafeAnchor[3040]
ApplyCrouch[3620] | UpdateCoverCrouch[4043] (grunt step11)
```
#### 6. TECHNICAL REFERENCE
- Ranges: HandleCQBProximity [3919-3970], SetSquadCrouchHold [3023-3027], ClearSquadCrouchHold [3029-3032], HoldAndCrouch [3034-3038], TryIssueSafeAnchor [3040-3050], ApplySquadCrouchHold [3052-3062], ApplyCrouch [3620-3626], UpdateCoverCrouch [4043-4059].
- Constants: CQB_BASH_SQ 14400.0, CQB_MID_SQ 32400.0, CQB_BASH_INTERVAL 0.8, CQB_STEPBACK_SPEED 100.0, COVER_RANGE_SQ 640000.0 [Base:335,336,337,338,339].
#### 7. WHERE TO FIX
CQB bash/stepback --> `HandleCQBProximity` [3919-3970]. Crouch/hold primitives --> `ApplySquadCrouchHold` [3052-3062]/`HoldAndCrouch` [3034-3038]. Cover --> `UpdateCoverCrouch` [4043-4059].

### P4.13 (B13) Grunt rescue   @SYS-BASE-GRUNT      Primary file: KF2BotBase.uc
#### 1. PLAIN-ENGLISH SUMMARY
Grunt rescue and grunt-combat behaviour: on-grunt-grabbed (dispatch a rescuer), begin rescue, grunt combat lock, grunt on-sight/enter-combat, grunt combat style pick, and cover crouch (shared with B12).
#### 2. EXPLANATION
- `OnGruntGrabbed()` [3977-4018] -- when a grunt is grabbed, find the nearest 2 squadmates and `BeginRescue`.
- `BeginRescue()` [4023-4036] -- begin a rescue (`RescueLoc`/`RescueUntil`).
- `IsGruntCombatLocked()` [4066-4071] -- grunt combat-lock predicate.
- `GruntOnSight()` [4076-4086] -- grunt sight reaction.
- `GruntEnterCombat()` [4091-4103] -- grunt enter-combat.
- `GruntPickCombatStyle()` [4108-4135] -- grunt combat style pick.
#### 3. LOGIC PIPELINE
Grab detection (`OnGruntGrabbed`) sets `RescueUntil`/`RescueLoc`, which the grunt tick (L3 step 10) consumes as `MoveToX(RescueLoc)`. Grunt combat (on-sight/enter/style) shapes grunt engagement.
#### 4. INPUTS / OUTPUTS
Input: grab event, `SquadMembers`, `Enemy`, `RescueUntil`/`RescueLoc`. Output: rescue assignment, grunt combat state.
#### 5. FLOW   @FLOW-BASE-GRUNT
```
OnGruntGrabbed[3977] (nearest 2) --> BeginRescue[4023] (RescueLoc/RescueUntil)
?  grunt tick step10 [Logic:327] --> MoveToX(RescueLoc)
IsGruntCombatLocked[4066] | GruntOnSight[4076] | GruntEnterCombat[4091] | GruntPickCombatStyle[4108]
```
#### 6. TECHNICAL REFERENCE
- Ranges: OnGruntGrabbed [3977-4018], BeginRescue [4023-4036], IsGruntCombatLocked [4066-4071], GruntOnSight [4076-4086], GruntEnterCombat [4091-4103], GruntPickCombatStyle [4108-4135].
- Constants: RESCUE_RANGE_SQ 1000000.0, RESCUE_DURATION 5.0 [Base:340,341].
- Cross-file: rescue consumed by grunt tick [Logic:327] step 10.
#### 7. WHERE TO FIX
Rescue dispatch --> `OnGruntGrabbed` [3977-4018]/`BeginRescue` [4023-4036]. Grunt combat --> `GruntPickCombatStyle` [4108-4135]/`GruntEnterCombat` [4091-4103].

### P4.14 (B14) Panic broadcast   @SYS-BASE-PANIC      Primary file: KF2BotBase.uc
#### 1. PLAIN-EnGLISH SUMMARY
Squad panic broadcast: update the panic broadcast, receive it, and apply panic variance (scatter) to a bot's behaviour.
#### 2. EXPLANATION
- `UpdatePanicBroadcast()` [4188-4203] -- SL broadcasts panic (300u radius, `PANIC_MULT` 2.0, scatter `PANIC_SCATTER_MIN`/`MAX` 200-400u).
- `ReceivePanic()` [4205-4210] -- receive the panic broadcast.
- `ApplyPanicVariance()` [4212-4225] -- apply panic variance (grunt tick step 2).
#### 3. LOGIC PIPELINE
`SLDecisionLoop` (B9) calls `UpdatePanicBroadcast`; grunts receive it (`ReceivePanic`) and `ApplyPanicVariance` (grunt tick step 2) compresses their formation offset (with `GetWaveMomentum`, B8).
#### 4. INPUTS / OUTPUTS
Input: `PanicActive`, `PanicVarianceMultiplier`, `PanicScanSpeedMultiplier`, wave momentum. Output: panic broadcast, scattered grunt offsets.
#### 5. FLOW   @FLOW-BASE-PANIC
```
UpdatePanicBroadcast[4188] (SL, 300u, PANIC_MULT 2.0, scatter 200-400u) --> ReceivePanic[4205]
ApplyPanicVariance[4212] (grunt tick step2 [Logic:327])
```
#### 6. TECHNICAL REFERENCE
- Ranges: UpdatePanicBroadcast [4188-4203], ReceivePanic [4205-4210], ApplyPanicVariance [4212-4225].
- Constants: PANIC_MULT 2.0, PANIC_SCATTER_MIN 200.0, PANIC_SCATTER_MAX 400.0 [Base:360,361,362].
#### 7. WHERE TO FIX
Panic broadcast --> `UpdatePanicBroadcast` [4188-4203]. Scatter application --> `ApplyPanicVariance` [4212-4225].

### P4.15 (B15) Reload drift   @SYS-BASE-RELOAD      Primary file: KF2BotBase.uc
#### 1. PLAIN-ENGLISH SUMMARY
Reload-drift: when a bot starts reloading, the squad "drifts" it slightly to break line-of-sight; track reload state, broadcast/receive drift, anchor, reload-complete, and the is-reloading test.
#### 2. EXPLANATION
- `IsReloading()` [4229-4235] -- reloading predicate.
- `HandleReloadDrift()` [4237-4285] -- >=2 reloading, 0.75s, `RELOAD_DRIFT_DIST` (100u) drift.
- `ReceiveReloadDrift()` [4287-4309] -- receive the drift.
- `OnReloadDriftAnchor()` [4311-4316] -- drift anchor.
- `OnReloadComplete()` [4318-4322] -- reload complete.
- `TrackReloadState()` [4324-4333] -- track reload state (grunt tick step 2).
#### 3. LOGIC PIPELINE
`SLDecisionLoop` (B9) calls `HandleReloadDrift`; `TrackReloadState` (grunt tick step 2) tracks it. The grunt tick (L3 step 12) consumes `bReloadDriftMove`/`ReloadDriftLoc` as `MoveToX`.
#### 4. INPUTS / OUTPUTS
Input: `bWasReloading`, `ReloadDriftUntil`/`ReloadPullStamp`, `ReloadDriftLoc`/`ReloadDriftOffset`. Output: drift broadcast/receive, reload state.
#### 5. FLOW   @FLOW-BASE-RELOAD
```
HandleReloadDrift[4237] (>=2 reloading, 0.75s, 100u) --> ReceiveReloadDrift[4287]
TrackReloadState[4324] (grunt step2 [Logic:327])
OnReloadDriftAnchor[4311] | OnReloadComplete[4318] | IsReloading[4229]
?  grunt tick step12 [Logic:327] --> MoveToX(ReloadDriftLoc)
```
#### 6. TECHNICAL REFERENCE
- Ranges: IsReloading [4229-4235], HandleReloadDrift [4237-4285], ReceiveReloadDrift [4287-4309], OnReloadDriftAnchor [4311-4316], OnReloadComplete [4318-4322], TrackReloadState [4324-4333].
- Constants: RELOAD_DRIFT_DIST 100.0, RELOAD_DRIFT_LEASE 1.0 [Base:363,364].
#### 7. WHERE TO FIX
Drift broadcast --> `HandleReloadDrift` [4237-4285]. State tracking --> `TrackReloadState` [4324-4333].

### P4.16 (B16) Lieutenant human bounding   @SYS-BASE-LTBOUND      Primary file: KF2BotBase.uc
#### 1. PLAIN-EnGLISH SUMMARY
Lieutenant-level human bounding: start/begin Lt human bounding, and the Lt loop that bounds/protects each human in range via per-human wedge dispatch.
#### 2. EXPLANATION
- `StartLtHumanBounding()` [4337-4340] -- start Lt human bounding.
- `BeginLtHumanBounding()` [4342-4348] -- begin it.
- `LtHumanBoundLoop()` [4350-4415] -- per-human wedge dispatch via `mut.CachedHumans`; picks the 2 nearest SLs and sends `ReceiveWedgeOrder` (B17). Range `HUMAN_LT_RANGE_SQ` (2500000 = 1581u2), push dot `HUMAN_PUSH_DOT` 0.5, min speed `HUMAN_MIN_SPEED_SQ` 10000.0, interval `HUMAN_BOUND_INTERVAL` 1.5.
#### 3. LOGIC PIPELINE
The Lt (once armed by `ArmRankTimers`) runs `LtHumanBoundLoop`, which for each human in range selects the 2 nearest squad leaders and issues wedge orders (B17) to keep the humans covered.
#### 4. INPUTS / OUTPUTS
Input: `mut.CachedHumans`, SL positions, human range/speed. Output: per-human wedge orders (B17).
#### 5. FLOW   @FLOW-BASE-LTBOUND
```
StartLtHumanBounding[4337] --> BeginLtHumanBounding[4342]
LtHumanBoundLoop[4350] (per human in 1581u via mut.CachedHumans)
?  pick 2 nearest SLs --> ReceiveWedgeOrder [4417] (B17)
```
#### 6. TECHNICAL REFERENCE
- Ranges: StartLtHumanBounding [4337-4340], BeginLtHumanBounding [4342-4348], LtHumanBoundLoop [4350-4415].
- Constants: HUMAN_BOUND_INTERVAL 1.5, HUMAN_PUSH_DOT 0.5, HUMAN_MIN_SPEED_SQ 10000.0, HUMAN_LT_RANGE_SQ 2500000.0 [Base:365,366,367,368].
- Cross-file: wedge target in B17; `mut.CachedHumans`.
#### 7. WHERE TO FIX
Human bounding loop --> `LtHumanBoundLoop` [4350-4415]. Start/begin --> `StartLtHumanBounding` [4337-4340]/`BeginLtHumanBounding` [4342-4348].

### P4.17 (B17) Wedge   @SYS-BASE-WEDGE      Primary file: KF2BotBase.uc
#### 1. PLAIN-EnGLISH SUMMARY
The wedge (cover-flank) posture: receive a wedge order, update wedge mode, clear wedge, compute the wedge offset, and apply the wedge target.
#### 2. EXPLANATION
- `ReceiveWedgeOrder()` [4417-4434] -- receive a wedge order (from `LtHumanBoundLoop` B16).
- `UpdateWedgeMode()` [4436-4443] -- update wedge mode (SLDecisionLoop).
- `ClearWedge()` [4445-4460] -- clear wedge.
- `ComputeWedgeOffset()` [4462-4486] -- wedge offset (angles -60/-30/30/60, dist 150+50*slot, `WEDGE_REAR_OFFSET` 150, `WEDGE_LEASE` 2.5).
- `ApplyWedgeTarget()` [4488-4497] -- apply the wedge target (grunt tick step 13).
#### 3. LOGIC PIPELINE
`LtHumanBoundLoop` (B16) issues `ReceiveWedgeOrder`; the grunt tick (L3 step 13) applies the wedge via `ApplyWedgeTarget` + `ComputeWedgeOffset`. `UpdateWedgeMode` (SLDecisionLoop) maintains it; `ClearWedge` releases it.
#### 4. INPUTS / OUTPUTS
Input: wedge order, `bWedgeActive`/`WedgeHuman`/`WedgeExpireTime`, slot. Output: wedge target/offset, grunt movement.
#### 5. FLOW   @FLOW-BASE-WEDGE
```
ReceiveWedgeOrder[4417] (from LtHumanBoundLoop [4350])
UpdateWedgeMode[4436] (SLDecisionLoop [2627])
?  grunt tick step13 [Logic:327] --> ApplyWedgeTarget[4488] (ComputeWedgeOffset[4462])
ClearWedge[4445]
```
#### 6. TECHNICAL REFERENCE
- Ranges: ReceiveWedgeOrder [4417-4434], UpdateWedgeMode [4436-4443], ClearWedge [4445-4460], ComputeWedgeOffset [4462-4486], ApplyWedgeTarget [4488-4497].
- Constants: WEDGE_REAR_OFFSET 150.0, WEDGE_LEASE 2.5 [Base:369,370].
- Cross-file: issued by `LtHumanBoundLoop` [4350]; applied by grunt tick [Logic:327] step 13.
#### 7. WHERE TO FIX
Wedge order intake --> `ReceiveWedgeOrder` [4417-4434]. Offset/target --> `ComputeWedgeOffset` [4462-4486]/`ApplyWedgeTarget` [4488-4497]. Release --> `ClearWedge` [4445-4460].

### P4.18 (B18) Emote echo   @SYS-BASE-EMOTE      Primary file: KF2BotBase.uc
#### 1. PLAIN-ENGLISH SUMMARY
Squad emote echo: when a human (or mate) plays an emote, nearby bots have a chance to echo it after a cooldown; start/begin/check the echo timer, play the emote, and clear the flag.
#### 2. EXPLANATION
- `StartEmoteEchoTimer()` [4501-4504] -- arm the echo timer.
- `BeginEmoteEcho()` [4506-4509] -- begin the echo evaluation.
- `CheckEmoteEcho()` [4511-4543] -- within `EMOTE_RADIUS_SQ` (150u2), `EMOTE_CHANCE` 0.30 roll, `EMOTE_ROLL_COOLDOWN` 6.0s; plays `PickRandEmote` [Mut:2754] or `PlayBotEmote`.
- `PlayBotEmote()` [4545-4557] -- play a bot emote.
- `ClearEmoteFlag()` [4559-4562] -- clear the echo flag.
#### 3. LOGIC PIPELINE
Triggered by emote observation; the timer runs to `BeginEmoteEcho` --> `CheckEmoteEcho` (roll/radius/cool), which plays the emote. No hub priority involved.
#### 4. INPUTS / OUTPUTS
Input: emote flag/observed emote, `EMOTE_*` constants, nearby bots/humans. Output: played emote, cleared flag.
#### 5. FLOW   @FLOW-BASE-EMOTE
```
StartEmoteEchoTimer[4501] --> BeginEmoteEcho[4506]
CheckEmoteEcho[4511]
?  radius<=150u (EMOTE_RADIUS_SQ) && roll<0.30 && cooldown>=6.0s --> PlayBotEmote[4545] / PickRandEmote [Mut:2754]
ClearEmoteFlag[4559]
```
#### 6. TECHNICAL REFERENCE
- Ranges: StartEmoteEchoTimer [4501-4504], BeginEmoteEcho [4506-4509], CheckEmoteEcho [4511-4543], PlayBotEmote [4545-4557], ClearEmoteFlag [4559-4562].
- Constants: EMOTE_RADIUS_SQ 22500.0, EMOTE_CHANCE 0.30, EMOTE_ROLL_COOLDOWN 6.0 [Base:371,372,373].
- Cross-file: `PickRandEmote` [Mut:2754] (KF2BotsMut.uc [2754-2763]).
#### 7. WHERE TO FIX
Echo roll/conditions --> `CheckEmoteEcho` [4511-4543]. Play path --> `PlayBotEmote` [4545-4557].

### P4.19 (B19) Weapon & grenade management   @SYS-BASE-WEAPON      Primary file: KF2BotBase.uc
#### 1. PLAIN-ENGLISH SUMMARY
Weapon/range/reload/grenade management: reload decision, effective range (UU conversion) tests, weapon re-equip, grenade decision, throw, the SL grenade check + LOS phase, clear the grenade signal, and the master weapon-management entry.
#### 2. EXPLANATION
- `ShouldReload()` [3259-3270] -- reload decision.
- `GetWeaponEffectiveRangeUU()` [3276-3297] -- weapon effective range in UU.
- `IsInEffectiveRange()` [3299-3320] / `CloseToEffectiveRange()` [3322-3340] -- effective-range tests.
- `CheckWeaponReequip()` [3343-3375] -- re-equip check (SLDecisionLoop).
- `ShouldThrowGrenade()` [3378-3420] -- grenade decision (target scoring, `BestScore` -- see Appendix C: uninitialized `BestScore`).
- `TryThrowGrenade()` [3422-3454] -- throw the grenade.
- `SLGrenadeCheck()` [3456-3476] -- SL grenade check (SLDecisionLoop).
- `SLGrenadeLOSPhase()` [3478-3516] -- grenade LOS phase.
- `ClearGrenadeSignal()` [3518-3523] -- clear the grenade signal.
- `HandleWeaponManagement()` [3526-3562] -- master weapon management entry.
#### 3. LOGIC PIPELINE
`SLDecisionLoop` (B9) calls `CheckWeaponReequip` and `SLGrenadeCheck`. Range/reload tests shape combat posture (B3) and movement intent. `ShouldThrowGrenade`/`TryThrowGrenade` execute grenade throws; `ClearGrenadeSignal` releases the grenade signal.
#### 4. INPUTS / OUTPUTS
Input: weapon state, enemy distance, `BOTFM_*`, grenade inventory. Output: reload/re-equip decisions, range tests, grenade throw, weapon management.
#### 5. FLOW   @FLOW-BASE-WEAPON
```
HandleWeaponManagement[3526]
CheckWeaponReequip[3343] (SLDecisionLoop [2627])
ShouldReload[3259] | GetWeaponEffectiveRangeUU[3276] | IsInEffectiveRange[3299] | CloseToEffectiveRange[3322]
SLGrenadeCheck[3456] --> SLGrenadeLOSPhase[3478]
?  ShouldThrowGrenade[3378] --> TryThrowGrenade[3422]
ClearGrenadeSignal[3518]
```
#### 6. TECHNICAL REFERENCE
- Ranges: ShouldReload [3259-3270], GetWeaponEffectiveRangeUU [3276-3297], IsInEffectiveRange [3299-3320], CloseToEffectiveRange [3322-3340], CheckWeaponReequip [3343-3375], ShouldThrowGrenade [3378-3420], TryThrowGrenade [3422-3454], SLGrenadeCheck [3456-3476], SLGrenadeLOSPhase [3478-3516], ClearGrenadeSignal [3518-3523], HandleWeaponManagement [3526-3562].
- Constants: BOTFM_PRIMARY 0, BOTFM_RELOAD 2, BOTFM_BASH 3, BOTFM_GRENADE 4 [Base:292,293,294,295].
- Cross-file: firing in B3; hub P5 grenade intent (hub P5 in KF2Bot).
#### 7. WHERE TO FIX
Grenade decision --> `ShouldThrowGrenade` [3378-3420]/`SLGrenadeCheck` [3456-3476]. Range/reload --> `GetWeaponEffectiveRangeUU` [3276-3297]/`ShouldReload` [3259-3270]. Master entry --> `HandleWeaponManagement` [3526-3562].

### P4.20 (B20) Audit & watchdog   @SYS-BASE-AUDIT      Primary file: KF2BotBase.uc
#### 1. PLAIN-ENGLISH SUMMARY
The audit/watchdog layer that detects stalls and force-reissues: rate-limited audit entry, state-entry/exit auditing, goal logging, and the follow-order anchor override.
#### 2. EXPLANATION
- `AuditRateLimit()` [2499-2524] -- rate-limited audit entry (`AUDIT_INTENT_TIMEOUT` 10s, `AUDIT_HUB_TIMEOUT` 20s, `AUDIT_IDLE_STUCK_DELTA` 50.0, `AUDIT_ATTACH_RADIUS` 3000.0, `AUDIT_WD_PERIOD` 1.5, `AUDIT_WD_STEP_COOLDOWN` 5.0).
- `AuditStateEntry()` [2557-2566] -- log a state entry.
- `AuditStateExit()` [2568-2586] -- log a state exit (GrenadeTarget state is missing its exit call -- see Appendix C).
- `AuditGoalLog()` [2591-2609] -- log a goal change.
- `FollowGetOrderAnchor()` [2530-2550] -- override of the follow-order anchor ([Nav:232-236]); supplies the HCA anchor for following.
#### 3. LOGIC PIPELINE
State transitions call `AuditStateEntry`/`AuditStateExit`; goal changes call `AuditGoalLog`. `AuditRateLimit` gates reissue/watchdog actions so they don't spam. `FollowGetOrderAnchor` overrides the base follow anchor ([Nav:232-236]) to point at the HCA intent.
#### 4. INPUTS / OUTPUTS
Input: state/goal transitions, `AUDIT_*` constants, follow anchor. Output: audit log lines, rate-limited reissue, follow anchor.
#### 5. FLOW   @FLOW-BASE-AUDIT
```
state entry --> AuditStateEntry[2557]
state exit  --> AuditStateExit[2568]
goal change --> AuditGoalLog[2591]
AuditRateLimit[2499] (intent 10s / hub 20s / idle 50 / attach 3000u / wd 1.5s / step 5s)
FollowGetOrderAnchor[2530] (overrides [Nav:232-236])
```
#### 6. TECHNICAL REFERENCE
- Ranges: AuditRateLimit [2499-2524], FollowGetOrderAnchor [2530-2550], AuditStateEntry [2557-2566], AuditStateExit [2568-2586], AuditGoalLog [2591-2609].
- Constants: AUDIT_INTENT_TIMEOUT 10.0, AUDIT_HUB_TIMEOUT 20.0, AUDIT_IDLE_STUCK_DELTA 50.0, AUDIT_ATTACH_RADIUS 3000.0, AUDIT_WD_PERIOD 1.5, AUDIT_WD_STEP_COOLDOWN 5.0 [Base:103,104,105,106,107,108].
- Cross-file: overrides `FollowGetOrderAnchor` [Nav:232-236]; `EchelonLog` [2484-2495] (B1).
#### 7. WHERE TO FIX
Rate limiting --> `AuditRateLimit` [2499-2524]. State/goal logging --> `AuditStateEntry` [2557-2566]/`AuditStateExit` [2568-2586]/`AuditGoalLog` [2591-2609]. Follow anchor --> `FollowGetOrderAnchor` [2530-2550].

### P4.21 (B21) Heal capability & misc   @SYS-BASE-HEALQ      Primary file: KF2BotBase.uc
#### 1. PLAIN-ENGLISH SUMMARY
Heal capability queries and small misc predicates: can-heal-others, heal-locked-out, should-abort-retreat, is-bot-alive, and the enemy-changed hook.
#### 2. EXPLANATION
- `CanHealOthers()` [2425-2428] -- whether the bot can heal others (medic/medic-gun).
- `IsHealLockedOut()` [2430-2433] -- whether healing is locked out.
- `ShouldAbortRetreat()` [2435-2438] -- retreat-abort predicate.
- `IsBotAlive()` [2420-2423] -- alive predicate.
- `EnemyChanged()` [1035-1038] -- enemy-changed hook.
#### 3. LOGIC PIPELINE
Heal capability queries feed the hub P6 heal intent and the Logic healing subsystem (L1). `ShouldAbortRetreat` gates retreat persistence. `EnemyChanged` fires on enemy swap.
#### 4. INPUTS / OUTPUTS
Input: bot inventory/role, `Enemy`, retreat state. Output: heal capability, retreat-abort decision, enemy-changed hook.
#### 5. FLOW   @FLOW-BASE-HEALQ
```
CanHealOthers[2425] | IsHealLockedOut[2430]  --> hub P6 heal intent [Bot:57]
ShouldAbortRetreat[2435] | IsBotAlive[2420]
EnemyChanged[1035]
```
#### 6. TECHNICAL REFERENCE
- Ranges: IsBotAlive [2420-2423], CanHealOthers [2425-2428], IsHealLockedOut [2430-2433], ShouldAbortRetreat [2435-2438], EnemyChanged [1035-1038].
- Cross-file: hub P6 [Bot:57]; Logic healing [Logic:4-115] (L1); `RestartBot` [Mut:2433] (KF2BotsMut.uc [2433-2533]).
#### 7. WHERE TO FIX
Heal capability --> `CanHealOthers` [2425-2428]/`IsHealLockedOut` [2430-2433]. Retreat abort --> `ShouldAbortRetreat` [2435-2438].

# PART 4 (L) -- KF2BotLogic.uc Subsystems (L1--L6, P4.22--P4.27)

Primary file: KF2BotLogic.uc (1377 lines, `ffc4906a`). Class `KF2BotLogic` extends `KF2BotBase` [1], `hidecategories(Navigation)` [2]. The "Logic" layer of the HCA: healing, grunt-restricted tick, idle watchdog, overwatch phase, follower exit gate, death sequence, retreat-move pick, squad-tether evaluation, CQB formation probe, pillar-of-salt stuck tracking, and the timer callbacks armed in `KF2BotBase.PreBeginPlay`. **No states of its own** (states are in KF2Bot.uc), **no class vars of its own** (all state lives in KF2BotBase), **no `defaultproperties` block**. Citations `[123]` = KF2BotLogic.uc line; `[Base:123]` = KF2BotBase.uc; `[Bot:123]` = KF2Bot.uc; `[Mut:123]` = KF2BotsMut.uc; `[Nav:123]` = KF2BotsFollowNavBase.uc.

---

### P4.22 (L1) Healing subsystem   @SYS-LOGIC-HEAL      Primary file: KF2BotLogic.uc
#### 1. PLAIN-ENGLISH SUMMARY
The medic brain. Decides whether the bot should heal a teammate with a syringe (close, trader round), with a ranged medic dart, or heal itself -- scores every candidate victim, applies a VIP triage bias, and paces heals so the whole squad does not drain syringes in one frame.
#### 2. EXPLANATION
- `CheckShouldHealMate()` [4-115] `final` -- trader-round **syringe** heal. Gate: `KFGRI.bTraderIsOpen`; `HealRetryAfter` backoff gate. Picks a `MedicGun` (`KFWeap_HealerBase` with `HasAmmo(0)`) from `KFInvManager.InventoryActors`. Victim scan: `WorldInfo.AllPawns(KFPawn_Human, mut.HealCylinderRadius)` -- team match, `Pct <= HEAL_MAX_NEED_PCT` (80), `TargetLowHealth` [Base:727], cylinder `DHoriz <= mut.HealCylinderRadius` and `DVert <= mut.HealCylinderHeight`, `ActorReachable`, optional `FastTrace` (Loophole gate `mut.bEnableFastTraceHealing`). VIP triage bias (Loophole 2 fix): if `P == mut.VIPController.Pawn && Pct < VIP_TRIAGE_GATE_PCT` (50), `EffectivePct = FMax(Pct - VIP_TRIAGE_BONUS_PCT (15), 0)`. Sets `PendingHeal = Best`.
- `CheckMedicGunHeal()` [117-200] `final` -- ranged medic **dart**. `RangeMedicGun = KFWeap_MedicBase(Pawn.Weapon)`, `HasAmmo(1)`; scan `AllPawns` at 1800.0u; 25s per-target cooldown via `mut.IsRangedHealTargetOnCooldown(P)`; same `Pct`/VIP-bias logic; no cylinder gate.
- `CheckShouldSelfHeal()` [202-259] `final` -- gate `KPawn.Health < (HEAL_MAX_NEED_PCT/100)*HealthMax`; `SyringeRechargeEnd` (15s mechanical recharge) and `HealPacingEnd` (30s behavioral pacing) are **bypassed** when health < 50% or trader open; returns `MedicGun != none` after inventory scan.
- `CanAffordHeal()` [521-528] -- Type 0 (syringe): `MedicGun.AmmoCount[0] >= 100.0`; Type 1 (ranged): `RangeMedicGun.AmmoCount[1] >= 50.0`. Source comment: gate and state must agree on the same threshold to prevent the "1-99 silent-skip livelock".
- `HealFail()` [532-537] -- `FailStreak++`; `HealRetryAfter = now + FMin(4.0*FailStreak, 20.0)`; `PendingHeal = none`. Every non-success exit routes here (bounded backoff).
- `HealSuccess()` [541-548] -- the **only** writer of the pacing stamps: `FailStreak = 0`; `SyringeRechargeEnd = now + 15.0`; `HealPacingEnd = now + (20.0 + FRand()*10.0)` (desync across bots).
- `VerifyWeapon()` [553-567] -- global 1.5s safety net after any heal-state exit; if state is not `HealingSelf`/`HealOther`/`HealRanged` and `KFWeap_HealerBase(Pawn.Weapon) != none` --> `Pawn.InvManager.SwitchToBestWeapon(true)`. Replaces the dead `HealTimeOut` timer.
- `HealTimeOut()` [569-572] -- legacy stub: `PickCombatStyle()` [Base:2123].
#### 3. LOGIC PIPELINE
Hub P3 `CheckShouldSelfHeal()` --> `HealingSelf` [Bot:1192]; hub P6 triage (2.0s `TRIAGE_INTERVAL`) --> `CheckMedicGunHeal()` --> `HealRanged` [Bot:1415] and `CheckShouldHealMate()` --> `HealOther` [Bot:1295]. Each heal state calls `CanAffordHeal`/`VerifyWeapon` on entry, and `HealSuccess`/`HealFail` on completion. The pacing stamps written by `HealSuccess` gate the next `CheckShouldSelfHeal`.
#### 4. INPUTS / OUTPUTS
Input: `mut.KF.MyKFGRI` (bTraderIsOpen, WaveNum), `mut.VIPController`, `mut.HealCylinderRadius`/`Height`, `mut.bEnableFastTraceHealing`, `mut.IsRangedHealTargetOnCooldown`, `KPawn` health/inventory. Output: `PendingHeal` (victim), pacing stamps (`SyringeRechargeEnd`, `HealPacingEnd`, `HealRetryAfter`, `FailStreak`), and state transitions to `HealingSelf`/`HealOther`/`HealRanged`.
#### 5. FLOW   @FLOW-LOGIC-HEAL
```
HUB P3  CheckShouldSelfHeal [202] --> HealingSelf [Bot:1192]
HUB P6  CheckMedicGunHeal [117]   --> HealRanged  [Bot:1415]
        CheckShouldHealMate [4]   --> HealOther   [Bot:1295]
?  gate: trader open / health<80% / recharge+pacing
?  scan: AllPawns human, team match, Pct<=80, cylinder, reachable
?  VIP bias: Pct<50 -> EffectivePct=max(Pct-15,0)
?  entry: CanAffordHeal [521] (syr>=100 / dart>=50), VerifyWeapon [553]
?  exit:  HealSuccess [541] (write stamps) | HealFail [532] (backoff)
```
#### 6. TECHNICAL REFERENCE
- Ranges: CheckShouldHealMate [4-115], CheckMedicGunHeal [117-200], CheckShouldSelfHeal [202-259], CanAffordHeal [521-528], HealFail [532-537], HealSuccess [541-548], VerifyWeapon [553-567], HealTimeOut [569-572].
- Constants: HEAL_MAX_NEED_PCT 80.0, HEAL_MIN_NEED_PCT 60.0, VIP_TRIAGE_GATE_PCT 50.0, VIP_TRIAGE_BONUS_PCT 15.0, TRIAGE_INTERVAL 2.0 [Base:76,77,78,84,85].
- Cross-file: heal states in KF2Bot.uc [Bot:1192-1537]; `mut` heal-cooldown bookkeeping in KF2BotsMut.uc (M10).
#### 7. WHERE TO FIX
Triage bias / VIP gate --> `CheckShouldHealMate` [4-115] and `CheckMedicGunHeal` [117-200]. Pacing / backoff --> `HealSuccess` [541-548] (only stamp writer) and `HealFail` [532-537]. Ammo threshold that must match the state --> `CanAffordHeal` [521-528]. Weapon-restore safety net --> `VerifyWeapon` [553-567].

---

### P4.23 (L2) Watchdogs & cadence timers   @SYS-LOGIC-WATCHDOG      Primary file: KF2BotLogic.uc
#### 1. PLAIN-ENGLISH SUMMARY
The safety nets. A per-bot, staggered idle watchdog escalates a stuck bot through reissue-order --> reassign-to-nearest-leader --> forced hub recovery; a promotion-gap timer self-promotes an orphaned grunt; a grunt decision timer drives the engage flag; and two cadence timers (overwatch phase, captain path) run the Echelon rank loops.
#### 2. EXPLANATION
- `GruntDecisionTimer()` [595-629] -- 1.5s cadence (armed [Base:452]), GRUNT only. `VisibleCollidingActors(KFPawn_Monster, 800.0u)` for best-alive distance; `bEngageActive = (BestDist < 800.0)`. Primary driver of the grunt engage flag.
- `IdleWatchdogTimer()` [639-643] -- self-rearms `SetTimer(AUDIT_WD_PERIOD=1.5, false, 'IdleWatchdogTimer')`, then calls `IdleWatchdog()`.
- `IdleWatchdog()` [645-805] -- AUDIT_3B Step 6, per-bot staggered watchdog. Signals: `IterSinceIntent = now - WdLastMoveIntentTime`, `IterSinceHub = now - WdLastHubContactTime`. **Legit-state whitelist**: HealingSelf, HealOther, HealRanged, BreakLose, VictoryDance, Camp, GoShopping, FollowingLeader, FollowingLeaderBasic, DoObjective, Hunting; plus FightEnemy with a live `Enemy` (aiming/reloading is legit stationary). Idle = NOT whitelisted AND intent stale > `AUDIT_INTENT_TIMEOUT` (10) AND hub stale > `AUDIT_HUB_TIMEOUT` (20) -- **AND, not OR** (OR would flag every solo hunter). Displacement: `IterStuckDelta = VSize(Pawn.Location - WdIdleStartLoc)`; `bStuck` if < `AUDIT_IDLE_STUCK_DELTA` (50u). Progress: `mut.GetBotObjective(KF2Bot(self))` goal D2 shrinking. Escalation ladder, 5.0s between steps (`AUDIT_WD_STEP_COOLDOWN`): Step 1 `mut.HasSquadGoal` --> `mut.ReissueSquadOrder`; Step 2 if SL invalid --> `mut.FindNearestActiveLeader(AUDIT_ATTACH_RADIUS)` --> `mut.ReassignBotToGroup` (0-based fireteam index; `GroupID` is 1-based) + `FollowStart(ctrl)`; Step 3 `GotoState('PickNextMove')` terminal recovery (native pick-move handles self-promotion + P8.5 hunting). Each successful step resets `bWdEscalating`/`WdEscStep`/`WdLastStepTime`/`WdProgressGoalD2`.
- `PromotionGapTimer()` [508-516] -- 10s self-promotion failsafe: GRUNT + SL permanently lost --> `SetBotRank(SQUAD_LEADER)` [Base:3223] + `PickCombatStyle()` [Base:2123] (must enter a valid combat state because the restricted `CheckGrabbed` tick no longer drives SQUAD_LEADER movement).
- `CaptainPathTimer()` [809-816] -- 2.0s (armed [Base:448]). Guard `BotRank != LIEUTENANT --> return`. **Placeholder**: `EchelonLog("CaptainPathTimer: path re-evaluation")` only; comment "Full implementation will be added in a later batch". (Name says *Captain*, guard says *Lieutenant* -- the comment block reads "Lieutenant Path Timer"; see Appendix C.)
- `ProcessOverwatchPhase()` [821-832] -- 5.0s (armed [Base:444]), CAPTAIN only. Toggles `bOverwatchPhase` when `now > EngageExpireTime`, re-stamps `EngageExpireTime = now + 5.0`; `EchelonLog` HOLD/ADVANCE.
#### 3. LOGIC PIPELINE
`KF2BotBase.PreBeginPlay` arms `IdleWatchdogTimer` [639] (self-rearming 1.5s), `ProcessOverwatchPhase` [821] (5.0s), `CaptainPathTimer` [809] (2.0s), and `GruntDecisionTimer` [595] (1.5s). `IdleWatchdog` is the recovery sink for every other subsystem: when it fires Step 3 it funnels the bot back into the hub [Bot:17]. `PromotionGapTimer` is armed from `UpdateGruntOffset` step 5 [327] when the SL is lost.
#### 4. INPUTS / OUTPUTS
Input: `WdLastMoveIntentTime`, `WdLastHubContactTime`, `WdIdleStartLoc`, `WdProgressGoalD2`, `bWdEscalating`/`WdEscStep`/`WdLastStepTime`, `GroupID`, `mut` (HasSquadGoal, ReissueSquadOrder, FindNearestActiveLeader, ReassignBotToGroup, GetBotObjective). Output: escalation state resets, `BotRank` promotion, `FollowStart`/`GotoState('PickNextMove')`, `bOverwatchPhase`, `bEngageActive`.
#### 5. FLOW   @FLOW-LOGIC-WATCHDOG
```
IdleWatchdogTimer [639] (1.5s, self-rearm) --> IdleWatchdog [645]
?  whitelist? (heal/break/victory/camp/shop/follow/objective/hunt,
|            FightEnemy+liveEnemy) -> skip
?  idle = !whitelist AND intent>10 AND hub>20 (AND-gate)
?  bStuck = VSize(loc - WdIdleStartLoc) < 50u
?  step ladder (5.0s apart):
|   1 ReissueSquadOrder (HasSquadGoal)
|   2 SL invalid -> FindNearestActiveLeader -> ReassignBotToGroup + FollowStart
|   3 GotoState('PickNextMove') [Bot:17]
GruntDecisionTimer [595] (1.5s) -> bEngageActive = bestDist<800
ProcessOverwatchPhase [821] (5.0s, CAPTAIN) -> toggle bOverwatchPhase
CaptainPathTimer [809] (2.0s, LIEUTENANT) -> log-only placeholder
PromotionGapTimer [508] (10s) -> SetBotRank(SQUAD_LEADER)+PickCombatStyle
```
#### 6. TECHNICAL REFERENCE
- Ranges: GruntDecisionTimer [595-629], IdleWatchdogTimer [639-643], IdleWatchdog [645-805], PromotionGapTimer [508-516], CaptainPathTimer [809-816], ProcessOverwatchPhase [821-832].
- Constants: AUDIT_WD_PERIOD 1.5, AUDIT_INTENT_TIMEOUT 10.0, AUDIT_HUB_TIMEOUT 20.0, AUDIT_IDLE_STUCK_DELTA 50.0, AUDIT_WD_STEP_COOLDOWN 5.0, AUDIT_ATTACH_RADIUS 3000 [Base:103,104,105,106,107,108].
- Cross-file: watchdog arms [Base:437-452]; escalation recovery target hub [Bot:17]; orphan-grunt promotion armed from `UpdateGruntOffset` [508] (L3).
#### 7. WHERE TO FIX
Whitelist / idle AND-gate / escalation ladder --> `IdleWatchdog` [645-805]. Orphan self-promotion --> `PromotionGapTimer` [508-516]. Engage flag cadence --> `GruntDecisionTimer` [595-629]. Captain/Lt path placeholder --> `CaptainPathTimer` [809-816]. Overwatch cadence --> `ProcessOverwatchPhase` [821-832].

---

### P4.24 (L3) Grunt restricted tick   @SYS-LOGIC-GRUNTMOVE      Primary file: KF2BotLogic.uc
#### 1. PLAIN-ENGLISH SUMMARY
The grunt's per-tick body. Instead of the full hub, a grunt runs a short, ordered decision chain that resolves one movement intent (or combat) each tick: grab --> break, panic/reload upkeep, line-focus, SL-validity self-promotion, overwatch move, sector watch, CQB, rescue, cover crouch, reload-drift, wedge, or formation offset with Z-step and wall-safety.
#### 2. EXPLANATION
- `CheckGrabbed()` [304-318] (override) -- `IsDoingSpecialMove(31)` (grapple) + `InteractionPawn` --> `GotoState('BreakLose')`. Else if `BotRank == GRUNT` --> `UpdateGruntOffset()`.
- `UpdateGruntOffset()` [327-465] -- the grunt decision chain, in order: (1) grab --> BreakLose (return); (2) `ApplyPanicVariance()` [Base:4212] + `TrackReloadState()` [Base:4324]; (3) `SyncLineFocus()` [Base:2893] --> return if in line formation; (4) `ApplySquadCrouchHold()` [Base:3052]; (5) SL null guard: `SquadLeader`/`Pawn` dead --> `MoveToX(LastValidSquadLeaderPos)` (or VIP pawn if no valid pos), arm 10.0s `PromotionGapTimer` (Edge Case #2), return; (6) SL valid: `LastValidSquadLeaderPos` bookkeeping, cancel `bPromotionGapTimerActive` (Bug 2 fix); (7) `bOverwatchMoving` --> `UpdateOverwatchMovement(OverwatchMoveTarget)` [Base:3778] --> `MoveToX`, return; (8) `CurrentOrder == 'CMD_HoldArea' && Enemy == none` --> `UpdateSectorWatch()` [Base:3873], return; (9) `HandleCQBProximity()` [Base:3919]; (10) `RescueUntil > now` --> `MoveToX(RescueLoc)`, return; (11) `UpdateCoverCrouch()` [Base:4043]; (12) `bReloadDriftMove && ReloadDriftUntil > now` --> `MoveToX(ReloadDriftLoc)`, return; (13) `SquadLeader.bWedgeActive` --> `GruntTarget = SL loc`, `ApplyWedgeTarget` [Base:4488], `ApplyZStep`, `MoveToX`, return; (14) formation: `GruntTarget = SL loc + ComputeSlotOffset()` [Base:2842], panic scale `sc = PanicVarianceMultiplier / GetWaveMomentum()` [Base:4566] compresses X/Y, breathing offset `bOff = (Sin(BreathingPhase)*10, Cos(BreathingPhase)*10, 0)`, `ApplyZStep`, wall safety `!ValidateOffsetTarget(GruntTarget)` [Base:2955] --> `GruntTarget = SL loc` (prevents 2-bot limbo lockup), `MoveToX(GruntTarget)`.
- `ApplyZStep()` [476-496] -- `|DZ| > 300` --> snap target Z to current floor Z (cross-floor guard: native pathing cannot reach a different floor Z); `|DZ| > 200` --> 50u step; `|T.Z - Pawn.Z| <= 50` --> snap (stability band, kills micro-jitter / wall-bounce loop near doors/stairs).
- `RequestReroute()` [499-502] -- `LastValidSquadLeaderPos = SquadLeader.Pawn.Location` (Tier 2 stub).
- `ConsumePathToken()` [577-590] -- max 10 pathfinding calls/sec across all bots (budget counter `PathTokensUsed`/`PathTokenResetTime`, reset every 1.0s).
#### 3. LOGIC PIPELINE
`CheckGrabbed` is the entry for the grunt tick (driven each tick). It routes grapple to `BreakLose` [Bot:954] or into `UpdateGruntOffset`, which resolves a single `MoveToX`/combat intent. Formation offsets come from `ComputeSlotOffset` [Base:2842]; wall safety from `ValidateOffsetTarget` [Base:2955]. Path calls are metered by `ConsumePathToken`.
#### 4. INPUTS / OUTPUTS
Input: `SquadLeader`/`Pawn` state, `LastValidSquadLeaderPos`, `bOverwatchMoving`, `CurrentOrder`, `Enemy`, `RescueUntil`/`RescueLoc`, `bReloadDriftMove`/`ReloadDriftLoc`, `bWedgeActive`, `PanicVarianceMultiplier`, `BreathingPhase`, `mut.VIPController`. Output: one `MoveToX`/`MoveTowardX`/`GotoState('BreakLose')` per tick, plus `PromotionGapTimer` arming and `LastValidSquadLeaderPos` updates.
#### 5. FLOW   @FLOW-LOGIC-GRUNTMOVE
```
CheckGrabbed [304]
?  grapple (SM 31)+InteractionPawn --> GotoState('BreakLose') [Bot:954]
?  else GRUNT --> UpdateGruntOffset [327]
|  1 grab --> BreakLose
|  2 ApplyPanicVariance, TrackReloadState
|  3 SyncLineFocus [Base:2893] -> return (line form)
|  4 ApplySquadCrouchHold [Base:3052]
|  5 SL dead --> MoveToX(LastValidSquadLeaderPos|VIP), arm PromotionGapTimer [508]
|  6 SL valid: bookkeep pos, cancel bPromotionGapTimerActive
|  7 bOverwatchMoving --> UpdateOverwatchMovement --> MoveToX
|  8 CMD_HoldArea && !Enemy --> UpdateSectorWatch
|  9 HandleCQBProximity [Base:3919]
| 10 RescueUntil>now --> MoveToX(RescueLoc)
| 11 UpdateCoverCrouch [Base:4043]
| 12 reloadDrift --> MoveToX(ReloadDriftLoc)
| 13 SL.bWedgeActive --> ApplyWedgeTarget, ApplyZStep, MoveToX
| 14 formation: SL loc + ComputeSlotOffset; panic scale; breathing;
|     ApplyZStep; !ValidateOffsetTarget --> SL loc; MoveToX
ApplyZStep [476]: DZ>300 snap; DZ>200 50u step; |dZ|<=50 snap
ConsumePathToken [577]: <=10 path/s
```
#### 6. TECHNICAL REFERENCE
- Ranges: CheckGrabbed [304-318], UpdateGruntOffset [327-465], ApplyZStep [476-496], RequestReroute [499-502], ConsumePathToken [577-590].
- Constants: promotion-gap 10.0s [508]; Z-step bands 300/200/50 [476-496]; path budget 10/s [577].
- Cross-file: every offset/wall/crouch/wedge target is a `KF2BotBase` call (B10/B12/B17); the state reached (`BreakLose`) is in KF2Bot.uc [Bot:954].
#### 7. WHERE TO FIX
Chain order / precedence --> `UpdateGruntOffset` [327-465]. Cross-floor / micro-jitter --> `ApplyZStep` [476-496]. Orphan self-promotion arming --> step 5 of `UpdateGruntOffset` + `PromotionGapTimer` [508-516]. Path budget --> `ConsumePathToken` [577-590].

---

### P4.25 (L4) Move evaluation & squad tether   @SYS-LOGIC-MOVEVAL      Primary file: KF2BotLogic.uc
#### 1. PLAIN-ENGLISH SUMMARY
The movement-intent evaluators. Leader/follower move evaluation, squad-tether resolution, anchor validity, goal pursuit, CQB formation probe, pillar-of-salt stuck tracking, camp entry, stuck reset, and the follower exit gate that lets a FollowingLeader bot leave its leader for trader or objective.
#### 2. EXPLANATION
- `EvaluateLeaderMove()` [1205-1211] -- leader-side move evaluation (thin; delegates to goal pursuit).
- `EvaluateFollowerMove()` [1213-1267] -- follower-side move evaluation; Loophole 4 **hold-position** path and a Plan-B `FollowStart` hook to re-attach to the leader when the follower loses track.
- `EvaluateSquadTether()` [1169-1194] -- resolves the squad tether (hub P8 [Bot:232]); returns a move intent so the follower stays within tether of the leader/anchor.
- `IsAnchorValid()` [1196-1203] -- validates a move/hold anchor before use.
- `MoveTowardGoal()` [1269-1286] -- drives pursuit of the current goal/anchor.
- `UpdateCQBFormation()` [1288-1308] -- CQB formation probe (single-file spacing in close quarters).
- `UpdatePillarOfSaltTracking()` [1310-1363] -- pillar-of-salt stuck tracking; Loophole 5 ghost-door GC (drops a stuck tracking reference when the door is gone).
- `ExecuteCampState()` [1365-1371] -- `GotoState('Camp')` [1369] (hub P10 [Bot:251] and regroup leader-hold [Bot:157]).
- `ResetStuckState()` [1373-1377] -- clears the stuck trackers.
- `FollowCheckExit()` [839-873] -- `function bool` override of the FollowNavBase hook [Nav:308-311] (runs from the base's `FollowWatchdog` each pass). AUDIT 2nd-priority(b) follower-limbo breaker: (1) trader open (`KFGRI.bTraderIsOpen && OpenedTrader != none`) and `NextShoppingTime < now` --> `FollowExitState = 'GoShopping'`, `bFollowExit...`; other exit conditions follow (objective / leash).
#### 3. LOGIC PIPELINE
Hub P8 calls `EvaluateSquadTether` [Bot:232] and, through `PickCombatStyle`/move paths, `EvaluateFollowerMove`/`EvaluateLeaderMove`. `FollowCheckExit` is polled by the FollowNav watchdog; when it sets a `FollowExitState` the follow layer hands control back to the hub so the bot can enter GoShopping/objective. `ExecuteCampState` is the hub's camp sink.
#### 4. INPUTS / OUTPUTS
Input: `Enemy`, goal/anchor (`OrderAnchor`, `AssignedAnchor`), `SquadLeader`/`SquadMembers`, `mut` (objective phase, slot location), `KFGRI.bTraderIsOpen`/`OpenedTrader`, `NextShoppingTime`. Output: move intents (`MoveToX`/`MoveTowardX`/`FollowStart`), `FollowExitState`, state transitions (`Camp`, `GoShopping`).
#### 5. FLOW   @FLOW-LOGIC-MOVEVAL
```
HUB P8  EvaluateSquadTether [1169] --> move intent (stay tethered)
        EvaluateLeaderMove [1205] | EvaluateFollowerMove [1213]
?  follower: hold-position (Loophole 4) / Plan-B FollowStart
FollowCheckExit [839] (FollowNav watchdog poll)
?  trader open && NextShoppingTime --> FollowExitState='GoShopping'
?  (objective / leash exits)
MoveTowardGoal [1269] --> pursue goal/anchor
UpdateCQBFormation [1288] | UpdatePillarOfSaltTracking [1310] (ghost-door GC)
ExecuteCampState [1365] --> GotoState('Camp') [1369]
IsAnchorValid [1196] | ResetStuckState [1373]
```
#### 6. TECHNICAL REFERENCE
- Ranges: EvaluateLeaderMove [1205-1211], EvaluateFollowerMove [1213-1267], EvaluateSquadTether [1169-1194], IsAnchorValid [1196-1203], MoveTowardGoal [1269-1286], UpdateCQBFormation [1288-1308], UpdatePillarOfSaltTracking [1310-1363], ExecuteCampState [1365-1371], ResetStuckState [1373-1377], FollowCheckExit [839-873].
- Cross-file: hub P8 [Bot:232], hub P10 [Bot:251], FollowNavBase hook [Nav:308-311]; trader flags from `mut.KF.MyKFGRI`.
#### 7. WHERE TO FIX
Follower tether / hold-position --> `EvaluateFollowerMove` [1213-1267] + `EvaluateSquadTether` [1169-1194]. Leaving-follow for trader/objective --> `FollowCheckExit` [839-873]. Ghost-door stuck --> `UpdatePillarOfSaltTracking` [1310-1363]. Camp entry --> `ExecuteCampState` [1365-1371].

---

### P4.26 (L5) Death & damage   @SYS-LOGIC-DEATH      Primary file: KF2BotLogic.uc
#### 1. PLAIN-ENGLISH SUMMARY
Death and kill handling. Aborts in-flight latent moves on death, clears rank timers, routes to the `Dead` state; runs the player-died sequence events; and, on `NotifyKilled`, triggers the boss-kill victory dance.
#### 2. EXPLANATION
- `PawnDied()` [875-914] -- aborts latents, `ClearRankTimers()` [Base:3066], `GotoState('Dead')` [912] (--> [Bot:1913]).
- `ActivatePlayerDiedSequenceEvents()` [916-952] -- fires the replicated died-sequence events.
- `NotifyKilled()` [1156-1167] -- boss kill --> `bBossKillVictory = true` + `VictoryDance` [1163] (--> [Bot:1972]).
- `ReplicatedEvent()` [1057-1082] -- `'RagdollMove'` --> `IsRagdolled` [1063] (--> [Bot:1948]); `'EndRagdollMove'` --> terminal? `VictoryDance` [1070] : `PickNextMove` [1074].
- `FinishObjective()` [1084-1092] -- objective-completion bookkeeping (called from `DoObjective` [Bot:485]).
#### 3. LOGIC PIPELINE
Death: `PawnDied` --> clear timers --> `Dead` [Bot:1913]. Ragdoll: `ReplicatedEvent` (`'RagdollMove'`/`'EndRagdollMove'`) bridges ragdoll into `IsRagdolled` or back to the hub/victory. Kill credit: `NotifyKilled` sets the boss-kill victory flag and dances. Objective: `FinishObjective` (from `DoObjective`) closes the goal before the next hub pass.
#### 4. INPUTS / OUTPUTS
Input: death/ragdoll replicated events, `bBossKillVictory`, `Enemy` (boss), objective state. Output: `GotoState('Dead'/'IsRagdolled'/'VictoryDance'/'PickNextMove')`, `ClearRankTimers`, `bBossKillVictory = true`.
#### 5. FLOW   @FLOW-LOGIC-DEATH
```
PawnDied [875] --> abort latents, ClearRankTimers [Base:3066], GotoState('Dead') [912] [Bot:1913]
ActivatePlayerDiedSequenceEvents [916] --> replicated died events
NotifyKilled [1156] --> boss: bBossKillVictory=true, VictoryDance [1163] [Bot:1972]
ReplicatedEvent [1057]
?  'RagdollMove'      --> IsRagdolled [1063] [Bot:1948]
?  'EndRagdollMove'  --> terminal ? VictoryDance [1070] : PickNextMove [1074]
FinishObjective [1084] (from DoObjective [Bot:485]) --> close goal
```
#### 6. TECHNICAL REFERENCE
- Ranges: PawnDied [875-914], ActivatePlayerDiedSequenceEvents [916-952], NotifyKilled [1156-1167], ReplicatedEvent [1057-1082], FinishObjective [1084-1092].
- Cross-file: target states in KF2Bot.uc -- Dead [Bot:1913], IsRagdolled [Bot:1948], VictoryDance [Bot:1972], hub [Bot:17]; `ClearRankTimers` [Base:3066].
#### 7. WHERE TO FIX
Death abort / rank-timer clear --> `PawnDied` [875-914]. Ragdoll bridging --> `ReplicatedEvent` [1057-1082]. Boss-kill victory flag --> `NotifyKilled` [1156-1167]. Objective close --> `FinishObjective` [1084-1092].

---

### P4.27 (L6) Utility & move pick   @SYS-LOGIC-UTIL      Primary file: KF2BotLogic.uc
#### 1. PLAIN-ENGLISH SUMMARY
Free-standing helpers: grenade-throw heuristic, collectable/factory search, near-point sampling, retreat-move pick, jump-apex and AI-info plumbing.
#### 2. EXPLANATION
- `ShouldNadeEnemies()` [261-302] -- grenade heuristic. **Known decompile anomaly**: `local float BestScore` is referenced but not initialized (score predicate `(Score > 300.0) && (Best == none) || Score > BestScore`); see Appendix C.
- `FindCollectable()` [1004-1043] -- `KFPickupFactory` search at 800u; armor-only gate; `LastFactory` latch.
- `GetPointNear()` [1094-1154] -- 25-iteration near-point sampler for a usable landing point.
- `PickRetreatMove()` [954-1002] -- `RadiusNavigationPoints(1200)` scoring to pick a retreat target.
- `NotifyJumpApex()` [1045-1049] -- jump-apex callback.
- `GetAIInfo()` [1051-1055] -- AI-info accessor.
#### 3. LOGIC PIPELINE
These are leaf helpers called from the hub and states (e.g. retreat from P4 [Bot:57] / tactical-retreat path, collectable from `GetItem`/economy, near-point from move pick). They mutate no persistent state beyond their own locals plus `LastFactory`.
#### 4. INPUTS / OUTPUTS
Input: `Enemy`, `Pawn` location/rotation, `mut` (node block, objective), world nav points. Output: a scored/selected point or pawn (`RetreatDest`, collectable, near-point), grenade-throw decision, `LastFactory` latch.
#### 5. FLOW   @FLOW-LOGIC-UTIL
```
ShouldNadeEnemies [261] --> nade decision (BestScore anomaly: uninitialized)
FindCollectable [1004] --> KFPickupFactory @800u, armor-only, LastFactory latch
GetPointNear [1094]    --> 25-iter near-point sampler
PickRetreatMove [954]  --> RadiusNavigationPoints(1200) scoring
NotifyJumpApex [1045] | GetAIInfo [1051]
```
#### 6. TECHNICAL REFERENCE
- Ranges: ShouldNadeEnemies [261-302], FindCollectable [1004-1043], GetPointNear [1094-1154], PickRetreatMove [954-1002], NotifyJumpApex [1045-1049], GetAIInfo [1051-1055].
- Cross-file: callers in hub [Bot:17] and states (`GetItem` [Bot:1718], tactical retreat [Bot:888]); `LastFactory` var [Base:165].
#### 7. WHERE TO FIX
Grenade heuristic (incl. the `BestScore` anomaly) --> `ShouldNadeEnemies` [261-302]. Collectable gate --> `FindCollectable` [1004-1043]. Retreat scoring --> `PickRetreatMove` [954-1002]. Near-point sampler --> `GetPointNear` [1094-1154].

# PART 4 (K) -- KF2Bot.uc State Systems (K1--K6, P4.28--P4.33)

Primary file: KF2Bot.uc (2075 lines, `17aad4ee`). Class `KF2Bot` extends `KF2BotLogic` [2], with `hidecategories(Navigation)` [2]. Inheritance chain: KF2BotsFollowNavBase --> KF2BotBase --> KF2BotLogic --> **KF2Bot** (leaf; defines all 18 states). Citations `[123]` = KF2Bot.uc line; `[Base:123]` = KF2BotBase.uc; `[Logic:123]` = KF2BotLogic.uc; `[Mut:123]` = KF2BotsMut.uc; `[Nav:123]` = KF2BotsFollowNavBase.uc.

---

### P4.28 (K1) Decision Hub   @SYS-BOT-HUB      Primary file: KF2Bot.uc
#### 1. PLAIN-ENGLISH SUMMARY
The bot's brain tick. Every state funnels back here through PickCombatStyle, and `PickMove` re-runs one fixed priority queue (P1--P10) that decides what the bot does next: survive (match over / heal self), disengage (retreat, regroup), work (objective, heal others), fight (combat, hunting), or idle (camp).
#### 2. EXPLANATION
`state PickNextMove` [4-259]; `BeginState` [6]; `Begin` [257-259]: `Sleep(0.0); PickMove(); stop;`. `PickMove` [17-253] hoists all locals at the top [20-24] (incl. the `Regroup*` set [21-24] and `bHasAmmo`), satisfying strict hoisting.
- **P1 Terminal** [28-37]: `bInTerminalState` --> `GotoState('VictoryDance')` [28-31]; `mut.KF.MyKFGRI.bMatchIsOver` --> VictoryDance [32-35].
- **P2 Grab** [37-39]: comment only -- handled asynchronously via CheckGrabbed [Logic:304] --> BreakLose, per Design Doc aSec2.3.
- **P3 Critical survival** [41-51]: `CheckShouldSelfHeal()` [Logic:202] --> `GotoState('HealingSelf')` [47-51]; pacing stamps set by HealSuccess [Logic:541], backoff by HealFail [Logic:532].
- **P4 Tactical retreat** [53-62]: gate `bIsGroupLeader && KPawn != none && !bIsRetreating && ShouldTacticalRetreat()` [57-62] (ShouldTacticalRetreat [Base:2293]); followers react passively in EvaluateFollowerMove [Logic:1213].
- **P4.5 Regroup** [63-166]: gate `mut.GetSquadPhase(self) == mut.PHASE_REGROUP` + not FollowingLeader, `RegroupElapsed < REGROUP_HARD_TIMEOUT` (6.0) [67-71]. Branch 1 trader [73-81] (same condition as P9, single source of truth); Branch 2 hunt band [85-91]: `GlobalZedCount > 0 && != 15 && <= 30` --> Hunting (15 = deadband, >30 falls through to P5--P10); Branch 3 attach/merge [95-155]: `FindNearestActiveLeader(AUDIT_ATTACH_RADIUS)` [108], cross-squad `MoveSquadMembers` with larger squad absorbing smaller [115-119], human-anchor `FollowStart(RegroupAttach)` [135-140], hold band `REGROUP_HOLD_DIST_SQ` [147-153]; leader camp [157-160] via `ExecuteCampState()` [Logic:1365].
- **P5 SYG enforcement** [168-189]: gate `mut.bObjectiveActive` [171]; ammo gate `bHasAmmo = (Pawn != None) && (Pawn.Weapon != None) && (KFWeapon(Pawn.Weapon).GetTotalAmmoAmount(0) > 0)` [177]; goal roll `ObjectiveGoal = mut.GetBotObjective(self)` + `AuditGoalLog("GOAL_SET", ...)` [181-184]; goto [186-189]: `ObjectiveGoal != none && bHasAmmo && VSizeSq(...) > SYG_DISTANCE_SQ (1000000 = 1000u2) && now >= ObjectiveBailUntil` --> DoObjective.
- **P6 Squad medic triage** [193-208]: 2.0s `TRIAGE_INTERVAL` shared by dart and syringe scans [195-197]; `CheckMedicGunHeal()` [Logic:117] --> HealRanged [198-201]; `CheckShouldHealMate()` [Logic:4] --> HealOther [202-205].
- **P7 Combat engagement** [210-229]: alive + non-headless filter [214]; leash drop `LEASH_DROP_DIST_SQ` (5760000 = 2400u2) --> `Enemy = none` + cooldown stamp [215-219]; `LineOfSightTo(Enemy)` --> FightEnemy [219-221], else Hunting [222-225].
- **P8 Squad tethering** [232-233]: `EvaluateSquadTether()` [Logic:1169] (may return a move intent).
- **P8.5 Low zed count** [235-241]: `Enemy == none && GlobalZedCount > 0 && < HUNT_ZED_THRESHOLD (15)` --> Hunting.
- **P9 Economy** [244-249]: `KFGRI.bTraderIsOpen && NextShoppingTime < now && KFGRI.OpenedTrader != none` --> GoShopping.
- **P10 Camp** [251-252]: `ExecuteCampState()` [252] --> `GotoState('Camp')` [Logic:1369].
#### 3. LOGIC PIPELINE
Any state's exit path --> PickCombatStyle [Base:2123-2159] (terminal lock --> VictoryDance; advanced-locomotion follow guard --> return without hopping; else GotoState('PickNextMove')) --> Begin --> PickMove --> first matching priority P1..P10 --> one of {VictoryDance, HealingSelf, TacticalRetreat, GoShopping, Hunting, DoObjective, HealRanged, HealOther, FightEnemy} or Camp.
#### 4. INPUTS / OUTPUTS
Input: `Enemy`, `ObjectiveGoal`, mutator phase/flags (`mut.GetSquadPhase`, `mut.bObjectiveActive`, KFGRI `bTraderIsOpen`/`bMatchIsOver`), `GlobalZedCount`, pawn health/ammo. Output: exactly one state transition per hub run; writes `ObjectiveGoal`/`ObjectiveBailUntil` [181-184], `bIsRetreating` [57-62], `Enemy`/`LastLeashDropTime` [217-218], `LastTriageTime` [197].
#### 5. FLOW   @FLOW-BOT-HUB
```
PICKMOVE [17]  (per state exit via PickCombatStyle [Base:2123])
|--> P1 bInTerminalState | bMatchIsOver --> VictoryDance [28-35]
?+ P2 grab: async via CheckGrabbed [Logic:304] (comment only [37-39])
?+ P3 CheckShouldSelfHeal --> HealingSelf [47-51]
?+ P4 leader && ShouldTacticalRetreat --> TacticalRetreat [57-62]
?+ P4.5 PHASE_REGROUP && elapsed<6.0 [63-166]
|  ?+ trader open (==P9) --> GoShopping [73-81]
|  ?+ zed band (1..14, 16..30) --> Hunting [85-91]
|  ?+ attach/merge (FindNearestActiveLeader) [95-155]
|  ?+ hold band (>100u from leader) --> FollowStart [147-153]
|  ?+ leader holds --> ExecuteCampState [157-160]
|--> P5 objective && ammo && >1000u --> DoObjective [168-189]
```
```
PICKMOVE (cont.)
|--> P6 triage (2.0s): CheckMedicGunHeal --> HealRanged [198-201]
|                         CheckShouldHealMate --> HealOther [202-205]
|--> P7 Enemy alive non-headless [210-229]
|  ?+ >2400u leash drop: Enemy=none [215-219]
|  ?+ LOS --> FightEnemy [219-221]; else --> Hunting [222-225]
|--> P8 EvaluateSquadTether [232-233]
|--> P8.5 Enemy==none && zeds 1..14 --> Hunting [235-241]
|--> P9 trader open && NextShoppingTime --> GoShopping [244-249]
|--> P10 ExecuteCampState (Camp) [251-252]
GATE: entry = PickCombatStyle [Base:2123], IdleWatchdog escalation [Logic:799],
      EndRagdollMove [Logic:1074]; every exit re-enters the hub.
```
#### 6. TECHNICAL REFERENCE
- State: `PickNextMove` [4-259] (Begin [257-259]); `PickMove` [17-253].
- Timers: none direct (hub is state-driven); regroup cadence via `mut.GetSquadStartTime`.
- Constants: REGROUP_HARD_TIMEOUT 6.0, REGROUP_DURATION 5.0, REGROUP_HOLD_DIST_SQ 10000, AUDIT_ATTACH_RADIUS 3000, SYG_DISTANCE_SQ 1000000, TRIAGE_INTERVAL 2.0, LEASH_DROP_DIST_SQ 5760000, HUNT_ZED_THRESHOLD 15 [Base:61,71,76,90,106,113,114,115].
- Edge cases: P2 is a comment placeholder [37-39]; P4.5 deadband `GlobalZedCount == 15` falls through; P5 only forces the objective path when outside the 1000u zone (AUDIT_3B Step 2 safe early fix [173-177]); P9 "only reachable once SYG (P5) is satisfied" [244].
#### 7. WHERE TO FIX
- Priority ordering / adding a priority: PickMove body [28-252].
- Regroup behaviour: [63-166] (branches 1--3).
- Hub entry funnel: PickCombatStyle [Base:2123-2159].

---

### P4.29 (K2) Movement & economy states (Roaming, Camp, GetItem, DonatingMoney)   @SYS-BOT-MOVE      Primary file: KF2Bot.uc
#### 1. PLAIN-ENGLISH SUMMARY
Idle and economy movement: roaming wander (with the Camp substate), the stationary Camp hold, collectable pickup (GetItem), and cash tossing to a human (DonatingMoney, whose substate MoneyToss spawns the coins).
#### 2. EXPLANATION
- **Roaming** [261-450]: legacy wander state. `BeginState` (AuditStateEntry, melee-weapon swap for melee-only bots, bounded `WaitForLanding`, PickStyle). PickStyle: group leader converges when >360000 sq (600u) from anchor, else `Rand(3)` wander; FollowingHuman --> follow; else `BuildRandomPath` [Base:1654] with a `VRand * 300` jitter fallback. Embedded `EnemyChanged` [419-423] and `DonateMoney` [425-434] (sets `DonateHuman`, enters DonatingMoney). Camp-style substate [444-449]: `Sleep(0.5+FRand())` + PickCombatStyle. `FinishedMove` --> PickCombatStyle. `EndState`: AuditStateExit.
- **Camp** [452-483]: stationary hold. `BeginState`: AbortMove; sprint off; `SetFocalPoint`; `Sleep(1.0 + FRand())`; PickCombatStyle. Entered via `ExecuteCampState()` (P10 [252] and P4.5 [160]) --> [Logic:1369]. `EndState`: AuditStateExit.
- **GetItem** [1718-1776]: collectable pickup. `BeginState`: AuditStateEntry; AbortMove; `SetSprinting(Enemy == none)`; armed 0.1--0.25s fire timer when Enemy visible. Timer: `FireWeaponAt(Enemy)` [Base:881]. Begin: landing; `MoveTowardX(LastFactory, Enemy)` [1718-1776] (`LastFactory` = FindCollectable latch [Logic:1037]). EndState: AuditStateExit; stop timer; sprint off; StopFiring.
- **DonatingMoney** [1778-1911]: the only state whose `Tick(Delta)` calls `global.Tick(Delta)` (delegates to [Base:1322]). Tick: human dead/absent --> PickCombatStyle; within 90000 sq (300u) with clear `FastTrace` --> PickCombatStyle; `MoveFlags != 0` --> substate MoneyToss; else `Acceleration` toward human. `DropMoney()` [1804-1880]: `TossVel = Normal(toHuman) * ((Velocity Dot TossVel) + 500) + vect(0,0,200)`; `Amount = Min(50, int(PRI.Score))`; spawns `KFDroppedPickup_Cash` kinematic (`SetPhysics(2)`, `InventoryClass = KFInventory_Money`, `Velocity = TossVel * 1.6`, `TosserPRI`), authority dialog `PlayDoshTossDialog`. MoneyToss: `NextDoshShareTime = now + 5.0`; up to 8 coins x 0.35s cadence (`DoshDropCounter = byte(Rand(4))`).
#### 3. LOGIC PIPELINE
Hub P10 --> Camp (hold) --> PickCombatStyle. Roaming = legacy wander (hub P4.5/P10 and Restart paths). GetItem --> FindCollectable latch (P4/PickCombatStyle pickup paths, Logic:1004-1043). DonatingMoney --> Roaming DonateMoney [425-434]; MoneyToss tosses coins and returns to hub.
#### 4. INPUTS / OUTPUTS
Input: `AssignedAnchor` [Base:25], `LastFactory` [Base:165], `DonateHuman`, `PRI.Score`, `MoveFlags`. Output: `KFDroppedPickup_Cash` actors (<=8, <=50 score each), Score decremented per coin, `NextDoshShareTime`/`NextShoppingTime` stamps. Single-writer: `DropMoney` is the only Score-decrement site in this file.
#### 5. FLOW   @FLOW-BOT-MOVE
```
ROAMING [261]
|--> BeginState: audit, melee swap, WaitForLanding, PickStyle
?+ leader >600u from anchor --> converge; else Rand(3) wander
|--> following human --> follow; else BuildRandomPath (VRand*300 jitter)
|--> EnemyChanged [419] / FinishedMove --> PickCombatStyle
|--> DonateMoney [425] --> state DonatingMoney
CAMP [452]  (hub P10 [252] / P4.5 [160] via ExecuteCampState [Logic:1365])
|--> AbortMove, sprint off, SetFocalPoint, Sleep(1+FRand), PickCombatStyle
GETITEM [1718]
|--> BeginState: audit, AbortMove, sprint(Enemy==none)
?+ Enemy visible --> timer FireWeaponAt (0.1-0.25s)
|--> MoveTowardX(LastFactory, Enemy) [Logic:1037]
|--> EndState --> hub
DONATINGMONEY [1778]
|--> Tick: global.Tick; human dead --> hub
?+ <300u && FastTrace clear --> hub
?+ MoveFlags!=0 --> MoneyToss
|--> MoneyToss: NextDoshShareTime+=5; 8x coins (0.35s) via DropMoney [1804]
|--> PickCombatStyle
```
#### 6. TECHNICAL REFERENCE
- States: Roaming [261-450], Camp [452-483], GetItem [1718-1776], DonatingMoney [1778-1911].
- Functions: DropMoney [1804-1880]; substate MoneyToss [1778-1911]; embedded DonateMoney [425-434].
- Edge cases: kinematic cash spawn (`SetPhysics(2)`) [1804-1880]; coin total bounded by score; `global.Tick` delegation is unique to this state; native pickup path of GetItem (auto-collect on pickup factory) not verified in SDK (SDK behaviour not verified).
#### 7. WHERE TO FIX
- Wander distribution / leader convergence: Roaming PickStyle [261-450].
- Coin toss physics / amounts: DropMoney [1804-1880].
- Pickup target: FindCollectable [Logic:1004-1043] (LastFactory latch).

---

### P4.30 (K3) Combat states (DoObjective, FightEnemy, TacticalRetreat, BreakLose, Hunting, GrenadeTarget)   @SYS-BOT-COMBAT      Primary file: KF2Bot.uc
#### 1. PLAIN-ENGLISH SUMMARY
All fight and disengage states: objective push (DoObjective, which extends Roaming), the core engagement state FightEnemy (with its 0.2s timer and PickStyle), the hysteresis-based TacticalRetreat, grapple escape (BreakLose), zed hunting, and the legacy GrenadeTarget lob.
#### 2. EXPLANATION
- **DoObjective extends Roaming** [485-603]: `FinishObjective` wrapper calls `global.FinishObjective` [Logic:1084] + PickCombatStyle. PickStyle: `CheckObjectiveHazard` [Base:2318] (siren/zed hazard, Loophole 7) --> goal roll with `AuditGoalLog` --> `mut.IsNodeBlocked` gate (Step 4b) --> reachability test `VSizeSq > 90000.0` (300u) --> node-block recording (`AddNodeBlock` when >=2s apart, <2 blocks per episode); bail --> `ObjectiveBailUntil = now + OBJ_BAIL_COOLDOWN` (8.0); fallback random path (inherited Roaming PickStyle). Inherits BeginState/Timer/EndState from Roaming (decompile artifact: extends clause + bare `stop;`, Appendix C).
- **FightEnemy** [605-886]: `BeginState` [607-615]: `SetTimer(0.2, true)` (Timer); `Focus = Enemy`; `Timer()`. `EndState` [617-629]: clear timers, `ShouldCrouch(false)`, StopFiring. `Timer` [633-682]: dead enemy --> `PickNextEnemy` [Base:779]; FinishedMove path; headless drop; `SyncLineFocus` [Base:2893]; `CheckWeaponReequip` [Base:3343]; `EnemyEncounterTime`; `HasOwnFireLine` gate [Base:2938] else StopFiring + `NotifyBlockedShooter` [Base:3234] (GRUNT in LineFormation); `FireWeaponAt(Enemy)` [Base:881]. PickStyle: `[GRUNT] GruntPickCombatStyle [Base:4108]` bypasses the legacy funnel; SYG gate 640000 sq (800u2); group-leader / FollowingHuman tether 2250000 sq (1500u2); IsMeleeOnly handling; `bOutOfEffectiveRange && !bMelee` --> `CloseToEffectiveRange` [Base:3322]; **Boss-Melee Guard (Loophole 1)**: `bMelee && Enemy.Health > BOSS_HEALTH_THRESHOLD (5000)` --> drop + PickCombatStyle; retreat gate `Enemy.Health > 500 ? 250000 : 14400` (120u2) --> `PickRetreatMove` [Logic:954]; melee `StartFire(0)` when dist < 40000 sq (200u2); strafe `Rand(2)` / crouch + `SetTimer(0.5 + FRand*1.5, 'FinishedMove')`. `NotifyKilled`: boss kill --> `bBossKillVictory` + VictoryDance; enemy killed --> PickNextEnemy; victory-dance roll `(Killer == self) && Rand(3) == 0 && mut.ShouldDoVictoryDance()`. `NotifyBump` [855-875] --> global.NotifyBump [Base:1749] + bump-vs-Enemy handling.
- **TacticalRetreat** [888-952]: BeginState: sprint ON; `SetTimer(ZED_COUNT_INTERVAL (1.0), true, 'CheckRetreatStatus')`; `PickRetreatMove` [Logic:954]. `CheckRetreatStatus` [913-928]: hysteresis -- `CountNearbyZeds(RETREAT_ZED_RADIUS 500u) < RETREAT_ZED_CLEAR_COUNT (2) && !HeavyZedWithin(RETREAT_HEAVY_RADIUS 300u)` [Base:2275] --> `bIsRetreating = false; PickCombatStyle()`. `FinishedMove`: burst PickRetreatMove. `EnemyChanged` ignored.
- **BreakLose** [954-1062]: `ignores CheckGrabbed`. BeginState: reset counters; `SetTimer(0.15, true)`; `Focus = InteractionPawn`; `OnGruntGrabbed` [Base:3977] buddy-rescue notify; bDebugGrapple log. EndState: StopFiring; `OnBreakLoseComplete` [Base:3859]. Timer: still grabbed --> Focus; 1.5s-throttled `TryBreakFree` [Base:945] + `BreakFreeAttempts`; failsafe `now - GrabStartTime >= mut.FailsafeActivationDelay && CountNearbyZeds(600) <= mut.MaxZedsForFailsafe` --> `ForceBreakGrapple` [Base:2375]; else PickCombatStyle.
- **Hunting** [1064-1190]: BeginState: sprint ON; `SetTimer(0.25, true)`. PickStyle: leader/FollowingHuman at >810000 sq (900u) --> `Enemy = none`; dead enemy --> PickCombatStyle; `BuildPathToward(Enemy)` [Base:1496]. Timer: AllPawns scan over `KFPawn_Monster` within `HUNT_SCAN_RADIUS` (5000u; alive, team mismatch, FastTrace) --> `SetEnemy` [Base:805] + BuildPathToward + MoveTowardX; else no enemy --> PickCombatStyle, or `LineOfSightTo` --> PickCombatStyle.
- **GrenadeTarget** [1538-1576]: legacy grenade-lob. Begin: landing (`Physics == 2` --> WaitForLanding); `Focus = Target; FinishRotation(); Pawn.Weapon.StartFire(4); Sleep(0.2); Enemy = Target; PickRetreatMove()`. FinishedMove --> PickCombatStyle. **EndState: only StopFiring -- NO AuditStateExit** (Appendix C, finding #4). Unreachable from current hub priorities (Appendix D).
#### 3. LOGIC PIPELINE
Hub P5 --> DoObjective (objective push, hazard-checked); P7 --> FightEnemy (LOS) / Hunting (no LOS); P4 --> TacticalRetreat (leader disengage, 1s hysteresis recheck); CheckGrabbed [Logic:304] --> BreakLose (grapple interrupt); hub P8.5/P7 --> Hunting. GrenadeTarget: legacy funnel residual only.
#### 4. INPUTS / OUTPUTS
Input: `Enemy`, `InteractionPawn`, ObjectiveGoal, `bMelee`/`bOutOfEffectiveRange` [Base:308-310], mut failsafe config. Output: `FireWeaponAt`/`StartFire` fire intents, `PickRetreatMove` move intents, `bIsRetreating` latch [Base:180], `ObjectiveBailUntil`/node-block records, rescue notify [Base:3977]. Single-writer: `bIsRetreating` written only by hub P4 [57-62] and CheckRetreatStatus [913-928].
#### 5. FLOW   @FLOW-BOT-COMBAT
```
DOOBJECTIVE [485]  extends Roaming
|--> FinishObjective --> global.FinishObjective [Logic:1084] + hub
?+ CheckObjectiveHazard [Base:2318] --> FightEnemy / focal hold
?+ mut.IsNodeBlocked || unreachable (<300u)
|--> bail: ObjectiveBailUntil += 8.0; fallback Roaming random path
FIGHTENEMY [605]
|--> BeginState: Timer 0.2s; Focus=Enemy; Timer()
?+ timer: enemy dead --> PickNextEnemy [Base:779]
?+ !HasOwnFireLine [Base:2938] --> StopFiring + NotifyBlockedShooter [Base:3234]
|--> FireWeaponAt(Enemy) [Base:881]
|--> PickStyle: [GRUNT] --> GruntPickCombatStyle [Base:4108]
?+ SYG 800u gate; leader/FollowingHuman 1500u tether
?+ bMelee && Enemy.Health>5000 (boss) --> drop + hub (Loophole 1)
?+ dist < (Health>500 ? 250000 : 14400) sq --> PickRetreatMove [Logic:954]
?+ melee <200u --> StartFire(0); else strafe Rand(2) / crouch + 0.5-2.0s timer
```
```
TACTICALRETREAT [888]
|--> BeginState: sprint ON; Timer 1.0s 'CheckRetreatStatus'; PickRetreatMove
?+ CheckRetreatStatus [913]: zeds(500u)<2 && !HeavyZed(300u)
|--> bIsRetreating=false; hub  (else keep retreating; FinishedMove bursts)
BREAKLOSE [954]  (ignores CheckGrabbed)
|--> BeginState: Timer 0.15s; Focus=InteractionPawn; OnGruntGrabbed [Base:3977]
?+ still grabbed --> Focus; TryBreakFree [Base:945] every 1.5s
?+ failsafe: elapsed >= FailsafeActivationDelay && zeds(600) <= MaxZedsForFailsafe
|--> ForceBreakGrapple [Base:2375]; else hub
HUNTING [1064]
|--> BeginState: sprint ON; Timer 0.25s
?+ leader/FollowingHuman >900u --> Enemy=none
|--> BuildPathToward(Enemy) [Base:1496]
?+ timer: AllPawns KFPawn_Monster <5000u, alive, team mismatch, FastTrace
|--> SetEnemy + BuildPathToward + MoveTowardX; else --> hub
GRENADETARGET [1538]  (legacy, hub-unreachable; no AuditStateExit)
|--> StartFire(4) x0.2s; Enemy=Target; PickRetreatMove; FinishedMove --> hub
```
#### 6. TECHNICAL REFERENCE
- States: DoObjective [485-603], FightEnemy [605-886] (BeginState [607-615], EndState [617-629], Timer [633-682], NotifyBump [855-875]), TacticalRetreat [888-952] (CheckRetreatStatus [913-928]), BreakLose [954-1062], Hunting [1064-1190], GrenadeTarget [1538-1576].
- Timers: FightEnemy 0.2s [607-615]; TacticalRetreat 1.0s; BreakLose 0.15s; Hunting 0.25s.
- Constants: SYG 640000 (800u2, FightEnemy-local literal [605-886]), tether 2250000 (1500u2 [605-886]), melee 40000 (200u2 [605-886]), retreat gate 14400/250000 (120u2/500u2 [605-886]); BOSS_HEALTH_THRESHOLD 5000 [Base:62], RETREAT_ZED_RADIUS 500.0 [Base:64], RETREAT_ZED_CLEAR_COUNT 2 [Base:66], RETREAT_HEAVY_RADIUS 300.0 [Base:67], OBJ_BAIL_COOLDOWN 8.0 [Base:69], HUNT_SCAN_RADIUS 5000.0 [Base:72].
- Edge cases: GrenadeTarget missing AuditStateExit (Appendix C); DoObjective `extends Roaming` + bare `stop;` (Appendix C); boss-melee guard drops engagement above 5000 HP (Loophole 1).
#### 7. WHERE TO FIX
- Engagement style per rank: FightEnemy PickStyle [605-886] and GruntPickCombatStyle [Base:4108].
- Retreat trigger/hysteresis: hub P4 [53-62] + CheckRetreatStatus [913-928].
- Grapple escape tuning: BreakLose timer [954-1062] (failsafe via mut config).
- Objective push/bail: DoObjective PickStyle [485-603].

---

### P4.31 (K4) Heal states (HealingSelf, HealOther, HealRanged)   @SYS-BOT-HEAL      Primary file: KF2Bot.uc
#### 1. PLAIN-ENGLISH SUMMARY
The three heal states: self-heal with the syringe, melee-range heal of a mate, and ranged dart heal. All follow the same shape -- audit + abort move, a bounded landing wait, an 8s failsafe, an "approach first, equip last" sequence, the heal application (HealthToRegen + clamped regen timer), and HealSuccess pacing.
#### 2. EXPLANATION
Common shape: BeginState = AuditStateEntry + AbortMove; EndState = AuditStateExit, ClearTimer('HealFailsafe')/('VerifyWeapon'), `PendingHeal = none`, StopFiring, weapon restore, `SetTimer(1.5, false, 'VerifyWeapon')`.
- **HealingSelf** [1192-1294]: `ignores FinishedMove`. EndState [1197-1217]: comment "Weapon restore on EVERY exit path... 1.5s VerifyWeapon one-shot is a backstop" [1207-1209]; `KFWeap_HealerBase(Pawn.Weapon) != none` --> `SwitchToBestWeapon(true)` [1211-1213] (restore check uses HealerBase). TimeOut --> HealFail [Logic:532] + hub. `HealFailsafe` [1225-1229]: 8s force-exit. Begin [1231-1294]: bounded landing (`landingDeadline = now + 2.0`; WaitForLanding has no timeout in KF2 SDK) [1231-1238]; `SetTimer(8.0, false, 'HealFailsafe')` [1239]; dead/None pawn --> HealFail [1242-1246]; `!CanAffordHeal(0)` (shared predicate with the gate, [Logic:521]) --> HealFail [1249-1253]; equip syringe bounded 3s (re-request every 0.1s) [1255-1260] --> fail --> HealFail [1261-1264]; `Focus = Pawn` [1266]; apply [1268-1294]: `AmmoCount[0] -= 100`, `PerformReload`, `PlayAnimation('Heal_Self')`, `KPawn.HealthToRegen += 20`, bounded anim sleep `FMin(FMax(GetAnimInterruptTime, 0.1), 3.0)`, clamp to HealthMax, `SetTimer(HealthRegenRate, true, 'GiveHealthOverTime')`, `PlayHeal`, `HealSuccess()` [Logic:541], hub.
- **HealOther** [1295-1413]: `ignores FinishedMove`. EndState same shape (HealerBase restore). Begin: bounded landing; 8s failsafe; `PendingHeal == none` --> fail+stop; **APPROACH FIRST** loop (bot walks with combat weapon, not the syringe): abort if PendingHeal dead/none or `PendingHeal.Health >= (HEAL_MIN_NEED_PCT/100.0) * PendingHeal.HealthMax` (need-satisfied); break at `VSize <= 200.0 && LineOfSightTo(PendingHeal)`; else MoveTowardX + Sleep(0.1); **EQUIP LAST** bounded 3s syringe loop; `AbortMove(); Acceleration = vect(0,0,0); Focus = PendingHeal; Target = PendingHeal; FinishRotation();`; apply: `AmmoCount[0] -= 100; PerformReload; PlayAnimation('Heal_Team'); PendingHeal.HealthToRegen += 20;` bounded anim sleep; clamp; `GiveHealthOverTime`; PlayHeal; HealSuccess; hub.
- **HealRanged** [1415-1537]: `ignores FinishedMove`. Same shape; **EndState restores on `KFWeap_MedicBase` (the dart-gun class), not HealerBase**. Begin: bounded landing; 8s failsafe; approach-first with range break `VSize <= 1500.0 && LineOfSightTo` (1500u dart range); same need-satisfied abort; **EQUIP LAST** with `!CanAffordHeal(1)` gate (type1 >=50) [Logic:521] + 3s bounded equip loop for RangeMedicGun; apply: `StartHealRecharge()`, `PlayAnimation('Shoot_Dart')`, `mut.RegisterRangedHealTarget(PendingHeal)` (per-target 25s cooldown, [Mut:900]), `PendingHeal.HealthToRegen += RangeMedicGun.default.HealAmount`, `Sleep(FMin(GetFireInterval(1), 3.0))`, clamp, GiveHealthOverTime, PlayHeal, HealSuccess; hub.
#### 3. LOGIC PIPELINE
Hub P3 --> HealingSelf; hub P6 --> HealRanged (dart, 2s triage) / HealOther (syringe); all exits --> HealSuccess [Logic:541] (the ONLY pacing-stamp writer: SyringeRechargeEnd = now+15, HealPacingEnd = now+20+FRand*10) or HealFail [Logic:532] (backoff FMin(4*streak,20)) --> hub.
#### 4. INPUTS / OUTPUTS
Input: `PendingHeal` (set by CheckShouldHealMate/CheckMedicGunHeal [Logic:4,117]), `CanAffordHeal` [Logic:521], MedicGun/RangeMedicGun ammo. Output: `HealthToRegen += 20` (syringe) or `+= HealAmount` (dart), `GiveHealthOverTime` timer, ammo decrements, pacing stamps via HealSuccess, `mut.RegisterRangedHealTarget` cooldown. Single-writer: heal application code is the only HealthToRegen writer in this file.
#### 5. FLOW   @FLOW-BOT-HEAL
```
HEALINGSELF [1192]  (hub P3)
|--> BeginState: audit, AbortMove
|--> Begin: landing (2s cap); Timer 8.0s 'HealFailsafe'
?+ pawn dead/None --> HealFail [Logic:532] + hub
?+ !CanAffordHeal(0) --> HealFail + hub  (shared predicate [Logic:521])
?+ syringe equip (3s cap) fails --> HealFail + hub
|--> Focus=Pawn; AmmoCount[0]-=100; 'Heal_Self' anim; HealthToRegen+=20
|--> clamp; GiveHealthOverTime; PlayHeal; HealSuccess [Logic:541]; hub
HEALOTHER [1295]  (hub P6, syringe)
|--> APPROACH FIRST: abort if need-satisfied (>=60%); break at <=200u + LOS
|--> EQUIP LAST (3s cap); Focus/Target=PendingHeal; FinishRotation
|--> AmmoCount[0]-=100; 'Heal_Team'; PendingHeal.HealthToRegen+=20; heal
HEALRANGED [1415]  (hub P6, dart)
|--> APPROACH FIRST: break at <=1500u + LOS
?+ !CanAffordHeal(1) --> fail  (type1 >=50)
|--> StartHealRecharge; 'Shoot_Dart'; RegisterRangedHealTarget [Mut:900]
|--> HealthToRegen += HealAmount; heal
HOLD: 8s 'HealFailsafe' in all three [1244,1344,1464]
ABORT: TimeOut/HealFailsafe --> HealFail + hub; EndState restores weapon
       (HealerBase [1211] / MedicBase [1415-1537]) + 1.5s VerifyWeapon [Logic:553]
```
#### 6. TECHNICAL REFERENCE
- States: HealingSelf [1192-1294] (EndState [1197-1217], TimeOut [1219-1223], HealFailsafe [1225-1229]), HealOther [1295-1413], HealRanged [1415-1537].
- Timers: 'HealFailsafe' 8.0s (one-shot) in each; 'VerifyWeapon' 1.5s from each EndState --> [Logic:553-567]; `GiveHealthOverTime` (HealthRegenRate, looping) on the healed pawn.
- Constants: HEAL_MIN_NEED_PCT 60.0, HEAL_MAX_NEED_PCT 80.0 [Base:84,85]; approach breaks 200u (melee) / 1500u (ranged) are state-local literals.
- Edge cases: weapon-restore class differs (HealerBase vs MedicBase); WaitForLanding has no SDK timeout --> bounded 2s deadline pattern; HealSuccess is the sole pacing writer.
#### 7. WHERE TO FIX
- Pacing / backoff: HealSuccess [Logic:541] / HealFail [Logic:532].
- Approach range: HealOther <=200u, HealRanged <=1500u literals inside Begin.
- Weapon restore: EndState blocks [1211-1213] and HealRanged EndState.

---

### P4.32 (K5) Shopping (GoShopping)   @SYS-BOT-SHOP      Primary file: KF2Bot.uc
#### 1. PLAIN-ENGLISH SUMMARY
The trader visit: walk to the opened trader, purchase via the shared economy layer, then return to combat -- with a bounded retry (linear backoff) when the trader doorway is body-blocked.
#### 2. EXPLANATION
`state GoShopping` [1578-1716]. BeginState: AuditStateEntry. EndState: AuditStateExit; ClearTimer('DoTrading'); sprint off. `EnemyChanged` --> PickCombatStyle. PickStyle: `KFGRI.OpenedTrader == none` --> hub; `ActorReachable(OpenedTrader)` --> `TraderRetryCount = 0; MoveToX(OpenedTrader.Location)`; `BuildPathToward(OpenedTrader)` [Base:1496] --> MoveTowardX(MoveTarget); else **Loophole 6 (trader bodyblock mitigation)** -- bounded retry with backoff instead of cycling DoTrading forever: `++TraderRetryCount`; `>= TRADER_MAX_RETRIES (3)` --> reset + `NextShoppingTime = now + TRADER_GIVEUP_COOLDOWN (10.0)` --> hub; else `SetTimer((1.0 + FRand()*2.0) + TraderRetryCount*1.0, false, 'DoTrading')` (linear backoff). Timer (re-armed 0.4--0.65s): `OpenedTrader == none` --> hub; `Pawn.IsOverlapping(OpenedTrader)` --> AbortMove + stop timer + `SetTimer(1.0 + FRand()*2.0, false, 'DoTrading')`. `DoTrading`: `KFGRI.TraderItems != none` --> `ProcessPurchase(KFGRI.TraderItems)` [Base:1939]; `NextShoppingTime = now + 60.0`; `NextDoshShareTime = now + 50.0`; `Rand(3) == 0` --> `GotoState('VictoryDance', 'MoveTaunt')` (post-shopping taunt), else hub. `NotifyBump` [1697-1706]: active 'DoTrading' timer --> false, else `global.NotifyBump`. Begin: landing; PickStyle; stop.
#### 3. LOGIC PIPELINE
Hub P9 (or P4.5 Branch 1, identical trader condition) --> GoShopping --> DoTrading --> ProcessPurchase [Base:1939] (InitTraderList, sells, up to 8 purchase loops, ammo top-up, CreateInventory) --> hub (or VictoryDance taunt).
#### 4. INPUTS / OUTPUTS
Input: `KFGRI.OpenedTrader`/`TraderItems`, `NextShoppingTime`, `TraderRetryCount` [Base:232]. Output: inventory/money changes via ProcessPurchase; `NextShoppingTime` (+60) and `NextDoshShareTime` (+50) written here (single-writer in this file); retry stamps.
#### 5. FLOW   @FLOW-BOT-SHOP
```
GOSHOPPING [1578]  (hub P9 [244-249] / P4.5 branch1 [73-81])
|--> PickStyle: OpenedTrader none --> hub
?+ ActorReachable --> MoveToX(OpenedTrader)  (TraderRetryCount=0)
?+ BuildPathToward --> MoveTowardX(MoveTarget)
?+ else (bodyblock): TraderRetryCount++
|  ?+ >=3 --> NextShoppingTime += 10s; hub   (Loophole 6 giveup)
|  --> SetTimer (1+FRand*2)+count*1  'DoTrading'  (linear backoff)
?+ Timer (0.4-0.65s): IsOverlapping --> AbortMove, SetTimer(1+FRand*2)
|--> DoTrading: ProcessPurchase [Base:1939]
|--> NextShoppingTime += 60; NextDoshShareTime += 50
|--> Rand(3)==0 --> VictoryDance 'MoveTaunt'; else hub
```
#### 6. TECHNICAL REFERENCE
- State: GoShopping [1578-1716] (NotifyBump [1697-1706]).
- Timers: 'DoTrading' (re-armed 0.4--0.65s / 1.0--3.0s); backoff timers 1.0--5.0s.
- Constants: TRADER_MAX_RETRIES 3, TRADER_GIVEUP_COOLDOWN 10.0 [Base:99,100].
- Edge cases: retry bounded at 3 with linear backoff (Loophole 6); 'DoTrading' timer guard in NotifyBump [1697-1706].
#### 7. WHERE TO FIX
- Retry/backoff: PickStyle else-branch [1578-1716].
- Purchase policy: ProcessPurchase [Base:1939-2111].
- Revisit cadence: NextShoppingTime (+60) / NextDoshShareTime (+50) in DoTrading.

---

### P4.33 (K6) Terminal states (Dead, IsRagdolled, VictoryDance)   @SYS-BOT-TERM      Primary file: KF2Bot.uc
#### 1. PLAIN-ENGLISH SUMMARY
End-of-life states: Dead (scoreboard-flag reassert until respawn), IsRagdolled (physics ragdoll bridge), and VictoryDance (emote dance, the P1 terminal sink of the whole hub).
#### 2. EXPLANATION
- **Dead** [1913-1946]: `ignores StopAdjusting, Tick, CheckGrabbed, PickCombatStyle, SetEnemy, KilledBy, HearNoise, SeeMonster, SeePlayer`. BeginState: AuditStateEntry + `SetTimer(1.0, true, 'ReassertScoreboardFlags')`. EndState: AuditStateExit + ClearTimer. `ReassertScoreboardFlags`: `KFPRI = KFPlayerReplicationInfo(PlayerReplicationInfo); if (KFPRI != none) KFPRI.bHasSpawnedIn = true;` (prevents scoreboard "not yet spawned" flicker). Begin: `stop`. Entered by PawnDied [Logic:875-914] (GotoState('Dead') [Logic:912]).
- **IsRagdolled** [1948-1970]: same ignores list. BeginState: AuditStateEntry; AbortMove; StopFiring. EndState: AuditStateExit. Begin: `stop`. Entered/exited by ReplicatedEvent 'RagdollMove'/'EndRagdollMove' [Logic:1057-1082], which routes `bInTerminalState --> VictoryDance else PickNextMove` [Logic:1070,1074].
- **VictoryDance** [1972-2075]: `ignores HearNoise, SeeMonster, SeePlayer`. BeginState: AuditStateEntry; AbortMove; StopFiring; **P1 terminal lock** -- derive the flag from the live match-over condition: `if (mut.KF.MyKFGRI.bMatchIsOver) bInTerminalState = true;`. EndState: AuditStateExit; `bBossKillVictory = false`. `PlayDance`: `NextVictoryDance = now + 20.0`; `KPawn.DoSpecialMove(35, true, , mut.PickRandEmote())` [Mut:2754] (35 = emote special-move id). `FinishedMove`: random 2D focal 1000u; `GotoState('VictoryDance', 'Begin')` (re-dance loop via move completion). `GetRandMove`: 5-iter loop; candidate `Pawn.Location + Normal2D(V) * (FRand()*200 + 250)`; `FastTrace` break; returns last candidate if all traces fail. `EnemyChanged`: `if (!bBossKillVictory) PickCombatStyle();` (boss-kill dance persists despite enemy loss). `MoveTaunt`: `MoveToX(GetRandMove())`; stop. Begin: landing; `Sleep(0.1 + FRand())`; `PlayDance()`; `while (IsDoingSpecialMove(35) && ++DoshDropCounter < 250) Sleep(0.1)` (25s cap); hub.
#### 3. LOGIC PIPELINE
Death --> PawnDied [Logic:875] --> Dead (scoreboard reassert) --> respawn (mut RestartBot [Mut:2433]) or EndRagdollMove --> VictoryDance (if terminal) else hub. Match over --> VictoryDance (hub P1 [28-35] or terminal lock in BeginState).
#### 4. INPUTS / OUTPUTS
Input: `mut.KF.MyKFGRI.bMatchIsOver`, `bInTerminalState` [Base:177], `bBossKillVictory` [Base:174], `NextVictoryDance` [Base:159]. Output: `bHasSpawnedIn` (KFPRI), emote special-move 35, `bInTerminalState = true` (only hub-visible writer), dance re-entry via GotoState('VictoryDance','Begin').
#### 5. FLOW   @FLOW-BOT-TERM
```
DEAD [1913]  (PawnDied [Logic:875-914])
|--> BeginState: audit; Timer 1.0s 'ReassertScoreboardFlags' (bHasSpawnedIn)
|--> Begin: stop  (respawn: mut.RestartBot [Mut:2433])
ISRAGDOLLED [1948]  (ReplicatedEvent [Logic:1057-1082])
|--> 'RagdollMove' --> enter; 'EndRagdollMove' --> terminal? VictoryDance
|                                                        : PickNextMove
VICTORYDANCE [1972]  (hub P1 [28-35]; boss kill [P4.30]; post-shop taunt [P4.32])
|--> BeginState: terminal lock (bMatchIsOver --> bInTerminalState=true)
|--> PlayDance: NextVictoryDance += 20; DoSpecialMove(35, PickRandEmote)
?+ FinishedMove --> focal 1000u; GotoState('VictoryDance','Begin') (re-dance)
?+ EnemyChanged: !bBossKillVictory --> hub  (boss dance persists)
|--> Begin: dance loop (250x0.1s cap); hub  (exits reset bBossKillVictory)
```
#### 6. TECHNICAL REFERENCE
- States: Dead [1913-1946], IsRagdolled [1948-1970], VictoryDance [1972-2075].
- Timers: ReassertScoreboardFlags 1.0s looping (Dead only).
- Edge cases: `bInTerminalState` derives from live match state, not entry reason (BeginState comment); emote id 35 hard-coded; GetRandMove returns the last candidate when all 5 traces fail.
#### 7. WHERE TO FIX
- Terminal lock: VictoryDance BeginState [1972-2075].
- Dance emote/loop: PlayDance + FinishedMove/GetRandMove [1972-2075].
- Scoreboard flicker: ReassertScoreboardFlags (Dead) [1913-1946].

# PART 5 -- KF2BotsFollowNavBase.uc Systems (N1--N10)

Primary file: KF2BotsFollowNavBase.uc (1552 lines, `d543db64`), class `KF2BotsFollowNavBase extends AIController` `abstract` [29]. Citations `[123]` = KF2BotsFollowNavBase.uc line; `[Base:]`/`[Logic:]`/`[Bot:]`/`[Mut:]` = cross-file (see PART 1 manifest).

**Layer role.** This file is the HCA **Locomotion** layer for squad followers (Grunt --> Squad Leader). It owns every per-frame movement decision: it reads the leader/slot/order data the Hub writes, produces a `FollowAction` each watchdog pass, drives the Pawn with `Pawn.Acceleration` + `Sleep` (no native mover -- see N6/N9), and reports back through `FollowStatus` / `FollowNotifyHub` [1198-1212]. It **never mutates Hub state** (single-writer rule; header [18-19]).

---

### N1 Episode control   @SYS-NAV-EPISODE      Primary file: KF2BotsFollowNavBase.uc
#### 1. PLAIN-ENGLISH SUMMARY
The on/off controls for one follower episode. The Hub calls `FollowStart` to point this bot at its leader and drop it into the right state (advanced or basic). The Hub re-points the leader with `FollowSetLeader`, assigns the bot's slot with `FollowSetSlot`, and can read an "order anchor" from the Hub via `FollowGetOrderAnchor`. All per-episode counters are wiped by `FollowResetEpisode`, which also clears the route.
#### 2. EXPLANATION
`FollowStart(Controller NewLeaderCtrl)` [198-210]: calls `FollowSetLeader`, then `GotoState('FollowingLeader')` when `bEnableAdvancedLocomotion` [202] else `GotoState('FollowingLeaderBasic')` [205]. `FollowSetLeader` [212-219] stores `FollowLeaderCtrl`, nulls `FollowLeaderPawn`, zeroes `FollowLeaderInvalidSince`, clears `bFollowArrived`, then `FollowResetEpisode`. `FollowSetSlot(int,int)` [223-227] clamps `FollowSlotIndex = Max(n,0)` / `FollowSlotCount = Max(n,1)` (slot drives both the arrival ring and the time-slice phase). `FollowGetOrderAnchor(out vector OutLoc)` [232-236] is the **base no-op** (AUDIT_3B Step 5 hook): `OutLoc = vect(0,0,0)`, `return false`; KF2Bot overrides with the hub's SquadOrder data. `FollowResetEpisode` [238-261] zeroes every episode counter (`FollowRetries`, `FollowBlocksThisEpisode`, `FollowSameNodeCount`, `FollowNodeLast`, `FollowWallHitCount`, `FollowLastWall`, escape/yield/dispatch/exit flags, `FollowForcePathUntil`, `FollowStuckRefTime`), sets `FollowRetryAnchorLoc = Pawn.Location` when `Pawn != None` [253-256], and ends with `FollowInvalidateRoute`. `FollowInvalidateRoute` [263-270] clears `FollowRoute` (`.Length = 0`), resets `FollowRouteIdx`, sets `bFollowRouteStale = true`, `bFollowReachKnown = false`, `FollowReachFailStreak = 0`, `FollowNextReachCheckTime = 0.0`.
#### 3. LOGIC PIPELINE
Hub --> FollowStart --> (FollowSetLeader --> FollowResetEpisode --> FollowInvalidateRoute) --> GotoState(advanced|basic). Roster change --> FollowSetSlot. Order anchor --> FollowGetOrderAnchor (per pass).
#### 4. INPUTS / OUTPUTS
Input: `Controller NewLeaderCtrl`, slot ints. Output: `FollowLeaderCtrl`, `FollowSlotIndex/Count`, all episode counters, `FollowingLeader`/`FollowingLeaderBasic` state entry. Single-writer: this layer writes the episode counters; the Hub writes slot/leader/order.
#### 5. FLOW   @FLOW-NAV-EPISODE
```
FOLLOWSTART [198]
|--> FollowSetLeader(NewLeaderCtrl) [212]
|--> if bEnableAdvancedLocomotion --> GotoState('FollowingLeader') [202]
|--> else                        --> GotoState('FollowingLeaderBasic') [205]
FOLLOWSETLEADER [212]
|--> FollowLeaderCtrl = NewLeaderCtrl; FollowLeaderPawn = None
|--> FollowLeaderInvalidSince = 0; bFollowArrived = false
|--> FollowResetEpisode [238] -> zero counters -> FollowInvalidateRoute [263]
FOLLOWSETSLOT [223]
|--> FollowSlotIndex = Max(n,0); FollowSlotCount = Max(n,1)
FOLLOWGETORDERANCHOR [232]  (base)
|--> OutLoc = vect(0,0,0); return false   (KF2Bot override supplies anchor)
```
#### 6. TECHNICAL REFERENCE
- Functions: `FollowStart` [198-210], `FollowSetLeader` [212-219], `FollowSetSlot` [223-227], `FollowGetOrderAnchor` [232-236], `FollowResetEpisode` [238-261], `FollowInvalidateRoute` [263-270].
- Override points: `FollowGetOrderAnchor` (base false; KF2Bot supplies SquadOrder anchor -- see p4 K-series), `FollowStart` callers are the Hub ([Base:]).
- Edge cases: `FollowResetEpisode` guards `Pawn != None` before reading `Pawn.Location` [253-256].
#### 7. WHERE TO FIX
- Change which state a follower enters: `FollowStart` [198-210].
- Change order-anchor base behaviour: `FollowGetOrderAnchor` [232-236] (or the KF2Bot override).
- Change what an episode reset clears: `FollowResetEpisode` [238-261].

---

### N2 Watchdog & dispatch   @SYS-NAV-WATCHDOG      Primary file: KF2BotsFollowNavBase.uc
#### 1. PLAIN-ENGLISH SUMMARY
A per-slot time-sliced supervisor. Every follower runs a watchdog timer (phase-offset by slot so six bots never tick together). Each pass it checks, cheap-first, whether the leader is still valid, whether an in-flight move has timed out, whether the pawn is actually stuck, and whether a reachability query flipped. Any hit interrupts the move and re-enters `Dispatch`. `FollowRequestDispatch` performs the state re-entry, debounced.
#### 2. EXPLANATION
`FollowSlotPhase()` [280-282] = `(float(FollowSlotIndex) / FMax(float(Max(FollowSlotCount,1)), 0.0001f)) * FollowWatchdogPeriod` -- a deterministic per-slot offset inside one period (six followers can never land on the same offset). `FollowScheduleWatchdog()` [285-294]: `IterDelay = FollowSlotPhase() + (FRand() * FollowPhaseJitter)`; floor 0.01; `SetTimer(IterDelay, false, 'FollowWatchdogBegin')`. `FollowWatchdogBegin()` [296-299]: `SetTimer(FollowWatchdogPeriod, true, 'FollowWatchdog')` then `FollowWatchdog()`. `FollowCheckExit()` [308-311] is the overridable Hub hook (base `return false`; KF2Bot override at [Logic:839-873] routes the bot to an objective/trader by setting `bFollowExitPending` + `FollowExitState`). `FollowWatchdog()` [318-410] runs in strict cheap-first order:
- GATE: `!bEnableAdvancedLocomotion || !IsInState('FollowingLeader')` --> `ClearTimer('FollowWatchdog')` + return [327-331].
- `FollowCheckExit()` true --> return [334-337] (Hub-directed exit; state's Dispatch does the GotoState).
- Yield in-flight: `bFollowYielding` and now >= `FollowYieldEndTime` --> `bFollowYielding=false` + `GotoState('FollowingLeader','Dispatch')`; always return [340-346] (bounds `MoveTo`-style hold that has no native timeout).
- Hold/Sleep: `!bFollowMoveActive || Pawn == None` --> return [349-352].
- Dispatch already requested: `bFollowDispatchPending` --> `FollowRequestDispatch()` + return [354-357].
- (1) leader validity/teleport: `!FollowRefreshLeader() || bFollowLeaderJumped` --> clear jumped flag + `FollowRequestDispatch()` + return [360-365].
- (2) per-leg timeout (AUDIT 4.6, node legs only): `!bFollowDirectActive && (now - FollowMoveStartTime) > FollowLegTimeout` --> `FollowOnStuck('Timeout')` + return [368-372].
- (3) displacement-window stuck (not instantaneous Velocity): when grounded and `(now - FollowStuckRefTime) >= FollowStuckWindow`, compare `VSizeSq(Pawn.Location - FollowStuckRefLoc)` vs `FollowStuckMinMove2`; below --> `FollowOnStuck(FollowGuessStuckCause())` + return. Above --> if `VSizeSq(Pawn.Location - FollowRetryAnchorLoc) > FollowRetryResetDist2` reset `FollowRetries`/`FollowBlocksThisEpisode` + re-anchor [375-393].
- (4) budgeted native reachability: `IterReach = FollowCheckReachable(false)`; `now >= FollowForcePathUntil && IterReach != bFollowDirectActive` --> `FollowRequestDispatch()` (direct<->path flip) + return [396-401].
- (5) AUDIT 4.1 stale route: `!IterReach && !bFollowRouteStale && VSizeSq(leader - FollowLastLeaderPathLoc) > FollowRepathDistance2` --> `bFollowRouteStale = true` [404-409].
`FollowRequestDispatch()` [416-434]: no-op if `!bFollowMoveActive` (state-code callers already inactive --> GotoState never issued from running state code); debounced by `FollowNextInterruptTime` (`now < FollowNextInterruptTime` --> set `bFollowDispatchPending`, retried next tick); else `FollowNextInterruptTime = now + FollowInterruptMinGap`, clear pending, `` `log `` and `GotoState('FollowingLeader','Dispatch')`.
#### 3. LOGIC PIPELINE
FollowScheduleWatchdog --> one-shot 'FollowWatchdogBegin' --> looping 'FollowWatchdog'. Each tick: gate --> exit --> yield-bound --> hold --> dispatch --> (1) leader --> (2) leg timeout --> (3) stuck --> (4) reach flip --> (5) stale. Any hit --> FollowRequestDispatch --> GotoState Dispatch.
#### 4. INPUTS / OUTPUTS
Input: watchdog timer, `FollowMoveStartTime`, `FollowStuckRefLoc/Time`, `FollowLegTimeout`, leader/pawn locations. Output: `bFollowDispatchPending`, `FollowNextInterruptTime`, `FollowRetries`/`FollowBlocksThisEpisode` reset, `bFollowRouteStale`, `GotoState(...,'Dispatch')`. Never writes Hub state.
#### 5. FLOW   @FLOW-NAV-WATCHDOG
```
TIMER 'FollowWatchdog' (period FollowWatchdogPeriod, slot-phase offset)
| GATE: !flag || !IsInState('FollowingLeader') --> ClearTimer + return [327]
? FollowCheckExit() [334]
   --> true  : Hub set bFollowExitPending; return (Dispatch does GotoState)
| bFollowYielding [340]
   ? now >= FollowYieldEndTime --> clear flag + GotoState('Dispatch') + return
   | else return (still yielding)
? !bFollowMoveActive || Pawn==None --> return [349]   (HOLD/Sleep)
? bFollowDispatchPending --> FollowRequestDispatch() + return [354]
| (1) LEADER [360]: !FollowRefreshLeader() || bFollowLeaderJumped
   --> clear jumped; FollowRequestDispatch(); return
| (2) LEG TIMEOUT [368]: !bFollowDirectActive && now-moveStart > FollowLegTimeout
   --> FollowOnStuck('Timeout'); return
| (3) STUCK WINDOW [375] (grounded && now-stuckRef >= FollowStuckWindow)
   ? movedSq < minMoveSq --> FollowOnStuck(FollowGuessStuckCause()); return
   ? movedSq > retryResetDist^2 --> reset retries/blocks + re-anchor
| (4) REACH FLIP [396]: now>=forcePathUntil && reach != directActive
   --> FollowRequestDispatch(); return
| (5) STALE ROUTE [404]: !reach && !stale && leaderDelta > RepathDist^2
   --> bFollowRouteStale = true
FOLLOWREQUESTDISPATCH [416]
? !bFollowMoveActive --> return (state-code no-op)
? now < FollowNextInterruptTime --> bFollowDispatchPending=true (retry next tick)
| else --> FollowNextInterruptTime=now+gap; log; GotoState('FollowingLeader','Dispatch')
```
#### 6. TECHNICAL REFERENCE
- Functions: `FollowSlotPhase` [280-282], `FollowScheduleWatchdog` [285-294], `FollowWatchdogBegin` [296-299], `FollowCheckExit` [308-311] (override [Logic:839-873]), `FollowWatchdog` [318-410], `FollowRequestDispatch` [416-434].
- Timers: one-shot `'FollowWatchdogBegin'` [293]; looping `'FollowWatchdog'` [297]. (Timer name `'FollowWatchdog'` matches the function name -- legal, timer names are name literals.)
- Edge cases: watchdog clears itself on flag-off/state-exit [327-331]; the reachability query is the only native call and is rate-limited via `FollowCheckReachable` (N3); stuck detection uses a displacement window, not `Pawn.Velocity`.
- SDK: `IsInState`, `ClearTimer`, `SetTimer`, `GotoState`, `WorldInfo.TimeSeconds` (PART 1.1); AUDIT 4.1/4.6 SDK cross-refs from `Bot_Navigation_Fixes.md`.
#### 7. WHERE TO FIX
- Change tick cadence / stagger: `FollowWatchdogBegin` [296-299], `FollowScheduleWatchdog` [285-294], `FollowWatchdogPeriod`.
- Change which conditions interrupt: the numbered steps in `FollowWatchdog` [318-410].
- Change interrupt debounce: `FollowRequestDispatch` [416-434] / `FollowInterruptMinGap`.

---

### N3 Leader tracking   @SYS-NAV-LEADER      Primary file: KF2BotsFollowNavBase.uc
#### 1. PLAIN-ENGLISH SUMMARY
Keeps a live, validated handle on the leader's pawn, detects respawns and teleports, measures the per-slot arrival radius, decides "arrived" with hysteresis, and runs the single rate-limited native reachability query for the whole layer.
#### 2. EXPLANATION
`FollowRefreshLeader()` [442-507]: re-resolves `FollowLeaderPawn` from `FollowLeaderCtrl`; on pawn change --> `FollowInvalidateRoute` + set `bFollowLeaderJumped` (respawn); grace handling -- a missing leader starts `FollowLeaderInvalidSince` and only flips to `FS_LeaderLost` after `FollowLeaderGraceTime` elapses; teleport detection needs a sample gap >= 0.2s, a jump > `FollowLeaderTeleportDist`, and a speed > `FollowLeaderTeleportSpeed` --> `FS_LeaderTeleported` + jumped flag. `FollowGetArrivalRadius()` [517-527] computes the per-slot arrival band from `FollowBaseOffset` + `FollowSlotRingStep` (slot ring). `FollowEvalArrived()` [531-580] is 2D+Z hysteresis: arrival requires being inside the arrival radius **and** within `FollowResumeMargin` (a bot already arrived doesn't re-trigger until it has left the resume band); sets `bFollowArrived`. `FollowCheckReachable(bool)` [587-640] is the **ONLY `ActorReachable` call site** in the layer: cached until `FollowNextReachCheckTime` (interval = `FollowReachIntervalDirect` when direct-active else `FollowReachIntervalPath`), skipped while airborne, with a fail-streak (`FollowReachFailStreak`) that promotes to path after `FollowReachFailsToPath` misses; writes `bFollowReachStable`/`bFollowReachKnown`.
#### 3. LOGIC PIPELINE
Watchdog --> FollowRefreshLeader (validate/teleport) --> [per Decide] FollowGetArrivalRadius/FollowEvalArrived (arrival) --> FollowCheckReachable (rate-limited native). All write local flags; only FollowCheckReachable spends a native query.
#### 4. INPUTS / OUTPUTS
Input: `FollowLeaderCtrl`, leader/pawn transforms, slot. Output: `FollowLeaderPawn`, `FollowLeaderInvalidSince`, `bFollowLeaderJumped`, `bFollowArrived`, `bFollowReachStable/known`, `FollowNextReachCheckTime`, `FollowReachFailStreak`, `FollowStatus` (LeaderLost/LeaderTeleported via `FollowSetStatus`, N8).
#### 5. FLOW   @FLOW-NAV-LEADER
```
FOLLOWREFRESHLEADER [442]
? leaderCtrl None || pawn None
   | start/hold FollowLeaderInvalidSince
   ? grace elapsed --> FS_LeaderLost (via SetStatus); return false
? pawn changed since last --> FollowInvalidateRoute + bFollowLeaderJumped=true
? teleport (sample gap >=0.2s && jump>TeleportDist && speed>TeleportSpeed)
   --> FS_LeaderTeleported + jumped flag
| else --> update sample loc/time; return true
FOLLOWEVALARRIVED [531]  (per Decide)
| r = FollowGetArrivalRadius()   [517]
? inside arrival radius && inside FollowResumeMargin
   --> bFollowArrived = true (hysteresis: needs to leave band first)
FOLLOWCHECKREACHABLE [587]  (ONLY ActorReachable site)
? now < FollowNextReachCheckTime --> return cached bFollowReachStable
? airborne --> skip native, keep cached
| else ActorReachable(leader) [native]
   | interval = directActive ? Direct : Path  -> FollowNextReachCheckTime
   ? reach --> reset failStreak
   ? !reach --> failStreak++ ; >= FollowReachFailsToPath --> promote to path
```
#### 6. TECHNICAL REFERENCE
- Functions: `FollowRefreshLeader` [442-507], `FollowGetArrivalRadius` [517-527], `FollowEvalArrived` [531-580], `FollowCheckReachable` [587-640].
- SDK: `ActorReachable` (PART 1.1) -- the single native reachability query for this file. Teleport heuristic constants: `FollowLeaderTeleportDist` (1200.0), `FollowLeaderTeleportSpeed` (4000.0), grace `FollowLeaderGraceTime` (2.0).
- Edge cases: grace window prevents a one-frame leader gap from flagging LeaderLost; reachability is skipped while `Pawn.Physics == PHYS_Falling`.
#### 7. WHERE TO FIX
- Teleport/respawn sensitivity: `FollowRefreshLeader` [442-507] + the three `FollowLeader*` constants.
- Arrival band: `FollowGetArrivalRadius` [517-527] + `FollowEvalArrived` [531-580] / `FollowResumeMargin`.
- Reachability rate: `FollowCheckReachable` [587-640] / `FollowReachInterval*`, `FollowReachFailsToPath`.

---

### N4 Path build   @SYS-NAV-PATH      Primary file: KF2BotsFollowNavBase.uc
#### 1. PLAIN-ENGLISH SUMMARY
Builds a snapshot route to the leader (the only `FindPathToward` call site in the layer, spent against a per-bot token so even failures cool down), steps the route node-by-node, and tracks move begin/end so a moving target can invalidate the route.
#### 2. EXPLANATION
`FollowBuildPath()` [645-688]: **ONLY `FindPathToward` call site** (one-arg form). Spends the path token **before** the call (`FollowNextPathTime = now + interval`; refuse if `now < FollowNextPathTime`); on a `None` result applies backoff x2 clamped to `[FollowPathFailBackoffMin, FollowPathFailBackoffMax]`; on success snapshots `RouteCache` --> `FollowRoute` (capped at `FollowMaxRouteNodes`), sets idx=0, backoff 0, `bFollowRouteStale=false`, `FollowLastLeaderPathLoc = leader` [667-688]. `FollowGetNextNode()` [692-721]: state-code only -- rewrites `Pawn.DestinationOffset` (zeroed first so a stale direct offset doesn't trip `ReachedDestination` early [703-704]); skips destroyed (`None`) nodes [711-715]; returns the node on `Pawn.ReachedDestination(node)` [716-719]. Move lifecycle: `FollowOnMoveBegin(bool bDirect)` [813-834] sets `moveActive`/`directActive`, `moveStart=now`; the stuck window is kept across short legs but restarted after a pause > 3x the window [820-828]; AUDIT 4.6: node-leg timeout = `FMax(0.5, 2.0 * Dist / GroundSpeed)` [830-833]. `FollowOnMoveEnd(bool bDirect)` [837-853]: AUDIT 2.5 native-consistent arrival -- `DestinationOffset` = arrival radius, `ReachedDestination(leader)` --> `bFollowArrived` (prevents a MoveToward re-spin on an already-reached leader) [841-852]. `FollowOnNodeMoveEnd(Actor)` [855-890]: calls `OnMoveEnd(false)`, zeroes `DestinationOffset`; same-node counting via `FollowNodeLast` -- on `ReachedDestination` count 0 + AUDIT 4.2 per-node moving-target repath (leader > 7682 from last target --> stale) [873-883]; else same-node count > `FollowSameNodeLimit` && `Velocity2 < 600.0` --> `FollowOnStuck('SameNode')` [885-888].
#### 3. LOGIC PIPELINE
Decide --> (stale/empty) FollowBuildPath --> FollowRoute array --> per pass FollowGetNextNode --> accel toward node (N9 PathMove) --> FollowOnNodeMoveEnd. Token `FollowNextPathTime` gates every build.
#### 4. INPUTS / OUTPUTS
Input: leader location, `FollowNextPathTime`, route cache. Output: `FollowRoute array`, `FollowRouteIdx`, `bFollowRouteStale`, `FollowNextPathTime` (token), `FollowLegTimeout`, `bFollowArrived`, `FollowNodeLast`/`FollowSameNodeCount`.
#### 5. FLOW   @FLOW-NAV-PATH
```
FOLLOWBUILDPATH [645]  (ONLY FindPathToward site)
? now < FollowNextPathTime --> refuse (token not yet available)
| spend token FIRST: FollowNextPathTime = now + interval (backoff-aware)
? FindPathToward(leader) == None            [native]
   --> backoff *= 2, clamp [FailBackoffMin, FailBackoffMax]; return false
| else snapshot RouteCache -> FollowRoute (cap FollowMaxRouteNodes)
   | idx=0; backoff=0; bFollowRouteStale=false; FollowLastLeaderPathLoc=leader [667-688]
FOLLOWGETNEXTNODE [692]  (state-code only)
| Pawn.DestinationOffset = vect(0,0,0)      [703] (kill stale direct offset)
? node destroyed (None) --> skip [711]
? Pawn.ReachedDestination(node) --> return that node [716]
| else advance idx; return next node (or None when exhausted)
FOLLOWONNODEMOVEEND [855]
| OnMoveEnd(false); DestinationOffset = 0
? ReachedDestination(node) --> sameNode=0; AUDIT 4.2 moving-target check
   ? leader > 768^2 from last target --> stale (repath next pass) [873]
? sameNodeCount > FollowSameNodeLimit && Velocity^2 < 600
   --> FollowOnStuck('SameNode') [885]
```
#### 6. TECHNICAL REFERENCE
- Functions: `FollowBuildPath` [645-688], `FollowGetNextNode` [692-721], `FollowOnMoveBegin` [813-834], `FollowOnMoveEnd` [837-853], `FollowOnNodeMoveEnd` [855-890].
- SDK: `FindPathToward` (one-arg, PART 1.1), `RouteCache`, `Pawn.DestinationOffset`, `Pawn.ReachedDestination` (AUDIT 2.5/4.2 SDK cross-refs). Constants: `FollowRepathDistance` 1224.0, `FollowNodeRepathDistSq` 589824.0 (=7682), `FollowMaxRouteNodes` 24, `FollowPathMinInterval` 0.75.
- Edge cases: token spent before the native call so a failure still cools down; route snapshot is capped; a destroyed node is skipped, not an error.
#### 7. WHERE TO FIX
- Path budget / backoff: `FollowBuildPath` [645-688] / `FollowPath*` constants.
- Node stepping / moving-target repath: `FollowGetNextNode` [692-721], `FollowOnNodeMoveEnd` [855-890].
- Leg timeout formula: `FollowOnMoveBegin` [830-833].

---

### N5 Decision engine   @SYS-NAV-DECIDE      Primary file: KF2BotsFollowNavBase.uc
#### 1. PLAIN-ENGLISH SUMMARY
The one place all movement branching happens. Each watchdog pass `FollowDecide` returns a single `FollowAction`; the state code only obeys it. Everything is ordered by priority -- safety first, then give-up, then escape, then arrival, then yield, then wait, then direct/path.
#### 2. EXPLANATION
`FollowDecide()` [727-807] returns, in strict priority order:
1. Pawn None/dead --> `FA_Wait` 0.5 [736-740].
2. `!FollowRefreshLeader()` --> `FA_Wait` 0.5 [741-745].
3. Refresh order anchor via `FollowGetOrderAnchor` (AUDIT_3B Step 5) [747-755].
4. Retries >= `FollowRetriesGiveUpAt` --> `FA_GiveUp` [756-759].
5. `bFollowEscaping` (until `FollowEscapeUntil`) --> `FA_Escape` [761-770].
6. `FollowEvalArrived()` --> `FS_Arrived` + `FA_Hold` (period + jitter) [771-776].
7. `bFollowYieldPending` --> `FA_Yield` [777-780].
8. `FollowRepathPauseUntil` active --> `FA_Wait` (remaining) [781-785].
9. `FS_Following`; `IterUsePath = forcePathUntil active || !CheckReachable` (AUDIT 4.1: no pathfind while in LOS) --> `FA_Direct` [787-795].
10. Stale/empty route: try `FollowBuildPath`; if refused AND route exhausted --> `FA_Wait` until the path token [797-805].
11. Else `FA_Path` [806-807].
#### 3. LOGIC PIPELINE
Watchdog/Dispatch --> FollowDecide --> single FollowAction --> Dispatch GotoState to the matching step (N9).
#### 4. INPUTS / OUTPUTS
Input: leader validity, retries, escape/yield/pause flags, arrival, reachability, route state. Output: one `EFollowAction` (written to `FollowAction`), plus side flags `FS_Arrived`/`FS_Following` and order-anchor state.
#### 5. FLOW   @FLOW-NAV-DECIDE
```
FOLLOWDECIDE [727]   (priority order; first match wins)
1 ? Pawn None/dead            --> FA_Wait 0.5      [736]
2 ? !FollowRefreshLeader()    --> FA_Wait 0.5      [741]
3 | refresh order anchor (FollowGetOrderAnchor) [747]
4 ? retries >= GiveUpAt       --> FA_GiveUp        [756]
5 ? bFollowEscaping           --> FA_Escape        [761]
6 ? FollowEvalArrived()       --> FS_Arrived; FA_Hold [771]
7 ? bFollowYieldPending       --> FA_Yield         [777]
8 ? repathPauseUntil active   --> FA_Wait(remaining) [781]
9 | FS_Following
  | usePath = forcePathUntil || !CheckReachable   (no pathfind in LOS) [791]
  ? !usePath                          --> FA_Direct    [794]
10? route stale/empty
   | BuildPath
   ? refused && route exhausted --> FA_Wait until path token [797-805]
11| else                          --> FA_Path        [806]
```
#### 6. TECHNICAL REFERENCE
- Function: `FollowDecide` [727-807]. Returns `EFollowAction` (N10).
- Priority is load-bearing: safety (1--2) > give-up (4) > escape (5) > arrival (6) > yield (7) > wait (8) > direct (9) > path (10--11). Reordering changes follow behaviour.
- Edge cases: rule 9 encodes AUDIT 4.1 (stay direct while in LOS, path only when unreachable); rule 10 avoids spinning on a route that was just refused by the token.
#### 7. WHERE TO FIX
- Reorder or add a follow behaviour: `FollowDecide` [727-807] (keep safety first).
- Give-up threshold: rule 4 / `FollowRetriesGiveUpAt`.
- Direct-vs-path policy: rule 9--10 / `FollowForcePathUntil` + `FollowCheckReachable`.

---

### N6 Stuck & wall escape   @SYS-NAV-STUCK      Primary file: KF2BotsFollowNavBase.uc
#### 1. PLAIN-ENGLISH SUMMARY
When a move jams, this layer guesses why (pawn vs wall vs unknown), escalates the retry ladder, forces a repath, and -- for a persistent wall -- physically drives the pawn off the wall along the hit normal before re-pathing. The node blacklist is a deliberate no-op (PLAN B): this class extends `AIController`, not `KFAIController`, so the KFAIController blacklist members are unreachable.
#### 2. EXPLANATION
`FollowGuessStuckCause()` [896-910]: bump < 1s ago --> `'Pawn'`; wall (non-Pawn) < 2s ago --> `'Wall'`; else `'Unknown'`. `FollowOnStuck(Name)` [915-959]: no-op if a repath pause is already running [923-926]; `Retries++` + `` `log `` [928-930]; AUDIT 4.3 local force-pause-and-repath (flag + 0.25 + FRand + slot-phase -- the SDK's `AICommand_Pause` is the wrong tool for a state-driven follower) [933-938]; a direct-jam --> `FollowForcePathUntil = now + FollowForcePathDuration` [941-944]; cause `'Pawn'` --> `bFollowYieldPending` (never blacklist) [946-947]; `'SameNode' || ('Wall'/'Unreachable' && retries >= FollowRetriesBlockAt)` --> `FollowTryBlockNode(FollowNodeLast)` [948-950]; resets node tracking + stuck ref; ends with `FollowRequestDispatch` [951-962]. `FollowTryBlockNode` [965-968] is the **PLAN B no-op**: `CreateTemporaryBlockedReach`/`Path` are `KFAIController` members (KFAIController.uc:984/1016 -- SDK, verify in PART 1) unreachable from `AIController`; the retry ladder survives but recovery degrades to repath-only. `FollowSetWallEscape` [1032-1049]: AUDIT 2nd-priority(a) -- no blacklist, so it physically drives off the wall along the normalized hit normal for `FollowEscapeDuration`; the next repath starts off-wall; `` `log ``.
#### 3. LOGIC PIPELINE
Watchdog(2/3) or node-move-end --> FollowOnStuck(cause) --> guess cause --> escalate ladder --> (force-path | yield-pending | TryBlockNode) --> FollowRequestDispatch --> next Decide (FA_Escape for wall, FA_Yield for pawn).
#### 4. INPUTS / OUTPUTS
Input: `FollowLastBumpTime`, `FollowLastWall/Time`, `FollowNodeLast`, `FollowRetries`. Output: `FollowRetries`/`FollowBlocksThisEpisode`, `FollowForcePathUntil`, `bFollowYieldPending`, `bFollowEscaping`/`FollowEscapeNormal`/`FollowEscapeUntil` (via `FollowSetWallEscape`), repath pause, `GotoState(...,'Dispatch')`.
#### 5. FLOW   @FLOW-NAV-STUCK
```
FOLLOWGUESSSTUCKCAUSE [896]
? bump < 1s ago            --> 'Pawn'
? wall (non-Pawn) < 2s ago --> 'Wall'
| else                       --> 'Unknown'
FOLLOWONSTUCK [915]
? repath pause already running --> no-op [923]
| Retries++ ; log [928]
| AUDIT 4.3 local force-pause-and-repath [933]
? direct-jam  --> FollowForcePathUntil = now + ForcePathDuration [939]
? cause 'Pawn'  --> bFollowYieldPending=true (NEVER blacklist) [946]
? 'SameNode' || ('Wall'/'Unreachable' && retries>=BlockAt)
   --> FollowTryBlockNode(FollowNodeLast)   [948]  (PLAN B no-op [965])
| reset node tracking + stuck ref; FollowRequestDispatch [951]
FOLLOWSETWALLESCAPE [1032]  (from HandleHitWall, N7)
| bFollowEscaping=true; FollowEscapeNormal=normalized hit normal
| FollowEscapeUntil = now + FollowEscapeDuration   (drive OFF wall, no blacklist)
```
#### 6. TECHNICAL REFERENCE
- Functions: `FollowGuessStuckCause` [896-910], `FollowOnStuck` [915-959], `FollowTryBlockNode` [965-968], `FollowSetWallEscape` [1032-1049].
- Constants: `FollowRetriesBlockAt` 5, `FollowRetriesGiveUpAt` 10, `FollowForcePathDuration` 2.0, `FollowEscapeDuration` 0.8.
- Edge cases: the blacklist is intentionally unavailable (PLAN B) -- a persistent blocker is handled by force-repath + wall-escape, not by blocking the node. `AICommand_Pause` is deliberately not used (state-driven follower).
#### 7. WHERE TO FIX
- Escalation thresholds: `FollowOnStuck` [915-959] / `FollowRetries*`.
- Wall-escape behaviour: `FollowSetWallEscape` [1032-1049].
- If KFAIController is later available: implement `FollowTryBlockNode` [965-968] (currently no-op).

---

### N7 Bump / yield / fail   @SYS-NAV-HANDLE      Primary file: KF2BotsFollowNavBase.uc
#### 1. PLAIN-ENGLISH SUMMARY
The event hook layer. The base engine events `NotifyHitWall`, `NotifyBump`, and `MoveUnreachable` are re-routed to this layer's handlers when (and only when) the flag is on and we are in `FollowingLeader`; otherwise they fall through to `Super`. The handlers turn raw hits/bumps into a yield sidestep or a stuck report, using a deterministic side choice so two yielding bots never pick the same side.
#### 2. EXPLANATION
`FollowOwnsEvents()` [974-976]: `bEnableAdvancedLocomotion && IsInState('FollowingLeader')`. `FollowHandleHitWall` [981-1025]: returning FALSE keeps native wall resolution (`PickWallAdjust`, AUDIT 3.3) [979-980]; debounce -- the same wall within `FollowWallDebounce` is ignored [991-994]; airborne --> true (swallow, no count) [996-999]; per-wall windowed counter (`FollowWallWindow`) [1001-1008]; when count >= `FollowWallHitThreshold` && `moveActive`: cause = `'Pawn'` if `Wall.IsA('Pawn')` else `'Wall'` --> `FollowOnStuck(cause)`; the non-Pawn case also calls `FollowSetWallEscape(HitNormal)` [1010-1023]. `FollowIsFriendly(Pawn)` [1051-1066]: leader, has a `PlayerController`, or whose controller is a `KF2BotsFollowNavBase`. `FollowShouldYieldTo(Pawn)` [1071-1089]: leader + humans always win; between bots the lower slot index holds ground and the higher yields; equal slots --> Name string compare (a misconfigured pair can't deadlock) [1071-1078]. `FollowHandleBump` [1092-1121]: non-friend --> false (legacy path); one reaction per `FollowBumpCooldown` [1107-1111]; a yield --> `FollowYieldAway` (2D), set `bFollowYieldPending`, `FollowRequestDispatch` [1115-1118]; returns true (swallow cascade). `FollowHandleMoveUnreachable` [1123-1146]: path-leg unreachable --> `FollowOnStuck('Unreachable')` [1130-1134]; direct unreachable: if `forcePathUntil` active ignore (AUDIT 6.4: never retry the same direct point), else force path + decorrelated `FollowNextPathTime` + stale + dispatch [1141-1145]. `FollowComputeYieldPoint` [1148-1192]: away vector (fallback away from leader); even slots step LEFT, odd slots RIGHT (two yielding bots never pick the same side) [1172-1178]; `PointReachable` check, flip side on fail [1181-1191]. Engine overrides `NotifyHitWall` [1225-1231], `NotifyBump` [1234-1240], `MoveUnreachable` [1243-1250]: `FollowOwnsEvents() ? handler : Super`.
#### 3. LOGIC PIPELINE
Engine --> NotifyHitWall/NotifyBump/MoveUnreachable --> FollowOwnsEvents gate --> handler --> (yield-pending | stuck) --> FollowRequestDispatch --> next Decide.
#### 4. INPUTS / OUTPUTS
Input: hit wall/normal, bumping pawn, unreachable target. Output: `bFollowYieldPending`, `FollowYieldAway`, wall counters (`FollowWallHitCount`, `FollowLastWall/Time`), `FollowRetries` (via OnStuck), `GotoState(...,'Dispatch')`. Returns true/false to control native fall-through.
#### 5. FLOW   @FLOW-NAV-HANDLE
```
ENGINE NOTIFYHITWALL [1225]
? !FollowOwnsEvents() [974] --> Super
| HandleHitWall [981]
? same wall within FollowWallDebounce --> ignore [991]
? airborne        --> return true (swallow) [996]
| per-wall windowed count++  [1001]
? count >= WallHitThreshold && moveActive
   | Wall.IsA('Pawn') ? OnStuck('Pawn') : OnStuck('Wall') + SetWallEscape(normal) [1010-1023]
ENGINE NOTIFYPUMP [1234]
? !FollowOwnsEvents() --> Super
| HandleBump [1092]
? !IsFriendly(bumper)  --> return false (legacy) [1092]
? now-lastBump < BumpCooldown --> return false (no re-react) [1107]
? ShouldYieldTo(bumper) [1071]  (leader/human win; higher slot yields; Name tiebreak)
   --> FollowYieldAway(2D) + bFollowYieldPending + RequestDispatch [1115]
| return true (swallow cascade)
ENGINE MOVEUNREACHABLE [1243]
? !FollowOwnsEvents() --> Super
| HandleMoveUnreachable [1123]
? path-leg unreachable        --> OnStuck('Unreachable') [1130]
? direct unreachable
   ? forcePathUntil active --> ignore (AUDIT 6.4) 
   | else force path + decorrelate NextPathTime + stale + dispatch [1141]
COMPUTEYIELDPOINT [1148]
| away vector (fallback: away from leader)
| even slot LEFT / odd slot RIGHT   [1174]
? PointReachable(side) --> use; else flip side [1181]
```
#### 6. TECHNICAL REFERENCE
- Functions: `FollowOwnsEvents` [974-976], `FollowHandleHitWall` [981-1025], `FollowIsFriendly` [1051-1066], `FollowShouldYieldTo` [1071-1089], `FollowHandleBump` [1092-1121], `FollowHandleMoveUnreachable` [1123-1146], `FollowComputeYieldPoint` [1148-1192]; engine overrides `NotifyHitWall` [1225-1231], `NotifyBump` [1234-1240], `MoveUnreachable` [1243-1250].
- Constants: `FollowWallHitThreshold` 5, `FollowWallWindow` 3.0, `FollowWallDebounce` 0.2, `FollowBumpCooldown` 0.5, `FollowYieldDist` 64.0.
- Edge cases: returning FALSE from `FollowHandleHitWall`/`FollowHandleBump` defers to native resolution (deliberate, AUDIT 3.3/6.4); the left/right side choice is deterministic per slot so two bots never collide on the same yield side.
#### 7. WHERE TO FIX
- Wall threshold / debounce: `FollowHandleHitWall` [981-1025] / `FollowWall*`.
- Yield policy: `FollowShouldYieldTo` [1071-1089], `FollowComputeYieldPoint` [1148-1192].
- Unreachable handling: `FollowHandleMoveUnreachable` [1123-1146].

---

### N8 Status & hub reporting   @SYS-NAV-STATUS      Primary file: KF2BotsFollowNavBase.uc
#### 1. PLAIN-ENGLISH SUMMARY
The single-writer bridge back to the Hub. Locomotion writes its own status and reports it through a mailbox hook; it never touches Hub state. `FollowOnGaveUp` reports that the retry ladder is exhausted -- the Hub (not Locomotion) decides regroup/teleport/hold.
#### 2. EXPLANATION
`FollowSetStatus()` [1198-1207]: no-op if the status is unchanged; writes `FollowStatus` then calls `FollowNotifyHub`. `FollowNotifyHub()` [1209-1212]: the base body is `` `log `` only; KF2Bot overrides it (Hub mailbox, [Base:1287-1312]) so the Hub is told of the new status without Locomotion writing Hub state. `FollowOnGaveUp()` [1216-1219]: `` `log ``; the Hub decides (regroup/teleport/hold). The SDK terminal-stuck "suicide" is deliberately **not** replicated here [1214-1215].
#### 3. LOGIC PIPELINE
Any status transition (LeaderLost/Teleported/Arrived/Blocked) --> FollowSetStatus --> (unchanged? skip) --> FollowNotifyHub (log base / Hub mailbox override) --> Hub reads mailbox, acts.
#### 4. INPUTS / OUTPUTS
Input: the new `EFollowStatus`. Output: `FollowStatus` (this layer's own field), then a notification to the Hub via `FollowNotifyHub`. Single-writer: Locomotion writes `FollowStatus`; the Hub reads it and owns any Hub-side reaction.
#### 5. FLOW   @FLOW-NAV-STATUS
```
SETSTATUS [1198]
? newStatus == FollowStatus --> no-op (no notify)
| FollowStatus = newStatus
| FollowNotifyHub [1209]
   | base:  `log only
   | KF2Bot override: Hub mailbox [Base:1287-1312]
ONGAVEUP [1216]
| `log ; Hub decides regroup/teleport/hold  (no suicide replicated [1214])
```
#### 6. TECHNICAL REFERENCE
- Functions: `FollowSetStatus` [1198-1207], `FollowNotifyHub` [1209-1212] (override [Base:1287-1312]), `FollowOnGaveUp` [1216-1219].
- Edge cases: the unchanged-status guard prevents mailbox spam; the base `FollowNotifyHub` is a pure log so the file is usable standalone.
#### 7. WHERE TO FIX
- Add/remove a reported status: the `EFollowStatus` enum (N10) + `FollowSetStatus` [1198-1207].
- Change how the Hub is told: `FollowNotifyHub` base [1209-1212] or the KF2Bot override [Base:1287-1312].

---

### N9 States   @SYS-NAV-STATE      Primary file: KF2BotsFollowNavBase.uc
#### 1. PLAIN-ENGLISH SUMMARY
Two states. `FollowingLeader` (advanced) is a `Dispatch` entry point that reads the `FollowAction` and re-enters one of eight thin substates; the substates only set `Pawn.Acceleration` and `Sleep` (no native mover -- the native-fatal workaround), then re-dispatch. `FollowingLeaderBasic` (flag-off) is a self-contained 0.25s-loop fallback with no watchdog/events/repath/blacklist.
#### 2. EXPLANATION
`FollowingLeader` [1257-1418]. `BeginState` [1259-1271]: `FollowResetEpisode`, move flags false, **`Pawn.Acceleration = 0`** (clears stale combat drive; Hold/Wait steps never set Acceleration) [1264-1270], `FollowScheduleWatchdog`, `` `log ``. `EndState` [1273-1280]: `ClearTimer` on both watchdog timers, move/yield flags false, `` `log ``. `Begin` [1282-1283] --> `Dispatch`. `Dispatch` label [1285-1337]: stale-resume guard (`!IsInState` --> **`Stop`**; UScript state functions can't `return`, KFAIController `Action_Idle` uses the same construct) [1286-1291]; move/dispatch flags false; **`bFollowExitPending`** --> `GotoState(FollowExitState)` + `Stop` [1293-1301]; `FollowAction = FollowDecide()`; then Goto DirectMove/PathMove/YieldStep/EscapeStep/HoldStep/GiveUpStep/WaitStep [1302-1337]. Substates: `WaitStep` [1342-1344] `Sleep(clamp(FollowWaitTime, MinLoopSleep, 1.0))`; `HoldStep` [1346-1352] `Acceleration 0` + Sleep; `DirectMove` [1354-1371] **Acceleration-based move, no native mover** -- KF2Bot's Tick combat-escape GotoState fires at any frame, and cancelling the native MoveToward mover mid-flight is the suspected native-fatal trigger [1355-1357]; anchor-active --> accel toward `FollowOrderAnchorLoc` (AUDIT_3B Step 5) else toward leader [1359-1368]; `Sleep(MinLoopSleep)`; `PathMove` [1373-1384] `node = FollowGetNextNode`, None --> Sleep+Dispatch else accel toward node; `EscapeStep` [1386-1396] `accel = FollowEscapeNormal x GroundSpeed`, stuck window NOT reset (a persistent corner still times out) [1387-1389]; `YieldStep` [1398-1409] clears `bFollowYieldPending`, `ComputeYieldPoint` --> accel toward yield point + `YieldHold` sleep [1399-1405] (the `bFollowYielding` window is set true-->false within the same pass; the watchdog bound applies across dispatch re-entry); `GiveUpStep` [1411-1417] `FS_Blocked` + `FollowOnGaveUp` + `Sleep(FollowGiveUpHold)` + reset retries/blocks. `FollowingLeaderBasic` [1427-1491] (AUDIT 6.7): no watchdog/events/repath/blacklist; a `Sleep(0.25)` hard floor caps it at <=4 `ActorReachable`/`FindPathToward` per second per bot so it can't spin [1425-1429]. `Begin` [1430-1490]: stale-resume guard (`Stop`) [1433-1436]; exit-pending --> `GotoState`+`Stop` [1437-1443]; Pawn None/`!RefreshLeader` --> `Sleep(0.5)` [1444-1447]; `Acceleration 0` [1448-1450]; `EvalArrived` --> `Sleep(0.3)` [1451-1454]; order-anchor refresh [1455-1462]; `ActorReachable` --> accel toward anchor (if active) else leader [1463-1472]; else `FindPathToward(leader)` first node --> accel toward it [1473-1483]; `Sleep(0.25)`.
#### 3. LOGIC PIPELINE
FollowStart --> state entry --> BeginState (reset + accel 0 + schedule watchdog) --> Begin --> Dispatch --> (exit? stop) --> FollowAction --> substate --> Sleep --> Dispatch ... (loop). Flag-off: single 0.25s loop in `FollowingLeaderBasic`.
#### 4. INPUTS / OUTPUTS
Input: `FollowAction` (from Decide), order anchor, node (from path). Output: `Pawn.Acceleration`, `Sleep` pacing, watchdog timers, `GotoState` (substate hops, exit GotoState, `Stop`). Never writes Hub state.
#### 5. FLOW   @FLOW-NAV-STATE
```
STATE FollowingLeader [1257]  (advanced)
BEGINSTATE [1259]
| ResetEpisode; move flags false; Pawn.Acceleration = 0 [1264]
| FollowScheduleWatchdog
BEGIN [1282] --> DISPATCH
DISPATCH [1285]
? !IsInState (stale resume) --> Stop [1286]
| move/dispatch flags false
? bFollowExitPending --> GotoState(FollowExitState) + Stop [1293]
| FollowAction = FollowDecide()
| switch FollowAction [1302]
   FA_Direct --> DirectMove [1354]
   FA_Path   --> PathMove  [1373]
   FA_Yield  --> YieldStep [1398]
   FA_Escape --> EscapeStep[1386]
   FA_Hold   --> HoldStep  [1346]
   FA_GiveUp --> GiveUpStep[1411]
   FA_Wait   --> WaitStep  [1342]
  (each substate: set Acceleration + Sleep, then re-Dispatch)
ENDSTATE [1273]
| ClearTimer x2; move/yield flags false

STATE FollowingLeaderBasic [1427]  (flag-off, AUDIT 6.7)
BEGIN [1431]  (single 0.25s loop, <=4 native/s)
? !IsInState            --> Stop [1433]
? bFollowExitPending    --> GotoState + Stop [1437]
? Pawn None/!RefreshLeader --> Sleep(0.5) [1444]
| Acceleration = 0 [1448]
? EvalArrived           --> Sleep(0.3) [1451]
| refresh order anchor [1455]
? ActorReachable(leader) --> accel toward anchor/leader [1463]
| else FindPathToward(leader) first node -> accel toward it [1473]
| Sleep(0.25)  (hard floor)
```
#### 6. TECHNICAL REFERENCE
- States: `FollowingLeader` [1257-1418], `FollowingLeaderBasic` [1427-1491]. Substate labels: Dispatch [1285-1337], WaitStep [1342-1344], HoldStep [1346-1352], DirectMove [1354-1371], PathMove [1373-1384], EscapeStep [1386-1396], YieldStep [1398-1409], GiveUpStep [1411-1417].
- SDK: `BeginState`/`EndState`/`Begin`/`GotoState`/`Sleep`/`Stop`/`IsInState` (PART 1.1). `Pawn.Acceleration` written directly (no native mover).
- Edge cases: `Dispatch` uses `Stop` (not `return`) for the stale-resume guard because state functions can't return; DirectMove avoids the native mover on purpose (native-fatal workaround, [1355-1357]); EscapeStep intentionally leaves the stuck window un-reset.
#### 7. WHERE TO FIX
- Substate behaviour: the individual labels in `FollowingLeader` [1257-1418].
- Entry/teardown: `BeginState` [1259-1271] / `EndState` [1273-1280].
- Flag-off path: `FollowingLeaderBasic` [1427-1491].
- Move method (accel vs native): `DirectMove` [1354-1371] (see [1355-1357] comment).

---

### N10 Enums & config   @SYS-NAV-CONFIG      Primary file: KF2BotsFollowNavBase.uc
#### 1. PLAIN-ENGLISH SUMMARY
The two enums that define every follow decision (`EFollowAction`) and every reported status (`EFollowStatus`), the single feature flag, and the `defaultproperties` block that sets all tunables.
#### 2. EXPLANATION
`EFollowAction` [35-44]: `FA_Hold` (arrived, idle in hysteresis band), `FA_Direct` (move toward leader pawn), `FA_Path` (walk the snapshot route node-by-node), `FA_Escape` (back off a persistent wall, then re-evaluate), `FA_Yield` (short sidestep for a friendly bump), `FA_Wait` (nothing safe this pass -- budget/pause/no leader), `FA_GiveUp` (retry ladder exhausted --> report to Hub). `EFollowStatus` [46-54]: `FS_Idle`, `FS_Following`, `FS_Arrived`, `FS_Blocked`, `FS_LeaderLost`, `FS_LeaderTeleported`. Feature flag `bEnableAdvancedLocomotion` [59] default `true` [1496]. `defaultproperties` [1494-1552]: Leader -- `FollowLeaderGraceTime=2.0`, `FollowLeaderTeleportDist=1200.0`, `FollowLeaderTeleportSpeed=4000.0`; Slots/arrival -- `FollowSlotIndex=0`, `FollowSlotCount=1`, `FollowBaseOffset=96.0`, `FollowSlotRingStep=64.0`, `FollowResumeMargin=96.0`, `FollowZTolerance=128.0`; Time-slicing -- `FollowWatchdogPeriod=0.25`, `FollowPhaseJitter=0.03`, `FollowReachIntervalDirect=0.25`, `FollowReachIntervalPath=0.5`, `FollowReachFailsToPath=2`, `FollowMinLoopSleep=0.05`, `FollowInterruptMinGap=0.15`; A* budget -- `FollowPathMinInterval=0.75`, `FollowPathFailBackoffMin=0.5`, `FollowPathFailBackoffMax=4.0`, `FollowRepathDistance=1224.0`, `FollowNodeRepathDistSq=589824.0` (=7682), `FollowForcePathDuration=2.0`, `FollowMaxRouteNodes=24`; Stuck -- `FollowStuckWindow=1.5`, `FollowStuckMinMove=32.0`, `FollowSameNodeLimit=20`; Wall/bump -- `FollowWallHitThreshold=5`, `FollowWallWindow=3.0`, `FollowWallDebounce=0.2`, `FollowBumpCooldown=0.5`, `FollowYieldDist=64.0`, `FollowYieldHold=0.3`, `FollowYieldTimeout=0.75`, `FollowEscapeDuration=0.8`; Retry ladder -- `FollowRetriesBlockAt=5`, `FollowRetriesGiveUpAt=10`, `FollowRetryResetDist=384.0`, `FollowMaxBlocksPerEpisode=2`, `FollowBlockMinGap=2.0`, `FollowGiveUpHold=2.0`. `FollowExitState="PickNextMove"` [1497].
#### 3. LOGIC PIPELINE
Enums are read by `FollowDecide` (N5) and `FollowSetStatus` (N8); `bEnableAdvancedLocomotion` gates every advanced path (N2 gate, N9 state choice, N7 event ownership); the defaultproperties block is the single tuning surface.
#### 4. INPUTS / OUTPUTS
Input: config file (if any) overriding the defaults. Output: all tunables for N2--N9. Note: three config vars are **dead** (declared + defaulted, unused in all 5 mod files, grep-verified): `FollowNextBlockTime` [180], `FollowBlockMinGap` [181], `FollowMaxBlocksPerEpisode` [179] (defaults [1549-1550]) -- see Appendix D.
#### 5. FLOW   @FLOW-NAV-CONFIG
```
DECIDE (N5) consumes EFollowAction
SETSTATUS (N8) consumes EFollowStatus
bEnableAdvancedLocomotion [59]
| true  --> FollowingLeader (advanced) + events + watchdog
| false --> FollowingLeaderBasic (0.25s loop) + native fall-through
```
#### 6. TECHNICAL REFERENCE
- Enums: `EFollowAction` [35-44], `EFollowStatus` [46-54]. Flag: `bEnableAdvancedLocomotion` [59], default `true` [1496]. `defaultproperties` [1494-1552].
- Values above are taken verbatim from [1494-1552] (see PART 2 constants registry for the authoritative cross-file list).
- Edge cases: `FollowExitState` = `"PickNextMove"` [1497] (the state `bFollowExitPending` routes to); dead config keys flagged for Appendix D.
#### 7. WHERE TO FIX
- Add a follow behaviour: extend `EFollowAction` [35-44] + a case in `FollowDecide` (N5) + a substate (N9).
- Add a reported status: extend `EFollowStatus` [46-54] + `FollowSetStatus` (N8).
- Tune any follow behaviour: `defaultproperties` [1494-1552].
- Toggle the whole advanced layer: `bEnableAdvancedLocomotion` [59]/[1496].

# PART 6 -- Boundaries & Single-Writer Rules

The Echelon HCA is five classes split by ownership: `KF2BotsMut` (roster / squad /
objective truth), `KF2BotBase` (hub behaviour-tree states), `KF2BotLogic` (hub
priority decisions), `KF2Bot` (hub intent emission), and `KF2BotsFollowNavBase`
(locomotion). This part re-verifies every cross-file boundary call and states the
single-writer rule for every piece of shared state. Every line below was re-read
from source in this pass; the rule columns name the one writer.

## 6.1 Cross-file call matrix   @SYS-P6-BOUNDARY

| Caller file | Called file | Symbol | Caller site | Definition site | Data moved |
|---|---|---|---|---|---|
| Bot | Nav | `FollowStart(Leader)` | `Bot:131` (SquadLeader), `Bot:140` (RegroupAttach), `Bot:153` (RegroupHoldLeader) | `Nav:198` | sets `FollowLeaderCtrl` `Nav:214` |
| Logic | Nav | `FollowStart(Leader)` | `Logic:780` (IterAttachCtrl), `Logic:1260` (Leader) | `Nav:198` | sets `FollowLeaderCtrl` `Nav:214` |
| Mut | Nav | `FollowSetSlot(idx,count)` | `Mut:511` in `SyncSquadLeaders()` `Mut:471` | `Nav:223` | writes `FollowSlotIndex` `Nav:225`, `FollowSlotCount` `Nav:226` |
| Base | Mut | `IsSquadInObjectivePhase(B)` | `Base:2539` (inside `FollowGetOrderAnchor` `Base:2530`) | `Mut:1645` | read-only squad phase |
| Base | Mut | `GetSlotLocation(B)` | `Base:2543` (inside `FollowGetOrderAnchor` `Base:2530`) | `Mut:1657` | read-only slot location |
| Bot | Mut | `MoveSquadMembers(a,b)` | `Bot:125` (regroup re-parent) | `Mut` roster fns | mutates `Fireteams` (Mut-owned) |
| Base | Mut | `RegisterBot(bot)` | `Base:432` (self-reg in PreBeginPlay) | `Mut:334` | adds to `ActiveBots`; stamps `WdLastHubContactTime` `Mut:340` |
| Base | Mut | `UnregisterBot(bot)` | `Base:469` | `Mut:343` | removes from `ActiveBots` |
| Nav | Base | `FollowNotifyHub(status)` | `Nav:1205` (from `FollowSetStatus` `Nav:1198`) | base `Nav:1209`, override `Base:1287` | status callback; override may set hub intent |
| Nav | Logic(via Base) | `FollowCheckExit()` | `Nav:333` (from `FollowWatchdog` `Nav:318`) | base `Nav:308`, override `Logic:839` | override may set hub intent |

## 6.2 Single-writer rules   @SYS-P6-BOUNDARY

| Shared state | Owner / writer | Readers | Rule |
|---|---|---|---|
| `FollowStatus` `Nav:190` | Locomotion only -- `FollowSetStatus` `Nav:1204` | hub via `FollowNotifyHub` `Base:1287` | Hub never writes `FollowStatus` directly. The source comment at `Nav:190` states the rule: "Hub reads this; only Locomotion writes it." |
| `FollowLeaderCtrl` | Locomotion, via `FollowStart` `Nav:198` (commanded by hub) | Nav loop | Locomotion never picks its own leader; it is always set by a hub `FollowStart` call (Bot / Logic). |
| `FollowSlotIndex` / `FollowSlotCount` | Locomotion, via `FollowSetSlot` `Nav:223` (commanded by Mut `Mut:511`) | Nav loop, `Mut:1664` (read) | Slot is assigned by the Mut roster hook only. |
| `FollowExitState` / `bFollowExitPending` (hub intent) | hub-side override code: `Base:1308` `Base:1309`, `Logic:849` `Logic:865` | Locomotion Dispatch `Nav:1301`--`Nav:1311`, `Nav:1438`--`Nav:1443` | Locomotion invokes the virtual override; the hub side writes the intent; Locomotion then `GotoState`s out. Locomotion never sets its own exit. |
| `SquadOrders` / `Fireteams` / `ActiveBots` | Mut only (`SyncSquadLeaders` `Mut:471`, `EvaluateSquadPhase` `Mut:1672`, `RegisterBot` `Mut:334`, `ShuffleActiveBots` `Mut:518`, `PruneInvalidBots`) | Bot/Nav via read-only `mut.GetSlotLocation` `Mut:1657`, `mut.IsSquadInObjectivePhase` `Mut:1644` | Bot/Nav must not mutate squad arrays; they read through the Mut getters. |
| `WdLastHubContactTime` `Base:400` | multi-writer by design: `Mut:340` (register init), `Mut:1939` (contact), `Logic:852` `Logic:868` (FollowCheckExit) | watchdog `Logic:664` | A stamp (last-write-wins); readers only. |
| `WdLastMoveIntentTime` | hub `PickCombatStyle` `Base:2131` | move-intent watchdog | hub stamp, readers only. |
| `NextShoppingTime` `Base:150` | `Bot:1641` (give-up cooldown), `Bot:1683` (+60), `Base:541` / `Mut:2114` (reset) | `Bot:77` `Bot:245`, `Logic:846` | hub-owned timer; readers only. |
| `bEnableAdvancedLocomotion` `Nav:58` (default `Nav:1496`) | config only | gates `Nav:327` (watchdog), `Base:2152` (PickCombatStyle early-return), state entry | Feature flag: `false` routes through native behaviour, `true` (default) enables the follower states. |

## 6.3 Intent channel (hub --> locomotion)   @SYS-P6-BOUNDARY

There is no shared intent struct. The hub drives locomotion three ways, all verified
call-by-call above:

1. **Command calls.** The hub calls `FollowStart` (Bot `Bot:131` `Bot:140` `Bot:153`;
   Logic `Logic:780` `Logic:1260`) and the Mut roster calls `FollowSetSlot` (`Mut:511`).
   Locomotion stores the result in its own vars. The hub never writes those vars
   directly.
2. **Hub intent fields.** `FollowExitState` / `bFollowExitPending` are written by the
   hub-side virtual overrides (`FollowNotifyHub` `Base:1287`, `FollowCheckExit`
   `Logic:839`) and consumed by the Locomotion Dispatch (`Nav:1301`--`Nav:1311`).
   This is the only "mailbox" in the system: hub writes, locomotion reads and
   `GotoState`s out of the follower state.
3. **Status callback (locomotion --> hub).** Locomotion writes `FollowStatus`
   (`Nav:1204`) then calls `FollowNotifyHub` (`Nav:1205` --> override `Base:1287`).
   For `FS_LeaderLost` / `FS_Blocked` the override sets the hub intent to
   `'PickNextMove'` (`Base:1308`--`Base:1309`) so the next Dispatch returns the bot to
   the decision hub.

## 6.4 Hub re-evaluation funnel   @SYS-P6-BOUNDARY

`PickCombatStyle` (`Base:2124`) is the single hub re-eval funnel. It stamps the
move-intent time (`Base:2131`), locks terminal bots into `VictoryDance`
(`Base:2138`--`Base:2142`), early-returns while a follower state is active
(`Base:2152`--`Base:2156`) so the follower's own watchdog drives re-eval, and otherwise
`GotoState('PickNextMove')` (`Base:2157`). The follower states own their re-eval
(watchdog + Dispatch); the hub funnel never yanks a following bot back into the
behaviour tree -- this was the flap that hammered the native pathfinder (see the crash
fix comment `Base:2144`--`Base:2151`).

# APPENDIX A -- DEPRECATION LEDGER

Items the old AUDIT_3B doc marked deprecated, re-verified against the current 5-file split. Kept only where the code still confirms the claim.

| # | Deprecated item | Status (re-verified) | Evidence |
|---|-----------------|----------------------|----------|
| A1 | Per-bot independent pathfinding | DEPRECATED -- bots no longer path independently; a single FollowNav locomotion system drives slot following. The Hub (Base) only writes follow order/anchor/slot state; locomotion is owned by Nav. | `FollowStart` calls [Bot:131,140,153] --> [Nav:198]; intent channel in sec6.3 |
| A2 | Uncoordinated random objective picking | DEPRECATED -- `GetBotObjective` now returns the squad's shared `GoalNav` instead of an independent random pick. Random pick survives only as a fallback when the bot argument is `None`. | [Mut:1970-1979] (comment "AUDIT_3B Step 3: return the caller's squad GoalPoint" + `return O.GoalNav;`); fallback `ValidPoints[Rand(ValidPoints.Length)]` [Mut:1967]; `final function NavigationPoint GetBotObjective(KF2Bot B)` [Mut:1953] |
| A3 | Private per-bot bail paths | DEPRECATED -- bail is squad-level: one `ObjectiveBailUntil` per squad, not per bot. | [Mut:35] (declaration), squad bail handling [Mut:1009,1328,1372,1457] |
| A4 | `KFAIController` blocked-reach machinery | NOT USABLE in this mod (Plan B). `KF2Bot` extends `AIController`, not `KFAIController`, so the node-blocking API is unreachable. A no-op seam exists for a future hook. | [SDK KFGame/Classes/KFAIController.uc:984] `CreateTemporaryBlockedPath`, [SDK KFGame/Classes/KFAIController.uc:1016] `CreateTemporaryBlockedReach`, [SDK KFGame/Classes/KFAIController.uc:6934] `state Action_Idle`; mod-side no-op seam `FollowTryBlockNode` [Nav:965-968]; Plan-B header comment [Nav:8-12] |
| A5 | `PHASE_SHOPPING` phase constant | PARTIALLY SUPERSEDED -- constant retained but the only remaining reference is the declaration itself; shopping is now routed through `PickMove` exit logic and the `GoShopping` state. | [Mut:80] `const PHASE_SHOPPING = 4;` (only occurrence); `GotoState('GoShopping')` [Bot:80,247]; `FollowExitState = 'GoShopping';` [Logic:848]; `state GoShopping` [Bot:1578] |
| A6 | Pre-split `KF2Bot.uc` single-file layout (8063 lines) | SUPERSEDED -- file split into the 5-file chain; the 8063-line metric no longer applies to any single file. | File metrics in PART 2.1; split documented in old doc "File Layout" (verbatim line-range move, chain Nav-->Base-->Logic-->Bot) |

# APPENDIX B -- GLOSSARY

Plain-English definitions of the terms used in this document.

| Term | Plain English |
|------|---------------|
| Hub | The decision layer. `KF2BotBase` runs the per-bot decision loop (`PickMove`): it chooses what a bot should do (fight, retreat, follow, shop) and writes the intent, but it never moves the bot itself. |
| Fireteam | A squad of 2 bots under one leader bot (the `Captain`). Fireteams share a `SquadOrder` and move as a unit. |
| Squad | The fireteam concept at the Mutator level -- `SquadOrders` entries indexed by `GroupID - 1`, each holding a leader, a shared goal point, and bail state. |
| Slot | A formation position relative to the squad leader. `FollowSlotIndex` / `FollowSlotCount` describe where in the ring a bot stands; the Nav system computes concrete ring offsets around the leader. |
| Anchor | The leader's position that the slot ring is computed around. Followers track the anchor, not the map objective. |
| Regroup | A phase in which a squad stops fighting and reassembles at a shared regroup point before continuing. Governed by `REGROUP_HOLD_DIST_SQ` hold distance. |
| SYG | "Should You Go" -- a distance-based gate (800-unit radius, 640000 u2) that decides whether a bot commits to an objective or holds. |
| Blacklist | A per-bot list of recently failed destinations (path failures, blocks) that the hub avoids retrying, so bots don't thrash at the same spot. |
| Plan B | The architectural choice to extend `AIController` directly instead of `KFAIController`, because KFAIController's node-blacklist API does not work for this mod's needs. |
| Intent | The hub's output: `FollowStart` (leader, order, anchor, slot index/count) plus follow-order/anchor/slot state that locomotion (Nav) reads and executes; Nav reports back through `FollowNotifyHub`. Hub writes, Nav reads -- never the reverse. |
| Locomotion | The Nav layer (`KF2BotsFollowNavBase`): the only code that actually moves pawns (follow, path, direct acceleration). |
| Captain | The leader bot of a fireteam. Its decisions (squad orders, path timing) drive the whole team. |
| GoalPoint / GoalNav | The squad's shared objective navigation point. All members of a squad converge on the same `GoalNav` (see A2). |
| Bail | A squad-level retreat from the objective for a timed window (`ObjectiveBailUntil`), after which the squad re-engages. |
| Watchdog | Timers that detect stalls (e.g. hub contact timeout, move-intent timeout) and force a state change so a bot can never softlock. |

# APPENDIX C -- CORRECTIONS LOG

Claims from the old AUDIT_3B document (or from in-code comments) that do NOT match the current code. Each entry: old claim --> what the code actually says.

| # | Old claim | What the code actually says | Evidence |
|---|-----------|------------------------------|----------|
| C1 | `KF2Bot.uc` is 8063 lines | `KF2Bot.uc` is now **2075** lines. 8063 was the pre-split total; the class chain is now `KF2BotBase` (4615) + `KF2BotLogic` (1377) + `KF2Bot` (2075). | PART 2.1 file metrics |
| C2 | File metrics: Mut 3037 / KF2Bot 8063 / Nav 1552 (3 files) | The codebase is now **5 files** (Mut 3037, Nav 1552, Base 4615, Logic 1377, Bot 2075). Mut and Nav counts are unchanged; KF2Bot split into three. | PART 2.1 file metrics |
| C3 | `NumBots` defaults comment "defaults (6 / 25 / 1.0 / 0.2)" | The defaultproperties comment is **stale**: the actual config default is **7** (`NumBots = 7;`), not 6. `var() config byte NumBots` [Mut:44]. | [Mut:196] vs stale comment [Mut:3033-3035] |
| C4 | `FindNearestNavPoint` / `FindNearestChokepoint` find the *nearest* point | Both iterate `WorldInfo.RadiusNavigationPoints(...)` and **return the FIRST hit**, not the nearest -- there is no distance sort. | `FindNearestNavPoint` [Mut:678-686], `FindNearestChokepoint` [Mut:688-703] |
| C5 | `CaptainPathTimer` / `CaptainPathLoop` re-evaluate paths | Both are **log-only placeholders**. `CaptainPathTimer` logs and does nothing else; `CaptainPathLoop` is a log-only stub. No path re-evaluation happens. | [Logic:809-816] (`EchelonLog("CaptainPathTimer: path re-evaluation")`), [Base:2691-2694] (log-only body), timer wiring [Base:448,3073,3219-3220] |
| C6 | `ShouldNadeEnemies` scoring guards against no-candidate | `BestScore` is **uninitialized** (`local float Score, BestScore;` -- relies on the float default of 0); the no-candidate guard is the inline `Best == none` check, unlike `PickRetreatMove` which uses an explicit `(Best == none) \|\| BestScore < Score` guard. | [Logic:265,288] vs [Logic:957,978] |
| C7 | Nav design rule: "Events and timers never call FindPathToward" (token-based pathing) | The header design rules describe a **superseded token approach**. `DirectMove` is **acceleration-based** and does not use `FindPathToward` at all; the in-code comment explains that cancelling a native `MoveToward` mover mid-flight was the suspected native-fatal trigger. The header is partially outdated. | Header rules [Nav:19-27]; `DirectMove` [Nav:1354-1371] with rationale comment [Nav:1355-1357] |
| C8 | `SetCharacterArch` runs before `SetTeam` | **Wrong order** -- `SetCharacterArch` MUST run **after** `SetTeam`: `SetTeam` fires `NotifyTeamChanged()`, which calls `SetCharacterArch(GetCharacterInfo())` (per the in-code comment). The native `NotifyTeamChanged` is only declared in the SDK (no body), so the snap-back behaviour is SDK-unverified (see D5). | [Mut:2512] `SetTeam`, comment [Mut:2515-2518], [Mut:2522] `SetCharacterArch`; [SDK KFGame/Classes/KFPawn.uc:1260] |
| C9 | Follow config vars `FollowMaxBlocksPerEpisode` / `FollowNextBlockTime` / `FollowBlockMinGap` are functional | They are **dead config**: declared [Nav:179-181] with defaults only for two of them [Nav:1549-1550] (`FollowNextBlockTime` has no default line), and are never read anywhere in the code. | Declarations [Nav:179-181]; defaults [Nav:1549-1550]; no other references |

# APPENDIX D -- OPEN QUESTIONS / UNVERIFIED

Items that cannot be fully resolved from the local source + SDK. Marked `(UNVERIFIED)` / `(INFERRED)` per the anti-hallucination rules.

| # | Item | Status |
|---|------|--------|
| D1 | `GrenadeTarget` state [Bot:1538-1576] has **no `GotoState` call site in any of the 5 files**. The related signal vars (`GrenadeTargetPawn` [Base:302]) and SL signal logic [Base:3398-3402,3512,3522] exist, but nothing in the mod enters this state. It may be reachable only via a native/external path. (UNVERIFIED how it is ever entered) |
| D2 | `GetItem` state [Bot:1718-1776] has no `GotoState` call site in the 5 files either; the only mod reference is `IsInState('GetItem')` [Base:4525]. It is presumably entered via the native pickup/pawn path. (SDK behaviour not verified) |
| D3 | `KFAIController` blocked-reach: SDK line numbers confirmed ([SDK KFGame/Classes/KFAIController.uc:984, 1016, 6934]), but whether the KFAIController path would actually work if used is not verifiable from local source -- Plan B was chosen because it does not. (SDK behaviour not verified) |
| D4 | `KFMutator` class file is **absent from the local SDK** (`Development\Src`), so any claim about KFMutator behaviour is "SDK behaviour not verified". |
| D5 | Native `NotifyTeamChanged` behaviour (team change resetting archetype, causing the Mr. Foster snap-back): only declared in the SDK, no body -- [SDK Engine/Classes/Pawn.uc:1436] `simulated function NotifyTeamChanged();`. The ordering guard comment [Mut:2515-2518] describes the behaviour but is a code comment, not a verified SDK fact. (SDK behaviour not verified) |
| D6 | Dead config vars `FollowMaxBlocksPerEpisode` / `FollowNextBlockTime` / `FollowBlockMinGap` [Nav:179-181]: intentional reserved knobs or leftover from the superseded token approach (C7)? No in-code answer. (UNVERIFIED intent) |
