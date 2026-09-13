-- pfUI Druid Mana Bar
-- Shows a druid's mana while shapeshifted into a non-mana form.
-- Uses Nampower GetUnitField() when available and SuperWoW's extended
-- UnitMana() return value as a fallback for the player.

pfUI.druidmana = pfUI.druidmana or {}

pfUI:RegisterModule("druidmana", "vanilla", function ()
  local C = pfUI_config
  local DC = C.unitframes


  local _, playerClass = UnitClass("player")
  if playerClass ~= "DRUID" and not GetUnitField then return end

  local _, default_border = GetBorderSize("unitframes")
  local bars = {}

  local function GetMana(unit)
    local mana, maxmana

    -- Nampower exposes the underlying mana slot even while shapeshifted.
    if GetUnitField then
      mana = GetUnitField(unit, "power1")
      maxmana = GetUnitField(unit, "maxPower1")
      if type(mana) == "number" and type(maxmana) == "number" and maxmana > 0 then
        return math.floor(mana), math.floor(maxmana)
      end
    end

    -- SuperWoW exposes the caster's mana as the second return value of
    -- UnitMana/UnitManaMax. This is reliable for the player, but not for
    -- arbitrary target units, so don't pretend it is available there.
    if unit == "player" and SUPERWOW_VERSION and UnitMana and UnitManaMax then
      local _, casterMana = UnitMana(unit)
      local _, casterMaxMana = UnitManaMax(unit)
      if type(casterMana) == "number" and type(casterMaxMana) == "number" and casterMaxMana > 0 then
        return math.floor(casterMana), math.floor(casterMaxMana)
      end
    end

    return nil, nil
  end

  local function IsShapeshifted(unit)
    if not UnitExists(unit) then return false end
    if not UnitPowerType then return false end

    -- Power type 0 is mana. Rage/energy/etc. means the druid is shifted and
    -- the secondary mana bar should be visible.
    return UnitPowerType(unit) ~= 0
  end

  local function SetBarFont(bar)
    local parent = bar.parent
    local fontname = pfUI.font_unit
    local fontsize = tonumber(C.global.font_unit_size) or 12
    local fontstyle = C.global.font_unit_style or "OUTLINE"

    if parent and parent.config and parent.config.customfont == "1" then
      fontname = pfUI.media[parent.config.customfont_name] or fontname
      fontsize = tonumber(parent.config.customfont_size) or fontsize
      fontstyle = parent.config.customfont_style or fontstyle
    end

    bar.text:SetFont(fontname, fontsize, fontstyle)
  end

  local function SetBarColor(bar)
    local manaColor = DC.manacolor or ".5,.5,1,1"
    local r, g, b, a = pfUI.api.strsplit(",", manaColor)
    r, g, b, a = tonumber(r) or .5, tonumber(g) or .5, tonumber(b) or 1, tonumber(a) or 1
    bar:SetStatusBarColor(r, g, b, a)

    if bar.text then
      if DC.pastel == "1" then
        bar.text:SetTextColor((r + .75) * .5, (g + .75) * .5, (b + .75) * .5, a)
      else
        bar.text:SetTextColor(r, g, b, a)
      end
    end
  end

  local function SetBarGeometry(bar)
    local parent = bar.parent
    if not parent or not parent.power then return end

    local height = tonumber(DC.druidmanaheight) or 6
    local width = tonumber(DC.druidmanawidth)
    local offx = tonumber(DC.druidmanaoffx) or 0
    local offy = tonumber(DC.druidmanaoffy) or 0
    local space = tonumber(DC.druidmanaspace)
    if space == nil then space = 0 end

    local power = parent.power
    bar:ClearAllPoints()
    bar:SetHeight(height)

    if width and width >= 0 then
      bar:SetWidth(width)
      bar:SetPoint("TOP", power, "BOTTOM", offx, -2 * default_border - space + offy)
    else
      bar:SetPoint("TOPLEFT", power, "BOTTOMLEFT", offx, -2 * default_border - space + offy)
      bar:SetPoint("TOPRIGHT", power, "BOTTOMRIGHT", offx, -2 * default_border - space + offy)
    end

    local texture = DC.druidmanatexture or DC.druidmana_texture or DC.player and DC.player.pbartexture
    texture = texture or "Interface\\AddOns\\pfUI\\img\\bar"
    bar:SetStatusBarTexture(pfUI.media[texture] or texture)
  end

  local function UpdateText(bar, mana, maxmana)
    if DC.druidmanatext ~= "1" then
      bar.text:Hide()
      return
    end

    bar.text:Show()
    bar.text:SetText(string.format("%s/%s", Abbreviate(mana), Abbreviate(maxmana)))
  end

  local function UpdateBar(bar)
    if not bar or not bar.parent then return end

    local unit = bar.unit
    local enabled = DC.druidmanabar == "1"

    if not enabled or not UnitExists(unit) or not IsShapeshifted(unit) then
      bar:Hide()
      return
    end

    -- Target mana requires Nampower. SuperWoW's special UnitMana return is
    -- player-only, matching the original DruidManaBar addon behavior.
    if unit ~= "player" and not GetUnitField then
      bar:Hide()
      return
    end

    if unit ~= "player" then
      local _, class = UnitClass(unit)
      if class ~= "DRUID" then
        bar:Hide()
        return
      end
    end

    local mana, maxmana = GetMana(unit)
    if not mana or not maxmana or maxmana <= 0 then
      bar:Hide()
      return
    end

    bar:SetMinMaxValues(0, maxmana)
    bar:SetValue(math.min(mana, maxmana))
    UpdateText(bar, mana, maxmana)
    SetBarColor(bar)
    bar:Show()
  end

  local function CreateBar(parent, unit)
    if not parent or not parent.power then return nil end

    local name = "pfDruidMana_" .. unit
    local bar = CreateFrame("StatusBar", name, parent)
    bar.parent = parent
    bar.unit = unit
    bar:SetFrameStrata(parent:GetFrameStrata())
    bar:SetFrameLevel(parent:GetFrameLevel() + 5)
    bar:EnableMouse(false)
    bar:Hide()

    bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bar.text:SetFontObject(GameFontWhite)
    bar.text:SetJustifyH("CENTER")
    bar.text:SetPoint("CENTER", bar, "CENTER", 0, 0)

    CreateBackdrop(bar)
    CreateBackdropShadow(bar)

    SetBarFont(bar)

    bar.elapsed = 0
    bar:SetScript("OnUpdate", function()
      if not bar:IsShown() then
        bar.elapsed = 0
        return
      end

      bar.elapsed = bar.elapsed + arg1
      if bar.elapsed >= 0.10 then
        bar.elapsed = 0
        UpdateBar(bar)
      end
    end)

    bar:RegisterEvent("UNIT_MANA")
    bar:RegisterEvent("UNIT_MAXMANA")
    bar:RegisterEvent("UNIT_DISPLAYPOWER")
    bar:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    bar:RegisterEvent("PLAYER_AURAS_CHANGED")
    bar:RegisterEvent("PLAYER_ENTERING_WORLD")
    if unit == "target" then
      bar:RegisterEvent("PLAYER_TARGET_CHANGED")
    end

    bar:SetScript("OnEvent", function()
      if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_ENTERING_WORLD" or event == "UPDATE_SHAPESHIFT_FORM" or event == "PLAYER_AURAS_CHANGED" then
        UpdateBar(bar)
        return
      end

      if arg1 == nil or arg1 == unit then
        UpdateBar(bar)
      end
    end)

    SetBarGeometry(bar)
    SetBarColor(bar)
    bars[unit] = bar
    UpdateBar(bar)
    return bar
  end

  if pfUI.uf and pfUI.uf.player then
    CreateBar(pfUI.uf.player, "player")
  end

  if pfUI.uf and pfUI.uf.target and DC.druidmanatarget == "1" then
    CreateBar(pfUI.uf.target, "target")
  end

  -- Apply settings immediately and whenever the normal pfUI unit-frame
  -- configuration is changed from the GUI.
  function pfUI.druidmana.UpdateConfig()
    DC = pfUI_config.unitframes

    for unit, bar in pairs(bars) do
      SetBarGeometry(bar)
      SetBarFont(bar)
      SetBarColor(bar)
      UpdateBar(bar)
    end

    if DC.druidmanatarget == "1" then
      if not bars.target and pfUI.uf and pfUI.uf.target then
        CreateBar(pfUI.uf.target, "target")
      end
    elseif bars.target then
      bars.target:Hide()
    end
  end

  -- Hook unit-frame updates so custom fonts, power-bar size and other frame
  -- settings are reflected on the secondary mana bar immediately.
  if pfUI.uf.player then
    local oldPlayerUpdate = pfUI.uf.player.UpdateConfig
    pfUI.uf.player.UpdateConfig = function()
      oldPlayerUpdate()
      pfUI.druidmana.UpdateConfig()
    end
  end

  if pfUI.uf.target then
    local oldTargetUpdate = pfUI.uf.target.UpdateConfig
    pfUI.uf.target.UpdateConfig = function()
      oldTargetUpdate()
      pfUI.druidmana.UpdateConfig()
    end
  end
end)
