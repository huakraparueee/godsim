function love.conf(t)
    t.identity = "GodSim"
    -- Minimum LÖVE version; bump when you rely on newer APIs.
    t.version = "11.5"

    t.appendidentity = true
    t.console = true

    t.window.title = "GodSim"
    t.window.width = 1280
    t.window.height = 720
    t.window.minwidth = 480
    t.window.minheight = 270
    t.window.resizable = true
    t.window.vsync = 1

    if t.window.usedpiscale ~= nil then
        t.window.usedpiscale = true
    end
end
