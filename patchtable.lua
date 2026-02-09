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

-- Threshold for custom TurtleWoW quests (used for map icon coloring)
local CUSTOM_QUEST_ID_THRESHOLD = 15000

-- NOTE:
-- Coloring quest titles inside the database breaks quest-log ID matching,
-- which prevents some active quests from showing their map dots after reload.
-- Custom quests are still visually distinguished via icon color.
if pfQuest_questcache then
  -- Clear stale quest cache from previous sessions with colored titles.
  pfQuest_questcache = nil
end

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

-- Enable mouse wheel zoom on the expanded world map
local function pfQuestInstallWorldMapZoom()
  local ZOOM_VERSION = 2
  if pfMap.worldmap_zoom_version ~= ZOOM_VERSION then
    pfMap.worldmap_zoom_installed = nil
    pfMap.worldmap_zoom_state = nil
    pfMap.worldmap_zoom_scroll = nil
    pfMap.worldmap_zoom_content = nil
    pfMap.worldmap_zoom_drag = nil
    pfMap.worldmap_zoom_events = nil
    pfMap.worldmap_zoom_version = ZOOM_VERSION
  end

  if pfMap and pfMap.worldmap_zoom_installed then return true end
  if not WorldMapFrame or not WorldMapDetailFrame or not WorldMapButton then return nil end

  local zoom_min = 1.0
  local zoom_max = 5
  local zoom_step = 0.2

  pfMap.worldmap_zoom_state = pfMap.worldmap_zoom_state or { scale = 1, scrollX = 0, scrollY = 0 }
  local state = pfMap.worldmap_zoom_state
  local function clamp(value, minv, maxv)
    if value < minv then return minv end
    if value > maxv then return maxv end
    return value
  end

  local function cursor_local_to(frame)
    if not frame then return nil end
    local scale = frame:GetEffectiveScale() or 1
    local cursorX, cursorY = GetCursorPosition()
    local left = frame:GetLeft()
    local bottom = frame:GetBottom()
    local width = frame:GetWidth()
    local height = frame:GetHeight()
    if not left or not bottom or not width or not height or width == 0 or height == 0 then
      return nil
    end

    local x = cursorX / scale - left
    local y = cursorY / scale - bottom
    if x < 0 or x > width or y < 0 or y > height then
      return nil
    end
    return x, height - y
  end

  local function capture_base()
    local w = WorldMapDetailFrame:GetWidth()
    local h = WorldMapDetailFrame:GetHeight()
    if not w or not h or w <= 0 or h <= 0 then return nil end

    local should_update = (not state.base_width or not state.base_height or not state.base_points)
    if state.scale == 1 and (state.base_width ~= w or state.base_height ~= h) then
      should_update = true
    end

    if should_update then
      state.base_width = w
      state.base_height = h
      state.base_parent = WorldMapDetailFrame:GetParent() or WorldMapFrame
      state.base_points = {}
      local num = WorldMapDetailFrame:GetNumPoints()
      if num and num > 0 then
        for i = 1, num do
          local point, rel, relPoint, x, y = WorldMapDetailFrame:GetPoint(i)
          state.base_points[i] = { point = point, rel = rel, relPoint = relPoint, x = x, y = y }
        end
      else
        state.base_points[1] = { point = "TOPLEFT", rel = state.base_parent, relPoint = "TOPLEFT", x = 0, y = 0 }
      end
    end
    return true
  end

  local function ensure_scroll()
    if not capture_base() then return nil end
    local parent = state.base_parent or WorldMapFrame
    if not parent then return nil end

    local scroll = pfMap.worldmap_zoom_scroll
    local content = pfMap.worldmap_zoom_content

    if not scroll or not content then
      scroll = CreateFrame("ScrollFrame", "pfQuestWorldMapScroll", parent)
      scroll:SetFrameStrata(WorldMapDetailFrame:GetFrameStrata())
      scroll:SetFrameLevel(WorldMapDetailFrame:GetFrameLevel())
      scroll:EnableMouse(false)
      scroll:Show()

      scroll:ClearAllPoints()
      for i = 1, table.getn(state.base_points) do
        local p = state.base_points[i]
        local rel = p.rel or parent
        if rel == WorldMapDetailFrame then rel = parent end
        if type(rel) == "string" and rel == WorldMapDetailFrame:GetName() then rel = parent end
        scroll:SetPoint(p.point, rel, p.relPoint, p.x, p.y)
      end
      scroll:SetWidth(state.base_width)
      scroll:SetHeight(state.base_height)

      content = CreateFrame("Frame", "pfQuestWorldMapContent", scroll)
      content:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
      content:SetWidth(state.base_width)
      content:SetHeight(state.base_height)
      scroll:SetScrollChild(content)

      WorldMapDetailFrame:SetParent(content)
      WorldMapDetailFrame:ClearAllPoints()
      WorldMapDetailFrame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
      WorldMapDetailFrame:SetWidth(state.base_width)
      WorldMapDetailFrame:SetHeight(state.base_height)

      WorldMapButton:SetParent(content)
      WorldMapButton:ClearAllPoints()
      WorldMapButton:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
      WorldMapButton:SetWidth(state.base_width)
      WorldMapButton:SetHeight(state.base_height)

      pfMap.worldmap_zoom_scroll = scroll
      pfMap.worldmap_zoom_content = content
    else
      scroll:SetWidth(state.base_width)
      scroll:SetHeight(state.base_height)
      content:SetWidth(state.base_width)
      content:SetHeight(state.base_height)
    end

    return scroll, content
  end

  local function max_scroll(viewW, viewH, scale)
    local mapW = state.base_width or viewW
    local mapH = state.base_height or viewH
    local maxX = mapW - (viewW / scale)
    local maxY = mapH - (viewH / scale)
    if maxX < 0 then maxX = 0 end
    if maxY < 0 then maxY = 0 end
    return maxX, maxY
  end

  local function apply_state()
    if not WorldMapFrame:IsShown() then return end
    local scroll, content = ensure_scroll()
    if not scroll or not content then return end

    if WorldMapDetailFrame:GetParent() ~= content then
      WorldMapDetailFrame:SetParent(content)
    end
    WorldMapDetailFrame:ClearAllPoints()
    WorldMapDetailFrame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    WorldMapDetailFrame:SetWidth(state.base_width)
    WorldMapDetailFrame:SetHeight(state.base_height)

    if WorldMapButton:GetParent() ~= content then
      WorldMapButton:SetParent(content)
    end
    WorldMapButton:ClearAllPoints()
    WorldMapButton:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
    WorldMapButton:SetWidth(state.base_width)
    WorldMapButton:SetHeight(state.base_height)

    if scroll.GetScrollChild and scroll:GetScrollChild() ~= content then
      scroll:SetScrollChild(content)
    end

    if state.scale < zoom_min then state.scale = zoom_min end
    if state.scale > zoom_max then state.scale = zoom_max end
    if state.scale == 1 then
      state.scrollX = 0
      state.scrollY = 0
    end

    content:SetScale(state.scale)

    local viewW = scroll:GetWidth()
    local viewH = scroll:GetHeight()
    if not viewW or not viewH or viewW <= 0 or viewH <= 0 then return end

    local maxX, maxY = max_scroll(viewW, viewH, state.scale)
    state.scrollX = clamp(state.scrollX or 0, 0, maxX)
    state.scrollY = clamp(state.scrollY or 0, 0, maxY)

    if scroll.SetHorizontalScroll then
      scroll:SetHorizontalScroll(0)
      scroll:SetVerticalScroll(0)
    end
    content:ClearAllPoints()
    content:SetPoint("TOPLEFT", scroll, "TOPLEFT", -state.scrollX, state.scrollY)

    pfMap.queue_update = GetTime()
  end

  local function zoom_by(delta)
    if not WorldMapFrame:IsShown() then return end
    local scroll, content = ensure_scroll()
    if not scroll or not content then return end

    local viewW = scroll:GetWidth()
    local viewH = scroll:GetHeight()
    if not viewW or not viewH or viewW <= 0 or viewH <= 0 then return end

    local current = state.scale or 1
    local target = clamp(current + delta, zoom_min, zoom_max)
    if target == current then return end

    local localX, localY = cursor_local_to(scroll)
    if not localX or not localY then return end

    local mapX = state.scrollX + (localX / current)
    local mapY = state.scrollY + (localY / current)

    state.scale = target
    state.scrollX = mapX - (localX / target)
    state.scrollY = mapY - (localY / target)

    apply_state()
  end

  local function on_mousewheel(_, delta)
    local wheel = delta or arg1 or 0
    if wheel > 0 then
      zoom_by(zoom_step)
    elseif wheel < 0 then
      zoom_by(-zoom_step)
    end
  end

  local function hook_wheel(frame, require_hover)
    if not frame or frame.pfquest_zoom_hooked then return end
    frame:EnableMouseWheel(true)
    if frame.HookScript then
      frame:HookScript("OnMouseWheel", function(self, delta)
        if require_hover then
          local view = pfMap.worldmap_zoom_scroll or WorldMapDetailFrame
          if not MouseIsOver(view) then return end
        end
        on_mousewheel(self, delta)
      end)
    else
      local original = frame:GetScript("OnMouseWheel")
      frame:SetScript("OnMouseWheel", function(self, delta)
        if original then original(self, delta) end
        if require_hover then
          local view = pfMap.worldmap_zoom_scroll or WorldMapDetailFrame
          if not MouseIsOver(view) then return end
        end
        on_mousewheel(self, delta)
      end)
    end
    frame.pfquest_zoom_hooked = true
  end

  hook_wheel(WorldMapButton, true)
  hook_wheel(WorldMapFrame, true)

  if not pfMap.worldmap_zoom_drag then
    local drag = CreateFrame("Frame")
    drag:SetScript("OnUpdate", function()
      if not state.dragging then return end
      if ( this.throttle or 0) > GetTime() then return else this.throttle = GetTime() + 0.01 end

      local scroll, content = ensure_scroll()
      if not scroll or not content then return end
      local localX, localY = cursor_local_to(scroll)
      if not localX or not localY then return end

      local dx = localX - (state.dragStartX or localX)
      local dy = localY - (state.dragStartY or localY)

      local viewW = scroll:GetWidth()
      local viewH = scroll:GetHeight()
      local maxX, maxY = max_scroll(viewW, viewH, state.scale)

      state.scrollX = clamp((state.dragBaseX or 0) - (dx / state.scale), 0, maxX)
      state.scrollY = clamp((state.dragBaseY or 0) - (dy / state.scale), 0, maxY)

      apply_state()
    end)
    pfMap.worldmap_zoom_drag = drag
  end

  local function hook_drag(frame)
    if not frame or frame.pfquest_drag_hooked then return end
    local function on_down(self, button)
      if not WorldMapFrame:IsShown() then return end
      if button ~= "MiddleButton" and button ~= "Button3" then return end
      local view = pfMap.worldmap_zoom_scroll or WorldMapDetailFrame
      if not MouseIsOver(view) then return end

      local localX, localY = cursor_local_to(view)
      if not localX or not localY then return end

      state.dragging = true
      state.dragStartX = localX
      state.dragStartY = localY
      state.dragBaseX = state.scrollX or 0
      state.dragBaseY = state.scrollY or 0
    end

    local function on_up(self, button)
      if button ~= "MiddleButton" and button ~= "Button3" then return end
      state.dragging = nil
    end

    if frame.HookScript then
      frame:HookScript("OnMouseDown", on_down)
      frame:HookScript("OnMouseUp", on_up)
    else
      local original_down = frame:GetScript("OnMouseDown")
      local original_up = frame:GetScript("OnMouseUp")
      frame:SetScript("OnMouseDown", function(self, button)
        if original_down then original_down(self, button) end
        on_down(self, button)
      end)
      frame:SetScript("OnMouseUp", function(self, button)
        if original_up then original_up(self, button) end
        on_up(self, button)
      end)
    end

    frame.pfquest_drag_hooked = true
  end

  hook_drag(WorldMapButton)
  hook_drag(WorldMapFrame)

  if not pfMap.worldmap_zoom_events then
    local events = CreateFrame("Frame")
    events:RegisterEvent("WORLD_MAP_UPDATE")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:SetScript("OnEvent", function()
      apply_state()
    end)
    pfMap.worldmap_zoom_events = events
  end

  if pfMap then
    pfMap.worldmap_zoom_installed = true
  end

  apply_state()
  return true
end

if not pfQuestInstallWorldMapZoom() then
  local zoominit = CreateFrame("Frame")
  zoominit:RegisterEvent("PLAYER_ENTERING_WORLD")
  zoominit:RegisterEvent("WORLD_MAP_UPDATE")
  zoominit:SetScript("OnEvent", function()
    if pfQuestInstallWorldMapZoom() then
      this:UnregisterAllEvents()
    end
  end)
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
