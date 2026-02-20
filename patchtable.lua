local locale = GetLocale()
local dbs = { "items", "quests", "quests-itemreq", "objects", "units", "zones", "professions", "areatrigger", "refloot" }

local function patchtable(base, diff)
  if not base or not diff then return end
  for k, v in pairs(diff) do
    if type(v) == "string" and v == "_" then
      base[k] = nil
    else
      base[k] = v
    end
  end
end

-- Keep this legacy typo for older clients.
for _, name in pairs({ GetMapZones(2) }) do
  if name == "Northwind " then
    pfDB["zones"]["enUS-turtle"][5581] = "Northwind "
    break
  end
end

for _, db in ipairs(dbs) do
  local database = pfDB[db]
  if database["data-turtle"] then
    patchtable(database["data"], database["data-turtle"])
  end

  for locale_name in pairs(pfDB.locales) do
    if database[locale_name] and database[locale_name .. "-turtle"] then
      patchtable(database[locale_name], database[locale_name .. "-turtle"])
    end
  end
end

local loc_core = pfDB["professions"][locale] or pfDB["professions"]["enUS"]
local loc_update = pfDB["professions"][locale .. "-turtle"] or pfDB["professions"]["enUS-turtle"]
if loc_core and loc_update then patchtable(loc_core, loc_update) end

if pfDB["minimap-turtle"] then patchtable(pfDB["minimap"], pfDB["minimap-turtle"]) end
if pfDB["meta-turtle"] then patchtable(pfDB["meta"], pfDB["meta-turtle"]) end

local CUSTOM_QUEST_ID_THRESHOLD = 15000

if pfQuest_questcache then
  -- Keep quest titles raw; custom quests are highlighted by icon tint.
  pfQuest_questcache = nil
end

if TURTLE_DE_PATCH then
  pfDB["zones"]["loc"] = pfDB["zones"]["deDE"] or pfDB["zones"]["enUS"]
  pfDB["professions"]["loc"] = pfDB["professions"]["deDE"] or pfDB["professions"]["enUS"]
end

if pfDB.bitraces then
  pfDB.bitraces[256] = "Goblin"
  pfDB.bitraces[512] = "BloodElf"
end

pfQuest.dburl = "https://database.turtle-wow.org/?quest="

function pfMap:HasMinimap(map_id)
  if not IsInInstance() then
    return true
  end

  return GetCurrentMapContinent() < 3
end

local original_UpdateNode = pfMap.UpdateNode
local original_UpdateNodes = pfMap.UpdateNodes
local original_GetMapID = pfMap.GetMapID
local CONTINENT_NODE_ADDON = "PFQUEST_TURTLE_CONTINENT"
local CONTINENT_COORD_PATTERN = "([^|]+)|([^|]+)"
local CONTINENT_COORD_FORMAT = "%.2f|%.2f"
local continent_map_cache = {}

local function pfQuestApplyWorldMapPinSize(pin)
  if not pin then return end

  local base_size = tonumber(pin.pfquest_base_defsize) or tonumber(pin.defsize) or 14
  if base_size <= 0 then base_size = 14 end
  pin.pfquest_base_defsize = base_size

  local eff_scale = tonumber(pin:GetEffectiveScale()) or 1
  if eff_scale <= 0 then eff_scale = 1 end

  local zoom = tonumber(pfMap and pfMap.worldmap_zoom_state and pfMap.worldmap_zoom_state.scale) or 1
  if zoom <= 0 then zoom = 1 end

  if zoom == 1 or not pin.pfquest_base_screen_size then
    pin.pfquest_base_screen_size = base_size * eff_scale
  end

  local target_screen_size = tonumber(pin.pfquest_base_screen_size) or (base_size * eff_scale)
  local size = target_screen_size / eff_scale

  pin.defsize = size
  pin:SetWidth(size)
  pin:SetHeight(size)

  if pin.hl then
    local ratio = size / base_size
    local hl = 12 * ratio
    local off = 5 * ratio
    pin.hl:SetWidth(hl)
    pin.hl:SetHeight(hl)
    pin.hl:ClearAllPoints()
    pin.hl:SetPoint("TOPLEFT", pin, "TOPLEFT", -off, off)
  end
end

local function pfQuestApplyAllWorldMapPinSizes()
  if not pfMap or not pfMap.pins then return end

  for _, pin in pairs(pfMap.pins) do
    pfQuestApplyWorldMapPinSize(pin)
  end
end

function pfMap:UpdateNode(frame, node, color, obj, distance)
  original_UpdateNode(self, frame, node, color, obj, distance)

  if frame and frame.questid and frame.texture and tonumber(frame.questid) >= CUSTOM_QUEST_ID_THRESHOLD then
    if frame.tex and frame.tex.SetVertexColor then
      frame.tex:SetVertexColor(0.28, 0.82, 0.8, 1)
    end
  end

  if obj ~= "minimap" and frame then
    frame.pfquest_base_defsize = (frame.cluster or frame.layer == 4) and 18 or 14
    pfQuestApplyWorldMapPinSize(frame)
  end
end

local function pfQuestGetContinentMapID(continent)
  if continent_map_cache[continent] then return continent_map_cache[continent] end
  if not continent or continent <= 0 then return nil end

  local zones = pfDB and pfDB["zones"] and pfDB["zones"]["data"]
  if not zones then return nil end

  local roots, best_id, best_count = {}, nil, 0
  for _, zone_name in pairs({ GetMapZones(continent) }) do
    local map_id = pfMap:GetMapIDByName(zone_name)
    while map_id and zones[map_id] and zones[map_id][1] and zones[map_id][1] > 0 do
      map_id = zones[map_id][1]
    end

    if map_id and map_id > 0 then
      roots[map_id] = (roots[map_id] or 0) + 1
      if roots[map_id] > best_count then
        best_id, best_count = map_id, roots[map_id]
      end
    end
  end

  continent_map_cache[continent] = best_id
  return best_id
end

local function pfQuestTranslateToMap(map_id, x, y, target_id)
  local zones = pfDB and pfDB["zones"] and pfDB["zones"]["data"]
  if not zones or not map_id or not target_id then return nil end

  while map_id and map_id > 0 and map_id ~= target_id do
    local meta = zones[map_id]
    if not meta then return nil end

    local parent, width, height, parent_x, parent_y = unpack(meta)
    if not parent or parent <= 0 then return nil end
    if not width or not height or not parent_x or not parent_y then return nil end

    -- Child map coords are centered at 50,50 in parent-space percentages.
    x = parent_x + ((x - 50) * width / 100)
    y = parent_y + ((y - 50) * height / 100)
    map_id = parent
  end

  if map_id == target_id then return x, y end
end

local function pfQuestBuildContinentQuestNodes(continent_map)
  local continent_nodes = {}

  for addon, maps in pairs(pfMap.nodes or {}) do
    if addon ~= CONTINENT_NODE_ADDON then
      for map_id, map_nodes in pairs(maps or {}) do
        map_id = tonumber(map_id)
        if map_id and map_id > 0 and map_id ~= continent_map then
          for coords, node in pairs(map_nodes) do
            local coord_x_str, coord_y_str = string.match(coords, CONTINENT_COORD_PATTERN)
            local x, y = tonumber(coord_x_str), tonumber(coord_y_str)

            if x and y then
              local tx, ty = pfQuestTranslateToMap(map_id, x, y, continent_map)
              if tx and ty then
                local filtered = nil
                for title, meta in pairs(node) do
                  local texture = meta and meta.texture
                  if texture and (string.find(texture, "available", 1, true) or string.find(texture, "complete", 1, true)) then
                    filtered = filtered or {}
                    filtered[title] = meta
                  end
                end

                if filtered then
                  local key = string.format(CONTINENT_COORD_FORMAT, tx, ty)
                  continent_nodes[key] = continent_nodes[key] or {}
                  for title, meta in pairs(filtered) do continent_nodes[key][title] = meta end
                end
              end
            end
          end
        end
      end
    end
  end

  return continent_nodes
end

function pfMap:GetMapID(cid, mid)
  local continent = cid or GetCurrentMapContinent()
  local zone = mid
  if zone == nil then zone = GetCurrentMapZone() end

  if zone == 0 then
    local continent_map = pfQuestGetContinentMapID(continent)
    if continent_map then return continent_map end
  end

  return original_GetMapID(self, cid, mid)
end

function pfMap:UpdateNodes()
  if GetCurrentMapZone() == 0 then
    local continent_map = pfQuestGetContinentMapID(GetCurrentMapContinent())
    if continent_map then
      pfMap.nodes[CONTINENT_NODE_ADDON] = pfMap.nodes[CONTINENT_NODE_ADDON] or {}
      pfMap.nodes[CONTINENT_NODE_ADDON][continent_map] = pfQuestBuildContinentQuestNodes(continent_map)
    end
  end

  return original_UpdateNodes(self)
end

local function pfQuestInstallWorldMapZoom()
  local ZOOM_VERSION = 4
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
    pfQuestApplyAllWorldMapPinSizes()

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
pfDatabase:Reload()

local function strsplit(delimiter, subject)
  if not subject then return nil end
  local fields = {}
  local pattern = string.format("([^%s]+)", delimiter or ":")
  string.gsub(subject, pattern, function(token) fields[table.getn(fields)+1] = token end)
  return unpack(fields)
end

-- Server reports direct completions only; close/pre chains are resolved here.
local function complete(history, qid)
  qid = tonumber(qid)
  if not qid then return end

  local previous = pfQuest_history and pfQuest_history[qid]
  history[qid] = { previous and previous[1] or 0, previous and previous[2] or 0 }

  local quest_data = pfDB["quests"] and pfDB["quests"]["data"]
  local quest = quest_data and quest_data[qid]
  if not quest then return end

  local close = quest["close"]
  if close then
    for _, close_qid in pairs(close) do
      if not history[close_qid] then complete(history, close_qid) end
    end
  end

  local prequests = quest["pre"]
  if prequests then
    for _, pre_qid in pairs(prequests) do
      if not history[pre_qid] then complete(history, pre_qid) end
    end
  end
end

local query = CreateFrame("Frame")
query:Hide()

query:SetScript("OnEvent", function()
  if arg1 == "TWQUEST" then
    for _, qid in pairs({strsplit(" ", arg2)}) do
      complete(this.history, qid)
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

local update_check = CreateFrame("Frame")
update_check:RegisterEvent("PLAYER_ENTERING_WORLD")
update_check:SetScript("OnEvent", function()
  local turtle_quests = pfDB["quests"]["data-turtle"]
  if turtle_quests then
    local count = 0
    for _ in pairs(turtle_quests) do
      count = count + 1
    end

    pfQuest:Debug("TurtleWoW loaded with |cff33ffcc" .. count .. "|r quests.")

    if not pfQuest_turtlecount or pfQuest_turtlecount ~= count then
      pfQuest:Debug("New quests found. Reloading |cff33ffccCache|r")
      pfQuest_questcache = {}
    end

    pfQuest_turtlecount = count
  end
end)
