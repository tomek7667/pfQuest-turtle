-- Enable infinite zoom on the world map using mouse scroll
-- This allows players to zoom in/out continuously on the large map

-- Initialize zoom variables
local zoomLevel = 1.0
local minZoom = 0.5   -- Maximum zoom out
local maxZoom = 3.0   -- Maximum zoom in
local zoomStep = 0.1  -- Zoom increment per scroll

-- Store original position for dragging
local isDragging = false
local dragStartX, dragStartY = 0, 0
local mapOffsetX, mapOffsetY = 0, 0

-- Function to apply zoom to the WorldMapDetailFrame
local function ApplyZoom(zoom)
  if WorldMapDetailFrame then
    WorldMapDetailFrame:SetScale(zoom)
    
    -- Adjust position to maintain center
    local centerX = WorldMapDetailFrame:GetWidth() / 2
    local centerY = WorldMapDetailFrame:GetHeight() / 2
    
    WorldMapDetailFrame:ClearAllPoints()
    if zoom > 1.0 then
      -- When zoomed in, apply offset for dragging
      WorldMapDetailFrame:SetPoint("CENTER", WorldMapButton, "CENTER", mapOffsetX, mapOffsetY)
    else
      -- Reset to default position when zoomed out
      WorldMapDetailFrame:SetPoint("TOPLEFT", WorldMapButton, "TOPLEFT", 0, 0)
      mapOffsetX, mapOffsetY = 0, 0
    end
  end
end

-- Function to handle mouse wheel zoom
local function OnMouseWheel(self, delta)
  -- Adjust zoom level based on scroll direction
  if delta > 0 then
    -- Scroll up = zoom in
    zoomLevel = math.min(zoomLevel + zoomStep, maxZoom)
  else
    -- Scroll down = zoom out
    zoomLevel = math.max(zoomLevel - zoomStep, minZoom)
  end
  
  -- Apply the new zoom level
  ApplyZoom(zoomLevel)
end

-- Function to handle mouse down for dragging
local function OnMouseDown(self, button)
  if button == "LeftButton" and zoomLevel > 1.0 then
    isDragging = true
    dragStartX, dragStartY = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    dragStartX = dragStartX / scale
    dragStartY = dragStartY / scale
  end
end

-- Function to handle mouse up
local function OnMouseUp(self, button)
  if button == "LeftButton" then
    isDragging = false
  end
end

-- Function to handle mouse movement for dragging
local function OnUpdate()
  if isDragging and zoomLevel > 1.0 then
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    x = x / scale
    y = y / scale
    
    local deltaX = x - dragStartX
    local deltaY = y - dragStartY
    
    mapOffsetX = mapOffsetX + deltaX
    mapOffsetY = mapOffsetY + deltaY
    
    dragStartX, dragStartY = x, y
    
    ApplyZoom(zoomLevel)
  end
end

-- Initialize the map zoom functionality
local function InitMapZoom()
  if not WorldMapFrame or not WorldMapDetailFrame then
    return
  end
  
  -- Enable mouse wheel on the detail frame
  WorldMapDetailFrame:EnableMouseWheel(1)
  WorldMapDetailFrame:SetScript("OnMouseWheel", OnMouseWheel)
  
  -- Enable mouse events for dragging
  WorldMapDetailFrame:EnableMouse(1)
  WorldMapDetailFrame:SetScript("OnMouseDown", OnMouseDown)
  WorldMapDetailFrame:SetScript("OnMouseUp", OnMouseUp)
  WorldMapDetailFrame:SetScript("OnUpdate", OnUpdate)
  
  -- Reset zoom when map is opened
  local originalShow = WorldMapFrame:GetScript("OnShow")
  WorldMapFrame:SetScript("OnShow", function()
    zoomLevel = 1.0
    mapOffsetX, mapOffsetY = 0, 0
    isDragging = false
    ApplyZoom(zoomLevel)
    if originalShow then
      originalShow()
    end
  end)
  
  -- Reset zoom when map is closed
  local originalHide = WorldMapFrame:GetScript("OnHide")
  WorldMapFrame:SetScript("OnHide", function()
    zoomLevel = 1.0
    mapOffsetX, mapOffsetY = 0, 0
    isDragging = false
    if originalHide then
      originalHide()
    end
  end)
end

-- Wait for the world map to be available
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function()
  if arg1 == "pfQuest-turtle" then
    -- Delay initialization slightly to ensure WorldMap is loaded
    local delayFrame = CreateFrame("Frame")
    local elapsed = 0
    delayFrame:SetScript("OnUpdate", function()
      elapsed = elapsed + arg1
      if elapsed > 0.5 then
        InitMapZoom()
        this:Hide()
      end
    end)
    initFrame:UnregisterEvent("ADDON_LOADED")
  end
end)
