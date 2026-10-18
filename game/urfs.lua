-- Copyright (C) 2022 Ross Grams
--
-- This module is free software; you can redistribute it and/or
-- modify it under the terms of the MIT license.

local M = {}

local ffi = require "ffi"
local C = ffi.os == "Windows" and ffi.load("love") or ffi.C

ffi.cdef[[
int          PHYSFS_mount(const char *newDir, const char *mountPoint, int appendToPath);
int          PHYSFS_unmount(const char *oldDir);
const char * PHYSFS_getWriteDir(void);
int          PHYSFS_setWriteDir(const char *newDir);
const char * PHYSFS_getLastError(void);
]]

local mountedAs = {}

local function getLastErrorMessage()
    local err = C.PHYSFS_getLastError()

    if err == nil then
        return "unknown PhysicsFS error"
    end

    return ffi.string(err)
end

function M.mount(archive, mountPoint, appendToPath)
    if C.PHYSFS_mount(
        archive,
        mountPoint,
        appendToPath and 1 or 0
    ) == 0 then
        return false, getLastErrorMessage()
    end

    if not mountedAs[archive] then
        mountedAs[archive] = mountPoint or ""
    end

    return true
end

function M.unmount(archive)
    if C.PHYSFS_unmount(archive) == 0 then
        return false, getLastErrorMessage()
    end

    mountedAs[archive] = nil

    return true
end

function M.getMountPoint(archive)
    return mountedAs[archive]
end

function M.setWriteDir(dir)
    if type(dir) ~= "string" or dir == "" then
        return false, "invalid write directory"
    end

    if C.PHYSFS_setWriteDir(dir) == 0 then
        return false, getLastErrorMessage()
    end

    return true
end

function M.getWriteDir()
    local r = C.PHYSFS_getWriteDir()

    if r == nil then
        return love.filesystem.getSaveDirectory()
    end

    return ffi.string(r)
end

return M