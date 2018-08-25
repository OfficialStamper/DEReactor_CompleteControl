--derl (Draconic Evolution Reactor Listener) V1.1.0
--Official Stamper (c) Aug 2018

--Changelog V1.1.0 added OC Code

local modemSide = 'bottom'    -- Only required for CC
local reactorSide = 'top'
local modemTx = 21
local modemRx = 21

--Peripherals and components (do not initialise to values)
local modem
local reactor 
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
end

if CC then
	--Open the modem on the channel specified 
	modem = peripheral.wrap(modemSide)
	reactor = peripheral.wrap(reactorSide)
	fileIO = fs

elseif OC then
	local component = require("component")
	local computer = require("computer")
	local event = require("event")
	local term = require("term")
	serialization = require("serialization")
	fileIO = require("filesystem")
	modem = component.modem
	local gpu = component.gpu
	reactor = component.draconic_reactor
	os.pullEvent = event.pull
	modem.transmit = modem.broadcast
	os.getComputerID = computer.address
	os.reboot = function()
					computer.shutdown(true)
				end

else
	-- no valid OS
end

modem.open(modemRx)
print("Listening on port ("..modemRx..").....")

local request = {
	getReactorInfo 	= function(id)
							local info = reactor.getReactorInfo()
							if OC then info = serialization.serialize(info) end
							modem.transmit(modemTx, id, info) 
						end,
	chargeReactor 	= function() reactor.chargeReactor() end,
	activateReactor = function() reactor.activateReactor() end,
	stopReactor 	= function() reactor.stopReactor() end,
	setFailSafe 	= function() reactor.setFailSafe() end,
	reset 			= function() reactor.reset() end
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
			request[message.req](id)
		else 
			--Message not for me
		end

	end
end

--main()
local errNo, errMsg = pcall(main)

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

