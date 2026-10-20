class KF2BotBase extends KF2BotsFollowNavBase
hidecategories(Navigation);

struct FRouteDoorBlockade
{
    var KFDoorActor door;
    var NavigationPoint Path;
};

// ============================================================
// --- Rank data model: the echelon hierarchy (Grunt -> Squad Leader ->
//     Lieutenant -> Captain) and each bot's place in the chain of command ---
// ============================================================
enum EBotRank
{
    GRUNT,
    SQUAD_LEADER,
    LIEUTENANT,
    CAPTAIN,
};

var array<FRouteDoorBlockade> DoorPaths;
var array<NavigationPoint> BotBlockRoutes;
var byte PlayStyle;
var Actor AssignedAnchor;
var EBotRank	BotRank;
var KF2Bot	SquadLeader;
var vector	LastValidSquadLeaderPos;
var float	LastValidSLTime;
var int		BlockedCounter;
var bool		bPromotionGapTimerActive;
var int			GroupID;
var bool  bIsGroupLeader;
var bool  bIsAlphaCommander;

var bool  bSingleFileFormation;
var float LastCQBCheckTime;

var bool    bIsStuck;
var bool    bAttemptingUnweld;
var bool    bHasStuckBaseline;
var vector  LeaderLocation3SecAgo;
var float   LastStuckSampleTime;
var float   LastRouteDist;

const CQB_TRACE_RADIUS_SQ  = 90000.0;
const CQB_TRACE_INTERVAL   = 1.0;
const CQB_PROBE_DIST       = 150.0;
const STUCK_SAMPLE_INTERVAL = 3.0;
const STUCK_DIST_SQ         = 10000.0;
const DOOR_CHECK_RADIUS     = 200.0;
const SINGLE_FILE_SPACING = 130.0;
const PERIMETER_RADIUS    = 220.0;
const DEG_TO_RAD          = 0.0174532925;

// ============================================================
// Throttle & priority tuning constants: cadence gates and distance
// thresholds that keep per-bot work bounded so the squad stays within
// the single-threaded game-thread frame budget.
// ============================================================
const SYG_DISTANCE_SQ               = 1000000.0;  // P5: 1000u
const BOSS_HEALTH_THRESHOLD         = 5000;       // P7 boss classification

const RETREAT_ZED_RADIUS            = 500.0;      // P4
const RETREAT_ZED_TRIGGER_COUNT     = 4;
const RETREAT_ZED_CLEAR_COUNT       = 2;
const RETREAT_HEAVY_RADIUS          = 300.0;
const FOLLOWER_DRIFT_SQ             = 250000.0;   // 500u
const OBJ_BAIL_COOLDOWN             = 8.0;        // finding #3: unreachable-objective retry cooldown (s)
const FOLLOW_ESCAPE_COOLDOWN        = 1.5;        // follow-combat-escape debounce (s)
const HUNT_ZED_THRESHOLD            = 15;        // low-zed hunting trigger
const HUNT_SCAN_RADIUS              = 5000.0;    // active nearest-zed scan radius (units)
const GLOBAL_ZED_RADIUS             = 8000.0;    // approximate full-map zed scan
const GLOBAL_ZED_COUNT_INTERVAL     = 3.0;       // seconds between global zed scans

const TRIAGE_INTERVAL               = 2.0;        // P6
const VIP_TRIAGE_GATE_PCT           = 50.0;
const VIP_TRIAGE_BONUS_PCT          = 15.0;

// Healing overhaul (Obs 10): proactive heal thresholds. A pawn is "needy"
// when its health % is below HEAL_MAX_NEED_PCT (bot starts healing), and
// healing stops once the target reaches HEAL_MIN_NEED_PCT (no over-healing,
// conserves syringe ammo -- mirrors human players who top up on cooldown).
const HEAL_MAX_NEED_PCT             = 80.0;
const HEAL_MIN_NEED_PCT             = 60.0;

const ENEMY_SCAN_INTERVAL           = 0.5;        // P7
const ENEMY_SCAN_RADIUS             = 1500.0;
const SPOT_RADIUS_SQ                = 4000000.0;  // 2000u
const LEASH_DROP_DIST_SQ            = 5760000.0;  // 2400u
const LEASH_COOLDOWN                = 2.0;

const ZED_COUNT_INTERVAL            = 1.0;        // P4 perf gate

const OBJECTIVE_HAZARD_RADIUS       = 800.0;      // P5
const OBJECTIVE_HAZARD_ZED_COUNT    = 3;
const SIREN_CHECK_RADIUS            = 1200.0;

const TRADER_MAX_RETRIES            = 3;          // P9
const TRADER_GIVEUP_COOLDOWN        = 10.0;

// AUDIT_3B Step 6: idle watchdog budget.
const AUDIT_INTENT_TIMEOUT          = 10.0;       // stale move-intent signal (s)
const AUDIT_HUB_TIMEOUT             = 20.0;       // stale hub-contact signal (s)
const AUDIT_IDLE_STUCK_DELTA        = 50.0;       // displacement floor (u)
const AUDIT_ATTACH_RADIUS           = 3000.0;     // nearest-leader attach radius (u)
const AUDIT_WD_PERIOD               = 1.5;        // per-bot evaluation period (s)
const AUDIT_WD_STEP_COOLDOWN        = 5.0;        // between escalation steps (s)

// AUDIT_3B Step 7 (regroup, doc s2.4): 5s regroup window, guaranteed
// 6s hard timeout; hold band of 100u around the leader. Attach radius
// reuses AUDIT_ATTACH_RADIUS (3000u, same as idle-watchdog step 2).
const REGROUP_DURATION              = 5.0;
const REGROUP_HARD_TIMEOUT          = 6.0;
const REGROUP_HOLD_DIST_SQ          = 10000.0;   // 100u^2

// Trader round roam/reform: while the trader is open the squad tether is
// dropped and each bot roams within TRADER_ROAM_RADIUS (units) of the trader;
// the final TRADER_REFORM_REMAINING seconds re-engage the tether so the squad
// re-forms before the trader closes.
const TRADER_ROAM_RADIUS = 3000.0;
const TRADER_ROAM_RADIUS_SQ = 9000000.0;
const TRADER_REFORM_REMAINING = 5.0;

var transient byte CallStack;
var byte MoveFlags;
var byte HealingStage;
var byte FailedMoveCount;
var byte DoshDropCounter;
var int CurrentLevel;
var Class<KFPerk> Perk;
var Class<KFWeapon> FavoriteWeapon;
var KF2BotsMut mut;
var KFCharacterInfo_Human CharacterArch;
var KFPawn_Human KPawn;
var KFPawn_Human PendingHeal;
var Pawn FollowingHuman;
var Pawn DonateHuman;
var KFInventoryManager KFInvManager;
var KFGameReplicationInfo KFGRI;
var transient KFWeap_HealerBase MedicGun;
var transient KFWeap_MedicBase RangeMedicGun;
var transient bool bHealFired;
var transient float LastHealFireTime;
var transient float LastCallTimer;
var transient float EndMoveTime;
var transient float SerpentineTime;
var transient float NextGrenadeTimer;
var transient float EnemyEncounterTime;
var transient float NextShoppingTime;
var transient float ObjectiveBailUntil;
// AUDIT_3B Step 4b: per-bot nav-node blacklist throttle (<=2 per
// episode, >=2s apart); reset on Restart and FinishObjective.
var transient float LastNodeBlockTime;
var int NodeBlockCount;
var transient float NextAdjustTime;
var transient float MovePauseTime;
var transient float TempBlockTime;
var transient float NextVictoryDance;
var transient float NextDoshShareTime;
var transient float GrabStartTime;
var transient int BreakFreeAttempts;
var transient float NextEscapeAttempt;
var transient bool bGrappleFailsafeTriggered;
var transient KFPickupFactory LastFactory;
var transient Vector PrevMovePos;
var NavigationPoint RandGoal;
var NavigationPoint ObjectiveGoal;
var NavigationPoint LastFailedMove;
var NavigationPoint TempBlockPath;
var Actor Target;
var bool bSerpentineMove;
var bool bSerpentLeft;
var bool bBossKillVictory;

// P1 -- terminal-state lock
var bool bInTerminalState;

// P4 -- Tactical Retreat
var bool  bIsRetreating;
var float LastZedCountTime;
var int   CachedZedCount;
var bool  bCachedHeavyZed;

// Follow-combat-escape debounce
var float LastFollowEscapeTime;

// Global zed count (low-zed hunting trigger)
var int   GlobalZedCount;
var float LastGlobalZedCountTime;

// [KF2BotsAudit] AUDIT_3B Stage 3: instrumentation state
var float AuditStateEntryTime;
var name  AuditStateEntryName;
var float AuditDwellTotal;
var float AuditLastLog_STATE_EXIT;
var float AuditLastLog_GOAL;
var float AuditLastLog_FOLLOWGATE;
var float AuditLastLog_GEN;
var float AuditLastLog_DWELLTOT;

// P8 EvaluateFollowerMove -- Retreat Paradox hold-position
var bool   bHasHoldPosition;
var vector HoldPosition;

// P6 -- triage throttle
var float LastTriageTime;

// P3 -- Dual-timer self-heal pacing system:
// SyringeRechargeEnd: 15s mechanical lockout (syringe recharge, absolute gate)
// HealPacingEnd: 30s behavioral pacing (bypassed by emergency < 50%)
var float SyringeRechargeEnd;
var float HealPacingEnd;
var float HealRetryAfter;
var int FailStreak;
var float landingDeadline;
var float equipDeadline;

// Obs 2 -- Random spawn gate: only freshly-spawned bots are teleported to
// ammo-crate positions. Cleared once the bot enters its first combat state.
var bool bJustSpawned;

// Bug 2 fix -- stores the base player name (without rank prefix) so
// RefreshRoleNameTag() can reconstruct the full name after rank changes.
var string BasePlayerName;

// P7 -- enemy scan throttle + leash cooldown
var float LastEnemyScanTime;
var float LastLeashDropTime;

// Trader body-block bounded retry: gives up shopping after too many blocked attempts
var int TraderRetryCount;

// --- Echelon command hierarchy: per-rank runtime state ---
// Overwatch leapfrog phase flag, toggled by the Captain on a fixed cadence so
// the squad alternates between holding cover and advancing.
var bool bOverwatchPhase;

// Grunt 2D offset tether: the anchor a grunt follows, plus the active/expiry
// state that gates whether the tether is currently applied.
var vector EngageAnchor;
var bool bEngageActive;
var float EngageExpireTime;

// Restricted-tick phase: while true, a grunt runs full per-frame processing
// (it is panicking); otherwise the grunt's Tick early-exits to save CPU.
var bool PanicActive;

// Cached path route for the bot's current objective leg.
var NavigationPoint CachedRoutePoint;

// Hierarchy links: the bot's subordinates and its immediate supervisor.
var array<KF2Bot> Subordinates;
var KF2Bot Supervisor;

// Pathfinding budget: bounds nav-mesh queries per interval to avoid stalling
// the single-threaded pathfinding loop.
var int PathTokensUsed;
var float PathTokenResetTime;

// --- Formation & spatial navigation ---
const FORM_SCAN_DIST = 150.0;
const FORM_LINE_DIST = 650.0;

var name CurrentFormation;             // 'Arrowhead' | 'StaggeredColumn' | 'SingleFile' | 'LineFormation'
var name PendingFormation;             // debounce candidate
var byte PendingFormationCount;
var byte ScanMask;                     // last scan: 1=fwd 2=left 4=right 8=back (bit set = clear)
var int FormationEpoch;                // bumps on formation change / reroute; grunts re-seed variance
var int FormationYaw;                  // SL heading cached at 0.5s cadence (stable formation frame)
var float FormationHoldUntil;
var float LastRerouteTime;
var bool bRerouteRequested;
var bool bSquadCrouchHold;
var bool bHoldCrouching;
var Pawn InheritedEnemy;               // Line-formation inherited target (grunt)
var transient bool bFormationScanDeferred;
var transient float LastFormationScanTime;
var transient float NextFireLineCheck;
var transient bool bFireLineClear;
var transient Actor FireLineTarget;
var transient bool bOffsetCached;
var transient Vector CachedLocalOffset;
var transient int CachedOffsetEpoch;
var transient int CachedOffsetSlot;
var transient name CachedOffsetFormation;
var transient int LastFormationYaw;
var transient float LastOffsetUpdate;
var transient float LastHealthCheck;
var int GruntSlot;
// --- Weapon & combat discipline ---
const BOTFM_PRIMARY = 0;
const BOTFM_RELOAD = 2;
const BOTFM_BASH = 3;
const BOTFM_GRENADE = 4;

var Pawn SquadZedCache[16];
var byte SquadZedCount;

var bool GrenadeSignal;
var byte GrenadeThrowsLeft;
var Pawn GrenadeTargetPawn;
var float NextGrenadeSignalTime;

var int HearNoiseZedCount;
var float HearNoiseExpireTime;
var Vector LastNoiseLoc;
var bool bOutOfEffectiveRange;
var bool bFallbackWeapon;
var bool bFallbackHadSpare;
var byte BlockedShooterCount;
var float BlockedShooterWindowStart;
var float LineSuppressUntil;
var transient KFWeapon RangeCacheWeapon;
var transient float RangeCacheSq;
var float ShotgunEffectiveRangeUU;
var float FlamethrowerEffectiveRangeUU;
var float DefaultWeaponEffectiveRangeUU;
var transient float NextReloadAttempt;
var transient float NextWeaponSwitchTime;
var transient float NextFallbackPoll;
var transient KFWeapon FallbackPrimary;
var transient float FallbackSince;
var transient byte GrenadeAimTicks;
// --- Tactical squad maneuvers ---
const OW_TOGGLE_INTERVAL   = 1.5;
const OW_STUCK_TIME        = 1.0;
const OW_STUCK_MIN_DIST_SQ = 10000.0;
const OW_STUCK_MOVE_SQ     = 900.0;
const SW_ARRIVE_SQ         = 22500.0;
const SW_SCAN_AMP_DEG      = 15.0;
const SW_SCAN_OMEGA        = 1.5707963;
const SW_TWO_PI            = 6.2831853;
const SW_DEG_TO_URU        = 182.0444;
const CQB_BASH_SQ          = 14400.0;
const CQB_MID_SQ           = 32400.0;
const CQB_BASH_INTERVAL    = 0.8;
const CQB_STEPBACK_SPEED   = 100.0;
const COVER_RANGE_SQ       = 640000.0;
const RESCUE_RANGE_SQ      = 1000000.0;
const RESCUE_DURATION      = 5.0;
const HEAR_RANGE_SQ        = 4000000.0;

var float  OverwatchResetUntil;
var byte   StuckCounter;
var bool   GruntOverwatchPhase, bOverwatchAllMove, bOverwatchMoving, bOverwatchLOS, bGruntMeleeStyle;
var byte   OverwatchSlot;
var vector OverwatchOffset, OverwatchSamplePos, RescueLoc;
var float  OverwatchSampleTime, OverwatchStuckTime, NextOverwatchLOSTime;
var float  SectorScanPhase, SectorLastTime, NoiseGlanceUntil, NextBashTime, RescueUntil, StyleCrouchUntil;
var int    LastValidSquadLeaderYaw;

var KF2Bot SquadMembers[4];
var name   CurrentOrder;
var vector OrderAnchor;
// Squad leader references owned by the Lieutenant
var array<KF2Bot> SquadLeaders;

// --- Immersion, cohesion & inter-perk polish ---
const PANIC_MULT              = 2.0;
const PANIC_SCATTER_MIN       = 200.0;
const PANIC_SCATTER_MAX       = 400.0;
const RELOAD_DRIFT_DIST       = 100.0;
const RELOAD_DRIFT_LEASE      = 1.0;
const HUMAN_BOUND_INTERVAL    = 1.5;
const HUMAN_PUSH_DOT          = 0.5;
const HUMAN_MIN_SPEED_SQ      = 10000.0;
const HUMAN_LT_RANGE_SQ       = 250000.0;
const WEDGE_REAR_OFFSET       = 150.0;
const WEDGE_LEASE             = 2.5;
const EMOTE_RADIUS_SQ         = 22500.0;
const EMOTE_CHANCE            = 0.30;
const EMOTE_ROLL_COOLDOWN     = 6.0;
const BREATH_OMEGA            = 0.3;
const DRIFT_RATE              = 0.8333333;
const DRIFT_MIN_DIST_SQ       = 10000.0;
const DRIFT_MAX_TOTAL         = 300.0;

// Suppressive panic variance: per-bot multipliers that scale threat-scan speed
var float  PanicVarianceMultiplier, PanicScanSpeedMultiplier;
// Staggered reload drift: state for pulling the squad to a safe anchor while reloading
var bool   bWasReloading, bReloadDriftMove, bReloadPullClear;
var float  ReloadDriftUntil, ReloadPullStamp;
var vector ReloadDriftLoc, ReloadDriftOffset, ReloadPullAnchor, HoldAreaAnchor;
// Human-centric bounding: a temporary wedge the SL forms around a specific human
var bool   bWedgeActive;
var KFPawn_Human WedgeHuman;
var float  WedgeExpireTime;
// Trader emote echo: mirrors nearby human player emotes
var bool   bPlayingEmote;
var float  NextEmoteRollTime;
// Immersion polish: breathing phase, panic flash, and drift/hold state
var bool   bSLLoopSuspended;
var float  BreathingPhase, PanicFlashUntil, LastDriftTime, HoldDriftDist;
var vector PanicFlashLoc;
// AUDIT_3B Step 6: idle-watchdog per-bot signal + escalation bookkeeping
var bool   bWdEscalating;
var int    WdEscStep;
var float  WdLastMoveIntentTime;
var float  WdLastHubContactTime;
var float  WdLastStepTime;
var float  WdProgressGoalD2;
var vector WdIdleStartLoc;

simulated function PreBeginPlay()
{
    local Mutator M;

    M = WorldInfo.Game.BaseMutator;
    J0x3D:

    // End:0xA5 [Loop If]
    if(M != none)
    {
        mut = KF2BotsMut(M);
        // End:0x7A
        if(mut != none)
        {
            // [Explicit Break]
            goto J0xA5;
        }
        M = M.NextMutator;
        // [Loop Continue]
        goto J0x3D;
    }
    J0xA5:

    super.PreBeginPlay();
    ++WorldInfo.Game.NumBots;
    KFGRI = KFGameReplicationInfo(WorldInfo.GRI);
    SetTimer(0.5000000 + (FRand() * 0.5000000), true, 'EyeSightCheck');
    if (mut != None) mut.RegisterBot(KF2Bot(self));
    bJustSpawned = true;

    // AUDIT_3B Step 6: arm the idle-watchdog timer, staggered by squad id so
    // no two bots evaluate in the same frame (non-repeating; self re-arms).
    SetTimer(0.5 + (Max(GroupID, 0) * 0.1), false, 'IdleWatchdogTimer');

    // Rank-specific decision timers: each echelon level runs its own cadence,
    // with the Captain driving overwatch, the Lieutenant driving pathing,
    // and the Grunt running the restricted decision loop.
    if (BotRank == CAPTAIN)
    {
        SetTimer(5.0, true, 'ProcessOverwatchPhase');
    }
    if (BotRank == LIEUTENANT)
    {
        SetTimer(2.0, true, 'CaptainPathTimer');
    }
    if (BotRank == GRUNT)
    {
        SetTimer(1.5, true, 'GruntDecisionTimer');
    }

    // Immersion initialization: randomize the breathing phase and arm the
    // emote echo loop so squadmates mirror nearby human players.
    BreathingPhase = FRand() * 6.2831853;
    StartEmoteEchoTimer();
    //return;    
}

simulated function Destroyed()
{
    // Clear all rank timers on destruction so no orphaned decision loops
    // fire against a dead bot.
    ClearRankTimers();
    super(Controller).Destroyed();
    --WorldInfo.Game.NumBots;
    if (mut != None) mut.UnregisterBot(KF2Bot(self));
    //return;    
}

function InitPlayerReplicationInfo()
{
    local KFGameInfo KFGI;
    local KFPlayerReplicationInfo KFPRI;

    super(Controller).InitPlayerReplicationInfo();
    
    if(PlayerReplicationInfo != none)
    {
        PlayerReplicationInfo.bBot = false;
        PlayerReplicationInfo.bOnlySpectator = false;
        // Only set a placeholder name if the Mutator hasn't already assigned
        // a custom name via InitBotCharacter() — prevents clobbering the join
        // message broadcast with "Bot_XXXX".
        if(PlayerReplicationInfo.PlayerName == "")
        {
            PlayerReplicationInfo.PlayerName = "Bot_" $ Rand(9999);
        }
        
        KFPRI = KFPlayerReplicationInfo(PlayerReplicationInfo);
        if(KFPRI != none)
        {
            KFPRI.bHasSpawnedIn = true;
        }

        KFGI = KFGameInfo(WorldInfo.Game);
        if((KFGI != none) && KFGI.Teams[0] != none)
        {
            KFGI.SetTeam(self, KFGI.Teams[0]);
        }

        if(WorldInfo.GRI != none)
        {
            WorldInfo.GRI.AddPRI(PlayerReplicationInfo);
        }
    }
    
    if(mut != none)
    {
        mut.InitBotCharacter(KF2Bot(self));
    }
}

final function GiveWeaponDef(Class<KFWeaponDefinition> W)
{
    local Class<Weapon> WC;

    // End:0x11
    if(W == none)
    {
        return;
    }
    WC = Class<Weapon>(DynamicLoadObject(W.default.WeaponClassPath, Class'Core.Class'));
    // End:0xA3
    if(WC != none)
    {
        Pawn.InvManager.CreateInventory(WC);
    }
    //return;    
}

function Restart(bool bVehicleTransition)
{
    local KFPlayerReplicationInfo KFPRI;

    FollowingHuman = none;
    LastFactory = none;
    FavoriteWeapon = none;
    NextShoppingTime = WorldInfo.TimeSeconds - float(1);
    // End:0x168
    if((KFInventoryManager(Pawn.InvManager) != none) && Pawn.InvManager.Class != Class'KF2Bots.KFInventoryManager_Bot')
    {
        Pawn.InvManager.Destroy();
        Pawn.InvManager = Spawn(Class'KF2Bots.KFInventoryManager_Bot', Pawn);
        Pawn.InvManager.SetupFor(Pawn);
    }
    super(Controller).Restart(bVehicleTransition);
    // Reset rank to GRUNT on respawn: the Hub re-assigns the correct rank
    // via SyncSquadLeaders() on the next macro-tick. Without this, a bot
    // promoted to SQUAD_LEADER before death respawns as a leader, creating
    // duplicate leaders in the same fireteam (5-leader bug).
    BotRank = GRUNT;
    bIsGroupLeader = false;
    // Arm staggered rank timers after restart
    ArmRankTimers();
    // Reset weapon fallback state
    bFallbackWeapon = false;
    FallbackPrimary = none;
    NextGrenadeTimer = 0.0;
    Pawn.PeripheralVision = -0.2000000;
    Pawn.JumpZ = FMax(Pawn.JumpZ, 750.0000000);
    KPawn = KFPawn_Human(Pawn);
    KPawn.NumJumpsAllowed = 2;
    // End:0x264
    if(Pawn.Physics == 0)
    {
        Pawn.SetPhysics(2);
    }
    SetTimer(0.2000000 + (FRand() * 0.1000000), true, 'CheckGrabbed');
    KFInvManager = KFInventoryManager(Pawn.InvManager);
    // End:0x3B4
    if(KFInvManager != none)
    {
        // End:0x393
        if(Perk != none)
        {
            GiveWeaponDef(Perk.default.PrimaryWeaponDef);
            GiveWeaponDef(Perk.default.SecondaryWeaponPaths[Rand(Perk.default.SecondaryWeaponPaths.Length)]);
            GiveWeaponDef(Perk.default.KnifeWeaponDef);
            GiveWeaponDef(Perk.default.GrenadeWeaponDef);
        }
        KFInvManager.GrenadeCount = 2;
    }
    KFPRI = KFPlayerReplicationInfo(PlayerReplicationInfo);
    Pawn.bModifyReachSpecCost = false;
    Pawn.PathSearchType = 1; // PST_Constraint: forces nav-mesh-constrained paths (no impossible vertical jumps)
    // AUDIT_3B Step 4a: clear the stale goal on respawn (R8 orphan-goal fix).
    AuditGoalLog("GOAL_CLEAR", "Restart");
    ObjectiveGoal = none;
    ObjectiveBailUntil = 0.0;
    LastNodeBlockTime = 0.0;
    NodeBlockCount = 0;
    ValidateAndNudgeSpawn();
    GotoState('Roaming');
    // End:0x60D
    if(KPawn != none)
    {
        // End:0x60D
        if((Perk == Class'KFGame.KFPerk_Berserker') || Perk == Class'KFGame.KFPerk_FieldMedic')
        {
            KPawn.HealthMax = 100 + Min(CurrentLevel * 4, 100);
            KPawn.Health = KPawn.HealthMax;
            // End:0x588
            if(KFPRI != none)
            {
                KFPRI.PlayerHealthPercent = FloatToByte(float(KPawn.Health) / float(KPawn.HealthMax));
                KFPRI.PlayerHealth = KPawn.Health;
            }
            KPawn.MaxArmor = byte(100 + Min(CurrentLevel * 2, 150));
            // End:0x60D
            if(CurrentLevel > 20)
            {
                KPawn.Armor = KPawn.MaxArmor;
            }
        }
    }
    // End:0x63D
    if(KFPRI != none)
    {
        KFPRI.bHasSpawnedIn = true;
    }
    //return;    
}

function NotifyTakeHit(Controller InstigatedBy, Vector HitLocation, int Damage, Class<DamageType> DamageType, Vector Momentum)
{
    // End:0x5E
    if((InstigatedBy != none) && InstigatedBy.Pawn != none)
    {
        SetEnemy(InstigatedBy.Pawn);
    }
    //return;    
}

function SeePlayer(Pawn Seen)
{
    // Grunts enter combat via the event-driven sight pipeline rather than
    // the legacy priority funnel.
    if (BotRank == GRUNT) { GruntOnSight(Seen); return; }
    SetEnemy(Seen);
}

function SeeMonster(Pawn Seen)
{
    // Grunts enter combat via the event-driven sight pipeline rather than
    // the legacy priority funnel.
    if (BotRank == GRUNT) { GruntOnSight(Seen); return; }
    SetEnemy(Seen);
}

event bool NotifyBump(Actor Other, Vector HitNormal)
{
    local Vector Dir;

    // Follower mode: the base's handler owns friendly-bump reaction, so
    // skip the legacy door / adjust body below to avoid a double reaction.
    if (FollowOwnsEvents() && FollowHandleBump(Other, HitNormal))
    {
        return true;
    }

    // Chain to the base class first: some Controller.NotifyBump
    // implementations disable the bump probe, so re-arm it here to keep
    // our own bump handling firing below.
    super.NotifyBump(Other, HitNormal);
    Enable('NotifyBump');

    // End:0x2E8
    if((Pawn(Other) != none) && !SetEnemy(Pawn(Other)))
    {
        // End:0x228
        if(MoveFlags > 0)
        {
            Dir = GetMoveDirection();
            // End:0x225
            if((Dir Dot (Other.Location - Pawn.Location)) > float(0))
            {
                HitNormal.X = -Dir.Y;
                HitNormal.Y = Dir.X;
                HitNormal.Z = 0.0000000;
                HitNormal = Normal(HitNormal);
                bAdjusting = true;
                // End:0x1D8
                if((HitNormal Dot Dir) < float(0))
                {
                    AdjustPosition.Position = Pawn.Location + (HitNormal * 80.0000000);                    
                }
                else
                {
                    AdjustPosition.Position = Pawn.Location - (HitNormal * 80.0000000);
                }
            }            
        }
        else
        {
            // End:0x2E5
            if(!bAdjusting)
            {
                bAdjusting = true;
                AdjustPosition.Position = ((Normal(Pawn.Location - Other.Location) * 45.0000000) + (VRand() * 25.0000000)) + Pawn.Location;
                SetTimer(0.5000000, false, 'StopAdjusting');
            }
        }        
    }
    else
    {
        // End:0x382
        if(KFDoorActor(Other) != none)
        {
            // End:0x355
            if(!MarkDoorPath(KFDoorActor(Other)))
            {
                KFDoorActor(Other).UseDoor(Pawn);                
            }
            else
            {
                EndMoveTime = WorldInfo.TimeSeconds - float(1);
            }
        }
    }
    return false;
    //return ReturnValue;    
}

final function bool TargetLowHealth(Pawn Other)
{
    local float T;
    local int H;

    H = Other.Health;
    // End:0x74
    if(KFPawn_Human(Other) != none)
    {
        H += int(KFPawn_Human(Other).HealthToRegen);
    }
    // End:0x11A
    if(H < Other.HealthMax)
    {
        T = WorldInfo.TimeSeconds - EnemyEncounterTime;
        // End:0xEB
        if(T > 4.0000000)
        {
            return true;            
        }
        else
        {
            // End:0x10C
            if(T > 2.0000000)
            {
                return H < 85;
            }
        }
        return H < 70;
    }
    return false;
    //return ReturnValue;    
}

function EyeSightCheck()
{
    if((Pawn != none) && Pawn.IsAliveAndWell())
    {
        // Performance Gate: only re-scan for a new/better target when we
        // don't already have a live one, and no more than once every
        // ENEMY_SCAN_INTERVAL seconds. NotifyKilled's direct call to
        // PickNextEnemy() (immediate re-acquire right after a kill) is
        // deliberately NOT gated by this -- that call already runs on a
        // kill event, not per-tick.
        if (Enemy != none && Enemy.IsAliveAndWell()) return;
        if (WorldInfo.TimeSeconds - LastEnemyScanTime < ENEMY_SCAN_INTERVAL) return;

        LastEnemyScanTime = WorldInfo.TimeSeconds;
        PickNextEnemy();
    }
}

final function bool PickNextEnemy()
{
    local KFPawn_Monster P;
    local bool bResult;

    // P7 Leash Cooldown (Loophole 3): after dropping a target for being
    // too far away, don't immediately re-scan and grab the next best thing
    // -- wait out the cooldown so a distance-hovering target doesn't thrash
    // the bot between FightEnemy/Hunting and this scan every tick.
    if (WorldInfo.TimeSeconds - LastLeashDropTime < LEASH_COOLDOWN)
    {
        return false;
    }

    bResult = false;
    foreach WorldInfo.AllPawns(Class'KFGame.KFPawn_Monster', P, Pawn.Location, ENEMY_SCAN_RADIUS)
    {
        if(((P != Pawn) && P.IsAliveAndWell()) && FastTrace(P.Location, Pawn.Location))
        {
            bResult = (SetEnemy(P, true)) || bResult;
        }        
    }    
    return bResult;
    //return ReturnValue;    
}

function bool SetEnemy(Pawn Other, optional bool bNoNotify)
{
    if(((((Other == none) || Other == Pawn) || Other.SpawnTime == WorldInfo.TimeSeconds) || !Other.IsAliveAndWell()) || (KFPawn_Monster(Other) != none) && KFPawn_Monster(Other).bIsHeadless)
    {
        return false;
    }

    // Boss-Melee Guard (Loophole 1): a bot with nothing but melee left
    // must never target a boss-tier Zed. This is the single choke point
    // every acquisition path (native notifies, PickNextEnemy(), and the
    // leader-spotter broadcast below) funnels through -- but it only
    // catches acquisition-time melee state; see FightEnemy.PickStyle()
    // for the ammo-depletes-mid-fight case this alone can't catch.
    if (Other.Health > BOSS_HEALTH_THRESHOLD && IsMeleeOnly())
    {
        return false;
    }

    if(Pawn.IsSameTeam(Other))
    {
        if((((((PlayStyle == 1) && KPawn != none) && FollowingHuman == none) && KFPawn_Human(Other) != none) && Other.IsHumanControlled()) && Rand(3) == 0)
        {
            FollowingHuman = Other;
        }
        if(((((Enemy == none) && NextDoshShareTime > WorldInfo.TimeSeconds) && PlayerReplicationInfo.Score > float(800)) && Other.PlayerReplicationInfo != none) && Other.PlayerReplicationInfo.Score < float(500))
        {
            DonateMoney(Other);
        }
        return false;
    }
    EnemyEncounterTime = WorldInfo.TimeSeconds;
    if((Enemy != none) && (GetEnemyThreat(Enemy)) > (GetEnemyThreat(Other)))
    {
        return false;
    }
    Enemy = Other;
    if(!bNoNotify)
    {
        EnemyChanged();
    }

    // P7 Spotter (leader-only): share a close-range target with followers
    // who don't already have a live Enemy of their own, instead of making
    // them wait for their own FastTrace scan to independently spot it.
    if (bIsGroupLeader && mut != none && VSizeSq(Other.Location - Pawn.Location) <= SPOT_RADIUS_SQ)
    {
        mut.BroadcastSpottedEnemy(GroupID, Other);
    }

    return true;
    //return ReturnValue;    
}

function float GetEnemyThreat(Pawn Other)
{
    local float V;

    V = FMin(float(Other.Health), 600.0000000) + float(100);
    // End:0x5B
    if(V < float(30))
    {
        V += float(800);
    }
    V -= (VSize(Other.Location - Pawn.Location) / 2.0000000);
    // End:0xD4
    if(Other == Enemy)
    {
        V *= 1.2500000;
    }
    return V;
    //return ReturnValue;    
}

// Unified firing gate: applies the trajectory validation, reload gate,
// range-efficiency culling, weapon management, and inherited-focus
// override before delegating to the base fire behaviour.
function bool FireWeaponAt(Actor inActor)
{
	local KFWeapon W;

	bOutOfEffectiveRange = false;

	if((InheritedEnemy != none) && (inActor == InheritedEnemy) && !HasOwnFireLine(inActor))
	{
		Pawn.StopFiring();
		return false;
	}
	if(Pawn.IsFiring())
	{
		return true;
	}
	if((inActor == none) || NeedToTurn(inActor.Location) || !Pawn.CanAttack(inActor))
	{
		return false;
	}
	Target = inActor;
	W = KFWeapon(Pawn.Weapon);
	if(W != none)
	{
		if(HandleWeaponManagement(W))
		{
			return false;
		}
		if(TryThrowGrenade(W, inActor))
		{
			return true;
		}
		if(W.bMeleeWeapon)
		{
			W.StartFire(BOTFM_PRIMARY);
		}
		else if(VSizeSq(inActor.Location - Pawn.Location) < 40000.0)
		{
			W.StartFire(BOTFM_BASH);
		}
		else
		{
			if(!IsInEffectiveRange(inActor))
			{
				bOutOfEffectiveRange = true;
				return false;
			}
			W.StartFire(BOTFM_PRIMARY);
		}
	}
	return Pawn.BotFire(false);
    //return ReturnValue;    
}

// Forces a melee/bash attempt every tick while grabbed by a Zed, mirroring
// the real escape input (mashing melee) instead of a normal ranged attack.
// This deliberately does NOT go through FireWeaponAt(): that function's own
// guards (Pawn.IsFiring(), NeedToTurn(), and especially Pawn.CanAttack())
// are exactly why the bot used to just stand there - CanAttack() correctly
// refuses a normal attack while the grab special move is playing, since you
// can't legitimately fire/swing mid-animation. Breaking free is a different
// action from attacking, so it's triggered directly here instead. Fire mode
// 3 is this codebase's existing "bash with a ranged weapon at melee range"
// mode (see FireWeaponAt above); mode 0 on an actual melee weapon is its
// normal swing - both are the correct escape input for a grab.
final function TryBreakFree()
{
    local KFWeapon W;
    local KFPawn GrabbingZed;

    if(Pawn == none)
    {
        return;
    }
    // A bot with nothing currently equipped (just disarmed, mid weapon-
    // switch, etc.) has no swing/bash to throw and would otherwise sit in
    // BreakLose forever with every Timer tick silently doing nothing. Get
    // it a weapon so the next tick has something to fire.
    if(Pawn.Weapon == none)
    {
        if(Pawn.InvManager != none)
        {
            Pawn.InvManager.SwitchToBestWeapon(true);
        }
        return;
    }
    W = KFWeapon(Pawn.Weapon);
    if(W == none)
    {
        return;
    }

    // Grabbing Zed reference for the simulated bash damage.
    GrabbingZed = KPawn.InteractionPawn;

    if(W.bMeleeWeapon)
    {
        W.StartFire(0);
        // Simulated bash: apply programmatic damage to the grabbing Zed.
        SimulateBashHit(GrabbingZed, W);
    }
    else if(W == MedicGun)
    {
        // Immersion exception: syringe is excluded from bash damage.
        // Switch to a melee weapon for a reliable strike.
        if(Pawn.InvManager != none)
        {
            Pawn.InvManager.SwitchToBestWeapon(true);
        }
    }
    else
    {
        W.StartFire(3);
        // Simulated bash: apply programmatic damage to the grabbing Zed.
        SimulateBashHit(GrabbingZed, W);
    }
}

// Simulated bash override: applies programmatic damage to the grabbing Zed
// when the bot performs a bash. This ensures the bash always "connects"
// even if the native hit detection fails. 30% chance for a headshot kill.
// The Medical Syringe is explicitly excluded (no bash damage from syringe).
final function SimulateBashHit(KFPawn TargetZed, KFWeapon W)
{
    local float RngRoll;
    local int BashDamage;

    // No target or dead target -- nothing to hit.
    if(TargetZed == none || !TargetZed.IsAliveAndWell())
    {
        return;
    }
    // Immersion exception: syringe does not deal bash damage.
    if(W == MedicGun)
    {
        return;
    }

    // 30% chance for a headshot kill (guaranteed one-shot on trash Zeds).
    RngRoll = FRand();
    if(RngRoll < 0.30)
    {
        // Headshot: instant kill.
        BashDamage = 200;
    }
    else
    {
        // Normal bash: solid damage that staggers the Zed.
        BashDamage = 25;
    }

    // Apply damage directly to the Zed's health.
    TargetZed.TakeDamage(BashDamage, self, TargetZed.Location, vect(0.0, 0.0, 0.0), Class'Engine.DamageType');
}

function EnemyChanged()
{
    //return;    
}

function DonateMoney(Pawn Other)
{
    //return;    
}

exec function SwitchToBestWeapon(optional bool bForceNewWeapon, optional bool check_9mm_logic = false)
{
    // End:0x83
    if((Pawn != none) && Pawn.InvManager != none)
    {
        Pawn.InvManager.SwitchToBestWeapon(bForceNewWeapon, check_9mm_logic);
    }
    //return;    
}

function Rotator GetAdjustedAimFor(Weapon W, Vector StartFireLoc)
{
    local Vector TargetPos;

    // End:0x4E
    if(Target == none)
    {
        Target = Enemy;
        // End:0x4E
        if(Target == none)
        {
            return super(Controller).GetAdjustedAimFor(W, StartFireLoc);
        }
    }
    // End:0xE9
    if((W != none) && KFPawn(Target) != none)
    {
        TargetPos = KFPawn(Target).Mesh.GetBoneLocation(KFPawn(Target).HeadBoneName);        
    }
    else
    {
        TargetPos = Target.Location;
    }
    return Rotator(TargetPos - StartFireLoc);
    //return ReturnValue;    
}

simulated function GetPlayerViewPoint(out Vector out_Location, out Rotator out_Rotation)
{
    // End:0x7E
    if(Pawn != none)
    {
        Pawn.GetActorEyesViewPoint(out_Location, out_Rotation);
        out_Rotation = GetAdjustedAimFor(Pawn.Weapon, out_Location);        
    }
    else
    {
        out_Location = Location;
        out_Rotation = Rotation;
    }
    //return;    
}

final function MoveToX(Vector Dest, optional Actor ViewFocus, optional bool bSerpent = true)
{
    bAdjusting = false;
    MoveFlags = 1;
    SetDestinationPosition(Dest);
    SetFocalPoint(Dest);
    Focus = ViewFocus;
    EndMoveTime = (WorldInfo.TimeSeconds + (VSize(Dest - Pawn.Location) / Pawn.GroundSpeed)) + 0.6000000;
    bSerpentineMove = bSerpent;
    PrevMovePos = Pawn.Location;
    MovePauseTime = WorldInfo.TimeSeconds;
    // End:0x159
    if(bSerpent)
    {
        bSerpentLeft = Rand(2) == 0;
    }
    //return;    
}

final function MoveTowardX(Actor Dest, optional Actor ViewFocus, optional bool bSerpent = true)
{
    bAdjusting = false;
    MoveFlags = 2;
    MoveTarget = Dest;
    bSerpentineMove = bSerpent;
    PrevMovePos = Pawn.Location;
    MovePauseTime = WorldInfo.TimeSeconds;
    // End:0x19B
    if(Dest != none)
    {
        SetDestinationPosition(Dest.Location);
        SetFocalPoint(Dest.Location);
        Focus = Dest;
        EndMoveTime = (WorldInfo.TimeSeconds + (VSize(Dest.Location - Pawn.Location) / Pawn.GroundSpeed)) + 0.7500000;
    }
    // End:0x1BD
    if(ViewFocus != none)
    {
        Focus = ViewFocus;
    }
    // End:0x1DC
    if(bSerpent)
    {
        bSerpentLeft = Rand(2) == 0;
    }
    //return;    
}

final function StrafeTowardPoint(Vector Dest)
{
    local Vector X, Y;

    X = Dest - Pawn.Location;
    // End:0x19F
    if(VSizeSq2D(X) > 22500.0000000)
    {
        Y.X = -X.Y;
        Y.Y = X.X;
        // End:0x141
        if(SerpentineTime < WorldInfo.TimeSeconds)
        {
            SerpentineTime = (WorldInfo.TimeSeconds + 0.3000000) + (FRand() * 0.0500000);
            bSerpentLeft = !bSerpentLeft;
        }
        // End:0x178
        if(bSerpentLeft)
        {
            X = Normal(X + (Y * 0.5000000));            
        }
        else
        {
            X = Normal(X - (Y * 0.5000000));
        }
    }
    Pawn.Acceleration = X * 2000.0000000;
    //return;    
}

final function Vector GetMoveDirection()
{
    switch(MoveFlags)
    {
        // End:0x55
        case 1:
            return DestinationPosition.Position - Pawn.Location;
        // End:0xB7
        case 2:
            return ((MoveTarget != none) ? MoveTarget.Location - Pawn.Location : vect(0.0000000, 0.0000000, 0.0000000));
        // End:0xFFFF
        default:
            return vect(0.0000000, 0.0000000, 0.0000000);
            break;
    }
    //return ReturnValue;    
}

final function ProcessMoveTo()
{
    // End:0xA0
    if(VSizeSq2D(DestinationPosition.Position - Pawn.Location) < 2500.0000000)
    {
        Pawn.Acceleration = vect(0.0000000, 0.0000000, 0.0000000);
        MoveFlags = 0;
        CurrentPath = none;
        FinishedMove();        
    }
    else
    {
        // End:0xD6
        if(bSerpentineMove)
        {
            StrafeTowardPoint(DestinationPosition.Position);            
        }
        else
        {
            Pawn.Acceleration = DestinationPosition.Position - Pawn.Location;
        }
    }
    //return;    
}

final function ProcessMoveToward()
{
    // End:0xD5
    if((MoveTarget == none) || Pawn.ReachedDestination(MoveTarget))
    {
        // End:0x85
        if(NavigationPoint(MoveTarget) != none)
        {
            Pawn.SetAnchor(NavigationPoint(MoveTarget));
        }
        Pawn.Acceleration = vect(0.0000000, 0.0000000, 0.0000000);
        MoveFlags = 0;
        CurrentPath = none;
        FinishedMove();        
    }
    else
    {
        // End:0x10D
        if(bSerpentineMove)
        {
            StrafeTowardPoint(MoveTarget.Location);            
        }
        else
        {
            Pawn.Acceleration = MoveTarget.Location - Pawn.Location;
        }
    }
    //return;    
}

final function AbortMove()
{
    Pawn.Acceleration = vect(0.0000000, 0.0000000, 0.0000000);
    MoveFlags = 0;
    bAdjusting = false;
    CurrentPath = none;
    //return;    
}

final function CheckBlockedPath(Actor Start, NavigationPoint End)
{
    local KFPawnBlockingVolume B;
    local Vector HL, HN;

    // End:0x40
    if(((Start == none) || End == none) || BotBlockRoutes.Find(End) >= 0)
    {
        return;
    }
    // End:0x106
    foreach Pawn.TraceActors(Class'KFGame.KFPawnBlockingVolume', B, HL, HN, End.Location, Start.Location, vect(32.0000000, 32.0000000, 64.0000000))
    {
        // End:0x105
        if(B.bBlockPlayers)
        {
            BotBlockRoutes.AddItem(End);
            // End:0x106
            break;
        }        
    }    
    //return;    
}

// HCA wiring: hub-side reaction to follower-nav status changes. The base
// calls this synchronously from inside its state function, so we do NOT
// GotoState here -- that would make UE3 resume the old state function after
// the next latent. Instead we set bFollowExitPending; the base checks the
// flag in its Dispatch label and performs the GotoState + return there.
function FollowNotifyHub(EFollowStatus NewStatus)
{
    switch (NewStatus)
    {
        case FS_Arrived:
            // Base holds position in its slot ring (FA_Hold); Hub just records.
            `log("[FollowNav] KF2Bot: FS_Arrived -- holding slot " $ string(FollowSlotIndex) $ "/" $ string(FollowSlotCount));
            break;

        case FS_LeaderTeleported:
            // Route invalidated; the base decorrelates and repaths on its own.
            `log("[FollowNav] KF2Bot: FS_LeaderTeleported -- route invalid, decorrelated");
            break;

        case FS_LeaderLost:
        case FS_Blocked:
            // Never freeze: hand control back to the decision hub. The base
            // exits to FollowExitState on its next dispatch and the P8
            // tether hook re-decides (regroup, or anchor fallback if the
            // leader is gone).
            `log("[FollowNav] KF2Bot: " $ string(int(NewStatus)) @ "-- returning to PickNextMove");
            FollowExitState = 'PickNextMove';
            bFollowExitPending = true;
            break;
    }
}

// Retry ladder exhausted before the hub takes over: log and let the
// deferred FS_Blocked return re-decide. The SDK's terminal-stuck "suicide"
// is deliberately not replicated here.
function FollowOnGaveUp()
{
    `log("[FollowNav] KF2Bot: follow retry ladder exhausted; hub will re-decide via PickNextMove");
}

function Tick(float Delta)
{
    // WARNING: never call Super.Tick(Delta) here. KFAIController.Tick
    // (SDK line 3934) evaluates stuck-possibility and its terminal
    // "suicide" recovery kills the bot - if this class is ever re-parented
    // under KFAIController, that path would fire for follower bots.
    // End:0x11
    if(Pawn == none)
    {
        return;
    }
    
    // Follow-combat escape (HCA wiring): the follower state is nav-only and
    // SetEnemy() never transitions state, so a Zed with LOS while tethered
    // would go unfought. Route to P7 combat exactly as PickNextMove would.
    // The base's Dispatch stale-resume guard stops the old state function
    // from dispatching stale follow code after this transition.
    if (IsInState('FollowingLeader') || IsInState('FollowingLeaderBasic'))
    {
        if (Enemy != none && Enemy.IsAliveAndWell()
            && !(KFPawn_Monster(Enemy) != none && KFPawn_Monster(Enemy).bIsHeadless)
            && (WorldInfo.TimeSeconds - LastFollowEscapeTime >= FOLLOW_ESCAPE_COOLDOWN))
        {
            LastFollowEscapeTime = WorldInfo.TimeSeconds;
            if (LineOfSightTo(Enemy))
            {
                `log("[FollowNav]" @ string(Name) @ "Tick escape -> FightEnemy " $ string(Enemy));
                GotoState('FightEnemy');
            }
            else
            {
                `log("[FollowNav]" @ string(Name) @ "Tick escape -> Hunting " $ string(Enemy));
                GotoState('Hunting');
            }
            return;
        }
    }
    
    // Global zed count refresh (throttled): feeds the low-zed hunting trigger
    // in PickNextMove. 8000u radius approximates the full KF2 map.
    if (WorldInfo.TimeSeconds - LastGlobalZedCountTime >= GLOBAL_ZED_COUNT_INTERVAL)
    {
        LastGlobalZedCountTime = WorldInfo.TimeSeconds;
        GlobalZedCount = CountNearbyZeds(GLOBAL_ZED_RADIUS);
    }

    // Grunt movement must run every frame: the restricted-tick gate that
    // early-exited here blocked the MoveFlags execution block below, leaving
    // Grunts frozen (the "limbo" state) until a Zed set bEngageActive.
    // Tactical-decision throttling now lives in GruntDecisionTimer(); the
    // per-frame movement processing (ProcessMoveTo/ProcessMoveToward) must
    // run so tethered Grunts actually walk to their formation offset.
        // End:0xDF
    if(bAdjusting)
    {
        // End:0x7B
        if(VSizeSq2D(AdjustPosition.Position - Pawn.Location) < 2500.0000000)
        {
            StopAdjusting();            
        }
        else
        {
            Pawn.Acceleration = Normal(AdjustPosition.Position - Pawn.Location) * 2000.0000000;
        }
    }
    // End:0x3C9
    if(MoveFlags != 0)
    {
        // End:0x2A7
        if(EndMoveTime < WorldInfo.TimeSeconds)
        {
            // End:0x262
            if(MoveFlags == 2)
            {
                // End:0x175
                if(LastFailedMove != MoveTarget)
                {
                    LastFailedMove = NavigationPoint(MoveTarget);
                    FailedMoveCount = 0;                    
                }
                else
                {
                    // End:0x1DE
                    if((LastFailedMove != none) && ++FailedMoveCount > 5)
                    {
                        TempBlockPath = LastFailedMove;
                        TempBlockTime = WorldInfo.TimeSeconds + 30.0000000;
                    }
                }
                // End:0x237
                if(CurrentPath != none)
                {
                    CheckBlockedPath(CurrentPath.Start, CurrentPath.GetEnd());                    
                }
                else
                {
                    // End:0x262
                    if(LastFailedMove != none)
                    {
                        CheckBlockedPath(Pawn, LastFailedMove);
                    }
                }
            }
            Pawn.Acceleration = vect(0.0000000, 0.0000000, 0.0000000);
            MoveFlags = 0;
            FinishedMove();            
        }
        else
        {
            // End:0x33F
            if(VSizeSq(PrevMovePos - Pawn.Location) < (float(2500) * Delta))
            {
                // End:0x33C
                if((WorldInfo.TimeSeconds - MovePauseTime) > 0.5000000)
                {
                    Pawn.DoJump(false);
                }                
            }
            else
            {
                PrevMovePos = Pawn.Location;
                MovePauseTime = WorldInfo.TimeSeconds;
            }
            // End:0x3C9
            if(!bAdjusting)
            {
                // End:0x3BF
                if(MoveFlags == 1)
                {
                    ProcessMoveTo();                    
                }
                else
                {
                    ProcessMoveToward();
                }
            }
        }
    }
    //return;    
}

final function bool MarkDoorPath(KFDoorActor door)
{
    local int I;
    local NavigationPoint N;

    // End:0x6E
    if((door.bIsDoorOpen || door.WeldIntegrity <= 0) || door.bAutomaticDoor)
    {
        return false;
    }
    N = NavigationPoint(MoveTarget);
    // End:0x1D3
    if(N != none)
    {
        // End:0xC0
        if(DoorPaths.Find('Path', N) >= 0)
        {
            return true;
        }
        // End:0x148
        if(((N.Location - Pawn.Location) Dot (door.Location - Pawn.Location)) < float(0))
        {
            return false;
        }
        I = DoorPaths.Length;
        DoorPaths.Length = I + 1;
        DoorPaths[I].door = door;
        DoorPaths[I].Path = N;
    }
    return true;
    //return ReturnValue;    
}

final function bool BuildPathToward(Actor Other)
{
    local int I;

    I = DoorPaths.Length - 1;
    J0x17:

    // End:0x18E [Loop If]
    if(I >= 0)
    {
        // End:0x142
        if(((DoorPaths[I].Path.bBlocked || DoorPaths[I].door.bIsDestroyed) || DoorPaths[I].door.bIsDoorOpen) || DoorPaths[I].door.WeldIntegrity <= 0)
        {
            DoorPaths.Remove(I, 1);            
        }
        else
        {
            DoorPaths[I].Path.bBlocked = true;
        }
        --I;
        // [Loop Continue]
        goto J0x17;
    }
    I = BotBlockRoutes.Length - 1;
    J0x1A5:

    // End:0x1ED [Loop If]
    if(I >= 0)
    {
        BotBlockRoutes[I].bBlocked = true;
        --I;
        // [Loop Continue]
        goto J0x1A5;
    }
    // End:0x257
    if(TempBlockPath != none)
    {
        // End:0x236
        if(TempBlockTime < WorldInfo.TimeSeconds)
        {
            TempBlockPath = none;            
        }
        else
        {
            TempBlockPath.bBlocked = true;
        }
    }
    MoveTarget = FindPathToward(Other);
    I = DoorPaths.Length - 1;
    J0x287:

    // End:0x2E2 [Loop If]
    if(I >= 0)
    {
        DoorPaths[I].Path.bBlocked = false;
        --I;
        // [Loop Continue]
        goto J0x287;
    }
    I = BotBlockRoutes.Length - 1;
    J0x2F9:

    // End:0x341 [Loop If]
    if(I >= 0)
    {
        BotBlockRoutes[I].bBlocked = false;
        --I;
        // [Loop Continue]
        goto J0x2F9;
    }
    // End:0x371
    if(TempBlockPath != none)
    {
        TempBlockPath.bBlocked = false;
    }
    return MoveTarget != none;
    //return ReturnValue;    
}

final function bool BuildPathTo(Vector Dest)
{
    local int I;

    I = DoorPaths.Length - 1;
    J0x17:

    // End:0x18E [Loop If]
    if(I >= 0)
    {
        // End:0x142
        if(((DoorPaths[I].Path.bBlocked || DoorPaths[I].door.bIsDestroyed) || DoorPaths[I].door.bIsDoorOpen) || DoorPaths[I].door.WeldIntegrity <= 0)
        {
            DoorPaths.Remove(I, 1);            
        }
        else
        {
            DoorPaths[I].Path.bBlocked = true;
        }
        --I;
        // [Loop Continue]
        goto J0x17;
    }
    I = BotBlockRoutes.Length - 1;
    J0x1A5:

    // End:0x1ED [Loop If]
    if(I >= 0)
    {
        BotBlockRoutes[I].bBlocked = true;
        --I;
        // [Loop Continue]
        goto J0x1A5;
    }
    // End:0x257
    if(TempBlockPath != none)
    {
        // End:0x236
        if(TempBlockTime < WorldInfo.TimeSeconds)
        {
            TempBlockPath = none;            
        }
        else
        {
            TempBlockPath.bBlocked = true;
        }
    }
    MoveTarget = FindPathTo(Dest);
    I = DoorPaths.Length - 1;
    J0x286:

    // End:0x2E1 [Loop If]
    if(I >= 0)
    {
        DoorPaths[I].Path.bBlocked = false;
        --I;
        // [Loop Continue]
        goto J0x286;
    }
    I = BotBlockRoutes.Length - 1;
    J0x2F8:

    // End:0x340 [Loop If]
    if(I >= 0)
    {
        BotBlockRoutes[I].bBlocked = false;
        --I;
        // [Loop Continue]
        goto J0x2F8;
    }
    // End:0x370
    if(TempBlockPath != none)
    {
        TempBlockPath.bBlocked = false;
    }
    return MoveTarget != none;
    //return ReturnValue;    
}

final function bool BuildRandomPath()
{
    local int I;

    I = DoorPaths.Length - 1;
    J0x17:

    // End:0x18E [Loop If]
    if(I >= 0)
    {
        // End:0x142
        if(((DoorPaths[I].Path.bBlocked || DoorPaths[I].door.bIsDestroyed) || DoorPaths[I].door.bIsDoorOpen) || DoorPaths[I].door.WeldIntegrity <= 0)
        {
            DoorPaths.Remove(I, 1);            
        }
        else
        {
            DoorPaths[I].Path.bBlocked = true;
        }
        --I;
        // [Loop Continue]
        goto J0x17;
    }
    I = BotBlockRoutes.Length - 1;
    J0x1A5:

    // End:0x1ED [Loop If]
    if(I >= 0)
    {
        BotBlockRoutes[I].bBlocked = true;
        --I;
        // [Loop Continue]
        goto J0x1A5;
    }
    // End:0x257
    if(TempBlockPath != none)
    {
        // End:0x236
        if(TempBlockTime < WorldInfo.TimeSeconds)
        {
            TempBlockPath = none;            
        }
        else
        {
            TempBlockPath.bBlocked = true;
        }
    }
    RandGoal = FindRandomDest();
    I = DoorPaths.Length - 1;
    J0x27B:

    // End:0x2D6 [Loop If]
    if(I >= 0)
    {
        DoorPaths[I].Path.bBlocked = false;
        --I;
        // [Loop Continue]
        goto J0x27B;
    }
    I = BotBlockRoutes.Length - 1;
    J0x2ED:

    // End:0x335 [Loop If]
    if(I >= 0)
    {
        BotBlockRoutes[I].bBlocked = false;
        --I;
        // [Loop Continue]
        goto J0x2ED;
    }
    // End:0x365
    if(TempBlockPath != none)
    {
        TempBlockPath.bBlocked = false;
    }
    return RandGoal != none;
    //return ReturnValue;    
}

function StopAdjusting()
{
    bAdjusting = false;
    Pawn.Acceleration = vect(0.0000000, 0.0000000, 0.0000000);
    //return;    
}

final function bool NeedToTurn(Vector targ)
{
    local Rotator R;

    R.Yaw = Pawn.Rotation.Yaw;
    return (Vector(R) Dot Normal2D(targ - Pawn.Location)) < 0.9300000;
    //return ReturnValue;    
}

event bool NotifyHitWall(Vector HitNormal, Actor Wall)
{
    // Follower mode: the base's handler owns wall reaction (per-wall hit
    // counter + stuck ladder), so skip the legacy door / wall-adjust body
    // below to avoid a double reaction.
    if (FollowOwnsEvents())
    {
        return FollowHandleHitWall(HitNormal, Wall);
    }

    // Chain to the base class before our door / wall-adjust handling so the
    // legacy wall-bump behaviour is preserved.
    super.NotifyHitWall(HitNormal, Wall);

    // End:0x227
    if(MoveFlags != 0)
    {
        // End:0xAE
        if(KFDoorActor(Wall) != none)
        {
            // End:0x81
            if(!MarkDoorPath(KFDoorActor(Wall)))
            {
                KFDoorActor(Wall).UseDoor(Pawn);                
            }
            else
            {
                EndMoveTime = WorldInfo.TimeSeconds - float(1);
            }
        }
        // End:0xFC
        if((MoveFlags == 2) && MoveTarget != none)
        {
            SetDestinationPosition(MoveTarget.Location);
        }
        // End:0x1F8
        if(!PickWallAdjust(HitNormal))
        {
            // End:0x1F5
            if((NextAdjustTime < WorldInfo.TimeSeconds) && Pawn.Physics == 1)
            {
                // End:0x191
                if(Rand(3) == 0)
                {
                    Pawn.DoJump(false);                    
                }
                else
                {
                    bAdjusting = true;
                    AdjustPosition.Position = (Pawn.Location + (HitNormal * 80.0000000)) + (VRand() * 50.0000000);
                }
            }            
        }
        else
        {
            NextAdjustTime = WorldInfo.TimeSeconds + 0.5000000;
        }
    }
    return false;
    //return ReturnValue;    
}

function FinishedMove()
{
    PickCombatStyle();
}

final function PickFavorite()
{
    local float desire, BestDesire;
    local AIWeaponInfo A;

    // End:0x136
    foreach mut.TraderList(A)
    {
        desire = A.AIRating * (FRand() + 0.3000000);
        // End:0xD2
        if(((Perk != none) && A.Perk != none) && Perk != A.Perk)
        {
            desire *= 0.1500000;
        }
        // End:0x135
        if((FavoriteWeapon == none) || desire > BestDesire)
        {
            FavoriteWeapon = A.WeaponClass;
            BestDesire = desire;
        }        
    }    
    //return;    
}

final function bool SellWeapon(KFWeapon W, out int Dosh)
{
    local float desire, BestDesire;
    local KFWeapon T;
    local AIWeaponInfo A;

    // End:0x157
    if(W == none)
    {
        // End:0x145
        foreach KFInvManager.InventoryActors(Class'KFGame.KFWeapon', T)
        {
            A = mut.FindWeaponByClass(T.Class);
            // End:0xC3
            if((A == none) || !A.bCanSell)
            {
                continue;                
            }
            desire = A.AIRating * (0.5000000 + FRand());
            // End:0x144
            if((W == none) || desire < BestDesire)
            {
                W = T;
                BestDesire = desire;
            }            
        }        
        // End:0x157
        if(W == none)
        {
            return false;
        }
    }
    A = mut.FindWeaponByClass(W.Class);
    // End:0x1D5
    if((A == none) || !A.bCanSell)
    {
        return false;
    }
    W.Destroy();
    Dosh += int(float(A.BuyPrice) * 0.7500000);
    return true;
    //return ReturnValue;    
}

final function AIWeaponInfo GetBestBuy(int Cash)
{
    local AIWeaponInfo A, Best;
    local float desire, BestDesire;
    local KFWeapon W;

    // End:0x2E9
    foreach mut.TraderList(A)
    {
        desire = A.AIRating * (FRand() + 0.5000000);
        // End:0x9E
        if(FavoriteWeapon == A.WeaponClass)
        {
            desire *= 4.0000000;            
        }
        else
        {
            // End:0x105
            if(((Perk != none) && A.Perk != none) && Perk != A.Perk)
            {
                continue;
            }
        }
        W = KFWeapon(KFInvManager.FindInventoryType(A.WeaponClass));
        // End:0x1F7
        if(W != none)
        {
            // End:0x1E4
            if((!W.UsesAmmo() || W.GetMissingSpareAmmoAmount(0) <= 0) || Cash < A.AmmoPricePerMag)
            {
                continue;
            }
            desire *= 2.5000000;            
        }
        else
        {
            // End:0x29A
            if((Cash < A.BuyPrice) || !KFInvManager.CanCarryWeapon(A.WeaponClass) && FavoriteWeapon != A.WeaponClass)
            {
                continue;
            }
        }
        // End:0x2E8
        if((Best == none) || desire > BestDesire)
        {
            Best = A;
            BestDesire = desire;
        }        
    }
    J0x2E9:
    
    return Best;
    //return ReturnValue;    
}

final function ProcessPurchase(KFGFxObject_TraderItems L)
{
    local int S, N, J, olds;
    local byte I, loops;
    local KFWeapon W;
    local AIWeaponInfo A;
    local KFWeapon WW;

    // End:0x4C
    if(!mut.bTraderListInit)
    {
        mut.InitTraderList(L);
    }
    // End:0x65
    if(FavoriteWeapon == none)
    {
        PickFavorite();
    }
    S = int(PlayerReplicationInfo.Score);
    olds = 0;
    // End:0x1E5
    if(Perk != none)
    {
        // End:0x1E4
        foreach KFInvManager.InventoryActors(Class'KFGame.KFWeapon', WW)
        {
            // End:0x117
            if(WW.GetWeaponPerkClass(Perk) == Perk)
            {
                continue;                
            }
            A = mut.FindWeaponByClass(WW.Class);
            // End:0x197
            if((A == none) || !A.bCanSell)
            {
                continue;                
            }
            WW.Destroy();
            S += int(float(A.BuyPrice) * 0.7500000);            
        }        
    }
    J0x1E5:

    // End:0x5FA [Loop If]
    if((((S > 150) || mut.bBotsUnlimitedCash) && olds != S) && ++loops < 8)
    {
        olds = S;
        // End:0x29B
        if(mut.bBotsUnlimitedCash)
        {
            A = GetBestBuy(999999);            
        }
        else
        {
            A = GetBestBuy(S);
        }
        // End:0x2CA
        if(A == none)
        {
            // [Explicit Break]
            goto J0x5FA;
        }
        W = KFWeapon(KFInvManager.FindInventoryType(A.WeaponClass));
        // End:0x50F
        if(W != none)
        {
            // End:0x351
            if(!W.UsesAmmo())
            {
                // [Explicit Break]
                goto J0x5FA;
            }
            J = -1;
            I = 0;
            J0x36C:

            // End:0x50C [Loop If]
            if(I < 2)
            {
                // End:0x3BD
                if((I == 1) && !W.UsesSecondaryAmmo())
                {                    
                }
                else
                {
                    N = W.GetMissingSpareAmmoAmount(I);
                    // End:0x401
                    if(N <= 0)
                    {                        
                    }
                    else
                    {
                        // End:0x473
                        if(!mut.bBotsUnlimitedCash)
                        {
                            N = Min(N, int(float(S) / A.PricePerBullet[I]));
                        }
                        W.SpareAmmoCount[I] += N;
                        S -= int(float(N) * A.PricePerBullet[I]);
                        // End:0x4FE
                        if(S <= 0)
                        {
                            // [Explicit Break]
                            goto J0x50C;
                        }
                    }
                }
                ++I;
                // [Loop Continue]
                goto J0x36C;
            }
            J0x50C:
            
        }
        else
        {
            J = 0;
            J0x51A:

            // End:0x590 [Loop If]
            if(!KFInvManager.CanCarryWeapon(A.WeaponClass) && ++J < 6)
            {
                // End:0x58D
                if(!SellWeapon(none, S))
                {
                    // [Explicit Break]
                    goto J0x590;
                }
                // [Loop Continue]
                goto J0x51A;
            }
            J0x590:

            KFInvManager.CreateInventory(A.WeaponClass);
            S -= A.BuyPrice;
        }
        // [Loop Continue]
        goto J0x1E5;
    }
    J0x5FA:

    // End:0x7CC
    if(((S >= L.ArmorPrice) || mut.bBotsUnlimitedCash) && KPawn.Armor < KPawn.MaxArmor)
    {
        N = KPawn.MaxArmor - KPawn.Armor;
        // End:0x76D
        if(((N * L.ArmorPrice) > S) && !mut.bBotsUnlimitedCash)
        {
            N = S / L.ArmorPrice;
        }
        KPawn.Armor += byte(N);
        S -= (N * L.ArmorPrice);
    }
    // End:0x8EA
    if((S > 0) || mut.bBotsUnlimitedCash)
    {
        N = (1 + Rand(4)) - KFInvManager.GrenadeCount;
        J0x832:

        // End:0x8EA [Loop If]
        if((N > 0) && (S >= L.GrenadePrice) || mut.bBotsUnlimitedCash)
        {
            S -= L.GrenadePrice;
            ++KFInvManager.GrenadeCount;
            --N;
            // [Loop Continue]
            goto J0x832;
        }
    }
    PlayerReplicationInfo.Score = float(Max(S, 0));
    PlayerReplicationInfo.bForceNetUpdate = true;
    //return;    
}

function NotifyAddInventory(Inventory NewItem)
{
    // End:0x45
    if(KFWeap_Welder(NewItem) != none)
    {
        Weapon(NewItem).AIRating = -1.0000000;
    }
    //return;    
}

function PickCombatStyle()
{
    // Obs 2 -- Clear the spawn flag once the bot enters its first combat
    // state, so RelocateBotsToAmmoCrates will not teleport it again.
    bJustSpawned = false;

    // Step 6 signal: every combat re-evaluation is a fresh move-intent
    // (FinishedMove / Timer / EnemyChanged / NotifyKilled all funnel here).
    WdLastMoveIntentTime = WorldInfo.TimeSeconds;

    // P1 Terminal Lock: once bInTerminalState is set, every other state's
    // re-evaluation call (FinishedMove/Timer/EnemyChanged/NotifyKilled --
    // all of which funnel through here) routes back into VictoryDance
    // instead of GotoState('PickNextMove'), so nothing can pull the bot
    // back into the behavior tree after the match is over.
    if (bInTerminalState)
    {
        GotoState('VictoryDance');
        return;
    }

    // HCA wiring (crash fix): the follower-nav states own their own
    // re-evaluation (watchdog + Dispatch). Every re-eval funnel here
    // (FinishedMove/Timer/EnemyChanged) was yanking bots back to
    // PickNextMove, and the P8 tether hook re-issued FollowStart on
    // every entry -- an infinite FollowingLeader<->PickNextMove flap
    // that hammered the native pathfinder and crashed the game.
    // Combat escape is handled in Tick(); the hub exit flag (FS_LeaderLost/
    // FS_Blocked) is handled by the base's Dispatch, not here.
    if (bEnableAdvancedLocomotion
        && (IsInState('FollowingLeader') || IsInState('FollowingLeaderBasic')))
    {
        return;
    }
    GotoState('PickNextMove');
    //return;    
}

// Post-respawn spawn validation: in rare edge cases (e.g., Steam Fortress
// random-spawn glitch) a bot can spawn embedded in a wall with no valid
// floor. If the spawn is not on a walkable floor, nudge the pawn
// horizontally in a bounded loop until it lands on one.
function ValidateAndNudgeSpawn()
{
    local vector NudgeLoc;
    local int Attempts;

    if (Pawn == None) return;
    if (IsOnWalkableFloor()) return;
    `log("[FollowNav] ValidateAndNudgeSpawn: spawn not on a floor, nudging");
    for (Attempts = 0; Attempts < 6; Attempts++)
    {
        NudgeLoc = Pawn.Location;
        NudgeLoc.X = NudgeLoc.X + (FRand() * 128.0 - 64.0);
        NudgeLoc.Y = NudgeLoc.Y + (FRand() * 128.0 - 64.0);
        SetLocation(NudgeLoc);
        if (IsOnWalkableFloor()) return;
    }
    `log("[FollowNav] ValidateAndNudgeSpawn: nudged, still settling");
}

function bool IsOnWalkableFloor()
{
    if (Pawn == None || Pawn.Base == None || Pawn.Base == Pawn) return false;
    if (Pawn.Location.Z < Pawn.Base.Location.Z) return false;
    return (Pawn.Location.Z - Pawn.Base.Location.Z) < 80.0;
}

function vector ComputeFormationOffset(KF2Bot Leader, bool bSingleFile)
{
    local int FollowerIdx, GroupSize;
    local float Angle;
    local vector Forward, Right, Offset;

    if (Leader == None || Leader.Pawn == None || Pawn == None)
        return Pawn.Location;

    FollowerIdx = mut.GetFollowerIndex(KF2Bot(self));
    GroupSize   = mut.GetGroupSize(GroupID);
    if (GroupSize <= 0) GroupSize = 1;

    Forward = vector(Leader.Pawn.Rotation);
    Right   = Normal(Forward cross vect(0,0,1));

    if (bSingleFile)
    {
        Offset = Leader.Pawn.Location - (Forward * (SINGLE_FILE_SPACING * FollowerIdx));
    }
    else
    {
        Angle = ((360.0 / GroupSize) * FollowerIdx) + (GroupID * 15.0);
        Offset = Leader.Pawn.Location
               + (Forward * PERIMETER_RADIUS * cos(Angle * DEG_TO_RAD))
               + (Right   * PERIMETER_RADIUS * sin(Angle * DEG_TO_RAD));
    }
    return Offset;
}

// Counts living Zeds within Radius of the bot's own pawn, including
// whichever Zed currently has the bot grabbed. Used by the BreakLose
// escape failsafe below to tell "stuck because of a fluke" apart from
// "still stuck because we're at the bottom of an actual horde pile" -
// the failsafe should only ever fire for the former.
final function int CountNearbyZeds(float Radius)
{
    local KFPawn_Monster Z;
    local int ZedCount;

    if(Pawn == none)
    {
        return 0;
    }
    ZedCount = 0;
    foreach WorldInfo.AllPawns(Class'KFGame.KFPawn_Monster', Z, Pawn.Location, Radius)
    {
        if((Z != none) && Z.IsAliveAndWell())
        {
            ++ZedCount;
        }
    }
    return ZedCount;
    //return ReturnValue;
}

// ============================================================
//  New helper functions (P4/P5/P7) -- inserted after CountNearbyZeds()
// ============================================================

// AreZedsNear/HeavyZedWithin: KF2Bot extends the plain engine AIController
// (not KFAIController), so unlike the native SDK helpers referenced in the
// Design Doc, these don't already exist here -- added fresh to match the
// signatures used throughout this patch.
final function bool AreZedsNear(vector Loc, bool bRequireCanSee, float CheckRadius, int MinimalCount)
{
    local KFPawn_Monster Z;
    local int ZedCount;

    ZedCount = 0;
    foreach WorldInfo.AllPawns(class'KFGame.KFPawn_Monster', Z, Loc, CheckRadius)
    {
        if (Z == none || !Z.IsAliveAndWell()) continue;
        if (bRequireCanSee && !FastTrace(Z.Location, Loc)) continue;

        ++ZedCount;
        if (ZedCount >= MinimalCount) return true;
    }
    return false;
}

// HeavyZedWithin -- FINAL VERSION (bLargeZed + Siren class check).
// bLargeZed catches Scrake (1100 HP), Fleshpound (1500 HP), Hans, Patriarch.
// Explicit Siren class check catches KFPawn_ZedSiren (230 HP, NOT bLargeZed).
final function bool HeavyZedWithin(float Radius)
{
    local KFPawn_Monster Z;

    if (Pawn == none) return false;

    foreach WorldInfo.AllPawns(class'KFGame.KFPawn_Monster', Z, Pawn.Location, Radius)
    {
        if (Z == none || !Z.IsAliveAndWell()) continue;

        if (Z.bLargeZed || Z.Class == class'KFGameContent.KFPawn_ZedSiren')
        {
            return true;
        }
    }
    return false;
}

final function bool ShouldTacticalRetreat()
{
    if (Pawn == none) return false;

    // P4 Performance Gate: leader-only zed density scan, refreshed at most
    // once per ZED_COUNT_INTERVAL rather than every PickMove() tick.
    if (WorldInfo.TimeSeconds - LastZedCountTime >= ZED_COUNT_INTERVAL)
    {
        LastZedCountTime = WorldInfo.TimeSeconds;
        CachedZedCount   = CountNearbyZeds(RETREAT_ZED_RADIUS);
        bCachedHeavyZed  = HeavyZedWithin(RETREAT_HEAVY_RADIUS);
    }

    return (CachedZedCount >= RETREAT_ZED_TRIGGER_COUNT) || bCachedHeavyZed || ExceedsRetreatZedCount();
}

final function bool IsMeleeOnly()
{
    if (Pawn == none) return false;
    return (Pawn.Weapon != none) ? Pawn.Weapon.bMeleeWeapon : !Pawn.HasRangedAttack();
}

// P5 SYG Death March fix (Loophole 7). Returns true if it took over
// PickStyle() this call (either engaging a hazard, or holding position
// waiting for one to resolve) -- caller should return immediately.
final function bool CheckObjectiveHazard()
{
    local KFPawn_Monster P;

    if (Pawn == none) return false;

    // Siren check: engage a nearby Siren before pushing further into the
    // objective corridor. Identified by class, not HP -- Sirens are a
    // ranged/scream hazard, not a high-health one.
    foreach WorldInfo.AllPawns(class'KFGame.KFPawn_Monster', P, Pawn.Location, SIREN_CHECK_RADIUS)
    {
        if (P == none || !P.IsAliveAndWell()) continue;
        if (P.Class == class'KFGameContent.KFPawn_ZedSiren' && FastTrace(Pawn.Location, P.Location))
        {
            SetEnemy(P, true);
            GotoState('FightEnemy');
            return true;
        }
    }

    if (!AreZedsNear(Pawn.Location, false, OBJECTIVE_HAZARD_RADIUS, OBJECTIVE_HAZARD_ZED_COUNT))
    {
        return false; // corridor is clear -- safe to path
    }

    // Dense crowd in the approach corridor: fight through it first instead
    // of marching past/into it.
    if (Enemy == none || !Enemy.IsAliveAndWell())
    {
        PickNextEnemy();
    }
    if (Enemy != none && Enemy.IsAliveAndWell())
    {
        GotoState('FightEnemy');
        return true;
    }

    // Zeds are near but nothing is actually targetable yet (e.g. around a
    // corner) -- hold this PickStyle() call rather than pathing blindly
    // into them; the next call retries.
    Focus = none;
    SetFocalPoint(Pawn.Location + (VRand() * 300.0));
    return true;
}

// Last-resort escape used by BreakLose once a grab has gone on longer
// than FailsafeActivationDelay: forces the special move to end on both
// sides of the grab rather than continuing to rely on the mash input
// (TryBreakFree) eventually lining up with a break-free window. The
// caller is responsible for the MaxZedsForFailsafe crowd-size check -
// this function always forces the break once called.
//
// Assumes KFPawn (the common base of KFPawn_Human/KFPawn_Monster)
// exposes EndSpecialMove() - the standard KF2 SDK function for
// interrupting whatever special move a pawn is currently playing. If
// your SDK snapshot names this differently, that's the one line below
// to adjust.
final function ForceBreakGrapple()
{
    local KFPawn GrabbingZed;

    if(KPawn == none)
    {
        return;
    }

    GrabbingZed = KPawn.InteractionPawn;

    if((mut != none) && mut.bDebugGrapple)
    {
        mut.DebugMessage(GetHumanReadableName() $ " grapple failsafe triggered after " $ string(int(WorldInfo.TimeSeconds - GrabStartTime)) $ "s - forcing a break free.");
    }

    // Shove the Zed off first so the forced break reads as a hit landing
    // rather than it just letting go for no visible reason, then end its
    // side of the special move so it doesn't stay locked into a grab
    // animation with no InteractionPawn left to hold onto. Momentum is
    // left at zero rather than guessing at a push-back magnitude - add
    // an outward vector here if you want a more dramatic shove.
    if(GrabbingZed != none)
    {
        GrabbingZed.TakeDamage(150, self, GrabbingZed.Location, vect(0.0000000, 0.0000000, 0.0000000), Class'Engine.DamageType');
        GrabbingZed.EndSpecialMove();
    }

    // Ending the special move on the bot's own pawn is what actually
    // hands control back to normal AI logic. Also hard-clear
    // InteractionPawn as a belt-and-braces measure, in case the special
    // move class ever ignores EndSpecialMove() - BreakLose's Timer()
    // exit check reads KPawn.InteractionPawn directly, so clearing it
    // here guarantees the state actually exits next tick either way.
    KPawn.EndSpecialMove();
    KPawn.InteractionPawn = none;
    //return;
}

// --- Helper Stubs ---
//
// Small utility predicates and lookups used throughout the echelon
// hierarchy. Full implementations live in the formation, weapon, and
// tactical sections below.

function bool IsBotAlive()
{
    return (Pawn != none) && (Pawn.Health > 0);
}

function bool CanHealOthers()
{
    return MedicGun != none;
}

function bool IsHealLockedOut()
{
    return false;
}

function bool ShouldAbortRetreat()
{
    return false;
}

function vector GetObjectiveLocation()
{
    local vector ObjLoc;

    // Delegate to the Mutator's implementation. The Mutator returns
    // vect(0,0,0) when there is no objective/hold volume, so treat that
    // as "none" and fall back to our own position instead of steering
    // to world origin.
    if (mut != none)
    {
        ObjLoc = mut.GetObjectiveLocation();
        if (VSizeSq(ObjLoc) > 1.0)
        {
            return ObjLoc;
        }
    }
    if (Pawn != none)
    {
        return Pawn.Location;
    }
    return vect(0, 0, 0);
}

function bool IsBossWaveActive()
{
    local KFGameReplicationInfo GRI;

    // Uses the same API the Mutator already relies on. WorldInfo.GRI is
    // the correct path to the KFGameReplicationInfo (WorldInfo.Game is
    // a GameInfo, so a cast would be None). IsBossWave() is preferred
    // over a WaveNum threshold because WaveMax differs per game length
    // (Short/Normal/Long).
    GRI = KFGameReplicationInfo(WorldInfo.GRI);
    return (GRI != none && GRI.IsBossWave());
}

function KFPawn_Monster GetActiveBoss()
{
    return none;
}


// Diagnostic logging -- writes [KF2BotsAudit] lines to the AI profiler log.
// Rate limit per AUDIT_3B Stage 3: <= 1 line per 5s per bot per line-type.
function EchelonLog(string Msg)
{
	if (WorldInfo == None)
	{
		return;
	}
	if (!AuditRateLimit(Msg))
	{
		return;
	}
	`log("[KF2BotsAudit] " $ Name $ " " $ Msg);
}

// AUDIT_3B Stage 3: per-line-type 5s rate limit. Buckets: STATE_EXIT, GOAL,
// FOLLOWGATE_EVAL, and everything else (GEN).
function bool AuditRateLimit(string Msg)
{
	local float IterNow;
	IterNow = WorldInfo.TimeSeconds;
	if (Left(Msg, 10) ~= "STATE_EXIT")
	{
		if (IterNow - AuditLastLog_STATE_EXIT < 5.0) { return false; }
		AuditLastLog_STATE_EXIT = IterNow;
		return true;
	}
	if (Left(Msg, 4) ~= "GOAL")
	{
		if (IterNow - AuditLastLog_GOAL < 5.0) { return false; }
		AuditLastLog_GOAL = IterNow;
		return true;
	}
	if (Left(Msg, 15) ~= "FOLLOWGATE_EVAL")
	{
		if (IterNow - AuditLastLog_FOLLOWGATE < 5.0) { return false; }
		AuditLastLog_FOLLOWGATE = IterNow;
		return true;
	}
	if (IterNow - AuditLastLog_GEN < 5.0) { return false; }
	AuditLastLog_GEN = IterNow;
	return true;
}

// AUDIT_3B Step 5 (model b): while the squad order is Enroute/Holding,
// the follower ring anchors to the bot's claimed slot position around
// the squad GoalPoint; in every other state the leader's live position
// governs (existing FollowNav ring, untouched).
function bool FollowGetOrderAnchor(out vector OutLoc)
{
    local vector Loc;

    OutLoc = vect(0, 0, 0);
    if (mut == None)
    {
        return false;
    }
    if (!mut.IsSquadInObjectivePhase(KF2Bot(self)))
    {
        return false;
    }
    Loc = mut.GetSlotLocation(KF2Bot(self));
    if (Loc == vect(0, 0, 0))
    {
        return false;
    }
    OutLoc = Loc;
    return true;
}

// AUDIT_3B Stage 3: STATE_EXIT hooks. AuditStateEntry() is called from every
// state's BeginState; AuditStateExit() from every state's EndState. Dwells
// under 3s are not logged (avoids reproducing the ~56k-line Hunting churn);
// a DWELL_TOTAL line reports cumulative dwell every 60s (aggregate across
// states, to keep the per-bot log budget bounded).
function AuditStateEntry()
{
	if (WorldInfo != None)
	{
		AuditStateEntryTime = WorldInfo.TimeSeconds;
		AuditStateEntryName = GetStateName();
		// Step 6 signal: a state entry is a fresh move-intent.
		WdLastMoveIntentTime = WorldInfo.TimeSeconds;
	}
}

function AuditStateExit(name NextStateName)
{
	local float IterDwell;
	if (WorldInfo != None)
	{
		IterDwell = WorldInfo.TimeSeconds - AuditStateEntryTime;
		AuditDwellTotal += IterDwell;
		if (IterDwell >= 3.0)
		{
			EchelonLog("STATE_EXIT bot=" $ Name $ " state=" $ AuditStateEntryName $ " next=" $ NextStateName $ " reason=unspecified" $ " duration=" $ string(IterDwell));
		}
		if (WorldInfo.TimeSeconds - AuditLastLog_DWELLTOT >= 60.0)
		{
			EchelonLog("DWELL_TOTAL bot=" $ Name $ " sinceLast=" $ string(AuditDwellTotal));
			AuditDwellTotal = 0.0;
			AuditLastLog_DWELLTOT = WorldInfo.TimeSeconds;
		}
	}
}

// AUDIT_3B Stage 3: GOAL_SET / GOAL_CLEAR hooks at the ObjectiveGoal write
// and clear sites. GOAL_SET includes goal coords and ammo at set time
// (Step-2 test: GOAL_SET ammo=0 must be 0 after the ammo gate lands).
function AuditGoalLog(string Op, string Src)
{
	local string IterLoc;
	local int IterAmmo;
	if (ObjectiveGoal == None || WorldInfo == None)
	{
		return;
	}
	IterAmmo = (Pawn != None && Pawn.Weapon != None && KFWeapon(Pawn.Weapon).GetTotalAmmoAmount(0) > 0) ? 1 : 0;
	IterLoc = string(FFloor(ObjectiveGoal.Location.X / 100.0)) $ "," $ string(FFloor(ObjectiveGoal.Location.Y / 100.0)) $ "," $ string(FFloor(ObjectiveGoal.Location.Z / 100.0));
	if (Op == "GOAL_SET")
	{
		EchelonLog("GOAL_SET bot=" $ Name $ " goal=(" $ IterLoc $ ") ammo=" $ string(IterAmmo) $ " src=" $ Src);
	}
	else
	{
		EchelonLog("GOAL_CLEAR bot=" $ Name $ " src=" $ Src);
	}
}

// --- Additional Helper Stubs ---
//
// Command dispatch and the Squad Leader decision loop, the heart of the
// echelon hierarchy.


function IssueCommand(name Cmd, Vector Anchor)
{
    CurrentOrder = Cmd;
    OrderAnchor = Anchor;
    EchelonLog("IssueCommand: " $ Cmd);
}

// Squad Leader decision loop: runs on a 0.5s cadence and orchestrates the
// full tactical cycle -- room scanning, zed caching, overwatch management,
// panic/reload/wedge coordination, and tactical retreat.
function SLDecisionLoop()
{
    local Vector RetreatDest;
    local Rotator R;
    local Vector Fwd, Rgt, Up;

    // Suspend gate: derive the flag from states the codebase already
    // models (dead, pawnless, grabbed, ragdolled). Recomputed every tick
    // so it self-clears the moment the SL recovers.
    bSLLoopSuspended = (Pawn == none || Pawn.Health <= 0
                        || IsInState('BreakLose') || IsInState('IsRagdolled') || IsInState('Dead'));
    if (bSLLoopSuspended) return;

    // 4-way room scan: form the squad layout before any early returns.
    ScanRoomForFormation();

    // Zed cache and grenade broadcast: refresh the nearby-zed snapshot and
    // evaluate grenade usage.
    RefreshSquadZedCache();
    SLGrenadeCheck();
    CheckWeaponReequip();

    // Bounding overwatch: advance the leapfrog phase and detect stalls.
    UpdateOverwatchTimer();
    CheckOverwatchStall();

    // Panic broadcast: propagate wave pressure to the grunts.
    UpdatePanicBroadcast();

    // Reload drift: stagger reloads so the squad never reloads in sync.
    HandleReloadDrift();

    // Wedge mode: expire the human-centric bounding target.
    UpdateWedgeMode();

    // Hold area drift: budget the rally-point drift.
    UpdateHoldAreaDrift();

    // Tactical retreat: pull back when the zed count exceeds the safe
    // threshold, with a wall safety check.
    if(ShouldTacticalRetreat() || ExceedsRetreatZedCount())
    {
        R.Yaw = Pawn.Rotation.Yaw;
        GetAxes(R, Fwd, Rgt, Up);
        RetreatDest = Pawn.Location - (Fwd * 300.0);
        if(!IsRetreatSafe(RetreatDest))
        {
            HoldAndCrouch();
            return;
        }
        IssueCommand('CMD_TacticalRetreat', RetreatDest);
        return;
    }
}

// Lieutenant dispatch loop: placeholder for the pathing delegation that
// will be wired up once the Lieutenant nav-mesh pathing is implemented.
function LTDispatchLoop()
{
    EchelonLog("LTDispatchLoop");
}

// Captain path loop: placeholder for the 3D nav-mesh pathing that will be
// wired up once the Captain navigation is implemented.
function CaptainPathLoop()
{
    EchelonLog("CaptainPathLoop");
}

// ============================================================
//  Formation & Spatial Navigation
// ============================================================

// 4-way room scan: traces the four cardinal directions to determine the
// squad layout. Exactly 4 traces per SL per 0.5s cycle.
final function ScanRoomForFormation()
{
	local Vector Src, X, Y, Z, EndPt, HitLoc, HitNorm;
	local Rotator FlatRot;
	local Actor HitActor;
	local float FwdDistSq;
	local int ClearCount;
	local bool bFwd, bLeft, bRight, bBack;
	local name Wanted;

	if((BotRank != SQUAD_LEADER) || (Pawn == none) || bFormationScanDeferred)
	{
		return;
	}
	FormationYaw = Pawn.Rotation.Yaw;

	if(bRerouteRequested)
	{
		bRerouteRequested = false;
		++FormationEpoch;
		if((WorldInfo.TimeSeconds - LastRerouteTime) < 4.0)
		{
			CurrentFormation = 'SingleFile';
			PendingFormationCount = 0;
			FormationHoldUntil = WorldInfo.TimeSeconds + 3.0;
		}
		LastRerouteTime = WorldInfo.TimeSeconds;
	}
	if(WorldInfo.TimeSeconds < FormationHoldUntil)
	{
		return;
	}

	if(Class'KF2Bots.KF2Bot'.default.LastFormationScanTime == WorldInfo.TimeSeconds)
	{
		bFormationScanDeferred = true;
		SetTimer(0.034, false, 'DeferredFormationScan');
		return;
	}
	LastFormationScanTime = WorldInfo.TimeSeconds;

	Src = Pawn.Location;
	FlatRot.Yaw = Pawn.Rotation.Yaw;
	GetAxes(FlatRot, X, Y, Z);

	EndPt = Src + (X * FORM_LINE_DIST);
	HitActor = Trace(HitLoc, HitNorm, EndPt, Src, false);
	if((HitActor != none) && (KFPawn_Human(HitActor) == none))
	{
		FwdDistSq = VSizeSq(HitLoc - Src);
	}
	else
	{
		FwdDistSq = 422500.0;
	}
	bFwd = FwdDistSq >= 22500.0;

	bLeft = FastTrace(Src - (Y * FORM_SCAN_DIST), Src);
	bRight = FastTrace(Src + (Y * FORM_SCAN_DIST), Src);
	bBack = FastTrace(Src - (X * FORM_SCAN_DIST), Src);

	ScanMask = 0;
	if(bFwd)   { ScanMask = byte(ScanMask | 1); ++ClearCount; }
	if(bLeft)  { ScanMask = byte(ScanMask | 2); ++ClearCount; }
	if(bRight) { ScanMask = byte(ScanMask | 4); ++ClearCount; }
	if(bBack)  { ScanMask = byte(ScanMask | 8); ++ClearCount; }

	if(ClearCount >= 3)
	{
		Wanted = 'Arrowhead';
	}
	else if(ClearCount >= 2)
	{
		Wanted = 'StaggeredColumn';
	}
	else
	{
		Wanted = 'SingleFile';
	}

	if((FwdDistSq >= 360000.0) && bLeft && bRight && (Enemy != none) && Enemy.IsAliveAndWell()
		&& ((X Dot Normal(Enemy.Location - Src)) > 0.5)
		&& (WorldInfo.TimeSeconds >= LineSuppressUntil))
	{
		Wanted = 'LineFormation';
	}

	if(Wanted == CurrentFormation)
	{
		PendingFormationCount = 0;
		return;
	}
	if(Wanted != PendingFormation)
	{
		PendingFormation = Wanted;
		PendingFormationCount = 1;
		return;
	}
	CurrentFormation = Wanted;
	PendingFormationCount = 0;
	++FormationEpoch;
}

function DeferredFormationScan()
{
	bFormationScanDeferred = false;
	ScanRoomForFormation();
}

// Formation offset math: computes the world-space offset for each squad
// slot, with variance to avoid a rigid grid.
final function Vector GetFormationBase(int Slot, name Formation, bool bMirror)
{
	local Vector V;
	local float SideSign, Tier;

	Slot = Slot % 4;
	SideSign = ((Slot % 2) == 0) ? -1.0 : 1.0;
	Tier = float((Slot / 2) + 1);
	switch(Formation)
	{
		case 'Arrowhead':
			V.X = -150.0 * Tier;
			V.Y = SideSign * 150.0 * Tier;
			break;
		case 'LineFormation':
			V.X = -40.0;
			V.Y = SideSign * (120.0 * Tier);
			break;
		case 'SingleFile':
			V.X = -150.0 * float(Slot + 1);
			break;
		default:
			V.X = -130.0 * float(Slot + 1);
			V.Y = SideSign * 70.0 * (bMirror ? -1.0 : 1.0);
			break;
	}
	return V;
}

function Vector ComputeSlotOffset(optional int Slot = -1)
{
	local KF2Bot SL;
	local name Form;
	local int Epoch, Yaw;
	local float Jitter;
	local Rotator R;
	local Vector Fwd, Rgt, Up;

	if(Slot < 0)
	{
		Slot = GruntSlot;
	}
	SL = SquadLeader;
	if(SL != none)
	{
		Form = SL.CurrentFormation;
		Epoch = SL.FormationEpoch;
		Yaw = SL.FormationYaw;
		LastFormationYaw = Yaw;
	}
	else
	{
		Form = CachedOffsetFormation;
		Epoch = CachedOffsetEpoch;
		Yaw = LastFormationYaw;
	}
	if(Form == 'None')
	{
		Form = 'StaggeredColumn';
	}

	if(!bOffsetCached || (Epoch != CachedOffsetEpoch) || (Slot != CachedOffsetSlot) || (Form != CachedOffsetFormation))
	{
		bOffsetCached = true;
		CachedOffsetEpoch = Epoch;
		CachedOffsetSlot = Slot;
		CachedOffsetFormation = Form;
		Jitter = 0.10 + (0.05 * FRand());
		CachedLocalOffset = GetFormationBase(Slot, Form, Rand(2) == 0);
		CachedLocalOffset.X *= 1.0 + ((Rand(2) == 0) ? Jitter : -Jitter);
		CachedLocalOffset.Y *= 1.0 + ((Rand(2) == 0) ? Jitter : -Jitter);
	}

	R.Yaw = Yaw;
	GetAxes(R, Fwd, Rgt, Up);
	return (Fwd * CachedLocalOffset.X) + (Rgt * CachedLocalOffset.Y);
}

// Line formation: inherited focus from the SL with independent grunt
// line-of-sight checks.
final function bool SyncLineFocus()
{
	local Pawn LT;

	if((BotRank != GRUNT) || (Pawn == none))
	{
		return false;
	}
	if((SquadLeader != none) && (SquadLeader.CurrentFormation == 'LineFormation'))
	{
		LT = SquadLeader.Enemy;
		if((LT != none) && LT.IsAliveAndWell())
		{
			if(InheritedEnemy != LT)
			{
				InheritedEnemy = LT;
				Enemy = LT;
				Focus = LT;
				if(GetStateName() != 'FightEnemy')
				{
					GotoState('FightEnemy');
				}
			}
			return false;
		}
	}
	if(InheritedEnemy != none)
	{
		if(Enemy == InheritedEnemy)
		{
			Enemy = none;
			Focus = none;
			Pawn.StopFiring();
			InheritedEnemy = none;
			if(GetStateName() == 'FightEnemy')
			{
				PickCombatStyle();
				return true;
			}
		}
		InheritedEnemy = none;
	}
	return false;
}

final function bool HasOwnFireLine(Actor T)
{
	if((T == none) || (Pawn == none))
	{
		return false;
	}
	if((T != FireLineTarget) || (WorldInfo.TimeSeconds >= NextFireLineCheck))
	{
		FireLineTarget = T;
		NextFireLineCheck = WorldInfo.TimeSeconds + 0.5;
		bFireLineClear = FastTrace(T.Location, Pawn.Location + (vect(0.0, 0.0, 1.0) * Pawn.BaseEyeHeight));
	}
	return bFireLineClear;
}

// Wall safety: validates offset targets against geometry, tracks blocked
// attempts, requests reroutes, and validates retreat paths.
final function bool ValidateOffsetTarget(Vector OffsetTarget)
{
	if(FastTrace(OffsetTarget, Pawn.Location))
	{
		BlockedCounter = 0;
		return true;
	}
	if(++BlockedCounter >= 3)
	{
		BlockedCounter = 0;
		if((SquadLeader != none) && (SquadLeader.Pawn != none) && SquadLeader.Pawn.IsAliveAndWell())
		{
			SquadLeader.RequestRerouteWithBlock(Pawn.Location);
		}
	}
	return false;
}

function RequestRerouteWithBlock(Vector BlockedPos)
{
	if(BotRank == SQUAD_LEADER)
	{
		bRerouteRequested = true;
	}
}

final function bool IsDirClearCached(Vector Dest)
{
	local Vector X, Y, Z, Dir;
	local Rotator R;
	local float DX, DY;
	local byte Bit;

	R.Yaw = FormationYaw;
	GetAxes(R, X, Y, Z);
	Dir = Normal2D(Dest - Pawn.Location);
	DX = Dir Dot X;
	DY = Dir Dot Y;
	if((DX * DX) >= (DY * DY))
	{
		if(DX > 0.0) { Bit = 1; } else { Bit = 8; }
	}
	else
	{
		if(DY > 0.0) { Bit = 4; } else { Bit = 2; }
	}
	return (ScanMask & Bit) != 0;
}

final function bool IsRetreatSafe(Vector RetreatDest)
{
	local KFPawn_Monster M;
	local byte Zeds;
	Zeds = 0;
	if(!IsDirClearCached(RetreatDest))
	{
		return false;
	}
	foreach VisibleCollidingActors(class'KFPawn_Monster', M, 500.0, RetreatDest)
	{
		if(M.IsAliveAndWell() && (++Zeds >= 20))
		{
			return false;
		}
	}
	return true;
}

final function SetSquadCrouchHold()
{
	bSquadCrouchHold = true;
	SetTimer(3.0, false, 'ClearSquadCrouchHold');
}

function ClearSquadCrouchHold()
{
	bSquadCrouchHold = false;
}

final function HoldAndCrouch()
{
	IssueCommand('CMD_HoldArea', Pawn.Location);
	SetSquadCrouchHold();
}

final function bool TryIssueSafeAnchor(Vector NewAnchor)
{
	if((Pawn != none) && IsDirClearCached(NewAnchor))
	{
		bSquadCrouchHold = false;
		IssueCommand('CMD_HoldArea', NewAnchor);
		return true;
	}
	SetSquadCrouchHold();
	return false;
}

final function ApplySquadCrouchHold()
{
	local bool bWant;

	bWant = (SquadLeader != none) && SquadLeader.bSquadCrouchHold;
	if(bWant != bHoldCrouching)
	{
		bHoldCrouching = bWant;
		Pawn.ShouldCrouch(bWant);
	}
}

// Staggered timer initialization: offsets each bot's decision timer so
// they don't all fire in the same frame.
final function ClearRankTimers()
{
	ClearTimer('StartSLLoop');
	ClearTimer('SLDecisionLoop');
	ClearTimer('StartLTLoop');
	ClearTimer('LTDispatchLoop');
	ClearTimer('StartCaptainLoop');
	ClearTimer('CaptainPathLoop');
	ClearTimer('DeferredFormationScan');
	ClearTimer('ClearSquadCrouchHold');
	// Grenade timers
	ClearTimer('SLGrenadeLOSPhase');
	ClearTimer('ClearGrenadeSignal');
	GrenadeSignal = false;
	GrenadeThrowsLeft = 0;
	GrenadeTargetPawn = none;
	bFormationScanDeferred = false;
}

// Obs 11 -- Returns the rank display name for the name tag.
final function name GetRankName()
{
    switch (BotRank)
    {
        case CAPTAIN:
            return 'Captain';
        case LIEUTENANT:
            return 'Lieutenant';
        case SQUAD_LEADER:
            return 'SquadLeader';
        default:
            return 'Grunt';
    }
    //return ReturnValue;
}

// Obs 11 -- Updates the PlayerName to include the [Rank] prefix.
// Called from PreBeginPlay so the HUD shows [Captain] Alice etc.
final function UpdateRoleNameTag()
{
    local string IDStr;
    local int StartIdx;
    if (PlayerReplicationInfo != none)
    {
        // Store the base name (without rank prefix) for later refresh.
        if (BasePlayerName == "")
        {
            BasePlayerName = PlayerReplicationInfo.PlayerName;
        }
        // Extract the ID number from "Bot_1234" -> "1234"
        StartIdx = 0;
        if (Left(BasePlayerName, 4) == "Bot_")
        {
            StartIdx = 4;
        }
        IDStr = Mid(BasePlayerName, StartIdx, Len(BasePlayerName) - StartIdx);
        PlayerReplicationInfo.PlayerName = "[" $ GetRankName() $ "] " $ IDStr;
    }
}
 
// Bug 2 fix -- Reconstructs the PlayerName from the bot's base name + current rank.
// Called from InitializePlatoon() after rank assignment so the HUD reflects
// the newly-assigned rank (not the spawn-time default of GRUNT).
// Self-contained: extracts the base name from the current PlayerName by
// stripping any existing "[...]" prefix, so it works even if BasePlayerName
// was never initialized by UpdateRoleNameTag().
final function RefreshRoleNameTag()
{
    local string BaseName;
    local int BracketsEnd;
    local int StartIdx;

    if (PlayerReplicationInfo == none)
    {
        return;
    }

    // Use cached BasePlayerName if available; otherwise extract from current name.
    if (BasePlayerName != "")
    {
        BaseName = BasePlayerName;
    }
    else
    {
        BaseName = PlayerReplicationInfo.PlayerName;
        // Strip any existing "[Rank]" prefix from the current name.
        if (Left(BaseName, 1) == "[")
        {
            BracketsEnd = InStr(BaseName, "]");
            if (BracketsEnd >= 0)
            {
                BaseName = Mid(BaseName, BracketsEnd + 1, Len(BaseName) - BracketsEnd - 1);
                // Trim leading space
                if (Left(BaseName, 1) == " ")
                {
                    BaseName = Mid(BaseName, 1, Len(BaseName) - 1);
                }
            }
        }
        // Store for future refreshes.
        BasePlayerName = BaseName;
    }

    // Strip "Bot_" prefix if present (legacy naming).
    StartIdx = 0;
    if (Left(BaseName, 4) == "Bot_")
    {
        StartIdx = 4;
    }
    PlayerReplicationInfo.PlayerName = "[" $ GetRankName() $ "] " $ Mid(BaseName, StartIdx, Len(BaseName) - StartIdx);
}

final function SeedGruntGates()
{
	LastOffsetUpdate = WorldInfo.TimeSeconds - (FRand() * 0.2);
	LastHealthCheck = WorldInfo.TimeSeconds - (FRand() * 2.0);
	NextFireLineCheck = WorldInfo.TimeSeconds + (FRand() * 0.5);
}

final function ArmRankTimers()
{
	ClearRankTimers();
	switch(BotRank)
	{
		case SQUAD_LEADER:
			SetTimer(0.01 + (FRand() * 0.49), false, 'StartSLLoop');
			break;
		case LIEUTENANT:
			SetTimer(0.01 + (FRand() * 0.99), false, 'StartLTLoop');
			break;
		case CAPTAIN:
			SetTimer(0.01 + (FRand() * 2.99), false, 'StartCaptainLoop');
			break;
		default:
			SeedGruntGates();
			break;
	}
}

function StartSLLoop()
{
	SetTimer(0.5, true, 'SLDecisionLoop');
	SLDecisionLoop();
}

function StartLTLoop()
{
	SetTimer(1.0, true, 'LTDispatchLoop');
	LTDispatchLoop();
}

function StartCaptainLoop()
{
	SetTimer(3.0, true, 'CaptainPathLoop');
	CaptainPathLoop();
}

final function SetBotRank(EBotRank NewRank)
{
	BotRank = NewRank;
	ArmRankTimers();
}

// ============================================================
//  Weapon & Combat Discipline
// ============================================================

// Fire trajectory validation: SL-side blocked shooter tracking
final function NotifyBlockedShooter(KF2Bot Shooter)
{
	if(BotRank != SQUAD_LEADER)
	{
		return;
	}
	if((WorldInfo.TimeSeconds - BlockedShooterWindowStart) > 1.5)
	{
		BlockedShooterWindowStart = WorldInfo.TimeSeconds;
		BlockedShooterCount = 0;
	}
	if(++BlockedShooterCount >= 2)
	{
		BlockedShooterCount = 0;
		LineSuppressUntil = WorldInfo.TimeSeconds + 4.0;
		if(CurrentFormation == 'LineFormation')
		{
			CurrentFormation = 'StaggeredColumn';
			PendingFormationCount = 0;
			++FormationEpoch;
		}
	}
}

// Magazine-empty reload gate
final function bool ShouldReload(KFWeapon W)
{
	if(W == none)
	{
		return false;
	}
	if(W.HasAmmo(BOTFM_PRIMARY, 1))
	{
		return false;
	}
	return W.HasAnyAmmo();
}

// Weapon range efficiency gate -- EffectiveRange lives on KFWeaponDefinition,
// which is not directly reachable from a KFWeapon instance. Firearms keep a
// wide default; close-range weapons (shotguns, flamethrowers) get a short
// gate so they close distance instead of firing from afar.
final function float GetWeaponEffectiveRangeUU(KFWeapon W)
{
	if(W == none)
	{
		return DefaultWeaponEffectiveRangeUU;
	}
	if(W.IsA('KFWeap_ShotgunBase'))
	{
		return ShotgunEffectiveRangeUU;
	}
	if(W.IsA('KFWeap_Flame_Flamethrower'))
	{
		return FlamethrowerEffectiveRangeUU;
	}
	// ShrinkRayGun, FreezeThrower, and any future FlameBase children
	// share the close-range gate; Flamethrower is matched above first.
	if(W.IsA('KFWeap_FlameBase'))
	{
		return FlamethrowerEffectiveRangeUU;
	}
	return DefaultWeaponEffectiveRangeUU;
}

final function bool IsInEffectiveRange(Actor T)
{
	local KFWeapon W;
	local float MaxRange;

	W = KFWeapon(Pawn.Weapon);
	if((W == none) || (T == none))
	{
		return false;
	}
	if(W != RangeCacheWeapon)
	{
		RangeCacheWeapon = W;
		MaxRange = GetWeaponEffectiveRangeUU(W);
		RangeCacheSq = MaxRange * MaxRange;
	}
	if(RangeCacheSq <= 0.0)
	{
		return true;
	}
	return VSizeSq(T.Location - Pawn.Location) <= RangeCacheSq;
}

final function CloseToEffectiveRange()
{
	if(BotRank == GRUNT)
	{
		MoveToX(Pawn.Location + (Normal2D(Enemy.Location - Pawn.Location) * 250.0), Enemy);
	}
	else if(ActorReachable(Enemy))
	{
		MoveTowardX(Enemy, Enemy);
	}
	else if(BuildPathToward(Enemy))
	{
		MoveTowardX(MoveTarget, Enemy);
	}
	else
	{
		MoveToX(Pawn.Location + (Normal2D(Enemy.Location - Pawn.Location) * 300.0), Enemy);
	}
}

// Ammo-crate reset and no permanent melee lock
final function CheckWeaponReequip()
{
	local bool bReady;

	if(!bFallbackWeapon || (Pawn == none))
	{
		return;
	}
	if((FallbackPrimary == none) || (Pawn.Weapon == FallbackPrimary))
	{
		bFallbackWeapon = false;
		return;
	}
	if(bFallbackHadSpare)
	{
		bReady = ((WorldInfo.TimeSeconds - FallbackSince) > 1.5) && ((Enemy == none) || (CountNearbyZedsCached(500.0) < 3));
	}
	else
	{
		bReady = FallbackPrimary.HasAnyAmmo();
	}
	if(bReady)
	{
		bFallbackWeapon = false;
		Pawn.InvManager.SetCurrentWeapon(FallbackPrimary);
		return;
	}
	if((Pawn.Weapon != none) && Pawn.Weapon.bMeleeWeapon && (NextFallbackPoll < WorldInfo.TimeSeconds))
	{
		NextFallbackPoll = WorldInfo.TimeSeconds + 1.0;
		SwitchToBestWeapon(true);
	}
}

// Event-driven grenading
final function bool ShouldThrowGrenade(out Actor Aim, bool bFromSignal, Actor CurEnemy)
{
	local KF2Bot SL;

	Aim = none;
	bFromSignal = false;
	if((KFInvManager == none) || (KFInvManager.GrenadeCount <= 0) || (NextGrenadeTimer > WorldInfo.TimeSeconds))
	{
		return false;
	}
	if(BotRank == SQUAD_LEADER)
	{
		SL = KF2Bot(self);
	}
	else
	{
		SL = SquadLeader;
	}

	// (1) SL broadcast
	if((SL != none) && SL.GrenadeSignal && (SL.GrenadeThrowsLeft > 0) && (SL.GrenadeTargetPawn != none)
		&& SL.GrenadeTargetPawn.IsAliveAndWell()
		&& (VSizeSq(SL.GrenadeTargetPawn.Location - Pawn.Location) < 90000.0))
	{
		Aim = SL.GrenadeTargetPawn;
		bFromSignal = true;
		return true;
	}
	// (2) HearNoise
	if((CurEnemy != none) && (HearNoiseZedCount >= 2) && (WorldInfo.TimeSeconds < HearNoiseExpireTime)
		&& (VSizeSq(LastNoiseLoc - Pawn.Location) < 160000.0))
	{
		Aim = CurEnemy;
		return true;
	}
	// (3) self-preservation
	if((CurEnemy != none) && (Pawn.Health < (Pawn.HealthMax * 0.3)) && (CountNearbyZedsCached(200.0) >= 2))
	{
		Aim = CurEnemy;
		return true;
	}
	return false;
}

final function bool TryThrowGrenade(KFWeapon W, Actor CurEnemy)
{
	local Actor Aim;
	local bool bFromSignal;
	bFromSignal = false;

	if(!ShouldThrowGrenade(Aim, bFromSignal, CurEnemy))
	{
		GrenadeAimTicks = 0;
		return false;
	}
	if(NeedToTurn(Aim.Location))
	{
		if(++GrenadeAimTicks > 3)
		{
			GrenadeAimTicks = 0;
			NextGrenadeTimer = WorldInfo.TimeSeconds + 2.0;
			return false;
		}
		Focus = Aim;
		return true;
	}
	GrenadeAimTicks = 0;
	NextGrenadeTimer = WorldInfo.TimeSeconds + 4.0 + (FRand() * 3.0);
	if(bFromSignal && (SquadLeader != none) && (SquadLeader.GrenadeThrowsLeft > 0))
	{
		--SquadLeader.GrenadeThrowsLeft;
	}
	Target = Aim;
	Focus = Aim;
	W.StartFire(BOTFM_GRENADE);
	return true;
}

function SLGrenadeCheck()
{
	local int I, Near;

	if((BotRank != SQUAD_LEADER) || (Pawn == none) || GrenadeSignal || (NextGrenadeSignalTime > WorldInfo.TimeSeconds))
	{
		return;
	}
	for(I = 0; I < SquadZedCount; I++)
	{
		if((SquadZedCache[I] != none) && (SquadZedCache[I].Health > 0)
			&& (VSizeSq(SquadZedCache[I].Location - Pawn.Location) < 90000.0))
		{
			++Near;
		}
	}
	if(Near >= 3)
	{
		SetTimer(0.07, false, 'SLGrenadeLOSPhase');
	}
}

function SLGrenadeLOSPhase()
{
	local int I, Traces, NoLOS, Near;
	local Pawn Z, Pick;

	if((BotRank != SQUAD_LEADER) || (Pawn == none))
	{
		return;
	}
	for(I = 0; I < SquadZedCount; I++)
	{
		Z = SquadZedCache[I];
		if((Z == none) || (Z.Health <= 0) || (VSizeSq(Z.Location - Pawn.Location) >= 90000.0))
		{
			continue;
		}
		++Near;
		if(Traces < 3)
		{
			++Traces;
			if(!FastTrace(Z.Location, Pawn.Location))
			{
				++NoLOS;
				if(Pick == none)
				{
					Pick = Z;
				}
			}
		}
	}
	if((Near >= 3) && (NoLOS >= 2))
	{
		GrenadeSignal = true;
		GrenadeThrowsLeft = 2;
		GrenadeTargetPawn = Pick;
		NextGrenadeSignalTime = WorldInfo.TimeSeconds + 6.0;
		SetTimer(2.0, false, 'ClearGrenadeSignal');
	}
}

function ClearGrenadeSignal()
{
	GrenadeSignal = false;
	GrenadeThrowsLeft = 0;
	GrenadeTargetPawn = none;
}

// Weapon management: reload, sidearm, and melee-fallback discipline
final function bool HandleWeaponManagement(KFWeapon W)
{
	local KFWeapon Best;

	// Reload gate
	if(ShouldReload(W))
	{
		if(NextReloadAttempt < WorldInfo.TimeSeconds)
		{
			NextReloadAttempt = WorldInfo.TimeSeconds + 1.0;
			W.StartFire(BOTFM_RELOAD);
		}
		return true;
	}

	// No ammo at all: switch to best loaded weapon
	if(!W.HasAnyAmmo())
	{
		SwitchToBestWeapon(true);
		Best = KFWeapon(Pawn.Weapon);
		if(Best != W)
		{
			bFallbackWeapon = true;
			bFallbackHadSpare = W.HasAnyAmmo();
			FallbackPrimary = W;
			FallbackSince = WorldInfo.TimeSeconds;
			return true;
		}
		// No better weapon: try melee
		if((Pawn.Weapon == none) || (Pawn.Weapon.bMeleeWeapon == false))
		{
			SwitchToBestWeapon(true);
		}
		return true;
	}
	return false;
}

// Cached nearby-zed count: reads from SquadZedCache, zero AllPawns scan
final function int CountNearbyZedsCached(float Radius)
{
	local int I, C;
	local float R2;

	R2 = Radius * Radius;
	C = 0;
	for(I = 0; I < SquadZedCount; I++)
	{
		if((SquadZedCache[I] != none) && (SquadZedCache[I].Health > 0)
			&& (VSizeSq(SquadZedCache[I].Location - Pawn.Location) < R2))
		{
			++C;
		}
	}
	return C;
}

// Refresh zed cache: single AllPawns foreach per SL
final function RefreshSquadZedCache()
{
	local KFPawn_Monster P;

	SquadZedCount = 0;
	if(Pawn == none)
	{
		return;
	}
	foreach WorldInfo.AllPawns(class'KFPawn_Monster', P, Pawn.Location, 300.0)
	{
		if(P == none)
		{
			continue;
		}
		if(P.Health > 0)
		{
			if(SquadZedCount < 16)
			{
				SquadZedCache[SquadZedCount] = P;
				++SquadZedCount;
			}
		}
	}
}

// ============================================================
//  Tactical Squad Maneuvers
// ============================================================

// ============================================================
//  BATCH 5: Tactical Squad Maneuvers (Tasks 5.1 a" 5.6)
// ============================================================

// --- Shared Helpers ---

final function ApplyCrouch(bool bWant)
{
    if (Pawn != none && Pawn.bWantsToCrouch != bWant)
    {
        Pawn.ShouldCrouch(bWant);
    }
}

final function bool IsHostileZed(Pawn P)
{
    local KFPawn_Monster M;
    M = KFPawn_Monster(P);
    return (M != none && M.IsAliveAndWell());
}

// --- 5.1 BOUNDING OVERWATCH LEAPFROG ---

// Overwatch phase toggle: advances the leapfrog phase on a 5.0s cadence
function ToggleOverwatchPhase()
{
    if (BotRank != SQUAD_LEADER || Pawn == none)
    {
        ClearTimer('ToggleOverwatchPhase');
        return;
    }
    bOverwatchPhase = !bOverwatchPhase;
    if (bOverwatchAllMove && WorldInfo.TimeSeconds >= OverwatchResetUntil)
    {
        bOverwatchAllMove = false; // Edge #10 reset window elapsed
    }
    BroadcastOverwatchState();
}

// Broadcast the overwatch state to all grunts in the squad
function BroadcastOverwatchState()
{
    local int i;
    for (i = 0; i < 4 && i < 4; i++)
    {
        if (SquadMembers[i] != none && SquadMembers[i].Pawn != none)
        {
            SquadMembers[i].ReceiveOverwatchState(bOverwatchPhase, byte(i), bOverwatchAllMove);
        }
    }
}

// Assign formation slots to each grunt based on the current layout
function AssignSquadSlots()
{
    local int i;
    for (i = 0; i < 4 && i < 4; i++)
    {
        if (SquadMembers[i] != none)
        {
            SquadMembers[i].OverwatchSlot = byte(i);
        }
    }
}

// Update the overwatch timer on each 0.5s SL decision cycle
function UpdateOverwatchTimer()
{
    local int i;
    local bool bMoveOrder;

    bMoveOrder = (CurrentOrder == 'CMD_PushAnchor' || CurrentOrder == 'CMD_TacticalRetreat');
    if (bMoveOrder)
    {
        if (!IsTimerActive('ToggleOverwatchPhase'))
        {
            bOverwatchAllMove = false;
            StuckCounter = 0;
            BroadcastOverwatchState();
            SetTimer(OW_TOGGLE_INTERVAL, true, 'ToggleOverwatchPhase');
        }
    }
    else
    {
        AssignSquadSlots();
        if (IsTimerActive('ToggleOverwatchPhase'))
        {
            ClearTimer('ToggleOverwatchPhase');
            bOverwatchAllMove = false;
            StuckCounter = 0;
            for (i = 0; i < 4 && i < 4; i++)
            {
                if (SquadMembers[i] != none)
                {
                    SquadMembers[i].bOverwatchMoving = false;
                    SquadMembers[i].OverwatchStuckTime = 0.0;
                }
            }
        }
    }
}

// Stall detection: detect when overwatch movement is stuck and reset
function CheckOverwatchStall()
{
    local int i, stuckCount;
    local KF2Bot G;
    local vector newAnchor;

    if (!IsTimerActive('ToggleOverwatchPhase') || bOverwatchAllMove)
    {
        StuckCounter = 0;
        return;
    }

    stuckCount = 0;
    for (i = 0; i < 4 && i < 4; i++)
    {
        G = SquadMembers[i];
        if (G != none && G.Pawn != none && G.GetStateName() != 'BreakLose' && G.IsOverwatchStuck())
        {
            stuckCount++;
        }
    }

    if (stuckCount < 2)
    {
        StuckCounter = 0;
        return;
    }

    StuckCounter++;
    if (StuckCounter < 2)
    {
        return;
    }

    StuckCounter = 0;
    bOverwatchAllMove = true;
    OverwatchResetUntil = WorldInfo.TimeSeconds + OW_TOGGLE_INTERVAL;
    BroadcastOverwatchState();

    newAnchor = OrderAnchor + (VRand() * 150.0);
    newAnchor.Z = OrderAnchor.Z;
    IssueCommand(CurrentOrder, newAnchor);
}

// Grunt receives the overwatch state broadcast from the SL
function ReceiveOverwatchState(bool bPhase, byte InSlot, bool bAllMove)
{
    if (Pawn == none) return;
    GruntOverwatchPhase = bPhase;
    OverwatchSlot = InSlot;
    bOverwatchAllMove = bAllMove;
    OverwatchOffset = ComputeSlotOffset(InSlot);
}

// Check if the grunt is stuck in overwatch movement
final function bool IsOverwatchStuck()
{
    return (bOverwatchMoving && OverwatchStuckTime >= OW_STUCK_TIME);
}

// Grunt overwatch movement: leapfrog toward the overwatch target
function bool UpdateOverwatchMovement(out vector OutMovePos)
{
    local bool bMovingTeam;
    local float now;
    local vector moved, toGoal;
    local Pawn tgt;

    if (SquadLeader == none || SquadLeader.Pawn == none)
    {
        bOverwatchMoving = false;
        return true;
    }

    now = WorldInfo.TimeSeconds;

    if (bOverwatchAllMove)
    {
        bMovingTeam = true;
    }
    else if ((OverwatchSlot & 1) == 1)
    {
        bMovingTeam = GruntOverwatchPhase;
    }
    else
    {
        bMovingTeam = !GruntOverwatchPhase;
    }
    bOverwatchMoving = bMovingTeam;

    if (bMovingTeam)
    {
        ApplyCrouch(false);
        OutMovePos = SquadLeader.Pawn.Location + OverwatchOffset;

        if (now - OverwatchSampleTime >= 0.5)
        {
            moved = Pawn.Location - OverwatchSamplePos;
            moved.Z = 0.0;
            toGoal = OutMovePos - Pawn.Location;
            toGoal.Z = 0.0;
            if (VSizeSq(toGoal) > OW_STUCK_MIN_DIST_SQ && VSizeSq(moved) < OW_STUCK_MOVE_SQ)
            {
                OverwatchStuckTime += (now - OverwatchSampleTime);
            }
            else
            {
                OverwatchStuckTime = 0.0;
            }
            OverwatchSamplePos = Pawn.Location;
            OverwatchSampleTime = now;
        }
        return true;
    }

    // Covering team
    OverwatchStuckTime = 0.0;
    OverwatchSampleTime = now;
    OverwatchSamplePos = Pawn.Location;
    ApplyCrouch(true);

    if (GetStateName() != 'FightEnemy')
    {
        tgt = Enemy;
        if (tgt == none) tgt = SquadLeader.Enemy;
        if (tgt != none && tgt.IsAliveAndWell())
        {
            if (now >= NextOverwatchLOSTime)
            {
                NextOverwatchLOSTime = now + 0.5;
                bOverwatchLOS = FastTrace(tgt.Location, Pawn.Location);
            }
            if (bOverwatchLOS)
            {
                FireWeaponAt(tgt);
            }
        }
    }
    return false;
}

// Re-sync the overwatch phase after breaking free from a grab
function OnBreakLoseComplete()
{
    if (SquadLeader != none && SquadLeader.Pawn != none)
    {
        ReceiveOverwatchState(SquadLeader.bOverwatchPhase, OverwatchSlot, SquadLeader.bOverwatchAllMove);
    }
    OverwatchStuckTime = 0.0;
    OverwatchSampleTime = WorldInfo.TimeSeconds;
    RescueUntil = 0.0;
}

// --- 5.2 360-DEGREE SECTOR WATCH ---

// Sector watch: sweep the 360-degree sector when holding area
function UpdateSectorWatch()
{
    local float now, dt;
    local int baseYaw, scanOffset;
    local Rotator R;

    if (Pawn == none) return;
    now = WorldInfo.TimeSeconds;

    ApplyCrouch(true);

    if ((Enemy != none && Enemy.IsAliveAndWell()) || now < NoiseGlanceUntil)
    {
        SectorLastTime = now;
        return;
    }

    if (SquadLeader != none && SquadLeader.Pawn != none && SquadLeader.Pawn.IsAliveAndWell())
    {
        LastValidSquadLeaderYaw = SquadLeader.Pawn.Rotation.Yaw;
    }
    else if (LastValidSquadLeaderYaw == 0)
    {
        LastValidSquadLeaderYaw = Pawn.Rotation.Yaw;
    }

    dt = now - SectorLastTime;
    SectorLastTime = now;
    if (dt > 0.5) dt = 0.2;

    SectorScanPhase += dt * SW_SCAN_OMEGA * PanicScanSpeedMultiplier;
    if (SectorScanPhase > SW_TWO_PI) SectorScanPhase -= SW_TWO_PI;

    baseYaw = LastValidSquadLeaderYaw + (OverwatchSlot * 16384);
    scanOffset = int(SW_SCAN_AMP_DEG * PanicScanSpeedMultiplier * Sin(SectorScanPhase + (float(OverwatchSlot) * 0.7853982)) * SW_DEG_TO_URU);

    R.Pitch = 0;
    R.Roll = 0;
    R.Yaw = (baseYaw + scanOffset) & 65535;

    SetFocalPoint(Pawn.Location + (vector(R) * 512.0));
}

// --- 5.3 CQB FLASHLIGHT / BASH INTERLOCK ---

// CQB proximity: flashlight and bash interlock in close quarters
function HandleCQBProximity()
{
    local float distSq, now;
    local KFWeapon W;
    local KFPawn_Human KFPH;
    local vector awayDir;
    local bool bWantLight;

    if (Pawn == none || Enemy == none || Enemy.Health <= 0 || CurrentFormation != 'SingleFile')
    {
        return;
    }

    now = WorldInfo.TimeSeconds;
    KFPH = KFPawn_Human(Pawn);
    distSq = VSizeSq(Enemy.Location - Pawn.Location);

    if (distSq < CQB_BASH_SQ)
    {
        if (now >= NextBashTime)
        {
            NextBashTime = now + CQB_BASH_INTERVAL;

            W = KFWeapon(Pawn.Weapon);
            if (W != none)
            {
                if (W.bMeleeWeapon) W.StartFire(0);
                else W.StartFire(3);
            }

            if (Pawn.Physics == PHYS_Walking)
            {
                awayDir = Pawn.Location - Enemy.Location;
                awayDir.Z = 0.0;
                Pawn.Velocity = Normal(awayDir) * CQB_STEPBACK_SPEED;
            }

            if (KFPH != none)
            {
                KFPH.SetFlashlight(!KFPH.bFlashlightOn, false);
            }
        }
    }
    else if (KFPH != none)
    {
        bWantLight = (distSq >= CQB_MID_SQ);
        if (KFPH.bFlashlightOn != bWantLight)
        {
            KFPH.SetFlashlight(bWantLight, false);
        }
    }
}

// --- Buddy Rescue ---
//
// SL-level handler: when a teammate Grunt is grabbed, dispatch the two
// nearest squadmates to the grab location to attempt a rescue.

function OnGruntGrabbed(KF2Bot GruntBot)
{
    local int i;
    local KF2Bot M, N1, N2;
    local float d, D1, D2;
    local vector grabLoc;
    local Pawn grabber;
    local KFPawn KFP;

    if (GruntBot == none || GruntBot.Pawn == none) return;

    grabLoc = GruntBot.Pawn.Location;
    KFP = KFPawn(GruntBot.Pawn);
    if (KFP != none) grabber = KFP.InteractionPawn;

    D1 = RESCUE_RANGE_SQ;
    D2 = RESCUE_RANGE_SQ;
    N1 = none;
    N2 = none;

    for (i = 0; i < 4 && i < 4; i++)
    {
        M = SquadMembers[i];
        if (M == none || M == GruntBot || M.Pawn == none || M.GetStateName() == 'BreakLose' || !M.Pawn.IsAliveAndWell())
        {
            continue;
        }
        d = VSizeSq(M.Pawn.Location - grabLoc);
        if (d < D1)
        {
            D2 = D1; N2 = N1;
            D1 = d;  N1 = M;
        }
        else if (d < D2)
        {
            D2 = d;  N2 = M;
        }
    }

    if (N1 != none) N1.BeginRescue(grabLoc, grabber);
    if (N2 != none) N2.BeginRescue(grabLoc, grabber);
}

// Grunt-level handler: move toward the grab location, focus the grabber,
// and engage it if it is a hostile Zed.

function BeginRescue(vector GrabLoc, Pawn Grabber)
{
    if (Pawn == none || IsGruntCombatLocked()) return;

    RescueLoc = GrabLoc;
    RescueUntil = WorldInfo.TimeSeconds + RESCUE_DURATION;
    IssueCommand('CMD_FocusTarget', GrabLoc);

    if (IsHostileZed(Grabber))
    {
        SetEnemy(Grabber);
        GruntEnterCombat(Grabber);
    }
}

// --- Cover-Aware Crouching ---
//
// Crouches a Grunt when the squad is single-file behind cover and the SL's
// target is within engagement range, keeping the Grunt low profile.

function UpdateCoverCrouch()
{
    local bool bWantCrouch;

    if (WorldInfo.TimeSeconds < StyleCrouchUntil) return;

    bWantCrouch = false;
    if (SquadLeader != none && CurrentFormation == 'SingleFile' && SquadLeader.Enemy != none)
    {
        if (SquadLeader.Enemy.IsAliveAndWell()
            && VSizeSq(SquadLeader.Enemy.Location - Pawn.Location) < COVER_RANGE_SQ)
        {
            bWantCrouch = true;
        }
    }
    ApplyCrouch(bWantCrouch);
}

// --- Grunt Combat Style Router ---
//
// Guards combat entry: returns true when the Grunt is in a state that
// should not be interrupted (break, healing, ragdoll, dead, victory).

final function bool IsGruntCombatLocked()
{
    return (GetStateName() == 'BreakLose' || GetStateName() == 'HealingSelf' || GetStateName() == 'HealOther'
         || GetStateName() == 'HealRanged' || GetStateName() == 'TacticalRetreat' || GetStateName() == 'IsRagdolled'
         || GetStateName() == 'Dead' || GetStateName() == 'VictoryDance');
}

// Sight entry point: if already fighting, optionally swap the target;
// otherwise transition into combat.

function GruntOnSight(Pawn Seen)
{
    if (Pawn == none || !IsHostileZed(Seen)) return;

    if (GetStateName() == 'FightEnemy')
    {
        if (Enemy == none || !Enemy.IsAliveAndWell()) SetEnemy(Seen);
        return;
    }
    GruntEnterCombat(Seen);
}

// Combat entry: assign the enemy, pick melee vs. ranged style, and drive
// the Grunt into the FightEnemy state.

function GruntEnterCombat(Pawn NewEnemy)
{
    if (Pawn == none || NewEnemy == none || IsGruntCombatLocked()) return;

    if (Enemy != NewEnemy && (Enemy == none || !Enemy.IsAliveAndWell()))
    {
        SetEnemy(NewEnemy);
    }
    if (Enemy == none) return;

    bGruntMeleeStyle = IsMeleeOnly();
    GotoState('FightEnemy');
}

// Combat style: melee Grunts push straight at the target; ranged Grunts
// strafe or crouch to break line of sight.

function GruntPickCombatStyle()
{
    local vector toEnemy, strafeDir;

    if (Pawn == none || Enemy == none) return;

    if (bGruntMeleeStyle)
    {
        ApplyCrouch(false);
        MoveTowardX(Enemy);
        return;
    }

    if (FRand() < 0.5)
    {
        ApplyCrouch(false);
        toEnemy = Enemy.Location - Pawn.Location;
        toEnemy.Z = 0.0;
        strafeDir = Normal(toEnemy Cross vect(0,0,1));
        if (FRand() < 0.5) strafeDir = -strafeDir;
        MoveToX(Pawn.Location + (strafeDir * 150.0));
    }
    else
    {
        StyleCrouchUntil = WorldInfo.TimeSeconds + 1.0 + FRand();
        ApplyCrouch(true);
    }
}

// Noise reaction: non-Grunt ranks keep the legacy behaviour (follow the
// instigator and delegate to the base class). Grunt ranks apply the
// Echelon sight pipeline, engaging a hostile Zed within range or
// simply glancing at benign noise.
event HearNoise(float Loudness, Actor NoiseMaker, optional Name NoiseType)
{
    local Pawn NoisePawn;

    if (BotRank != GRUNT || Pawn == none || NoiseMaker == none)
    {
        if (NoiseMaker != none && NoiseMaker.Instigator != none)
        {
            SetEnemy(NoiseMaker.Instigator);
        }
        Super.HearNoise(Loudness, NoiseMaker, NoiseType);
        return;
    }

    if (Loudness <= 0.5 || VSizeSq(NoiseMaker.Location - Pawn.Location) >= HEAR_RANGE_SQ) return;
    if (Enemy != none && Enemy.IsAliveAndWell()) return;

    NoisePawn = Pawn(NoiseMaker);
    if (NoisePawn == none) NoisePawn = NoiseMaker.Instigator;

    if (IsHostileZed(NoisePawn))
    {
        GruntOnSight(NoisePawn);
    }
    else
    {
        NoiseGlanceUntil = WorldInfo.TimeSeconds + 1.5;
        SetFocalPoint(NoiseMaker.Location);
    }
}

// ============================================================
//  Immersion, Cohesion & Inter-Perk Polish
// ============================================================

// --- Suppressing Panic Variance ---
//
// Detects heavy Zeds (high threat tier) to drive the suppressive panic
// variance behaviour.

final function bool IsHeavyZedPawn(Pawn P)
{
    local KFPawn_Monster M;
    M = KFPawn_Monster(P);
    return (M != none && M.bLargeZed);
}

function UpdatePanicBroadcast()
{
    local int i;
    local bool bWantPanic;

    bWantPanic = (Enemy != none && Enemy.IsAliveAndWell() && IsHeavyZedPawn(Enemy)
               && VSizeSq(Enemy.Location - Pawn.Location) < 90000.0);

    for (i = 0; i < 4 && i < 4; i++)
    {
        if (SquadMembers[i] != none)
        {
            SquadMembers[i].ReceivePanic(bWantPanic);
        }
    }
}

function ReceivePanic(bool bPanic)
{
    if (PanicActive == bPanic) return;
    PanicActive = bPanic;
    ApplyPanicVariance();
}

function ApplyPanicVariance()
{
    local float wantMult;

    if (PanicActive) wantMult = PANIC_MULT;
    else             wantMult = 1.0;

    PanicScanSpeedMultiplier = wantMult;

    if (PanicVarianceMultiplier != wantMult)
    {
        PanicVarianceMultiplier = wantMult;
    }
}

// --- 6.2 Staggered Reload Drift ---

final function bool IsReloading()
{
    local KFWeapon W;
    if (Pawn == none) return false;
    W = KFWeapon(Pawn.Weapon);
    return (W != none && W.IsInState('Reloading'));
}

function HandleReloadDrift()
{
    local int i, reloadingCount;
    local float now;
    local vector dir;
    local KF2Bot Grunt;

    if (Pawn == none) return;
    if (CurrentOrder == 'CMD_PushAnchor' || CurrentOrder == 'CMD_TacticalRetreat') return;

    now = WorldInfo.TimeSeconds;

    for (i = 0; i < 4 && i < 4; i++)
    {
        Grunt = SquadMembers[i];
        if (Grunt != none && Grunt.Pawn != none && Grunt.IsReloading())
        {
            reloadingCount++;
        }
    }
    if (reloadingCount < 2) return;

    if (now - ReloadPullStamp > 0.75)
    {
        if (Enemy != none) dir = Enemy.Location - Pawn.Location;
        else               dir = vector(Pawn.Rotation);
        dir.Z = 0.0;
        if (VSizeSq(dir) < 1.0) dir = vect(1,0,0);
        dir = Normal(dir);

        ReloadPullAnchor = Pawn.Location - (dir * RELOAD_DRIFT_DIST);
        bReloadPullClear = FastTrace(ReloadPullAnchor, Pawn.Location);

        if (bReloadPullClear)
        {
            HoldAreaAnchor = ReloadPullAnchor;
            IssueCommand('CMD_HoldArea', ReloadPullAnchor);
        }
    }
    ReloadPullStamp = now;

    for (i = 0; i < 4 && i < 4; i++)
    {
        if (SquadMembers[i] != none && SquadMembers[i].Pawn != none)
        {
            SquadMembers[i].ReceiveReloadDrift(ReloadPullAnchor, bReloadPullClear, RELOAD_DRIFT_LEASE);
        }
    }
}

function ReceiveReloadDrift(vector Anchor, bool bMove, float Lease)
{
    local float now;
    local bool bNewEpisode;

    now = WorldInfo.TimeSeconds;
    bNewEpisode = (ReloadDriftUntil <= now);
    ReloadDriftUntil = now + Lease;
    bReloadDriftMove = bMove;

    if (bMove)
    {
        if (bNewEpisode)
        {
            ReloadDriftOffset = SquadLeader.Pawn.Location + ComputeFormationOffset(SquadLeader, false) - SquadLeader.Pawn.Location;
        }
        OnReloadDriftAnchor(Anchor);
    }
    else
    {
        ApplyCrouch(true);
    }
}

function OnReloadDriftAnchor(vector Anchor)
{
    ReloadDriftLoc = Anchor + ReloadDriftOffset;
    ApplyCrouch(true);
    MoveToX(ReloadDriftLoc);
}

function OnReloadComplete()
{
    ReloadDriftUntil = 0.0;
    ApplyCrouch(false);
}

function TrackReloadState()
{
    local bool bNow;
    bNow = IsReloading();
    if (bWasReloading && !bNow)
    {
        OnReloadComplete();
    }
    bWasReloading = bNow;
}

// --- 6.3 Human-Centric Bounding (Lieutenant) ---

function StartLtHumanBounding()
{
    SetTimer(FRand() * HUMAN_BOUND_INTERVAL, false, 'BeginLtHumanBounding');
}

function BeginLtHumanBounding()
{
    if (BotRank == LIEUTENANT)
    {
        SetTimer(HUMAN_BOUND_INTERVAL, true, 'LtHumanBoundLoop');
    }
}

function LtHumanBoundLoop()
{
    local int hIdx, s;
    local float now, pushDot, d, d1, d2;
    local vector objLoc, objDir, hVel, hLoc, ltAnchor, wedgeCenter;
    local KFPawn_Human Human;
    local KF2Bot SL, N1, N2;

    if (BotRank != LIEUTENANT || Pawn == none || mut == none)
    {
        ClearTimer('LtHumanBoundLoop');
        return;
    }
    if (mut.CachedHumans.Length == 0 || SquadLeaders.Length == 0) return;

    now = WorldInfo.TimeSeconds;

    ltAnchor = OrderAnchor;
    if (ltAnchor == vect(0,0,0)) ltAnchor = Pawn.Location;

    if (mut.bObjectiveActive) objLoc = mut.GetObjectiveLocation();
    else                      objLoc = ltAnchor;

    for (hIdx = 0; hIdx < mut.CachedHumans.Length; hIdx++)
    {
        Human = mut.CachedHumans[hIdx].HumanPawn;
        if (Human == none || !Human.IsAliveAndWell()) continue;

        hVel = mut.CachedHumans[hIdx].Vel;
        hVel.Z = 0.0;
        if (VSizeSq(hVel) < HUMAN_MIN_SPEED_SQ) continue;

        hLoc = mut.CachedHumans[hIdx].Loc;
        if (VSizeSq(hLoc - ltAnchor) >= HUMAN_LT_RANGE_SQ) continue;

        objDir = objLoc - hLoc;
        objDir.Z = 0.0;
        if (VSizeSq(objDir) < 1.0) continue;
        objDir = Normal(objDir);

        pushDot = objDir dot Normal(hVel);
        if (pushDot <= HUMAN_PUSH_DOT) continue;

        d1 = 99999999.0;
        d2 = 99999999.0;
        N1 = none;
        N2 = none;
        for (s = 0; s < SquadLeaders.Length; s++)
        {
            SL = SquadLeaders[s];
            if (SL == none || SL.Pawn == none || !SL.Pawn.IsAliveAndWell()) continue;
            if (SL.CurrentOrder == 'CMD_TacticalRetreat') continue;
            if (SL.WedgeExpireTime > now + HUMAN_BOUND_INTERVAL) continue;

            d = VSizeSq(SL.Pawn.Location - hLoc);
            if (d < d1)      { d2 = d1; N2 = N1; d1 = d; N1 = SL; }
            else if (d < d2) { d2 = d;  N2 = SL; }
        }

        wedgeCenter = hLoc - (objDir * WEDGE_REAR_OFFSET);
        wedgeCenter.Z = hLoc.Z;

        if (N1 != none) N1.ReceiveWedgeOrder(Human, wedgeCenter, now + WEDGE_LEASE);
        if (N2 != none) N2.ReceiveWedgeOrder(Human, wedgeCenter, now + WEDGE_LEASE);
    }
}

function ReceiveWedgeOrder(KFPawn_Human Human, vector WedgeCenter, float ExpireTime)
{
    local int i;

    bWedgeActive = true;
    WedgeHuman = Human;
    WedgeExpireTime = ExpireTime;
    CurrentFormation = 'WedgeBehindHuman';

    for (i = 0; i < 4 && i < 4; i++)
    {
        if (SquadMembers[i] != none)
        {
            SquadMembers[i].CurrentFormation = 'WedgeBehindHuman';
        }
    }
    IssueCommand('CMD_PushAnchor', WedgeCenter);
}

function UpdateWedgeMode()
{
    if (!bWedgeActive) return;
    if (WorldInfo.TimeSeconds > WedgeExpireTime || WedgeHuman == none || !WedgeHuman.IsAliveAndWell())
    {
        ClearWedge();
    }
}

function ClearWedge()
{
    local int i;

    bWedgeActive = false;
    WedgeHuman = none;
    WedgeExpireTime = 0.0;
    CurrentFormation = 'StaggeredColumn';
    for (i = 0; i < 4 && i < 4; i++)
    {
        if (SquadMembers[i] != none)
        {
            SquadMembers[i].CurrentFormation = 'StaggeredColumn';
        }
    }
}

function vector ComputeWedgeOffset(int Slot, KFPawn_Human PlayerRef)
{
    local rotator R;
    local vector AxX, AxY, AxZ, dir;
    local float ang, dist;
    local int sl;

    sl = Clamp(Slot, 0, 3);
    switch (sl)
    {
        case 0:  ang = -60.0; break;
        case 1:  ang = -30.0; break;
        case 2:  ang =  30.0; break;
        default: ang =  60.0; break;
    }
    ang *= DEG_TO_RAD;
    dist = 150.0 + (50.0 * float(sl));

    R = rot(0,0,0);
    R.Yaw = PlayerRef.Rotation.Yaw;
    GetAxes(R, AxX, AxY, AxZ);

    dir = ((-AxX) * Cos(ang)) + (AxY * Sin(ang));
    return dir * dist;
}

function ApplyWedgeTarget(out vector OutTarget)
{
    local KFPawn_Human Human;

    if (SquadLeader == none || !SquadLeader.bWedgeActive) return;
    Human = SquadLeader.WedgeHuman;
    if (Human == none || !Human.IsAliveAndWell()) return;

    OutTarget = Human.Location + ComputeWedgeOffset(OverwatchSlot, Human);
}

// --- 6.4 Trader Round Emote Echo ---

function StartEmoteEchoTimer()
{
    SetTimer(FRand(), false, 'BeginEmoteEcho');
}

function BeginEmoteEcho()
{
    SetTimer(1.0, true, 'CheckEmoteEcho');
}

function CheckEmoteEcho()
{
    local int i;
    local float now;
    local KFPawn_Human H;
    local KFGameReplicationInfo GRI;

    if (Pawn == none || bPlayingEmote || mut == none) return;

    GRI = mut.KF.MyKFGRI;
    if (GRI == none || !(GRI.bTraderIsOpen || GRI.WaveNum == 0)) return;

    now = WorldInfo.TimeSeconds;
    if (now < NextEmoteRollTime || Enemy != none) return;
    if (IsGruntCombatLocked() || IsInState('GoShopping') || IsInState('GetItem') || IsInState('DonatingMoney')) return;

    for (i = 0; i < mut.CachedHumans.Length; i++)
    {
        H = mut.CachedHumans[i].HumanPawn;
        if (H == none || !H.IsAliveAndWell()) continue;
        if (VSizeSq(H.Location - Pawn.Location) >= EMOTE_RADIUS_SQ) continue;
        if (!H.IsDoingSpecialMove(SM_Emote)) continue;

        NextEmoteRollTime = now + EMOTE_ROLL_COOLDOWN;
        if (FRand() < EMOTE_CHANCE)
        {
            Focus = none;
            SetFocalPoint(H.Location);
            PlayBotEmote();
        }
        break;
    }
}

final function PlayBotEmote()
{
    local KFPawn KFP;

    KFP = KFPawn(Pawn);
    if (KFP == none || bPlayingEmote) return;

    if (!KFP.CanDoSpecialMove(SM_Emote)) return;

    bPlayingEmote = true;
    KFP.DoSpecialMove(SM_Emote, true, none, 0);
    SetTimer(4.0, false, 'ClearEmoteFlag');
}

function ClearEmoteFlag()
{
    bPlayingEmote = false;
}

// --- 6.6 Immersion Polish Helpers ---

final function float GetWaveMomentum()
{
    local KFGameReplicationInfo GRI;
    GRI = mut.KF.MyKFGRI;
    if (GRI == none) return 1.0;
    return Max(1.0, float(GRI.WaveNum) * 0.15 + 1.0);
}

final function bool ExceedsRetreatZedCount()
{
    if (Pawn == none) return false;
    return (CachedZedCount >= int(RETREAT_ZED_TRIGGER_COUNT / GetWaveMomentum()));
}

function ApplyBreathing(float t)
{
    BreathingPhase += BREATH_OMEGA * t;
}

function UpdateHoldAreaDrift()
{
    local float now, drift;

    if (CurrentOrder != 'CMD_HoldArea') return;
    now = WorldInfo.TimeSeconds;
    if (now - LastDriftTime < 60.0) return;
    LastDriftTime = now;

    drift = DRIFT_RATE * 60.0;
    HoldDriftDist += drift;
    if (HoldDriftDist > DRIFT_MAX_TOTAL) HoldDriftDist = DRIFT_MAX_TOTAL;
}

// ============================================================

defaultproperties
{
	bIsPlayer=true
	bNotifyApex=true
	// Batch 3: Formation defaults
	CurrentFormation=StaggeredColumn
	ScanMask=15
	// Batch 6: Panic defaults
	PanicVarianceMultiplier=1.0
	PanicScanSpeedMultiplier=1.0
	// Close-weapon effective range gates (UU)
	ShotgunEffectiveRangeUU=1100.0
	FlamethrowerEffectiveRangeUU=700.0
	DefaultWeaponEffectiveRangeUU=5000.0
}
