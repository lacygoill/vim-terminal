vim9 noclear

if exists('loaded') | finish | endif
var loaded = true

import Catch from 'lg.vim'
const SFILE = expand('<sfile>:p')

# Interface {{{1
def terminal#setup() #{{{2
    # TODO: Once Vim supports `ModeChanged`, get rid of `Wrap()`.{{{
    #
    # Instead, refactor your autocmds to listen to `ModeChanged`.
    #
    # See: https://github.com/vim/vim/issues/2487#issuecomment-353735824
    # And `:h todo /modechanged`.
    #}}}
    nno <buffer><nowait> i <cmd>call <sid>Wrap('i')<cr>
    nno <buffer><nowait> a <cmd>call <sid>Wrap('a')<cr>

    nno <buffer><nowait> I <cmd>call <sid>Wrap('I')<cr>
    nno <buffer><nowait> A <cmd>call <sid>Wrap('A')<cr>

    nno <buffer><nowait> C <cmd>call <sid>Wrap('C')<cr>
    nno <buffer><nowait> cc <cmd>call <sid>Wrap('cc')<cr>

    # Let us paste a register like we would in a regular buffer (e.g. `"ap`).{{{
    #
    # In Vim, the sequence to press is awkward:
    #
    #    ┌─────┬───────────────────────────────────────────┐
    #    │ key │                  meaning                  │
    #    ├─────┼───────────────────────────────────────────┤
    #    │ i   │ enter Terminal-Job mode                   │
    #    ├─────┼───────────────────────────────────────────┤
    #    │ C-e │ move to the end of the shell command-line │
    #    ├─────┼───────────────────────────────────────────┤
    #    │ C-w │ or whatever key is set in 'termwinkey'    │
    #    ├─────┼───────────────────────────────────────────┤
    #    │ "   │ specify a register name                   │
    #    ├─────┼───────────────────────────────────────────┤
    #    │ x   │ name of the register to paste             │
    #    └─────┴───────────────────────────────────────────┘
    #
    # And  paste bracket  control codes  are not  inserted around  the register.
    # As a result, Vim automatically executes  any text whenever it encounters a
    # newline.  We don't want that; we just want to insert some text.
    #}}}
    nno <buffer><expr><nowait> p <sid>Put()

    nno <buffer><nowait> D  <cmd>call <sid>KillLine()<cr>
    nno <buffer><nowait> dd i<c-e><c-u><c-\><c-n>

    xno <buffer><nowait> c <nop>
    xno <buffer><nowait> d <nop>
    xno <buffer><nowait> p <nop>
    xno <buffer><nowait> x <nop>

    noremap <buffer><expr><nowait> [c brackets#move#regex('shell_prompt', 0)
    noremap <buffer><expr><nowait> ]c brackets#move#regex('shell_prompt', 1)
    sil! repmap#make#repeatable({
        mode: '',
        buffer: true,
        from: SFILE .. ':' .. expand('<sflnum>'),
        motions: [{bwd: '[c', fwd: ']c'}]
        })

    # If `'termwinkey'` is not set, Vim falls back on `C-w`.  See `:h 'twk`.
    var twk = &l:twk == '' ? '<c-w>' : &l:twk
    # don't execute an inserted register when it contains a newline
    exe 'tno <buffer><expr><nowait> ' .. twk .. '" <sid>InsertRegister()'
    # we don't want a timeout when we press the termwinkey + `C-w` to focus the next window:
    # https://vi.stackexchange.com/a/24983/17449
    exe printf('tno <buffer><nowait> %s<c-w> %s<c-w>', twk, twk)

    # `ZF` and `mq` don't work on relative paths.{{{
    #
    # Solution1:
    #
    #     # in ~/.zshrc
    #     rg() {
    #       emulate -L zsh
    #       command rg -LS --vimgrep --color=auto $* $(pwd)
    #       #                                        ^----^
    #       #                        To get absolute paths.
    #       # See: https://github.com/BurntSushi/ripgrep/issues/958#issuecomment-404471289
    #     }
    #
    # Solution2: Install `ZF`/`mq` local  mappings, which are able  to parse the
    # cwd from the previous shell prompt.
    #
    # I prefer the  second solution, because I don't always  want absolute paths
    # in the shell, and because a smarter `ZF` is actually more powerful/useful;
    # it can help with any shell command, not just `rg(1)`.
    # E.g., you can press `ZF` on a file output by `$ ls`.
    #}}}
    &l:inex = expand('<SID>') .. 'Inex()'
    xno <buffer><nowait> mq <c-\><c-n><cmd>call <sid>SelectionToQf()<cr>

    # Rationale:{{{
    #
    # Setting `'siso'` to a non-zero value is useless in a terminal buffer; long
    # lines are automatically hard-wrapped.
    # Besides, it makes the window's view "dance" when pressing `l` and reaching
    # the end of a long line, which is jarring.
    #
    # ---
    #
    # We  reset  `'so'` because  it  makes  moving  in  a terminal  buffer  more
    # consistent with tmux copy-mode.
    #}}}
    setl so=0 siso=0
    setl nowrap

    augroup TermPreserveCwd
        au! * <buffer>
        # Useful to preserve the local cwd after you've temporarily loaded a different buffer in the terminal window.{{{
        #
        # MWE:
        #
        #     $ cd
        #     $ vim
        #     :term
        #     $ cd /etc
        #     $ ls
        #     " press:  C-\ C-n
        #     " move onto the 'group' file
        #     " press:  gf
        #     " press:  C-^
        #     " move onto the 'hosts' file
        #     " press:  gf
        #     E447: Can't find file "/etc /hosts" in path~
        #}}}
        au BufWinLeave <buffer> b:_cwd = getcwd()
        au BufWinEnter <buffer> if exists('b:_cwd') | exe 'lcd ' .. b:_cwd | endif
    augroup END

    if win_gettype() == 'popup'
        SetPopup()
    endif
enddef

def Wrap(lhs: string) #{{{2
    try
        if lhs[0] =~? 'c'
            norm! i
        else
            exe 'norm! ' .. lhs[0]
        endif
    # Why?{{{
    #
    # When the job  associated to a terminal has finished,  pressing `i` doesn't
    # make you enter  Terminal-Job mode (there is no job  anymore); it makes you
    # enter insert mode.  The terminal buffer becomes a normal buffer.
    # However, it's not modifiable, so `i` raises `E21`.
    #
    # All of this is explained at `:h E947`.
    #}}}
    catch /^Vim\%((\a\+)\)\=:E21:/
        # I want to edit this kind of buffer!{{{
        #
        # Then replace the next `return` with sth like this:
        #
        #     nunmap <buffer> i
        #     nunmap <buffer> a
        #     ...
        #     setl ma
        #     startinsert
        #     return
        #
        # ---
        #
        # You would probably need to  refactor `#setup()` and `#setup_vim()`, so
        # that  they  expect  an  argument  telling  them  whether  they  should
        # customize the current terminal buffer or undo previous customizations.
        # This way, you could simply write sth like:
        #
        #     return terminal#setup('disable')
        #
        # Inside your function, for each setting  you apply when the buffer is a
        # terminal one, you would also have  a line undoing the setting for when
        # the buffer becomes normal:
        #
        #     if action == 'enable'
        #         nno <buffer><nowait> D i<c-k><c-\><c-n>
        #         ...
        #     elseif action == 'disable'
        #         nunmap <buffer> D
        #         ...
        #     endif
        #}}}
        Catch()
        return
    endtry
    # Why does `TermEnter` need to be fired?{{{
    #
    # We have  a few autocmds  which listen to this  event to detect  that we've
    # switched from Terminal-Normal mode to Terminal-Job mode.
    #
    # ---
    #
    # It also fixes another issue.
    # In  a popup  terminal, if  you press  `i` while  in the  middle of  a long
    # scrollback buffer (e.g. `$ infocmp -1x`), Vim doesn't move the cursor back
    # to the bottom.
    # This leads to an unexpected screen: it doesn't display the end of the last
    # shell command (like what would happen in a normal terminal), and the shell
    # prompt is not visible until you insert a character.
    #}}}
    # Why not `CursorMoved`?{{{
    #
    # It's an unreliable proxy event.
    # It's fired  most of the time when we enter terminal-job mode, but not always.
    # For example, it's not fired when we're on the last line of the terminal buffer.
    #
    # Besides, using `CursorMoved` here means that  we would need to do the same
    # in any  autocmd whose purpose  is to  execute a command  when Terminal-Job
    # mode  is  entered.  But  `CursorMoved`  can  be  fired too  frequently  in
    # Terminal-Normal mode; so  our autocmds could be executed  too often (which
    # may have an impact even with a guard such as `if mode() == 't'`).
    #}}}
    FireTermenter()
    if lhs == 'i' || lhs == 'a'
        return
    endif
    if lhs == 'C'
        var startofline = term_getline('', '.')
            ->matchstr('٪ \zs.*\%' .. col('.') .. 'c')
        term_sendkeys('', "\<c-e>\<c-u>" .. startofline)
        return
    endif
    var keys = {
        I: "\<c-a>",
        A: "\<c-e>",
        cc: "\<c-e>\<c-u>",
        }[lhs]
    term_sendkeys('', keys)
enddef

def terminal#fireTermleave() #{{{2
    if exists('#User#TermLeave')
        do <nomodeline> User TermLeave
    endif
enddef
#}}}1
# Core {{{1
def KillLine() #{{{2
    var buf = bufnr('%')
    var vimpos = getcurpos()
    var jobpos = term_getcursor(buf)
    var offcol = jobpos[1] - vimpos[2]
    var offline = jobpos[0] - vimpos[1]
    norm! i
    var keys = repeat("\<left>", offcol)
        .. repeat("\<up>", offline)
        .. "\<c-k>"
    term_sendkeys(buf, keys)
    term_wait(buf, 50)
    feedkeys("\<c-\>\<c-n>", 'nx')
enddef

def Inex(): string #{{{2
    var cwd = Getcwd()
    # most of the code is leveraged from a similar function in our vimrc
    var line = getline('.')
    var pat = '${\f\+}' .. '\V' .. v:fname .. '\m'
        .. '\|${\V' .. v:fname .. '}\f\+'
        .. '\|\%' .. col('.') .. 'c${\f\+}\f\+'
    var cursor_after = '\m\%(.*\%' .. col('.') .. 'c\)\@='
    var cursor_before = '\m\%(\%' .. col('.') .. 'c.*\)\@<='
    pat = cursor_after .. pat .. cursor_before
    if line =~ pat
        pat = matchstr(line, pat)
        var env = matchstr(pat, '\w\+')
        return substitute(pat, '${' .. env .. '}', eval('$' .. env), '')
    elseif line =~ cursor_after .. '=' .. cursor_before
        return substitute(v:fname, '.*=', '', '')
    elseif line =~ '^\./'
        return substitute(v:fname, '^\./', cwd, '')
    else
        return cwd .. v:fname
    endif
enddef

def InsertRegister(): string #{{{2
    var numeric = range(10)
    var alpha = range(char2nr('a'), char2nr('z'))->map('nr2char(v:val)')
    var other = ['-', '*', '+', '/', '=']
    var reg = getchar()->nr2char()
    if index(numeric + alpha + other, reg) == -1
        return ''
    endif
    UseBracketedPaste(reg)
    var twk = &l:twk == '' ? "\<c-w>" : eval('"\' .. &l:twk .. '"')
    return twk .. '"' .. reg
enddef

def SelectionToQf() #{{{2
    var cwd = Getcwd()
    var lnum1 = line("'<")
    var lnum2 = line("'>")
    var lines = getline(lnum1, lnum2)->map((_, v) => cwd .. v)
    setqflist([], ' ', {lines: lines, title: ':' .. lnum1 .. ',' .. lnum2 .. 'cgetbuffer'})
    cw
enddef

def Put(): string #{{{2
    var reg = v:register
    UseBracketedPaste(reg)
    var twk = &l:twk == '' ? "\<c-w>" : eval('"\' .. &l:twk .. '"')
    FireTermenter()
    return "i\<c-e>" .. twk .. '"' .. reg
enddef

def SetPopup() #{{{2
    # Like for  all local options,  the local  value of `'termwinkey'`  has been
    # reset to its default value (empty string), which makes Vim use `C-w`.
    # Set the option  again, so that we  get the same experience  as in terminal
    # buffers in non-popup windows.
    set twk<

    # suppress error: "Vim(wincmd):E994: Not allowed in a popup window"
    nno <buffer><nowait> <c-h> <nop>
    nno <buffer><nowait> <c-j> <nop>
    nno <buffer><nowait> <c-k> <nop>
    nno <buffer><nowait> <c-l> <nop>
enddef
#}}}1
# Utilities {{{1
def FireTermenter() #{{{2
    if exists('#User#TermEnter')
        do <nomodeline> User TermEnter
    endif
enddef

def Getcwd(): string #{{{2
    var cwd = (search('^٪', 'bnW') - 1)
        ->getline()
        # We include a no-break space right after the shell's cwd in our shell's prompt.{{{
        #
        # This is necessary because the prompt  might contain extra info, like a
        # git branch name.
        #}}}
        ->matchstr('.\{-}\ze\%xa0')
    # Warning: in the future, we may define other named directories in our zshrc.
    # Warning: `1000` may be the wrong UID.  We should inspect `$UID` but it's not in the environment.
    cwd = substitute(cwd, '^\~tmp', '/run/user/1000/tmp', '')
    cwd = substitute(cwd, '^\~xdcc', $HOME .. '/Dowloads/XDCC', '')
    return cwd .. '/'
enddef

def UseBracketedPaste(reg: string) #{{{2
    # don't execute anything, even if the register contains newlines
    var reginfo = getreginfo(reg)
    var save = deepcopy(reginfo)
    if get(reginfo, 'regcontents', [])->len() > 1
        var before = &t_PS
        var after = &t_PE
        reginfo.regcontents[0] = before .. reginfo.regcontents[0]
        # TODO(Vim9): In the future, try to use `..=` to simplify:
        #     reginfo.regcontents[-1] ..= after
        reginfo.regcontents[-1] = reginfo.regcontents[-1] .. after
        # Don't use the `'l'` or `'V'` type.  It would cause the automatic execution of the pasted command.
        reginfo.regtype = 'c'
        setreg(reg, reginfo)
        timer_start(0, () => setreg(reg, save))
    endif
enddef

