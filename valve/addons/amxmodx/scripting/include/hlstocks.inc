/*
* AMX mod X functions for Half-Life
*
* Supported AMX Mod X versions: 1.9 or newer
*
* Version 1.1 (date: 29.07.2010) Author: Kord
* Version 1.2 (date: 02.10.2013) Author: Kord
* Version 1.3 (date: 22.12.2018) Author: rtxa
*  - Now AMXX 1.9 is required to use this include.
*  - Now offsets are retrieved from gamedata instead of hardcoding them inside plugin (AMXX 1.9 feature).
*  - Added send of Spectator msg in hl_set_user_spectator(). Fixes wrong colors in scoreboard for some clients.
*  - Added HL_MAX_TEAMNAME_LENGTH constant.
*  - Added hl_[g|s]et_user_frags().
* Version 1.4 (date: 02.02.2019) Author: rtxa
*  - Renamed hl.inc to hlstocks.inc to differentiate from original.
*
* http://aghl.ru/forum/ - Russian Half-Life and Adrenaline Gamer Community
*
*/

#if defined _hlstocks_included
#endinput
#endif
#define _hlstocks_included

#include <amxmodx>
#include <fakemeta>

#define HL_MAX_TEAMS			10
#define HL_MAX_TEAMNAME_LENGTH 	16

stock static teams[HL_MAX_TEAMS][HL_MAX_TEAMNAME_LENGTH];

static const _HLW_to_rgAmmoIdx[] =
{
	0, 	// none
	0,	// crowbar
	2, 	// 9mmhandgun
	4, 	// 357
	2, 	// 9mmAR
	3, 	// m203
	7, 	// crossbow
	1, 	// shotgun
	6, 	// rpg
	5, 	// gauss
	5, 	// egon
	12,	// hornetgun
	10, // handgrenade
	8, 	// tripmine
	9, 	// satchel
	11  // snark
};

/* Returns player frags.
*/
stock hl_get_user_frags(id)
{
	return pev(id, pev_frags, frags);
}

/* Sets player frags.
*/
stock hl_set_user_frags(id, frags)
{
	static ScoreInfo;

	if (!ScoreInfo)
		ScoreInfo = get_user_msgid("ScoreInfo");

	set_pev(id, pev_frags, frags);

	message_begin(MSG_BROADCAST, ScoreInfo);
	write_byte(id);
	write_short(frags);
	write_short(hl_get_user_deaths(id));
	write_short(0);
	write_short(hl_get_user_team(id));
	message_end();
}

/* Returns player deaths.
*/
stock hl_get_user_deaths(client)
{
	return get_ent_data(client, "CBasePlayer", "m_iDeaths");
}

/* Sets player deaths.
*/
stock hl_set_user_deaths(client, deaths)
{
	set_ent_data(client, "CBasePlayer", "m_iDeaths", deaths);

	static ScoreInfo;
	if (ScoreInfo || (ScoreInfo = get_user_msgid("ScoreInfo")))
	{
		message_begin(MSG_BROADCAST, ScoreInfo);
		write_byte(client);
		write_short(get_user_frags(client));
		write_short(deaths);
		write_short(0);
		write_short(hl_get_user_team(client));
		message_end();
	}
}

/* Get amount of ammo in backpack on a user for a specific weapon.
* Look in hlsdk_const.inc for weapon types: HLW_*.
* Weapons on the same line uses the same ammo type:
* shotgun
* mp5, glock
* argrenade
* python
* gauss, egon
* rpg
* crossbow
* tripmine
* satchel
* handgrenade
* snark
* hornet
*/
stock hl_get_user_bpammo(client, weapon)
{
	return get_ent_data(client, "CBasePlayer", "m_rgAmmo", _HLW_to_rgAmmoIdx[weapon]);
}

/* Restock/remove ammo in a user's backpack.
*/
stock hl_set_user_bpammo(client, weapon, ammo)
{
	if (weapon <= HLW_CROWBAR)
		return;

	set_ent_data(client, "CBasePlayer", "m_rgAmmo", _HLW_to_rgAmmoIdx[weapon], ammo);
}

/* Get user model.
*/
stock hl_get_user_model(client, model[], len)
{
	get_user_info(client, "model", model, len);
}

/* Set user model.
*/
stock hl_set_user_model(client, const model[])
{
	set_user_info(client, "model", model);
}

/* Returns health value.
*/
stock hl_get_user_health(client)
{
	static Float:healthvalue;
	pev(client, pev_health, healthvalue);
	return floatround(healthvalue);
}

/* Sets player health.
*/
stock hl_set_user_health(client, health)
{
	health > 0 ? set_pev(client, pev_health, float(health)) : dllfunc(DLLFunc_ClientKill, client);

	return 1;
}

/* Returns armor value.
*/
stock hl_get_user_armor(client)
{
	static Float:armorvalue;
	pev(client, pev_armorvalue, armorvalue);
	return floatround(armorvalue);
}

/* Sets player armor.
*/
stock hl_set_user_armor(client, armorvalue)
{
	set_pev(client, pev_armorvalue, float(armorvalue));
}

/* Returns team id. When length is greater then 0 then a name of team is set.
 * @note: player must be connected, if not, this will not work
*/
stock hl_get_user_team(client, team[] = "", len = 0)
{
	if (hl_get_user_spectator(client))
		return 0;

	static Float:tdm;
	global_get(glb_teamplay, tdm);
	if (tdm < 1.0) return 0;

	if (!len) len = HL_MAX_TEAMNAME_LENGTH;
	get_user_info(client, "model", team, len);

	return __get_team_index(team);
}

/* Set player team by teamname.
*/
stock hl_set_user_team(client, const team[])
{
	static Float:tdm;
	global_get(glb_teamplay, tdm);
	if (tdm < 1.0) return 0;

	static teamid;
	teamid = __get_team_index(team);
	if (teamid == -1) return 0;

	hl_set_user_spectator(client, false);

	engfunc(EngFunc_SetClientKeyValue, client, engfunc(EngFunc_GetInfoKeyBuffer, client), "model", team);
	engfunc(EngFunc_SetClientKeyValue, client, engfunc(EngFunc_GetInfoKeyBuffer, client), "team", team);

	static TeamInfo;
	if (TeamInfo || (TeamInfo = get_user_msgid("TeamInfo")))
	{
		message_begin(MSG_ALL, TeamInfo);
		write_byte(client);
		write_string(team);
		message_end();
	}

	static ScoreInfo;
	if (ScoreInfo || (ScoreInfo = get_user_msgid("ScoreInfo")))
	{
		message_begin(MSG_ALL, ScoreInfo);
		write_byte(client);
		write_short(get_user_frags(client));
		write_short(hl_get_user_deaths(client));
		write_short(0);
		write_short(teamid);
		message_end();
	}

	return 1;
}

stock __get_team_index(const team[])
{
	static teamid;
	teamid = 0;
	static valid;
	valid = 0;
	static i;
	i = 0;

	__count_teams();

	for (i = 0; i < sizeof(teams); i++)
	{
		teamid++;
		if (equali(teams[i][0], team))
		{
			valid = 1;
			break;
		}
	}

	if (valid)
		return teamid;

	return 0;
}

stock __count_teams()
{
	if (!teams[0][0])
	{
		new teamlist[50];
		get_pcvar_string(get_cvar_pointer("mp_teamlist"), teamlist, charsmax(teamlist));
		trim(teamlist);
		__explode_teamlist(teams, charsmax(teams[]), teamlist, ';');
	}

	static teamcount;

	if (!teamcount)
	{
		for (new i = 0; i < sizeof(teams); i++)
		{
			if (teams[i][0])
				teamcount++;
		}
	}

	return teamcount;
}

stock __explode_teamlist(output[][], size, input[], delimiter)
{
	new nIdx = 0, l = strlen(input);
	new nLen = (1 + copyc(output[nIdx], size, input, delimiter));

	while ((nLen < l) && (++nIdx < HL_MAX_TEAMS))
		nLen += (1 + copyc(output[nIdx], size, input[nLen], delimiter));
}

/* Returns entity index of active weapon.
*/
stock hl_get_user_weapon_ent(client)
{
	return get_ent_data_entity(client, "CBasePlayer", "m_pActiveItem");
}

/* Returns amount of ammo in weapon's clip.
*/
stock hl_get_weapon_ammo(entity)
{
	return get_ent_data(entity, "CBasePlayerWeapon", "m_iClip");
}

/* Set amount of ammo in weapon's clip.
*/
stock hl_set_weapon_ammo(entity, clip)
{
	set_ent_data(entity, "CBasePlayerWeapon", "m_iClip", clip);
}

/* Get weapon type. Corresponds to HLW_* in hlsdk_const.inc: 1 is HLW_CROWBAR, 2 is HLW_GLOCK and so on...
*/
stock hl_get_weapon_id(entity)
{
	return get_ent_data(entity, "CBasePlayerItem", "m_iId");
}

/* Returns weapon entity index from weaponbox.
*/
stock hl_get_wbox_weapon_ent(entity)
{
	static wpn_entity;
	for (new i = 1; i < 6; i++)
	{
		wpn_entity = get_ent_data_entity(entity, "CWeaponBox", "m_rgpPlayerItems", i);
		if (wpn_entity > 0)
		{
			break;
		}
	}

	return wpn_entity;
}

/* Returns amount of ammo in weaponbox.
*/
stock hl_get_wbox_ammo(entity)
{
	return get_ent_data(entity, "CWeaponBox", "m_rgAmmo", 1);
}

/* Set amount of ammo in weaponbox.
*/
stock hl_set_wbox_ammo(entity, ammo)
{
	set_ent_data(entity, "CWeaponBox", "m_rgAmmo", ammo, 1);
}

/* Spawns a Half-Life player.
*/
stock hl_user_spawn(client)
{
	if (!hl_strip_user_weapons(client))
		return;

	set_pev(client, pev_deadflag, DEAD_RESPAWNABLE);
	dllfunc(DLLFunc_Spawn, client);
}

/* Strips all weapons from player.
*/
stock hl_strip_user_weapons(client)
{
	new ent = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "player_weaponstrip"));
	if (!pev_valid(ent))
		return 0;

	dllfunc(DLLFunc_Spawn, ent);
	dllfunc(DLLFunc_Use, ent, client);
	engfunc(EngFunc_RemoveEntity, ent);

	return 1;
}

/* Check if player in spectator mode.
*/
stock bool:hl_get_user_spectator(client)
{
	if (pev(client, pev_iuser1) || pev(client, pev_iuser2))
		return true;

	return false;
}

/* Switch player to spectator mode.
*/
stock hl_set_user_spectator(client, bool:spectator = true)
{
	if (hl_get_user_spectator(client) == spectator)
		return;

	if (spectator)
	{
		static AllowSpectatorsCvar;
		if (AllowSpectatorsCvar || (AllowSpectatorsCvar = get_cvar_pointer("allow_spectators")))
		{
			if (!get_pcvar_num(AllowSpectatorsCvar))
				set_pcvar_num(AllowSpectatorsCvar, 1);

			engclient_cmd(client, "spectate");
		}
	}
	else
	{
		hl_user_spawn(client);

		set_pev(client, pev_iuser1, 0);
		set_pev(client, pev_iuser2, 0);

		set_ent_data(client, "CBasePlayer", "m_iHideHUD", 0);

		static szTeam[HL_MAX_TEAMNAME_LENGTH];
		hl_get_user_team(client, szTeam, charsmax(szTeam));

		// this fix when using openag client the scoreboard user colors
		static Spectator;
		if (Spectator || (Spectator = get_user_msgid("Spectator"))) {
			message_begin(MSG_ALL, Spectator);
			write_byte(client);
			write_byte(0);
			message_end();
		}

		static TeamInfo;
		if (TeamInfo || (TeamInfo = get_user_msgid("TeamInfo")))
		{
			message_begin(MSG_ALL, TeamInfo);
			write_byte(client);
			write_string(szTeam);
			message_end();
		}
	}
}

/* Check if player have longjump module.
*/
stock bool:hl_get_user_longjump(client)
{
	new value[2];
	engfunc(EngFunc_GetPhysicsKeyValue, client, "slj", value, 1);
	switch (value[0])
	{
	case '1': return true;
	}

	return false;
}

/* Set longjump module to player.
*/
stock hl_set_user_longjump(client, bool:longjump = true, bool:tempicon = true)
{
	if (longjump == hl_get_user_longjump(client))
		return;

	if (longjump)
	{
		engfunc(EngFunc_SetPhysicsKeyValue, client, "slj", "1");

		if (tempicon)
		{
			static msgid_itempickup;
			if (!msgid_itempickup)
				msgid_itempickup = get_user_msgid("ItemPickup");

			message_begin(MSG_ONE, msgid_itempickup, _, client);
			write_string("item_longjump");
			message_end();
		}
	}
	else
		engfunc(EngFunc_SetPhysicsKeyValue, client, "slj", "0");

	set_ent_data(client, "CBasePlayer", "m_fLongJump", longjump);
}
