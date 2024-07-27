local M = {}

-- IO redirection types
local PIPE_INHERIT = 1
local PIPE_CAPTURE = 2
local PIPE_DEVNULL = 3

M.PIPE_INHERIT = PIPE_INHERIT
M.PIPE_CAPTURE = PIPE_CAPTURE
M.PIPE_DEVNULL = PIPE_DEVNULL

-- escape shell argumengs
local function escape_and_join_tbl(args)
    local cmdline = {}

	--[[
	TODO this has a very confusing error message if you pass in a string
	instead of a table on accident
	lua: /usr/share/lua/5.4/subproc.lua:16: bad argument #1 to 'for iterator' (table expected, got string).
	This can happen with run_with or lines_with
	]]
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

        -- Add space to separate args, unless this is the first arg
        if #cmdline > 0 then
            table.insert(cmdline, ' ')
        end

        table.insert(cmdline, "'")
        table.insert(cmdline, (arg:gsub("'", "'\"'\"'")))
        table.insert(cmdline, "'")
    end

    -- remove leading space
    return table.concat(cmdline)
end

function M.escape_and_join(...)
    return escape_and_join_tbl({...})
end

-- convenience alias
M.esc = M.escape_and_join

--[[
Returns a `runner` which lets you have a bit more flexibility over how
running works.

    local runner = subproc.runner {
        log = nil | true | string | function,
        err = nil | true | function,

		TODO: want a way to pass a string as stdin
        stdin  = nil | PIPE_MODE | '/path/to/file'

        TODO: want a way to append to files
        stdout = nil | PIPE_MODE | '/path/to/file',
        stderr = nil | PIPE_MODE | '/path/to/file'
    }

    local output, exit_reason, exit_code = runner('some', 'command')

    for ln in runner.lines('some', 'command') do
        -- `ln` includes the trailing '\n'
    end
    local exit_reason, exit_code = run.last_exit()

#### `log`

when `log` is non-nil, all command output will be read from the child
process line by line, even if it's going to be returned as a single string
to your code.

When `log` is true, command output will be repeated to stdout with `print()`

When `log` is a string, command output will be repeated to stdout as with
`true`, but the string will be prepended as a prefix to each line

When `log` is a function, that function will be called with each lines of
input. This shares some functionality overlap with .lines(), but it's
intended to make it easy to pass in a custom logger function. The function
will be called with 2 arguments,

    log(line_of_output, cmd)

where `cmd` will the command that was passed to io.popen()

#### `err`

When `err` is true, the runner will call the lua stdlib error() function
if the process exits from a signal, or with a none-zero exit code.

When `err` is a function, the runner will call that function under the same
conditions:
    err(exit_reason, exit_code, cmd)

#### `stdin`, `stdout`, and `stderr`

io.popen is pretty limited in what it can do with stdin/stdout/stderr. We
can only capture the stdout stream of the procces, not stderr. we can choose
to write to the process's stdin, but if we do that we cannot read its
stdout.

But, we are just running a shell command after all, so we can use shell
redirects to work within these limitations.

These arguments all append shell IO redirections to the command passed in.
If you want to handle these redirections entirely yourself, here is what you
should do:

- Set `stdin` to `subproc.PIPE_INHERIT`
- Set `stdout` to `subproc.PIPE_CAPTURE`, or leave it as nil
- Set `stderr` to `subproc.PIPE_INHERIT`, or leave it as nil

This will ensure no redirections are added.

#### `stdin`

By default, `stdin` defaults to `subproc.PIPE_DEVNULL`:

    command < /dev/null

This is the default because giving your main process's stdin to your
subcommand is probably not what you intended. If you did intend that, you
can set `stdin` to `subproc.PIPE_INHERIT`, and the command will use your
process's stdin

    command

You can also set it to a filepath to direct stdin from the file at that path.

    command < /some/file

#### `stdout`

Usually when running commands, we want stdout. So, when stdout is `nil`,
we default to `subproc.PIPE_CAPTURE`.

If `stdout` is `subproc.PIPE_CAPTURE`, the command's stdout will be captured
and returned in the string output of the command. Note that if you also have
`stderr` set to PIPE_CAPTURE, your command output will have both stdout and
stderr mixed together into a single output stream.

If `stdout` is `subproc.PIPE_DEVNULL`, it will be redirected to /dev/null

If `stdout` is a filepath, stdout will be redirected to that file.

`subproc.PIPE_INHERIT` can be confusing here, so be careful. If `stdout` is
`subproc.PIPE_INHERIT`, we will execute the command with `os.execute()`
instead of `io.popen()`. This has two major implications:

1. There is no way to actually capture stderr when stdout is PIPE_INHERIT
2. If stderr is set to PIPE_CAPTURE, it will be redirected to the the
   inherited stdout.

As such, the `log` function will also never run, even if stderr is set to
capture, because capturing is impossible in this scenario.


#### `stderr`

`stderr` defaults to `subproc.PIPE_INHERIT`

If `stderr` is `subproc.PIPE_CAPTURE`, the process's stderr will captured
and returned in the string output of the command. Note that if you also have
`stdout` set to PIPE_CAPTURE, your command output will have both stdout and
stderr mixed together into a single output stream.

If `stderr` is `subproc.PIPE_DEVNULL`, it will be redirected to /dev/null

If `stderr` is a filepath, stderr will be redirected to that file.

If `stderr` is `subproc.PIPE_INHERIT`, stderr is not redirected at all, and
will this inherit the parent process's stderr. There are no strange caveats
with this the way there is for stdout's PIPE_INHERIT behavior.

]]
M.runner = function(args)
    local log = args.log
    local err = args.err
    local stdin = args.stdin
    local stdout = args.stdout
    local stderr = args.stderr

    -- TODO document this
    local drop_output = args.drop_output

    -- Construct the IO redirects as needed for stdin/stdout/stderr
    -- Start off with a spacer string to space our redirects away from the cmd
    local redirects = {' '}
    local inherit_stdout = false

    -- stdin
    if stdin == nil or stdin == PIPE_DEVNULL then
        table.insert(redirects, '</dev/null')
    elseif stdin == PIPE_INHERIT then
        -- Append nothing
    elseif stdin == PIPE_CAPTURE then
        error('cannot PIPE_CAPTURE stdin')
    elseif type(stdin) == 'string' then
        table.insert(redirects, '<' .. M.escape_and_join(stdin))
    end


    --[[
    stderr
    it's very important that this happen before stdout, because shell redirects
    are stateful. By redirecting stderr first, we can set it to the default
    value of stdout, and then change stdout.
    ]]
    if stderr == nil or stderr == PIPE_INHERIT then
        -- Append nothing
    elseif stderr == PIPE_CAPTURE then
        table.insert(redirects, '2>&1')
    elseif stderr == PIPE_DEVNULL then
        table.insert(redirects, '2>/dev/null')
    elseif type(stderr) == 'string' then
        table.insert(redirects, '2>'.. M.escape_and_join(stderr))
    end

    -- stdout
    if stdout == nil or stdout == PIPE_CAPTURE then
        -- Append nothing
    elseif stdout == PIPE_INHERIT then
        -- Append nothing BUT we need to switch to os.execute!!!
        inherit_stdout = true
    elseif stdout == PIPE_DEVNULL then
        table.insert(redirects, '>/dev/null')
    elseif type(stdout) == 'string' then
        table.insert(redirects, '>' .. M.escape_and_join(stdout))
    end

    local redirect_suffix = table.concat(redirects, ' ')

    -- Generate our error handler. It'll be a noop if `err` is nil.
    local err_type = type(err)
    if err == nil or err == false then
        -- no-op
        err = function()
        end

    elseif err_type == 'function' then
        -- nothing to do

	-- explicit `==` because we only want this to pass for booleans
    elseif err == true then
        -- default error handler
        err = function(exit_reason, exit_code, cmd)
            error(cmd .. ': cmd died by ' .. exit_reason .. ' with code ' .. exit_code)
        end

    else
        error('invalid value type for `err`: ' .. err_type)

    end

    -- Generate our log handler
    local log_type = type(log)
    if log == nil then
        -- do nothing!

	-- nil overrides can't pass through run_with, so false can do that.
    elseif log == false then
    	log = nil

    elseif log_type == 'string' then
        local prefix = log
        log = function(str)
            io.write(prefix)
            io.write(str)
            io.flush()
        end

	-- explicit `==` because we only want this to pass for booleans
    elseif log == true then
        log = function(str)
            io.write(str)
            io.flush()
        end

    elseif log_type == 'function' then
        -- leave the logger as it is

    else
        error('invalid value type for `log`: ' .. log_type)

    end

    -- Define these up in this scope so that we can return them with last_exit()
    local success, exit_reason, exit_code

    local runner = {}

    function runner.last_exit()
        return exit_reason, exit_code
    end

    --[[
    We'll change what shell() and lines() does depending on if we're inheriting
    stdout and if we're logging.

    Note that all of these set the success/exit_reason/exit_code variables
    defined above, that way a program can query them with last_exit()
    ]]
    if inherit_stdout then
        -- Simple os.execute() runner
        function runner.shell(cmd)
            success, exit_reason, exit_code = os.execute(cmd .. redirect_suffix)
            if not success then
                err(exit_reason, exit_code, cmd .. redirect_suffix)
            end
        end

        runner.shell_lines = function(cmd)
            runner.shell(cmd)

            -- We won't have any lines to return, but still return a valid
            -- iterator
            return coroutine.wrap(function()
            end)
        end

    elseif log then
        -- Collect output while logging it line by line. We can define shell()
        -- in terms of lines() for this one.
        function runner.shell(cmd)
            local output = {}
            for line in runner.shell_lines(cmd) do
                table.insert(output, line)
            end
            return table.concat(output), runner.last_exit()
        end

        function runner.shell_lines(cmd)
            local p = io.popen(cmd .. redirect_suffix, 'r')

            return coroutine.wrap(function()
                local ln = p:read('L')
                while ln do
                    log(ln)
                    coroutine.yield(ln)
                    ln = p:read('L')
                end

                success, exit_reason, exit_code = p:close()
                if not success then
                    err(exit_reason, exit_code, cmd .. redirect_suffix)
                end
            end)
        end

    else
        -- Read all input in one go. Ideal for reading lots of data into a
        -- buffer
        function runner.shell(cmd)
            local p = io.popen(cmd .. redirect_suffix, 'r')
            local output = p:read('a')
            success, exit_reason, exit_code = p:close()
            if not success then
                err(exit_reason, exit_code, cmd .. redirect_suffix)
            end
            return output, exit_reason, exit_code
        end

        -- works like the lines() when logging, but without the logging
        function runner.shell_lines(cmd)
            local p = io.popen(cmd .. redirect_suffix, 'r')

            return coroutine.wrap(function()
                local ln = p:read('L')
                while ln do
                    coroutine.yield(ln)
                    ln = p:read('L')
                end

                success, exit_reason, exit_code = p:close()
                if not success then
                    err(exit_reason, exit_code, cmd .. redirect_suffix)
                end
            end)
        end
    end

    if drop_output then
        -- Useful if you want to log stuff but you don't want to actually do
        -- anything with the output. No reason to buffer it in that case.
        runner.subproc = function(...)
            for ln in runner.shell_lines(M.escape_and_join(...)) do
            end
            return nil, runner.last_exit()
        end

        runner.lines = function(...)
            for ln in runner.shell_lines(M.escape_and_join(...)) do
            end
            return coroutine.wrap(function()
            end)
        end
    else
        -- normal behavior
        runner.subproc = function(...)
            return runner.shell(M.escape_and_join(...))
        end

        runner.lines = function(...)
            return runner.shell_lines(M.escape_and_join(...))
        end
    end

    --[[
    convenience, so we can do like

    require('subproc').runner { }

    without having to keep the original subproc ref around for escape
    ]]
    runner.escape_and_join = M.escape_and_join
    runner.esc = M.escape_and_join
    runner.PIPE_INHERIT = PIPE_INHERIT
    runner.PIPE_CAPTURE = PIPE_CAPTURE
    runner.PIPE_DEVNULL = PIPE_DEVNULL


    --[[
    A few shortcuts for instantiating a one-off runner with config slightly
    modified, and then running a command with it. Specify configuration as
    with runner(), but also specify a command as
        cmd = { 'some', 'args' }
    ]]
    function runner.extend(extra_args)
        local sub_args = {}
        for k, v in pairs(args) do
            sub_args[k] = v
        end
        for k, v in pairs(extra_args) do
            sub_args[k] = v
        end
        return M.runner(sub_args)
    end

    function runner.run_with(extra_args)
        assert(extra_args.cmd, 'no command provided in `cmd` variable')
        local r = runner.extend(extra_args)
        return r.shell(escape_and_join_tbl(extra_args.cmd))
    end

	-- TODO because of using extend(), we cannot get the exit code
    function runner.lines_with(extra_args)
        assert(extra_args.cmd, 'no command provided in `cmd` variable')
        local r = runner.extend(extra_args)
        return r.shell_lines(escape_and_join_tbl(extra_args.cmd))
    end

    setmetatable(runner, {__call = function (_, ...) return runner.subproc(...) end })

    return runner
end


-- Create a default runner, which maintains the original subproc behavior
local default_runner = M.runner {
    log = nil,
    err = nil,
    stdin = PIPE_INHERIT,
    stdout = PIPE_CAPTURE,
    stderr = PIPE_INHERIT
}

-- Define the toplevel functions from this runner
for k, v in pairs(default_runner) do
    if type(v) == 'function' then
        M[k] = v
    end
end

-- allow subproc() as shorthand for subproc.subproc
setmetatable(M, {__call = function (_, ...) return M.subproc(...) end })

return M
