VyHub.Util = VyHub.Util or {}
VyHub.Util.chat_commands = VyHub.Util.chat_commands or {}

if SERVER then
	util.AddNetworkString("vyhub_run_lua")
end

function VyHub.Util:format_datetime(unix_timestamp)
    unix_timestamp = unix_timestamp or os.time()

    local tz_wrong = os.date("%z", unix_timestamp)
    local timezone = string.format("%s:%s", string.sub(tz_wrong, 1, 3), string.sub(tz_wrong, 4, 5))

    return os.date("%Y-%m-%dT%H:%M:%S" .. timezone, unix_timestamp)
end

function VyHub.Util:is_server(obj)
	if type(obj) == "Entity" and (obj.EntIndex and obj:EntIndex() == 0) and !IsValid(obj) then
		return true
	else
		return false
	end
end

function VyHub.Util:iso_to_unix_timestamp(datetime)
	if datetime == nil then return nil end

	local pd = date(datetime)

	if pd == nil then return nil end

	local time = os.time(
		{
			year = pd:getyear(),
			month = pd:getmonth(),
			day = pd:getday(),
			hour = pd:gethours(),
			minute = pd:getminutes(),
			second = pd:getseconds(),
		}
	)

	return time
end

function VyHub.Util:get_ply_by_nick(nick)
	nick = string.lower(nick);
	
	for _,v in ipairs(player.GetHumans()) do
		if(string.find(string.lower(v:Name()), nick, 1, true) != nil)
			then return v;
		end
	end
end

function VyHub.Util:register_chat_command(strCommand, Func)
	if !strCommand || !Func then return end
	
	for k, v in pairs( VyHub.Util.chat_commands ) do
		if( strCommand == k ) then
			return
		end
	end
	
	VyHub.Util.chat_commands[ tostring( strCommand ) ] = Func;
end

function VyHub.Util:concat_args(args, pos)
	local toconcat = {}

	if pos > 1 then
		for i = pos, #args, 1 do
			toconcat[#toconcat+1] = args[i]
		end
	end

	return string.Implode(" ", toconcat)
end


if SERVER then
	hook.Add("PlayerSay", "vyhub_util_PlayerSay", function(ply, message)
		if VyHub.ready then
			local chat_string = string.Explode(" ", message)
			local ret = nil
		
			for k, v in pairs( VyHub.Util.chat_commands ) do
				if( string.lower(chat_string[1]) == string.lower(k) ) then
					table.remove(chat_string, 1)
					ret = v(ply, chat_string)
					break
				end
			end
		
			if ret != nil then
				return ret
			end
		end	
	end)
end

function VyHub.Util:replace_colors(message)
	message = string.Replace(message, '"', '')
	message = string.Replace(message, '<red>', '", Color(255, 24, 35), "')
	message = string.Replace(message, '</red>', '", Color(255, 255, 255), "')
	message = string.Replace(message, '<green>', '", Color(45, 170, 0), "')
	message = string.Replace(message, '</green>', '", Color(255, 255, 255), "')
	message = string.Replace(message, '<blue>', '", Color(0, 115, 204), "')
	message = string.Replace(message, '</blue>', '", Color(255, 255, 255), "')
	message = string.Replace(message, '<yellow>', '", Color(229, 221, 0), "')
	message = string.Replace(message, '</yellow>', '", Color(255, 255, 255), "')
	message = string.Replace(message, '<pink>', '", Color(229, 0, 218), "')
	message = string.Replace(message, '</pink>', '", Color(255, 255, 255), "')

	return message
end

function VyHub.Util:print_chat(ply, message, tag, color)
	if SERVER then
		if IsValid(ply) then
			if not VyHub.Config.chat_tag then
				VyHub.Config.chat_tag = "VyHub"
			end

			if not tag then
				tag = [[Color(0, 187, 255), "[]] .. VyHub.Config.chat_tag .. [[] ", ]]
			end

			if not color then
				color = [[255, 255, 255]]
			end

			message = string.Replace(message, '"', '')
			message = string.Replace(message, '\r', '')
			message = string.Replace(message, '\n', '')

			message = VyHub.Util:replace_colors(message)

			local tosend = [[chat.AddText(]] .. tag .. [[Color(]] .. color .. [[), "]] .. message .. [[" )]]

			net.Start("vyhub_run_lua")
				net.WriteString(tosend)
			net.Send(ply)
		end
	end
end

function VyHub.Util:print_chat_steamid(steamid, message, tag, color)
	if steamid != nil and steamid != false then
		ply = player.GetBySteamID64(steamid)
	
		if IsValid(ply) then
			VyHub.Util:print_chat(ply,  message, tag, color)
		end
	end
end

function VyHub.Util:play_sound_steamid(steamid, url)
	if steamid != nil and steamid != false then
		ply = player.GetBySteamID64(steamid)
	
		if IsValid(ply) then
			net.Start("vyhub_run_lua")
				net.WriteString([[sound.PlayURL ( "]] .. url .. [[", "", function() end)]])
			net.Send(ply)
		end
	end
end


function VyHub.Util:print_chat_all(message, tag, color)
	for _, ply in pairs(player.GetHumans()) do
		VyHub.Util:print_chat(ply, message, tag, color)
	end
end


function VyHub.Util:get_player_by_nick(nick)
	nick = string.lower(nick);
	
	for _,v in ipairs(player.GetHumans()) do
		if(string.find(string.lower(v:Name()), nick, 1, true) != nil)
			then return v;
		end
	end
end


function VyHub.Util:hex2rgb(hex)
    hex = hex:gsub("#","")
    if(string.len(hex) == 3) then
        return Color(tonumber("0x"..hex:sub(1,1)) * 17, tonumber("0x"..hex:sub(2,2)) * 17, tonumber("0x"..hex:sub(3,3)) * 17)
    elseif(string.len(hex) == 6) then
        return Color(tonumber("0x"..hex:sub(1,2)), tonumber("0x"..hex:sub(3,4)), tonumber("0x"..hex:sub(5,6)))
    else
    	return Color(255,255,255)
    end
end

function VyHub.Util:iso_ts_to_local_str(iso_ts)
	local bias = VyHub.Config.time_offset != nil and -math.Round(VyHub.Config.time_offset * 60 * 60) or nil

	return date(iso_ts):setbias(bias):tolocal():fmt(VyHub.Config.date_format)
end
