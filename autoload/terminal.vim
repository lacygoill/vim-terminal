import Catch from 'lg.vim'

const s:SFILE = expand('<sfile>:p')

" Interface {{{1
fu terminal#setup() abort "{{{2
    " TODO: Once Vim supports `ModeChanged`, get rid of `s:wrap()`.{{{
    "
    " Instead, refactor your autocmds to listen to `ModeChanged`.
    "
    " See: https://github.com/vim/vim/issues/2487#issuecomment-353735824
    " And `:h todo /modechanged`.
    "}}}
    nno <buffer><nowait> i <cmd>call <sid>wrap('i')<cr>
    nno <buffer><nowait> a <cmd>call <sid>wrap('a')<cr>

    nno <buffer><nowait> I <cmd>call <sid>wrap('I')<cr>
    nno <buffer><nowait> A <cmd>call <sid>wrap('A')<cr>

    nno <buffer><nowait> C <cmd>call <sid>wrap('C')<cr>
    nno <buffer><nowait> cc <cmd>call <sid>wrap('cc')<cr>

    " Let us paste a register like we would in a regular buffer (e.g. `"ap`).{{{
    "
    " In Vim, the sequence to press is awkward:
    "
    "    ┌─────┬───────────────────────────────────────────┐
    "    │ key │                  meaning                  │
    "    ├─────┼───────────────────────────────────────────┤
    "    │ i   │ enter Terminal-Job mode                   │
    "    ├─────┼───────────────────────────────────────────┤
    "    │ C-e │ move to the end of the shell command-line │
    "    ├─────┼───────────────────────────────────────────┤
    "    │ C-w │ or whatever key is set in 'termwinkey'    │
    "    ├─────┼───────────────────────────────────────────┤
    "    │ "   │ specify a register name                   │
    "    ├─────┼───────────────────────────────────────────┤
    "    │ x   │ name of the register to paste             │
    "    └─────┴───────────────────────────────────────────┘
    "
    " And  paste bracket  control codes  are not  inserted around  the register.
    " As a result, Vim automatically executes  any text whenever it encounters a
    " newline.  We don't want that; we just want to insert some text.
    "}}}
    nno <buffer><expr><nowait> p <sid>p()

    nno <buffer><nowait> D  i<c-k><c-\><c-n>
    nno <buffer><nowait> dd i<c-e><c-u><c-\><c-n>

    xno <buffer><nowait> c <nop>
    xno <buffer><nowait> d <nop>
    xno <buffer><nowait> p <nop>
    xno <buffer><nowait> x <nop>

    noremap <buffer><expr><nowait> [c brackets#move#regex('shell_prompt', 0)
    noremap <buffer><expr><nowait> ]c brackets#move#regex('shell_prompt', 1)
    sil! call repmap#make#repeatable(#{
        \ mode: '',
        \ buffer: 1,
        \ from: s:SFILE .. ':' .. expand('<sflnum>'),
        \ motions: [{'bwd': '[c', 'fwd': ']c'}]
        \ })

    " If `'termwinkey'` is not set, Vim falls back on `C-w`.  See `:h 'twk`.
    let twk = &l:twk == '' ? '<c-w>' : &l:twk
    " don't execute an inserted register when it contains a newline
    exe 'tno <buffer><expr><nowait> ' .. twk .. '" <sid>insert_register()'
    " we don't want a timeout when we press the termwinkey + `C-w` to focus the next window:
    " https://vi.stackexchange.com/a/24983/17449
    exe printf('tno <buffer><nowait> %s<c-w> %s<c-w>', twk , twk)

    " `ZF` and `mq` don't work on relative paths.{{{
    "
    " Solution1:
    "
    "     # in ~/.zshrc
    "     rg() {
    "       emulate -L zsh
    "       command rg -LS --vimgrep --color=auto $* $(pwd)
    "       #                                        ^----^
    "       #                        To get absolute paths.
    "       # See: https://github.com/BurntSushi/ripgrep/issues/958#issuecomment-404471289
    "     }
    "
    " Solution2: Install `ZF`/`mq` local  mappings, which are able  to parse the
    " cwd from the previous shell prompt.
    "
    " I prefer the  second solution, because I don't always  want absolute paths
    " in the shell, and because a smarter `ZF` is actually more powerful/useful;
    " it can help with any shell command, not just `rg(1)`.
    " E.g., you can press `ZF` on a file output by `$ ls`.
    "}}}
    let &l:inex = expand('<SID>') .. 'inex()'
    xno <buffer><nowait> mq <c-\><c-n><cmd>call <sid>mq()<cr>

    " Rationale:{{{
    "
    " Setting `'siso'` to a non-zero value is useless in a terminal buffer; long
    " lines are automatically hard-wrapped.
    " Besides, it makes the window's view "dance" when pressing `l` and reaching
    " the end of a long line, which is jarring.
    "
    " ---
    "
    " We  reset  `'so'` because  it  makes  moving  in  a terminal  buffer  more
    " consistent with tmux copy-mode.
    "}}}
    setl so=0 siso=0
    setl nowrap

    augroup term_preserve_cwd
        au! * <buffer>
        " Useful to preserve the local cwd after you've temporarily loaded a different buffer in the terminal window.{{{
        "
        " MWE:
        "
        "     $ cd
        "     $ vim
        "     :term
        "     $ cd /etc
        "     $ ls
        "     " press:  C-\ C-n
        "     " move onto the 'group' file
        "     " press:  gf
        "     " press:  C-^
        "     " move onto the 'hosts' file
        "     " press:  gf
        "     E447: Can't find file "/etc /hosts" in path~
        "}}}
        au BufWinLeave <buffer> let b:_cwd = getcwd()
        au BufWinEnter <buffer> if exists('b:_cwd') | exe 'lcd ' .. b:_cwd | endif
    augroup END

    if win_gettype() is# 'popup'
        call s:set_popup()
    endif
endfu

fu s:wrap(lhs) abort "{{{2
    try
        if a:lhs[0] =~? 'c'
            norm! i
        else
            exe 'norm! ' .. a:lhs[0]
        endif
    " Why?{{{
    "
    " When the job  associated to a terminal has finished,  pressing `i` doesn't
    " make you enter  Terminal-Job mode (there is no job  anymore); it makes you
    " enter insert mode.  The terminal buffer becomes a normal buffer.
    " However, it's not modifiable, so `i` raises `E21`.
    "
    " All of this is explained at `:h E947`.
    "}}}
    catch /^Vim\%((\a\+)\)\=:E21:/
        " I want to edit this kind of buffer!{{{
        "
        " Then replace the next `return` with sth like this:
        "
        "     nunmap <buffer> i
        "     nunmap <buffer> a
        "     ...
        "     setl ma
        "     startinsert
        "     return
        "
        " ---
        "
        " You would probably need to  refactor `#setup()` and `#setup_vim()`, so
        " that  they  expect  an  argument  telling  them  whether  they  should
        " customize the current terminal buffer or undo previous customizations.
        " This way, you could simply write sth like:
        "
        "     return terminal#setup('disable')
        "
        " Inside your function, for each setting  you apply when the buffer is a
        " terminal one, you would also have  a line undoing the setting for when
        " the buffer becomes normal:
        "
        "     if a:action is# 'enable'
        "         nno <buffer><nowait> D i<c-k><c-\><c-n>
        "         ...
        "     elseif a:action is# 'disable'
        "         nunmap <buffer> D
        "         ...
        "     endif
        "}}}
        return s:Catch()
    endtry
    " Why does `TermEnter` need to be fired?{{{
    "
    " We have  a few autocmds  which listen to this  event to detect  that we've
    " switched from Terminal-Normal mode to Terminal-Job mode.
    "
    " ---
    "
    " It also fixes another issue.
    " In  a popup  terminal, if  you press  `i` while  in the  middle of  a long
    " scrollback buffer (e.g. `$ infocmp -1x`), Vim doesn't move the cursor back
    " to the bottom.
    " This leads to an unexpected screen: it doesn't display the end of the last
    " shell command (like what would happen in a normal terminal), and the shell
    " prompt is not visible until you insert a character.
    "}}}
    " Why not `CursorMoved`?{{{
    "
    " It's an unreliable proxy event.
    " It's fired  most of the time when we enter terminal-job mode, but not always.
    " For example, it's not fired when we're on the last line of the terminal buffer.
    "
    " Besides, using `CursorMoved` here means that  we would need to do the same
    " in any  autocmd whose purpose  is to  execute a command  when Terminal-Job
    " mode  is  entered.  But  `CursorMoved`  can  be  fired too  frequently  in
    " Terminal-Normal mode; so  our autocmds could be executed  too often (which
    " may have an impact even with a guard such as `if mode() is# 't'`).
    "}}}
    call s:fire_termenter()
    if a:lhs ==# 'i' || a:lhs ==# 'a'
        return
    endif
    if a:lhs ==# 'C'
        let startofline = term_getline('', '.')
            \ ->matchstr('٪ \zs.*\%' .. col('.') .. 'c')
        call term_sendkeys('', "\<c-e>\<c-u>" .. startofline)
        return
    endif
    let keys = #{
        \ I: "\<c-a>",
        \ A: "\<c-e>",
        \ cc: "\<c-e>\<c-u>",
        \ }[a:lhs]
    call term_sendkeys('', keys)
endfu

fu terminal#fire_termleave() abort "{{{2
    if exists('#User#TermLeave')
        do <nomodeline> User TermLeave
    endif
endfu
"}}}1
" Core {{{1
fu s:inex() abort "{{{2
    let cwd = s:getcwd()
    " most of the code is leveraged from a similar function in our vimrc
    let line = getline('.')
    let pat = '\m\C${\f\+}' .. '\V' .. v:fname .. '\m\|${\V' .. v:fname .. '}\f\+\|\%' .. col('.') .. 'c${\f\+}\f\+'
    let cursor_after = '\m\%(.*\%' .. col('.') .. 'c\)\@='
    let cursor_before = '\m\%(\%' .. col('.') .. 'c.*\)\@<='
    let pat = cursor_after .. pat .. cursor_before
    if line =~# pat
        let pat = matchstr(line, pat)
        let env = matchstr(pat, '\w\+')
        return substitute(pat, '${' .. env .. '}', eval('$' .. env), '')
    elseif line =~# cursor_after .. '=' .. cursor_before
        return substitute(v:fname, '.*=', '', '')
    elseif line =~# '^\./'
        return substitute(v:fname, '^\./', cwd, '')
    else
        return cwd .. v:fname
    endif
endfu

fu s:insert_register() abort "{{{2
    let numeric = range(10)
    let alpha = range(char2nr('a'), char2nr('z'))->map('nr2char(v:val)')
    let other = ['-', '*', '+', '/', '=']
    let reg = getchar()->nr2char()
    if index(numeric + alpha + other, reg) == -1
        return ''
    endif
    call s:use_bracketed_paste(reg)
    let twk = &l:twk == '' ? "\<c-w>" : eval('"\' .. &l:twk .. '"')
    return twk .. '"' .. reg
endfu

fu s:mq() abort "{{{2
    let cwd = s:getcwd()
    let [lnum1, lnum2] = [line("'<"), line("'>")]
    let lines = getline(lnum1, lnum2)->map({_, v -> cwd .. v})
    call setqflist([], ' ', {'lines': lines, 'title': ':' .. lnum1 .. ',' .. lnum2 .. 'cgetbuffer'})
    cw
endfu

fu s:p() abort "{{{2
    let reg = v:register
    call s:use_bracketed_paste(reg)
    let twk = &l:twk == '' ? "\<c-w>" : eval('"\' .. &l:twk .. '"')
    call s:fire_termenter()
    return "i\<c-e>" .. twk .. '"' .. reg
endfu

fu s:set_popup() abort "{{{2
    " Like for  all local options,  the local  value of `'termwinkey'`  has been
    " reset to its default value (empty string), which makes Vim use `C-w`.
    " Set the option  again, so that we  get the same experience  as in terminal
    " buffers in non-popup windows.
    set twk<

    " suppress error: Vim(wincmd):E994: Not allowed in a popup window
    nno <buffer><nowait> <c-h> <nop>
    nno <buffer><nowait> <c-j> <nop>
    nno <buffer><nowait> <c-k> <nop>
    nno <buffer><nowait> <c-l> <nop>
endfu
"}}}1
" Utilities {{{1
fu s:fire_termenter() abort "{{{2
    if exists('#User#TermEnter') | do <nomodeline> User TermEnter | endif
endfu

fu s:getcwd() abort "{{{2
    let cwd = (search('^٪', 'bnW') - 1)->getline()
    let cwd = substitute(cwd, '\s*\%(\[\d\+\]\)\=\s*$', '', '')
    " Warning: in the future, we may define other named directories in our zshrc.
    " Warning: `1000` may be the wrong UID.  We should inspect `$UID` but it's not in the environment.
    let cwd = substitute(cwd, '^\~tmp', '/run/user/1000/tmp', '')
    let cwd = substitute(cwd, '^\~xdcc', $HOME .. '/Dowloads/XDCC', '')
    return cwd .. '/'
endfu

fu s:use_bracketed_paste(reg) abort "{{{2
    " don't execute anything, even if the register contains newlines
    let reginfo = getreginfo(a:reg)
    let save = deepcopy(reginfo)
    if get(reginfo, 'regcontents', [])->len() > 1
        let [before, after] = [&t_PS, &t_PE]
        let reginfo.regcontents[0] = before .. reginfo.regcontents[0]
        let reginfo.regcontents[-1] ..= after
        " Don't use the `'l'` or `'V'` type.  It would cause the automatic execution of the pasted command.
        let reginfo.regtype = 'c'
        call setreg(a:reg, reginfo)
        call timer_start(0, {-> setreg(a:reg, save)})
    endif
endfu

