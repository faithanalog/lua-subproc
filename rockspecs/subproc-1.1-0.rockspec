package = 'subproc'
version = '1.1-0'
source = {
    url = 'git://github.com/faithanalog/lua-subproc.git',
    tag = 'v1.1-0'
}
description = {
    summary = 'execute system commands with escaped arguments',
    homepage = 'https://github.com/faithanalog/lua-subproc',
    maintainer = 'Artemis Everfree',
    license = 'MIT'
}
supported_platforms = { 
	"unix", 
}
dependencies = {
    'lua >= 5.1'
}
build = {
    type = 'builtin',
    modules = {
        subproc = 'subproc.lua'
    }
}
