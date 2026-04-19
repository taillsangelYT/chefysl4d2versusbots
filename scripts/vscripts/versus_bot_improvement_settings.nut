VBI_USER_SETTINGS <-
{
	// Script tuning
	follow_anchor_soft_distance = 225.0,
	catchup_distance = 650.0,
	rescue_search_distance = 1400.0,
	bile_grace_time = 1.5,
	boost_move_scale = 1.20,
	boost_temp_health = 8.0,
	grenade_search_distance = 300.0,
	grenade_pull_distance = 18.0,
	debug_enabled = true,
	debug_chat = true,
	debug_hud = true,
	debug_status_interval = 1.5,

	// Engine convars
	convar_overrides =
	{
		sb_friend_immobilized_reaction_time_vs = "0"
		sb_friend_immobilized_reaction_time_normal = "0"
		sb_friend_immobilized_reaction_time_hard = "0"
		sb_friend_immobilized_reaction_time_expert = "0"
		allow_all_bot_survivor_team = "1"
	}
}

Convars.SetValue("allow_all_bot_survivor_team", "1");
