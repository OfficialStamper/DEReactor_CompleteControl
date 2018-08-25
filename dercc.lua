--dercc (Draconic Evolution Reactor Complete Control) V1.1
--Official Stamper (c) Aug 2018

--Changelog V1.0.1 added maxFuel = 10368 to use as factor in getOutFlux function
--          V1.0.2 added tempDrainFactor to info. and fuelUseRate to getOutFlux, but made no difference to low fuel calcs :(
--          V1.1.0 added OpenComputers layer

-- *** REQUIRED *** --
local modemTx = 21				-- Must be a unique channel not used by any other computer on the server and MUST be the same as the reactor modem channel(s)
local modemRx = 21				-- Must be a unique channel not used by any other computer on the server and MUST be the same as the reactor modem channel(s)

-- *** REQUIRED FOR COMPUTERCRAFT *** --
local modemSide = 'back'
local monitorSide = 'top'
local inFluxSide = 'right'                                   -- required for CC (ComputerCraft) only, Side of the Flux Gate used as Input into the reactor to power the Containment Field and warm up the reactor
local outFluxSide = 'left'                                   -- required for CC (ComputerCraft) only, Side of the Flux Gate used as Output of RF from reactor into your RF Storeage solution

-- *** REQUIRED FOR OPENCOMPUTERS *** --
local inFluxAddr = 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'    -- required for OC (OpenComputers) only, Address of the Flux Gate used as Input into the reactor to power the Containment Field and warm up the reactor
local outFluxAddr = 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx'   -- required for OC (OpenComputers) only, Address of the Flux Gate used as Output of RF from reactor into your RF Storage solution

-- *** STARTUP VALUES *** --
local reqTemp = 6000      									 -- Default starting required temperature (this is used if error caused reboot or server restarts)
local reqField = 10       									 -- Default starting required field (this is used if error caused reboot or server restarts)    

-- Recommended no other values below are changed
-- Debug only
local skip = 0

-- Startup Values
local waitTime = 0.15       -- time/ticks between event operations (0.05 = 1 tick @ 20TPS) - time to wait for modem to respond, recommended value 0.10
local minTemp = 2500		-- minimum temperature allowed (also used for fail-safe, do not change)
local maxTemp = 8000		-- maximum temperature allowed
local cutoffTemp = 8100		-- shutdown reactor if temp exceeds this value
local warmUpRF = 20000000   -- how much RF/t to inject to warm reactor up to get to over 2000C
local minField = 1			-- minimum field percentage allowed
local maxField = 90			-- maximum field percentaged allowed
local inFluxRF = 0      	-- default value for offline, cooling or cold
local outFluxRF = 20     	-- default value for offline, cooling or cold
local graphLen = 44			-- width graphs will take on screen
local screenWidth = 50      -- width of screen
	
-- Tweaks
local outTrimPct = 1        -- 2 = 200%, 1 = 100%, 0.5 = 50%	the percentage of the genRate difference to trim the outFluxRF
	
-- other variable initialisation (do not change these values as declare and/or constants only)
local info = {}					-- table for holding reactor.info
local debugMode = false     	-- flag used to indicate if the monitor is on the debug screen or normal screen array
local msg = ''					-- for sending adhoc messages to screen
local timerId = 0           	-- event timer
local oc_id = 0                 -- because OpenComputers timer Id's do not work
local maxId = 65535         	-- maximun number that can be sent as a modem id
local maxFuel = 10368       	-- maximum possible fuel
local maxInteger = 2147483647 	-- maximun integer allowed (math.maxInteger doesn't seem to work here)

--Peripherals and components (do not initialise to values)
local monitor
local modem 
local outFlux = {}
local inFlux = {} 
local serialization
local fileIO

--check os version
local OSVer = ""
local OC = false
local CC = false

if _OSVERSION then
	OSVer = _OSVERSION
	OC = true
elseif os.version() then
	OSVer = os.version()
	CC = true
else
	print("OS not supported!")
	return
end

print("OSVer: "..OSVer)
print("OpenComputers: "..tostring(OC))
print("ComputerCraft: "..tostring(CC))

--ComputerCraft - wrap the peripherals
if CC then
	fileIO = fs
	monitor = peripheral.wrap(monitorSide)
	modem = peripheral.wrap(modemSide)
	if not modem then print("No modem found, please attach an 'Ender Modem'"); return; end
	outFlux = peripheral.wrap(outFluxSide)
	if not outFlux then print("No Flux Gate found for side '"..outFluxSide.."', please attach a Flux Gate"); return; end
	inFlux = peripheral.wrap(inFluxSide)
	if not inFlux then print("No Flux Gate found for side '"..inFluxSide.."', please attach a Flux Gate"); return; end
	print('inFlux='..inFluxSide)
	print('outFlux='..outFluxSide)
end

--OpenComputers - Override ComputerCraft API's to make compatable with OpenComputers
if OC then
	local component = require("component")
	local computer = require("computer")
	local event = require("event")
	local term = require("term")
	fileIO = require("filesystem")
	serialization = require("serialization")
	
	--GPU check
	if not component.gpu or component.gpu.getDepth() ~= 8 then 
		print("No GPU or incorrect Tier GPU present, please install Graphics Card (Tier 3)")
		os.exit()
	end
	local gpu = component.gpu
	
	--Modem Check
	if not component.modem or not component.modem.isWireless() then 
		print("No wireless modem present, please install Wireless Network Card (Tier 2)")
		os.exit()
	end
	modem = component.modem

	--Flux gate checks
	for i, v in pairs(component.list("flux_gate")) do
		print("Found: "..v.." : "..i)
		if i == inFluxAddr then inFlux = component.proxy(inFluxAddr) end
		if i == outFluxAddr then outFlux = component.proxy(outFluxAddr) end
	end
	if not inFlux.address or not outFlux.address then
		print("Flux Gate(s) are not present or incorrect address specified, please check flux gates and address(s) specified")
		print("inFluxAddr: "..inFluxAddr.." Found: "..tostring(inFlux.address))
		print("outFluxAddr: "..outFluxAddr.." Found: "..tostring(outFlux.address))
		os.exit()
	end

	-- Overrides
	modem.transmit = modem.broadcast
	colors = {
		white		=0xF0F0F0,
		orange		=0xF2B233,
		magenta		=0xE57FD8,
		lightBlue	=0x99B2F2,
		yellow		=0xDEDE6C,
		lime		=0x7FCC19,
		pink		=0xF2B2CC,
		gray		=0x4C4C4C,
		lightGray	=0x999999,
		cyan		=0x4C99B2,
		purple		=0xB266E5,
		blue		=0x3366CC,
		brown		=0x7F664C,
		green		=0x57A64E,
		red			=0xCC4C4C,
		black		=0x191919,
		['0']		=0xF0F0F0,
		['1']		=0xF2B233,
		['2']		=0xE57FD8,
		['3']		=0x99B2F2,
		['4']		=0xDEDE6C,
		['5']		=0x7FCC19,
		['6']		=0xF2B2CC,
		['7']		=0x4C4C4C,
		['8']		=0x999999,
		['9']		=0x4C99B2,
		a			=0xB266E5,
		b			=0x3366CC,
		c			=0x7F664C,
		d			=0x57A64E,
		e			=0xCC4C4C,
		f			=0x191919
	}
	monitor = {
		setResolution		= function(inX, inY)    gpu.setResolution(inX, inY) end,
		resetResolution     = function() 			local rx, ry = gpu.maxResolution(); gpu.setResolution(rx, ry) end,
		setBackgroundColor  = function(inCol) 		gpu.setBackground(inCol) end,
		setTextColor        = function(inCol) 		gpu.setForeground(inCol) end,
		setCursorPos	    = function(inX, inY) 	term.setCursor(inX, inY) end,
		write               = function(inStr) 		term.write(inStr, false) end,
		blit				= function(inStr, fCol, bCol) 	
									local _f = string.sub(fCol, 1, 1)
									local _b = string.sub(bCol, 1, 1)
									local _p = 1
									local _l = string.len(inStr)
									for i = 1, _l do
										if string.sub(fCol, i, i) ~= _f or string.sub(bCol, i, i) ~= _b or i == _l then
											gpu.setBackground(colors[_b])
											gpu.setForeground(colors[_f])
											term.write(string.sub(inStr, _p, i - 1 + ((i == _l) and 1 or 0)))
											_f = string.sub(fCol, i, i)
											_b = string.sub(bCol, i, i)
											_p = i
										end
									end
								end,
		clear				= function() 					term.clear() end
	}
	os.getComputerID = computer.address
	os.pullEvent = event.pull
	os.queueEvent = event.push

	local function ocTimer() 
		event.push('timer', timerId)
	end

	os.startTimer =	function(inWaitTime) 
						--OpenComputers does not return a unique Event Id, so have to manage our own
						local _id = timerId + 1
						if _id >= maxInteger - 1 then _id = 1 end
						oc_id = event.timer(inWaitTime, ocTimer)
						return _id 
					end
	os.cancelTimer = function()
						event.cancel(oc_id)
					 end
	os.reboot = function()
						computer.shutdown(true)
					end
	
end

local function modTemp(val)
	reqTemp = reqTemp + val
	if reqTemp > maxTemp then reqTemp = maxTemp end
	if reqTemp < minTemp then reqTemp = minTemp end
end

local function modField(val)
	reqField = reqField + val
	if reqField > maxField then reqField = maxField end
	if reqField < minField then reqField = minField end
end

local state = {
	active 		= "active",
	disabled 	= "disabled",
	enabled 	= "enabled",
	off 		= "off"
}

local buttonColors = {
	active 		= function() 
						monitor.setBackgroundColor(colors.green)
						monitor.setTextColor(colors.white)
					end,
	disabled 	= function() 
						monitor.setBackgroundColor(colors.gray)
						monitor.setTextColor(colors.black)
					end,
	enabled 	= function() 
						monitor.setBackgroundColor(colors.lightGray)
						monitor.setTextColor(colors.white)
					end,
	off 		= function() 
						monitor.setBackgroundColor(colors.black)
						monitor.setTextColor(colors.lightGray)
					end
}

local buttonType = {
	label = {
		id = 'label',
		setColors = function() 
				monitor.setBackgroundColor(colors.black) 
				monitor.setTextColor(colors.white) 
			end
		},
	button = {
		id = 'button',
		setColors = function(inState) 
				buttonColors[inState]() 
			end
		},
	val1 = {
		id = 'val1',
		setColors = function() 
				monitor.setBackgroundColor(colors.gray) 
				monitor.setTextColor(colors.white) 
			end
		},
	val10 = {
		id = 'val10',
		setColors = function() 
				monitor.setBackgroundColor(colors.lightGray)
				monitor.setTextColor(colors.white) 
			end
		}
}

local function printStatic(inTable)
	monitor.clear()
	monitor.setBackgroundColor(inTable.bCol)
	monitor.setTextColor(inTable.fCol)
	for i, v in pairs(inTable.array) do
		monitor.setCursorPos(1, i)
		monitor.write(v)
	end
	monitor.setCursorPos(1,2)       --display any std out on line 2
end

local function printUpdates(inTable)
	for i, v in pairs(inTable) do
		monitor.setCursorPos(v.x, v.y)
		if v.blit then
			monitor.blit(v.txt(), v.fCol(), v.bCol())
		else
			if v.bCol then monitor.setBackgroundColor(v.bCol()) end
			if v.fCol then monitor.setTextColor(v.fCol()) end
			monitor.write(v.txt())
		end
	end
	monitor.setCursorPos(1,2)       --display any std out on line 2
end

local function printButtons(inTable)
	for n, b in pairs(inTable) do
		if b.depressed then
			monitor.setBackgroundColor(colors.green)
			monitor.setTextColor(colors.red)
			b.depressed = b.depressed - 1
			if b.depressed == 0 then b.depressed = nil; end
		else
			buttonType[b.type].setColors(b.state)
		end
		monitor.setCursorPos(b.x,b.y)
		monitor.write(b.txt)
	end
	monitor.setCursorPos(1,2)       --display any std out on line 2
end

local infoStatus = {
	['cold'] 		= function() return colors.lightBlue; end,
	['running']		= function() return colors.green; end,
	['stopping'] 	= function() return colors.yellow; end,
	['warming_up']  = function() return colors.yellow; end,
	['beyond_hope'] = function() return colors.red; end,
	['cooling'] 	= function() return colors.orange; end
}

local function callReactor(request)
	if request == 'getReactorInfo' then
		timerId = os.startTimer(waitTime)
	end
	local int, _ = math.modf(timerId / maxId)
	local _id = timerId - (maxId * int)
	-- Transmit variables for use by a.n.other computer sniffing the wifi to monitor taffic and/or reactor(s)
	local tRequest = {req = request, inRF = inFluxRF, outRF = outFluxRF, reqTemp = reqTemp, reqField = reqField}
	if OC then tRequest = serialization.serialize(tRequest) end  --stupid OpenComputers can't handle tables, have to serialize
	modem.transmit(modemTx, _id, tRequest) 
end

local function getInFlux()
	-- Field(shield) Calculation
	local reqFieldStrength = (info.maxFieldStrength / 100) * reqField

	if info.temperature > 8000 then
		info.tempDrainFactor = 1 + ((info.temperature - 8000)^2 * 0.0000025)
	elseif info.temperature > 2000 then
		info.tempDrainFactor = 1
	elseif info.temperature > 1000 then
		info.tempDrainFactor = (info.temperature - 1000) / 1000
	else
		info.tempDrainFactor = 0
	end

	--fieldDrainRate calculation needs to be calculated on startup, else we can use info.fieldDrainRate	
	if not info.fieldDrainRate or info.fieldDrainRate == 0 then
		local baseMaxRFt = (3 * info.maxEnergySaturation) / 2000 -- converted for integer maths
		local drainMax = math.max(0.01, (1 - info.satPct))
		info.fieldDrainRate = math.ceil(math.min(info.tempDrainFactor * drainMax * (baseMaxRFt / 10.923556), maxInteger))  -- 2147483647 = math.maxinteger which doesnt work here :(
	else
		--info.fieldDrainRate = info.fieldDrainRate
	end
	
	--fieldCharge calculation based on the required field strength
	local fieldNegPercent = 1 - (reqFieldStrength / info.maxFieldStrength)
	local fieldInputRate = info.fieldDrainRate / fieldNegPercent
	info.fieldCharge = reqFieldStrength - math.min(info.fieldDrainRate , reqFieldStrength)

	-- injectEnergy  (happens after update)
    local tempFactor = 1
    if info.temperature > 15000 then
      tempFactor = 1 - math.min(1, (info.temperature - 15000) / 10000)
    end

	local rf = inFluxRF
	if inFluxRF == 0 then rf = 1 end
	
	info.fieldCharge = info.fieldCharge + math.min(rf * (1 - (info.fieldCharge / info.maxFieldStrength)) , info.maxFieldStrength - info.fieldCharge) * tempFactor
	info.reqInDiff = reqFieldStrength - info.fieldCharge
	local inFlux = rf + ((info.maxFieldStrength * info.reqInDiff) / (info.maxFieldStrength - info.fieldCharge))

	--to speed things up, subtract the current field from the reqField and add the difference to the rf (divided by 10)
	inFlux = inFlux + ((reqFieldStrength - info.fieldStrength) / 10)

	if inFlux < 0 then inFlux = 0 end
	
	return inFlux

end

local function getRiseAmt()
	-- Calculate the current resist and expo(nential)
	local t50 = info.temperature / 10000 * 50
	local tResist = (t50^4) / (100 - t50)
	local tfResist = ((1.3 * info.fuelPct * tResist) + (1300 * info.fuelPct) - (1.3 * tResist) - 300) / 10000
	local negCSat = (1 - info.satPct) * 99
	local tExpo = (((negCSat^3) / (100 - negCSat)) + 444.7) / 10000
	local tRiseAmt = (tfResist + tExpo) * 100 --correct format for display on debug screen 
	
	return tRiseAmt
	
end

local function getOutFlux()
	--fuel use rate
	if info.fuelPct > 0 then
		local fuelUseRate = info.tempDrainFactor * (1 - info.satPct) * 0.001
		info.fuelPct = (info.fuelConversion + fuelUseRate) / info.maxFuelConversion
	end

	-- RF out calculation
	info.outDiff = reqTemp - info.temperature
	--calculate the required resist
	local reqTResist = -(reqTemp^4 / (8000000 * (reqTemp - 20000)))
	local reqResist = ((1.3 * info.fuelPct * reqTResist) + (1300 * info.fuelPct) - (1.3 * reqTResist) - 300) / 10000
	-- The required Expo will be a reversed sign of reqResist
	local reqExpo = ((reqResist * -1) * 10000) - 444.7  
	local _E = reqExpo
	--reverse the expo to get the expected required saturation%
	local revNegCSat =(((math.sqrt(3)*(math.sqrt((_E^3)+(67500*(_E^2)))))+(450*_E))^(1/3))/(3^(2/3))-(_E/((3^(1/3))*(((math.sqrt(3)*(math.sqrt((_E^3)+(67500*(_E^2)))))+(450*_E))^(1/3))))
	--calculate the required genRate
	info.reqGenRate = (revNegCSat / 99) * (((info.maxEnergySaturation / 1000) * 1.5) * (1 + (((info.fuelPct * 1.3) - 0.3) * 2)))
	--subtract the current genRate from the required genRate to get the new outGenRate
	info.outGenRate = info.reqGenRate - info.generationRate
	
	if math.abs(info.outDiff) > 1 then
		info.outSpeed = info.outDiff * (info.temperature / reqTemp ) * 10 * (info.maxFuelConversion / maxFuel)
		info.outIncrease = info.outGenRate + info.outSpeed
		info.outGenRateTrim = 0
	elseif math.abs(info.outDiff) == 1 then
		info.outSpeed = 0
		info.outIncrease = info.outGenRate
		info.outGenRateTrim = info.outGenRate * outTrimPct
	else
		info.outSpeed = 0
		info.outIncrease = 0
		info.outGenRateTrim = info.outGenRate * outTrimPct
	end
	
	local outFlux = info.reqGenRate + info.outIncrease + info.outSpeed + info.outGenRateTrim
	
	if outFlux < 0 or info.generationRate == 0 or outFlux == (1 / 0) or outFlux ~= outFlux then outFlux = 1000 end
	
	return outFlux

end

local function getGraph(inVal, inMax, inSize)
	local strGraph = ''
	local val = (((inVal / inMax) * inSize) - 1)  	--divide the width of screen by the colored chunks required
	for i = 1, val do								-- build the '='
		strGraph = strGraph.."="
	end
	strGraph = strGraph..">"						-- concat the '>'
	for i = val, inSize do							-- set the remaining width to spaces
		strGraph = strGraph.." "
	end
	
	--In case we have a divide by zero, thus no data, pad the string out with spaces
	strGraph = strGraph..string.rep(" ",inSize)
	strGraph = string.sub(strGraph,1,inSize)
	return strGraph
	
end

local function fmtNum( inVal, inWidth, inDec, boolC )
	--because string.format is broken in ComputerCraft, need own format function
	local rtn = inVal
	if type(rtn) == 'number' then
		--Round and get the modulus padded with zeros
		local mod
		if inDec > 0 then											-- number of decimal places
			inVal = (math.floor(inVal * (10^(inDec)) + 0.5) / 10^(inDec))   -- round to the specified decimal places
			-- multiply by 10 to the power of decimals places
			mod = math.floor((inVal % 1) * ( 10 ^ (inDec) ))
			-- pad the decimal with zeros
			mod = string.rep(
				"0",(
						( (inDec-string.len(mod)>=0)  and 1 or 0)
						* (inDec-string.len(mod))
					)
				)..mod
		end
		-- get the integral part
		local int = math.floor(inVal)

		-- add the commas
		while boolC do
			local k
			int, k = string.gsub(int, "^(-?%d+)(%d%d%d)", '%1,%2')
			if (k==0) then
				break
			end
		end

		if mod then
			-- concatonate integral with modulus and decimal point
			rtn = int.."."..mod
		else
			rtn = int	
		end
		
		-- pad with leading spaces
		local pad = inWidth - string.len(rtn)

		if pad > 0 then rtn = string.rep(" ",(pad) )..rtn end
	else
		rtn = tostring(rtn)
		rtn = string.rep(" ",inWidth - string.len(rtn))..rtn
	end
	rtn = string.sub(rtn,1,inWidth)
	return rtn
end

local scrnStatic = {
	main = {
		bCol = colors.black,
		fCol = colors.lightBlue,
		x = 1,
		y = 1,
		array = {
			'                                                  ',
			'                                                  ',
			'Temp:                                             ',
			'                                                  ',
			'Fld:                                              ',
			'                                                  ',
			'Satn:                                             ',
			'                                                  ',
			'Fuel:                                             ',
			'                                                  ',
			'FldDrainRate:            GenRate:                 ',
			'In(Field):           Gain:           Out:         '
			}
		},
	debug = {
		bCol = colors.black,
		fCol = colors.lightBlue,
		x = 1,
		y = 1,
		array = {
			'Status             Debug Screen                   ',
			'                                                  ',
			'Fld:                                 Temp:        ',
			'FldChrg:                  outDiff:                ',
			'                          riseAmt:                ',
			' reqInDiff:              tRiseAmt:                ',
			'                       reqGenRate:                ',
			'                       outGenRate:                ',
			'                      outIncrease:                ',
			'fieldDrain:            speed/trim:                ',
			'fldDrnRate:               GenRate:                ',
			'In(Field):           Gain:           Out:         '
		}
	}
}

local scrnDynamic = {
	main = {
		[1] = { --status = {
			x = 8,
			y = 1,
			fCol = function() return infoStatus[info.status](); end,
			bCol = function() return colors.black; end,
			txt = function() return string.sub(info.status..'      ',1,10) end
			},
		[2] = { --tempVal = {
			x = 7,
			y = 3,
			fCol = function() 
						if math.floor(info.temperature) > reqTemp and info.temperature > 2500 then 
							return colors.red
						else 
							return colors.white 
						end 
					end,
			bCol = function() return colors.black; end,
			txt = function() return fmtNum(math.floor(info.temperature),4,0,false).."C"	end
			},
		[3] = { --reqTemp = {
			x = 37,
			y = 3,
			fCol = function() return colors.blue; end,
			bCol = function() return colors.black; end,
			txt = function() return fmtNum(reqTemp,4,0,false).."C" end
			},
		[4] = { --tempVal2 = {
			x = 1,
			y = 4,
			fCol = function() 
						if math.floor(info.temperature) > reqTemp and info.temperature > 2500 then 
							return colors.red
						else 
							return colors.white 
						end 
					end,
			bCol = function() return colors.black; end,
			txt = function() return fmtNum(math.floor(info.temperature),5,0,false).."C" end
			},
		[5] = { --tempBar = {
			x = 7,
			y = 4,
			blit = true,
			fCol = function() return string.rep("f",graphLen); end,
			bCol = function() return "eeeeeeeeeee111111111114444444444400000000000"; end,
			txt = function() return getGraph(info.temperature, cutoffTemp, graphLen) end
			},
		[6] = { --field = {
			x = 7,
			y = 5,
			fCol = function() return colors.white; end,
			bCol = function() return colors.black; end,
			txt = function() return fmtNum(math.floor(info.fieldStrength),9,0,false).."/"..fmtNum(info.maxFieldStrength,9,0,false) end
			},
		[7] = { --reqField = {
			x = 37,
			y = 5,
			fCol = function() return colors.blue; end,
			bCol = function() return colors.black; end,
			txt = function() return fmtNum(reqField,3,0,false).."%" end
			},
		[8] = { --fieldPct = {
			x = 1,
			y = 6,
			fCol = function() 
						if info.status == 'cold' or info.status == 'offline' or info.status == 'cooling' then
							return colors.white;
						else
							local fieldPct = info.fieldPct * 100
							if     fieldPct < reqField - 0.5 then return colors.red;
							elseif fieldPct < reqField - 0.2 then return colors.orange;
							elseif fieldPct < reqField - 0.1 then return colors.yellow;
							else return colors.white;  
							end
						end
					end,
			bCol = function() return colors.black; end,
			txt = function() return fmtNum(info.fieldPct*100,5,2,false).."%" end
			},
		[9] = { --fieldBar = {
			x = 7,
			y = 6,
			blit = true,
			fCol = function() return string.rep("f",graphLen); end,
			bCol = function() return "eeeeeeeeeaaaaaaaaa222222222bbbbbbbbb99999999"; end,
			txt = function() return getGraph(info.fieldStrength, info.maxFieldStrength, graphLen) end
			},
		[10] = { --sat = {
			x = 7,
			y = 7,
			fCol = function() return colors.white; end,
			bCol = function() return colors.black; end,
			txt = function() return fmtNum(math.floor(info.energySaturation),9,0,false).."/"..fmtNum(info.maxEnergySaturation,10,0,false) end
			},
		[11] = { --satPct = {
			x = 1,
			y = 8,
			fCol = function() 
						local satPct = info.satPct*100
						if     satPct > 99 then return colors.red; 
						elseif satPct > 95 then return colors.orange; 
						elseif satPct > 90 then return colors.yellow; 
						else return colors.white; 
						end
					end,
			bCol = function() return colors.black; end,
			txt = function() return fmtNum(info.satPct*100,5,2,false).."%" end
			},
		[12] = { --satBar = {
			x = 7,
			y = 8,
			blit = true,
			fCol = function() return string.rep("f",graphLen); end,
			bCol = function() return "eeeeeeeeeeeeeeeddddddddddddddd99999999999999"; end,
			txt = function() return getGraph(info.energySaturation, info.maxEnergySaturation, graphLen) end
			},
		[13] = { --fuel = {
			x = 7,
			y = 9,
			fCol = function() return colors.white; end,
			bCol = function() return colors.black; end,
			txt = function() return fmtNum(info.fuelConversion,9,3,false).."/"..fmtNum(info.maxFuelConversion,5,0,false) end
			},
		[14] = { --fuelPct = {
			x = 1,
			y = 10,
			fCol = function() 
						local fuelPct = info.fuelPct*100
						if     fuelPct > 95 then return colors.red;
						elseif fuelPct > 90 then return colors.orange;
						elseif fuelPct > 85 then return colors.yellow;
						else return colors.white; 
						end
					end,
			bCol = function() return colors.black; end,
			txt = function() return fmtNum(info.fuelPct*100,5,2,false).."%" end
			},
		[15] = { --fuelBar = {
			x = 7,
			y = 10,
			blit = true,
			fCol = function() return string.rep("f",graphLen); end,
			bCol = function() return "44444444444ddddddddddd22222222222eeeeeeeeeee"; end,
			txt = function() return getGraph(info.fuelConversion, info.maxFuelConversion, graphLen) end
			},
		[16] = { --fieldDrainRate = {
			x = 14,
			y = 11,
			fCol = function() return colors.white; end,
			bCol = function() return colors.black; end,
			txt = function() return fmtNum(info.fieldDrainRate,9,0,false) end
			},
		[17] = { --generationRate = {
			x = 34,
			y = 11,
			fCol = function() return colors.white; end,
			bCol = function() return colors.black; end,
			txt = function() return fmtNum(info.generationRate,9,0,false) end
			},
		[18] = { --inFluxRF = {
			x = 11,
			y = 12,
			fCol = function() return colors.white; end,
			bCol = function() return colors.black; end,
			txt = function() return fmtNum(inFluxRF,8,0,false) end
			},
		[19] = { --gain = {
			x = 28,
			y = 12,
			fCol = function() return colors.white; end,
			bCol = function() return colors.black; end,
			txt = function() return fmtNum(outFluxRF-inFluxRF,8,0,false) end
			},
		[20] = { --outFluxRF = {
			x = 43,
			y = 12,
			fCol = function() return colors.white; end,
			bCol = function() return colors.black; end,
			txt = function() return fmtNum(outFluxRF,8,0,false) end
			}
		},
	debug = {
		[1] = { --skip = {
			x = 1,
			y = 2,
			txt = function() return 'Ticks lost: '..skip.."  TimerId: "..timerId; end
			},
		[2] = { --status = {
			x = 8,
			y = 1,
			txt = function() return string.sub(info.status..'      ',1,10); end
			},
		[3] = { --fldPct = {
			x = 5,
			y = 3,
			txt = function() return fmtNum(info.fieldPct*100,5,2,false); end
			},
		[4] = { --field = {
			x = 12,
			y = 3,
			txt = function() return fmtNum(info.fieldStrength,9,0,false).."/"; end
			},
		[5] = { --maxField = {
			x = 22,
			y = 3,
			txt = function() return fmtNum(info.maxFieldStrength,9,0,false); end
			},
		[6] = { --temperature = {
			x = 43,
			y = 3,
			txt = function() return fmtNum(info.temperature,4,0,false).."C"; end
			},
		[7] = { --fieldCharge = {
			x = 10,
			y = 4,
			txt = function() return fmtNum(info.fieldCharge,11,0,false); end
			},
		[8] = { --outDiff = {
			x = 35,
			y = 4,
			txt = function() return fmtNum(info.outDiff,8,0,false); end
			},
		[9] = { --riseAmount = {
			x = 35,
			y = 5,
			txt = function() if info.riseAmount then return info.riseAmount * 10; else return 'N/A'; end; end
			},
		[10] = { --tRiseAmount = {
			x = 35,
			y = 6,
			txt = function() return getRiseAmt(); end
			},
		[11] = { --reqInDiff = {
			x = 12,
			y = 6,
			txt = function() return fmtNum(info.reqInDiff,10,0,false); end
			},
		[12] = { --reqGenRate = {
			x = 35,
			y = 7,
			txt = function() return fmtNum(info.reqGenRate,11,2,false); end
			},
		[13] = { --outGenRate = {
			x = 35,
			y = 8,
			txt = function() return fmtNum(info.outGenRate,11,2,false); end
			},
		[14] = { --outIncrease = {
			x = 35,
			y = 9,
			txt = function() return fmtNum(info.outIncrease,11,2,false) end
			},
		[15] = { --fieldDrain = {
			x = 12,
			y = 10,
			txt = function() return fmtNum(info.fieldDrain,10,2,false); end
			},
		[16] = { --speedTrim = {
			x = 35,
			y = 10,
			txt = function() return fmtNum(info.outSpeed,11,2,false).."/"..tostring(info.outGenRateTrim).."       "; end
			},
		[17] = { --fieldDrainRate = {
			x = 12,
			y = 11,
			txt = function() return fmtNum(info.fieldDrainRate,10,2,false); end
			},
		[18] = { --generationRate = {
			x = 35,
			y = 11,
			txt = function() return fmtNum(info.generationRate,8,0,false); end
			},
		[19] = { --inFluxRF = {
			x = 11,
			y = 12,
			txt = function() return fmtNum(inFluxRF,8,0,false); end
			},
		[20] = { --gain = {
			x = 28,
			y = 12,
			txt = function() return fmtNum(outFluxRF-inFluxRF,8,0,false); end
			},
		[21] = { --outFluxRF = {
			x = 43,
			y = 12,
			txt = function() return fmtNum(outFluxRF,8,0,false); end
			}
		}
}

local buttons = {
	[1] = { --status = {
		x = 1,
		y = 1,
		txt = 'Status',
		type = buttonType.label.id,
		state = state.enabled,
		action = function() debugMode = not debugMode; if debugMode then printStatic(scrnStatic.debug); else printStatic(scrnStatic.main); end; end
	},
	[2] = { --charge = {
		x = 18,
		y = 1,
		txt = '[Charge]',
		type = buttonType.button.id,
		state = state.off,
		action = function(self) if self.state == state.enabled then callReactor('chargeReactor'); end; end
	},
	[3] = { --activate = {
		x = 28,
		y = 1,
		txt = '[Activate]',
		type = buttonType.button.id,
		state = state.off,
		action = function(self) if self.state == state.enabled then callReactor('activateReactor'); end; end
	},
	[4] = { --stop = {
		x = 40,
		y = 1,
		txt = '[Shutdown]',
		type = buttonType.button.id,
		state = state.off,	
		action = function(self) if self.state == state.enabled then callReactor('stopReactor'); end; end
	},
	[5] = { --tempUp1 = {
		x = 42,
		y = 3,
		txt = '[]',
		type = buttonType.val1.id,
		action=function() modTemp(1); end,
		state = state.enabled	
	},
	[6] = { --tempUp10 = {
		x = 44,
		y = 3,
		txt = '[>]',
		type = buttonType.val10.id,
		action=function() modTemp(10); end,
		state = state.enabled
	},
	[7] = { --tempUp100 = {
		x = 47,
		y = 3,
		txt = '[>>]',
		type = buttonType.val1.id,
		action=function() modTemp(100); end,
		state = state.enabled
	},
	[8] = { --tempDown1 = {
		x = 35,
		y = 3,
		txt = '[]',
		type = buttonType.val1.id,
		action=function() modTemp(-1); end,
		state = state.enabled
	},
	[9] = { --tempDown10 = {
		x = 32,
		y = 3,
		txt = '[<]',
		type = buttonType.val10.id,
		action=function() modTemp(-10); end,
		state = state.enabled
	},
	[10] = { --tempDown100 = {
		x = 28,
		y = 3,
		txt = '[<<]',
		type = buttonType.val1.id,
		action=function() modTemp(-100); end,
		state = state.enabled
	},
	[11] = { --fieldUp1 = {
		x = 42,
		y = 5,
		txt = '[]',
		type = buttonType.val1.id,
		action=function() modField(1); end,
		state = state.enabled
	},
	[12] = { --fieldUp10 = {
		x = 44,
		y = 5,
		txt = '[>]',
		type = buttonType.val10.id,
		action=function() modField(10); end,
		state = state.enabled
	},
	[13] = { --fieldDown1 = {
		x = 35,
		y = 5,
		txt = '[]',
		type = buttonType.val1.id,
		action=function() modField(-1); end,
		state = state.enabled
	},
	[14] = { --fieldDown10 = {
		x = 32,
		y = 5,
		txt = '[<]',
		type = buttonType.val10.id,
		action=function() modField(-10); end,
		state = state.enabled
	}
}

local setStatus = {
	["running"] = 	function() 
						buttons[2].state = state.disabled
						buttons[3].state = state.active
						buttons[4].state = state.enabled
					end,
    ["cold"] =  	function() 
						buttons[2].state = state.enabled
						buttons[3].state = state.disabled
						buttons[4].state = state.disabled
					end,
	["stopping"] =  function() 
						if info.temperature > 2000 then
							buttons[2].state = state.disabled
							buttons[3].state = state.enabled
						else
							buttons[2].state = state.enabled
							buttons[3].state = state.disabled
						end
						buttons[4].state = state.active
					end,
    ["warming_up"] =  function() 
						if info.temperature > 2000 then
							buttons[2].state = state.active
							buttons[3].state = state.enabled
						else
							buttons[2].state = state.active
							buttons[3].state = state.disabled
						end
						buttons[4].state = state.enabled
					end,
    ["cooling"] =  function() 
						if info.satPct >= 0.99 then
							buttons[2].state = state.disabled
						else
							buttons[2].state = state.enabled
						end
						buttons[3].state = state.disabled
						buttons[4].state = state.active
					end,
	['beyond_hope'] = function() 
						buttons[2].state = state.off
						buttons[3].state = state.off
						buttons[4].state = state.off
					end
}

local function userAction(op1, op2)
	local x = op1  -- x coord of where click happened
	local y = op2  -- y coord of where click happened
	--Loop through all the buttons and compare x/y's to see if button was pressed, if so, execute the buttons action function
	for n, b in pairs(buttons) do
		if (x >= b.x and x <= b.x + string.len(b.txt) and y == b.y and b.state == state.enabled) then
			b:action()
			b.depressed = 3
		end
	end

end

local function core()
	if info.fieldStrength    then info.fieldPct = info.fieldStrength    / info.maxFieldStrength;    else info.fieldPct = 0; end
	if info.energySaturation then info.satPct   = info.energySaturation / info.maxEnergySaturation; else info.satPct   = 0; end
	if info.fuelConversion   then info.fuelPct  = info.fuelConversion   / info.maxFuelConversion;   else info.fuelPct  = 0; end
	-- test for Nan and Inf
	if info.fieldPct == (1 / 0) or info.fieldPct ~= info.fieldPct then info.fieldPct = 0; end
	if info.satPct   == (1 / 0) or info.satPct   ~= info.satPct   then info.satPct   = 0; end
	if info.fuelPct  == (1 / 0) or info.fuelPct  ~= info.fuelPct  then info.fuelPct  = 0; end
	
	--Safty Checks
	if info.temperature > cutoffTemp or (info.temperature < minTemp and info.satPct >= 0.99) then
		--**** STOP REACTOR ****
		if info.status ~= state.stopping then callReactor("stopReactor"); end
	end

	--print("set status")		
	setStatus[info.status]()
	
	--print("--Calculate and Set Flux Gate Values")
	if info.status == 'cold' or info.status == 'offline' or info.status == 'cooling' then
		inFluxRF = 0
		outFluxRF = info.generationRate
		
	elseif info.status == 'warming_up' then
		if info.temperature < 2000 then
			inFluxRF = warmUpRF
		else
			inFluxRF = 0
		end
		
	elseif info.status == 'stopping' then
		--print("Stopping, so just calculate inFluxRF to maintain containment field, set outFlux to the info.generationRate")
		if reqField < 10 then reqField = 10; end  -- set the containment field to 10% for safety reasons
		inFluxRF = getInFlux()
		outFluxRF = info.generationRate
		
	else
		--print("--Calculate in and out flux requirements")		
		inFluxRF = getInFlux()
		outFluxRF = getOutFlux()
	end
	
	--print("--Update Flux Gates with requirements")
	inFlux.setFlowOverride(inFluxRF)
	outFlux.setFlowOverride(outFluxRF)

	--print("update screen")
	if debugMode then
		monitor.setTextColor(colors.white)
		printUpdates(scrnDynamic.debug)
	else
		printUpdates(scrnDynamic.main)
		printButtons(buttons)
	end
	monitor.setCursorPos(1,2)

end

local eventHandler = {
	timer 				= function(id, op1, op2, op3, op4, op5)
								if id == timerId then
									callReactor('getReactorInfo')
									skip = skip + 1                           --Debug Only
								end
							end,
	modem_message 		= function(id, op1, op2, op3, op4, op5) 
								if OC then
									op2 = op4
									op3 = serialization.unserialize(op5)
								end
								local int, _ = math.modf(timerId / maxId)
								if op2 + (maxId * int) == timerId then 
									os.cancelTimer(timerId)  			-- Cancel the timer as we have the message
									info = op3   -- set reactor info table as returned in op3/message
									core()
									callReactor('getReactorInfo')
								end
							end,
	mouse_click 		= function(id, op1, op2, op3, op4) userAction(op1, op2); end,
	eventmouse_click	= function(id, op1, op2, op3, op4) userAction(op1, op2); end,
	monitor_touch 		= function(id, op1, op2, op3, op4) userAction(op1, op2); end,
	touch 				= function(id, op1, op2, op3, op4) userAction(op1, op2); end,
	interrupted			= function() end,   -- TO DO
	['*']				= function() end
}

local function errorHandler(errNo, errMsg)
	if not errNo then
		print(tostring(errNo).."	"..tostring(errMsg))
		if errMsg == "Terminated" or errMsg == "interrupted" then
			return
		else
			local f = fileIO.open("log","a")
			f:write("#"..os.getComputerID().." :: "..errMsg.."\n")
			f:close()
			os.reboot() 
--print("Reboot commented")
		end
	end
end

local function initialise()
	--Initialise Flux Gates
	inFlux.setFlowOverride(0)
	outFlux.setFlowOverride(0)
	inFlux.setOverrideEnabled(true)
	outFlux.setOverrideEnabled(true)

	--Initialise Monitor
	if CC then
		if monitor == nil then 
			print("setting monitor to term") 
			monitor = term 
		else	
			monitor.setTextScale(1)
		end
	elseif OC then
		monitor.setResolution(50, 12)
	else
		--Doh, we have no recognised OS
	end
	print("Monitor initialised")
	
	monitor.clear()
	printStatic(scrnStatic.main)

	--redirect std out to monitor
	if monitor ~= term and CC then
		term.redirect(monitor)		--redirct all future std out to monitor instead of local computer screen
	end
	
	-- open modem on listen channel
	modem.open(modemRx)  

	print("request initial reactor info")
	callReactor('getReactorInfo')
	local try = 0

	--Loop until we get a response from reactor modem or have info.* 
	while info.status == nil do
		monitor.setCursorPos(1, 2)
		try = try + 1
		monitor.write("waiting for response from reactor modem Try:"..try)

		local event, id, op1, op2, op3, op4, op5 = os.pullEvent()
		
		if type(eventHandler[event]) == 'function' then
			eventHandler[event](id, op1, op2, op3, op4, op5)
		else
			eventHandler['*'](event, id, op1, op2, op3, op4, op5)
		end
	end -- end while loop
	
	monitor.setBackgroundColor(colors.black)
	monitor.setCursorPos(1, 2)
	monitor.write(string.rep(" ", screenWidth))

end

local function main()
	--**************************
	--****** START MAIN ********
	--**************************
	--print("start main while loop")
	while true do
		--print("wait for the timer event or some other event")
		local event, id, op1, op2, op3, op4, op5 = os.pullEvent()
		
		if type(eventHandler[event]) == 'function' then
			eventHandler[event](id, op1, op2, op3, op4, op5)
		else
			eventHandler['*'](event, id, op1, op2, op3, op4, op5)
		end
	end -- end while true loop
end

-- initialise()
-- main()

local errNo, errMsg = pcall(initialise)
errorHandler(errNo, errMsg)
if errNo then
	local errNo, errMsg = pcall(main)
	errorHandler(errNo, errMsg)
end

--Reset the stupid OpenComputers screen
if OC then
	monitor.resetResolution()
end

