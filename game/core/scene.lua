local scene = {
    current = nil
}

function scene.set(nextScene)
    if scene.current and scene.current.quit then
        scene.current.quit()
    end
    scene.current = nextScene
    if scene.current and scene.current.load then
        scene.current.load()
    end
end

function scene.attach(currentScene)
    scene.current = currentScene
end

function scene.update(dt)
    if scene.current and scene.current.update then
        scene.current.update(dt)
    end
end

function scene.draw()
    if scene.current and scene.current.draw then
        scene.current.draw()
    end
end

function scene.keypressed(key, scancode, isrepeat)
    if scene.current and scene.current.keypressed then
        scene.current.keypressed(key, scancode, isrepeat)
    end
end

function scene.keyreleased(key, scancode)
    if scene.current and scene.current.keyreleased then
        scene.current.keyreleased(key, scancode)
    end
end

return scene