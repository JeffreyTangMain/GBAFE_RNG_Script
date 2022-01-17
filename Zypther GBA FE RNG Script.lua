local absolute = math.abs
local mathfloor = math.floor 
local tableremove = table.remove 
local tableinsert = table.insert
local memoryreadbyte = memory.readbyte
local memoryreadword = memory.readword
local memorywriteword = memory.writeword
local tablesort = table.sort
local guitext = gui.text
local bitband = bit.band
local bitbxor = bit.bxor
local bitrshift = bit.rshift
local bitlshift = bit.lshift
local bitbor = bit.bor
local stringgmatch = string.gmatch
local memoryreaddword = memory.readdword
local savestatesave = savestate.save
local savestateload = savestate.load
local stringformat = string.format
local joypadset = joypad.set

local RNGBase = 0x03000000
local lastSeenRNG = {memoryreadword(RNGBase+4), memoryreadword(RNGBase+2), memoryreadword(RNGBase+0)}
local numDisplayedRNs = 20
local superRNToRNConversionDivisor = 655.36
local gameID = ""

local holdButtonCounterLimit = 7
local holdButtonCounter = 0
local staticCounter = 0
local acceleration = 0 -- used to decrease the length of time you must hold down a button to advance the RNG
local RNGPosition = 0
local lastRNGPosition = 0

local userInput = input.get()
local AIPhaseScriptEnabled = false
local displaySearchOn = false
local displayMinimalSearchOn = false
local displayHelpOn = false
local displayRNG = true
local consecutiveUpdatesFailedCounter = 0
local searchFoundPositions = {"Yahaha You found me!"}
local searchCompareTypes = {}
local searchComparators = {}
local searchNumbers = {}
local searchLeftBoundDefault = -200
local searchRightBoundDefault = 500
-- next two get reset later so change the defaults instead.
local searchLeftBound = searchRightBoundDefault
local searchRightBound = searchRightBoundDefault
local searchLeftPosition = nil
local searchRightPosition = nil
local searchLeftSeed = {}
local searchRightSeed = {}
local leftFoundPositions = {}
local backupLeftFoundPositions = {}
local rightFoundPositions = {}
local backupRightFoundPositions = {}
local rightStartIndex = 1
local setupTimerLeft = 0
local setupTimerRight = 0
local updateLoopLimit = 50000000
local skipThousandAmount = 1
local searchDirection = 1

-- Read consecutive values from the ROM to find a special string (ex/ FIREEMBLEM6.AFEJ01) used to distinguish between games
for i = 0, 18, 1 do
	gameID = gameID..memoryreadbyte(0x080000A0 + i)
end

local gameIDMap = {
	['70738269697766766977540657069744849150'] = "Sealed Sword J",
	['70738269697766766977690656955694849150'] = "Blazing Sword U",
	['70738269697766766977550656955744849150'] = "Blazing Sword J",
	['707382696977667669775069666956694849150'] = "Sacred Stones U",
	['70738269697766766977560666956744849150'] = "Sacred Stones J"
}

local phaseMap = {
	['Sealed Sword J'] = 0x0202AA57,
	['Blazing Sword U'] = 0x0202BC07,
	['Blazing Sword J'] = 0x0202BC03,
	['Sacred Stones U'] = 0x0202BCFF,
	['Sacred Stones J'] = 0x0202BCFB
}

local currentGame = gameIDMap[gameID]

print("Current game: "..currentGame)

local heldDown = {
	['1'] = false, 
	['2'] = false, 
	['3'] = false, 
	['4'] = false, 
	['5'] = false, 
	['6'] = false, 
	['7'] = false, 
	['8'] = false, 
	['9'] = false, 
	['0'] = false,
	['comma'] = false,
	['period'] = false,
	['plus'] = false,
	['backspace'] = false,
	['enter'] = false,
	['I'] = false, --search
	['O'] = false, --hide search
	['E'] = false, --enable ephase
	['F'] = false, --skip left search
	['G'] = false, --skip right search 
	['R'] = false, --disable ephase
	['L'] = false, --reset search 
	['V'] = false, --print enemy information
	['Y'] = false, --print exp
	['K'] = false, --go back to 0 RNG
	['J'] = false, --minimum search
	['U'] = false, --hide ui completely
	['up'] = false, --^^
	['down'] = false, --^^
	['left'] = false, --^^
	['right'] = false, --^^
	['H'] = false --show help
}

function superRNToRN(srn)
	return mathfloor(srn/superRNToRNConversionDivisor)
end

function updateRNGPosition()
	local superRNList = {lastSeenRNG[1], lastSeenRNG[2], lastSeenRNG[3]}
	local superRNListReverse = {lastSeenRNG[1], lastSeenRNG[2], lastSeenRNG[3]}
	lastRNGPosition = RNGPosition
	positionFound = false
	i = 0
	--print(superRNList)
	--print(memoryreadword(RNGBase+4).." "..memoryreadword(RNGBase+2).." "..memoryreadword(RNGBase+0))
	while positionFound == false do
		if i > updateLoopLimit then
			--print("update failed")
			--emu.pause()
			consecutiveUpdatesFailedCounter = consecutiveUpdatesFailedCounter + 1
			searchFoundPositions[1] = "No search has been completed"
			return
		end
		--print(i)
		local match1 = RNGMatchDetailed(superRNList[1], superRNList[2], superRNList[3])
		if match1 then
			positionFound = true
			lastRNGPosition = RNGPosition
			RNGPosition = RNGPosition + i
			if (absolute(RNGPosition - lastRNGPosition)) > (absolute(searchRightBound) + absolute(searchLeftBound)) then
				--print("K")
				searchFoundPositions[1] = "No search has been completed"
			end
			break
		end

		local match2 = RNGMatchDetailed(superRNListReverse[1], superRNListReverse[2], superRNListReverse[3])

		if match2 then
			positionFound = true
			lastRNGPosition = RNGPosition
			RNGPosition = RNGPosition - i
			if (absolute(RNGPosition - lastRNGPosition)) > (absolute(searchRightBound) + absolute(searchLeftBound)) then
				--print("K")
				searchFoundPositions[1] = "No search has been completed"
			end
			break
		end

		local temp1 = superRNList[1]
		local temp2 = superRNList[2]
		local temp3 = superRNList[3]
		
		local tempReverse1 = superRNListReverse[1]
		local tempReverse2 = superRNListReverse[2]
		local tempReverse3 = superRNListReverse[3]
		
		superRNList[1] = temp2
		superRNList[2] = temp3
		superRNList[3] = nextSuperRN(temp1, temp2 , temp3)

		superRNListReverse[1] = previousSuperRN(superRNListReverse[1], superRNListReverse[2] , superRNListReverse[3])
		superRNListReverse[2] = tempReverse1
		superRNListReverse[3] = tempReverse2
		i = i + 1
	end
	lastSeenRNG[1] = memoryreadword(RNGBase+4)
	lastSeenRNG[2] = memoryreadword(RNGBase+2)
	lastSeenRNG[3] = memoryreadword(RNGBase+0)
	consecutiveUpdatesFailedCounter = 0
end

function RNGMatchDetailed(a,b,c)
	return (memoryreadword(RNGBase+4) == a) and (memoryreadword(RNGBase+2) == b) and (memoryreadword(RNGBase+0) == c)
end

function previousSuperRN(r1, r2, r3)
	-- Given three sequential RNG values, generate the value before it
	local val = bitband(0xFFFE,bitbxor(r3, bitrshift(r2, 5), bitlshift(r1, 11)))
	val = bitbor(val,bitband(0x0001,bitbxor(r2,bitrshift(r1,5))))

   return bitbor(
	  bitlshift(bitband(0x0001,val),15),
	  bitrshift(bitband(0xFFFE,val), 1)
   )
end

function nextSuperRN(r1, r2, r3)
	-- Given three sequential RNG values, generate a fourth
	return AND(XOR(SHIFT(r3, 5), SHIFT(r2, -11), SHIFT(r1, -1), SHIFT(r2, 15)),0xFFFF)
end

function printRNG(n)
	-- Print n entries of the RNG table
	RNGTable = RNGSimulate(n)
	-- Print each RNG value
	for i=1,n do
		--guitext(232, 8*(i-1), superRNToRN(RNGTable[i]), 0xFF5555FF)
		guitext(232, 8*(i-1), superRNToRN(RNGTable[i]))
	end
	--guitext(170,0,"Next RNs:", 0xFF5555FF)
end

function RNGSimulate(n)
	-- Generate n entries of the RNG table (including the 3 RNs used for the RNG seed)
	local result = { memoryreadword(RNGBase+4), memoryreadword(RNGBase+2), memoryreadword(RNGBase+0) }
	advanceRNGTable(result,3)
	for i = 4, n do
		result[i] = nextSuperRN(result[i-3],result[i-2],result[i-1])
	end
	return result
end

function advanceRNG()
	-- Identify the memory addresses of the first 4 RNG values
	local RNG1 =  memoryreadword(RNGBase+4)
	local RNG2 =  memoryreadword(RNGBase+2)
	local RNG3 = memoryreadword(RNGBase+0)
	local RNG4 = nextSuperRN(RNG1, RNG2, RNG3)
	-- Swap the values in RNG Seed 1,2,3 by the RNG values 2,3,4
	memorywriteword(RNGBase + 4, RNG2)
	memorywriteword(RNGBase + 2, RNG3)
	memorywriteword(RNGBase + 0, RNG4)
end

-- Given an input table [RNG1, RNG2, RNG3], return [RNG2, RNG3, RNG4]
function advanceRNGTable(RNGTable,n)
	if n == 0 then
		return RNGTable
	end
	for i = 1, absolute(n), 1 do
		local nextRN
		if n > 0 then
			nextRN = nextSuperRN(RNGTable[#RNGTable-2], RNGTable[#RNGTable-1], RNGTable[#RNGTable])
			for j = 1, #RNGTable - 1, 1 do
				RNGTable[j] = RNGTable[j+1]
			end
			RNGTable[#RNGTable] = nextRN
		else
			nextRN = previousSuperRN(RNGTable[1], RNGTable[2], RNGTable[3])
			for j = #RNGTable, 2, -1 do
				RNGTable[j] = RNGTable[j-1]
			end
			RNGTable[1] = nextRN
		end
	end
	return RNGTable
end

function decrementRNG()
	-- Identify the memory addresses of the first 4 RNG values
	local RNG2 =  memoryreadword(RNGBase+4)
	local RNG3 = memoryreadword(RNGBase+2)
	local RNG4 = memoryreadword(RNGBase+0)
	local RNG1 =  previousSuperRN(RNG2, RNG3, RNG4)
	-- Swap the values in RNG Seed 1,2,3 by the RNG values 2,3,4
	memorywriteword(RNGBase + 4, RNG1)
	memorywriteword(RNGBase + 2, RNG2)
	memorywriteword(RNGBase + 0, RNG3)
end

function copyOf(t)
	local newTable = {}
	for i = 1, #t, 1 do
		newTable[i] = t[i]
	end
	return newTable
end

function compareLists(list1, comparators, list2)
	local match = true
	for i = 1, #list1, 1 do
		if not compareValues(list1[i], comparators[i], list2[i]) then
			match = false
			break
		end
	end
	return match
end

-- returns the boolean equal to value1 comparator value2
function compareValues(value1, comparator, value2)
	if comparator == '=' then
		return value1 == value2
	elseif comparator == '<' then
		return value1 < value2
	elseif comparator == '<=' then
		return value1 <= value2
	elseif comparator == '>' then
		return value1 > value2
	elseif comparator == '>=' then
		return value1 >= value2
	end
end

function readInSearchFile()
	searchFoundPositions = {"No search has been completed"}
	fileIterator = io.lines("SearchInputs.txt")
	local y = 1
	local x = 1
	local eof = false
	searchLeftPosition = RNGPosition
	searchRightPosition = RNGPosition
	searchLeftBound = searchLeftBoundDefault
	searchRightBound = searchRightBoundDefault
	searchCompareTypes = {}
	searchComparators = {}
	searchNumbers = {}
	searchCompareTypes[1] = {}
	searchComparators[1] = {}
	searchNumbers[1] = {}
	for line in fileIterator do
		local letterPatternMatcher = stringgmatch(line, "%a+")
		local symbolPatternMatcher = stringgmatch(line, "[<>=]+")
		local numberPatternMatcher = stringgmatch(line, "[-%d]+")
		if y == 1 then
			searchLeftBound = tonumber(numberPatternMatcher())
			searchRightBound = tonumber(numberPatternMatcher())
		else
			local letters = letterPatternMatcher()
			if letters == "or" then
				y = 1
				x = x + 1
				searchCompareTypes[x] = {}
				searchComparators[x] = {}
				searchNumbers[x] = {}
			elseif letters == "end" then
				eof = true
			else
				local symbols = symbolPatternMatcher()
				local number = numberPatternMatcher()
				if letters == nil then
					searchCompareTypes[x][y - 1] = "nil"
				else
					searchCompareTypes[x][y - 1] = letters
				end
				searchComparators[x][y - 1] = symbols
				searchNumbers[x][y - 1] = tonumber(number)
			end

		end
		if eof then
			break
		end
		y = y + 1
	end

end

-- does not modify inputs
function generateCompareList(compareTypeList, startSeed)
	local seed = copyOf(startSeed)
	local compareList = {}
	local i = 1
	while i <= #compareTypeList do
		if compareTypeList[i] == "nil" then
			compareList[i] = mathfloor((nextSuperRN(seed[1], seed[2], seed[3]) / superRNToRNConversionDivisor))
			
		elseif compareTypeList[i] == "h" then
			local num = 0
			num = mathfloor((nextSuperRN(seed[1], seed[2], seed[3]) / superRNToRNConversionDivisor))
			advanceRNGTable(seed, 1)
			num = num + mathfloor((nextSuperRN(seed[1], seed[2], seed[3]) / superRNToRNConversionDivisor))
			compareList[i] = mathfloor(num / 2)
		end
		
		seed = advanceRNGTable(seed, 1)
		i = i + 1
	end
	return compareList
end

function searchLeft()
	leftFoundPositions = {}
	local j = 0
	local i = 1
	while searchLeftPosition >= (searchLeftBound + RNGPosition) do
		local leftMatch = false
		for x = 1, #searchComparators, 1 do
			if compareLists(generateCompareList(searchCompareTypes[x], searchLeftSeed), searchComparators[x], searchNumbers[x]) then
				leftMatch = true
				break
			end
		end
		if leftMatch then
			leftFoundPositions[i] = searchLeftPosition
			i = i + 1
		end
		searchLeftPosition = searchLeftPosition - 1
		advanceRNGTable(searchLeftSeed, -1)
		j = j + 1
	end
	setupTimerLeft = setupTimerLeft + 1
	if setupTimerLeft == 1 then 
		setupSkip(1)
	end
	--print("L: "..j)
end

function searchRight()
	rightFoundPositions = {}
	local j = 0
	local i = 1
	while searchRightPosition <= (searchRightBound + RNGPosition) do
		local rightMatch = false
		for x = 1, #searchComparators, 1 do
			if compareLists(generateCompareList(searchCompareTypes[x], searchRightSeed), searchComparators[x], searchNumbers[x]) then
				rightMatch = true
				break
			end
		end
		if rightMatch then
			rightFoundPositions[i] = searchRightPosition
			i = i + 1
		end
		searchRightPosition = searchRightPosition + 1
		advanceRNGTable(searchRightSeed, 1)
		j = j + 1
	end
	setupTimerRight = setupTimerRight + 1
	if setupTimerRight == 1 then 
		setupSkip(2)
	end
	--print("R: "..j)
end

function search()
	local shiftDistance = RNGPosition - lastRNGPosition
	local i = 0
	local j = 0
	if (shiftDistance == 0 and searchFoundPositions[1] ~= "No search has been completed") or searchFoundPositions[1] == "Yahaha You found me!" then
		return
	end
	if searchFoundPositions[1] == "No search has been completed" then
		searchLeftSeed = {memoryreadword(RNGBase+4), memoryreadword(RNGBase+2), memoryreadword(RNGBase+0)}
		searchRightSeed = {memoryreadword(RNGBase+4), memoryreadword(RNGBase+2), memoryreadword(RNGBase+0)}
		advanceRNGTable(searchLeftSeed, -1)
		searchLeftPosition = RNGPosition - 1
		searchRightPosition = RNGPosition
		
		searchLeft()
		searchRight()
		--print("ONE")
		--print(searchFoundPositions)
		
		searchFoundPositions = {}
		
		--print(searchFoundPositions)
		--print("1.2")
		--print(leftFoundPositions)
		--print(rightFoundPositions)
		
		i = 1
		j = #leftFoundPositions
		while j > 0  do
			searchFoundPositions[i] = leftFoundPositions[j]
			i = i + 1
			j = j - 1
		end
		j = 1
		while j <= #rightFoundPositions  do
			searchFoundPositions[i] = rightFoundPositions[j]
			i = i + 1
			j = j + 1
		end
		--print("1.3")
		--print(searchFoundPositions)
	--else do an update
	else
		tablesort(searchFoundPositions)
		searchLeft()
		searchRight()
		--print("TWO")
		--print(searchFoundPositions)
		--print(leftFoundPositions)
		--print(rightFoundPositions)
		if(shiftDistance < 0) then
			
			 i = 1
			while i <= #leftFoundPositions do
				tableinsert(searchFoundPositions, 1, leftFoundPositions[i])
				i = i + 1
			end
			
			while #searchFoundPositions > 0 and searchFoundPositions[#searchFoundPositions] >  searchRightBound + RNGPosition do
				tableremove(searchFoundPositions, #searchFoundPositions)
			end
			searchRightPosition = searchRightPosition + shiftDistance
			advanceRNGTable(searchRightSeed, shiftDistance)
			
		elseif(shiftDistance > 0) then
			
			 i = 1
			while i <= #rightFoundPositions do
				tableinsert(searchFoundPositions, #searchFoundPositions + 1, rightFoundPositions[i])
				i = i + 1
			end
			
			while #searchFoundPositions > 0 and searchFoundPositions[1] < searchLeftBound + RNGPosition do
				tableremove(searchFoundPositions, 1)
			end
			searchLeftPosition = searchLeftPosition + shiftDistance
			advanceRNGTable(searchLeftSeed, shiftDistance)
			
		end
	end
end

function searchLeftMinimal()
	setupTimerLeft = setupTimerLeft + 1
	if setupTimerLeft == 1 then
		backupLeftFoundPositions = {}
		leftFoundPositions = {}
		local j = 0
		local i = 1
		while leftFoundPositions[1] == nil and j < 30000000 do
			local leftMatch = false
			for x = 1, #searchComparators, 1 do
				if compareLists(generateCompareList(searchCompareTypes[x], searchLeftSeed), searchComparators[x], searchNumbers[x]) then
					leftMatch = true
					break
				end
			end
			if leftMatch then
				leftFoundPositions[i] = searchLeftPosition
				i = i + 1
			end
			searchLeftPosition = searchLeftPosition - 1
			advanceRNGTable(searchLeftSeed, -1)
			j = j + 1
		end
		setupSkip(1)
	end
end

function searchRightMinimal()
	setupTimerRight = setupTimerRight + 1
	if setupTimerRight == 1 then
		backupRightFoundPositions = {}
		rightFoundPositions = {}
		local j = 0
		local i = 1
		while rightFoundPositions[1] == nil and j < 30000000 do
			local rightMatch = false
			for x = 1, #searchComparators, 1 do
				if compareLists(generateCompareList(searchCompareTypes[x], searchRightSeed), searchComparators[x], searchNumbers[x]) then
					rightMatch = true
					break
				end
			end
			if rightMatch then
				leftFoundPositions[i] = searchRightPosition
				rightFoundPositions[i] = searchRightPosition
				i = i + 1
			end
			searchRightPosition = searchRightPosition + 1
			advanceRNGTable(searchRightSeed, 1)
			j = j + 1
		end
		setupSkip(3)
	end
end

function searchMinimal()
	local shiftDistance = RNGPosition - lastRNGPosition
	local i = 0
	local j = 0
	if (shiftDistance == 0 and searchFoundPositions[1] ~= "No search has been completed") or searchFoundPositions[1] == "Yahaha You found me!" then
		return
	end
	if searchFoundPositions[1] == "No search has been completed" then
		searchLeftSeed = {memoryreadword(RNGBase+4), memoryreadword(RNGBase+2), memoryreadword(RNGBase+0)}
		searchRightSeed = {memoryreadword(RNGBase+4), memoryreadword(RNGBase+2), memoryreadword(RNGBase+0)}
		advanceRNGTable(searchLeftSeed, -1)
		searchLeftPosition = RNGPosition - 1
		searchRightPosition = RNGPosition
		
		if searchDirection == 1 then 
			searchLeftMinimal()
		else 
			searchRightMinimal()
		end
		
		--print("ONE")
		--print(searchFoundPositions)
		
		searchFoundPositions = {}
		
		--print(searchFoundPositions)
		--print("1.2")
		--print(leftFoundPositions)
		--print(rightFoundPositions)
		
		i = 1
		j = #leftFoundPositions
		while j > 0  do
			searchFoundPositions[i] = leftFoundPositions[j]
			i = i + 1
			j = j - 1
		end
		j = 1
		while j <= #rightFoundPositions  do
			searchFoundPositions[i] = rightFoundPositions[j]
			i = i + 1
			j = j + 1
		end
		--print("1.3")
		--print(searchFoundPositions)
	--else do an update
	else
		tablesort(searchFoundPositions)
		
		if searchDirection == 1 then 
			searchLeftMinimal()
		else 
			searchRightMinimal()
		end
		
		--print("TWO")
		--print(searchFoundPositions)
		--print(leftFoundPositions)
		--print(rightFoundPositions)
		if(shiftDistance < 0) then
			
			 i = 1
			while i <= #leftFoundPositions do
				tableinsert(searchFoundPositions, 1, leftFoundPositions[i])
				i = i + 1
			end
			
			while #searchFoundPositions > 0 and searchFoundPositions[#searchFoundPositions] >  searchRightBound + RNGPosition do
				tableremove(searchFoundPositions, #searchFoundPositions)
			end
			searchRightPosition = searchRightPosition + shiftDistance
			advanceRNGTable(searchRightSeed, shiftDistance)
			
		elseif(shiftDistance > 0) then
			
			 i = 1
			while i <= #rightFoundPositions do
				tableinsert(searchFoundPositions, #searchFoundPositions + 1, rightFoundPositions[i])
				i = i + 1
			end
			
			while #searchFoundPositions > 0 and searchFoundPositions[1] < searchLeftBound + RNGPosition do
				tableremove(searchFoundPositions, 1)
			end
			searchLeftPosition = searchLeftPosition + shiftDistance
			advanceRNGTable(searchLeftSeed, shiftDistance)
			
		end
	end
end

--binary search
function getRightStartIndex(list, value)
	if #list == 0 then
		return nil
	elseif #list == 1 then
		return 1
	end
	local leftBound = 1
	local rightBound = #list
	local index = mathfloor(#list / 2)
	
	while mathfloor((rightBound - leftBound + 1) / 2) > 0 do
		--print(list)
		--print(leftBound)
		--print(rightBound)
		--print(mathfloor((rightBound - leftBound + 1) / 2))
		if index <= 1 or index >= #list then
			return index
		elseif list[index - 1] <= value and list[index] >= value then
			return index
		elseif value < list[index] then
			rightBound = index
		else --value > list[index]
			leftBound = index
		end
		index = leftBound + mathfloor((rightBound - leftBound) / 2)
		--print("index: "..index)
	end
	--print("after loop")
	return index
end

function displaySearch()
	--print("display: ")
	--print(searchFoundPositions)
	search()
	local xDistance = 0
	local displayTable = {}
	local i = 1
	--print("display: ")
	--print(searchFoundPositions)
	if tonumber(searchFoundPositions[1]) == nil then
		displayTable = searchFoundPositions
		
	else
		--i = getRightStartIndex(searchFoundPositions, RNGPosition)
		while i <= #searchFoundPositions and searchFoundPositions[i] < RNGPosition do
			i = i + 1
		end
		rightStartIndex = i
		i = i - 2
		if i < 1 then
			i = 1
		end
		local j = i
		local displayCount = 1
		while j <= #searchFoundPositions and displayCount <= 5 do
			tableinsert(displayTable, #displayTable + 1, searchFoundPositions[j])
			displayCount = displayCount + 1
			j = j + 1
		end
		if i > #searchFoundPositions then
			i = #searchFoundPositions
		end
		j = i - 1
		while j > 0 and displayCount <= 5 do
			tableinsert(displayTable, 1, searchFoundPositions[j])
			displayCount = displayCount + 1
			j = j - 1
		end
		tablesort(displayTable)
		
	end
	if tonumber(displayTable[1]) == nil then
		guitext(0, 8, displayTable[1], "cyan")
		return
	end
	local color = "cyan"
	for i = 1, #displayTable, 1 do
		if displayTable[i] < RNGPosition then
			color = 0xFF90C0FF
		elseif displayTable[i] > RNGPosition then
			color = 0x00B0C0FF
		else
			color = "green"
		end
		guitext(xDistance, 8, displayTable[i], color)
		xDistance = xDistance + (#tostring(displayTable[i])) * 4 + 2
		if i < #displayTable then
			guitext(xDistance, 8, ",", "white")
			xDistance = xDistance + 5
		end
	end
	local j = rightStartIndex
	for i=1,20 do
		if tonumber(searchFoundPositions[j]) ~= nil and searchFoundPositions[j] == RNGPosition + (i-1)  and displaySearchOn then
			if(i == 1) then
				guitext(213, 8*(i-1), "--->", "green")
			else
				guitext(213, 8*(i-1), "--->", 0x00B0C0FF)
			end
			j = j + 1
		end
	end
	--print(displayTable)
end

function displaySearchMinimal()
	--print("display: ")
	--print(searchFoundPositions)
	searchMinimal()
	local xDistance = 0
	local displayTable = {}
	local i = 1
	--print("display: ")
	--print(searchFoundPositions)
	if tonumber(searchFoundPositions[1]) == nil then
		displayTable = searchFoundPositions
		
	else
		--i = getRightStartIndex(searchFoundPositions, RNGPosition)
		while i <= #searchFoundPositions and searchFoundPositions[i] < RNGPosition do
			i = i + 1
		end
		rightStartIndex = i
		i = i - 2
		if i < 1 then
			i = 1
		end
		local j = i
		local displayCount = 1
		while j <= #searchFoundPositions and displayCount <= 5 do
			tableinsert(displayTable, #displayTable + 1, searchFoundPositions[j])
			displayCount = displayCount + 1
			j = j + 1
		end
		if i > #searchFoundPositions then
			i = #searchFoundPositions
		end
		j = i - 1
		while j > 0 and displayCount <= 5 do
			tableinsert(displayTable, 1, searchFoundPositions[j])
			displayCount = displayCount + 1
			j = j - 1
		end
		tablesort(displayTable)
		
	end
	if tonumber(displayTable[1]) == nil then
		guitext(0, 8, displayTable[1], "cyan")
		return
	end
	local color = "cyan"
	for i = 1, #displayTable, 1 do
		if displayTable[i] < RNGPosition then
			color = 0xFF90C0FF
		elseif displayTable[i] > RNGPosition then
			color = 0x00B0C0FF
		else
			color = "green"
		end
		guitext(xDistance, 8, displayTable[i], color)
		xDistance = xDistance + (#tostring(displayTable[i])) * 4 + 2
		if i < #displayTable then
			guitext(xDistance, 8, ",", "white")
			xDistance = xDistance + 5
		end
	end
	local j = rightStartIndex
	for i=1,20 do
		if tonumber(searchFoundPositions[j]) ~= nil and searchFoundPositions[j] == RNGPosition + (i-1)  and displaySearchOn then
			if(i == 1) then
				guitext(213, 8*(i-1), "--->", "green")
			else
				guitext(213, 8*(i-1), "--->", 0x00B0C0FF)
			end
			j = j + 1
		end
	end
	--print(displayTable)
end

function displayHelp()
	guitext(45,25,"\'Q/W' - Decrement/Advance RNG\n'E/R' - Turn on/off AI phase script\n'U' - RNG display on/off\n'I' - Read SearchInputs.txt\n'O' - Search Result Display on/off\n'H' - Display Help\n'F/G' - Skip to left/right match\n'V' - Print Data\n'Y' - Print Total Exp\n'L' - Debug Functions\n'M + Arrows' - Skip Larger RNG Amounts\n'J + Arrows' - Minimal Search\n'K' - Return to 0 RN")
end

function obtainedexp()
	local level = 0x0202BE54
	local experience = 0x0202BE55
	local total = 0
	for i = 0, 7, 1 do
		total = total + (memoryreadbyte(level+(i*72))*100)
		if memoryreadbyte(experience+(i*72)) ~= 255 then
			total = total + memoryreadbyte(experience+(i*72))
		end
	end
	return total
end

function searchSkip(value)
	--Gets rid of duplicates and splits them in between both lists
	if backupLeftFoundPositions[1] == backupLeftFoundPositions[2] and backupLeftFoundPositions[1] ~= nil then 
		tableinsert(backupRightFoundPositions,1,backupLeftFoundPositions[1])
		tableremove(backupLeftFoundPositions,1)
	elseif backupRightFoundPositions[1] == backupRightFoundPositions[2] and backupRightFoundPositions[1] ~= nil then 
		tableinsert(backupLeftFoundPositions,1,backupRightFoundPositions[1])
		tableremove(backupRightFoundPositions,1)
	end
	
	--If a list is empty, copy the entry over from the other list
	if #backupLeftFoundPositions == 0 and backupRightFoundPositions[1] ~= nil then 
		tableinsert(backupLeftFoundPositions,1,backupRightFoundPositions[1])
	elseif #backupRightFoundPositions == 0 and backupLeftFoundPositions[1] ~= nil then 
		tableinsert(backupRightFoundPositions,1,backupLeftFoundPositions[1])
	end
	
	--Makes sure there are only 1 of the same number in both lists
	--if backupLeftFoundPositions[1] == backupRightFoundPositions[1] then 
	--	if #backupLeftFoundPositions > 1 then 
	--		tableremove(backupLeftFoundPositions,1)
	--	elseif #backupRightFoundPositions > 1 then 
	--		tableremove(backupRightFoundPositions,1)
	--	end
	--end
	
	if value == 1 then 
		if backupLeftFoundPositions[1] == RNGPosition then 
			while backupLeftFoundPositions[2] < RNGPosition do
				decrementRNG()
				updateRNGPosition()
			end
		elseif backupLeftFoundPositions[1] < RNGPosition then
			while backupLeftFoundPositions[1] < RNGPosition do
				decrementRNG()
				updateRNGPosition()
			end
		end
		tableinsert(backupRightFoundPositions,1,backupLeftFoundPositions[1])
		tableremove(backupLeftFoundPositions,1)
	else 
		if backupRightFoundPositions[1] == RNGPosition then 
			while backupRightFoundPositions[2] > RNGPosition do
				advanceRNG()
				updateRNGPosition()
			end
		elseif backupRightFoundPositions[1] > RNGPosition then
			while backupRightFoundPositions[1] > RNGPosition do
				advanceRNG()
				updateRNGPosition()
			end
		end 
		tableinsert(backupLeftFoundPositions,1,backupRightFoundPositions[1])
		tableremove(backupRightFoundPositions,1)
	end
end

function skipThousand(value)
	if value == 1 then 
		for p = skipThousandAmount,1,-1 do
			decrementRNG()
			updateRNGPosition()
		end
	else 
		for p = skipThousandAmount,1,-1 do
			advanceRNG()
			updateRNGPosition()
		end
	end
end

function updateBackup()
	if backupLeftFoundPositions[1] > RNGPosition then 
		if #backupLeftFoundPositions == 1 and #backupRightFoundPositions == 0 then 
			if backupLeftFoundPositions[1] == backupRightFoundPositions[1] then 
				
			else
				tableinsert(backupRightFoundPositions,1,backupLeftFoundPositions[1])
			end
		else
			tableinsert(backupRightFoundPositions,1,backupLeftFoundPositions[1])
			tableremove(backupLeftFoundPositions,1)
		end 
	elseif backupRightFoundPositions[1] < RNGPosition then
		if #backupRightFoundPositions == 1 and #backupLeftFoundPositions == 0 then 
			if backupRightFoundPositions[1] == backupLeftFoundPositions[1] then 
				
			else
				tableinsert(backupLeftFoundPositions,1,backupRightFoundPositions[1])
			end
		else
			tableinsert(backupLeftFoundPositions,1,backupRightFoundPositions[1])
			tableremove(backupRightFoundPositions,1)
		end
	end
end

function setupSkip(value)
	if value == 1 then
		backupLeftFoundPositions = leftFoundPositions
	elseif value == 2 then
		backupRightFoundPositions = rightFoundPositions
	elseif value == 3 then
		backupLeftFoundPositions = leftFoundPositions
		backupRightFoundPositions = rightFoundPositions
	end
	updateRNGPosition()
end

function battleInformation()
	print("--------------------")
	local pspd = 0x0203A502
	local phit = 0x0203A550
	local pcrt = 0x0203A556
	local php =  0x0203A55E
	--local pdmg = 0x0203A4D8

	local espd = 0x0203A582
	local ehit = 0x0203A5D0
	local ecrt = 0x0203A5D6
	local ehp =  0x0203A5DE
	--local edmg = 0x0203A5EF
	
	local patk = 0x0203A546
	local pdef = 0x0203A548
	local eatk = 0x0203A5C6
	local edef = 0x0203A5C8
	
	pdmg = memoryreadbyte(patk) - memoryreadbyte(edef)
	edmg = memoryreadbyte(eatk) - memoryreadbyte(pdef)
	
	--Checking who doubles
	local spdDiff = memoryreadbyte(pspd) - memoryreadbyte(espd)
	--Checking if anyone survives a crit/attack and whether or not to print a second attack
	
	local pRemainingHealth
	if memoryreadbyte(ecrt) > 0 then 
		pRemainingHealth = memoryreadbyte(php) - (edmg * 3)
	else
		pRemainingHealth = memoryreadbyte(php) - edmg
	end
	local eRemainingHealth
	if memoryreadbyte(pcrt) > 0 then 
		eRemainingHealth = memoryreadbyte(ehp) - (pdmg * 3)
	else
		eRemainingHealth = memoryreadbyte(ehp) - pdmg
	end
	
	local growth = memoryreaddword(0x3004E50)
	local growth = memoryreaddword(growth)
	local growthList = {}
	print("Growths of unit under cursor:")
	for p = 0x1C,0x22,0x01 do
		if memoryreadbyte(growth+p) == 0 then
			print("<100")
		elseif memoryreadbyte(growth+p) > 100 and memoryreadbyte(growth+p) < 200 then 
			print("<" .. (memoryreadbyte(growth+p) - 100))
		elseif memoryreadbyte(growth+p) > 200 then 
			print("<" .. (memoryreadbyte(growth+p) - 200))
		else
			print("<" .. memoryreadbyte(growth+p))
		end
	end
	print("Player hit and crit:")
	if memoryreadbyte(phit) == 100 or memoryreadbyte(phit) == 0 then  
	else 
		print("h>=" .. memoryreadbyte(phit))
		if spdDiff >= 4 then 
			print("h>=" .. memoryreadbyte(phit))
		end
		print("\n")
	end
	if memoryreadbyte(phit) == 0 then 
		--You have a 0 chance of hitting
		print("h>=0")
		if spdDiff >= 4 then 
			print("h>=0")
		end
	else
		--You have a >0 chance of hitting
		print("h<" .. memoryreadbyte(phit))
		if memoryreadbyte(pcrt) == 0 then 
			print("<100")
		else 
			if (memoryreadbyte(ehp) - pdmg) <= 0 then 
				print("<100")
			else
				print("<" .. memoryreadbyte(pcrt))
			end
		end
		if spdDiff >= 4 and eRemainingHealth >= 0 then 
			print("h<" .. memoryreadbyte(phit))
			if memoryreadbyte(pcrt) == 0 then 
				print("<100")
			else 
				if (memoryreadbyte(ehp) - (pdmg * 4)) <= 0 then 
					print("<100")
					eRemainingHealth = eRemainingHealth - pdmg
				else
					print("<" .. memoryreadbyte(pcrt))
					eRemainingHealth = eRemainingHealth - (pdmg * 3)
				end
			end
		end
	end
	if eRemainingHealth > 0 then
		print("Enemy lives with " .. eRemainingHealth)
	end 
	
	print("Enemy hit and crit:")
	if memoryreadbyte(ehit) == 100 or memoryreadbyte(ehit) == 0 then  
	else 
		print("h>=" .. memoryreadbyte(ehit))
		if spdDiff <= -4 then 
			print("h>=" .. memoryreadbyte(ehit))
		end
		print("\n")
	end
	if memoryreadbyte(ehit) == 0 then 
		--You have a 0 chance of hitting
		print("h>=0")
		if spdDiff <= -4 then 
			print("h>=0")
		end
	else
		--You have a >0 chance of hitting
		print("h<" .. memoryreadbyte(ehit))
		if memoryreadbyte(ecrt) == 0 then 
			print("<100")
		else 
			if (memoryreadbyte(php) - edmg) <= 0 then 
				print("<100")
			else
				print("<" .. memoryreadbyte(ecrt))
			end
		end
		if spdDiff <= -4 and eRemainingHealth >= 0 then 
			print("h<" .. memoryreadbyte(ehit))
			if memoryreadbyte(ecrt) == 0 then 
				print("<100")
			else 
				if (memoryreadbyte(php) - (edmg * 4)) <= 0 then 
					print("<100")
					pRemainingHealth = pRemainingHealth - edmg
				else
					print("<" .. memoryreadbyte(ecrt))
					pRemainingHealth = pRemainingHealth - (edmg * 3)
				end
			end
		end
	end
	if pRemainingHealth > 0 then
		print("Player lives with " .. pRemainingHealth)
	end 
end

function checkForUserInput()
	
	--Enable Enemy Phase
	if userInput.E then
		AIPhaseScriptEnabled = true
	end
	
	--Disable Enemy Phase
	if userInput.R then
		AIPhaseScriptEnabled = false
	end
	
	--Skip to left search
	if userInput.F and heldDown['F'] == false then
		if pcall(searchSkip, 1) then 
		else 
			--print("LError")
		end
	end

	--Skip to right search
	if userInput.G and heldDown['G'] == false then
		if pcall(searchSkip) then 
		else
			--print("RError")
		end
	end
	
	--Print obtained EXP
	if userInput.Y and heldDown['Y'] == false then
		print("EXP: " .. obtainedexp())
	end
	
	--Back to 0 RNG
	if userInput.K and heldDown['K'] == false then
		while RNGPosition ~= 0 do
			if RNGPosition > 0 then 
				decrementRNG()
				updateRNGPosition()
			elseif RNGPosition < 0 then 
				advanceRNG()
				updateRNGPosition()
			end
		end
	end
	
	--Reset search function
	if userInput.L and heldDown['L'] == false then
		--print("Backup Completed!")
		--setupSkip()
		
		--print("Reset Completed!")
		--leftFoundPositions = {}
		--backupLeftFoundPositions = {}
		--rightFoundPositions = {}
		--backupRightFoundPositions = {}
		
		print("--------------------------------------------")
		print(backupLeftFoundPositions)
		print(backupLeftFoundPositions[1])
		print(#backupLeftFoundPositions)
		print(backupRightFoundPositions)
		print(backupRightFoundPositions[1])
		print(#backupRightFoundPositions)
		print(RNGPosition)
	end
	
	--Print enemy and user data
	if userInput.V and heldDown['V'] == false then
		battleInformation()
	end
	
	--Search from inputs
	if userInput.I and heldDown['I'] == false then
		-- read in file
		setupTimerLeft = 0
		setupTimerRight = 0
		readInSearchFile()
		displayMinimalSearchOn = false
		displaySearchOn = true
	end
	
	--Minimal Search
	if userInput.J then
		if userInput.left and heldDown['left'] == false then
			searchDirection = 1
			setupTimerLeft = 0
			setupTimerRight = 0
			readInSearchFile()
			displayMinimalSearchOn = true 
			displaySearchOn = false
		elseif userInput.right and heldDown['right'] == false then
			searchDirection = 2
			setupTimerLeft = 0
			setupTimerRight = 0
			readInSearchFile()
			displayMinimalSearchOn = true 
			displaySearchOn = false
		end
	end
	
	--Move larger RNG units
	if userInput.M then
		if userInput.up and heldDown['up'] == false then
			skipThousandAmount = skipThousandAmount * 10
			print("Skip Amount is now " .. skipThousandAmount)
		end
		
		if userInput.down and heldDown['down'] == false then
			skipThousandAmount = skipThousandAmount / 10
			if skipThousandAmount < 1 then
				skipThousandAmount = 1
			end
			print("Skip Amount is now " .. skipThousandAmount)
		end
		
		if userInput.left and heldDown['left'] == false then
			skipThousand(1)
		end
		
		if userInput.right and heldDown['right'] == false then
			skipThousand()
		end
	end
	
	--Hide search display
	if userInput.O and heldDown['O'] == false and displayRNG then
		-- toggle search display
		displaySearchOn = false
		displayMinimalSearchOn = false
		-- if you turn the search display off, do a new search from scratch next time.
		if not displaySearchOn or not displayMinimalSearchOn then
			searchFoundPositions[1] = "No search has been completed"
			--print("AHHH")
		end
	end
	
	--Show help display
	if userInput.H and heldDown['H'] == false then
		-- help display on/off
		displayHelpOn = not displayHelpOn
	end
	
	--Hide UI completely
	if userInput.U and heldDown['U'] == false then
		-- help display on/off
		displayRNG = not displayRNG
	end
	
	for key, value in pairs(heldDown) do
		heldDown[key] = true
		if userInput[key] == nil then
			heldDown[key] = false
		end
	end
	
	--Ugly button holding logic
	--Move RNG units
	if userInput.W then
		holdButtonCounter = holdButtonCounter + 1
		if holdButtonCounter >= holdButtonCounterLimit - acceleration then
			advanceRNG() -- Important function call is here
			holdButtonCounter = 0
			staticCounter = staticCounter + 1
			if staticCounter % 10 then
				if acceleration < holdButtonCounterLimit then
					acceleration = acceleration + 1
				end
			end
		end
	-- Ugly button holding logic
	elseif userInput.Q then
		holdButtonCounter = holdButtonCounter + 1
		if holdButtonCounter >= holdButtonCounterLimit - acceleration then
			decrementRNG() -- Important function call is here
			holdButtonCounter = 0
			staticCounter = staticCounter + 1
			if staticCounter % 10 then
				if acceleration < holdButtonCounterLimit then
					acceleration = acceleration + 1
				end
			end
		end
	else
		holdButtonCounter = holdButtonCounterLimit
		acceleration = 0
	end
	
end

function AIPhaseScript()
	local escape = false
	local battleLimit = 1000
	local key1 = {}
	key1['A'] = true

	-- Create a script-only savestate
	RNGCheck = savestate.create()
	savestatesave(RNGCheck)
	local currentBattle = 0
	while not escape do
	  
	  	savestateload(RNGCheck)
		
		-- RNG Loop
		for i = 1, currentBattle, 1 do
			advanceRNG()
		end
		
		local startingNextTableValue = nextSuperRN(memoryreadword(RNGBase + 4), memoryreadword(RNGBase + 2), memoryreadword(RNGBase + 0))
		updateRNGPosition()
		local startingPosition = RNGPosition
		local startFrame = emu.framecount()

		-- Phase Loop
		while memoryreadbyte(phaseMap[currentGame]) ~= 0 do
			userInput = input.get()
			
			if userInput.R then
				AIPhaseScriptEnabled = false
				escape = true
				break
			end
			
			key1.start = (not key1.start) or nil -- press start every two frames
			key1.b = not key1.start
			joypadset(1, key1)
			
			updateRNGPosition()
			emu.frameadvance()
			
			printRNG(numDisplayedRNs)
			guitext(0, 0, RNGPosition, "green")
			guitext(0, 8, stringformat('%d', currentBattle))
		end
		
		currentBattle = currentBattle + 1
		
		if escape == false then
			print("Initial RN is "..superRNToRN(startingNextTableValue).." at relative position "..startingPosition
			..". Phase took "..emu.framecount() - startFrame.." frames. ("..(emu.framecount() - startFrame)/60 .." sec)")
		end
		
	end
end

while true do
	userInput = input.get()
	if consecutiveUpdatesFailedCounter >= 5 then
		checkForUserInput()
		printRNG(numDisplayedRNs)
		if userInput.T == true then
			updateRNGPosition()
			print("check")
		else
			consecutiveUpdatesFailedCounter = consecutiveUpdatesFailedCounter + 1
		end
		guitext(0, 0, "Position not updated", "red")
		guitext(0, 8, "you can't jump more than "..updateLoopLimit.." positions at once", "red")
		guitext(0, 16, "press 'T' to try again", "red")
		emu.frameadvance()
	else
		if AIPhaseScriptEnabled and memoryreadbyte(phaseMap[currentGame]) ~= 0 then
			AIPhaseScript()
		else
			checkForUserInput()
			updateRNGPosition()
			
			if displayRNG then
				printRNG(numDisplayedRNs)
				guitext(0, 0, RNGPosition, "green")
			end
			
			if displaySearchOn and displayRNG then
				displaySearch()
				pcall(updateBackup)
			end
			
			if displayMinimalSearchOn and displayRNG then
				displaySearchMinimal()
				pcall(updateBackup)
			end
			
			if displayHelpOn then
				displayHelp()
			end
			
			emu.frameadvance()
			
		end
	end
end