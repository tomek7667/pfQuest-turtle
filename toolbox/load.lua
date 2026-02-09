#!/usr/bin/env lua

local function tblsize(tbl)
  local count = 0
  for _ in pairs(tbl) do
    count = count + 1
  end
  return count
end

local function smalltable(tbl)
  local size = tblsize(tbl)
  if size > 10 or size < 1 then return nil end

  for i = 1, size do
    if not tbl[i] or type(tbl[i]) == "table" then
      return nil
    end
  end

  return true
end

local function sanitize(str)
  str = string.gsub(str, "\\", "\\\\")
  str = string.gsub(str, "\"", "\\\"")
  str = string.gsub(str, "\'", "\\\'")
  str = string.gsub(str, "\r", "")
  str = string.gsub(str, "\n", "")
  return str
end

local function sanitize_table(tbl)
  if type(tbl) ~= "table" then return end

  for k, v in pairs(tbl) do
    if type(v) == "string" then
      tbl[k] = sanitize(v)
    elseif type(v) == "table" then
      sanitize_table(v)
    end
  end
end

local function gen_ordered_index(tbl)
  local ordered_index = {}
  for key in pairs(tbl) do
    table.insert(ordered_index, key)
  end
  table.sort(ordered_index)
  return ordered_index
end

local function ordered_next(tbl, state)
  local key
  if state == nil then
    tbl.__orderedIndex = gen_ordered_index(tbl)
    key = tbl.__orderedIndex[1]
  else
    for i = 1, #tbl.__orderedIndex do
      if tbl.__orderedIndex[i] == state then
        key = tbl.__orderedIndex[i + 1]
      end
    end
  end

  if key then
    return key, tbl[key]
  end

  tbl.__orderedIndex = nil
  return nil
end

local function opairs(tbl)
  return ordered_next, tbl, nil
end

local function isdiff(new, base)
  if type(new) ~= type(base) then
    return true
  end

  if type(new) ~= "table" then
    return new ~= base
  end

  for k in pairs(new) do
    if isdiff(new[k], base[k]) then
      return true
    end
  end

  return nil
end

local function tablesubtract(new, base)
  local result = {}

  for k in pairs(new) do
    if new[k] and not base[k] then
      result[k] = new[k]
    elseif new[k] and base[k] and isdiff(new[k], base[k]) then
      result[k] = new[k]
    end
  end

  for k in pairs(base) do
    if base[k] and not new[k] then
      result[k] = "_"
    end
  end

  return result
end

local function serialize(target, name, tbl, spacing, flat)
  local close_handle = type(target) == "string"
  local file = close_handle and io.open(target, "w") or target
  local indent = spacing or ""

  if tblsize(tbl) == 0 then
    file:write(indent .. name .. " = {},\n")
  else
    file:write(indent .. name .. " = {\n")

    for k, v in opairs(tbl) do
      local prefix = "[" .. k .. "]"
      if type(k) == "string" then
        prefix = "[\"" .. k .. "\"]"
      end

      if type(v) == "table" and flat then
        file:write("  " .. indent .. prefix .. " = {},\n")
      elseif type(v) == "table" and smalltable(v) then
        local init
        local line = indent .. "  " .. prefix .. " = { "
        for _, entry in pairs(v) do
          line = line .. (init and ", " or "") .. (type(entry) == "string" and "\"" .. entry .. "\"" or entry)
          if not init then
            init = true
          end
        end
        file:write(line .. " },\n")
      elseif type(v) == "table" then
        serialize(file, prefix, v, indent .. "  ")
      elseif type(v) == "string" then
        file:write("  " .. indent .. prefix .. " = \"" .. v .. "\",\n")
      elseif type(v) == "number" then
        file:write("  " .. indent .. prefix .. " = " .. v .. ",\n")
      end
    end

    file:write(indent .. "}" .. (not close_handle and "," or "") .. "\n")
  end

  if close_handle then
    file:close()
  end
end

local function new_db_root()
  return {
    ["areatrigger"] = {},
    ["units"] = {},
    ["objects"] = {},
    ["items"] = {},
    ["refloot"] = {},
    ["quests"] = {},
    ["quests-itemreq"] = {},
    ["zones"] = {},
    ["minimap"] = {},
    ["meta"] = {},
    ["professions"] = {},
  }
end

local list = { "areatrigger", "units", "objects", "items", "refloot", "quests", "quests-itemreq", "zones", "minimap", "meta" }
local loclist = { "items", "objects", "professions", "quests", "units", "zones" }

local function load_tree(root)
  pfDB = new_db_root()

  for _, name in ipairs(list) do
    dofile(root .. "/db/" .. name .. ".lua")
  end

  for _, name in ipairs(loclist) do
    dofile(root .. "/db/enUS/" .. name .. ".lua")
  end

  sanitize_table(pfDB)
  local data = pfDB
  pfDB = nil
  return data
end

local pfDBF = load_tree("pfQuest-fork")
pfDB = load_tree("pfQuest")

local data = "data-turtle"
local loc = "enUS"
local exp = "-turtle"
local data_tables = { "areatrigger", "units", "objects", "items", "refloot", "quests", "quests-itemreq", "zones" }
local locale_tables = { "units", "objects", "items", "quests", "professions", "zones" }

for _, name in ipairs(data_tables) do
  pfDB[name][data] = tablesubtract(pfDBF[name]["data"], pfDB[name]["data"])
end
pfDB["minimap" .. exp] = tablesubtract(pfDBF["minimap"], pfDB["minimap"])
pfDB["meta" .. exp] = tablesubtract(pfDBF["meta"], pfDB["meta"])

for _, name in ipairs(locale_tables) do
  pfDB[name][loc .. exp] = tablesubtract(pfDBF[name][loc], pfDB[name][loc])
end

for _, name in ipairs(data_tables) do
  serialize(string.format("../db/%s%s.lua", name, exp), "pfDB[\"" .. name .. "\"][\"" .. data .. "\"]", pfDB[name][data])
end
serialize(string.format("../db/minimap%s.lua", exp), "pfDB[\"minimap" .. exp .. "\"]", pfDB["minimap" .. exp])
serialize(string.format("../db/meta%s.lua", exp), "pfDB[\"meta" .. exp .. "\"]", pfDB["meta" .. exp])

for _, name in ipairs(locale_tables) do
  serialize(string.format("../db/%s/%s%s.lua", loc, name, exp), "pfDB[\"" .. name .. "\"][\"" .. loc .. exp .. "\"]", pfDB[name][loc .. exp])
end
