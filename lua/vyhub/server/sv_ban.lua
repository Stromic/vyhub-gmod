VyHub.Ban = VyHub.Ban or {}
VyHub.Ban.ban_queue = VyHub.Ban.ban_queue or {}
VyHub.Ban.unban_queue = VyHub.Ban.unban_queue or {}

--[[
    ban_queue: Dict[<user_steamid>,List[Dict[...]\]\]
        user_steamid: str
        length: int (seconds)
        reason: str
        creator_steamid: str
        created_on: date
        status: str

    unban_queue: Dict[<user_steamid>, <processor_steamid>]
]]--


local default_ban_msg = ">>> Ban Message <<<" .. "\n\n"
.. VyHub.lang.other.reason .. ": %reason%" .. "\n" 
.. VyHub.lang.other.ban_date .. ": %ban_date%" .. "\n" 
.. VyHub.lang.other.unban_date .. ": %unban_date%" .. "\n" 
.. VyHub.lang.other.admin .. ": %admin%" .. "\n" 
.. VyHub.lang.other.id .. ": %id%" .. "\n\n" 
.. VyHub.lang.other.unban_url .. ": %unban_url%" .. "\n\n" 

function VyHub.Ban:check_player_banned(steamid)
    local bans = VyHub.bans[steamid]
    local queued_bans = VyHub.Ban.ban_queue[steamid]

    ban_exists = bans != nil and not table.IsEmpty(bans)

    queued_ban_exists = false

    if queued_bans != nil then
        for _, ban in pairs(queued_bans) do
            if ban != nil and ban.status == 'ACTIVE' then
                queued_ban_exists = true 
                break
            end
        end
    end

    queued_unban_exists = VyHub.Ban.unban_queue[steamid] != nil

    return (ban_exists or queued_ban_exists) and not queued_unban_exists
end

function VyHub.Ban:kick_banned_players()
    for _, ply in pairs(player.GetHumans()) do
        if VyHub.Ban:check_player_banned(ply:SteamID64()) then
            ply:Kick("You are banned from the server.")
        end    
    end
end

function VyHub.Ban:refresh()
    VyHub.API:get("/server/bundle/%s/ban", { VyHub.server.serverbundle_id }, { active = "true" }, function(code, result)
        VyHub.bans = result

        VyHub.Cache:save("bans", VyHub.bans)
        
        VyHub:msg(string.format("Found %s users with active bans.", table.Count(VyHub.bans)), "debug")

        hook.Run("vyhub_bans_refreshed")
    end, function()
        VyHub:msg("Could not refresh bans, trying to use cache.", "error")

        local result = VyHub.Cache:get("bans")

        if result != nil then
            VyHub.bans = result

            VyHub:msg(string.format("Found %s users with cached active bans.", table.Count(VyHub.bans)), "neutral")

            hook.Run("vyhub_bans_refreshed")
        else
            VyHub:msg("No cached bans available!", "error")
        end
    end)
end

function VyHub.Ban:handle_queue()
    local function failed_ban(steamid)
        VyHub:msg(string.format("Could not send ban of user %s to API. Retrying..", steamid), "error")
    end

    local function failed_unban(steamid)
        VyHub:msg(string.format("Could not send unban of user %s to API. Retrying..", steamid), "error")
    end

    local function failed_ban_abort(steamid)
        
    end

    if not table.IsEmpty(VyHub.Ban.ban_queue) then
        for steamid, bans in pairs(VyHub.Ban.ban_queue) do
            if bans != nil then
                if not table.IsEmpty(bans) then
                    for i, ban in pairs(bans) do
                        if ban != nil then
                            VyHub.Player:get(ban.user_steamid, function(user)
                                if user then
                                    VyHub.Player:get(ban.creator_steamid, function(creator)
                                        if creator == false then
                                            return
                                        end

                                        local data = {
                                            length = ban.length,
                                            reason = ban.reason,
                                            serverbundle_id = VyHub.server.serverbundle.id,
                                            user_id = user.id,
                                            created_on = ban.created_on,
                                            status = ban.status,
                                        }

                                        local morph_user_id = creator and creator.id or nil
                                        local url = '/ban/'

                                        if morph_user_id != nil then
                                            url = url .. f('?morph_user_id=%s', morph_user_id)
                                        end
                
                                        VyHub.API:post(url, nil, data, function(code, result)
                                            VyHub.Ban.ban_queue[steamid][i] = nil
                                            VyHub.Ban:save_queues()
                                            VyHub.Ban:refresh()

                                            local msg = f(VyHub.lang.ban.created, user.username, data.reason)

                                            VyHub:msg(msg, "success")

                                            if creator != nil then
                                                VyHub.Util:print_chat_steamid(creator.identifier, msg)
                                            end
                                        end, function(code, reason)
                                            if code >= 400 and code < 500 then
                                                msg = reason

                                                local error_msg = string.format("Could not create ban for %s, aborting: %s", steamid, json.encode(msg))

                                                VyHub:msg(error_msg, "error")
                                                
                                                VyHub.Ban.ban_queue[steamid][i] = nil
                                                VyHub.Ban:save_queues()

                                                if creator != nil then
                                                    VyHub.Util:print_chat_steamid(creator.identifier, error_msg)
                                                end
                                            else
                                                failed_ban(ban.user_steamid)
                                            end
                                        end)
                                    end)
                                elseif user == false then 
                                    VyHub.Ban.ban_queue[steamid][i] = nil
                                    VyHub.Ban:save_queues()
                                else
                                    failed_ban(ban.user_steamid)
                                end                            
                            end)
                        end
                    end
                else
                    VyHub.Ban.ban_queue[steamid] = nil
                    VyHub.Ban:save_queues()
                end
            end
        end
    end

    if not table.IsEmpty(VyHub.Ban.unban_queue) then
        for steamid, creator_steamid in pairs(VyHub.Ban.unban_queue) do
            if creator_steamid == nil then
                continue 
            end

            VyHub.Player:get(steamid, function(user)
                if user == false then
                    VyHub.Ban.unban_queue[steamid] = nil
                    VyHub.Ban:save_queues()

                    local error_msg = f("Could not unban user %s, aborting: User not found", steamid)

                    VyHub:msg(error_msg, "error")
                    VyHub.Util:print_chat_steamid(creator_steamid, error_msg)
                elseif user == nil then
                    failed_unban(steamid)
                else
                    local url = '/user/%s/ban'

                    creator_steamid = creator_steamid == false and nil or creator_steamid

                    VyHub.Player:get(creator_steamid, function(creator)
                        if creator_steamid != nil and creator == nil then
                            return
                        end

                        if creator then
                            url = url .. f('?morph_user_id=%s', creator.id)
                        end

                        VyHub.API:patch(url, {user.id}, nil, function (code, reslt)
                            VyHub.Ban.unban_queue[steamid] = nil
                            VyHub.Ban:save_queues()
                            VyHub.Ban:refresh()
    
                            local msg = f("Successfully unbanned user %s.", steamid)
                            VyHub:msg(msg, "success")
                            VyHub.Util:print_chat_steamid(creator_steamid, msg)
                        end, function (code, reason)
                            if code >= 400 and code < 500 then
                                VyHub.Ban.unban_queue[steamid] = nil
                                VyHub.Ban:save_queues()
                                
                                local error_msg = f("Could not unban user %s, aborting: %s", steamid, json.encode(msg))
    
                                VyHub:msg(error_msg, "error")
                                VyHub.Util:print_chat_steamid(creator_steamid, error_msg)
                            else
                                failed_unban(steamid)
                            end
                        end)
                    end)
                end
            end)
        end
    end
end

function VyHub.Ban:create(steamid, length, reason, creator_steamid)
    length = tonumber(length)

    if length == 0 then
        length = nil
    end

    local data = {
        user_steamid = steamid,
        length = length and length * 60 or nil,
        reason = reason,
        creator_steamid = creator_steamid,
        created_on = VyHub.Util:format_datetime(),
        status = 'ACTIVE',
    }

    if VyHub.Ban.ban_queue[steamid] == nil then
        VyHub.Ban.ban_queue[steamid] = {}
    end

    table.insert(VyHub.Ban.ban_queue[steamid], data)

    local ply = player.GetBySteamID64(steamid)
    if IsValid(ply) then
        local lstr = length == nil and VyHub.lang.other.permanently or f("%i %s", length, VyHub.lang.other.minutes)

        VyHub.Util:print_chat_all(f(VyHub.lang.ply.banned, ply:Nick(), lstr, reason))
    end

    VyHub.Ban:kick_banned_players()
    VyHub.Ban:save_queues()
    VyHub.Ban:handle_queue()

    VyHub:msg(string.format("Scheduled ban for user %s.", steamid))
end

function VyHub.Ban:unban(steamid, processor_steamid)
    processor_steamid = processor_steamid or false

    if VyHub.Ban.ban_queue[steamid] != nil then
        for i, ban in pairs(VyHub.Ban.ban_queue[steamid]) do
            if ban != nil and ban.status != 'UNBANNED' then
                VyHub.Ban.ban_queue[steamid][i].status = 'UNBANNED'

                VyHub:msg(string.format("Set status of queued ban of %s to UNBANNED.", steamid), 'neutral')
            end
        end
    end

    VyHub.Ban.unban_queue[steamid] = processor_steamid

    VyHub.Ban:save_queues()
    VyHub.Ban:handle_queue()

    VyHub:msg(string.format("Scheduled unban for user %s.", steamid))
end

function VyHub.Ban:save_queues()
    VyHub.Cache:save("ban_queue", VyHub.Ban.ban_queue)
    VyHub.Cache:save("unban_queue", VyHub.Ban.unban_queue)
end

function VyHub.Ban:clear()
    VyHub.Ban.ban_queue = {}
    VyHub.Ban.unban_queue = {}
    VyHub.Ban:save_queues()
end

function VyHub.Ban:create_ban_msg(ban)
    local msg = VyHub.Config.ban_message or default_ban_msg

    local created_on = VyHub.Util:iso_ts_to_local_str(ban.created_on)
    local ends_on = ban.ends_on != nil and VyHub.Util:iso_ts_to_local_str(ban.ends_on) or VyHub.lang.other.never
    local creator_username = ban.creator != nil and ban.creator.username or VyHub.lang.other.unknown
    local id = string.upper(string.sub(ban.id, 1, 8))
    local unban_url = VyHub.Config.unban_url or VyHub.frontend_url or '-'

    msg = string.Replace(msg, '%reason%', ban.reason)
    msg = string.Replace(msg, '%ban_date%', created_on)
    msg = string.Replace(msg, '%unban_date%', ends_on)
    msg = string.Replace(msg, '%admin%', creator_username)
    msg = string.Replace(msg, '%id%', id)
    msg = string.Replace(msg, '%unban_url%', unban_url)

    return msg
end

hook.Add("vyhub_ready", "vyhub_ban_vyhub_ready", function ()
    VyHub.Ban:refresh()

    VyHub.Ban.ban_queue = VyHub.Cache:get("ban_queue") or {}
    VyHub.Ban.unban_queue = VyHub.Cache:get("unban_queue") or {}

    timer.Create("vyhub_ban_refresh", 60, 0, function()
        VyHub.Ban:refresh()
    end)

    timer.Create("vyhub_ban_handle_queues", 10, 0, function ()
        VyHub.Ban:handle_queue()
    end)

    hook.Add("CheckPassword", "vyhub_ban_CheckPassword", function(steamid64, ip)
        if VyHub.Ban:check_player_banned(steamid64) then
            local msg = VyHub.lang.ply.banned_self
            
            local bans = VyHub.bans[steamid64] or {}

            if table.Count(bans) > 0 then
                local ban = bans[1]
                msg = VyHub.Ban:create_ban_msg(ban)
            end

            VyHub:msg(f("%s tried to connect with ip %s, but is banned.", steamid64, ip))
            return false, msg
        end
    end)
end)


hook.Add("vyhub_ready", "vyhub_ban_replacements_vyhub_ready", function()
    if ULib then
        ULib.kickban = function(ply, length, reason, admin)
            if IsValid(ply) then
                if IsValid(admin) then
                    VyHub.Ban:create(ply:SteamID64(), length, reason, admin:SteamID64())
                else
                    VyHub.Ban:create(ply:SteamID64(), length, reason)
                end
            end
        end

        ULib.ban = function(ply, length, reason, admin)
            if IsValid(ply) then
                if IsValid(admin) then
                    VyHub.Ban:create(ply:SteamID64(), length, reason, admin:SteamID64())
                else
                    VyHub.Ban:create(ply:SteamID64(), length, reason)
                end
            end
        end

        ULib.addBan = function(steamid32, length, reason, nick, admin)
            local steamid64 = util.SteamIDTo64(steamid32)

            if not steamid64 then return end

            if IsValid(admin) then
                VyHub.Ban:create(steamid64, length, reason, admin:SteamID64())
            else
                VyHub.Ban:create(steamid64, length, reason)
            end
        end

        VyHub.Ban.ulx_unban = VyHub.Ban.ulx_unban or ULib.unban

        ULib.unban = function(steamid32, steamid32_admin)
            if VyHub.Config.ulib_replace_bans then
                if string.match(debug.traceback(), "xgui/server/sv_bans.lua") then
                    return false
                end
            end

            local steamid64 = util.SteamIDTo64(steamid32)
            local steamid64_admin = nil

            if steamid32_admin then
                if VyHub.Util.is_server(steamid32_admin) then
                    steamid64_admin = nil
                elseif isentity(steamid32_admin) and steamid32_admin:IsPlayer() and IsValid(steamid32_admin) then
                    steamid64_admin = steamid32_admin:SteamID64()
                elseif isstring(steamid32_admin) and string.find(steamid32_admin, "STEAM_(%d+):(%d+):(%d+)") then
                    steamid64_admin = util.SteamIDTo64(steamid32_admin)
                end
            end

            if steamid64 then
                if steamid64_admin == nil then
                    VyHub.Ban:unban(steamid64, steamid64_admin)
                else
                    local ply = player.GetBySteamID64(steamid64_admin)

                    if IsValid(ply) then
                        VyHub.Ban:unban(steamid64, steamid64_admin)
                    else
                        VyHub:msg("Invalid player tried to unban " .. steamid64 .. ".", "error")
                    end
                end
            end

            if not VyHub.Config.ulib_replace_bans then
                VyHub.Ban.ulx_unban(steamid32, steamid32_admin)
            end
        end

        local function voteBanDone2(t, nick, steamid, time, ply, reason)
            local shouldBan = false

            if t.results[1] and t.results[1] > 0 then
                ulx.fancyLogAdmin(ply, "#A approved the voteban against #s (#s minutes) (#s)", nick, time, reason or "")
                shouldBan = true
            else
                ulx.fancyLogAdmin(ply, "#A denied the voteban against #s", nick)
            end

            if shouldBan then
                local steamid64 = util.SteamIDTo64(steamid)
                VyHub.Ban:create(steamid64, time, reason, nil)
            end
        end

        local function voteBanDone(t, nick, steamid, time, ply, reason)
            local results = t.results
            local winner
            local winnernum = 0
            for id, numvotes in pairs(results) do
                if numvotes > winnernum then
                    winner = id
                    winnernum = numvotes
                end
            end

            local ratioNeeded = GetConVarNumber("ulx_votebanSuccessratio")
            local minVotes = GetConVarNumber("ulx_votebanMinvotes")
            local str
            if winner ~= 1 or winnernum < minVotes or winnernum / t.voters < ratioNeeded then
                str = "Vote results: User will not be banned. (" .. (results[1] or "0") .. "/" .. t.voters .. ")"
            else
                reason = ("[ULX Voteban] " .. (reason or "")):Trim()
                if ply:IsValid() then
                    str = "Vote results: User will now be banned, pending approval. (" .. winnernum .. "/" .. t.voters .. ")"
                    ulx.doVote( "Accept result and ban " .. nick .. "?", {"Yes", "No" }, voteBanDone2, 30000, {ply}, true, nick, steamid, time, ply, reason)
                else -- Vote from server console, roll with it
                    str = "Vote results: User will now be banned. (" .. winnernum .. "/" .. t.voters .. ")"
                    local steamid64 = util.SteamIDTo64(steamid)
                    VyHub.Ban:create(steamid64, time, reason, nil)
                end
            end

            ULib.tsay(_, str) -- TODO, color?
            ulx.logString(str)
            MsgN(str)
        end

        function ulx.voteban(calling_ply, target_ply, minutes, reason)
            if target_ply:IsListenServerHost() or target_ply:IsBot() then
                ULib.tsayError(calling_ply, "This player is immune to banning", true)
                return
            end

            if ulx.voteInProgress then
                ULib.tsayError(calling_ply, "There is already a vote in progress. Please wait for the current one to end.", true)
                return
            end

            local msg = "Ban " .. target_ply:Nick() .. " for " .. minutes .. " minutes?"
            if reason and reason ~= "" then
                msg = msg .. " (" .. reason .. ")"
            end

            ulx.doVote(msg, {"Yes", "No"}, voteBanDone, _, _, _, target_ply:Nick(), target_ply:SteamID(), minutes, calling_ply, reason)
            if reason and reason ~= "" then
                ulx.fancyLogAdmin(calling_ply, "#A started a voteban of #i minute(s) against #T (#s)", minutes, target_ply, reason )
            else
                ulx.fancyLogAdmin(calling_ply, "#A started a voteban of #i minute(s) against #T", minutes, target_ply)
            end
        end

        function ulx_xgui_updateban( ply, args )
            local steamid32 = args[1]
            local steamid64 = util.SteamIDTo64(steamid32)

            if steamid64 then
                VyHub:get_frontend_url(function (frontend_url)
                    if frontend_url != nil then
                        ply:vh_open_url(frontend_url .. "/bans")
                    end
                end)
            end
        end
        xgui.addCmd( "updateBan", ulx_xgui_updateban )

        function VyHub.Ban:replace_ulib_bans()
            hook.Remove("CheckPassword", "ULibBanCheck")
            
            ULib.bans = {}
            for steamid, bans in pairs(VyHub.bans) do
                if bans != nil then
                    for _, ban in pairs(bans) do
                        if ban != nil then
                            local steamid32 = util.SteamIDFrom64(steamid)
                            local unban_ts = 0
                            
                            if ban.ends_on != nil then
                                unban_ts = VyHub.Util:iso_to_unix_timestamp(ban.ends_on)
                            end
            
                            ULib.bans[steamid32] = {
                                name = ban.user.username,
                                admin = ban.creator != nil and ban.creator.username or nil,
                                unban = unban_ts,
                                time = VyHub.Util:iso_to_unix_timestamp(ban.created_on),
                                steamID = steamid32,
                                reason = ban.reason,
                            }
                        end
                    end
                end
            end

            xgui.bansbyid = {}
            xgui.bansbyname = {}
            xgui.bansbyadmin = {}
            xgui.bansbyreason = {}
            xgui.bansbydate = {}
            xgui.bansbyunban = {}
            xgui.bansbybanlength = {}
            xgui.sendDataTable({}, "bans")
        end
    end

    if evolve then
        function evolve:Ban(ply, length, reason)
            VyHub.Ban:create(ply:SteamID64(), length, reason)
        end
    end

    if serverguard then
        function serverguard:BanPlayer(admin, ply_obj, length, reason)
            if ply_obj then
                local steamid64 = nil;

                if type(ply_obj) == "Player" then
                    steamid64 = ply_obj:SteamID64()
                elseif type(ply_obj) == "string" then
                    local target = VyHub.Util:get_ply_by_nick(ply_obj)

                    if IsValid(target) then
                        ply_obj = target

                        steamid64 = ply_obj:SteamID64()
                    elseif string.find(ply_obj, "STEAM_(%d+):(%d+):(%d+)") then
                        steamid64 = util.SteamIDTo64(ply_obj)
                    end
                end

                if IsValid(admin) then
                    VyHub.Ban:create(steamid64, length, reason, admin:SteamID64())
                else
                    VyHub.Ban:create(ply:SteamID64(), length, reason)
                end
            end
        end

        VyHub.Ban.servergaurd_unban = VyHub.Ban.servergaurd_unban or serverguard["UnbanPlayer"]

        function serverguard:UnbanPlayer(steamid32, admin)
            local steamid64_admin = "0"
            local steamid64 = util.SteamIDTo64(steamid32)

            if IsValid(admin) then
                steamid64_admin = admin:SteamID64()
            end

            if steamid64 and steamid64_admin then
                if steamid64_admin == "0" then
                    VyHub.Ban:unban(steamid64, steamid64_admin)
                else
                    if IsValid(admin) then
                        VyHub.Ban:unban(steamid64, steamid64_admin)
                    else
                        VyHub:msg("Tried to unban " .. steamid64 .. " from invalid player.", "error")
                    end
                end
            end

            VyHub.Ban.servergaurd_unban(self, steamid32, admin)
        end

        concommand.Add("serverguard_addmban", function(ply, _, args)
            if (serverguard.player:HasPermission(ply, "Ban")) then
                local steamid32 	= string.Trim(args[1]) 
                local steamid64 	= util.SteamIDTo64(steamid32)
                local length 		= tonumber(args[2]);
                local reason 		= table.concat(args, " ", 4) or ""
                local steamid64_admin 	= ply:SteamID64()

                VyHub.Ban:create(steamid64, length, reason, steamid64_admin)
            end
        end)

        concommand.Add("serverguard_unban", function(ply, _, args)
            if (util.IsConsole(ply)) then
                local steamID = args[1]

                if (serverguard.banTable[steamID]) then
                    serverguard.Notify(nil, SERVERGUARD.NOTIFY.GREEN, "Console", SERVERGUARD.NOTIFY.WHITE, " has unbanned ", SERVERGUARD.NOTIFY.RED, serverguard.banTable[steamID].player, SERVERGUARD.NOTIFY.WHITE, ".")
                end	

                serverguard:UnbanPlayer(steamID)
            else
                if (serverguard.player:HasPermission(ply, "Unban")) then
                    local steamID = args[1]
                    
                    if (serverguard.banTable[steamID]) then
                        serverguard.Notify(nil, SERVERGUARD.NOTIFY.GREEN, serverguard.player:GetName(ply), SERVERGUARD.NOTIFY.WHITE, " has unbanned ", SERVERGUARD.NOTIFY.RED, serverguard.banTable[steamID].player, SERVERGUARD.NOTIFY.WHITE, ".")
                    end
                        
                    serverguard:UnbanPlayer(steamID, ply)
                end
            end
        end)

        local command = {}

        command.help				= "Unban a player."
        command.command 			= "unban"
        command.arguments 			= {"steamid"}
        command.permissions 		= {"Unban"}

        function command:Execute(player, silent, arguments)
            local steamID = arguments[1]
            
            if (serverguard.banTable[steamID]) then
                if (!silent) then
                    serverguard.Notify(nil, SGPF("command_unban", serverguard.player:GetName(player), serverguard.banTable[steamID].player))
                end
            end

            serverguard:UnbanPlayer(steamID, player)
        end

        serverguard.command:Add(command)
    end

    if xAdmin and not xAdmin.Admin.RegisterBan then
        -- xAdmin 1

        function xAdmin.RegisterNewBan(ply, admin, reason, length)
            local steamid64 = nil
            if isstring(ply) then steamid64 = util.SteamIDTo64(ply) elseif IsValid(ply) then steamid64 = ply:SteamID64() end

            local admin = player.GetBySteamID(admin)

            if IsValid(admin) then
                VyHub.Ban:create(steamid64, length, reason, admin:SteamID64())
            else
                VyHub.Ban:create(steamid64, length, reason)
            end
        end

        VyHub.Ban.xadmin_removeban = VyHub.Ban.xadmin_removeban or xAdmin.RemoveBan

        function xAdmin.RemoveBan(steamid64)
            VyHub.Ban:unban(steamid64)

            VyHub.Ban.xadmin_removeban(steamid64)
        end
    elseif xAdmin and xAdmin.Admin.RegisterBan then	
        -- xAdmin 2
        function xAdmin.Admin.RegisterBan(ply, admin, reason, length)
            local steamid64 = nil
            if isstring(ply) then steamid64 = util.SteamIDTo64(ply) elseif IsValid(ply) then steamid64 = ply:SteamID64() end

            if IsValid(admin) and admin:EntIndex() != 0 then
                VyHub.Ban:create(steamid64, length, reason, admin:SteamID64())
            else
                VyHub.Ban:create(steamid64, length, reason)
            end
        end

        VyHub.Ban.xadmin_removeban = VyHub.Ban.xadmin_removeban or xAdmin.Admin.RemoveBan

        function xAdmin.Admin.RemoveBan(steamid64)
            VyHub.Ban:unban(steamid64)

            VyHub.Ban.xadmin_removeban(steamid64)
        end

        if VyHub.Config.replace_xadmin2_bans then
            function VyHub.Ban:replace_xadmin2_bans()
                xAdmin.Admin.Bans = {}

                for steamid, bans in pairs(VyHub.bans) do
                    if ban != nil then
                        for _, ban in pairs(bans) do
                            if ban != nil then
                                admin_steamid = nil 

                                if ban.creator != nil and ban.creator.type == "STEAM" then
                                    admin_steamid = ban.creator.identifier
                                end

                                xAdmin.Admin.Bans[tostring(steamid)] = {
                                    SteamID = tostring(steamid),
                                    Admin = tostring(admin_steamid),
                                    Reason = ban.reasion,
                                    StartTime = VyHub.Util:iso_to_unix_timestamp(ban.created_on),
                                    Length = ban.length,
                                }
                            end
                        end
                    end
                end

                for _, ply in ipairs(player.GetHumans()) do
                    if ply:xAdminHasPermission("ban") then
                        xAdmin.Admin.UpdateAllBans(ply)
                    end
                end
            end

        
            function xAdmin.Admin.ModifyBan(admin, ply, reason, length)
                if not VyHub.Util:is_server(admin) then
                    VyHub.Util:print_chat(ply, "Operation not supported.")
                    VyHub:get_frontend_url(function (frontend_url)
                        if frontend_url != nil then
                            ply:vh_open_url(frontend_url .. "/bans")
                        end
                    end)
                else
                    VyHub:msg("Operation not supported.", "error")
                end
            end
        end
    end

    if FAdmin and FAdmin.Commands and FAdmin.Commands.AddCommand then
        if FAdmin.GlobalSetting.FAdmin then
            hook.Add("FAdmin_UnBan", "vyhub_FAdmin_UnBan", function(ply, steamid32)
                local steamid64 = util.SteamIDTo64(steamid32)

                local steamid64_admin = ""

                if IsValid(ply) then
                    steamid64_admin = ply:SteamID64()
                end

                if steamid64 then
                    VyHub.Ban:unban(steamid64, steamid64_admin)
                end
            end)

            local StartBannedUsers = {} 
            hook.Add("PlayerAuthed", "FAdmin_LeavingBeforeBan", function(ply, SteamID, ...)
                if table.HasValue(StartBannedUsers, SteamID) then
                    game.ConsoleCommand(string.format("kickid %s %s\n", ply:UserID(), "Getting banned"))
                end
            end)

            FAdmin.Commands.AddCommand("ban", function(ply, cmd, args)
                if not args[2] then return false end
                --start cancel update execute

                local targets = FAdmin.FindPlayer(args[1])

                if not targets and string.find(args[1], "STEAM_") ~= 1 and string.find(args[2], "STEAM_") ~= 1 then
                    FAdmin.Messages.SendMessage(ply, 1, "Player not found")
                    return false
                elseif not targets and (string.find(args[1], "STEAM_") == 1 or string.find(args[2], "STEAM_") == 1) then
                    targets = {(args[1] ~= "execute" and args[1]) or args[2]}
                    if args[1] == "STEAM_0" then
                        targets[1] = table.concat(args, "", 1, 5)
                        args[1] = targets[1]
                        args[2] = args[6]
                        args[3] = args[7]
                        for i = 2, #args do
                            if i >= 4 then args[i] = nil end
                        end
                    end
                end

                local CanBan = hook.Call("FAdmin_CanBan", nil, ply, targets)

                if CanBan == false then return false end

                local stage = string.lower(args[2])
                local stages = {"start", "cancel", "update", "execute"}
                local Reason = (not table.HasValue(stages, stage) and table.concat(args, ' ', 3)) or table.concat(args, ' ', 4) or ply.FAdminKickReason

                for _, target in pairs(targets) do
                    if (type(target) == "string" and not FAdmin.Access.PlayerHasPrivilege(ply, "Ban")) or
                    not FAdmin.Access.PlayerHasPrivilege(ply, "Ban", target) then
                        FAdmin.Messages.SendMessage(ply, 5, "No access!")
                        return false
                    end
                    if stage == "start" and type(target) ~= "string" and IsValid(target) then
                        SendUserMessage("FAdmin_ban_start", target) -- Tell him he's getting banned
                        target:Lock() -- Make sure he can't remove the hook clientside and keep minging.
                        target:KillSilent()
                        table.insert(StartBannedUsers, target:SteamID())

                    elseif stage == "cancel" then
                        if type(target) ~= "string" and IsValid(target) then
                            SendUserMessage("FAdmin_ban_cancel", target) -- No I changed my mind, you can stay
                            target:UnLock()
                            target:Spawn()
                            for k,v in pairs(StartBannedUsers) do
                                if v == target:SteamID() then
                                    table.remove(StartBannedUsers, k)
                                end
                            end
                        else -- If he left and you want to cancel
                            for k,v in pairs(StartBannedUsers) do
                                if v == args[1] then
                                    table.remove(StartBannedUsers, k)
                                end
                            end
                        end
                    elseif stage == "update" then -- Update reason text
                        if not args[4] or type(target) == "string" or not IsValid(target) then return false end
                        ply.FAdminKickReason = args[4]
                        umsg.Start("FAdmin_ban_update", target)
                            umsg.Long(tonumber(args[3]))
                            umsg.String(tostring(args[4]))
                        umsg.End()
                    else
                        local time = tonumber(args[2]) or 0
                        Reason = (Reason ~= "" and Reason) or args[3] or ""

                        if stage == "execute" then
                            time = tonumber(args[3]) or 60 --Default to one hour, not permanent.
                            Reason = args[4]  or ""
                        end

                        local TimeText = FAdmin.PlayerActions.ConvertBanTime(time)

                        if type(target) ~= "string" and  IsValid(target) then
                            for k,v in pairs(StartBannedUsers) do
                                if v == target:SteamID() then
                                    table.remove(StartBannedUsers, k)
                                    break
                                end
                            end
                            local nick = ply.Nick and ply:Nick() or "console"

                            VyHub.Ban:create(target:SteamID64(), time, Reason, ply:SteamID64() or nil)
                        else
                            for k,v in pairs(StartBannedUsers) do
                                if v == args[1] then
                                    table.remove(StartBannedUsers, k)
                                    break
                                end
                            end

                            local steamid64 = util.SteamIDTo64(target)

                            VyHub.Ban:create(steamid64, time, Reason, ply:SteamID64() or nil)
                        end
                        ply.FAdminKickReason = nil
                    end
                end

                return true, targets, stage, Reason
            end)
        end
    end

    if sam then
        function sam.player.ban(ply, length, reason, admin_steamid)
            local steamid64 = ply:SteamID64()

            if not sam.isstring(reason) then
                reason = DEFAULT_REASON
            end

            local admin = nil

            if sam.is_steamid(admin_steamid) then
                admin = player.GetBySteamID(admin_steamid)
            end

            if IsValid(admin) then
                VyHub.Ban:create(steamid64, length, reason, admin:SteamID64())
            else
                VyHub.Ban:create(steamid64, length, reason)
            end
        end

        function sam.player.ban_id(steamid, length, reason, admin_steamid)
            local steamid64 = util.SteamIDTo64(steamid)

            if not sam.isstring(reason) then
                reason = DEFAULT_REASON
            end

            local admin = nil

            if sam.is_steamid(admin_steamid) then
                admin = player.GetBySteamID(admin_steamid)
            end

            if IsValid(admin) then
                VyHub.Ban:create(steamid64, length, reason, admin:SteamID64())
            else
                VyHub.Ban:create(steamid64, length, reason)
            end
        end

        VyHub.Ban.sam_unban = VyHub.Ban.sam_unban or sam.player.unban

        function sam.player.unban(steamid, admin_steamid)
            local steamid64 = util.SteamIDTo64(steamid)
            
            local admin = nil

            if sam.is_steamid(admin_steamid) then
                admin = player.GetBySteamID(admin_steamid)
            end

            if IsValid(admin) then
                VyHub.Ban:unban(steamid64, admin:SteamID64())
            else
                VyHub.Ban:unban(steamid64)
            end

            VyHub.Ban.sam_unban(steamid, admin_steamid)
        end
    end

    if not ULib and not evolve and not serverguard and not xAdmin and not sam then
        -- GExtension:RegisterChatCommand("!ban", function(ply, args)
        --     if not args[1] or not args[2] or not args[3] then return end

        --     local reason = GExtension:ConcatArgs(args, 3)

        --     local target = GExtension:GetPlayerByNick(args[1])

        --     if IsValid(target) and isnumber(args[2]) then
        --         if ply:GE_CanBan(target:SteamID64(), args[2]) then
        --             target:GE_Ban(length, reason, ply:SteamID64())
        --         end
        --     end
        -- end)
    end

    hook.Add("vyhub_bans_refreshed", "vyhub_ban_vyhub_bans_refreshed", function()
        VyHub.Ban:kick_banned_players()

        if VyHub.Config.replace_ulib_bans then
            if VyHub.Ban.replace_ulib_bans then
                VyHub.Ban:replace_ulib_bans()
            end
        end

        if VyHub.Config.replace_xadmin2_bans then
            if VyHub.Ban.replace_xadmin2_bans then
                VyHub.Ban:replace_xadmin2_bans()
            end
        end
    end)

    concommand.Add("vh_ban", function(ply, _, args)
        if not args[1] or not args[2] or not args[3] then return end
        
        if VyHub.Util:is_server(ply) then
            VyHub.Ban:create(args[1], args[2], args[3])
        end
    end)

    concommand.Add("vh_unban", function(ply, _, args)
        if not args[1] then return end
        
        if VyHub.Util:is_server(ply) then
            VyHub.Ban:unban(args[1])
        end
    end)
end)