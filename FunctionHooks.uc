//=============================================================================
// FunctionHooks
//
// The original version of this class used a hex-patched (non-standard)
// UnrealScript compiler together with raw memory-pointer manipulation -
// writing directly into a compiled UFunction's bytecode array, exposed in
// the decompiled source as a fabricated ".H48" property - to silently
// redirect native engine functions (KFWeapon.SendToFiringState,
// KFGameInfo.ScoreDamage, KFPawn_Human.TakeDamage, etc.) to the functions
// below. Each hooked function then relied on effectively "becoming" the
// target object at runtime, which is how it could reference members like
// Instigator, FireModeNum, or Health that don't actually exist on Object.
//
// None of that is possible with the official SDK: Function objects don't
// expose a writable bytecode property, and a class can't silently borrow
// another class's members just by being memory-patched onto it. Attempting
// to compile the original file as-is fails outright.
//
// AttachHooks() and every hook function below are therefore stubbed out.
// They keep their original names/signatures so nothing else in the project
// breaks if it still references them, but none of them do anything or
// affect gameplay anymore - the hooking mechanism itself is gone.
//
// If any of this behavior is actually needed going forward, it has to be
// reimplemented through a supported mechanism instead, for example:
//   - Subclassing the real class (e.g. a custom KFWeapon subclass) and
//     assigning it through a supported extension point (a mutator's
//     CheckReplacement(), a weapon-definition swap, etc) rather than
//     patching the base class's bytecode.
//   - Moving the logic directly into a class that legitimately extends the
//     target, such as putting bot-specific behavior in KF2Bot.uc itself.
//   - Using a supported delegate/interface the SDK already exposes for that
//     particular callback, if one exists.
//=============================================================================
class FunctionHooks extends Object
    abstract;

static final function AttachHooks()
{
    // No-op: bytecode hooking is not possible through the official SDK.
    // Left in place (rather than removed) so existing call sites, such as
    // KF2BotsMut.PostBeginPlay, keep compiling without further changes.
}

function SendToFiringState()
{
    // Stub - was hooked onto KFWeapon.SendToFiringState.
}

function PlayWeaponAnimation()
{
    // Stub - was hooked onto KFWeapon.PlayWeaponAnimation.
}

function name GetMeleeAnimName()
{
    // Stub - was hooked onto KFWeapon.GetMeleeAnimName.
    return 'None';
}

final function Bot_MeleeAtk()
{
    // Stub - internal helper used only by the old GetMeleeAnimName hook.
}

function Class<KFProjectile> GetKFProjectileClass()
{
    // Stub - was hooked onto KFWeapon.GetKFProjectileClass.
    return none;
}

final function Class<KFProjectile> GetBotGrenade()
{
    // Stub - internal helper used only by the old GetKFProjectileClass hook.
    return none;
}

function PlaySprintLoop()
{
    // Stub - was hooked onto KFWeapon.PlaySprintLoop.
}

function NotifyTakeHit()
{
    // Stub - was hooked onto KFAfflictionManager.NotifyTakeHit.
}

function PlayPlayerDamageDialog()
{
    // Stub - was hooked onto KFDialogManager.PlayPlayerDamageDialog.
}

function PlayDialogEvent()
{
    // Stub - was hooked onto KFDialogManager.PlayDialogEvent.
}

function StopBreathingDialog()
{
    // Stub - was hooked onto KFDialogManager.StopBreathingDialog.
}

function Class<KFDamageType> GetMedicToxicDmgType()
{
    // Stub - was hooked onto KFDT_Dart_Toxic.GetMedicToxicDmgType.
    return none;
}

function ScoreDamage()
{
    // Stub - was hooked onto KFGameInfo.ScoreDamage.
}

function bool CanSpectate()
{
    // Stub - was hooked onto KFGameInfo.CanSpectate. The return value is
    // never consulted by anything now that the hook itself is disabled.
    return true;
}

function bool HealDamageForce()
{
    // Stub - was hooked onto KFPawn_Human.HealDamageForce.
    return false;
}

function KFH_TakeDamage()
{
    // Stub - was hooked onto KFPawn_Human.TakeDamage.
}

function KFH_UpdateActiveSkillsPath()
{
    // Stub - was hooked onto KFPawn_Human.UpdateActiveSkillsPath.
}

function bool ShouldConcludeSkipTraderVote()
{
    // Stub - was hooked onto KFVoteCollector.ShouldConcludeSkipTraderVote.
    return false;
}

function ConcludeVoteSkipTrader()
{
    // Stub - was hooked onto KFVoteCollector.ConcludeVoteSkipTrader.
}

function PerformReload()
{
    // Stub - was hooked onto KFWeap_HealerBase.PerformReload.
}

function StartFire()
{
    // Stub - was hooked onto KFWeap_HealerBase.StartFire.
}

final function Pawn Bot_GetHealTarget()
{
    // Stub - internal helper used only by the old StartFire hook.
    return none;
}

function StartHealRecharge()
{
    // Stub - was hooked onto KFWeap_MedicBase.StartHealRecharge.
}

function RG_Tick()
{
    // Stub - was hooked onto KFWeap_Rifle_RailGun.Tick.
}

function KFAF_ToggleEffects()
{
    // Stub - was hooked onto KFAffliction_Fire.ToggleEffects.
}
