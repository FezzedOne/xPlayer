local __xPlayer_oldInit = init
local __xPlayer_oldUpdate = update
local __xPlayer_oldUninit = uninit

local function contains(t, v)
    for _, v2 in ipairs(t) do
        if v == v2 then return true end
    end
    return false
end

local function checkMouseState(down, up)
    if down and up then
        return #down > #up and "down" or "up"
    elseif down then
        return "down"
    elseif up then
        return "up"
    else
        return nil
    end
end

function init()
    if __xPlayer_oldInit then __xPlayer_oldInit() end

    if not xsb then return end

    if not self.disabled then
        if root.assetJson("/player.config").xPlayerDisabled then
            sb.logInfo("[xPlayer::Player] xPlayer disabled.")
            self.disabled = true
            return
        else
            self.disabled = false
        end

        if xsb then
            world.setGlobal("xPlayer::oldPrimaryPlayer", world.primaryPlayerUuid())
            if world.getGlobal("xPlayer::controllingAim") == nil then
                world.setGlobal("xPlayer::controllingAim", false)
            end
            sb.logInfo("[xPlayer] Initialised.")
        end

        self.xPlayerConfig = root.getConfiguration("xPlayer")
        if type(self.xPlayerConfig) ~= "table" then
            root.setConfiguration("xPlayer", jobject{})
            self.xPlayerConfig = jobject{}
        end
    end
end

function update(dt)
    if __xPlayer_oldUpdate then __xPlayer_oldUpdate(dt) end

    if xsb and not self.disabled then
        local primaryPlayer, activePlayers = world.primaryPlayerUuid(), world.ownPlayerUuids()
        local oldPrimaryPlayer = world.getGlobal("xPlayer::oldPrimaryPlayer")
        local primaryPlayerId = world.primaryPlayer()
        local isPrimary = entity.id() == primaryPlayerId
        local justSwapped = oldPrimaryPlayer ~= primaryPlayer

        if justSwapped and not self.xPlayerConfig.disableAutoNick then
            chat.command("/nick " .. tostring(player.name()))
        end

        if isPrimary and input.bindDown("xPlayer", "swapPlayer") then
            local nearbyPlayers =
                world.playerQuery(player.aimPosition(), 2.5, { withoutEntityId = primaryPlayerId, order = "nearest" })
            if
                nearbyPlayers[1]
                and world.entityExists(nearbyPlayers[1])
                and contains(activePlayers, world.entityUniqueId(nearbyPlayers[1]))
            then
                world.swapPlayer(world.entityUniqueId(nearbyPlayers[1]))
            end
        end

        if isPrimary and input.bindDown("xPlayer", "controlAim") then
            local toggle = not world.getGlobal("xPlayer::controllingAim")
            sb.logInfo("[xPlayer] %s secondary aim control.", toggle and "Enabled" or "Disabled")
            local queueMessage = (toggle and "^green;Enabled^reset;" or "^red;Disabled^reset;")
                .. " secondary aim control."
            interface.queueMessage(queueMessage)
            world.setGlobal("xPlayer::controllingAim", toggle)
        end

        local pathfinderRun = input.bindDown("xPlayer", "controlPathfindingRun")
        local pathfinderWalk = input.bindDown("xPlayer", "controlPathfindingWalk")
        if isPrimary and (pathfinderRun or pathfinderWalk) then
            local selectedPlayerId = world.getGlobal("xPlayer::selectedPlayer")
            if not selectedPlayerId then
                local nearbyPlayers = world.playerQuery(player.aimPosition(), 2.5, { order = "nearest" })
                if
                    nearbyPlayers[1]
                    and world.entityExists(nearbyPlayers[1])
                    and contains(activePlayers, world.entityUniqueId(nearbyPlayers[1]))
                then
                    local playerName = world.entityName(nearbyPlayers[1])
                    local queueMessage = "Selected ^orange,set;"
                        .. (playerName == "" and ("<" .. nearbyPlayers[1] .. ">") or playerName)
                        .. "^white,set;."
                    interface.queueMessage(queueMessage)
                    world.setGlobal("xPlayer::selectedPlayer", nearbyPlayers[1])
                else
                    local walking = not not pathfinderWalk
                    world.sendEntityMessage(
                        primaryPlayerId,
                        "xPlayer::setPathfinderTarget",
                        player.aimPosition(),
                        walking
                    )
                    world.setGlobal("xPlayer::selectedPlayer", nil)
                end
            else
                local walking = not not pathfinderWalk
                world.sendEntityMessage(selectedPlayerId, "xPlayer::setPathfinderTarget", player.aimPosition(), walking)
                world.setGlobal("xPlayer::selectedPlayer", nil)
            end
        end

        if world.getGlobal("xPlayer::controllingAim") then
            if isPrimary then
                world.setGlobal("xPlayer::primaryAimPosition", player.aimPosition())
            else
                local primaryAimPosition = world.getGlobal("xPlayer::primaryAimPosition")
                if primaryAimPosition then player.controlAimPosition(primaryAimPosition) end

                local primaryDown, primaryUp = input.mouseDown("MouseLeft"), input.mouseUp("MouseLeft")
                local altDown, altUp = input.mouseDown("MouseRight"), input.mouseUp("MouseRight")
                local primaryState, altState = checkMouseState(primaryDown, primaryUp), checkMouseState(altDown, altUp)

                if primaryState then player.controlFire(primaryState == "down" and "beginPrimary" or "endPrimary") end
                if altState then player.controlFire(altState == "down" and "beginAlt" or "endAlt") end

                player.controlShifting(input.keyHeld("LShift"))
            end
        else
            if isPrimary and not justSwapped then
                world.setGlobal("xPlayer::primaryState", nil)
                world.setGlobal("xPlayer::altState", nil)
            else
                player.controlFire()
                player.controlShifting()
            end
        end

        if justSwapped and isPrimary then
            local playerName = world.entityName(primaryPlayerId)
            sb.logInfo("[xPlayer] Swapped to '%s' [%s].", playerName, primaryPlayer)
            local queueMessage = "Swapped to ^orange,set;"
                .. (playerName == "" and ("<" .. primaryPlayer .. ">") or playerName)
                .. "^white,set;."
            interface.queueMessage(queueMessage)
        end

        world.setGlobal("xPlayer::oldPrimaryPlayer", primaryPlayer)
    end
end

function uninit()
    if __xPlayer_oldUninit then __xPlayer_oldUninit() end
end
