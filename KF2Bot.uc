class KF2Bot extends KF2BotLogic
hidecategories(Navigation);

state PickNextMove
{
    event BeginState(Name PreviousStateName)
    {
        AuditStateEntry();
        `log("KF2BOT: SUCCESS - Entered PickNextMove from " $ PreviousStateName);
    }

    event EndState(name NextStateName)
    {
        AuditStateExit(NextStateName);
    }

    function PickMove()
    {
        local bool bHasAmmo;
        // AUDIT_3B Step 7 (regroup): hoisted locals for the P4.5 block.
        local float RegroupElapsed;
        local int RegroupMyIdx, RegroupTargetIdx, RegroupMySize, RegroupTargetSize, ZedNearLeader;
        local Controller RegroupAttach;
        local KF2Bot RegroupAttachBot, RegroupHoldLeader;
        // Priority 1: Match Ended -- terminal, no further evaluation. Guarded
        // centrally in PickCombatStyle() too; this copy covers the direct
        // GotoState('PickNextMove') from ReplicatedEvent('EndRagdollMove').
        if (bInTerminalState)
        {
            GotoState('VictoryDance');
            return;
        }
        if (mut != none && mut.KF != none && mut.KF.MyKFGRI != none && mut.KF.MyKFGRI.bMatchIsOver)
        {
            GotoState('VictoryDance');
            return;
        }

        // Priority 2: Grabbed Override -- handled as an async interrupt via
        // CheckGrabbed()/BreakLose (see Restart()'s timer), not as a
        // sequential branch here. Per Design Doc aSec2.3.

        // Priority 3: Critical Survival -- Health < 80% HealthMax.
        // Pacing stamps (15s/30s) are set in HealSuccess() on the state's
        // happy path, not here. A failed heal uses HealFail()'s bounded
        // backoff instead, preventing a livelock without a 30s dead zone.
        if (KPawn != none && CheckShouldSelfHeal())
        {
            GotoState('HealingSelf');
            return;
        }

        // Priority 4: Tactical Retreat -- leader-only trigger; followers react
        // passively via EvaluateFollowerMove()'s Leader.bIsRetreating check
        // during P8 below.
        if (bIsGroupLeader && KPawn != none && !bIsRetreating && ShouldTacticalRetreat())
        {
            bIsRetreating = true;
            GotoState('TacticalRetreat');
            return;
        }

        // Priority 4.5: Regroup (AUDIT_3B Step 7) -- squad formation/safety
        // state. Preempts objective work (P5) but not lethal retreat (P4).
        // Followers in FollowingLeader states exit via FollowCheckExit
        // instead; this block runs for non-follower states only.
        if (mut != None && mut.GetSquadPhase(self) == mut.PHASE_REGROUP
            && !IsInState('FollowingLeader') && !IsInState('FollowingLeaderBasic'))
        {
            RegroupElapsed = WorldInfo.TimeSeconds - mut.GetSquadStartTime(self);
            if (RegroupElapsed < REGROUP_HARD_TIMEOUT && Pawn != None)
            {
                // Branch 1: trader open -- identical condition to P9 (single
                // source of truth); the hard cap is GoShopping's own
                // give-up/cooldown.
                if (RegroupElapsed < REGROUP_DURATION
                    && KFGRI.bTraderIsOpen && NextShoppingTime < WorldInfo.TimeSeconds && KFGRI.OpenedTrader != None)
                {
                    EchelonLog("REGROUP_SHOP bot=" $ Name $ " src=PickMove");
                    GotoState('GoShopping');
                    return;
                }
                // Branch 2: zeds worth engaging -- 1-14 global hunt, 16-30
                // sweep nearest (the Hunting state handles both).
                if (RegroupElapsed < REGROUP_DURATION
                    && GlobalZedCount > 0 && GlobalZedCount != 15 && GlobalZedCount <= 30)
                {
                    EchelonLog("REGROUP_HUNT bot=" $ Name $ " zeds=" $ string(GlobalZedCount));
                    GotoState('Hunting');
                    return;
                }
                // Branch 3: no zeds / deadband 15 -> hold near leader; > 30
                // zeds falls through to normal combat priorities (P5-P10).
                if (GlobalZedCount <= 30)
                {
                    if (bIsGroupLeader && !mut.HasSquadGoal(self))
                    {
                        ZedNearLeader = mut.CountZedsInRadius(Pawn.Location, mut.REGROUP_SCAN_RADIUS);
                        if (ZedNearLeader == 0)
                        {
                            // Inter-squad rule: attach the WHOLE squad to the
                            // nearest active leader or human within
                            // AUDIT_ATTACH_RADIUS. Merge only when the target
                            // leader's squad is also idle (larger absorbs
                            // smaller). Humans are attach anchors only --
                            // never merged.
                            RegroupMyIdx = GroupID - 1;
                            RegroupAttach = mut.FindNearestActiveLeader(self, AUDIT_ATTACH_RADIUS);
                            RegroupAttachBot = KF2Bot(RegroupAttach);
                            if (RegroupAttachBot != None && RegroupAttachBot.GroupID - 1 != RegroupMyIdx)
                            {
                                RegroupTargetIdx = RegroupAttachBot.GroupID - 1;
                                RegroupMySize = mut.GetGroupSize(GroupID);
                                RegroupTargetSize = mut.GetGroupSize(RegroupAttachBot.GroupID);
                                if (RegroupMySize > RegroupTargetSize
                                    && mut.GetSquadPhase(RegroupAttachBot) == mut.PHASE_REGROUP)
                                {
                                    // I'm the larger idle squad: absorb target.
                                    mut.MoveSquadMembers(RegroupTargetIdx, RegroupMyIdx);
                                }
                                else
                                {
                                    // Attach (active target) or merge (idle
                                    // target, I'm smaller): move my squad in.
                                    mut.MoveSquadMembers(RegroupMyIdx, RegroupTargetIdx);
                                }
                                EchelonLog("REGROUP_ATTACH bot=" $ Name $ " target=" $ string(RegroupTargetIdx + 1) $ " size=" $ string(RegroupMySize));
                                // If I was re-parented, follow my new SquadLeader.
                                if (!bIsGroupLeader && SquadLeader != None && SquadLeader.Pawn != None)
                                {
                                    FollowStart(SquadLeader);
                                    return;
                                }
                            }
                            else if (RegroupAttach != None && RegroupAttach.PlayerReplicationInfo != None)
                            {
                                // Human anchor: leader follows; grunts chain via
                                // existing follower logic.
                                EchelonLog("REGROUP_ATTACH bot=" $ Name $ " human=" $ string(RegroupAttach.PlayerReplicationInfo.Name));
                                FollowStart(RegroupAttach);
                                return;
                            }
                        }
                    }
                    // Hold within 100u of the leader; if farther, follow to
                    // converge. The leader itself holds in place (its own
                    // distance is 0) and falls to the P10 Camp hold band.
                    RegroupHoldLeader = SquadLeader;
                    if (!bIsGroupLeader && RegroupHoldLeader != None && RegroupHoldLeader.Pawn != None
                        && VSizeSq(RegroupHoldLeader.Pawn.Location - Pawn.Location) > REGROUP_HOLD_DIST_SQ)
                    {
                        EchelonLog("REGROUP_HOLD bot=" $ Name $ " toLeader");
                        FollowStart(RegroupHoldLeader);
                        return;
                    }
                }
                // Leader holding in place: same terminal hold as P10 (Camp).
                if (bIsGroupLeader)
                {
                    ExecuteCampState();
                    return;
                }
            }
        }

        // Priority 5: SYG Enforcement -- only forces the objective path when
        // actually outside the zone (>1000u); otherwise falls through so
        // Medic/Combat can still run.
        if (mut.bObjectiveActive)
        {
            // AUDIT_3B Step 2 (SAFE EARLY FIX): ammo gate. If the equipped
            // weapon has no ammo, do not roll ObjectiveGoal and do not
            // GotoState('DoObjective') -- fall through to combat/medic.
            bHasAmmo = (Pawn != None) && (Pawn.Weapon != None)
                && (KFWeapon(Pawn.Weapon).GetTotalAmmoAmount(0) > 0);
            if (ObjectiveGoal == none)
            {
                if (bHasAmmo)
                {
                    ObjectiveGoal = mut.GetBotObjective(self);
                    ObjectiveBailUntil = 0.0;
                    AuditGoalLog("GOAL_SET", "PickMove");
                }
            }
            if (ObjectiveGoal != none && bHasAmmo && VSizeSq(ObjectiveGoal.Location - Pawn.Location) > SYG_DISTANCE_SQ
                && WorldInfo.TimeSeconds >= ObjectiveBailUntil)
            {
                GotoState('DoObjective');
                return;
            }
        }

        // Priority 6: Squad Medic (Triage) -- 2.0s throttle shared by both the
        // dart (ranged) and syringe (melee-range) triage scans.
        if (KPawn != none && WorldInfo.TimeSeconds - LastTriageTime >= TRIAGE_INTERVAL)
        {
            LastTriageTime = WorldInfo.TimeSeconds;
            if (CheckMedicGunHeal())
            {
                GotoState('HealRanged');
                return;
            }
            if (CheckShouldHealMate())
            {
                GotoState('HealOther');
                return;
            }
        }

        // Priority 7: Combat Engagement -- boss-melee targets are already
        // filtered at the source in SetEnemy()/FightEnemy.PickStyle(). Leash:
        // drop and cooldown past 2400u instead of thrashing.
        if (Enemy != none && Enemy.IsAliveAndWell() && !(KFPawn_Monster(Enemy) != none && KFPawn_Monster(Enemy).bIsHeadless))
        {
            if (VSizeSq(Enemy.Location - Pawn.Location) > LEASH_DROP_DIST_SQ)
            {
                Enemy = none;
                LastLeashDropTime = WorldInfo.TimeSeconds;
            }
            else if (LineOfSightTo(Enemy))
            {
                GotoState('FightEnemy');
                return;
            }
            else
            {
                GotoState('Hunting');
                return;
            }
        }

        // Priority 8: Squad Tethering
        if (EvaluateSquadTether()) return;

        // Priority 8.5: Low zed count → force hunting.
        // When few zeds remain map-wide, don't let bots camp or tether
        // passively — actively hunt the last stragglers.
        if (Enemy == none && GlobalZedCount > 0 && GlobalZedCount < HUNT_ZED_THRESHOLD)
        {
            GotoState('Hunting');
            return;
        }

        // Priority 9: Economy -- only reachable once SYG (P5) is satisfied.
        if (KFGRI.bTraderIsOpen && NextShoppingTime < WorldInfo.TimeSeconds && KFGRI.OpenedTrader != none)
        {
            GotoState('GoShopping');
            return;
        }

        // Priority 10: Camp
        ExecuteCampState();
    }

Begin:
    Sleep(0.0);
    PickMove();
    stop;
}

state Roaming
{
    event BeginState(name PreviousStateName)
    {
        local KFWeapon MW;
        AuditStateEntry();
        AbortMove();
        // End:0x44
        if(KPawn != none)
        {
            KPawn.SetSprinting(!bIsGroupLeader);
            // Obs 6 -- During trader rounds, prefer a melee weapon (knife) over
            // the syringe. Bots should roam with a melee weapon ready.
            if(KFGRI != none && KFGRI.bTraderIsOpen && Pawn.Weapon != none && !Pawn.Weapon.bMeleeWeapon)
            {
                    foreach Pawn.InvManager.InventoryActors(Class'KFGame.KFWeapon', MW)
                {
                        if(MW != none && MW.bMeleeWeapon)
                    {
                            Pawn.InvManager.SetCurrentWeapon(MW);
                        break;
                    }
                }
            }
        }
        //return;        
    }

    event EndState(name NextStateName)
    {
        AuditStateExit(NextStateName);
        // End:0x2F
        if(KPawn != none)
        {
            KPawn.SetSprinting(false);
        }
        //return;        
    }

    function PickStyle()
    {
        local KF2Bot GroupLeader;
        // End:0x224
        if((PlayStyle == 0) && KPawn != none)
        {
            GroupLeader = (mut != None) ? mut.GetGroupLeader(GroupID) : None;
            // End:0x221
            if((!bIsGroupLeader) && GroupLeader != none && GroupLeader.Pawn != none)
            {
                // End:0x18C
                if(VSizeSq(GroupLeader.Pawn.Location - Pawn.Location) > 360000.0000000)
                {
                    // End:0x147
                    if(ActorReachable(GroupLeader.Pawn))
                    {
                        MoveToX(GetPointNear(GroupLeader.Pawn, 600.0000000));
                        return;
                    }
                    // End:0x189
                    if(BuildPathToward(GroupLeader.Pawn))
                    {
                        MoveTowardX(MoveTarget);
                        return;
                    }                    
                }
                else
                {
                    // End:0x1D2
                    if(Rand(3) == 0)
                    {
                        MoveToX(GetPointNear(GroupLeader.Pawn, 600.0000000));                        
                    }
                    else
                    {
                        Focus = none;
                        SetFocalPoint(Pawn.Location + (VRand() * 1000.0000000));
                    }
                    return;
                }
            }            
        }
        else
        {
            // End:0x394
            if(FollowingHuman != none)
            {
                // End:0x265
                if(!FollowingHuman.IsAliveAndWell())
                {
                    FollowingHuman = none;                    
                }
                else
                {
                    // End:0x314
                    if(VSizeSq(FollowingHuman.Location - Pawn.Location) > 360000.0000000)
                    {
                        // End:0x2E4
                        if(ActorReachable(FollowingHuman))
                        {
                            MoveToX(GetPointNear(FollowingHuman, 600.0000000));
                            return;
                        }
                        // End:0x311
                        if(BuildPathToward(FollowingHuman))
                        {
                            MoveTowardX(MoveTarget);
                            return;
                        }                        
                    }
                    else
                    {
                        // End:0x345
                        if(Rand(3) == 0)
                        {
                            MoveToX(GetPointNear(FollowingHuman, 600.0000000));                            
                        }
                        else
                        {
                            Focus = none;
                            SetFocalPoint(Pawn.Location + (VRand() * 1000.0000000));
                        }
                        return;
                    }
                }
            }
        }
        // End:0x3EB
        if((RandGoal == none) && !BuildRandomPath())
        {
            J0x3B4:

            MoveToX(Pawn.Location + (VRand() * 300.0000000));
            return;
        }
        // End:0x41C
        if(ActorReachable(RandGoal))
        {
            MoveTowardX(RandGoal);
            RandGoal = none;
            return;
        }
        // End:0x442
        if(!BuildPathToward(RandGoal))
        {
            RandGoal = none;
            // [Loop Continue]
            goto J0x3B4;
        }
        MoveTowardX(MoveTarget);
        //return;        
    }

    function FinishedMove()
    {
        PickCombatStyle();
        //return;        
    }

    function EnemyChanged()
    {
        PickCombatStyle();
        //return;        
    }

    function DonateMoney(Pawn Other)
    {
        // End:0x30
        if(ActorReachable(Other))
        {
            DonateHuman = Other;
            GotoState('DonatingMoney');
        }
        //return;        
    }
Begin:

    // End:0x2D
    if(Pawn.Physics == 2)
    {
        WaitForLanding();
    }
    PickStyle();
    stop;
Camp:


    Sleep(0.5000000 + FRand());
    PickCombatStyle();
    stop;        
}

state Camp
{
    event BeginState(name PreviousStateName)
    {
        AuditStateEntry();
        AbortMove();
        if (KPawn != none)
        {
            KPawn.SetSprinting(false);
        }
    }

    event EndState(name NextStateName)
    {
        AuditStateExit(NextStateName);
    }

    function EnemyChanged()
    {
        PickCombatStyle();
    }
Begin:
    if (Pawn.Physics == 2)
    {
        WaitForLanding();
    }
    Focus = none;
    SetFocalPoint(Pawn.Location + (VRand() * 1000.0000000));
    Sleep(1.0000000 + FRand());
    PickCombatStyle();
    stop;
}

state DoObjective extends Roaming
{
    function FinishObjective()
    {
        global.FinishObjective();
        PickCombatStyle();
        //return;        
    }

    function PickStyle()
    {
        local bool IterGoalReachable;

        IterGoalReachable = false;

        // P5 SYG Death March fix (Loophole 7): assess the approach corridor
        // for hazards before committing to another leg of the path.
        if (CheckObjectiveHazard())
        {
            return;
        }

        if(ObjectiveGoal == none)
        {
            ObjectiveGoal = mut.GetBotObjective(self);
            ObjectiveBailUntil = 0.0;
            AuditGoalLog("GOAL_SET", "DoObjectivePick");
        }

        // GC Null-Check: ObjectiveGoal can still be None here (objective
        // cleared between the check above and now) -- don't dereference
        // .Location below.
        if (ObjectiveGoal == none)
        {
            PickCombatStyle();
            return;
        }

        // AUDIT_3B Step 4b: my own path-fail blacklist (owner-only, 8s) --
        // never re-path to a node I blacklisted; combat until it expires.
        if (mut != None && mut.IsNodeBlocked(self, ObjectiveGoal))
        {
            PickCombatStyle();
            return;
        }

        if(VSizeSq(ObjectiveGoal.Location - Pawn.Location) > 90000.0000000)
        {
            if(ActorReachable(ObjectiveGoal))
            {
                IterGoalReachable = true;
                MoveTowardX(ObjectiveGoal);
                return;
            }
            if(BuildPathToward(ObjectiveGoal))
            {
                IterGoalReachable = true;
                MoveTowardX(MoveTarget);
                return;
            }            
        }
        else
        {
            Focus = none;
            SetFocalPoint(Pawn.Location + (VRand() * 1000.0000000));
            return;
        }
        // AUDIT finding #3: goal is far but BOTH reachable checks failed ->
        // the objective is geometrically unreachable (locked door / other
        // floor). Bail out to combat instead of death-marching on
        // BuildRandomPath; P5 + FollowCheckExit skip DoObjective during the
        // cooldown, so the bot follows the leader and re-evaluates after.
        if (!IterGoalReachable
            && VSizeSq(ObjectiveGoal.Location - Pawn.Location) > 90000.0000000)
        {
            if (WorldInfo.TimeSeconds < ObjectiveBailUntil)
            {
                PickCombatStyle();
                return;
            }
            ObjectiveBailUntil = WorldInfo.TimeSeconds + OBJ_BAIL_COOLDOWN;
            // AUDIT_3B Step 4b: record the failed nav node for ME only
            // (owner-only, 8s expiry, <=2 per episode, >=2s apart).
            if (mut != None && ObjectiveGoal != none
                && WorldInfo.TimeSeconds - LastNodeBlockTime >= 2.0
                && NodeBlockCount < 2)
            {
                mut.AddNodeBlock(self, ObjectiveGoal);
                LastNodeBlockTime = WorldInfo.TimeSeconds;
                NodeBlockCount++;
                EchelonLog("NODE_BLOCK bot=" $ Name $ " node=(" $ string(FFloor(ObjectiveGoal.Location.X / 100.0)) $ "," $ string(FFloor(ObjectiveGoal.Location.Y / 100.0)) $ "," $ string(FFloor(ObjectiveGoal.Location.Z / 100.0)) $ ") reason=pathfail ttl=8s");
            }
            EchelonLog("DoObjective: objective unreachable, bailing to combat (slot=" $ string(FollowSlotIndex) $ ")");
            PickCombatStyle();
            return;
        }
        if((RandGoal == none) && !BuildRandomPath())
        {
            J0x148:

            MoveToX(Pawn.Location + (VRand() * 300.0000000));
            return;
        }
        if(ActorReachable(RandGoal))
        {
            MoveTowardX(RandGoal);
            RandGoal = none;
            return;
        }
        if(!BuildPathToward(RandGoal))
        {
            RandGoal = none;
            goto J0x148;
        }
        MoveTowardX(MoveTarget);
        //return;        
    }
    stop;    
}

state FightEnemy
{
    event BeginState(name PreviousStateName)
    {
        AuditStateEntry();
        AbortMove();
        SetTimer(0.2000000, true);
        Focus = Enemy;
        Timer();
        //return;        
    }

    event EndState(name NextStateName)
    {
        AuditStateExit(NextStateName);
        SetTimer(0.0000000, false);
        ClearTimer('FinishedMove');
        // End:0x6D
        if(Pawn != none)
        {
            Pawn.ShouldCrouch(false);
            Pawn.StopFiring();
        }
        //return;        
    }

    // Fire trajectory validation and weapon reequip poll: each tick,
    // validate the line of fire and check for a better-loaded weapon.
    event Timer()
    {
        if(Enemy == none)
        {
            return;
        }
        if(!Enemy.IsAliveAndWell() && !PickNextEnemy())
        {
            if(Pawn != none)
            {
                Pawn.StopFiring();
            }
            Enemy = none;
            AbortMove();
            CheckWeaponReequip();
            FinishedMove();
            return;
        }
        // A zed with its head blown off dies within seconds; stop wasting
        // ammo on it and acquire a live target instead.
        if((Enemy != none) && (KFPawn_Monster(Enemy) != none) && KFPawn_Monster(Enemy).bIsHeadless)
        {
            if(Pawn != none)
            {
                Pawn.StopFiring();
            }
            Enemy = none;
            AbortMove();
            CheckWeaponReequip();
            FinishedMove();
            return;
        }
        if(SyncLineFocus())
        {
            return;
        }
        CheckWeaponReequip();
        EnemyEncounterTime = WorldInfo.TimeSeconds;
        Focus = Enemy;
        if(!HasOwnFireLine(Enemy))
        {
            Pawn.StopFiring();
            if((BotRank == GRUNT) && (SquadLeader != none) && (SquadLeader.CurrentFormation == 'LineFormation'))
            {
                SquadLeader.NotifyBlockedShooter(self);
            }
            return;
        }
        FireWeaponAt(Enemy);
    }

    function NotifyKilled(Controller Killer, Controller Killed, Pawn KilledPawn, Class<DamageType> damageTyp)
    {
        // End:0x3F
        if(KFPawn_MonsterBoss(KilledPawn) != none)
        {
            Enemy = none;
            bBossKillVictory = true;
            GotoState('VictoryDance');
            return;
        }
        // End:0x12A
        if(Enemy == KilledPawn)
        {
            // End:0x104
            if(!PickNextEnemy())
            {
                Enemy = none;
                AbortMove();
                // End:0xF7
                if((((Killer == self) && NextVictoryDance < WorldInfo.TimeSeconds) && Rand(3) == 0) && mut.ShouldDoVictoryDance())
                {
                    GotoState('VictoryDance');
                    return;
                }
                FinishedMove();                
            }
            else
            {
                Focus = Enemy;
                Target = Enemy;
            }
        }
        //return;        
    }

    function FinishedMove()
    {
        Pawn.ShouldCrouch(false);
        PickCombatStyle();
        //return;        
    }

    function PickStyle()
    {
        local bool bMelee;
        local KF2Bot GroupLeader;

            // Grunts use the event-driven combat style router (strafe,
            // crouch, or melee charge) instead of the legacy funnel.
            if (BotRank == GRUNT) { GruntPickCombatStyle(); return; }

        // End:0xF8
        if(mut.bObjectiveActive)
        {
            if(ObjectiveGoal == none)
            {
                ObjectiveGoal = mut.GetBotObjective(self);
                AuditGoalLog("GOAL_SET", "PickCombatStyle");
            }
            // GC Null-Check: GetBotObjective() can still return None (objective
            // cleared / ValidPoints emptied between the check above and here) --
            // guard before dereferencing .Location.
            if(ObjectiveGoal != none && VSizeSq(ObjectiveGoal.Location - Pawn.Location) > 640000.0000000)
            {
                if(ActorReachable(ObjectiveGoal))
                {
                    MoveTowardX(ObjectiveGoal);
                    return;
                }
                if(BuildPathToward(ObjectiveGoal))
                {
                    MoveTowardX(MoveTarget);
                    return;
                }
            }
        }
        // End:0x213
        GroupLeader = (mut != None) ? mut.GetGroupLeader(GroupID) : None;
        if((!bIsGroupLeader) && GroupLeader != none && GroupLeader.Pawn != none && VSizeSq(GroupLeader.Pawn.Location - Pawn.Location) > 2250000.0000000)
        {
            // End:0x210
            if(BuildPathToward(GroupLeader.Pawn))
            {
                MoveTowardX(MoveTarget, Enemy);
                return;
            }            
        }
        else
        {
            // End:0x2A3
            if((FollowingHuman != none) && VSizeSq(FollowingHuman.Location - Pawn.Location) > 2250000.0000000)
            {
                // End:0x2A3
                if(BuildPathToward(FollowingHuman))
                {
                    MoveTowardX(MoveTarget, Enemy);
                    return;
                }
            }
        }
        bMelee = IsMeleeOnly();

        // Out of effective range: close the distance before engaging.
        if(bOutOfEffectiveRange && !bMelee)
        {
            CloseToEffectiveRange();
            return;
        }

        // Boss-Melee Guard (Loophole 1) -- primary fix point: an ammo-depleted
        // mid-fight weapon switch (FireWeaponAt() -> SwitchToBestWeapon() ->
        // melee fallback) surfaces HERE, since SetEnemy() only gates at initial
        // acquisition and isn't re-invoked when ammo runs dry later in the same
        // engagement. Re-checked every time PickStyle() runs (state re-entry),
        // so this closes the loop within one FinishedMove() re-evaluation cycle.
        if (bMelee && Enemy.Health > BOSS_HEALTH_THRESHOLD)
        {
            Enemy = none;
            PickCombatStyle();
            return;
        }
        if((((KPawn != none) || !bMelee) && !bMelee || (Vector(Enemy.Rotation) Dot (Enemy.Location - Pawn.Location)) < 0.0000000) && VSizeSq(Enemy.Location - Pawn.Location) < ((Enemy.Health > 500) ? 250000.0000000 : 14400.0000000))
        {
            PickRetreatMove();            
        }
        else
        {
            // End:0x541
            if(bMelee)
            {
                // Obs 5 -- Melee bots must actively swing, not just path toward
                // the enemy. Fire the melee weapon when within attack range.
                if(Pawn.Weapon != none && VSizeSq(Enemy.Location - Pawn.Location) < 40000.0)
                {
                    Pawn.Weapon.StartFire(0);
                }
                // End:0x482
                if(ActorReachable(Enemy))
                {
                    MoveTowardX(Enemy);                    
                }
                else
                {
                    // End:0x4B8
                    if(BuildPathToward(Enemy))
                    {
                        MoveTowardX(MoveTarget, Enemy);                        
                    }
                    else
                    {
                        MoveToX(((Normal(Enemy.Location - Pawn.Location) * 150.0000000) + Pawn.Location) + (VRand() * 200.0000000), Enemy);
                    }
                }                
            }
            else
            {
                // End:0x58B
                if(Rand(2) == 0)
                {
                    MoveToX(Pawn.Location + (VRand() * 300.0000000), Enemy);                    
                }
                else
                {
                    Pawn.ShouldCrouch(Rand(2) == 0);
                    SetTimer(0.5000000 + (FRand() * 1.5000000), false, 'FinishedMove');
                }
            }
        }
        //return;        
    }

    event bool NotifyBump(Actor Other, Vector HitNormal)
    {
        global.NotifyBump(Other, HitNormal);
        // End:0xF6
        if((Other == Enemy) && MoveTarget == Enemy)
        {
            // End:0xC3
            if((Vector(Enemy.Rotation) Dot (Enemy.Location - Pawn.Location)) < 0.0000000)
            {
                FinishedMove();                
            }
            else
            {
                MoveTarget = none;
                AbortMove();
                SetTimer(0.2000000 + (FRand() * 0.7500000), false, 'FinishedMove');
            }
        }
        return false;
        //return ReturnValue;        
    }

Begin:

    // End:0x2D
    if(Pawn.Physics == 2)
    {
        WaitForLanding();
    }
    PickStyle();
    stop;                    
}

state TacticalRetreat
{
    event BeginState(name PreviousStateName)
    {
        AuditStateEntry();
        AbortMove();
        bIsRetreating = true;
        if (KPawn != none)
        {
            KPawn.SetSprinting(true);
        }
        SetTimer(ZED_COUNT_INTERVAL, true, 'CheckRetreatStatus');
    }

    event EndState(name NextStateName)
    {
        AuditStateExit(NextStateName);
        ClearTimer('CheckRetreatStatus');
        bIsRetreating = false;
        if (KPawn != none)
        {
            KPawn.SetSprinting(false);
        }
    }

    function CheckRetreatStatus()
    {
        if (Pawn == none || Pawn.Health <= 0)
        {
            return;
        }

        // Hysteresis: only stand down once the crowd has genuinely thinned
        // (< RETREAT_ZED_CLEAR_COUNT), not merely dropped below the entry
        // trigger -- avoids flickering in and out of TacticalRetreat.
        if (CountNearbyZeds(RETREAT_ZED_RADIUS) < RETREAT_ZED_CLEAR_COUNT && !HeavyZedWithin(RETREAT_HEAVY_RADIUS))
        {
            bIsRetreating = false;
            PickCombatStyle();
        }
    }

    function FinishedMove()
    {
        // Latent retreat step landed -- keep falling back in bursts while
        // still in danger. CheckRetreatStatus() decides when to stand down.
        if (bIsRetreating)
        {
            PickRetreatMove();
        }
    }

    function EnemyChanged()
    {
        // Deliberately ignored -- P4 overrides P7: a newly spotted Zed must
        // not interrupt an active retreat.
    }
Begin:
    if (Pawn.Physics == 2)
    {
        WaitForLanding();
    }
    PickRetreatMove();
    stop;
}

state BreakLose
{
    ignores CheckGrabbed;

    event BeginState(name PreviousStateName)
    {
        AuditStateEntry();
        AbortMove();
        BreakFreeAttempts = 0;
        GrabStartTime = WorldInfo.TimeSeconds;
        NextEscapeAttempt = 0.0;
        bGrappleFailsafeTriggered = false;
        SetTimer(0.1500000, true);
        Focus = KPawn.InteractionPawn;

        // Buddy rescue: notify the SL to dispatch the two nearest grunts
        // to the grab location.
        if (BotRank == GRUNT && SquadLeader != none)
        {
            SquadLeader.OnGruntGrabbed(self);
        }

        // Confirms the state itself is actually being entered. If this
        // never prints while a bot is visibly grabbed, the bug is in
        // CheckGrabbed/special-move detection upstream, not in the escape
        // logic below - useful to know before chasing the wrong half of
        // the bug in a live horde.
        if((mut != none) && mut.bDebugGrapple)
        {
            mut.DebugMessage(GetHumanReadableName() $ " grabbed - attempting to break free.");
        }
        //return;        
    }

    event EndState(name NextStateName)
    {
        AuditStateExit(NextStateName);
        SetTimer(0.0000000, false);
        // End:0x39
        if(Pawn != none)
        {
            Pawn.StopFiring();
        }
        // Re-sync the overwatch phase after breaking free from a grab.
        OnBreakLoseComplete();
        // Only reports success when we're leaving BreakLose because the
        // grab special move itself actually ended while the bot is still
        // alive - not because the bot died mid-grab, or something else
        // force-switched states out from under us.
        if((((mut != none) && mut.bDebugGrapple) && Pawn != none) && (Pawn.IsAliveAndWell() && ((KPawn == none) || !KPawn.IsDoingSpecialMove(31))))
        {
            mut.DebugMessage(GetHumanReadableName() $ " broke free after " $ string(BreakFreeAttempts) $ " attempt(s), " $ string(int(WorldInfo.TimeSeconds - GrabStartTime)) $ "s.");
        }
        //return;        
    }

    function Timer()
    {
        local int NearbyZeds;

        // End:0x86
        if((((KPawn != none) && KPawn.Health > 0) && KPawn.IsDoingSpecialMove(31)) && KPawn.InteractionPawn != none)
        {
            Focus = KPawn.InteractionPawn;

            // Throttled escape attempt: the mash input (TryBreakFree) and
            // its debug log used to fire on every 0.15s Timer tick, which
            // is what was causing the stutter/log flooding - several
            // grabbed bots at once turned into a Timer-tick-rate stream of
            // StartFire() calls and log lines. The state's own Timer still
            // ticks every 0.15s (needed to keep Focus current and to
            // evaluate the failsafe below promptly), but the actual
            // attempt + log now only fire once every 1.5s.
            if(WorldInfo.TimeSeconds >= NextEscapeAttempt)
            {
                NextEscapeAttempt = WorldInfo.TimeSeconds + 1.5000000;
                ++BreakFreeAttempts;
                TryBreakFree();
                if((mut != none) && mut.bDebugGrapple)
                {
                    mut.DebugMessage(GetHumanReadableName() $ " struggling free (attempt " $ string(BreakFreeAttempts) $ ")");
                }
            }

            // Escape failsafe: if the bot has been held for longer than
            // FailsafeActivationDelay, force the grab to end rather than
            // leaving it to keep mashing indefinitely. Restricted to
            // MaxZedsForFailsafe or fewer Zeds nearby so this can't be used
            // to shrug off a grab in the middle of a genuinely dangerous
            // crowd - it's meant to catch the "stuck on nothing" case, not
            // to make grabs harmless.
            if(((mut != none) && !bGrappleFailsafeTriggered) && (WorldInfo.TimeSeconds - GrabStartTime) >= mut.FailsafeActivationDelay)
            {
                NearbyZeds = CountNearbyZeds(600.0000000);
                if(NearbyZeds <= mut.MaxZedsForFailsafe)
                {
                    bGrappleFailsafeTriggered = true;
                    ForceBreakGrapple();
                }
            }
        }
        else
        {
            PickCombatStyle();
        }
        //return;        
    }
    stop;    
}

state Hunting
{
    event BeginState(name PreviousStateName)
    {
        AuditStateEntry();
        AbortMove();
        // End:0x39
        if(KPawn != none)
        {
            KPawn.SetSprinting(true);
        }
        SetTimer(0.2500000, true);
        //return;        
    }

    event EndState(name NextStateName)
    {
        AuditStateExit(NextStateName);
        SetTimer(0.0000000, false);
        // End:0x3A
        if(KPawn != none)
        {
            KPawn.SetSprinting(false);
        }
        //return;        
    }

    function PickStyle()
    {
        local KF2Bot GroupLeader;
        // End:0xDC
        GroupLeader = (mut != None) ? mut.GetGroupLeader(GroupID) : None;
        if((!bIsGroupLeader) && GroupLeader != none && GroupLeader.Pawn != none && VSizeSq(GroupLeader.Pawn.Location - Pawn.Location) > 810000.0000000)
        {
            Enemy = none;            
        }
        else
        {
            // End:0x142
            if((FollowingHuman != none) && VSizeSq(FollowingHuman.Location - Pawn.Location) > 810000.0000000)
            {
                Enemy = none;
            }
        }
        // End:0x183
        if((Enemy == none) || !Enemy.IsAliveAndWell())
        {
            PickCombatStyle();
            return;
        }
        // End:0x1B3
        if(!BuildPathToward(Enemy))
        {
            Enemy = none;
            PickCombatStyle();            
        }
        else
        {
            MoveTowardX(MoveTarget, Enemy);
        }
        //return;        
    }

    function FinishedMove()
    {
        PickCombatStyle();
        //return;        
    }

    function EnemyChanged()
    {
        PickCombatStyle();
        //return;        
    }

    function Timer()
    {
        // Actively hunt: scan for the nearest live, visible zed and chase it
        // rather than only reacting when a zed gets close.
        local KFPawn_Monster BestZed;
        local float BestDist;
        BestZed = None;
        BestDist = 999999.0;
        foreach WorldInfo.AllPawns(class'KFPawn_Monster', BestZed, Pawn.Location, HUNT_SCAN_RADIUS)
        {
            if (!BestZed.IsAliveAndWell())
            {
                continue;
            }
            if (BestZed.GetTeamNum() == GetTeamNum())
            {
                continue;
            }
            if (!FastTrace(BestZed.Location, Pawn.Location))
            {
                continue;
            }
            if (VSizeSq(BestZed.Location - Pawn.Location) < BestDist)
            {
                BestDist = VSizeSq(BestZed.Location - Pawn.Location);
            }
        }
        if (BestZed != None)
        {
            SetEnemy(BestZed);
            BuildPathToward(Enemy);
            MoveTowardX(MoveTarget, Enemy);
        }
        else if ((Enemy == none) || !Enemy.IsAliveAndWell())
        {
            PickCombatStyle();
        }
        else if (LineOfSightTo(Enemy))
        {
            PickCombatStyle();
        }
    }
Begin:

    // End:0x2D
    if(Pawn.Physics == 2)
    {
        WaitForLanding();
    }
    PickStyle();
    stop;                    
}

state HealingSelf
{
    ignores FinishedMove;

    event BeginState(name PreviousStateName)
    {
        AuditStateEntry();
        AbortMove();
    }

    event EndState(name NextStateName)
    {
        AuditStateExit(NextStateName);
        ClearTimer('HealFailsafe');
        ClearTimer('VerifyWeapon');
        PendingHeal = none;
        if(Pawn != none)
        {
            Pawn.StopFiring();
            // Weapon restore on EVERY exit path (timeout, order, death,
            // enemy-sight). The 1.5s VerifyWeapon one-shot is a backstop
            // for any exit path that missed the switch.
            if(KFWeap_HealerBase(Pawn.Weapon) != none)
            {
                Pawn.InvManager.SwitchToBestWeapon(true);
            }
            SetTimer(1.5, false, 'VerifyWeapon');
        }
    }

    function TimeOut()
    {
        HealFail();
        PickCombatStyle();
    }

    function HealFailsafe()
    {
        // 8-second failsafe: force-exit to combat if heal never completes
        HealFail();
        PickCombatStyle();
    }
Begin:
    // Bounded landing check (WaitForLanding has no timeout in KF2 SDK)
    if(Pawn.Physics == PHYS_Walking)
    {
        landingDeadline = WorldInfo.TimeSeconds + 2.0;
        while(Pawn.Physics == PHYS_Walking && WorldInfo.TimeSeconds < landingDeadline)
        {
            Sleep(0.1);
        }
    }
    SetTimer(8.0, false, 'HealFailsafe');

    if((KPawn == none) || KPawn.Health <= 0)
    {
        HealFail();
        PickCombatStyle();
        stop;
    }

    // Shared predicate: gate and state must agree on ammo threshold
    if(!CanAffordHeal(0))
    {
        HealFail();
        PickCombatStyle();
        stop;
    }

    // Equip syringe (bounded: 3s max, re-request every 0.1s)
    equipDeadline = WorldInfo.TimeSeconds + 3.0;
    while(Pawn.Weapon != MedicGun && WorldInfo.TimeSeconds < equipDeadline)
    {
        Pawn.InvManager.SetCurrentWeapon(MedicGun);
        Sleep(0.1);
    }
    if(Pawn.Weapon != MedicGun)
    {
        HealFail();
        PickCombatStyle();
        stop;
    }

    Focus = Pawn;

    // Apply self-heal
    MedicGun.AmmoCount[0] -= 100;
    MedicGun.PerformReload();
    MedicGun.PlayAnimation('Heal_Self');
    KPawn.HealthToRegen += 20;
    Sleep(FMin(FMax(MedicGun.MySkelMesh.GetAnimInterruptTime('Heal_Self'), 0.1), 3.0));

    if(KPawn.Health + KPawn.HealthToRegen > KPawn.HealthMax)
    {
        KPawn.HealthToRegen = KPawn.HealthMax - KPawn.Health;
    }
    KPawn.SetTimer(KPawn.HealthRegenRate, true, 'GiveHealthOverTime');
    KPawn.PlayHeal(class'KFDT_Healing');

    HealSuccess();
    PickCombatStyle();
    stop;
}
state HealOther
{
    ignores FinishedMove;

    event BeginState(name PreviousStateName)
    {
        AuditStateEntry();
        AbortMove();
    }

    event EndState(name NextStateName)
    {
        AuditStateExit(NextStateName);
        ClearTimer('HealFailsafe');
        ClearTimer('VerifyWeapon');
        PendingHeal = none;
        if(Pawn != none)
        {
            Pawn.StopFiring();
            if(KFWeap_HealerBase(Pawn.Weapon) != none)
            {
                Pawn.InvManager.SwitchToBestWeapon(true);
            }
            SetTimer(1.5, false, 'VerifyWeapon');
        }
    }

    function TimeOut()
    {
        HealFail();
        PickCombatStyle();
    }

    function HealFailsafe()
    {
        // 8-second failsafe: force-exit to combat if heal never completes
        HealFail();
        PickCombatStyle();
    }
Begin:
    // Bounded landing check (WaitForLanding has no timeout in KF2 SDK)
    if(Pawn.Physics == PHYS_Walking)
    {
        landingDeadline = WorldInfo.TimeSeconds + 2.0;
        while(Pawn.Physics == PHYS_Walking && WorldInfo.TimeSeconds < landingDeadline)
        {
            Sleep(0.1);
        }
    }
    SetTimer(8.0, false, 'HealFailsafe');

    if(PendingHeal == none)
    {
        HealFail();
        PickCombatStyle();
        stop;
    }

    // APPROACH FIRST (bot walks with combat weapon, not the syringe)
    while(true)
    {
        if((PendingHeal == none) || !PendingHeal.IsAliveAndWell() || PendingHeal.Health >= (HEAL_MIN_NEED_PCT / 100.0) * PendingHeal.HealthMax)
        {
            HealFail();
            PickCombatStyle();
            stop;
        }
        if((VSize(PendingHeal.Location - Pawn.Location) <= 200.0) && LineOfSightTo(PendingHeal))
        {
            break;
        }
        MoveTowardX(PendingHeal);
        Sleep(0.1);
    }

    // EQUIP LAST (bounded: 3s max)
    if(!CanAffordHeal(0))
    {
        HealFail();
        PickCombatStyle();
        stop;
    }
    equipDeadline = WorldInfo.TimeSeconds + 3.0;
    while(Pawn.Weapon != MedicGun && WorldInfo.TimeSeconds < equipDeadline)
    {
        Pawn.InvManager.SetCurrentWeapon(MedicGun);
        Sleep(0.1);
    }
    if(Pawn.Weapon != MedicGun)
    {
        HealFail();
        PickCombatStyle();
        stop;
    }

    AbortMove();
    Pawn.Acceleration = vect(0, 0, 0);
    Focus = PendingHeal;
    Target = PendingHeal;
    FinishRotation();

    // APPLY heal
    MedicGun.AmmoCount[0] -= 100;
    MedicGun.PerformReload();
    MedicGun.PlayAnimation('Heal_Team');
    PendingHeal.HealthToRegen += 20;
    Sleep(FMin(FMax(MedicGun.MySkelMesh.GetAnimInterruptTime('Heal_Team'), 0.1), 3.0));

    if(PendingHeal.Health + PendingHeal.HealthToRegen > PendingHeal.HealthMax)
    {
        PendingHeal.HealthToRegen = PendingHeal.HealthMax - PendingHeal.Health;
    }
    PendingHeal.SetTimer(PendingHeal.HealthRegenRate, true, 'GiveHealthOverTime');
    PendingHeal.PlayHeal(class'KFDT_Healing');

    HealSuccess();
    PickCombatStyle();
    stop;
}

state HealRanged
{
    ignores FinishedMove;

    event BeginState(name PreviousStateName)
    {
        AuditStateEntry();
        AbortMove();
    }

    event EndState(name NextStateName)
    {
        AuditStateExit(NextStateName);
        ClearTimer('HealFailsafe');
        ClearTimer('VerifyWeapon');
        PendingHeal = none;
        if(Pawn != none)
        {
            Pawn.StopFiring();
            if(KFWeap_MedicBase(Pawn.Weapon) != none)
            {
                Pawn.InvManager.SwitchToBestWeapon(true);
            }
            SetTimer(1.5, false, 'VerifyWeapon');
        }
    }

    function TimeOut()
    {
        HealFail();
        PickCombatStyle();
    }

    function HealFailsafe()
    {
        // 8-second failsafe: force-exit to combat if heal never completes
        HealFail();
        PickCombatStyle();
    }
Begin:
    // Bounded landing check (WaitForLanding has no timeout in KF2 SDK)
    if(Pawn.Physics == PHYS_Walking)
    {
        landingDeadline = WorldInfo.TimeSeconds + 2.0;
        while(Pawn.Physics == PHYS_Walking && WorldInfo.TimeSeconds < landingDeadline)
        {
            Sleep(0.1);
        }
    }
    SetTimer(8.0, false, 'HealFailsafe');

    if(PendingHeal == none)
    {
        HealFail();
        PickCombatStyle();
        stop;
    }

    // APPROACH FIRST (bot walks with combat weapon, not the medic gun)
    while(true)
    {
        if((PendingHeal == none) || !PendingHeal.IsAliveAndWell() || PendingHeal.Health >= (HEAL_MIN_NEED_PCT / 100.0) * PendingHeal.HealthMax)
        {
            HealFail();
            PickCombatStyle();
            stop;
        }
        if((VSize(PendingHeal.Location - Pawn.Location) <= 1500.0) && LineOfSightTo(PendingHeal))
        {
            break;
        }
        MoveTowardX(PendingHeal);
        Sleep(0.1);
    }

    // EQUIP LAST (bounded: 3s max)
    if(!CanAffordHeal(1))
    {
        HealFail();
        PickCombatStyle();
        stop;
    }
    equipDeadline = WorldInfo.TimeSeconds + 3.0;
    while(Pawn.Weapon != RangeMedicGun && WorldInfo.TimeSeconds < equipDeadline)
    {
        Pawn.InvManager.SetCurrentWeapon(RangeMedicGun);
        Sleep(0.1);
    }
    if(Pawn.Weapon != RangeMedicGun)
    {
        HealFail();
        PickCombatStyle();
        stop;
    }

    AbortMove();
    Pawn.Acceleration = vect(0, 0, 0);
    Focus = PendingHeal;
    Target = PendingHeal;
    FinishRotation();

    // APPLY dart
    RangeMedicGun.AmmoCount[1] -= 50;
    RangeMedicGun.StartHealRecharge();
    RangeMedicGun.PlayAnimation('Shoot_Dart');
    if(mut != none)
    {
        mut.RegisterRangedHealTarget(PendingHeal);
    }
    PendingHeal.HealthToRegen += RangeMedicGun.default.HealAmount;
    Sleep(FMin(RangeMedicGun.GetFireInterval(1), 3.0));

    if(PendingHeal.Health + PendingHeal.HealthToRegen > PendingHeal.HealthMax)
    {
        PendingHeal.HealthToRegen = PendingHeal.HealthMax - PendingHeal.Health;
    }
    PendingHeal.SetTimer(PendingHeal.HealthRegenRate, true, 'GiveHealthOverTime');
    PendingHeal.PlayHeal(class'KFDT_Healing');

    HealSuccess();
    PickCombatStyle();
    stop;
}
state GrenadeTarget
{
    event BeginState(name PreviousStateName)
    {
        AuditStateEntry();
        AbortMove();
        //return;        
    }

    event EndState(name NextStateName)
    {
        // End:0x2E
        if(Pawn != none)
        {
            Pawn.StopFiring();
        }
        //return;        
    }

    function FinishedMove()
    {
        PickCombatStyle();
        //return;        
    }
Begin:

    // End:0x2D
    if(Pawn.Physics == 2)
    {
        WaitForLanding();
    }
    Focus = Target;
    FinishRotation();
    Pawn.Weapon.StartFire(4);
    Sleep(0.2000000);
    Enemy = Pawn(Target);
    PickRetreatMove();
    stop;                    
}

state GoShopping
{
    event BeginState(name PreviousStateName)
    {
        AuditStateEntry();
        AbortMove();
        if (KPawn != none)
        {
            KPawn.SetSprinting(true);
        }
        SetTimer(0.4000000 + (FRand() * 0.2500000), true);
        TraderRetryCount = 0;
    }

    event EndState(name NextStateName)
    {
        AuditStateExit(NextStateName);
        ClearTimer('DoTrading');
        SetTimer(0.0000000, false);
        // End:0x4E
        if(KPawn != none)
        {
            KPawn.SetSprinting(false);
        }
        //return;        
    }

    function EnemyChanged()
    {
        PickCombatStyle();
        //return;        
    }

    function PickStyle()
    {
        if(KFGRI.OpenedTrader == none)
        {
            PickCombatStyle();
            return;
        }
        if(ActorReachable(KFGRI.OpenedTrader))
        {
            TraderRetryCount = 0;
            MoveToX(KFGRI.OpenedTrader.Location);
            return;
        }
        if(BuildPathToward(KFGRI.OpenedTrader))
        {
            TraderRetryCount = 0;
            MoveTowardX(MoveTarget);            
        }
        else
        {
            AbortMove();
            SetTimer(0.0000000, false);

            // Trader Bodyblock mitigation (Loophole 6): bounded retry with
            // backoff instead of cycling DoTrading forever against a blocked
            // doorway.
            ++TraderRetryCount;
            if (TraderRetryCount >= TRADER_MAX_RETRIES)
            {
                TraderRetryCount = 0;
                NextShoppingTime = WorldInfo.TimeSeconds + TRADER_GIVEUP_COOLDOWN;
                PickCombatStyle();
                return;
            }
            SetTimer((1.0000000 + (FRand() * 2.0000000)) + (float(TraderRetryCount) * 1.0000000), false, 'DoTrading');
        }
        //return;        
    }

    function Timer()
    {
        // End:0x31
        if(KFGRI.OpenedTrader == none)
        {
            PickCombatStyle();            
        }
        else
        {
            // End:0xA4
            if(Pawn.IsOverlapping(KFGRI.OpenedTrader))
            {
                AbortMove();
                SetTimer(0.0000000, false);
                SetTimer(1.0000000 + (FRand() * 2.0000000), false, 'DoTrading');
            }
        }
        //return;        
    }

    function FinishedMove()
    {
        PickCombatStyle();
        //return;        
    }

    function DoTrading()
    {
        // End:0x4C
        if(KFGRI.TraderItems != none)
        {
            ProcessPurchase(KFGRI.TraderItems);
        }
        NextShoppingTime = WorldInfo.TimeSeconds + 60.0000000;
        NextDoshShareTime = WorldInfo.TimeSeconds + 50.0000000;
        // End:0xCD
        if(Rand(3) == 0)
        {
            GotoState('VictoryDance', 'MoveTaunt');            
        }
        else
        {
            PickCombatStyle();
        }
        //return;        
    }

    event bool NotifyBump(Actor Other, Vector HitNormal)
    {
        // End:0x19
        if(IsTimerActive('DoTrading'))
        {
            return false;
        }
        return global.NotifyBump(Other, HitNormal);
        //return ReturnValue;        
    }
Begin:

    // End:0x2D
    if(Pawn.Physics == 2)
    {
        WaitForLanding();
    }
    PickStyle();
    stop;                    
}

state GetItem
{
    event BeginState(name PreviousStateName)
    {
        AuditStateEntry();
        AbortMove();
        KPawn.SetSprinting(Enemy == none);
        // End:0x6D
        if((Enemy != none) && LineOfSightTo(Enemy))
        {
            SetTimer(0.1000000 + (FRand() * 0.1500000), true);
        }
        //return;        
    }

    event EndState(name NextStateName)
    {
        AuditStateExit(NextStateName);
        SetTimer(0.0000000, false);
        // End:0x3A
        if(KPawn != none)
        {
            KPawn.SetSprinting(false);
        }
        // End:0x68
        if(Pawn != none)
        {
            Pawn.StopFiring();
        }
        //return;        
    }

    function Timer()
    {
        // End:0x5D
        if(Enemy != none)
        {
            EnemyEncounterTime = WorldInfo.TimeSeconds;
            Focus = Enemy;
            FireWeaponAt(Enemy);
        }
        //return;        
    }

    function FinishedMove()
    {
        PickCombatStyle();
        //return;        
    }
Begin:

    // End:0x2D
    if(Pawn.Physics == 2)
    {
        WaitForLanding();
    }
    MoveTowardX(LastFactory, Enemy);
    stop;        
}

state DonatingMoney
{
    event BeginState(name PreviousStateName)
    {
        AuditStateEntry();
        // End:0x2E
        if(Pawn != none)
        {
            Pawn.StopFiring();
        }
        //return;        
    }

    event EndState(name NextStateName)
    {
        AuditStateExit(NextStateName);
    }

    function Tick(float Delta)
    {
        global.Tick(Delta);
        // End:0x65
        if(((DonateHuman == none) || DonateHuman.Health <= 0) || Pawn == none)
        {
            PickCombatStyle();
            return;
        }
        // End:0x166
        if(VSizeSq(DonateHuman.Location - Pawn.Location) < 90000.0000000)
        {
            // End:0x100
            if(FastTrace(DonateHuman.Location, Pawn.Location))
            {
                PickCombatStyle();                
            }
            else
            {
                // End:0x137
                if(MoveFlags != 0)
                {
                    AbortMove();
                    GotoState('DonatingMoney', 'MoneyToss');                    
                }
                else
                {
                    Pawn.Acceleration = vect(0.0000000, 0.0000000, 0.0000000);
                }
            }            
        }
        else
        {
            Pawn.Acceleration = DonateHuman.Location - Pawn.Location;
        }
        //return;        
    }

    function FinishedMove()
    {
        PickCombatStyle();
        //return;        
    }

    final function bool DropMoney()
    {
        local Vector TossVel, StartLocation;
        local Rotator R;
        local Vector X, Y, Z;
        local KFDroppedPickup_Cash KFDP;
        local int Amount;

        X = DonateHuman.Location - Pawn.Location;
        TossVel = Normal(X);
        TossVel = (TossVel * ((Pawn.Velocity Dot TossVel) + float(500))) + vect(0.0000000, 0.0000000, 200.0000000);
        X.Z = 0.0000000;
        R = Rotator(X);
        GetAxes(R, X, Y, Z);
        StartLocation = (Pawn.Location + ((0.8000000 * Pawn.CylinderComponent.CollisionRadius) * X)) - ((0.5000000 * Pawn.CylinderComponent.CollisionRadius) * Y);
        Amount = Min(50, int(PlayerReplicationInfo.Score));
        // End:0x205
        if(Amount <= 0)
        {
            return false;
        }
        StartLocation.Z += (Pawn.BaseEyeHeight / float(2));
        KFDP = Spawn(Class'KFGame.KFDroppedPickup_Cash', self,, StartLocation,,, true);
        // End:0x283
        if(KFDP == none)
        {
            return false;
        }
        KFDP.SetPhysics(2);
        KFDP.InventoryClass = Class'KFGameContent.KFInventory_Money';
        KFDP.Velocity = TossVel * 1.6000000;
        KFDP.Instigator = Pawn;
        KFDP.SetPickupMesh(Class'KFGameContent.KFInventory_Money'.default.DroppedPickupMesh);
        KFDP.SetPickupParticles(Class'KFGameContent.KFInventory_Money'.default.DroppedPickupParticles);
        KFDP.CashAmount = Amount;
        KFDP.TosserPRI = PlayerReplicationInfo;
        PlayerReplicationInfo.Score -= float(Amount);
        // End:0x4F3
        if(((Role == ROLE_Authority) && KFGameInfo(WorldInfo.Game) != none) && KFGameInfo(WorldInfo.Game).DialogManager != none)
        {
            KFGameInfo(WorldInfo.Game).DialogManager.PlayDoshTossDialog(KPawn);
        }
        return true;
        //return ReturnValue;        
    }
Begin:

    // End:0x2D
    if(Pawn.Physics == 2)
    {
        WaitForLanding();
    }
    MoveTowardX(DonateHuman, DonateHuman, false);
    stop;
MoneyToss:

    NextDoshShareTime = WorldInfo.TimeSeconds + 5.0000000;
    Sleep(0.4500000);
    DoshDropCounter = byte(Rand(4));
    while(DoshDropCounter < 8)
    {
        Sleep(0.3500000);
        if(!DropMoney())
        {
            break;
        }
        ++DoshDropCounter;
    }

    PickCombatStyle();
    stop;
}

state Dead
{
    ignores StopAdjusting, Tick, CheckGrabbed, PickCombatStyle, SetEnemy, KilledBy, 
            HearNoise, SeeMonster, SeePlayer;

    event BeginState(name PreviousStateName)
    {
        AuditStateEntry();
        SetTimer(1.0000000, true, 'ReassertScoreboardFlags');
    }

    event EndState(name NextStateName)
    {
        AuditStateExit(NextStateName);
        ClearTimer('ReassertScoreboardFlags');
    }

    function ReassertScoreboardFlags()
    {
        local KFPlayerReplicationInfo KFPRI;
        
        if(PlayerReplicationInfo != none)
        {
            KFPRI = KFPlayerReplicationInfo(PlayerReplicationInfo);
            if(KFPRI != none)
            {
                KFPRI.bHasSpawnedIn = true;
            }
        }
    }

Begin:
    stop;    
}

state IsRagdolled
{
    ignores StopAdjusting, Tick, CheckGrabbed, PickCombatStyle, SetEnemy, HearNoise, 
	    SeeMonster, SeePlayer;

    event BeginState(name PreviousStateName)
    {
        AuditStateEntry();
        AbortMove();
        // End:0x38
        if(Pawn != none)
        {
            Pawn.StopFiring();
        }
        //return;        
    }

    event EndState(name NextStateName)
    {
        AuditStateExit(NextStateName);
    }
    stop;    
}

state VictoryDance
{
    ignores HearNoise, SeeMonster, SeePlayer;

    event BeginState(name PreviousStateName)
    {
        AuditStateEntry();
        AbortMove();
        if(Pawn != none)
        {
            Pawn.StopFiring();
        }

        // P1 Terminal Lock: derive the flag from the live match-over condition
        // rather than from WHY VictoryDance was entered -- a boss-kill dance or
        // post-shopping taunt that happens to coincide with the match already
        // being over still correctly locks in as terminal, while normal
        // in-progress dances do not.
        if (mut != none && mut.KF != none && mut.KF.MyKFGRI != none && mut.KF.MyKFGRI.bMatchIsOver)
        {
            bInTerminalState = true;
        }
        //return;        
    }

    event EndState(name NextStateName)
    {
        AuditStateExit(NextStateName);
        bBossKillVictory = false;
        //return;        
    }

    final function PlayDance()
    {
        NextVictoryDance = WorldInfo.TimeSeconds + 20.0000000;
        KPawn.DoSpecialMove(35, true,, mut.PickRandEmote());
        //return;        
    }

    function FinishedMove()
    {
        local Vector V;

        V.X = FRand() - 0.5000000;
        V.Y = FRand() - 0.5000000;
        Focus = none;
        SetFocalPoint(Pawn.Location + (Normal2D(V) * 1000.0000000));
        GotoState('VictoryDance', 'Begin');
        //return;        
    }

    final function Vector GetRandMove()
    {
        local Vector V;
        local int I;

        I = 0;
        while(I < 5)
        {
            V.X = FRand() - 0.5000000;
            V.Y = FRand() - 0.5000000;
            V = Pawn.Location + (Normal2D(V) * ((FRand() * 200.0000000) + 250.0000000));
            if(FastTrace(V, Pawn.Location))
            {
                break;
            }
            ++I;
        }

        return V;
        //return ReturnValue;        
    }

    function EnemyChanged()
    {
        // End:0x19
        if(!bBossKillVictory)
        {
            PickCombatStyle();
        }
        //return;        
    }
MoveTaunt:

    MoveToX(GetRandMove(),, false);
    stop;
Begin:


    // End:0x44
    if(Pawn.Physics == 2)
    {
        WaitForLanding();
    }
    Sleep(0.1000000 + FRand());
    PlayDance();
    DoshDropCounter = 0;
    while(KPawn.IsDoingSpecialMove(35) && ++DoshDropCounter < 250)
    {
        Sleep(0.1000000);
    }
    PickCombatStyle();
    stop;
}
