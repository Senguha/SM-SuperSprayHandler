#if defined _ssh_included
	#endinput
#endif
#define _ssh_included
#pragma newdecls required

/**
 * Called when a client gets spray banned.
 *
 * @param userName		Name of the user that got spray banned.
 * @param userAuth		SteamID of the user that got spray banned.
 * @param adminName		Name of the admin that banned the user.
 * @param adminAuth		SteamID of the admin that banned the user.
 * @param time			Duration of the ban in seconds.
 * @param reason		Reason of the ban.
 *
 * @noreturn
 */
forward void SSH_OnBan(char[] userName, char[] userAuth, char[] adminName, char[] adminAuth, int time, char[] reason);

public SharedPlugin __pl_ranking =
{
	name = "ssh",
	file = "supersprayhandler.smx",
	#if defined REQUIRE_PLUGIN
	required = 1,
	#else
	required = 0,
	#endif
};