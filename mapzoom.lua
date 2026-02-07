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
    
    -- Center the map after zoom
    if zoom > 1.0 then
      -- When zoomed in, allow the map to be repositioned
      WorldMapDetailFrame:EnableMouse(true)
      WorldMapDetailFrame:SetMovable(true)
    end
  end
end

-- Function to handle mouse wheel zoom on WorldMapFrame
local function OnMouseWheel(delta)
  if not WorldMapFrame:IsVisible() then
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

-- Hook into WorldMapFrame to enable mouse wheel scrolling
if WorldMapFrame then
  WorldMapFrame:EnableMouseWheel(true)
  WorldMapFrame:SetScript("OnMouseWheel", OnMouseWheel)
  
  -- Reset zoom when map is opened or changed
  local originalShow = WorldMapFrame:GetScript("OnShow")
  WorldMapFrame:SetScript("OnShow", function()
    zoomLevel = 1.0
    ApplyZoom(zoomLevel)
    if originalShow then
      originalShow()
    end
  end)
  
  -- Reset zoom when map zone changes
  local zoomResetFrame = CreateFrame("Frame")
  zoomResetFrame:RegisterEvent("WORLD_MAP_UPDATE")
  zoomResetFrame:SetScript("OnEvent", function()
    if WorldMapFrame:IsVisible() then
      zoomLevel = 1.0
      ApplyZoom(zoomLevel)
    end
  end)
end

