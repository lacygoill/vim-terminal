" Interface {{{1
fu terminal#setup() abort "{{{2
    " in this function, put settings which should be applied both in Vim and Nvim

    nno <buffer><nowait><silent> D  i<c-k><c-\><c-n>
    nno <buffer><nowait><silent> dd i<c-e><c-u><c-\><c-n>

    xno <buffer><nowait><silent> c <nop>
    xno <buffer><nowait><silent> d <nop>
    xno <buffer><nowait><silent> p <nop>
    xno <buffer><nowait><silent> x <nop>

    noremap <buffer><expr><nowait><silent> [c lg#motion#rhs('shell_prompt', 0)
    noremap <buffer><expr><nowait><silent> ]c lg#motion#rhs('shell_prompt', 1)
    sil! call repmap#make#all({
        \ 'mode': '',
        \ 'buffer': 1,
        \ 'from': expand('<sfile>:p')..':'..expand('<slnum>'),
        \ 'motions': [{'bwd': '[c',  'fwd': ']c'}]})

    " `ZF` and `mq` don't work on relative paths.{{{
    "
    " Solution1:
    "
    "     # in ~/.zshrc
    "     rg() {
    "       emulate -L zsh
    "       command rg -LS --vimgrep --color=auto $* $(pwd)
    "       #                                        ^^^^^^
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
    let &l:inex = s:snr..'inex()'
    xno <buffer><nowait><silent> mq :<c-u>call <sid>mq()<cr>
endfu

fu terminal#setup_neovim() abort "{{{2
    augroup terminal_disable_scrolloff
        au! * <buffer>
        au WinEnter <buffer> set so=0 siso=0
        let [_so, _siso] = [&so, &siso]
        exe 'au WinLeave <buffer> set so='.._so..' siso='.._siso
    augroup END

    nno <buffer><nowait><silent> I  I<c-a>
    nno <buffer><nowait><silent> A  A<c-e>
    nno <buffer><nowait><silent> C  i<c-k>
    nno <buffer><nowait><silent> cc i<c-e><c-u>
endfu

fu terminal#setup_vim() abort "{{{2
    " Neovim automatically disables `'wrap'` in a terminal buffer.
    " Not Vim. We do it in this function.
    setl nowrap
    " Rationale:{{{
    "
    " Setting `'siso'` to a non-zero value is useless in a terminal buffer; long
    " lines are automatically hard-wrapped.
    " Besides, it makes the window's view "dance" when pressing `l` and reaching
    " the end of a long line, which is jarring.
    "
    " ---
    "
    " We reset `'so'` because:
    "
    "    - it makes moving in a terminal buffer more consistent with tmux copy-mode
    "
    "    - it fixes an issue where the terminal flickers in Terminal-Job mode
    "      (the issue only affects Nvim, but let's be consistent between Vim and Nvim)
    "
    "    - it could prevent other issues in the future (be it in Vim or in Nvim)
    "
    " ---
    "
    " Here's a MWE of the issue where the terminal flickers:
    "
    "     $ nvim -Nu NONE +'set so=3 | 10sp | term' +'startinsert'
    "     # press C-g C-g Esc
    "     # insert some random characters
    "     # the terminal window flickers
    "
    " Imo, it's a bug:
    " https://github.com/neovim/neovim/issues/11072#issuecomment-533828802
    " But the devs closed the issue.
    "
    " There may be other similar issues:
    " https://github.com/neovim/neovim/search?q=terminal+scrolloff&type=Issues
    "}}}
    " TODO: When the PR #11854 is merged in Nvim, move this line in `#setup()`.{{{
    "
    " This way, it will be applied both in Vim and in Nvim.
    " Also, remove the autocmd `terminal_disable_scrolloff`; it will be useless then.
    "}}}
    setl so=0 siso=0
    " Here, `'termwinkey'` seems to behave a little like `C-r` in insert mode.
    " With one difference though: when specifying the register, you need to prefix it with `"`.
    exe 'nnoremap <buffer><nowait><silent> p i<c-e>'..&l:termwinkey..'""'

    " TODO: Once Vim supports `ModeChanged`, get rid of `s:fire_termenter()`.{{{
    "
    " Instead, refactor your autocmds to listen to `ModeChanged`.
    "
    " See: https://github.com/vim/vim/issues/2487#issuecomment-353735824
    " And `:h todo /modechanged`.
    "}}}
    nno <buffer><nowait><silent> i :<c-u>call <sid>fire_termenter('i')<cr>
    nno <buffer><nowait><silent> a :<c-u>call <sid>fire_termenter('a')<cr>

    nno <buffer><nowait><silent> I :<c-u>call <sid>fire_termenter('I<c-v><c-a>')<cr>
    nno <buffer><nowait><silent> A :<c-u>call <sid>fire_termenter('A<c-v><c-e>')<cr>

    nno <buffer><nowait><silent> C  :<c-u>call <sid>fire_termenter('i<c-v><c-k>')<cr>
    nno <buffer><nowait><silent> cc :<c-u>call <sid>fire_termenter('i<c-v><c-e><c-v><c-u>')<cr>

    " suppress error: Vim(wincmd):E994: Not allowed in a popup window
    if win_gettype() is# 'popup'
        nno <buffer><nowait> <c-h> <nop>
        nno <buffer><nowait> <c-j> <nop>
        nno <buffer><nowait> <c-k> <nop>
        nno <buffer><nowait> <c-l> <nop>
    endif
endfu

fu s:fire_termenter(rhs) abort "{{{2
    try
        exe 'norm! '..a:rhs[0]
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
        "         nno <buffer><nowait><silent> D i<c-k><c-\><c-n>
        "         ...
        "     elseif a:action is# 'disable'
        "         nunmap <buffer> D
        "         ...
        "     endif
        "
        " ---
        "
        " Warning: I don't think you can edit a terminal buffer in Nvim once its
        " job has finished.  IOW, allowing that in Vim will be inconsistent with
        " Nvim.
        "}}}
        return lg#catch_error()
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
    if exists('#User#TermEnter') | do <nomodeline> User TermEnter | endif
    if len(a:rhs) == 1 | return | endif
    call term_sendkeys('', a:rhs[1:])
endfu

fu terminal#fire_termleave() abort "{{{2
    if exists('#User#TermLeave')
        do <nomodeline> User TermLeave
    endif
endfu
"}}}1
" Utilities {{{1

fu s:snr() abort "{{{2
    return matchstr(expand('<sfile>'), '.*\zs<SNR>\d\+_')
endfu
let s:snr = get(s:, 'snr', s:snr())

