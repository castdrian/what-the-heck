local NAMED_CATALOGS = { "pokemon", "moves", "items", "trainers" }
local DISPLAY_NAME_ALIASES = {
  FARFETCHD = "FARFETCH'D",
  FARFETCH_D = "FARFETCH'D",
  MR_MIME = "MR.MIME",
  MR__MIME = "MR.MIME",
  NIDORAN_F = "NIDORAN♀",
  NIDORAN_M = "NIDORAN♂",
  HO_OH = "HO-OH",
}

local function loadVersionModule()
  local names = { "src.core.GameVersion", "src.gen2.core.GameVersion" }
  for _, name in ipairs(names) do
    local ok, value = pcall(require, name)
    if ok and type(value) == "table" then return value end
  end
  return {}
end

local function activeVersion()
  local version = loadVersionModule()
  local generation = type(version.generation) == "function" and version.generation()
  local id = type(version.get) == "function" and version.get() or ""
  id = tostring(id):lower()
  if generation == 2 or id == "gold" or id == "gen2" then return "gold" end
  if id == "blue" or (type(version.isBlue) == "function" and version.isBlue()) then
    return "blue"
  end
  if id == "yellow" or (type(version.isYellow) == "function" and version.isYellow()) then
    return "yellow"
  end
  return "red"
end

local function readCatalog(mod, name)
  local source = mod:read("lang/" .. name .. ".lua")
  if type(source) ~= "string" then return {} end
  local chunk, err = loadstring(source, "@what-the-heck/lang/" .. name .. ".lua")
  if not chunk then
    mod.log:warn("could not load translation catalog %s: %s", name, tostring(err))
    return {}
  end
  local ok, catalog = pcall(chunk)
  if not ok or type(catalog) ~= "table" then
    mod.log:warn("translation catalog %s did not return a table", name)
    return {}
  end
  return catalog
end

local function isAsciiWordCharacter(value)
  if value == "" then return false end
  local byte = value:byte()
  return (byte >= 48 and byte <= 57)
    or (byte >= 65 and byte <= 90)
    or (byte >= 97 and byte <= 122)
    or byte == 95
end

local function replaceSpeciesToken(value, source, replacement)
  local offset = 1
  while true do
    local start, finish = value:find(source, offset, true)
    if not start then return value end
    local before = value:sub(start - 1, start - 1)
    local after = value:sub(finish + 1, finish + 1)
    if not isAsciiWordCharacter(before) and not isAsciiWordCharacter(after) then
      value = value:sub(1, start - 1) .. replacement .. value:sub(finish + 1)
      offset = start + #replacement
    else
      offset = finish + 1
    end
  end
end

local function speciesReplacements(catalog)
  local replacements = {}
  for id, value in pairs(catalog or {}) do
    if type(id) == "string" and type(value) == "string" and value ~= "" then
      local source = DISPLAY_NAME_ALIASES[id] or id
      if source ~= value then
        replacements[#replacements + 1] = { source = source, value = value }
      end
    end
  end
  table.sort(replacements, function(left, right)
    return #left.source > #right.source
  end)
  return replacements
end

local function translateSpeciesNames(value, replacements)
  for _, replacement in ipairs(replacements) do
    value = replaceSpeciesToken(value, replacement.source, replacement.value)
  end
  return value
end

local function applyCatalog(registry, catalog, pokemonCatalog)
  if not registry then return 0 end
  local replacements = speciesReplacements(pokemonCatalog)
  local count = 0
  for id, value in pairs(catalog) do
    if type(id) == "string" and type(value) == "string" and value ~= "" then
      registry:override(id, translateSpeciesNames(value, replacements))
      count = count + 1
    end
  end
  return count
end

local function applyNamedCatalog(mod, version, name)
  local registry = mod.content and mod.content[name]
  if not registry or type(registry.patch) ~= "function" then return 0 end
  local count = 0
  for id, value in pairs(readCatalog(mod, version .. "_" .. name)) do
    if type(id) == "string" and type(value) == "string" and value ~= "" then
      registry:patch(id, { name = value })
      count = count + 1
    end
  end
  return count
end

local function translateMenuRows(rows, catalog)
  if type(rows) ~= "table" then return rows end
  for _, row in ipairs(rows) do
    if type(row) == "table" and type(row.label) == "string" then
      row.label = catalog[row.label] or row.label
    end
  end
  return rows
end

local function installMenuHooks(mod, catalog)
  if not mod.hooks or type(mod.hooks.wrap) ~= "function" then return end
  mod.hooks:wrap("ui.title_menu.items", function(next, game, rows)
    return translateMenuRows(next(game, rows), catalog)
  end)
  mod.hooks:wrap("ui.start_menu.items", function(next, game, rows)
    return translateMenuRows(next(game, rows), catalog)
  end)
  mod.hooks:wrap("ui.party.submenu", function(next, game, rows, mon, context)
    return translateMenuRows(next(game, rows, mon, context), catalog)
  end)
  mod.hooks:wrap("ui.options.rows", function(next, game, rows)
    return translateMenuRows(next(game, rows), catalog)
  end)
end

return function(mod)
  local version = activeVersion()
  local pokemonCatalog = readCatalog(mod, version .. "_pokemon")
  local textCount = applyCatalog(mod.content.text, readCatalog(mod, version), pokemonCatalog)
  local stringCatalog = readCatalog(mod, "strings")
  local stringCount = applyCatalog(mod.content.strings, stringCatalog, pokemonCatalog)
  installMenuHooks(mod, stringCatalog)
  local namedCounts = {}
  for _, name in ipairs(NAMED_CATALOGS) do
    namedCounts[name] = applyNamedCatalog(mod, version, name)
  end
  local namedCount = namedCounts.pokemon + namedCounts.moves + namedCounts.items + namedCounts.trainers
  mod.log:info("loaded %d %s nonsense text entries, %d engine strings, and %d named records", textCount, version, stringCount, namedCount)
end
