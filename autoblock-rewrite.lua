local Players = game:GetService('Players')
local Player = Players.LocalPlayer

local CONFIG = {
    DetectionRange = 50,
    PredictionWindow = 0.15,
    ParryPreemption = 1.0,
    ParryCooldown = 1.0,
    MaxSwingDuration = .3,
    SwingBlacklistMaxAge = 15,
    SwingBlacklistSweepInterval = 10,
    FacingThreshold = 0.56
}

local SWING_BLACKLIST = {}

local sin, cos = math.sin, math.cos
local abs, sqrt = math.abs, math.sqrt
local v3new = Vector3.new

local rotationCache = {}
local function getCachedRotation(rot, timestamp)
    local key = string.format("%.3f_%.3f_%.3f", rot.Yaw, rot.Pitch, rot.Roll)
    local cached = rotationCache[key]
    if cached and (timestamp - cached.time) < 0.1 then
        return cached.matrices
    end

    local cy, sy = cos(rot.Yaw), sin(rot.Yaw)
    local cp, sp = cos(rot.Pitch), sin(rot.Pitch)
    local cr, sr = cos(rot.Roll), sin(rot.Roll)

    local matrices = {

        m00 = cy * cr + sy * sp * sr,
        m01 = sr * cp,
        m02 = -sy * cr + cy * sp * sr,
        m10 = -cy * sr + sy * sp * cr,
        m11 = cr * cp,
        m12 = sr * sy + cy * sp * cr,
        m20 = sy * cp,
        m21 = -sp,
        m22 = cy * cp,

        i00 = cy * cr + sy * sp * sr,
        i01 = -cy * sr + sy * sp * cr,
        i02 = sy * cp,
        i10 = sr * cp,
        i11 = cr * cp,
        i12 = -sp,
        i20 = -sy * cr + cy * sp * sr,
        i21 = sr * sy + cy * sp * cr,
        i22 = cy * cp
    }

    rotationCache[key] = {
        matrices = matrices,
        time = timestamp
    }
    return matrices
end

local function rotate_vec_inline(x, y, z, m)
    return x * m.m00 + y * m.m01 + z * m.m02, x * m.m10 + y * m.m11 + z * m.m12, x * m.m20 + y * m.m21 + z * m.m22
end

local function inverse_rotate_inline(x, y, z, m)
    return x * m.i00 + y * m.i10 + z * m.i20, x * m.i01 + y * m.i11 + z * m.i21, x * m.i02 + y * m.i12 + z * m.i22
end

local function point_in_box_fast(px, py, pz, ox, oy, oz, m, hx, hy, hz)

    local rx, ry, rz = px - ox, py - oy, pz - oz
    local lx, ly, lz = inverse_rotate_inline(rx, ry, rz, m)

    return abs(lx) <= hx and abs(ly) <= hy and abs(lz) <= hz
end

local DEBUG = {
    Enabled = false,
    BoxColor = Color3.fromRGB(255, 0, 0),
    PlayerColor = Color3.fromRGB(0, 255, 0),
    Duration = 0.25,
    MaxDrawings = 50,
    CleanupInterval = 0.5
}

local DrawObjects = {}
local ActiveDrawings = 0
local LastCleanup = 0

local function remove_drawing(obj)
    if obj then
        pcall(function()
            obj.Visible = false
            if obj.Remove then
                obj:Remove()
            end
        end)
    end
end

local function debug_clear()
    if #DrawObjects == 0 then
        return
    end

    for i = #DrawObjects, 1, -1 do
        if DrawObjects[i] then
            remove_drawing(DrawObjects[i])
            DrawObjects[i] = nil
        end
    end
    ActiveDrawings = 0
    table.clear(DrawObjects)
end

local function compute_box_corners_fast(cx, cy, cz, m, hx, hy, hz)
    local corners = {}
    local signs = {{1, 1, 1}, {1, 1, -1}, {1, -1, 1}, {1, -1, -1}, {-1, 1, 1}, {-1, 1, -1}, {-1, -1, 1}, {-1, -1, -1}}

    for i = 1, 8 do
        local sx, sy, sz = signs[i][1], signs[i][2], signs[i][3]
        local lx, ly, lz = hx * sx, hy * sy, hz * sz
        local rx, ry, rz = rotate_vec_inline(lx, ly, lz, m)
        corners[i] = v3new(cx + rx, cy + ry, cz + rz)
    end
    return corners
end

local function debug_box(center, size, color, rot)
    if not DEBUG.Enabled then
        return
    end
    if ActiveDrawings >= DEBUG.MaxDrawings then
        debug_clear()
        return
    end

    local ok, err = pcall(function()
        local m = getCachedRotation(rot, os.clock())
        local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
        local corners = compute_box_corners_fast(center.X, center.Y, center.Z, m, hx, hy, hz)
        local edges = {{1, 2}, {1, 3}, {1, 5}, {2, 4}, {2, 6}, {3, 4}, {3, 7}, {4, 8}, {5, 6}, {5, 7}, {6, 8}, {7, 8}}

        for _, edge in ipairs(edges) do
            if ActiveDrawings >= DEBUG.MaxDrawings then
                return
            end

            local p1, p2 = corners[edge[1]], corners[edge[2]]
            local s1, on1 = WorldToScreen(p1)
            local s2, on2 = WorldToScreen(p2)

            if s1 and s2 and on1 and on2 then
                local line = Drawing.new("Line")
                if line then
                    line.From = Vector2.new(s1.X, s1.Y)
                    line.To = Vector2.new(s2.X, s2.Y)
                    line.Color = color or DEBUG.BoxColor
                    line.Thickness = 1
                    line.Transparency = 0.8
                    line.Visible = true
                    line.CreatedAt = os.clock()
                    table.insert(DrawObjects, line)
                    ActiveDrawings = ActiveDrawings + 1
                end
            end
        end
    end)

    if not ok then
        warn("[Debug] Box drawing error:", err)
    end
end

local function debug_point(point, color)
    if not DEBUG.Enabled then
        return
    end
    if ActiveDrawings >= DEBUG.MaxDrawings then
        return
    end

    local ok, err = pcall(function()
        local screenPos, onScreen = WorldToScreen(point)
        if not screenPos or not onScreen then
            return
        end

        local dot = Drawing.new("Circle")
        if dot then
            dot.Radius = 3
            dot.Thickness = 2
            dot.Color = color or DEBUG.PlayerColor
            dot.Filled = true
            dot.Position = Vector2.new(screenPos.X, screenPos.Y)
            dot.CreatedAt = os.clock()
            dot.Visible = true
            table.insert(DrawObjects, dot)
            ActiveDrawings = ActiveDrawings + 1
        end
    end)

    if not ok then
        warn("[Debug] Point drawing error:", err)
    end
end

local KillerSwings = {
    ['JohnDoe'] = {'rbxassetid://140242176732868', 'rbxassetid://81702359653578', 'rbxassetid://86174610237192'},
    ['Slasher'] = {'rbxassetid://112809109188560', 'rbxassetid://102228729296384', 'rbxassetid://12222216',
                   'rbxassetid://108907358619313', 'rbxassetid://127793641088496', 'rbxassetid://116581754553533',
                   'rbxassetid://86833981571073', 'rbxassetid://110372418055226', 'rbxassetid://105840448036441',
                   'rbxassetid://86494585504534'},
    ['1x1x1x1'] = {'rbxassetid://117173212095661', 'rbxassetid://121954639447247', 'rbxassetid://115026634746636',
                   'rbxassetid://109431876587852', 'rbxassetid://119942598489800', 'rbxassetid://85853080745515',
                   'rbxassetid://119089145505438', 'rbxassetid://95079963655241'},
    ['c00lkidd'] = {'rbxassetid://106776364623742', 'rbxassetid://18885909645', 'rbxassetid://80516583309685',
                    'rbxassetid://82221759983649', 'rbxassetid://97167027849946', 'rbxassetid://84307400688050',
                    'rbxassetid://127846074966393', 'rbxassetid://75330693422988'},
    ['Noli'] = {'rbxassetid://109348678063422', 'rbxassetid://131406927389838', 'rbxassetid://106300477136129',
                'rbxassetid://89315669689903', 'rbxassetid://106300477136129', 'rbxassetid://77893377257526',
                'rbxassetid://131406927389838', 'rbxassetid://108610718831698', 'rbxassetid://114742322778642',
                'rbxassetid://112395455254818', 'rbxassetid://136323728355613', 'rbxassetid://89004992452376',
                'rbxassetid://140659146085461'},
    ['Sixer'] = {'rbxassetid://119583605486352', 'rbxassetid://137719096698985', 'rbxassetid://79980897195554',
                 'rbxassetid://128414736976503', 'rbxassetid://117231507259853', 'rbxassetid://101698569375359',
                 'rbxassetid://101553872555606', 'rbxassetid://71805956520207', 'rbxassetid://125213046326879',
                 'rbxassetid://78298577002481'}
}

local KillerConfigs = {
    ['1x1x1x1'] = {
        SlashWindup = 0.4,
        SlashLinger = 0.25,
        SlashSize = Vector3.new(4.5, 6, 7.5),
        SlashOffset = Vector3.new(0, 0, -1.25)
    },
    ['c00lkidd'] = {
        SlashWindup = 0.1,
        SlashLinger = 0.3,
        SlashSize = Vector3.new(4.5, 6, 5),
        SlashOffset = Vector3.new(0, 0, -1.5)
    },
    ['JohnDoe'] = {
        SlashWindup = 0.4,
        SlashLinger = 0.25,
        SlashSize = Vector3.new(4.5, 6, 7.5),
        SlashOffset = Vector3.new(0, 0, -1.25)
    },
    ['Noli'] = {
        SlashWindup = 0.35,
        SlashLinger = 0.25,
        SlashSize = Vector3.new(4.5, 6, 7.5),
        SlashOffset = Vector3.new(0, 0, -1.25)
    },
    ['Sixer'] = {
        SlashWindup = 0.3,
        SlashLinger = 0.25,
        SlashSize = Vector3.new(5, 7, 7.25),
        SlashOffset = Vector3.new(0, -1, -4.25)
    },
    ['Slasher'] = {
        SlashWindup = 0.2,
        SlashLinger = 0.25,
        SlashSize = Vector3.new(4.5, 6, 7.5),
        SlashOffset = Vector3.new(0, 0, -1.25)
    }
}

local function safe_http_get(url)
    local ok, res = pcall(function()
        return game.HttpGet and game:HttpGet(url)
    end)
    if ok and type(res) == "string" then
        return res
    end
    return nil
end

local function get_offsets()
    local t = {}
    local result = safe_http_get("https://offsets.ntgetwritewatch.workers.dev/offsets.json")
    if result then
        for k, v in result:gmatch('"([^"]-)"%s*:%s*"([^"]-)"') do
            t[k] = v
        end
    end
    return t
end

local function readMatrix3(address)
    local out = {}
    for i = 0, 8 do
        local val = memory_read("float", address + (i * 0x04))
        if not val then
            return nil
        end
        out[tostring(i)] = val
    end
    return out
end

local SOUNDID_ADDR = get_offsets()['SoundId']
local PRIMITIVE_ADDR = get_offsets()['Primitive']

local function getPrimitive(instance)
    if not PRIMITIVE_ADDR or not instance or not instance.Address then
        return nil
    end

    local ok, addr = pcall(function()
        return memory_read("uintptr_t", instance.Address + tonumber(PRIMITIVE_ADDR))
    end)
    if ok then
        return addr
    end

    local ok2, addr2 = pcall(function()
        return memory_read("uintptr_t", instance.Address + PRIMITIVE_ADDR)
    end)
    if ok2 then
        return addr2
    end
    return nil
end

local asin, atan2, pi = math.asin, math.atan2, math.pi

local function cframe_to_euler(hrp)
    local primitive = getPrimitive(hrp)
    local rotation = readMatrix3(primitive + 0xF8)

    local m21 = -rotation["5"]
    local pitch, yaw, roll

    if m21 < 0.99999 then
        if m21 > -0.99999 then
            pitch = asin(m21)
            yaw = atan2(-rotation["2"], -rotation["8"])
            roll = atan2(-rotation["3"], -rotation["4"])
        else
            pitch = pi / 2
            yaw = -atan2(rotation["6"], rotation["0"])
            roll = 0
        end
    else
        pitch = -pi / 2
        yaw = atan2(rotation["6"], rotation["0"])
        roll = 0
    end

    return {
        Yaw = yaw,
        Pitch = pitch,
        Roll = roll
    }
end

local VirtualHitbox = {}
VirtualHitbox.__index = VirtualHitbox

function VirtualHitbox.new(origin_pos, origin_rot, offset, size, linger)
    return setmetatable({

        OriginX = origin_pos.X,
        OriginY = origin_pos.Y,
        OriginZ = origin_pos.Z,
        OriginRot = {
            Yaw = origin_rot.Yaw or 0,
            Pitch = origin_rot.Pitch or 0,
            Roll = origin_rot.Roll or 0
        },
        OffsetX = offset.X,
        OffsetY = offset.Y,
        OffsetZ = offset.Z,
        HalfX = size.X / 2,
        HalfY = size.Y / 2,
        HalfZ = size.Z / 2,
        Size = size,
        Linger = linger or 0.1,
        Time = 0,
        Active = true
    }, VirtualHitbox)
end

function VirtualHitbox:WillHit(playerCharacter, killerCharacter, predictionTime, killerVelocity)
    if not self.Active or not playerCharacter then
        return false
    end

    predictionTime = predictionTime or 1.9
    killerVelocity = killerVelocity or Vector3.new(0, 0, 0)

    local predicted_x = self.OriginX
    local predicted_y = self.OriginY
    local predicted_z = self.OriginZ

    if predictionTime > 0 then
        local vx, vy, vz = killerVelocity.X, killerVelocity.Y, killerVelocity.Z
        local vel_mag = sqrt(vx * vx + vy * vy + vz * vz)
        if vel_mag > 0.1 then
            local scale = predictionTime * 1.5
            predicted_x = predicted_x + vx * scale
            predicted_y = predicted_y + vy * scale
            predicted_z = predicted_z + vz * scale
        end
    end

    local now = os.clock()
    local m = getCachedRotation(self.OriginRot, now)

    local corrected_ox, corrected_oy, corrected_oz = self.OffsetX, self.OffsetY, -self.OffsetZ
    local rotated_ox, rotated_oy, rotated_oz = rotate_vec_inline(corrected_ox, corrected_oy, corrected_oz, m)

    local world_ox = predicted_x + rotated_ox
    local world_oy = predicted_y + rotated_oy
    local world_oz = predicted_z + rotated_oz

    local limbNames = {"Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg"}
    local leeway = 2
    local expanded_hx = self.HalfX + leeway
    local expanded_hy = self.HalfY + leeway
    local expanded_hz = self.HalfZ + leeway

    for _, name in ipairs(limbNames) do
        local part = playerCharacter:FindFirstChild(name)
        if part and part.Position then
            local pos = part.Position
            local inside = point_in_box_fast(pos.X, pos.Y, pos.Z, world_ox, world_oy, world_oz, m, expanded_hx,
                expanded_hy, expanded_hz)
            if inside then
                return true
            end

            if DEBUG.Enabled then
                pcall(function()
                    debug_point(pos, DEBUG.PlayerColor)
                end)
            end
        end
    end

    if DEBUG.Enabled then
        coroutine.wrap(function()
            pcall(function()
                debug_box(v3new(world_ox, world_oy, world_oz), self.Size, DEBUG.BoxColor, self.OriginRot)
            end)
        end)()
    end

    return false
end

function VirtualHitbox:Step(dt)
    if not self.Active then
        return false
    end
    self.Time = self.Time + (dt or 0)
    if self.Time >= self.Linger then
        self.Active = false
        return false
    end
    return true
end

function VirtualHitbox:UpdatePosition(x, y, z)
    self.OriginX = x
    self.OriginY = y
    self.OriginZ = z
end

function VirtualHitbox:UpdateRotation(rot)
    self.OriginRot = rot
end

local AutoParry = {}
AutoParry.__index = AutoParry

function AutoParry.new()
    local self = setmetatable({}, AutoParry)
    self.isActive = false
    self.lastParryTime = 0
    self.attackStates = {}
    self.swingBlacklist = {}
    self.lastSweepTime = os.clock()
    return self
end

function AutoParry:SanityCheck()
    if not Player or not Player.Character then
        return false
    end
    if not workspace:FindFirstChild('Map') then
        return false
    end
    if not Player.Character:FindFirstChild("HumanoidRootPart") then
        return false
    end
    return true
end

function AutoParry:GetKillerVelocity(killer)
    if not killer or not killer:FindFirstChild("HumanoidRootPart") then
        return Vector3.new(0, 0, 0)
    end

    if not self.positionHistory then
        self.positionHistory = {}
    end

    local key = killer.Address
    if not key then
        return Vector3.new(0, 0, 0)
    end

    if not self.positionHistory[key] then
        self.positionHistory[key] = {
            positions = {},
            lastUpdate = 0,
            lastVelocity = {
                x = 0,
                y = 0,
                z = 0
            }
        }
    end

    local history = self.positionHistory[key]
    local currentTime = os.clock()
    local hrp = killer.HumanoidRootPart

    local ok, pos = pcall(function()
        return hrp.Position
    end)
    if not ok or not pos then
        return Vector3.new(history.lastVelocity.x, history.lastVelocity.y, history.lastVelocity.z)
    end

    if currentTime - history.lastUpdate >= 0.0016 then
        table.insert(history.positions, {
            x = pos.X,
            y = pos.Y,
            z = pos.Z,
            time = currentTime
        })
        history.lastUpdate = currentTime

        while #history.positions > 6 do
            table.remove(history.positions, 1)
        end
    end

    if #history.positions < 2 then
        return Vector3.new(history.lastVelocity.x, history.lastVelocity.y, history.lastVelocity.z)
    end

    local oldest = history.positions[1]
    local newest = history.positions[#history.positions]
    local dt = newest.time - oldest.time

    if dt <= 0.005 then
        return Vector3.new(history.lastVelocity.x, history.lastVelocity.y, history.lastVelocity.z)
    end

    local dx = newest.x - oldest.x
    local dy = newest.y - oldest.y
    local dz = newest.z - oldest.z

    local vx = dx / dt
    local vy = dy / dt
    local vz = dz / dt

    local alpha = 0.35
    history.lastVelocity.x = history.lastVelocity.x * (1 - alpha) + vx * alpha
    history.lastVelocity.y = history.lastVelocity.y * (1 - alpha) + vy * alpha
    history.lastVelocity.z = history.lastVelocity.z * (1 - alpha) + vz * alpha

    return Vector3.new(history.lastVelocity.x, history.lastVelocity.y, history.lastVelocity.z)
end

function AutoParry:FindActiveSwingSound(killer, swingIds)
    if not swingIds or not killer then
        return nil
    end

    local descendants = killer.HumanoidRootPart:GetChildren()

    for _, swingId in pairs(swingIds) do
        for _, desc in ipairs(descendants) do
            if desc and desc:IsA("Sound") then
                local soundId = nil
                local success = pcall(function()
                    if desc.Address and SOUNDID_ADDR then
                        local pointer = memory_read('uintptr_t', desc.Address + SOUNDID_ADDR)
                        soundId = memory_read('string', pointer)
                    end
                end)

                if success and soundId == swingId then
                    local idkey = desc.Address and tostring(desc.Address) or tostring(desc)
                    if not SWING_BLACKLIST[idkey] then
                        return desc
                    end
                end
            end
        end
    end
    return nil
end

function AutoParry:CreateVirtualHitbox(killer, killerName)
    local config = KillerConfigs[killerName] or {
        SlashSize = Vector3.new(4.5, 6, 7.5),
        SlashOffset = Vector3.new(0, 0, -1.25),
        SlashLinger = 0.25
    }

    local hrp = killer:FindFirstChild("HumanoidRootPart")
    if not hrp then
        return nil
    end

    local position = v3new(0, 0, 0)
    local rot = nil
    local ok, pos = pcall(function()
        return hrp.Position
    end)
    if ok and pos then
        position = pos
    end
    rot = cframe_to_euler(hrp)

    return VirtualHitbox.new(position, rot, config.SlashOffset, config.SlashSize, config.SlashLinger)
end

function AutoParry:UpdateAttackStates()
    if not self:SanityCheck() then
        return
    end
    local playerRoot = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
    if not playerRoot then
        return
    end

    local killersFolder = workspace:FindFirstChild('Players')
    if killersFolder then
        killersFolder = killersFolder:FindFirstChild('Killers')
    end
    if not killersFolder then
        return
    end

    coroutine.wrap(function()
        local existingKillers = {}
        for _, killer in pairs(killersFolder:GetChildren()) do
            if killer:IsA("Model") then
                existingKillers[killer.Name] = true
            end
        end
        for killerName in pairs(self.attackStates) do
            if not existingKillers[killerName] then
                self.attackStates[killerName] = nil
            end
        end
    end)()

    for _, killer in pairs(killersFolder:GetChildren()) do
        if killer:IsA("Model") and killer:FindFirstChild("HumanoidRootPart") then
            local killerName = killer.Name
            local swingIds = KillerSwings[killerName]
            if swingIds then
                local activeSwing = self:FindActiveSwingSound(killer, swingIds)

                local state = self.attackStates[killerName]
                if not state then
                    state = {
                        isAttacking = false,
                        swingInstance = nil,
                        startTime = nil,
                        shouldParry = false,
                        hitbox = nil,
                        killer = killer
                    }
                    self.attackStates[killerName] = state
                end

                state.killer = killer

                if activeSwing and not state.isAttacking then
                    state.isAttacking = true
                    state.swingInstance = activeSwing
                    state.startTime = os.clock()
                    state.shouldParry = false
                    state.hitbox = nil

                    local hitbox = self:CreateVirtualHitbox(killer, killerName)
                    if hitbox then
                        state.hitbox = hitbox

                        local config = KillerConfigs[killerName]
                        local windup = (config and config.SlashWindup) or 0.3
                        local pollDelay = math.max(0, windup - CONFIG.ParryPreemption)

                        spawn(function()
                            local maxEndTime = state.startTime +
                                                   math.max(CONFIG.MaxSwingDuration,
                                    windup + (config and config.SlashLinger or 0.25))

                            coroutine.wrap(function()
                                while state.isAttacking and state.hitbox and self.isActive do
                                    local killerHrp = killer:FindFirstChild("HumanoidRootPart")
                                    if not killerHrp then
                                        break
                                    end

                                    local rot = cframe_to_euler(killerHrp)
                                    if rot then
                                        state.hitbox:UpdateRotation(rot)
                                    end

                                    local ok, pos = pcall(function()
                                        return killerHrp.Position
                                    end)
                                    if ok and pos then
                                        state.hitbox:UpdatePosition(pos.X, pos.Y, pos.Z)
                                    end

                                    task.wait()
                                end
                            end)()

                            while state.isAttacking and state.hitbox and self.isActive and os.clock() < maxEndTime do
                                local currentPlayerRoot = Player.Character and
                                                              Player.Character:FindFirstChild("HumanoidRootPart")
                                if not currentPlayerRoot then
                                    break
                                end

                                local killerHrp = killer:FindFirstChild("HumanoidRootPart")
                                if killerHrp then
                                    local ok, pos = pcall(function()
                                        return killerHrp.Position
                                    end)
                                    if ok and pos then
                                        state.hitbox:UpdatePosition(pos.X, pos.Y, pos.Z)
                                    end
                                end

                                local velocity = self:GetKillerVelocity(state.killer)
                                local ok, willHit = pcall(function()
                                    return state.hitbox:WillHit(Player.Character, killer, CONFIG.PredictionWindow,
                                        velocity)
                                end)
                                if ok and willHit then
                                    state.shouldParry = true
                                    break
                                end

                                task.wait()
                            end
                        end)
                    else

                    end

                elseif not activeSwing and state.isAttacking then
                    if state.swingInstance then
                        local identifier = state.swingInstance.Address and tostring(state.swingInstance.Address) or
                                               tostring(state.swingInstance)
                        self.swingBlacklist[identifier] = os.clock()
                    end
                    state.isAttacking = false
                    state.swingInstance = nil
                    state.startTime = nil
                    state.shouldParry = false
                    state.hitbox = nil

                elseif activeSwing and state.isAttacking then
                    local elapsed = os.clock() - (state.startTime or 0)
                    if elapsed > CONFIG.MaxSwingDuration then
                        state.isAttacking = false
                        state.swingInstance = nil
                        state.startTime = nil
                        state.shouldParry = false
                        state.hitbox = nil
                    end

                end
            end
        end
    end
end

function AutoParry:ShouldParryAnyKiller()
    for killerName, state in pairs(self.attackStates) do
        if state.isAttacking and state.shouldParry then
            return true, killerName
        end
    end
    return false, nil
end

function AutoParry:ExecuteParry()
    local currentTime = os.clock()
    if currentTime - self.lastParryTime < CONFIG.ParryCooldown then
        return false
    end

    keypress(0x51)

    self.lastParryTime = currentTime
    return true
end

function AutoParry:CleanupBlacklist()
    local now = os.clock()
    if now - self.lastSweepTime > CONFIG.SwingBlacklistSweepInterval then
        for key, timestamp in pairs(self.swingBlacklist) do
            if now - timestamp > CONFIG.SwingBlacklistMaxAge then
                self.swingBlacklist[key] = nil
            end
        end
        self.lastSweepTime = now
    end
end

function AutoParry:Step()
    if not self.isActive or not self:SanityCheck() then
        return false
    end
    self:CleanupBlacklist()
    self:UpdateAttackStates()
    local shouldParry, killerName = self:ShouldParryAnyKiller()
    if shouldParry then
        local success = self:ExecuteParry()
        return success
    end
    return false
end

function AutoParry:Start()
    if self.isActive then
        return
    end
    self.isActive = true
    self.attackStates = {}
end

function AutoParry:Stop()
    if not self.isActive then
        return
    end
    self.isActive = false
    self.attackStates = {}
end

local parrySystem = AutoParry.new()
parrySystem:Start()

warn('Autoblock awesome edition')
warn('Detection Range:', CONFIG.DetectionRange)
warn('Prediction Window:', CONFIG.PredictionWindow, 's')
warn('Parry Preemption:', CONFIG.ParryPreemption, 's')
warn('Parry Cooldown:', CONFIG.ParryCooldown, 's')

spawn(function()
    while true do
        if iskeypressed(0x46) then
            parrySystem:Step()
        end
        task.wait()
    end
end)
