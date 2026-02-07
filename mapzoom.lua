-- Enable infinite zoom on the world map using mouse scroll
-- This allows players to zoom in/out continuously on the large map

-- Initialize zoom variables
local zoomLevel = 1.0
local minZoom = 0.5   -- Maximum zoom out
local maxZoom = 3.0   -- Maximum zoom in
local zoomStep = 0.1  -- Zoom increment per scroll

-- Function to apply zoom to the WorldMapDetailFrame
local function ApplyZoom(zoom)
  if WorldMapDetailFrame then
    local scale = zoom
    WorldMapDetailFrame:SetScale(scale)
    
    -- When zoomed in, allow the map to be repositioned
    if zoom > 1.0 then
      WorldMapDetailFrame:EnableMouse(true)
      WorldMapDetailFrame:SetMovable(true)
    end
  end
end

-- Function to handle mouse wheel zoom on WorldMapFrame
local function OnMouseWheel(delta)
  if not WorldMapFrame or not WorldMapFrame:IsVisible() then
    return
  end
  
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

-- Initialize the map zoom functionality
local function InitMapZoom()
  if not WorldMapFrame then
    return
  end
  
  WorldMapFrame:EnableMouseWheel(true)
  WorldMapFrame:SetScript("OnMouseWheel", OnMouseWheel)
  
  -- Reset zoom when map is opened
  local originalShow = WorldMapFrame:GetScript("OnShow")
  WorldMapFrame:SetScript("OnShow", function()
    zoomLevel = 1.0
    ApplyZoom(zoomLevel)
    if originalShow then
      originalShow()
    end
  end)
end

-- Wait for the map frame to be available before initializing
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function()
  if arg1 == "pfQuest-turtle" then
    InitMapZoom()
    this:UnregisterEvent("ADDON_LOADED")
  end
end)


