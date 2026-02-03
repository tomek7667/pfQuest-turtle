-- Initialize all static variables
local loc = GetLocale()
local dbs = { "items", "quests", "quests-itemreq", "objects", "units", "zones", "professions", "areatrigger", "refloot" }
local noloc = { "items", "quests", "objects", "units" }

-- Patch databases to merge TurtleWoW data
local function patchtable(base, diff)
  for k, v in pairs(diff) do
    if type(v) == "string" and v == "_" then
      base[k] = nil
    else
      base[k] = v
    end
  end
end

-- Detect a typo from old clients and re-apply the typo to the zones table
-- This is a workaround which is required until all clients are updated
for id, name in pairs({GetMapZones(2)}) do
  if name == "Northwind " then
    pfDB["zones"]["enUS-turtle"][5581] = "Northwind "
  end
end

local loc_core, loc_update
for _, db in pairs(dbs) do
  if pfDB[db]["data-turtle"] then
    patchtable(pfDB[db]["data"], pfDB[db]["data-turtle"])
  end

  for loc, _ in pairs(pfDB.locales) do
    if pfDB[db][loc] and pfDB[db][loc.."-turtle"] then
      loc_update = pfDB[db][loc.."-turtle"] or pfDB[db]["enUS-turtle"]
      patchtable(pfDB[db][loc], loc_update)
    end
  end
end

loc_core = pfDB["professions"][loc] or pfDB["professions"]["enUS"]
loc_update = pfDB["professions"][loc.."-turtle"] or pfDB["professions"]["enUS-turtle"]
if loc_update then patchtable(loc_core, loc_update) end

if pfDB["minimap-turtle"] then patchtable(pfDB["minimap"], pfDB["minimap-turtle"]) end
if pfDB["meta-turtle"] then patchtable(pfDB["meta"], pfDB["meta-turtle"]) end

-- Configuration: Color custom TurtleWoW quests to distinguish them from classic quests
local CUSTOM_QUEST_COLOR = "|cff48d1cc"  -- Teal/cyan color
local COLOR_END = "|r"
local CUSTOM_QUEST_ID_THRESHOLD = 40000  -- Custom TurtleWoW quests start at ID 40000

-- Detect german client patch and switch some databases
if TURTLE_DE_PATCH then
  pfDB["zones"]["loc"] = pfDB["zones"]["deDE"] or pfDB["zones"]["enUS"]
  pfDB["professions"]["loc"] = pfDB["professions"]["deDE"] or pfDB["professions"]["enUS"]
end

-- Update bitmasks to include custom races
if pfDB.bitraces then
  pfDB.bitraces[256] = "Goblin"
  pfDB.bitraces[512] = "BloodElf"
end

-- Use turtle-wow database url
pfQuest.dburl = "https://database.turtle-wow.org/?quest="

-- Disable Minimap in custom dungeon maps
function pfMap:HasMinimap(map_id)
  -- disable dungeon minimap
  local has_minimap = not IsInInstance()

  -- enable dungeon minimap if continent is less then 3 (e.g AV)
  if IsInInstance() and GetCurrentMapContinent() < 3 then
    has_minimap = true
  end

  return has_minimap
end

-- Override map node rendering to make custom TurtleWoW quest icons cyan
-- This hooks into pfMap's UpdateNode function to color quest markers
local original_UpdateNode = pfMap.UpdateNode
function pfMap:UpdateNode(frame, node, color, obj, distance)
  -- Call original function first
  original_UpdateNode(self, frame, node, color, obj, distance)
  
  -- Check if this node is a quest icon (has texture path) with a custom quest ID
  -- Note: frame.texture is the texture path string, frame.tex is the texture object
  if frame.questid and frame.texture and tonumber(frame.questid) >= CUSTOM_QUEST_ID_THRESHOLD then
    -- Apply cyan color to custom TurtleWoW quest icons
    -- RGB values: 0.28, 0.82, 0.8 matches |cff48d1cc
    if frame.tex and frame.tex.SetVertexColor then
      frame.tex:SetVertexColor(0.28, 0.82, 0.8, 1)
    end
  end
end

-- Reload all pfQuest internal database shortcuts
pfDatabase:Reload()

local function strsplit(delimiter, subject)
  if not subject then return nil end
  local delimiter, fields = delimiter or ":", {}
  local pattern = string.format("([^%s]+)", delimiter)
  string.gsub(subject, pattern, function(c) fields[table.getn(fields)+1] = c end)
  return unpack(fields)
end

-- Complete quest id including all pre quests
local function complete(history, qid)
  -- ignore empty or broken questid
  if not qid or not tonumber(qid) then return end

  -- mark quest as complete
  local time = pfQuest_history[qid] and pfQuest_history[qid][1] or 0
  local level = pfQuest_history[qid] and pfQuest_history[qid][2] or 0
  history[qid] = { time, level }

  -- complete all quests that are closed by the selcted one
  local close = pfDB["quests"]["data"][qid] and pfDB["quests"]["data"][qid]["close"]
  if close then
    for _, qid in pairs(close) do
      if not history[qid] then complete(history, qid) end
    end
  end

  -- make sure all prequests are marked as done aswell
  local prequests = pfDB["quests"]["data"][qid] and pfDB["quests"]["data"][qid]["pre"]
  if prequests then
    for _, qid in pairs(prequests) do
      if not history[qid] then complete(history, qid) end
    end
  end
end

-- Temporary workaround for a faction group translation error

-- Add function to query for quest completion
local query = CreateFrame("Frame")
query:Hide()

query:SetScript("OnEvent", function()
  if arg1 == "TWQUEST" then
    for _, qid in pairs({strsplit(" ", arg2)}) do
      complete(this.history, tonumber(qid))
    end
  end
end)

query:SetScript("OnShow", function()
  this.history = {}
  this.time = GetTime()
  this:RegisterEvent("CHAT_MSG_ADDON")
  SendChatMessage(".queststatus", "GUILD")
end)

query:SetScript("OnHide", function()
  this:UnregisterEvent("CHAT_MSG_ADDON")

  local count = 0
  for qid in pairs(this.history) do count = count + 1 end

  DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpf|cffffffffQuest|r: A total of " .. count .. " quests have been marked as completed.")

  pfQuest_history = this.history
  this.history = nil

  pfQuest:ResetAll()
end)

query:SetScript("OnUpdate", function()
  if GetTime() > this.time + 3 then this:Hide() end
end)

function pfDatabase:QueryServer()
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpf|cffffffffQuest|r: Receiving quest data from server...")
  query:Show()
end

-- Automatically clear quest cache if new turtle quests have been found
local updatecheck = CreateFrame("Frame")
updatecheck:RegisterEvent("PLAYER_ENTERING_WORLD")
updatecheck:SetScript("OnEvent", function()
  if pfDB["quests"]["data-turtle"] then
    -- count all known turtle-wow quests
    local count = 0
    for k, v in pairs(pfDB["quests"]["data-turtle"]) do
      count = count + 1
    end

    pfQuest:Debug("TurtleWoW loaded with |cff33ffcc" .. count .. "|r quests.")

    -- check if the last count differs to the current amount of quests
    if not pfQuest_turtlecount or pfQuest_turtlecount ~= count then
      -- remove quest cache to force reinitialisation of all quests.
      pfQuest:Debug("New quests found. Reloading |cff33ffccCache|r")
      pfQuest_questcache = {}
    end

    -- write current count to the saved variable
    pfQuest_turtlecount = count
  end
end)

-- Hook into pfDatabase to apply custom quest coloring on-demand (lazy evaluation)
-- This is MUCH more performant than coloring all quests at load time
if pfDatabase and pfDatabase.GetQuestTitle then
  local pfDatabase_GetQuestTitle = pfDatabase.GetQuestTitle
  
  function pfDatabase:GetQuestTitle(questId)
    local title = pfDatabase_GetQuestTitle(self, questId)
    
    -- Apply cyan color to custom TurtleWoW quests (ID >= 40000)
    if title and type(questId) == "number" and questId >= CUSTOM_QUEST_ID_THRESHOLD then
      -- Only add color if title doesn't already have a color code
      if not string.find(title, "^|c") then
        return CUSTOM_QUEST_COLOR .. title .. COLOR_END
      end
    end
    
    return title
  end
  
  pfQuest:Debug("Custom quest coloring hook installed (lazy evaluation)")
end
