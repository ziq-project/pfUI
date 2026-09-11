SLASH_RELOAD1 = '/rl'
function SlashCmdList.RELOAD(msg, editbox)
  ReloadUI()
end

SLASH_PFUI1 = '/pfui'
function SlashCmdList.PFUI(msg, editbox)
  if pfUI.gui:IsShown() then
    pfUI.gui:Hide()
  else
    pfUI.gui:Show()
  end
end

SLASH_GM1, SLASH_GM2 = '/gm', '/support'
function SlashCmdList.GM(msg, editbox)
  ToggleHelpFrame(1)
end

-- CONFIRMED IN-GAME (2026-09-11): this build's ClassicAPI exposes several
-- modern-retail UI mixins (CreateColor/Mixin/ColorMixin, CreateObjectPool,
-- the Item mixin) but not these two convenience constructors -- global,
-- since callers (loothistory.lua and, ported later, equipmentmanager.lua)
-- use them as bare globals the same way upstream's client provides them.
-- Guarded so a future client that does add real support isn't overridden.
if not CreateScrollFrame then
  function CreateScrollFrame(name, parent)
    local scroll = CreateFrame("ScrollFrame", name, parent)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function()
      local child = this:GetScrollChild()
      if not child then return end
      local range = child:GetHeight() - this:GetHeight()
      if range < 0 then range = 0 end
      local cur = this:GetVerticalScroll() - (arg1 * 20)
      if cur < 0 then cur = 0 end
      if cur > range then cur = range end
      this:SetVerticalScroll(cur)
    end)
    -- No-op: real ScrollFrames recompute their scroll range on
    -- SetScrollChild already, kept only so callers written against the
    -- retail API (which calls this after resizing the child) don't error.
    function scroll:UpdateScrollState() end
    return scroll
  end
end

-- Also missing here. Every UIPanelButtonTemplate button in this codebase
-- already gets pfUI's border via the global Blizzard-template skin
-- (skins/blizzard/*) without any per-instance call, so callers written
-- against the retail API (which calls this once per button after creating
-- it) need nothing further done -- a no-op satisfies the call.
if not SkinButton then
  function SkinButton(button) end
end

if not CreateScrollChild then
  function CreateScrollChild(name, scrollFrame)
    local child = CreateFrame("Frame", name, scrollFrame)
    child:SetWidth(scrollFrame:GetWidth())
    scrollFrame:SetScrollChild(child)
    return child
  end
end

pfUI = CreateFrame("Frame", nil, UIParent)
pfUI:RegisterEvent("ADDON_LOADED")
-- Also fire on VARIABLES_LOADED (fires once, after every addon has
-- finished loading) and PLAYER_ENTERING_WORLD (fires after that, once
-- the world/UI is fully up) so UpdateColors() gets the final say even if
-- something resets RAID_CLASS_COLORS after pfUI's own ADDON_LOADED runs.
pfUI:RegisterEvent("VARIABLES_LOADED")
pfUI:RegisterEvent("PLAYER_ENTERING_WORLD")

-- Belt-and-suspenders: some clients/servers reset RAID_CLASS_COLORS from
-- code that runs *after* all of the events above (e.g. late FrameXML
-- init). Re-assert our color table a few times over the following
-- seconds after entering the world to defend against that.
do
  local colorWatcher = CreateFrame("Frame")
  local elapsedTotal = 0
  local ticks = 0
  colorWatcher:Hide()
  colorWatcher:SetScript("OnUpdate", function()
    elapsedTotal = elapsedTotal + arg1
    if elapsedTotal >= 1 then
      elapsedTotal = 0
      ticks = ticks + 1
      pfUI:UpdateColors()
      if ticks >= 10 then
        this:Hide()
      end
    end
  end)
  pfUI.colorWatcher = colorWatcher
end

-- setup bootvar
pfUI.bootup = true

-- initialize saved variables
pfUI_playerDB = {}
pfUI_config = {}
pfUI_init = {}
pfUI_profiles = {}
pfUI_addon_profiles = {}
pfUI_cache = {}

-- localization
pfUI_locale = {}
pfUI_translation = {}

-- initialize default variables
pfUI.cache = {}
pfUI.module = {}
pfUI.modules = {}
pfUI.skin = {}
pfUI.skins = {}
pfUI.environment = {}
pfUI.movables = {}
pfUI.version = {}
pfUI.hooks = {}
pfUI.env = {}

-- detect current addon path
local tocs = { "", "-master", "-tbc", "-wotlk" }
for _, name in pairs(tocs) do
  local current = string.format("pfUI%s", name)
  local _, title = GetAddOnInfo(current)
  if title then
    pfUI.name = current
    pfUI.path = "Interface\\AddOns\\" .. current
    break
  end
end

-- handle/convert media dir paths
pfUI.media = setmetatable({}, { __index = function(tab,key)
  local value = tostring(key)
  if strfind(value, "img:") then
    value = string.gsub(value, "img:", pfUI.path .. "\\img\\")
  elseif strfind(value, "font:") then
    value = string.gsub(value, "font:", pfUI.path .. "\\fonts\\")
  else
    value = string.gsub(value, "Interface\\AddOns\\pfUI\\", pfUI.path .. "\\")
  end
  rawset(tab,key,value)
  return value
end})

-- cache client version
local _, _, _, client = GetBuildInfo()
client = client or 11200

-- detect client expansion
if client >= 20000 and client <= 20400 then
  pfUI.expansion = "tbc"
  pfUI.client = client
elseif client >= 30000 and client <= 30300 then
  pfUI.expansion = "wotlk"
  pfUI.client = client
else
  pfUI.expansion = "vanilla"
  pfUI.client = client
end

-- setup pfUI namespace
setmetatable(pfUI.env, {__index = getfenv(0)})

-- Dedicated, pfUI-owned class color table. Unitframes code should read
-- from THIS table (via pfUI:GetClassColor below) instead of the shared
-- global RAID_CLASS_COLORS. On some servers something else keeps
-- resetting that global back to Blizzard's defaults (where Shaman and
-- Paladin share the exact same pink), so pfUI's own unit frames no
-- longer depend on it at all and are immune to whatever does that.
pfUI.classcolors = {
  ["WARRIOR"] = { r = 0.78, g = 0.61, b = 0.43, colorStr = "ffc79c6e" },
  ["MAGE"]    = { r = 0.41, g = 0.8,  b = 0.94, colorStr = "ff69ccf0" },
  ["ROGUE"]   = { r = 1,    g = 0.96, b = 0.41, colorStr = "fffff569" },
  ["DRUID"]   = { r = 1,    g = 0.49, b = 0.04, colorStr = "ffff7d0a" },
  ["HUNTER"]  = { r = 0.67, g = 0.83, b = 0.45, colorStr = "ffabd473" },
  ["SHAMAN"]  = { r = 0.14, g = 0.35, b = 1.0,  colorStr = "ff0070de" },
  ["PRIEST"]  = { r = 1,    g = 1,    b = 1,    colorStr = "ffffffff" },
  ["WARLOCK"] = { r = 0.58, g = 0.51, b = 0.79, colorStr = "ff9482c9" },
  ["PALADIN"] = { r = 0.96, g = 0.55, b = 0.73, colorStr = "fff58cba" },
}
setmetatable(pfUI.classcolors, { __index = function(tab,key)
  return { r = 0.6,  g = 0.6,  b = 0.6,  colorStr = "ff999999" }
end})

--- Returns the class color for a class token. Always prefer this over
--- indexing RAID_CLASS_COLORS directly for anything pfUI renders itself.
function pfUI:GetClassColor(class)
  return pfUI.classcolors[class]
end

function pfUI:UpdateColors()
  -- update table to get unknown colors and blue shamans.
  -- NOTE: this used to be gated behind `pfUI.expansion == "vanilla"`,
  -- but some servers report a client/build value that gets misclassified
  -- by the expansion detection above, silently skipping this whole fix
  -- and leaving Blizzard's raw default table in place (where Shaman and
  -- Paladin share the exact same pink color). Applying it unconditionally
  -- is safe and fixes that case too.
  -- This also keeps the *global* RAID_CLASS_COLORS in sync for other
  -- addons/Blizzard frames, but pfUI's own unit frames no longer rely on
  -- it (see pfUI.classcolors / pfUI:GetClassColor above).
  RAID_CLASS_COLORS = {
    ["WARRIOR"] = { r = 0.78, g = 0.61, b = 0.43, colorStr = "ffc79c6e" },
    ["MAGE"]    = { r = 0.41, g = 0.8,  b = 0.94, colorStr = "ff69ccf0" },
    ["ROGUE"]   = { r = 1,    g = 0.96, b = 0.41, colorStr = "fffff569" },
    ["DRUID"]   = { r = 1,    g = 0.49, b = 0.04, colorStr = "ffff7d0a" },
    ["HUNTER"]  = { r = 0.67, g = 0.83, b = 0.45, colorStr = "ffabd473" },
    ["SHAMAN"]  = { r = 0.14, g = 0.35, b = 1.0,  colorStr = "ff0070de" },
    ["PRIEST"]  = { r = 1,    g = 1,    b = 1,    colorStr = "ffffffff" },
    ["WARLOCK"] = { r = 0.58, g = 0.51, b = 0.79, colorStr = "ff9482c9" },
    ["PALADIN"] = { r = 0.96, g = 0.55, b = 0.73, colorStr = "fff58cba" },
  }

  RAID_CLASS_COLORS = setmetatable(RAID_CLASS_COLORS, { __index = function(tab,key)
    return { r = 0.6,  g = 0.6,  b = 0.6,  colorStr = "ff999999" }
  end})
end

function pfUI:UpdateFonts()
  -- abort when config is not ready yet
  if not pfUI_config or not pfUI_config.global then return end

  -- load font configuration
  local default, tooltip, unit, unit_name, combat
  if pfUI_config.global.force_region == "1" and GetLocale() == "zhCN" and pfUI.expansion == "vanilla" then
    -- force locale compatible fonts (zhCN 1.12)
    default = "Fonts\\FZXHLJW.TTF"
    tooltip = "Fonts\\FZXHLJW.TTF"
    combat = "Fonts\\FZXHLJW.TTF"
    unit = "Fonts\\FZXHLJW.TTF"
    unit_name = "Fonts\\FZXHLJW.TTF"
  elseif pfUI_config.global.force_region == "1" and GetLocale() == "zhCN" and pfUI.expansion == "tbc" then
    -- force locale compatible fonts (zhCN 2.4.3)
    default = "Fonts\\ZYHei.ttf"
    tooltip = "Fonts\\ZYHei.ttf"
    combat = "Fonts\\ZYKai_C.ttf"
    unit = "Fonts\\ZYKai_T.ttf"
    unit_name = "Fonts\\ZYHei.ttf"
  elseif pfUI_config.global.force_region == "1" and GetLocale() == "zhTW" and pfUI.expansion == "vanilla" then
    -- force locale compatible fonts (zhTW 1.12)
    default = "Fonts\\FZXHLJW.ttf"
    tooltip = "Fonts\\FZXHLJW.ttf"
    combat = "Fonts\\FZXHLJW.ttf"
    unit = "Fonts\\FZXHLJW.ttf"
    unit_name = "Fonts\\FZXHLJW.ttf"
  elseif pfUI_config.global.force_region == "1" and GetLocale() == "zhTW" and pfUI.expansion == "tbc" then
    -- force locale compatible fonts (zhTW 2.4.3)
    default = "Fonts\\bHEI01B.ttf"
    tooltip = "Fonts\\bHEI01B.ttf"
    combat = "Fonts\\bHEI01B.ttf"
    unit = "Fonts\\bHEI01B.ttf"
    unit_name = "Fonts\\bHEI01B.ttf"
  elseif pfUI_config.global.force_region == "1" and GetLocale() == "koKR" then
    -- force locale compatible fonts (koKR)
    default = "Fonts\\2002.TTF"
    tooltip = "Fonts\\2002.TTF"
    combat = "Fonts\\2002.TTF"
    unit = "Fonts\\2002.TTF"
    unit_name = "Fonts\\2002.TTF"
  else
    -- use default entries
    default = pfUI.media[pfUI_config.global.font_default]
    tooltip = pfUI.media[pfUI_config.tooltip.font_tooltip]
    combat = pfUI.media[pfUI_config.global.font_combat]
    unit = pfUI.media[pfUI_config.global.font_unit]
    unit_name = pfUI.media[pfUI_config.global.font_unit_name]
  end

  -- write setting shortcuts
  pfUI.font_default = default
  pfUI.font_combat = combat
  pfUI.font_unit = unit
  pfUI.font_unit_name = unit_name

  -- skip setting fonts, keep blizzard defaults
  if pfUI_config.global.font_blizzard == "1" then
    return
  end

  -- set game constants
  STANDARD_TEXT_FONT = default
  DAMAGE_TEXT_FONT   = combat
  NAMEPLATE_FONT     = default
  UNIT_NAME_FONT     = unit_name

  -- set dropdown font to default size
  UIDROPDOWNMENU_DEFAULT_TEXT_HEIGHT = 11

  -- change default game font objects
  SystemFont:SetFont(default, 15)
  GameFontNormal:SetFont(default, 12)
  GameFontBlack:SetFont(default, 12)
  GameFontNormalSmall:SetFont(default, 11)
  GameFontNormalLarge:SetFont(default, 16)
  GameFontNormalHuge:SetFont(default, 20)
  NumberFontNormal:SetFont(default, 14, "OUTLINE")
  NumberFontNormalSmall:SetFont(default, 14, "OUTLINE")
  NumberFontNormalLarge:SetFont(default, 16, "OUTLINE")
  NumberFontNormalHuge:SetFont(default, 30, "OUTLINE")
  QuestTitleFont:SetFont(default, 18)
  QuestFont:SetFont(default, 13)
  QuestFontHighlight:SetFont(default, 14)
  ItemTextFontNormal:SetFont(default, 15)
  MailTextFontNormal:SetFont(default, 15)
  SubSpellFont:SetFont(default, 12)
  DialogButtonNormalText:SetFont(default, 16)
  ZoneTextFont:SetFont(default, 34, "OUTLINE")
  SubZoneTextFont:SetFont(default, 24, "OUTLINE")
  GameTooltipText:SetFont(tooltip, pfUI_config.tooltip.font_tooltip_size)
  GameTooltipTextSmall:SetFont(tooltip, pfUI_config.tooltip.font_tooltip_size)
  GameTooltipHeaderText:SetFont(tooltip, pfUI_config.tooltip.font_tooltip_size + 1)
  WorldMapTextFont:SetFont(default, 102, "THICK")
  InvoiceTextFontNormal:SetFont(default, 12)
  InvoiceTextFontSmall:SetFont(default, 12)
  CombatTextFont:SetFont(combat, 25)
  ChatFontNormal:SetFont(default, 13, pfUI_config.chat.text.outline == "1" and "OUTLINE")

  if TextStatusBarTextSmall then -- does not exist in koKR
    TextStatusBarTextSmall:SetFont(default, 12, "NORMAL")
  end
end

local translations
function pfUI:GetEnvironment()
  -- load api into environment
  for m, func in pairs(pfUI.api or {}) do
    pfUI.env[m] = func
  end

  if pfUI_config and pfUI_config.global and pfUI_config.global.language and not translations then
    local lang = pfUI_config and pfUI_config.global and pfUI_config.global.language and pfUI_translation[pfUI_config.global.language] and pfUI_config.global.language or GetLocale()
    pfUI.env.T = setmetatable(pfUI_translation[lang] or {}, { __index = function(tab,key)
      local value = tostring(key)
      rawset(tab,key,value)
      return value
    end})
    translations = true
  end

  pfUI.env._G = getfenv(0)
  pfUI.env.C = pfUI_config
  pfUI.env.L = (pfUI_locale[GetLocale()] or pfUI_locale["enUS"])

  return pfUI.env
end

function pfUI:RegisterModule(name, a2, a3)
  if pfUI.module[name] then return end
  local hasv = type(a2) == "string"
  local func, version = hasv and a3 or a2, hasv and a2 or "vanilla:tbc:wotlk"

  -- check for client compatibility
  if not strfind(version, pfUI.expansion) then return end

  pfUI.module[name] = func
  table.insert(pfUI.modules, name)
  if not pfUI.bootup then
    pfUI:LoadModule(name)
  end
end

function pfUI:RegisterSkin(name, a2, a3)
  if pfUI.skin[name] then return end
  local hasv = type(a2) == "string"
  local func, version = hasv and a3 or a2, hasv and a2 or "vanilla:tbc:wotlk"

  -- check for client compatibility
  if not strfind(version, pfUI.expansion) then return end

  pfUI.skin[name] = func
  table.insert(pfUI.skins, name)
  if not pfUI.bootup then
    pfUI:LoadSkin(name)
  end
end

function pfUI:LoadModule(m)
  setfenv(pfUI.module[m], pfUI:GetEnvironment())
  pfUI.module[m]()
end

function pfUI:LoadSkin(s)
  setfenv(pfUI.skin[s], pfUI:GetEnvironment())
  pfUI.skin[s]()
end

pfUI:SetScript("OnEvent", function()
  -- enforce color updates on each event
  pfUI:UpdateColors()

  if event == "PLAYER_ENTERING_WORLD" and pfUI.colorWatcher then
    pfUI.colorWatcher:Show()
  end

  -- make sure to initialize and set our fonts
  -- each time an addon got loaded but only
  -- when the config is already accessible
  if not pfUI.bootup then
    pfUI:UpdateFonts()
  end

  if arg1 == pfUI.name then
    -- read pfUI version from .toc file
    local major, minor, fix = pfUI.api.strsplit(".", tostring(GetAddOnMetadata(pfUI.name, "Version")))
    pfUI.version.major = tonumber(major) or 1
    pfUI.version.minor = tonumber(minor) or 2
    pfUI.version.fix   = tonumber(fix)   or 0
    pfUI.version.string = pfUI.version.major .. "." .. pfUI.version.minor .. "." .. pfUI.version.fix

    -- CONFIRMED IN-GAME (user report, 2026-09-08): a client crash during
    -- logout can leave a SavedVariable explicitly written as literal
    -- "= nil" (WoW faithfully serializes whatever's in memory at save time,
    -- crash mid-write or not) rather than simply missing -- NOT the same
    -- case as "fresh install" (pfUI_init and pfUI_config both empty
    -- together, the only scenario the block below originally guarded for)
    -- and can hit pfUI_profiles/pfUI_config/pfUI_init/pfUI_cache
    -- independently of each other and of a fresh install. Any one of them
    -- nil here throws ("attempt to index...") and aborts pfUI's entire
    -- ADDON_LOADED handling -- which cascades hard, since pfQuest,
    -- LoseControl, ModernMapMarkers, BetterCharacterPanel etc. all call
    -- into pfUI's own shared skinning API (CreateBackdrop -> GetBorderSize,
    -- both index pfUI_config) for their own UI, so a nil pfUI_config breaks
    -- THEM too, not just pfUI. Guard all four defensively up front, before
    -- anything below (or any later event, e.g. libhealth.lua/libpredict.lua
    -- on PLAYER_ENTERING_WORLD, which index pfUI_cache) touches them --
    -- same fix shape as the earlier pfUI_profiles-only guard in
    -- env\profiles.lua, but here at the point actually guaranteed to run
    -- AFTER SavedVariables have loaded (env\profiles.lua's own top-level
    -- code runs too early to survive a SavedVariables file that overwrites
    -- pfUI_profiles again, e.g. back to a literal nil, right after).
    pfUI_profiles = pfUI_profiles or {}
    pfUI_init = pfUI_init or {}
    pfUI_config = pfUI_config or {}
    pfUI_cache = pfUI_cache or {}
    pfUI_throttle = pfUI_throttle or {}

    -- use "Modern" as default profile on a fresh install
    if pfUI.api.isempty(pfUI_init) and pfUI.api.isempty(pfUI_config) then
      pfUI_config = pfUI.api.CopyTable(pfUI_profiles["Modern"]) or {}
    end

    pfUI:LoadConfig()
    pfUI:MigrateConfig()
    pfUI:UpdateFonts()

    -- load modules
    for _, m in pairs(this.modules) do
      if not ( pfUI_config["disabled"] and pfUI_config["disabled"][m]  == "1" ) then
        pfUI:LoadModule(m)
      end
    end

    -- load skins
    for _, s in pairs(this.skins) do
      if not ( pfUI_config["disabled"] and pfUI_config["disabled"]["skin_" .. s]  == "1" ) then
        pfUI:LoadSkin(s)
      end
    end

    pfUI.bootup = nil
  end
end)

pfUI.backdrop = {
  bgFile = "Interface\\BUTTONS\\WHITE8X8", tile = false, tileSize = 0,
  edgeFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 1,
  insets = {left = -1, right = -1, top = -1, bottom = -1},
}
pfUI.backdrop_no_top = pfUI.backdrop

pfUI.backdrop_thin = {
  bgFile = "Interface\\BUTTONS\\WHITE8X8", tile = false, tileSize = 0,
  edgeFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 1,
  insets = {left = 0, right = 0, top = 0, bottom = 0},
}

pfUI.backdrop_hover = {
  edgeFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 24,
  insets = {left = -1, right = -1, top = -1, bottom = -1},
}

pfUI.backdrop_shadow = {
  edgeFile = pfUI.media["img:glow2"], edgeSize = 8,
  insets = {left = 0, right = 0, top = 0, bottom = 0},
}

pfUI.backdrop_blizz_bg = {
  bgFile =  "Interface\\BUTTONS\\WHITE8X8", tile = true, tileSize = 8,
  insets = { left = 3, right = 3, top = 3, bottom = 3 }
}

pfUI.backdrop_blizz_border = {
  edgeFile = pfUI.media["img:border_blizz"], edgeSize = 6,
  insets = { left = 3, right = 3, top = 3, bottom = 3 }
}

pfUI.backdrop_blizz_full = {
  bgFile =  "Interface\\BUTTONS\\WHITE8X8", tile = true, tileSize = 8,
  edgeFile = pfUI.media["img:border_blizz"], edgeSize = 6,
  insets = { left = 3, right = 3, top = 3, bottom = 3 }
}

message = function(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cffcccc33INFO: |cffffff55" .. ( msg or "nil" ))
end
print = print or message

error = function(msg)
  if PF_DEBUG_MODE then message(debugstack()) end
  if string.find(msg, "AddOns\\pfUI") then
    DEFAULT_CHAT_FRAME:AddMessage("|cffcc3333ERROR: |cffff5555".. (msg or "nil" ))
  elseif not pfUI_config or (pfUI_config.global and pfUI_config.global.errors == "1") then
    DEFAULT_CHAT_FRAME:AddMessage("|cffcc3333ERROR: |cffff5555".. (msg or "nil" ))
  end
end
seterrorhandler(error)

function pfUI.SetupCVars()
  ClearTutorials()
  TutorialFrame_HideAllAlerts()

  ConsoleExec("CameraDistanceMaxFactor 5")

  SetCVar("autoSelfCast", "1")
  SetCVar("profanityFilter", "0")

  MultiActionBar_ShowAllGrids()
  ALWAYS_SHOW_MULTIBARS = "1"

  SHOW_BUFF_DURATIONS = "1"
  QUEST_FADING_DISABLE = "1"
  NAMEPLATES_ON = "1"
  SIMPLE_CHAT = "0"

  SHOW_COMBAT_TEXT = "1"
  COMBAT_TEXT_SHOW_LOW_HEALTH_MANA = "1"
  COMBAT_TEXT_SHOW_AURAS = "1"
  COMBAT_TEXT_SHOW_AURA_FADE = "1"
  COMBAT_TEXT_SHOW_COMBAT_STATE = "1"
  COMBAT_TEXT_SHOW_DODGE_PARRY_MISS = "1"
  COMBAT_TEXT_SHOW_RESISTANCES = "1"
  COMBAT_TEXT_SHOW_REPUTATION = "1"
  COMBAT_TEXT_SHOW_REACTIVES = "1"
  COMBAT_TEXT_SHOW_FRIENDLY_NAMES = "1"
  COMBAT_TEXT_SHOW_COMBO_POINTS = "1"
  COMBAT_TEXT_SHOW_MANA = "1"
  COMBAT_TEXT_FLOAT_MODE = "1"
  COMBAT_TEXT_SHOW_HONOR_GAINED = "1"
  UIParentLoadAddOn("Blizzard_CombatText")
end
