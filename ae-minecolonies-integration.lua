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

local logFile = "RSWarehouse.log"
local currentTab = "Requests"

----------------------------------------------------------------------------
-- FUNCTIONS
----------------------------------------------------------------------------

function drawMenuBar(mon)
    local w, _ = mon.getSize()
    mon.setCursorPos(1, 1)
    mon.setBackgroundColor(colors.gray)
    mon.setTextColor(colors.white)
    mon.clearLine()
    mon.write(" Requests ")
    mon.setCursorPos(w - 10, 1)
    mon.write(" Statistics ")
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)
end

function mPrintRowJustified(mon, y, pos, text, ...)
    local w, _ = mon.getSize()
    local fg = mon.getTextColor()
    local bg = mon.getBackgroundColor()

    local x = 2  -- Start at 2 to avoid the box
    if pos == "center" then x = math.floor((w - #text) / 2) end
    if pos == "right" then x = w - #text - 1 end  -- Adjusted to avoid the box

    if #arg > 0 then mon.setTextColor(arg[1]) end
    if #arg > 1 then mon.setBackgroundColor(arg[2]) end
    mon.setCursorPos(x, y)
    mon.write(text)
    mon.setTextColor(fg)
    mon.setBackgroundColor(bg)
end

function drawBox(mon, x1, y1, x2, y2)
    mon.setCursorPos(x1, y1)
    mon.write(string.rep("-", x2 - x1 + 1))
    mon.setCursorPos(x1, y2)
    mon.write(string.rep("-", x2 - x1 + 1))
    for y = y1 + 1, y2 - 1 do
        mon.setCursorPos(x1, y)
        mon.write("|")
        mon.setCursorPos(x2, y)
        mon.write("|")
    end
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

    mPrintRowJustified(mon, 2, "left", string.format("Time: %s [%s]    ", textutils.formatTime(now, false), cycle), cycle_color)
    if cycle ~= "night" then
        mPrintRowJustified(mon, 2, "right", string.format("    Remaining: %ss", t), timer_color)
    else
        mPrintRowJustified(mon, 2, "right", "    Remaining: PAUSED", colors.red)
    end
end

function scanWorkRequests()
    local builder_list = {}
    local nonbuilder_list = {}
    local equipment_list = {}

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

        local target_name = target_words[#target_words - 2] and (target_words[#target_words - 2] .. " " .. target_words[#target_words]) or target
        local target_type = table.concat(target_words, " ", 1, #target_words - 3) or ""

        local useRS = not (desc:find("Tool of class") or name:match("Hoe|Shovel|Axe|Pickaxe|Bow|Sword|Shield|Helmet|Leather Cap|Chestplate|Tunic|Pants|Leggings|Boots|Rallying Banner|Crafter|Compostable|Fertilizer|Flowers|Food|Fuel|Smeltable Ore|Stack List"))

        local color = colors.blue
        if useRS then
            if item_array_colony[item] then
                provided = bridgeColony.exportItem({name = item, count = needed}, storage)
            elseif item_array_main[item] then
                local exportCount = math.min(needed - provided, item_array_main[item])
                provided = provided + bridgeMain.exportItem({name = item, count = exportCount}, storage)
                bridgeColony.importItem({name = item, count = exportCount}, storage)
            end

            color = colors.green
            if provided < needed then
                if bridgeColony.isItemCrafting({name = item}) or bridgeMain.isItemCrafting({name = item}) then
                    color = colors.yellow
                    print("[Crafting]", item)
                else
                    if bridgeColony.craftItem({name = item, count = needed}) or bridgeMain.craftItem({name = item, count = needed}) then
                        color = colors.yellow
                        print("[Scheduled]", needed, "x", item)
                    else
                        color = colors.red
                        print("[Failed to Craft]", item)
                    end
                end
            end
        else
            local nameString = name .. " [" .. target .. "]"
            print("[Skipped]", nameString)
        end

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
    end

    return builder_list, nonbuilder_list, equipment_list
end

function isdigit(c)
    return c >= '0' and c <= '9'
end


function displayRequests(mon)
    local builder_list, nonbuilder_list, equipment_list = scanWorkRequests()

    local row = 4
    local w, h = mon.getSize()
    mon.clear()
    drawMenuBar(mon)
    drawBox(mon, 1, 2, w, h)
    displayTimer(mon, current_run)  -- Ensure timer is displayed

    local function displayList(title, list)
        if #list > 0 then
            mPrintRowJustified(mon, row, "center", title)
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

    displayList("Equipment", equipment_list)
    displayList("Builder Requests", builder_list)
    displayList("Nonbuilder Requests", nonbuilder_list)

    if row == 4 then mPrintRowJustified(mon, row, "center", "No Open Requests") end
end

function displayStatistics(mon)
    local row = 4
    local w, h = mon.getSize()
    mon.clear()
    drawMenuBar(mon)
    drawBox(mon, 1, 2, w, h)
    displayTimer(mon, current_run)  -- Ensure timer is displayed

    mPrintRowJustified(mon, row, "center", "Statistics View")
    row = row + 1
    -- Add statistics display logic here
    mPrintRowJustified(mon, row, "center", "Statistics not implemented yet.")
end


function handleMonitorTouch(x, y)
    local w, _ = monitor.getSize()
    if y == 1 then
        if x <= 10 then
            currentTab = "Requests"
        elseif x >= w - 10 then
            currentTab = "Statistics"
        end
    end
end

----------------------------------------------------------------------------
-- MAIN
----------------------------------------------------------------------------

local time_between_runs = 30
current_run = time_between_runs  -- Make current_run global
displayRequests(monitor)
displayTimer(monitor, current_run)
local TIMER = os.startTimer(1)

while true do
    local e = {os.pullEvent()}
    if e[1] == "timer" and e[2] == TIMER then
        local now = os.time()
        if now >= 5 and now < 19.5 then
            current_run = current_run - 1
            if current_run <= 0 then
                if currentTab == "Requests" then
                    displayRequests(monitor)
                elseif currentTab == "Statistics" then
                    displayStatistics(monitor)
                end
                current_run = time_between_runs
            end
        end
        displayTimer(monitor, current_run)
        TIMER = os.startTimer(1)
    elseif e[1] == "monitor_touch" then
        handleMonitorTouch(e[3], e[4])
        if currentTab == "Requests" then
            displayRequests(monitor)
        elseif currentTab == "Statistics" then
            displayStatistics(monitor)
        end
    end
end

