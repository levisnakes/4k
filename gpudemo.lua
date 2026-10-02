-- gpudemo.lua  --  DirectGPU feature showcase
-- Cycles through scenes that exercise most of the DirectGPU API:
--   1. 2D primitives      5. Metaballs
--   2. Vector graphics    6. World dashboard
--   3. Text rendering     7. Touch paint
--   4. 3D scene (primitives + generated OBJ torus)
--
-- Setup: computer touching a DirectGPU block, monitor nearby.
-- Controls (computer keyboard):
--   Space / Right = next scene    Left = previous scene
--   Q = quit                      P = pause auto-advance
-- Tapping the monitor also advances (except in the paint scene).
 
local RESOLUTION   = 1     -- resolution multiplier (higher = more pixels, slower)
local SCENE_TIME   = 12    -- seconds per scene before auto-advance
local FRAME_DELAY  = 0.05  -- seconds between frames
 
---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------
local gpu = peripheral.find("directgpu")
if not gpu then
    printError("DirectGPU peripheral not found.")
    return
end
 
-- Remove any displays left over from other scripts (e.g. the terminal
-- example), otherwise they can sit on top of the monitor and hide ours.
do
    local old = gpu.listDisplays and gpu.listDisplays() or {}
    for _, id in ipairs(old) do pcall(gpu.removeDisplay, id) end
    if #old > 0 then print("Removed " .. #old .. " old display(s)") end
end
 
local display = gpu.autoDetectAndCreateDisplayWithResolution(RESOLUTION)
if not display or display == -1 then
    printError("Failed to create display (is a monitor nearby?)")
    return
end
 
local info = gpu.getDisplayInfo(display)
local W, H = info.pixelWidth, info.pixelHeight
local S = math.min(W, H)                       -- scale reference
print(("Display %d: %dx%d px"):format(display, W, H))
 
-- Wrap calls so one unsupported function doesn't kill the whole demo
local failed = {}
local function safe(name, ...)
    local fn = gpu[name]
    if not fn then failed[name] = "missing"; return nil end
    local ok, a, b = pcall(fn, ...)
    if not ok then failed[name] = tostring(a); return nil end
    return a, b
end
 
-- Pick a font: prefer Arial, fall back to whatever exists
local FONT = "Arial"
do
    local fonts = safe("getAvailableFonts")
    if type(fonts) == "table" and #fonts > 0 then
        local found = false
        for _, f in ipairs(fonts) do
            if f == "Arial" then found = true break end
        end
        if not found then FONT = fonts[1] end
    end
end
local FS_BIG   = math.max(14, math.floor(H / 9))
local FS_MED   = math.max(11, math.floor(H / 16))
local FS_SMALL = math.max(9,  math.floor(H / 24))
 
---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local sin, cos, pi, floor = math.sin, math.cos, math.pi, math.floor
 
local function hsv(h, s, v)
    h = (h % 1) * 6
    local i = floor(h)
    local f = h - i
    local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
    local r, g, b
    if i == 0 then r, g, b = v, t, p
    elseif i == 1 then r, g, b = q, v, p
    elseif i == 2 then r, g, b = p, v, t
    elseif i == 3 then r, g, b = p, q, v
    elseif i == 4 then r, g, b = t, p, v
    else r, g, b = v, p, q end
    return floor(r * 255), floor(g * 255), floor(b * 255)
end
 
local function gradient(r1, g1, b1, r2, g2, b2, bands)
    bands = bands or 24
    local bh = math.ceil(H / bands)
    for i = 0, bands - 1 do
        local t = i / (bands - 1)
        safe("fillRect", display, 0, i * bh, W, bh,
            floor(r1 + (r2 - r1) * t),
            floor(g1 + (g2 - g1) * t),
            floor(b1 + (b2 - b1) * t))
    end
end
 
local function textCentered(text, y, r, g, b, size, style)
    local m = safe("measureText", text, FONT, size, style or "bold")
    local tw = (type(m) == "table" and m.width) or (#text * size * 0.55)
    safe("drawText", display, text, floor((W - tw) / 2), y, r, g, b, FONT, size, style or "bold")
end
 
local function header(title, sceneIdx, total)
    safe("fillRect", display, 0, 0, W, FS_MED + 8, 0, 0, 0)
    safe("drawText", display, title, 6, 3, 255, 255, 255, FONT, FS_MED, "bold")
    local tag = ("%d/%d"):format(sceneIdx, total)
    safe("drawText", display, tag, W - FS_MED * 2 - 6, 3, 160, 160, 160, FONT, FS_MED, "plain")
end
 
---------------------------------------------------------------------------
-- Scene 1: 2D primitives
---------------------------------------------------------------------------
local balls = {}
for i = 1, 8 do
    balls[i] = {
        x = math.random(20, W - 20), y = math.random(40, H - 20),
        vx = (math.random() - 0.5) * S * 0.04, vy = (math.random() - 0.5) * S * 0.04,
        r = math.random(floor(S * 0.03), floor(S * 0.07)), hue = i / 8,
    }
end
 
local function scene2D(t)
    gradient(10, 10, 40, 40, 10, 60)
 
    -- radar sweep of lines
    local cx, cy, rad = W * 0.25, H * 0.55, S * 0.3
    safe("drawCircle", display, floor(cx), floor(cy), floor(rad), 0, 120, 60, false)
    safe("drawCircle", display, floor(cx), floor(cy), floor(rad * 0.66), 0, 90, 45, false)
    safe("drawCircle", display, floor(cx), floor(cy), floor(rad * 0.33), 0, 60, 30, false)
    for k = 0, 10 do
        local a = t * 2 - k * 0.06
        local c = 255 - k * 22
        safe("drawLine", display, floor(cx), floor(cy),
            floor(cx + cos(a) * rad), floor(cy + sin(a) * rad), 0, c, floor(c / 2))
    end
 
    -- pulsing ellipses
    local ex, ey = W * 0.75, H * 0.35
    for k = 1, 4 do
        local rx = S * 0.05 * k * (1 + 0.2 * sin(t * 3 + k))
        local r, g, b = hsv(t * 0.2 + k * 0.15, 0.8, 1)
        safe("drawEllipse", display, floor(ex), floor(ey), floor(rx * 1.6), floor(rx), r, g, b, false)
    end
 
    -- rotating filled triangle (polygon)
    local px, py, pr = W * 0.75, H * 0.75, S * 0.13
    local pts = {}
    for k = 0, 2 do
        local a = t * 1.5 + k * 2 * pi / 3
        pts[#pts + 1] = { floor(px + cos(a) * pr), floor(py + sin(a) * pr) }
    end
    safe("drawPolygon", display, pts, 255, 180, 40)
 
    -- bouncing filled circles
    for _, bl in ipairs(balls) do
        bl.x, bl.y = bl.x + bl.vx, bl.y + bl.vy
        if bl.x < bl.r or bl.x > W - bl.r then bl.vx = -bl.vx end
        if bl.y < bl.r + FS_MED + 8 or bl.y > H - bl.r then bl.vy = -bl.vy end
        local r, g, b = hsv(bl.hue + t * 0.05, 0.7, 1)
        safe("drawCircle", display, floor(bl.x), floor(bl.y), bl.r, r, g, b, true)
    end
end
 
---------------------------------------------------------------------------
-- Scene 2: Vector graphics
---------------------------------------------------------------------------
local BOLT = "M 6 0 L 0 10 L 5 10 L 3 18 L 10 7 L 5 7 L 8 0 Z"
 
local function sceneVector(t)
    gradient(5, 20, 30, 5, 50, 60)
 
    -- spinning stars with varying point counts
    for k = 1, 5 do
        local cx = W * (k / 6)
        local cy = H * 0.35 + sin(t * 2 + k) * S * 0.05
        local outer = S * 0.07
        local r, g, b = hsv(k / 5 + t * 0.1, 0.6, 1)
        safe("drawStar", display, floor(cx), floor(cy), 3 + k,
            floor(outer), floor(outer * (0.4 + 0.15 * sin(t * 3 + k))), r, g, b, true)
    end
 
    -- animated bezier curves
    for k = 0, 4 do
        local y0 = H * 0.6 + k * S * 0.04
        local pts = {
            { 0, floor(y0) },
            { floor(W * 0.33), floor(y0 + sin(t * 2 + k) * S * 0.2) },
            { floor(W * 0.66), floor(y0 + cos(t * 1.7 + k) * S * 0.2) },
            { W, floor(y0) },
        }
        local r, g, b = hsv(0.5 + k * 0.05, 0.8, 1)
        safe("drawBezierCurve", display, pts, r, g, b, 40)
    end
 
    -- rounded-rect "buttons"
    local bw, bh = floor(W * 0.22), floor(S * 0.1)
    for k = 0, 2 do
        local x = floor(W * 0.06 + k * (bw + W * 0.08))
        local y = H - bh - 8
        local lit = (floor(t * 2) % 3) == k
        safe("drawRoundedRect", display, x, y, bw, bh, floor(bh / 3),
            lit and 60 or 30, lit and 200 or 80, lit and 255 or 120, true)
        safe("drawRoundedRect", display, x, y, bw, bh, floor(bh / 3), 255, 255, 255, false)
    end
 
    -- SVG path (lightning bolt), scaled
    local sc = math.max(1, floor(S * 0.012))
    safe("drawSVGPath", display, BOLT, floor(W * 0.88), floor(H * 0.55), sc, 255, 230, 60)
end
 
---------------------------------------------------------------------------
-- Scene 3: Text rendering
---------------------------------------------------------------------------
local LOREM = "DirectGPU renders text with your system fonts at any size, "
    .. "measures it for layout, draws it over background boxes, and wraps "
    .. "long paragraphs to a maximum width like this one."
 
local function sceneText(t)
    gradient(25, 25, 25, 50, 40, 30)
    local r, g, b = hsv(t * 0.1, 0.6, 1)
    textCentered("DirectGPU", floor(H * 0.12), r, g, b, FS_BIG, "bold")
    textCentered("24-bit color for ComputerCraft", floor(H * 0.12 + FS_BIG + 4),
        200, 200, 200, FS_SMALL, "italic")
 
    safe("drawTextWithBg", display, " Font: " .. FONT .. " ", 8, floor(H * 0.38),
        255, 255, 255, 60, 60, 140, 4, FONT, FS_SMALL, "plain")
 
    local ticker = ("Uptime %.1fs   Clock %.2f"):format(os.clock(), os.time())
    safe("drawTextWithBg", display, ticker, 8, floor(H * 0.38 + FS_SMALL + 14),
        0, 0, 0, 255, 200, 60, 4, FONT, FS_SMALL, "bold")
 
    safe("drawTextWrapped", display, LOREM, 8, floor(H * 0.62), W - 16,
        230, 230, 230, 2, FONT, FS_SMALL, "plain")
end
 
---------------------------------------------------------------------------
-- Scene 4: 3D (primitives + generated OBJ torus, lit and shaded)
---------------------------------------------------------------------------
local function makeTorusOBJ(R, r, seg, side)
    local out = {}
    for i = 0, seg - 1 do
        local u = i / seg * 2 * pi
        for j = 0, side - 1 do
            local v = j / side * 2 * pi
            out[#out + 1] = ("v %.4f %.4f %.4f"):format(
                (R + r * cos(v)) * cos(u), r * sin(v), (R + r * cos(v)) * sin(u))
        end
    end
    for i = 0, seg - 1 do
        for j = 0, side - 1 do
            local a = i * side + j + 1
            local b = ((i + 1) % seg) * side + j + 1
            local c = ((i + 1) % seg) * side + (j + 1) % side + 1
            local d = i * side + (j + 1) % side + 1
            out[#out + 1] = ("f %d %d %d"):format(a, b, c)
            out[#out + 1] = ("f %d %d %d"):format(a, c, d)
        end
    end
    return table.concat(out, "\n")
end
 
local torusId = safe("load3DModel", makeTorusOBJ(1.0, 0.35, 24, 12))
 
local function setup3D()
    safe("setupCamera", display, 60, 0.1, 1000)
    safe("setCameraPosition", display, 0, 2.5, 8)
    safe("lookAt", display, 0, 0, 0)
    safe("clearLights", display)
    safe("addAmbientLight", display, 60, 60, 80, 0.35)
    safe("addDirectionalLight", display, -0.5, -1, -0.6, 255, 245, 230, 0.85)
    safe("setPhongShading", display, true)
    safe("setBackfaceCulling", display, true)
end
 
local function scene3D(t)
    gradient(5, 5, 15, 20, 20, 45)
    safe("clearZBuffer", display)
    local deg = t * 60
 
    -- slowly orbit the camera
    safe("setCameraPosition", display, sin(t * 0.3) * 8, 2.5, cos(t * 0.3) * 8)
    safe("lookAt", display, 0, 0, 0)
 
    if torusId then
        safe("draw3DModel", display, torusId, 0, 0, 0, deg * 0.7, deg, 0, 1.2, 120, 200, 255)
    end
    for k = 0, 2 do
        local a = t + k * 2 * pi / 3
        local x, z = cos(a) * 3.2, sin(a) * 3.2
        if k == 0 then
            safe("drawCube", display, x, 0, z, 1.1, deg, deg * 0.5, 0, 255, 110, 110)
        elseif k == 1 then
            safe("drawSphere", display, x, sin(t * 2) * 0.5, z, 0.7, 16, 110, 255, 140, nil)
        else
            safe("drawPyramid", display, x, 0, z, 1.2, 0, deg * 1.5, 0, 255, 220, 80)
        end
    end
end
 
---------------------------------------------------------------------------
-- Scene 5: Metaballs
---------------------------------------------------------------------------
local metaSys
 
local function setupMeta()
    if not metaSys then metaSys = safe("createMetaballSystem", display) end
end
 
local function sceneMeta(t)
    safe("clear", display, 0, 0, 0)
    if not metaSys then
        textCentered("Metaballs unavailable", floor(H / 2), 255, 80, 80, FS_MED)
        return
    end
    safe("clearMetaballs", metaSys)
    for k = 0, 5 do
        local a = t * (0.6 + k * 0.15) + k
        local x = W / 2 + cos(a) * W * 0.3 * sin(t * 0.4 + k)
        local y = H / 2 + sin(a * 1.3) * H * 0.3
        local id = safe("addMetaball", metaSys, floor(x), floor(y), floor(S * 0.12), 1.0)
        if id then
            local r, g, b = hsv(k / 6 + t * 0.05, 0.8, 1)
            safe("setMetaballColor", metaSys, id, r, g, b)
        end
    end
    safe("renderMetaballs", metaSys, 1.0, 0)
end
 
---------------------------------------------------------------------------
-- Scene 6: World dashboard
---------------------------------------------------------------------------
local function fmt(v)
    if type(v) == "number" then
        return (v % 1 == 0) and tostring(v) or ("%.2f"):format(v)
    end
    return tostring(v)
end
 
local function flatList(tbl, max)
    local out = {}
    if type(tbl) ~= "table" then return out end
    local keys = {}
    for k, v in pairs(tbl) do
        if type(v) ~= "table" then keys[#keys + 1] = k end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for i = 1, math.min(#keys, max) do
        out[#out + 1] = tostring(keys[i]) .. ": " .. fmt(tbl[keys[i]])
    end
    return out
end
 
local function sceneWorld(t)
    local ti = safe("getTimeInfo")
    local tod
    if type(ti) == "table" then
        tod = ti.timeOfDay or ti.dayTime or ti.time
        if type(tod) == "number" and tod > 1 then tod = (tod % 24000) / 24000 end
    end
    tod = tod or ((os.time() / 24) % 1)
 
    -- sky color from time of day (0 = 6am in MC ticks)
    local day = math.max(0, cos((tod - 0.25) * 2 * pi))
    gradient(floor(20 + 80 * day), floor(20 + 140 * day), floor(50 + 190 * day),
             floor(10 + 160 * day), floor(10 + 190 * day), floor(30 + 200 * day))
 
    -- sun / moon arc
    local a = tod * 2 * pi - pi / 2
    local sx, sy = W / 2 + cos(a + pi) * W * 0.4, H * 0.9 + sin(a + pi) * H * 0.7
    safe("drawCircle", display, floor(sx), floor(sy), floor(S * 0.06), 255, 230, 120, true)
    local mx, my = W / 2 + cos(a) * W * 0.4, H * 0.9 + sin(a) * H * 0.7
    safe("drawCircle", display, floor(mx), floor(my), floor(S * 0.05), 220, 220, 240, true)
 
    -- info panel
    local lines = {}
    lines[#lines + 1] = "Dimension: " .. fmt(safe("getDimension"))
    lines[#lines + 1] = "Biome here: " .. fmt(safe("getBiomeAt", info.x or 0, info.y or 64, info.z or 0))
    for _, l in ipairs(flatList(safe("getWeather"), 3)) do lines[#lines + 1] = "Weather " .. l end
    for _, l in ipairs(flatList(safe("getMoonInfo"), 2)) do lines[#lines + 1] = "Moon " .. l end
    for _, l in ipairs(flatList(ti, 3)) do lines[#lines + 1] = "Time " .. l end
 
    local lh = FS_SMALL + 4
    local ph = #lines * lh + 10
    safe("drawRoundedRect", display, 6, FS_MED + 14, floor(W * 0.62), ph, 6, 0, 0, 0, true)
    for i, l in ipairs(lines) do
        safe("drawText", display, l, 12, FS_MED + 14 + (i - 1) * lh + 4,
            230, 230, 230, FONT, FS_SMALL, "plain")
    end
end
 
---------------------------------------------------------------------------
-- Scene 7: Touch paint (uses display input events)
---------------------------------------------------------------------------
local strokes, lastPt, paintHue = {}, nil, 0
 
local function scenePaintSetup()
    strokes, lastPt = {}, nil
end
 
local function scenePaint(t, events)
    gradient(240, 240, 235, 220, 220, 210, 8)
    for _, ev in ipairs(events) do
        if ev.type == "mouse_click" or ev.type == "mouse_drag" then
            paintHue = paintHue + 0.01
            local r, g, b = hsv(paintHue, 0.9, 0.9)
            local p = { x = ev.x, y = ev.y, r = r, g = g, b = b }
            if ev.type == "mouse_drag" and lastPt then p.prev = lastPt end
            strokes[#strokes + 1] = p
            lastPt = p
            if #strokes > 400 then table.remove(strokes, 1) end
        elseif ev.type == "mouse_up" then
            lastPt = nil
        end
    end
    local rad = math.max(2, floor(S * 0.015))
    for _, p in ipairs(strokes) do
        if p.prev then
            safe("drawLine", display, p.prev.x, p.prev.y, p.x, p.y, p.r, p.g, p.b)
        end
        safe("drawCircle", display, p.x, p.y, rad, p.r, p.g, p.b, true)
    end
    if #strokes == 0 then
        textCentered("Click or drag on the monitor to paint", floor(H / 2), 80, 80, 80, FS_SMALL, "italic")
    end
end
 
---------------------------------------------------------------------------
-- Scene table & main loop
---------------------------------------------------------------------------
local scenes = {
    { name = "2D Primitives",    draw = scene2D },
    { name = "Vector Graphics",  draw = sceneVector },
    { name = "Text Rendering",   draw = sceneText },
    { name = "3D Scene",         draw = scene3D,    setup = setup3D },
    { name = "Metaballs",        draw = sceneMeta,  setup = setupMeta },
    { name = "World Dashboard",  draw = sceneWorld },
    { name = "Touch Paint",      draw = scenePaint, setup = scenePaintSetup, touchy = true },
}
 
local current, sceneStart, running, paused = 1, os.clock(), true, false
 
local function goto_(n)
    current = ((n - 1) % #scenes) + 1
    sceneStart = os.clock()
    if scenes[current].setup then scenes[current].setup() end
    safe("clearEvents", display)
    term.clear(); term.setCursorPos(1, 1)
    print("DirectGPU demo  [Space/arrows] scene  [P] pause  [Q] quit")
    print(("Scene %d/%d: %s"):format(current, #scenes, scenes[current].name))
end
 
local function renderLoop()
    goto_(1)
    while running do
        local t = os.clock() - sceneStart
 
        -- collect touch events
        local events = {}
        while safe("hasEvents", display) do
            local ev = safe("pollEvent", display)
            if not ev then break end
            events[#events + 1] = ev
        end
 
        local sc = scenes[current]
        if not sc.touchy then
            for _, ev in ipairs(events) do
                if ev.type == "mouse_click" then goto_(current + 1); sc = scenes[current]; break end
            end
        end
 
        sc.draw(os.clock() - sceneStart, events)
        header(sc.name .. (paused and "  (paused)" or ""), current, #scenes)
        safe("updateDisplay", display)
 
        if not paused and t > SCENE_TIME then goto_(current + 1) end
        sleep(FRAME_DELAY)
    end
end
 
local function keyLoop()
    while running do
        local _, key = os.pullEvent("key")
        if key == keys.q then running = false
        elseif key == keys.space or key == keys.right then goto_(current + 1)
        elseif key == keys.left then goto_(current - 1)
        elseif key == keys.p then paused = not paused end
    end
end
 
parallel.waitForAny(renderLoop, keyLoop)
 
-- Cleanup
if torusId then safe("unload3DModel", torusId) end
if metaSys then safe("removeMetaballSystem", metaSys) end
safe("clear", display, 0, 0, 0)
safe("updateDisplay", display)
safe("removeDisplay", display)
 
term.clear(); term.setCursorPos(1, 1)
print("DirectGPU demo finished.")
local any = false
for name, err in pairs(failed) do
    if not any then print("Calls that failed on this version:") any = true end
    print(" - " .. name .. ": " .. err)
end
