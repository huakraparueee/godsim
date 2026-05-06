--[[
  Bootstrap: require paths, dev hot-reload (lurker), delegate to src.main → src.scenes.play.
  Restart the game after changing main.lua or conf.lua.
]]

local DEV = true

love.filesystem.setRequirePath("?.lua;?/init.lua;src/libraries/?.lua")

local lurker
if DEV then
    lurker = require("lurker")
    lurker.path = "src"
    lurker.interval = 0.35
    lurker.quiet = false
end

local game

local function clear_src_modules()
    for name in pairs(package.loaded) do
        if name:match("^src%.") then
            package.loaded[name] = nil
        end
    end
end

local function bind_game()
    game = require("src.main")
end

function love.load()
    bind_game()
    if game.load then
        game.load()
    end
end

function love.update(dt)
    if lurker then
        lurker.update()
    end
    if game and game.update then
        game.update(dt)
    end
end

function love.draw()
    if game and game.draw then
        game.draw()
    end
end

function love.keypressed(key, scancode, isrepeat)
    if DEV and key == "f5" then
        clear_src_modules()
        bind_game()
        if game.load then
            game.load()
        end
        return
    end
    if game and game.keypressed then
        game.keypressed(key, scancode, isrepeat)
    end
end

function love.resize(w, h)
    if game and game.resize then
        game.resize(w, h)
    end
end

function love.wheelmoved(x, y)
    if game and game.wheelmoved then
        game.wheelmoved(x, y)
    end
end

function love.mousepressed(x, y, button, istouch, presses)
    if game and game.mousepressed then
        game.mousepressed(x, y, button, istouch, presses)
    end
end

function love.mousereleased(x, y, button, istouch, presses)
    if game and game.mousereleased then
        game.mousereleased(x, y, button, istouch, presses)
    end
end

function love.mousemoved(x, y, dx, dy, istouch)
    if game and game.mousemoved then
        game.mousemoved(x, y, dx, dy, istouch)
    end
end

function love.visible(visible)
    if game and game.visible then
        game.visible(visible)
    end
end
