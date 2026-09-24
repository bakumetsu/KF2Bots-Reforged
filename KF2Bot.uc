class KF2Bot extends AIController
    hidecategories(Navigation);

struct FRouteDoorBlockade
{
    var KFDoorActor door;
    var NavigationPoint Path;
};

var array<FRouteDoorBlockade> DoorPaths;
var array<NavigationPoint> BotBlockRoutes;
var byte PlayStyle;
var byte SquadID;
var transient byte CallStack;
var byte MoveFlags;
var byte HealingStage;
var byte FailedMoveCount;
var byte DoshDropCounter;
var KF2Bot BotLeader;
var int CurrentLevel;
var Class<KFPerk> Perk;
var Class<KFWeapon> FavoriteWeapon;
var KF2BotsMut mut;
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
    //return;    
}

simulated function Destroyed()
{
    super(Controller).Destroyed();
    --WorldInfo.Game.NumBots;
    mut.FreeSquadID(self);
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
        PlayerReplicationInfo.PlayerName = "Horzine_Bot_" $ Rand(9999);
        
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
        mut.InitBotCharacter(self);
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
    Pawn.PathSearchType = 0;
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

function HearNoise(float Loudness, Actor NoiseMaker, optional name NoiseType)
{
    // End:0x5F
    if((NoiseMaker != none) && NoiseMaker.Instigator != none)
    {
        SetEnemy(NoiseMaker.Instigator);
    }
    //return;    
}

function SeePlayer(Pawn Seen)
{
    SetEnemy(Seen);
    //return;    
}

function SeeMonster(Pawn Seen)
{
    SetEnemy(Seen);
    //return;    
}

event bool NotifyBump(Actor Other, Vector HitNormal)
{
    local Vector Dir;

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
    // End:0x3D
    if((Pawn != none) && Pawn.IsAliveAndWell())
    {
        PickNextEnemy();
    }
    //return;    
}

final function bool PickNextEnemy()
{
    local KFPawn_Monster P;
    local bool bResult;

    bResult = false;
    // End:0x113
    foreach WorldInfo.AllPawns(Class'KFGame.KFPawn_Monster', P, Pawn.Location, 1500.0000000)
    {
        // End:0x112
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
    // End:0xDB
    if(((((Other == none) || Other == Pawn) || Other.SpawnTime == WorldInfo.TimeSeconds) || !Other.IsAliveAndWell()) || (KFPawn_Monster(Other) != none) && KFPawn_Monster(Other).bIsHeadless)
    {
        return false;
    }
    // End:0x27F
    if(Pawn.IsSameTeam(Other))
    {
        // End:0x19A
        if((((((PlayStyle == 1) && KPawn != none) && FollowingHuman == none) && KFPawn_Human(Other) != none) && Other.IsHumanControlled()) && Rand(3) == 0)
        {
            FollowingHuman = Other;
        }
        // End:0x27D
        if(((((Enemy == none) && NextDoshShareTime > WorldInfo.TimeSeconds) && PlayerReplicationInfo.Score > float(800)) && Other.PlayerReplicationInfo != none) && Other.PlayerReplicationInfo.Score < float(500))
        {
            DonateMoney(Other);
        }
        return false;
    }
    EnemyEncounterTime = WorldInfo.TimeSeconds;
    // End:0x2E5
    if((Enemy != none) && (GetEnemyThreat(Enemy)) > (GetEnemyThreat(Other)))
    {
        return false;
    }
    Enemy = Other;
    // End:0x311
    if(!bNoNotify)
    {
        EnemyChanged();
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

function bool FireWeaponAt(Actor inActor)
{
    local KFWeapon W;

    // End:0x24
    if(Pawn.IsFiring())
    {
        return true;
    }
    // End:0x91
    if(((inActor == none) || NeedToTurn(inActor.Location)) || !Pawn.CanAttack(inActor))
    {
        return false;
    }
    Target = inActor;
    W = KFWeapon(Pawn.Weapon);
    // End:0x247
    if(W != none)
    {
        // End:0x161
        if(!W.HasAmmo(0))
        {
            // End:0x13E
            if(!W.HasAnyAmmo())
            {
                SwitchToBestWeapon();                
            }
            else
            {
                W.StartFire(2);
            }
            return false;
        }
        // End:0x1A7
        if(W.bMeleeWeapon)
        {
            W.StartFire(0);            
        }
        else
        {
            // End:0x226
            if((inActor != none) && VSizeSq(inActor.Location - Pawn.Location) < 40000.0000000)
            {
                W.StartFire(3);                
            }
            else
            {
                W.StartFire(0);
            }
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
    if(W.bMeleeWeapon)
    {
        W.StartFire(0);
    }
    else
    {
        W.StartFire(3);
    }
    //return;    
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

function Tick(float Delta)
{
    // End:0x11
    if(Pawn == none)
    {
        return;
    }
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
    //return;    
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

final function bool CheckShouldHealMate()
{
    local KFWeap_HealerBase W;
    local KFPawn_Human P, Best;
    local float Pct, BestPct, DHoriz, DVert;

    if(mut == none)
    {
        return false;
    }
    if((KPawn == none) || !KPawn.IsAliveAndWell())
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
    BestPct = 0.0000000;
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
        if(Pct > mut.HealMinHealthPct)
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
        if((Best == none) || (Pct < BestPct))
        {
            Best = P;
            BestPct = Pct;
        }
    }

    PendingHeal = Best;
    return Best != none;
}

final function bool CheckMedicGunHeal()
{
    local KFPawn_Human P, Best;
    local float Pct, BestPct;

    if(mut == none)
    {
        return false;
    }
    if((KPawn == none) || !KPawn.IsAliveAndWell())
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
    BestPct = 0.0000000;
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
        Pct = (float(P.Health) / float(P.HealthMax)) * 100.0000000;
        if(Pct > mut.HealMinHealthPct)
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
        if((Best == none) || (Pct < BestPct))
        {
            Best = P;
            BestPct = Pct;
        }
    }

    PendingHeal = Best;
    return Best != none;
}

final function bool CheckShouldSelfHeal()
{
    local KFWeap_HealerBase W;
    local float Pct;

    if(mut == none)
    {
        return false;
    }
    if((KPawn == none) || !KPawn.IsAliveAndWell())
    {
        return false;
    }

    Pct = (float(KPawn.Health) / float(KPawn.HealthMax)) * 100.0000000;
    if(Pct > mut.HealMinHealthPct)
    {
        return false;
    }
    if(!TargetLowHealth(KPawn))
    {
        return false;
    }

    MedicGun = none;
    foreach KFInvManager.InventoryActors(Class'KFGame.KFWeap_HealerBase', W)
    {
        if(W.HasAmmo(1))
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
    //return;    
}

function PickCombatStyle()
{
    GotoState('PickNextMove');
    //return;    
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
            GotoState('PickNextMove');
            // End:0x50
            break;
        // End:0xFFFF
        default:
            break;
    }
    //return;    
}

function FinishObjective()
{
    ObjectiveGoal = none;
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

state PickNextMove
{
    function PickCombatStyle()
    {
        local KFWeapon W;

        // End:0x45
        if((Pawn == none) || !Pawn.IsAliveAndWell())
        {
            GotoState('Dead');
            return;
        }
        // End:0x123
        if(KPawn != none)
        {
            // End:0xAE
            if(KPawn.IsDoingSpecialMove(31) && KPawn.InteractionPawn != none)
            {
                GotoState('BreakLose');
                return;
            }
            // End:0xE6
            if(TargetLowHealth(Pawn) && CheckShouldSelfHeal())
            {
                GotoState('HealingSelf');
                return;                
            }
            else
            {
                // End:0x106
                if(CheckMedicGunHeal())
                {
                    GotoState('HealRanged');
                    return;                    
                }
                else
                {
                    // End:0x123
                    if(CheckShouldHealMate())
                    {
                        GotoState('HealOther');
                        return;
                    }
                }
            }
        }
        SwitchToBestWeapon();
        // End:0x169
        if(((KPawn != none) && Rand(4) == 0) && FindCollectable())
        {
            GotoState('GetItem');
            return;
        }
        // End:0x340
        if(((Enemy == none) || !Enemy.IsAliveAndWell()) || (KFPawn_Monster(Enemy) != none) && KFPawn_Monster(Enemy).bIsHeadless)
        {
            W = KFWeapon(Pawn.Weapon);
            // End:0x26B
            if((W != none) && W.CanReload())
            {
                W.StartFire(2);
            }
            Enemy = none;
            // End:0x2FD
            if((KFGRI.bTraderIsOpen && NextShoppingTime < WorldInfo.TimeSeconds) && KFGRI.OpenedTrader != none)
            {
                GotoState('GoShopping');                
            }
            else
            {
                // End:0x330
                if(mut.bObjectiveActive)
                {
                    GotoState('DoObjective');                    
                }
                else
                {
                    GotoState('Roaming');
                }
            }
            return;
        }
        // End:0x40B
        if((KPawn != none) && NextGrenadeTimer < WorldInfo.TimeSeconds)
        {
            NextGrenadeTimer = (WorldInfo.TimeSeconds + 0.5000000) + (FRand() * 3.0000000);
            // End:0x40B
            if(((KFInvManager.GrenadeCount > 0) && Rand(2) == 0) && ShouldNadeEnemies())
            {
                GotoState('GrenadeTarget');
                return;
            }
        }
        // End:0x42D
        if(LineOfSightTo(Enemy))
        {
            GotoState('FightEnemy');            
        }
        else
        {
            // End:0x460
            if(mut.bObjectiveActive)
            {
                GotoState('DoObjective');                
            }
            else
            {
                GotoState('Hunting');
            }
        }
        //return;        
    }
Begin:

    Sleep(0.0000000);
    PickCombatStyle();
    stop;        
}

state Roaming
{
    event BeginState(name PreviousStateName)
    {
        AbortMove();
        // End:0x44
        if(KPawn != none)
        {
            KPawn.SetSprinting(BotLeader != self);
        }
        //return;        
    }

    event EndState(name NextStateName)
    {
        // End:0x2F
        if(KPawn != none)
        {
            KPawn.SetSprinting(false);
        }
        //return;        
    }

    function PickStyle()
    {
        // End:0x224
        if((PlayStyle == 0) && KPawn != none)
        {
            // End:0x54
            if(BotLeader == none)
            {
                mut.SetSquadLeader(self);
            }
            // End:0x221
            if((BotLeader != self) && BotLeader.Pawn != none)
            {
                // End:0x18C
                if(VSizeSq(BotLeader.Pawn.Location - Pawn.Location) > 360000.0000000)
                {
                    // End:0x147
                    if(ActorReachable(BotLeader.Pawn))
                    {
                        MoveToX(GetPointNear(BotLeader.Pawn, 600.0000000));
                        return;
                    }
                    // End:0x189
                    if(BuildPathToward(BotLeader.Pawn))
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
                        MoveToX(GetPointNear(BotLeader.Pawn, 600.0000000));                        
                    }
                    else
                    {
                        Focus = none;
                        SetFocalPoint(Pawn.Location + (VRand() * 1000.0000000));
                        GotoState('Camp');
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
                            GotoState('Camp');
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
        // End:0x39
        if(ObjectiveGoal == none)
        {
            ObjectiveGoal = mut.GetBotObjective(self);
        }
        // End:0xD9
        if(VSizeSq(ObjectiveGoal.Location - Pawn.Location) > 90000.0000000)
        {
            // End:0xA9
            if(ActorReachable(ObjectiveGoal))
            {
                MoveTowardX(ObjectiveGoal);
                return;
            }
            // End:0xD6
            if(BuildPathToward(ObjectiveGoal))
            {
                MoveTowardX(MoveTarget);
                return;
            }            
        }
        else
        {
            Focus = none;
            SetFocalPoint(Pawn.Location + (VRand() * 1000.0000000));
            GotoState('Camp');
            return;
        }
        // End:0x17F
        if((RandGoal == none) && !BuildRandomPath())
        {
            J0x148:

            MoveToX(Pawn.Location + (VRand() * 300.0000000));
            return;
        }
        // End:0x1B0
        if(ActorReachable(RandGoal))
        {
            MoveTowardX(RandGoal);
            RandGoal = none;
            return;
        }
        // End:0x1D6
        if(!BuildPathToward(RandGoal))
        {
            RandGoal = none;
            // [Loop Continue]
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
        AbortMove();
        SetTimer(0.2000000, true);
        Focus = Enemy;
        Timer();
        //return;        
    }

    event EndState(name NextStateName)
    {
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

        // End:0xF8
        if(mut.bObjectiveActive)
        {
            // End:0x5B
            if(ObjectiveGoal == none)
            {
                ObjectiveGoal = mut.GetBotObjective(self);
            }
            // End:0xF8
            if(VSizeSq(ObjectiveGoal.Location - Pawn.Location) > 640000.0000000)
            {
                // End:0xCB
                if(ActorReachable(ObjectiveGoal))
                {
                    MoveTowardX(ObjectiveGoal);
                    return;
                }
                // End:0xF8
                if(BuildPathToward(ObjectiveGoal))
                {
                    MoveTowardX(MoveTarget);
                    return;
                }
            }
        }
        // End:0x213
        if((((((PlayStyle == 0) && KPawn != none) && BotLeader != none) && BotLeader != self) && BotLeader.Pawn != none) && VSizeSq(BotLeader.Pawn.Location - Pawn.Location) > 2250000.0000000)
        {
            // End:0x210
            if(BuildPathToward(BotLeader.Pawn))
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
        bMelee = ((Pawn.Weapon != none) ? Pawn.Weapon.bMeleeWeapon : !Pawn.HasRangedAttack());
        // End:0x44E
        if((((KPawn != none) || !bMelee) && !bMelee || (Vector(Enemy.Rotation) Dot (Enemy.Location - Pawn.Location)) < 0.0000000) && VSizeSq(Enemy.Location - Pawn.Location) < ((Enemy.Health > 500) ? 250000.0000000 : 14400.0000000))
        {
            PickRetreatMove();            
        }
        else
        {
            // End:0x541
            if(bMelee)
            {
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
Begin:

    // End:0x2D
    if(Pawn.Physics == 2)
    {
        WaitForLanding();
    }
    PickStyle();
    stop;                    
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

state BreakLose
{
    ignores CheckGrabbed;

    event BeginState(name PreviousStateName)
    {
        AbortMove();
        BreakFreeAttempts = 0;
        GrabStartTime = WorldInfo.TimeSeconds;
        NextEscapeAttempt = 0.0;
        bGrappleFailsafeTriggered = false;
        SetTimer(0.1500000, true);
        Focus = KPawn.InteractionPawn;

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
        SetTimer(0.0000000, false);
        // End:0x39
        if(Pawn != none)
        {
            Pawn.StopFiring();
        }
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
        // End:0xDC
        if((((((PlayStyle == 0) && KPawn != none) && BotLeader != none) && BotLeader != self) && BotLeader.Pawn != none) && VSizeSq(BotLeader.Pawn.Location - Pawn.Location) > 810000.0000000)
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
        // End:0x52
        if(((Enemy == none) || !Enemy.IsAliveAndWell()) || LineOfSightTo(Enemy))
        {
            PickCombatStyle();
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
}

state HealingSelf
{
    ignores FinishedMove;

    event BeginState(name PreviousStateName)
    {
        AbortMove();
    }

    event EndState(name NextStateName)
    {
        ClearTimer('TimeOut');
        if(Pawn != none)
        {
            Pawn.StopFiring();
        }
    }

    function TimeOut()
    {
        PickCombatStyle();
    }
Begin:

    if(Pawn.Physics == 2)
    {
        WaitForLanding();
    }
    SetTimer(5.0000000, false, 'TimeOut');

    if((KPawn == none) || KPawn.Health <= 0)
    {
        ClearTimer('TimeOut');
        PickCombatStyle();
        stop;
    }

    // Step 1: equip the syringe
    while((MedicGun != none) && Pawn.Weapon != MedicGun)
    {
        Pawn.InvManager.SetCurrentWeapon(MedicGun);
        Sleep(0.1000000);
    }
    if(MedicGun == none)
    {
        ClearTimer('TimeOut');
        PickCombatStyle();
        stop;
    }
    if(KPawn.Health <= 0)
    {
        ClearTimer('TimeOut');
        PickCombatStyle();
        stop;
    }
    ClearTimer('TimeOut');

    Focus = Pawn;

    // Step 2: apply self-heal
    if(MedicGun.AmmoCount[0] >= 100)
    {
        MedicGun.AmmoCount[0] -= 100;
        MedicGun.PerformReload();
        MedicGun.PlayAnimation('Heal_Self');
        KPawn.HealthToRegen += 20;
        Sleep(FMax(MedicGun.MySkelMesh.GetAnimInterruptTime('Heal_Self'), 0.1000000));

        // Step 3: native triggers, on KPawn (not PendingHeal)
        if(KPawn.Health + KPawn.HealthToRegen > KPawn.HealthMax)
        {
            KPawn.HealthToRegen = KPawn.HealthMax - KPawn.Health;
        }
        KPawn.SetTimer(KPawn.HealthRegenRate, true, 'GiveHealthOverTime');
        KPawn.PlayHeal(class'KFDT_Healing');
    }

    // Step 4
    PickCombatStyle();
    stop;
}
state HealOther
{
    ignores FinishedMove;

    event BeginState(name PreviousStateName)
    {
        AbortMove();
    }

    event EndState(name NextStateName)
    {
        ClearTimer('TimeOut');
        if(Pawn != none)
        {
            Pawn.StopFiring();
        }
    }

    function TimeOut()
    {
        PendingHeal = none;
        PickCombatStyle();
    }
Begin:

    if(Pawn.Physics == 2)
    {
        WaitForLanding();
    }
    SetTimer(5.0000000, false, 'TimeOut');

    while((MedicGun != none) && Pawn.Weapon != MedicGun)
    {
        Pawn.InvManager.SetCurrentWeapon(MedicGun);
        Sleep(0.1000000);
    }
    if(MedicGun == none)
    {
        ClearTimer('TimeOut');
        PendingHeal = none;
        PickCombatStyle();
        stop;
    }

    while(true)
    {
        if((PendingHeal == none) || !PendingHeal.IsAliveAndWell() || PendingHeal.Health >= PendingHeal.HealthMax)
        {
            ClearTimer('TimeOut');
            PendingHeal = none;
            PickCombatStyle();
            stop;
        }
        if((VSize(PendingHeal.Location - Pawn.Location) <= 200.0000000) && LineOfSightTo(PendingHeal))
        {
            break;
        }
        MoveTowardX(PendingHeal);
        Sleep(0.1000000);
    }
    ClearTimer('TimeOut');

    AbortMove();
    Pawn.Acceleration = vect(0.0000000, 0.0000000, 0.0000000);
    Focus = PendingHeal;
    Target = PendingHeal;
    FinishRotation();

    if(MedicGun.AmmoCount[0] >= 100)
    {
        MedicGun.AmmoCount[0] -= 100;
        MedicGun.PerformReload();
        MedicGun.PlayAnimation('Heal_Team');
        PendingHeal.HealthToRegen += 20;
        Sleep(FMax(MedicGun.MySkelMesh.GetAnimInterruptTime('Heal_Team'), 0.1000000));

        if(PendingHeal.Health + PendingHeal.HealthToRegen > PendingHeal.HealthMax)
        {
            PendingHeal.HealthToRegen = PendingHeal.HealthMax - PendingHeal.Health;
        }
        PendingHeal.SetTimer(PendingHeal.HealthRegenRate, true, 'GiveHealthOverTime');
        PendingHeal.PlayHeal(class'KFDT_Healing');
    }

    PendingHeal = none;
    PickCombatStyle();
    stop;
}

state HealRanged
{
    ignores FinishedMove;

    event BeginState(name PreviousStateName)
    {
        AbortMove();
    }

    event EndState(name NextStateName)
    {
        ClearTimer('TimeOut');
        if(Pawn != none)
        {
            Pawn.StopFiring();
        }
    }

    function TimeOut()
    {
        PendingHeal = none;
        PickCombatStyle();
    }
Begin:

    if(Pawn.Physics == 2)
    {
        WaitForLanding();
    }
    SetTimer(5.0000000, false, 'TimeOut');

    while((RangeMedicGun != none) && Pawn.Weapon != RangeMedicGun)
    {
        Pawn.InvManager.SetCurrentWeapon(RangeMedicGun);
        Sleep(0.1000000);
    }
    if(RangeMedicGun == none)
    {
        ClearTimer('TimeOut');
        PendingHeal = none;
        PickCombatStyle();
        stop;
    }

    while(true)
    {
        if((PendingHeal == none) || !PendingHeal.IsAliveAndWell() || PendingHeal.Health >= PendingHeal.HealthMax)
        {
            ClearTimer('TimeOut');
            PendingHeal = none;
            PickCombatStyle();
            stop;
        }
        if((VSize(PendingHeal.Location - Pawn.Location) <= 1500.0000000) && LineOfSightTo(PendingHeal))
        {
            break;
        }
        MoveTowardX(PendingHeal);
        Sleep(0.1000000);
    }
    ClearTimer('TimeOut');

    AbortMove();
    Pawn.Acceleration = vect(0.0000000, 0.0000000, 0.0000000);
    Focus = PendingHeal;
    Target = PendingHeal;
    FinishRotation();

    if(RangeMedicGun.AmmoCount[1] >= 50)
    {
        RangeMedicGun.AmmoCount[1] -= 50;
        RangeMedicGun.StartHealRecharge();
        RangeMedicGun.PlayAnimation('Shoot_Dart');
        PendingHeal.HealthToRegen += RangeMedicGun.default.HealAmount;
        Sleep(RangeMedicGun.GetFireInterval(1));

        if(PendingHeal.Health + PendingHeal.HealthToRegen > PendingHeal.HealthMax)
        {
            PendingHeal.HealthToRegen = PendingHeal.HealthMax - PendingHeal.Health;
        }
        PendingHeal.SetTimer(PendingHeal.HealthRegenRate, true, 'GiveHealthOverTime');
        PendingHeal.PlayHeal(class'KFDT_Healing');
    }

    PendingHeal = none;
    PickCombatStyle();
    stop;
}
state GrenadeTarget
{
    event BeginState(name PreviousStateName)
    {
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
        AbortMove();
        KPawn.SetSprinting(true);
        SetTimer(0.4000000 + (FRand() * 0.2500000), true);
        //return;        
    }

    event EndState(name NextStateName)
    {
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
        // End:0x30
        if(KFGRI.OpenedTrader == none)
        {
            PickCombatStyle();
            return;
        }
        // End:0x95
        if(ActorReachable(KFGRI.OpenedTrader))
        {
            MoveToX(KFGRI.OpenedTrader.Location);
            return;
        }
        // End:0xD8
        if(BuildPathToward(KFGRI.OpenedTrader))
        {
            MoveTowardX(MoveTarget);            
        }
        else
        {
            AbortMove();
            SetTimer(0.0000000, false);
            SetTimer(1.0000000 + (FRand() * 2.0000000), false, 'DoTrading');
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
        // End:0x2E
        if(Pawn != none)
        {
            Pawn.StopFiring();
        }
        //return;        
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
        SetTimer(1.0000000, true, 'ReassertScoreboardFlags');
    }

    event EndState(name NextStateName)
    {
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
        AbortMove();
        // End:0x38
        if(Pawn != none)
        {
            Pawn.StopFiring();
        }
        //return;        
    }
    stop;    
}

state VictoryDance
{
    ignores HearNoise, SeeMonster, SeePlayer;

    event BeginState(name PreviousStateName)
    {
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

defaultproperties
{
    SquadID=255
    bIsPlayer=true
    bNotifyApex=true
}
