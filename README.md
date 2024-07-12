Wrapper around `io.popen()`/`os.execute()` designed to make these functions
easier to use safely. Only useable on unix systems- won't do anything that
makes sense on windows.

These stdlib functions have some inherent limitations. If you find yourself
running into those limits, you should go use
[luaposix](https://luaposix.github.io/luaposix/modules/posix.html), which has a
much more powerful set of tools for launching child processes, including the
ability to create pipelines of processes.

## install

```
luarocks install subproc
```

## simple usage

```
local subproc = require 'subproc'

local output, exit_reason, status = subproc('ls', '-l', '/')
print(output, exit_reason, status)
```

you can also use `io.popen(subproc.escape_and_join('command', 'arg1', 'arg2...'))` to safely implement anything that popen can do but this library can't.


## basic exported functions

- `subproc.escape_and_join(...)`: tostring() and shell-escape all arguments,
  then join them with spaces. output is suitable to provide to `io.popen` or
  `os.execute`.
  - alias: `subproc.esc()`
- `subproc.shell(cmdline)`: passes `cmdline` to `io.popen` and captures output.
  returns `output, exit_reason, status` where `exit_reason, status` come from
  `io.close()`
- `subproc.subproc(...)`: escapes all arguments with `subproc.escape_and_join`,
  and runs with `subproc.shell`.
- `subproc(...)`: alias of `subproc.subproc`
- `subproc.lines(...)`: escapes all arguments, returns an iterator over lines.
  The iterator receives each line with the trailing newline still attached.
- `subproc.last_exit()`: Returns the exit code of the last command that finished
  running. Useful to get the exit code of a command after consuming all the
  lines from `subproc.lines()`. Do be careful with this one though. If you find
  yourself launching multiple processes in parallel, and you need their exit
  statuses, go use `popen` manually instead of using this function.


## custom runners

All the top level functions in `subproc` are actually functions of the default
subproc runner. You can create custom runners that do different things with
stdin/stdout/stderr, or do automatic error handling,

- `subproc.runner()`: Create a custom runner. Docs for this are extensive, so
  see them below this function list.
- `runner.extend(conf)`: Create a custom runner, inheriting the config of the
  source runner and overriding it with new values in `conf`
- `runner.run_with(conf)`: Creates a new runner with `runner.extend`, and then
  runs the command specified by the table `conf.cmd`
- `runner.lines_with(conf)`: Creates a new runner with `runner.extend`, and then
  runs the command specified by the table `conf.cmd`. Returns an iterator over
  the lines


### `subproc.runner()`

Returns a `runner` which lets you have a bit more flexibility over how
running works.

    local runner = subproc.runner {
        log = nil | true | string | function,
        err = nil | true | function,

        stdin  = nil | PIPE_MODE | '/path/to/file'
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

