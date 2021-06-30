vim9script noclear

if exists('loaded') | finish | endif
var loaded = true

import Catch from 'lg.vim'
const SFILE: string = expand('<sfile>:p')

# Interface {{{1
def terminal#setup() #{{{2
    # TODO: Once Vim supports `ModeChanged`, get rid of `Wrap()`.{{{
    #
    # Instead, refactor your autocmds to listen to `ModeChanged`.
    #
    # See: https://github.com/vim/vim/issues/2487#issuecomment-353735824
    # And `:help todo /modechanged`.
    #}}}
    nnoremap <buffer><nowait> i <Cmd>call <SID>Wrap('i')<CR>
    nnoremap <buffer><nowait> a <Cmd>call <SID>Wrap('a')<CR>

    nnoremap <buffer><nowait> I <Cmd>call <SID>Wrap('I')<CR>
    nnoremap <buffer><nowait> A <Cmd>call <SID>Wrap('A')<CR>

    nnoremap <buffer><nowait> C <Cmd>call <SID>Wrap('C')<CR>
    nnoremap <buffer><nowait> cc <Cmd>call <SID>Wrap('cc')<CR>

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
    nnoremap <buffer><expr><nowait> p <SID>Put()

    nnoremap <buffer><nowait> D  <Cmd>call <SID>KillLine()<CR>
    nnoremap <buffer><nowait> dd i<C-E><C-U><C-\><C-N>

    xnoremap <buffer><nowait> c <Nop>
    xnoremap <buffer><nowait> d <Nop>
    xnoremap <buffer><nowait> p <Nop>
    xnoremap <buffer><nowait> x <Nop>

    noremap <buffer><expr><nowait> [c brackets#move#regex('shell_prompt', v:false)
    noremap <buffer><expr><nowait> ]c brackets#move#regex('shell_prompt', v:true)
    # Do not remove the try/catch.
    # `silent!` cannot always suppress a thrown error in Vim9.
    try
        silent! repmap#make#repeatable({
            mode: '',
            buffer: true,
            from: SFILE .. ':' .. expand('<sflnum>'),
            motions: [{bwd: '[c', fwd: ']c'}]
        })
    catch /^E8003:/
    endtry

    # If `'termwinkey'` is not set, Vim falls back on `C-w`.  See `:help 'termwinkey`.
    var termwinkey: string = &l:termwinkey == '' ? '<C-W>' : &l:termwinkey
    # don't execute an inserted register when it contains a newline
    execute 'tnoremap <buffer><expr><nowait> ' .. termwinkey .. '" <SID>InsertRegister()'
    # we don't want a timeout when we press the termwinkey + `C-w` to focus the next window:
    # https://vi.stackexchange.com/a/24983/17449
    execute printf('tnoremap <buffer><nowait> %s<C-W> %s<C-W>', termwinkey, termwinkey)

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
    &l:includeexpr = expand('<SID>') .. 'Includeexpr()'
    xnoremap <buffer><nowait> mq <C-\><C-N><Cmd>call <SID>SelectionToQf()<CR>

    # Rationale:{{{
    #
    # Setting `'sidescrolloff'`  to a  non-zero value is  useless in  a terminal
    # buffer; long lines are automatically hard-wrapped.
    # Besides, it makes the window's view "dance" when pressing `l` and reaching
    # the end of a long line, which is jarring.
    #
    # ---
    #
    # We reset `'scrolloff'`  because it makes moving in a  terminal buffer more
    # consistent with tmux copy-mode.
    #}}}
    &l:scrolloff = 0 | &l:sidescrolloff = 0
    &l:wrap = false

    if win_gettype() == 'popup'
        SetPopup()
    endif
enddef

def Wrap(lhs: string) #{{{2
    try
        if lhs[0] =~ '[cC]'
            normal! i
        else
            execute 'normal! ' .. lhs[0]
        endif
    # Why?{{{
    #
    # When the job  associated to a terminal has finished,  pressing `i` doesn't
    # make you enter  Terminal-Job mode (there is no job  anymore); it makes you
    # enter insert mode.  The terminal buffer becomes a normal buffer.
    # However, it's not modifiable, so `i` raises `E21`.
    #
    # All of this is explained at `:help E947`.
    #}}}
    catch /^Vim\%((\a\+)\)\=:E21:/
        # I want to edit this kind of buffer!{{{
        #
        # Then replace the next `return` with sth like this:
        #
        #     nunmap <buffer> i
        #     nunmap <buffer> a
        #     ...
        #     &l:modifiable = true
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
        #         nnoremap <buffer><nowait> D i<C-K><C-\><C-N>
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
        var startofline: string = term_getline('', '.')
            ->matchstr('٪ \zs.*\%' .. col('.') .. 'c')
        term_sendkeys('', "\<C-E>\<C-U>" .. startofline)
        return
    endif
    var keys: string = {
        I: "\<C-A>",
        A: "\<C-E>",
        cc: "\<C-E>\<C-U>",
        }[lhs]
    term_sendkeys('', keys)
enddef

def terminal#fireTermleave() #{{{2
    if exists('#User#TermLeave')
        doautocmd <nomodeline> User TermLeave
    endif
enddef
#}}}1
# Core {{{1
def KillLine() #{{{2
    var buf: number = bufnr('%')
    var vimpos: list<number> = getcurpos()
    var jobpos: list<any> = term_getcursor(buf)
    var offcol: number = jobpos[1] - vimpos[2]
    var offline: number = jobpos[0] - vimpos[1]
    normal! i
    var keys: string = repeat("\<Left>", offcol)
        .. repeat("\<Up>", offline)
        .. "\<C-K>"
    term_sendkeys(buf, keys)
    term_wait(buf, 50)
    feedkeys("\<C-\>\<C-N>", 'nx')
enddef

def Includeexpr(): string #{{{2
    var cwd: string = Getcwd()
    # most of the code is leveraged from a similar function in our vimrc
    var line: string = getline('.')
    var col: number = col('.')
    var pat: string = '${\f\+}' .. '\V' .. v:fname .. '\m'
        .. '\|${\V' .. v:fname .. '\m}\f\+'
        .. '\|\%' .. col .. 'c${\f\+}\f\+'
    var cursor_is_after: string = '\%<' .. (col + 1) .. 'c'
    var cursor_is_before: string = '\%>' .. col .. 'c'
    pat = cursor_is_after .. '\%(' .. pat .. '\)' .. cursor_is_before
    if line =~ pat
        pat = line->matchstr(pat)
        var env: string = pat->matchstr('\w\+')
        return pat->substitute('${' .. env .. '}', getenv(env) ?? '', '')
    elseif line =~ cursor_is_after .. '=' .. cursor_is_before
        return v:fname->substitute('.*=', '', '')
    elseif line =~ '^\./'
        return v:fname->substitute('^\./', cwd, '')
    else
        return cwd .. v:fname
    endif
enddef

def InsertRegister(): string #{{{2
    var numeric: list<number> = range(10)
    var alpha: list<string> = range(char2nr('a'), char2nr('z'))
        ->mapnew((_, v: number): string => nr2char(v))
    var other: list<string> = ['-', '*', '+', '/', '=']
    var reg: string = getcharstr()
    if index(numeric + alpha + other, reg) == -1
        return ''
    endif
    UseBracketedPaste(reg)
    var termwinkey: string = &l:termwinkey == '' ? "\<C-W>" : eval('"\' .. &l:termwinkey .. '"')
    return termwinkey .. '"' .. reg
enddef

def SelectionToQf() #{{{2
    var cwd: string = Getcwd()
    var lnum1: number = line("'<")
    var lnum2: number = line("'>")
    var lines: list<string> = getline(lnum1, lnum2)
        ->map((_, v: string): string => cwd .. v)
    setqflist([], ' ', {lines: lines, title: ':' .. lnum1 .. ',' .. lnum2 .. 'cgetbuffer'})
    cwindow
enddef

def Put(): string #{{{2
    var reg: string = v:register
    UseBracketedPaste(reg)
    var termwinkey: string = &l:termwinkey == '' ? "\<C-W>" : eval('"\' .. &l:termwinkey .. '"')
    FireTermenter()
    return "i\<C-E>" .. termwinkey .. '"' .. reg
enddef

def SetPopup() #{{{2
    # Like for  all local options,  the local  value of `'termwinkey'`  has been
    # reset to its default value (empty string), which makes Vim use `C-w`.
    # Set the option  again, so that we  get the same experience  as in terminal
    # buffers in non-popup windows.
    set termwinkey<

    # suppress error: "Vim(wincmd):E994: Not allowed in a popup window"
    nnoremap <buffer><nowait> <C-H> <Nop>
    nnoremap <buffer><nowait> <C-J> <Nop>
    nnoremap <buffer><nowait> <C-K> <Nop>
    nnoremap <buffer><nowait> <C-L> <Nop>
enddef
#}}}1
# Utilities {{{1
def FireTermenter() #{{{2
    if exists('#User#TermEnter')
        doautocmd <nomodeline> User TermEnter
    endif
enddef

def Getcwd(): string #{{{2
    var cwd: string = (search('^٪', 'bnW') - 1)
        ->getline()
        # We include a no-break space right after the shell's cwd in our shell's prompt.{{{
        #
        # This is necessary because the prompt  might contain extra info, like a
        # git branch name.
        #}}}
        ->matchstr('.\{-}\ze\%xa0')
        # Warning: in the future, we may define other named directories in our zshrc.
        # Warning: `1000` may be the wrong UID.  We should inspect `$UID` but it's not in the environment.
        ->substitute('^\~tmp', '/run/user/1000/tmp', '')
        ->substitute('^\~xdcc', $HOME .. '/Dowloads/XDCC', '')
    return cwd .. '/'
enddef

def UseBracketedPaste(reg: string) #{{{2
    # don't execute anything, even if the register contains newlines
    var reginfo: dict<any> = getreginfo(reg)
    var save: dict<any> = deepcopy(reginfo)
    if get(reginfo, 'regcontents', [])->len() > 1
        var before: string = &t_PS
        var after: string = &t_PE
        reginfo.regcontents[0] = before .. reginfo.regcontents[0]
        reginfo.regcontents[-1] ..= after
        # Don't use the `'l'` or `'V'` type.  It would cause the automatic execution of the pasted command.
        reginfo.regtype = 'c'
        setreg(reg, reginfo)
        timer_start(0, (_) => setreg(reg, save))
    endif
enddef

