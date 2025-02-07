
#define POPCOUNT_SURVIVORS "survivors"					//Not dead at roundend
#define POPCOUNT_DEADS "deads"							//Dead at roundend
#define POPCOUNT_ESCAPEES "escapees"					//Not dead and on centcom/shuttles marked as escaped
#define POPCOUNT_SHUTTLE_ESCAPEES "shuttle_escapees" 	//Emergency shuttle only
#define POPCOUNT_ANOTHER_ESCAPEES "another_escapees" 	//Another way than shuttle to escape
#define PERSONAL_LAST_ROUND "personal last round"
#define SERVER_LAST_ROUND "server last round"

/datum/controller/subsystem/ticker/proc/gather_roundend_feedback()
	gather_antag_data()
	var/json_file = file("[GLOB.log_directory]/round_end_data.json")
	// All but npcs sublists and ghost category contain only mobs with minds
	var/list/file_data = list("escapees" = list("humans" = list(), "silicons" = list(), "others" = list(), "npcs" = list()), "abandoned" = list("humans" = list(), "silicons" = list(), "others" = list(), "npcs" = list()), "ghosts" = list(), "additional data" = list())
	var/num_survivors = 0 //Count of non-brain non-camera mobs with mind that are alive
	var/num_deads = 0 //Count of non-brain non-camera mobs with mind that are dead
	var/num_escapees = 0 //Above and on centcom z
	var/num_shuttle_escapees = 0 //Above and on escape shuttle
	var/num_another_escapees = 0 //Above and on escape pod or anothers ways
	for(var/mob/M in GLOB.mob_list)
		var/list/mob_data = list()
		if(isnewplayer(M))
			continue

		var/escape_status = "abandoned" //default to abandoned
		var/category = "npcs" //Default to simple count only bracket
		var/count_only = TRUE //Count by name only or full info

		mob_data["name"] = M.name
		if(M.mind)
			count_only = FALSE
			mob_data["ckey"] = M.mind.key
			if(M.stat != DEAD && !isbrain(M) && !iscameramob(M))
				num_survivors++
			else
				num_deads++
			if(isliving(M))
				var/mob/living/L = M
				mob_data["location"] = get_area(L)
				mob_data["health"] = L.health
				if(ishuman(L))
					var/mob/living/carbon/human/H = L
					category = "humans"
					if(H.mind)
						mob_data["job"] = H.mind.assigned_role
					else
						mob_data["job"] = "Unknown"
					mob_data["species"] = H.dna.species.name
				else
					category = "others"
					mob_data["typepath"] = M.type
		//Ghosts don't care about minds, but we want to retain ckey data etc
		if(isobserver(M))
			count_only = FALSE
			escape_status = "ghosts"
			if(!M.mind)
				mob_data["ckey"] = M.key
			category = null //ghosts are one list deep
		//All other mindless stuff just gets counts by name
		if(count_only)
			var/list/npc_nest = file_data["[escape_status]"]["npcs"]
			var/name_to_use = initial(M.name)
			if(ishuman(M))
				name_to_use = "Unknown Human" //Monkeymen and other mindless corpses
			if(npc_nest.Find(name_to_use))
				file_data["[escape_status]"]["npcs"][name_to_use] += 1
			else
				file_data["[escape_status]"]["npcs"][name_to_use] = 1
		else
			//Mobs with minds and ghosts get detailed data
			if(category)
				var/pos = length(file_data["[escape_status]"]["[category]"]) + 1
				file_data["[escape_status]"]["[category]"]["[pos]"] = mob_data
			else
				var/pos = length(file_data["[escape_status]"]) + 1
				file_data["[escape_status]"]["[pos]"] = mob_data

	WRITE_FILE(json_file, json_encode(file_data))

	SSblackbox.record_feedback("nested tally", "round_end_stats", num_survivors, list("survivors", "total"))
	SSblackbox.record_feedback("nested tally", "round_end_stats", num_deads, list("deads", "total"))
	SSblackbox.record_feedback("nested tally", "round_end_stats", GLOB.joined_player_list.len, list("players", "total"))
	SSblackbox.record_feedback("nested tally", "round_end_stats", GLOB.joined_player_list.len - num_survivors, list("players", "dead"))
	. = list()
	.[POPCOUNT_SURVIVORS] = num_survivors
	.[POPCOUNT_DEADS] = num_deads
	.[POPCOUNT_ESCAPEES] = num_escapees
	.[POPCOUNT_SHUTTLE_ESCAPEES] = num_shuttle_escapees
	.[POPCOUNT_ANOTHER_ESCAPEES] = num_another_escapees

/datum/controller/subsystem/ticker/proc/gather_antag_data()
	var/team_gid = 1
	var/list/team_ids = list()

	var/list/greentexters = list()

	for(var/datum/antagonist/A in GLOB.antagonists)
		if(!A.owner)
			continue
		var/ckey = ckey(A.owner?.key)
		var/client/C = GLOB.directory[ckey]

		var/list/antag_info = list()
		antag_info["key"] = A.owner.key
		antag_info["name"] = A.owner.name
		antag_info["antagonist_type"] = A.type
		antag_info["antagonist_name"] = A.name //For auto and custom roles
		antag_info["objectives"] = list()
		antag_info["team"] = list()
		var/datum/team/T = A.get_team()
		if(T)
			antag_info["team"]["type"] = T.type
			antag_info["team"]["name"] = T.name
			if(!team_ids[T])
				team_ids[T] = team_gid++
			antag_info["team"]["id"] = team_ids[T]

		var/greentexted = TRUE

		if(A.objectives.len)
			for(var/datum/objective/O in A.objectives)
				var/result = O.check_completion() ? "SUCCESS" : "FAIL"
				if (result == "FAIL")
					greentexted = FALSE
				antag_info["objectives"] += list(list("objective_type"=O.type,"text"=O.explanation_text,"result"=result))
		SSblackbox.record_feedback("associative", "antagonists", 1, antag_info)

		if (greentexted)
			if (A.owner && A.owner.key)
				if (A.type != /datum/antagonist/custom)
					if (C)
						greentexters |= C

/datum/controller/subsystem/ticker/proc/declare_completion()
	set waitfor = FALSE

	to_chat(world, "<br><br><br><center><span class='big bold'>Round Ended.</span></center><br><br><br>")

	log_game("The round has ended.")

	for(var/I in round_end_events)
		var/datum/callback/cb = I
		cb.InvokeAsync()
	LAZYCLEARLIST(round_end_events)

	for(var/client/C in GLOB.clients)
		if(!C.credits)
			C.RollCredits()
		C.playtitlemusic(5)

	var/popcount = gather_roundend_feedback()
	display_report(popcount)

	CHECK_TICK

	// Add AntagHUD to everyone, see who was really evil the whole time!
	for(var/datum/atom_hud/antag/H in GLOB.huds)
		for(var/m in GLOB.player_list)
			var/mob/M = m
			H.add_hud_to(M)

	CHECK_TICK

	//Set news report and mode result
	mode.set_round_result()

	if(length(CONFIG_GET(keyed_list/cross_server)))
		send_news_report()

	CHECK_TICK

	handle_hearts()
	set_observer_default_invisibility(0, span_warning("The round has ended. You are now visible!"))

	CHECK_TICK

	//These need update to actually reflect the real antagonists
	//Print a list of antagonists to the server log
	var/list/total_antagonists = list()
	//Look into all mobs in world, dead or alive
	for(var/datum/antagonist/A in GLOB.antagonists)
		if(!A.owner)
			continue
		if(!(A.name in total_antagonists))
			total_antagonists[A.name] = list()
		total_antagonists[A.name] += "[key_name(A.owner)]"

	CHECK_TICK

	//Now print them all into the log!
	log_game("Antagonists at round end were...")
	for(var/antag_name in total_antagonists)
		var/list/L = total_antagonists[antag_name]
		log_game("[antag_name]s :[L.Join(", ")].")

	CHECK_TICK
	SSdbcore.SetRoundEnd()
	//Collects persistence features
	if(mode.allow_persistence_save)
		SSpersistence.CollectData()

	//stop collecting feedback during grifftime
	SSblackbox.Seal()

	sleep(50)
	ready_for_reboot = TRUE
	standard_reboot()

/datum/controller/subsystem/ticker/proc/standard_reboot()
	if(ready_for_reboot)
		Reboot("Round Ended.", "proper completion")
	else
		CRASH("Attempted standard reboot without ticker roundend completion")

//Common part of the report
/datum/controller/subsystem/ticker/proc/build_roundend_report()
	var/list/parts = list()

	//Gamemode specific things. Should be empty most of the time.
	parts += mode.special_report()

	CHECK_TICK

	//Antagonists
	parts += antag_report()

	parts += hardcore_random_report()

	CHECK_TICK
	//Medals
	parts += medal_report()

	list_clear_nulls(parts)

	return parts.Join()

/datum/controller/subsystem/ticker/proc/survivor_report(popcount)
	var/list/parts = list()

	parts += "<hr><b><font color=\"#60b6ff\">Round Information //</font></b>"
	if(GLOB.round_id)
		var/statspage = CONFIG_GET(string/roundstatsurl)
		var/info = statspage ? "<a href='?action=openLink&link=[url_encode(statspage)][GLOB.round_id]'>[GLOB.round_id]</a>" : GLOB.round_id
		parts += "[FOURSPACES]├ Round ID: <b>[info]</b>"
	else
		parts += "[FOURSPACES]├ Round ID: <b>(<i>unavailable</i>)</b>"
	parts += "[FOURSPACES]└ Round Duration: <b>[DisplayTimeText(world.time - SSticker.round_start_time)]</b>"

	parts += "<hr><b><font color=\"#60b6ff\">Player Information //</font></b>"
	var/total_players = GLOB.joined_player_list.len
	if(total_players)
		parts += "[FOURSPACES]├ Total: <b>[total_players]</b>"
		parts += "[FOURSPACES]├ Dead: <b>[popcount[POPCOUNT_DEADS]]</b> (or <b>[PERCENT(popcount[POPCOUNT_DEADS]/total_players)]%</b> of total)"
		parts += "[FOURSPACES]├ Survived: <b>[popcount[POPCOUNT_SURVIVORS]]</b> (or <b>[PERCENT(popcount[POPCOUNT_SURVIVORS]/total_players)]%</b> of total)"
		parts += "<hr><b><font color=\"#60b6ff\">First Death //</font></b>"
		if(SSblackbox.first_death)
			var/list/first_death = SSblackbox.first_death
			if(first_death.len)
				parts += "[FOURSPACES]├ Name: <b>[first_death["name"]]</b>"
				parts += "[FOURSPACES]├ Area: <b>[first_death["area"]]</b>"
				parts += "[FOURSPACES]├ Damage: <b>[first_death["damage"]]</b>"
				parts += "[FOURSPACES]└ Last Words: <b>[first_death["last_words"] ? "[first_death["last_words"]]" : "<i>none</i>"]</b>"
				// ignore this comment, it fixes the broken sytax parsing caused by the " above
			else
				parts += "[FOURSPACES]└ <span class='greentext'>Nobody died </span>!"
	else
		parts += "[FOURSPACES]└ <i><span class='redtext'>No players</span>?</i>"

	return parts.Join("<br>")

/client/proc/roundend_report_file()
	return "data/roundend_reports/[ckey].html"

/**
 * Log the round-end report as an HTML file
 *
 * Composits the roundend report, and saves it in two locations.
 * The report is first saved along with the round's logs
 * Then, the report is copied to a fixed directory specifically for
 * housing the server's last roundend report. In this location,
 * the file will be overwritten at the end of each shift.
 */
/datum/controller/subsystem/ticker/proc/log_roundend_report()
	var/filename = "[GLOB.log_directory]/round_end_data.html"
	var/list/parts = list()
	parts += GLOB.survivor_report
	parts += "</div>"
	parts += GLOB.common_report
	var/content = parts.Join()
	//Log the rendered HTML in the round log directory
	fdel(filename)
	text2file(content, filename)
	//Place a copy in the root folder, to be overwritten each round.
	filename = "data/server_last_roundend_report.html"
	fdel(filename)
	text2file(content, filename)

/datum/controller/subsystem/ticker/proc/show_roundend_report(client/C, report_type = null)
	var/datum/browser/roundend_report = new(C, "roundend")
	roundend_report.width = 800
	roundend_report.height = 600
	var/content
	var/filename = C.roundend_report_file()
	if(report_type == PERSONAL_LAST_ROUND) //Look at this player's last round
		content = file2text(filename)
	else if (report_type == SERVER_LAST_ROUND) //Look at the last round that this server has seen
		content = file2text("data/server_last_roundend_report.html")
	else //report_type is null, so make a new report based on the current round and show that to the player
		var/list/report_parts = list(personal_report(C), GLOB.common_report)
		content = report_parts.Join()
		remove_verb(C, /client/proc/show_previous_roundend_report)
		fdel(filename)
		text2file(content, filename)

	roundend_report.set_content(content)
	roundend_report.stylesheets = list()
	roundend_report.add_stylesheet("roundend", 'html/browser/roundend.css')
	roundend_report.add_stylesheet("font-awesome", 'html/font-awesome/css/all.min.css')
	roundend_report.open(FALSE)

/datum/controller/subsystem/ticker/proc/personal_report(client/C, popcount)
	var/list/parts = list()
	// var/mob/M = C.mob
	parts += "<br><center><span class='big bold'>Round End</span></center>"
	parts += "</div>"

	return parts.Join()

/datum/controller/subsystem/ticker/proc/display_report(popcount)
	GLOB.common_report = build_roundend_report()
	GLOB.survivor_report = survivor_report(popcount)
	log_roundend_report()
	for(var/client/C in GLOB.clients)
		show_roundend_report(C)
		give_show_report_button(C)
		CHECK_TICK

/datum/controller/subsystem/ticker/proc/medal_report()
	if(GLOB.commendations.len)
		var/list/parts = list()
		parts += span_header("Medal Commendations:")
		for (var/com in GLOB.commendations)
			parts += com
		return "<div class='panel stationborder'>[parts.Join("<br>")]</div>"
	return ""

///Generate a report for all players who made it out alive with a hardcore random character and prints their final score
/datum/controller/subsystem/ticker/proc/hardcore_random_report()
	. = list()
	var/list/hardcores = list()
	for(var/i in GLOB.player_list)
		if(!ishuman(i))
			continue
		var/mob/living/carbon/human/human_player = i
		if(!human_player.hardcore_survival_score || !human_player.onCentCom() || human_player.stat == DEAD) ///gotta escape nerd
			continue
		if(!human_player.mind)
			continue
		hardcores += human_player
	if(!length(hardcores))
		return
	. += "<div class='panel stationborder'><span class='header'>The following people made it out as a random hardcore character:</span>"
	. += "<ul class='playerlist'>"
	for(var/mob/living/carbon/human/human_player in hardcores)
		. += "<li>[printplayer(human_player.mind)] with a hardcore random score of [round(human_player.hardcore_survival_score)]</li>"
	. += "</ul></div>"

/datum/controller/subsystem/ticker/proc/antag_report()
	var/list/result = list()
	var/list/all_teams = list()
	var/list/all_antagonists = list()

	for(var/datum/team/A in GLOB.antagonist_teams)
		all_teams |= A

	for(var/datum/antagonist/A in GLOB.antagonists)
		if(!A.owner)
			continue
		all_antagonists |= A

	for(var/datum/team/T in all_teams)
		result += T.roundend_report()
		for(var/datum/antagonist/X in all_antagonists)
			if(X.get_team() == T)
				all_antagonists -= X
		result += " "//newline between teams
		CHECK_TICK

	var/currrent_category
	var/datum/antagonist/previous_category

	sortTim(all_antagonists, GLOBAL_PROC_REF(cmp_antag_category))

	for(var/datum/antagonist/A in all_antagonists)
		if(!A.show_in_roundend)
			continue
		if(A.roundend_category != currrent_category)
			if(previous_category)
				result += previous_category.roundend_report_footer()
				result += "</div>"
			result += "<div class='panel redborder'>"
			result += A.roundend_report_header()
			currrent_category = A.roundend_category
			previous_category = A
		result += A.roundend_report()
		result += "<br><br>"
		CHECK_TICK

	if(all_antagonists.len)
		var/datum/antagonist/last = all_antagonists[all_antagonists.len]
		result += last.roundend_report_footer()
		result += "</div>"

	return result.Join()

/proc/cmp_antag_category(datum/antagonist/A,datum/antagonist/B)
	return sorttext(B.roundend_category,A.roundend_category)


/datum/controller/subsystem/ticker/proc/give_show_report_button(client/C)
	var/datum/action/report/R = new
	C.player_details.player_actions += R
	R.Grant(C.mob)
	to_chat(C,"<a href='?src=[REF(R)];report=1'>Show round end results again.</a>")

/datum/action/report
	name = "Show round end results"
	button_icon_state = "round_end"

/datum/action/report/Trigger()
	if(owner && GLOB.common_report && SSticker.current_state == GAME_STATE_FINISHED)
		SSticker.show_roundend_report(owner.client)

/datum/action/report/IsAvailable()
	return 1

/datum/action/report/Topic(href,href_list)
	if(usr != owner)
		return
	if(href_list["report"])
		Trigger()
		return


/proc/printplayer(datum/mind/ply, fleecheck)
	var/jobtext = ""
	if(ply.assigned_role)
		jobtext = " <b>[ply.assigned_role]</b>"
	var/text = "<b>[ply.key]</b> as <b>[ply.name]</b>[jobtext] "
	if(ply.current)
		if(ply.current.stat == DEAD)
			text += " <span class='redtext'>died</span>"
		else
			text += " <span class='greentext'>survived</span>"
		if(ply.current.real_name != ply.name)
			text += " as <b>[ply.current.real_name]</b>"
	else
		text += " <span class='redtext'>destroyed</span>"
	return text

/proc/printplayerlist(list/players,fleecheck)
	var/list/parts = list()

	parts += "<ul class='playerlist'>"
	for(var/datum/mind/M in players)
		parts += "<li>[printplayer(M,fleecheck)]</li>"
	parts += "</ul>"
	return parts.Join()


/proc/printobjectives(list/objectives)
	if(!objectives || !objectives.len)
		return
	var/list/objective_parts = list()
	var/count = 1
	for(var/datum/objective/objective in objectives)
		if(objective.check_completion())
			objective_parts += "<b>Objective #[count]</b>: [objective.explanation_text] <span class='greentext'>Success!</span>"
		else
			objective_parts += "<b>Objective #[count]</b>: [objective.explanation_text] <span class='redtext'>Fail.</span>"
		count++
	return objective_parts.Join("<br>")

/datum/controller/subsystem/ticker/proc/save_admin_data()
	if(IsAdminAdvancedProcCall())
		to_chat(usr, "<span class='admin prefix'>Admin rank DB Sync blocked: Advanced ProcCall detected.</span>")
		return
	if(CONFIG_GET(flag/admin_legacy_system)) //we're already using legacy system so there's nothing to save
		return
	else if(load_admins(TRUE)) //returns true if there was a database failure and the backup was loaded from
		return
	sync_ranks_with_db()
	var/list/sql_admins = list()
	for(var/i in GLOB.protected_admins)
		var/datum/admins/A = GLOB.protected_admins[i]
		sql_admins += list(list("ckey" = A.target, "rank" = A.rank.name))
	SSdbcore.MassInsert(format_table_name("admin"), sql_admins, duplicate_key = TRUE)
	var/datum/db_query/query_admin_rank_update = SSdbcore.NewQuery("UPDATE [format_table_name("player")] p INNER JOIN [format_table_name("admin")] a ON p.ckey = a.ckey SET p.lastadminrank = a.rank")
	query_admin_rank_update.Execute()
	qdel(query_admin_rank_update)

	//json format backup file generation stored per server
	var/json_file = file("data/admins_backup.json")
	var/list/file_data = list("ranks" = list(), "admins" = list())
	for(var/datum/admin_rank/R in GLOB.admin_ranks)
		file_data["ranks"]["[R.name]"] = list()
		file_data["ranks"]["[R.name]"]["include rights"] = R.include_rights
		file_data["ranks"]["[R.name]"]["exclude rights"] = R.exclude_rights
		file_data["ranks"]["[R.name]"]["can edit rights"] = R.can_edit_rights
	for(var/i in GLOB.admin_datums+GLOB.deadmins)
		var/datum/admins/A = GLOB.admin_datums[i]
		if(!A)
			A = GLOB.deadmins[i]
			if (!A)
				continue
		file_data["admins"]["[i]"] = A.rank.name
	fdel(json_file)
	WRITE_FILE(json_file, json_encode(file_data))

/datum/controller/subsystem/ticker/proc/update_everything_flag_in_db()
	for(var/datum/admin_rank/R in GLOB.admin_ranks)
		var/list/flags = list()
		if(R.include_rights == R_EVERYTHING)
			flags += "flags"
		if(R.exclude_rights == R_EVERYTHING)
			flags += "exclude_flags"
		if(R.can_edit_rights == R_EVERYTHING)
			flags += "can_edit_flags"
		if(!flags.len)
			continue
		var/flags_to_check = flags.Join(" != [R_EVERYTHING] AND ") + " != [R_EVERYTHING]"
		var/datum/db_query/query_check_everything_ranks = SSdbcore.NewQuery(
			"SELECT flags, exclude_flags, can_edit_flags FROM [format_table_name("admin_ranks")] WHERE rank = :rank AND ([flags_to_check])",
			list("rank" = R.name)
		)
		if(!query_check_everything_ranks.Execute())
			qdel(query_check_everything_ranks)
			return
		if(query_check_everything_ranks.NextRow()) //no row is returned if the rank already has the correct flag value
			var/flags_to_update = flags.Join(" = [R_EVERYTHING], ") + " = [R_EVERYTHING]"
			var/datum/db_query/query_update_everything_ranks = SSdbcore.NewQuery(
				"UPDATE [format_table_name("admin_ranks")] SET [flags_to_update] WHERE rank = :rank",
				list("rank" = R.name)
			)
			if(!query_update_everything_ranks.Execute())
				qdel(query_update_everything_ranks)
				return
			qdel(query_update_everything_ranks)
		qdel(query_check_everything_ranks)
