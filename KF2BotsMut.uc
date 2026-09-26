class KF2BotsMut extends KFMutator
    config(BotsMut)
    hidecategories(Navigation,Movement,Collision);

const CUR_CONFIGVER = 3;

struct FireteamData
{
    var array<KF2Bot>   Members;
    var KF2Bot          Leader;
    var NavigationPoint Anchor;
};

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
var array<KF2Bot>       ActiveBots;
var array<FireteamData> Fireteams;
var int                 NumGroups;

var Controller VIPController;
var Controller AlphaCommander;
var Pawn CachedBossPawn;
var int LastPolledWaveNum;

const MIN_GROUPS                = 2;
const MAX_GROUPS                = 4;
const BOTS_PER_GROUP_TARGET     = 3;
const VIP_ESCORT_MIN_SIZE       = 2;
const GROUP_DISSOLVE_SIZE       = 1;
const VANGUARD_OFFSET           = 2000.0;
const REARGUARD_OFFSET          = 2000.0;
const CHOKEPOINT_LATERAL_OFFSET = 1000.0;
const NAV_SEARCH_RADIUS         = 1500.0;
const MACRO_WAYPOINT_INTERVAL   = 3.0;
const WAVE_POLL_INTERVAL        = 1.0;
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
var() config bool bShowBotLevel;
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
var config string _Separator7;
var() config float HealCylinderRadius;
var() config float HealCylinderHeight;
var() config float HealMinHealthPct;
var() config bool bEnableFastTraceHealing;
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
        bShowBotLevel = false;
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
        bDebugGrapple = false;
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
        // Healing system overhaul
        HealCylinderRadius = 400.0;
        HealCylinderHeight = 300.0;
        HealMinHealthPct = 60.0;
        bEnableFastTraceHealing = true;
        _Separator7 = "--- HEALING SETTINGS ---";
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
    SetTimer(WAVE_POLL_INTERVAL, true, 'PollWaveStart');
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

function RegisterBot(KF2Bot NewBot)
{
    if (NewBot == None) return;
    if (ActiveBots.Find(NewBot) == INDEX_NONE) ActiveBots.AddItem(NewBot);
    NewBot.mut = self;
}

function UnregisterBot(KF2Bot LeavingBot)
{
    local int Idx;
    if (LeavingBot == None) return;
    Idx = ActiveBots.Find(LeavingBot);
    if (Idx != INDEX_NONE) ActiveBots.Remove(Idx, 1);
    HandleFireteamCasualty(LeavingBot);
}

function PollWaveStart()
{
    local KFGameReplicationInfo KFGRI;
    KFGRI = KFGameReplicationInfo(WorldInfo.GRI);
    if (KFGRI == None || !KFGRI.bMatchHasBegun) return;

    if (KFGRI.WaveNum != LastPolledWaveNum)
    {
        LastPolledWaveNum = KFGRI.WaveNum;
        InitializePlatoon();
    }
}

function InitializePlatoon()
{
    local int i, GroupCount, GroupIdx;
    local KF2Bot Bot;

    PruneInvalidBots();
    ShuffleActiveBots();

    if (ActiveBots.Length == 0) return;

    GroupCount = DetermineGroupCount(ActiveBots.Length);
    NumGroups  = GroupCount;

    Fireteams.Length = 0;
    Fireteams.Length = GroupCount;

    for (i = 0; i < ActiveBots.Length; i++)
    {
        Bot = ActiveBots[i];
        if (Bot == None) continue;

        GroupIdx = i % GroupCount;
        Bot.GroupID        = GroupIdx + 1;
        Bot.bIsGroupLeader = false;
        Fireteams[GroupIdx].Members.AddItem(Bot);
    }

    for (GroupIdx = 0; GroupIdx < GroupCount; GroupIdx++)
    {
        if (Fireteams[GroupIdx].Members.Length > 0)
        {
            Fireteams[GroupIdx].Leader = Fireteams[GroupIdx].Members[0];
            Fireteams[GroupIdx].Leader.bIsGroupLeader = true;
        }
    }

    UpdateMacroWaypoints();
    if (!IsTimerActive('UpdateMacroWaypoints'))
        SetTimer(MACRO_WAYPOINT_INTERVAL, true, 'UpdateMacroWaypoints');
}

function ShuffleActiveBots()
{
    local int i, SwapIdx;
    local KF2Bot Temp;
    for (i = ActiveBots.Length - 1; i > 0; i--)
    {
        SwapIdx = Rand(i + 1);
        Temp = ActiveBots[i];
        ActiveBots[i] = ActiveBots[SwapIdx];
        ActiveBots[SwapIdx] = Temp;
    }
}

function PruneInvalidBots()
{
    local int i;
    for (i = ActiveBots.Length - 1; i >= 0; i--)
    {
        if (ActiveBots[i] == None || ActiveBots[i].bDeleteMe
            || ActiveBots[i].Pawn == None || ActiveBots[i].Pawn.Health <= 0)
        {
            ActiveBots.Remove(i, 1);
        }
    }
}

function int DetermineGroupCount(int BotCount)
{
    local int Count;
    Count = BotCount / BOTS_PER_GROUP_TARGET;
    if (Count < MIN_GROUPS) Count = MIN_GROUPS;
    if (Count > MAX_GROUPS) Count = MAX_GROUPS;
    return Count;
}

function UpdateMacroWaypoints()
{
    local int GroupIdx;
    local KF2Bot GroupLeader;
    local KFGameReplicationInfo KFGRI;
    local Pawn BossPawn;
    local Actor NewAnchor;
    local vector ProjectedLoc;
    local Controller VIP;

    PruneInvalidBots();

    if (VIPController != None && (VIPController.Pawn == None || VIPController.Pawn.Health <= 0))
    {
        HandleVIPSuccession();
    }

    if (ActiveBots.Length == 0 || NumGroups <= 0) return;

    KFGRI = KFGameReplicationInfo(WorldInfo.GRI);

    if (KFGRI != None && KFGRI.IsBossWave())
    {
        BossPawn = FindBossPawn();
        if (BossPawn != None)
        {
            for (GroupIdx = 0; GroupIdx < NumGroups; GroupIdx++)
            {
                GroupLeader = Fireteams[GroupIdx].Leader;
                if (GroupLeader == None) continue;
                Fireteams[GroupIdx].Anchor = None;
                GroupLeader.AssignedAnchor = BossPawn;
                PropagateAnchorToFollowers(GroupIdx);
            }
            return;
        }
    }

    VIP = GetVIPController();

    for (GroupIdx = 0; GroupIdx < NumGroups; GroupIdx++)
    {
        GroupLeader = Fireteams[GroupIdx].Leader;
        if (GroupLeader == None) continue;

        switch (GroupIdx)
        {
            case 0: 
                if (VIP != None && VIP.Pawn != None)
                {
                    Fireteams[GroupIdx].Anchor = None;
                    GroupLeader.AssignedAnchor = VIP.Pawn;
                }
                break;
            case 1: 
                if (VIP != None && VIP.Pawn != None)
                {
                    ProjectedLoc = VIP.Pawn.Location + (vector(VIP.Pawn.Rotation) * VANGUARD_OFFSET);
                    NewAnchor = FindNearestNavPoint(ProjectedLoc, NAV_SEARCH_RADIUS);
                    if (NewAnchor != None)
                    {
                        Fireteams[GroupIdx].Anchor = NavigationPoint(NewAnchor);
                        GroupLeader.AssignedAnchor = NewAnchor;
                    }
                }
                break;
            case 2: 
                if (VIP != None && VIP.Pawn != None)
                {
                    ProjectedLoc = VIP.Pawn.Location - (vector(VIP.Pawn.Rotation) * REARGUARD_OFFSET);
                    NewAnchor = FindNearestNavPoint(ProjectedLoc, NAV_SEARCH_RADIUS);
                    if (NewAnchor != None)
                    {
                        Fireteams[GroupIdx].Anchor = NavigationPoint(NewAnchor);
                        GroupLeader.AssignedAnchor = NewAnchor;
                    }
                }
                break;
            case 3: 
                NewAnchor = FindNearestChokepoint(VIP);
                if (NewAnchor != None)
                {
                    Fireteams[GroupIdx].Anchor = NavigationPoint(NewAnchor);
                    GroupLeader.AssignedAnchor = NewAnchor;
                }
                break;
        }
        PropagateAnchorToFollowers(GroupIdx);
    }
}

function PropagateAnchorToFollowers(int GroupIdx)
{
    local int i;
    local KF2Bot Member;

    if (Fireteams[GroupIdx].Leader == None) return;

    for (i = 0; i < Fireteams[GroupIdx].Members.Length; i++)
    {
        Member = Fireteams[GroupIdx].Members[i];
        if (Member != None && !Member.bIsGroupLeader)
        {
            Member.AssignedAnchor = Fireteams[GroupIdx].Leader.AssignedAnchor;
        }
    }
}

function NavigationPoint FindNearestNavPoint(vector ProjectedLoc, float SearchRadius)
{
    local NavigationPoint FoundNav;
    foreach WorldInfo.RadiusNavigationPoints(class'NavigationPoint', FoundNav, ProjectedLoc, SearchRadius)
    {
        return FoundNav; 
    }
    return None;
}

function NavigationPoint FindNearestChokepoint(Controller VIP)
{
    local vector ProjectedLoc, LateralVec;
    local NavigationPoint FoundNav;

    if (VIP == None || VIP.Pawn == None) return None;

    LateralVec = Normal(vector(VIP.Pawn.Rotation) cross vect(0,0,1));
    ProjectedLoc = VIP.Pawn.Location + (LateralVec * CHOKEPOINT_LATERAL_OFFSET);

    foreach WorldInfo.RadiusNavigationPoints(class'NavigationPoint', FoundNav, ProjectedLoc, NAV_SEARCH_RADIUS)
    {
        return FoundNav;
    }
    return None;
}

function Controller GetVIPController()
{
    local Controller C;

    if (VIPController != None && !VIPController.bDeleteMe
        && VIPController.Pawn != None && VIPController.Pawn.Health > 0)
    {
        return VIPController;
    }

    foreach WorldInfo.AllControllers(class'Controller', C)
    {
        if (PlayerController(C) != None && C.Pawn != None && C.Pawn.Health > 0)
        {
            VIPController = C;
            return VIPController;
        }
    }

    VIPController = None;
    return None;
}

function Pawn FindBossPawn()
{
    local Pawn P;
    local Pawn BestBoss;

    if (CachedBossPawn != None && !CachedBossPawn.bDeleteMe && CachedBossPawn.Health > 0)
        return CachedBossPawn;

    foreach WorldInfo.AllPawns(class'Pawn', P)
    {
        if (KFPawn_Monster(P) != None && P.Health > 5000)
        {
            if (BestBoss == None || P.Health > BestBoss.Health)
            {
                BestBoss = P;
            }
        }
    }

    CachedBossPawn = BestBoss;
    return BestBoss;
}

function OnBotKilled(KF2Bot DeadBot)
{
    if (DeadBot == None) return;

    if (DeadBot == VIPController)
    {
        HandleVIPSuccession();
        UpdateMacroWaypoints();
    }

    UnregisterBot(DeadBot);
}

function int ComputeCommandScore(KF2Bot Bot)
{
    if (Bot == None || Bot.PlayerReplicationInfo == None || Bot.Pawn == None)
        return -1;
    return (Bot.PlayerReplicationInfo.Kills * 10) + Bot.Pawn.Health;
}

function KF2Bot FindBestCandidate(array<KF2Bot> Candidates)
{
    local int i;
    local KF2Bot Best;
    Best = None;
    for (i = 0; i < Candidates.Length; i++)
    {
        if (Candidates[i] == None || Candidates[i].Pawn == None || Candidates[i].Pawn.Health <= 0)
            continue;
        if (Best == None || ComputeCommandScore(Candidates[i]) > ComputeCommandScore(Best))
            Best = Candidates[i];
    }
    return Best;
}

function KF2Bot FindExpendableMember(array<KF2Bot> Candidates)
{
    local int i;
    local KF2Bot Worst;
    Worst = None;
    for (i = 0; i < Candidates.Length; i++)
    {
        if (Candidates[i] == None || Candidates[i].bIsGroupLeader)
            continue;
        if (Candidates[i].Pawn == None || Candidates[i].Pawn.Health <= 0)
            continue;
        if (Worst == None || ComputeCommandScore(Candidates[i]) < ComputeCommandScore(Worst))
            Worst = Candidates[i];
    }
    return Worst;
}

function HandleVIPSuccession()
{
    local KF2Bot Best;

    Best = FindBestCandidate(ActiveBots);
    if (Best == None) return; 

    VIPController  = Best;
    AlphaCommander = Best;
    Best.bIsAlphaCommander = true;

    if (Best.bIsGroupLeader)
    {
        DemoteGroupLeader(Best);
    }
}

function HandleFireteamCasualty(KF2Bot DeadBot)
{
    local int GroupIdx, MemberIdx;
    local bool bWasLeader;
    local KF2Bot NewLeader;

    if (DeadBot == None) return;

    GroupIdx = DeadBot.GroupID - 1;
    if (GroupIdx < 0 || GroupIdx >= Fireteams.Length) return;

    bWasLeader = DeadBot.bIsGroupLeader;

    MemberIdx = Fireteams[GroupIdx].Members.Find(DeadBot);
    if (MemberIdx != INDEX_NONE)
    {
        Fireteams[GroupIdx].Members.Remove(MemberIdx, 1);
    }

    if (bWasLeader)
    {
        NewLeader = FindBestCandidate(Fireteams[GroupIdx].Members);
        if (NewLeader != None)
        {
            NewLeader.bIsGroupLeader = true;
            NewLeader.ResetStuckState();
            Fireteams[GroupIdx].Leader = NewLeader;
        }
        else
        {
            Fireteams[GroupIdx].Leader = None;
        }
    }
    ConsolidateFireteams();
}

function DemoteGroupLeader(KF2Bot OldLeader)
{
    local int GroupIdx, i;
    local KF2Bot Candidate, NewLeader;
    NewLeader = None;

    if (OldLeader == None || !OldLeader.bIsGroupLeader) return;

    GroupIdx = OldLeader.GroupID - 1;
    if (GroupIdx < 0 || GroupIdx >= Fireteams.Length) return;

    OldLeader.bIsGroupLeader = false;

    for (i = 0; i < Fireteams[GroupIdx].Members.Length; i++)
    {
        Candidate = Fireteams[GroupIdx].Members[i];
        if (Candidate == None || Candidate == OldLeader) continue;
        if (Candidate.Pawn == None || Candidate.Pawn.Health <= 0) continue;

        if (NewLeader == None || ComputeCommandScore(Candidate) > ComputeCommandScore(NewLeader))
        {
            NewLeader = Candidate;
        }
    }

    if (NewLeader != None)
    {
        NewLeader.bIsGroupLeader = true;
        NewLeader.ResetStuckState();
        Fireteams[GroupIdx].Leader = NewLeader;
    }
    ConsolidateFireteams();
}

function RequestLeaderDemotion(KF2Bot StuckLeader)
{
    DemoteGroupLeader(StuckLeader);
}

function ConsolidateFireteams()
{
    local int GroupIdx;
    if (Fireteams.Length > 0 && Fireteams[0].Members.Length < VIP_ESCORT_MIN_SIZE)
    {
        PullBotFromNearestGroup(0);
    }
    for (GroupIdx = 0; GroupIdx < Fireteams.Length; GroupIdx++)
    {
        if (Fireteams[GroupIdx].Members.Length == GROUP_DISSOLVE_SIZE)
        {
            DissolveGroup(GroupIdx);
        }
    }
}

function PullBotFromNearestGroup(int TargetGroupIdx)
{
    local int SourceGroupIdx, BestSourceIdx;
    local float BestDistSq, DistSq;
    local KF2Bot Puller;
    local vector TargetLoc;

    if (Fireteams[TargetGroupIdx].Leader == None || Fireteams[TargetGroupIdx].Leader.Pawn == None)
        return;

    TargetLoc = Fireteams[TargetGroupIdx].Leader.Pawn.Location;
    BestSourceIdx = INDEX_NONE;
    BestDistSq = 0.0;

    for (SourceGroupIdx = 0; SourceGroupIdx < Fireteams.Length; SourceGroupIdx++)
    {
        if (SourceGroupIdx == TargetGroupIdx) continue;
        if (Fireteams[SourceGroupIdx].Members.Length <= 2) continue;
        if (Fireteams[SourceGroupIdx].Leader == None || Fireteams[SourceGroupIdx].Leader.Pawn == None) continue;

        DistSq = VSizeSq(Fireteams[SourceGroupIdx].Leader.Pawn.Location - TargetLoc);
        if (BestSourceIdx == INDEX_NONE || DistSq < BestDistSq)
        {
            BestSourceIdx = SourceGroupIdx;
            BestDistSq = DistSq;
        }
    }

    if (BestSourceIdx == INDEX_NONE) return;

    Puller = FindExpendableMember(Fireteams[BestSourceIdx].Members);
    if (Puller == None) return;

    ReassignBotToGroup(Puller, TargetGroupIdx);
}

function DissolveGroup(int GroupIdx)
{
    local KF2Bot Remaining;
    local int NearestGroupIdx;

    if (Fireteams[GroupIdx].Members.Length != GROUP_DISSOLVE_SIZE) return;

    Remaining = Fireteams[GroupIdx].Members[0];
    NearestGroupIdx = FindNearestEligibleGroup(GroupIdx, Remaining);

    if (NearestGroupIdx == INDEX_NONE) return; 

    Fireteams[GroupIdx].Members.Remove(0, 1);
    Fireteams[GroupIdx].Leader = None;

    ReassignBotToGroup(Remaining, NearestGroupIdx);
}

function int FindNearestEligibleGroup(int ExcludeGroupIdx, KF2Bot Bot)
{
    local int GroupIdx, BestIdx;
    local float BestDistSq, DistSq;

    if (Bot == None || Bot.Pawn == None) return INDEX_NONE;

    BestIdx = INDEX_NONE;

    for (GroupIdx = 0; GroupIdx < Fireteams.Length; GroupIdx++)
    {
        if (GroupIdx == ExcludeGroupIdx) continue;
        if (Fireteams[GroupIdx].Members.Length < 2) continue;
        if (Fireteams[GroupIdx].Leader == None || Fireteams[GroupIdx].Leader.Pawn == None) continue;

        DistSq = VSizeSq(Fireteams[GroupIdx].Leader.Pawn.Location - Bot.Pawn.Location);
        if (BestIdx == INDEX_NONE || DistSq < BestDistSq)
        {
            BestIdx = GroupIdx;
            BestDistSq = DistSq;
        }
    }
    return BestIdx;
}

function ReassignBotToGroup(KF2Bot Bot, int NewGroupIdx)
{
    local int OldGroupIdx, MemberIdx;

    if (Bot == None) return;

    OldGroupIdx = Bot.GroupID - 1;
    if (OldGroupIdx >= 0 && OldGroupIdx < Fireteams.Length)
    {
        MemberIdx = Fireteams[OldGroupIdx].Members.Find(Bot);
        if (MemberIdx != INDEX_NONE)
        {
            Fireteams[OldGroupIdx].Members.Remove(MemberIdx, 1);
        }
    }

    Bot.bIsGroupLeader = false;
    Bot.GroupID = NewGroupIdx + 1;
    Bot.ResetStuckState();
    Fireteams[NewGroupIdx].Members.AddItem(Bot);

    if (Fireteams[NewGroupIdx].Leader != None)
    {
        Bot.AssignedAnchor = Fireteams[NewGroupIdx].Leader.AssignedAnchor;
    }
}

function KF2Bot GetGroupLeader(int GroupID)
{
    local int GroupIdx;
    GroupIdx = GroupID - 1;
    if (GroupIdx < 0 || GroupIdx >= Fireteams.Length) return None;
    return Fireteams[GroupIdx].Leader;
}

function int GetGroupSize(int GroupID)
{
    local int GroupIdx;
    GroupIdx = GroupID - 1;
    if (GroupIdx < 0 || GroupIdx >= Fireteams.Length) return 0;
    return Fireteams[GroupIdx].Members.Length;
}

function int GetFollowerIndex(KF2Bot Bot)
{
    local int GroupIdx, i, FollowerCount;

    if (Bot == None) return 1;

    GroupIdx = Bot.GroupID - 1;
    if (GroupIdx < 0 || GroupIdx >= Fireteams.Length) return 1;

    FollowerCount = 0;
    for (i = 0; i < Fireteams[GroupIdx].Members.Length; i++)
    {
        if (Fireteams[GroupIdx].Members[i] == Fireteams[GroupIdx].Leader) continue;
        FollowerCount++;
        if (Fireteams[GroupIdx].Members[i] == Bot) return FollowerCount;
    }
    return FollowerCount + 1;
}

// P7 Spotter: called by a group leader's SetEnemy() when it acquires a
// target within SPOT_RADIUS_SQ. Pushes that target to followers who don't
// already have a live Enemy of their own, rather than waiting for each
// follower's independent FastTrace scan to catch up.
function BroadcastSpottedEnemy(int GroupID, Pawn Spotted)
{
    local int GroupIdx, i;
    local KF2Bot Member;

    if (Spotted == None || !Spotted.IsAliveAndWell()) return;

    GroupIdx = GroupID - 1;
    if (GroupIdx < 0 || GroupIdx >= Fireteams.Length) return;

    for (i = 0; i < Fireteams[GroupIdx].Members.Length; i++)
    {
        Member = Fireteams[GroupIdx].Members[i];
        if (Member == None || Member.bIsGroupLeader) continue;
        if (Member.Pawn == None || Member.Pawn.Health <= 0) continue;
        if (Member.Enemy != None && Member.Enemy.IsAliveAndWell()) continue; // already has a target

        Member.SetEnemy(Spotted, true);
    }
}

// Bot self-registration is handled in KF2Bot.PreBeginPlay() via mut.RegisterBot(self).
// The actual bot spawning is done by final function bool AddBot() below.

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

// Randomly picks a fully-voiced character from the master roster
// (KFPlayerReplicationInfo.CharacterArchetypes) and stores it on the bot so
// RestartBot() can apply it via KFPawn.SetCharacterArch() once the pawn
// exists. Every playable character ships with a SoundGroupArch (its voice);
// any entry missing one is skipped. Falls back to index 0 (Mr. Foster) if the
// roster is empty or every entry fails the voice check.
final function InitBotCharacter(KF2Bot Bot)
{
    local byte I, C, lvl;
    local KF2Bot B;
    local KFPlayerReplicationInfo PRI;
    local KFCharacterInfo_Human H;
    local string BotName;

    lvl = byte(BotMinPerkLv + Rand((BotMaxPerkLv - BotMinPerkLv) + 1));
    Bot.CurrentLevel = lvl;
    PRI = KFPlayerReplicationInfo(Bot.PlayerReplicationInfo);

    if((PRI == none) || (PRI.CharacterArchetypes.Length == 0))
    {
        Bot.CharacterArch = none;
    }
    else
    {
        I = byte(Rand(PRI.CharacterArchetypes.Length));
        H = PRI.CharacterArchetypes[I];
        
        C = 0;
        while((H == none || H.SoundGroupArch == none) && C < PRI.CharacterArchetypes.Length)
        {
            I = byte((I + 1) % PRI.CharacterArchetypes.Length);
            H = PRI.CharacterArchetypes[I];
            C++;
        }
        
        if(H == none || H.SoundGroupArch == none)
        {
            I = 0;
            H = PRI.CharacterArchetypes[0];
        }
        
        if(PRI.CharacterArchetypes.Length > 1)
        {
            C = 0;
            while(C < 4)
            {
                B = none;
                foreach WorldInfo.AllControllers(class'KF2Bot', B)
                {
                    if((B != none) && (B != Bot) && (B.CharacterArch == H))
                    {
                        break;
                    }
                    B = none;
                }
                if(B == none)
                {
                    break;
                }
                I = byte((I + 1) % PRI.CharacterArchetypes.Length);
                H = PRI.CharacterArchetypes[I];
                C++;
            }
        }
        Bot.CharacterArch = H;
    }

    BotName = PickCustomBotName();
    if(BotName == "")
    {
        if(Bot.CharacterArch != none)
        {
            BotName = string(Bot.CharacterArch.Name);
        }
        else
        {
            BotName = "Horzine_Bot";
        }
    }
    
    if(bShowBotLevel)
    {
        BotName = ("[Lv" $ string(lvl) $ "] ") $ BotName;
    }
    if(PRI != none)
    {
        PRI.SetPlayerName(BotName);
    }
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
        // Apply the character arch chosen in InitBotCharacter() so the bot
        // gets its own mesh and voice instead of the engine default
        // (Mr. Foster). This MUST run after SetTeam above: SetTeam fires
        // NotifyTeamChanged(), which calls SetCharacterArch(GetCharacterInfo())
        // and would otherwise snap the bot back to Mr. Foster (index 0).
        // SetCharacterArch also wires up SoundGroupArch and VoiceGroupArch,
        // which is what gives each character its voice.
        if((KFPawn(NewPlayer.Pawn) != none) && (NewPlayer.CharacterArch != none))
        {
            KFPawn(NewPlayer.Pawn).SetCharacterArch(NewPlayer.CharacterArch, true);
        }
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
            PMsg(Sender, ("-SetBotsLevel <" $ string(bShowBotLevel)) $ "> = Show [Lv X] prefix on bot names");
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
        else if(Left(MutateString, 11) ~= "SetBotsLevel ")
        {
            bShowBotLevel = bool(Mid(MutateString, 11));
            SaveConfig();
            PMsg(Sender, "Bots show [Lv X] name prefix: " $ string(bShowBotLevel));
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
