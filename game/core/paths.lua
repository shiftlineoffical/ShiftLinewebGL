local paths = {}

local roots = {
    UserData = "",
    Settings = "Settings",
    Songs = "Songs",
    Cache = "Cache",
    Replays = "Replays",
    Screenshots = "Screenshots",
    Logs = "Logs"
}

function paths.get(name, child)
    local root = roots[name] or name or ""
    if child and child ~= "" then
        if root == "" then
            return child
        end
        return root .. "/" .. child:gsub("^/+", "")
    end
    return root
end

function paths.ensure()
    if not love or not love.filesystem then
        return false
    end
    for name, value in pairs(roots) do
        if name ~= "UserData" and value ~= "" then
            pcall(love.filesystem.createDirectory, value)
        end
    end
    return true
end

function paths.read(name, child)
    local path = paths.get(name, child)
    if love.filesystem.getInfo(path) then
        return love.filesystem.read(path)
    end
    return nil
end

function paths.write(name, child, data)
    paths.ensure()
    return love.filesystem.write(paths.get(name, child), data)
end

return paths