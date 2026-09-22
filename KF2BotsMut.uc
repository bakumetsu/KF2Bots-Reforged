class KF2BotsMut extends KFMutator
    config(BotsMut)
    hidecategories(Navigation,Movement,Collision);

const CUR_CONFIGVER = 3;

var transient array<AIWeaponInfo> TraderList;
var config int ConfigVer;
var config string _Separator1;
var() config byte NumBots;
var() config byte MinimumBots;
var byte OldWaveNum;
var config string _Separator2;
var() config int BotMinPerkLv;
var() config int BotMaxPerkLv;
var config string _Separator3;
var() config float BotsDamageScale;
var() config float ZedCountScaling;
var KF2BotChat ActiveChat;
var array<byte> SquadSize;
var array<KF2Bot> SquadLeader;
var KFGameInfo_Survival KF;
var Actor PrevObjective;
var array<NavigationPoint> ValidPoints;
var KFMapObjective_DoshHold HoldVolume;
var int MaxEmoteCount;
var float NextVictoryDance;
var bool bNewWave;
var bool bObjectiveActive;
var transient bool bTraderListInit;
var transient bool bChatterInit;
var config string _Separator4;
var() config bool bBotsUnlimitedAmmo;
var() config bool bBotsUnlimitedCash;
var config string _Separator5;
var() config bool bNoZerkerBots;
var() config bool bUseCustomBotNames;
var() config array<string> CustomBotNames;
// Perk class names only (e.g. "KFPerk_Berserker"), NOT full paths - these
// are resolved against the live PerkList at runtime (see ResolvePerkByName),
// because UnrealScript's compiler rejects 'config' on object/class-reference
// array properties outright.
var() config array<string> AllowedPerks;
var() config int MaxBotsPerPerk;
var config string _Separator6;
var() config bool bDebugGrapple;
var() config int MaxZedsForFailsafe;
var() config float FailsafeActivationDelay;
<<<<<<< HEAD
=======
var config string _Separator7;
var() config float HealCylinderRadius;
var() config float HealCylinderHeight;
var() config float HealMinHealthPct;
var() config bool bEnableFastTraceHealing;
>>>>>>> e6078b5 (Healing Behavior added, but only player vs npc worked)
var transient array<string> AvailableBotNames;
var transient array< Class<KFPerk> > PerkPool;
var transient array<int> PerkPoolCounts;

function PostBeginPlay()
{
    local int J;

    Class'KF2Bots.FunctionHooks'.static.AttachHooks();
    // End:0x19D
    if(WorldInfo.Game.BaseMutator == none)
    {
        WorldInfo.Game.BaseMutator = self;        
    }
    else
    {
        WorldInfo.Game.BaseMutator.AddMutator(self);
    }
    // End:0x1F6
    if(bDeleteMe)
    {
        return;
    }
    KF = KFGameInfo_Survival(WorldInfo.Game);
    // End:0x244
    if(ConfigVer != CUR_CONFIGVER)
    {
        // First run (or config reset). The compiler skips config properties
        // listed in defaultproperties ("Import failed ... property is config"),
        // so their intended defaults are applied here instead.
        NumBots = 6;
        BotMaxPerkLv = 25;
        BotsDamageScale = 1.0;
        ZedCountScaling = 0.2;
        bUseCustomBotNames = true;
        CustomBotNames.Length = 0;
        CustomBotNames.AddItem("Alex");
        CustomBotNames.AddItem("Reaper");
        CustomBotNames.AddItem("Ghost");
        CustomBotNames.AddItem("Widow");
        CustomBotNames.AddItem("Havoc");
        CustomBotNames.AddItem("Ranger");
        CustomBotNames.AddItem("Blaze");
        CustomBotNames.AddItem("Cipher");
        // Default to every perk the game itself knows about, capped at 1
        // bot per perk. Pulling names from the live PerkList (rather than
        // typing them out by hand) means this can never drift out of sync
        // with the actual registered perks. Trim AllowedPerks in BotsMut.ini
        // to restrict which perks bots can draw.
        MaxBotsPerPerk = 1;
        AllowedPerks.Length = 0;
        J = 0;
        while(J < Class'KFGame.KFPlayerController'.default.PerkList.Length)
        {
            AllowedPerks.AddItem(string(Class'KFGame.KFPlayerController'.default.PerkList[J].PerkClass.Name));
            ++J;
        }
        // Grapple escape failsafe (see KF2Bot.uc's BreakLose state). Debug
        // logging starts enabled (throttled to once per attempt-cooldown,
        // not per Timer tick) so it can be watched during this playtest -
        // flip to false in BotsMut.ini once confirmed working.
        bDebugGrapple = true;
        MaxZedsForFailsafe = 3;
        FailsafeActivationDelay = 8.0;

        // Dummy config strings with no code meaning of their own - purely
        // visual section dividers in BotsMut.ini, since SaveConfig() strips
        // real "; comment" lines on every save.
        _Separator1 = "--- BOT COUNT & SPAWNING ---";
        _Separator2 = "--- PERK LEVEL RANGE ---";
        _Separator3 = "--- DIFFICULTY & BALANCE ---";
        _Separator4 = "--- CHEATS ---";
        _Separator5 = "--- BOT NAMING & PERK RESTRICTIONS ---";
        _Separator6 = "--- GRAPPLE ESCAPE SETTINGS ---";

<<<<<<< HEAD
=======
        // Healing system overhaul
        HealCylinderRadius = 400.0;
        HealCylinderHeight = 300.0;
        HealMinHealthPct = 60.0;
        bEnableFastTraceHealing = true;
        _Separator7 = "--- HEALING SETTINGS ---";

>>>>>>> e6078b5 (Healing Behavior added, but only player vs npc worked)
        ConfigVer = CUR_CONFIGVER;
        SaveConfig();
    }
    // Spawn the chat handler immediately so the !botchat debug trigger and
    // ambient bot chatter are live from the start of the match. This used to
    // happen lazily inside AddBot() the first time a bot was added, which
    // meant the trigger silently did nothing at all until that first bot
    // existed - a likely cause of it feeling "unreliable" when tested early.
    if(!bChatterInit)
    {
        bChatterInit = true;
        ActiveChat = Spawn(Class'KF2Bots.KF2BotChat');
    }
    //return;    
}

function AddMutator(Mutator M)
{
    // End:0x69
    if(M != self)
    {
        // End:0x56
        if(M.Class == Class)
        {
            M.Destroy();            
        }
        else
        {
            super(Mutator).AddMutator(M);
        }
    }
    //return;    
}

function MatchStarting()
{
    local byte I;

    // End:0x6B
    if(WorldInfo.NetMode == NM_Standalone)
    {
        I = 0;
        while(I < NumBots)
        {
            AddBot();
            ++I;
        }
    }
    else
    {
        SetTimer(1.0000000, true);
    }
    SetTimer(0.1000000, true, 'CheckWave');
    //return;    
}

function Timer()
{
    // End:0x39
    if(KF.MyKFGRI.bMatchIsOver)
    {
        return;
    }
    // End:0xC4
    if(((KF.NumPlayers + KF.NumBots) < NumBots) || KF.NumBots < MinimumBots)
    {
        AddBot();        
    }
    else
    {
        // End:0x172
        if((((KF.NumPlayers + KF.NumBots) > NumBots) && KF.NumBots > 0) && KF.NumBots > MinimumBots)
        {
            RemoveBot();
        }
    }
    //return;    
}

final function SetSquadID(KF2Bot B)
{
    local byte I;

    // End:0x69
    if(KF.NumPlayers > KF.NumBots)
    {
        B.PlayStyle = byte(Rand(2));        
    }
    else
    {
        // End:0x98
        if(Rand(2) == 0)
        {
            B.PlayStyle = byte(Rand(3));
        }
    }
    // End:0xC3
    if(B.PlayStyle != 0)
    {
        return;
    }
    I = 0;
    while(I < SquadSize.Length)
    {
        if(SquadSize[I] < 4)
        {
            ++SquadSize[I];
            break;
        }
        ++I;
    }

    if(I == SquadSize.Length)
    {
        SquadSize.AddItem(byte(Rand(3) + 1));
        SquadLeader.AddItem(B);
    }
    B.SquadID = I;
    SetSquadLeader(B);
    //return;    
}

final function SetSquadLeader(KF2Bot B)
{
    // End:0x64
    if(SquadLeader[B.SquadID] == none)
    {
        SquadLeader[B.SquadID] = B;
    }
    B.BotLeader = SquadLeader[B.SquadID];
    //return;    
}

final function FreeSquadID(KF2Bot B)
{
    // End:0xB9
    if(B.SquadID != 255)
    {
        --SquadSize[B.SquadID];
        // End:0xB9
        if(SquadLeader[B.SquadID] == B)
        {
            SquadLeader[B.SquadID] = none;
        }
    }
    //return;    
}

function CheckWave()
{
    // End:0x4B
    if(bNewWave && KF.GetStateName() == 'TraderOpen')
    {
        bNewWave = false;
        RespawnBots();
    }
    // End:0x231
    if(KF.WaveNum != OldWaveNum)
    {
        OldWaveNum = byte(KF.WaveNum);
        bNewWave = true;
        // End:0x231
        if((ZedCountScaling > 0.0000000) && KF.SpawnManager.WaveTotalAI > 4)
        {
            KF.SpawnManager.WaveTotalAI *= (float(1) + (float(KF.NumBots) * ZedCountScaling));
            KF.MyKFGRI.AIRemaining = KF.SpawnManager.WaveTotalAI;
            KF.MyKFGRI.WaveTotalAICount = KF.SpawnManager.WaveTotalAI;
        }
    }
    // End:0x30A
    if(PrevObjective != KF.MyKFGRI.CurrentObjective)
    {
        PrevObjective = KF.MyKFGRI.CurrentObjective;
        HoldVolume = KFMapObjective_DoshHold(PrevObjective);
        // End:0x2F0
        if(HoldVolume != none)
        {
            SetHoldObjective(HoldVolume);            
        }
        else
        {
            // End:0x307
            if(bObjectiveActive)
            {
                EndObjective();
            }
        }        
    }
    else
    {
        // End:0x35D
        if((bObjectiveActive && HoldVolume != none) && HoldVolume.GetProgress() >= 0.9990000)
        {
            EndObjective();
        }
    }
    //return;    
}

final function SetHoldObjective(Volume V)
{
    local NavigationPoint N;

    // End:0x76
    foreach WorldInfo.AllNavigationPoints(Class'Engine.NavigationPoint', N)
    {
        // End:0x75
        if(V.Encompasses(N))
        {
            ValidPoints.AddItem(N);
        }        
    }    
    bObjectiveActive = ValidPoints.Length != 0;
    //return;    
}

final function EndObjective()
{
    local KF2Bot B;

    bObjectiveActive = false;
    ValidPoints.Length = 0;
    // End:0x6C
    foreach WorldInfo.AllControllers(Class'KF2Bots.KF2Bot', B)
    {
        B.FinishObjective();        
    }    
    //return;    
}

final function NavigationPoint GetBotObjective(KF2Bot B)
{
    // End:0x11
    if(!bObjectiveActive)
    {
        return none;
    }
    return ValidPoints[Rand(ValidPoints.Length)];
    //return ReturnValue;    
}

final function InitTraderList(KFGFxObject_TraderItems L)
{
    local int I;
    local AIWeaponInfo A;

    bTraderListInit = true;
    I = L.SaleItems.Length - 1;
    while(I >= 0)
    {
        if(A == none)
        {
            A = new (none) Class'KF2Bots.AIWeaponInfo';
        }
        if(A.InitInformation(L.SaleItems[I].WeaponDef, L.SaleItems[I].ClassName))
        {
            TraderList.AddItem(A);
            A = none;
        }
        --I;
    }
    //return;    
}

final function AIWeaponInfo FindWeaponByClass(Class<KFWeapon> W)
{
    local AIWeaponInfo A;

    // End:0x4F
    foreach TraderList(A)
    {
        // End:0x4E
        if(A.WeaponClass == W)
        {            
            return A;
        }        
    }    
    return none;
    //return ReturnValue;    
}

final function RespawnBots()
{
    local KF2Bot B;

    // End:0x129
    foreach WorldInfo.AllControllers(Class'KF2Bots.KF2Bot', B)
    {
        B.NextShoppingTime = WorldInfo.TimeSeconds - float(1);
        // End:0xEC
        if((B.Pawn == none) || !B.Pawn.IsAliveAndWell())
        {
            RestartBot(B);
            // End:0x128
            continue;
        }
        B.PlayerReplicationInfo.Score += float(500);        
    }    
    //return;    
}

// Draws a name from CustomBotNames (edit these under [KF2Bots.KF2BotsMut] in
// BotsMut.ini, or toggle with "-SetUseCustomNames") without replacement.
// AvailableBotNames is the "deck" still left to hand out this cycle; once
// it's empty it's refilled from the full CustomBotNames list, so no name
// can repeat until every other name has already been drawn at least once -
// this is what was producing duplicates like four "R1"s before. Returns ""
// if the pool is empty or disabled, so InitBotCharacter() falls back to the
// original look-based name.
final function string PickCustomBotName()
{
    local int Idx;
    local string PickedName;

    if(!bUseCustomBotNames || CustomBotNames.Length == 0)
    {
        return "";
    }
    if(AvailableBotNames.Length == 0)
    {
        AvailableBotNames = CustomBotNames;
    }
    Idx = Rand(AvailableBotNames.Length);
    PickedName = AvailableBotNames[Idx];
    AvailableBotNames.Remove(Idx, 1);
    return PickedName;
}

final function InitBotCharacter(KF2Bot Bot)
{
    local byte I, J, Z, C, lvl;

    local KFCharacterInfo_Human H;
    local KF2Bot B;
    local KFPlayerReplicationInfo PRI, PRIB;
    local string BotName;

    lvl = byte(BotMinPerkLv + Rand((BotMaxPerkLv - BotMinPerkLv) + 1));
    Bot.CurrentLevel = lvl;
    PRI = KFPlayerReplicationInfo(Bot.PlayerReplicationInfo);
    while(true)
    {
        I = byte(Rand(PRI.CharacterArchetypes.Length));
        H = PRI.CharacterArchetypes[I];
        J = byte(Rand(H.BodyVariants.Length));
        Z = byte(Rand(H.BodyVariants[J].SkinVariations.Length));
        if(++C < 4)
        {
            foreach WorldInfo.AllControllers(Class'KF2Bots.KF2Bot', B)
            {
                PRIB = KFPlayerReplicationInfo(B.PlayerReplicationInfo);
                if((PRIB != none) && PRIB != PRI)
                {
                    if(((PRIB.RepCustomizationInfo.CharacterIndex == I) && PRIB.RepCustomizationInfo.BodyMeshIndex == J) && PRIB.RepCustomizationInfo.BodySkinIndex == Z)
                    {
                        break;
                    }
                }
                PRIB = none;
            }
            if(PRIB != none)
            {
                continue;
            }
        }
        // DISABLED: the compiler rejects every write to PRI.RepCustomizationInfo
        // ("Can't assign Const variables"). Reading it (see the duplicate check
        // above) is still fine. Bots simply keep the default appearance the engine
        // gives them. The writes are commented out together because the compiler
        // stops at the first one and would flag the rest on the next build.
        //PRI.RepCustomizationInfo.CharacterIndex = I;
        //C = byte(Rand(H.HeadVariants.Length));
        //PRI.RepCustomizationInfo.HeadMeshIndex = C;
        //PRI.RepCustomizationInfo.HeadSkinIndex = Rand(H.HeadVariants[C].SkinVariations.Length);
        //PRI.RepCustomizationInfo.BodyMeshIndex = J;
        //PRI.RepCustomizationInfo.BodySkinIndex = Z;
        //if(Rand(3) != 0)
        //{
        //    C = byte(Rand(H.CosmeticVariants.Length));
        //    PRI.RepCustomizationInfo.AttachmentMeshIndices[0] = C;
        //    PRI.RepCustomizationInfo.AttachmentSkinIndices[0] = Rand(H.CosmeticVariants[C].SkinVariations.Length);
        //}
        BotName = PickCustomBotName();
        if(BotName == "")
        {
            BotName = Localize((string(H.Name) $ ".BodyMesh") $ string(J), "BodySkin" $ string(Z), "KFCharacterInfo");
        }
        PRI.SetPlayerName((("[Lv" $ string(lvl)) $ "] ") $ BotName);
        break;
    }

    //return;    
}

// Original selection logic (any registered perk, retried until it isn't
// Berserker when bNoZerkerBots is set). Used only when the pool system
// below can't supply a perk: AllowedPerks left empty, or emptied entirely
// because bNoZerkerBots filtered out everything that was in it.
final function Class<KFPerk> PickFallbackPerk()
{
    local Class<KFPerk> P;

    while(true)
    {
        P = Class'KFGame.KFPlayerController'.default.PerkList[Rand(Class'KFGame.KFPlayerController'.default.PerkList.Length)].PerkClass;
        if(!bNoZerkerBots || P != Class'KFGame.KFPerk_Berserker')
        {
            break;
        }
    }
    return P;
}

// Resolves a perk class name (e.g. "KFPerk_Berserker", as stored in the
// config AllowedPerks list) against whatever perks the running game has
// actually registered in KFPlayerController's PerkList. Returns none if
// nothing matches (typo, perk removed/renamed by a game update, etc.) so
// ResetPerkPool() can just skip it rather than storing a bad class ref.
final function Class<KFPerk> ResolvePerkByName(string PerkName)
{
    local int I;

    I = 0;
    while(I < Class'KFGame.KFPlayerController'.default.PerkList.Length)
    {
        if(string(Class'KFGame.KFPlayerController'.default.PerkList[I].PerkClass.Name) ~= PerkName)
        {
            return Class'KFGame.KFPlayerController'.default.PerkList[I].PerkClass;
        }
        ++I;
    }
    return none;
}

// Refills PerkPool (and its parallel draw-count tracker PerkPoolCounts) by
// resolving AllowedPerks' name strings against the live PerkList. Called
// whenever the pool has been drawn down to nothing, either because every
// perk hit MaxBotsPerPerk or on first use.
final function ResetPerkPool()
{
    local int I;
    local Class<KFPerk> P;

    PerkPool.Length = 0;
    PerkPoolCounts.Length = 0;
    I = 0;
    while(I < AllowedPerks.Length)
    {
        P = ResolvePerkByName(AllowedPerks[I]);
        // Keep bNoZerkerBots authoritative even if it was toggled, or
        // AllowedPerks edited, mid-match - never let Berserker back into a
        // freshly-reset pool while it's set. Unresolved names (P == none)
        // are silently skipped.
        if((P != none) && (!bNoZerkerBots || P != Class'KFGame.KFPerk_Berserker'))
        {
            PerkPool.AddItem(P);
            PerkPoolCounts.AddItem(0);
        }
        ++I;
    }
}

// "Gacha" draw-bag for bot perks. AllowedPerks (perk class names, config)
// and MaxBotsPerPerk (config, edit under [KF2Bots.KF2BotsMut] in
// BotsMut.ini) drive it. Draws a random perk out of the current pool; once
// a perk has been drawn MaxBotsPerPerk times it's pulled from the pool
// entirely until the whole pool empties out and refills, at which point
// every perk (including ones already used) is available again - so
// spawning more bots than there are perk slots for just starts a fresh
// cycle instead of running out. MaxBotsPerPerk<=0 disables the cap and
// draws uniformly from AllowedPerks forever.
final function Class<KFPerk> PickBotPerk()
{
    local int Idx;
    local Class<KFPerk> Picked;

    if(AllowedPerks.Length == 0)
    {
        return PickFallbackPerk();
    }
    if(PerkPool.Length == 0)
    {
        ResetPerkPool();
    }
    if(PerkPool.Length == 0)
    {
        // Degenerate config: AllowedPerks is nothing but Berserker while
        // bNoZerkerBots is set, so ResetPerkPool() emptied straight back out.
        return PickFallbackPerk();
    }
    Idx = Rand(PerkPool.Length);
    Picked = PerkPool[Idx];
    if(MaxBotsPerPerk > 0)
    {
        ++PerkPoolCounts[Idx];
        if(PerkPoolCounts[Idx] >= MaxBotsPerPerk)
        {
            PerkPool.Remove(Idx, 1);
            PerkPoolCounts.Remove(Idx, 1);
        }
    }
    return Picked;
}

final function bool AddBot()
{
    local KF2Bot B;
    local KFPlayerReplicationInfo PRI;
    local NavigationPoint PS;

    PS = KF.FindPlayerStart(none, 0);
    // End:0x3E
    if(PS == none)
    {
        return false;
    }
    B = Spawn(Class'KF2Bots.KF2Bot',,, PS.Location);
    // End:0x8F
    if(B == none)
    {
        return false;
    }
    B.Perk = PickBotPerk();

    SetSquadID(B);
    PRI = KFPlayerReplicationInfo(B.PlayerReplicationInfo);
    // End:0x254
    if(PRI != none)
    {
        PRI.CurrentPerkClass = B.Perk;
        PRI.PlayerID = KF.GetNextPlayerID();
    }
    KF.GenericPlayerInitialization(B);
    RestartBot(B);
    // End:0x2F4
    if(PRI != none)
    {
        PRI.Score = float(KF.DifficultyInfo.GetAdjustedStartingCash());
    }
    KF.bOnePlayerAtStart = false;
    KF.ForceLivingPlayerCount(byte(KF.NumPlayers + KF.NumBots));
    return true;
    //return ReturnValue;    
}

final function RemoveBot()
{
    local KF2Bot B, Best;
    local float Score, BestScore;

    BestScore = 0.0000000;
    Best = none;
    // End:0x19E
    foreach WorldInfo.AllControllers(Class'KF2Bots.KF2Bot', B)
    {
        Score = (100.0000000 * FRand()) + (B.PlayerReplicationInfo.Score * 0.2500000);
        // End:0x10F
        if((B.Pawn == none) || !B.Pawn.IsAliveAndWell())
        {
            Score -= 500.0000000;            
        }
        else
        {
            Score += float(B.Pawn.Health);
        }
        // End:0x19D
        if((Best == none) || Score < BestScore)
        {
            BestScore = Score;
            Best = B;
        }        
    }    
    // End:0x1C6
    if(Best != none)
    {
        Best.Destroy();
    }
    //return;    
}

final function RestartBot(KF2Bot NewPlayer, optional NavigationPoint StartSpot)
{
    local int TeamNum, Idx;
    local array<SequenceObject> Events;
    local SeqEvent_PlayerSpawned SpawnedEvent;

    // End:0xD3
    if((KF.bRestartLevel && WorldInfo.NetMode != NM_DedicatedServer) && WorldInfo.NetMode != NM_ListenServer)
    {
        WarnInternal("bRestartLevel && !server, abort from RestartPlayer" @ string(WorldInfo.NetMode));
        return;
    }
    TeamNum = 0;
    // End:0x12B
    if(StartSpot == none)
    {
        StartSpot = KF.FindPlayerStart(NewPlayer, byte(TeamNum));
    }
    // End:0x1F0
    if(StartSpot == none)
    {
        // End:0x1BA
        if(NewPlayer.StartSpot != none)
        {
            StartSpot = NewPlayer.StartSpot;
            WarnInternal("Player start not found, using last start spot");            
        }
        else
        {
            WarnInternal("Player start not found, failed to restart player");
            return;
        }
    }
    // End:0x264
    if(NewPlayer.Pawn == none)
    {
        NewPlayer.Pawn = KF.SpawnDefaultPawnFor(NewPlayer, StartSpot);
    }
    // End:0x2DA
    if(NewPlayer.Pawn == none)
    {
        LogInternal("failed to spawn player at " $ string(StartSpot));
        NewPlayer.GotoState('Dead');        
    }
    else
    {
        NewPlayer.Pawn.SetAnchor(StartSpot);
        NewPlayer.Pawn.LastStartSpot = PlayerStart(StartSpot);
        NewPlayer.Pawn.LastStartTime = WorldInfo.TimeSeconds;
        NewPlayer.Possess(NewPlayer.Pawn, false);
        NewPlayer.Pawn.PlayTeleportEffect(true, true);
        NewPlayer.ClientSetRotation(NewPlayer.Pawn.Rotation, true);
        // End:0x4D7
        if(!WorldInfo.bNoDefaultInventoryForPlayer)
        {
            KF.AddDefaultInventory(NewPlayer.Pawn);
        }
        KF.SetPlayerDefaults(NewPlayer.Pawn);
        // End:0x59E
        if(KFPawn(NewPlayer.Pawn) != none)
        {
            KFPawn(NewPlayer.Pawn).bIgnoreTeamCollision = KF.bDisableTeamCollision;
        }
        // End:0x6F1
        if(WorldInfo.GetGameSequence() != none)
        {
            WorldInfo.GetGameSequence().FindSeqObjectsByClass(Class'Engine.SeqEvent_PlayerSpawned', true, Events);
            Idx = 0;
            while(Idx < Events.Length)
            {
                SpawnedEvent = SeqEvent_PlayerSpawned(Events[Idx]);
                if((SpawnedEvent != none) && SpawnedEvent.CheckActivate(NewPlayer, NewPlayer))
                {
                    SpawnedEvent.SpawnPoint = StartSpot;
                    SpawnedEvent.PopulateLinkedVariableValues();
                }
                Idx++;
            }
        }
        KF.SetTeam(NewPlayer, KF.Teams[0]);
        // End:0x92B
        if(KFPlayerReplicationInfo(NewPlayer.PlayerReplicationInfo) != none)
        {
            KFPlayerReplicationInfo(NewPlayer.PlayerReplicationInfo).PlayerHealthPercent = FloatToByte(float(NewPlayer.Pawn.Health) / float(NewPlayer.Pawn.HealthMax));
            KFPlayerReplicationInfo(NewPlayer.PlayerReplicationInfo).PlayerHealth = NewPlayer.Pawn.Health;
            NewPlayer.PlayerReplicationInfo.Score = float(Max(int(NewPlayer.PlayerReplicationInfo.Score), KF.DifficultyInfo.GetAdjustedRespawnCash()));
        }
    }
    //return;    
}

static final function DebugMessage(string msg)
{
    local PlayerController P;

    LogInternal(msg, 'BotDebug');
    msg = "[BOT]" @ msg;
    // End:0xA5
    foreach Class'Engine.WorldInfo'.static.GetWorldInfo().AllControllers(Class'Engine.PlayerController', P)
    {
        P.ClientMessage(msg);        
    }    
    //return;    
}

final function PMsg(PlayerController Other, string msg)
{
    Other.TeamMessage(Other.PlayerReplicationInfo, msg, 'Event');
    // End:0xED
    if(LocalPlayer(Other.Player) != none)
    {
        LocalPlayer(Other.Player).ViewportClient.ViewportConsole.OutputText(msg);
    }
    //return;    
}

final function DebugAI(PlayerController Sender)
{
    local KF2Bot B, Best;
    local float Score, BestScore;
    local Vector V;

    V = Sender.ViewTarget.Location;
    // End:0x132
    foreach WorldInfo.AllControllers(Class'KF2Bots.KF2Bot', B)
    {
        // End:0x99
        if(B.Pawn == none)
        {
            continue;            
        }
        Score = VSizeSq(B.Pawn.Location - V);
        // End:0x131
        if((Best == none) || Score < BestScore)
        {
            Best = B;
            BestScore = Score;
        }        
    }    
    // End:0x1A9
    if(Best != none)
    {
        Sender.ClientMessage((Best.GetHumanReadableName() $ ": ") $ Best.GetAIInfo());
    }
    //return;    
}

function Mutate(string MutateString, PlayerController Sender)
{
    if(MutateString ~= "AI")
    {
        DebugAI(Sender);
    }
    else if((WorldInfo.NetMode == NM_Standalone) || Sender.PlayerReplicationInfo.bAdmin)
    {
        if(MutateString ~= "Help")
        {
            PMsg(Sender, "KF2Bot commands:");
            PMsg(Sender, ("-SetNumBots <" $ string(NumBots)) $ "> = Set bot count (subtracted by playercount)");
            PMsg(Sender, ("-SetMinBots <" $ string(MinimumBots)) $ "> = Change the minimum bot count");
            PMsg(Sender, ("-SetBotMinLv <" $ string(BotMinPerkLv)) $ "> = Set bots min perk level");
            PMsg(Sender, ("-SetBotMaxLv <" $ string(BotMaxPerkLv)) $ "> = Set bots max perk level");
            PMsg(Sender, ("-SetBotChat <" $ string(Class'KF2Bots.KF2BotChat'.default.bBotsChat)) $ "> = Enable bot chatting");
            PMsg(Sender, "-BotTalk = Make bots say one preset line if enabled");
            PMsg(Sender, ("-SetScaleZedCount <" $ string(ZedCountScaling)) $ "> = Set by how much should bots scale zed count");
            PMsg(Sender, ("-SetNoZerker <" $ string(bNoZerkerBots)) $ "> = New bots should never spawn as berserker");
            PMsg(Sender, ("-SetBotsInfAmmo <" $ string(bBotsUnlimitedAmmo)) $ "> = Bots have unlimited ammo");
            PMsg(Sender, ("-SetBotDamageScale <" $ string(BotsDamageScale)) $ "> = Damage scaling bots should take");
            PMsg(Sender, ("-SetBotInfDosh <" $ string(bBotsUnlimitedCash)) $ "> = Bots have unlimited spending cash");
            PMsg(Sender, ("-SetUseCustomNames <" $ string(bUseCustomBotNames)) $ "> = Use CustomBotNames instead of look-based names");
        }
        else if(Left(MutateString, 11) ~= "SetNumBots ")
        {
            NumBots = byte(int(Mid(MutateString, 11)));
            SaveConfig();
            PMsg(Sender, "Number of bots count changed to: " $ string(NumBots));
        }
        else if(Left(MutateString, 11) ~= "SetMinBots ")
        {
            MinimumBots = byte(int(Mid(MutateString, 11)));
            SaveConfig();
            PMsg(Sender, "Minimum amount of bots set to: " $ string(MinimumBots));
        }
        else if(Left(MutateString, 12) ~= "SetBotMinLv ")
        {
            BotMinPerkLv = int(Mid(MutateString, 12));
            SaveConfig();
            PMsg(Sender, "Set bots minimum perk level to: " $ string(BotMinPerkLv));
        }
        else if(Left(MutateString, 12) ~= "SetBotMaxLv ")
        {
            BotMaxPerkLv = int(Mid(MutateString, 12));
            SaveConfig();
            PMsg(Sender, "Set bots maximum perk level to: " $ string(BotMaxPerkLv));
        }
        else if(Left(MutateString, 17) ~= "SetScaleZedCount ")
        {
            ZedCountScaling = float(Mid(MutateString, 17));
            SaveConfig();
            PMsg(Sender, "Bots scale the number of zeds: X " $ string(ZedCountScaling));
        }
        else if(Left(MutateString, 12) ~= "SetNoZerker ")
        {
            bNoZerkerBots = bool(Mid(MutateString, 12));
            SaveConfig();
            PMsg(Sender, "Bots should never spawn as berserker: " $ string(bNoZerkerBots));
        }
        else if(Left(MutateString, 15) ~= "SetBotsInfAmmo ")
        {
            bBotsUnlimitedAmmo = bool(Mid(MutateString, 15));
            SaveConfig();
            PMsg(Sender, "Bots have infinite ammo: " $ string(bBotsUnlimitedAmmo));
        }
        else if(Left(MutateString, 14) ~= "SetBotInfDosh ")
        {
            bBotsUnlimitedCash = bool(Mid(MutateString, 14));
            SaveConfig();
            PMsg(Sender, "Bots have infinite dosh: " $ string(bBotsUnlimitedCash));
        }
        else if(Left(MutateString, 18) ~= "SetUseCustomNames ")
        {
            bUseCustomBotNames = bool(Mid(MutateString, 18));
            SaveConfig();
            PMsg(Sender, "Bots use custom name pool: " $ string(bUseCustomBotNames));
        }
        else if(Left(MutateString, 18) ~= "SetBotDamageScale ")
        {
            BotsDamageScale = float(Mid(MutateString, 18));
            SaveConfig();
            PMsg(Sender, "Bots new damage scaling: " $ string(BotsDamageScale));
        }
        else if(Left(MutateString, 11) ~= "SetBotChat ")
        {
            if(ActiveChat != none)
            {
                ActiveChat.bBotsChat = bool(Mid(MutateString, 11));
                ActiveChat.SaveConfig();
            }
            else
            {
                Class'KF2Bots.KF2BotChat'.default.bBotsChat = bool(Mid(MutateString, 11));
                Class'KF2Bots.KF2BotChat'.static.StaticSaveConfig();
            }
            PMsg(Sender, "Set bots chatting: " $ string(Class'KF2Bots.KF2BotChat'.default.bBotsChat));
        }
        else if(MutateString ~= "BotTalk")
        {
            if(ActiveChat != none)
            {
                ActiveChat.BotChatterTimer();
            }
            else
            {
                PMsg(Sender, "Bot chat disabled.");
            }
        }
    }
    if(NextMutator != none)
    {
        NextMutator.Mutate(MutateString, Sender);
    }
    //return;
}

function NetDamage(int OriginalDamage, out int Damage, Pawn injured, Controller InstigatedBy, Vector HitLocation, out Vector Momentum, Class<DamageType> DamageType, Actor DamageCauser)
{
    // End:0xF6
    if((Damage > 0) && KF2Bot(injured.Controller) != none)
    {
        // End:0xE2
        if(((InstigatedBy != none) && InstigatedBy != injured.Controller) && injured.GetTeamNum() == InstigatedBy.GetTeamNum())
        {
            Damage = 0;
            Momentum *= 0.2500000;            
        }
        else
        {
            Damage *= BotsDamageScale;
        }
    }
    // End:0x16C
    if(NextMutator != none)
    {
        NextMutator.NetDamage(OriginalDamage, Damage, injured, InstigatedBy, HitLocation, Momentum, DamageType, DamageCauser);
    }
    //return;    
}

final function InitEmotes()
{
    local array<Emote> EA;

    EA = Class'KFGame.KFEmoteList'.static.GetEmoteArray();
    MaxEmoteCount = EA.Length;
    //return;    
}

final function byte PickRandEmote()
{
    // End:0x1D
    if(MaxEmoteCount == -1)
    {
        InitEmotes();
    }
    return byte(Rand(MaxEmoteCount));
    //return ReturnValue;    
}

final function bool ShouldDoVictoryDance()
{
    // End:0x2E
    if(NextVictoryDance > WorldInfo.TimeSeconds)
    {
        return false;
    }
    NextVictoryDance = WorldInfo.TimeSeconds + 5.0000000;
    return true;
    //return ReturnValue;    
}

defaultproperties
{
    // NumBots, BotMaxPerkLv, BotsDamageScale and ZedCountScaling are config
    // properties, which the compiler will not import from this block.
    // Their defaults (6 / 25 / 1.0 / 0.2) are applied in PostBeginPlay().
    MaxEmoteCount=-1
}