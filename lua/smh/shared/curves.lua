-- Keyframe curves (graph / bezier easing).
--
-- A curve is stored per keyframe, per modifier, as a short string. It describes
-- how values travel from THAT keyframe to the NEXT one (like Blender / After Effects):
--   nil or ""             legacy: use the old EaseIn / EaseOut numbers
--   "const"               hold this keyframe's value until the next keyframe
--   "bounce", "elastic"   out-bounce / out-elastic (can't be drawn as a single bezier)
--   "bezier:x1,y1,x2,y2"  CSS-style cubic bezier. x1/x2 are 0-1, y1/y2 may overshoot

SMH.Curves = SMH.Curves or {}
local MGR = SMH.Curves

MGR.MaxLength = 64
MGR.DefaultBezier = "bezier:0.25,0.1,0.25,1"

-- { label, curve }. Bezier values are the common easings.net / CSS set.
MGR.Presets = {
    { "Linear",           "bezier:0,0,1,1" },
    { "Hold (no tween)",  "const" },
    { "Ease (CSS)",       "bezier:0.25,0.1,0.25,1" },

    { "In Sine",          "bezier:0.47,0,0.745,0.715" },
    { "Out Sine",         "bezier:0.39,0.575,0.565,1" },
    { "In Out Sine",      "bezier:0.445,0.05,0.55,0.95" },

    { "In Quad",          "bezier:0.55,0.085,0.68,0.53" },
    { "Out Quad",         "bezier:0.25,0.46,0.45,0.94" },
    { "In Out Quad",      "bezier:0.455,0.03,0.515,0.955" },

    { "In Cubic",         "bezier:0.55,0.055,0.675,0.19" },
    { "Out Cubic",        "bezier:0.215,0.61,0.355,1" },
    { "In Out Cubic",     "bezier:0.645,0.045,0.355,1" },

    { "In Quart",         "bezier:0.895,0.03,0.685,0.22" },
    { "Out Quart",        "bezier:0.165,0.84,0.44,1" },
    { "In Out Quart",     "bezier:0.77,0,0.175,1" },

    { "In Quint",         "bezier:0.755,0.05,0.855,0.06" },
    { "Out Quint",        "bezier:0.23,1,0.32,1" },
    { "In Out Quint",     "bezier:0.86,0,0.07,1" },

    { "In Expo",          "bezier:0.95,0.05,0.795,0.035" },
    { "Out Expo",         "bezier:0.19,1,0.22,1" },
    { "In Out Expo",      "bezier:1,0,0,1" },

    { "In Circ",          "bezier:0.6,0.04,0.98,0.335" },
    { "Out Circ",         "bezier:0.075,0.82,0.165,1" },
    { "In Out Circ",      "bezier:0.785,0.135,0.15,0.86" },

    { "In Back",          "bezier:0.6,-0.28,0.735,0.045" },
    { "Out Back",         "bezier:0.175,0.885,0.32,1.275" },
    { "In Out Back",      "bezier:0.68,-0.55,0.265,1.55" },

    { "Out Bounce",       "bounce" },
    { "Out Elastic",      "elastic" },
}

local function OutBounce(t)
    local n1, d1 = 7.5625, 2.75
    if t < 1 / d1 then
        return n1 * t * t
    elseif t < 2 / d1 then
        t = t - 1.5 / d1
        return n1 * t * t + 0.75
    elseif t < 2.5 / d1 then
        t = t - 2.25 / d1
        return n1 * t * t + 0.9375
    end
    t = t - 2.625 / d1
    return n1 * t * t + 0.984375
end

local function OutElastic(t)
    if t <= 0 then return 0 end
    if t >= 1 then return 1 end
    return 2 ^ (-10 * t) * math.sin((t * 10 - 0.75) * (2 * math.pi) / 3) + 1
end

-- Solves x(s) = t for the bezier parameter s, then returns y(s).
local function EvalBezier(x1, y1, x2, y2, t)
    if t <= 0 then return 0 end
    if t >= 1 then return 1 end

    local s = t
    for _ = 1, 6 do -- newton
        local u = 1 - s
        local err = 3 * u * u * s * x1 + 3 * u * s * s * x2 + s * s * s - t
        if math.abs(err) < 1e-6 then break end
        local d = 3 * u * u * x1 + 6 * u * s * (x2 - x1) + 3 * s * s * (1 - x2)
        if math.abs(d) < 1e-6 then break end
        s = s - err / d
    end

    local u = 1 - s
    if s < 0 or s > 1 or math.abs(3 * u * u * s * x1 + 3 * u * s * s * x2 + s * s * s - t) > 1e-4 then
        local lo, hi = 0, 1 -- bisection fallback (x is monotonic because x1, x2 are in 0-1)
        for _ = 1, 30 do
            s = (lo + hi) / 2
            u = 1 - s
            local x = 3 * u * u * s * x1 + 3 * u * s * s * x2 + s * s * s
            if x < t then lo = s else hi = s end
        end
        u = 1 - s
    end

    return 3 * u * u * s * y1 + 3 * u * s * s * y2 + s * s * s
end

local cache = {}

-- Returns a parsed curve table, or nil if the string is empty / invalid (= legacy).
function MGR.Parse(str)
    if type(str) ~= "string" or str == "" or #str > MGR.MaxLength then return nil end

    local cached = cache[str]
    if cached ~= nil then return cached or nil end

    local parsed = false
    if str == "const" or str == "bounce" or str == "elastic" then
        parsed = { Type = str }
    else
        local a, b, c, d = string.match(str, "^bezier:([%-%d%.]+),([%-%d%.]+),([%-%d%.]+),([%-%d%.]+)$")
        a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
        if a and b and c and d then
            parsed = {
                Type = "bezier",
                math.Clamp(a, 0, 1), b, math.Clamp(c, 0, 1), d,
            }
        end
    end

    cache[str] = parsed
    return parsed or nil
end

function MGR.IsValid(str)
    return str == "" or MGR.Parse(str) ~= nil
end

-- Builds a bezier curve string from 4 numbers (rounded so strings stay short).
function MGR.MakeBezier(x1, y1, x2, y2)
    local function f(v) return tostring(math.Round(v, 3)) end
    return "bezier:" .. f(x1) .. "," .. f(y1) .. "," .. f(x2) .. "," .. f(y2)
end

-- Eases t (0-1). Returns nil for legacy / invalid curves so callers can fall back.
function MGR.Eval(str, t)
    local curve = MGR.Parse(str)
    if not curve then return nil end

    t = math.Clamp(t, 0, 1)
    if curve.Type == "bezier" then
        return EvalBezier(curve[1], curve[2], curve[3], curve[4], t)
    elseif curve.Type == "const" then
        return t >= 1 and 1 or 0
    elseif curve.Type == "bounce" then
        return OutBounce(t)
    elseif curve.Type == "elastic" then
        return OutElastic(t)
    end
end

-- Single place that turns "how far between two keyframes" into the lerp multiplier.
-- A curve on the previous keyframe wins; otherwise the old ease in/out numbers apply.
function SMH.ApplyEasing(prevKeyframe, nextKeyframe, modname, t)
    local curve = prevKeyframe.Curve and prevKeyframe.Curve[modname]
    if curve then
        local eased = MGR.Eval(curve, t)
        if eased ~= nil then return eased end
    end
    return math.EaseInOut(t, prevKeyframe.EaseOut[modname], nextKeyframe.EaseIn[modname])
end
