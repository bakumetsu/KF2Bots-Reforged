class AIWeaponInfo extends Object
    transient;

var Class<KFWeapon> WeaponClass;
var Class<KFPerk> Perk;
var float AIRating;
var int BuyPrice;
var int AmmoPricePerMag;
var int SecondaryAmmoMagSize;
var int SecondaryAmmoMagPrice;
var float PricePerBullet[2];
var bool bCanSell;

final function bool InitInformation(Class<KFWeaponDefinition> Def, name ClassName)
{
    local Class<KFWeapon> WC;

    // End:0x11
    if(Def == none)
    {
        return false;
    }
    WC = Class<KFWeapon>(DynamicLoadObject(Def.default.WeaponClassPath, Class'Core.Class'));
    // End:0x67
    if(WC == none)
    {
        return false;
    }
    WeaponClass = WC;
    Perk = WC.static.GetWeaponPerkClassByIndex(0);
    AIRating = float(Def.default.BuyPrice);
    BuyPrice = Def.default.BuyPrice;
    AmmoPricePerMag = Def.default.AmmoPricePerMag;
    SecondaryAmmoMagSize = Def.default.SecondaryAmmoMagSize;
    SecondaryAmmoMagPrice = Def.default.SecondaryAmmoMagPrice;
    bCanSell = Def.default.BuyPrice > 0;
    // End:0x1DA
    if(WC.default.MagazineCapacity[0] == 0)
    {
        PricePerBullet[0] = float(AmmoPricePerMag);        
    }
    else
    {
        PricePerBullet[0] = float(AmmoPricePerMag) / float(WC.default.MagazineCapacity[0]);
    }
    // End:0x23E
    if(SecondaryAmmoMagSize == 0)
    {
        PricePerBullet[1] = float(SecondaryAmmoMagPrice);        
    }
    else
    {
        PricePerBullet[1] = float(SecondaryAmmoMagPrice) / float(SecondaryAmmoMagSize);
    }
    return true;
    //return ReturnValue;    
}
