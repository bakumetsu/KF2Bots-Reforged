//=============================================================================
// KF2BotsFollowNavBase
//
// HCA "Locomotion" layer for squad followers (Grunt -> Squad Leader).
// Drop-in intermediate base: put this file in KF2Bots\Classes\ and make your
// Grunt controller extend it instead of AIController.
//
// PLAN B (KFAIController-free): this class extends AIController directly, so
// none of KFAIController's zed machinery applies (no Action_Idle GotoState on
// Possess, no KFAIDirector registration, no stuck-suicide in Tick). The node
// blacklist is therefore unavailable; FollowTryBlockNode is a no-op and
// recovery degrades to the retry ladder only.
//
// GROUND TRUTH: every SDK symbol used below is either quoted in
// Bot_Navigation_Fixes.md (section noted as "AUDIT x.y") or is marked
// "VERIFY" at the point of use. Nothing here touches RouteCache by mutation,
// BasedPosition, AICommand_* or SetMoveGoal.
//
// DESIGN RULES
//  * State code is thin: it only calls latent natives and re-enters Dispatch.
//    All decisions live in ordinary functions (locals hoisted, no latent).
//  * Events and timers only set flags and request a Dispatch. They never call
//    FindPathToward.
//  * FindPathToward is spent from a per-bot token (FollowNextPathTime) that is
//    consumed BEFORE the call, so failures cool down too.
//  * Locomotion reports through FollowStatus / FollowNotifyHub and never
//    mutates Hub state (single-writer rule).
//=============================================================================
class KF2BotsFollowNavBase extends AIController
    abstract;

//-----------------------------------------------------------------------------
// ENUMS
//-----------------------------------------------------------------------------
enum EFollowAction
{
    FA_Hold,        // arrived: idle inside hysteresis band
    FA_Direct,      // MoveToward(leader pawn)
    FA_Path,        // walk the snapshot route node by node
    FA_Escape,      // back off a persistent wall, then re-evaluate
    FA_Yield,       // short sidestep for a friendly bump
    FA_Wait,        // nothing safe to do this pass (budget / pause / no leader)
    FA_GiveUp       // retry ladder exhausted -> report to Hub
};

enum EFollowStatus
{
    FS_Idle,
    FS_Following,
    FS_Arrived,
    FS_Blocked,
    FS_LeaderLost,
    FS_LeaderTeleported
};

//-----------------------------------------------------------------------------
// FEATURE FLAG
//-----------------------------------------------------------------------------
var bool bEnableAdvancedLocomotion;

//-----------------------------------------------------------------------------
// LEADER TRACKING
//-----------------------------------------------------------------------------
var Controller FollowLeaderCtrl;            // set by Hub via FollowStart/FollowSetLeader
var Pawn       FollowLeaderPawn;            // cached + validated each pass
var vector     FollowLeaderLastSampleLoc;
var float      FollowLeaderLastSampleTime;
var float      FollowLeaderInvalidSince;
var float      FollowLeaderGraceTime;
var float      FollowLeaderTeleportDist;
var float      FollowLeaderTeleportSpeed;
var bool       bFollowLeaderJumped;         // consumed by the watchdog

//-----------------------------------------------------------------------------
// SLOT BUFFERS / ARRIVAL (anti-crowding)
//-----------------------------------------------------------------------------
var int   FollowSlotIndex;                  // 0..FollowSlotCount-1, assigned by Hub
var int   FollowSlotCount;
var name  FollowExitState;                  // hub-directed exit target (default 'PickNextMove')
var bool  bFollowExitPending;               // set by the hub's FollowNotifyHub; cleared+checked in Dispatch
var float FollowBaseOffset;                 // replaces Pawn.MeleeRange from the Zed formula
var float FollowSlotRingStep;               // keep >= 2 * collision radius + margin
var float FollowResumeMargin;               // hysteresis: leave Hold only beyond radius + margin
var float FollowZTolerance;
var bool  bFollowArrived;

//-----------------------------------------------------------------------------
// TIME SLICING
//-----------------------------------------------------------------------------
var float FollowWatchdogPeriod;
var float FollowPhaseJitter;
var float FollowReachIntervalDirect;
var float FollowReachIntervalPath;
var float FollowNextReachCheckTime;
var bool  bFollowReachStable;
var bool  bFollowReachKnown;
var int   FollowReachFailStreak;
var int   FollowReachFailsToPath;
var float FollowMinLoopSleep;               // floor for every state-code loop pass
var float FollowInterruptMinGap;
var float FollowNextInterruptTime;
var bool  bFollowDispatchPending;

//-----------------------------------------------------------------------------
// A* BUDGET / ROUTE SNAPSHOT
//-----------------------------------------------------------------------------
var float FollowPathMinInterval;
var float FollowNextPathTime;
var float FollowPathFailBackoff;
var float FollowPathFailBackoffMin;
var float FollowPathFailBackoffMax;
var float FollowRepathDistance;             // AUDIT 4.1: 1224
var float FollowNodeRepathDistSq;           // AUDIT 4.2: 768^2 = 589824
var float FollowForcePathDuration;
var float FollowForcePathUntil;
var float FollowRepathPauseUntil;
var vector FollowLastLeaderPathLoc;
var vector FollowLastPawnTargetPathLoc;
var array<Actor> FollowRoute;
var int   FollowRouteIdx;
var int   FollowMaxRouteNodes;
var bool  bFollowRouteStale;

//-----------------------------------------------------------------------------
// MOVE BOOKKEEPING / STUCK DETECTION
//-----------------------------------------------------------------------------
var bool   bFollowMoveActive;               // true only while a latent move is in flight
var bool   bFollowDirectActive;
var float  FollowMoveStartTime;
var float  FollowLegTimeout;
var vector FollowStuckRefLoc;
var float  FollowStuckRefTime;
var float  FollowStuckWindow;
var float  FollowStuckMinMove;
var Actor  FollowNodeLast;
var int    FollowSameNodeCount;
var int    FollowSameNodeLimit;             // AUDIT 4.4: 20

//-----------------------------------------------------------------------------
// WALL / BUMP
//-----------------------------------------------------------------------------
var Actor FollowLastWall;
var float FollowLastWallTime;
var float FollowWallWindowStart;
var int   FollowWallHitCount;               // OUR counter - the SDK WallHitCount is dormant (AUDIT 3.1)
var int   FollowWallHitThreshold;
var float FollowWallWindow;
var float FollowWallDebounce;               // AUDIT 3.1: 0.2 (local debounce, Plan B)
var float FollowLastBumpTime;
var float FollowNextBumpReactTime;
var float FollowBumpCooldown;
var float FollowYieldDist;
var float FollowYieldHold;
var float FollowYieldTimeout;
var float FollowYieldEndTime;
var bool  bFollowYieldPending;
var bool  bFollowYielding;
var vector FollowYieldAway;
var vector FollowYieldPoint;
var bool  bFollowEscaping;
var vector FollowEscapeNormal;
var float  FollowEscapeUntil;
var float  FollowEscapeDuration;

//-----------------------------------------------------------------------------
// RETRY LADDER / OBSTACLE FAILOVER
//-----------------------------------------------------------------------------
var int    FollowRetries;
var int    FollowRetriesBlockAt;            // AUDIT 4.4: 5
var int    FollowRetriesGiveUpAt;           // AUDIT 4.4: 10
var vector FollowRetryAnchorLoc;
var float  FollowRetryResetDist;
var int    FollowBlocksThisEpisode;
var int    FollowMaxBlocksPerEpisode;
var float  FollowNextBlockTime;
var float  FollowBlockMinGap;
var float  FollowGiveUpHold;

//-----------------------------------------------------------------------------
// STATE-CODE SCRATCH + HUB-READABLE OUTPUT
//-----------------------------------------------------------------------------
var EFollowAction FollowAction;
var Actor         FollowNode;
var float         FollowWaitTime;
var EFollowStatus FollowStatus;             // Hub reads this; only Locomotion writes it


//=============================================================================
// ENTRY POINTS (called by the Hub)
//=============================================================================

// Hub emits "follow this leader": single entry point, honours the feature flag.
function FollowStart(Controller NewLeaderCtrl)
{
    FollowSetLeader(NewLeaderCtrl);

    if (bEnableAdvancedLocomotion)
    {
        GotoState('FollowingLeader');
    }
    else
    {
        GotoState('FollowingLeaderBasic');
    }
}

function FollowSetLeader(Controller NewLeaderCtrl)
{
    FollowLeaderCtrl = NewLeaderCtrl;
    FollowLeaderPawn = None;
    FollowLeaderInvalidSince = 0.0;
    bFollowArrived = false;
    FollowResetEpisode();
}

// Hub assigns the slot whenever the roster changes. Slot drives BOTH the
// arrival ring and the time-slice phase.
function FollowSetSlot(int NewSlotIndex, int NewSlotCount)
{
    FollowSlotIndex = Max(NewSlotIndex, 0);
    FollowSlotCount = Max(NewSlotCount, 1);
}

function FollowResetEpisode()
{
    FollowRetries = 0;
    FollowBlocksThisEpisode = 0;
    FollowSameNodeCount = 0;
    FollowNodeLast = None;
    FollowWallHitCount = 0;
    FollowLastWall = None;
    bFollowEscaping = false;
    FollowEscapeNormal = vect(0, 0, 0);
    FollowEscapeUntil = 0.0;
    FollowForcePathUntil = 0.0;
    FollowStuckRefTime = 0.0;
    bFollowYieldPending = false;
    bFollowYielding = false;
    bFollowDispatchPending = false;
    bFollowExitPending = false;

    if (Pawn != None)
    {
        FollowRetryAnchorLoc = Pawn.Location;
    }
    FollowInvalidateRoute();
}

function FollowInvalidateRoute()
{
    FollowRoute.Length = 0;
    FollowRouteIdx = 0;
    bFollowRouteStale = true;
    bFollowReachKnown = false;
    FollowReachFailStreak = 0;
    FollowNextReachCheckTime = 0.0;
}


//=============================================================================
// TIME SLICING
//=============================================================================

// Deterministic per-slot phase inside one watchdog period. Unlike FRand()
// alone, six followers can never land on the same offset.
function float FollowSlotPhase()
{
    return (float(FollowSlotIndex) / FMax(float(Max(FollowSlotCount, 1)), 0.0001f)) * FollowWatchdogPeriod;
}

function FollowScheduleWatchdog()
{
    local float IterDelay;

    IterDelay = FollowSlotPhase() + (FRand() * FollowPhaseJitter);
    if (IterDelay < 0.01)
    {
        IterDelay = 0.01;
    }
    SetTimer(IterDelay, false, 'FollowWatchdogBegin');
}

function FollowWatchdogBegin()
{
    SetTimer(FollowWatchdogPeriod, true, 'FollowWatchdog');
    FollowWatchdog();
}

// AUDIT 2nd-priority(b): overridable Hub hook. Called every watchdog pass while
// in a follower state (even Hold/Wait) so the Hub can route the bot out to an
// objective or the trader. Default is a no-op; KF2Bot overrides it. When an
// override returns true it has set bFollowExitPending (+ FollowExitState); the
// state's Dispatch performs the GotoState and ends the state function.
function bool FollowCheckExit()
{
    return false;
}

// Supervises a latent move that is IN FLIGHT. Cheap checks first; the single
// native reachability query is cached and rate-limited. AUDIT 6.2 only showed a
// do/until that is re-evaluated when MoveToward returns; the SDK actually
// interrupts the latent from a timer (CheckEnemyMoved, AUDIT 4.1) - this is
// that timer.
function FollowWatchdog()
{
    local float IterNow;
    local float IterMovedSq;
    local float IterMinMoveSq;
    local bool  IterReach;

    if (!bEnableAdvancedLocomotion || !IsInState('FollowingLeader'))
    {
        ClearTimer('FollowWatchdog');
        return;
    }
    IterNow = WorldInfo.TimeSeconds;

    // AUDIT 2nd-priority(b): Hub-directed exit (objective / trader).
    if (FollowCheckExit())
    {
        return;
    }

    // Yield sidestep: MoveTo has no native timeout, so bound it here.
    if (bFollowYielding)
    {
        if (IterNow >= FollowYieldEndTime)
        {
            bFollowYielding = false;
            GotoState('FollowingLeader', 'Dispatch');
        }
        return;
    }

    if (!bFollowMoveActive || Pawn == None)
    {
        return;     // Hold/Sleep phases: nothing in flight to supervise
    }

    if (bFollowDispatchPending)
    {
        FollowRequestDispatch();
        return;
    }

    // (1) cheap: leader validity / respawn / teleport
    if (!FollowRefreshLeader() || bFollowLeaderJumped)
    {
        bFollowLeaderJumped = false;
        FollowRequestDispatch();
        return;
    }

    // (2) cheap: per-leg timeout for node legs (AUDIT 4.6)
    if (!bFollowDirectActive && (IterNow - FollowMoveStartTime) > FollowLegTimeout)
    {
        FollowOnStuck('Timeout');
        return;
    }

    // (3) cheap: displacement window instead of instantaneous Velocity
    if (Pawn.Physics != PHYS_Falling && (IterNow - FollowStuckRefTime) >= FollowStuckWindow)
    {
        IterMovedSq = VSizeSq(Pawn.Location - FollowStuckRefLoc);
        IterMinMoveSq = FollowStuckMinMove * FollowStuckMinMove;
        FollowStuckRefLoc = Pawn.Location;
        FollowStuckRefTime = IterNow;

        if (IterMovedSq < IterMinMoveSq)
        {
            FollowOnStuck(FollowGuessStuckCause());
            return;
        }
        if (VSizeSq(Pawn.Location - FollowRetryAnchorLoc) > (FollowRetryResetDist * FollowRetryResetDist))
        {
            FollowRetries = 0;
            FollowBlocksThisEpisode = 0;
            FollowRetryAnchorLoc = Pawn.Location;
        }
    }

    // (4) budgeted native: reachability (cached, hysteresis, skipped when airborne)
    IterReach = FollowCheckReachable(false);
    if (IterNow >= FollowForcePathUntil && IterReach != bFollowDirectActive)
    {
        FollowRequestDispatch();    // direct <-> path mode flip
        return;
    }

    // (5) AUDIT 4.1 trigger: leader far from where the route was built AND not reachable
    if (!IterReach && !bFollowRouteStale
        && VSizeSq(FollowLeaderPawn.Location - FollowLastLeaderPathLoc) > (FollowRepathDistance * FollowRepathDistance))
    {
        bFollowRouteStale = true;
    }
}

// Interrupt an in-flight latent and re-enter Dispatch. Safe to call from
// timers/events. From state-code helpers it is a no-op because
// bFollowMoveActive is already false there, so GotoState is never issued
// from inside the running state code.
function FollowRequestDispatch()
{
    local float IterNow;

    if (!bFollowMoveActive)
    {
        return;
    }
    IterNow = WorldInfo.TimeSeconds;
    if (IterNow < FollowNextInterruptTime)
    {
        bFollowDispatchPending = true;      // retried by the next watchdog tick
        return;
    }
    FollowNextInterruptTime = IterNow + FollowInterruptMinGap;
    bFollowDispatchPending = false;
    `log("[FollowNav]" @ string(Name) @ "watchdog interrupt -> Dispatch");
    GotoState('FollowingLeader', 'Dispatch');
}


//=============================================================================
// LEADER VALIDATION
//=============================================================================

// Returns true only when there is a live leader pawn this pass.
function bool FollowRefreshLeader()
{
    local Pawn  IterPawn;
    local float IterNow;
    local float IterDt;
    local float IterJump;
    local float IterSpeed;

    IterNow = WorldInfo.TimeSeconds;
    IterPawn = None;

    if (FollowLeaderCtrl != None && !FollowLeaderCtrl.bDeleteMe)
    {
        IterPawn = FollowLeaderCtrl.Pawn;
    }

    // Dead-but-not-None, destroyed, or controller currently pawnless.
    if (IterPawn == None || IterPawn.bDeleteMe || IterPawn.Health <= 0)
    {
        FollowLeaderPawn = None;
        if (FollowLeaderInvalidSince <= 0.0)
        {
            FollowLeaderInvalidSince = IterNow;
        }
        if (FollowLeaderCtrl == None || (IterNow - FollowLeaderInvalidSince) >= FollowLeaderGraceTime)
        {
            FollowSetStatus(FS_LeaderLost);
        }
        return false;
    }

    FollowLeaderInvalidSince = 0.0;

    // First sight, or the leader respawned into a different pawn.
    if (IterPawn != FollowLeaderPawn)
    {
        FollowLeaderPawn = IterPawn;
        FollowInvalidateRoute();
        FollowLeaderLastSampleLoc = IterPawn.Location;
        FollowLeaderLastSampleTime = IterNow;
        bFollowLeaderJumped = true;
        return true;
    }

    // Teleport detection: large jump AND impossible speed (long sample gaps
    // alone must not trip it).
    IterDt = IterNow - FollowLeaderLastSampleTime;
    if (IterDt >= 0.2)
    {
        IterJump = VSize(IterPawn.Location - FollowLeaderLastSampleLoc);
        IterSpeed = IterJump / FMax(IterDt, 0.0001f);
        if (IterJump > FollowLeaderTeleportDist && IterSpeed > FollowLeaderTeleportSpeed)
        {
            FollowInvalidateRoute();
            FollowRetries = 0;
            FollowForcePathUntil = 0.0;
            // Whole squad sees the same teleport: decorrelate the repath.
            FollowNextPathTime = FMax(FollowNextPathTime, IterNow + FollowSlotPhase() + (FRand() * 0.25));
            bFollowLeaderJumped = true;
            FollowSetStatus(FS_LeaderTeleported);
        }
        FollowLeaderLastSampleLoc = IterPawn.Location;
        FollowLeaderLastSampleTime = IterNow;
    }
    return true;
}


//=============================================================================
// ARRIVAL / SLOT BUFFERS
//=============================================================================

// Pawn.GetCollisionRadius() + Leader.GetCollisionRadius() + FollowOffset,
// where FollowOffset grows by one ring step per slot so followers stop at
// distinct distances instead of piling onto the same point.
function float FollowGetArrivalRadius()
{
    local float IterOffset;

    IterOffset = FollowBaseOffset + (float(FollowSlotIndex) * FollowSlotRingStep);
    if (Pawn == None || FollowLeaderPawn == None)
    {
        return IterOffset;
    }
    return Pawn.GetCollisionRadius() + FollowLeaderPawn.GetCollisionRadius() + IterOffset;
}

// 2D distance + Z tolerance, with hysteresis so a leader drifting a few
// units never flips a holding follower back into MoveToward (and into a bump).
function bool FollowEvalArrived()
{
    local vector IterDelta;
    local float  IterDist;
    local float  IterDz;
    local float  IterRadius;
    local bool   IterWasArrived;

    if (Pawn == None || FollowLeaderPawn == None)
    {
        bFollowArrived = false;
        return false;
    }

    IterWasArrived = bFollowArrived;
    IterDelta = FollowLeaderPawn.Location - Pawn.Location;
    IterDz = Abs(IterDelta.Z);
    IterDelta.Z = 0.0;
    IterDist = VSize(IterDelta);
    IterRadius = FollowGetArrivalRadius();

    if (IterWasArrived)
    {
        bFollowArrived = (IterDist <= (IterRadius + FollowResumeMargin)) && (IterDz <= FollowZTolerance);
    }
    else
    {
        bFollowArrived = (IterDist <= IterRadius) && (IterDz <= FollowZTolerance);
    }

    if (bFollowArrived && !IterWasArrived)
    {
        FollowRetries = 0;
        FollowBlocksThisEpisode = 0;
        FollowRetryAnchorLoc = Pawn.Location;
    }
    return bFollowArrived;
}


//=============================================================================
// REACHABILITY (the only ActorReachable call site) + A* BUDGET
//=============================================================================

function bool FollowCheckReachable(bool bForceNow)
{
    local float IterNow;
    local bool  IterReach;

    if (Pawn == None || FollowLeaderPawn == None)
    {
        return false;
    }
    IterNow = WorldInfo.TimeSeconds;

    if (!bForceNow && bFollowReachKnown && IterNow < FollowNextReachCheckTime)
    {
        return bFollowReachStable;
    }

    // Airborne leader or follower gives false negatives: reuse the last verdict.
    if (bFollowReachKnown && (FollowLeaderPawn.Physics == PHYS_Falling || Pawn.Physics == PHYS_Falling))
    {
        FollowNextReachCheckTime = IterNow + FollowReachIntervalDirect;
        return bFollowReachStable;
    }

    IterReach = ActorReachable(FollowLeaderPawn);

    if (IterReach)
    {
        FollowReachFailStreak = 0;
        bFollowReachStable = true;
        if (bFollowDirectActive)
        {
            FollowNextReachCheckTime = IterNow + FollowReachIntervalDirect;
        }
        else
        {
            FollowNextReachCheckTime = IterNow + FollowReachIntervalPath;
        }
    }
    else
    {
        FollowReachFailStreak++;
        if (!bFollowReachKnown || FollowReachFailStreak >= FollowReachFailsToPath)
        {
            bFollowReachStable = false;
            FollowNextReachCheckTime = IterNow + FollowReachIntervalPath;
        }
        else
        {
            FollowNextReachCheckTime = IterNow + FollowReachIntervalDirect;   // quick confirmation
        }
    }
    bFollowReachKnown = true;
    return bFollowReachStable;
}

// The only FindPathToward call site. Token is spent BEFORE the native call.
// VERIFY: FindPathToward is not in AUDIT section 5. This uses the one-argument
// form (Actor goal, returns first node, fills RouteCache).
function bool FollowBuildPath()
{
    local float IterNow;
    local Actor IterFirst;
    local int   IterIdx;

    IterNow = WorldInfo.TimeSeconds;
    if (FollowLeaderPawn == None || IterNow < FollowNextPathTime)
    {
        return false;
    }

    FollowNextPathTime = IterNow + FollowPathMinInterval + (FRand() * FollowPhaseJitter);

    IterFirst = FindPathToward(FollowLeaderPawn);
    if (IterFirst == None)
    {
        FollowPathFailBackoff = FClamp(FollowPathFailBackoff * 2.0, FollowPathFailBackoffMin, FollowPathFailBackoffMax);
        FollowNextPathTime = IterNow + FMax(FollowPathMinInterval, FollowPathFailBackoff);
        FollowRetries++;
        `log("[FollowNav]" @ string(Name) @ "FindPathToward returned None, retries=" $ string(FollowRetries));
        return false;
    }

    // Snapshot: other systems (combat, Hub) may call FindPathToward on this
    // controller and overwrite RouteCache under us.
    FollowRoute.Length = 0;
    for (IterIdx = 0; IterIdx < RouteCache.Length && IterIdx < FollowMaxRouteNodes; IterIdx++)
    {
        FollowRoute.AddItem(RouteCache[IterIdx]);
    }
    if (FollowRoute.Length == 0)
    {
        FollowRoute.AddItem(IterFirst);
    }

    FollowRouteIdx = 0;
    FollowPathFailBackoff = 0.0;
    bFollowRouteStale = false;
    FollowLastLeaderPathLoc = FollowLeaderPawn.Location;
    FollowLastPawnTargetPathLoc = FollowLeaderPawn.Location;
    `log("[FollowNav]" @ string(Name) @ "A* OK " $ string(FollowRoute.Length) @ "nodes to " $ string(FollowLeaderPawn));
    return true;
}

// State-code only: must not be called while a latent move is in flight,
// because it rewrites Pawn.DestinationOffset.
function Actor FollowGetNextNode()
{
    local Actor IterNode;

    if (Pawn == None)
    {
        return None;
    }
    // A stale offset left by a direct move would make ReachedDestination() fire early.
    Pawn.DestinationOffset = 0.0;

    while (FollowRouteIdx < FollowRoute.Length)
    {
        IterNode = FollowRoute[FollowRouteIdx];
        // Skip a destroyed/invalid nav node so a stale node is never handed to
        // a mover (wave-start nav-graph churn is the suspected fatal trigger).
        // UE3 has no Actor.bDeleted; a destroyed actor is referenced as None.
        if (IterNode == None)
        {
            FollowRouteIdx++;
            continue;
        }
        if (!Pawn.ReachedDestination(IterNode))
        {
            return IterNode;
        }
        FollowRouteIdx++;
    }
    return None;
}


//=============================================================================
// DECISION (all branching lives here; the state code just obeys)
//=============================================================================
function EFollowAction FollowDecide()
{
    local float IterNow;
    local bool  IterUsePath;

    IterNow = WorldInfo.TimeSeconds;
    FollowWaitTime = FollowWatchdogPeriod;

    if (Pawn == None || Pawn.Health <= 0)
    {
        FollowWaitTime = 0.5;
        return FA_Wait;
    }
    if (!FollowRefreshLeader())
    {
        FollowWaitTime = 0.5;
        return FA_Wait;
    }
    if (FollowRetries >= FollowRetriesGiveUpAt)
    {
        return FA_GiveUp;
    }
    // AUDIT 2nd-priority(a): drive off a persistent wall before re-pathing.
    if (bFollowEscaping)
    {
        if (IterNow < FollowEscapeUntil)
        {
            return FA_Escape;
        }
        bFollowEscaping = false;
        FollowEscapeNormal = vect(0, 0, 0);
        FollowEscapeUntil = 0.0;
    }
    if (FollowEvalArrived())
    {
        FollowSetStatus(FS_Arrived);
        FollowWaitTime = FollowWatchdogPeriod + (FRand() * FollowPhaseJitter);
        return FA_Hold;
    }
    if (bFollowYieldPending)
    {
        return FA_Yield;
    }
    if (IterNow < FollowRepathPauseUntil)
    {
        FollowWaitTime = FollowRepathPauseUntil - IterNow;
        return FA_Wait;
    }

    FollowSetStatus(FS_Following);

    // Direct follow is the default; pathing only when the leader is NOT
    // directly reachable (AUDIT 4.1: no wasted pathfind while in LOS).
    IterUsePath = (IterNow < FollowForcePathUntil) || !FollowCheckReachable(false);
    if (!IterUsePath)
    {
        return FA_Direct;
    }

    if (bFollowRouteStale || FollowRouteIdx >= FollowRoute.Length)
    {
        // Keep walking the old route while the budget refuses a new one.
        if (!FollowBuildPath() && FollowRouteIdx >= FollowRoute.Length)
        {
            FollowWaitTime = FMax(FollowNextPathTime - IterNow, FollowMinLoopSleep);
            return FA_Wait;
        }
    }
    return FA_Path;
}


//=============================================================================
// MOVE LIFECYCLE (called from state code)
//=============================================================================
function FollowOnMoveBegin(bool bDirect)
{
    local float IterNow;

    IterNow = WorldInfo.TimeSeconds;
    bFollowMoveActive = true;
    bFollowDirectActive = bDirect;
    FollowMoveStartTime = IterNow;

    // Keep the stuck window running across short node legs; restart it only
    // after a pause (Hold/Wait/Yield).
    if (FollowStuckRefTime <= 0.0 || (IterNow - FollowStuckRefTime) > (FollowStuckWindow * 3.0))
    {
        FollowStuckRefLoc = Pawn.Location;
        FollowStuckRefTime = IterNow;
    }

    // AUDIT 4.6: FMax(0.5, 2.0 * Dist / GroundSpeed)
    if (!bDirect && FollowNode != None)
    {
        FollowLegTimeout = FMax(0.5f, 2.0f * (VSize(FollowNode.Location - Pawn.Location) / FMax(Pawn.GroundSpeed, 0.0001f)));
    }
}

function FollowOnMoveEnd(bool bDirect)
{
    bFollowMoveActive = false;
    bFollowDirectActive = false;

    // Native-consistent arrival test (AUDIT 2.5): MoveToward may return at a
    // slightly different distance than our 2D test, which would otherwise
    // respin MoveToward on a leader we have already reached.
    if (bDirect && Pawn != None && FollowLeaderPawn != None)
    {
        Pawn.DestinationOffset = FollowGetArrivalRadius();
        if (Pawn.ReachedDestination(FollowLeaderPawn))
        {
            bFollowArrived = true;
        }
    }
}

function FollowOnNodeMoveEnd(Actor IterNode)
{
    FollowOnMoveEnd(false);

    if (Pawn == None || IterNode == None)
    {
        return;
    }
    Pawn.DestinationOffset = 0.0;

    if (IterNode == FollowNodeLast)
    {
        FollowSameNodeCount++;
    }
    else
    {
        FollowNodeLast = IterNode;
        FollowSameNodeCount = 1;
    }

    if (Pawn.ReachedDestination(IterNode))
    {
        FollowSameNodeCount = 0;
        // AUDIT 4.2: per-node moving-target repath (768^2).
        if (FollowLeaderPawn != None
            && VSizeSq(FollowLeaderPawn.Location - FollowLastPawnTargetPathLoc) > FollowNodeRepathDistSq)
        {
            bFollowRouteStale = true;
            FollowLastPawnTargetPathLoc = FollowLeaderPawn.Location;
        }
    }
    else if (FollowSameNodeCount > FollowSameNodeLimit && VSizeSq(Pawn.Velocity) < 600.0)
    {
        FollowOnStuck('SameNode');      // AUDIT 4.4
    }
}


//=============================================================================
// STUCK / OBSTACLE FAILOVER
//=============================================================================
function Name FollowGuessStuckCause()
{
    local float IterNow;

    IterNow = WorldInfo.TimeSeconds;
    if ((IterNow - FollowLastBumpTime) < 1.0)
    {
        return 'Pawn';
    }
    if (FollowLastWall != None && (IterNow - FollowLastWallTime) < 2.0 && !FollowLastWall.IsA('Pawn'))
    {
        return 'Wall';
    }
    return 'Unknown';
}

// Causes: 'Wall' 'Pawn' 'SameNode' 'Timeout' 'Unreachable' 'Unknown'.
// Retry ladder (AUDIT 4.4): < BlockAt plain repath, BlockAt..GiveUpAt block
// node (static causes only), >= GiveUpAt -> FA_GiveUp in FollowDecide.
function FollowOnStuck(Name IterCause)
{
    local float IterNow;

    IterNow = WorldInfo.TimeSeconds;
    if (IterNow < FollowRepathPauseUntil)
    {
        return;     // a recovery is already running
    }

    FollowRetries++;
    `log("[FollowNav]" @ string(Name) @ "stuck cause=" $ string(IterCause) @ "retries=" $ string(FollowRetries));

    // Local equivalent of ForcePauseAndRepath (AUDIT 4.3): flag + 0.25 + FRand()
    // pause, plus the slot phase. The SDK function pushes AICommand_Pause and
    // notifies the command stack, which is the wrong tool for a state-driven
    // follower.
    FollowRepathPauseUntil = IterNow + 0.25 + FRand() + FollowSlotPhase();
    bFollowRouteStale = true;

    // A direct move that jams while ActorReachable() says true must be forced
    // onto the nav graph, otherwise the same direct move repeats.
    if (bFollowDirectActive)
    {
        FollowForcePathUntil = IterNow + FollowForcePathDuration;
    }

    if (IterCause == 'Pawn')
    {
        bFollowYieldPending = true;         // friendly block: sidestep, never blacklist
    }
    else if (IterCause == 'SameNode' || ((IterCause == 'Wall' || IterCause == 'Unreachable') && FollowRetries >= FollowRetriesBlockAt))
    {
        FollowTryBlockNode(FollowNodeLast);
    }

    FollowNodeLast = None;
    FollowSameNodeCount = 0;
    if (Pawn != None)
    {
        FollowStuckRefLoc = Pawn.Location;
    }
    FollowStuckRefTime = IterNow;
    FollowRequestDispatch();
}

// PLAN B: the node blacklist is unavailable here. CreateTemporaryBlockedReach/
// Path and CurrentPath are KFAIController members (KFAIController.uc:984/1016)
// and this class extends AIController, so they cannot be called. FollowOnStuck
// still runs the retry ladder; recovery degrades to repath-only.
function bool FollowTryBlockNode(Actor IterNodeActor)
{
    return false;
}


//=============================================================================
// EVENT ROUTING (hooks; see integration notes)
//=============================================================================
function bool FollowOwnsEvents()
{
    return (bEnableAdvancedLocomotion && IsInState('FollowingLeader'));
}

// Returns the value to hand back to the engine. false keeps native wall
// resolution (PickWallAdjust, AUDIT 3.3) intact.
function bool FollowHandleHitWall(vector HitNormal, Actor Wall)
{
    local float IterNow;

    IterNow = WorldInfo.TimeSeconds;

    // AUDIT 3.1 throttle. Plan B has no KFAIController wall-disable, so the
    // debounce is applied locally: hits on the same wall within the window
    // are not counted, and the engine keeps native wall resolution running
    // (PickWallAdjust stays intact).
    if ((IterNow - FollowLastWallTime) < FollowWallDebounce)
    {
        return false;
    }

    if (Pawn != None && Pawn.Physics == PHYS_Falling)
    {
        return true;        // airborne: do not count, do not react
    }

    if (Wall != FollowLastWall || (IterNow - FollowWallWindowStart) > FollowWallWindow)
    {
        FollowLastWall = Wall;
        FollowWallWindowStart = IterNow;
        FollowWallHitCount = 0;
    }
    FollowLastWallTime = IterNow;
    FollowWallHitCount++;

    if (FollowWallHitCount >= FollowWallHitThreshold && bFollowMoveActive)
    {
        FollowWallHitCount = 0;

        if (Wall != None && Wall.IsA('Pawn'))
        {
            FollowOnStuck('Pawn');
        }
        else
        {
            FollowOnStuck('Wall');
            FollowSetWallEscape(HitNormal);
        }
    }
    return false;
}

// AUDIT 2nd-priority(a): Plan B has no node blacklist (FollowTryBlockNode is a
// no-op), so a wall-stuck bot would re-approach the SAME node and hit the SAME
// wall forever. On a wall-stuck, physically drive the bot OFF the wall along
// the hit normal for a bounded time; the next repath then starts from an
// off-wall position and can find a viable route.
function FollowSetWallEscape(vector HitNormal)
{
    local float IterNow;
    local float IterLen;

    IterNow = WorldInfo.TimeSeconds;
    IterLen = VSize(HitNormal);
    if (IterLen < 0.01)
    {
        return;
    }
    FollowEscapeNormal.X = HitNormal.X / IterLen;
    FollowEscapeNormal.Y = HitNormal.Y / IterLen;
    FollowEscapeNormal.Z = HitNormal.Z / IterLen;
    bFollowEscaping = true;
    FollowEscapeUntil = IterNow + FollowEscapeDuration;
    `log("[FollowNav] wall-escape set: nx=" $ string(FollowEscapeNormal.X) $ " ny=" $ string(FollowEscapeNormal.Y) $ " for=" $ string(FollowEscapeDuration) $ "s (slot=" $ string(FollowSlotIndex) $ ")");
}

function bool FollowIsFriendly(Pawn IterOther)
{
    if (IterOther == None)
    {
        return false;
    }
    if (IterOther == FollowLeaderPawn)
    {
        return true;
    }
    if (PlayerController(IterOther.Controller) != None)
    {
        return true;
    }
    return (KF2BotsFollowNavBase(IterOther.Controller) != None);
}

// Deterministic priority: leader and humans always win; among bots the lower
// slot index holds its ground and the higher one yields. Equal slots fall
// back to a name compare so a misconfigured pair cannot deadlock.
function bool FollowShouldYieldTo(Pawn IterOther)
{
    local KF2BotsFollowNavBase IterBot;

    if (IterOther == FollowLeaderPawn)
    {
        return true;
    }
    IterBot = KF2BotsFollowNavBase(IterOther.Controller);
    if (IterBot == None)
    {
        return true;
    }
    if (IterBot.FollowSlotIndex == FollowSlotIndex)
    {
        return (string(IterBot.Name) < string(Name));
    }
    return (IterBot.FollowSlotIndex < FollowSlotIndex);
}

// Returns true when the bump was consumed (so the legacy handler is skipped).
function bool FollowHandleBump(Actor Other, vector HitNormal)
{
    local Pawn  IterOther;
    local float IterNow;

    IterOther = Pawn(Other);
    if (IterOther == None || Pawn == None || !FollowIsFriendly(IterOther))
    {
        return false;       // zeds etc. stay with the legacy/combat path
    }

    IterNow = WorldInfo.TimeSeconds;
    FollowLastBumpTime = IterNow;

    // Swallow the rest of the cascade: one reaction per cooldown.
    if (IterNow < FollowNextBumpReactTime)
    {
        return true;
    }
    FollowNextBumpReactTime = IterNow + FollowBumpCooldown;

    if (FollowShouldYieldTo(IterOther))
    {
        FollowYieldAway = Pawn.Location - IterOther.Location;
        FollowYieldAway.Z = 0.0;
        bFollowYieldPending = true;
        FollowRequestDispatch();    // holding followers pick the flag up on their next pass
    }
    return true;
}

function FollowHandleMoveUnreachable(vector AttemptedDest, Actor AttemptedTarget)
{
    local float IterNow;

    IterNow = WorldInfo.TimeSeconds;

    // Unreachable node during a path leg: counts against the retry ladder.
    if (bFollowMoveActive && !bFollowDirectActive)
    {
        FollowOnStuck('Unreachable');
        return;
    }

    // AUDIT 6.4: never retry the same direct point; force the nav graph.
    if (IterNow < FollowForcePathUntil)
    {
        return;     // already switched to pathing, ignore the repeat
    }
    `log("[FollowNav]" @ string(Name) @ "MoveUnreachable -> forcing path, target=" $ string(AttemptedTarget));
    FollowForcePathUntil = IterNow + FollowForcePathDuration;
    FollowNextPathTime = FMax(FollowNextPathTime, IterNow + FollowSlotPhase());
    bFollowRouteStale = true;
    FollowRequestDispatch();
}

function bool FollowComputeYieldPoint()
{
    local vector IterAway;
    local vector IterSide;
    local vector IterDest;

    if (Pawn == None)
    {
        return false;
    }

    IterAway = FollowYieldAway;
    IterAway.Z = 0.0;
    if (VSize(IterAway) < 1.0 && FollowLeaderPawn != None)
    {
        IterAway = Pawn.Location - FollowLeaderPawn.Location;
        IterAway.Z = 0.0;
    }
    if (VSize(IterAway) < 1.0)
    {
        return false;
    }
    IterAway = Normal(IterAway);

    // Even slots step left, odd slots step right: two yielding bots never
    // pick the same side.
    IterSide = IterAway Cross vect(0.0, 0.0, 1.0);
    if ((FollowSlotIndex % 2) == 1)
    {
        IterSide = -IterSide;
    }

    IterDest = Pawn.Location + (IterSide * FollowYieldDist) + (IterAway * (FollowYieldDist * 0.5));
    if (!PointReachable(IterDest))
    {
        IterSide = -IterSide;
        IterDest = Pawn.Location + (IterSide * FollowYieldDist) + (IterAway * (FollowYieldDist * 0.5));
        if (!PointReachable(IterDest))
        {
            return false;
        }
    }
    FollowYieldPoint = IterDest;
    return true;
}


//=============================================================================
// STATUS REPORTING (single-writer: Locomotion writes, Hub reads)
//=============================================================================
function FollowSetStatus(EFollowStatus NewStatus)
{
    if (NewStatus == FollowStatus)
    {
        return;
    }
    FollowStatus = NewStatus;
    FollowNotifyHub(NewStatus);
}

// Override in your Grunt controller to forward to the Hub's mailbox.
function FollowNotifyHub(EFollowStatus NewStatus)
{
    `log("[FollowNav]" @ string(Name) @ "status=" $ string(int(NewStatus)));
}

// Retry ladder exhausted. Hub decides (regroup / teleport / hold). The SDK's
// terminal-stuck "suicide" recovery is deliberately NOT replicated.
function FollowOnGaveUp()
{
    `log("[FollowNav]" @ string(Name) @ "gave up following; Hub should decide");
}


//=============================================================================
// ENGINE EVENT OVERRIDES
//=============================================================================
event bool NotifyHitWall(vector HitNormal, Actor Wall)
{
    if (FollowOwnsEvents())
    {
        return FollowHandleHitWall(HitNormal, Wall);
    }
    return Super.NotifyHitWall(HitNormal, Wall);
}

event bool NotifyBump(Actor Other, vector HitNormal)
{
    if (FollowOwnsEvents() && FollowHandleBump(Other, HitNormal))
    {
        return true;
    }
    return Super.NotifyBump(Other, HitNormal);
}

event MoveUnreachable(vector AttemptedDest, Actor AttemptedTarget)
{
    if (FollowOwnsEvents())
    {
        FollowHandleMoveUnreachable(AttemptedDest, AttemptedTarget);
        return;
    }
    Super.MoveUnreachable(AttemptedDest, AttemptedTarget);
}


//=============================================================================
// STATE: advanced follower
//=============================================================================
state FollowingLeader
{
    event BeginState(Name PreviousStateName)
    {
        FollowResetEpisode();
        bFollowMoveActive = false;
        bFollowDirectActive = false;
        // Clear any stale combat Acceleration inherited from a prior state so
        // a Hold/Wait step (which does not set Acceleration) can't leave the
        // bot drifting on a leftover combat drive.
        if (Pawn != None)
        {
            Pawn.Acceleration = vect(0.0, 0.0, 0.0);
        }
        FollowScheduleWatchdog();
        `log("[FollowNav]" @ string(Name) @ "Enter FollowingLeader from " $ string(PreviousStateName));
    }

    event EndState(Name NextStateName)
    {
        ClearTimer('FollowWatchdogBegin');
        ClearTimer('FollowWatchdog');
        bFollowMoveActive = false;
        bFollowDirectActive = false;
        bFollowYielding = false;
        `log("[FollowNav]" @ string(Name) @ "Exit FollowingLeader to " $ string(NextStateName));
    }

Begin:
    Goto('Dispatch');

Dispatch:
    // Stale-resume guard: if an event (Tick combat escape) switched the state
    // while this function was suspended in a latent, exit immediately so the
    // new state's function takes over instead of dispatching stale follow code.
    // UScript 2.2 state functions cannot use 'return'; 'Stop' ends the state
    // function (SDK: KFAIController.uc Action_Idle uses the same construct).
    if (!IsInState('FollowingLeader'))
    {
        Stop;
    }
    bFollowMoveActive = false;
    bFollowDirectActive = false;
    bFollowDispatchPending = false;
    // Hub-directed exit: FollowNotifyHub sets bFollowExitPending; leave the
    // follower state on the next dispatch. GotoState + Stop ends this
    // function cleanly (UScript 2.2: 'return' is illegal in state functions;
    // UE3 resumes a suspended state function after a latent, so the
    // transition must happen here, not in the event handler).
    if (bFollowExitPending)
    {
        bFollowExitPending = false;
        if (FollowExitState != '')
        {
            GotoState(FollowExitState);
            Stop;
        }
    }
    FollowAction = FollowDecide();
    if (FollowAction == FA_Direct)
    {
        Goto('DirectMove');
    }
    if (FollowAction == FA_Path)
    {
        Goto('PathMove');
    }
    if (FollowAction == FA_Yield)
    {
        Goto('YieldStep');
    }
    if (FollowAction == FA_Escape)
    {
        Goto('EscapeStep');
    }
    if (FollowAction == FA_Hold)
    {
        Goto('HoldStep');
    }
    if (FollowAction == FA_GiveUp)
    {
        Goto('GiveUpStep');
    }
    Goto('WaitStep');

WaitStep:
    Sleep(FClamp(FollowWaitTime, FollowMinLoopSleep, 1.0));
    Goto('Dispatch');

HoldStep:
    if (Pawn != None)
    {
        Pawn.Acceleration = vect(0.0, 0.0, 0.0);
    }
    Sleep(FClamp(FollowWaitTime, FollowMinLoopSleep, 1.0));
    Goto('Dispatch');

DirectMove:
    // Acceleration-based move (no native mover). KF2Bot's Tick combat-escape
    // can GotoState at any frame; cancelling a native MoveToward mover mid-
    // flight is the suspected native-fatal trigger. Arrive via FollowDecide.
    FollowOnMoveBegin(true);
    `log("[FollowNav]" @ string(Name) @ "Accel leader " $ string(FollowLeaderPawn) @ " radius=" $ string(FollowGetArrivalRadius()));
    Pawn.Acceleration = Normal(FollowLeaderPawn.Location - Pawn.Location) * FMax(Pawn.GroundSpeed, 0.0001f);
    Sleep(FollowMinLoopSleep);
    Goto('Dispatch');

PathMove:
    FollowNode = FollowGetNextNode();
    if (FollowNode == None)
    {
        Sleep(FollowMinLoopSleep);
        Goto('Dispatch');
    }
    FollowOnMoveBegin(false);
    `log("[FollowNav]" @ string(Name) @ "Accel node " $ string(FollowNode));
    Pawn.Acceleration = Normal(FollowNode.Location - Pawn.Location) * FMax(Pawn.GroundSpeed, 0.0001f);
    Sleep(FollowMinLoopSleep);
    Goto('Dispatch');

EscapeStep:
    // AUDIT 2nd-priority(a): drive OFF the wall along the hit normal. The stuck
    // window is NOT reset here, so a persistent corner still times out and
    // re-triggers a repath from the new off-wall position.
    if (Pawn != None)
    {
        Pawn.Acceleration = FollowEscapeNormal * FMax(Pawn.GroundSpeed, 0.0001f);
    }
    `log("[FollowNav]" @ string(Name) @ "Accel escape off wall nx=" $ string(FollowEscapeNormal.X) $ " ny=" $ string(FollowEscapeNormal.Y));
    Sleep(FollowMinLoopSleep);
    Goto('Dispatch');

YieldStep:
    bFollowYieldPending = false;
    if (FollowComputeYieldPoint())
    {
        bFollowYielding = true;
        FollowYieldEndTime = WorldInfo.TimeSeconds + FollowYieldTimeout;
        `log("[FollowNav]" @ string(Name) @ "Accel yield " $ string(FollowYieldPoint.X) $ "," $ string(FollowYieldPoint.Y) $ "," $ string(FollowYieldPoint.Z));
        Pawn.Acceleration = Normal(FollowYieldPoint - Pawn.Location) * FMax(Pawn.GroundSpeed, 0.0001f);
        bFollowYielding = false;
    }
    Sleep(FollowYieldHold);
    Goto('Dispatch');

GiveUpStep:
    FollowSetStatus(FS_Blocked);
    FollowOnGaveUp();
    Sleep(FollowGiveUpHold);
    FollowRetries = 0;
    FollowBlocksThisEpisode = 0;
    Goto('Dispatch');
}


//=============================================================================
// STATE: fallback when bEnableAdvancedLocomotion == false (AUDIT 6.7)
// No watchdog, no per-node repath, no node blacklist, no event interception.
// Sleep(0.25) is a hard floor: at most 4 ActorReachable/FindPathToward per
// second per bot, and the state code can never spin.
//=============================================================================
state FollowingLeaderBasic
{
Begin:
    // Same stale-resume + hub-exit guards as the advanced state
    // ('Stop', not 'return' -- UScript 2.2 state functions).
    if (!IsInState('FollowingLeaderBasic'))
    {
        Stop;
    }
    if (bFollowExitPending)
    {
        bFollowExitPending = false;
        if (FollowExitState != '')
        {
            GotoState(FollowExitState);
            Stop;
        }
    }
    if (Pawn == None || !FollowRefreshLeader())
    {
        Sleep(0.5);
        Goto('Begin');
    }
    // Clear stale combat Acceleration so an arrived/holding iteration can't
    // leave the bot drifting on a leftover combat drive.
    Pawn.Acceleration = vect(0.0, 0.0, 0.0);
    if (FollowEvalArrived())
    {
        Sleep(0.3);
        Goto('Begin');
    }
    if (ActorReachable(FollowLeaderPawn))
    {
        Pawn.Acceleration = Normal(FollowLeaderPawn.Location - Pawn.Location) * FMax(Pawn.GroundSpeed, 0.0001f);
    }
    else
    {
        FollowNode = FindPathToward(FollowLeaderPawn);
        if (FollowNode != None)
        {
            Pawn.Acceleration = Normal(FollowNode.Location - Pawn.Location) * FMax(Pawn.GroundSpeed, 0.0001f);
        }
    }
    Sleep(0.25);
    Goto('Begin');
}


defaultproperties
{
    bEnableAdvancedLocomotion=true
    FollowExitState="PickNextMove"

    // Leader
    FollowLeaderGraceTime=2.0
    FollowLeaderTeleportDist=1200.0
    FollowLeaderTeleportSpeed=4000.0

    // Slots / arrival
    FollowSlotIndex=0
    FollowSlotCount=1
    FollowBaseOffset=96.0
    FollowSlotRingStep=64.0
    FollowResumeMargin=96.0
    FollowZTolerance=128.0

    // Time slicing
    FollowWatchdogPeriod=0.25
    FollowPhaseJitter=0.03
    FollowReachIntervalDirect=0.25
    FollowReachIntervalPath=0.5
    FollowReachFailsToPath=2
    FollowMinLoopSleep=0.05
    FollowInterruptMinGap=0.15

    // A* budget (RepathDistance and 589824 are the SDK values from AUDIT 4.1/4.2)
    FollowPathMinInterval=0.75
    FollowPathFailBackoffMin=0.5
    FollowPathFailBackoffMax=4.0
    FollowRepathDistance=1224.0
    FollowNodeRepathDistSq=589824.0
    FollowForcePathDuration=2.0
    FollowMaxRouteNodes=24

    // Stuck detection
    FollowStuckWindow=1.5
    FollowStuckMinMove=32.0
    FollowSameNodeLimit=20

    // Wall / bump
    FollowWallHitThreshold=5
    FollowWallWindow=3.0
    FollowWallDebounce=0.2
    FollowBumpCooldown=0.5
    FollowYieldDist=64.0
    FollowYieldHold=0.3
    FollowYieldTimeout=0.75
    FollowEscapeDuration = 0.8;

    // Retry ladder / obstacle failover
    FollowRetriesBlockAt=5
    FollowRetriesGiveUpAt=10
    FollowRetryResetDist=384.0
    FollowMaxBlocksPerEpisode=2
    FollowBlockMinGap=2.0
    FollowGiveUpHold=2.0
}
