vim9script noclear

if exists('loaded') | finish | endif
var loaded = true

# Interface {{{1
def terminal#unnest#main() #{{{2
    # Why do you check this again?  We already did it in `plugin/terminal.vim`...{{{
    #
    # Just in case we call this function manually by accident.
    #}}}
    if !InVimTerminal()
        return
    endif
    # This check is important.{{{
    #
    #    - we assume that Vim was invoked in a pipeline if the current buffer has no name
    #    - we fire `StdinReadPost` when we think Vim was invoked in a pipeline
    #    - we have an autocmd which runs `:cquit` when the latter is fired and the buffer is empty
    #
    # As a result, if you start Vim  with no argument in a Vim terminal, without
    # this  guard,  `:cquit` would  be  run  in the  outer  Vim  making it  quit
    # entirely.
    #
    # As a bonus, this  guard lets us start a nested Vim  instance, for the rare
    # case where  we would want  to study some bug  or Vim's behavior  when it's
    # nested.
    #}}}
    if NothingToRead()
        return
    endif

    if VimUsedAsManpager()
        return OpenManpage()
    endif

    var filelist: string = WriteFilepaths()
    var used_in_a_pipeline: bool = CalledByVipe() || expand('%:p') == ''
    OpenFiles(filelist)
    if used_in_a_pipeline
        FireStdinreadpost()
    endif

    # Why the delay?{{{
    #
    #     $ vim +terminal
    #     $ trans hedge | vipe
    #
    # The buffer which is opened in the outer Vim is empty.
    # Delaying `:quitall!` fixes the issue.
    #}}}
    timer_start(0, (_) => execute('quitall!'))
enddef
#}}}1
# Core {{{1
def OpenManpage() #{{{2
    var page: string = expand('%:p')->substitute('^man://', '', '')
    # Why `json_encode()` instead of `string()`?{{{
    #
    # The man page must be surrounded by double quotes, not single quotes.
    #}}}
    printf('%s]51;["call", "Tapi_man", %s]%s', "\033", json_encode(page), "\007")
        ->echoraw()
    quitall!
enddef

def WriteFilepaths(): string #{{{2
    # handle `$ some cmd | vim -`
    var files: list<string>
    if expand('%:p') == ''
        var stdin: string = tempname()
        files = [stdin]
        # Don't use `:write`.{{{
        #
        #     execute 'write ' .. stdin
        #
        # It would change the current buffer.
        # We want  the latter to be  unchanged, because we may  inspect its name
        # later, and check whether it's empty.
        #
        # Yes, we could  refactor the code so that it  doesn't happen *now*, but
        # it may  happen in the  future after  yet another refactoring;  IOW, it
        # would be too brittle.
        #}}}
        getline(1, '$')->writefile(stdin)
    else
        files = argv()->map((_, v: string): string => v->fnamemodify(':p'))
    endif
    # Don't try to pass the file paths directly to the outer Vim.{{{
    #
    # It makes the code much more verbose.
    # Indeed, if there  are too many files, and the  OSC 51 sequence gets too long,
    # the command fails; the outer Vim doesn't open anything.
    # You have to split the command `:tab drop file1 file2 ...` into sth like:
    #
    #     :tab drop file1 ... file50
    #     :argadd file51 ...
    #     :argadd file101 ...
    #     ...
    #
    # So, you need a  while loop to iterate over the list  of files, and you
    # need an additional `Tapi_` function to execute `:argadd`.
    #}}}
    var filelist: string = tempname()
    writefile(files, filelist)
    return filelist
enddef

def OpenFiles(filelist: string) #{{{2
    # to avoid error message due to swap files when opening files in the outer Vim
    try
        # Why the bang?{{{
        #
        # To suppress `E89` which is raised when the current buffer is an unnamed one:
        #
        #     E89: No write since last change for buffer 1 (add ! to override)˜
        #
        # It happens when Vim is used in a pipeline to read the output of another command:
        #
        #     $ some cmd | vim -
        #}}}
        :% bdelete!
    # E937: Attempt to delete a buffer that is in use: [NULL]
    # That might happen if there are popup windows.
    catch /^Vim\%((\a\+)\)\=:E937:/
    endtry
    # open files in the outer Vim instance using `:help terminal-api`
    printf('%s]51;["call", "Tapi_drop", "%s"]%s', "\033", filelist, "\007")
        ->echoraw()
enddef

def FireStdinreadpost() #{{{2
    # correctly highlight a buffer containing ansi escape sequences{{{
    #
    #     $ vim +terminal
    #     $ trans word 2>&1 | vipe >/dev/null
    #}}}
    printf('%s]51;'
        .. '["call", "Tapi_exe", "doautocmd <nomodeline> StdinReadPost"]'
        .. '%s', "\033", "\007")->echoraw()
enddef
#}}}1
# Utilities {{{1
def InVimTerminal(): bool #{{{2
    return !empty($VIM_TERMINAL)
enddef

def NothingToRead(): bool #{{{2
    return (line('$') + 1)->line2byte() <= 2
enddef

def VimUsedAsManpager(): bool #{{{2
    return expand('%:p') =~ '^\Cman://'
enddef

def CalledByVipe(): bool #{{{2
    return $_ =~ '\C/vipe$'
enddef

