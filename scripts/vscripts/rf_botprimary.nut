printl("Bot Primary Weapon Enforcer script by RF");

function IHateYouEllis()
{
	local playarr = null;
	while(playarr = Entities.FindByClassname(playarr, "player"))
	{
		if(playarr.IsSurvivor() && !playarr.IsDead() && !playarr.IsIncapacitated() && IsPlayerABot(playarr) && playarr.GetActiveWeapon() != null)
		{
			local AWClass = playarr.GetActiveWeapon().GetClassname();
			if(AWClass == "weapon_pistol" || AWClass == "weapon_pistol_magnum" || AWClass == "weapon_melee" || AWClass == "weapon_chainsaw")
			{
				local inv = {};
				GetInvTable(playarr , inv);
				if("slot0" in inv)
				{
					local PrimType = NetProps.GetPropInt(inv.slot0, "m_iPrimaryAmmoType");
					if(NetProps.GetPropIntArray(playarr, "m_iAmmo", PrimType) > 0)
					{
						playarr.SwitchToItem(inv.slot0.GetClassname());
						NetProps.SetPropFloat(inv.slot0, "LocalActiveWeaponData.m_flNextPrimaryAttack", 0.0);
						NetProps.SetPropFloat(inv.slot0, "LocalActiveWeaponData.m_flNextSecondaryAttack", 0.0);
						// ^ Makes the bots able to attack instantly
						// Shadowysn: I know you may not want the bots to be able to skip one of their attacking delays and get a 
						// miniscule advantage to shoot immediately but as a trade-off, SwitchToItem reduces the invisible guns 
						// to a small flicker rather than being forever invisible until another gun switch is performed
						// Reload bug where they reset their reload timer again when they attempt to switch is still here tho
					}
				}
			}
		}
	}
}