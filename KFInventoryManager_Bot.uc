class KFInventoryManager_Bot extends KFInventoryManager
    hidecategories(Navigation);

var byte MaxGrenades;

simulated function bool AddInventory(Inventory NewItem, optional bool bDoNotActivate)
{
    return super(InventoryManager).AddInventory(NewItem, bDoNotActivate);
    //return ReturnValue;    
}

simulated function Inventory CreateInventory(Class<Inventory> NewInventoryItemClass, optional bool bDoNotActivate)
{
    local KFWeapon KFWeap;
    local Class<KFWeapon> KFWeapClass;

    KFWeapClass = Class<KFWeapon>(NewInventoryItemClass);
    // End:0x15F
    if(KFWeapClass != none)
    {
        // End:0x15D
        if(CanCarryWeapon(KFWeapClass))
        {
            // End:0x5F
            if((FindInventoryType(KFWeapClass)) != none)
            {
                return none;
            }
            KFWeap = KFWeapon(super(InventoryManager).CreateInventory(KFWeapClass, bDoNotActivate));
            // End:0x12E
            if(((WorldInfo.TimeSeconds - CreationTime) > float(1)) && (WorldInfo.TimeSeconds - LastCreatedWeaponTime) > float(1))
            {
                PlayGiveInventorySound(ItemPickupSound);
                LastCreatedWeaponTime = WorldInfo.TimeSeconds;
            }
            // End:0x150
            if(KFWeap != none)
            {
                CheckForExcessRemoval(KFWeap);
            }
            return KFWeap;            
        }
        else
        {
            return none;
        }
    }
    return super(InventoryManager).CreateInventory(NewInventoryItemClass, bDoNotActivate);
    //return ReturnValue;    
}

simulated function ShowAllHUDGroups()
{
    //return;    
}

function bool GiveInitialGrenadeCount()
{
    local byte OriginalGrenadeCount;

    OriginalGrenadeCount = GrenadeCount;
    // End:0x44
    if(Class'KF2Bots.KF2BotsMut'.default.bBotsUnlimitedAmmo)
    {
        GrenadeCount = 231;        
    }
    else
    {
        GrenadeCount = 2;
    }
    return int(GrenadeCount) > int(OriginalGrenadeCount);
    //return ReturnValue;    
}

function bool AddGrenades(int AmountToAdd)
{
    // End:0x30
    if(Class'KF2Bots.KF2BotsMut'.default.bBotsUnlimitedAmmo)
    {
        GrenadeCount = 231;
        return false;
    }
    // End:0x96
    if((KFPawn(Instigator) != none) && int(GrenadeCount) < int(MaxGrenades))
    {
        GrenadeCount = byte(Min(int(MaxGrenades), int(GrenadeCount) + AmountToAdd));
        return true;
    }
    return false;
    //return ReturnValue;    
}

function bool GiveWeaponsAmmo(bool bIncludeGrenades)
{
    local KFWeapon W;
    local bool bAddedAmmo;

    // End:0x68
    foreach InventoryActors(Class'KFGame.KFWeapon', W)
    {
        // End:0x67
        if(!W.bInfiniteSpareAmmo && GiveWeaponAmmo(W))
        {
            bAddedAmmo = true;
        }        
    }    
    // End:0x81
    if(bIncludeGrenades)
    {
        AddGrenades(1);
    }
    PlayGiveInventorySound(AmmoPickupSound);
    return bAddedAmmo;
    //return ReturnValue;    
}

reliable client simulated function SetCurrentWeapon(Weapon DesiredWeapon)
{
    super(InventoryManager).SetCurrentWeapon(DesiredWeapon);
    //return;    
}

function bool AddArmorFromPickup()
{
    local KFPawn_Human KFPH;

    KFPH = KFPawn_Human(Instigator);
    // End:0x94
    if(int(KFPH.Armor) != KFPH.GetMaxArmor())
    {
        PlayGiveInventorySound(ArmorPickupSound);
        KFPH.GiveMaxArmor();
        return true;
    }
    return false;
    //return ReturnValue;    
}

simulated function RemoveFromInventory(Inventory ItemToRemove)
{
    local Inventory Item;
    local bool bFound;

    // End:0x11
    if(ItemToRemove == none)
    {
        return;
    }
    // End:0x37
    if(PreviousEquippedWeapons[0] == ItemToRemove)
    {
        PreviousEquippedWeapons[0] = none;
    }
    // End:0x5D
    if(PreviousEquippedWeapons[1] == ItemToRemove)
    {
        PreviousEquippedWeapons[1] = none;
    }
    // End:0x7F
    if(PendingWeapon == ItemToRemove)
    {
        PendingWeapon = none;
    }
    // End:0xDC
    if((Instigator != none) && Instigator.Weapon == ItemToRemove)
    {
        Instigator.Weapon = none;
    }
    // End:0x12A
    if(InventoryChain == ItemToRemove)
    {
        bFound = true;
        InventoryChain = ItemToRemove.Inventory;        
    }
    else
    {
        Item = InventoryChain;
        J0x13D:

        // End:0x1EF [Loop If]
        if(Item != none)
        {
            // End:0x1C4
            if(Item.Inventory == ItemToRemove)
            {
                bFound = true;
                Item.Inventory = ItemToRemove.Inventory;
                // [Explicit Break]
                goto J0x1EF;
            }
            Item = Item.Inventory;
            // [Loop Continue]
            goto J0x13D;
        }
    }
    J0x1EF:

    // End:0x254
    if(bFound)
    {
        ItemToRemove.ItemRemovedFromInvManager();
        ItemToRemove.SetOwner(none);
        ItemToRemove.Inventory = none;
    }
    // End:0x364
    if((((Instigator != none) && Instigator.Health > 0) && Instigator.Controller != none) && Instigator.Weapon == none)
    {
        // End:0x30A
        if((PendingWeapon != none) && PendingWeapon != ItemToRemove)
        {
            ChangedWeapon();            
        }
        else
        {
            // End:0x364
            if(Instigator.Controller != none)
            {
                Instigator.Controller.SwitchToBestWeapon(true);
            }
        }
    }
    //return;    
}

simulated function Weapon GetBestWeapon(optional bool bForceADifferentWeapon, optional bool allow9mm)
{
    local KFWeapon W, BestWeapon;
    local float Rating, BestRating;

    // End:0x29E
    foreach InventoryActors(Class'KFGame.KFWeapon', W)
    {
        // End:0x29D
        if((!W.IsA('KFWeap_HealerBase') && !W.IsA('KFWeap_Welder')) && W.HasAnyAmmo())
        {
            Rating = (W.GroupPriority + 10.0000000) * (2.0000000 + FRand());
            switch(W.InventoryGroup)
            {
                // End:0x10B
                case 0:
                    Rating *= 2.5000000;
                    // End:0x13E
                    break;
                // End:0x123
                case 1:
                    Rating *= 1.5000000;
                    // End:0x13E
                    break;
                // End:0x12B
                case 2:
                    // End:0x13E
                    break;
                // End:0xFFFF
                default:
                    Rating *= 0.2500000;
                    break;
            }
            // End:0x181
            if(Class'KF2Bots.KF2BotsMut'.default.bBotsUnlimitedAmmo)
            {
                W.SpareAmmoCount[0] = 9999;
                W.SpareAmmoCount[1] = 9999;
            }
            // End:0x1F3
            if(!W.HasAmmo(0) && Instigator.Controller.Enemy != none)
            {
                Rating *= 0.7500000;
            }
            // End:0x24F
            if(W == Instigator.Weapon)
            {
                // End:0x23F
                if(bForceADifferentWeapon)
                {
                    Rating *= 0.2500000;                    
                }
                else
                {
                    Rating *= 1.1500000;
                }
            }
            // End:0x29D
            if((BestWeapon == none) || Rating > BestRating)
            {
                BestWeapon = W;
                BestRating = Rating;
            }
        }        
    }    
    return BestWeapon;
    //return ReturnValue;    
}

simulated function SwitchToBestWeapon(optional bool bForceADifferentWeapon, optional bool check_9mm_logic = false)
{
    local Weapon BestWeapon;

    // End:0x8B
    if(bForceADifferentWeapon || PendingWeapon == none)
    {
        BestWeapon = GetBestWeapon(bForceADifferentWeapon, check_9mm_logic);
        // End:0x5D
        if(BestWeapon == none)
        {
            return;
        }
        // End:0x8B
        if(BestWeapon == Instigator.Weapon)
        {
            return;
        }
    }
    Instigator.Controller.StopFiring();
    SetCurrentWeapon(BestWeapon);
    //return;    
}

defaultproperties
{
    MaxGrenades=5
    RemoteRole=ROLE_None
}