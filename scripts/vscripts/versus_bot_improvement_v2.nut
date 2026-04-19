Msg("===================================\n");
Msg(" Versus Bot Improvement v2 (Advanced)\n");
Msg("===================================\n");

GrenadierBots <- 1          // Default ON — set to 0 in cfg to disable
MobSizeToThrowGrenade <- 4  // Lowered from 6; versus has smaller hordes
UsePipeBomb <- 3            // 3 = commons + tank
UseMolotov <- 3             // 3 = commons + tank (was 2 = tank only, which skipped commons)
UseVomitjar <- 3            // 3 = commons + tank
GrenadeThrowCooldown <- 0   // Legacy global fallback; per-bot timers now preferred
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
    follow_distance         = 300.0,
    spread_distance         = 120.0,
    max_follow_distance     = 500.0,
    rescue_check_interval   = 0.15,   // FIX: faster rescue polling
    grenade_lock_duration   = 1.5,    // FIX: how long a bot stays in grenade mode
    ammo_refill_threshold   = 30,     // Refill reserve ammo when it drops below this
    ammo_refill_amount      = 200,    // How much reserve ammo to restore
    // Damage reduction for hazards bots are slow to react to.
    // 1.0 = full damage (vanilla), 0.0 = no damage, 0.25 = 25% of normal damage.
    fire_damage_scale       = 0.25,   // Molotov / burning tank swipe fire
    spit_damage_scale       = 0.25,   // Spitter acid pool
    // Per-bot grenade throw cooldown in seconds
    grenade_throw_cooldown  = 15.0,   // Min seconds between throws per bot
    // Proximity radius to count nearby commons when deciding to throw
    grenade_mob_radius      = 250.0,  // Units around bot to count common infected
    // How close a tank/common must be before a bot will throw at it
    grenade_throw_range     = 600.0,
    debug                   = false
};

// FIX: Wire VBI_USER_SETTINGS into VBI_CFG on load
// VBI_USER_SETTINGS is defined in versus_bot_improvement_settings.nut
if ("VBI_USER_SETTINGS" in getroottable())
{
    foreach (key, val in VBI_USER_SETTINGS)
    {
        if (key in VBI_CFG)
            VBI_CFG[key] = val;
        // Engine convar overrides
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

//////////////////////////////////////////////////
// BASIC HELPERS
//////////////////////////////////////////////////

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

//////////////////////////////////////////////////
// THREAT SYSTEM — PER-BOT DISTANCE-WEIGHTED
//////////////////////////////////////////////////

function VBI_IsEnemy(ent)
{
    return ent != null && ent.GetTeam() == 3 && ent.IsAlive();
}

// FIX: Returns base threat score — distance weighting applied per-bot in VBI_FindThreatForBot
function VBI_GetThreatScore(e)
{
    local t = e.GetZombieType();
    if (t == ZOMBIE_TANK)    return 200;
    if (t == ZOMBIE_SMOKER)  return 100;
    if (t == ZOMBIE_HUNTER)  return 95;
    if (t == ZOMBIE_JOCKEY)  return 90;
    if (t == ZOMBIE_CHARGER) return 85;
    if (t == ZOMBIE_SPITTER) return 80;
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

// FIX: Kept for backwards-compat / grenadier system; bots now use VBI_FindThreatForBot
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

//////////////////////////////////////////////////
// GRAB / INCAP RESCUE DETECTION  (NEW)
//////////////////////////////////////////////////

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
        while ((hunter = Entities.FindByClassnameWithin(hunter, "player", p.GetOrigin(), 120)) != null)
            if (hunter.GetZombieType() == ZOMBIE_HUNTER && hunter.IsAlive())
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
        while ((hunter = Entities.FindByClassnameWithin(hunter, "player", p.GetOrigin(), 120)) != null)
            if (hunter.GetZombieType() == ZOMBIE_HUNTER && hunter.IsAlive())
                return hunter;
    }

    return null;
}

// FIX: Find any grabbed teammate. Returns { victim, grabber } or null.
function VBI_FindGrabbedTeammate(bot)
{
    foreach (p in VBI_GetAll())
    {
        if (!VBI_IsSurvivor(p)) continue;
        if (p == bot) continue;
        if (!VBI_IsGrabbed(p)) continue;

        local grabber = VBI_GetGrabber(p);
        return { victim = p, grabber = grabber };
    }
    return null;
}

//////////////////////////////////////////////////
// COMMAND SYSTEM
//////////////////////////////////////////////////

function VBI_Attack(bot, target)
{
    CommandABot({ bot = bot, cmd = DirectorScript.BOT_CMD_ATTACK, target = target });
}

function VBI_Move(bot, pos)
{
    CommandABot({ bot = bot, cmd = DirectorScript.BOT_CMD_MOVE, pos = pos });
}

function VBI_Reset(bot)
{
    CommandABot({ bot = bot, cmd = DirectorScript.BOT_CMD_RESET });
}

//////////////////////////////////////////////////
// POSITIONING SYSTEM
//////////////////////////////////////////////////

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

    // FIX: Full-bot team fallback — anchor to nearest alive bot
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

//////////////////////////////////////////////////
// GRENADE SYSTEM (preserved, bug fixes applied)
//////////////////////////////////////////////////

function MercilessToggleFileCheck(filename)
{
    local files = FileToString(filename);
    if (!files) return false;
    return true;
}

function GenerateGrenadeThrowFile()
{
    local DefaultToggleFile = "";
    local CfgToggleFile =
    [
        "GrenadierBots 1",
        "MobSizeToThrowGrenade 4",
        "UsePipeBomb 3",
        "UseMolotov 3",
        "UseVomitjar 3",
        "GrenadeAutoGive 1",
        ".",
        ".",
        "// ====== TOGGLE SETTING INFO ======",
        "//GrenadierBots= 0=Off (Default L4D2). 1=On, bots will pick & use grenades.",
        "//MobSizeToThrowGrenade= Min common infected count before bots throw. Default 6.",
        "//UsePipeBomb= 0=Off. 1=commons only. 2=tank only. 3=both.",
        "//UseMolotov=  0=Off. 1=commons only. 2=tank (not burning). 3=both.",
        "//UseVomitjar= 0=Off. 1=commons only. 2=tank (not burning). 3=both.",
        "//GrenadeAutoGive= 1=bots give grenade to player they face who has none.",
        ".",
        "// =================================",
        "//Notes: Delete file to regenerate defaults.",
        "."
    ];

    foreach (line in CfgToggleFile)
        DefaultToggleFile = DefaultToggleFile + line + "\n";

    if (!MercilessToggleFileCheck("bots throw grenades cfg/bots throw grenades.txt"))
    {
        StringToFile("bots throw grenades cfg/bots throw grenades.txt", DefaultToggleFile);
        printl("The 'bots throw grenades.txt' file can't be found. Generating new file...");
    }
}

// FIX: Rewrote config loader — the original had a misplaced else that set
// trigger=1 for every key that wasn't MobSizeToThrowGrenade (the else was
// attached to the innermost if, not the outer if/else-if chain).
function LoadSpecificConfigFile(filename)
{
    local files = FileToString(filename);
    if (!files) return 0;

    local toggles = split(files, "\r\n");
    foreach (toggle in toggles)
    {
        if (!toggle || toggle == "") continue;
        toggle = strip(toggle);

        // Skip comments and section markers
        if (toggle.find("//") == 0) continue;
        if (toggle.find("===") != null) continue;
        if (toggle == ".") continue;

        local idx = toggle.find(" ");
        if (idx == null) continue;

        local cmd = toggle.slice(0, idx);
        local val = toggle.slice(idx + 1);

        // FIX: Each branch is now independent — no dangling else
        if      (cmd == "GrenadierBots")         GrenadierBots         = val.tointeger();
        else if (cmd == "MobSizeToThrowGrenade") MobSizeToThrowGrenade = val.tointeger();
        else if (cmd == "UsePipeBomb")           UsePipeBomb           = val.tointeger();
        else if (cmd == "UseMolotov")            UseMolotov            = val.tointeger();
        else if (cmd == "UseVomitjar")           UseVomitjar           = val.tointeger();
        else if (cmd == "GrenadeAutoGive")       GrenadeAutoGive       = val.tointeger();
    }

    return 1;
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
        // Only reduce damage for bots — human survivors get vanilla damage
        if (!IsPlayerABot(self)) return;

        local dtype = params.damage_type;

        if (dtype & DMG_BURN)
        {
            params.damage = params.damage * ::VBI_CFG.fire_damage_scale;
            return;
        }

        if (dtype & DMG_POISON)
        {
            params.damage = params.damage * ::VBI_CFG.spit_damage_scale;
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

function OnGameEvent_player_spawn(event)
{
    local kent = GetPlayerFromUserID(event.userid);
    if (!kent.IsSurvivor()) return;
    if (!kent.ValidateScriptScope()) return;

    local scope = kent.GetScriptScope();
    if (!("kuro_grenadier_bots" in scope) || scope.kuro_grenadier_bots != 6)
        scope["kuro_grenadier_bots"] <- 6;

    // Attach fire/acid damage reduction hook to bots on spawn
    if (IsPlayerABot(kent))
        VBI_AttachDamageHook(kent);
}

function OnGameEvent_weapon_fire(event)
{
    local kent = GetPlayerFromUserID(event.userid);
    if (!kent.IsSurvivor()) return;
    if (GrenadierBots == 0) return;

    local active = GetActiveMainWeapon(kent);
    if (active != "weapon_vomitjar" && active != "weapon_molotov" && active != "weapon_pipe_bomb")
        return;

    GrenadeThrowCooldown = Time();

    local survteam = null;
    while (survteam = Entities.FindByClassname(survteam, "player"))
    {
        if (!survteam.IsSurvivor() || !IsPlayerABot(survteam) || survteam == kent) continue;
        if (GetActiveMainWeapon(survteam) == GetThrowableSlot(survteam))
            if (GetSecondarySlot(survteam) != null)
                survteam.SwitchToItem(GetSecondarySlot(survteam));
    }
    ReleaseForcedButton(kent, FireButton);
}

function OnGameEvent_player_shoved(event)
{
    if (GrenadierBots == 0) return;

    local shovetarget = GetPlayerFromUserID(event.userid);
    local kent        = GetPlayerFromUserID(event.attacker);

    if (!kent.IsSurvivor() || !shovetarget.IsSurvivor()) return;

    if (!IsPlayerABot(kent) && IsPlayerABot(shovetarget))
    {
        if (GetThrowableSlot(kent) == null)
        {
            local thr = GetThrowableSlot(shovetarget);
            if (thr != null)
            {
                shovetarget.DropItem(thr);
                local pickname = thr.slice(0, thr.len() - 1); // trim last char for PickItem
                PickItem(kent, pickname, 150);
            }
        }
    }

    if (IsPlayerABot(shovetarget))
    {
        for (local grenadenearby; grenadenearby = Entities.FindByClassnameWithin(
                grenadenearby, "weapon_*", shovetarget.GetOrigin(), 150); )
        {
            if (grenadenearby.GetOwnerEntity() != null) continue;
            local cn = grenadenearby.GetClassname();
            if (UseVomitjar > 0 && cn.find("weapon_vomitja") != null)
                DoEntFire("!self", "Use", "", 0.1, shovetarget, grenadenearby);
            if (UseMolotov > 0 && cn.find("weapon_moloto") != null)
                DoEntFire("!self", "Use", "", 0.1, shovetarget, grenadenearby);
            if (UsePipeBomb > 0 && cn.find("weapon_pipe_bo") != null)
                DoEntFire("!self", "Use", "", 0.1, shovetarget, grenadenearby);
        }
        ReleaseForcedButton(shovetarget, FireButton);
    }
}

function OnGameEvent_weapon_drop(event)
{
    if (!("userid" in event)) return;
    local kent = GetPlayerFromUserID(event.userid);
    if (!IsPlayerABot(kent)) return;
    if (!kent.ValidateScriptScope()) return;

    local entity = null;
    if ("propid" in event) entity = EntIndexToHScript(event.propid);
    if (!IsAvailableEntity(entity)) return;

    local cn = entity.GetClassname();
    if (cn.find("weapon_moloto") != null || cn.find("weapon_pipe_bo") != null || cn.find("weapon_vomitja") != null)
    {
        local scope = kent.GetScriptScope();
        if ("grenadier_bots_pick_timer" in scope)
            scope.grenadier_bots_pick_timer = Time();
    }
}

function OnGameEvent_weapon_reload(event)
{
    local kent = GetPlayerFromUserID(event.userid);
    if (!kent.IsSurvivor()) return;

    if (!IsPlayerABot(kent))
    {
        if (!MercilessToggleFileCheck("bots throw grenades cfg/bots throw grenades.txt"))
            GenerateGrenadeThrowFile();
        LoadSpecificConfigFile("bots throw grenades cfg/bots throw grenades.txt");
    }
    else
    {
        ReleaseForcedButton(kent, FireButton);
    }
}

function OnGameEvent_round_start_post_nav(event)
{
    printl("The 'BOTS THROW GRENADES' mod is launched.");
    if (!MercilessToggleFileCheck("bots throw grenades cfg/bots throw grenades.txt"))
        GenerateGrenadeThrowFile();
    LoadSpecificConfigFile("bots throw grenades cfg/bots throw grenades.txt");

    // Attach damage hooks to any bots already in the server at round start
    foreach (bot in VBI_GetBots())
        VBI_AttachDamageHook(bot);
}

function IsLookingAtTarget(kent, classname)
{
    local traceEndpoint = kent.EyePosition() + VectorFromQAngle(kent.EyeAngles(), 666666);
    local traceTable = { start = kent.EyePosition(), end = traceEndpoint, ignore = kent };
    if (!TraceLine(traceTable)) return false;
    if (!("enthit" in traceTable)) return false;

    local hit = traceTable.enthit;
    if (classname == "tank")
        return hit.GetClassname() == "player" && hit.GetZombieType() == ZOMBIE_TANK;
    else if (classname == "special")
        return hit.GetClassname() == "player" && hit.GetZombieType() < 7;
    else if (classname == "survplayer")
        return hit.GetClassname() == "player" && hit.GetZombieType() == ZOMBIE_SURVIVOR;
    else
        return hit.GetClassname() == classname && hit.GetHealth() > 0;
}

function GiveGrenade(kent)
{
    local traceEndpoint = kent.EyePosition() + VectorFromQAngle(kent.EyeAngles(), 666666);
    local traceTable = { start = kent.EyePosition(), end = traceEndpoint, ignore = kent };
    if (!TraceLine(traceTable)) return;
    if (!("enthit" in traceTable)) return;

    local hit = traceTable.enthit;
    if (!kent.IsSurvivor() || hit.GetClassname() != "player") return;
    if (!hit.IsSurvivor() || IsPlayerABot(hit) || hit.IsDead()) return;
    if (GetThrowableSlot(kent) == null || GetThrowableSlot(hit) != null) return;
    if ((kent.GetOrigin() - hit.GetOrigin()).Length() > 150) return;

    hit.GiveItem(GetThrowableSlot(kent));
    EmitSoundOnClient("Hint.LittleReward", hit);
    GetThrowableRemoved(kent);
}

function GetCommonZombieWithin(player, range)
{
    local table = {};
    local i = -1;
    local entzom = null;
    while (entzom = Entities.FindByClassnameWithin(entzom, "infected", player.GetOrigin(), range))
        if (entzom.GetHealth() > 0)
            table[++i] <- entzom;
    return table;
}

function GetTankThreatWithin(player, range)
{
    local entzom = null;
    while (entzom = Entities.FindByClassnameWithin(entzom, "player", player.GetOrigin(), range))
        if (entzom.GetZombieType() == ZOMBIE_TANK && !entzom.IsDead() && !entzom.IsDying())
            return true;
    return false;
}

function PickItem(kent, classname, range)
{
    for (local grenadenearby; grenadenearby = Entities.FindByClassname(grenadenearby, "weapon_*"); )
    {
        if (grenadenearby.GetClassname().find(classname) == null) continue;
        if (grenadenearby.GetOwnerEntity() != null) continue;
        if ((kent.GetOrigin() - grenadenearby.GetOrigin()).Length() <= range)
            DoEntFire("!self", "Use", "", 0, kent, grenadenearby);
    }
}

// Returns true if bot is off per-bot throw cooldown and ready to throw
function VBI_BotCanThrow(bot)
{
    if (!bot.ValidateScriptScope()) return false;
    local scope = bot.GetScriptScope();
    if (!("vbi_last_throw" in scope)) return true;
    return Time() >= scope.vbi_last_throw + VBI_CFG.grenade_throw_cooldown;
}

function VBI_RecordThrow(bot)
{
    if (!bot.ValidateScriptScope()) return;
    bot.GetScriptScope()["vbi_last_throw"] <- Time();
}

// Proximity-based grenade throw: no raycast required.
// Checks what enemies are near the bot and decides whether to throw.
// Returns true if a throw was initiated.
function VBI_TryThrowGrenade(bot)
{
    local slot = GetThrowableSlot(bot);
    if (slot == null) return false;
    if (!VBI_BotCanThrow(bot)) return false;

    local botPos    = bot.GetOrigin();
    local range     = VBI_CFG.grenade_throw_range;
    local mobRadius = VBI_CFG.grenade_mob_radius;

    // Count common infected nearby
    local commonCount = 0;
    local nearestCommon = null;
    local nearestCommonDist = 999999;
    local ent = null;
    while ((ent = Entities.FindByClassnameWithin(ent, "infected", botPos, range)) != null)
    {
        if (ent.GetHealth() <= 0) continue;
        commonCount++;
        local d = VBI_Dist(botPos, ent.GetOrigin());
        if (d < nearestCommonDist) { nearestCommonDist = d; nearestCommon = ent; }
    }

    // Find a nearby tank
    local nearestTank = null;
    local nearestTankDist = 999999;
    local p = null;
    while ((p = Entities.FindByClassnameWithin(p, "player", botPos, range)) != null)
    {
        if (p.GetZombieType() != ZOMBIE_TANK) continue;
        if (p.IsDead() || p.IsDying()) continue;
        local d = VBI_Dist(botPos, p.GetOrigin());
        if (d < nearestTankDist) { nearestTankDist = d; nearestTank = p; }
    }

    local shouldThrow = false;
    local target      = null;

    if (slot == "weapon_pipe_bomb" && UsePipeBomb > 0)
    {
        // Pipe bomb: lure commons away or distract tank
        if (UsePipeBomb == 1 || UsePipeBomb >= 3)
            if (commonCount >= MobSizeToThrowGrenade && nearestCommon != null)
                { shouldThrow = true; target = nearestCommon; }

        if (UsePipeBomb == 2 || UsePipeBomb >= 3)
            if (nearestTank != null)
                { shouldThrow = true; target = nearestTank; }
    }
    else if (slot == "weapon_molotov" && UseMolotov > 0)
    {
        if (UseMolotov == 1 || UseMolotov >= 3)
            if (commonCount >= MobSizeToThrowGrenade && nearestCommon != null)
                { shouldThrow = true; target = nearestCommon; }

        if (UseMolotov == 2 || UseMolotov >= 3)
            if (nearestTank != null && !nearestTank.IsOnFire())
                { shouldThrow = true; target = nearestTank; }
    }
    else if (slot == "weapon_vomitjar" && UseVomitjar > 0)
    {
        if (UseVomitjar == 1 || UseVomitjar >= 3)
            if (commonCount >= MobSizeToThrowGrenade && nearestCommon != null)
                { shouldThrow = true; target = nearestCommon; }

        if (UseVomitjar == 2 || UseVomitjar >= 3)
            if (nearestTank != null)
                { shouldThrow = true; target = nearestTank; }
    }

    if (!shouldThrow || target == null) return false;

    // Switch to grenade and trigger throw via per-bot fire timer.
    // SwitchToItem requires an entity handle, not a classname string.
    local inv = {};
    GetInvTable(bot, inv);
    if (!("slot2" in inv) || inv.slot2 == null) return false;
    local grenadeEnt = inv.slot2;

    bot.SwitchToItem(grenadeEnt);
    VBI_BotFireGrenade(bot, 0.8);
    VBI_RecordThrow(bot);

    if (VBI_CFG.debug)
        printl("[VBI] " + bot.GetPlayerName() + " throwing " + slot
               + " at " + target.GetClassname());

    return true;
}

function GrenadierBotsScript()
{
    if (GrenadierBots < 1) return;

    for (local survbot; survbot = Entities.FindByClassname(survbot, "player"); )
    {
        if (!survbot.IsSurvivor()) continue;
        if (!IsPlayerABot(survbot) || !survbot.ValidateScriptScope()) continue;

        local scope = survbot.GetScriptScope();
        if (!("kuro_grenadier_bots" in scope) || scope.kuro_grenadier_bots != 6) continue;
        if (survbot.IsDead()) continue;

        // Skip grenade logic while rescuing a teammate
        if ("vbi_rescuing" in scope && scope.vbi_rescuing) continue;

        if (GetThrowableSlot(survbot) == null)
        {
            // Scan for the nearest unclaimed grenade on the map
            local bestGrenade = null;
            local bestDist    = 999999;

            local grenadenearby = null;
            while (grenadenearby = Entities.FindByClassname(grenadenearby, "weapon_*"))
            {
                local cn = grenadenearby.GetClassname();
                if (cn.find("weapon_vomitja") == null
                    && cn.find("weapon_moloto") == null
                    && cn.find("weapon_pipe_bo") == null) continue;

                // Skip grenades already owned by someone
                if (grenadenearby.GetOwnerEntity() != null) continue;

                // Skip types that are disabled in config
                if (cn.find("weapon_vomitja") != null && UseVomitjar == 0) continue;
                if (cn.find("weapon_moloto")  != null && UseMolotov  == 0) continue;
                if (cn.find("weapon_pipe_bo") != null && UsePipeBomb == 0) continue;

                local d = (survbot.GetOrigin() - grenadenearby.GetOrigin()).Length();
                if (d < bestDist) { bestDist = d; bestGrenade = grenadenearby; }
            }

            if (bestGrenade != null)
            {
                if (bestDist <= 80)
                {
                    // Bot is on top of it — give directly, no timer needed
                    survbot.GiveItem(bestGrenade.GetClassname());

                    // Remove the world entity to avoid a duplicate
                    bestGrenade.Kill();

                    if (VBI_CFG.debug)
                        printl("[VBI] " + survbot.GetPlayerName()
                               + " picked up " + bestGrenade.GetClassname());
                }
                else if (bestDist <= 600)
                {
                    // Grenade is nearby — walk toward it
                    // Only move if not already busy rescuing or throwing
                    if (!("vbi_rescuing" in scope && scope.vbi_rescuing))
                        VBI_Move(survbot, bestGrenade.GetOrigin());
                }
                // Beyond 600u — don't divert the bot, let normal AI handle positioning
            }
        }
        else
        {
            // Bot has a grenade — offer it to a nearby human first
            if (GrenadeAutoGive > 0 && IsLookingAtTarget(survbot, "survplayer"))
            {
                GiveGrenade(survbot);
                continue;
            }

            // Try proximity-based throw
            VBI_TryThrowGrenade(survbot);
        }
    }
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
    "weapon_hunting_rifle",
    "weapon_sniper_military",
    "weapon_sniper_scout",
    "weapon_sniper_awp",
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

//////////////////////////////////////////////////
// MAIN AI — now with grab-rescue priority
//////////////////////////////////////////////////

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
                VBI_Attack(bot, grabInfo.grabber);
            else
                VBI_Move(bot, grabInfo.victim.GetOrigin());
            continue;
        }
        else
        {
            if (scope != null) scope["vbi_rescuing"] <- false;
        }

        // Priority 2 — per-bot distance-weighted threat
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
        VBI_CheckAmmo(bot);
}

//////////////////////////////////////////////////
// Primary Weapon Enforcer
/////////////////////////////////////////////////
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

printl("[VBI] Advanced AI v2 Loaded");
