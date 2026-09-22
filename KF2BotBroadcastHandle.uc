class KF2BotBroadcastHandle extends BroadcastHandler
    config(Game)
    hidecategories(Navigation,Movement,Collision);

var BroadcastHandler MainHandle;
var KF2BotsMut mut;

static final function SpawnBBHandle(KF2BotsMut M)
{
    local KF2BotBroadcastHandle B;

    B = M.Spawn(Class'KF2Bots.KF2BotBroadcastHandle');
    B.mut = M;
    B.MainHandle = M.WorldInfo.Game.BroadcastHandler;
    M.WorldInfo.Game.BroadcastHandler = B;
    //return;    
}

function UpdateSentText()
{
    MainHandle.UpdateSentText();
    //return;    
}

function bool AllowsBroadcast(Actor broadcaster, int InLen)
{
    return MainHandle.AllowsBroadcast(broadcaster, InLen);
    //return ReturnValue;    
}

function Broadcast(Actor Sender, coerce string msg, optional name Type)
{
    MainHandle.Broadcast(Sender, msg, Type);
    //return;    
}

function BroadcastTeam(Controller Sender, coerce string msg, optional name Type)
{
    MainHandle.BroadcastTeam(Sender, msg, Type);
    //return;    
}

event AllowBroadcastLocalized(Actor Sender, Class<LocalMessage> Message, optional int Switch, optional PlayerReplicationInfo RelatedPRI_1, optional PlayerReplicationInfo RelatedPRI_2, optional Object OptionalObject)
{
    // End:0x1B
    if(Message == Class'KFGame.KFLocalMessage_VoiceComms')
    {
    }
    MainHandle.AllowBroadcastLocalized(Sender, Message, Switch, RelatedPRI_1, RelatedPRI_2, OptionalObject);
    //return;    
}

event AllowBroadcastLocalizedTeam(int TeamIndex, Actor Sender, Class<LocalMessage> Message, optional int Switch, optional PlayerReplicationInfo RelatedPRI_1, optional PlayerReplicationInfo RelatedPRI_2, optional Object OptionalObject)
{
    MainHandle.AllowBroadcastLocalizedTeam(TeamIndex, Sender, Message, Switch, RelatedPRI_1, RelatedPRI_2, OptionalObject);
    //return;    
}
