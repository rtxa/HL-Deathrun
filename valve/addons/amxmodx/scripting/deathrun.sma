/*
*
* Half-Life Deathrun by rtxA	
*
*/

#include <amxmodx>
#include <amxmisc>
#include <hlstocks>
#include <engine>
#include <fakemeta>
#include <hamsandwich>
#include <fun>
#include <restore_map>

#pragma semicolon 1

#define PLUGIN 	"HL Deathrun"
#define VERSION "1.3"
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

new const SND_BLUE_WIN[] = "deathrun/w_blue.wav";
new const SND_RED_WIN[] = "deathrun/w_red.wav";
new const SND_DRAW[] = "deathrun/draw.wav";

#define BLUE_TEAMID 1
#define RED_TEAMID 2

#define TEAMNAME_LENGTH 16

#define MAX_SPAWNS 64 // increase it in case the mapmap has more spawns than needed...

new gNumBlueTeam;
new gNumRedTeam;

new gBlueSpawns[MAX_SPAWNS];
new gNumBlueSpawns;

// game rules
new bool:gRoundStarted;

new gFirstRoundTime; // in seconds

public plugin_precache() {
	new blue[TEAMNAME_LENGTH], red[TEAMNAME_LENGTH];
	// i use this as parameter for change team
	GetTeamListModel(blue, red);

	new file[128];

	formatex(file, charsmax(file), "models/player/%s/%s.mdl", blue, blue);
	if (file_exists(file))
		precache_model(file);

	formatex(file, charsmax(file), "models/player/%s/%s.mdl", red, red);
	if (file_exists(file))
		precache_model(file);

	precache_sound(SND_BLUE_WIN);
	precache_sound(SND_RED_WIN);
	precache_sound(SND_DRAW);

	create_cvar("dr_firstround_time", "15");
}

// Game mode name that should be displayed in server browser
public OnGetGameDescription() {
	forward_return(FMV_STRING, PLUGIN + " " + VERSION);
	return FMRES_SUPERCEDE;
}

public plugin_init() {
	register_plugin(PLUGIN, VERSION, AUTHOR);

	if (get_cvar_num("mp_teamplay") <= 0) {
		log_amx("Server is not in TDM");
		StopPlugin();
		return;
	}

	register_dictionary("deathrun.txt");

	register_forward(FM_GetGameDescription, "OnGetGameDescription");

	register_message(get_user_msgid("SayText"), "OnMsgSayText");
	register_message(get_user_msgid("TextMsg"), "OnMsgTextMsg");

	// cache only spawns from blue team
	GetBlueTeamSpawns(gBlueSpawns, sizeof gBlueSpawns, gNumBlueSpawns);

	if (gNumBlueSpawns <= 0) {
		log_amx("This map is not compatible with Deathrun");
		return;
	}

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

	gFirstRoundTime = get_cvar_num("dr_firstround_time");
	set_task(1.0, "FirstRoundCountdown", TASK_FIRSTROUND, _, _, "b");
}

public FirstRoundCountdown() {
	gFirstRoundTime--;
	client_print(0, print_center, "%l", "ROUND_FIRSTROUND", gFirstRoundTime);

	if (gFirstRoundTime == 0)
		RoundStart();
}

public RoundStart() {
	gRoundStarted = false;

	// avoid overlapping tasks
	remove_task(TASK_FIRSTROUND);
	remove_task(TASK_ROUNDSTART);
	remove_task(TASK_ROUNDEND);

	new players[32], numPlayers, player;
	get_players_ex(players, numPlayers, GetPlayers_ExcludeHLTV);

	if (!numPlayers) {
		set_task(5.0, "RoundStart", TASK_ROUNDSTART);
		return;
	} else if (numPlayers == 1) {
 		player = players[0];

 		// let him play so he doesn't get bored waiting for someone
 		if (hl_get_user_team(player) == RED_TEAMID)
 			ChangeTeam(player, BLUE_TEAMID);
 		if (hl_get_user_spectator(player)) {
 		    dr_set_user_spectator(player, false);
 		    TeleportToSpawn(player, gBlueSpawns[random(gNumBlueSpawns)]);
 		    ChangeTeam(player, BLUE_TEAMID);
 		}
		client_print(player, print_center, "%l", "ROUND_MINPLAYERS", 2);
		set_task(5.0, "RoundStart", TASK_ROUNDSTART);
		return;
	}

	new randomPlayer = RandomPlayer(players, numPlayers); // choose player to be red team

	// randomize teleport locations for blue team
	SortIntegers(gBlueSpawns, gNumBlueSpawns, Sort_Random);

	for (new i; i < numPlayers; i++) {
		player = players[i];
		if (hl_get_user_spectator(player))
			dr_set_user_spectator(player, false);
		else
			dr_user_spawn(player);

		if (player != randomPlayer) {
			TeleportToSpawn(player, gBlueSpawns[i]);
			ChangeTeam(player, BLUE_TEAMID, false);
			client_print(player, print_chat, "%l", "OBJECTIVE_RUNNERS");
		}
 	}
 	ChangeTeam(randomPlayer, RED_TEAMID, false);
 	CheckGameStatus(); // check players one time to avoid doing it every changeteam...

	client_print(randomPlayer, print_chat, "%l", "OBJECTIVE_ACTIVATOR");

	ResetMap();

	gRoundStarted = true;
}

public RoundEnd() {
	if (task_exists(TASK_ROUNDSTART))
		return;

	if (gNumBlueTeam == 0 && gNumRedTeam > 0) {
		client_print(0, print_center, "%l", "ROUND_WINACTIVATOR");
		PlaySound(0, SND_RED_WIN);
	} else if (gNumRedTeam == 0 && gNumBlueTeam > 0) {
		client_print(0, print_center, "%l", "ROUND_WINRUNNERS");
		PlaySound(0, SND_BLUE_WIN);
	} else {
		client_print(0, print_center, "%l", "ROUND_DRAW");
		PlaySound(0, SND_DRAW);
	}

	set_task(5.0, "RoundStart", TASK_ROUNDSTART);
}

public client_putinserver(id) {
	set_task(0.1, "SendToSpecPutIn", id); // i use a delay to avoid scoreboard glitchs
	set_task(0.1, "CheckGameStatus", TASK_CHECKGAMESTATUS);
}

public client_remove(id) {
	set_task(0.1, "CheckGameStatus", TASK_CHECKGAMESTATUS);
}

public FwClientKill() {
	return FMRES_SUPERCEDE;
}

public PlayerPreTakeDamage(victim, inflictor, attacker, Float:damage, damagetype) {
	// block falldamage of red team to avoid kill himself
	if (hl_get_user_team(victim) == RED_TEAMID && damagetype & DMG_FALL) {
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
	CheckGameStatus();
	return HAM_IGNORED;
}

stock ChangeTeam(id, teamId, check = true) {
	hl_set_user_team_ex(id, teamId);

	if (check)
		CheckGameStatus();

	return PLUGIN_HANDLED;
}

public CheckGameStatus() {
	gNumBlueTeam = hl_get_team_count(BLUE_TEAMID);
	gNumRedTeam = hl_get_team_count(RED_TEAMID);

	if (gRoundStarted && (gNumBlueTeam < 1 || gNumRedTeam < 1))
		set_task(0.5, "RoundEnd", TASK_ROUNDEND);
}

public SendToSpecPutIn(id) {
	dr_set_user_spectator(id, true);
}

public SendToSpec(taskid) {
	new id = taskid - TASK_SENDTOSPEC;
	if (!is_user_alive(id) || is_user_bot(id))
		dr_set_user_spectator(id, true);
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

public OnMsgTextMsg(msg_id, msg_dest, receiver) {
	new text[191];
	get_msg_arg_string(2, text, charsmax(text));
	
	if (containi(text, "switched to spectator mode") != -1)
		return PLUGIN_HANDLED;

	return PLUGIN_CONTINUE;
}

public OnMsgSayText(msg_id, msg_dest, receiver) {
	new text[191];
	get_msg_arg_string(2, text, charsmax(text));

	new sender = get_msg_arg_int(1);

	// player message
	if (text[0] == 2) {
		if (!is_user_alive(sender)) {
			SetGlobalTransTarget(receiver);
			replace(text, charsmax(text), "^x02", fmt("%c%l ", 2, "TAG_DEAD"));
		}
	}

	set_msg_arg_string(2, text);

	return PLUGIN_CONTINUE;
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

public GetBlueTeamSpawns(spawn[], size, &numspawns) {
	new entid;
	while ((entid = find_ent_by_class(entid, "info_player_start"))) {
		if (numspawns >= size)
			break;
		spawn[numspawns++] = entid;
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
			StrToVec(value, origin);
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

// This only works inside of pfn_keyvalue forward
// Note: There's a bug with deathrun_aqa, problem is bad enginenring in the map
// Is being called twice, the game_player_equip has not set the 'Use only' option
// So the multimanager, will give him the weapon on spawn, and the game_player_equio
// Will do too, maybe we can workaround it, but no time for that..
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

	//server_print("Key %s; New Key: %s Value %i", csWeapon, classname, value);
	DispatchKeyValue(classname, 1);
}

public CmdSpectate() {
	return PLUGIN_HANDLED;
}

public CmdRoundRestart(id, level, cid) {
	if (!cmd_access(id, level, cid, 0))
	    return PLUGIN_HANDLED;
	RoundStart();
	return PLUGIN_HANDLED;
}

public CmdRespawnUser(id, level, cid) {
	if (!cmd_access(id, level, cid, 0))
	    return PLUGIN_HANDLED;

	new target[32];
	read_argv(1, target, charsmax(target));

	new player = cmd_target(id, target, 0);

	if (!is_user_connected(player)) {
		return PLUGIN_HANDLED;
	}

	ChangeTeam(player, BLUE_TEAMID);

	if (hl_get_user_spectator(player))
		hl_set_user_spectator(player, false);
	else
		dr_user_spawn(player);

	TeleportToSpawn(player, gBlueSpawns[random(gNumBlueSpawns)]);

	return PLUGIN_HANDLED;
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

	return PLUGIN_HANDLED;
}

public CmdArraySpawns(id, level, cid) {
	if (!cmd_access(id, level, cid, 0))
	    return PLUGIN_HANDLED;
	PrintArraySpawn(id);
	return PLUGIN_HANDLED;
}

public CmdRoundInfo(id, level, cid) {
	if (!cmd_access(id, level, cid, 0))
	    return PLUGIN_HANDLED;
	PrintRoundInfo(id);
	return PLUGIN_HANDLED;
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
	return PLUGIN_HANDLED;
}

public PrintArraySpawn(id) {
	for(new i; i < sizeof gBlueSpawns; i++)
		console_print(id, "%i. blue spawn: %i", i, gBlueSpawns[i]);
	return PLUGIN_HANDLED;
}

public PrintRoundInfo(id) {
	client_print(id, print_chat, "Blue count: %i; Red count: %i; gRoundStarted: %i; gNumBlueSpawns: %i", gNumBlueTeam, gNumRedTeam, gRoundStarted, gNumBlueSpawns);
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

public GetTeamListModel(team1[TEAMNAME_LENGTH], team2[TEAMNAME_LENGTH]) {
	new teamlist[64];
	get_pcvar_string(get_cvar_pointer("mp_teamlist"), teamlist, charsmax(teamlist));
	trim(teamlist);
	replace_string(teamlist, charsmax(teamlist), ";", " ");
	parse(teamlist, team1, charsmax(team1), team2, charsmax(team2));
}

public PlaySound(id, const sound[]) {
	client_cmd(id, "spk %s", sound);
}

stock hl_get_team_count(teamindex) {
	new players[MAX_PLAYERS], numPlayers;
	get_players_ex(players, numPlayers, GetPlayers_ExcludeDead);

	new num;
	for (new i; i < numPlayers; i++)
		if (hl_get_user_team(players[i]) == teamindex)
			num++;

	return num;
}

/* Set player team by passing teamid instead of teamname.
*/
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

	DispatchKeyValue(entTeamMaster, "teamindex", fmt("%i", teamId - 1));

	ExecuteHamB(Ham_Use, entPlayerTeam, id, 0, USE_ON, 0.0);
}

stock dr_set_user_spectator(client, bool:spectator = true) {
	if (!spectator)
		remove_task(client + TASK_SENDTOSPEC); // remove task to let him respawn

	hl_set_user_spectator(client, spectator);
}

stock dr_user_spawn(client) {
	remove_task(client + TASK_SENDTOSPEC); // if you dont remove this, he will not respawn
	hl_user_spawn(client);
}

// the parsed string is in this format "x y z" e.g "128 0 256"
Float:StrToVec(const string[], Float:vector[3]) {
	new arg[3][12]; // hold parsed vector
	parse(string, arg[0], charsmax(arg[]), arg[1], charsmax(arg[]), arg[2], charsmax(arg[]));

	for (new i; i < sizeof arg; i++)
		vector[i] = str_to_float(arg[i]);
}

/* ===========================================================================​=============================
 *         [ Reset Map Functions ]
 * ===========================================================================​===========================*/

// this will clean entities from previous matchs
ClearField() {
	static const fieldEnts[][] = { "bolt", "monster_snark", "monster_satchel", "monster_tripmine", "beam", "weaponbox" };

	for (new i; i < sizeof fieldEnts; i++)
		remove_entity_name(fieldEnts[i]);

	new ent;
	while ((ent = find_ent_by_class(ent, "rpg_rocket")))
		set_pev(ent, pev_dmg, 0);

	ent = 0;
	while ((ent = find_ent_by_class(ent, "grenade")))
		set_pev(ent, pev_dmg, 0);
}

ClearCorpses() {
	new ent;
	while ((ent = find_ent_by_class(ent, "bodyque")))
		set_pev(ent, pev_effects, EF_NODRAW);
}

// This will respawn all weapons, ammo and items of the map to prepare for a new match (agstart)
RespawnItems() {
	new classname[32];
	for (new i; i < global_get(glb_maxEntities); i++) {
		if (pev_valid(i)) {
			pev(i, pev_classname, classname, charsmax(classname));
			if (contain(classname, "weapon_") != -1 || contain(classname, "ammo_") != -1 || contain(classname, "item_") != -1) {
				set_pev(i, pev_nextthink, get_gametime());
			}
		}
	}
}

ResetMap() {
	ClearField();
	ClearCorpses();
	RespawnItems();

	// HL Restore Map API
	hl_restore_all();
}

stock StopPlugin() {
	new pluginName[32];
	get_plugin(-1, pluginName, sizeof(pluginName));
	pause("d", pluginName);
	return;
}