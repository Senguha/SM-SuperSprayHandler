#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <clientprefs>
#include <morecolors>
#include <decalmanager>
#include <tf2items>
#include <tf2attributes>

#define MAX_STEAMAUTH_LENGTH 21 
#define MAX_COMMUNITYID_LENGTH 18 
#define PREFIX "{violet}[Decal Manager]{plum} "


#include <tf2_stocks>
#undef REQUIRE_PLUGIN
#include <adminmenu>


//Used to easily access my cvars out of an array.
#define PLUGIN_VERSION "1.4.0"
enum {
	ENABLED = 0,
	ANTIOVERLAP,
	AUTH,
	MAXDIS,
	REFRESHRATE,
	USEBAN,
	BURNTIME,
	SLAPDMG,
	USESLAY,
	USEBURN,
	USEPBAN,
	USEKICK,
	USEFREEZE,
	USEBEACON,
	USEFREEZEBOMB,
	USEFIREBOMB,
	USETIMEBOMB,
	USESPRAYBAN,
	DRUGTIME,
	AUTOREMOVE,
	RESTRICT,
	IMMUNITY,
	GLOBAL,
	LOCATION,
	HUDTIME,
	CONFIRMACTIONS,
	NUMCVARS
}

#define MAX_CONNECTIONS 5
#define ZERO_VECTOR view_as<float>({0.0, 0.0, 0.0})

//Creates my array of CVars
ConVar g_arrCVars[NUMCVARS];

//Vital arrays that store all of our important information :D
char g_arrSprayName[MAXPLAYERS + 1][MAX_NAME_LENGTH];
char g_arrSprayID[MAXPLAYERS + 1][32];
char g_arrMenuSprayID[MAXPLAYERS + 1][32];

// this client's spray
float g_fSprayVector[MAXPLAYERS+1][3];

int g_arrSprayTime[MAXPLAYERS + 1];
char g_sAuth[MAXPLAYERS+1][512];
Database g_Database;
float NormalForSpray[MAXPLAYERS+1][3];

StringMap SpraybansMap;

enum struct SprayBan {
	int startTime;
	int length;
	int endTime;
	char adminSteamID[MAX_AUTHID_LENGTH];
	char reason[64];
	char auth[MAX_AUTHID_LENGTH];
	bool notyfied;
}

//Our Timer that will be initialized later
Handle g_hSprayTimer;

//Global boolean that is defined later on if your server can use the HUD. (sm_ssh_location == 4)
bool g_bCanUseHUD;
int g_iHudLoc;

//The HUD that will be initialized later IF your server supports the HUD.
Handle g_hHUD;


int g_iConnections;

//Our main admin menu handle >.>
TopMenu g_hAdminMenu;
TopMenuObject menu_category;

//Forwards
Handle g_hBanForward;

//Timer
Handle g_BanExpireTimer[MAXPLAYERS + 1] = { null, ... };

//Were we late loaded?
bool g_bLate;

//Used for the glow that is applied when tracing a spray
//int g_PrecacheRedGlow;

bool highMaxPlayers = false;


//The plugin info :D
public Plugin myinfo = {
	name = "Decal Manager",
	description = "Ultimate Tool for Admins to manage Sprays and Decals on their servers.",
	author = "shavit, Nican132, CptMoore, Lebson506th, TheWreckingCrew6, JoinedSenses, sappho.io, Mtseng",
	version = PLUGIN_VERSION,
	url = "",
}

//Used to create the natives for other plugins to hook into this beauty
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {

	g_hBanForward = CreateGlobalForward("DecalManager_OnBan", ET_Ignore, Param_String, Param_String,Param_String,Param_String,Param_Cell,Param_String);
	RegPluginLibrary("DecalManager");

	g_bLate = late;

	return APLRes_Success;
}

void ForwardSprayBan(char[] userName = "<unknown>", char[] userAuth, char[] adminName, char[] adminAuth, int time, char[] reason){

	Call_StartForward(g_hBanForward);
	Call_PushString(userName);
	Call_PushString(userAuth);
	Call_PushString(adminName);
	Call_PushString(adminAuth);
	Call_PushCell(time);
	Call_PushString(reason);
	Call_Finish();
}

int laser = -1;

//What we want to do when this beauty starts up.
public void OnPluginStart() {

	SpraybansMap = CreateTrie();
	
	char cmdline[512];
	GetCommandLine(cmdline, sizeof(cmdline));

	if (StrContains(cmdline, "-unrestricted_maxplayers") != -1)
	{
		highMaxPlayers = true;
	}


	// precache our sprite
	laser = PrecacheModel("sprites/laser.vmt", true);

	//We want these translations files :D
	LoadTranslations("ssh.phrases");
	LoadTranslations("common.phrases");

	//Base convar obviously
	CreateConVar("sm_spray_version", PLUGIN_VERSION, "Super Spray Handler plugin version", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);


	//Beautiful Commands
	RegAdminCmd("sm_spraytrace", Command_TraceSpray, ADMFLAG_KICK, "Look up the owner of the logo in front of you.");
	RegAdminCmd("sm_removespray", Command_RemoveSpray, ADMFLAG_KICK, "Remove the logo in front of you.");
	RegAdminCmd("sm_adminspray", Command_AdminSpray, ADMFLAG_KICK, "Sprays the named player's logo in front of you.");
	RegAdminCmd("sm_qremovespray", Command_QuickRemoveSpray, ADMFLAG_KICK, "Removes the logo in front of you without opening punishment menu.");
	RegAdminCmd("sm_removeallsprays", Command_RemoveAllSprays, ADMFLAG_UNBAN, "Removes all sprays from the map.");
	RegAdminCmd("sm_cleardecals", Command_ClearDecals, ADMFLAG_UNBAN, "Usage : sm_cleardecals <target> - Removes all decals from target items.");

	RegAdminCmd("sm_sbans", Command_Spraybans, ADMFLAG_GENERIC, "Shows a list of all connected spray banned players.");
	RegAdminCmd("sm_spraybans", Command_Spraybans, ADMFLAG_GENERIC, "Shows a list of all connected spray banned players.");
	
	RegConsoleCmd("sm_spraystatus", Command_SprayStatus, "Shows the sprayban status of a player.");

	RegAdminCmd("sm_sban", Command_SpraybanNew, ADMFLAG_KICK, "Usage: sm_sban <target> <duration in days)> [reason]");
	RegAdminCmd("sm_sprayban", Command_SpraybanNew, ADMFLAG_KICK, "Usage: sm_sprayban <target> <duration in days)> [reason]");
	RegAdminCmd("sm_sunban", Command_SprayUnbannew, ADMFLAG_KICK, "Usage: sm_sunban <target>");
	RegAdminCmd("sm_sprayunban", Command_SprayUnbannew, ADMFLAG_KICK, "Usage: sm_sprayunban <target>");
	RegAdminCmd("sm_offsban", Command_SpraybanOfflinenew, ADMFLAG_KICK, "Usage: sm_offsban <'steamid'> <duration in days> [reason]");
	RegAdminCmd("sm_offsprayban", Command_SpraybanOfflinenew, ADMFLAG_KICK, "Usage: sm_offsprayban <'steamid'> <duration in days> [reason]");
	RegAdminCmd("sm_offsunban", Command_SprayUnbanOfflinenew, ADMFLAG_KICK, "Usage: sm_offsunban <'steamid'>");
	RegAdminCmd("sm_offsprayunban", Command_SprayUnbanOfflinenew, ADMFLAG_KICK, "Usage: sm_offsprayunban <'steamid'>");

	CreateConVar("sm_ssh_version", PLUGIN_VERSION, "Super Spray Handler version", FCVAR_SPONLY|FCVAR_DONTRECORD|FCVAR_NOTIFY);

	//Spray Manager CVars
	g_arrCVars[ENABLED] = CreateConVar("sm_ssh_enabled", "1", "Enable \"Super Spray Handler\"?", 0, true, 0.0, true, 1.0);
	g_arrCVars[ANTIOVERLAP] = CreateConVar("sm_ssh_overlap", "0", "Prevent spray-on-spray overlapping?\nIf enabled, specify an amount of units that another player spray's distance from the new spray needs to be it or more, recommended value is 75.", 0, true, 0.0);
	g_arrCVars[AUTH] = CreateConVar("sm_ssh_auth", "1", "Which authentication identifiers should be seen in the HUD?\n- This is a \"math\" cvar, add the proper numbers for your likings. (Example: 1 + 4 = 5/Name + IP address)\n1 - Name\n2 - SteamID\n4 - IP address", 0, true, 1.0);

	//SSH CVars
	g_arrCVars[REFRESHRATE] = CreateConVar("sm_ssh_refresh","0.1","How often the program will trace to see player's spray to the HUD. 0 to disable.");
	g_arrCVars[MAXDIS] = CreateConVar("sm_ssh_dista","64.0","How far away (FROM YOUR MOUSE, NOT YOUR POSITION) the spray will be traced to.");
	g_arrCVars[USEBAN] = CreateConVar("sm_ssh_enableban","1","Whether or not banning is enabled. 0 to disable temporary banning.");
	g_arrCVars[BURNTIME] = CreateConVar("sm_ssh_burntime","10","How long the burn punishment is for.");
	g_arrCVars[SLAPDMG] = CreateConVar("sm_ssh_slapdamage","5","How much damage the slap punishment is for. 0 to disable.");
	g_arrCVars[USESLAY] = CreateConVar("sm_ssh_enableslay","0","Enables the use of Slay as a punishment.");
	g_arrCVars[USEBURN] = CreateConVar("sm_ssh_enableburn","0","Enables the use of Burn as a punishment.");
	g_arrCVars[USEPBAN] = CreateConVar("sm_ssh_enablepban","1","Enables the use of a Permanent Ban as a punishment.");
	g_arrCVars[USEKICK] = CreateConVar("sm_ssh_enablekick","1","Enables the use of Kick as a punishment.");
	g_arrCVars[USEBEACON] = CreateConVar("sm_ssh_enablebeacon","0","Enables putting a beacon on the sprayer as a punishment.");
	g_arrCVars[USEFREEZE] = CreateConVar("sm_ssh_enablefreeze","0","Enables the use of Freeze as a punishment.");
	g_arrCVars[USEFREEZEBOMB] = CreateConVar("sm_ssh_enablefreezebomb","0","Enables the use of Freeze Bomb as a punishment.");
	g_arrCVars[USEFIREBOMB] = CreateConVar("sm_ssh_enablefirebomb","0","Enables the use of Fire Bomb as a punishment.");
	g_arrCVars[USETIMEBOMB] = CreateConVar("sm_ssh_enabletimebomb","0","Enables the use of Time Bomb as a punishment.");
	g_arrCVars[USESPRAYBAN] = CreateConVar("sm_ssh_enablespraybaninmenu","1","Enables Spray Ban in the Punishment Menu.");
	g_arrCVars[DRUGTIME] = CreateConVar("sm_ssh_drugtime","0","set the time a sprayer is drugged as a punishment. 0 to disable.");
	g_arrCVars[AUTOREMOVE] = CreateConVar("sm_ssh_autoremove","0","Enables automatically removing sprays when a punishment is dealt.");
	g_arrCVars[RESTRICT] = CreateConVar("sm_ssh_restrict","1","Enables or disables restricting admins to punishments they are given access to. (1 = commands they have access to, 0 = all)");
	g_arrCVars[IMMUNITY] = CreateConVar("sm_ssh_useimmunity","1","Enables or disables using admin immunity to determine if one admin can punish another."); //disabled
	g_arrCVars[GLOBAL] = CreateConVar("sm_ssh_global","1","Enables or disables global spray tracking. If this is on, sprays can still be tracked when a player leaves the server.");
	g_arrCVars[LOCATION] = CreateConVar("sm_ssh_location","1","Where players will see the owner of the spray that they're aiming at? 0 - Disabled 1 - Hud hint 2 - Hint text (like sm_hsay) 3 - Center text (like sm_csay) 4 - HUD");
	g_arrCVars[HUDTIME] = CreateConVar("sm_ssh_hudtime","1.0","How long the HUD messages are displayed.");
	g_arrCVars[CONFIRMACTIONS] = CreateConVar("sm_ssh_confirmactions","1","Should you have to confirm spray banning and un-spraybanning?"); // disabled

	g_arrCVars[REFRESHRATE].AddChangeHook(TimerChanged);
	g_arrCVars[LOCATION].AddChangeHook(LocationChanged);
	g_iHudLoc = g_arrCVars[LOCATION].IntValue;

	AutoExecConfig(true, "plugin.ssh");


	//Adds hook that looks for when a player sprays a decal.
	AddTempEntHook("Player Decal", Player_Decal);

	//Figures out what game you're running to then check for HUD support.
	char gamename[32];
	GetGameFolderName(gamename, sizeof gamename);

	//Checks for support of the HUD in current server, if not supported, changes sm_ssh_location to 1.
	g_bCanUseHUD = StrEqual(gamename,"tf", false)
		|| StrEqual(gamename,"hl2mp", false)
		|| StrEqual(gamename, "synergy", false)
		|| StrEqual(gamename,"sourceforts", false)
		|| StrEqual(gamename,"obsidian", false)
		|| StrEqual(gamename,"left4dead", false)
		|| StrEqual(gamename,"l4d", false);

	if (g_bCanUseHUD) {
		g_hHUD = CreateHudSynchronizer();
	}

	if (g_hHUD == null && g_arrCVars[LOCATION].IntValue == 4) {
		g_arrCVars[LOCATION].SetInt(1, true);

		LogError("[Super Spray Handler] This game can't use HUD messages, value of \"sm_ssh_location\" forced to 1.");
	}

	//Calls creating the admin menu, but checks to make sure server has admin menu plugin loaded.
	TopMenu topmenu;
	if (LibraryExists("adminmenu") && ((topmenu = GetAdminTopMenu()) != null)) {
		OnAdminMenuReady(topmenu);
	}

	SQL_Connector();
}

//When the map starts we want to create timers, and clear any info that may have decided to stick around.
public void OnMapStart() {
	
	ClearTrie(SpraybansMap);
	
	CreateTimers();

	for (int i = 1; i <= MaxClients; i++) {
		ClearVariables(i);
	}
}

//If sm_ssh_global = 0 then we want to get rid of a players spray when they leave.
public void OnClientDisconnect(int client)
{
	
	char clientKey[16];
	IntToString(client, clientKey, sizeof(clientKey));
	
	RemoveFromTrie(SpraybansMap, clientKey);
	CloseBanTimer(client);
	
	if (!g_arrCVars[GLOBAL].BoolValue)
	{
		ClearVariables(client);
	}
}

//When a client joins we need to 1: default his spray to 0 0 0. 2: Check in the database if he is spray banned.
public void OnClientPutInServer(int client)
{
	g_fSprayVector[client] = ZERO_VECTOR;

	CheckBan(client);
}

public Action Timer_BanExpire(Handle timer, DataPack dataPack)
{
	dataPack.Reset();
	g_BanExpireTimer[dataPack.ReadCell()] = null;

	int client = GetClientOfUserId(dataPack.ReadCell());
	if (!client)
		return Plugin_Continue;

	char targetAuth[MAX_STEAMAUTH_LENGTH];
	GetClientAuthId(client, AuthId_Steam2, targetAuth, sizeof targetAuth);
	LogMessage("Ban expired for %s", targetAuth);

	CPrintToChat(client, "%s%T", PREFIX, "Ban expired", client);

	if (IsClientInGame(client)){
		char clientKey[16];
		IntToString(client, clientKey, sizeof(clientKey));
		SpraybansMap.Remove(clientKey);
	}
		
	return Plugin_Continue;
}
void CloseBanTimer(int target)
{
	if (g_BanExpireTimer[target] != INVALID_HANDLE && CloseHandle(g_BanExpireTimer[target]))
		g_BanExpireTimer[target] = INVALID_HANDLE;
}
void CreateBanTimer(int target, int remainingTime)
{
	// 1 day
	if (remainingTime < 86400)
	{
		DataPack dataPack;

		if (remainingTime)
			g_BanExpireTimer[target] = CreateDataTimer(float(remainingTime), Timer_BanExpire, dataPack, TIMER_FLAG_NO_MAPCHANGE);

		dataPack.WriteCell(target);
		dataPack.WriteCell(GetClientUserId(target));
	}
}

//If you unload the admin menu, we don't want to keep using it :/
public void OnLibraryRemoved(const char[] name) {
	if (StrEqual(name, "adminmenu")) {
		g_hAdminMenu = null;
	}
}


/******************************************************************************************
 *                           SPRAY TRACING TO THE HUD/HINT TEXT                           *
 ******************************************************************************************/

int g_iSprayTarget[MAXPLAYERS+1] = {-1, ...};

//0 is last look time, 1 is last actual hud text time
float g_fSprayTraceTime[MAXPLAYERS + 1][2];

//Handles tracing sprays to the HUD or hint message
Action CheckAllTraces(Handle hTimer)
{
	if (!GetClientCount(true))
	{
		return Plugin_Continue;
	}

	char strMessage[128];
	int hudType = (g_bCanUseHUD ? g_iHudLoc : 0);
	float vecPos[3];
	bool bHudParamsSet = false;
	float flGameTime = GetGameTime();

	//Pray for the processor - O(n^2) (but better now)
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsValidClient(client) || IsFakeClient(client))
		{
			g_iSprayTarget[client] = -1;
			continue;
		}

		//We don't want the message to show on our screen for years after we stopped looking at a spray. right?
		switch (hudType)
		{
			case 1: {
				Client_PrintKeyHintText(client, "");
			}
			case 2: {
				Client_PrintHintText(client, "");
			}
			case 3: {
				PrintCenterText(client, "");
			}
		}

		//Make sure you're looking at a valid location.
		if (!GetClientEyeEndLocation(client, vecPos))
		{
			ClearHud(client, hudType, flGameTime);
			continue;
		}

		////Let's check if you can trace admins
		// bool bTraceAdmins = CheckCommandAccess(client, "ssh_hud_can_trace_admins", 0, true);
		// vecPos is where the client is looking
		// g_fSprayVector[client_indx] is where that client's spray is
		float eyePos[3] = {0.0, 0.0, 0.0};
		GetClientEyePosition(client, eyePos);

		// dont check sprays that are kind of far away from the client
		static float tooFar = 65536.0; // 256.0 * 256.0;
		float worldDist = GetVectorDistance(vecPos, eyePos, true);
		if (worldDist >= tooFar)
		{
			ClearHud(client, hudType, flGameTime);
			continue;
		}

		int target = -1;
		for (int curcl = 1; curcl <= MaxClients; curcl++)
		{
			// dist between our mouse and this spray
			float dist = GetVectorDistance(vecPos, g_fSprayVector[curcl]);
			float curshortestdist;
			if
			(
				// our cvar dist
				dist <= g_arrCVars[MAXDIS].FloatValue
				&&
				// dist between our mouse and our last target
				dist > curshortestdist
			)
			{
				target = curcl;
				curshortestdist = dist;
				continue;
			}
		}

		// Lets just figure out what target we're looking at?
		if (!IsValidClient(target))
		{
			ClearHud(client, hudType, flGameTime);
			continue;
		}

		////Check if you're an admin.
		//bool bTargetIsAdmin = CheckCommandAccess(target, "ssh_hud_is_admin", ADMFLAG_GENERIC, true);
		//if (!bTraceAdmins && bTargetIsAdmin) {
		//    ClearHud(client, hudType, flGameTime);
		//    continue;
		//}

		if (CheckForZero(g_fSprayVector[target]))
		{
			ClearHud(client, hudType, flGameTime);
			continue;
		}

		//Generate the text that is to be shown on your screen.
		FormatEx(strMessage, sizeof strMessage, "%T", "HUD Spray", client, g_sAuth[target]);

		// check if this spray is too close to another spray
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsValidClient(i) && i != client && !CheckForZero(g_fSprayVector[i]))
			{
				float spraydist = GetVectorDistance(g_fSprayVector[client], g_fSprayVector[i], true);
				if (spraydist <= 256 /*(16*16)*/ )
				{
					FormatEx(strMessage, sizeof(strMessage), "%T", "HUD Sprays too close", client);
				}
				else if (!highMaxPlayers && spraydist <= 16384 /*(128*128)*/)
				{
					// todo: do we need to clear this entire array? do we even need to do *this*? why is this here
					strMessage[0] = 0x0;
					
					FormatEx(strMessage, sizeof(strMessage), "%T", "HUD Spray", client, g_sAuth[target]);
					//showTraceSquare(g_fSprayVector[target], target, client);
				}
			}
		}


		switch (hudType)
		{
			case 1:
			{
				Client_PrintKeyHintText(client, strMessage);
			}
			//This is annoying af. Need to find a way to fix it.
			case 2:
			{
				Client_PrintHintText(client, strMessage);
			}
			case 3:
			{
				PrintCenterText(client, strMessage);
			}
			case 4:
			{
				if (!bHudParamsSet)
				{
					bHudParamsSet = true;
					//15s sounds reasonable
					//the color tends to get weird if you don't set it different each tick
					SetHudTextParams(0.04, 0.6, 15.0, 255, 12, 39, 240 + (RoundToFloor(flGameTime) % 2), _, 0.2);
				}

				if (flGameTime > g_fSprayTraceTime[client][1] + 14.5 || target != g_iSprayTarget[client]) {
					ShowSyncHudText(client, g_hHUD, strMessage);
					g_iSprayTarget[client] = target;
					g_fSprayTraceTime[client][1] = flGameTime;
				}

				g_fSprayTraceTime[client][0] = flGameTime;
			}
		}
	}

	return Plugin_Continue;
}

bool GetNormalAtPoint(float vec[3], int client)
{
	float clangles[3];
	GetClientEyeAngles(client, clangles);

	Handle hTraceRay = TR_TraceRayEx(vec, clangles, MASK_SHOT, RayType_Infinite);

	if (TR_DidHit(hTraceRay))
	{
		TR_GetPlaneNormal(hTraceRay, NormalForSpray[client]);

		delete hTraceRay;

		return true;
	}
	return false;
}

void ClearHud(int client, int hudType, float gameTime) {
	if (gameTime > g_fSprayTraceTime[client][0] + g_arrCVars[HUDTIME].FloatValue - g_arrCVars[REFRESHRATE].FloatValue) {
		//wow, such repeated code
		if (g_iSprayTarget[client] != -1) {
			if (g_hHUD != null) {
				ClearSyncHud(client, g_hHUD);
			}
			else {
				switch (hudType) {
					case 1: {
						Client_PrintKeyHintText(client, "");
					}
					case 2: {
						Client_PrintHintText(client, "");
					}
					case 3: {
						PrintCenterText(client, "");
					}
				}
			}
		}

		g_iSprayTarget[client] = -1;
	}
}

/******************************************************************************************
 *                           ADMIN MENU METHODS FOR CUSTOM MENU                           *
 ******************************************************************************************/

 //Our custom category needs to know what to do right?
public void CategoryHandler(Handle topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength) {
	if (action == TopMenuAction_DisplayTitle) {
		Format(buffer, maxlength, "%T","SprayCommands", param);
	}

	else if (action == TopMenuAction_DisplayOption) {
		Format(buffer, maxlength, "%T","SprayCommands", param);
	}
}

//When the admin menu is ready, lets define our topmenu object, and add our commands to it.
public void OnAdminMenuReady(Handle aTopMenu) {
	TopMenu topmenu = TopMenu.FromHandle(aTopMenu);

	if (menu_category == INVALID_TOPMENUOBJECT) {
		OnAdminMenuCreated(topmenu);
	}

	if (topmenu == g_hAdminMenu) {
		return;
	}

	g_hAdminMenu = topmenu;

	g_hAdminMenu.AddItem("sm_spraybans", AdminMenu_SprayBans, menu_category, "sm_spraybans", ADMFLAG_KICK);
	g_hAdminMenu.AddItem("sm_spraytrace", AdminMenu_TraceSpray, menu_category, "sm_spraytrace", ADMFLAG_KICK);
	g_hAdminMenu.AddItem("sm_removespray", AdminMenu_SprayRemove, menu_category, "sm_removespray", ADMFLAG_KICK);
	g_hAdminMenu.AddItem("sm_adminspray", AdminMenu_AdminSpray, menu_category, "sm_adminspray", ADMFLAG_KICK);
	g_hAdminMenu.AddItem("sm_sprayban", AdminMenu_SprayBan, menu_category, "sm_sprayban", ADMFLAG_KICK);
	g_hAdminMenu.AddItem("sm_sprayunban", AdminMenu_SprayUnban, menu_category, "sm_sprayunban", ADMFLAG_KICK);
	g_hAdminMenu.AddItem("sm_qremovespray", AdminMenu_QuickSprayRemove, menu_category, "sm_qremovespray", ADMFLAG_KICK);
	g_hAdminMenu.AddItem("sm_removeallsprays", AdminMenu_RemoveAllSprays, menu_category, "sm_removeallsprays", ADMFLAG_UNBAN);
}

//When we have our admin menu created, lets make our custom category.
public void OnAdminMenuCreated(Handle aTopMenu) {
	TopMenu topmenu = TopMenu.FromHandle(aTopMenu);
	/* Block us from being called twice */
	if (topmenu == g_hAdminMenu && menu_category != INVALID_TOPMENUOBJECT) {
		return;
	}

	menu_category = topmenu.AddCategory("Spray Commands", CategoryHandler);
}
/******************************************************************************************
 *                               SQL METHODS FOR SPRAY BANS                               *
 ******************************************************************************************/

 //Connects us to the database and reads the databases.cfg
void SQL_Connector() {
	delete g_Database;

	if (!SQL_CheckConfig("ssh")) {
		SetFailState("PLUGIN STOPPED - Reason: No config entry found for 'ssh' in databases.cfg - PLUGIN STOPPED");
	}

	Database.Connect(SQL_ConnectorCallback, "ssh");
}

//What actually is called to establish a connection to the database.
//public SQL_ConnectorCallback(Handle owner, Handle hndl, const char[] error, any data) {
public void SQL_ConnectorCallback(Database db, const char[] error, any data) {
	if (!db || error[0]) {
		LogError("Connection to SQL database has failed, reason: %s", error);

		g_iConnections++;

		SQL_Connector();

		if (g_iConnections == MAX_CONNECTIONS) {
			SetFailState("Connection to SQL database has failed too many times (%d), plugin unloaded to prevent spam.", MAX_CONNECTIONS);
		}

		return;
	}

	g_Database = db;

	DBDriver dbDriver = g_Database.Driver;
	char driver[16];
	dbDriver.GetIdentifier(driver, sizeof(driver));

	if (StrEqual(driver, "mysql", false)) {
		SQL_LockDatabase(g_Database);
		SQL_FastQuery(g_Database, "SET NAMES \"UTF8\"");
		SQL_UnlockDatabase(g_Database);

		g_Database.Query(SQL_CreateTableCallback, "CREATE TABLE IF NOT EXISTS `ssh` ( \
  			`banID` INT NOT NULL AUTO_INCREMENT, \
  			`auth` VARCHAR(45) NOT NULL, \
  			`name` VARCHAR(45) NULL DEFAULT '<unknown>', \
  			`created` INT NOT NULL, \
  			`ends` INT NOT NULL, \
  			`duration` INT NOT NULL, \
  			`adminID` VARCHAR(45) NOT NULL, \
  			`reason` VARCHAR(64) NULL, \
			`removedType` varchar(1) DEFAULT NULL, \
			`removedBy` varchar(45) NULL, \
			`removedOn` INT NULL, \
  			PRIMARY KEY (`banID`)) ENGINE = InnoDB CHARACTER SET utf8 COLLATE utf8_general_ci;");
	}

	else if (StrEqual(driver, "sqlite", false)) {
		g_Database.Query(SQL_CreateTableCallback, "CREATE TABLE  IF NOT EXISTS `ssh` ( \
			`auth`	VARCHAR(45) NOT NULL, \
			`name`	VARCHAR(45) DEFAULT '<unknown>', \
			`banID`	INTEGER, \
			`created`	INTEGER NOT NULL, \
			`duration`	INTEGER NOT NULL, \
			`ends`	INTEGER NOT NULL, \
			`adminID`	VARCHAR(45) NOT NULL, \
			`reason`	VARCHAR(64), \
			`removedType` varchar(1) DEFAULT NULL, \
			`removedBy` varchar(45) NULL, \
			`removedOn` INT NULL, \
			PRIMARY KEY(`banID` AUTOINCREMENT) );");
	}

	delete dbDriver;
}

//More SQL Stuff
public void SQL_CreateTableCallback(Database db, DBResultSet results, const char[] error, any data) {
	if (!db || !results || error[0]) {
		LogError(error);
		return;
	}

	if (g_bLate) {
		for (int i = 1; i <= MaxClients; i++) {
			if (IsValidClient(i)) {
				OnClientPutInServer(i);
			}
		}
	}
}

//What is called to check in the database if a player is spray banned.
void CheckBan(int client)
{
	if (!IsValidClient(client))
	{
		LogError("Client %L not authed in CheckBan, waiting 5 sec...", client);
		CreateTimer(5.0, timerCheckBan, GetClientUserId(client));
		return;
	}
	
	if (!g_Database || IsClientSourceTV(client))
	{
		return;
	}

	char auth[32];
	if (!GetClientAuthId(client, AuthId_Steam2, auth, 32, true))
	{
		CreateTimer(5.0, timerCheckBan, GetClientUserId(client));
		return;
	}
	
	char escapedAuth[64];
	g_Database.Escape(auth, escapedAuth, sizeof(escapedAuth));
	
	char query[1024];

	g_Database.Format(query, sizeof(query), "\
	SELECT `auth`, `created`, `ends`, `duration`, `adminID`, `reason` \
	FROM `ssh` WHERE `auth` = '%s' AND `removedType` IS NULL \
	AND (`duration` = 0 OR `ends` > UNIX_TIMESTAMP()) LIMIT 1", escapedAuth);

	g_Database.Query(sqlQuery_CheckBan, query, GetClientUserId(client));
}

public Action timerCheckBan(Handle timer, int userid) {
	int client = GetClientOfUserId(userid);
	if (!client)
	{
		return Plugin_Stop;
	}

	CheckBan(client);

	return Plugin_Stop;
}

public void sqlQuery_CheckBan(Database db, DBResultSet results, const char[] error, int userid) {
	if (!db || !results || error[0])
	{
		LogError("CheckBan query failed. (%s)", error);
		return;
	}

	int client = GetClientOfUserId(userid);

	if (results.HasResults && results.RowCount && results.FetchRow())
	{
		
		char auth[MAX_AUTHID_LENGTH];
		char authAdmin[MAX_AUTHID_LENGTH];
		char reason[64];

		results.FetchString(0, auth, sizeof(auth));
		int created = results.FetchInt(1);
		int ends = results.FetchInt(2);
		int duration = results.FetchInt(3);
		results.FetchString(4, authAdmin, sizeof(authAdmin));
		results.FetchString(5, reason, sizeof(reason));

		AdminId adm = FindAdminByIdentity("steam", authAdmin);
		char admName[MAX_NAME_LENGTH];
		adm.GetUsername(admName, sizeof(admName));
		
		SprayBan banInfo;
		banInfo.adminSteamID = authAdmin;
		strcopy(banInfo.reason, sizeof(banInfo.reason), reason);
		banInfo.startTime = created;
		banInfo.endTime = ends;
		banInfo.length = duration;
		banInfo.auth = auth;
		
		char clientKey[16];
		IntToString(client, clientKey, sizeof(clientKey));
		SetTrieArray(SpraybansMap, clientKey, banInfo, sizeof(banInfo), true);

		int timeLeft = ends - GetTime();
		if (timeLeft < 86400)
			CreateBanTimer(client, timeLeft);
	}
}

/******************************************************************************************
 *                           OUR HOOKS :D TO ACTUALLY DO STUFF                            *
 ******************************************************************************************/

 //When a player trys to spray a decal.
public Action Player_Decal(const char[] name, const int[] clients, int count, float delay) {
	//Is this plugin enabled? If not then no need to run the rest of this.
	if (!g_arrCVars[ENABLED].BoolValue) {
		return Plugin_Continue;
	}

	//Gets the client that is spraying.
	int client = TE_ReadNum("m_nPlayer");

	if (client >= 65)
	{
		CPrintToChat(client, "%s Due to an ongoing TF2 bug involving players with client slots over 64 spraying the wrong spray, you have been blocked from spraying. Sorry!" ,PREFIX);
		CPrintToChat(client, "%s For more info, see https://github.com/ValveSoftware/Source-1-Games/issues/5266.",PREFIX);
	}

	//Is this even a valid client?
	if (IsValidClient(client) && !IsClientReplay(client) && !IsClientSourceTV(client)) {
		//We need to check if this player is spray banned, and if so, we will pre hook this spray attempt and block it.
		char clientKey[16];
		IntToString(client, clientKey, sizeof(clientKey));
		if (SpraybansMap.ContainsKey(clientKey)){
			CPrintToChat(client, "%s%T", PREFIX, "You are SprayBanned Reply", client);
			return Plugin_Handled;
		}

		//If we're here, they are obviously not spray banned. So lets find where they are spraying.
		float fSprayVector[3];
		TE_ReadVector("m_vecOrigin", fSprayVector);

		//Now we need to check if this spray is too close to another spray if sm_ssh_overlap > 0
		if (g_arrCVars[ANTIOVERLAP].FloatValue > 0) {
			for (int i = 1; i <= MaxClients; i++) {
				if (IsValidClient(i) && i != client && !CheckForZero(g_fSprayVector[i])) {
					if (GetVectorDistance(fSprayVector, g_fSprayVector[i]) <= g_arrCVars[ANTIOVERLAP].FloatValue) {
						char clientName[MAX_NAME_LENGTH];
						GetClientName(i, clientName, sizeof clientName);
						PrintToChat(client ,"%s%T", PREFIX, "Your Spray too close Reply", client, clientName);

						return Plugin_Handled;
					}
				}
			}
		}

		//Either anti-overlapping isn't enabled or the spray was sprayed in an ok location
		//Now Let's store the Sprays Location, Time of Spray, Who Sprayed it, and the ID of the player.
		g_fSprayVector[client] = fSprayVector;
		g_arrSprayTime[client] = RoundFloat(GetGameTime());
		GetClientName(client, g_arrSprayName[client], sizeof g_arrSprayName[]);
		if (!GetClientAuthId(client, AuthId_Steam2, g_arrSprayID[client], sizeof g_arrSprayID[])) {
			g_arrSprayID[client][0] = '\0';
		}

		//This is where we generate what is displayed when tracing a spray to HUD/Hint
		g_sAuth[client][0] = '\0';

		//If our math variable includes a 1 in it, we will add the player's name into the string.
		if (g_arrCVars[AUTH].IntValue & 1) {
			Format(g_sAuth[client], sizeof g_sAuth[], "%s%N", g_sAuth[client], client);
		}

		//If our math variable includes a 2 in it, we will add the player's STEAM_ID into the string.
		if (g_arrCVars[AUTH].IntValue & 2) {
			Format(g_sAuth[client], sizeof g_sAuth[], "%s%s(%s)", g_sAuth[client], g_arrCVars[AUTH].IntValue & 1 ? "\n" : "", g_arrSprayID[client]);
		}

		//And lastly, if our math variable includes a 4 in it, we simply add the IP into the string.
		if (g_arrCVars[AUTH].IntValue & 4) {
			char IP[32];
			GetClientIP(client, IP, sizeof IP);

			Format(g_sAuth[client], sizeof g_sAuth[], "%s%s(%s)", g_sAuth[client], g_arrCVars[AUTH].IntValue & (1|2) ? "\n" : "", IP);
		}
	}

	GetNormalAtPoint(g_fSprayVector[client], client);

	//Now we're done here.
	return Plugin_Continue;
}

//When the Location cvar changes, this is called
public void LocationChanged(ConVar hConVar, const char[] szOldValue, const char[] szNewValue) {
	g_iHudLoc = hConVar.IntValue;
	g_arrCVars[LOCATION].SetInt(StringToInt(szNewValue), true, false);
}

/******************************************************************************************
 *                                   SPRAY BANNING >.>                                    *
 ******************************************************************************************/

 //What decides what happens when you select the Spray Ban option in the admin menu
public void AdminMenu_SprayBan(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength) {
	if (action == TopMenuAction_DisplayOption) {
		Format(buffer, maxlength, "%T", "Menu SprayBan", param);
	}
	else if (action == TopMenuAction_SelectOption) {
		Menu menu = new Menu(MenuHandler_SprayBan);
		menu.SetTitle("%T", "Menu SprayBan", param);

		int count;

		for (int i = 1; i <= MaxClients; i++) {
			if (!IsValidClient(i) || IsClientReplay(i) || IsClientSourceTV(i)) {
				continue;
			}
			char targetS[MAX_TARGET_LENGTH];
			IntToString(i, targetS, sizeof(targetS));
			
			if (SpraybansMap.ContainsKey(targetS)) {
				continue;
			}

			char targetID[8];
			char name[MAX_NAME_LENGTH];

			IntToString(GetClientUserId(i), targetID, sizeof targetID);
			GetClientName(i, name, MAX_NAME_LENGTH);

			menu.AddItem(targetID, name, CanUserTarget(param, i) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
			count++;
		}

		if (!count) {
			char display[64];
			FormatEx(display, sizeof(display), "%T", "Menu No Targets", param);
			
			menu.AddItem("none", display, ITEMDRAW_DISABLED);
		}

		menu.ExitBackButton = true;

		menu.Display(param, MENU_TIME_FOREVER);
	}
}

//What happens when you use the spray ban menu?
public int MenuHandler_SprayBan(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Select: {
			char targetID[8];
			menu.GetItem(param2, targetID, sizeof targetID);
			AdminMenu_SpraybanDuration(param1, StringToInt(targetID));
		}
		case MenuAction_Cancel: {
			if (param2 == MenuCancel_ExitBack) {
				RedisplayAdminMenu(g_hAdminMenu, param1);
			}
		}
		case MenuAction_End: {
			delete menu;
		}
	}
	return 0;
}

void AdminMenu_SpraybanDuration(int client, int target){
	Menu menu = new Menu(MenuHandler_SpraybanDuration);
	char buffer[192];
	menu.SetTitle("%T","Menu Sprayban Duration", client);
	menu.ExitBackButton = true;

	// duration in days because of GetCmdArgsTTR()
	int durationArr[] = {1,7, 14, 30,90,365};
	char durationStr[][] = {"1 день", "7 дней", "2 недели", "1 месяц", "3 месяца", "1 год"};

	for (int i = 0; i < sizeof durationArr; i++)
	{
			Format(buffer, sizeof(buffer), "%d;%d",target, durationArr[i]) ; // TargetID index_of_Time
			menu.AddItem(buffer, durationStr[i]);
	}

	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_SpraybanDuration(Menu menu, MenuAction action, int param1, int param2){
	switch (action)
	{
		case MenuAction_End:
			delete menu;
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack && g_hAdminMenu != INVALID_HANDLE)
				g_hAdminMenu.Display(param1, TopMenuPosition_LastCategory);
		}
		case MenuAction_Select:
		{
			char sOption[192], sTemp[2][64];
			menu.GetItem(param2, sOption, sizeof(sOption));
			// TargetID  duration_in_sec
			ExplodeString(sOption, ";", sTemp, 2, 64);
			int targetSlot = GetClientOfUserId(StringToInt(sTemp[0]));

			if (IsValidClient(targetSlot))
			{
				int duration = StringToInt(sTemp[1]);
				AdminMenu_SpraybanReason(param1, StringToInt(sTemp[0]), duration);
			}
		}
	}
	return 0;
}

void AdminMenu_SpraybanReason(int client, int target, int duration)
{
	Menu menu = new Menu(MenuHandler_SpraybanReason);
	char buffer[192];
	menu.SetTitle("%T","Menu Sprayban Reason", client);
	menu.ExitBackButton = true;

	char reasons[][] = {"Нацистская символика", "Порнография", "Политика"};

	for (int i = 0; i < sizeof reasons; i++)
	{
			Format(buffer, sizeof(buffer), "%d;%d;%s",target, duration,reasons[i]); // TargetID index_of_Time reason
			menu.AddItem(buffer, reasons[i]);
	}
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_SpraybanReason(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End:
			delete menu;
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack && g_hAdminMenu != INVALID_HANDLE)
				g_hAdminMenu.Display(param1, TopMenuPosition_LastCategory);
		}
		case MenuAction_Select:
		{
			char sOption[192], sTemp[3][64];
			menu.GetItem(param2, sOption, sizeof(sOption));
			// TargetID  duration_in_sec reason
			ExplodeString(sOption, ";", sTemp, 3, 64);
			int target = GetClientOfUserId(StringToInt(sTemp[0]));

			if (IsValidClient(target))
			{
				int duration = StringToInt(sTemp[1]);
				char reason[64];
				strcopy(reason, sizeof(reason), sTemp[2]);
				FakeClientCommand(param1, "sm_sban #%s %d %s", sTemp[0], duration, reason);
			}
		}
	}
	return 0;
}



/******************************************************************************************
 *                                 SPRAY UN-BANNING >.>                                   *
 ******************************************************************************************/

//What handles when you select to Un-Spray ban someone
public void AdminMenu_SprayUnban(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength) {
	if (action == TopMenuAction_DisplayOption) {
		Format(buffer, maxlength, "%T","Menu SprayUnban", param);
	}
	else if (action == TopMenuAction_SelectOption) {
		Menu menu = new Menu(MenuHandler_SprayUnban);
		menu.SetTitle("%T","Menu SprayUnban", param);

		int count;

		for (int i = 1; i <= MaxClients; i++) {
			if (!IsValidClient(i) || IsClientReplay(i) || IsClientSourceTV(i)) {
				continue;
			}
			char targetS[MAX_TARGET_LENGTH];
			IntToString(i, targetS, sizeof(targetS));
			
			if (!SpraybansMap.ContainsKey(targetS)) {
				continue;
			}

			char targetID[8];
			char name[MAX_NAME_LENGTH];

			IntToString(GetClientUserId(i), targetID, sizeof targetID);
			GetClientName(i, name, MAX_NAME_LENGTH);

			menu.AddItem(targetID, name, CanUserTarget(param, i) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
			count++;
		}

		if (!count) {
			char display[64];
			FormatEx(display, sizeof(display), "%T", "Menu No Targets", param);
			
			menu.AddItem("none", display), ITEMDRAW_DISABLED;
		}

		menu.ExitBackButton = true;

		menu.Display(param, MENU_TIME_FOREVER);
	}
}

//What handles your selection on who to unspray ban.
public int MenuHandler_SprayUnban(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Select: {
			char info[8];
			menu.GetItem(param2, info, 8);

			FakeClientCommand(param1, "sm_sunban #%d", StringToInt(info));
		}
		case MenuAction_Cancel: {
			if (param2 == MenuCancel_ExitBack) {
				RedisplayAdminMenu(g_hAdminMenu, param1);
			}
		}
		case MenuAction_End: {
			delete menu;
		}
	}

	return 0;
}

/******************************************************************************************
 *                              LISTING OUR SPRAYBANNED PLAYERS                           *
 ******************************************************************************************/

//What happens when you run sm_spraybans
public Action Command_Spraybans(int client, int args) {
	if (!IsValidClient(client)) {
		return Plugin_Handled;
	}

	if (!g_arrCVars[ENABLED].BoolValue) {
		ReplyToCommand(client, "[SM] This plugin is currently disabled.");
		return Plugin_Handled;
	}

	ShowSpraybanListOptions(client);

	return Plugin_Handled;
}
 
 
 //What is called to display the Options Menu
 void ShowSpraybanListOptions(int client) {
	Menu menu = new Menu(MenuHandler_ListOptions);
	menu.SetTitle("%T","Menu SprayBanList", client);

	char title1[64], title2[64];
	Format(title1, sizeof(title1), "%T", "Menu AllOnlinePlayers", client);
	Format(title2, sizeof(title1), "%T", "Menu AllPlayers", client);
	
	menu.AddItem("1", title1);
	menu.AddItem("2", title2);

	menu.ExitButton = true;

	menu.Display(client, MENU_TIME_FOREVER);
 }

//Menu Handler for the Options Menu
int MenuHandler_ListOptions(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Select: {
			char choice[32];
			menu.GetItem(param2, choice, sizeof(choice));

			switch (StringToInt(choice)) {
				case 1: {
					DisplayOnlineSprayBans(param1);
				}
				case 2: {
					char query[1024];

					g_Database.Format(query, sizeof(query), "\
					SELECT `auth`, `name`, `created`, `ends`, `duration`, `adminID`, `reason` \
					FROM `ssh` WHERE `removedType` IS NULL \
					AND (`duration` = 0 OR `ends` > UNIX_TIMESTAMP())");
					
					g_Database.Query(AllSprayBansCallback, query, GetClientUserId(param1));
				}
			}
		}     			
		case MenuAction_End: {
			delete menu;
		}
	}
	return 0;
}

//What happens when you select to list currently connected spray banned players?
void AdminMenu_SprayBans(TopMenu topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength) {
	switch (action) {
		case TopMenuAction_DisplayOption: {
			Format(buffer, maxlength, "%T","Menu SprayBanList", param);
		}
		case TopMenuAction_SelectOption: {
			ShowSpraybanListOptions(param);
		}
	}
}


//Display the currently connected spray banned players.
void DisplayOnlineSprayBans(int client) {
	Menu menu = new Menu(MenuHandler_OnlineSprayBans);
	
	menu.SetTitle("%T","Menu Blocked Players", client);


	for (int i = 1; i <= MaxClients; i++) {
		if (IsValidClient(i)) {
			char clientS[MAX_TARGET_LENGTH];
			IntToString(i, clientS, sizeof clientS);
			if (SpraybansMap.ContainsKey(clientS)) {
				char auth[MAX_STEAMAUTH_LENGTH];
				if (!GetClientAuthId(i, AuthId_Steam2, auth, sizeof auth)) {
					strcopy(auth, sizeof auth, "SteamID Unavailable");
				}

				char name[MAX_NAME_LENGTH];
				GetClientName(i, name, sizeof name);

				int info = GetClientUserId(i);
				char infoS[64];
				
				IntToString(info, infoS, sizeof(infoS));

				menu.AddItem(infoS, name);
			}
		}
	}
	if (menu.ItemCount == 0) {
		char display[64];
		FormatEx(display, sizeof(display), "%T", "Menu No Targets", client);
		menu.AddItem("none", display, ITEMDRAW_DISABLED);
	}
	menu.ExitButton = true;
	menu.ExitBackButton = true;

	menu.Display(client, MENU_TIME_FOREVER);
}

//Menu HAndler for the spray bans menu
int MenuHandler_OnlineSprayBans(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Select: {

			char info[MAX_TARGET_LENGTH];
			menu.GetItem(param2, info, MAX_TARGET_LENGTH);
			int target = StringToInt(info);

			FakeClientCommand(param1, "sm_spraystatus #%d", target);
		}
		case MenuAction_Cancel: {
			if (param2 == MenuCancel_ExitBack) {
				ShowSpraybanListOptions(param1);
			}
		}
		case MenuAction_End: {
			delete menu;
		}
	}
	return 0;
}

//What is called to list all the spray bans there are in a database
void AllSprayBansCallback(Database db, DBResultSet results, const char[] error, any data) {
	if (!db || !results || error[0]) {
		LogError("SQL error in Listing All Spray Bans: %s", error);
		return;
	}

	int client = GetClientOfUserId(data);

	if (!IsValidClient(client)) {
		return;
	}
	
	Menu menu = new Menu(MenuHandler_AllSpraybans);
	menu.SetTitle("%T","Menu Blocked Players", client);
	
	if (results.HasResults && results.RowCount){
		char auth[MAX_STEAMAUTH_LENGTH],
		name[MAX_NAME_LENGTH],
		admID[MAX_AUTHID_LENGTH],
		reason[64],
		info[256];
		int createdTime, endsTime, duration;

	//SELECT `auth`, `name`, `created`, `ends`, `duration`, `adminID`, `reason` 
		while(results.FetchRow()){
			results.FetchString(0, auth, sizeof(auth));
			results.FetchString(1, name, sizeof(name));
			createdTime = results.FetchInt(2);
			endsTime = results.FetchInt(3);
			duration = results.FetchInt(4);
			results.FetchString(5, admID, sizeof(admID));
			results.FetchString(6, reason, sizeof(reason));
			
			FormatEx(info,sizeof info, "%s;%s;%d;%d;%d;%s;%s", auth, name, createdTime, endsTime, duration, admID, reason);

			char display[64];
			FormatEx(display, sizeof(display), "%s - %s", auth, name);
			
			menu.AddItem(info, display);
		}	
	}

	if (!menu.ItemCount) {
		char display[64];
		FormatEx(display, sizeof(display), "%T", "Menu No Targets", client);
		menu.AddItem("none", display, ITEMDRAW_DISABLED);
	}
	menu.ExitButton = true;
	menu.ExitBackButton = true;

	menu.Display(client, MENU_TIME_FOREVER);
}

//Menu Handler for the full list of spray banned players
public int MenuHandler_AllSpraybans(Menu menu, MenuAction action, int param1, int param2) {
	switch (action) {
		case MenuAction_Select: {
			char infoBuf[256], temp[7][64], name[MAX_NAME_LENGTH];
			menu.GetItem(param2, infoBuf, sizeof(infoBuf));
			ExplodeString(infoBuf, ";", temp, 7, 64);
			
			//SELECT `auth`, `name`, `created`, `ends`, `duration`, `adminID`, `reason` 
			SprayBan banInfo;
			strcopy(banInfo.auth, sizeof(banInfo.auth), temp[0]);
			strcopy(name, sizeof(name), temp[1]);
			banInfo.startTime = StringToInt(temp[2]);
			banInfo.endTime = StringToInt(temp[3]);
			banInfo.length = StringToInt(temp[4]);
			strcopy(banInfo.adminSteamID, sizeof(banInfo.adminSteamID), temp[5]);
			strcopy(banInfo.reason, sizeof(banInfo.reason), temp[6]);

			ShowBlockMenu(param1, banInfo, name);
		}
		case MenuAction_Cancel: {
			if (param2 == MenuCancel_ExitBack) {
				ShowSpraybanListOptions(param1);
			}
		}
		case MenuAction_End: {
			delete menu;
		}
	}
	return 0;
}

/******************************************************************************************
 *                                         TIMERS :D                                      *
 ******************************************************************************************/

//sm_spray_refresh handlers for tracing to HUD or hint message
public void TimerChanged(ConVar hConVar, const char[] szOldValue, const char[] szNewValue) {
	delete g_hSprayTimer;
	CreateTimers();
}

//Now we make the timers, and start them up.
stock void CreateTimers() {
	float timer = g_arrCVars[REFRESHRATE].FloatValue;

	if (timer > 0.0) {
		g_hSprayTimer = CreateTimer(timer, CheckAllTraces, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
}

/******************************************************************************************
 *                                     TRACING SPRAYS                                     *
 ******************************************************************************************/

//What happens when you run the !sm_spraytrace command?
public Action Command_TraceSpray(int client, int args) {
	
	if (!g_arrCVars[ENABLED].BoolValue) {
		ReplyToCommand(client, "[SM] This plugin is currently disabled.");
		return Plugin_Handled;
	}
	
	if (!IsValidClient(client)) {
		return Plugin_Handled;
	}

	float vecPos[3];

	if (GetClientEyeEndLocation(client, vecPos))
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (GetVectorDistance(vecPos, g_fSprayVector[i]) <= g_arrCVars[MAXDIS].FloatValue)
			{
				

				CPrintToChat(client, "%s%T", PREFIX, "Spray By", client, g_arrSprayName[i], (RoundFloat(GetGameTime() - g_arrSprayTime[i])));
				//GlowEffect(client, g_fSprayVector[i], 2.0, 0.3, 255, g_PrecacheRedGlow);

				if (!highMaxPlayers)
				{
					//showTraceSquare(g_fSprayVector[i], i, client);
				}

				if (CanUserTarget(client, i))
					PunishmentMenu(client, i);

				return Plugin_Handled;
			}
		}
	}

	CPrintToChat(client,"%s%T", PREFIX, "No Spray", client);

	return Plugin_Handled;
}

//Crashes the client on some servers
stock void showTraceSquare(float vec[3], int client, int lookingclient){
	// get normal angle for this spray
	float vnormal[3];
	vnormal = NormalForSpray[client];

	// we set teamcolor here, so spray box glows the clients team color
	int teamcolor[4];
	TFTeam team = TF2_GetClientTeam(client);

	if (team == TFTeam_Red)
	{
		teamcolor = {255, 128, 128, 128};
	}
	else if (team == TFTeam_Blue)
	{
		teamcolor = {128, 128, 255, 128};
	}
	else
	{
		teamcolor = {255, 255, 255, 128};
	}
	// get src world pos of spray
	float spraypos[3];
	spraypos = vec;

	// not a perfectly vertical wall OR on the ground - draw a box
	if (vnormal[2] != 0.0)
	{
		// 64 unit^3 cube
		float mins[3] = {-32.0, -32.0, -32.0};
		float maxs[3] = {32.0, 32.0, 32.0};

		// add cube vec to our pos to get the worldpos of our cube minmaxs
		AddVectors(spraypos, mins, mins);
		AddVectors(spraypos, maxs, maxs);
		// send the box
		TE_SendBeamBox
		(
			mins,                                       // upper corner
			maxs,                                       // lower corner
			laser,                                      // model index
			0,                                          // halo index
			0,                                          // startfame
			1,                                          // framerate
			0.5,                                        // lifetime
			1.0,                                        // Width
			1.0,                                        // endwidth
			1,                                          // fadelength
			1.0,                                        // amplitude
			teamcolor,                                  // color
			1,                                          // speed
			lookingclient                               // client to send to
		);
		return;

	}

    /*

          sprays are 64x64

                 64
        tleft --------- tright
          |       |       |
          |       | 32    |
          |       |   32  |
 vleft -> *       o-------* <- vright
          |       ^       |
          |    spraypos   |
        bleft --------- bright

    dist from center of spray is sqrt(2048) ftr because pythag. theorum

    the normal vector vnormal is sticking OUT from spraypos in 3d but i'm not drawing that in a code comment

    */

	// normalize our normal vector - that is, a vector perpendicular to the plane of the wall this spray is on
	NormalizeVector(vnormal, vnormal);
	// scale it so we have a 64x64 square
	ScaleVector(vnormal, 32.0);

	// get a vector perpendicular to our normal, aka a vector on the plane
	// this one happens to be always right because we handle z != 0 earlier
	float vright[3];
	vright[0] = -vnormal[1];
	vright[1] = vnormal[0];
	vright[2] = vnormal[2];

	//float normal[3];
	//float right[3];
	//float left[3];

	// we're gonna make a left vector by negativing our right vector
	float vleft[3];
	// negate our vector
	NegateVector(vright);
	// assign it
	vleft = vright;
	// uninvert it because sourcemod is fucking moronic
	NegateVector(vright);

	// top left, top right, bottom left, bottom right, geometric vector variables
	float tl_v[3];
	float tr_v[3];
	float br_v[3];
	float bl_v[3];

	// set up our square corners
	tl_v    = vleft;
	tl_v[2] = vleft[2] + 32.0;
	tr_v    = vright;
	tr_v[2] = vright[2] + 32.0;

	bl_v    = vleft;
	bl_v[2] = vleft[2] - 32.0;
	br_v    = vright;
	br_v[2] = vright[2] - 32.0;

	// our ACTUAL coords
	float tl[3];
	float tr[3];
	float br[3];
	float bl[3];


	// add our vectors to the spray pos
	AddVectors(spraypos, tl_v, tl);
	AddVectors(spraypos, tr_v, tr);
	AddVectors(spraypos, br_v, br);
	AddVectors(spraypos, bl_v, bl);


	// and we're in buisness!
	TE_SendBeamSq
	(
	tl,
	tr,
	br,
	bl,
	laser,                                      // model index
	0,                                          // halo index
	0,                                          // startfame
	1,                                          // framerate
	0.5,                                        // lifetime
	2.0,                                        // Width
	2.0,                                        // endwidth
	1,                                          // fadelength
	1.0,                                        // amplitude
	teamcolor,                                  // color
	1,                                          // speed
	lookingclient                               // client to send to
	);
}

// send a square with te_beams
void TE_SendBeamSq
(
	float tleft[3],
	float tright[3],
	float bright[3],
	float bleft[3],
	int ModelIndex,
	int HaloIndex,
	int StartFrame,
	int FrameRate,
	float Life,
	float Width,
	float EndWidth,
	int FadeLength,
	float Amplitude,
	const int Color[4],
	int Speed,
	int client
)
{
	// yeah it's a square
	TE_SetupBeamPoints(tleft, tright, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(tright, bright, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(bright, bleft, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(bleft, tleft, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
}

/* debug stock for sending a normal
void TE_SendBeamNormal
(
	float origin[3],
	float normal[3],
	float unnormal[3],
	int ModelIndex,
	int HaloIndex,
	int StartFrame,
	int FrameRate,
	float Life,
	float Width,
	float EndWidth,
	int FadeLength,
	float Amplitude,
	const int Color[4],
	int Speed,
	int client
)
{
	// yeah it's a square
	TE_SetupBeamPoints(origin, normal, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, {0, 0, 255, 255}, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(origin, unnormal, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, {255, 0, 255, 255}, Speed);
	TE_SendToClient(client);
}
*/

// just a stupid "send beam box" stock, i didn't write this
stock void TE_SendBeamBox
(
	float uppercorner[3],
	const float bottomcorner[3],
	int ModelIndex,
	int HaloIndex,
	int StartFrame,
	int FrameRate,
	float Life,
	float Width,
	float EndWidth,
	int FadeLength,
	float Amplitude,
	const int Color[4],
	int Speed,
	int client
)
{
	// Create the additional corners of the box
	float tc1[3];
	AddVectors(tc1, uppercorner, tc1);
	tc1[0] = bottomcorner[0];

	float tc2[3];
	AddVectors(tc2, uppercorner, tc2);
	tc2[1] = bottomcorner[1];

	float tc3[3];
	AddVectors(tc3, uppercorner, tc3);
	tc3[2] = bottomcorner[2];

	float tc4[3];
	AddVectors(tc4, bottomcorner, tc4);
	tc4[0] = uppercorner[0];

	float tc5[3];
	AddVectors(tc5, bottomcorner, tc5);
	tc5[1] = uppercorner[1];

	float tc6[3];
	AddVectors(tc6, bottomcorner, tc6);
	tc6[2] = uppercorner[2];

	// Draw all the edges
	TE_SetupBeamPoints(uppercorner, tc1, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(uppercorner, tc2, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(uppercorner, tc3, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(tc6, tc1, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(tc6, tc2, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(tc6, bottomcorner, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(tc4, bottomcorner, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(tc5, bottomcorner, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(tc5, tc1, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(tc5, tc3, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(tc4, tc3, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	TE_SetupBeamPoints(tc4, tc2, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, Color, Speed);
	TE_SendToClient(client);
	//TE_SetupBeamPoints(uppercorner, bottomcorner, ModelIndex, HaloIndex, StartFrame, FrameRate, Life, Width, EndWidth, FadeLength, Amplitude, {255, 0, 0, 255}, Speed);
	//TE_SendToClient(client);
}

//Admin Menu Handler for the spray trace function.
public void AdminMenu_TraceSpray(TopMenu hTopMenu, TopMenuAction action, TopMenuObject tmoObjectID, int param, char[] szBuffer, int iMaxLength) {
	if (!IsValidClient(param)) {
		return;
	}

	switch (action) {
		case TopMenuAction_DisplayOption: {
			Format(szBuffer, iMaxLength, "%T", "Menu Trace", param);
		}
		case TopMenuAction_SelectOption: {
			Command_TraceSpray(param, 0);
		}
	}
}

/******************************************************************************************
 *                                    REMOVING SPRAYS                                     *
 ******************************************************************************************/

 //What happens when you run sm_removespray?
public Action Command_RemoveSpray(int client, int args) {
	
	if (!g_arrCVars[ENABLED].BoolValue) {
		ReplyToCommand(client, "[SM] This plugin is currently disabled.");
		return Plugin_Handled;
	}
	
	if (!IsValidClient(client)) {
		return Plugin_Handled;
	}

	float vecPos[3];

	if (GetClientEyeEndLocation(client, vecPos)) {
		char szAdminName[32];

		GetClientName(client, szAdminName, sizeof szAdminName);

		for (int i = 1; i <= MaxClients; i++) {
			if (GetVectorDistance(vecPos, g_fSprayVector[i]) <= g_arrCVars[MAXDIS].FloatValue) {
								
				if(!CanUserTarget(client, i)){
					char iName[MAX_NAME_LENGTH];
					GetClientName(i, iName, sizeof iName);
					CReplyToCommand(client, "%s%T", PREFIX, "Admin Immune", client, iName);
					return Plugin_Handled;
				}			
				
				SprayNullDecal(i);

				CPrintToChat(client, "%s%T", PREFIX, "Spray Removed", client, g_arrSprayName[i], szAdminName);
				//LogAction(client, -1, "[SSH] %T", "Spray Removed", LANG_SERVER, g_arrSprayName[i], g_arrSprayID[i], szAdminName);
				PunishmentMenu(client, i);

				return Plugin_Handled;
			}
		}
	}

	CPrintToChat(client, "%s%T", PREFIX, "No Spray", client);

	return Plugin_Handled;
}

//Admin menu handler for the Spray Removal selection
public void AdminMenu_SprayRemove(TopMenu hTopMenu, TopMenuAction action, TopMenuObject tmoObjectID, int param, char[] szBuffer, int iMaxLength) {
	if (!IsValidClient(param)) {
		return;
	}

	switch (action) {
		case TopMenuAction_DisplayOption: {
			Format(szBuffer, iMaxLength, "%T", "Menu Remove", param);
		}
		case TopMenuAction_SelectOption: {
			Command_RemoveSpray(param, 0);
		}
	}
}

/******************************************************************************************
 *                                 QUICK REMOVING SPRAYS                                  *
 ******************************************************************************************/

 //What happens when you run !sm_qremovespray?
public Action Command_QuickRemoveSpray(int client, int args) {
	
	if (!g_arrCVars[ENABLED].BoolValue) {
		ReplyToCommand(client, "[SM] This plugin is currently disabled.");
		return Plugin_Handled;
	}
	
	if (!IsValidClient(client)) {
		return Plugin_Handled;
	}

	float vecPos[3];

	if (GetClientEyeEndLocation(client, vecPos)) {
		char szAdminName[MAX_NAME_LENGTH];

		GetClientName(client, szAdminName, sizeof szAdminName);

		for (int i = 1; i <= MaxClients; i++) {
			if (GetVectorDistance(vecPos, g_fSprayVector[i]) <= g_arrCVars[MAXDIS].FloatValue) {
				
				if(!CanUserTarget(client, i)){
					char iName[MAX_NAME_LENGTH];
					GetClientName(i, iName, sizeof iName);
					CReplyToCommand(client, "%s%T", PREFIX, "Admin Immune", client, iName);
					return Plugin_Handled;
				}

				SprayNullDecal(i);

				CPrintToChat(client, "%s%T", PREFIX, "Spray Removed", client, g_arrSprayName[i], szAdminName);
				//LogAction(client, -1, "[SSH] %T", "Spray Removed", LANG_SERVER, g_arrSprayName[i], g_arrSprayID[i], szAdminName);

				return Plugin_Handled;
			}
		}
	}

	CPrintToChat(client, "%s%T", PREFIX, "No Spray", client);

	return Plugin_Handled;
}

//Admin Menu handler for the QuickSprayRemove Selection
public void AdminMenu_QuickSprayRemove(TopMenu hTopMenu, TopMenuAction action, TopMenuObject tmoObjectID, int param, char[] szBuffer, int iMaxLength) {
	if (!IsValidClient(param)) {
		return;
	}

	switch (action) {
		case TopMenuAction_DisplayOption: {
			Format(szBuffer, iMaxLength, "%T","Menu QuickRemove", param);
		}
		case TopMenuAction_SelectOption: {
			Command_QuickRemoveSpray(param, 0);
			g_hAdminMenu.Display(param, TopMenuPosition_LastCategory);
		}
	}
}

/******************************************************************************************
 *                                  Removing All Sprays                                   *
 ******************************************************************************************/

public Action Command_RemoveAllSprays(int client, int args) {
	
	if (!g_arrCVars[ENABLED].BoolValue) {
		ReplyToCommand(client, "[SM] This plugin is currently disabled.");
		return Plugin_Handled;
	}
	
	if (!IsValidClient(client)) {
		return Plugin_Handled;
	}

	for (int i = 1; i <= MaxClients; i++) {
		SprayNullDecal(i);
	}

	char AdminName[MAX_NAME_LENGTH];
	GetClientName(client, AdminName, sizeof AdminName);
	LogAction(client, -1, "All sprays has been removed by %L", client);
	CShowActivity2(client, "", "%s%T", PREFIX, "AllSpraysRemoved",client, AdminName);

	return Plugin_Handled;
}

//Admin Menu handler for the RemoveAll Selection
public void AdminMenu_RemoveAllSprays(TopMenu hTopMenu, TopMenuAction action, TopMenuObject tmoObjectID, int param, char[] szBuffer, int iMaxLength) {
	if (!IsValidClient(param)) {
		return;
	}

	switch (action) {
		case TopMenuAction_DisplayOption: {
			Format(szBuffer, iMaxLength, "%T","Menu RemoveAll", param);
		}
		case TopMenuAction_SelectOption: {
			Command_RemoveAllSprays(param, 0);
			g_hAdminMenu.Display(param, TopMenuPosition_LastCategory);
		}
	}
}

/******************************************************************************************
 *                                     ADMIN SPRAYING                                     *
 ******************************************************************************************/

//What happens when you run the !sm_adminspray <target> command.
public Action Command_AdminSpray(int client, int args) {
	
	if (!g_arrCVars[ENABLED].BoolValue) {
		ReplyToCommand(client, "[SM] This plugin is currently disabled.");
		return Plugin_Handled;
	}
	
	if (!IsValidClient(client)) {
		return Plugin_Handled;
	}

	char arg[MAX_NAME_LENGTH];
	int target = client;
	if (args >= 1) {
		GetCmdArg(1, arg, sizeof arg);

		target = FindTarget(client, arg, false, false);
		if (target == -1) 
			return Plugin_Handled;
		
	}

	if (!GoSpray(client, target)) {
		CReplyToCommand(client, "%s%T", PREFIX, "Cannot Spray", client);
	}
	else {
		char clientName[MAX_NAME_LENGTH], targetName[MAX_NAME_LENGTH];
		GetClientName(client, clientName, sizeof(clientName));
		GetClientName(target, targetName, sizeof(targetName));

		CReplyToCommand(client, "%s%T", PREFIX, "Admin Sprayed", client, clientName, targetName);
		//LogAction(client, -1, "[SSH] %T", "Admin Sprayed", LANG_SERVER, client, target);
	}

	return Plugin_Handled;
}

//Displays the admin spray menu and adds targets to it.
void DisplayAdminSprayMenu(int client, int iPos = 0) {
	if (!IsValidClient(client)) {
		return;
	}

	Menu menu = new Menu(MenuHandler_AdminSpray);

	menu.SetTitle("%T", "Admin Spray Menu", client);
	menu.ExitBackButton = true;

	int targetCount;

	for (int i = 1; i <= MaxClients; i++) {
			if (IsValidClient(i)) {
				char iChar[MAX_TARGET_LENGTH];
				IntToString(i, iChar, MAX_TARGET_LENGTH);
				if (!SpraybansMap.ContainsKey(iChar)) {
					if (!IsClientReplay(i) && !IsClientSourceTV(i)) {
						char info[8];
						char name[MAX_NAME_LENGTH];

						IntToString(GetClientUserId(i), info, 8);
						GetClientName(i, name, MAX_NAME_LENGTH);

						menu.AddItem(info, name, (CanUserTarget(client, i) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED));
						targetCount++;
					}
				}
			}
		}
	if (!targetCount){
		char display[64];
		FormatEx(display, sizeof(display), "%T", "Menu No Targets", client);
		menu.AddItem("none", display, ITEMDRAW_DISABLED);	
	}
		
	if (iPos == 0) {
		menu.Display(client, MENU_TIME_FOREVER);
	}
	else {
		menu.DisplayAt(client, iPos, MENU_TIME_FOREVER);
	}
}

//Menu Handler for the admin spray selection menu
public int MenuHandler_AdminSpray(Menu menu, MenuAction action, int param1, int param2) {
	if (!IsValidClient(param1)) {
		return 0;
	}

	switch (action) {
		case MenuAction_Select: {
			char info[32];
			int target;

			menu.GetItem(param2, info, sizeof(info));

			target = GetClientOfUserId(StringToInt(info));
			char targetS[MAX_TARGET_LENGTH];
			IntToString(target, targetS, MAX_TARGET_LENGTH);

			if (target == 0 || !IsClientInGame(target)) {
				CPrintToChat(param1,"%s%T", PREFIX, "Could Not Find", param1);
			}
			else if (SpraybansMap.ContainsKey(targetS)) {
				char targetName[MAX_NAME_LENGTH];
				GetClientName(target, targetName, sizeof(targetName));
				CPrintToChat(param1, "%s%T", PREFIX, "Player is Spray Banned", param1, targetName);
			}
			else {
				GoSpray(param1, target);
				char clientName[MAX_NAME_LENGTH], targetName[MAX_NAME_LENGTH];
				GetClientName(param1, clientName, sizeof(clientName));
				GetClientName(param1, targetName, sizeof(targetName));

				CReplyToCommand(param1, "%s%T", PREFIX, "Admin Sprayed", param1, clientName, targetName);
			}

			DisplayAdminSprayMenu(param1, menu.Selection);
		}
		case MenuAction_Cancel: {
			if (param2 == MenuCancel_ExitBack && g_hAdminMenu != null) {
				g_hAdminMenu.Display(param1, TopMenuPosition_LastCategory);
			}
		}
		case MenuAction_End: {
			delete menu;
		}
	}

	return 0;
}

//Admin Menu handler for the Admin Spray Selection
public void AdminMenu_AdminSpray(TopMenu hTopMenu, TopMenuAction action, TopMenuObject tmoObjectID, int param, char[] szBuffer, int iMaxLength) {
	if (!IsValidClient(param)) {
		return;
	}

	switch (action) {
		case TopMenuAction_DisplayOption: {
			Format(szBuffer, iMaxLength, "%T", "Admin Spray Menu", param);
		}
		case TopMenuAction_SelectOption: {
			DisplayAdminSprayMenu(param);
		}
	}
}

/******************************************************************************************
 *                                  SPRAYING THE SPRAYS                                   *
 ******************************************************************************************/

//Called before SprayDecal() to receive a player's decal file and find where to spray it.
public bool GoSpray(int client, int target) {
	//Receives the player decal file.
	char spray[8];
	if (!GetPlayerDecalFile(target, spray, sizeof(spray))) {
		return false;
	}
	float vecEndPos[3];

	//Finds where to spray the spray.
	if (!GetClientEyeEndLocation(client, vecEndPos)) {
		return false;
	}
	int traceEntIndex = TR_GetEntityIndex();
	if (traceEntIndex < 0) {
		traceEntIndex = 0;
	}

	//What actually sprays the decal
	SprayDecal(target, traceEntIndex, vecEndPos);
	EmitSoundToAll("player/sprayer.wav", SOUND_FROM_WORLD, SNDCHAN_VOICE, SNDLEVEL_TRAFFIC, SND_NOFLAGS, _, _, _, vecEndPos);

	return true;
}

//Called to spray a players decal. Used for admin spray.
void SprayDecal(int client, int entIndex, float vecPos[3])
{
	char clientKey[8];
	IntToString(client, clientKey, sizeof clientKey);
	if (!IsValidClient(client) || SpraybansMap.ContainsKey(clientKey))
	{
		return;
	}

	TE_Start("Player Decal");
	TE_WriteVector("m_vecOrigin", vecPos);
	TE_WriteNum("m_nEntity", entIndex);
	TE_WriteNum("m_nPlayer", client);
	TE_SendToAll();
}

//Called to spray a NULL players decal. Used for deleting spray.
void SprayNullDecal(int client){
	
	char clientKey[8];
	IntToString(client, clientKey, sizeof clientKey);
	if (!IsValidClient(client) || SpraybansMap.ContainsKey(clientKey))
	{
		return;
	}

	float vecPos[3];

	g_fSprayVector[client] = ZERO_VECTOR;

	TE_Start("Player Decal");
	TE_WriteVector("m_vecOrigin", vecPos);
	TE_WriteNum("m_nEntity", 0);
	TE_WriteNum("m_nPlayer", client);
	TE_SendToAll();
}

/******************************************************************************************
 *                                    PUNISHMENT MENU                                     *
 ******************************************************************************************/

//Called to open the punishment menu.
public Action PunishmentMenu(int client, int sprayer) {
	if (!IsValidClient(client)) {
		return Plugin_Handled;
	}

	g_arrMenuSprayID[client] = g_arrSprayID[sprayer];
	Menu hMenu = new Menu(PunishmentMenuHandler);

	hMenu.SetTitle("%T", "Title", client, g_arrSprayName[sprayer], g_arrSprayID[sprayer], (RoundFloat(GetGameTime() - g_arrSprayTime[sprayer])));


	//Makes life simpler later
	//Gos ahead and creates all the booleans that decide what is put into the punishment menu

	//Is the restriction cvar = to 1?
	bool isRestricted = g_arrCVars[RESTRICT].BoolValue;

	bool useSlap = (g_arrCVars[SLAPDMG].IntValue > 0) && (isRestricted ? CheckCommandAccess(client, "sm_slap", ADMFLAG_SLAY, false) : true);
	bool useSlay = (g_arrCVars[USESLAY].BoolValue) && (isRestricted ? CheckCommandAccess(client, "sm_slay", ADMFLAG_SLAY, false) : true);
	bool useBurn = (g_arrCVars[USEBURN].BoolValue) && (isRestricted ? CheckCommandAccess(client, "sm_burn", ADMFLAG_SLAY, false) : true);
	bool useFreeze = (g_arrCVars[USEFREEZE].BoolValue) && (isRestricted ? CheckCommandAccess(client, "sm_freeze", ADMFLAG_SLAY, false) : true);
	bool useBeacon = (g_arrCVars[USEBEACON].BoolValue) && (isRestricted ? CheckCommandAccess(client, "sm_beacon", ADMFLAG_SLAY, false) : true);
	bool useFreezeBomb = (g_arrCVars[USEFREEZEBOMB].BoolValue) && (isRestricted ? CheckCommandAccess(client, "sm_freezebomb", ADMFLAG_SLAY, false) : true);
	bool useFireBomb = (g_arrCVars[USEFIREBOMB].BoolValue) && (isRestricted ? CheckCommandAccess(client, "sm_firebomb", ADMFLAG_SLAY, false) : true);
	bool useTimeBomb = (g_arrCVars[USETIMEBOMB].BoolValue) && (isRestricted ? CheckCommandAccess(client, "sm_timebomb", ADMFLAG_SLAY, false) : true);
	bool useDrug = (g_arrCVars[DRUGTIME].IntValue > 0) && (isRestricted ? CheckCommandAccess(client, "sm_drug", ADMFLAG_SLAY, false) : true);
	bool useKick = (g_arrCVars[USEKICK].BoolValue) && (isRestricted ? CheckCommandAccess(client, "sm_kick", ADMFLAG_KICK, false) : true);
	//bool useBan = (g_arrCVars[USEBAN].BoolValue) && (isRestricted ? CheckCommandAccess(client, "sm_ban", ADMFLAG_BAN, false) : true);
	bool useSprayBan = (g_arrCVars[USESPRAYBAN].BoolValue) && (isRestricted ? CheckCommandAccess(client, "sm_sprayban", ADMFLAG_BAN, false) : true);

	//Adding Punishments to Punishment Menu
	char szWarn[128];
	Format(szWarn, sizeof szWarn, "%T", "Warn", client);
	hMenu.AddItem("warn", szWarn);

	if (useSlap) {
		char szSlap[128];
		Format(szSlap, sizeof szSlap, "%T", "SlapWarn", client, g_arrCVars[SLAPDMG].IntValue);
		hMenu.AddItem("slap", szSlap);
	}

	if (useSlay) {
		char szSlay[128];
		Format(szSlay, sizeof szSlay, "%T", "Slay", client);
		hMenu.AddItem("slay", szSlay);
	}

	if (useBurn) {
		char szBurn[128];
		Format(szBurn, sizeof szBurn, "%T", "BurnWarn", client, g_arrCVars[BURNTIME].IntValue);
		hMenu.AddItem("burn", szBurn);
	}

	if (useFreeze) {
		char szFreeze[128];
		Format(szFreeze, sizeof szFreeze, "%T", "Freeze", client);
		hMenu.AddItem("freeze", szFreeze);
	}

	if (useBeacon) {
		char szBeacon[128];
		Format(szBeacon, sizeof szBeacon, "%T", "Beacon", client);
		hMenu.AddItem("beacon", szBeacon);
	}

	if (useFreezeBomb) {
		char szFreezeBomb[128];
		Format(szFreezeBomb, sizeof szFreezeBomb, "%T", "FreezeBomb", client);
		hMenu.AddItem("freezebomb", szFreezeBomb);
	}

	if (useFireBomb) {
		char szFireBomb[128];
		Format(szFireBomb, sizeof szFireBomb, "%T", "FireBomb", client);
		hMenu.AddItem("firebomb", szFireBomb);
	}

	if (useTimeBomb) {
		char szTimeBomb[128];
		Format(szTimeBomb, sizeof szTimeBomb, "%T", "TimeBomb", client);
		hMenu.AddItem("timebomb", szTimeBomb);
	}

	if (useDrug) {
		char szDrug[128];
		Format(szDrug, sizeof szDrug, "%T", "szDrug", client);
		hMenu.AddItem("drug", szDrug);
	}

	if (useKick) {
		char szKick[128];
		Format(szKick, sizeof szKick, "%T", "Kick", client);
		hMenu.AddItem("kick", szKick);
	}

/*	if (useBan) {
		char szBan[128];
		Format(szBan, sizeof szBan, "%T", "Ban", client);
		hMenu.AddItem("ban", szBan);
	}
*/
	if (useSprayBan) {
		char szSPBan[128];
		Format(szSPBan, sizeof szSPBan, "%T", "SPBan", client);
		hMenu.AddItem("spban", szSPBan);
	}

	hMenu.ExitButton = true;
	hMenu.ExitBackButton = true;
	hMenu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

//Handler for the Punishment Menu
public int PunishmentMenuHandler(Menu hMenu, MenuAction action, int client, int itemNum) {
	switch (action) {
		case MenuAction_Select: {
			char szInfo[32];
			char szSprayerName[MAX_NAME_LENGTH];
			char szAdminName[MAX_NAME_LENGTH];
			int sprayer, sprayerUserID;

			sprayer = (FindTargetSteam(g_arrMenuSprayID[client]));
			sprayerUserID= GetClientUserId(sprayer);
			szSprayerName = g_arrSprayName[sprayer];
			GetClientName(client, szAdminName, sizeof(szAdminName));
			hMenu.GetItem(itemNum, szInfo, sizeof(szInfo));

			
			//Guess you selected not to ban someone, so now we do this stuff.
			if (sprayer && IsClientInGame(sprayer)) {
				//Uh Oh. You can't target this person. Now they're going to kill you.
				if (!CanUserTarget(client, sprayer)) {
					CPrintToChat(client, "%s%T", PREFIX, "Admin Immune", client, szSprayerName);
				}
				//Wag that finger at them. You're doing good.
				else if (strcmp(szInfo, "warn") == 0) {
					CPrintToChat(sprayer, "%s%T", PREFIX, "Please change spray", sprayer);
					CShowActivity2(client, "", "%s%T", PREFIX, "Warned", client, szAdminName, szSprayerName);
					LogAction(client, sprayer, "%L Warned %L for a bad spray logo", client, sprayer);
					PunishmentMenu(client, sprayer);
				}
				//SMACK! SLAP THAT HOE INTO THE NEXT DIMENSION.
				else if (strcmp(szInfo, "slap") == 0) {
					CPrintToChat(sprayer, "%s%T", PREFIX, "Please change spray", sprayer);
					CShowActivity2(client, "","%s%T", PREFIX, "Slapped And Warned", client, szAdminName, szSprayerName, g_arrCVars[SLAPDMG].IntValue);
					LogAction(client, sprayer, "%L Slapped And Warned %L", client, sprayer);
					SlapPlayer(sprayer, g_arrCVars[SLAPDMG].IntValue);
					PunishmentMenu(client, sprayer);
				}
				//Now they're dead...>.>
				else if (strcmp(szInfo, "slay") == 0) {
					CPrintToChat(sprayer, "%s%T", PREFIX, "Please change spray", sprayer);
					CShowActivity2(client, "","%s%T", PREFIX, "Slayed And Warned", client, szAdminName, szSprayerName);
					LogAction(client, sprayer, "%L Slayed And Warned %L", client, sprayer);
					ClientCommand(client, "sm_slay \"%s\"", szSprayerName);
					PunishmentMenu(client, sprayer);
				}
				//You get to watch them scream in agony :D
				else if (strcmp(szInfo, "burn") == 0) {
					CPrintToChat(sprayer, "%s%T", PREFIX, "Please change spray", sprayer);
					CShowActivity2(client, "", "%s%T", PREFIX, "Burnt And Warned", client, szAdminName, szSprayerName);
					LogAction(client, sprayer, "%L Burnt And Warned %L", client, sprayer);
					FakeClientCommand(client, "sm_burn \"%s\" %d", szSprayerName, g_arrCVars[BURNTIME].IntValue);
					PunishmentMenu(client, sprayer);
				}
				//All of a sudden. Their legs don't work anymore. odd.
				else if (strcmp(szInfo, "freeze", false) == 0) {
					CPrintToChat(sprayer, "%s%T", PREFIX, "Please change spray", sprayer);
					CShowActivity2(client, "", "%s%T", PREFIX, "Froze", client, szAdminName, szSprayerName);
					LogAction(client, sprayer, "%L Froze %L", client, sprayer);
					FakeClientCommand(client, "sm_freeze \"%s\"", szSprayerName);
					PunishmentMenu(client, sprayer);
				}
				//BEEP. BEEP. BEEP. Now the whole server knows where they are.
				else if (strcmp(szInfo, "beacon", false) == 0) {
					CPrintToChat(sprayer, "%s%T", PREFIX, "Please change spray", sprayer);
					CShowActivity2(client, "", "%s%T", PREFIX, "Beaconed", client, szAdminName, szSprayerName);
					LogAction(client, sprayer, "%L Put a beacon on %L", client, sprayer);
					FakeClientCommand(client, "sm_beacon \"%s\"", szSprayerName);
					PunishmentMenu(client, sprayer);
				}
				//Their legs and anyone's legs around them are magically going to stop working in like....10 seconds...
				else if (strcmp(szInfo, "freezebomb", false) == 0) {
					CPrintToChat(sprayer, "%s%T", PREFIX, "Please change spray", sprayer);
					CShowActivity2(client, "", "%s%T", PREFIX, "FreezeBombed", client, szAdminName, szSprayerName);
					LogAction(client, sprayer, "%L Put a freezebomb on %L", client, sprayer);
					FakeClientCommand(client, "sm_freezebomb \"%s\"", szSprayerName);
					PunishmentMenu(client, sprayer);
				}
				//Now this is just cruel. You're going to hurt other people too....
				else if (strcmp(szInfo, "firebomb", false) == 0) {
					CPrintToChat(sprayer, PREFIX ,"%s%T", PREFIX, "Please change spray", sprayer);
					CShowActivity2(client, "","%s%T", PREFIX, "FireBombed", client, szAdminName, szSprayerName);
					LogAction(client, sprayer, "%L Put a firebomb on %L", client, sprayer);
					FakeClientCommand(client, "sm_firebomb \"%s\"", szSprayerName);
					PunishmentMenu(client, sprayer);
				}
				//This is just horrible. You're straight murdering other people too...
				else if (strcmp(szInfo, "timebomb", false) == 0) {
					CPrintToChat(sprayer, "%s%T", PREFIX, "Please change spray", sprayer);
					CShowActivity2(client,"", "%s%T", PREFIX, "TimeBombed", client, szAdminName, szSprayerName);
					LogAction(client, sprayer, "%L Put a timebomb on %L", client, sprayer);
					FakeClientCommand(client, "sm_timebomb \"%s\"", szSprayerName);
					PunishmentMenu(client, sprayer);
				}
				//Slip something into their drink?
				else if (strcmp(szInfo, "drug", false) == 0) {
					CPrintToChat(sprayer, "%s%T", PREFIX, "Please change spray", sprayer);
					CShowActivity2(client,"", "%s%T", PREFIX, "Drugged", client, szAdminName, szSprayerName);
					LogAction(client, sprayer, "%L Drugged %L", client, sprayer);
					CreateTimer(g_arrCVars[DRUGTIME].FloatValue, Undrug, sprayer, TIMER_FLAG_NO_MAPCHANGE);
					FakeClientCommand(client, "sm_drug \"%s\"", szSprayerName);
					PunishmentMenu(client, sprayer);
				}
				//GTFO
				else if (strcmp(szInfo, "kick") == 0) {
					KickClient(sprayer, "%T", "Bad Spray Logo", sprayer);
					CShowActivity2(client, "", "%s%T", PREFIX, "Kicked", client, szAdminName, szSprayerName);
					LogAction(client, sprayer, "%L kicked %L for a bad spray logo", client, sprayer);
				}
				//No more spraying for you :)
				else if (strcmp(szInfo, "spban") == 0) {
					AdminMenu_SpraybanDuration(client, sprayerUserID);
				}
			}
			//Nice. That's not a person.
			else {
				CPrintToChat(client,  "%s%T", PREFIX, "Could Not Find Name", client, szSprayerName);
			}

			//If you want to auto-remove their spray after punishing, this does it.
			if (g_arrCVars[AUTOREMOVE].BoolValue) {
				SprayNullDecal(sprayer);
				CPrintToChat(client, "%s%T", PREFIX, "Spray Removed", client, szSprayerName, szAdminName);
			}
		}
		case MenuAction_Cancel: {
			if (itemNum == MenuCancel_ExitBack) {
				RedisplayAdminMenu(g_hAdminMenu, client);
			}
		}
		case MenuAction_End: {
			delete hMenu;
		}
	}

	return 0;
}

/******************************************************************************************
 *                                     HELPER METHODS                                     *
 ******************************************************************************************/

 //Used to clear a player from existence in this plugin.
public void ClearVariables(int client)
{
	NormalForSpray[client] = ZERO_VECTOR;
	g_fSprayVector[client] = ZERO_VECTOR;
	g_arrSprayName[client][0] = '\0';
	g_sAuth[client][0] = '\0';
	g_arrSprayID[client][0] = '\0';
	g_arrMenuSprayID[client][0] = '\0';
	g_arrSprayTime[client] = 0;
}

public bool TraceEntityFilter_NoPlayers(int entity, int contentsMask) {
	return entity > MaxClients;
}

public bool TraceEntityFilter_OnlyWorld(int entity, int contentsMask) {
	return entity == 0;
}

//Used to make fix removing a spray when sm_ssh_overlap != 0
public bool CheckForZero(float vecPos[3]) {
	return (vecPos[0] == 0 && vecPos[1] == 0 && vecPos[2] == 0);
}

//Applies the glow effect on a spray when you trace the spray
public void GlowEffect(int client, float vecPos[3], float flLife, float flSize, int bright, int model) {
	if (!IsValidClient(client)) {
		return;
	}

	int arrClients[1];
	arrClients[0] = client;
	TE_SetupGlowSprite(vecPos, model, flLife, flSize, bright);
	TE_Send(arrClients, 1);
}

//Handles actually making drugs work on a timer.
public Action Undrug(Handle hTimer, any client) {
	if (IsValidClient(client)) {
		ServerCommand("sm_undrug \"%N\"", client);
	}

	return Plugin_Handled;
}

//Pretty obvious what this accomplishes :/
stock bool IsValidClient(int client) {
	return (0 < client <= MaxClients && IsClientInGame(client));
}


//What is used to find the exact location a player is looking. Used for tracing sprays to the hud/hint and other functions.
public bool GetClientEyeEndLocation(int client, float vector[3])
{
	if (!IsValidClient(client)) {
		return false;
	}

	float vOrigin[3];
	float vAngles[3];

	GetClientEyePosition(client, vOrigin);
	GetClientEyeAngles(client, vAngles);

	Handle hTraceRay = TR_TraceRayFilterEx(vOrigin, vAngles, MASK_SHOT, RayType_Infinite, ValidSpray);

	if (TR_DidHit(hTraceRay)) {
		TR_GetEndPosition(vector, hTraceRay);

		delete hTraceRay;

		return true;
	}

	delete hTraceRay;

	return false;
}


//Checks to make sure a spray is of a valid client.
public bool ValidSpray(int entity, int contentsmask)
{
	return entity > MaxClients;
}


// following are stolen from smlib


/**
 * Prints white text to the bottom center of the screen
 * for one client. Does not work in all games.
 * Line Breaks can be done with "\n".
 *
 * @param client		Client Index.
 * @param format		Formatting rules.
 * @param ...			Variable number of format parameters.
 * @return				True on success, false if this usermessage doesn't exist.
 */
bool Client_PrintHintText(int client, const char[] format, any ...) {
	Handle userMessage = StartMessageOne("HintText", client);

	if (userMessage == INVALID_HANDLE) {
		return false;
	}

	char buffer[254];

	SetGlobalTransTarget(client);
	VFormat(buffer, sizeof(buffer), format, 3);


	if (GetFeatureStatus(FeatureType_Native, "GetUserMessageType") == FeatureStatus_Available
		&& GetUserMessageType() == UM_Protobuf) {

		PbSetString(userMessage, "text", buffer);
	}
	else {
		BfWriteByte(userMessage, 1);
		BfWriteString(userMessage, buffer);
	}

	EndMessage();

	return true;
}

/**
 * Prints white text to the right-center side of the screen
 * for one client. Does not work in all games.
 * Line Breaks can be done with "\n".
 *
 * @param client		Client Index.
 * @param format		Formatting rules.
 * @param ...			Variable number of format parameters.
 * @return				True on success, false if this usermessage doesn't exist.
 */
bool Client_PrintKeyHintText(int client, const char[] format, any ...) {
	Handle userMessage = StartMessageOne("KeyHintText", client);

	if (userMessage == INVALID_HANDLE) {
		return false;
	}

	char buffer[254];

	SetGlobalTransTarget(client);
	VFormat(buffer, sizeof(buffer), format, 3);

	if (GetFeatureStatus(FeatureType_Native, "GetUserMessageType") == FeatureStatus_Available
		&& GetUserMessageType() == UM_Protobuf) {

		PbAddString(userMessage, "hints", buffer);
	}
	else {
		BfWriteByte(userMessage, 1);
		BfWriteString(userMessage, buffer);
	}

	EndMessage();

	return true;
}


public Action Command_SprayStatus(int client, int args){
	
	if (!g_arrCVars[ENABLED].BoolValue) {
		ReplyToCommand(client, "[SM] This plugin is currently disabled.");
		return Plugin_Handled;
	}
	
	char clientKey[16];
	IntToString(client, clientKey, sizeof(clientKey));
	if (args == 0){
		if (!SpraybansMap.ContainsKey(clientKey)){
			ShowNoBlockMenu(client);
			return Plugin_Handled;
		}
		SprayBan info;		
		SpraybansMap.GetArray(clientKey,info,sizeof(info));
		ShowBlockMenu(client, info);
		return Plugin_Handled;
	}
	char authClient[MAX_AUTHID_LENGTH];
	GetClientAuthId(client, AuthId_Steam2, authClient, sizeof(authClient));
	AdminId clientAdmID = FindAdminByIdentity("steam", authClient);
	
	

	if (!GetAdminFlag(clientAdmID, Admin_Kick)){
		ReplyToCommand(client, "[SM] You don't have the permission to use this command.");
		return Plugin_Handled;
	}
	
	char target[MAX_TARGET_LENGTH];
	GetCmdArg(1, target, sizeof(target));

	int targetClient = FindTarget(client, target, true, true);
	if (targetClient == -1) 
		return Plugin_Handled;
	
	IntToString(targetClient, clientKey, sizeof(clientKey));
			
	if (!SpraybansMap.ContainsKey(clientKey)){
			ShowNoBlockMenu(client);
			return Plugin_Handled;
	}
	SprayBan info;
	SpraybansMap.GetArray(clientKey,info,sizeof(info));
	ShowBlockMenu(client, info);
	return Plugin_Handled;
}


void ShowNoBlockMenu(int client){
	Panel panel = new Panel();
	panel.SetTitle("Информация о блокировке спреев\n \n");
	panel.DrawText("У вас нет активной блокировки \n \n");
	panel.DrawItem("Закрыть");
    
	panel.Send(client,HandlerNoBlock ,MENU_TIME_FOREVER);

	delete panel;
}

public int HandlerNoBlock(Menu menu, MenuAction action, int client, int itemNum){
    return 0;
}

void ShowBlockMenu(int client, SprayBan blockInfo, const char[] nameOffline = ""){
	Panel panel = new Panel();
	
	
	char title[64];
	char nameField[64];
	char authField[MAX_AUTHID_LENGTH];
	char admName[64];
	char admField[64];
	char duration[64];
	char durationField[64];
	char reasonField[64];
	char createDate[64];
	char createDateField[64];
	char endDate[64];
	char endDateField[64];
	char s_timeLeft[64];
	char timeLeftField[64];

	FormatEx(title, sizeof(title), "%T", "ShowBlockMenu_Title", client);
	panel.SetTitle(title);
	
	int timeLeft = blockInfo.endTime - GetTime();
	int iTarget = FindTargetSteam(blockInfo.auth);

	if (nameOffline[0])
		FormatEx(nameField,sizeof(nameField),"%T%s", "ShowBlockMenu_Name", client, nameOffline);
	else 
		(iTarget<=0) ? FormatEx(nameField,sizeof(nameField),"%T", "ShowBlockMenu_NoName", client) : FormatEx(nameField,sizeof(nameField),"%T%N","ShowBlockMenu_Name", client, iTarget);
	
	panel.DrawText(nameField);

	FormatEx(authField, sizeof(authField), "SteamID: %s", blockInfo.auth);
	panel.DrawText(authField);
	
	AdminId admID = FindAdminByIdentity("steam", blockInfo.adminSteamID);
	admID.GetUsername(admName, sizeof(admName));
	FormatEx(admField, sizeof(admField), "%T", "ShowBlockMenu_BlockedBy", client, admName);
	panel.DrawText(admField);
	
	FormatDuration(client, blockInfo.length, duration, sizeof(duration));
	FormatEx(durationField, sizeof(durationField), "%T","ShowBlockMenu_Duration", client, duration);
	panel.DrawText(durationField);

	FormatEx(reasonField, sizeof(reasonField), "%T","ShowBlockMenu_Reason", client, blockInfo.reason);
	panel.DrawText(reasonField);

	FormatTime(createDate, sizeof(createDate), "%d.%m.%Y %H:%M:%S", blockInfo.startTime);
	FormatEx(createDateField, sizeof(createDateField), "%T","ShowBlockMenu_BanDate", client, createDate);
	panel.DrawText(createDateField);

	if (blockInfo.length>0){
		FormatTime(endDate, sizeof(endDate), "%d.%m.%Y %H:%M:%S", blockInfo.endTime);
		FormatEx(endDateField, sizeof(endDateField), "%T","ShowBlockMenu_ExpireDate", client, endDate);
		panel.DrawText(endDateField);

		FormatDuration(client, timeLeft, s_timeLeft, sizeof(s_timeLeft));
		FormatEx(timeLeftField, sizeof(timeLeftField), "%T","ShowBlockMenu_TimeRemaining", client, s_timeLeft);
		panel.DrawText(timeLeftField);
	}

	panel.DrawItem("Закрыть");

	panel.Send(client,HandlerBlockMenu ,MENU_TIME_FOREVER);

	delete panel;
}

public int HandlerBlockMenu(Menu menu, MenuAction action, int client, int itemNum){
    return 0;
}

public Action Command_SpraybanNew(int client, int args){
	
	if (!g_arrCVars[ENABLED].BoolValue) {
		ReplyToCommand(client, "[SM] This plugin is currently disabled.");
		return Plugin_Handled;
	}
	
	char fullArg[128], err[128], reason[64], target[MAX_TARGET_LENGTH];
	int time, iTarget;

	GetCmdArgString(fullArg, sizeof(fullArg));
	
	if (!GetCmdArgsTTR(fullArg, target, sizeof target , time, reason,sizeof reason, err, sizeof err, BAN)){
		ReplyToCommand(client, err);
		return Plugin_Handled;
	}

	iTarget = FindTarget(client, target, true, true);
		
	if (iTarget == -1) 
		return Plugin_Handled;
	
	char authTarget[MAX_AUTHID_LENGTH], authClient[MAX_AUTHID_LENGTH];
	
	GetClientAuthId(iTarget, AuthId_Steam2, authTarget, sizeof(authTarget));
	GetClientAuthId(client, AuthId_Steam2, authClient, sizeof(authClient));

	char targetKey[16];
	IntToString(iTarget, targetKey, sizeof(targetKey));

	if (SpraybansMap.ContainsKey(targetKey)){
		char targetName[MAX_NAME_LENGTH];
		GetClientName(iTarget, targetName, sizeof(targetName));
		CReplyToCommand(client,  "%s%T", PREFIX, "Already Spraybanned", client, targetName);
		return Plugin_Handled;
	}


	SprayBan info;
	info.startTime = GetTime();
	info.length = time;
	info.endTime = info.startTime + time;
	strcopy(info.reason, sizeof(info.reason), reason);
	strcopy(info.adminSteamID, sizeof(info.adminSteamID), authClient);
	strcopy(info.auth, sizeof(info.auth), authTarget);
	


	char query[1024];
	g_Database.Format(query, sizeof(query), "INSERT INTO ssh (auth, name, created, ends, duration, reason, adminID) \
	VALUES ('%s', '%N', UNIX_TIMESTAMP(), UNIX_TIMESTAMP() + '%d', '%d', '%s', '%s');", authTarget, iTarget, info.length, info.length, info.reason, info.adminSteamID);

	SQL_LockDatabase(g_Database);
	if(!SQL_FastQuery(g_Database, query)){
		char error[256];
		SQL_GetError(g_Database, error, sizeof(error));
		LogError("SQL Error: %s", error);

		CReplyToCommand(client, "%s%T", PREFIX, "DB Error", client);
		SQL_UnlockDatabase(g_Database);
		return Plugin_Handled;
	}	
	SQL_UnlockDatabase(g_Database);

	SprayNullDecal(iTarget);
	
	SpraybansMap.SetArray(targetKey, info, sizeof(info), true);

	char clientName[MAX_NAME_LENGTH], targetName[MAX_NAME_LENGTH];
	GetClientName(iTarget, targetName, sizeof targetName);
	GetClientName(client, clientName, sizeof clientName);
	char duration[32];
	FormatDuration(client, info.length, duration, sizeof duration);

	CPrintToChat(iTarget, "%s%T",PREFIX, "You are SprayBanned Reply", iTarget);

	LogAction(client, iTarget, "%L Spraybanned %L. Duration %d seconds. Reason %s", client, iTarget, info.length, reason);
	CShowActivity2(client, "", "%s%T", PREFIX, "SPBanned", client, clientName, targetName, duration, reason);

	ClearBannedItems(iTarget);
	
	ForwardSprayBan(targetName, authTarget, clientName, authClient, time, reason);
	
	return Plugin_Handled;
}

public Action Command_SprayUnbannew(int client, int args){

	if (!g_arrCVars[ENABLED].BoolValue) {
		ReplyToCommand(client, "[SM] This plugin is currently disabled.");
		return Plugin_Handled;
	}
	
	if (args < 1)
	{
		ReplyToCommand(client, "Usage: sm_sunban <target>");
		return Plugin_Handled;
	}
	
	char target[MAX_TARGET_LENGTH];

	GetCmdArg(1, target, sizeof(target));

	int iTarget = FindTarget(client, target, true, true);

	if (iTarget == -1) 
		return Plugin_Handled;

	char authTarget[MAX_AUTHID_LENGTH], authClient[MAX_AUTHID_LENGTH];

	GetClientAuthId(iTarget, AuthId_Steam2, authTarget, sizeof(authTarget));
	GetClientAuthId(client, AuthId_Steam2, authClient, sizeof(authClient));
	AdminId admIDClient = FindAdminByIdentity("steam", authClient);

	char targetKey[16];
	IntToString(iTarget, targetKey, sizeof(targetKey));

	if (!SpraybansMap.ContainsKey(targetKey)){
		char targetName[MAX_NAME_LENGTH];
		GetClientName(iTarget, targetName, sizeof(targetName));
		CReplyToCommand(client,  "%s%T", PREFIX, "No Sprayban", client, targetName);
		return Plugin_Handled;
	}

	SprayBan info;
	SpraybansMap.GetArray(targetKey, info, sizeof(info));

	AdminId admID = FindAdminByIdentity("steam", info.adminSteamID);

	if(!CanAdminTarget(admIDClient, admID)){
		char targetName[MAX_NAME_LENGTH];
		GetClientName(iTarget, targetName, sizeof(targetName));
		CReplyToCommand(client, "%s%T", PREFIX, "Cant Unban Admin Immun",client, targetName);
		return Plugin_Handled;
	}

	char query[512];

	g_Database.Format(query, sizeof(query), "\
						UPDATE `ssh` SET `RemovedBy` = '%!s', `RemovedType` = 'U', `RemovedOn` = UNIX_TIMESTAMP() \
						WHERE (`auth` = '%s') AND (`duration` = 0 OR `ends` > UNIX_TIMESTAMP()) AND `RemovedType` IS NULL", authClient, authTarget);

	SQL_LockDatabase(g_Database);
	if(!SQL_FastQuery(g_Database, query)){
		char error[256];
		SQL_GetError(g_Database, error, sizeof(error));
		LogError("SQL Error: %s", error);

		CReplyToCommand(client, "%s%T", PREFIX, "DB Error", client);
		SQL_UnlockDatabase(g_Database);
		return Plugin_Handled;
	}	
	
	SQL_UnlockDatabase(g_Database);

	SpraybansMap.Remove(targetKey);

	char clientName[MAX_NAME_LENGTH];
	GetClientName(client, clientName, sizeof(clientName));
	char targetName[MAX_NAME_LENGTH];
	GetClientName(iTarget, targetName, sizeof(targetName));
	
	CPrintToChat(iTarget, "%s%T", PREFIX, "You are UnSprayBanned Reply", iTarget);
	LogAction(client, iTarget, "%L UnSpraybanned %L", client, iTarget);
	CShowActivity2(client,"", "%s%T",PREFIX, "Spray Unban",client, clientName,targetName);

	return Plugin_Handled;

}

public Action Command_SpraybanOfflinenew(int client, int args){

	if (!g_arrCVars[ENABLED].BoolValue) {
		ReplyToCommand(client, "[SM] This plugin is currently disabled.");
		return Plugin_Handled;
	}
	
	char fullArg[128], err[128], reason[64], authTarget[MAX_AUTHID_LENGTH];
	int time;

	GetCmdArgString(fullArg, sizeof(fullArg));
	
	if (!GetCmdArgsTTR(fullArg, authTarget, sizeof authTarget ,time, reason,sizeof reason, err, sizeof err, OFFBAN)){
		ReplyToCommand(client, err);
		return Plugin_Handled;
	}

	char query[1024];

	g_Database.Format(query, sizeof(query), "\
	SELECT `auth`, `created`, `ends`, `duration`, `adminID`, `reason` \
	FROM `ssh` WHERE `auth` = '%s' AND `removedType` IS NULL \
	AND (`duration` = 0 OR `ends` > UNIX_TIMESTAMP()) LIMIT 1", authTarget);

	DataPack pack = new DataPack();
	pack.WriteCell(GetClientUserId(client));
	pack.WriteString(authTarget);
	pack.WriteCell(time);
	pack.WriteString(reason);

	g_Database.Query(OfflinebanCallback, query, pack);

	return Plugin_Handled;
}
public void OfflinebanCallback(Database db, DBResultSet results, const char[] error, DataPack pack) {
	if (!db || !results || error[0]){
		LogError("CheckBan query failed. (%s)", error);
		return;
	}
	
	char authTarget[MAX_AUTHID_LENGTH], authClient[MAX_AUTHID_LENGTH], reason[64];
	int time, clientID;

	pack.Reset();

	clientID = pack.ReadCell();
	pack.ReadString(authTarget, sizeof(authTarget));
	time = pack.ReadCell();
	pack.ReadString(reason, sizeof(reason));
	delete pack;

	char authResult[MAX_AUTHID_LENGTH];

	int client = GetClientOfUserId(clientID);
	
	if (results.HasResults && results.RowCount && results.FetchRow()){
		results.FetchString(0, authResult, sizeof(authResult));
	}
	if (authResult[0]){
		CReplyToCommand(client, "%s%T", PREFIX, "Already Spraybanned", client, authResult);
		return;
	}

	GetClientAuthId(client, AuthId_Steam2, authClient, sizeof(authClient));
	
	AdminId admIDClient = FindAdminByIdentity("steam", authClient);
	AdminId admIDTarget = FindAdminByIdentity("steam", authTarget);

	if(!CanAdminTarget(admIDClient, admIDTarget)){
		ReplyToCommand(client, "%s%T", PREFIX, "Cant ban Admin Immun", client, authTarget);
		return;
	}

	char query[1024];
	g_Database.Format(query, sizeof(query), "INSERT INTO ssh (auth, created, ends, duration, reason, adminID) \
	VALUES ('%s', UNIX_TIMESTAMP(), UNIX_TIMESTAMP() + '%d', '%d', '%s', '%s');", authTarget, time, time, reason, authClient);

	SQL_LockDatabase(g_Database);
	if(!SQL_FastQuery(g_Database, query)){
		char sError[256];
		SQL_GetError(g_Database, sError, sizeof(sError));
		LogError("SQL Error: %s", sError);

		CReplyToCommand(client, "%s%T", PREFIX, "DB Error", client);
		SQL_UnlockDatabase(g_Database);
		return;
	}	
	SQL_UnlockDatabase(g_Database);

	int targetClient = FindTargetSteam(authTarget);

	if (targetClient != 0){
		SprayBan info;
		info.startTime = GetTime();
		info.length = time;
		info.endTime = info.startTime + time;
		strcopy(info.reason, sizeof(info.reason), reason);
		strcopy(info.adminSteamID, sizeof(info.adminSteamID), authClient);
		strcopy(info.auth, sizeof(info.auth), authTarget);
		
		char clientKey[16];
		IntToString(targetClient, clientKey, sizeof(clientKey));

		SprayNullDecal(targetClient);
		
		SpraybansMap.SetArray(clientKey, info, sizeof(info), true);

		CPrintToChat(targetClient, "%s%T",PREFIX, "You are SprayBanned Reply", targetClient);
		char clientName[MAX_NAME_LENGTH];
		GetClientName(client, clientName, sizeof(clientName));
		char targetName[MAX_NAME_LENGTH];
		GetClientName(targetClient, targetName, sizeof(targetName));

		LogAction(client, targetClient, "%L Spraybanned %L. Duration %d seconds. Reason %s", client, targetClient, info.length, reason);
		CShowActivity2(client,"", "%s%T", PREFIX, "SPBanned",client, clientName,targetName, info.length, reason);

		ClearBannedItems(targetClient);

		ForwardSprayBan(targetName, authTarget, clientName, authClient, time, reason);
		return;
	}
	char clientName[MAX_NAME_LENGTH];
	GetClientName(client, clientName, sizeof(clientName));

	LogAction(client, -1, "%L Spraybanned %s. Duration %d seconds. Reason %s", client, authTarget, time, reason);
	CShowActivity2(client,"", "%s%T", PREFIX, "SPBanned",client, clientName, authTarget, time, reason);

	ForwardSprayBan(_, authTarget, clientName, authClient, time, reason);
}

public Action Command_SprayUnbanOfflinenew(int client, int args){

	if (!g_arrCVars[ENABLED].BoolValue) {
		ReplyToCommand(client, "[SM] This plugin is currently disabled.");
		return Plugin_Handled;
	}
	
	if (args < 1)
	{
		ReplyToCommand(client, "Usage: sm_offsunban2 <'steamID'>");
		return Plugin_Handled;
	}
	
	char authTarget[MAX_AUTHID_LENGTH];

	GetCmdArg(1, authTarget, sizeof(authTarget));

	char query[1024];

	g_Database.Format(query, sizeof(query), "\
	SELECT `auth`, `created`, `ends`, `duration`, `adminID`, `reason` \
	FROM `ssh` WHERE `auth` = '%s' AND `removedType` IS NULL \
	AND (`duration` = 0 OR `ends` > UNIX_TIMESTAMP()) LIMIT 1", authTarget);

	DataPack pack = new DataPack();
	pack.WriteCell(GetClientUserId(client));
	pack.WriteString(authTarget);

	g_Database.Query(OfflineUnbanCallback, query, pack);

	return Plugin_Handled;
}
public void OfflineUnbanCallback(Database db, DBResultSet results, const char[] error, DataPack pack) {
	if (!db || !results || error[0]){
		LogError("CheckBan query failed. (%s)", error);
		return;
	}
	
	char authTarget[MAX_AUTHID_LENGTH], authClient[MAX_AUTHID_LENGTH];
	int clientID;

	pack.Reset();

	clientID = pack.ReadCell();
	pack.ReadString(authTarget, sizeof(authTarget));
	delete pack;

	char authResult[MAX_AUTHID_LENGTH];

	int client = GetClientOfUserId(clientID);
	
	if (results.HasResults && results.RowCount && results.FetchRow()){
		results.FetchString(0, authResult, sizeof(authResult));
	}
	if (!authResult[0]){
		CReplyToCommand(client, "%s%T", PREFIX, "No Sprayban", client, authTarget);
		return;
	}

	GetClientAuthId(client, AuthId_Steam2, authClient, sizeof(authClient));
	char authAdmin[MAX_AUTHID_LENGTH];
	results.FetchString(4, authAdmin, sizeof(authAdmin));
	
	AdminId admIDClient = FindAdminByIdentity("steam", authClient);
	AdminId admID = FindAdminByIdentity("steam", authAdmin);

	if(!CanAdminTarget(admIDClient, admID)){
		CReplyToCommand(client, "%s%T", PREFIX, "Cant Unban Admin Immun",client, authTarget);
		return;
	}

	char query[1024];

	g_Database.Format(query, sizeof(query), "\
						UPDATE `ssh` SET `RemovedBy` = '%!s', `RemovedType` = 'U', `RemovedOn` = UNIX_TIMESTAMP() \
						WHERE (`auth` = '%s') AND (`duration` = 0 OR `ends` > UNIX_TIMESTAMP()) AND `RemovedType` IS NULL", authClient, authTarget);

	SQL_LockDatabase(g_Database);
	if(!SQL_FastQuery(g_Database, query)){
		char sError[256];
		SQL_GetError(g_Database, sError, sizeof(sError));
		LogError("SQL Error: %s", sError);

		CReplyToCommand(client, "%s%T", PREFIX, "DB Error", client);
		SQL_UnlockDatabase(g_Database);
		return;
	}	
	
	SQL_UnlockDatabase(g_Database);

	int targetClient = FindTargetSteam(authTarget);

	if (targetClient != 0){
		
		char targetKey[16];
		IntToString(targetClient, targetKey, sizeof(targetKey));
		
		SpraybansMap.Remove(targetKey);

		char clientName[MAX_NAME_LENGTH];
		GetClientName(client, clientName, sizeof(clientName));
		char targetName[MAX_NAME_LENGTH];
		GetClientName(targetClient, targetName, sizeof(targetName));
	
		CPrintToChat(targetClient, "%s%T", PREFIX, "You are UnSprayBanned Reply", targetClient);
		LogAction(client, targetClient, "%L UnSpraybanned %L", client, targetClient);
		CShowActivity2(client,"", "%s%T", PREFIX, "Spray Unban",client, clientName,targetName);
		return;
	}
	char clientName[MAX_NAME_LENGTH];
	GetClientName(client, clientName, sizeof(clientName));
	LogAction(client, -1, "%L UnSpraybanned %s", client, authTarget);
	CShowActivity2(client,"", "%s%T", PREFIX, "Spray Unban",client, clientName,authTarget);
}

void FormatDuration(int client, int seconds, char[] buffer, int bufferSize)
{
    if (seconds <= 0)
    {
        Format(buffer, bufferSize, "%T", "Time_Never", client);
        return;
    }
    
    int days = seconds / 86400;
    int hours = (seconds % 86400) / 3600;
    int minutes = (seconds % 3600) / 60;
    int secs = seconds % 60;
    
    char tempBuffer[128];
    buffer[0] = '\0';
    
    if (days > 0)
    {
        Format(tempBuffer, sizeof(tempBuffer), "%T", "Time_Days", client, days);
        StrCat(buffer, bufferSize, tempBuffer);
    }
    
    if (hours > 0)
    {
        if (strlen(buffer) > 0)
            StrCat(buffer, bufferSize, " ");
        Format(tempBuffer, sizeof(tempBuffer), "%T", "Time_Hours", client, hours);
        StrCat(buffer, bufferSize, tempBuffer);
    }
    
    if (minutes > 0)
    {
        if (strlen(buffer) > 0)
            StrCat(buffer, bufferSize, " ");
        Format(tempBuffer, sizeof(tempBuffer), "%T", "Time_Minutes", client, minutes);
        StrCat(buffer, bufferSize, tempBuffer);
    }
    
    if (secs > 0 || strlen(buffer) == 0)
    {
        if (strlen(buffer) > 0)
            StrCat(buffer, bufferSize, " ");
        Format(tempBuffer, sizeof(tempBuffer), "%T", "Time_Seconds", client, secs);
        StrCat(buffer, bufferSize, tempBuffer);
    }
    
    TrimString(buffer);
}


enum CommandType {
	BAN,
	OFFBAN,
}

//Gets the command arguments from input. Target, time and reason. returns false if args are invalid
bool GetCmdArgsTTR(char[] input, char[] target, int targetS, int& time, char[] reason, int reasonS, char[] err, int errS, CommandType type){
	char sTime[32];	
	int iLen,
		iTotelLen;
	
	if ((iLen = BreakString(input, target, targetS)) == -1){
		switch (type) {
			case BAN: {
				strcopy(err, errS, "Usage: sm_sban <target> <duration in days> [reason]");
			}
			case OFFBAN: {
				strcopy(err, errS, "Usage: sm_offsban <'steamid'> <duration in days> [reason]");
			}
		}
		return false;
	}
	iTotelLen += iLen;
	
	if ((iLen = BreakString(input[iTotelLen], sTime, sizeof(sTime))) == -1){
		strcopy(reason, reasonS, "Нет причины");
		time = StringToInt(sTime) * 86400; 
		if(time<0){
			strcopy(err, errS, "Время наказания должно быть положительным или 0");
			return false;
		}	
		return true;	
	}
	iTotelLen += iLen;
	time = StringToInt(sTime) * 86400;
		
	if(time<0){
	  	strcopy(err, errS, "Время наказания должно быть положительным или 0");
	  	return false;
	}
	strcopy(reason, reasonS, input[iTotelLen]);

	return true;
}

int FindTargetSteam(const char[] sSteamID){
	char sSteamIDs[MAX_AUTHID_LENGTH];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			GetClientAuthId(i, AuthId_Steam2, sSteamIDs, sizeof(sSteamIDs));
			if(StrEqual(sSteamID[8], sSteamIDs[8],false))
			{
				return i;
			}	
		}
	}
	return 0;
}

//Removes decals from items when equiping: objector, flairs etc..
public int TF2Items_OnGiveNamedItem_Post(int iClient, char[] sClassName, int iItemDefinitionIndex, int iItemLevel, int iItemQuality, int iEntityIndex) {

	char clientKey[8];
	IntToString(iClient, clientKey, 8);
	if (!SpraybansMap.ContainsKey(clientKey))
		return;

	if(iItemDefinitionIndex == 474 || iItemDefinitionIndex == 619 || iItemDefinitionIndex == 623 || iItemDefinitionIndex == 624) {

		TF2Attrib_SetByDefIndex(iEntityIndex, 227, view_as<float>(0));
		TF2Attrib_SetByDefIndex(iEntityIndex, 152, view_as<float>(0));

		SprayBan info;
		SpraybansMap.GetArray(clientKey, info, sizeof(info));
		if(!info.notyfied) {
			info.notyfied = true;
			SpraybansMap.SetArray(clientKey, info, sizeof(info), true);
			RequestFrame(Notify_ItemChange, EntIndexToEntRef(iClient));
		}
	}
}

public Action Command_ClearDecals(int client, int args) {
	
	if (args < 1)
	{
		ReplyToCommand(client, "Usage: sm_cleardecals <target>");
		return Plugin_Handled;
	}
	char target[MAX_TARGET_LENGTH];
	GetCmdArg(1, target, sizeof(target));
	
	int targetClient = FindTarget(client, target, true, true);
	if (!IsValidClient(targetClient) || !IsPlayerAlive(targetClient))
		return Plugin_Handled;
	
	ClearBannedItems(targetClient);

	char clientName[MAX_NAME_LENGTH], targetName[MAX_NAME_LENGTH];
	GetClientName(targetClient, targetName, sizeof(targetName));
	GetClientName(client, clientName, sizeof(clientName));

	CShowActivity2(client, "", "%s%T", PREFIX, "Admin Cleared Decals", LANG_SERVER, clientName, targetName);
	return Plugin_Handled;
}

void ClearBannedItems(int target){
	if (!IsPlayerAlive(target)){
		ClearBannedItems_CreateTimer(target);
		return;
	}		
	int edict = -1;
	while((edict = FindEntityByClassname(edict, "tf_wearable")) != -1)
	{
		char netclass[32];
		if (GetEntityNetClass(edict, netclass, sizeof(netclass)) && StrEqual(netclass, "CTFWearable"))
		{
			if (GetEntPropEnt(edict, Prop_Send, "m_hOwnerEntity") == target)
			{
				int index = GetEntProp(edict, Prop_Send, "m_iItemDefinitionIndex");
				if (index == 619 || index == 623 || index == 624)
				{
					TF2Attrib_SetByDefIndex(edict, 227, view_as<float>(0));
					TF2Attrib_SetByDefIndex(edict, 152, view_as<float>(0));
				}
			}
		}
	}
	
	int wepEnt = GetPlayerWeaponSlot(target, 2);
	int wepIndex = GetEntProp(wepEnt, Prop_Send, "m_iItemDefinitionIndex");
	if (wepIndex != 474)
		return;
	TF2Attrib_SetByDefIndex(wepEnt, 227, view_as<float>(0));
	TF2Attrib_SetByDefIndex(wepEnt, 152, view_as<float>(0));
}

void ClearBannedItems_CreateTimer(int target) {
	CreateTimer(5.0, ClearBannedItems_TimerCallback, target, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public Action ClearBannedItems_TimerCallback(Handle timer, int target){
	if (!IsPlayerAlive(target))
		return Plugin_Continue;
	
	int edict = -1;
	while((edict = FindEntityByClassname(edict, "tf_wearable")) != -1)
	{
		char netclass[32];
		if (GetEntityNetClass(edict, netclass, sizeof(netclass)) && StrEqual(netclass, "CTFWearable"))
		{
			if (GetEntPropEnt(edict, Prop_Send, "m_hOwnerEntity") == target)
			{
				int index = GetEntProp(edict, Prop_Send, "m_iItemDefinitionIndex");
				if (index == 619 || index == 623 || index == 624)
				{
					TF2Attrib_SetByDefIndex(edict, 227, view_as<float>(0));
					TF2Attrib_SetByDefIndex(edict, 152, view_as<float>(0));
				}
			}
		}
	}
	int wepEnt = GetPlayerWeaponSlot(target, 2);
	int wepIndex = GetEntProp(wepEnt, Prop_Send, "m_iItemDefinitionIndex");
	if (wepIndex == 474){
		TF2Attrib_SetByDefIndex(wepEnt, 227, view_as<float>(0));
		TF2Attrib_SetByDefIndex(wepEnt, 152, view_as<float>(0));
	}
	return Plugin_Stop;
}

void Notify_ItemChange(any ref) {
	int iClient = EntRefToEntIndex(ref);
	if(iClient == INVALID_ENT_REFERENCE)
		return;
		
	CPrintToChat(iClient, "%s%T", PREFIX, "Notify Decalban", iClient);
}