require("/scripts/util.lua")
require("/scripts/vec2.lua")
require("/scripts/poly.lua")
require("/scripts/pathing.lua")

local __xPlayer_oldInit = init
local __xPlayer_oldUpdate = update
local __xPlayer_oldUninit = uninit

local function mulPoly(poly, mul)
    local newPoly = jarray()
    for k, coord in pairs(poly) do
        local coordCopy = { coord[1] * mul, coord[2] * mul }
        newPoly[k] = coordCopy
    end
    return newPoly
end

local function deepCopy(objectToCopy)
    local lookup_table = {}
    local function _copy(object)
        if type(object) ~= "table" then
            return object
        elseif lookup_table[object] then
            return lookup_table[object]
        end
        local new_table = {}
        lookup_table[object] = new_table
        for index, value in pairs(object) do
            new_table[_copy(index)] = _copy(value)
        end
        return setmetatable(new_table, _copy(getmetatable(object)))
    end
    return _copy(objectToCopy)
end

local function initPather()
    local movementParameters = status.statusProperty("xPlayer::customMovementParameters")
    movementParameters = type(movementParameters) == "table"
            and util.mergeTable(mcontroller.baseParameters(), movementParameters)
        or mcontroller.baseParameters()
    local scaleFactor = status.stat("charHeight") ~= 0 and (status.stat("charHeight") / 187.5)
        or (
            status.stat("bodysize") ~= 0 and status.stat("bodysize")
            or (type(globals.scale == "number") and globals.scale or 1.0)
        )
    movementParameters.flySpeed = 35
    movementParameters.airForce = 120
    movementParameters.standingPoly = mulPoly(movementParameters.standingPoly, scaleFactor)
    movementParameters.crouchingPoly = mulPoly(movementParameters.crouchingPoly, scaleFactor)
    -------
    local highGrav = world.gravity(mcontroller.position()) >= 30
    -------
    local jumpDropDistMultiplier = 1 + status.stat("pathDropMultiplier")
    local maxFallVelMultiplier = 1 + status.stat("pathFallVelMultiplier")
    local tailed = status.statPositive("noLegs") or status.statusProperty("noLegs")
    local potted = status.statPositive("potted") or status.statusProperty("potted")
    local bouncy = status.statPositive("bouncy") or status.statPositive("bouncy2")
    local largePotted = status.statPositive("largePotted") or status.statusProperty("largePotted")
    local fireworks = status.statPositive("fireworks") or status.statusProperty("fireworks")
    local mertail = status.statPositive("mertail") or status.statusProperty("mertail")
    local leggedOverride = status.statPositive("legged") or status.statusProperty("legged")
    local scarecrowPole = status.statPositive("scarecrowPole") or status.statusProperty("scarecrowPole")
    local ghostTail = status.statPositive("ghostTail") or status.statusProperty("ghostTail")
    local avosiFlight = status.statPositive("avosiFlight") or status.statusProperty("avosiFlight")
    local avosiJetpack = status.statPositive("avosiJetpack") or status.statusProperty("avosiJetpack")
    local avolitePack = status.statPositive("avolitePack") or status.statusProperty("avolitePack")
    local avosiWingedArms = status.statPositive("avosiWingedArms") or status.statusProperty("avosiWingedArms")
    local avosiWings = status.statPositive("avosiWings") or status.statusProperty("avosiWings")
    local swimmingFlight = status.statPositive("swimmingFlight") or status.statusProperty("swimmingFlight")
    local flightEnabled = status.statPositive("flightEnabled")
    local avosiGlider = status.statPositive("avosiGlider") or status.statusProperty("avosiGlider")
    local windSail = status.statPositive("windSail") or status.statusProperty("windSail")
    local shadowRun = status.statPositive("shadowRun") or status.statusProperty("shadowRun")
    local paragliderPack = status.statPositive("paragliderPack") or status.statusProperty("paragliderPack")
    local paramotor = (status.statPositive("paramotor") or status.statusProperty("paramotor")) and highGrav
    local garyTech = status.statPositive("garyTech") or status.statusProperty("garyTech")
    local fezTech = status.statPositive("fezTech") or status.statusProperty("fezTech")
    local parkourThrusters = (status.statPositive("parkourThrusters") or status.statusProperty("parkourThrusters"))
        and highGrav
    local leglessRaw = status.statPositive("leglessSmallColBox")
        or status.statusProperty("leglessSmallColBox")
        or status.statPositive("legless")
    local flyboard = (status.statPositive("flyboard") or status.statusProperty("flyboard")) and globals.flyboardActive
    -------
    local legless = tailed
        or potted
        or bouncy
        or largePotted
        or fireworks
        or mertail
        or ((scarecrowPole or leglessRaw) and not leggedOverride)
    local winged = avosiWings or avosiWingedArms or avosiJetpack or avolitePack
    local canFly = (
        winged
        or flightEnabled
        or swimmingFlight
        or avosiGlider
        or windSail
        or (paragliderPack and paramotor)
        or shadowRun
        or garyTech
        or fezTech
        or parkourThrusters
    ) and globals.isParkourTech
    -------
    local canGlide = (paragliderPack or swimmingFlight or avosiGlider or avosiFlight) and globals.isParkourTech
    local gravMod = tonumber(movementParameters.gravityMultiplier) or 1.5
    local gravityModifier = globals.isParkourTech and (status.stat("gravityModifier") + 1) or 1
    -------
    local jumpModifier = canGlide and 0.75 or 0
    movementParameters.gravityMultiplier = gravMod * gravityModifier
    -------
    local hopInstead = status.statPositive("pathHopInstead") or legless
    local alwaysFly = status.statPositive("alwaysPathFly") or ((ghostTail or flyboard) and globals.isParkourTech)
    local tryFlying = status.statPositive("canPathFly") or canFly
    local tryBiggerJumps = math.max(status.stat("jumpAdder"), status.stat("pathJumpAdder"))
    if tryBiggerJumps <= 0 then tryBiggerJumps = false end
    -------
    local parkourFlight = status.statPositive("levitating")
        or status.statPositive("hoverFlight")
        or status.statPositive("canSwim")
        or status.statPositive("flyWhenGliding")
        or status.statPositive("gravGliding")
        or status.statPositive("gravGlidingInSpace")
    local targetThreshold = status.statPositive("patherTargetThreshold") and status.stat("patherTargetThreshold")
        or (parkourFlight and 2.25)
    -------
    self.maxPathingDistance = status.statPositive("maxPathDist") and status.stat("maxPathDist") or 50
    -------
    self.pathing = PathMover:new({
        returnBest = false,
        run = true,
        movementParameters = movementParameters,
        pathOptions = {
            mustEndOnGround = false,
            maxDistance = 750,
            maxFScore = 2400,
            glideAdjustment = canGlide,
            jumpModifier = jumpModifier,
            maxLandingVelocity = -10 * maxFallVelMultiplier,
            enableVerticalJumpAirControl = false,
            jumpDropXMultiplier = 1 * jumpDropDistMultiplier,
            tryBiggerJumps = tryBiggerJumps,
            tryFlying = tryFlying,
            alwaysFly = alwaysFly,
            hopInstead = hopInstead,
            targetThreshold = targetThreshold,
        },
    })
    self.pathing2 = PathMover:new({
        returnBest = false,
        run = false,
        movementParameters = movementParameters,
        pathOptions = {
            mustEndOnGround = false,
            maxDistance = 750,
            maxFScore = 2400,
            glideAdjustment = canGlide,
            jumpModifier = 0,
            maxLandingVelocity = -10 * maxFallVelMultiplier,
            enableVerticalJumpAirControl = false,
            jumpDropXMultiplier = 1 * jumpDropDistMultiplier,
            tryFlying = tryFlying,
            tryBiggerJumps = false,
            alwaysFly = alwaysFly,
            hopInstead = hopInstead,
            targetThreshold = targetThreshold,
        },
    })
end

local function mulPoly(poly, mul)
    local newPoly = jarray()
    for k, coord in pairs(poly) do
        local coordCopy = { coord[1] * mul, coord[2] * mul }
        newPoly[k] = coordCopy
    end
    return newPoly
end

local function groundBelow(posToCheck, maxDist, scaleFactor)
    local aPos = { posToCheck[1], posToCheck[2] - (2.5 * scaleFactor) }
    for i = 1, math.floor(maxDist or 1), 1 do
        local cPos = { aPos[1], aPos[2] - i }
        if
            world.pointCollision(cPos, { "Block", "Dynamic", "Slippery", "Platform" })
            or world.pointTileCollision(cPos, { "Block", "Dynamic", "Slippery", "Platform" })
        then -- world.tileIsOccupied(cPos)
            return { cPos[1], cPos[2] + 2.5 * scaleFactor }
        end
    end
    return false
end

local function snapToGround(position, maxDistance, checkPlatforms, scaleFactor)
    local adjPos = groundBelow(position, maxDistance or 8, scaleFactor) or position
    local hitbox = mulPoly(mcontroller.baseParameters().standingPoly, scaleFactor)

    if checkPlatforms then
        if world.polyCollision(hitbox, adjPos, { "Block", "Dynamic", "Slippery", "Platform" }) then
            local adjPos2 =
                world.resolvePolyCollision(hitbox, adjPos, 12, { "Block", "Dynamic", "Slippery", "Platform" })
            if not adjPos2 then
                return adjPos
            else
                return adjPos2
            end
        end
    else
        if world.polyCollision(hitbox, adjPos) then
            local adjPos2 = world.resolvePolyCollision(hitbox, adjPos, 12)
            if not adjPos2 then
                return adjPos
            else
                return adjPos2
            end
        end
    end

    return adjPos
end

local function setPathfinderTarget(targetPosition, shouldWalk)
    local pathInitStatus, exceptionMsg = pcall(initPather) -- Reinitialise the pather any time the trigger item or xPlayer bind is used, so as to update movement parameters.
    if not pathInitStatus then
        local playerName, playerUuid = player.name(), player.uniqueId()
        sb.logError(
            "[xPlayer::Player] Pathing initialisation error for player '%s' [%s]: %s",
            playerName,
            playerUuid,
            exceptionMsg
        )
        return
    end
    self.followWalking = shouldWalk
    self.followedId = world.playerQuery(targetPosition, 3, { order = "nearest", boundMode = "position" })[1]
        or world.npcQuery(targetPosition, 0.75, { order = "nearest" })[1]
        or world.monsterQuery(targetPosition, 0.75, { order = "nearest" })[1]
    if self.followedId then
        local isPlayer = world.entityType(self.followedId) == "player"
        local isNpc = world.entityType(self.followedId) == "npc"
        local isMonster = world.entityType(self.followedId) == "monster"
        if isPlayer and self.followedId ~= entity.id() then
            local followUuid = world.entityUniqueId(self.followedId)
            if followUuid ~= "" then world.sendEntityMessage(entity.id(), "setFollowUuid", followUuid) end
        end
        if interface and self.followedId ~= entity.id() then
            local targetName = world.entityName(self.followedId)
            local targetUuid = world.entityUniqueId(self.followedId) or ""
            local playerName = world.entityName(entity.id())
            playerName = (playerName == "" and ("<" .. entity.uniqueId() .. ">") or playerName)
            local entityName = targetName
                or (isPlayer and ("<" .. targetUuid .. ">") or ("[" .. self.followedId .. "]"))
            local entityColourCode = isPlayer and "player ^orange,set;"
                or (isNpc and "NPC ^cyan,set;" or "monster ^yellow,set;")
            local queueMessage = "Player ^orange,set;"
                .. playerName
                .. "^white,set; is now following "
                .. entityColourCode
                .. entityName
                .. "^white,set;."
            interface.queueMessage(queueMessage)
        end
    end
    if self.followedId == entity.id() then
        self.followedId = nil
        world.sendEntityMessage(entity.id(), "setFollowUuid", nil)
        self.pathDestination = nil
        status.setStatusProperty("pathDestination", nil)
        if interface then
            local playerName = world.entityName(entity.id())
            playerName = (playerName == "" and ("<" .. entity.uniqueId() .. ">") or playerName)
            local queueMessage = "Player ^orange,set;" .. playerName .. "^white,set; is no longer pathfinding."
            interface.queueMessage(queueMessage)
        end
    elseif self.followedId == nil then
        local scaleFactor = status.stat("charHeight") ~= 0 and (status.stat("charHeight") / 187.5)
                or (
                    status.stat("bodysize") ~= 0 and status.stat("bodysize")
                    or (type(globals.scale == "number") and globals.scale or 1.0)
                )
        self.pathDestination = snapToGround(targetPosition, 2, true, scaleFactor)
        status.setStatusProperty("pathDestination", self.pathDestination)
        if interface then
            local playerName = world.entityName(entity.id())
            playerName = (playerName == "" and ("<" .. entity.uniqueId() .. ">") or playerName)
            local queueMessage = "Player ^orange,set;"
                .. playerName
                .. "^white,set; is now pathfinding to selected location."
            interface.queueMessage(queueMessage)
        end
    else
        self.pathDestination = nil
        status.setStatusProperty("pathDestination", nil)
    end
end

local function pathingUpdate(dt)
    if self.followedId and world.entityExists(self.followedId) then
        local playerPosition = world.entityPosition(self.followedId)
        local ownPosition = mcontroller.position()
        local distance = world.distance(playerPosition, ownPosition)
        local adjustedDistance = math.sqrt(distance[1] ^ 2 + distance[2] ^ 2)
        if storage.invisible then
            mcontroller.setPosition(world.entityPosition(self.followedId))
        else
            local scaleFactor = status.stat("charHeight") ~= 0 and (status.stat("charHeight") / 187.5)
                or (
                    status.stat("bodysize") ~= 0 and status.stat("bodysize")
                    or (type(globals.scale == "number") and globals.scale or 1.0)
                )
            if not self.oldTargetPosiition then
                self.oldTargetPosiition = world.entityPosition(self.followedId)
                self.oldTargetDirection = 1
            end
            local adjustedPlayerPosition
            if math.abs(playerPosition[1] - self.oldTargetPosiition[1]) < 0.3 then
                adjustedPlayerPosition = { playerPosition[1] + (3 * -self.oldTargetDirection), playerPosition[2] }
            else
                adjustedPlayerPosition = (playerPosition[1] - self.oldTargetPosiition[1]) > 0
                        and { playerPosition[1] - 3, playerPosition[2] }
                    or { playerPosition[1] + 3, playerPosition[2] }
                self.oldTargetDirection = (playerPosition[1] - self.oldTargetPosiition[1]) > 0 and 1 or -1
            end
            if adjustedDistance > 8 then adjustedPlayerPosition = nil end
            local colPoly = mcontroller.baseParameters().standingPoly
            if type(self.customMovementParameters) == "table" then
                if self.customMovementParameters.standingPoly then
                    colPoly = self.customMovementParameters.standingPoly
                end
            end
            playerPosition = groundBelow(playerPosition, 6, scaleFactor) or playerPosition
            if world.polyCollision(colPoly, playerPosition) then
                local resPos = world.resolvePolyCollision(colPoly, playerPosition, 8)
                playerPosition = resPos or playerPosition
            end
            if adjustedPlayerPosition then
                adjustedPlayerPosition = groundBelow(adjustedPlayerPosition, 6, scaleFactor) or playerPosition
                if world.polyCollision(colPoly, adjustedPlayerPosition) then
                    local resPos = world.resolvePolyCollision(colPoly, adjustedPlayerPosition, 8)
                    adjustedPlayerPosition = resPos
                end
            end
            local adjDestPos = adjustedPlayerPosition or playerPosition
            distance = world.distance(adjDestPos, ownPosition)
            if distance[2] >= 2 then
                adjDestPos = { adjDestPos[1], adjDestPos[2] + 1 }
                if world.polyCollision(colPoly, adjDestPos) then
                    local resPos = world.resolvePolyCollision(colPoly, adjDestPos, 2)
                    adjDestPos = resPos or adjDestPos
                end
            end
            adjDestPos = vec2.add(adjDestPos, {0, 0.25})
            adjustedDistance = math.sqrt(distance[1] ^ 2 + distance[2] ^ 2)
            -----
            if not self.pathingTimer then self.pathingTimer = 0 end
            if not self.playerPosition then self.playerPosition = adjDestPos end
            if not self.pathDistance then self.pathDistance = adjustedDistance end
            self.pathingTimer = self.pathingTimer + dt
            if self.pathingTimer >= 0.20 then
                self.playerPosition = adjDestPos
                self.pathDistance = adjustedDistance
                self.pathingTimer = 0
            end
            -----
            local dPos = self.playerPosition
            local x, y = dPos[1], dPos[2]
            local dPos2 = adjDestPos
            local x2, y2 = dPos2[1], dPos2[2]
            -----
            if status.statPositive("pathNoclip") then -- or self.noclipFollowing
                self.pathDestination = playerPosition
                if adjustedDistance >= 8 then -- or self.noclipFollowing
                    mcontroller.controlApproachVelocity(vec2.mul(vec2.norm(distance), 80), 240)
                else
                    mcontroller.controlApproachVelocity({ 0, 0 }, 1000)
                end
                if
                    adjustedDistance <= 8
                    and (not world.polyCollision(colPoly, ownPosition))
                    and groundBelow(adjDestPos, 6, scaleFactor)
                    and (world.gravity(ownPosition) ~= 0)
                then
                    mcontroller.controlApproachVelocity({ 0, 0 }, 1000)
                    self.noclipFollowing = false
                end
            else
                self.pathDestination = self.playerPosition
                local objects = world.objectQuery(mcontroller.position(), 3, { order = "nearest" })
                for _, object in ipairs(objects) do
                    if world.getObjectParameter(object, "category") == "door" then
                        world.sendEntityMessage(object, "openDoor")
                    end
                end
                if self.followWalking then
                    local pathStatus, unstickPos = self.pathing2:move(self.playerPosition, dt)
                    if
                        (unstickPos and status.statPositive("pathStuckTeleport"))
                        or adjustedDistance >= self.maxPathingDistance
                    then
                        -- sb.logInfo("[xFollow] Getting unstuck.")
                        mcontroller.setPosition(unstickPos or adjDestPos)
                    end
                    self.pathStatus = pathStatus
                else
                    local pathStatus, unstickPos = self.pathing:move(self.playerPosition, dt)
                    if
                        (unstickPos and status.statPositive("pathStuckTeleport"))
                        or adjustedDistance >= self.maxPathingDistance
                    then
                        mcontroller.setPosition(unstickPos or adjDestPos)
                    end
                    self.pathStatus = pathStatus
                end
                -- local canNoclip = not status.statusProperty("disableNoclipPathing")
                -- -- if type(self.customMovementParameters) == "table" then
                -- --     canNoclip = not self.customMovementParameters.disableNoclipPathing
                -- -- end
                -- if canNoclip then
                --     if adjustedDistance >= 30 or (world.lineCollision(ownPosition, playerPosition) and adjustedDistance >= 25) or
                --       (not groundBelow(adjustedPlayerPosition or playerPosition, 10, scaleFactor)) or world.polyCollision(colPoly, ownPosition) or
                --       world.gravity(ownPosition) == 0 then self.noclipFollowing = true end
                -- end
                self.oldTargetPosiition = world.entityPosition(self.followedId)
            end
        end
    elseif self.followedId then
        self.pathDestination = nil
    elseif type(self.pathDestination) == "table" and #self.pathDestination == 2 then
        if not (type(self.pathDestination[1]) == "number" and type(self.pathDestination[2]) == "number") then
            self.pathDestination = nil
            goto noDestination
        end
        local ownPosition = mcontroller.position()
        local distance = world.distance(self.pathDestination, ownPosition)
        local adjustedDistance = math.sqrt(distance[1] ^ 2 + distance[2] ^ 2)
        -- local canNoclip = not status.statusProperty("disableNoclipPathing")
        -- if type(self.customMovementParameters) == "table" then canNoclip = not self.customMovementParameters.disableNoclipPathing end
        -- if canNoclip then
        --     if adjustedDistance >= 35 or (world.lineCollision(ownPosition, self.pathDestination) and adjustedDistance >= 25) then
        --         self.noclipFollowing = true
        --     end
        -- end
        if (not self.noclipFollowing) and world.gravity(ownPosition) == 0 then self.noclipFollowing = true end
        local scaleFactor = status.stat("charHeight") ~= 0 and (status.stat("charHeight") / 187.5)
            or (
                status.stat("bodysize") ~= 0 and status.stat("bodysize")
                or (type(globals.scale == "number") and globals.scale or 1.0)
            )
        local colPoly = mulPoly(mcontroller.baseParameters().standingPoly, scaleFactor)
        if
            adjustedDistance <= 5.5
            and (
                ((not world.polyCollision(colPoly, ownPosition)) and (world.gravity(ownPosition) ~= 0))
                or (status.statPositive("godmode") or self.platLock or self.noclipping)
            )
        then
            if self.noclipFollowing or status.statPositive("godmode") or self.platLock or self.noclipping then
                mcontroller.controlApproachVelocity({ 0, 0 }, 1000)
                if status.statPositive("godmode") or self.platLock or self.noclipping then
                    self.pathDestination = nil
                    status.setStatusProperty("pathDestination", nil)
                end
            end
            self.noclipFollowing = false
        end
        if self.noclipping or self.platLock or status.statPositive("godmode") then -- or self.noclipFollowing
            mcontroller.controlApproachVelocity(vec2.mul(vec2.norm(distance), 80), 240)
        else
            local objects = world.objectQuery(mcontroller.position(), 3, { order = "nearest" })
            for _, object in ipairs(objects) do
                if world.getObjectParameter(object, "category") == "door" then
                    world.sendEntityMessage(object, "openDoor")
                end
            end
            if self.followWalking then
                local pathStatus, unstickPos = self.pathing2:move(self.pathDestination, dt)
                if pathStatus == true then
                    self.pathDestination = nil
                    status.setStatusProperty("pathDestination", nil)
                elseif unstickPos and status.statPositive("pathStuckTeleport") then
                    -- sb.logInfo("[xPlayer::Player] Getting unstuck.")
                    mcontroller.setPosition(unstickPos)
                end
                self.pathStatus = pathStatus
            else
                local pathStatus, unstickPos = self.pathing:move(self.pathDestination, dt)
                if pathStatus == true then
                    self.pathDestination = nil
                    status.setStatusProperty("pathDestination", nil)
                elseif unstickPos and status.statPositive("pathStuckTeleport") then
                    mcontroller.setPosition(unstickPos)
                end
                self.pathStatus = pathStatus
            end
        end
        ::noDestination::
    else
        self.pathDestination = nil
        self.pathStatus = nil
        self.noclipFollowing = nil
    end
end

function init()
    if __xPlayer_oldInit then __xPlayer_oldInit() end

    if not xsb then
        sb.logWarn("[xPlayer] xClient not detected! xPlayer disabled.")
        return
    end

    if not self.disabled then
        -- Initialise FezzedTech globals if FezzedTech is present.
        if root.assetExists("/fezTech.binds") then
            require("/scripts/util/globals.lua")
        else
            globals = {}
        end

        self.debug = true

        if root.assetJson("/player.config").xPlayerDisabled then
            sb.logInfo("[xPlayer::Player] xPlayer disabled.")
            self.disabled = true
            return
        else
            self.disabled = false
        end

        message.setHandler("xPlayer::setPathfinderTarget", function(_, isLocal, cursorPosition, shouldWalk)
            if isLocal then
                local pathStatus, exceptionMsg = pcall(setPathfinderTarget, cursorPosition, shouldWalk)
                if pathStatus then
                    self.patherErrored = false
                    return true
                else
                    local playerName, playerUuid = player.name(), player.uniqueId()
                    sb.logError(
                        "[xPlayer::Player] Pathing error for player '%s' [%s]: %s",
                        playerName,
                        playerUuid,
                        exceptionMsg
                    )
                    return false
                end
            else
                return nil
            end
        end)

        local pathInitStatus, exceptionMsg = pcall(initPather)
        if not pathInitStatus then
            local playerName, playerUuid = player.name(), player.uniqueId()
            sb.logError(
                "[xPlayer::Player] Pathing initialisation error for player '%s' [%s]: %s",
                playerName,
                playerUuid,
                exceptionMsg
            )
            self.patherErrored = true
            return
        else
            self.patherErrored = false
        end

        self.oldTargetPosiition = nil

        local playerName, playerUuid = player.name(), player.uniqueId()
        return sb.logInfo("[xPlayer::Player] Initialised xPlayer controls for player '%s' [%s].", playerName, playerUuid)
    end
end

function update(dt)
    if __xPlayer_oldUpdate then __xPlayer_oldUpdate(dt) end

    if xsb and not self.disabled and not self.patherErrored then
        local pathStatus, exceptionMsg = pcall(pathingUpdate, dt)
        if not pathStatus then
            local playerName, playerUuid = player.name(), player.uniqueId()
            sb.logError(
                "[xPlayer::Player] Pathing error for player '%s' [%s]: %s",
                playerName,
                playerUuid,
                exceptionMsg
            )
            self.patherErrored = true
        end
    end
end

function uninit()
    if __xPlayer_oldUninit then __xPlayer_oldUninit() end
end
