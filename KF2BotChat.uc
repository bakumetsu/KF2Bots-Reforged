//=============================================================================
// KF2BotChat
//
// Makes idle bots occasionally "chat" in Say/TeamSay using a configurable
// list of preset sentences, and inserts itself into the BroadcastHandler
// chain (passing everything through to whatever handler was active before
// it) so normal chat keeps working exactly as before.
//
// This replaces the original dynamic "word learning" system, which parsed
// every player chat message character-by-character to build a vocabulary
// and periodically saved it to a config file, then composed random
// sentences out of the learned words. That system relied on decompiler-
// mangled, non-standard code and isn't needed for the mod's purpose, so it
// has been removed entirely in favor of a fixed, designer-controlled list
// of lines (PresetSentences) plus a debug chat command that forces an
// immediate bot line on demand.
//=============================================================================
class KF2BotChat extends BroadcastHandler
    config(BotChat)
    hidecategories(Navigation,Movement,Collision);

const CUR_CHAT_CONFIGVER = 2;

// Marks that the default config values below have been written once.
var config int ConfigVer;

// Next handler in the BroadcastHandler chain (whatever handler was active
// before this one inserted itself). All broadcast events are forwarded to
// it so other mods/handlers keep working normally.
var BroadcastHandler NextHandle;

// Master on/off switch for bot chat. Edit in BotChat.ini under
// [KF2Bots.KF2BotChat].
var config string _Separator1;
var() config bool bBotsChat;

// The lines bots will randomly choose from. Add/remove/edit these in
// BotChat.ini - each line becomes its own PresetSentences[n]=" ... " entry.
var config string _Separator2;
var() config array<string> PresetSentences;

// Minimum/maximum seconds between automatic bot chat lines.
var config string _Separator3;
var() config float ChatIntervalMin;
var() config float ChatIntervalMax;

// Chat command (typed as a normal Say/TeamSay message) that immediately
// forces a random bot to say a random preset line. Matched case-insensitively
// against the whole message. Leave blank to disable.
var config string _Separator4;
var() config string DebugTriggerWord;

function PostBeginPlay()
{
    InitConfigDefaults();

    if(!bBotsChat)
    {
        Destroy();
        return;
    }

    NextHandle = WorldInfo.Game.BroadcastHandler;
    WorldInfo.Game.BroadcastHandler = self;

    SetTimer(GetNextChatDelay(), false, 'BotChatterTimer');
}

// The compiler skips config properties listed in defaultproperties ("Import
// failed ... property is config"), so the default values are written here the
// first time this class runs (ConfigVer not yet stored in the ini), then saved.
// After that the ini is the single source of truth and is not overwritten.
final function InitConfigDefaults()
{
    if(ConfigVer == CUR_CHAT_CONFIGVER)
    {
        return;
    }
    ConfigVer = CUR_CHAT_CONFIGVER;

    // Dummy config strings with no code meaning of their own - purely
    // visual section dividers in BotChat.ini, since SaveConfig() strips
    // real "; comment" lines on every save.
    _Separator1 = "--- GENERAL ---";
    _Separator2 = "--- CHAT LINES ---";
    _Separator3 = "--- TIMING ---";
    _Separator4 = "--- DEBUG TRIGGER ---";

    bBotsChat = true;
    ChatIntervalMin = 30.0;
    ChatIntervalMax = 90.0;
    DebugTriggerWord = "!botchat";
    PresetSentences.Length = 0;
    PresetSentences.AddItem("Watch out, more zeds incoming!");
    PresetSentences.AddItem("Nice shot!");
    PresetSentences.AddItem("I'm low on ammo.");
    PresetSentences.AddItem("Heads up, big one coming.");
    PresetSentences.AddItem("Anyone need healing?");
    PresetSentences.AddItem("Let's stick together.");
    PresetSentences.AddItem("That was close...");
    PresetSentences.AddItem("Trader's open, grab your gear.");
    PresetSentences.AddItem("On your six!");
    PresetSentences.AddItem("Reloading!");
    SaveConfig();
}

// Returns a random delay in [ChatIntervalMin, ChatIntervalMax], clamped to
// sane values so a blank/zero config can't spam a timer every tick.
final function float GetNextChatDelay()
{
    local float Lo, Hi;

    Lo = FMax(ChatIntervalMin, 1.0);
    Hi = FMax(ChatIntervalMax, Lo);
    return Lo + (FRand() * (Hi - Lo));
}

function UpdateSentText()
{
    if(NextHandle != none)
    {
        NextHandle.UpdateSentText();
    }
    else
    {
        super.UpdateSentText();
    }
}

// Picks a random configured line. Returns "" if none are configured.
final function string PickPresetSentence()
{
    if(PresetSentences.Length == 0)
    {
        return "";
    }
    return PresetSentences[Rand(PresetSentences.Length)];
}

// Finds a random active bot and has it say a random preset line to everyone.
// Returns true if a line was actually sent.
final function bool DoBotChat()
{
    local KF2Bot B, PickedBot;
    local int NumFound, PickIndex;
    local string S;
    local PlayerController PC;

    if(WorldInfo.Game.NumBots <= 0)
    {
        return false;
    }

    NumFound = 0;
    foreach WorldInfo.AllControllers(Class'KF2Bots.KF2Bot', B)
    {
        NumFound++;
    }
    if(NumFound == 0)
    {
        return false;
    }

    PickIndex = Rand(NumFound);
    foreach WorldInfo.AllControllers(Class'KF2Bots.KF2Bot', B)
    {
        if(PickIndex == 0)
        {
            PickedBot = B;
            break;
        }
        --PickIndex;
    }
    if(PickedBot == none)
    {
        return false;
    }

    S = PickPresetSentence();
    if(S == "")
    {
        return false;
    }

    foreach WorldInfo.AllControllers(Class'Engine.PlayerController', PC)
    {
        PC.TeamMessage(PickedBot.PlayerReplicationInfo, S, 'Say');
    }
    return true;
}

// Periodic timer: bots occasionally chat on their own, then reschedules
// itself. Also safe to call directly (e.g. from an admin mutate command)
// to force one line right now - it will simply reschedule the next
// automatic line from that point.
function BotChatterTimer()
{
    SetTimer(GetNextChatDelay(), false, 'BotChatterTimer');
    DoBotChat();
}

function bool AllowsBroadcast(Actor broadcaster, int InLen)
{
    if(NextHandle != none)
    {
        return NextHandle.AllowsBroadcast(broadcaster, InLen);
    }
    return super.AllowsBroadcast(broadcaster, InLen);
}

function BroadcastText(PlayerReplicationInfo SenderPRI, PlayerController Receiver, coerce string msg, optional name Type)
{
    if(NextHandle != none)
    {
        NextHandle.BroadcastText(SenderPRI, Receiver, msg, Type);
    }
    else
    {
        super.BroadcastText(SenderPRI, Receiver, msg, Type);
    }
}

function BroadcastLocalized(Actor Sender, PlayerController Receiver, Class<LocalMessage> Message, optional int Switch, optional PlayerReplicationInfo RelatedPRI_1, optional PlayerReplicationInfo RelatedPRI_2, optional Object OptionalObject)
{
    if(NextHandle != none)
    {
        NextHandle.BroadcastLocalized(Sender, Receiver, Message, Switch, RelatedPRI_1, RelatedPRI_2, OptionalObject);
    }
    else
    {
        super.BroadcastLocalized(Sender, Receiver, Message, Switch, RelatedPRI_1, RelatedPRI_2, OptionalObject);
    }
}

// Resolves the PlayerController behind a broadcast Sender, whether it was
// passed as the controller itself (BroadcastTeam) or as the sending Pawn/
// Actor (Broadcast). Returns none if it can't be resolved (e.g. a bot, or
// a non-player broadcaster) - callers must handle that.
final function PlayerController ResolveSenderPC(Actor Sender)
{
    local Pawn P;

    if(PlayerController(Sender) != none)
    {
        return PlayerController(Sender);
    }
    P = Pawn(Sender);
    if((P != none) && (PlayerController(P.Controller) != none))
    {
        return PlayerController(P.Controller);
    }
    return none;
}

// Shared by Broadcast()/BroadcastTeam(): if the message is a Say/TeamSay
// that STARTS WITH DebugTriggerWord (case-insensitive), force one bot chat
// line immediately. This is the "!botchat" debug trigger.
//
// Matching is a prefix check rather than exact equality on purpose: exact
// equality silently fails on a trailing space or any extra text after the
// word (e.g. "!botchat " or "!botchat pls"), which is an easy, invisible
// way for this to look "unreliable" when it's actually just not matching.
// The sender also always gets a direct confirmation message, so a tester
// can immediately tell whether the trigger fired and, if not, why - rather
// than a silent no-op that's indistinguishable from the feature not working.
final function CheckDebugTrigger(Actor Sender, coerce string msg, name Type)
{
    local PlayerController SenderPC;

    if(!bBotsChat || DebugTriggerWord == "")
    {
        return;
    }
    if((Type != 'Say') && (Type != 'TeamSay'))
    {
        return;
    }
    if(Left(msg, Len(DebugTriggerWord)) ~= DebugTriggerWord)
    {
        SenderPC = ResolveSenderPC(Sender);
        if(DoBotChat())
        {
            if(SenderPC != none)
            {
                SenderPC.ClientMessage("[BotChat] Trigger received - a bot just chatted.");
            }
        }
        else if(SenderPC != none)
        {
            if(WorldInfo.Game.NumBots <= 0)
            {
                SenderPC.ClientMessage("[BotChat] Trigger received, but there are no active bots.");
            }
            else
            {
                SenderPC.ClientMessage("[BotChat] Trigger received, but no PresetSentences are configured.");
            }
        }
    }
}

function Broadcast(Actor Sender, coerce string msg, optional name Type)
{
    CheckDebugTrigger(Sender, msg, Type);

    if(NextHandle != none)
    {
        NextHandle.Broadcast(Sender, msg, Type);
    }
    else
    {
        super.Broadcast(Sender, msg, Type);
    }
}

function BroadcastTeam(Controller Sender, coerce string msg, optional name Type)
{
    CheckDebugTrigger(Sender, msg, Type);

    if(NextHandle != none)
    {
        NextHandle.BroadcastTeam(Sender, msg, Type);
    }
    else
    {
        super.BroadcastTeam(Sender, msg, Type);
    }
}

event AllowBroadcastLocalized(Actor Sender, Class<LocalMessage> Message, optional int Switch, optional PlayerReplicationInfo RelatedPRI_1, optional PlayerReplicationInfo RelatedPRI_2, optional Object OptionalObject)
{
    if(NextHandle != none)
    {
        NextHandle.AllowBroadcastLocalized(Sender, Message, Switch, RelatedPRI_1, RelatedPRI_2, OptionalObject);
    }
    else
    {
        super.AllowBroadcastLocalized(Sender, Message, Switch, RelatedPRI_1, RelatedPRI_2, OptionalObject);
    }
}

event AllowBroadcastLocalizedTeam(int TeamIndex, Actor Sender, Class<LocalMessage> Message, optional int Switch, optional PlayerReplicationInfo RelatedPRI_1, optional PlayerReplicationInfo RelatedPRI_2, optional Object OptionalObject)
{
    if(NextHandle != none)
    {
        NextHandle.AllowBroadcastLocalizedTeam(TeamIndex, Sender, Message, Switch, RelatedPRI_1, RelatedPRI_2, OptionalObject);
    }
    else
    {
        super.AllowBroadcastLocalizedTeam(TeamIndex, Sender, Message, Switch, RelatedPRI_1, RelatedPRI_2, OptionalObject);
    }
}

defaultproperties
{
    // Config properties (bBotsChat, ChatIntervalMin/Max, DebugTriggerWord,
    // PresetSentences) cannot be imported from this block. Their defaults
    // live in InitConfigDefaults() above.
}
