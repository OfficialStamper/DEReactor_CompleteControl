--derEmulator (Draconic Evolution Reactor Emulator) V1.1.0
--Official Stamper (c) Aug 2018

--Changelog V1.1.0 added OC Code


-- Listen for modem request from control

local modemSide = 'top'    -- Only required for CC
local modemTx = 299
local modemRx = 299

-- Emulation values
local fuelInject = 10368
local fuelConversion = 0 --0.5427

--Peripherals and components (do not initialise to values)
--local monitor
local modem 
--local emulatedReactor
local serialization

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
end

if CC then
	--Open the modem on the channel specified 
	modem = peripheral.wrap(modemSide)
	os.loadAPI("emulatedReactor")
	--local reactor = peripheral.wrap(reactorSide)

elseif OC then
	local component = require("component")
	local computer = require("computer")
	local event = require("event")
	local term = require("term")
	serialization = require("serialization")
	modem = component.modem
	local gpu = component.gpu
	emulatedReactor = require("mooviesReactor")
	os.pullEvent = event.pull
	modem.transmit = modem.broadcast
else
	-- no valid OS
end

--Initialise emulatedReactor
emulatedReactor.fluxGates.input.setFlowOverride(0)
emulatedReactor.fluxGates.output.setFlowOverride(0)
emulatedReactor.fluxGates.input.setOverrideEnabled(true)
emulatedReactor.fluxGates.output.setOverrideEnabled(true)
emulatedReactor.setFuel(fuelInject, fuelConversion)

modem.open(modemRx)
print("Listening.....")

local request = {
	getReactorInfo 	= function(id)
							local info = emulatedReactor.getReactorInfo()
							if OC then info = serialization.serialize(info) end
							modem.transmit(modemTx, id, info) 
						end,
	chargeReactor 	= function() emulatedReactor.chargeReactor() end,
	activateReactor = function() emulatedReactor.activateReactor() end,
	stopReactor 	= function() emulatedReactor.stopReactor() end,
	setFailSafe 	= function() emulatedReactor.setFailSafe() end,
	reset 			= function() emulatedReactor.reset() end
}

function main()
	while true do
	
		local event, modemSide, senderChannel, id, message, senderDistance, more = os.pullEvent("modem_message")

		if OC then
			senderChannel = id
			id = senderDistance
			message = serialization.unserialize(more)
		end
		
		if (senderChannel == modemRx) then  -- is this message for me?
			emulatedReactor.fluxGates.input.setFlowOverride(message.inRF)
			emulatedReactor.fluxGates.output.setFlowOverride(message.outRF)
			emulatedReactor.update()
			request[message.req](id)
		else 
			--Message not for me
		end

	end
end

main()
--local errNo, errMsg = pcall(main)

-- print(tostring(errNo).." : "..errMsg)

-- if errMsg == "Terminated" then
	-- return
-- else
	-- local f = fs.open("log","a")
	-- f.writeLine(textutils.formatTime(os.time("utc"),true).."(UTC) #"..os.getComputerID()..": "..errMsg)
	-- f.close()
	-- os.reboot() 
-- end

