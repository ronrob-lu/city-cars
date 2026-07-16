local car_models = {
    "ambulance.glb",
    "delivery-flat.glb",
    "delivery.glb",
    "firetruck.glb",
    "garbage-truck.glb",
    "hatchback-sports.glb",
    "police.glb",
    "race-future.glb",
    "race.glb",
    "sedan-sports.glb",
    "sedan.glb",
    "suv-luxury.glb",
    "suv.glb",
    "taxi.glb",
    "tractor-police.glb",
    "tractor-shovel.glb",
    "tractor.glb",
    "truck-flat.glb",
    "truck.glb",
    "van.glb"
}

local active_cars = 0

minetest.register_entity("sfstreets:car", {
    initial_properties = {
        physical = true,
        collide_with_objects = true,
        collisionbox = {-1.5, 0.0, -2.5, 1.5, 2.3, 2.5},
        visual = "mesh",
        mesh = "sedan.glb",
        textures = {"colormap.png"},
        visual_size = {x=15, y=15, z=15},
        stepheight = 0.6,
    },

    on_activate = function(self, staticdata)
        active_cars = active_cars + 1

        local data = nil
        if staticdata ~= "" and staticdata ~= nil then
            data = minetest.deserialize(staticdata)
        end

        if data and data.model then
            self.model = data.model
            self.move_yaw = data.move_yaw or 0
        else
            self.model = car_models[math.random(#car_models)]
            local dirs = {0, math.pi/2, math.pi, 3*math.pi/2}
            self.move_yaw = dirs[math.random(4)]
        end

        self.object:set_properties({mesh = self.model})
        self.object:set_yaw(self.move_yaw + math.pi)
        self.object:set_armor_groups({fleshy = 100})
        self.object:set_acceleration({x=0, y=-9.81, z=0})
    end,

    get_staticdata = function(self)
        return minetest.serialize({
            model = self.model,
            move_yaw = self.move_yaw
        })
    end,

    on_step = function(self, dtime)
        local pos = self.object:get_pos()
        local vel = self.object:get_velocity()

        -- Fall logic
        if vel.y < -0.1 then
            if not self.fall_start_y then
                self.fall_start_y = pos.y
            end
        elseif vel.y > -0.1 and vel.y < 0.1 then
            if self.fall_start_y then
                local fall_depth = self.fall_start_y - pos.y
                if fall_depth > 4.0 then
                    self.object:remove()
                    return
                end
                self.fall_start_y = nil
            end
        end

        -- Despawn logic
        self.timer = (self.timer or 0) + dtime
        if self.timer > 2 then
            self.timer = 0
            local players = minetest.get_connected_players()
            local should_despawn = true
            for _, player in ipairs(players) do
                if vector.distance(pos, player:get_pos()) < 150 then
                    should_despawn = false
                    break
                end
            end
            if should_despawn then
                self.object:remove()
                return
            end
        end

        local yaw = self.move_yaw or (self.object:get_yaw() - math.pi)
        local dir = minetest.yaw_to_dir(yaw)
        if math.abs(dir.x) > math.abs(dir.z) then
            dir.x = dir.x > 0 and 1 or -1
            dir.z = 0
        else
            dir.x = 0
            dir.z = dir.z > 0 and 1 or -1
        end

        self.move_yaw = minetest.dir_to_yaw(dir)
        self.object:set_yaw(self.move_yaw + math.pi)

        -- Check for entities in front to stop and avoid glitching
        local front_pos = vector.add(pos, vector.multiply(dir, 3))
        local objs = minetest.get_objects_inside_radius(front_pos, 3)
        local blocked_by_entity = false
        for _, obj in ipairs(objs) do
            if obj ~= self.object then
                if obj:is_player() or (obj:get_luaentity() and obj:get_properties().collide_with_objects) then
                    blocked_by_entity = true
                    break
                end
            end
        end

        local speed = 4
        if blocked_by_entity then
            speed = 0
        end

        -- Stuck detection logic (for walls/terrain)
        if speed > 0 and math.abs(vel.x) < 0.1 and math.abs(vel.z) < 0.1 then
            self.stuck_timer = (self.stuck_timer or 0) + dtime
            if self.stuck_timer > 1.0 then
                local current_yaw = self.move_yaw
                local turn = (math.random(2) == 1) and (math.pi / 2) or (-math.pi / 2)
                self.move_yaw = current_yaw + turn
                self.object:set_yaw(self.move_yaw + math.pi)
                self.last_bpos = nil
                self.stuck_timer = 0
            end
        else
            self.stuck_timer = 0
        end

        self.object:set_velocity({x = dir.x * speed, y = vel.y, z = dir.z * speed})

        local current_bpos = vector.round(pos)
        if not self.last_bpos or not vector.equals(self.last_bpos, current_bpos) then
            self.last_bpos = current_bpos

            local next_pos = vector.add(current_bpos, dir)

            local next_ground_y = nil
            for i = 2, -2, -1 do
                local p = {x = next_pos.x, y = current_bpos.y + i, z = next_pos.z}
                local node = minetest.get_node(p)
                if node.name == "ignore" then
                    local current_yaw = self.move_yaw
                    local turn = (math.random(2) == 1) and (math.pi / 2) or (-math.pi / 2)
                    self.move_yaw = current_yaw + turn
                    self.object:set_yaw(self.move_yaw + math.pi)
                    return
                end

                local def = minetest.registered_nodes[node.name]
                if def and def.walkable then
                    next_ground_y = p.y
                    break
                end
            end

            if next_ground_y then
                local height_diff = next_ground_y - current_bpos.y
                if height_diff > 1 then
                    local current_yaw = self.move_yaw
                    local turn = (math.random(2) == 1) and (math.pi / 2) or (-math.pi / 2)
                    self.move_yaw = current_yaw + turn
                    self.object:set_yaw(self.move_yaw + math.pi)
                    self.object:set_velocity({x=0, y=vel.y, z=0})
                    self.last_bpos = nil
                end
            end
        end
    end,

    on_deactivate = function(self, removal)
        active_cars = math.max(0, active_cars - 1)
    end,
})

local spawn_timer = 0
minetest.register_globalstep(function(dtime)
    spawn_timer = spawn_timer + dtime
    if spawn_timer < 3 then return end
    spawn_timer = 0

    local players = minetest.get_connected_players()
    if #players == 0 then return end

    local max_cars = tonumber(minetest.settings:get("sfstreets_max_cars")) or 100
    if active_cars >= max_cars then return end

    local player = players[math.random(#players)]
    local ppos = player:get_pos()

    local angle = math.random() * math.pi * 2
    local dist = math.random(15, 100)
    local spawn_x = ppos.x + math.cos(angle) * dist
    local spawn_z = ppos.z + math.sin(angle) * dist

    local spawn_y = nil
    for y = math.floor(ppos.y) + 20, math.floor(ppos.y) - 20, -1 do
        local node = minetest.get_node({x=spawn_x, y=y, z=spawn_z})
        if node.name == "ignore" then return end

        local def = minetest.registered_nodes[node.name]
        if def and def.walkable then
            local node_above = minetest.get_node({x=spawn_x, y=y+1, z=spawn_z})
            local node_above2 = minetest.get_node({x=spawn_x, y=y+2, z=spawn_z})
            local def_above = minetest.registered_nodes[node_above.name]
            local def_above2 = minetest.registered_nodes[node_above2.name]

            if (not def_above or not def_above.walkable) and (not def_above2 or not def_above2.walkable) then
                spawn_y = y + 1
                break
            end
        end
    end

    if spawn_y then
        local spawn_pos = {x=spawn_x, y=spawn_y, z=spawn_z}

        -- Check if the spawn position is within the player's line of sight
        -- We check slightly above the ground (spawn_y + 1) and player's eye level (ppos.y + 1.5)
        local head_pos = {x=ppos.x, y=ppos.y+1.5, z=ppos.z}
        local car_vis_pos = {x=spawn_x, y=spawn_y+1, z=spawn_z}

        local is_visible = minetest.line_of_sight(head_pos, car_vis_pos)

        -- Alternatively, if they are really close, don't spawn them even if behind a wall
        if not is_visible and dist > 20 then
            minetest.add_entity(spawn_pos, "sfstreets:car")
        end
    end
end)

minetest.register_chatcommand("clear_all_cars", {
    description = "Removes all sfstreets:car entities from the loaded map",
    privs = {server = true},
    func = function(name, param)
        local count = 0
        for _, entity in pairs(minetest.luaentities) do
            if entity.name == "sfstreets:car" then
                entity.object:remove()
                count = count + 1
            end
        end
        return true, "Removed " .. count .. " cars."
    end,
})
