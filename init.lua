local car_models = {
    "ambulance.glb",
    "box.glb",
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
    "van.glb",
    "wheel-truck.glb"
}

local active_cars = 0

minetest.register_entity("sfstreets:car", {
    initial_properties = {
        physical = true,
        collide_with_objects = true,
        collisionbox = {-1.0, 0, -1.0, 1.0, 2.0, 1.0},
        visual = "mesh",
        mesh = "sedan.glb",
        textures = {"colormap.png"},
        stepheight = 1.1,
    },

    on_activate = function(self, staticdata)
        active_cars = active_cars + 1

        if staticdata == "" then
            local model = car_models[math.random(#car_models)]
            self.object:set_properties({mesh = model})
            self.model = model

            local dirs = {0, math.pi/2, math.pi, 3*math.pi/2}
            self.object:set_yaw(dirs[math.random(4)])
        else
            local data = minetest.deserialize(staticdata)
            if data and data.model then
                self.model = data.model
                self.object:set_properties({mesh = self.model})
            else
                self.model = "sedan.glb"
            end
        end
        self.object:set_armor_groups({immortal = 1})
    end,

    get_staticdata = function(self)
        return minetest.serialize({
            model = self.model
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

        local yaw = self.object:get_yaw()
        local dir = minetest.yaw_to_dir(yaw)
        if math.abs(dir.x) > math.abs(dir.z) then
            dir.x = dir.x > 0 and 1 or -1
            dir.z = 0
        else
            dir.x = 0
            dir.z = dir.z > 0 and 1 or -1
        end

        self.object:set_yaw(minetest.dir_to_yaw(dir))
        local speed = 4
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
                    local current_yaw = self.object:get_yaw()
                    local turn = (math.random(2) == 1) and (math.pi / 2) or (-math.pi / 2)
                    self.object:set_yaw(current_yaw + turn)
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
                    local current_yaw = self.object:get_yaw()
                    local turn = (math.random(2) == 1) and (math.pi / 2) or (-math.pi / 2)
                    self.object:set_yaw(current_yaw + turn)
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

    if active_cars >= 100 then return end

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
        minetest.add_entity({x=spawn_x, y=spawn_y, z=spawn_z}, "sfstreets:car")
    end
end)
