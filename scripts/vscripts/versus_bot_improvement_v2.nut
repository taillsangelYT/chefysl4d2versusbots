Msg("===================================\n");
Msg(" Versus Bot Improvement v2 (Advanced)\n");
Msg("===================================\n");

GrenadierBots <- 1          
MobSizeToThrowGrenade <- 4  
UsePipeBomb <- 3            
UseMolotov <- 3             
UseVomitjar <- 3            
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

// Special infected zombie type IDs
ZOMBIE_SMOKER   <- 1
ZOMBIE_BOOMER   <- 2
ZOMBIE_HUNTER   <- 3
ZOMBIE_SPITTER  <- 4
ZOMBIE_JOCKEY   <- 5
ZOMBIE_CHARGER  <- 6
ZOMBIE_TANK     <- 8
ZOMBIE_SURVIVOR <- 9

::VBI_CFG <-
{
    think_interval          = 0.25,
    threat_update_interval  = 0.3,
    follow_distance         = 150.0,
    spread_distance         = 120.0,
    max_follow_distance     = 300.0,
    rescue_check_interval   = 0.15,   
    grenade_lock_duration   = 1.5,    
    ammo_refill_threshold   = 30,    
    ammo_refill_amount      = 200,    
    fire_damage_scale       = 0.25,   
    spit_damage_scale       = 0.25,   
    grenade_throw_cooldown  = 15.0,   
    grenade_mob_radius      = 250.0,  
    grenade_throw_range     = 600.0,
    debug                   = false
};


if ("VBI_USER_SETTINGS" in getroottable())
{
    foreach (key, val in VBI_USER_SETTINGS)
    {
        if (key in VBI_CFG)
            VBI_CFG[key] = val;
        
        if (key == "convar_overrides")
            foreach (cvar, cval in val)
                SendToServerConsole(cvar + " " + cval);
    }
}

::VBI_STATE <-
{
    lastThink       = 0.0,
    lastThreatUpdate= 0.0,
    currentThreat   = null
};



function VBI_IsValidPlayer(p)
{
    return p != null && ("IsPlayer" in p) && p.IsPlayer();
}

function VBI_IsSurvivor(p)
{
    return VBI_IsValidPlayer(p) && p.GetTeam() == 2;
}

function VBI_IsBot(p)
{
    return VBI_IsSurvivor(p) && p.IsBot();
}

function VBI_GetAll()
{
    local arr = [];
    local p = null;
    while ((p = Entities.FindByClassname(p, "player")) != null)
        if (VBI_IsValidPlayer(p))
            arr.append(p);
    return arr;
}

function VBI_GetBots()
{
    local arr = [];
    foreach (p in VBI_GetAll())
        if (VBI_IsBot(p) && p.IsAlive())
            arr.append(p);
    return arr;
}

function VBI_Dist(a, b)
{
    return (a - b).Length();
}

function VBI_CanSee(bot, target)
{
    local traceTable = { start = bot.EyePosition(), end = target.EyePosition(), ignore = bot };
    TraceLine(traceTable);
    return traceTable.fraction == 1.0 || (("enthit" in traceTable) && traceTable.enthit == target);
}


function VBI_IsEnemy(ent)
{
    return ent != null && ent.GetTeam() == 3 && ent.IsAlive();
}

// FIX: Returns base threat score — distance weighting applied per-bot in VBI_FindThreatForBot
function VBI_GetThreatScore(e)
{
    local t = e.GetZombieType();
    if (t == ZOMBIE_TANK)    return 200;
    if (t == ZOMBIE_BOOMER)  return 110;
    if (t == ZOMBIE_SMOKER)  return 105;
    if (t == ZOMBIE_HUNTER)  return 95;
    if (t == ZOMBIE_JOCKEY)  return 90;
    if (t == ZOMBIE_CHARGER) return 85;
    if (t == ZOMBIE_SPITTER) return 85;
    return 10;
}

// FIX: Each bot picks its own nearest/most-dangerous threat, not a shared global one
function VBI_FindThreatForBot(bot)
{
    local best      = null;
    local bestScore = -1;
    local botPos    = bot.GetOrigin();

    local ent = null;
    while ((ent = Entities.FindByClassname(ent, "player")) != null)
    {
        if (!VBI_IsEnemy(ent)) continue;
        if (!VBI_CanSee(bot, ent)) continue;

        local baseScore = VBI_GetThreatScore(ent);
        local dist      = VBI_Dist(botPos, ent.GetOrigin());

        // Distance penalty: score halves every 600 units
        // A smoker at 100u (score ~97) beats a spitter at 800u (score ~38)
        local distFactor = 1.0 / (1.0 + dist / 600.0);
        local score      = baseScore * distFactor;

        if (score > bestScore)
        {
            bestScore = score;
            best      = ent;
        }
    }

    return best;
}


function VBI_FindThreat()
{
    local best      = null;
    local bestScore = -1;
    local ent       = null;
    while ((ent = Entities.FindByClassname(ent, "player")) != null)
    {
        if (!VBI_IsEnemy(ent)) continue;
        local score = VBI_GetThreatScore(ent);
        if (score > bestScore) { bestScore = score; best = ent; }
    }
    return best;
}

function VBI_UpdateThreat()
{
    if (Time() - VBI_STATE.lastThreatUpdate < VBI_CFG.threat_update_interval)
        return;
    VBI_STATE.lastThreatUpdate = Time();
    VBI_STATE.currentThreat    = VBI_FindThreat();
}



// FIX: Detect when a survivor is being controlled by a special infected
// Covers: Smoker tongue, Hunter pounce, Jockey ride, Charger carry
function VBI_IsGrabbed(p)
{
    if (!VBI_IsValidPlayer(p) || !p.IsAlive()) return false;

    // m_pummelAttacker / m_carryAttacker are set during Charger sequences
    local pummel = NetProps.GetPropEntity(p, "m_pummelAttacker");
    local carry  = NetProps.GetPropEntity(p, "m_carryAttacker");
    if (pummel != null || carry != null) return true;

    // m_tongueOwner set while Smoker tongue is active
    local tongue = NetProps.GetPropEntity(p, "m_tongueOwner");
    if (tongue != null) return true;

    // m_jockeyAttacker for Jockey
    local jockey = NetProps.GetPropEntity(p, "m_jockeyAttacker");
    if (jockey != null) return true;

    // Hunter pounce — victim is pinned (m_pounceVictim on the Hunter side,
    // but we can check from the victim using m_isHangingFromLedge is wrong here,
    // instead check if the survivor is incapacitated in a special way)
    if (p.IsIncapacitated())
    {
        // If incapped AND a hunter is nearby and alive, treat as pinned
        local hunter = null;
        while ((hunter = Entities.FindInSphere(hunter, p.GetOrigin(), 120)) != null)
            if (hunter.GetClassname() == "player" && hunter.GetZombieType() == ZOMBIE_HUNTER && hunter.IsAlive())
                return true;
    }

    return false;
}

// FIX: Find the attacker entity currently grabbing a survivor
function VBI_GetGrabber(p)
{
    if (!VBI_IsValidPlayer(p)) return null;

    local pummel = NetProps.GetPropEntity(p, "m_pummelAttacker");
    if (pummel != null) return pummel;
    local carry = NetProps.GetPropEntity(p, "m_carryAttacker");
    if (carry != null) return carry;
    local tongue = NetProps.GetPropEntity(p, "m_tongueOwner");
    if (tongue != null) return tongue;
    local jockey = NetProps.GetPropEntity(p, "m_jockeyAttacker");
    if (jockey != null) return jockey;

    // Hunter pin — find the hunter
    if (p.IsIncapacitated())
    {
        local hunter = null;
        while ((hunter = Entities.FindInSphere(hunter, p.GetOrigin(), 120)) != null)
            if (hunter.GetClassname() == "player" && hunter.GetZombieType() == ZOMBIE_HUNTER && hunter.IsAlive())
                return hunter;
    }

    return null;
}

// FIX: Find any grabbed teammate. Returns { victim, grabber } or null.
// Prioritizes the closest victim to the bot.
function VBI_FindGrabbedTeammate(bot)
{
    local best = null;
    local bestDist = 999999;
    local botPos = bot.GetOrigin();

    foreach (p in VBI_GetAll())
    {
        if (!VBI_IsSurvivor(p)) continue;
        if (p == bot) continue;
        if (!VBI_IsGrabbed(p)) continue;

        local d = VBI_Dist(botPos, p.GetOrigin());
        if (d < bestDist)
        {
            bestDist = d;
            best = p;
        }
    }

    if (best != null)
    {
        return { victim = best, grabber = VBI_GetGrabber(best) };
    }
    return null;
}



function VBI_Attack(bot, target)
{
    bot.CommandAttack(target);
}

function VBI_Move(bot, pos)
{
    bot.CommandMove(pos);
}

function VBI_Reset(bot)
{
    bot.CommandReset();
}

function GetInvTable(player, invTable)
{
    for (local i = 0; i < 5; i++)
    {
        local weapon = NetProps.GetPropEntity(player, "m_hMyWeapons", i);
        if (weapon) invTable["slot" + i] <- weapon;
    }
}



// FIX: Anchor can now fall back to any survivor (bot or human) if no human is present
function VBI_GetAnchor(bot)
{
    local best     = null;
    local bestDist = 999999;

    // Prefer human survivors first
    foreach (p in VBI_GetAll())
    {
        if (!VBI_IsSurvivor(p)) continue;
        if (p == bot) continue;
        if (VBI_IsBot(p)) continue;    // Skip bots in first pass

        local d = VBI_Dist(bot.GetOrigin(), p.GetOrigin());
        if (d < bestDist) { bestDist = d; best = p; }
    }

   
    if (best == null)
    {
        foreach (p in VBI_GetAll())
        {
            if (!VBI_IsSurvivor(p)) continue;
            if (p == bot) continue;
            if (!p.IsAlive()) continue;

            local d = VBI_Dist(bot.GetOrigin(), p.GetOrigin());
            if (d < bestDist) { bestDist = d; best = p; }
        }
    }

    return best;
}

// FIX: Stable spread direction — offset away from anchor rather than random each tick
function VBI_GetSpreadOffset(bot, anchor)
{
    local diff = bot.GetOrigin() - anchor.GetOrigin();
    local len  = diff.Length();
    if (len < 1.0)
    {
        // Degenerate case: bot is ON the anchor, pick a stable offset based on entindex
        local angle = (bot.entindex() % 4) * 90.0 * (3.14159 / 180.0);
        return Vector(cos(angle) * VBI_CFG.spread_distance,
                      sin(angle) * VBI_CFG.spread_distance, 0);
    }
    // Normalize and scale to desired spread distance
    return Vector((diff.x / len) * VBI_CFG.spread_distance,
                  (diff.y / len) * VBI_CFG.spread_distance, 0);
}

function VBI_Position(bot)
{
    local anchor = VBI_GetAnchor(bot);
    if (anchor == null) return;

    local dist = VBI_Dist(bot.GetOrigin(), anchor.GetOrigin());

    // If taking hazard damage, move towards anchor to path out
    if (bot.ValidateScriptScope())
    {
        local scope = bot.GetScriptScope();
        if ("last_hazard_time" in scope && Time() - scope.last_hazard_time < 1.0)
        {
            VBI_Move(bot, anchor.GetOrigin());
            return;
        }
    }

    if (dist > VBI_CFG.max_follow_distance)
    {
        VBI_Move(bot, anchor.GetOrigin());
        return;
    }

    if (dist < VBI_CFG.spread_distance)
    {
        // FIX: Stable direction instead of random offset every tick
        local offset = VBI_GetSpreadOffset(bot, anchor);
        VBI_Move(bot, anchor.GetOrigin() + offset);
        return;
    }

    VBI_Reset(bot);
}


function VectorFromQAngle(angles, radius = 1.0)
{
    local function ToRad(angle) { return (angle * PI) / 180; }
    local yaw   = ToRad(angles.Yaw());
    local pitch = ToRad(-angles.Pitch());
    local x = radius * cos(yaw) * cos(pitch);
    local y = radius * sin(yaw) * cos(pitch);
    local z = radius * sin(pitch);
    return Vector(x, y, z);
}

function ReleaseForcedButton(kent, keyvalue)
{
    if (kent.IsSurvivor())
        NetProps.SetPropInt(kent, "m_afButtonForced",
            NetProps.GetPropInt(kent, "m_afButtonForced") & ~keyvalue);
}

function ForcedButton(kent, keyvalue)
{
    if (kent.IsSurvivor())
        NetProps.SetPropInt(kent, "m_afButtonForced",
            NetProps.GetPropInt(kent, "m_afButtonForced") | keyvalue);
}

function GetForcedButton(kent, keyvalue)
{
    if (kent.IsSurvivor())
        return NetProps.GetPropInt(kent, "m_afButtonForced") & keyvalue;
    return null;
}

function IsAvailableEntity(kent)
{
    return kent != null;
}

function GetButtonPressed(kent, keyvalue)
{
    return (kent.GetButtonMask() & keyvalue) != 0;
}

function GetPrimarySlot(player)
{
    local invTable = {};
    GetInvTable(player, invTable);
    if (!("slot0" in invTable)) return null;
    local weapon = invTable.slot0;
    return weapon ? weapon.GetClassname() : null;
}

function GetSecondarySlot(player)
{
    local invTable = {};
    GetInvTable(player, invTable);
    if (!("slot1" in invTable)) return null;
    local weapon = invTable.slot1;
    return weapon ? weapon.GetClassname() : null;
}

function GetThrowableSlot(player)
{
    local invTable = {};
    GetInvTable(player, invTable);
    if (!("slot2" in invTable)) return null;
    local weapon = invTable.slot2;
    return weapon ? weapon.GetClassname() : null;
}

function GetThrowableRemoved(player)
{
    local invTable = {};
    GetInvTable(player, invTable);
    if (!("slot2" in invTable)) return null;
    local weapon = invTable.slot2;
    if (weapon) weapon.Kill();
}

function GetActiveMainWeapon(player)
{
    local weapon = player.GetActiveWeapon();
    return weapon ? weapon.GetClassname() : null;
}

// FIX: Per-bot grenade fire timer replaces the global toggle pattern.
// Instead of flipping forced-fire on/off and hoping timing is right, each bot
// gets its own "fire until" timestamp so concurrent bots don't stomp each other.
function VBI_BotFireGrenade(bot, durationSec)
{
    if (!bot.ValidateScriptScope()) return;
    local scope = bot.GetScriptScope();
    scope["grenade_fire_until"]    <- Time() + durationSec;
    scope["grenade_switched_back"] <- false;  // Reset so switch-back fires after this throw
}

// Called in the think loop to apply/release fire button per bot
function VBI_TickGrenadeFireButtons()
{
    local now = Time();
    for (local bot; bot = Entities.FindByClassname(bot, "player"); )
    {
        if (!bot.IsSurvivor() || !IsPlayerABot(bot) || bot.IsDead()) continue;
        if (!bot.ValidateScriptScope()) continue;
        local scope = bot.GetScriptScope();
        if (!("grenade_fire_until" in scope)) continue;

        if (now < scope.grenade_fire_until)
        {
            ForcedButton(bot, FireButton);
        }
        else if (!("grenade_switched_back" in scope) || !scope.grenade_switched_back)
        {
            // Throw window just closed — release fire and switch back to a real weapon
            ReleaseForcedButton(bot, FireButton);

            // Switch back using entity handles, not classname strings
            local inv = {};
            GetInvTable(bot, inv);
            if ("slot1" in inv && inv.slot1 != null)
                bot.SwitchToItem(inv.slot1);  // secondary (pistol etc.)
            else if ("slot0" in inv && inv.slot0 != null)
                bot.SwitchToItem(inv.slot0);  // primary

            scope["grenade_switched_back"] <- true;
        }
    }
}

function DisableGodModeOnAll(kent)
{
    local traceEndpoint = kent.EyePosition() + VectorFromQAngle(kent.EyeAngles(), 666666);
    local traceTable = { start = kent.EyePosition(), end = traceEndpoint, ignore = kent };
    TraceLine(traceTable);
    if ("enthit" in traceTable)
    {
        local survteam = null;
        while (survteam = Entities.FindByClassname(survteam, "player"))
            if (survteam.IsSurvivor())
                NetProps.SetPropInt(survteam, "m_takedamage", 2);
    }
}


//////////////////////////////////////////////////
// FIRE / ACID DAMAGE REDUCTION
//////////////////////////////////////////////////

// L4D2 damage type bitmask constants relevant to fire and spitter acid.
// DMG_BURN (8) covers molotov flames and fire from infected.
// DMG_POISON (64) is what the game uses for Spitter acid pool damage.
// The inferno entity that creates acid pools also inflicts DMG_BURN in
// some builds, so we catch both flags.
DMG_BURN   <- 8;
DMG_POISON <- 64;

// Called from OnGameEvent_player_spawn to attach the hook to a bot.
// Each bot gets its own ScriptScope function so the closure captures
// the correct player handle.
function VBI_AttachDamageHook(bot)
{
    if (!bot.ValidateScriptScope()) return;

    local scope = bot.GetScriptScope();

    // Avoid double-hooking if the player respawns mid-round
    if ("vbi_damage_hook_active" in scope && scope.vbi_damage_hook_active) return;

    scope["vbi_damage_hook_active"] <- true;

    // OnTakeDamage is called with a damage info table:
    //   params.damage       — damage amount (float, writable)
    //   params.damage_type  — bitmask of DMG_* flags
    //   params.inflictor    — entity dealing the damage (can be null)
    //   params.attacker     — entity that owns the inflictor
    scope["OnTakeDamage"] <- function(params)
    {
        local victim = params.victim;
        // Only reduce damage for bots — human survivors get vanilla damage
        if (!IsPlayerABot(victim)) return;

        local dtype = params.damage_type;

        if (dtype & DMG_BURN)
        {
            params.damage = params.damage * ::VBI_CFG.fire_damage_scale;
            victim.GetScriptScope()["last_hazard_time"] <- Time();
            return;
        }

        if (dtype & DMG_POISON)
        {
            params.damage = params.damage * ::VBI_CFG.spit_damage_scale;
            victim.GetScriptScope()["last_hazard_time"] <- Time();
            return;
        }

        // Spitter acid pools use an inferno-type entity whose classname is
        // "insect_swarm" or "spitter_projectile_*" — catch by inflictor name
        // as a secondary check in case the damage type flag differs by build.
        if ("inflictor" in params && params.inflictor != null)
        {
            local icn = params.inflictor.GetClassname();
            if (icn.find("spitter") != null || icn.find("insect") != null)
            {
                params.damage = params.damage * ::VBI_CFG.spit_damage_scale;
                return;
            }
            // Burning tank rock / burning common infected also inflict fire damage
            // sometimes tagged as generic; catch inferno entity as fallback
            if (icn == "inferno")
            {
                params.damage = params.damage * ::VBI_CFG.fire_damage_scale;
                return;
            }
        }
    };
}


//////////////////////////////////////////////////
// AMMO MANAGEMENT
//////////////////////////////////////////////////

// Weapons that use reserve ammo and should be kept topped up.
// Pistols are intentionally excluded — if a bot is on pistol it means
// their primary is empty, which IHateYouEllis + VBI_CheckAmmo fix together.
VBI_PRIMARY_WEAPONS <-
[
    "weapon_rifle",
    "weapon_rifle_ak47",
    "weapon_rifle_desert",
    "weapon_rifle_m60",
    "weapon_rifle_sg552",
    "weapon_smg",
    "weapon_smg_silenced",
    "weapon_smg_mp5",
    "weapon_pumpshotgun",
    "weapon_shotgun_chrome",
    "weapon_autoshotgun",
    "weapon_shotgun_spas",
    "weapon_grenade_launcher"
];

function VBI_IsPrimaryWeapon(classname)
{
    foreach (cn in VBI_PRIMARY_WEAPONS)
        if (classname == cn) return true;
    return false;
}

// Top up a bot's reserve ammo on their primary when it runs low.
// Uses m_iAmmo array indexed by the weapon's m_iPrimaryAmmoType.
function VBI_CheckAmmo(bot)
{
    if (!bot.IsAlive() || bot.IsIncapacitated()) return;

    local inv = {};
    GetInvTable(bot, inv);
    if (!("slot0" in inv)) return;

    local primary = inv.slot0;
    if (primary == null) return;

    local cn = primary.GetClassname();
    if (!VBI_IsPrimaryWeapon(cn)) return;

    local ammoType = NetProps.GetPropInt(primary, "m_iPrimaryAmmoType");
    if (ammoType < 0) return;

    local reserve = NetProps.GetPropIntArray(bot, "m_iAmmo", ammoType);

    if (reserve < VBI_CFG.ammo_refill_threshold)
    {
        NetProps.SetPropIntArray(bot, "m_iAmmo", VBI_CFG.ammo_refill_amount, ammoType);
        if (VBI_CFG.debug)
            printl("[VBI] Refilled ammo for " + bot.GetPlayerName()
                   + " (" + cn + ") " + reserve + " -> " + VBI_CFG.ammo_refill_amount);
    }
}

// Forces bots to switch back to primary weapon if they have ammo
function IHateYouEllis()
{
    foreach (bot in VBI_GetBots())
    {
        if (!bot.IsAlive() || bot.IsIncapacitated()) continue;

        local activeWeapon = bot.GetActiveWeapon();
        if (activeWeapon == null) continue;

        local cn = activeWeapon.GetClassname();
        // If holding a pistol and has a primary weapon, switch back
        if (cn == "weapon_pistol" || cn == "weapon_pistol_magnum")
        {
            local inv = {};
            GetInvTable(bot, inv);
            if ("slot0" in inv && inv.slot0 != null)
            {
                // Only switch if primary has some ammo or we don't care (since we refill ammo anyway)
                bot.SwitchToItem(inv.slot0);
            }
        }
    }
}



function VBI_RunAI()
{
    VBI_UpdateThreat();

    foreach (bot in VBI_GetBots())
    {
        local scope = null;
        if (bot.ValidateScriptScope())
            scope = bot.GetScriptScope();

        // FIX: Priority 1 — rescue a grabbed/pinned teammate immediately
        local grabInfo = VBI_FindGrabbedTeammate(bot);
        if (grabInfo != null)
        {
            if (scope != null) scope["vbi_rescuing"] <- true;

            if (grabInfo.grabber != null && grabInfo.grabber.IsAlive())
            {
                // Shove if close enough to help peel faster (Anti-Jockey/Hunter)
                if (VBI_Dist(bot.GetOrigin(), grabInfo.victim.GetOrigin()) < 120.0)
                    ForcedButton(bot, ShoveButton);

                VBI_Attack(bot, grabInfo.grabber);
            }
            else
            {
                VBI_Move(bot, grabInfo.victim.GetOrigin());
            }
            continue;
        }
        else
        {
            if (scope != null) scope["vbi_rescuing"] <- false;
        }

        // Priority 2 — Tactical Shoving
        // Shove visible enemies in melee range
        local ent = null;
        local shoved = false;
        while ((ent = Entities.FindInSphere(ent, bot.GetOrigin(), 120)) != null)
        {
            if (ent.GetClassname() == "player" && VBI_IsEnemy(ent) && VBI_CanSee(bot, ent))
            {
                ForcedButton(bot, ShoveButton);
                shoved = true;
                break;
            }
        }
        if (!shoved)
        {
            ReleaseForcedButton(bot, ShoveButton);
        }

        // Priority 3 — per-bot distance-weighted threat
        // FIX: Each bot picks its own nearest threat, not the global one
        local threat = VBI_FindThreatForBot(bot);
        if (threat != null && threat.IsAlive())
        {
            VBI_Attack(bot, threat);
            continue;
        }

        // Priority 3 — positioning / follow
        VBI_Position(bot);
    }

    // Run ammo refill and primary weapon enforcer for all bots every think tick
    IHateYouEllis();
    foreach (bot in VBI_GetBots())
    {
        // Enforce no snipers
        local inv = {};
        GetInvTable(bot, inv);
        if ("slot0" in inv && inv.slot0 != null)
        {
            local cn = inv.slot0.GetClassname();
            if (cn.find("sniper") != null || cn.find("hunting_rifle") != null)
            {
                inv.slot0.Kill();
                bot.GiveItem("weapon_rifle");
            }
        }
        VBI_CheckAmmo(bot);
    }
}



//////////////////////////////////////////////////
// LOOP
//////////////////////////////////////////////////

function VBI_Think()
{
    local now = Time();
    if (now - VBI_STATE.lastThink < VBI_CFG.think_interval) return;
    VBI_STATE.lastThink = now;

    // Tick per-bot grenade fire timers every frame so throws complete cleanly
    VBI_TickGrenadeFireButtons();

    // Run grenadier logic in the same tick as the main AI so they're coordinated
    GrenadierBotsScript();

    VBI_RunAI();
}

function Think()
{
    VBI_Think();
    return VBI_CFG.think_interval;
}

function OnGameEvent_player_spawn(event)
{
    local p = GetPlayerFromUserID(event.userid);
    if (VBI_IsBot(p))
    {
        VBI_AttachDamageHook(p);
    }
}

// Initial hook attachment for bots already in game
foreach (bot in VBI_GetBots())
{
    VBI_AttachDamageHook(bot);
}

__CollectEventCallbacks(this, "OnGameEvent_", "GameEventCallbacks", 0);

printl("[VBI] Advanced AI v2 Loaded");
