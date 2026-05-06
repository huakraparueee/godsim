--[[
  Phase 1 - Task 3:
  SpriteBatch-backed tilemap renderer.
]]

local map_renderer = {}
map_renderer.__index = map_renderer

local TILE_COLORS = {
    deep_water = { 0.03, 0.12, 0.42, 1.0 },
    shallow_water = { 0.12, 0.48, 0.78, 1.0 },
    sand = { 0.86, 0.78, 0.48, 1.0 },
    grass = { 0.22, 0.62, 0.24, 1.0 },
    forest = { 0.04, 0.26, 0.10, 1.0 },
    mountain = { 0.38, 0.40, 0.42, 1.0 },
}

local DEFAULT_COLOR = { 1, 0, 1, 1 } -- Magenta for unknown tile id

local function make_white_pixel_image()
    local image_data = love.image.newImageData(1, 1)
    image_data:setPixel(0, 0, 1, 1, 1, 1)
    return love.graphics.newImage(image_data)
end

function map_renderer.new(tile_size, max_sprites)
    local ts = tile_size or 4
    local image = make_white_pixel_image()
    image:setFilter("nearest", "nearest")

    local self = setmetatable({
        tile_size = ts,
        image = image,
        batch = love.graphics.newSpriteBatch(image, max_sprites or 65536, "static"),
        sprite_count = 0,
    }, map_renderer)

    return self
end

function map_renderer:rebuild(world)
    self.batch:clear()

    local ts = self.tile_size
    local width = world.width
    local total = #world.tiles

    for i = 1, total do
        local tile = world.tiles[i]
        local x = ((i - 1) % width) * ts
        local y = math.floor((i - 1) / width) * ts
        local color = TILE_COLORS[tile.type_id] or DEFAULT_COLOR
        self.batch:setColor(color[1], color[2], color[3], color[4])
        self.batch:add(x, y, 0, ts, ts)
    end

    self.batch:flush()
    self.sprite_count = total
end

function map_renderer:draw(x, y)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.batch, x or 0, y or 0)
end

return map_renderer
