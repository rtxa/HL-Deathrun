/*
* Half-Life Deathrun by rtxa
*
* To do:
*	Restart func_door_rotating, func_breakeable, etc...
*	Change values of weapons of game_player_equip to half life counterpart
*/

#include <amxmodx>
#include <amxmisc>
#include <hl>
#include <engine>
#include <fakemeta>
#include <hamsandwich>
#include <fun>

#pragma semicolon 1

#define PLUGIN 	"HL Deathrun"
#define VERSION "1.0"
#define AUTHOR 	"rtxa"

// TaskIDs
enum (+=100) {
	TASK_FIRSTROUND = 1000,
	TASK_ROUNDSTART,
	TASK_ROUNDEND,
	TASK_SENDTOSPEC,
	TASK_CHECKGAMESTATUS
};

// Armoury Entity Items
enum _:ArmouryIds{
    ARM_MP5,
    ARM_TMP,
    ARM_P90,
    ARM_MAC10,
    ARM_AK47,
    ARM_SG552,
    ARM_M4A1,
    ARM_AUG,
    ARM_SCOUT,
    ARM_G3SG1,
    ARM_AWP,
    ARM_M3,
    ARM_XM1014,
    ARM_M249,
    ARM_FLASHBANG,
    ARM_HEGRENADE,
    ARM_KEVLAR,
    ARM_ASSAULTSUIT,
    ARM_SMOKEGRENADE
}

new const CS_WEAPONS[][] = {
	"weapon_p228",
	"weapon_shield",
	"weapon_scout",
	"weapon_hegrenade",
	"weapon_xm1014",
	"weapon_c4",
	"weapon_mac10",
	"weapon_aug",
	"weapon_smokegrenade",
	"weapon_elite",
	"weapon_fiveseven",
	"weapon_ump45",
	"weapon_sg550",
	"weapon_galil",
	"weapon_famas",
	"weapon_usp",
	"weapon_glock18",
	"weapon_awp",
	"weapon_mp5navy",
	"weapon_m249",
	"weapon_m3",
	"weapon_m4a1",
	"weapon_tmp",
	"weapon_g3sg1",
	"weapon_flashbang",
	"weapon_deagle",
	"weapon_sg552",
	"weapon_ak47",
	"weapon_knife",
	"weapon_p90"
};

enum _:CsWeapons {
	CS_P228,
	CS_SHIELD,
	CS_SCOUT,
	CS_HEGRENADE,
	CS_XM1014,
	CS_C4,
	CS_MAC10,
	CS_AUG,
	CS_SMOKEGRENADE,
	CS_ELITE,
	CS_FIVESEVEN,
	CS_UMP45,
	CS_SG550,
	CS_GALIL,
	CS_FAMAS,
	CS_USP,
	CS_GLOCK18,
	CS_AWP,
	CS_MP5NAVY,
	CS_M249,
	CS_M3,
	CS_M4A1,
	CS_TMP,
	CS_G3SG1,
	CS_FLASHBANG,
	CS_DEAGLE,
	CS_SG552,
	CS_AK47,
	CS_KNIFE,
	CS_P90
}

new const gBlueWinsSnd[] = "deathrun/w_blue.wav";
new const gRedWinsSnd[] = "deathrun/w_red.wav";
new const gDrawSnd[] = "deathrun/3dmstart.wav";

#define DMG_CHANGETEAM 10000.0 // if you are not using Bugfixed and Improved HL Release by Lev, then set it to 900.0
#define DMG_SPAWN 300.0 // this is the dmg when user spawn close enough to other user

#define BLUE_TEAMID 1
#define RED_TEAMID 2

#define MAX_TEAMNAME_LENGTH 16

#define MAX_SPAWNS 64 // increase it in case the map has got more spawns...

new gBlueModel[MAX_TEAMNAME_LENGTH];
new gRedModel[MAX_TEAMNAME_LENGTH];

new gNumBlueTeam;
new gNumRedTeam;

new gBlueSpawns[MAX_SPAWNS];
new gNumBlueSpawns;

// game rules
new bool:gRoundStarted;

new gFirstRoundTime; // in seconds

// handle
new gMsgSayText;

public plugin_precache() {
	// i use this as parameter for change team
	GetTeamListModel(gBlueModel, gRedModel);

	new file[82];

	formatex(file, charsmax(file), "models/player/%s/%s.mdl", gBlueModel, gBlueModel);
	if (file_exists(file))
		precache_model(file);

	formatex(file, charsmax(file), "models/player/%s/%s.mdl", gRedModel, gRedModel);
	if (file_exists(file))
		precache_model(file);

	//precache_model("models/player/droid/droid.mdl");

	precache_sound(gBlueWinsSnd);
	precache_sound(gRedWinsSnd);
	precache_sound(gDrawSnd);

	create_cvar("dr_firstround_time", "15");
}

public plugin_init() {
	register_plugin(PLUGIN, VERSION, AUTHOR);

	if (get_cvar_num("mp_teamplay") <= 0) {
		server_print("* El servidor no esta en modo TDM");
		return PLUGIN_HANDLED;
	}

	// cache spawns of blue team
	GetInfoPlayerStart(gBlueSpawns, gNumBlueSpawns);

	if (gNumBlueSpawns <= 0) {
		server_print("Este mapa no es valido");
		return PLUGIN_HANDLED;
	}

	SetPlayerEquip();

	RegisterHam(Ham_TakeDamage, "player", "PlayerPreTakeDamage");
	RegisterHam(Ham_Spawn, "player", "PlayerSpawn");
	RegisterHam(Ham_Killed, "player", "PlayerKilled");

	register_forward(FM_ClientKill, "FwClientKill"); // block kill command

	register_concmd("dr_restart", "CmdRoundRestart", ADMIN_IMMUNITY);
	register_concmd("dr_respawn", "CmdRespawnUser", ADMIN_IMMUNITY);
	register_concmd("dr_roundinfo", "CmdRoundInfo", ADMIN_IMMUNITY);
	register_concmd("dr_userinfo", "CmdUserInfo", ADMIN_IMMUNITY);
	register_concmd("dr_arrays", "CmdArraySpawns", ADMIN_IMMUNITY);
	register_clcmd("dr_weapons", "CmdGiveWeapons", ADMIN_IMMUNITY);
	register_clcmd("spectate", "CmdSpectate"); // block spectate

	gMsgSayText = get_user_msgid("SayText");
	//register_message(gMsgSayText, "MsgSayText"); // block change team msg

	gFirstRoundTime = get_cvar_num("dr_firstround_time");
	set_task(1.0, "FirstRoundCountdown", TASK_FIRSTROUND, _, _, "b");

	return PLUGIN_CONTINUE;
}

public FirstRoundCountdown() {
	gFirstRoundTime--;
	client_print(0, print_center, "La partida comienza en %i", gFirstRoundTime);

	if (gFirstRoundTime == 0)
		RoundStart();
}

// read game_player_equip from pfn_keyvalue, change weapons to counterpart to avoid create own gameplayer_equip and keep compatibility with cs 1.6 maps...
SetPlayerEquip() {
	//remove_entity_name("player_weaponstrip");
	//remove_entity_name("game_player_equip");

	//new ent = create_entity("game_player_equip");
	//DispatchKeyValue(ent, "weapon_crowbar", "1");
}

public RoundStart() {
	gRoundStarted = false;

	// avoid overlapping tasks
	remove_task(TASK_FIRSTROUND);
	remove_task(TASK_ROUNDSTART);
	remove_task(TASK_ROUNDEND);

	new players[32], numPlayers, player;

	deathrun_get_players(players, numPlayers);

	if (!numPlayers) {
		set_task(5.0, "RoundStart", TASK_ROUNDSTART);
		return;
	} else if (numPlayers == 1) {
 		player = players[0];

 		// let him play so he doesn't get bored waiting for someone
 		if (hl_get_user_team(player) == RED_TEAMID)
 			ChangeTeam(player, BLUE_TEAMID);
 		if (hl_get_user_spectator(player)) {
 		    deathrun_set_user_spectator(player, false);
 		    TeleportToSpawn(player, gBlueSpawns[random(gNumBlueSpawns)]);
 		    ChangeTeam(player, BLUE_TEAMID);
 		}
		client_print(player, print_center, "Se requiere dos jugadores para iniciar");
		set_task(5.0, "RoundStart", TASK_ROUNDSTART);
		return;
	}

	new randomPlayer = RandomPlayer(players, numPlayers); // choose player to be red team

	// randomize teleports of blue team
	SortIntegers(gBlueSpawns, gNumBlueSpawns, Sort_Random);

	for (new i; i < numPlayers; i++) {
		player = players[i];
		if (hl_get_user_spectator(player))
			deathrun_set_user_spectator(player, false);
		else
			dr_user_spawn(player);
			
		if (player != randomPlayer) {
			TeleportToSpawn(player, gBlueSpawns[i]);
			ChangeTeam(player, BLUE_TEAMID, false);
			hl_client_print_color(player, player, "^x02* Elimina al jugador del equipo rojo atravesando sus trampas");
			//client_print(player, print_chat, "Elimina al jugador del equipo rojo, evadiendo sus trampas en el camino hasta poder llegar a el");
		}
 	}
 	ChangeTeam(randomPlayer, RED_TEAMID, false);
 	CheckPlayers(); // check players one time to avoid doing it every changeteam...

	hl_client_print_color(randomPlayer, randomPlayer, "^x02* Elimina al equipo azul activando las trampas desde tu lugar");
	//client_print(player, print_chat, "* Elimina al equipo azul activando las trampas desde tu lugar");

	RestartButtons(); // red team can't use buttons because they were triggered in last round

	remove_entity_name("weaponbox"); // red team can pick up a weaponbox from last round

	gRoundStarted = true;
}

stock hl_client_print_color(id, sender, const message[]) {
	new name[32];
	get_user_name(sender, name, charsmax(name));

	message_begin(MSG_ONE, gMsgSayText, _, id);
	write_byte(sender);
	write_string(fmt("^x02%s %s^n", message, name));
	message_end();	
}

public RoundEnd() {
	if (task_exists(TASK_ROUNDSTART))
		return;

	if (gNumBlueTeam == 0 && gNumRedTeam > 0) {
		client_print(0, print_center, "El equipo rojo ha ganado");
		PlaySound(0, gRedWinsSnd);
	} else if (gNumRedTeam == 0 && gNumBlueTeam > 0) {
		client_print(0, print_center, "El equipo azul ha ganado");
		PlaySound(0, gBlueWinsSnd);
	} else {
		client_print(0, print_center, "Nadie ha ganado");
		PlaySound(0, gDrawSnd);
	}

	set_task(5.0, "RoundStart", TASK_ROUNDSTART);
}

public client_putinserver(id) {
	set_task(0.1, "SendToSpecPutIn", id); // i use a delay to avoid scoreboard glitchs
	set_task(0.1, "CheckPlayers", TASK_CHECKGAMESTATUS);
}

public client_remove(id) {
	set_task(0.1, "CheckPlayers", TASK_CHECKGAMESTATUS);
}

public FwClientKill() {
	return FMRES_SUPERCEDE;
}

public PlayerPreTakeDamage(victim, inflictor, attacker, Float:damage, damagetype) {
	// block falldamage of red team to avoid kill himself	
	if (deathrun_get_user_team(victim) == RED_TEAMID && damagetype & DMG_FALL) {
		return HAM_SUPERCEDE;
	}

	// block teleport kill
	if (damagetype == DMG_GENERIC && damage == 300.0) {
		return HAM_SUPERCEDE;
	}

	return HAM_IGNORED;
}

public PlayerSpawn(id) {
	// if player has to spec, don't let him spawn...
	if (task_exists(TASK_SENDTOSPEC + id))
		return HAM_SUPERCEDE;
	return HAM_IGNORED;
}

public PlayerKilled(victim, attacker) {
	set_task(3.0, "SendToSpec", victim + TASK_SENDTOSPEC); // send to spec mode after 3s
	CheckPlayers();
	return HAM_IGNORED;
}

stock ChangeTeam(id, teamId, check = true) {
	hl_set_user_team_ex(id, teamId);

	if (check)
		CheckPlayers();

	return PLUGIN_HANDLED;
}

public CheckPlayers() {
	deathrun_get_team_alives(gNumBlueTeam, BLUE_TEAMID);
	deathrun_get_team_alives(gNumRedTeam, RED_TEAMID);

	if (gRoundStarted && (gNumBlueTeam < 1 || gNumRedTeam < 1))
		set_task(0.5, "RoundEnd", TASK_ROUNDEND);
}

public SendToSpecPutIn(id) {
	deathrun_set_user_spectator(id, true);
}

public SendToSpec(taskid) {
	new id = taskid - TASK_SENDTOSPEC;
	if (!is_user_alive(id) || is_user_bot(id))
		deathrun_set_user_spectator(id, true);
}

public TeleportToSpawn(id, spawn) {
	new Float:origin[3];
	new Float:angle[3];

	if (!pev_valid(id))
		return;

	// get origin and angle of spawn
	pev(spawn, pev_origin, origin);
	pev(spawn, pev_angles, angle);

	// teleport it
	entity_set_origin(id, origin);
	set_pev(id, pev_angles, angle);
	set_pev(id, pev_fixangle, 1);
}

public RandomPlayer(players[], numplayers) {
	static rnd;
	new oldRnd = rnd;
	if (numplayers > 1)
	rnd = players[random(numplayers)];
	// avoid same player of last round
	while (oldRnd == rnd)
		rnd = players[random(numplayers)];

	return rnd;
}

public RestartButtons() {
	new ent;
	while ((ent = find_ent_by_class(ent, "func_button")) > 0)
		call_think(ent);
}

public GetInfoPlayerStart(spawn[], &numspawns) {
	new entid;
	while ((spawn[numspawns] = find_ent_by_class(entid, "info_player_start"))) {
		entid = spawn[numspawns];
		numspawns++;
	}
}

/* Get item and origin of armoury_entity to sustitute it with his counterpart on Half-Life.
 */
public pfn_keyvalue(entid) {	
	new classname[32], key[32], value[64];
	copy_keyvalue(classname, sizeof classname, key, sizeof key, value, sizeof value);
	if (equal(classname, "armoury_entity")) {
		static Float:origin[3];
		if (equal(key, "origin")) {
			new arg[3][12]; // hold parsed origin
			parse(value, arg[0], charsmax(arg[]), arg[1], charsmax(arg[]), arg[2], charsmax(arg[]));
			for (new i; i < sizeof arg; i++)
				origin[i] = str_to_float(arg[i]);
		} else if (equal(key, "item"))
			SustiteArmouryEnt(origin, str_to_num(value));
	} else if (equal(classname, "game_player_equip")) {
		SustiteGamePlayerEquip(key);
	}
}

// Nota: para aumentar el valor de la bateria, hay que interceptar el ham touch de la bateria y cambiarlo
public SustiteArmouryEnt(Float:origin[3], item){
	new classname[32];
	switch(item) {
		case ARM_TMP, ARM_P90, ARM_MAC10, ARM_MP5: classname = "weapon_357";
		case ARM_M3, ARM_XM1014: classname = "weapon_shotgun";
		case ARM_M4A1, ARM_AK47, ARM_AUG: classname = "weapon_9mmAR";
		case ARM_AWP, ARM_SCOUT, ARM_SG552, ARM_G3SG1: classname = "weapon_crossbow";
		case ARM_M249: classname = "weapon_rpg";
		case ARM_SMOKEGRENADE: classname = "weapon_handgrenade";
		case ARM_FLASHBANG: classname = "weapon_snark";
		case ARM_HEGRENADE: classname = "weapon_satchel";
		case ARM_KEVLAR, ARM_ASSAULTSUIT: classname = "item_battery";
		default: {
			server_print("WARNING: Item %i doesn't exist!", item);
			return;
		}
	}

	new ent = create_entity(classname);
	entity_set_origin(ent, origin);
	DispatchSpawn(ent);
}

/*public SustiteGamePlayerEquip(const csWeapon[], hlWeapon[], size) {
	static Trie:weaponList;
	if (!weaponList) {
		weaponList = TrieCreate();
		for (new i; i < 0; i++)
			TrieSetCell(weaponList, CS_WEAPONS[i], i);
	}

	new classname[32], value;
	TrieGetCell(weaponList, csWeapon, value);

	switch(value) {
		case CS_KNIFE: classname = "weapon_crowbar";
		case CS_USP, CS_GLOCK18: classname = "weapon_9mmhandgun";
		case CS_TMP, CS_P90, CS_MAC10, CS_MP5NAVY: classname = "weapon_357";
		case CS_M3, CS_XM1014: classname = "weapon_shotgun";
		case CS_M4A1, CS_AK47, CS_AUG: classname = "weapon_9mmAR";
		case CS_AWP, CS_SCOUT, CS_SG552, CS_G3SG1: classname = "weapon_crossbow";
		case CS_M249: classname = "weapon_rpg";
		case CS_SMOKEGRENADE: classname = "weapon_handgrenade";
		case CS_FLASHBANG: classname = "weapon_snark";
		case CS_HEGRENADE: classname = "weapon_satchel";
		//case CS_KEVLAR, CS_ASSAULTSUIT: classname = "item_battery";
	}
	copy(hlWeapon, size, classname);
	
}*/

// This only works inside of pfn_keyvalue forward
public SustiteGamePlayerEquip(const csWeapon[]) {
	static Trie:weaponList;
	if (!weaponList) {
		weaponList = TrieCreate();
		for (new i; i < sizeof CS_WEAPONS; i++)
			TrieSetCell(weaponList, CS_WEAPONS[i], i);
	}

	if (contain(csWeapon, "weapon_") == -1)
		return;

	new classname[32], value;
	TrieGetCell(weaponList, csWeapon, value);

	switch(value) {
		case CS_KNIFE: classname = "weapon_crowbar";
		case CS_USP, CS_GLOCK18: classname = "weapon_9mmhandgun";
		case CS_TMP, CS_P90, CS_MAC10, CS_MP5NAVY: classname = "weapon_357";
		case CS_M3, CS_XM1014: classname = "weapon_shotgun";
		case CS_M4A1, CS_AK47, CS_AUG: classname = "weapon_9mmAR";
		case CS_AWP, CS_SCOUT, CS_SG552, CS_G3SG1: classname = "weapon_crossbow";
		case CS_M249: classname = "weapon_rpg";
		case CS_SMOKEGRENADE: classname = "weapon_handgrenade";
		case CS_FLASHBANG: classname = "weapon_snark";
		case CS_HEGRENADE: classname = "weapon_satchel";
		//case CS_KEVLAR, CS_ASSAULTSUIT: classname = "item_battery";
		default: classname = "weapon_snark";
	}

	server_print("Key %s; New Key: %s Value %i", csWeapon, classname, value);
	DispatchKeyValue(classname, 1);	
}

public MsgSayText(msg_id, msg_dest, destid) {
	new text[192];
	get_msg_arg_string(2, text, charsmax(text));

	if (text[0] == '*') { 	// if first character is *, then is a server message
		if (contain(text, "has changed to team") != -1)
			return PLUGIN_HANDLED;
		return PLUGIN_CONTINUE;
	}

	new id = get_msg_arg_int(1);
	
	// Change say tags	
	if (is_user_connected(id)) {
		new isAdmin = is_user_admin(id);
		if (is_user_alive(id)) {
			if (isAdmin)
				format(text, charsmax(text), "^x02[ADMIN]%s", text); // All
		} else {
			if (isAdmin)
				format(text, charsmax(text), "^x02(MUERTO) [ADMIN]%s", text);
			else
				format(text, charsmax(text), "^x02(MUERTO)%s", text);
		}
	}

	// Send final message
	set_msg_arg_string(2, text);

	return PLUGIN_CONTINUE;
}

public CmdSpectate() {
	return PLUGIN_HANDLED;
}

public CmdRoundRestart(id, level, cid) {
	if (!cmd_access(id, level, cid, 0))
	    return PLUGIN_HANDLED;
	RoundStart();
	return PLUGIN_CONTINUE;
}

public CmdRespawnUser(id, level, cid) {
	if (!cmd_access(id, level, cid, 0))
	    return PLUGIN_HANDLED;

	new target[32];
	read_argv(1, target, charsmax(target));

	new player = cmd_target(id, target, 0);
	remove_task(player + TASK_SENDTOSPEC);
	if (is_user_connected(player))
		if (hl_get_user_spectator(player))
			hl_set_user_spectator(player, false);
		else
			dr_user_spawn(player);
	else
		return PLUGIN_HANDLED;

	ChangeTeam(id, BLUE_TEAMID);

	TeleportToSpawn(player, gBlueSpawns[random(gNumBlueSpawns)]);
	
	return PLUGIN_CONTINUE;
}

public CmdGiveWeapons(id, level, cid) {
	if (!cmd_access(id, level, cid, 0))
	    return PLUGIN_HANDLED;

	//set_user_godmode(id, true);

	for (new i; i < 9; i++)
		give_item(id, "weapon_9mmAR");

	for (new i; i < 5; i++)
		give_item(id, "ammo_mp5grenades");

	for (new i; i < 5; i++)
		give_item(id, "weapon_gauss");

	return PLUGIN_CONTINUE;
}

public CmdArraySpawns(id, level, cid) {
	if (!cmd_access(id, level, cid, 0))
	    return PLUGIN_HANDLED;
	PrintArraySpawn(id);
	return PLUGIN_CONTINUE;
}

public CmdRoundInfo(id, level, cid) {
	if (!cmd_access(id, level, cid, 0))
	    return PLUGIN_HANDLED;
	PrintRoundInfo(id);
	return PLUGIN_CONTINUE;
}

public CmdUserInfo(id, level, cid) {
	if (!cmd_access(id, level, cid, 1))
	    return PLUGIN_HANDLED;

	new target[32];
	read_argv(1, target, charsmax(target));
	// Si el usuario no ingreso ningun parametro, entonces mostrar info de ti mismo
	if (equal(target, "")) {
	    PrintUserInfo(id, id);
	    return PLUGIN_HANDLED;
	}

	new player = cmd_target(id, target);

	if (!player)
		return PLUGIN_HANDLED;
	// Mostrar informacion del usuario selecionado
	PrintUserInfo(id, player);
	return PLUGIN_CONTINUE;
}

public PrintArraySpawn(id) {
	for(new i=0; i<32; i++)
		console_print(id, "%i. blue spawn: %i", i, gBlueSpawns[i]);
}

public PrintRoundInfo(id) {
	client_print(id, print_chat, "Azul vivos: %i; Rojo vivos: %i; gRoundStarted: %i; gNumBlueSpawns: %i", gNumBlueTeam, gNumRedTeam, gRoundStarted, gNumBlueSpawns);
}

public PrintUserInfo(caller, target) {
	new model[16];
	new team = hl_get_user_team(target);

	new iuser1 = pev(target, pev_iuser1);
	new iuser2 = pev(target, pev_iuser2);

	new alive = is_user_alive(target);
	new dead = pev(target, pev_deadflag);

	hl_get_user_model(target, model, charsmax(model));

	client_print(caller, print_chat, "Team: %i; Model: %s; iuser1: %i; iuser2: %i Alive: %i; Deadflag: %i", team, model, iuser1, iuser2, alive, dead);
}

public GetTeamListModel(team1[MAX_TEAMNAME_LENGTH], team2[MAX_TEAMNAME_LENGTH]) {
	new teamlist[64];
	get_pcvar_string(get_cvar_pointer("mp_teamlist"), teamlist, charsmax(teamlist)); 
	trim(teamlist);
	replace_string(teamlist, charsmax(teamlist), ";", " ");
	parse(teamlist, team1, charsmax(team1), team2, charsmax(team2));
}

public PlaySound(id, const sound[]) {
	client_cmd(id, "spk %s", sound);
}

stock deathrun_set_user_spectator(client, bool:spectator = true) {
	if(hl_get_user_spectator(client) == spectator)
		return;

	if(spectator) {
		static AllowSpectatorsCvar;
		if(AllowSpectatorsCvar || (AllowSpectatorsCvar = get_cvar_pointer("allow_spectators"))) {
			if(!get_pcvar_num(AllowSpectatorsCvar))
				set_pcvar_num(AllowSpectatorsCvar, 1);

			engclient_cmd(client, "spectate");
		}
	} else {
		dr_user_spawn(client);

		set_pev(client, pev_iuser1, 0);
		set_pev(client, pev_iuser2, 0);

		set_pdata_int(client, OFFSET_HUD, 0);

		// clear message when exit of spectator
 		client_print(client, print_center, "");

		static szTeam[16];
		hl_get_user_team(client, szTeam, charsmax(szTeam));

		// this fix when using openag client the scoreboard user colors
		static Spectator;
		if(Spectator || (Spectator = get_user_msgid("Spectator"))) {
			message_begin(MSG_ALL, Spectator);
			write_byte(client);
			write_byte(0);
			message_end();
		}

		static TeamInfo;
		if(TeamInfo || (TeamInfo = get_user_msgid("TeamInfo"))) {
			message_begin(MSG_ALL, TeamInfo);
			write_byte(client);
			write_string(szTeam);
			message_end();
		}
	}
}

stock deathrun_get_players(players[MAX_PLAYERS], &numplayers) {
	arrayset(players, 0, charsmax(players));
	get_players(players, numplayers);
}

stock deathrun_get_team_alives(&teamAlives, teamindex) {
	teamAlives = 0;
	for (new id=1; id<=MaxClients; id++)
		if (is_user_alive(id) && deathrun_get_user_team(id) == teamindex)
			teamAlives++;
}

stock deathrun_get_user_team(client, team[] = "", len = 0) {
	if(!client || client > MaxClients || hl_get_user_spectator(client))
		return 0;

	static Float: tdm; global_get(glb_teamplay, tdm);
	if(tdm < 1.0) return 0;

	if(!len) len = 16;
	get_user_info(client, "model", team, len);

	return __get_team_index(team);
}

stock dr_user_spawn(client) {
	remove_task(client + TASK_SENDTOSPEC); // if you dont remove this, he will not respawn
	
	if(!hl_strip_user_weapons(client))
		return;

	set_pev(client, pev_deadflag, DEAD_RESPAWNABLE);
	dllfunc(DLLFunc_Spawn, client);
}

stock hl_set_user_team_ex(id, teamId) {
	static entTeamMaster, entPlayerTeam;

	if (!entTeamMaster) {
		entTeamMaster = create_entity("game_team_master");
		set_pev(entTeamMaster, pev_targetname, "changeteam");
	}

	if (!entPlayerTeam) {
		entPlayerTeam = create_entity("game_player_team");
		DispatchKeyValue(entPlayerTeam, "target", "changeteam");
	}

	// teamid = 0 (azul) teamid = 1 (rojo), etc...
	DispatchKeyValue(entTeamMaster, "teamindex", fmt("%i", teamId - 1)); // le resto 1 para que pueda usarlo con las constantes que tengo de teamid 
	
	ExecuteHamB(Ham_Use, entPlayerTeam, id, 0, 1.0, 0.0);
}
