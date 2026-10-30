-- Graph editor for keyframe curves (see shared/curves.lua).
-- Edits the curve that leads from the selected keyframe to the next one.

local PANEL = {}

local GRAPH_W, GRAPH_H = 280, 200
local MARGIN = 16
local Y_MIN, Y_MAX = -0.75, 1.75
local SAMPLES = 64
local GRAB_RADIUS = 14
local HANDLE_RADIUS = 6

local COL_BG = Color(32, 32, 32)
local COL_GRID = Color(55, 55, 55)
local COL_GRID_MAIN = Color(95, 95, 95)
local COL_CURVE = Color(90, 200, 255)
local COL_CURVE_DIM = Color(110, 110, 110)
local COL_HANDLE_1 = Color(255, 210, 60)
local COL_HANDLE_2 = Color(90, 230, 120)
local COL_TEXT = Color(190, 190, 190)

local LEGACY_LABEL = "Legacy (Ease in / out)"
local CUSTOM_LABEL = "Custom bezier"

local function DefaultBezier()
    return { 0.25, 0.1, 0.25, 1 }
end

function PANEL:Init()

    self:SetTitle("SMH Curve")
    self:SetDeleteOnClose(false)
    self:SetSize(300, 316)

    self.Curve = ""
    self.Bezier = DefaultBezier()
    self._active = false
    self._loading = false
    self._drag = nil

    self.Info = vgui.Create("DLabel", self)
    self.Info:SetText("From the selected keyframe to the next one")
    self.Info:SizeToContents()

    self.Preset = vgui.Create("DComboBox", self)
    self.Preset:SetSortItems(false)
    self.Preset:AddChoice(LEGACY_LABEL, "")
    self.Preset:AddChoice(CUSTOM_LABEL, "custom")
    for _, preset in ipairs(SMH.Curves.Presets) do
        self.Preset:AddChoice(preset[1], preset[2])
    end
    self.Preset.OnSelect = function(_, _, _, data)
        if self._loading then return end
        self:SelectPreset(data)
    end

    self.Graph = vgui.Create("DPanel", self)
    self.Graph.Paint = function(graph, w, h) self:PaintGraph(w, h) end
    self.Graph.OnMousePressed = function(graph, mouseCode) self:GraphPressed(mouseCode) end
    self.Graph.OnCursorMoved = function(graph, x, y) self:GraphMoved(x, y) end
    self.Graph.OnMouseReleased = function(graph, mouseCode) self:GraphReleased(mouseCode) end

    self.Entry = vgui.Create("DTextEntry", self)
    self.Entry:SetUpdateOnType(false)
    self.Entry.OnEnter = function() self:ApplyEntryText() end

    self:SetActive(false)
    self:SetCurveInternal("")

end

function PANEL:PerformLayout(width, height)

    self.BaseClass.PerformLayout(self, width, height)

    self.Info:SetPos(10, 28)
    self.Preset:SetPos(10, 46)
    self.Preset:SetSize(width - 20, 22)
    self.Graph:SetPos(10, 74)
    self.Graph:SetSize(GRAPH_W, GRAPH_H)
    self.Entry:SetPos(10, 74 + GRAPH_H + 8)
    self.Entry:SetSize(width - 20, 22)

end

-- graph space (x 0-1, y Y_MIN..Y_MAX) <-> panel pixels
local function ToPixels(x, y)
    local px = MARGIN + x * (GRAPH_W - MARGIN * 2)
    local py = MARGIN + (1 - (y - Y_MIN) / (Y_MAX - Y_MIN)) * (GRAPH_H - MARGIN * 2)
    return px, py
end

local function FromPixels(px, py)
    local x = (px - MARGIN) / (GRAPH_W - MARGIN * 2)
    local y = Y_MIN + (1 - (py - MARGIN) / (GRAPH_H - MARGIN * 2)) * (Y_MAX - Y_MIN)
    return x, y
end

function PANEL:IsBezier()
    local parsed = SMH.Curves.Parse(self.Curve)
    return parsed ~= nil and parsed.Type == "bezier"
end

function PANEL:HandlePixels(index)
    if index == 1 then
        return ToPixels(self.Bezier[1], self.Bezier[2])
    end
    return ToPixels(self.Bezier[3], self.Bezier[4])
end

function PANEL:PaintGraph(w, h)

    surface.SetDrawColor(COL_BG)
    surface.DrawRect(0, 0, w, h)

    for i = 0, 4 do
        local gx = ToPixels(i / 4, 0)
        surface.SetDrawColor((i == 0 or i == 4) and COL_GRID_MAIN or COL_GRID)
        surface.DrawLine(gx, 0, gx, h)
    end
    for _, gy in ipairs({ -0.5, 0, 0.5, 1, 1.5 }) do
        local _, py = ToPixels(0, gy)
        surface.SetDrawColor((gy == 0 or gy == 1) and COL_GRID_MAIN or COL_GRID)
        surface.DrawLine(0, py, w, py)
    end

    local legacy = SMH.Curves.Parse(self.Curve) == nil
    surface.SetDrawColor(legacy and COL_CURVE_DIM or COL_CURVE)
    local lastX, lastY
    for i = 0, SAMPLES do
        local t = i / SAMPLES
        local value = SMH.Curves.Eval(self.Curve, t) or t
        local px, py = ToPixels(t, value)
        if lastX then surface.DrawLine(lastX, lastY, px, py) end
        lastX, lastY = px, py
    end

    if self:IsBezier() then
        local x0, y0 = ToPixels(0, 0)
        local x1, y1 = ToPixels(1, 1)
        local h1x, h1y = self:HandlePixels(1)
        local h2x, h2y = self:HandlePixels(2)

        surface.SetDrawColor(COL_HANDLE_1)
        surface.DrawLine(x0, y0, h1x, h1y)
        surface.SetDrawColor(COL_HANDLE_2)
        surface.DrawLine(x1, y1, h2x, h2y)

        draw.RoundedBox(HANDLE_RADIUS, h1x - HANDLE_RADIUS, h1y - HANDLE_RADIUS, HANDLE_RADIUS * 2, HANDLE_RADIUS * 2, COL_HANDLE_1)
        draw.RoundedBox(HANDLE_RADIUS, h2x - HANDLE_RADIUS, h2y - HANDLE_RADIUS, HANDLE_RADIUS * 2, HANDLE_RADIUS * 2, COL_HANDLE_2)
    elseif legacy then
        draw.SimpleText("Using the Ease in / out numbers.", "DermaDefault", 8, 6, COL_TEXT)
        draw.SimpleText("Pick a preset to use a curve instead.", "DermaDefault", 8, 20, COL_TEXT)
    else
        draw.SimpleText("Pick \"" .. CUSTOM_LABEL .. "\" to edit handles.", "DermaDefault", 8, 6, COL_TEXT)
    end

    if not self._active then
        surface.SetDrawColor(0, 0, 0, 170)
        surface.DrawRect(0, 0, w, h)
        draw.SimpleText("Move to a keyframe to edit its curve", "DermaDefault", w / 2, h / 2, COL_TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

end

function PANEL:GraphPressed(mouseCode)
    if mouseCode ~= MOUSE_LEFT or not self._active or not self:IsBezier() then return end

    local mx, my = self.Graph:CursorPos()
    local best, bestDist = nil, GRAB_RADIUS * GRAB_RADIUS
    for index = 1, 2 do
        local hx, hy = self:HandlePixels(index)
        local dist = (mx - hx) ^ 2 + (my - hy) ^ 2
        if dist < bestDist then
            best, bestDist = index, dist
        end
    end

    if best then
        self._drag = best
        self.Graph:MouseCapture(true)
    end
end

function PANEL:GraphMoved(mx, my)
    if not self._drag then return end

    local x, y = FromPixels(mx, my)
    if input.IsShiftDown() then
        x, y = math.Round(x * 20) / 20, math.Round(y * 20) / 20
    end
    x = math.Clamp(x, 0, 1)
    y = math.Clamp(y, Y_MIN, Y_MAX)

    if self._drag == 1 then
        self.Bezier[1], self.Bezier[2] = x, y
    else
        self.Bezier[3], self.Bezier[4] = x, y
    end

    self.Curve = SMH.Curves.MakeBezier(unpack(self.Bezier))
    self:RefreshControls()
end

function PANEL:GraphReleased(mouseCode)
    if not self._drag then return end

    self._drag = nil
    self.Graph:MouseCapture(false)
    self:Commit()
end

function PANEL:SelectPreset(data)
    if data == "custom" then
        data = SMH.Curves.MakeBezier(unpack(self.Bezier))
    end
    self:SetCurveInternal(data)
    self:Commit()
end

function PANEL:ApplyEntryText()
    local numbers = {}
    for n in string.gmatch(self.Entry:GetValue(), "%-?%d*%.?%d+") do
        numbers[#numbers + 1] = tonumber(n)
    end

    if #numbers >= 4 then
        local curve = SMH.Curves.MakeBezier(
            math.Clamp(numbers[1], 0, 1), math.Clamp(numbers[2], Y_MIN, Y_MAX),
            math.Clamp(numbers[3], 0, 1), math.Clamp(numbers[4], Y_MIN, Y_MAX)
        )
        self:SetCurveInternal(curve)
        self:Commit()
    else
        self:RefreshControls() -- bad input, put the real value back
    end
end

-- Updates the stored curve and every control, without sending anything.
function PANEL:SetCurveInternal(curve)
    self.Curve = curve or ""

    local parsed = SMH.Curves.Parse(self.Curve)
    if parsed and parsed.Type == "bezier" then
        self.Bezier = { parsed[1], parsed[2], parsed[3], parsed[4] }
    end

    self:RefreshControls()
end

function PANEL:RefreshControls()
    local wasLoading = self._loading
    self._loading = true

    local label = (self.Curve == "") and LEGACY_LABEL or nil
    for _, preset in ipairs(SMH.Curves.Presets) do
        if preset[2] == self.Curve then label = preset[1] end
    end
    self.Preset:SetValue(label or CUSTOM_LABEL)

    if self:IsBezier() then
        self.Entry:SetText(string.format("%s, %s, %s, %s",
            tostring(math.Round(self.Bezier[1], 3)), tostring(math.Round(self.Bezier[2], 3)),
            tostring(math.Round(self.Bezier[3], 3)), tostring(math.Round(self.Bezier[4], 3))))
    else
        self.Entry:SetText("")
    end

    self._loading = wasLoading
end

function PANEL:Commit()
    if self._loading or not self._active then return end
    self:OnCurveChanged(self.Curve)
end

-- Called when the selected keyframe changes (or its data arrives from the server).
function PANEL:SetCurve(curve)
    if self._drag then return end -- don't yank the handle out of the user's hand

    self._loading = true
    self:SetActive(true)
    self:SetCurveInternal(curve)
    self._loading = false
end

function PANEL:SetActive(active)
    self._active = active and true or false
    self.Preset:SetEnabled(self._active)
    self.Entry:SetEnabled(self._active)
end

function PANEL:OnCurveChanged(curve) end

vgui.Register("SMHCurveEditor", PANEL, "DFrame")
