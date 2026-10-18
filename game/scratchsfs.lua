local _G = _G
local love = love
local string = string
local table = table
local math = math
local ipairs = ipairs
local pairs = pairs
local pcall = pcall
local tostring = tostring
local tonumber = tonumber
local type = type
local string_format = string.format
local table_insert = table.insert
local table_remove = table.remove
local table_concat = table.concat
local math_floor = math.floor
local math_max = math.max
local math_min = math.min

--[[
螟画焚陦ｨ
sflfoldname: 譖ｲ縺ｮ繝輔か繝ｫ繝蜷阪ｒ譬ｼ邏阪☆繧九ユ繝ｼ繝悶Ν
filelist: 譖ｲ縺ｮ繝輔か繝ｫ繝蜀・・繝輔ぃ繧､繝ｫ蜷阪ｒ譬ｼ邏阪☆繧九ユ繝ｼ繝悶Ν
髢｢謨ｰ陦ｨ
notesetting.load(): 譖ｲ縺ｮ繝輔か繝ｫ繝蜷阪ｒ蜿門ｾ励＠縺ｦ繝・・繝悶Ν縺ｫ譬ｼ邏阪☆繧・
foldName: 譖ｲ縺ｮ繝輔か繝ｫ繝蜷・
songPath: 譖ｲ縺ｮ繝輔か繝ｫ繝縺ｮ繝代せ
sflpath: sfl繝輔ぃ繧､繝ｫ縺ｮ繝代せ



notesetting.load()縺ｮ蜃ｦ逅・・豬√ｌ
1. "lib/data/Songs"繝・ぅ繝ｬ繧ｯ繝医Μ蜀・・繧｢繧､繝・Β繧貞叙蠕励＠縲√ユ繝ｼ繝悶Νsongsfold縺ｫ譬ｼ邏阪☆繧・
2. songsfold繧偵い繝ｫ繝輔ぃ繝吶ャ繝磯・↓繧ｽ繝ｼ繝医☆繧・
3. sflfoldname縺ｨsflpath縺ｨ縺・≧遨ｺ縺ｮ繝・・繝悶Ν繧剃ｽ懈・縺吶ｋ
4. songsfold縺ｮ蜷・い繧､繝・Β縺ｫ縺､縺・※莉･荳九・蜃ｦ逅・ｒ陦後≧
    a. 繧｢繧､繝・Β縺後ョ繧｣繝ｬ繧ｯ繝医Μ縺ｧ縺ゅｋ縺狗｢ｺ隱阪☆繧・
    b. 繝・ぅ繝ｬ繧ｯ繝医Μ蜀・・繧｢繧､繝・Β繧貞叙蠕励＠縲√ユ繝ｼ繝悶Νsongsfold縺ｫ譬ｼ邏阪☆繧・
    c. songsfold繧偵い繝ｫ繝輔ぃ繝吶ャ繝磯・↓繧ｽ繝ｼ繝医☆繧・
    d. 繝・ぅ繝ｬ繧ｯ繝医Μ蜀・・繧｢繧､繝・Β繧帝・分縺ｫ遒ｺ隱阪＠縲∵僑蠑ｵ蟄舌′.sfl縺ｮ繝輔ぃ繧､繝ｫ縺後≠繧後・縺昴・繝代せ繧団hartPath縺ｫ譬ｼ邏阪＠縲√Ν繝ｼ繝励ｒ謚懊￠繧・
    f. chartPath縺瑚ｦ九▽縺九▲縺溷ｴ蜷医《flfoldname縺ｫ繝輔か繝ｫ繝蜷阪ｒ縲《flpath縺ｫchartPath繧呈ｼ邏阪☆繧・
5. sflfoldname縺ｨsflpath縺ｨ縺・≧遨ｺ縺ｮ繝・・繝悶Ν繧剃ｽ懈・縺吶ｋ
6. sflfoldname縺ｮ譛蛻昴・隕∫ｴ縺悟ｭ伜惠縺吶ｋ蝣ｴ蜷医√◎縺ｮ繝輔か繝ｫ繝蜀・・繧｢繧､繝・Β繧貞叙蠕励＠縲√ユ繝ｼ繝悶Νfilelist縺ｫ譬ｼ邏阪☆繧・
7. filelist繧偵い繝ｫ繝輔ぃ繝吶ャ繝磯・↓繧ｽ繝ｼ繝医☆繧・
8. sflfoldname縺ｨfilelist縲《flpath繧定ｿ斐☆



sflpath縺ｮ蜀・ｮｹ
sflpath縺ｯ縲・lib/data/Songs"繝・ぅ繝ｬ繧ｯ繝医Μ蜀・・蜷・峇縺ｮ繝輔か繝ｫ繝縺ｫ蟄伜惠縺吶ｋ.sfl繝輔ぃ繧､繝ｫ縺ｮ繝代せ繧呈ｼ邏阪☆繧九ユ繝ｼ繝悶Ν
萓九∴縺ｰ縲・lib/data/Songs/ExampleSong/ExampleSong.sfl"縺ｮ繧医≧縺ｪ繝代せ縺梧ｼ邏阪＆繧後ｋ



    ]]

local scratchsfs = {}


scratchsfs.foldname={}
scratchsfs.list={}
scratchsfs.path={}

local log = require("log")


function scratchsfs.load()
    local function listDir(path)
        local ok, items = pcall(love.filesystem.getDirectoryItems, path)
        if ok and type(items) == "table" and #items > 0 then
            table.sort(items)
            return items
        end

        local okLfs, lfs = pcall(require, "lfs")
        if okLfs and lfs then
            local out = {}
            for name in lfs.dir(path) do
                if name ~= "." and name ~= ".." then
                    out[#out+1] = name
                end
            end
            table.sort(out)
            return out
        end

        local sep = package.config:sub(1,1)
        local cmd
        if sep == '\\' then
            cmd = 'dir /b "'..path..'"'
        else
            cmd = 'ls -A "'..path..'"'
        end
        local p = io.popen(cmd)
        if p then
            local out = {}
            for line in p:lines() do
                out[#out+1] = line
            end
            p:close()
            table.sort(out)
            return out
        end

        return {}
    end

    local basePaths = {"lib/data/Storys"}
    -- AppData・井ｿ晏ｭ倬伜沺・峨・縺ｾ縺・Lﾃ坊E 縺ｮ繝輔ぃ繧､繝ｫ繧ｷ繧ｹ繝・Β蜀・・逶ｸ蟇ｾ繝代せ繧貞━蜈医＠縺ｦ蜿ら・縺吶ｋ
    if love and love.filesystem and love.filesystem.getSaveDirectory then
        basePaths[#basePaths+1] = "ShiftLine/Storys"
    else
        local appdata = os.getenv("APPDATA") or os.getenv("HOME")
        if appdata then
            local appSongs = appdata .. "/ShiftLine/Storys"
            basePaths[#basePaths+1] = appSongs
        end
    end

    local sflfoldname = {}
    local sflpath = {}

    log.info('scratchsfl: scanning basePaths: '..table.concat(basePaths, ', '))
    for _, base in ipairs(basePaths) do
        local entries = listDir(base)
        for i = 1, #entries do
            local foldName = entries[i]
            local songPath = base .. "/" .. foldName
            local isDir = false

            local okInfo, info = pcall(love.filesystem.getInfo, songPath)
            if okInfo and info and info.type == "directory" then
                isDir = true
            else
                local okLfs, lfs = pcall(require, "lfs")
                if okLfs and lfs then
                    local attr = lfs.attributes(songPath)
                    if attr and attr.mode == "directory" then isDir = true end
                end
            end

            if isDir then
                local items = listDir(songPath)
                local chartPaths = {}
                for j = 1, #items do
                    local fname = items[j]
                    local lowerName = string.lower(fname)
                    if lowerName:match("%.sfs$") then
                        chartPaths[#chartPaths + 1] = songPath .. "/" .. fname
                    end
                end

                if #chartPaths > 0 then
                    for _, chartPath in ipairs(chartPaths) do
                        sflfoldname[#sflfoldname + 1] = foldName
                        sflpath[#sflpath + 1] = chartPath
                    end
                end
            elseif string.lower(foldName):match("%.sfs$") then
                -- 逶ｴ謗･ Storys 繝輔か繝ｫ繝蜀・↓ .sfs 縺後≠繧句ｴ蜷医ｂ蟇ｾ蠢・
                local chartPath = base .. "/" .. foldName
                sflfoldname[#sflfoldname + 1] = foldName:gsub("%.sfs$", "")
                sflpath[#sflpath + 1] = chartPath
            end
        end
    end

    local filelist = {}
    if #sflfoldname > 0 then
        for i = 1, #sflfoldname do
            local folderPath = "lib/data/Storys/" .. sflfoldname[i]
            local items = listDir(folderPath)
            table.sort(items)
            for _, item in ipairs(items) do
                if string.sub(item, -4) == ".sfs" then
                    filelist[#filelist + 1] = item
                end
            end
        end
    end
    scratchsfs.foldname, scratchsfs.list, scratchsfs.path= sflfoldname, filelist, sflpath
    log.info('scratchsfs: found ' .. tostring(#sflfoldname) .. ' stories, ' .. tostring(#sflpath) .. ' sfs paths')
end

-- 繝｢繧ｸ繝･繝ｼ繝ｫ縺ｨ縺励※繝・・繝悶Ν繧定ｿ斐☆
return scratchsfs, scratchsfs.foldname, scratchsfs.list, scratchsfs.path




