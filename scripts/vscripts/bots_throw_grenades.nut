GrenadierBots <- 0
MobSizeToThrowGrenade <- 6
UsePipeBomb <- 1
UseMolotov <- 2
UseVomitjar <- 1
GrenadeThrowCooldown <- 0
GrenadeAutoGive <- 0

FireButton <- 1
JumpButton <- 2
DuckButton <- 4
ForwardButton <- 8
BackButton <- 16
UseButton <- 32
LeftButton <- 512
RightButton <- 1024
ShoveButton <- 2048
ReloadButton <- 8192
ScoreButton <- 65536
ZoomButton <- 524288

function MercilessToggleFileCheck(filename)
{
	local files = FileToString(filename);
	if(!files)
	{
		return false;
	}
	return true;
}
function GenerateGrenadeThrowFile()
{
	local DefaultToggleFile = "";
	
	local CfgToggleFile =
	[
		"GrenadierBots 1",
		"MobSizeToThrowGrenade 6",
		"UsePipeBomb 1",
		"UseMolotov 2",
		"UseVomitjar 1",
		"GrenadeAutoGive 1",
		".",
		".",
		"// ====== TOGGLE SETTING INFO ======",
		"//GrenadierBots= This controls whether bots will pick & use grenades or not. It's disabled by default to prevent conflicts with other bot mods that also allow bots to use grenades, but it can be enabled via this cfg file",
		"0= Off (Default L4D2).",
		"1= On, bots will pick & use grenades.",
		".",
		"//MobSizeToThrowGrenade= This controls how many common infected in group are detected until a bot starts to throw a grenade. Default value is 6. (NOTES: The value for mob size might not be accurate enough, so just make some experiments to find which value fits you best)",
		"0= Only 1 common infected is all bots need to throw grenades.",
		"1 or higher= There must be at least (1 * value) common infected on sight until a bot throws grenade.",
		".",
		"//UsePipeBomb= This controls whether bots will pick & use pipe bomb or not.",
		"0= Off, bots won't pick or use pipe bomb.",
		"1= On, bots will use pipe bomb only on common infected.",
		"2= On, bots will use pipe bomb only on tank.",
		"3= On, bots will use pipe bomb on both common infected & tank.",
		".",
		"//UseMolotov= This controls whether bots will pick & use molotov or not. The value also affects the target priority.",
		"0= Off, bots won't pick or use molotov.",
		"1= On, bots will use molotov only on common infected.",
		"2= On, bots will use molotov only on tank that's not in burning state.",
		"3= On, bots will use molotov on both common infected & tank.",
		".",
		"//UseVomitjar= This controls whether bots will pick & use bile bomb or not. The value also affects the target priority.",
		"0= Off, bots won't pick or use bile bomb.",
		"1= On, bots will use bile bomb only on common infected.",
		"2= On, bots will use bile bomb only on tank that's not in burning state.",
		"3= On, bots will use bile bomb on both common infected & tank.",
		".",
		"//GrenadeAutoGive= Enabled by default. Bots will give their grenade to a survivor player they're looking at if the player doesn't have a grenade. When this is disabled, bots won't give grenades, but player can still take their grenades by shoving them.",
		"0= Off, bots won't give grenades.",
		"1= On, bots will give grenades to a player they're looking at.",
		".",
		".",
		"// =================================",
		"//Notes: This file is generated automatically when using this mod for the first time. To reset the this toggle back to the default, delete the file & then reload your gun.",
		"."
		
	]
	
	foreach (line in CfgToggleFile)
	{
		DefaultToggleFile = DefaultToggleFile + line + "\n";
	}
	if(!MercilessToggleFileCheck("bots throw grenades cfg/bots throw grenades.txt"))
	{
		
		StringToFile("bots throw grenades cfg/bots throw grenades.txt", DefaultToggleFile);
		printl("The 'bots throw grenades.txt' file can't be found. Generating a new 'bots throw grenades.txt' file...");
		
	}
	
}
function LoadSpecificConfigFile(filename)
{
	local trigger = 0;
	local files = FileToString(filename);
	if(!files)
	{
		return trigger;
	}
	local toggles = split(files, "\r\n");
	foreach(toggle in toggles)
	{
		if(toggle && toggle != "")
		{
			toggle = strip(toggle);
			local idx = toggle.find(" ");
			if(idx != null)
			{
				local togglecommand = toggle.slice(0, idx);
				local togglevalue = toggle.slice(idx + 1);
				local togglevalue2 = null;
				if(toggle.find("//") != null || toggle.find("===") != null)
				{
					trigger = 1;
				}
				else
				{
					if(togglecommand == "GrenadeAutoGive")
					{
						GrenadeAutoGive = togglevalue.tointeger();
						
					}
					if(togglecommand == "GrenadierBots")
					{
						GrenadierBots = togglevalue.tointeger();
						
					}
					if(togglecommand == "UsePipeBomb")
					{
						UsePipeBomb = togglevalue.tointeger();
						
					}
					if(togglecommand == "UseMolotov")
					{
						UseMolotov = togglevalue.tointeger();
						
					}
					if(togglecommand == "UseVomitjar")
					{
						UseVomitjar = togglevalue.tointeger();
						
					}
					if(togglecommand == "MobSizeToThrowGrenade")
					{
						MobSizeToThrowGrenade = togglevalue.tointeger();
						
					}
					else
					{
						trigger = 1;
					}
				}
			}
			
		}
	}
	
}

function VectorFromQAngle(angles, radius = 1.0)
{
	local function ToRad(angle)
	{
		return (angle * PI) / 180;
	}
	local yaw = ToRad(angles.Yaw());
	local pitch = ToRad(-angles.Pitch());
	local x = radius * cos(yaw) * cos(pitch);
	local y = radius * sin(yaw) * cos(pitch);
	local z = radius * sin(pitch);
	return Vector(x, y, z);
}

function ReleaseForcedButton(kent, keyvalue)
{
	local DisabledButtons = NetProps.GetPropInt(kent, "m_afButtonForced");
	local IsDisabled = DisabledButtons & keyvalue;
	if(kent.IsSurvivor())
	{
		return NetProps.SetPropInt(kent, "m_afButtonForced", DisabledButtons & ~ keyvalue);
	}
	return null;
}
function ForcedButton(kent, keyvalue)
{
	local DisabledButtons = NetProps.GetPropInt(kent, "m_afButtonForced");
	local IsDisabled = DisabledButtons & keyvalue;
	if(kent.IsSurvivor())
	{
		return NetProps.SetPropInt(kent, "m_afButtonForced", DisabledButtons | keyvalue);
		
	}
	return null;
}
function GetForcedButton(kent, keyvalue)
{
	local DisabledButtons = NetProps.GetPropInt(kent, "m_afButtonForced");
	local IsDisabled = DisabledButtons & keyvalue;
	if(kent.IsSurvivor())
	{
		return IsDisabled;
		
	}
	return null;
}

function IsAvailableEntity(kent)
{
	if(kent)
	{
		return true;
	}
	return false;
	
}
function GetButtonPressed(kent, keyvalue)
{
	if(kent.GetButtonMask() & keyvalue)
	{
		return true;
	}
	return false;
}
function GetPrimarySlot(player)
{
	local invTable = {};
	GetInvTable(player, invTable);

	if(!("slot0" in invTable))
		return null;
		
	local weapon = invTable.slot0;
	
	if(weapon)
		return weapon.GetClassname();
		
	return null;
}
function GetSecondarySlot(player)
{
	local invTable = {};
	GetInvTable(player, invTable);

	if(!("slot1" in invTable))
		return null;
		
	local weapon = invTable.slot1;
	
	if(weapon)
		return weapon.GetClassname();
		
	return null;
}
function GetThrowableSlot(player)
{
	local invTable = {};
	GetInvTable(player, invTable);

	if(!("slot2" in invTable))
		return null;
		
	local weapon = invTable.slot2;
	
	if(weapon)
		return weapon.GetClassname();
		
	return null;
}
function GetThrowableRemoved(player)
{
	local invTable = {};
	GetInvTable(player, invTable);

	if(!("slot2" in invTable))
		return null;
		
	local weapon = invTable.slot2;
	
	if(weapon)
		return weapon.Kill();
		
	return null;
}
function GetActiveMainWeapon(player)
{
	local weapon = player.GetActiveWeapon();
	
	if(weapon)
		return weapon.GetClassname();
		
	return null;
}
function PlayerChat(kent, chat)
{
	local argv = ::split( chat.slice(1), " " )
	
}

function DisableGodModeOnAll(kent)
{
	local traceEndpoint = kent.EyePosition() + VectorFromQAngle(kent.EyeAngles(), 666666);
	local traceTable =
	{
		start = kent.EyePosition()
		end = traceEndpoint
		ignore = kent
	}
	TraceLine(traceTable)
	if("enthit" in traceTable)
	{
		local survteam = null;
		while(survteam = Entities.FindByClassname(survteam, "player"))
		{
			if(survteam.IsSurvivor())
			{
				NetProps.SetPropInt(survteam, "m_takedamage", 2);
				
			}
		}
	}
}

function OnGameEvent_player_spawn(event)
{
	local entDamage = {};
	local kent = GetPlayerFromUserID(event.userid);
	
	if(kent.IsSurvivor())
	{
		if(kent.ValidateScriptScope())
		{
			if(!("kuro_grenadier_bots" in kent.GetScriptScope()) || kent.GetScriptScope().kuro_grenadier_bots != 6)
			{
				kent.GetScriptScope()["kuro_grenadier_bots"] <- 6;
			}
			if(!("grenadier_bots_pick_timer" in kent.GetScriptScope()))
			{
				kent.GetScriptScope()["grenadier_bots_pick_timer"] <- Time();
			}
			
		}
	}
}

function OnGameEvent_weapon_fire(event)
{
	local entDamage = {};
	local kent = GetPlayerFromUserID(event.userid);
	
	if(kent.IsSurvivor())
	{
		if(GrenadierBots != 0)
		{
			if(GetActiveMainWeapon(kent) == "weapon_vomitjar" || GetActiveMainWeapon(kent) == "weapon_molotov" || GetActiveMainWeapon(kent) == "weapon_pipe_bomb")
			{
				GrenadeThrowCooldown = Time();
				local survteam = null;
				while(survteam = Entities.FindByClassname(survteam, "player"))
				{
					if(survteam.IsSurvivor())
					{
						if(IsPlayerABot(survteam))
						{
							if(survteam != kent)
							{
								if(GetActiveMainWeapon(survteam) == GetThrowableSlot(survteam))
								{
									if(GetSecondarySlot(survteam) != null)
									{
										survteam.SwitchToItem(GetSecondarySlot(survteam));
										
									}
									
								}
							}
						}
						
					}
				}
				ReleaseForcedButton(kent, FireButton);
			}
		}
		
	}
}

function OnGameEvent_player_shoved(event)
{
	if(GrenadierBots != 0)
	{
		local shovetarget = GetPlayerFromUserID(event.userid);
		local kent = GetPlayerFromUserID(event.attacker);
		
		if(kent.IsSurvivor() && shovetarget.IsSurvivor())
		{
			if(!IsPlayerABot(kent))
			{
				if(IsPlayerABot(shovetarget))
				{
					if(GetThrowableSlot(kent) == null)
					{
						if(GetThrowableSlot(shovetarget) == "weapon_pipe_bomb")
						{
							shovetarget.DropItem(GetThrowableSlot(shovetarget));
							PickItem(kent, "weapon_pipe_bo", 150);
						}
						else if(GetThrowableSlot(shovetarget) == "weapon_molotov")
						{
							shovetarget.DropItem(GetThrowableSlot(shovetarget));
							PickItem(kent, "weapon_moloto", 150);
						}
						else if(GetThrowableSlot(shovetarget) == "weapon_vomitjar")
						{
							shovetarget.DropItem(GetThrowableSlot(shovetarget));
							PickItem(kent, "weapon_vomitja", 150);
						}
						
					}
				}
			}
			if(IsPlayerABot(shovetarget))
			{
				for(local grenadenearby; grenadenearby = Entities.FindByClassnameWithin(grenadenearby, "weapon_*", shovetarget.GetOrigin(), 150); )
				{
					if(grenadenearby.GetOwnerEntity() == null)
					{
						if(UseVomitjar > 0)
						{
							if(grenadenearby.GetClassname().find("weapon_vomitja") != null)
							{
								DoEntFire("!self", "Use", "", 0.1, shovetarget, grenadenearby);
							}
						}
						if(UseMolotov > 0)
						{
							if(grenadenearby.GetClassname().find("weapon_moloto") != null)
							{
								DoEntFire("!self", "Use", "", 0.1, shovetarget, grenadenearby);
							}
						}
						if(UsePipeBomb > 0)
						{
							if(grenadenearby.GetClassname().find("weapon_pipe_bo") != null)
							{
								DoEntFire("!self", "Use", "", 0.1, shovetarget, grenadenearby);
							}
						}
						
					}
				}
				ReleaseForcedButton(shovetarget, FireButton);
			}
		}
	}
	
}
function OnGameEvent_weapon_drop(event)
{
	local kent = null;
	if(("userid" in event))
	{
		kent = GetPlayerFromUserID(event.userid);
		
	}
	local droppeditem = null;
	if(("item" in event))
	{
		droppeditem = event["item"];
		
	}
	local entity = null;
	if("propid" in event)
	{
		entity = EntIndexToHScript(event.propid);
	}
	if(IsAvailableEntity(entity))
	{
		if(IsPlayerABot(kent))
		{
			if(kent.ValidateScriptScope())
			{
				if(entity.GetClassname().find("weapon_moloto") != null || entity.GetClassname().find("weapon_pipe_bo") != null || entity.GetClassname().find("weapon_vomitja") != null)
				{
					if(("grenadier_bots_pick_timer" in kent.GetScriptScope()))
					{
						kent.GetScriptScope().grenadier_bots_pick_timer = Time();
					}
					
				}
				
			}
		}
	}
}	
function OnGameEvent_weapon_reload(event)
{
	local kent = GetPlayerFromUserID(event.userid);
	
	if(kent.IsSurvivor())
	{
		if(!IsPlayerABot(kent))
		{
			if(!MercilessToggleFileCheck("bots throw grenades cfg/bots throw grenades.txt"))
			{
				GenerateGrenadeThrowFile();
				
			}
			LoadSpecificConfigFile("bots throw grenades cfg/bots throw grenades.txt");
			
		}
		else
		{
			ReleaseForcedButton(kent, FireButton);
		}
	}
}
function OnGameEvent_round_start_post_nav(event)
{
	AddThinkToEnt(self, "GrenadierBotsScript");
	printl("The 'BOTS THROW GRENADES' mod is launched.");
	if(!MercilessToggleFileCheck("bots throw grenades cfg/bots throw grenades.txt"))
	{
		GenerateGrenadeThrowFile();
		
	}
	LoadSpecificConfigFile("bots throw grenades cfg/bots throw grenades.txt");
	
}

function IsLookingAtTarget(kent, classname)
{
	local traceEndpoint = kent.EyePosition() + VectorFromQAngle(kent.EyeAngles(), 666666);
	local traceTable =
	{
		start = kent.EyePosition()
		end = traceEndpoint
		ignore = kent
	}
	if(TraceLine(traceTable))
	{
		if("enthit" in traceTable)
		{
			if(classname == "tank")
			{
				if(traceTable.enthit.GetClassname() == "player")
				{
					if(traceTable.enthit.GetZombieType() == 8)
					{
						return true;
					}
					
				}
			}
			else if(classname == "special")
			{
				if(traceTable.enthit.GetClassname() == "player")
				{
					if(traceTable.enthit.GetZombieType() < 7)
					{
						return true;
					}
					
				}
			}
			else if(classname == "survplayer")
			{
				if(traceTable.enthit.GetClassname() == "player")
				{
					if(traceTable.enthit.GetZombieType() == 9)
					{
						return true;
					}
					
				}
			}
			else
			{
				if(traceTable.enthit.GetClassname() == classname)
				{
					if(traceTable.enthit.GetHealth() > 0)
					{
						return true;
					}
					
				}
			}
			
		}
		
	}
	return false;
}

function GiveGrenade(kent)
{
	local traceEndpoint = kent.EyePosition() + VectorFromQAngle(kent.EyeAngles(), 666666);
	local traceTable =
	{
		start = kent.EyePosition()
		end = traceEndpoint
		ignore = kent
	}
	if(TraceLine(traceTable))
	{
		if("enthit" in traceTable)
		{
			if(kent.IsSurvivor())
			{
				if(traceTable.enthit.GetClassname() == "player")
				{
					if(traceTable.enthit.IsSurvivor())
					{
						if(!IsPlayerABot(traceTable.enthit) && !traceTable.enthit.IsDead())
						{
							if(GetThrowableSlot(kent) != null)
							{
								if(GetThrowableSlot(traceTable.enthit) == null)
								{
									if((kent.GetOrigin() - traceTable.enthit.GetOrigin()).Length() > 150)
									{
										return;
									}
									else
									{
										traceTable.enthit.GiveItem(GetThrowableSlot(kent));
										EmitSoundOnClient("Hint.LittleReward", traceTable.enthit);
										GetThrowableRemoved(kent);
									}
								}
							}
							
						}
					}
				}
				
			}
		}
		
	}
	
}

function GetCommonZombieWithin(player, range)
{
	local table = {};
	local i = -1;
	local entzom = null;
	while (entzom = Entities.FindByClassnameWithin(entzom, "infected", player.GetOrigin(), range))
	{
		if(entzom.GetHealth() > 0)
		{
			table[++i] <- entzom;
		}
			
	}
	return table;
}
function GetTankThreatWithin(player, range)
{
	local table = {};
	local i = -1;
	local entzom = null;
	while (entzom = Entities.FindByClassnameWithin(entzom, "player", player.GetOrigin(), range))
	{
		if(entzom.GetZombieType() == 8)
		{
			if(!entzom.IsDead() && !entzom.IsDying())
			{
				return true;
			}
			
		}
			
	}
	return false;
}
function PickItem(kent, classname, range)
{
	for(local grenadenearby; grenadenearby = Entities.FindByClassname(grenadenearby, "weapon_*"); )
	{
		if(grenadenearby.GetClassname().find( classname ) != null)
		{
			if(grenadenearby.GetOwnerEntity() == null)
			{
				if((kent.GetOrigin() - grenadenearby.GetOrigin()).Length() <= range)
				{
					DoEntFire("!self", "Use", "", 0, kent, grenadenearby);
				}
			}
		}
	}
	return null;
}

function BotsFireInHole(kent)
{
	local traceEndpoint = kent.EyePosition() + VectorFromQAngle(kent.EyeAngles(), 666666);
	local traceTable =
	{
		start = kent.EyePosition()
		end = traceEndpoint
		ignore = kent
	}
	if(TraceLine(traceTable))
	{
		if("enthit" in traceTable)
		{
			if(kent.IsSurvivor())
			{
				if(GetThrowableSlot(kent) != null)
				{
					if(Time() >= GrenadeThrowCooldown + 20)
					{
						if(UseVomitjar > 0)
						{
							if(GetThrowableSlot(kent) == "weapon_vomitjar")
							{
								if(UseVomitjar >= 2)
								{
									if(NetProps.GetPropInt(traceTable.enthit, "m_zombieClass") == 8)
									{
										if(!traceTable.enthit.IsDead() && !traceTable.enthit.IsDying())
										{
											if((kent.GetOrigin() - traceTable.enthit.GetOrigin()).Length() > 900)
											{
												return;
											}
											else
											{
												kent.SwitchToItem(GetThrowableSlot(kent));
												
												if(GetForcedButton(kent, FireButton))
												{
													ReleaseForcedButton(kent, FireButton);
												}
												else
												{
													ForcedButton(kent, FireButton);
												}
											}
										}
										
									}
									
								}
								if(UseVomitjar == 1 || UseVomitjar >= 3)
								{
									if(traceTable.enthit.GetClassname() == "infected")
									{
										if(traceTable.enthit.GetHealth() > 0)
										{
											if(GetCommonZombieWithin(traceTable.enthit, 300).len() < MobSizeToThrowGrenade)
											{
												return;
											}
											else
											{
												kent.SwitchToItem(GetThrowableSlot(kent));
												
												if(GetForcedButton(kent, FireButton))
												{
													ReleaseForcedButton(kent, FireButton);
												}
												else
												{
													ForcedButton(kent, FireButton);
												}
											}
											
										}
									}
									
								}
								
							}
							
						}
						if(UseMolotov > 0)
						{
							if(GetThrowableSlot(kent) == "weapon_molotov")
							{
								if(UseMolotov >= 2)
								{
									if(NetProps.GetPropInt(traceTable.enthit, "m_zombieClass") == 8)
									{
										if(!traceTable.enthit.IsDead() && !traceTable.enthit.IsDying())
										{
											if(!traceTable.enthit.IsOnFire())
											{
												if((kent.GetOrigin() - traceTable.enthit.GetOrigin()).Length() > 900)
												{
													return;
												}
												else
												{
													kent.SwitchToItem(GetThrowableSlot(kent));
													
													if(GetForcedButton(kent, FireButton))
													{
														ReleaseForcedButton(kent, FireButton);
													}
													else
													{
														ForcedButton(kent, FireButton);
													}
												}
											}
										}
										
									}
									
								}
								if(UseMolotov == 1 || UseMolotov >= 3)
								{
									if(traceTable.enthit.GetClassname() == "infected")
									{
										if(traceTable.enthit.GetHealth() > 0)
										{
											if(GetCommonZombieWithin(traceTable.enthit, 300).len() < MobSizeToThrowGrenade)
											{
												return;
											}
											else
											{
												kent.SwitchToItem(GetThrowableSlot(kent));
												
												if(GetForcedButton(kent, FireButton))
												{
													ReleaseForcedButton(kent, FireButton);
												}
												else
												{
													ForcedButton(kent, FireButton);
												}
											}
											
										}
									}
									
								}
								
							}
							
						}
						if(UsePipeBomb > 0)
						{
							if(GetThrowableSlot(kent) == "weapon_pipe_bomb")
							{
								if(UsePipeBomb >= 2)
								{
									if(NetProps.GetPropInt(traceTable.enthit, "m_zombieClass") == 8)
									{
										if(!traceTable.enthit.IsDead() && !traceTable.enthit.IsDying())
										{
											if((kent.GetOrigin() - traceTable.enthit.GetOrigin()).Length() > 900)
											{
												return;
											}
											else
											{
												kent.SwitchToItem(GetThrowableSlot(kent));
												
												if(GetForcedButton(kent, FireButton))
												{
													ReleaseForcedButton(kent, FireButton);
												}
												else
												{
													ForcedButton(kent, FireButton);
												}
											}
										}
										
									}
									
								}
								if(UsePipeBomb == 1 || UsePipeBomb >= 3)
								{
									if(traceTable.enthit.GetClassname() == "infected")
									{
										if(traceTable.enthit.GetHealth() > 0)
										{
											if(GetCommonZombieWithin(traceTable.enthit, 300).len() < MobSizeToThrowGrenade)
											{
												return;
											}
											else
											{
												kent.SwitchToItem(GetThrowableSlot(kent));
												
												if(GetForcedButton(kent, FireButton))
												{
													ReleaseForcedButton(kent, FireButton);
												}
												else
												{
													ForcedButton(kent, FireButton);
												}
											}
											
										}
									}
									
								}
								
							}
							
						}
						
					}
					
				}
			}
		}
	}
	
}

function GrenadierBotsScript()
{
	if(GrenadierBots >= 1)
	{
		local returner = 6;
		local grenadenearby = null;
		for(local survbot; survbot = Entities.FindByClassname(survbot, "player"); )
		{
			if(survbot.IsSurvivor())
			{
				if(IsPlayerABot(survbot) && survbot.ValidateScriptScope())
				{
					if(("kuro_grenadier_bots" in survbot.GetScriptScope()) && survbot.GetScriptScope().kuro_grenadier_bots == 6)
					{
						if(!survbot.IsDead())
						{
							if(GetThrowableSlot(survbot) == null)
							{
								while(grenadenearby = Entities.FindByClassname(grenadenearby, "weapon_*"))
								{
									if(grenadenearby.GetClassname().find("weapon_vomitja") != null || grenadenearby.GetClassname().find("weapon_moloto") != null || grenadenearby.GetClassname().find("weapon_pipe_bo") != null)
									{
										if(grenadenearby.GetOwnerEntity() == null)
										{
											if((survbot.GetOrigin() - grenadenearby.GetOrigin()).Length() > 150)
											{
												returner = 666;
												
											}
											else
											{
												if(("grenadier_bots_pick_timer" in survbot.GetScriptScope()) && Time() >= survbot.GetScriptScope().grenadier_bots_pick_timer + 2)
												{
													survbot.GetScriptScope().grenadier_bots_pick_timer = Time();
													
													if(UseVomitjar > 0)
													{
														if(grenadenearby.GetClassname().find("weapon_vomitja") != null)
														{
															DoEntFire("!self", "Use", "", 0.1, survbot, grenadenearby);
														}
													}
													if(UseMolotov > 0)
													{
														if(grenadenearby.GetClassname().find("weapon_moloto") != null)
														{
															DoEntFire("!self", "Use", "", 0.1, survbot, grenadenearby);
														}
													}
													if(UsePipeBomb > 0)
													{
														if(grenadenearby.GetClassname().find("weapon_pipe_bo") != null)
														{
															DoEntFire("!self", "Use", "", 0.1, survbot, grenadenearby);
														}
													}
													
												}
												
											}
											
										}
										
									}
									else
									{
										returner = 666;
									}
									
								}
							}
							else if(GetThrowableSlot(survbot) != null)
							{
								if(GetThrowableSlot(survbot) == "weapon_vomitjar")
								{
									if(GrenadeAutoGive > 0)
									{
										if(IsLookingAtTarget(survbot, "survplayer"))
										{
											GiveGrenade(survbot);
										}
										
									}
									
									if(UseVomitjar > 0)
									{
										if(UseVomitjar == 1)
										{
											if(IsLookingAtTarget(survbot, "infected"))
											{
												BotsFireInHole(survbot);
											}
											else
											{
												return;
											}
											
										}
										else if(UseVomitjar == 2)
										{
											if(IsLookingAtTarget(survbot, "tank"))
											{
												BotsFireInHole(survbot);
											}
											else
											{
												return;
											}
											
										}
										else if(UseVomitjar >= 3)
										{
											if(IsLookingAtTarget(survbot, "infected") || IsLookingAtTarget(survbot, "tank"))
											{
												BotsFireInHole(survbot);
											}
											else
											{
												return;
											}
											
										}
										
									}
								}
								else if(GetThrowableSlot(survbot) == "weapon_molotov")
								{
									if(GrenadeAutoGive > 0)
									{
										if(IsLookingAtTarget(survbot, "survplayer"))
										{
											GiveGrenade(survbot);
										}
										
									}
									if(UseMolotov > 0)
									{
										if(UseMolotov == 1)
										{
											if(IsLookingAtTarget(survbot, "infected"))
											{
												BotsFireInHole(survbot);
											}
											else
											{
												return;
											}
											
										}
										else if(UseMolotov == 2)
										{
											if(IsLookingAtTarget(survbot, "tank"))
											{
												BotsFireInHole(survbot);
											}
											else
											{
												return;
											}
											
										}
										else if(UseMolotov >= 3)
										{
											if(IsLookingAtTarget(survbot, "infected") || IsLookingAtTarget(survbot, "tank"))
											{
												BotsFireInHole(survbot);
											}
											else
											{
												return;
											}
											
										}
										
									}
								}
								else if(GetThrowableSlot(survbot) == "weapon_pipe_bomb")
								{
									if(GrenadeAutoGive > 0)
									{
										if(IsLookingAtTarget(survbot, "survplayer"))
										{
											GiveGrenade(survbot);
										}
										
									}
									if(UsePipeBomb > 0)
									{
										if(UsePipeBomb == 1)
										{
											if(IsLookingAtTarget(survbot, "infected"))
											{
												BotsFireInHole(survbot);
											}
											else
											{
												return;
											}
											
										}
										else if(UsePipeBomb == 2)
										{
											if(IsLookingAtTarget(survbot, "tank"))
											{
												BotsFireInHole(survbot);
											}
											else
											{
												return;
											}
											
										}
										else if(UsePipeBomb >= 3)
										{
											if(IsLookingAtTarget(survbot, "infected") || IsLookingAtTarget(survbot, "tank"))
											{
												BotsFireInHole(survbot);
											}
											else
											{
												return;
											}
											
										}
										
									}
								}
								
							}
						}
					}
				}
			}
			
		}
	}
	
}