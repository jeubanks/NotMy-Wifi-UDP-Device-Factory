--
-- WiFi UDP Switch Controller (formerly ECO Switch)
-- Version 2.0
-- Plugin for   ECO Wifi Controlled Outlet,
--              TP-LINK Wi-Fi Smart Plug and bulbs, and
--              SENGLED Boost bulb/extenders
-- by CYBRMAGE, Modified by Jim McGhee
-- Copyright (C) 2009-2017
--
-- Derived from:
-- Plugin for Belkin WeMo
-- Copyright (C) 2009-2011 Deborah Pickett

-- This program is free software; you can redistribute it and/or
-- modify it under the terms of the GNU General Public License
-- as published by the Free Software Foundation; either version 2
-- of the License, or (at your option) any later version.

-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.

-- You should have received a copy of the GNU General Public License
-- along with this program; if not, write to the Free Software
-- Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
--

local version = "v2.0"
local PLUGIN = {
	VERA_IP = "",
	NAME = "WIFI_Switch_and_Light",
	MIOS_VERSION == "",
	OPENLUUP = false,
	OPENLUUP_ICONFIX = false,
	PollPeriod = 60
}

local function BitXOR(a,b)--Bitwise xor
    local p,c=1,0
    while a>0 and b>0 do
        local ra,rb=a%2,b%2
        if ra~=rb then c=c+p end
        a,b,p=(a-ra)/2,(b-rb)/2,p*2
    end
    if a<b then a=b end
    while a>0 do
        local ra=a%2
        if ra>0 then c=c+p end
        a,p=(a-ra)/2,p*2
    end
    return c
end


ipAddr = ""
ipPort = 80
lug_device = 0
switchID = ""
retryCount = 1

local socket = require("socket")
local http = require("socket.http")

local ECO_GATEWAY_DEVICE

local CONFIGURED_DEVICES = {}
local DISCOVERED_DEVICES = {} 

local ECO_SID = "urn:micasaverde-com:serviceId:ECO_Switch1"
local SWITCH_SID = "urn:upnp-org:serviceId:SwitchPower1"
local DIMMER_SID = "urn:upnp-org:serviceId:Dimming1"
local COLOR_SID = "urn:micasaverde-com:serviceId:Color1"

local BINARY_LIGHT_DEVICE = "D_BinaryLight1.xml"
local DIMMABLE_LIGHT_DEVICE = 'D_DimmableLight1.xml'
local RGB_LIGHT_DEVICE = 'D_DimmableRGBLight1.xml'


log = luup.log
-- debug = luup.log

local isDebug = true

function bool2string(b)
	return b and "true" or "false"
end 

function toBool(s)
--	luup.log(" McGhee toBool:"..(bool2string(tonumber(s, 10) ~= 0))..".")
	return (tonumber(s, 10) ~= 0)
end

function debug(s)
	if (isDebug) then
		luup.log(s)
	end
end

function URLEnclode(s)
	return string.gsub(s, "%A", function(c) return string.format("%%%02X", string.byte(c)) end)
end

function shellExecute(cmd, Output)
	if (Output == nil) then Output = true end
	local file = assert(io.popen(cmd, 'r'))
	if (Output == true) then
		local cOutput = file:read('*all')
		file:close()
		return cOutput
	else
		file:close()
		return
	end
end

function print_r(arr, level)
	if (level == nil) then
		level = 0
	end
	if (arr == nil) then
		return ""
	end
	local str = ""
	local indentStr = string.rep("  ",level)
	if (type(arr) == "table") then
		for index,value in pairs(arr) do
			if type(value) == "table" then
				str = str..indentStr..index..": [\n"..print_r(value, level + 1)..indentStr.."]\n"
			elseif type(value) == "boolean" then
				str = str..indentStr..index..": "..(value and "TRUE" or "FALSE").."\n"
			elseif type(value) == "function" then
				str = str..indentStr..index..": FUNCTION("..print_r(value, level + 1)..")\n"
			else
				if ((not tonumber(index,10)) and (index:find("updated_at") or index:find("changed_at"))) then
					str = str..indentStr..index..": ".."("..value..") = "..unixTimeToDateString(value).."\n"
				else
					str = str..indentStr..index..": "..value.."\n"
				end
			end
		end
	elseif ((type(arr) == "string") or (type(arr) == "number")) then
		str = arr
	elseif (type(arr) == "boolean") then
		str = (arr and "TRUE" or "FALSE")
	end
	return str
end

local json = {
	encode =function (self,arr)
		if (arr == nil) then
			return ""
		end
		local str = ""
		if (type(arr) == "table") then
			for index,value in pairs(arr) do
	--			if type(index) == "string" then
					str = str.."\""..index.."\": "
	--			else
	--				str = str..index..": "
	--			end
				if type(value) == "table" then
--				if (#value > 1) then
--					str = str.."["..self:encode(value).."],"
--				else
						str = str..self:encode(value)..","
--				end
				elseif type(value) == "boolean" then
					str = str..(value and "true" or "false")
				elseif type(value) == "number" then
					str = str..value
				else
					str = str.."\""..value.."\""
				end
				str = str..","
			end
		elseif (type(arr) == "number") then
			str = arr
		elseif ((type(arr) == "string") or (type(arr) == "number")) then
			str = "\""..arr.."\""
		elseif (type(arr) == "boolean") then
			str = (arr and "TRUE" or "FALSE")
		end
--		return ("{"..str.."}"):gsub(",,",","):gsub(",]","]"):gsub(",}","}"):gsub("{{","[{"):gsub("}}","}]")
		return ("{"..str.."}"):gsub(",,",","):gsub(",]","]"):gsub(",}","}")
	end,

	decode = function(self,json)
		if (not json) then 
			return nil
		end
		local str = {} 
		local escapes = { r='\r', n='\n', b='\b', f='\f', t='\t', Q='"', ['\\'] = '\\', ['/']='/' } 
		json = json:gsub('([^\\])\\"', '%1\\Q'):gsub('"(.-)"', function(s) 
			str[#str+1] = s:gsub("\\(.)", function(c) return escapes[c] end) 
			return "$"..#str 
		end):gsub("%s", ""):gsub("%[","{"):gsub("%]","}"):gsub("null", "nil") 
		json = json:gsub("(%$%d+):", "[%1]="):gsub("%$(%d+)", function(s) 
			return ("%q"):format(str[tonumber(s)])
		end)
		return assert(loadstring("return "..json))()
	end
}

function set_failure(value,device)
	if (PLUGIN.MIOS_VERSION == "UI7") then
		luup.set_failure(value,device)
	end
end

function table.contains (t, item)
	for k, v in pairs(t) do
		if ((v.ID == item.ID) and (v.MAC == item.MAC)) then
			return true, k
		end
	end
	return false
end

function table.insertSet(t, item)
	if (not table.contains(t, item)) then
		t[#t + 1] = item
		return true
	end
	return false
end

function getMiosVersion()
	local mios_branch = luup.version_branch
	local mios_major = luup.version_major
	local mios_minor = luup.version_minor
	local vera_model = luup.attr_get("model",0)
	debug("("..PLUGIN.NAME.."::getMiosVersion): vera_model ["..(vera_model or "NIL").."] mios_branch ["..(mios_branch or "NIL").."] mios_major ["..(mios_major or "NIL").."] mios_minor ["..(mios_minor or "NIL").."].",2)
	if (tonumber(mios_branch,10) == 1) then
		if (tonumber(mios_major,10) == 5) then
			PLUGIN.MIOS_VERSION = "UI5"
		elseif (tonumber(mios_major,10) == 7) then
			PLUGIN.MIOS_VERSION = "UI7"
		else
			PLUGIN.MIOS_VERSION = "unknown"
		end
	else
		PLUGIN.MIOS_VERSION = "unknown"
	end

	if ((file_exists("/mios/usr/bin/cmh_Reset.sh") == false) and (file_exists("/etc/cmh-ludl/openLuup/init.lua") == true)) then 
		log("("..PLUGIN.NAME.."::getMiosVersion): PLUGIN is running under openluup.",2)
		PLUGIN.OPENLUUP = true 
		-- verify the openluup.io version and enable LIP if newer that 2016.01.26
		INITversion = self:shellExecute('head -n 3 /etc/cmh-ludl/openLuup/init.lua |grep -e "revisionDate ="')
		_,_,init_year,init_month,init_day = INITversion:find("(%d+)\.(%d+)\.(%d+)")
		init_datestamp = (init_year * 372) + ((init_month-1) * 31) + init_day
		if (init_datestamp > 750007) then
			log("("..PLUGIN.NAME.."::getMiosVersion): OpenLuup v7 Icon fix enabled.",2)
			PLUGIN.OPENLUUP_ICONFIX = true
		end
	end
	log("("..PLUGIN.NAME.."::getMiosVersion): MIOS_VERSION ["..(PLUGIN.MIOS_VERSION or "NIL").."].",2)
end

function file_exists(filename)
		local file = io.open(filename)
		if (file) then
			io.close(file)
			return true
		else
			return false
		end
end

local ICONS = {
	ICON_LIST = {
		["ECO_Switch.png"] = "89504E470D0A1A0A0000000D494844520000003C0000003C08060000003AFCD972000000017352474200AECE1CE90000000467414D410000B18F0BFC61050000000970485973000006EB000006EB014C319E4A0000001A74455874536F667477617265005061696E742E4E45542076332E352E313030F472A1000009EB494441546843E59B7B5054D71DC7136B133126C507FA8733A25327157CBF581F7F88C1DAFCA1F18169339AB4A95367AA0926C660A0A245C40734538DDA421934658C5A222AEC8E05792DA804545444C18505C10B0222042DBE157EFD7DEF7AD9BBCBD975C10536C99DF98C77CEF9FDBE7BBE7BCE3DF71C3CFB1211FDA41016FE9831DFB4BF5E665E658633CB9904E614D3C420C115B8C3E43149CCE7CC18C68D41DB2DAEE719EECD8C60D633D5CC830103063C1E366C18B92203070E7CC46DBCC7FC8FD9CD7833AF306D973DC37D183FE638D33C64C890268D465370ECD8B14A4992C815D1E974C69933679EE2B6D6709B615CCF2C60FA31F265CB307A16668D83060D7A3A67CE9CAAB8B8B812D187B822F1F1F10573E7CE2DF3F0F078C81E6A99A50C3A506818E31EC3F838CC6EDAB4E9A148B4A7484949B979E448420DC0BD284661DBB66D8D6CFA3E7B2960A630BD44863141E1996D46CF8A84BA9BF4F4F45B07F6473DD0A7FC9D360779194256F72B04B84719EA1023CA0D0D0D7DC2F34E2BFBD9CF0C1419FE1553CDCF41832B0C639D36E1696890AFB43BCCFD6ED67FDCE8FAE9DE74A7B0970CEE5186BAD0A0D9929663451A93264DC2B0BECBCC17190E60EE4F9F3EFDAC28B93B39AEFBB675E796194F4E1DEED372F7CACBD45AF69210D4216607C722C75A273636B6D6DDDDFD09FB8A13193ECA43E0515252D235EBC4EE44A73DFA6447F8CCC797925FA5C725B6CD2A2006B1C841AEB51E5E5BECAD5464F82A2AAD13BA93AC2C7DCD86403F63C601B71647CC2A2036E340DF9690C03946BD5E5FA3D6F4F4F4C4E4F54064F8414F1B8EFB77CC9D8860F786DB977A098DD90339C885865AF399E1569161B9FBD5C1DD8DEEE88ED6C498BEAD2D0243CF0339C885865A933D61A6668B2E68382FEB4BCAD7BE2234E408C885865A139E5CD2705A5ADA8D4D5F8CBE589AF973A11947402E34A0A5E8BAAC615E4094ADFFF497D945A99DEF61E442035A8AAE730D9F3B47D29933F63118C4B9023279F5A43FD44768C611900B0DB5E68B198681F47433132690F4E69BF6090DB5CC292F176B3387BED9F52436A2DFA38EBC921490835C68A8353B67383797A4C44492962C119BEA087BF79AB474BA769FA3D5263545FE7552BD51DFF1E71839911B27D54343ADD931C3E8D1FDFB49FAF043CB46BFF71E492B56740C8DC65263DC389212122C3F8F89DBF7B7A6E8AD6F34359C77FC5D8C58E420D75ACF71C330BB6A95B981FEFE24AD596302CFAE4AD42176EC30E78F1E6DD29C3A95A483072DE2323333AB3E0B987BF970D46BCD771C588020E6F03F5F6B460E72D55AC071C3D9D9242D5B46D28205246DDC48526AAA8590CCCE9D244546DA47AF6F9F171E6ED204BB76B5AB4F4E4EBE19B87A56DDD9C43E4F5B8C62A3007588412C72AC7580E386011A6BFDAC45479B1B3B668C7904D8025F9A127FE182A5961D4242822B0E47BDDE78BFD8F60486BA048E41AC480374CCB09A7DFB4CC371C60CB1314758BEDCA4515A2AFE0C15DBB76FCFFD64C5C8CA237B2753FAB7D385A00E3188156980CE19FEFA6B9266CDB26CFCEEDDA609CD11162EB4CCC52428FA1C15E1E1E127D77CBAB25C97F40D65EB9384A00E3188156980CE19C6704443C3C24CAF1460348A6345603E50F2A64D336989E25444464624FBFB2FBEBA67CF6E3AC8139B08D42106B1220DD039C378F6B068282A6A5F376F9E6D6263DBC7C33CB4ACCBADD8BC394CBF6E5DA03123239DF2F3F385A00E3188156980CE19B606431243DC7A985B3379B2392E3959AC650383C1F0202464FDC32D5BB6B4EEE5C5CA3E9E43D4A00C758841AC4803BC98E1800093092F2FB1417B8C1F6FCAEDC03BDCC88FCD575FEDC49F68292F2FCF0294A10E31A25C05E71856282E16C7A9090EB6CCE9E0A2253838483B66CC68ADB7B7D7093528439D2847CD8B1916515969DE1959E3C817D2C538CFB032F968B5E2210CD6ADB33DD97513CE33FCBC094B0D5E673D64DAF986453B23053F3F530C161E1811229D2EC67986B1B1C7325154A7C08B0339C681F76E57E13CC30A6565E25D926083DF1338DF705090E5F3AA806DE50B988E8989A1952B573A0462451AC0F986456615D0D3A21C3BECE7CDC6D2A54B69E4C891B4ECFDDFD3F6C82FEDB2ECFD0FE458E420D75ACFF986D5BB226B7272C43936C08660D4A851B468B13F45C7C4D299FC8B24DDA8B30B62108B1CE44243ADE97CC34E84F7B5F4CE8285947B269FAE57D752495905155E31D0A5CBC574A5B894CA2AABA892CB8B4BCAA980CB2E5DB9CAF765547EBD9A72F2CED2FCF9EFC81A6ACDAE337CFAB4799764F5A18E809E193A7428ADFCE863BACE3D078A0C467AF7B7BF232F2F6F4AD79FA4D26BD7E5F2EFF80B19C565FE4BDEA573170AC9C05F0CBE08E44243DDCB5D6398B76A167F0979DEEB4A405454142D5CB4982E5F2D69338C1EF4D14C931B9C9C9AD166F8D47767E4B271E327506A4616159796CBBD7CB9D8400B162E92B514DDAE318C75B37AB2C25F25F1873A51AC0DD0484C5252CDCD36C3056C78AA8F466EF089743D192B24B9FC74EE59B96CECB8F194929641453CAC31DC910B8DAE378C1D90F2BF10DEDEA61D9228CE0E68E4529E7115B3687C51899134D34C3D9CA6CFA66BDC8B35371B78A2BA20974D983891B24FE7CA5F047A1879D0E87AC3004B472C370303C5F5CF4164B8BC52A2C53CFB0E1F3E5C365621DDA0EADA7A3A7FB1502E5BECBF84CAD82CBE0825AFFB0CBF2068E4B20FCC431AFFD6D537D2ADC6DB32300A63989CEA6E7D4F0DDF9BCA6BEB1BE43225A72343FA514F1BF69BF36B9E90F2DA7A4B36C154B1114C58E70BAE3097E57B98936ACC7100B9D0501BF6F4F4C4394CA1E18A9E349C98984863C78EB5782D2966D183C753D268EDE75FC824F34455595D4355B56CFA592C402E34A0A5E8F2D0C789DB4722C3FA9E340CB068F0F59D4D27D232E51E845918A9A8AAA17F44FD8BDCDCDCC8AD6F5F8AE29515CA508718C426A7A6D32C5F5F5B0B8F6A91E1487777F7A7D1D1D18DEA84EE44ABD5D2349E9567BFE5477F09D940FA53BC34E5618B1ECEE2FBCFD606720F07D2C99C5CB90CBDAB3F9943C1EB37D0ECD96FC9B9D050F4E2E3E38BFAF7EF8F83A63A91E199CCBD891327F6986190949444C1FC5A9BC0AFB9DFBCFD36ADFA2840E6E380D514B0FA1319DCAFE2E18B72C4201639C8556BF9F8F814B12718FE93C8F0EBCC211CC8C4C14C75624F909090200F4F4740AC75FED6AD5BEFB0171C3BCC6186890CF7627C98020F0F8F7B111111F5D6223F14F6ECD963183C78701D7B01F398DE22C3B87098FA8F4C139B6E0E0B0B73A933D38EC03DDEC86671321EA76843983718B34F2BC33824DE9FF93353C943A265CA9429D77863DDA3074E1D818775A146A329E4363FE6B6E3D8F026662823FFE0C396615C08C02F437C99FF32F779F6967FE0C1EFB4467E913FC4BD2B80739423468CA8C3FDB3D918E099C530FE05D3F6EB167B8695EB67CC10E60F4C2A739BC1B945F9ECA28B80B6B430CDCC49662D3392C16F372CAE76867F2A080B7FBCD04BFF07642E6F70139BBE680000000049454E44AE426082",
	},
	decode_hex_string = function(self,hexStr)
		if (not hexStr) then
			luup.log("("..PLUGIN.NAME.."::ICONS::decode_hex_string) No hex data supplied.",1)
			return nil
		end
		if (math.floor(#hexStr/2) ~= (#hexStr/2)) then
			luup.log("("..PLUGIN.NAME.."::ICONS::decode_hex_string) Invalid hex data supplied.",1)
			return nil
		end
		debug("("..PLUGIN.NAME.."::ICONS::decode_hex_string) input size ["..(#hexStr or "NIL").."].",2)
	  local i = 1
	  local hexStr_len = hexStr:len()
	  local VALUE = ""
	  while i <= hexStr_len do
	     local c = hexStr:sub(i,i+1)
	     VALUE = VALUE .. string.char(tonumber(c,16))
	     i = i + 2
	  end
		debug("("..PLUGIN.NAME.."::ICONS::decode_hex_string) output size ["..(#VALUE or "NIL").."].",2)
	  return VALUE
	end,
	create_png = function(self,filename,data)
		-- data = hex encoded png file contents
		local png_data = self:decode_hex_string(data)
		if (png_data and (#png_data == (#data/2))) then
			debug("("..PLUGIN.NAME.."::ICONS::create_png): writing PNG Data for file ["..(filename or "NIL").."]",2)
			local file = io.open(filename,"wb")
			if (file) then
				file:write(png_data)
				file:close()
				return true
			else
				return false
			end
		else
			luup.log("("..PLUGIN.NAME.."::ICONS::create_png): PNG Data DECODE ERROR",1)
			return false
		end
	end,
	CreateIcons = function(self)
		local fPath = "/www/cmh/skins/default/icons/"										-- UI5 icon file location
		if (PLUGIN.MIOS_VERSION == "UI7") then
			fPath = "/www/cmh/skins/default/img/devices/device_states/"		-- UI7 icon file location
		end
		if (PLUGIN.OPENLUUP and PLUGIN.OPENLUUP_ICONFIX) then
			-- make sure the icons directory exists
			os.execute("mkdir /etc/cmh-ludl/icons")
			fPath = "/etc/cmh-ludl/icons/"
		end
		for fName, fData in pairs(self.ICON_LIST) do
--			if (not file_exists(fPath..fName)) then
				self:create_png(fPath..fName,fData)
--			end
		end
	end
}

function hex_dump(buf)
	if (buf == nil) then return nil end
	local outBuf = "\n"
	for i=1,math.ceil(#buf/16) * 16 do
		if (i-1) % 16 == 0 then 
			outBuf = outBuf .. string.format('%08X  ', i-1) 
		end
		outBuf = outBuf .. ((i > #buf) and '   ' or string.format('%02X ', buf:byte(i)))
		if ((i %  8) == 0) then 
			outBuf = outBuf .. " " 
		end
		if ((i % 16) == 0) then 
			outBuf = outBuf .. buf:sub(i-16+1, i):gsub("%c","."):gsub("%W",".").."\n" 
		end
	end
	return outBuf
end


function getLocalNet()
	local sCmd = ""
	if ((file_exists("/mios/usr/bin/cmh_Reset.sh") == false) and (file_exists("/etc/cmh-ludl/openLuup/init.lua") == true)) then
		sCmd = "head -n2 /proc/net/arp |tail -n1|tr -s [:blank:] ,|cut -d ',' -f1|cut -d '.' -f1-3"
	else
		if ( (tonumber(mios_branch,10) == 1) and (tonumber(mios_major,10) == 5)) then
			sCmd = "ip addr show|grep -e eth0|grep -e eth0:0|cut -d ' ' -f6|cut -d '/' -f1|cut -d '.' -f1-3"
		elseif ( (tonumber(mios_branch,10) == 1) and (tonumber(mios_major,10) == 7)) then
			--sCmd = "ip addr show dev eth0.2|grep -e inet|cut -d ' ' -f6|cut -d '/' -f1|cut -d '.' -f1-3"
			sCmd = "get_unit_info.sh |cut -d';' -f 2|cut -d'.' -f 1-3"
		else
			sCmd = "traceroute www.google.com -m 1|tail -n 1|cut -d ' ' -f4|cut -d '.' -f1-3"
		end
	end
	local LocalNet = shellExecute(sCmd)
	LocalNet = LocalNet:gsub("\n",""):gsub("\r","")
	debug("("..PLUGIN.NAME.."getLocalNet): Found Local Network ["..(LocalNet or "NIL")..".0]")
	-- load the arp table using the ping command
	-- the arp table will flush unneeded entries automatically
	debug("("..PLUGIN.NAME.."getLocalNet): Found network ["..(LocalNet and (LocalNet..".0") or "NIL").."]")
	return LocalNet or nil
end


local TPLINK = {

	commands = {
		['info']					= '"system":{"get_sysinfo":{}}',
		['IOT.SMARTPLUGSWITCH'] = {
			['on']					= '"system":{"set_relay_state":{"state": 1}},"system":{"get_sysinfo":null}',
			['off']					= '"system":{"set_relay_state":{"state": 0}},"system":{"get_sysinfo":null}'
		},
		['IOT.SMARTBULB'] = {
			['on']					= '"smartlife.iot.smartbulb.lightingservice":{"transition_light_state":{"on_off": 1,"transition_period": 0}}',
			['off']					= '"smartlife.iot.smartbulb.lightingservice":{"transition_light_state":{"on_off": 0,"transition_period": 0}}',
			['color_temp']	= '"smartlife.iot.smartbulb.lightingservice":{"transition_light_state":{"hue": 0,"saturation": 0,"color_temp": %s}}',
			['color_hsv']		= '"smartlife.iot.smartbulb.lightingservice":{"transition_light_state":{"color_temp": 0,"hue": %s,"saturation": %s,"brightness": %s}}',
			['hue']					= '"smartlife.iot.smartbulb.lightingservice":{"transition_light_state":{"hue": %s}}',
			['sat']					= '"smartlife.iot.smartbulb.lightingservice":{"transition_light_state":{"saturation": %s}}',
			['brightness']	= '"smartlife.iot.smartbulb.lightingservice":{"transition_light_state":{"brightness": %s}}'
		},
		['reboot']				= '{"system":{"reboot":{"delay":1}}}'
	},

	encodePacket = function(self,packet)
		local key = 171
		local size = #packet
		local decoded = ""
		for i=1,size do
			local c = packet:byte(i)
			key = BitXOR(c,key)
			decoded = decoded .. string.char(key)
		end
		return decoded
	end,

	decodePacket = function(self,packet)
		if (packet == nil) then return nil end
		local key = 171
		local size = #packet
		local result = ""
		for i=1,size do
			a = BitXOR(key,packet:byte(i))
			key = packet:byte(i)
			result = result..string.char(a)
		end
		return result
	end,

	HSVtoRGB = function(self, h, s, v)
	  local cR, cG, cB

	  local f = (h * 6) - math.floor(h * 6)
	  local p,q,t = (v * (1 - s)), (v * (1 - f * s)), (v * (1 - (1 - f) * s))

	  local i = (math.floor(h * 6)) % 6

	  if (i == 0) then 
	  	cR, cG, cB = v, t, p
	  elseif (i == 1) then 
	  	cR, cG, cB = q, v, p
	  elseif (i == 2) then 
	  	cR, cG, cB = p, v, t
	  elseif (i == 3) then 
	  	cR, cG, cB = p, q, v
	  elseif (i == 4) then 
	  	cR, cG, cB = t, p, v
	  elseif (i == 5) then 
	  	cR, cG, cB = v, p, q
	  end

	  return math.floor(cR * 255), math.floor(cG * 255), math.floor(cB * 255)
	end,

	getColorSpec = function(self,colorTemp,hue,sat,bri)
		local C0,C1,C2,C3,C4

		debug(" McGhee beginning getColorSpec: colorTemp="..(colorTemp or 'nil')..", hue="..(hue or 'nil')..", sat="..(sat or 'nil')..", bri="..(bri or 'nil'))
		if (colorTemp > 0) then
			if (colorTemp < 5500) then
				C0 = math.floor(((colorTemp - 2200)/((5500-3000)/256)) + 0.5)
			else
				C1 = math.floor(((colorTemp - 5500)/((9000-5500)/256)) + 0.5)
			end
			-- color temperature
		else
			-- HSB
			C0 = ""
			C1 = ""
			if ((hue ~= nil) and (sat ~= nil) and (bri ~= nil)) then
				C2, C3, C4 = self:HSVtoRGB(hue,sat,bri)
			end
		end
		debug(" McGhee return from getColorSpec: 0="..(C0 or 'nil')..", 1="..(C1 or 'nil')..", 2="..(C2 or 'nil')..", 3="..(C3 or 'nil')..", 4="..(C4 or 'nil'))
		return "0="..(C0 or '')..",1="..(C1 or '')..",2="..(C2 or '')..",3="..(C3 or '')..",4="..(C4 or '')
	end,
	
	parseStatusResponse = function(self,packet)
		local sArray = {}
		local STATUS = json:decode(packet)
		luup.log("("..PLUGIN.NAME.."::TPLINK::parseStatusResponse)    decoded packet [\n"..print_r(STATUS).."\n]")

		for key,data in pairs(STATUS) do
			luup.log("("..PLUGIN.NAME.."::TPLINK::parseStatusResponse)      parsing key ["..(key or "NIL").."]")
			if (key == "system") then
				local sysinfo = data['get_sysinfo']
				luup.log("("..PLUGIN.NAME.."::TPLINK::parseStatusResponse) McGhee sysinfo:[\n"..print_r(sysinfo).."\n]")
				if ((sysinfo['type'] == "IOT.SMARTBULB") or (sysinfo["mic_type"] == "IOT.SMARTBULB")) then
					sArray.isDimmable = toBool(sysinfo["is_dimmable"])
					luup.log(" McGhee isDimmable:"..bool2string(sArray.isDimmable)..".")
					sArray.isTunable = toBool(sysinfo["is_variable_color_temp"])
--					sArray.isTunable = (toBool(sysinfo["is_variable_color_temp"],10) == 1) and true or false
					sArray.isColor = toBool(sysinfo["is_color"])
--					sArray.isColor = (toBool(sysinfo["is_color"],10) == 1) and true or false
					if (not sArray.isDimmable) then
						sArray.powered = toBool(sysinfo["light_state"]["on_off"])
--						sArray.powered = (toBool(sysinfo["light_state"]["on_off"],10) == 1) and true or false
						luup.log(" McGhee is NOT dimmable")
					else
						sArray.powered = toBool(sysinfo["light_state"]["on_off"])
--						sArray.powered = (toBool(sysinfo["light_state"]["on_off"],10) == 1) and true or false
						if (sysinfo["light_state"]["dft_on_state"] == nil) then
							sArray.brightness = tonumber(sysinfo["light_state"]["brightness"],10)
						else
							sArray.brightness = tonumber(sysinfo["light_state"]["dft_on_state"]["brightness"],10)
						end
						luup.log(" McGhee is dimmable, powered:"..bool2string(sArray.powered)..", brightness:"..sArray.brightness..".")
					end
					if (sArray.isTunable) then
						if (sysinfo["light_state"]["dft_on_state"] == nil) then
							sArray.color_temp = tonumber(sysinfo["light_state"]["color_temp"],10)
							sArray.brightness = tonumber(sysinfo["light_state"]["brightness"],10)
						else
							sArray.color_temp = tonumber(sysinfo["light_state"]["dft_on_state"]["color_temp"],10)
							sArray.brightness = tonumber(sysinfo["light_state"]["dft_on_state"]["brightness"],10)
						end
						sArray.current_color = self:getColorSpec(sArray.color_temp)
						luup.log(" McGhee is tunable, color_temp:"..sArray.color_temp..", brightness:"..sArray.brightness..", current_color:"..sArray.current_color..".")
					end
					if (sArray.isColor) then
						sArray.hue = tonumber(sysinfo["light_state"]["hue"],10)
						sArray.saturation = tonumber(sysinfo["light_state"]["saturation"],10)
						if (sysinfo["light_state"]["dft_on_state"] == nil) then
							sArray.brightness = tonumber(sysinfo["light_state"]["brightness"],10)
						else
							sArray.brightness = tonumber(sysinfo["light_state"]["dft_on_state"]["brightness"],10)
						end
						sArray.current_color = self:getColorSpec(0,sArray.hue,sArray.saturation,sArray.brightness)
						luup.log(" McGhee is color, color_temp:"..bool2string(sArray.color_temp)..", brightness:"..sArray.brightness..", current_color:"..sArray.current_color..".")
					end
				elseif ((sysinfo["type"] == "IOT.SMARTPLUGSWITCH") or (sysinfo["mic_type"] == "IOT.SMARTPLUGSWITCH")) then
					sArray.powered = toBool(sysinfo["relay_state"])
					sArray.isDimmable = false
					sArray.isColor = false
					sArray.isTunable = false
					luup.log(" McGhee is IOT.SMARTPLUGSWITCH, powered:"..bool2string(sArray.powered)..".")
				end
			elseif (key == "smartlife.iot.smartbulb.lightingservice") then
				luup.log("("..PLUGIN.NAME.."::TPLINK::parseStatusResponse)    decoded packet data [\n"..print_r(data).."\n]")
				local sysinfo = data['transition_light_state']
				sArray.powered = toBool(sysinfo["on_off"])
--				sArray.brightness = tonumber(sysinfo["brightness"],10) or tonumber(sysinfo["dft_on_state"]["brightness"],10)
				if (sysinfo["dft_on_state"] == nil) then
					sArray.brightness = tonumber(sysinfo["brightness"],10)
				else
					sArray.brightness = tonumber(sysinfo["dft_on_state"]["brightness"],10)
				end
				sArray.hue = tonumber(sysinfo["hue"],10) or tonumber(sysinfo["dft_on_state"]["hue"],10)
				sArray.saturation = tonumber(sysinfo["saturation"],10) or tonumber(sysinfo["dft_on_state"]["saturation"],10)
				sArray.color_temp = tonumber(sysinfo["color_temp"],10) or tonumber(sysinfo["dft_on_state"]["color_temp"],10)
				sArray.err_code = sysinfo["err_code"]
				sArray.current_color = self:getColorSpec(sArray.color_temp,sArray.hue,sArray.saturation,sArray.brightness)
			end
		end
		luup.log("("..PLUGIN.NAME.."::TPLINK::parseStatusResponse) McGhee sArray [\n"..print_r(sArray).."\n]")
		return sArray
	end,

	sendMessage = function(self, address, id, msg, retry_count)
		luup.log("("..PLUGIN.NAME.."::TPLINK::sendMessage) Called sendMessage("..(address or "nil")..",\""..(id or "nil").."\","..(msg or "nil")..","..(retry_count or "nil")..").")
		if ((retry_count == nil) or (retry_count == 0)) then retry_count = 1 end
		local resp = nil
		repeat
			local socket = require("socket")
			local udp = assert(socket.udp())
			udp:settimeout(1)
			luup.log("("..PLUGIN.NAME.."::TPLINK::sendMessage)    Sending command...")
			assert(udp:sendto(self:encodePacket(msg), address, 9999))
			resp = udp:receive()
			udp:close()
			retry_count = retry_count - 1
		until ( (retry_count == 0) or ((resp ~= nil) and (resp ~= "")))
		luup.log("("..PLUGIN.NAME.."::TPLINK::sendMessage)   received response ["..(hex_dump(self:decodePacket(resp)) or "NIL").."]")
		if ((resp ~= nil) and (resp ~= "")) then
			luup.log("("..PLUGIN.NAME.."::TPLINK::sendMessage)   Sent command.",1)
			return false, self:decodePacket(resp)
		else
			luup.log("("..PLUGIN.NAME.."::TPLINK::sendMessage)   Send command failed.",1)
		end
		return true, nil
	end,

	parseDiscoveryPacket = function (self,packet,packet_ip,packet_port)
		local Device = json:decode(self:decodePacket(packet))
		Device.Version = Device.system.get_sysinfo.sw_ver
		Device.ID = Device.system.get_sysinfo.deviceId
		Device.Name = Device.system.get_sysinfo.alias
		Device.AreaCode = ""
		Device.MAC = Device.system.get_sysinfo.mic_mac
		Device.IP = packet_ip
		Device.PORT = packet_port
		Device.PROTOCOL = "TPLINK"
		Device.TYPE = Device.system.get_sysinfo.mic_type
		return Device
	end,

	DoDiscovery = function(self,retry_count)
		luup.log("("..PLUGIN.NAME.."::TPLINK::DoDiscovery) Called DoDiscovery("..(retry_count or "nil")..").")
		if ((retry_count == nil) or (retry_count == 0)) then retry_count = 1 end
		local resp
		local resp_ip
		local resp_port
		local DISCOVERED = {}
		local LocalNet = getLocalNet()
		local msg = self:encodePacket('{ "smartlife.iot.common.cloud" : {"get_info" : {}}, "system" : {"get_sysinfo" : {}},"emeter": {"get_realtime" : {}}, "cnCloud" : {"get_info" : {}}}')
		
		repeat
			local socket = require("socket")
			local udp = assert(socket.udp())
			udp:settimeout(1)
			luup.log("("..PLUGIN.NAME.."::TPLINK::DoDiscovery)    Sending command to ["..(LocalNet)..".255]...")
			assert(udp:setoption("broadcast",true))
			assert(udp:setsockname("*",9998))
			assert(udp:sendto(msg, LocalNet..".255", 9999))
			local rcv_retry = 4
			repeat
				resp, resp_ip, resp_port = udp:receivefrom()
				if (resp and (#resp > 0)) then
					luup.log("("..PLUGIN.NAME.."::TPLINK::DoDiscovery)    Received response from ["..(resp_ip or "NIL")..":"..(resp_port or "NIL").."]...")
					table.insertSet(DISCOVERED,self:parseDiscoveryPacket(resp,resp_ip,resp_port))
				end
				rcv_retry = rcv_retry - 1
			until (rcv_retry == 0)
			udp:close()
			retry_count = retry_count - 1
		until ( (retry_count == 0) or ((resp ~= nil) and (resp ~= "")))
		if (table.getn(DISCOVERED) == 1000) then
			-- broadcast search failed - do device by device search
			local LocalNet = getLocalNet()
			Idx = 1
			repeat
				local tmpIP = LocalNet.."."..Idx
				local socket = require("socket")
				local udp = assert(socket.udp())
				udp:settimeout(1)
				luup.log("("..PLUGIN.NAME.."::TPLINK::DoDiscovery)    Sending command to "..(tmpIP or "NIL").."...")
				assert(udp:setsockname("*",9998))
				assert(udp:sendto(msg, tmpIP, 9999))
				resp, resp_ip, resp_port = udp:receivefrom()
				if (resp and (#resp == 408)) then
					table.insertSet(DISCOVERED,self:parseDiscoveryPacket(resp,resp_ip,resp_port))
				end
				udp:close()
				Idx = Idx + 1
			until (Idx == 254)
		end
		if (table.getn(DISCOVERED) == 0) then
			luup.log("("..PLUGIN.NAME.."::TPLINK::DoDiscover)   Discovery found no devices.")
			return true, DISCOVERED
		else
			local devCount = table.getn(DISCOVERED)
			luup.log("("..PLUGIN.NAME.."::TPLINK::DoDiscovery)   Discovery found ["..(devCount or "NIL").."] devices.",1)
			return false, DISCOVERED
		end
		return true, nil
	end,

	clamp = function( self, x, min, max )
		if(x<min) then return min end
		if(x>max) then return max end
		return math.floor(x)
	end,

	RGBtoHSB = function(self, r, g, b)
	  r, g, b = r / 255, g / 255, b / 255
	  local max, min = math.max(r, g, b), math.min(r, g, b)
	  local cH, cS, cV
	  cV = max

	  local d = max - min
	  if (max == 0) then 
	  	cS = 0 
	  else 
	  	cS = d / max 
	  end

	  if (max == min) then
	    cH = 0 -- achromatic
	  else
	    if (max == r) then
	    	cH = (g - b) / d
	    	if (g < b) then 
	    		cH = cH + 6
	    	end
	    elseif (max == g) then 
	    	cH = (b - r) / d + 2
	    elseif (max == b) then 
	    	cH = (r - g) / d + 4
	    end
	    cH = cH / 6
	  end

	  cH = self:clamp((math.floor(cH * 100)/100)*360,0,359.99)
	  cS = self:clamp((math.floor(cS * 100)/100)*100,0,100)
	  cV = self:clamp((math.floor(cV * 100)/100)*100,1,100)
	  return cH, cS, cV
	end,

	setColorRGB = function(self,deviceConfig,colorTarget)
		local lul_device = deviceConfig.VERA_ID
		local address = deviceConfig.IP
		local id = deviceConfig.ID
		local colorSpec
		
		local RED,GREEN,BLUE = colorTarget:match("(%d+),(%d+),(%d+)")
		colorSpec = "0=,1=,2="..RED..",3="..GREEN..",4="..BLUE

		local swStatus = tonumber(luup.variable_get(SWITCH_SID,"Status",lul_device),10)
		local llStatus = tonumber(luup.variable_get(DIMMER_SID,"LoadLevelStatus",lul_device),10)
		local isOff = (llStatus == 0) and true or false
		luup.log("("..PLUGIN.NAME.."::TPLINK::setColorRGB) swStatus ["..(swStatus or "NIL").."] llStatus ["..(llStatus or "NIL").."] isOff ["..(isOff and "TRUE" or "FALSE").."].")
		local msg

		local HUE,SATURATION,BRIGHTNESS = self:RGBtoHSB(RED,GREEN,BLUE)
		
--		msg = string.format(self.commands['IOT.SMARTBULB']['hue'],HUE)..","..string.format(self.commands['IOT.SMARTBULB']['sat'],SATURATION)..","..string.format(self.commands['IOT.SMARTBULB']['brightness'],BRIGHTNESS)..","..string.format(self.commands['IOT.SMARTBULB']['color_temp'],"0")

		msg = string.format(self.commands['IOT.SMARTBULB']['color_hsv'],HUE,SATURATION,BRIGHTNESS)
		if (isOff == true) then
			msg = self.commands['IOT.SMARTBULB']['on']..","..msg..","..self.commands['IOT.SMARTBULB']['off']
		end
		msg = "{"..msg.."}"
		local err, resp = self:sendMessage(address, id, msg, 3)
		if (not err) then
			local status = self:parseStatusResponse(resp)
			if (status ~= nil) then
				luup.log("("..PLUGIN.NAME.."::TPLINK::setColorRGB) Color of device with ID "..(id or "NIL").." set to: ["..(status.color_temp or "NIL").."]")
				status.current_color = colorSpec
				return status
			else
				luup.log("("..PLUGIN.NAME.."::TPLINK::setColorRGB) Color change of device with ID "..(id or "NIL").." to: [H:"..(status.hue or "NIL").." S:"..(status.saturation or "NIL").." V:"..(status.brightness or "NIL").."] NOT VERIFIED")
				return nil
			end
		else
			luup.log("("..PLUGIN.NAME.."::TPLINK::setColorRGB) Error setting color of device with ID "..(id or "NIL")..".")
		end
		return nil

	end,
	
	setColor = function(self,deviceConfig,colorTarget)
		local lul_device = deviceConfig.VERA_ID
		local address = deviceConfig.IP
		local id = deviceConfig.ID
		local colorTemp
		local colorSpec
		
		debug("("..PLUGIN.NAME.."::TPLINK::setColor) McGhee colorTarget: "..(colorTarget or "NIL")..".")
		if ((colorTarget:sub(1,1) == "W") or (colorTarget:sub(1,1) == "D")) then
			local ctValue = tonumber(colorTarget:sub(2,#colorTarget),10)
			if (colorTarget:sub(1,1) == "W") then
				colorTemp = (((5500 - 2200)/256) * ctValue) + 2200
				colorSpec = "0="..ctValue..",1=,2=,3=,4="
			elseif (colorTarget:sub(1,1) == "D") then
				colorTemp = (((9000 - 5500)/256) * ctValue) + 5500
				colorSpec = "0=,1="..ctValue..",2=,3=,4="
			end
		else
			luup.log("("..PLUGIN.NAME.."::TPLINK::setColor) Invalid Color Temperature specified.")
			return nil
		end

		colorTemp = math.floor(colorTemp)
		local status = self:setColorTemp(deviceConfig, colorTemp)
		status.current_color = colorSpec
		return status
	end,

--		colorTemp = math.floor(colorTemp)
		
--		debug("("..PLUGIN.NAME.."::TPLINK::setColor) McGhee colorTemp: "..(colorTemp or "NIL")..", colorSpec:"..(colorSpec or "NIL")..".")
--		local swStatus = tonumber(luup.variable_get(SWITCH_SID,"Status",lul_device),10)
--		local llStatus = tonumber(luup.variable_get(DIMMER_SID,"LoadLevelStatus",lul_device),10)
--		local isOff = (llStatus == 0) and true or false
--		luup.log("("..PLUGIN.NAME.."::TPLINK::setColor) swStatus ["..(swStatus or "NIL").."] llStatus ["..(llStatus or "NIL").."] isOff ["..(isOff and "TRUE" or "FALSE").."].")
--		local msg
		
--		msg = string.format(self.commands['IOT.SMARTBULB']['color_temp'],colorTemp)
--		if (isOff == true) then
--			msg = self.commands['IOT.SMARTBULB']['on']..","..msg..","..self.commands['IOT.SMARTBULB']['off']
--		end
--		msg = "{"..msg.."}"
--		debug("("..PLUGIN.NAME.."::TPLINK::setColor) McGhee msg: "..(msg or "NIL")..".")

--		local retry_count = 3
--
--		local err, resp = self:sendMessage(address, id, msg, retry_count)
--		if (not err) then
--			local status = self:parseStatusResponse(resp)
--			if (status ~= nil) then
--				luup.log("("..PLUGIN.NAME.."::TPLINK::setColor) Color Temperature of device with ID "..(id or "NIL").." set to: ["..(status.color_temp or "NIL").."]")
--				status.current_color = colorSpec
--				return status
--			else
--				luup.log("("..PLUGIN.NAME.."::TPLINK::setColor) Color Temperature change of device with ID "..(id or "NIL").." to: ["..(status.color_temp or "NIL").."] NOT VERIFIED")
--				return nil
--			end
--		else
--			luup.log("("..PLUGIN.NAME.."::TPLINK::setColor) Error setting color temperature of device with ID "..(id or "NIL")..".")
--		end
--		return nil
--	end,
	
	setColorTemp = function(self,deviceConfig, colorTemp)
		local lul_device = deviceConfig.VERA_ID
		local address = deviceConfig.IP
		local id = deviceConfig.ID
--		local colorTemp
--		local colorSpec
		debug("("..PLUGIN.NAME.."::TPLINK::setColor) McGhee colorTemp: "..(colorTemp or "NIL")..".")
		
--		if ((colorTarget:sub(1,1) == "W") or (colorTarget:sub(1,1) == "D")) then
--			local ctValue = tonumber(colorTarget:sub(2,#colorTarget),10)
--			if (colorTarget:sub(1,1) == "W") then
--				colorTemp = (((5500 - 2200)/256) * ctValue) + 2200
--				colorSpec = "0="..ctValue..",1=,2=,3=,4="
--			elseif (colorTarget:sub(1,1) == "D") then
--				colorTemp = (((9000 - 5500)/256) * ctValue) + 5500
--				colorSpec = "0=,1="..ctValue..",2=,3=,4="
--			end
--		else
--			luup.log("("..PLUGIN.NAME.."::TPLINK::setColorTemp) Invalid Color Temperature specified.",1)
--			return nil
--		end
		
		local swStatus = tonumber(luup.variable_get(SWITCH_SID,"Status",lul_device),10)
		local llStatus = tonumber(luup.variable_get(DIMMER_SID,"LoadLevelStatus",lul_device),10)
		local isOff = (llStatus == 0) and true or false
		luup.log("("..PLUGIN.NAME.."::TPLINK::setColorTemp) swStatus ["..(swStatus or "NIL").."] llStatus ["..(llStatus or "NIL").."] isOff ["..(isOff and "TRUE" or "FALSE").."].",2)
		local msg
		
		msg = string.format(self.commands['IOT.SMARTBULB']['color_temp'],colorTemp)
		if (isOff == true) then
			msg = self.commands['IOT.SMARTBULB']['on']..","..msg..","..self.commands['IOT.SMARTBULB']['off']
		end
		msg = "{"..msg.."}"
		debug("("..PLUGIN.NAME.."::TPLINK::setColor) McGhee msg: "..(msg or "NIL")..".")

		local retry_count = 3

		local err, resp = self:sendMessage(address, id, msg, retry_count)
		if (not err) then
			local status = self:parseStatusResponse(resp)
			if (status ~= nil) then
				luup.log("("..PLUGIN.NAME.."::TPLINK::setColorTemp) Color Temperature of device with ID "..(id or "NIL").." set to: ["..(status.color_temp or "NIL").."]",2)
				status.current_color = self:getColorSpec(colorTemp)
				return status
			else
				luup.log("("..PLUGIN.NAME.."::TPLINK::setColorTemp) Color Temperature change of device with ID "..(id or "NIL").." to: ["..(status.color_temp or "NIL").."] NOT VERIFIED",1)
				return nil
			end
		else
			luup.log("("..PLUGIN.NAME.."::TPLINK::setColorTemp) Error setting color temperature of device with ID "..(id or "NIL")..".",1)
		end
		return nil

	end,
	
	setLoadLevelTarget = function(self,deviceConfig,level)
		local address = deviceConfig.IP
		local id = deviceConfig.ID
		luup.log("("..PLUGIN.NAME.."::TPLINK::setLoadLevelTarget) Called setLoadLevelTarget("..(address or "nil")..",\""..(id or "nil").."\","..(level or "NIL")..").")
		local msg 
		
		level = tonumber(level,10)
		if (level > 100) then level = 100 end
		if (0 > level) then level = 0 end
		
		msg = string.format(self.commands['IOT.SMARTBULB']['brightness'],level)

		if (level == 0) then
			msg = "{"..self.commands['IOT.SMARTBULB']['off'].."}"
		else
			msg = "{"..self.commands['IOT.SMARTBULB']['on']..","..msg.."}"
		end
		
		local retry_count = 3

		local err, resp = self:sendMessage(address, id, msg, retry_count)
		if (not err) then
			local status = self:parseStatusResponse(resp)
			if (status ~= nil) then
				luup.log("("..PLUGIN.NAME.."::TPLINK::setLoadLevelTarget) State of switch with ID "..(id or "NIL").." set to: ["..(status.powered and "ON" or "OFF").." - "..(status.brightness or "NIL").."%]")
				return status
			else
--				luup.log("("..PLUGIN.NAME.."::TPLINK::setLoadLevelTarget) State of switch with ID "..(id or "NIL").." set to: ["..((status.powered == true)and "ON" or "OFF").."]")
				luup.log("("..PLUGIN.NAME.."::TPLINK::setLoadLevelTarget) State of switch with ID "..(id or "NIL").." set to: ["..(status.powered and "ON" or "OFF").." - "..(status.brightness or "NIL").."%]")
				return nil
			end
		else
			luup.log("("..PLUGIN.NAME.."::TPLINK::setLoadLevelTarget) Error getting status of switch with ID "..(id or "NIL")..".")
		end
		return nil

	end,
	
	setTarget = function(self,deviceConfig,on)
		local address = deviceConfig.IP
		local id = deviceConfig.ID
		luup.log("("..PLUGIN.NAME.."::TPLINK::setTarget) McGhee deviceConfig: [\n"..print_r(deviceConfig).."\n]")
		local devType = (deviceConfig.system.get_sysinfo.mic_type or deviceConfig.system.get_sysinfo.type)
		luup.log("("..PLUGIN.NAME.."::TPLINK::setTarget) McGhee TYPE: "..(devType or 'nul')..".")
		luup.log("("..PLUGIN.NAME.."::TPLINK::setTarget) Called setTarget("..(address or "nil")..",\""..(id or "nil").."\","..(on and "true" or "false")..").")

		local msg
		if (devType == "IOT.SMARTPLUGSWITCH") then
			msg = "{"..(on and self.commands['IOT.SMARTPLUGSWITCH']['on'] or self.commands['IOT.SMARTPLUGSWITCH']['off']).."}"
		else
			msg = "{"..(on and self.commands['IOT.SMARTBULB']['on'] or self.commands['IOT.SMARTBULB']['off']).."}"
		end
		luup.log("("..PLUGIN.NAME.."::TPLINK::setTarget) McGhee TYPE: "..devType..", msg: "..msg..".")
		local retry_count = 3

		local err, resp = self:sendMessage(address, id, msg, retry_count)
		-- the set command does NOT respond with a device status report
		if (not err) then
			local status = self:parseStatusResponse(resp)
			if (status ~= nil) then
				luup.log("("..PLUGIN.NAME.."::TPLINK::setTarget) State of switch with ID "..(id or "NIL").." set to: ["..(status.powered and "ON" or "OFF").."]")
				return status
			else
				luup.log("("..PLUGIN.NAME.."::TPLINK::setTarget) State of switch with ID "..(id or "NIL").." set to: ["..(status.powered and "ON" or "OFF").."]")
				return nil
			end
		else
			luup.log("("..PLUGIN.NAME.."::TPLINK::setTarget) Error getting status of switch with ID "..(id or "NIL")..".")
		end
		return nil
	end,
	
	getStatus = function(self,deviceConfig)
		local address = deviceConfig.IP
		local id = deviceConfig.ID
		luup.log("("..PLUGIN.NAME.."::TPLINK::getStatus) Called getStatus("..(address or "nil")..",\""..(id or "nil").."\").")
--		local status = {}
		local msg = "{"..self.commands['info'].."}"
		local retry_count = 3
		local err, resp = self:sendMessage(address, id, msg, retry_count)
		if (err == false) then
			local status = self:parseStatusResponse(resp)
			luup.log("("..PLUGIN.NAME.."::TPLINK::getStatus) Status of switch with ID "..(id or "NIL").." is: ["..(status.powered  and "ON" or "OFF").."]")
			return status
		else
			luup.log("("..PLUGIN.NAME.."::TPLINK::getStatus) Error getting status of switch with ID "..(id or "NIL")..".")
		end
		return nil
	end
}



local SENGLED = {
	-- XML startes at byte $46
	parseStatusResponse = function(self, packet)
		debug("("..PLUGIN.NAME.."::SENGLED::parseStatusResponse) McGhee packet: ["..hex_dump(packet),2)
		local sArray = {}
		local NameEnd = packet:find("\0", 46)
		debug("("..PLUGIN.NAME.."::SENGLED::parseStatusResponse) NameEnd: "..(NameEnd or "nil")..".", 2)
		sArray.Name = packet:sub(46, NameEnd - 1) 
		debug("("..PLUGIN.NAME.."::SENGLED::parseStatusResponse) Name: "..(sArray.Name or "nil")..".", 2)
		sArray.brightness = tonumber(packet:byte(146), 10)
		sArray.powered = (sArray.brightness ~= 0)
		debug("("..PLUGIN.NAME.."::SENGLED::parseStatusResponse) Name: "..(sArray.Name or "nil")..", brightness: "..(sArray.brightness or "nil")..", powered:"..(bool2string(sArray.powered) or "nil")..".", 2)
		return sArray
	end,

	parseDiscoveryPacket = function (self,packet,packet_ip,packet_port)
		local Device = {}
		Device.ID = "BOOST_"..packet_ip
		Device.Name = "BOOST_"..packet_ip
		Device.IP = packet_ip
		Device.PORT = packet_port
		Device.PROTOCOL = "SENGLED"
		Device.TYPE = "IOT.SMARTBULB"
		debug("("..PLUGIN.NAME.."::SENGLED::parseDiscoveryPacket) Device.TYPE: "..(Device.TYPE or "nil")..".", 2)
		return Device
	end,

	DoDiscovery = function(self,retry_count)
		luup.log("("..PLUGIN.NAME.."::SENGLED::DoDiscovery) Called DoDiscovery("..(retry_count or "nil")..").")
		if ((retry_count == nil) or (retry_count == 0)) then retry_count = 1 end
		local resp
		local resp_ip
		local resp_port
		local DISCOVERED = {}
		local LocalNet = getLocalNet()
		local veraIP1, veraIP2, veraIP3, veraIP4 = string.match(PLUGIN.VERA_IP,"(%d+)%.(%d+)%.(%d+)%.(%d+)")
		
		local msg = string.char(0x0d,0x00,0x02,0x00,0x01)
		msg = msg .. string.char(veraIP1,veraIP2,veraIP3,veraIP4)
		msg = msg .. string.char(0xff,0xff,0xff,0xff)
		msg = msg .. string.char(veraIP1,veraIP2,veraIP3,veraIP4)
		msg = msg .. string.char(0xff,0xff,0xff,0xff)
		msg = msg .. string.char(0x03,0x00,0x01,0x00)

		repeat
			local socket = require("socket")
			local udp = assert(socket.udp())
			udp:settimeout(1)
			luup.log("("..PLUGIN.NAME.."::SENGLED::DoDiscovery)    Sending command to ["..(LocalNet)..".255]...")
			assert(udp:setoption("broadcast",true))
			assert(udp:setsockname("*",9060))
			assert(udp:sendto(msg, LocalNet..".255", 9060))
			local rcv_retry = 4
			repeat
				resp, resp_ip, resp_port = udp:receivefrom()
				if (resp and (#resp > 0)) then
					if (resp_ip ~= PLUGIN.VERA_IP) then
						luup.log("("..PLUGIN.NAME.."::SENGLED::DoDiscovery)    Received response from "..(resp_ip or "NIL")..":"..(resp_port or "NIL")..", \n   resp: ["..hex_dump(resp).."]...", 2)
						table.insertSet(DISCOVERED,self:parseDiscoveryPacket(resp,resp_ip,resp_port))
					end
				end
				rcv_retry = rcv_retry - 1
			until (rcv_retry == 0)
			udp:close()
			retry_count = retry_count - 1
		until ( (retry_count == 0) or ((resp ~= nil) and (resp ~= "")))
		if (table.getn(DISCOVERED) == 1000) then
			-- broadcast search failed - do device by device search
			local LocalNet = getLocalNet()
			Idx = 1
			repeat
				local tmpIP = LocalNet.."."..Idx
				local socket = require("socket")
				local udp = assert(socket.udp())
				udp:settimeout(1)
				luup.log("("..PLUGIN.NAME.."::SENGLED::DoDiscovery)    Sending command to "..(tmpIP or "NIL").."...")
				assert(udp:setsockname("*",9060))
				assert(udp:sendto(msg, tmpIP, 9060))
				resp, resp_ip, resp_port = udp:receivefrom()
				if (resp and (#resp > 0)) then
					if (resp_ip ~= PLUGIN.VERA_IP) then
						table.insertSet(DISCOVERED,self:parseDiscoveryPacket(resp,resp_ip,resp_port))
					end
				end
				udp:close()
				Idx = Idx + 1
			until (Idx == 254)
		end
		if (table.getn(DISCOVERED) == 0) then
			luup.log("("..PLUGIN.NAME.."::SENGLED::DoDiscover)   Discovery found no devices.")
			return true, DISCOVERED
		else
			local devCount = table.getn(DISCOVERED)
			luup.log("("..PLUGIN.NAME.."::SENGLED::DoDiscovery)   Discovery found ["..(devCount or "NIL").."] devices.",1)
			return false, DISCOVERED
		end
		return true, nil
	end,

	sendMessage = function(self, address, msg, retry_count)
		luup.log("("..PLUGIN.NAME.."::SENGLED::sendMessage) Called sendMessage("..(address or "nil")..", retry count:"..(retry_count or "nil")..").")
		if ((retry_count == nil) or (retry_count == 0)) then retry_count = 1 end
		local resp
		repeat
			local socket = require("socket")
			local udp = assert(socket.udp())
			luup.log("("..PLUGIN.NAME.."::SENGLED::sendMessage)    Sending command...")
			udp:settimeout(1)
--			assert(udp:setsockname("*",9060))
			luup.log("("..PLUGIN.NAME.."::SENGLED::sendMessage) setsockname returns:("..(udp:setsockname("*",9060) or "nil")..").")
			assert(udp:sendto(msg, address, 9060))
			resp = udp:receive()
			luup.log("("..PLUGIN.NAME.."::SENGLED::sendMessage) resp:"..(resp or "nil")..".")
			udp:close()
			retry_count = retry_count - 1
		until ( (retry_count == 0) or ((resp ~= nil) and (#resp > 0)))
		if ((resp ~= nil) and (#resp > 0)) then
			luup.log("("..PLUGIN.NAME.."::SENGLED::sendMessage)   Received Response.",1)
			return false, resp
		else
			luup.log("("..PLUGIN.NAME.."::SENGLED::sendMessage)   Recieve failed.",1)
		end
		return true, nil	-- all retries exausted
	end,
  
	setLoadLevelTarget = function(self, deviceConfig, newlevel)
		debug("("..PLUGIN.NAME.."::SENGLED::setLoadLevelTarget) newlevel: "..(newlevel or "nil")..", deviceConfig: ["..print_r(deviceConfig),2)
		local veraId = deviceConfig.VERA_ID
		local address = deviceConfig.IP
		local port = deviceConfig.PORT
		veraIP1, veraIP2, veraIP3, veraIP4 = string.match(PLUGIN.VERA_IP,"(%d+)%.(%d+)%.(%d+)%.(%d+)")
		lightIP1, lightIP2, lightIP3, lightIP4 = string.match(address,"(%d+)%.(%d+)%.(%d+)%.(%d+)")

--		local llstatus = luup.variable_get("urn:upnp-org:serviceId:Dimming1","LoadLevelStatus",lul_device)
		local level = tonumber(newlevel,10)
		if level > 100 then level = 100 end
		if level < 0 then level = 0 end

		debug("("..PLUGIN.NAME.."::SENGLED::setLoadLevelTarget) McGhee level: "..(level or "nil")..".", 2)
		--
		--  create and send Set Target msg
		--
		local sCommand = string.char(0x0d,0x00,0x02,0x00,0x01)
		sCommand = sCommand .. string.char(veraIP1,veraIP2,veraIP3,veraIP4)	-- set the ip addresses
		sCommand = sCommand .. string.char(lightIP1,lightIP2,lightIP3,lightIP4)
		sCommand = sCommand .. string.char(veraIP1,veraIP2,veraIP3,veraIP4)
		sCommand = sCommand .. string.char(lightIP1,lightIP2,lightIP3,lightIP4)
		sCommand = sCommand .. string.char(0x01,0x00,0x01,0x00,0x00,0x00)
		sCommand = sCommand .. string.char(level,0x64)

		self:sendMessage(address, sCommand, 3)
		luup.log("("..PLUGIN.NAME.."::SENGLED::setLoadTarget) McGhee Setting load target for "..(address or 'nil')..".")

		local status = (self:getStatus(deviceConfig))

		if (status ~= nil) then
			luup.log("("..PLUGIN.NAME.."::SENGLED::setLoadLevelTarget) State of device ID "..(veraId or "NIL").." set to: "..bool2string(status.powered)..",  brightness: "..(status.brightness or "NIL")..".")
			return status
		else
			luup.log("("..PLUGIN.NAME.."::SENGLED::setLoadLevelTarget) State of device ID "..(veraId or "NIL").." NOT SET DUE TO ERROR")
			return nil
		end
		
--		luup.variable_set(DIMMER_SID, "LoadLevelStatus", newlevel, veraId)
--		luup.variable_set(DIMMER_SID, "LoadLevelTarget", newlevel, veraId)
--		if (newlevel == 0) then
--			luup.variable_set(SWITCH_SID, "Status", 0, veraId)
--			luup.variable_set(SWITCH_SID, "Target", 0, veraId)
--		else
--			luup.variable_set(SWITCH_SID, "Status", 1, veraId)
--			luup.variable_set(SWITCH_SID, "Target", 1, veraId)
--		end

--		return (self:getStatus(deviceConfig))
	end,

  	setTarget = function(self, deviceConfig, target)
		local level
		if (target) then
			level = 100
		else
			level = 0
		end
		debug("("..PLUGIN.NAME.."::SENGLED::setTarget) McGhee target: "..bool2string(target or "nil")..", level: "..(level or "nil")..".", 2)
		return self:setLoadLevelTarget(deviceConfig, level)
--		return (self:getStatus(deviceConfig))
	end,

	getStatus = function(self, deviceConfig)
		debug("("..PLUGIN.NAME.."::SENGLED::getStatus) McGhee deviceConfig: ["..print_r(deviceConfig).."]", 1)
		local status = {}
		local lul_device = deviceConfig.VERA_ID
		local address = deviceConfig.IP
		veraIP1, veraIP2, veraIP3, veraIP4 = string.match(PLUGIN.VERA_IP,"(%d+)%.(%d+)%.(%d+)%.(%d+)")
		lightIP1, lightIP2, lightIP3, lightIP4 = string.match(address,"(%d+)%.(%d+)%.(%d+)%.(%d+)")
		--
		--  create and send Set Target msg
		--
		local sCommand = string.char(0x0d,0x00,0x02,0x00,0x01)
		sCommand = sCommand .. string.char(veraIP1,veraIP2,veraIP3,veraIP4)		-- set the ip addresses
		sCommand = sCommand .. string.char(lightIP1,lightIP2,lightIP3,lightIP4)
		sCommand = sCommand .. string.char(veraIP1,veraIP2,veraIP3,veraIP4)
		sCommand = sCommand .. string.char(lightIP1,lightIP2,lightIP3,lightIP4)
		sCommand = sCommand .. string.char(0x03,0x00,0x13,0x00)

		luup.log("("..PLUGIN.NAME.."::SENGLED::getStatus) Sending Message:("..(address or "nil")..", "..(hex_dump(sCommand) or "nil")..").")
		local err, resp = self:sendMessage(address, sCommand, 3)
		luup.log("("..PLUGIN.NAME.."::SENGLED::getStatus) err: "..bool2string(err)..".")
		if (not err) then
			luup.log("("..PLUGIN.NAME.."::SENGLED::getStatus)   resp: ["..(hex_dump(resp) or "NIL").."]")
			status = self:parseStatusResponse(resp)
			luup.log("("..PLUGIN.NAME.."::SENGLED::getStatus)   sArray: ["..(print_r(sArray) or "NIL").."]")
			luup.log("("..PLUGIN.NAME.."::SENGLED::getStatus) Status of switch with address "..(address or "NIL").." is: "..(status.powered  and "ON" or "OFF")..".")
			return status
		else
			luup.log("("..PLUGIN.NAME.."::SENGLED::getStatus) Error getting status of switch with address "..(address or "NIL")..".")
		end
		return nil
	end
}

local EcoSwitch = {

	getString = function (self,string,index)
		local retVal = ""
		local idx = index
		while idx < #string do
			local chr = string:byte(idx)
			if (chr == 0) then return retVal end
			retVal = retVal .. string:sub(idx,idx)
			idx = idx + 1
		end
		return retVal
	end,
	
	parseDiscoveryPacket = function (self,packet)
		local Device = {}
		Device.Version = self:getString(packet,5)
		Device.ID = self:getString(packet,11)
		Device.Name = self:getString(packet,43)
		Device.AreaCode = self:getString(packet,261)
		Device.MAC = self:getString(packet,369)
		Device.IP = self:getString(packet,387)
		Device.PROTOCOL = "ECO_SWITCH"
		return Device
	end,

	createMessage = function(self, command, id, state)
		luup.log("("..PLUGIN.NAME.."::EcoSwitch::createMessage) Called createMessage("..(command or "nil")..",\""..(id or "nil").."\","..(state and "true" or "false")..").")

		local buffer = ""
		local command1 = ""
		local command2 = ""
		local new_state = ""

		if (command == 'set') then
			command1 = 0x16000500;
			command1 = string.char(22,0,5,0)
			command2 = string.char(2,0)
			if (state) then
				new_state = string.char(1,1)
			else
				new_state = string.char(1,0)
			end
		elseif (command == 'get') then
			command1 = string.char(23,0,5,0)
			command2 = string.char(0,0)
			new_state = ""
		elseif (command == 'discover') then
			buffer = string.char(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
			buffer = buffer..string.char(0,0,0,0,0,0,0,0,225,7,11,17,247,157,0,0)
			buffer = buffer..string.char(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
			buffer = buffer..string.char(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
			buffer = buffer..string.char(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
			buffer = buffer..string.char(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
			buffer = buffer..string.char(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
			buffer = buffer..string.char(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
			luup.log("("..PLUGIN.NAME.."::EcoSwitch::createMessage) Created discovery command data - time ["..(os.time() or "NIL").."] ["..hex_dump(buffer).."]")
			return buffer
		else
			return nil
		end

		-- Byte 0:3 - Command 0x16000500 = Write, 0x17000500 = Read
		buffer = command1
    
		-- Byte 4:7 - Command sequence num - looks random
		local rand = string.format("%08x",math.random(65535))
		buffer = buffer..string.char(tonumber(rand:sub(1,2),16),tonumber(rand:sub(3,4),16),tonumber(rand:sub(5,6),16),tonumber(rand:sub(7,8),16))

		-- Byte 8:9 - Not sure what this field is - 0x0200 = Write, 0x0000 = Read
		buffer = buffer..command2

		-- Byte 10:14 - ASCII encoded FW Version - Set in readback only?
		buffer = buffer..string.char(0,0,0,0,0)
    		
		-- Byte 15 - Always 0x0
		buffer = buffer..string.char(0)

		-- Byte 16:31 - ECO Plugs ID ASCII Encoded
		buffer = buffer..string.sub(id..string.char(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0),1,16)

		-- Byte 32:47 - 0's - Possibly extension of Plug ID
		buffer = buffer..string.char(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)

		-- Byte 48:79 - ECO Plugs name as set in app
		buffer = buffer..string.char(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
		buffer = buffer..string.char(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)

		-- Byte 80:95 - ECO Plugs ID without the 'ECO-' prefix - ASCII Encoded
		buffer = buffer..string.char(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)

		-- Byte 96:111 - 0's
		buffer = buffer..string.char(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)

		-- Byte 112:115 - Something gets returned here during readback - not sure
		buffer = buffer..string.char(0,0,0,0)

		-- Byte 116:119 - The current epoch time in Little Endian
		local timestamp = string.format("%08x",os.time())
		buffer = buffer..string.char(tonumber(timestamp:sub(1,2),16),tonumber(timestamp:sub(3,4),16),tonumber(timestamp:sub(5,6),16),tonumber(timestamp:sub(7,8),16))

		-- Byte 120:123 - 0's
		buffer = buffer..string.char(0,0,0,0)

		-- Byte 124:127 - Not sure what this field is - this value works, but i've seen others 0xCDB8422A
		buffer = buffer..string.char(205,184,66,42)

		-- Byte 128:129 - Power state (only for writes)
		buffer = buffer..new_state

		luup.log("("..PLUGIN.NAME.."::EcoSwitch::createMessage) Created command data - time ["..(os.time() or "NIL").."] ["..hex_dump(buffer).."]")
		return buffer
	end,
	
	DoDiscovery = function(self, retry_count)
		luup.log("("..PLUGIN.NAME.."::EcoSwitch::DoDiscovery) Called DoDiscovery("..(retry_count or "nil")..").")
		if ((retry_count == nil) or (retry_count == 0)) then retry_count = 1 end
		local resp = nil
		local DISCOVERED = {}
		local LocalNet = getLocalNet()
		local msg = self:createMessage("discover")
		repeat
			local socket = require("socket")
			local udp = assert(socket.udp())
			udp:settimeout(1)
			luup.log("("..PLUGIN.NAME.."::EcoSwitch::DoDiscovery)    Sending command to ["..(LocalNet)..".255]...")
			assert(udp:setoption("broadcast",true))
			assert(udp:setsockname("*",9000))
			assert(udp:sendto(msg, LocalNet..".255", 25))
			local rcv_retry = 4
			repeat
				resp = udp:receive()
				if (resp and (#resp == 408)) then
					table.insertSet(DISCOVERED,self:parseDiscoveryPacket(resp))
				end
				rcv_retry = rcv_retry - 1
			until (rcv_retry == 0)
			udp:close()
			retry_count = retry_count - 1
		until ( (retry_count == 0) or ((resp ~= nil) and (resp ~= "")))
		if (table.getn(DISCOVERED) == 1000) then
			-- broadcast search failed - do device by device search
			local LocalNet = getLocalNet()
			Idx = 1
			repeat
				local tmpIP = LocalNet.."."..Idx
				local socket = require("socket")
				local udp = assert(socket.udp())
				udp:settimeout(1)
				luup.log("("..PLUGIN.NAME.."::EcoSwitch::DoDiscovery)    Sending command to "..(tmpIP or "NIL").."...")
				assert(udp:setsockname("*",9000))
				assert(udp:sendto(msg, tmpIP, 25))
				resp = udp:receive()
				if (resp and (#resp == 408)) then
					table.insertSet(DISCOVERED,self:parseDiscoveryPacket(resp))
				end
				udp:close()
				Idx = Idx + 1
			until (Idx == 254)
		end
		if (table.getn(DISCOVERED) == 0) then
			luup.log("("..PLUGIN.NAME.."::EcoSwitch::DoDiscover)   Discovery found no devices.")
			return true, DISCOVERED
		else
			local devCount = table.getn(DISCOVERED)
			luup.log("("..PLUGIN.NAME.."::EcoSwitch::DoDiscovery)   Discovery found ["..(devCount or "NIL").."] devices.",1)
			return false, DISCOVERED
		end
		return true, nil
	end,

	sendMessage = function(self, address, id, msg, retry_count)
		luup.log("("..PLUGIN.NAME.."::EcoSwitch::sendMessage) Called sendMessage("..(address or "nil")..",\""..(id or "nil").."\","..(msg or "nil")..","..(retry_count or "nil")..").")
		if ((retry_count == nil) or (retry_count == 0)) then retry_count = 1 end
		local resp = nil
		repeat
			local socket = require("socket")
			local udp = assert(socket.udp())
			udp:settimeout(1)
			luup.log("("..PLUGIN.NAME.."::EcoSwitch::sendMessage)    Sending command...")
			assert(udp:sendto(msg, address, 80))
			resp = udp:receive()
			udp:close()
			retry_count = retry_count - 1
		until ( (retry_count == 0) or ((resp ~= nil) and (resp ~= "")))
		luup.log("("..PLUGIN.NAME.."::EcoSwitch::sendMessage)   received response ["..(hex_dump(resp) or "NIL").."]")
		if ((resp ~= nil) and (resp ~= "")) then
			luup.log("("..PLUGIN.NAME.."::EcoSwitch::sendMessage)   Sent command.",1)
			return false, resp
		else
			luup.log("("..PLUGIN.NAME.."::EcoSwitch::sendMessage)   Send command failed.",1)
		end
		return true, nil
	end,

	setTarget = function (self, deviceConfig, on)
		local address = deviceConfig.IP
		local id = deviceConfig.ID
		luup.log("("..PLUGIN.NAME.."::EcoSwitch::setTarget) Called setTarget("..(address or "nil")..",\""..(id or "nil").."\","..(on and "true" or "false")..").")

		local msg = self:createMessage('set', id, on)
		local retry_count = 3

		local err, resp = self:sendMessage(address, id, msg, retry_count)
		-- the set command does NOT respond with a device status report
		if (not err) then
			local status = self:getStatus(deviceConfig)
			if (status ~= nil) then
				luup.log("("..PLUGIN.NAME.."::EcoSwitch::setTarget) State of switch with ID "..(id or "NIL").." set to: ["..(status.powered and "ON" or "OFF").."]")
				return status
			else
				luup.log("("..PLUGIN.NAME.."::EcoSwitch::setTarget) State of switch with ID "..(id or "NIL").." set to: ["..(status.powered and "ON" or "OFF").."]")
				return nil
			end
		else
			luup.log("("..PLUGIN.NAME.."::EcoSwitch::setTarget) Error getting status of switch with ID "..(id or "NIL")..".")
		end
		return nil
	end,

	readState = function(self,msg)
		local status = {}
		if (msg:byte(130) == 0) then
			status.powered = false
		else
			status.powered = true
		end
		return status
	end,

	readName = function (self,msg)
		return (msg and (msg:sub(49, 80)) or nil)
	end,

	getStatus = function(self, deviceConfig)
		local address = deviceConfig.IP
		local id = deviceConfig.ID
		luup.log("("..PLUGIN.NAME.."::EcoSwitch::getStatus) Called getStatus("..(address or "nil")..",\""..(id or "nil").."\").")
		local status = false
		local msg = self:createMessage('get', id)
		local retry_count = 3
		local err, resp = self:sendMessage(address, id, msg, retry_count)
		if (err == false) then
			local status = self:readState(resp)
			luup.log("("..PLUGIN.NAME.."::EcoSwitch::getStatus) Status of switch with ID "..(id or "NIL").." is: ["..(status.powered and "ON" or "OFF").."]")
			return status
		else
			luup.log("("..PLUGIN.NAME.."::EcoSwitch::getStatus) Error getting status of switch with ID "..(id or "NIL")..".")
		end
		return nil
	end
}

function PollSwitchs()
	luup.log("("..PLUGIN.NAME.."::PollSwitchs) **************************",2)
	luup.log("("..PLUGIN.NAME.."::PollSwitchs) Polling for switch status.",2)
	luup.log("("..PLUGIN.NAME.."::PollSwitchs) Poll period ["..(PLUGIN.PollPeriod or "NIL").."].",2)
	for vera_id,dConfig in pairs(CONFIGURED_DEVICES) do
		luup.log("("..PLUGIN.NAME.."::PollSwitchs)   Getting status for device ["..(vera_id or "NIL").."].",2)
		local status
		if ((dConfig.PROTOCOL == "") or (dConfig.PROTOCOL == "ECO_SWITCH")) then
			status = EcoSwitch:getStatus(dConfig)
		elseif (dConfig.PROTOCOL == "TPLINK") then
			status = TPLINK:getStatus(dConfig)
		elseif (dConfig.PROTOCOL == "SENGLED") then
			status = SENGLED:getStatus(dConfig)
		end
		if (status == nil) then
			set_failure(1,vera_id)
			luup.log("("..PLUGIN.NAME.."::PollSwitchs)     Setting *FAILURE* for device ["..(vera_id or "NIL").."].",2)
		else
			luup.log("("..PLUGIN.NAME.."::PollSwitchs)   Received STATUS for device ["..(vera_id or "NIL").."].\n"..print_r(status),2)
			set_failure(0,vera_id)
			luup.variable_set(SWITCH_SID,"Status",(status.powered and 1 or 0),vera_id)
			luup.variable_set(SWITCH_SID,"Target",(status.powered and 1 or 0),vera_id)
			if (status.brightness) then
				if (status.powered) then
					luup.variable_set(DIMMER_SID,"LoadLevelStatus",status.brightness,vera_id)
					luup.variable_set(DIMMER_SID,"LoadLevelTarget",status.brightness,vera_id)
				else
					luup.variable_set(DIMMER_SID,"LoadLevelStatus",0,vera_id)
					luup.variable_set(DIMMER_SID,"LoadLevelTarget",0,vera_id)
				end
				luup.log("("..PLUGIN.NAME.."::PollSwitchs)     Setting LoadLevelStatus for device ["..(vera_id or "NIL").."].",2)
			end
			luup.log("("..PLUGIN.NAME.."::PollSwitchs)     Setting Status for device ["..(vera_id or "NIL").."].",2)
		end
	end
	luup.call_delay("PollSwitchs",PLUGIN.PollPeriod,"")
	luup.log("("..PLUGIN.NAME.."::PollSwitchs) Polling for switch status completed.",2)
	luup.log("("..PLUGIN.NAME.."::PollSwitchs) ************************************",2)
end

function UPNP_AddDevice(lul_device,lul_settings)
	luup.log("("..PLUGIN.NAME.."::UPNP_AddDevice) Preparing to add device.",2)
	luup.log("("..PLUGIN.NAME.."::UPNP_AddDevice) lul_settings ["..print_r(lul_settings).."].",2)
	local DeviceData = json:decode(lul_settings.DeviceData)
	table.insert(CONFIGURED_DEVICES,DeviceData)

	luup.log("("..PLUGIN.NAME.."::UPNP_AddDevice) CONFIGURED_DEVICES ["..print_r(CONFIGURED_DEVICES).."].",2)

	local rootPtr = luup.chdev.start(ECO_GATEWAY_DEVICE)
	local parameters
	for k,v in pairs(CONFIGURED_DEVICES) do
		luup.log("("..PLUGIN.NAME.."::UPNP_AddDevice) Adding/Updating device ["..print_r(v).."].",2)
		parameters = ECO_SID..",DeviceConfig="..json:encode(v)
		luup.log("("..PLUGIN.NAME.."::UPNP_AddDevice) Config reports        PROTOCOL ["..(v.PROTOCOL or "NIL").."] TYPE ["..(v.TYPE or "NIL").."].",2)
		if ((v.PROTOCOL == "") or (v.PROTOCOL == "ECO_SWITCH")) then
			luup.log("("..PLUGIN.NAME.."::UPNP_AddDevice)                   PROTOCOL   [ECO_SWITCH].",2)
			luup.log("("..PLUGIN.NAME.."::UPNP_AddDevice)                   devicetype [D_BinaryLight1.xml].",2)
			luup.chdev.append(
				ECO_GATEWAY_DEVICE, 
				rootPtr,
				v.ID,
				v.Name,
				nil,
				"D_BinaryLight1.xml",
				"",
				parameters,
				false
			)
		elseif (v.PROTOCOL == "SENGLED") then
			luup.log("("..PLUGIN.NAME.."::UPNP_AddDevice)                   PROTOCOL   [SENGLED].",2)
			luup.log("("..PLUGIN.NAME.."::UPNP_AddDevice)                   devicetype [D_DimmableLight1.xml].",2)
			luup.chdev.append(
				ECO_GATEWAY_DEVICE, 
				rootPtr,
				v.ID,
				v.Name,
				nil,
				"D_DimmableLight1.xml",
				"",
				parameters,
				false
			)
		elseif (v.PROTOCOL == "TPLINK") then
			luup.log("("..PLUGIN.NAME.."::UPNP_AddDevice)                   PROTOCOL   [TPLINK].",2)
			if (v.TYPE == "IOT.SMARTBULB") then
				luup.log("("..PLUGIN.NAME.."::UPNP_AddDevice)                   TYPE       [IOT.SMARTBULB].",2)
				debug("("..PLUGIN.NAME.."::UPNP_AddDevice) McGhee sysinfo.is_color: "..bool2string(toBool(v.system.get_sysinfo.is_color))..".",2)
				if (toBool(v.system.get_sysinfo.is_color)) then
					debug("("..PLUGIN.NAME.."::UPNP_AddDevice) McGhee is_color",2)
					luup.log("("..PLUGIN.NAME.."::UPNP_AddDevice)                   devicetype [D_DimmableRGBLight1.xml].",2)
					luup.chdev.append(
						ECO_GATEWAY_DEVICE, 
						rootPtr,
						v.ID,
						v.Name,
						nil,
						"D_DimmableRGBLight1.xml",
						"",
						parameters,
						false
					)
				elseif (toBool(v.system.get_sysinfo.is_variable_color_temp)) then
					debug("("..PLUGIN.NAME.."::UPNP_AddDevice) McGhee is_variable_color_temp",2)
					luup.log("("..PLUGIN.NAME.."::UPNP_AddDevice)                   devicetype [D_DimmableRGBLight2.xml].",2)
					luup.chdev.append(
						ECO_GATEWAY_DEVICE, 
						rootPtr,
						v.ID,
						v.Name,
						nil,
						"D_DimmableRGBLight2.xml",
						"",
						parameters,
						false
					)
				elseif (toBool(v.system.get_sysinfo.is_dimmable)) then
					debug("("..PLUGIN.NAME.."::UPNP_AddDevice) McGhee is_dimmable",2)
					luup.log("("..PLUGIN.NAME.."::UPNP_AddDevice)                   devicetype [D_DimmableLight1.xml].",2)
					luup.chdev.append(
						ECO_GATEWAY_DEVICE, 
						rootPtr,
						v.ID,
						v.Name,
						nil,
						"D_DimmableLight1.xml",
						"",
						parameters,
						false
					)
				else
					luup.log("("..PLUGIN.NAME.."::UPNP_AddDevice)                   devicetype [D_BinaryLight1.xml].",2)
					luup.chdev.append(
						ECO_GATEWAY_DEVICE, 
						rootPtr,
						v.ID,
						v.Name,
						nil,
						"D_BinaryLight1.xml",
						"",
						parameters,
						false
					)
				end
			else
				luup.log("("..PLUGIN.NAME.."::UPNP_AddDevice)                   TYPE       [IOT.SMARTPLUGSWITCH].",2)
				luup.log("("..PLUGIN.NAME.."::UPNP_AddDevice)                   devicetype [D_BinaryLight1.xml].",2)
				luup.chdev.append(
					ECO_GATEWAY_DEVICE, 
					rootPtr,
					v.ID,
					v.Name,
					nil,
					"D_BinaryLight1.xml",
					"",
					parameters,
					false
				)
			end
		end
	end
	luup.chdev.sync(ECO_GATEWAY_DEVICE, rootPtr)
	luup.log("("..PLUGIN.NAME.."::UPNP_AddDevice) Completed.",2)
	return 4,0
end

function UPNP_RenameDevice(lul_device,lul_settings)
	luup.log("("..PLUGIN.NAME.."::UPNP_RenameDevice) Preparing to rename device.",2)
	luup.log("("..PLUGIN.NAME.."::UPNP_RenameDevice) lul_settings ["..print_r(lul_settings).."].",2)
	local DeviceData = json:decode(lul_settings.DeviceData)
	debug("UPNP_RenameDevice - McGhee DeviceData:["..lul_settings.DeviceData.."].",2)
	
	local DeviceID = 0
	local DevName = DeviceData.Name
	local IP = DeviceData.IP
	local ID = DeviceData.ID
	local Service = lul_settings.serviceId
	debug("UPNP_RenameDevice - McGhee Service:"..(Service or 'nil')..",Name:"..DevName..",IP:"..IP..",ID:"..ID..".",2)
	for vera_id,dConfig in pairs(CONFIGURED_DEVICES) do

		luup.log("("..PLUGIN.NAME.."::RenameDevice)   inspecting device ["..(vera_id or "NIL").."].",2)
		local status
		if (((dConfig.ID ~= "") and (dConfig.ID == ID)) and
		   ((dConfig.IP ~= "") and (dConfig.IP == IP))) then
			DeviceID = vera_id
			debug("UPNP_RenameDevice - McGhee vera_id:"..DeviceID..", DeviceData:["..print_r(DeviceData).."].",2)
			luup.variable_set(Service, "DeviceConfig", lul_settings.DeviceData, DeviceID)
		end
	end
	local url = ("http://"..PLUGIN.VERA_IP..":3480/port_3480/data_request?id=device&action=rename&serviceId=urn:micasaverde-com:serviceId:HomeAutomationGateway1&device="..DeviceID.."&name="..URLEnclode(DevName))
	debug("UPNP_RenameDevice - McGhee url:"..url..".",2)

	local response, status = luup.inet.wget(url, 5, "", "")
	debug("McGhee response="..tostring(response).." status="..tostring(status),2)
	
	luup.call_action("urn:micasaverde-com:serviceId:HomeAutomationGateway1", "Reload", {}, 0)

	return 4,0
end

function UPNP_RemoveDevice(lul_device,lul_settings)
	luup.log("("..PLUGIN.NAME.."::UPNP_RemoveDevice) Preparing to remove device.",2)
	luup.log("("..PLUGIN.NAME.."::UPNP_RemoveDevice) lul_settings ["..print_r(lul_settings).."].",2)
	local DeviceData = json:decode(lul_settings.DeviceData)
	local DeviceID = tonumber(DeviceData.VERA_ID,10)
	luup.call_action("urn:micasaverde-com:serviceId:HomeAutomationGateway1", "DeleteDevice", {DeviceNum = DeviceID}, 0)
	luup.call_action("urn:micasaverde-com:serviceId:HomeAutomationGateway1", "Reload", {}, 0)
	return 4,0
end

function UPNP_SetColorRGB(lul_device,lul_settings)
	if (lul_settings and lul_settings.DeviceNum) then
		lul_device = tonumber(lul_settings.DeviceNum)
	end
	local deviceConfig = json:decode(luup.variable_get(ECO_SID,"DeviceConfig",lul_device))
	if (deviceConfig == nil) then
		luup.log("("..PLUGIN.NAME.."::ACTION::SetColorRGB) DEVICE not configured")
		return 2,nil
	end
	deviceConfig.VERA_ID = lul_device
	if ((deviceConfig.IP == nil) or (deviceConfig.IP == "")) then
		luup.log("("..PLUGIN.NAME.."::ACTION::SetColorRGB) IP ADDRESS not configured")
		return 2,nil
	end
	local TARGETval = lul_settings.newColorRGBTarget
	luup.log("("..PLUGIN.NAME.."::ACTION::SetColorRGB) Setting device color to ["..(TARGETval or "NIL").."]")
	-- luup.variable_set(SWITCH_SID, "Target", lul_settings.newTargetValue, lul_device)
	local resp
	if ((deviceConfig.PROTOCOL == "") or(deviceConfig.PROTOCOL == "ECO_SWITCH")) then
		luup.log("("..PLUGIN.NAME.."::ACTION::SetColorRGB) ECO Switch devices are not Color capable devices.",1)
		return 2,nil
	elseif (deviceConfig.PROTOCOL == "TPLINK") then
		if (toBool(deviceConfig.system.get_sysinfo.is_color)) then
			resp = TPLINK:setColorRGB(deviceConfig, TARGETval)
		else
			luup.log("("..PLUGIN.NAME.."::ACTION::SetColorRGB) Device is not Color capable.\ndevice: "..print_r(deviceConfig),1)
			return 2,nil
		end
	elseif (deviceConfig.PROTOCOL == "SENGLED") then
		luup.log("("..PLUGIN.NAME.."::ACTION::SetColorRGB) SengLED Boost are not Color capable devices.",1)
		return 2,nil
	end
	if (resp ~= nil) then
		luup.variable_set(COLOR_SID, "CurrentColor", resp.current_color, lul_device)
		luup.variable_set(DIMMER_SID, "LoadLevelStatus", resp.brightness, lul_device)
		luup.log("("..PLUGIN.NAME.."::ACTION::SetColorRGB) Set Color Temperature to "..(resp.color_temp or "NIL").."]")
	else
		luup.log("("..PLUGIN.NAME.."::ACTION::SetColorRGB) ERROR: Color Temperature change not verified for device ["..(deviceConfig.ID).."]")
		return 2,nil
	end
	return 4,nil
end
    
function UPNP_SetColor(lul_device,lul_settings)
	if (lul_settings and lul_settings.DeviceNum) then
		lul_device = tonumber(lul_settings.DeviceNum)
	end
	local deviceConfig = json:decode(luup.variable_get(ECO_SID,"DeviceConfig",lul_device))
	if (deviceConfig == nil) then
		luup.log("("..PLUGIN.NAME.."::ACTION::SetColor) DEVICE not configured")
		return 2,nil
	end
	deviceConfig.VERA_ID = lul_device
	if ((deviceConfig.IP == nil) or (deviceConfig.IP == "")) then
		luup.log("("..PLUGIN.NAME.."::ACTION::SetColor) IP ADDRESS not configured")
		return 2,nil
	end
	local TARGETval = lul_settings.newColorTarget
	luup.log("("..PLUGIN.NAME.."::ACTION::SetColor) Setting device color to ["..(TARGETval or "NIL").."]")
	-- luup.variable_set(SWITCH_SID, "Target", lul_settings.newTargetValue, lul_device)
	local resp
	if ((deviceConfig.PROTOCOL == "") or(deviceConfig.PROTOCOL == "ECO_SWITCH")) then
		luup.log("("..PLUGIN.NAME.."::ACTION::SetColor) ECO Switch devices are not Color Temperature capable devices.",1)
		return 2,nil
	elseif (deviceConfig.PROTOCOL == "TPLINK") then
		if ((toBool(deviceConfig.is_tunable)) or (toBool(deviceConfig.system.get_sysinfo.is_variable_color_temp))) then
			resp = TPLINK:setColor(deviceConfig, TARGETval)
		else
			luup.log("("..PLUGIN.NAME.."::ACTION::SetColor) Device is not Color Temperature capable.\ndevice: "..print_r(deviceConfig),1)
			return 2,nil
		end
	elseif (deviceConfig.PROTOCOL == "SENGLED") then
		luup.log("("..PLUGIN.NAME.."::ACTION::SetColor) SengLED Boost are not Color Temperature capable devices.",1)
		return 2,nil
	end
	if (resp ~= nil) then
		luup.log("("..PLUGIN.NAME.."::ACTION::SetColor) Set Color Temperature to "..(resp.color_temp or "NIL").."]")
		luup.variable_set(COLOR_SID, "CurrentColor", resp.color_temp, lul_device)
	else
		luup.log("("..PLUGIN.NAME.."::ACTION::SetColor) ERROR: Color Temperature change not verified for device ["..(deviceConfig.ID).."]")
		return 2,nil
	end
	return 4,nil
end

function UPNP_SetColorTemp(lul_device,lul_settings)
	luup.log("("..PLUGIN.NAME.."::ACTION::SetColorTemp) McGhee ")
	if (lul_settings and lul_settings.DeviceNum) then
		lul_device = tonumber(lul_settings.DeviceNum)
	end
	local deviceConfig = json:decode(luup.variable_get(ECO_SID,"DeviceConfig",lul_device))
	if (deviceConfig == nil) then
		luup.log("("..PLUGIN.NAME.."::ACTION::SetColorTemp) DEVICE not configured")
		return 2,nil
	end
	luup.log("("..PLUGIN.NAME.."::ACTION::SetColorTemp) McGhee deviceConfig: ["..(print_r(deviceConfig)).."]")
	deviceConfig.VERA_ID = lul_device
	if ((deviceConfig.IP == nil) or (deviceConfig.IP == "")) then
		luup.log("("..PLUGIN.NAME.."::ACTION::SetColorTemp) IP ADDRESS not configured")
		return 2,nil
	end
	local TARGETval = lul_settings.newColorTempTarget
	luup.log("("..PLUGIN.NAME.."::ACTION::SetColorTemp) Setting device color to ["..(TARGETval or "NIL").."]")
	-- luup.variable_set(SWITCH_SID, "Target", lul_settings.newTargetValue, lul_device)
	local resp
	if ((deviceConfig.PROTOCOL == "") or(deviceConfig.PROTOCOL == "ECO_SWITCH")) then
		luup.log("("..PLUGIN.NAME.."::ACTION::SetColorTemp) ECO Switch devices are not Color Temperature capable devices.",1)
		return 2,nil
	elseif (deviceConfig.PROTOCOL == "TPLINK") then
		if ((toBool(deviceConfig.is_tunable)) or (toBool(deviceConfig.system.get_sysinfo.is_variable_color_temp))) then
			resp = TPLINK:setColorTemp(deviceConfig, TARGETval)
		else
			luup.log("("..PLUGIN.NAME.."::ACTION::SetColorTemp) Device is not Color Temperature capable.\ndevice: "..print_r(deviceConfig),1)
			return 2,nil
		end
	elseif (deviceConfig.PROTOCOL == "SENGLED") then
		luup.log("("..PLUGIN.NAME.."::ACTION::SetColorTemp) SengLED Boost are not Color Temperature capable devices.",1)
		return 2,nil
	end
	if (resp ~= nil) then
		luup.log("("..PLUGIN.NAME.."::ACTION::SetColorTemp) Set Color Temperature to "..(resp.color_temp or "NIL").."]")
		luup.variable_set(COLOR_SID, "SetColorTemp", resp.color_temp, lul_device)
	else
		luup.log("("..PLUGIN.NAME.."::ACTION::SetColorTemp) ERROR: Color Temperature change not verified for device ["..(deviceConfig.ID).."]")
		return 2,nil
	end
	return 4,nil
end
    
function UPNP_SetTarget(lul_device,lul_settings)
	luup.log("("..PLUGIN.NAME.."::ACTION::SetTarget) DEVICE ["..(lul_device or "NIL").."] SETTINGS: "..print_r(lul_settings))
	if (lul_settings and lul_settings.DeviceNum) then
		lul_device = tonumber(lul_settings.DeviceNum)
	end
	local deviceConfig = json:decode(luup.variable_get(ECO_SID,"DeviceConfig",lul_device))
	if (deviceConfig == nil) then
		luup.log("("..PLUGIN.NAME.."::ACTION::SetTarget) DEVICE not configured")
		return 2,nil
	end
	deviceConfig.VERA_ID = lul_device
	if ((deviceConfig.IP == nil) or (deviceConfig.IP == "")) then
		luup.log("("..PLUGIN.NAME.."::ACTION::SetTarget) IP ADDRESS not configured")
		return 2,nil
	end
	local TARGETval = (tonumber(lul_settings.newTargetValue,10) == 1) and true or false
	luup.log("("..PLUGIN.NAME.."::ACTION::SetTarget) Setting device state to ["..(TARGETval and "ON" or "OFF").."]")
	luup.variable_set(SWITCH_SID, "Target", lul_settings.newTargetValue, lul_device)
	local resp
	if ((deviceConfig.PROTOCOL == "") or(deviceConfig.PROTOCOL == "ECO_SWITCH")) then
		resp = EcoSwitch:setTarget(deviceConfig, TARGETval)
	elseif (deviceConfig.PROTOCOL == "TPLINK") then
		resp = TPLINK:setTarget(deviceConfig, TARGETval)
	elseif (deviceConfig.PROTOCOL == "SENGLED") then
		resp = SENGLED:setTarget(deviceConfig, TARGETval)
	end
	if (resp ~= nil) then
		luup.log("("..PLUGIN.NAME.."::ACTION::SetTarget) Set state to "..(resp.powered and "ON" or "OFF").."]")
		luup.variable_set(SWITCH_SID, "Status", (resp.powered and 1 or 0), lul_device)
		luup.variable_set(DIMMER_SID, "LoadLevelStatus", resp.powered and resp.brightness or 0, lul_device)
	else
		luup.log("("..PLUGIN.NAME.."::ACTION::SetTarget) ERROR: State not set for device ["..(deviceConfig.ID).."]")
		return 2,nil
	end
	return 4,nil
end
    

function UPNP_GetStatus(lul_device,lul_settings)
	if (lul_settings and lul_settings.DeviceNum) then
		lul_device = tonumber(lul_settings.DeviceNum)
	end
	local deviceConfig = json:decode(luup.variable_get(ECO_SID,"DeviceConfig",lul_device))
	if (deviceConfig == nil) then
		luup.log("("..PLUGIN.NAME.."::ACTION::GetStatus) DEVICE not configured")
		return 2,nil
	end
	deviceConfig.VERA_ID = lul_device
	if ((deviceConfig.IP == nil) or (deviceConfig.IP == "")) then
		luup.log("("..PLUGIN.NAME.."::ACTION::GetStatus) IP ADDRESS not configured")
		return 2,nil
	end
	luup.log("("..PLUGIN.NAME.."::ACTION::GetStatus) Getting device state")
	local resp
	if ((deviceConfig.PROTOCOL == "") or(deviceConfig.PROTOCOL == "ECO_SWITCH")) then
		resp = EcoSwitch:getStatus(deviceConfig)
	elseif (deviceConfig.PROTOCOL == "TPLINK") then
		resp = TPLINK:getStatus(deviceConfig)
	elseif (deviceConfig.PROTOCOL == "SENGLED") then
		resp = SENGLED:getStatus(deviceConfig)
	end
	if (resp ~= nil) then
		luup.variable_set(SWITCH_SID, "Status", (resp.powered and 1 or 0), lul_device)
		luup.log("("..PLUGIN.NAME.."::ACTION::GetStatus) Device state is "..(resp and "ON" or "OFF").."]")
	else
		luup.log("("..PLUGIN.NAME.."::ACTION::GetStatus) Device state not returned for switch ["..(deviceConfig.ID).."]")
	end
	return 4,nil
end

function UPNP_SetLoadLevelTarget(lul_device,lul_settings)
	luup.log("("..PLUGIN.NAME.."::ACTION::SetLoadLevelTarget) CALLED - settings\n"..print_r(lul_settings))
	if (lul_settings and lul_settings.DeviceNum) then
		lul_device = tonumber(lul_settings.DeviceNum)
	end
	local deviceConfig = json:decode(luup.variable_get(ECO_SID,"DeviceConfig",lul_device))
	if (deviceConfig == nil) then
		luup.log("("..PLUGIN.NAME.."::ACTION::SetLoadLevelTarget) DEVICE not configured")
		return 2,nil
	end
	deviceConfig.VERA_ID = lul_device
	if ((deviceConfig.IP == nil) or (deviceConfig.IP == "")) then
		luup.log("("..PLUGIN.NAME.."::ACTION::SetLoadLevelTarget) IP ADDRESS not configured")
		return 2,nil
	end
	local TARGETval = tonumber(lul_settings.newLoadlevelTarget,10)
	luup.log("("..PLUGIN.NAME.."::ACTION::SetLoadLevelTarget) Setting device LoadLevelTarget to ["..TARGETval.."]")
	luup.variable_set(DIMMER_SID, "LoadLevelTarget", TARGETval, lul_device)
	local resp
	if ((deviceConfig.PROTOCOL == "") or(deviceConfig.PROTOCOL == "ECO_SWITCH")) then
		luup.log("("..PLUGIN.NAME.."::ACTION::SetLoadLevelTarget) ECO Switches are not dimming capable.",1)
		return 2,nil
	elseif (deviceConfig.PROTOCOL == "TPLINK") then
		debug("("..PLUGIN.NAME.."::ACTION::SetLoadLevelTarget) McGhee type: ["..deviceConfig.TYPE.."]")
		if (deviceConfig.TYPE ~= "IOT.SMARTBULB") then
			luup.log("("..PLUGIN.NAME.."::ACTION::SetLoadLevelTarget) TPLINK Switches are not dimming capable.",1)
			return 2,nil
		else
			resp = TPLINK:setLoadLevelTarget(deviceConfig, TARGETval)
		end
	elseif (deviceConfig.PROTOCOL == "SENGLED") then
		resp = SENGLED:setLoadLevelTarget(deviceConfig, TARGETval)
	end
	if (resp ~= nil) then
		luup.log("("..PLUGIN.NAME.."::ACTION::SetLoadLevelTarget) RESP - status\n"..print_r(resp))
		luup.variable_set(SWITCH_SID, "Status", (resp.powered and 1 or 0), lul_device)
--		luup.variable_set(SWITCH_SID, "Status", resp.powered, lul_device)
		luup.variable_set(DIMMER_SID, "LoadLevelStatus", resp.powered and resp.brightness or 0, lul_device)
		luup.log("("..PLUGIN.NAME.."::ACTION::SetTarget) Set LoadLevelTarget to "..(resp.powered and resp.brightness or 0).."]")
	else
		luup.log("("..PLUGIN.NAME.."::ACTION::SetTarget) ERROR: LoadLevelTarget not set for device ["..(deviceConfig.ID).."]")
		return 2,nil
	end
	return 4,nil
end
    
-- scan the vera devices for installed plugin devices (Children of ECO_GATEWAY_DEVICE)
-- Build the CONFIGURED_DEVICES table
function findChildDevices()
	CONFIGURED_DEVICES = {}
	log("("..PLUGIN.NAME.."::findChildDevices): Processing child devices.",2)
	-- mark installed devices in the VeraDevices table
	for VeraID,CurDev in pairs(luup.devices) do
		debug("("..PLUGIN.NAME.."::findChildDevices): testing device [\r\n"..(VeraID or "NIL").." - "..print_r(CurDev).."\r\n].")
		if (CurDev.device_num_parent == ECO_GATEWAY_DEVICE) then
			-- this is one of our devices
			local devID = CurDev.id
			debug("("..PLUGIN.NAME.."::findChildDevices): Found Device ID ["..(devID or "NIL").."] VeraID ["..(VeraID or "NIL").."].")
			-- find the corresponding device in the VeraDevices table
			if ((devID ~= nil) and (devID ~= "")) then
				local dConfig = luup.variable_get(ECO_SID,"DeviceConfig",VeraID)
				CONFIGURED_DEVICES[VeraID] = json:decode(dConfig)
				CONFIGURED_DEVICES[VeraID].VERA_ID = VeraID
				CONFIGURED_DEVICES[VeraID].Name = CurDev.description
			end
		end
	end
end

function initChild(vera_id)
	luup.log("("..PLUGIN.NAME.."::initChild) Initializing child device...")
	-- initialize sane values if not already set
	local target = luup.variable_get(SWITCH_SID,"Target", vera_id)
	if target == nil then
		luup.variable_set(SWITCH_SID,"Target","0",vera_id)
	end
	local status = luup.variable_get(SWITCH_SID,"Status", vera_id)
	if status == nil then
		luup.variable_set(SWITCH_SID,"Status","0",vera_id)
	end

	local devConfig = CONFIGURED_DEVICES[vera_id]

	if (devConfig and devConfig.ID and devConfig.IP) then
		luup.log("("..PLUGIN.NAME.."::initChild) Switch ID ["..(devConfig.ID or "NIL").."].")
		-- set initial status and start the poll process
		local status
		if ((devConfig.PROTOCOL == "") or (devConfig.PROTOCOL == "ECO_SWITCH")) then
			status = EcoSwitch:getStatus(devConfig)
		elseif (devConfig.PROTOCOL == "TPLINK") then
			status = TPLINK:getStatus(devConfig)
		elseif (devConfig.PROTOCOL == "SENGLED") then
			status = SENGLED:getStatus(devConfig)
		end
		if (status ~= nil) then
			luup.variable_set(SWITCH_SID,"Status",(status.powered and 1 or 0),vera_id)
			if (status.brightness) then
				luup.variable_set(DIMMER_SID,"LoadLevelStatus",(status.powered and status.brightness or 0),vera_id)
			end
			set_failure(0, vera_id)
			luup.log("("..PLUGIN.NAME.."::initChild) retrieved initial device status.",2)
			return true
		else
			set_failure(1, vera_id)
			luup.log("("..PLUGIN.NAME.."::initChild) Failed to retreive initial device status.",1)
			return false
		end
	else
		set_failure(1, vera_id)
		luup.log("("..PLUGIN.NAME.."::initChild) InitChild failed.",1)
		return false
	end
end

function DoDiscovery()
	local _,ALL_DEVICES = EcoSwitch:DoDiscovery()
	local _,DISCOVERED_TPLINK_DEVICES = TPLINK:DoDiscovery()
	local _,DISCOVERED_SENGLED_DEVICES = SENGLED:DoDiscovery()
	for _,device in pairs(DISCOVERED_TPLINK_DEVICES) do
		table.insertSet(ALL_DEVICES,device)
	end
	for _,device in pairs(DISCOVERED_SENGLED_DEVICES) do
		table.insertSet(ALL_DEVICES,device)
	end
	return true,ALL_DEVICES
end

function getVeraIP()
	local VeraIP = shellExecute("get_unit_info.sh | cut -d';' -f2")
	VeraIP = VeraIP:gsub("\r",""):gsub("\n","")
	PLUGIN.VERA_IP = VeraIP
end

function init(lul_device)
	luup.log("("..PLUGIN.NAME.."::Init) Starting...")
	ECO_GATEWAY_DEVICE = lul_device
	getMiosVersion()
	getVeraIP()
	ICONS:CreateIcons()
	ICONS = nil
	luup.variable_set(ECO_SID,"PLUGIN_VERSION",version,ECO_GATEWAY_DEVICE)
	-- get the available devices
	PLUGIN.PollPeriod = luup.variable_get(ECO_SID,"PollPeriod",ECO_GATEWAY_DEVICE)
	PLUGIN.PollPeriod = tonumber(PLUGIN.PollPeriod,10) or 60
	luup.variable_set(ECO_SID,"PollPeriod",PLUGIN.PollPeriod,ECO_GATEWAY_DEVICE)
	
	_,DISCOVERED_DEVICES = DoDiscovery()
	-- get the configured devices
	findChildDevices()

	log("("..PLUGIN.NAME.."::init) Configured ["..print_r(CONFIGURED_DEVICES).."]",2)

	luup.variable_set(ECO_SID,"CONFIGURED_DEVICES",json:encode(CONFIGURED_DEVICES),ECO_GATEWAY_DEVICE)
	luup.variable_set(ECO_SID,"DISCOVERED_DEVICES",json:encode(DISCOVERED_DEVICES),ECO_GATEWAY_DEVICE)

	-- mark configured devices that are not discovered as not available - set initial state of discovered devices
	for vera_id,dConfig in pairs(CONFIGURED_DEVICES) do
		if ((dConfig.ID ~= nil) and (dConfig.ID ~= "")) then
			local dDevFound = false
			for _,discDev in pairs(DISCOVERED_DEVICES) do
				if (dConfig.ID == discDev.ID) then dDevFound = true end
			end
			if (dDevFound) then
				set_failure(0,vera_id)
				initChild(vera_id)
			else
				set_failure(1,vera_id)
				luup.log("("..PLUGIN.NAME.."::init) Setting *FAILURE* for device"..(vera_id or "NIL")..".",2)
			end
		end
	end
	luup.call_delay("PollSwitchs",PLUGIN.PollPeriod,"")
	return true, "Started", "ECO_Switch"
end
