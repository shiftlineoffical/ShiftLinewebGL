local sync = {
    queue = {}
}

function sync.enqueue(kind, payload)
    sync.queue[#sync.queue + 1] = {kind = kind, payload = payload}
end

function sync.update(client, limit)
    local count = 0
    while count < (limit or 2) and #sync.queue > 0 do
        local item = table.remove(sync.queue, 1)
        if client and client[item.kind] then
            pcall(client[item.kind], item.payload)
        end
        count = count + 1
    end
end

return sync