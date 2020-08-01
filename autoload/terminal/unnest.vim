" Interface {{{1
fu terminal#unnest#main() abort "{{{2
    " Why do you check this again?  We already did it in `plugin/terminal.vim`...{{{
    "
    " Just in case we call this function manually by accident.
    "}}}
    if !s:in_vim_terminal() | return | endif
    " This check is important.{{{
    "
    "    - we assume that Vim was invoked in a pipeline if the current buffer has no name
    "    - we fire `StdinReadPost` when we think Vim was invoked in a pipeline
    "    - we have an autocmd which runs `:cquit` when the latter is fired and the buffer is empty
    "
    " As a result, if you start Vim  with no argument in a Vim terminal, without
    " this  guard,  `:cquit` would  be  run  in the  outer  Vim  making it  quit
    " entirely.
    "
    " As a bonus, this  guard lets us start a nested Vim  instance, for the rare
    " case where  we would want  to study some bug  or Vim's behavior  when it's
    " nested.
    "}}}
    if s:nothing_to_read() | return | endif

    if s:vim_used_as_manpager()
        return s:open_manpage()
    endif

    let filelist = s:write_filepaths()
    let used_in_a_pipeline = s:called_by_vipe() || expand('%:p') is# ''
    call s:open_files(filelist)
    if used_in_a_pipeline
        call s:fire_stdinreadpost()
    endif

    " Why the delay?{{{
    "
    "     $ vim +term
    "     $ trans hedge | vipe
    "
    " The buffer which is opened in the outer Vim is empty.
    " Delaying `:qa!` fixes the issue.
    "}}}
    call timer_start(0, {-> execute('qa!')})
endfu
"}}}1
" Core {{{1
fu s:open_manpage() abort "{{{2
    let page = matchstr(expand('%:p'), 'man://\zs.*')
    " Why `json_encode()` instead of `string()`?{{{
    "
    " The man page must be surrounded by double quotes, not single quotes.
    "}}}
    call printf('%s]51;["call", "Tapi_man", %s]%s', "\033", json_encode(page), "\007")->echoraw()
    qa!
endfu

fu s:write_filepaths() abort "{{{2
    " handle `$ some cmd | vim -`
    if expand('%:p') is# ''
        let stdin = tempname()
        let files = [stdin]
        " Don't use `:w`.{{{
        "
        "     exe 'w '..stdin
        "
        " It would change the current buffer.
        " We want  the latter to be  unchanged, because we may  inspect its name
        " later, and check whether it's empty.
        "
        " Yes, we could  refactor the code so that it  doesn't happen *now*, but
        " it may  happen in the  future after  yet another refactoring;  IOW, it
        " would be too brittle.
        "}}}
        call writefile(getline(1, '$'), stdin)
    else
        let files = map(argv(), {_,v -> fnamemodify(v, ':p')})
    endif
    " Don't try to pass the file paths directly to the outer Vim.{{{
    "
    " It makes the code much more verbose.
    " Indeed, if there  are too many files, and the  OSC 51 sequence gets too long,
    " the command fails; the outer Vim doesn't open anything.
    " You have to split the command `:tab drop file1 file2 ...` into sth like:
    "
    "     :tab drop file1 ... file50
    "     :argadd file51 ...
    "     :argadd file101 ...
    "     ...
    "
    " So, you need a  while loop to iterate over the list  of files, and you
    " need an additional `Tapi_` function to execute `:argadd`.
    "}}}
    let filelist = tempname()
    call writefile(files, filelist)
    return filelist
endfu

fu s:open_files(filelist) abort "{{{2
    " to avoid error message due to swap files when opening files in the outer Vim
    " Why the bang?{{{
    "
    " To suppress `E89` which is raised when the current buffer is an unnamed one:
    "
    "     E89: No write since last change for buffer 1 (add ! to override)~
    "
    " It happens when Vim is used in a pipeline to read the output of another command:
    "
    "     $ some cmd | vim -
    "}}}
    %bd!
    " open files in the outer Vim instance using `:h terminal-api`
    call printf('%s]51;["call", "Tapi_drop", "%s"]%s', "\033", a:filelist, "\007")->echoraw()
endfu

fu s:fire_stdinreadpost() abort "{{{2
    " correctly highlight a buffer containing ansi escape sequences{{{
    "
    "     $ vim +term
    "     $ trans word 2>&1 | vipe >/dev/null
    "}}}
    call printf('%s]51;["call", "Tapi_exe", "do <nomodeline> StdinReadPost"]%s', "\033", "\007")->echoraw()
endfu
"}}}1
" Utilities {{{1
fu s:in_vim_terminal() abort "{{{2
    return !empty($VIM_TERMINAL)
endfu

fu s:nothing_to_read() abort "{{{2
    return line2byte(line('$')+1) <= 2
endfu

fu s:vim_used_as_manpager() abort "{{{2
    return expand('%:p') =~# '^\Cman://'
endfu

fu s:called_by_vipe() abort "{{{2
    return $_ =~# '\C/vipe$'
endfu

