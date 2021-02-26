local M = {}

-- escape shell argumengs
M.escape_and_join = function(...)
    local args = {...}
    local cmdline = ''

    for _, arg in pairs(args) do
        arg = tostring(arg)

        -- sh doesn't have any escape sequences inside single quotes, so we can
        -- wrap each arg in single-quotes to make sure it gets passed how we like.
        --
        -- however, we first need to escape single-quotes so the argument doesnt get
        -- split up.
        --
        -- this is an escaped quote in sh: '"'"'
        --
        -- the way this works is, 
        --   - the first single-quote closes the current string
        --   - then we have a double-quote string containing a single-quote
        --   - the final single-quote opens a new string
        --   - because there are no spaces, sh will concatenate them into one
        --     string argument
        --
        -- this gets a little more absurd because we need to write the escaped
        -- quote inside a lua string. so the lua string is "'\"'\"'"
        arg = "'" .. arg:gsub("'", "'\"'\"'") .. "'"

        cmdline = cmdline .. ' ' .. arg
    end

    -- remove leading space
    return cmdline:sub(2)
end

M.shell = function(cmd)
    local p = io.popen(cmd, 'r')
    local output = p:read('*a')
    local _, exit_reason, status = p:close()
    return output, exit_reason, status
end

M.subproc = function(...)
    return M.shell(M.escape_and_join(...))
end

-- allow subproc() as shorthand for subproc.subproc
setmetatable(M, {__call = function (_, ...) return M.subproc(...) end })

return M
