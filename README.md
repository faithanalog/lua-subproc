simple usage:

```
subproc = require 'subproc'

local output, exit_reason, status = subproc('ls', '-l', '/')
print(output)
```

exported functions:

- `subproc.escape_and_join(...)`: tostring() and shell-escape all arguments,
  then join them with spaces. output is suitable to provide to `io.popen` or
  `os.execute`.
- `subproc.shell(cmdline)`: passes `cmdline` to `io.popen` and captures output.
  returns `output, exit_reason, status` where `exit_reason, status` come from
  `io.close()`
- `subproc.subproc(...)`: escapes all arguments with `subproc.escape_and_join`,
  and runs with `subproc.shell`.
- `subproc(...)`: alias of `subproc.subproc`

planned features:

I'd like to add things in future to allow providing stdin, or interactive use
with coroutines
