IncludeScript("versus_bot_improvement_settings");
IncludeScript("versus_bot_improvement_v2");
if(!Entities.FindByName(null, "rf_dambots"))
	SpawnEntityFromTable("logic_timer", {targetname = "rf_dambots", vscripts = "rf_botprimary", RefireTime = 0.1, OnTimer = "!caller,runscriptcode,IHateYouEllis()"});
Msg("DONE!");