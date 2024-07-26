-- Original author: Scott Adkins <adkinss@gmail.com> (Zucanthor)
-- This program monitors work requests for the Minecolonies Warehouse and
-- tries to fulfill requests from the AE2 network. If the item isn't in the colony network,
-- it will get it from the main network. If it's not in the main network, it will check if it can be crafted and if so, it will craft it.

-- Setup requirements:
--   * 1 ComputerCraft Computer
--   * 1 or more ComputerCraft Monitors (recommend 3x3 advanced monitors)
--   * 1 Advanced Peripheral Colony Integrator
--   * 2 Advanced Peripheral AE2 Bridges
--   * 1 Chest or other storage container

----------------------------------------------------------------------------
-- INITIALIZATION
----------------------------------------------------------------------------

local monitor = peripheral.find("monitor")
if not monitor then error("Monitor not found.") end
monitor.setTextScale(0.5)
monitor.clear()
monitor.setCursorPos(1, 1)
monitor.setCursorBlink(false)
print("Monitor initialized.")

local bridgeColony = peripheral.wrap("left")
if not bridgeColony then error("ME Bridge (Colony) not found.") end
print("ME Bridge (Colony) initialized.")

local bridgeMain = peripheral.wrap("right")
if not bridgeMain then error("ME Bridge (Main) not found.") end
print("ME Bridge (Main) initialized.")

local colony = peripheral.find("colonyIntegrator")
if not colony then error("Colony Integrator not found.") end
if not colony.isInColony then error("Colony Integrator is not in a colony.") end
print("Colony Integrator initialized.")

local storage = "south"
print("Storage initialized.")

local settings = {
    scanInterval = 30,
    logFile = "RSWarehouse.log"
}

function loadSettings()
    if fs.exists("settings.cfg") then
        local file = fs.open("settings.cfg", "r")
        settings = textutils.unserialize(file.readAll())
        file.close()
    end
end

function saveSettings()
    local file = fs.open("settings.cfg", "w")
    file.write(textutils.serialize(settings))
    file.close()
end

-- Load settings
loadSettings()

local logFile = settings.logFile

-- Statistics data
local requesters = {}
local itemsRequested = {}
local currentRequests = {} -- Store current requests for detail viewing

----------------------------------------------------------------------------
-- FUNCTIONS
----------------------------------------------------------------------------

function mPrintRowJustified(mon, y, pos, text, ...)
    local w, h = mon.getSize()
    local fg = mon.getTextColor()
    local bg = mon.getBackgroundColor()

    local x = 1
    if pos == "center" then x = math.floor((w - #text) / 2) end
    if pos == "right" then x = w - #text end

    if #arg > 0 then mon.setTextColor(arg[1]) end
    if #arg > 1 then mon.setBackgroundColor(arg[2]) end
    mon.setCursorPos(x, y)
    mon.write(text)
    mon.setTextColor(fg)
    mon.setBackgroundColor(bg)
end

function isdigit(c)
    return c >= '0' and c <= '9'
end

function logMessage(message)
    local file = fs.open("activity.log", "a")
    file.writeLine(os.date("%Y-%m-%d %H:%M:%S") .. " - " .. message)
    file.close()
end

function displayTimer(mon, t)
    local now = os.time()

    local cycle, cycle_color
    if now >= 4 and now < 6 then
        cycle = "sunrise"
        cycle_color = colors.orange
    elseif now >= 6 and now < 18 then
        cycle = "day"
        cycle_color = colors.yellow
    elseif now >= 18 and now < 19.5 then
        cycle = "sunset"
        cycle_color = colors.orange
    else
        cycle = "night"
        cycle_color = colors.red
    end

    local timer_color = colors.orange
    if t < 15 then timer_color = colors.yellow end
    if t < 5 then timer_color = colors.red end

    mPrintRowJustified(mon, 1, "left", string.format("Time: %s [%s]    ", textutils.formatTime(now, false), cycle), cycle_color)
    if cycle ~= "night" then
        mPrintRowJustified(mon, 1, "right", string.format("    Remaining: %ss", t), timer_color)
    else
        mPrintRowJustified(mon, 1, "right", "    Remaining: PAUSED", colors.red)
    end
end

function scanWorkRequests(mon, bridgeColony, bridgeMain, storage)
    local file = fs.open(logFile, "w")
    print("\nScan starting at", textutils.formatTime(os.time(), false) .. " (" .. os.time() .. ").")
    logMessage("Scan started")

    local builder_list = {}
    local nonbuilder_list = {}
    local equipment_list = {}
    currentRequests = {} -- Clear current requests

    local itemsColony = bridgeColony.listItems()
    local item_array_colony = {}
    for _, item in ipairs(itemsColony) do
        if not item.nbt or (next(item.nbt) and item.nbt.id) then
            item_array_colony[item.name] = item.amount
        end
    end

    local itemsMain = bridgeMain.listItems()
    local item_array_main = {}
    for _, item in ipairs(itemsMain) do
        if not item.nbt or (next(item.nbt) and item.nbt.id) then
            item_array_main[item.name] = item.amount
        end
    end

    local workRequests = colony.getRequests()
    for _, request in pairs(workRequests) do
        local name = request.name
        local item = request.items[1].name
        local target = request.target
        local desc = request.desc
        local needed = request.count
        local provided = 0

        local target_words = {}
        for word in target:gmatch("%S+") do
            table.insert(target_words, word)
        end

        local target_name = target_words[#target_words - 1] and (target_words[#target_words - 1] .. " " .. target_words[#target_words]) or target
        local target_type = table.concat(target_words, " ", 1, #target_words - 2)

        local useRS = not (desc:find("Tool of class") or name:match("Hoe|Shovel|Axe|Pickaxe|Bow|Sword|Shield|Helmet|Leather Cap|Chestplate|Tunic|Pants|Leggings|Boots|Rallying Banner|Crafter|Compostable|Fertilizer|Flowers|Food|Fuel|Smeltable Ore|Stack List"))

        local color = colors.blue
        if useRS then
            if item_array_colony[item] then
                provided = bridgeColony.exportItem({name = item, count = needed}, storage)
            elseif item_array_main[item] then
                provided = bridgeMain.exportItem({name = item, count = needed}, storage)
            end

            color = colors.green
            if provided < needed then
                if bridgeColony.isItemCrafting({name = item}) or bridgeMain.isItemCrafting({name = item}) then
                    color = colors.yellow
                    print("[Crafting]", item)
                    logMessage("[Crafting] " .. item)
                else
                    if bridgeColony.craftItem({name = item, count = needed}) or bridgeMain.craftItem({name = item, count = needed}) then
                        color = colors.yellow
                        print("[Scheduled]", needed, "x", item)
                        logMessage("[Scheduled] " .. needed .. "x " .. item)
                    else
                        color = colors.red
                        print("[Failed to Craft]", item)
                        logMessage("[Failed to Craft] " .. item)
                    end
                end
            end
        else
            local nameString = name .. " [" .. target .. "]"
            print("[Skipped]", nameString)
            logMessage("[Skipped] " .. nameString)
        end

        -- Update statistics
        requesters[target_name] = (requesters[target_name] or 0) + 1
        itemsRequested[item] = (itemsRequested[item] or 0) + provided

        if desc:find("of class") then
            local level = "Any Level"
            if desc:find("with maximal level:Leather") then level = "Leather" end
            if desc:find("with maximal level:Gold") then level = "Gold" end
            if desc:find("with maximal level:Chain") then level = "Chain" end
            if desc:find("with maximal level:Wood or Gold") then level = "Wood or Gold" end
            if desc:find("with maximal level:Stone") then level = "Stone" end
            if desc:find("with maximal level:Iron") then level = "Iron" end
            if desc:find("with maximal level:Diamond") then level = "Diamond" end
            local new_name = level .. " " .. name
            if level == "Any Level" then new_name = name .. " of any level" end
            local new_target = target_type .. " " .. target_name
            table.insert(equipment_list, {name = new_name, target = new_target, needed = needed, provided = provided, color = color})
        elseif target:find("Builder") then
            table.insert(builder_list, {name = name, item = item, target = target_name, needed = needed, provided = provided, color = color})
        else
            local new_target = target_type .. " " .. target_name
            table.insert(nonbuilder_list, {name = name, target = new_target, needed = needed, provided = provided, color = color})
        end
        -- Store request details for detail viewing
        table.insert(currentRequests, request)
    end

    local row = 3
    mon.clear()

    local function displayRequests(title, list)
        if #list > 0 then
            mPrintRowJustified(mon, row, "center", title, colors.cyan)
            row = row + 1
            for _, entry in ipairs(list) do
                local text = string.format("%d %s", entry.needed, entry.name)
                if isdigit(entry.name:sub(1, 1)) then
                    text = string.format("%d/%s", entry.provided, entry.name)
                end
                mPrintRowJustified(mon, row, "left", text, entry.color)
                mPrintRowJustified(mon, row, "right", " " .. entry.target, entry.color)
                row = row + 1
            end
        end
    end

    displayRequests("Equipment", equipment_list)
    displayRequests("Builder Requests", builder_list)
    displayRequests("Nonbuilder Requests", nonbuilder_list)

    if row == 3 then mPrintRowJustified(mon, row, "center", "No Open Requests", colors.red) end
    print("Scan completed at", textutils.formatTime(os.time(), false) .. " (" .. os.time() .. ").")
    logMessage("Scan completed")
    file.close()
end

function displayRequestDetails(request)
    local row = 3
    monitor.clear()
    mPrintRowJustified(monitor, row, "center", "Request Details", colors.cyan)
    row = row + 2
    mPrintRowJustified(monitor, row, "left", "Item: " .. request.name, colors.lightBlue)
    row = row + 1
    mPrintRowJustified(monitor, row, "left", "Quantity: " .. request.count, colors.lightBlue)
    row = row + 1
    mPrintRowJustified(monitor, row, "left", "Target: " .. request.target, colors.lightBlue)
    row = row + 1
    mPrintRowJustified(monitor, row, "left", "Description: " .. request.desc, colors.lightBlue)
    displayNavBar(monitor)
end

function displayStatistics(mon)
    local row = 3
    mon.clear()
    
    mPrintRowJustified(mon, row, "center", "Top Requesters", colors.cyan)
    row = row + 1
    local sortedRequesters = {}
    for requester, count in pairs(requesters) do
        table.insert(sortedRequesters, {requester = requester, count = count})
    end
    table.sort(sortedRequesters, function(a, b) return a.count > b.count end)
    for _, entry in ipairs(sortedRequesters) do
        mPrintRowJustified(mon, row, "left", entry.requester, colors.blue)
        mPrintRowJustified(mon, row, "right", tostring(entry.count), colors.blue)
        row = row + 1
    end

    row = row + 1
    mPrintRowJustified(mon, row, "center", "Top Requested Items", colors.cyan)
    row = row + 1
    local sortedItems = {}
    for item, count in pairs(itemsRequested) do
        table.insert(sortedItems, {item = item, count = count})
    end
    table.sort(sortedItems, function(a, b) return a.count > b.count end)
    for _, entry in ipairs(sortedItems) do
        mPrintRowJustified(mon, row, "left", entry.item, colors.green)
        mPrintRowJustified(mon, row, "right", tostring(entry.count), colors.green)
        row = row + 1
    end

    if row == 3 then mPrintRowJustified(mon, row, "center", "No Statistics Available", colors.red) end
    displayNavBar(mon)
end

function displayNavBar(mon)
    local w, h = mon.getSize()
    local barY = h
    mon.setCursorPos(1, barY)
    mon.setBackgroundColor(colors.gray)
    mon.clearLine()
    mPrintRowJustified(mon, barY, "left", "[Requests]", colors.white, colors.gray)
    mPrintRowJustified(mon, barY, "center", "[Details]", colors.white, colors.gray)
    mPrintRowJustified(mon, barY, "right", "[Statistics]", colors.white, colors.gray)
    mon.setBackgroundColor(colors.black)
end

----------------------------------------------------------------------------
-- MAIN
----------------------------------------------------------------------------

local time_between_runs = settings.scanInterval
local current_run = time_between_runs
local viewMode = "requests" -- "requests", "details", or "statistics"

displayNavBar(monitor)
scanWorkRequests(monitor, bridgeColony, bridgeMain, storage)
local TIMER = os.startTimer(1)

while true do
    local e = {os.pullEvent()}
    if e[1] == "timer" and e[2] == TIMER then
        if viewMode == "requests" then
            local now = os.time()
            if now >= 5 and now < 19.5 then
                current_run = current_run - 1
                if current_run <= 0 then
                    scanWorkRequests(monitor, bridgeColony, bridgeMain, storage)
                    current_run = time_between_runs
                end
            end
            displayTimer(monitor, current_run)
        end
        displayNavBar(monitor)
        TIMER = os.startTimer(1)
    elseif e[1] == "monitor_touch" then
        os.cancelTimer(TIMER)
        local x, y = e[3], e[4]
        local w, h = monitor.getSize()
        if y == h then
            if x <= w / 3 then
                viewMode = "requests"
                scanWorkRequests(monitor, bridgeColony, bridgeMain, storage)
            elseif x > w / 3 and x <= 2 * w / 3 then
                viewMode = "details"
                local selectedRequestIndex = math.floor((y - 3) / 2) + 1
                if currentRequests[selectedRequestIndex] then
                    displayRequestDetails(currentRequests[selectedRequestIndex])
                else
                    displayNavBar(monitor)
                end
            else
                viewMode = "statistics"
                displayStatistics(monitor)
            end
        end
        displayNavBar(monitor)
        current_run = time_between_runs
        TIMER = os.startTimer(1)
    end
end
