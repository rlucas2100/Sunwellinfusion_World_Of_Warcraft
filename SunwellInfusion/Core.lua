--[[ =========================================================================
  SunwellInfusion - big, bright Infusion of Light charges for Holy Paladin

  Infusion of Light (buff 54149) holds up to 2 charges with the talent
  Inflorescence of the Sunwell. The Season 2 4-piece doesn't add a new buff:
  it just grants more Infusion of Light (Judgment 20%, Holy Light 100%),
  so every source lands here.

  Two display modes, switched automatically:
    * Normal   - where the game lets addons read the buff: two sun-gems that
                 light up per charge, pop + sparkle chime when you gain one.
    * Engine   - where buffs are hidden from addons (M+, raids, boss fights):
                 the game draws it itself (see Engine.lua); the 2nd socket
                 shows a glowing "2" when you have both charges.

  /si            - help
  /si test       - preview (2 charges, then 1)
  /si unlock     - drag it,  /si lock to finish
  /si scale 1.3  - resize
  /si sound      - sparkle chime on/off
  /si engine auto|on|off
  /si reset
========================================================================= ]]

local ADDON, NS = ...
local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\media\\"
local IOL_ID = 54149
local EXTRA_IDS = {}        -- add alternative Infusion of Light IDs here if ever needed

local W, H, GEM = 230, 124, 74
NS.W, NS.H, NS.GEM, NS.MEDIA, NS.IOL_ID, NS.EXTRA_IDS = W, H, GEM, MEDIA, IOL_ID, EXTRA_IDS

-- big timer font (also used by the game-drawn countdown in Engine.lua)
local timerFont = CreateFont("SunwellInfusionTimerFont")
timerFont:SetFont("Fonts\\FRIZQT__.TTF", 28, "THICKOUTLINE")

local defaults = { point = "CENTER", relPoint = "CENTER", x = 0, y = -160, scale = 1, sound = true, engine = "auto" }
local db
NS.GetDB = function() return db end

local function Print(m) print("|cffffd200Sunwell|r|cffffffffInfusion|r: " .. tostring(m)) end
NS.Print = Print

local function Readable(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function HSV(h, s, v)
    h = (h % 1) * 6
    local i = math.floor(h); local f = h - i
    local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
    if i == 0 then return v, t, p elseif i == 1 then return q, v, p elseif i == 2 then return p, v, t
    elseif i == 3 then return p, q, v elseif i == 4 then return t, p, v else return v, p, q end
end

-- ---------------------------------------------------------------------------
-- Shared artwork (pure AnimationGroups, so it also works on engine buttons)
-- ---------------------------------------------------------------------------
local function Anim(region, looping, list)
    local ag = region:CreateAnimationGroup()
    if looping then ag:SetLooping(looping) end
    for _, a in ipairs(list) do
        local an = ag:CreateAnimation(a.type)
        an:SetDuration(a.d)
        an:SetOrder(a.order or 1)
        if a.delay then an:SetStartDelay(a.delay) end
        if a.type == "Alpha" then an:SetFromAlpha(a.from); an:SetToAlpha(a.to)
        elseif a.type == "Rotation" then an:SetDegrees(a.deg)
        elseif a.type == "Translation" then an:SetOffset(a.x, a.y)
        elseif a.type == "Scale" then an:SetScaleFrom(a.from, a.from); an:SetScaleTo(a.to, a.to) end
        if a.smooth then an:SetSmoothing(a.smooth) end
    end
    return ag
end
NS.Anim = Anim

function NS.BuildSocket(owner, x, y, size)
    local t = owner:CreateTexture(nil, "BORDER", nil, 1)
    t:SetTexture(MEDIA .. "socket")
    t:SetSize(size * 1.05, size * 1.05)
    t:SetPoint("CENTER", owner, "CENTER", x, y)
    return t
end

-- Look shared by BOTH charges in BOTH modes (normal + engine), so orange and
-- purple always match: full-colour gem + pulsing glow, spinning rays, spinning
-- ring and flying sparkles.
NS.ORB_COLORS = {
    orange = { text = { 1, 0.6, 0.18 },    shadow = { 1, 0.42, 0.05, 0.9 },
               halo = { 1, 0.55, 0.12 },   rays = { 1, 0.6, 0.18 },   spark = 0.02 },
    purple = { text = { 0.74, 0.38, 1 },   shadow = { 0.55, 0.1, 1, 0.9 },
               halo = { 0.7, 0.3, 1 },     rays = { 0.72, 0.42, 1 },  spark = 0.7 },
}

-- style a font string as the orb (also used on the game-driven charge string)
function NS.StyleOrb(fs, variant, anims)
    local c = NS.ORB_COLORS[variant] or NS.ORB_COLORS.orange
    local size = math.floor(GEM * 0.95)
    fs:SetFont(MEDIA .. "orb.ttf", size, "THICKOUTLINE")
    fs:SetTextColor(unpack(c.text))
    fs:SetShadowColor(unpack(c.shadow))
    fs:SetShadowOffset(0, 0)
    local ag = Anim(fs, "REPEAT", {
        { type = "Alpha", from = 1, to = 0.75, d = 0.45, order = 1 },
        { type = "Alpha", from = 0.75, to = 1, d = 0.45, order = 2 } })
    if anims then anims[#anims + 1] = ag else ag:Play() end
    return size
end

-- owner/x/y/size: where the orb sits.  variant: "orange" or "purple".
-- opts.anchor: engine-mode 2nd charge. The effects are stretched over the game's
--   charge string instead of a fixed size; that string is a wide box with 2
--   charges and zero width with 1, so the effects come and go with the charge.
--   (media\\orbbox.ttf: invisible glyphs, "2" = square box, "1"/blank = 0 wide)
function NS.BuildGem(owner, x, y, size, variant, opts)
    opts = opts or {}
    variant = (variant == "purple") and "purple" or "orange"
    local c = NS.ORB_COLORS[variant]
    local anchor, yOff = opts.anchor, opts.yOff or 0
    local g = { parts = {}, anims = {}, scales = {} }
    local function tex(file, layer, sub, scale, blend)
        local t = owner:CreateTexture(nil, layer, nil, sub)
        if anchor then
            t:SetTexture(MEDIA .. file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            t:SetPoint("LEFT", anchor, "LEFT", 0, yOff)
            t:SetPoint("RIGHT", anchor, "RIGHT", 0, yOff)
            t:SetHeight(size * scale)
            g.scales[t] = scale
        else
            t:SetTexture(MEDIA .. file)
            t:SetSize(size * scale, size * scale)
            t:SetPoint("CENTER", owner, "CENTER", x, y)
        end
        if blend then t:SetBlendMode(blend) end
        g.parts[#g.parts + 1] = t
        return t
    end

    local halo = tex("glow_outer", "BORDER", 2, 1.9, "ADD")
    halo:SetVertexColor(c.halo[1], c.halo[2], c.halo[3], 1)
    g.anims[#g.anims + 1] = Anim(halo, "REPEAT", {
        { type = "Alpha", from = 0.55, to = 1, d = 0.6, order = 1, smooth = "IN_OUT" },
        { type = "Alpha", from = 1, to = 0.55, d = 0.6, order = 2, smooth = "IN_OUT" } })

    local rays = tex("rays_white", "BORDER", 3, 1.7)
    rays:SetVertexColor(unpack(c.rays))
    g.anims[#g.anims + 1] = Anim(rays, "REPEAT", { { type = "Rotation", deg = -360, d = 12 } })
    g.anims[#g.anims + 1] = Anim(rays, "REPEAT", {
        { type = "Scale", from = 1, to = 1.07, d = 0.5, order = 1, smooth = "IN_OUT" },
        { type = "Scale", from = 1.07, to = 1, d = 0.5, order = 2, smooth = "IN_OUT" } })

    local ring = tex("ring", "ARTWORK", 1, 1.25)
    g.anims[#g.anims + 1] = Anim(ring, "REPEAT", { { type = "Rotation", deg = 360, d = 3.5 } })

    -- the full-colour gem, centred in its socket, with a gentle breathing bounce
    local gem = tex(variant == "purple" and "gem_purple" or "gem_orange", "ARTWORK", 2, 1.0)
    if not gem:GetTexture() then
        -- art not loaded yet (needs a full game restart): tint the gold gem instead
        if anchor then gem:SetTexture(MEDIA .. "gem", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        else gem:SetTexture(MEDIA .. "gem") end
        if variant == "purple" then gem:SetDesaturated(true); gem:SetVertexColor(0.82, 0.5, 1)
        else gem:SetVertexColor(1, 0.7, 0.45) end
    end
    g.anims[#g.anims + 1] = Anim(gem, "REPEAT", {
        { type = "Scale", from = 1, to = 1.05, d = 0.45, order = 1, smooth = "IN_OUT" },
        { type = "Scale", from = 1.05, to = 1, d = 0.45, order = 2, smooth = "IN_OUT" } })

    -- sparkles flying outward
    for i = 0, 9 do
        local ang = i * (math.pi * 2 / 10) + 0.3
        local r, gg, b = HSV(c.spark + (i % 4) * (variant == "purple" and 0.06 or 0.035), 0.5, 1)
        local sp = tex("spark", "OVERLAY", 5, 0.3)
        sp:SetVertexColor(r, gg, b, 1)
        sp:SetAlpha(0)
        local dist = size * (0.75 + (i % 3) * 0.12)
        g.anims[#g.anims + 1] = Anim(sp, "REPEAT", {
            { type = "Translation", x = math.cos(ang) * dist, y = math.sin(ang) * dist, d = 0.9, delay = i * 0.13, smooth = "OUT" },
            { type = "Alpha", from = 1, to = 0, d = 0.9, delay = i * 0.13 },
            { type = "Scale", from = 1.2, to = 0.4, d = 0.9, delay = i * 0.13 },
        })
    end

    -- one-shot "pop" when a charge arrives (normal mode)
    g.pop = Anim(gem, nil, {
        { type = "Scale", from = 1.6, to = 1, d = 0.25, smooth = "OUT" },
        { type = "Alpha", from = 0.3, to = 1, d = 0.15 } })
    g.flash = tex("glow_outer", "OVERLAY", 6, 2.6, "ADD")
    g.flash:SetVertexColor(1, 1, 0.8, 1)
    g.flash:SetAlpha(0)
    g.flashAnim = Anim(g.flash, nil, { { type = "Alpha", from = 1, to = 0, d = 0.45 } })

    function g:Show()
        for _, p in ipairs(self.parts) do p:Show() end
        for _, a in ipairs(self.anims) do if not a:IsPlaying() then a:Play() end end
    end
    function g:Hide()
        for _, p in ipairs(self.parts) do p:Hide() end
        for _, a in ipairs(self.anims) do a:Stop() end
    end
    function g:Pop()
        self.pop:Stop(); self.pop:Play()
        self.flashAnim:Stop(); self.flashAnim:Play()
    end
    function g:PlayAll() for _, a in ipairs(self.anims) do a:Play() end end
    -- anchored only: box = width of the game's "2" string. Each texture becomes a
    -- box x box square and its image is shrunk back to its normal size inside it.
    function g:Fit(box)
        if not anchor or not box or box <= 0 then return end
        for t, sc in pairs(self.scales) do
            local a = (box / (size * sc) - 1) / 2
            t:SetHeight(box)
            t:SetTexCoord(-a, 1 + a, -a, 1 + a)
        end
    end
    function g:RefreshFont() end
    return g
end

function NS.BuildTitle(owner)
    local t = owner:CreateFontString(nil, "OVERLAY", nil, 7)
    t:SetFont("Fonts\\FRIZQT__.TTF", 14, "THICKOUTLINE")
    t:SetPoint("TOP", owner, "TOP", 0, -2)
    t:SetTextColor(1, 0.62, 0.22)
    t:SetText("INFUSION OF LIGHT")
    local hint = owner:CreateFontString(nil, "OVERLAY", nil, 7)
    hint:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    hint:SetPoint("BOTTOM", owner, "BOTTOM", 0, 14)
    hint:SetTextColor(1, 0.95, 0.75)
    hint:SetText("Flash of Light  |  Judgment")
    return t, hint
end

-- ---------------------------------------------------------------------------
-- Normal display
-- ---------------------------------------------------------------------------
local frame = CreateFrame("Frame", "SunwellInfusionFrame", UIParent)
frame:SetSize(W, H)
frame:SetFrameStrata("HIGH")
frame:SetClampedToScreen(true)
frame:Hide()
NS.frame = frame

NS.BuildTitle(frame)
local GX = GEM * 0.62
NS.BuildSocket(frame, -GX, 2, GEM)
NS.BuildSocket(frame, GX, 2, GEM)
local gems = { NS.BuildGem(frame, -GX, 2, GEM, "orange"), NS.BuildGem(frame, GX, 2, GEM, "purple") }
NS.normalGems = gems
gems[1]:Hide(); gems[2]:Hide()

local timer = frame:CreateFontString(nil, "OVERLAY", nil, 7)
timer:SetFont("Fonts\\FRIZQT__.TTF", 28, "THICKOUTLINE")
timer:SetPoint("CENTER", frame, "CENTER", 0, 2)
timer:SetTextColor(1, 1, 1)

local bar = CreateFrame("StatusBar", nil, frame)
bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
bar:SetStatusBarColor(1, 0.55, 0.2)
bar:SetPoint("BOTTOMLEFT", 30, 4); bar:SetPoint("BOTTOMRIGHT", -30, 4)
bar:SetHeight(6)
local barBg = bar:CreateTexture(nil, "BACKGROUND"); barBg:SetAllPoints(); barBg:SetColorTexture(0, 0, 0, 0.55)

local drag = frame:CreateTexture(nil, "BACKGROUND")
drag:SetAllPoints(); drag:SetColorTexture(1, 0.8, 0.2, 0.2); drag:Hide()

local state = { stacks = 0, exp = nil, dur = 15, preview = false, unlocked = false }

local function Chime()
    if not (db and db.sound) then return end
    -- if the game-side chime is registered it already plays; don't double up
    if NS.EngineSoundRegistered and NS.EngineSoundRegistered() then return end
    pcall(PlaySoundFile, MEDIA .. "chime.ogg", "Master")
end

local function SetStacks(n)
    n = math.max(0, math.min(2, n or 0))
    for i = 1, 2 do
        if i <= n then
            gems[i]:Show()
            if i > state.stacks then gems[i]:Pop() end
        else
            gems[i]:Hide()
        end
    end
    if n > state.stacks then Chime() end
    state.stacks = n
end

frame:SetScript("OnUpdate", function(self, e)
    if state.exp then
        local remain = math.max(0, state.exp - GetTime())
        timer:SetText(remain >= 10 and string.format("%d", remain) or string.format("%.1f", remain))
        bar:SetMinMaxValues(0, state.dur or 15); bar:SetValue(remain)
        if remain < 3 then timer:SetTextColor(1, 0.4, 0.3) else timer:SetTextColor(1, 1, 1) end
    else
        timer:SetText(""); bar:SetValue(0)
    end
end)

local function FindIoL()
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, IOL_ID)
    if ok and aura then return aura end
    for _, id in ipairs(EXTRA_IDS) do
        ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
        if ok and aura then return aura end
    end
end

local function Update()
    if not db or state.preview or state.unlocked then return end
    if NS.EngineActive and NS.EngineActive() then
        if frame:IsShown() then frame:Hide() end
        state.stacks = 0
        return
    end
    local aura = FindIoL()
    if not aura then
        if frame:IsShown() then frame:Hide() end
        SetStacks(0)
        state.exp = nil
        return
    end
    local apps = Readable(aura.applications)
    local n = (apps and apps > 0) and apps or 1
    state.exp = Readable(aura.expirationTime)
    state.dur = Readable(aura.duration) or 15
    if state.exp and state.exp <= 0 then state.exp = nil end
    if not frame:IsShown() then frame:Show() end
    SetStacks(n)
end
NS.Update = Update

-- ---------------------------------------------------------------------------
-- Position, events, slash
-- ---------------------------------------------------------------------------
local function ApplyPosition()
    frame:ClearAllPoints()
    frame:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)
    frame:SetScale(db.scale)
    if NS.EngineApplyScale then NS.EngineApplyScale() end
end

frame:SetMovable(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    db.point, db.relPoint, db.x, db.y = p, rp, x, y
end)

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterUnitEvent("UNIT_AURA", "player")
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        SunwellInfusionDB = SunwellInfusionDB or {}
        db = SunwellInfusionDB
        for k, v in pairs(defaults) do if db[k] == nil then db[k] = v end end
        ApplyPosition()
        local v = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON, "Version")
        Print("v" .. tostring(v) .. " loaded - 2nd charge is |cffc070ffPURPLE|r. /si test to preview.")
    else
        pcall(Update)
    end
end)
C_Timer.NewTicker(0.2, function() pcall(Update) end)

SLASH_SUNWELLINFUSION1 = "/si"
SLASH_SUNWELLINFUSION2 = "/sunwell"
SlashCmdList.SUNWELLINFUSION = function(msg)
    local cmd, rest = strsplit(" ", (msg or ""):lower(), 2)
    if cmd == "test" then
        state.preview = true
        frame:Show(); state.stacks = 0
        state.dur, state.exp = 15, GetTime() + 15
        SetStacks(1)
        C_Timer.After(0.6, function() SetStacks(2) end)
        C_Timer.After(5, function() SetStacks(1) end)
        C_Timer.After(9, function() state.preview = false; SetStacks(0); Update() end)
    elseif cmd == "unlock" then
        state.unlocked = true
        frame:Show(); frame:EnableMouse(true); drag:Show()
        state.exp = nil; SetStacks(2)
        Print("Drag it where you want, then /si lock")
    elseif cmd == "lock" then
        state.unlocked = false
        frame:EnableMouse(false); drag:Hide()
        SetStacks(0); frame:Hide(); Update()
        Print("Locked.")
    elseif cmd == "scale" then
        local s = tonumber(rest)
        if s and s >= 0.3 and s <= 3 then db.scale = s; ApplyPosition(); Print("Scale " .. s)
        else Print("Usage: /si scale 0.3-3") end
    elseif cmd == "sound" then
        db.sound = not db.sound; Print("Chime " .. (db.sound and "ON" or "OFF"))
        if NS.EngineSound then NS.EngineSound() end
    elseif cmd == "engine" then
        if rest == "auto" or rest == "on" or rest == "off" then db.engine = rest end
        Print("Engine display: " .. tostring(db.engine) .. " (auto = only where buffs are hidden). Preview: /si engine on, then open Edit Mode.")
        if NS.EngineStatus then Print(NS.EngineStatus()) end
    elseif cmd == "orbtest" then
        if NS.OrbTest then NS.OrbTest() end
        Print("You should see the full PURPLE gem (glow, rays, sparkles) above your character for 4 sec, then it vanishes. That's the dungeon/raid 2nd charge. If it's squashed or missing, fully restart the game.")
    elseif cmd == "reset" then
        for k, v in pairs(defaults) do db[k] = v end
        ApplyPosition(); Print("Reset.")
    else
        Print("version " .. tostring((C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON, "Version")))
        Print("/si test | orbtest | unlock | lock | scale <n> | sound | engine auto|on|off | reset")
    end
end
