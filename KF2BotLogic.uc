class KF2BotLogic extends KF2BotBase
hidecategories(Navigation);

final function bool CheckShouldHealMate()
{
    local KFWeap_HealerBase W;
    local KFPawn_Human P, Best;
    local float Pct, DHoriz, DVert;
    local float EffectivePct, BestEffectivePct;

    if(mut == none)
    {
        return false;
    }
    if((KPawn == none) || !KPawn.IsAliveAndWell())
    {
        return false;
    }

    // Failure backoff: a failed heal stamps HealRetryAfter; the gate
    // rejects until the backoff elapses, preventing a livelock loop.
    if (WorldInfo.TimeSeconds < HealRetryAfter)
    {
        return false;
    }

    // Obs 1 / Obs 10: close-range syringe healing (HealOther) is highly
    // ineffective during active combat and caused the combat lockup. It is
    // only permitted during trader rounds; during combat the bot relies on
    // the ranged medic dart (CheckMedicGunHeal -> HealRanged) instead.
    if(KFGRI == none || !KFGRI.bTraderIsOpen)
    {
        return false;
    }

    MedicGun = none;
    foreach KFInvManager.InventoryActors(Class'KFGame.KFWeap_HealerBase', W)
    {
        if(W.HasAmmo(0))
        {
            MedicGun = W;
            break;
        }
    }
    if(MedicGun == none)
    {
        return false;
    }

    Best = none;
    BestEffectivePct = 0.0000000;
    foreach WorldInfo.AllPawns(Class'KFGame.KFPawn_Human', P, Pawn.Location, mut.HealCylinderRadius)
    {
        if(P == Pawn)
        {
            continue;
        }
        if(!P.IsAliveAndWell())
        {
            continue;
        }
        if(P.GetTeamNum() != GetTeamNum())
        {
            continue;
        }
        Pct = (float(P.Health) / float(P.HealthMax)) * 100.0000000;
        // Obs 10: proactive threshold -- a teammate is "needy" below 80%.
        if(Pct > HEAL_MAX_NEED_PCT)
        {
            continue;
        }
        if(!TargetLowHealth(P))
        {
            continue;
        }
        DHoriz = VSize(P.Location - Pawn.Location);
        DVert = Abs(P.Location.Z - Pawn.Location.Z);
        if(DHoriz > mut.HealCylinderRadius)
        {
            continue;
        }
        if(DVert > mut.HealCylinderHeight)
        {
            continue;
        }
        if(!ActorReachable(P))
        {
            continue;
        }
        if(mut.bEnableFastTraceHealing && !FastTrace(Pawn.Location, P.Location))
        {
            continue;
        }

        // P6 VIP Triage Bias fix (Loophole 2): only nudge priority toward
        // the VIP when they're already seriously wounded (<50% HP), and by
        // a bounded amount -- a lightly-scratched VIP can never leapfrog a
        // critically wounded teammate, but a genuinely wounded VIP in a
        // close call still wins.
        EffectivePct = Pct;
        if((mut.VIPController != none) && (P == mut.VIPController.Pawn) && (Pct < VIP_TRIAGE_GATE_PCT))
        {
            EffectivePct = FMax(Pct - VIP_TRIAGE_BONUS_PCT, 0.0);
        }

        if((Best == none) || (EffectivePct < BestEffectivePct))
        {
            Best = P;
            BestEffectivePct = EffectivePct;
        }
    }

    PendingHeal = Best;
    return Best != none;
}

final function bool CheckMedicGunHeal()
{
    local KFPawn_Human P, Best;
    local float Pct;
    local float EffectivePct, BestEffectivePct;

    if(mut == none)
    {
        return false;
    }
    if((KPawn == none) || !KPawn.IsAliveAndWell())
    {
        return false;
    }

    // Failure backoff: a failed heal stamps HealRetryAfter; the gate
    // rejects until the backoff elapses, preventing a livelock loop.
    if (WorldInfo.TimeSeconds < HealRetryAfter)
    {
        return false;
    }

    RangeMedicGun = KFWeap_MedicBase(Pawn.Weapon);
    if(RangeMedicGun == none)
    {
        return false;
    }
    if(!RangeMedicGun.HasAmmo(1))
    {
        return false;
    }

    Best = none;
    BestEffectivePct = 0.0000000;
    foreach WorldInfo.AllPawns(Class'KFGame.KFPawn_Human', P, Pawn.Location, 1800.0000000)
    {
        if(P == Pawn)
        {
            continue;
        }
        if(!P.IsAliveAndWell())
        {
            continue;
        }
        if(P.GetTeamNum() != GetTeamNum())
        {
            continue;
        }
        // 25s per-target cooldown: skip teammates who recently received a dart
        if(mut.IsRangedHealTargetOnCooldown(P))
        {
            continue;
        }
        Pct = (float(P.Health) / float(P.HealthMax)) * 100.0000000;
        // Obs 10: proactive threshold -- a teammate is "needy" below 80%.
        if(Pct > HEAL_MAX_NEED_PCT)
        {
            continue;
        }
        if(!TargetLowHealth(P))
        {
            continue;
        }
        if(mut.bEnableFastTraceHealing && !FastTrace(Pawn.Location, P.Location))
        {
            continue;
        }

        EffectivePct = Pct;
        if((mut.VIPController != none) && (P == mut.VIPController.Pawn) && (Pct < VIP_TRIAGE_GATE_PCT))
        {
            EffectivePct = FMax(Pct - VIP_TRIAGE_BONUS_PCT, 0.0);
        }

        if((Best == none) || (EffectivePct < BestEffectivePct))
        {
            Best = P;
            BestEffectivePct = EffectivePct;
        }
    }

    PendingHeal = Best;
    return Best != none;
}

final function bool CheckShouldSelfHeal()
{
    local KFWeap_HealerBase W;

    if(mut == none)
    {
        return false;
    }
    if((KPawn == none) || !KPawn.IsAliveAndWell())
    {
        return false;
    }

    // Failure backoff: a failed heal stamps HealRetryAfter; the gate
    // rejects until the backoff elapses, preventing a livelock loop.
    if (WorldInfo.TimeSeconds < HealRetryAfter)
    {
        return false;
    }

    // Primary threshold: bots attempt self-heal at 80% or below.
    if (KPawn.Health >= (HEAL_MAX_NEED_PCT / 100.0) * KPawn.HealthMax)
    {
        return false;
    }

    // Mechanical Recharge Timer (15s): the syringe requires a strict 15s
    // recharge after a self-heal. No heal is permitted under any
    // circumstance until this delay has elapsed.
    if (WorldInfo.TimeSeconds < SyringeRechargeEnd)
    {
        return false;
    }

    // Behavioral Pacing Timer (30s): prevents constant weapon-unequip for
    // minor chip damage. Bypassed in emergency (health < 50%) and while the
    // trader is open (trader rounds: let the bot fully top up on health).
    if (WorldInfo.TimeSeconds < HealPacingEnd && !(KFGRI != None && KFGRI.bTraderIsOpen))
    {
        // Emergency override: if health drops below 50%, bypass the pacing
        // gate since the mechanical recharge is already complete.
        if (KPawn.Health >= 0.50 * KPawn.HealthMax)
        {
            return false;
        }
    }

    MedicGun = none;
    foreach KFInvManager.InventoryActors(Class'KFGame.KFWeap_HealerBase', W)
    {
        if(W.HasAmmo(0))
        {
            MedicGun = W;
            break;
        }
    }
    return MedicGun != none;
}

final function bool ShouldNadeEnemies()
{
    local KFPawn_Monster M, B, Best;
    local byte T;
    local float Score, BestScore;

    T = GetTeamNum();
    // End:0x302
    foreach WorldInfo.AllPawns(Class'KFGame.KFPawn_Monster', M, Pawn.Location, 1400.0000000)
    {
        // End:0x10E
        if((!M.IsAliveAndWell() || !FastTrace(M.Location, Pawn.Location)) || M.GetTeamNum() == T)
        {
            continue;            
        }
        Score = FClamp(float(M.Health) / 5.0000000, 50.0000000, 150.0000000);
        // End:0x29D
        foreach WorldInfo.AllPawns(Class'KFGame.KFPawn_Monster', B, M.Location, 600.0000000)
        {
            // End:0x25E
            if((((B == M) || !B.IsAliveAndWell()) || !FastTrace(B.Location, M.Location)) || B.GetTeamNum() == T)
            {
                continue;                
            }
            Score += FClamp(float(B.Health) / 7.0000000, 50.0000000, 150.0000000);            
        }        
        // End:0x301
        if((Score > 300.0000000) && (Best == none) || Score > BestScore)
        {
            Best = M;
            BestScore = Score;
        }        
    }    
    // End:0x314
    if(Best == none)
    {
        return false;
    }
    Target = Best;
    return true;
    //return ReturnValue;    
}

function CheckGrabbed()
{
    // End:0x91
    if((((KPawn != none) && KPawn.Health > 0) && KPawn.IsDoingSpecialMove(31)) && KPawn.InteractionPawn != none)
    {
        GotoState('BreakLose');
        return;
    }
    // Echelon: grunt 2D offset + Z-step (Tier 1, Edge Case #1)
    if (BotRank == GRUNT)
    {
        UpdateGruntOffset();
    }
    //return;    
}

// ============================================================
//  Grunt Restricted Tick -- 2D Offset & Z-Step Navigation
// ============================================================

// Runs at a 0.2s cadence: computes the Grunt's formation target from the
// Squad Leader's position, applies tactical overrides (overwatch, rescue,
// crouching, panic variance), validates wall safety, and drives movement.
function UpdateGruntOffset()
{
    local vector GruntTarget;
    local vector OverwatchMoveTarget;
    local float sc;
    local vector bOff;
    local Controller VIP;

    // Grab override: a teammate being grabbed takes priority over all
    // other movement.
    if (((KPawn != none) && KPawn.Health > 0) && KPawn.IsDoingSpecialMove(31) && KPawn.InteractionPawn != none)
    {
        GotoState('BreakLose');
        return;
    }

    // Immersion: apply panic variance and track reload state.
    ApplyPanicVariance();
    TrackReloadState();

    // Formation focus sync: if in line formation, follow the inherited
    // focus GruntTarget.
    if(SyncLineFocus()) { return; }

    // Squad crouch hold: stay low when the squad is holding position.
    ApplySquadCrouchHold();

    // Null-reference guard (officer death) -- adopt last known valid position
    if (SquadLeader == none || SquadLeader.Pawn == none || SquadLeader.Pawn.Health <= 0)
    {
        if (LastValidSquadLeaderPos != vect(0, 0, 0))
        {
            MoveToX(LastValidSquadLeaderPos);
        }
        else
        {
            // Obs 4/7/8 -- Fallback: if no valid SL position, move toward the
            // VIP so the bot doesn't freeze in limbo. This resolves the
            // "permanently stuck" state seen in playtesting.
            VIP = (mut != None) ? mut.GetVIPController() : None;
            if (VIP != None && VIP.Pawn != None && VIP.Pawn.Health > 0)
            {
                MoveToX(VIP.Pawn.Location);
            }
        }
        // No valid SL -- arm the 10s promotion gap timer (Edge Case #2)
        if (!bPromotionGapTimerActive)
        {
            bPromotionGapTimerActive = true;
            SetTimer(10.0, false, 'PromotionGapTimer');
        }
        return;
    }

    // Track last valid SL time
    LastValidSLTime = WorldInfo.TimeSeconds;

    // SL is valid -- cancel the promotion-gap timer if it was armed
    // during the Restart()->SyncSquadLeaders() gap (Bug 2 fix).
    if (bPromotionGapTimerActive)
    {
        bPromotionGapTimerActive = false;
        SetTimer(0.0, false, 'PromotionGapTimer');
    }

    // Bounding overwatch: leapfrog movement toward the overwatch GruntTarget.
    if (bOverwatchMoving)
    {
        if (UpdateOverwatchMovement(OverwatchMoveTarget))
        {
            MoveToX(OverwatchMoveTarget);
        }
        return;
    }

    // Sector watch: when holding area with no enemy, sweep the sector.
    if (CurrentOrder == 'CMD_HoldArea' && Enemy == none)
    {
        UpdateSectorWatch();
        return;
    }

    // CQB proximity: flashlight / bash interlock in close quarters.
    HandleCQBProximity();

    // Buddy rescue: move to the grabbed teammate's location.
    if (RescueUntil > WorldInfo.TimeSeconds)
    {
        MoveToX(RescueLoc);
        return;
    }

    // Cover-aware crouching: stay low when behind cover in single file.
    UpdateCoverCrouch();

    // Reload drift: staggered reload movement to avoid simultaneous reloads.
    if (bReloadDriftMove && ReloadDriftUntil > WorldInfo.TimeSeconds)
    {
        MoveToX(ReloadDriftLoc);
        return;
    }

    // Wedge GruntTarget: human-centric bounding toward a focused human.
    if (SquadLeader != none && SquadLeader.bWedgeActive)
    {
        GruntTarget = SquadLeader.Pawn.Location;
        ApplyWedgeTarget(GruntTarget);
        GruntTarget = ApplyZStep(GruntTarget);
        MoveToX(GruntTarget);
        return;
    }

    // Formation offset GruntTarget: world-space offset rotated by the SL's heading.
    GruntTarget = SquadLeader.Pawn.Location + ComputeSlotOffset();

    // Panic / wave-momentum scale: compress the X/Y offset under pressure.
    sc = PanicVarianceMultiplier / GetWaveMomentum();
    GruntTarget.X = SquadLeader.Pawn.Location.X + (GruntTarget.X - SquadLeader.Pawn.Location.X) * sc;
    GruntTarget.Y = SquadLeader.Pawn.Location.Y + (GruntTarget.Y - SquadLeader.Pawn.Location.Y) * sc;

    // Breathing offset: subtle positional oscillation for immersion.
    bOff.X = Sin(BreathingPhase) * 10.0;
    bOff.Y = Cos(BreathingPhase) * 10.0;
    GruntTarget = GruntTarget + bOff;

    // Z-step navigation: resolve height differences on 3D terrain.
    GruntTarget = ApplyZStep(GruntTarget);

    // Wall safety: reject targets that would push the Grunt into geometry.
    // If blocked, fall back to the SL's position directly (no offset).
    // This prevents the 2-bot limbo lockup where Grunts get stuck behind
    // walls because their formation offset is unreachable.
    if(!ValidateOffsetTarget(GruntTarget))
    {
        GruntTarget = SquadLeader.Pawn.Location;
    }

    MoveToX(GruntTarget);
}

// Z-step -- take 50u toward GruntTarget Z (not a snap) when |DZ| > 200.
// The 50u step (reduced from 100u) and the 50u stability band prevent the
// continuous re-targeting loop that caused wall-bounce near doors/stairs.
//
// Cross-floor guard: when the target is on a different floor (>300u away in
// Z), snap to the bot's current floor Z. Targeting an unreachable floor Z
// made the bot walk to the floor edge and jump at the balcony/floor, because
// native pathing found no route to that height. Snapping to the current floor
// lets native pathing route on the floor (and via stairs when available).
function vector ApplyZStep(vector T)
{
    local float DZ;
    DZ = T.Z - Pawn.Location.Z;
    if (Abs(DZ) > 300.0)
    {
        // Different floor -- stay on the bot's current floor.
        T.Z = Pawn.Location.Z;
        return T;
    }
    if (Abs(DZ) > 200.0)
    {
        T.Z += (DZ > 0 ? 1.0 : -1.0) * 50.0;
    }
    // Stability band: if within 50u of target Z, snap to avoid micro-jitter
    if (Abs(T.Z - Pawn.Location.Z) <= 50.0)
    {
        T.Z = Pawn.Location.Z;
    }
    return T;
}

// Request SL reroute after 3 consecutive blocks (Tier 2 implements SL response)
function RequestReroute()
{
    LastValidSquadLeaderPos = SquadLeader.Pawn.Location;
}

// 10s self-promotion failsafe (Edge Case #2)
// Promotes a Grunt to SQUAD_LEADER when its Squad Leader is permanently
// lost. After promotion the bot must enter a valid combat state, because
// the restricted CheckGrabbed tick no longer drives SQUAD_LEADER movement.
function PromotionGapTimer()
{
    bPromotionGapTimerActive = false;
    if (BotRank == GRUNT && (SquadLeader == none || SquadLeader.Pawn == none || SquadLeader.Pawn.Health <= 0))
    {
        SetBotRank(SQUAD_LEADER);
        PickCombatStyle();
    }
}

// Heal-animation-hang failsafe -- never cleared during the animation
// Echelon Healing: shared affordability predicate. Gate AND state must
// agree on the same ammo threshold to prevent the 1-99 silent-skip livelock.
function bool CanAffordHeal(int Type)
{
    if (Type == 0)
    {
        return (MedicGun != none) && (MedicGun.AmmoCount[0] >= 100.0);
    }
    return (RangeMedicGun != none) && (RangeMedicGun.AmmoCount[1] >= 50.0);
}

// Echelon Healing: every non-success exit routes through here. Stamps a
// bounded backoff so a failing heal cannot livelock the priority chain.
function HealFail()
{
    FailStreak++;
    HealRetryAfter = WorldInfo.TimeSeconds + FMin(4.0 * FailStreak, 20.0);
    PendingHeal = none;
}

// Echelon Healing: the ONLY place 15s/30s pacing stamps are written.
// A failed heal never stamps pacing — it uses HealFail()'s backoff instead.
function HealSuccess()
{
    FailStreak = 0;
    SyringeRechargeEnd = WorldInfo.TimeSeconds + 15.0;
    // Behavioral pacing randomized to 20-30s so the 15s syringe lockout
    // and the pacing gate desync across bots instead of running in lockstep.
    HealPacingEnd = WorldInfo.TimeSeconds + (20.0 + FRand() * 10.0);
}

// Echelon Healing: global safety net. Replaces the dead HealTimeOut timer.
// Fires 1.5s after any heal-state exit; if the bot is still holding a
// healer in a non-heal state, force-switch to the best combat weapon.
function VerifyWeapon()
{
    if (Pawn == none)
    {
        return;
    }
    if (GetStateName() == 'HealingSelf' || GetStateName() == 'HealOther' || GetStateName() == 'HealRanged')
    {
        return;
    }
    if(KFWeap_HealerBase(Pawn.Weapon) != none)
    {
        Pawn.InvManager.SwitchToBestWeapon(true);
    }
}

function HealTimeOut()
{
    PickCombatStyle();
}

// Pathfinding Budget
// Limits pathfinding calls to prevent CPU frame spikes.
// Max 10 pathfinding calls per second across all bots.
function bool ConsumePathToken()
{
    if (WorldInfo.TimeSeconds > PathTokenResetTime)
    {
        PathTokensUsed = 0;
        PathTokenResetTime = WorldInfo.TimeSeconds + 1.0;
    }
    if (PathTokensUsed >= 10)
    {
        return false;
    }
    PathTokensUsed++;
    return true;
}
// Grunt Decision Timer
// Grunts make tactical decisions (engage, retreat, flank) every 1.5 seconds.
// This is the primary driver for bEngageActive and PanicActive states.
// Runs every 1.5s to keep Grunts responsive during trader rounds and combat.
function GruntDecisionTimer()
{
    local KFPawn_Monster M;
    local float BestDist;
    local float D;
    if (BotRank != GRUNT) return;
    if (Pawn == none || KPawn == none || !KPawn.IsAliveAndWell()) return;

    // Set bEngageActive if an enemy is within 800u
    BestDist = 800.0;
    foreach VisibleCollidingActors(class'KFPawn_Monster', M, 800.0, Pawn.Location)
    {
        if (M.IsAliveAndWell())
        {
            D = VSize(M.Location - Pawn.Location);
            if (D < BestDist)
            {
                BestDist = D;
            }
        }
    }

    if (BestDist < 800.0)
    {
        if (!bEngageActive)
        {
            bEngageActive = true;
            EchelonLog("GruntDecisionTimer: bEngageActive=true (enemy at " $ string(int(BestDist)) $ "u)");
        }
    }
    else
    {
        bEngageActive = false;
    }
}
// AUDIT_3B Step 6: Idle watchdog (per-bot, staggered).
// Two signal checks: (1) stale move-intent OR stale hub contact outside the
// legit-idle whitelist => idle candidate; (2) displacement since idle start
// < AUDIT_IDLE_STUCK_DELTA => physically stuck regardless of intents.
// Whitelisted states are only legit while the bot is still making progress
// (goal distance shrinking); a non-progressing Camp/Holding escalates.
// Escalation ladder (5s between steps): 1 = re-issue squad order,
// 2 = attach to nearest active leader (bot or human), 3 = self-promote
// and fall through to the default hunt flow (P8.5 zed thresholds).
function IdleWatchdogTimer()
{
    SetTimer(AUDIT_WD_PERIOD, false, 'IdleWatchdogTimer');
    IdleWatchdog();
}

function IdleWatchdog()
{
    local float IterNow;
    local float IterSinceIntent;
    local float IterSinceHub;
    local float IterStuckDelta;
    local float IterGoalD2;
    local name IterState;
    local bool bLegitState;
    local bool bNotIdle;
    local bool bStuck;
    local bool bProgressing;
    local bool bAttached;
    local NavigationPoint IterGoalN;
    local Controller IterAttachCtrl;

    if (Pawn == none || KPawn == none || !KPawn.IsAliveAndWell()) return;
    IterNow = WorldInfo.TimeSeconds;
    IterSinceIntent = IterNow - WdLastMoveIntentTime;
    IterSinceHub = IterNow - WdLastHubContactTime;
    IterState = GetStateName();
    bLegitState = (IterState == 'HealingSelf' || IterState == 'HealOther' ||
        IterState == 'HealRanged' || IterState == 'BreakLose' ||
        IterState == 'VictoryDance' || IterState == 'Camp' ||
        IterState == 'GoShopping' || IterState == 'FollowingLeader' ||
        IterState == 'FollowingLeaderBasic' || IterState == 'DoObjective' ||
        IterState == 'Hunting');
    // A bot actively engaged with a live enemy is legitimately stationary
    // (aiming/reloading), not idle.
    if (!bLegitState && IterState == 'FightEnemy' && Enemy != None && Enemy.Health > 0)
    {
        bLegitState = true;
    }
    // Idle means BOTH signals stale: no fresh decision AND no hub contact.
    // (OR would flag every solo hunter, whose hub contact is only at
    // registration, even while actively moving.)
    bNotIdle = !bLegitState && (IterSinceIntent > AUDIT_INTENT_TIMEOUT && IterSinceHub > AUDIT_HUB_TIMEOUT);

    if (!bNotIdle)
    {
        // Not idle: reset escalation bookkeeping.
        bWdEscalating = false;
        WdEscStep = 1;
        WdLastStepTime = 0.0;
        WdProgressGoalD2 = 0.0;
        return;
    }

    // Idle candidate: arm the displacement window on entry.
    if (!bWdEscalating)
    {
        bWdEscalating = true;
        WdEscStep = 1;
        WdLastStepTime = 0.0;
        WdProgressGoalD2 = 0.0;
        WdIdleStartLoc = Pawn.Location;
        EchelonLog("WD_IDLE bot=" $ Name $ " state=" $ IterState $ " intentAge=" $ string(IterSinceIntent) $ " hubAge=" $ string(IterSinceHub));
        return;
    }

    // Escalating: stuck check + progress check, then fire on cooldown.
    IterStuckDelta = VSize(Pawn.Location - WdIdleStartLoc);
    bStuck = (IterStuckDelta < AUDIT_IDLE_STUCK_DELTA);
    IterGoalN = None;
    if (mut != None)
    {
        IterGoalN = mut.GetBotObjective(KF2Bot(self));
    }
    if (IterGoalN != None)
    {
        IterGoalD2 = VSizeSq(Pawn.Location - IterGoalN.Location);
        if (WdProgressGoalD2 == 0.0 || IterGoalD2 < WdProgressGoalD2)
        {
            bProgressing = true;
            WdProgressGoalD2 = IterGoalD2;
        }
        else
        {
            bProgressing = false;
        }
    }
    else
    {
        // No goal to track: displacement is the only signal.
        bProgressing = !bStuck;
    }
    if (!bStuck && bProgressing)
    {
        // Making progress despite an odd state: de-escalate quietly.
        bWdEscalating = false;
        WdEscStep = 1;
        WdLastStepTime = 0.0;
        WdProgressGoalD2 = 0.0;
        return;
    }
    if (IterNow - WdLastStepTime < AUDIT_WD_STEP_COOLDOWN)
    {
        return;
    }
    WdLastStepTime = IterNow;

    if (WdEscStep == 1)
    {
        // Step 1: re-issue the squad order (stale bail -> fresh bail + resample).
        if (mut != None && mut.HasSquadGoal(KF2Bot(self)))
        {
            mut.ReissueSquadOrder(KF2Bot(self));
            EchelonLog("WD_FIRE bot=" $ Name $ " step=1 reissue state=" $ IterState $ " delta=" $ string(IterStuckDelta));
            WdEscStep++;
        }
        else
        {
            // No squad goal: nothing to re-issue, advance the ladder.
            WdEscStep = 2;
        }
    }
    else if (WdEscStep == 2)
    {
        // Step 2: attach to nearest active leader (bot or human).
        bAttached = false;
        if (SquadLeader == None || SquadLeader.Pawn == None || SquadLeader.Pawn.Health <= 0)
        {
            IterAttachCtrl = None;
            if (mut != None)
            {
        IterAttachCtrl = mut.FindNearestActiveLeader(KF2Bot(self), AUDIT_ATTACH_RADIUS);
            }
            if (IterAttachCtrl != None)
            {
        if (KF2Bot(IterAttachCtrl) != None)
        {
            // ReassignBotToGroup expects the 0-based Fireteam index (GroupID is 1-based).
            mut.ReassignBotToGroup(KF2Bot(self), KF2Bot(IterAttachCtrl).GroupID - 1);
        }
        EchelonLog("WD_FIRE bot=" $ Name $ " step=2 attach leader=" $ string(IterAttachCtrl.Name));
        FollowStart(IterAttachCtrl);
        bWdEscalating = false;
        WdEscStep = 1;
        WdLastStepTime = 0.0;
        WdProgressGoalD2 = 0.0;
        bAttached = true;
            }
        }
        if (!bAttached)
        {
            // Leader alive, or no leader in radius: advance the ladder.
            WdEscStep = 3;
        }
    }
    else
    {
        // Step 3: terminal recovery — force a fresh pick; the native
        // pick-move flow handles self-promotion and P8.5 zed hunting.
        EchelonLog("WD_FIRE bot=" $ Name $ " step=3 fresh-pick state=" $ IterState $ " delta=" $ string(IterStuckDelta));
        GotoState('PickNextMove');
        bWdEscalating = false;
        WdEscStep = 1;
        WdLastStepTime = 0.0;
        WdProgressGoalD2 = 0.0;
    }
}
// Lieutenant Path Timer
// Lieutenants re-evaluate their path every 2.0 seconds. Uses FindPathToward
// with a PathTokens budget to prevent native UE3 pathfinding thread stalls.
function CaptainPathTimer()
{
    if (BotRank != LIEUTENANT) return;
    
    // PathTokens budget: max 3 pathfinding calls per second
    // Full implementation will be added in a later batch.
    EchelonLog("CaptainPathTimer: path re-evaluation");
}
// Overwatch Leapfrog
// Bots alternate between "overwatch" (holding position, covering) and
// "advance" (moving forward) phases. The Captain toggles the phase
// every 5 seconds via the MacroTimer.
function ProcessOverwatchPhase()
{
    if (BotRank != CAPTAIN) return;
    
    // Toggle overwatch phase every 5 seconds
    if (WorldInfo.TimeSeconds > EngageExpireTime)
    {
        bOverwatchPhase = !bOverwatchPhase;
        EngageExpireTime = WorldInfo.TimeSeconds + 5.0;
        EchelonLog("Overwatch phase toggled: " $ (bOverwatchPhase ? "HOLD" : "ADVANCE"));
    }
}
// AUDIT 2nd-priority(b): break the follower limbo. A bot sitting in
// FollowingLeader never re-evaluates P5 (objective) or P9 (trader) because
// PickCombatStyle early-returns while in a follower state. This override runs
// from the base's FollowWatchdog each pass; when a higher-priority goal
// appears it sets FollowExitState + bFollowExitPending and the base's Dispatch
// GotoStates out of the follower state to that goal.
function bool FollowCheckExit()
{
    local int IterDistSq;

    if (KFGRI != none
        && KFGRI.bTraderIsOpen
        && KFGRI.OpenedTrader != none
        && NextShoppingTime < WorldInfo.TimeSeconds)
    {
        FollowExitState = 'GoShopping';
        bFollowExitPending = true;
        EchelonLog("FOLLOWGATE_EVAL bot=" $ Name $ " slot=" $ string(FollowSlotIndex) $ " result=GoShopping");
        // Step 6 signal: hub-directed follower evaluation = hub contact.
        WdLastHubContactTime = WorldInfo.TimeSeconds;
        return true;
    }

    if (mut != none
        && mut.bObjectiveActive
        && ObjectiveGoal != none)
    {
        IterDistSq = VSizeSq(ObjectiveGoal.Location - Pawn.Location);
        if (IterDistSq > SYG_DISTANCE_SQ
            && WorldInfo.TimeSeconds >= ObjectiveBailUntil)
        {
            FollowExitState = 'DoObjective';
            bFollowExitPending = true;
            EchelonLog("FOLLOWGATE_EVAL bot=" $ Name $ " slot=" $ string(FollowSlotIndex) $ " result=DoObjective distSq=" $ string(IterDistSq));
            // Step 6 signal: hub-directed follower evaluation = hub contact.
            WdLastHubContactTime = WorldInfo.TimeSeconds;
            return true;
        }
    }
    return false;
}

function PawnDied(Pawn inPawn)
{
    local int Idx;

    // End:0x19
    if(inPawn != Pawn)
    {
        return;
    }
    ActivatePlayerDiedSequenceEvents();
    TriggerEventClass(Class'Engine.SeqEvent_Death', self);
    Idx = 0;
    J0x45:

    // End:0xAE [Loop If]
    if(Idx < LatentActions.Length)
    {
        // End:0xA0
        if(LatentActions[Idx] != none)
        {
            LatentActions[Idx].AbortFor(self);
        }
        Idx++;
        // [Loop Continue]
        goto J0x45;
    }
    LatentActions.Length = 0;
    // End:0x109
    if(Pawn != none)
    {
        SetLocation(Pawn.Location);
        Pawn.UnPossessed();
    }
    Pawn = none;
    // Clear all rank timers before death so no decision loops fire after
    // the bot is gone.
    ClearRankTimers();
    GotoState('Dead');
    //return;    
}

final function ActivatePlayerDiedSequenceEvents()
{
    local Sequence GameSeq;
    local array<SequenceObject> AllSeqEvents;
    local array<int> ActivateIndices;
    local int I;
    local KFGameInfo KFGI;

    KFGI = KFGameInfo(WorldInfo.Game);
    GameSeq = WorldInfo.GetGameSequence();
    // End:0x166
    if((GameSeq != none) && KFGI != none)
    {
        GameSeq.FindSeqObjectsByClass(Class'KFGame.KFSeqEvent_PlayerDied', true, AllSeqEvents);
        // End:0xE1
        if(KFGI.GetLivingPlayerCount() > 0)
        {
            ActivateIndices[0] = 0;            
        }
        else
        {
            ActivateIndices[0] = 1;
        }
        I = 0;
        J0xF9:

        // End:0x166 [Loop If]
        if(I < AllSeqEvents.Length)
        {
            KFSeqEvent_PlayerDied(AllSeqEvents[I]).CheckActivate(WorldInfo, none, false, ActivateIndices);
            I++;
            // [Loop Continue]
            goto J0xF9;
        }
    }
    //return;    
}

final function PickRetreatMove()
{
    local NavigationPoint N, Best;
    local float Score, BestScore;

    // End:0x209
    foreach WorldInfo.RadiusNavigationPoints(Class'Engine.NavigationPoint', N, Pawn.Location, 1200.0000000)
    {
        // End:0xAD
        if(VSizeSq2D(N.Location - Pawn.Location) < 6400.0000000)
        {
            continue;            
        }
        // End:0x14B
        if(Enemy != none)
        {
            Score = VSizeSq(N.Location - Enemy.Location) - VSizeSq(N.Location - Pawn.Location);            
        }
        else
        {
            Score = VSizeSq(N.Location - Pawn.Location);
        }
        Score *= (0.5000000 + FRand());
        // End:0x208
        if(((Best == none) || BestScore < Score) && ActorReachable(N))
        {
            Best = N;
            BestScore = Score;
        }        
    }    
    // End:0x2E9
    if(Best == none)
    {
        // End:0x260
        if(Enemy == none)
        {
            MoveToX(Pawn.Location + (VRand() * 400.0000000));            
        }
        else
        {
            MoveToX(((Normal(Pawn.Location - Enemy.Location) * 500.0000000) + Pawn.Location) + (VRand() * 200.0000000), Enemy);
        }        
    }
    else
    {
        MoveTowardX(Best, Enemy);
    }
    //return;    
}

final function bool FindCollectable()
{
    local KFPickupFactory P;
    local KFPickupFactory_Item I;

    // End:0x14D
    foreach VisibleCollidingActors(Class'KFGame.KFPickupFactory', P, 800.0000000, Pawn.Location, true)
    {
        // End:0x14C
        if((LastFactory != P) && !P.bPickupHidden)
        {
            I = KFPickupFactory_Item(P);
            // End:0xBE
            if(I == none)
            {
                // End:0xBA
                if(ActorReachable(P))
                {
                    // End:0x14D
                    break;
                }
                continue;                
            }
            // End:0x14C
            if(((I.CurrentPickupIsArmor() && KPawn != none) && KPawn.Armor < KPawn.MaxArmor) && ActorReachable(P))
            {
                // End:0x14D
                break;
            }
        }        
    }    
    // End:0x172
    if(P != none)
    {
        LastFactory = P;
        return true;
    }
    return false;
    //return ReturnValue;    
}

event NotifyJumpApex()
{
    Pawn.DoJump(false);
    //return;    
}

function string GetAIInfo()
{
    return (((((((((((("State:" $ string(GetStateName())) $ " MoveType:") $ string(MoveFlags)) $ " AdjustMove:") $ string(bAdjusting)) $ " MoveTarget:") $ string(MoveTarget)) $ " Pawn:") $ string(Pawn)) $ " Pawn.State:") $ string(((Pawn != none) ? Pawn.GetStateName() : 'None'))) $ " Pawn.Health:") $ string(((Pawn != none) ? Pawn.Health : 0));
    //return ReturnValue;    
}

simulated event ReplicatedEvent(name VarName)
{
    switch(VarName)
    {
        // End:0x30
        case 'RagdollMove':
            GotoState('IsRagdolled');
            // End:0x50
            break;
        // End:0x4D
        case 'EndRagdollMove':
            if (bInTerminalState)
            {
                GotoState('VictoryDance');
            }
            else
            {
                GotoState('PickNextMove');
            }
            break;
        // End:0xFFFF
        default:
            break;
    }
    //return;    
}

function FinishObjective()
{
    AuditGoalLog("GOAL_CLEAR", "FinishObjective");
    ObjectiveGoal = none;
    ObjectiveBailUntil = 0.0;
    LastNodeBlockTime = 0.0;
    NodeBlockCount = 0;
    //return;    
}

final function Vector GetPointNear(Pawn Other, float MaxDist)
{
    local Vector V, HL, HN, E, Start;

    local byte I;

    E = Other.GetCollisionExtent();
    Start = Other.Location;
    // End:0x100
    if(Other.Physics == 2)
    {
        Start.Z -= float(1000);
        // End:0x100
        if(Trace(HL, HN, Start, Other.Location, false, E) != none)
        {
            Start = HL;
        }
    }
    E *= 0.7500000;
    I = 0;
    J0x11C:

    // End:0x281 [Loop If]
    if(true)
    {
        ++I;
        V.X = FRand() - 0.5000000;
        V.Y = FRand() - 0.5000000;
        V = Start + (Normal2D(V) * ((0.2500000 + (FRand() * 0.7500000)) * MaxDist));
        // End:0x21D
        if(Trace(HL, HN, V, Start, false, E) != none)
        {
            // End:0x21A
            if(I >= 25)
            {
                V = HL;
                // [Explicit Break]
                goto J0x281;                
            }
            else
            {
                // [Explicit Continue]
                goto J0x27E;
            }
        }
        // End:0x27E
        if((Trace(HL, HN, V - vect(0.0000000, 0.0000000, 500.0000000), V, false, E) != none) || I >= 25)
        {
            // [Explicit Break]
            goto J0x281;
        }
        J0x27E:

        // [Loop Continue]
        goto J0x11C;
    }
    J0x281:

    return V;
    //return ReturnValue;    
}

function NotifyKilled(Controller Killer, Controller Killed, Pawn KilledPawn, Class<DamageType> damageTyp)
{
    super(Controller).NotifyKilled(Killer, Killed, KilledPawn, damageTyp);
    // End:0x62
    if(KFPawn_MonsterBoss(KilledPawn) != none)
    {
        bBossKillVictory = true;
        GotoState('VictoryDance');
        return;
    }
    //return;    
}

function bool EvaluateSquadTether()
{
    local vector TDiff;

    if (Pawn == None || mut == None) return false;
    // Trader window: while the trader is open and more than
    // TRADER_REFORM_REMAINING seconds remain, drop the squad tether and let
    // each bot roam within TRADER_ROAM_RADIUS of the trader. Bots that drift
    // beyond the band path back to the trader. In the final seconds the
    // tether re-engages below (squad re-formation).
    if (KFGRI != None && KFGRI.bTraderIsOpen && KFGRI.OpenedTrader != None
        && KFGRI.GetTraderTimeRemaining() > TRADER_REFORM_REMAINING)
    {
        TDiff = Pawn.Location - KFGRI.OpenedTrader.Location;
        if (TDiff.X * TDiff.X + TDiff.Y * TDiff.Y + TDiff.Z * TDiff.Z > TRADER_ROAM_RADIUS_SQ)
        {
            // Drifted beyond the roam band: head back to the trader.
            MoveTowardGoal(KFGRI.OpenedTrader, vect(0, 0, 0), true);
            return true;
        }
        return false;
    }
    if (!IsAnchorValid(AssignedAnchor)) return false;
    if (bIsGroupLeader) return EvaluateLeaderMove();
    return EvaluateFollowerMove();
}

function bool IsAnchorValid(Actor Anchor)
{
    local Pawn AnchorPawn;
    if (Anchor == None || Anchor.bDeleteMe) return false;
    AnchorPawn = Pawn(Anchor);
    if (AnchorPawn != None && AnchorPawn.Health <= 0) return false;
    return true;
}

function bool EvaluateLeaderMove()
{
    UpdatePillarOfSaltTracking();
    if (bAttemptingUnweld) return false;
    UpdateCQBFormation();
    return MoveTowardGoal(AssignedAnchor, vect(0,0,0), true);
}

function bool EvaluateFollowerMove()
{
    local KF2Bot Leader;
    local vector FormationGoal;

    Leader = mut.GetGroupLeader(GroupID);

    // GC null-check -- Leader can be killed/demoted mid-evaluation.
    if (Leader == None || Leader.Pawn == None || Leader.Pawn.Health <= 0)
    {
        bHasHoldPosition = false;
        return MoveTowardGoal(AssignedAnchor, vect(0,0,0), true);
    }

    // P4 Retreat Paradox fix (Loophole 4): while the leader is actively
    // retreating, followers hold their current ground instead of tethering
    // toward AssignedAnchor -- which may sit back on the far side of the
    // horde the leader is falling back from -- rather than walking straight
    // into it.
    if (Leader.bIsRetreating)
    {
        if (!bHasHoldPosition)
        {
            HoldPosition = Pawn.Location;
            bHasHoldPosition = true;
        }
        if (VSizeSq(Pawn.Location - HoldPosition) > FOLLOWER_DRIFT_SQ)
        {
            return MoveTowardGoal(None, HoldPosition, false);
        }
        Pawn.Acceleration = vect(0.0, 0.0, 0.0);
        return false;
    }
    bHasHoldPosition = false;

    if (Leader.bIsStuck)
    {
        return MoveTowardGoal(AssignedAnchor, vect(0,0,0), true);
    }

    // HCA follower activation hook (Plan B): hand tethering to the follower
    // nav base. FollowStart is void (FollowSetLeader + GotoState); the
    // follower state then owns the slot ring, hysteresis, A* budget and the
    // staggered repath. Leader is already null-checked above. Flag OFF
    // falls through to the legacy formation-offset path below.
    if (bEnableAdvancedLocomotion)
    {
        FollowStart(Leader);
        `log("[FollowNav] KF2Bot: FollowStart issued; leaderGroup=" $ string(Leader.GroupID) $ " slot=" $ string(FollowSlotIndex) $ "/" $ string(FollowSlotCount));
        return true;
    }

    FormationGoal = ComputeFormationOffset(Leader, Leader.bSingleFileFormation);
    return MoveTowardGoal(None, FormationGoal, false);
}

function bool MoveTowardGoal(Actor GoalActor, vector GoalPoint, bool bActorGoal)
{
    local NavigationPoint PathNode;
    if (bActorGoal && GoalActor != None)
    {
        PathNode = NavigationPoint(FindPathToward(GoalActor));
        LastRouteDist = RouteDist;
        if (PathNode != None)
        {
            MoveTowardX(PathNode);
            return true;
        }
        MoveToX(GoalActor.Location);
        return true;
    }
    MoveToX(GoalPoint);
    return true;
}

function UpdateCQBFormation()
{
    local vector RightVec, ProbeStart, ProbeEndLeft, ProbeEndRight;
    local bool bLeftClear, bRightClear;

    if (Pawn == None || AssignedAnchor == None) return;
    if (WorldInfo.TimeSeconds - LastCQBCheckTime < CQB_TRACE_INTERVAL) return;
    if (VSizeSq(Pawn.Location - AssignedAnchor.Location) >= CQB_TRACE_RADIUS_SQ) return;

    LastCQBCheckTime = WorldInfo.TimeSeconds;

    RightVec = Normal(vector(Pawn.Rotation) cross vect(0,0,1));
    ProbeStart = Pawn.Location;
    ProbeEndLeft  = ProbeStart - (RightVec * CQB_PROBE_DIST);
    ProbeEndRight = ProbeStart + (RightVec * CQB_PROBE_DIST);

    bLeftClear  = FastTrace(ProbeEndLeft, ProbeStart);
    bRightClear = FastTrace(ProbeEndRight, ProbeStart);

    bSingleFileFormation = (!bLeftClear || !bRightClear);
}

function UpdatePillarOfSaltTracking()
{
    local KFDoorMarker Marker;
    local bool bFoundDoor;

    if (Pawn == None) return;

    if (!bHasStuckBaseline)
    {
        LeaderLocation3SecAgo = Pawn.Location;
        LastStuckSampleTime = WorldInfo.TimeSeconds;
        bHasStuckBaseline = true;
        return;
    }

    if (WorldInfo.TimeSeconds - LastStuckSampleTime < STUCK_SAMPLE_INTERVAL) return;

    bIsStuck = (VSizeSq(Pawn.Location - LeaderLocation3SecAgo) < STUCK_DIST_SQ);

    if (bIsStuck)
    {
        bFoundDoor = false;
        foreach Pawn.OverlappingActors(class'KFDoorMarker', Marker, DOOR_CHECK_RADIUS)
        {
            // Ghost Door GC fix (Loophole 5): KFDoorMarker can persist on the nav
            // mesh after its KFDoorActor is destroyed/opened/unwelded -- marker
            // presence alone isn't enough, verify the door is still a real,
            // closed, welded obstruction.
            if (Marker.MyKFDoor == none || Marker.MyKFDoor.bIsDestroyed) continue;
            if (Marker.MyKFDoor.bIsDoorOpen || Marker.MyKFDoor.WeldIntegrity <= 0) continue;

            bFoundDoor = true;
            break;
        }

        if (bFoundDoor)
        {
            bAttemptingUnweld = true;
            bIsStuck = false;
        }
        else
        {
            bAttemptingUnweld = false;
            mut.RequestLeaderDemotion(KF2Bot(self));
        }
    }
    else
    {
        bAttemptingUnweld = false;
    }

    LeaderLocation3SecAgo = Pawn.Location;
    LastStuckSampleTime = WorldInfo.TimeSeconds;
}

function bool ExecuteCampState()
{
    // P10 Camp: dedicated stationary hold -- replaces the fallback into
    // Roaming (which would wander via BuildRandomPath()).
    GotoState('Camp');
    return true;
}

function ResetStuckState()
{
    bHasStuckBaseline = false;
    bIsStuck          = false;
}
