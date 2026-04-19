# Improved L4D2 Bots for Versus Gamemode

Highly improved Survivor bot AI specifically tuned for the competitive Versus environment.

### Key Features
- **Tactical Shoving:** Bots proactively shove Special Infected in melee range to peel for teammates and protect themselves.
- **Line-of-Sight Awareness:** Bots use visibility checks to target visible threats and ignore enemies hidden behind walls.
- **Prioritized Threat Assessment:** Smarter target selection prioritizing high-impact Versus threats like Boomers and Smokers.
- **Hazard Avoidance:** Bots recognize when they are taking damage from fire or Spitter acid and actively path toward safety.
- **Efficient Rescuing:** Prioritizes rescuing the closest immobilized teammate first.
- **Grenade Usage:** Bots can intelligently pick up and throw grenades (Pipe Bombs, Molotovs, Bile Jars).
- **Ammo Management:** Automatically keeps bot primary weapons topped up to prevent them from falling back to pistols mid-combat.
- **Damage Reduction:** Slight reduction in fire and acid damage for bots to compensate for AI pathing limitations.

### Technical Details
- Core logic is in `scripts/vscripts/versus_bot_improvement_v2.nut`.
- Configuration settings available in `scripts/vscripts/versus_bot_improvement_settings.nut`.
