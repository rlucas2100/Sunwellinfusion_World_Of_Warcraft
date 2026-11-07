--[[ SunwellInfusion - ENGINE DISPLAY
  Where buffs are hidden from addons (M+, raids, boss fights), the game draws
  Infusion of Light itself in an AuraContainer (patch 12.1). We only style it:
    left socket  : lit sun-gem (the buff is up = at least 1 charge)
    right socket : the game writes the charge count here ("2" when you have
                   both; blank with 1), in big glowing gold
  The game also runs the timer and bar. A sparkle chime is registered with the game
  (C_UnitAuras.AddAuraSound) because addons can't see the buff arrive here. ]]

local ADDON, NS = ...

local parent, container
local built = false
local soundHandles = {}

local function AurasSecret()
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local ok, r = pcall(C_Secrets.ShouldAurasBeSecret)
        if ok then return r == true end
    end
    return false
end

local supported
local function Supported()
    if supported ~= nil then return supported end
    supported = false
    if not C_AuraContainerUtil then return false end
    local ok, f = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
    if ok and f then f:Hide(); supported = true end
    return supported
end

-- The ball font. WoW loads font files lazily, so we create it (and draw a
-- hidden "2" with it) as soon as the addon loads, long before any dungeon.
local orbFonts = {}
function NS.OrbFont(size)
    if not orbFonts[size] then
        local fo = CreateFont("SunwellInfusionOrb" .. size)
        fo:SetFont(NS.MEDIA .. "orb.ttf", size, "THICKOUTLINE")
        orbFonts[size] = fo
    end
    return orbFonts[size]
end
do
    local warm = CreateFrame("Frame", nil, UIParent)
    warm:SetSize(1, 1); warm:SetPoint("TOPLEFT", -100, 100); warm:SetAlpha(0.01)
    local fs = warm:CreateFontString(nil, "OVERLAY")
    fs:SetFontObject(NS.OrbFont(math.floor((NS.GEM or 74) * 0.95)))
    fs:SetText("2")
    NS.warmOrb = fs
end

-- 2nd-charge box font (media\\orbbox.ttf): every glyph is invisible, "2" is a
-- square box, "1"/blank take no space. The purple gem + effects are stretched
-- over the game's charge string, so they only exist when you have 2 charges.
local BOX_FS = math.floor((NS.GEM or 74) * 0.95)
local BOX_FONT = NS.MEDIA .. "orbbox.ttf"
local warmBox = NS.warmOrb:GetParent():CreateFontString(nil, "OVERLAY")
warmBox:SetFont(BOX_FONT, BOX_FS, "")
warmBox:SetText("2")

-- width of the "2" box (measured on our own readable copy of the string)
function NS.OrbBoxSize()
    local w = warmBox:GetStringWidth()
    if not w or w < 2 then return BOX_FS * 2 end
    return w
end

local boxStrings = {}
local function BuildPurpleCharge(owner, holder, x, y)
    local count = holder:CreateFontString(nil, "OVERLAY", nil, 7)
    count:SetFont(BOX_FONT, BOX_FS, "")
    count:SetTextColor(1, 1, 1, 0)
    count:SetShadowColor(0, 0, 0, 0)
    count:SetPoint("CENTER", owner, "CENTER", x, y)
    count:SetText("")
    boxStrings[#boxStrings + 1] = count
    local g = NS.BuildGem(owner, x, y, NS.GEM, "purple", { anchor = count })
    g:Fit(NS.OrbBoxSize())
    g:PlayAll()
    NS.anchoredGems = NS.anchoredGems or {}
    NS.anchoredGems[#NS.anchoredGems + 1] = g
    return count, g
end

-- /si orbtest: the in-combat 2nd charge, run outside combat.
-- "2" for 4 sec (full purple gem), then "1" (it must vanish)
function NS.OrbTest()
    if not NS.orbTestFrame then
        local f = CreateFrame("Frame", nil, UIParent)
        f:SetSize(NS.GEM * 2, NS.GEM * 2)
        f:SetPoint("CENTER", 0, 140)
        f:SetFrameStrata("HIGH")
        NS.BuildSocket(f, 0, 0, NS.GEM)
        NS.orbTestFrame = f
        NS.orbTestCount = BuildPurpleCharge(f, f, 0, 0)
    end
    local box = NS.OrbBoxSize()
    for _, gm in ipairs(NS.anchoredGems or {}) do gm:Fit(box) end
    local f, c = NS.orbTestFrame, NS.orbTestCount
    f:SetScale((NS.GetDB() and NS.GetDB().scale) or 1)
    f:Show(); c:SetText("2")
    C_Timer.After(4, function() c:SetText("1") end)
    C_Timer.After(6, function() f:Hide() end)
end

local function InitButton(button)
    local W, H, GEM = NS.W, NS.H, NS.GEM
    local GX = GEM * 0.62
    button:SetSize(W, H)

    NS.BuildTitle(button)
    NS.BuildSocket(button, -GX, 2, GEM)
    NS.BuildSocket(button, GX, 2, GEM)
    local g = NS.BuildGem(button, -GX, 2, GEM, "orange")
    g:PlayAll()
    NS.engineGems = NS.engineGems or {}
    NS.engineGems[#NS.engineGems + 1] = g

    -- the game sets the real buff icon here (small, inside the lit gem)
    local icon = button:CreateTexture(nil, "ARTWORK", nil, 4)
    icon:SetSize(GEM * 0.36, GEM * 0.36)
    icon:SetPoint("CENTER", button, "CENTER", -GX, 2)
    icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    icon:SetAlpha(0)          -- the game still needs an icon slot, but we don't show it
    button:SetIcon(icon)

    -- second charge: the game writes the charge count into an invisible box
    -- string; the full purple gem + glow, rays, ring and sparkles are stretched
    -- over it, centred in the right socket, so they show with 2 charges and
    -- vanish with 1 - identical to the orange gem on the left.
    local holder = CreateFrame("Frame", nil, button)
    holder:SetAllPoints()
    holder:SetFrameLevel(button:GetFrameLevel() + 3)
    local count = BuildPurpleCharge(button, holder, GX, 2)
    if button.SetApplicationCount then button:SetApplicationCount(count) end

    -- timer (game-driven countdown numbers) between the gems, and draining bar
    local cd = CreateFrame("Cooldown", nil, holder, "CooldownFrameTemplate")
    cd:SetSize(60, 36)
    cd:SetPoint("CENTER", button, "CENTER", 0, 2)
    cd:SetDrawSwipe(false); cd:SetDrawEdge(false); cd:SetDrawBling(false)
    cd:SetHideCountdownNumbers(false)
    pcall(cd.SetCountdownFont, cd, "SunwellInfusionTimerFont")
    button:SetDurationCooldown(cd)

    if button.SetDurationBar then
        local bar = CreateFrame("StatusBar", nil, holder)
        bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        bar:SetStatusBarColor(1, 0.55, 0.2)
        bar:SetPoint("BOTTOMLEFT", 30, 4); bar:SetPoint("BOTTOMRIGHT", -30, 4)
        bar:SetHeight(6)
        local bg = bar:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.55)
        local interp = Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Linear
        pcall(button.SetDurationBar, button, bar, interp and { interpolation = interp } or {})
    end
end

local function RegisterSound()
    if not (C_UnitAuras and C_UnitAuras.AddAuraSound and Enum.UnitAuraSoundTrigger) then return end
    for _, h in ipairs(soundHandles) do
        if C_UnitAuras.RemoveAuraSound then pcall(C_UnitAuras.RemoveAuraSound, h) end
    end
    wipe(soundHandles)
    local db = NS.GetDB()
    if not (db and db.sound) then return end
    if InCombatLockdown() then return end
    local info = { unitToken = "player", spellID = NS.IOL_ID,
                   soundFileName = NS.MEDIA .. "chime.ogg", outputChannel = "Master" }
    for _, trig in ipairs({ "Added", "ApplicationGained", "ApplicationAdded" }) do
        local t = Enum.UnitAuraSoundTrigger[trig]
        if t then
            local ok, h = pcall(C_UnitAuras.AddAuraSound, t, info)
            if ok and h then soundHandles[#soundHandles + 1] = h end
        end
    end
end
NS.EngineSound = RegisterSound
NS.EngineSoundRegistered = function() return #soundHandles > 0 end

local function Build()
    if built then return true end
    if not Supported() then return false end
    parent = CreateFrame("Frame", "SunwellInfusionEngine", UIParent)
    parent:SetSize(NS.W, NS.H)
    parent:SetPoint("CENTER", NS.frame, "CENTER")
    parent:SetFrameStrata("HIGH")
    parent:Hide()
    local ids = { [NS.IOL_ID] = true }
    for _, id in ipairs(NS.EXTRA_IDS) do ids[id] = true end
    local ok, err = pcall(function()
        container = CreateFrame("AuraContainer", "SunwellInfusionEngineContainer", parent, "CustomAuraContainerTemplate")
        container:Hide()
        container:SetPoint("TOPLEFT", parent, "TOPLEFT")
        container:SetFrameStrata("HIGH")
        container:SetUnit("player")
        container:AddAuraGroup("iol", "HELPFUL", {
            maxFrameCount = 1,
            candidateFilters = { includeSpellIDs = ids },
            initializeFrame = function(button)
                local okI, errI = pcall(InitButton, button)
                if not okI then NS.Print("engine build error: " .. tostring(errI)) end
            end,
            layout = { elementWidth = NS.W, elementHeight = NS.H, elementSpacing = 0, lineSpacing = 0,
                       elementSpacingX = 0, elementSpacingY = 0, layoutIndex = 1 },
        })
        container:Show()
    end)
    if not ok then NS.Print("Engine display unavailable: " .. tostring(err)) return false end
    built = true
    return true
end

local function Wanted()
    local db = NS.GetDB()
    local mode = db and db.engine or "auto"
    if mode == "off" then return false end
    if mode == "on" then return true end
    return AurasSecret()
end

NS.EngineActive = function() return built and parent and parent:IsShown() or false end
NS.EngineApplyScale = function()
    local db = NS.GetDB()
    if parent and db then parent:SetScale(db.scale or 1) end
end
NS.EngineStatus = function()
    if not built then return Supported() and "Engine: not built yet" or "Engine: |cffff4040not supported|r" end
    return "Engine: |cff00ff00built|r, " .. (parent:IsShown() and "|cff00ff00ACTIVE|r" or "standby")
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    pcall(Build)
    NS.EngineApplyScale()
    for _, delay in ipairs({ 1, 3, 8 }) do
        C_Timer.After(delay, function()
            if InCombatLockdown() then return end
            for _, fs in ipairs(boxStrings) do pcall(fs.SetFont, fs, BOX_FONT, BOX_FS, "") end
            local box = NS.OrbBoxSize()
            for _, gm in ipairs(NS.anchoredGems or {}) do gm:Fit(box) end
        end)
    end
    pcall(RegisterSound)
    C_Timer.NewTicker(0.25, function()
        if not built then return end
        local want = Wanted()
        if want and not parent:IsShown() then parent:Show()
        elseif not want and parent:IsShown() then parent:Hide() end
    end)
end)
