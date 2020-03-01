if exists('g:autoloaded_terminal#toggle_popup')
    finish
endif
let g:autoloaded_terminal#toggle_popup = 1

" Inspiration:
" https://github.com/junegunn/fzf/commit/7ceb58b2aadfcf0f5e99da83626cf88d282159b2
" https://github.com/junegunn/fzf/commit/a859aa72ee0ab6e7ae948752906483e468a501ee

" Init {{{1

const s:OPTS = {
    "\ percentage of the total width
    \ 'width': 0.9,
    "\ percentage of the total height
    \ 'height': 0.6,
    "\ the closer to 1 the further to the right
    \ 'xoffset': 0.5,
    "\ the closer to 1 the lower the window
    \ 'yoffset': 0.5,
    "\ border color when in terminal-normal mode
    \ 'term_normal_highlight': 'Title',
    "\ border color when in terminal-job mode
    \ 'term_job_highlight': 'Comment',
    \ }

fu s:sanitize() abort
    unlockvar s:OPTS
    for key in ['width', 'height', 'xoffset', 'yoffset']
        if s:OPTS[key] < 0
            let s:OPTS[key] = key =~# 'offset' ? 0 : 0.1
        elseif s:OPTS[key] > 1
            " not `1` for the height to still see what we write on the Ex command-line
            let s:OPTS[key] = key is# 'height' ? 0.99 : 1
        endif
    endfor
    lockvar s:OPTS
endfu
call s:sanitize()

" Interface {{{1
fu terminal#toggle_popup#main() abort "{{{2
    " close popup terminal window if it's already on
    if exists('b:toggling_popup_term')
        return s:close()
    " in Nvim, the popup terminal window is not necessarily the current window
    elseif has('nvim') && s:is_toggling_popup_term_on()
        call s:close(s:popup_winid)
    endif

    " Do *not* move these assignments outside this function.{{{
    "
    " These variables must be re-computed at runtime, on every toggling.
    " That's because Vim's geometry (i.e. `&columns`, `&lines`) can change at runtime.
    " In particular, the geometry it had  at startup time is not necessarily the
    " same as when this function is invoked.
    "
    " For example, if  you move these assignments directly to  the script level,
    " and execute  `:LogEvents`, then toggle  the popup terminal window  on, you
    " should see that the border is wrong.
    "}}}
    let [width, height, row, col] = s:get_term_geometry()

    " Why the difference?{{{
    "
    " Nvim doesn't support a border widget by default.
    " We emulate it by creating 2 floats; the bigger one draws the border.
    " We need to pass to `#popup#create()` the geometry of the border float.
    " The latter function will derive the geometry of the "inner" float.
    "
    " OTOH, Vim does support a border widget by default.
    " Such a widget changes the final geometry of the displayed popup window.
    " It makes  it slightly bigger;  how much depends  on the values  inside the
    " lists assigned to the keys `border` and `padding`.
    " Here, we don't assign anything to  `border` nor to `padding`, however – by
    " default –  `#popup#create()` assigns `[]`  to `border` and  `[0,1,0,1]` to
    " `padding`.
    "
    " Anyway, we want the exact same geometry, whether we use Vim or Nvim.
    " So we  need to take into  account the fact  that Vim will create  a bigger
    " window; that is, we need to make it smaller, so that in the ends, with the
    " added border, we get the exact same result as in Nvim.
    "}}}
    if has('nvim')
        let opts = {
            \ 'width': width,
            \ 'height': height,
            \ 'row': row,
            \ 'col': col,
            \ }
    else
        let opts = {
            \ 'width': width - 4,
            \ 'height': height - 2,
            \ 'row': row + 1,
            \ 'col': col + 2,
            \ }
    endif
    call extend(opts, {'borderhighlight': s:OPTS.term_normal_highlight, 'term': v:true})
    try
        let [term_bufnr, term_winid; border] = lg#popup#create(get(s:, 'popup_bufnr', ''), opts)
    catch /^Vim\%((\a\+)\)\=:E117:/
        echohl ErrorMsg | echom 'need lg#popup#create(); install vim-lg-lib' | echohl NONE
        return
    endtry
    " Don't try to get rid of this ad-hoc variable.{{{
    "
    " Yes, we should be able to detect a popup terminal without.
    " But we're not interested in *any* popup terminal.
    " We are interested in *our* custom popup terminal, which is toggled by `C-g C-g`.
    "}}}
    call setbufvar(term_bufnr, 'toggling_popup_term', v:true)

    let s:popup_winid = term_winid

    call s:dynamic_border_color(has('nvim') ? border[1] : term_winid)
    call s:persistent_view()
    if !exists('s:popup_bufnr') | let s:popup_bufnr = term_bufnr | endif
endfu
"}}}1
" Core {{{1
fu s:close(...) abort "{{{2
    let s:view = winsaveview()
    if has('nvim')
        if a:0
            let curwinid = win_getid()
            call win_gotoid(a:1)
            close
            call win_gotoid(curwinid)
        else
            close
        endif
    else
        call popup_close(win_getid())
    endif
endfu

fu s:get_term_geometry() abort "{{{2
    let width = float2nr(&columns * s:OPTS.width)
    let height = float2nr(&lines * s:OPTS.height)

    " Why `&lines - height`?  Why not just `&lines`{{{
    "
    " If your `yoffset`  is 1, and you  just write `&lines`, then  `row` will be
    " set to `&lines`, which  is wrong; the top of the popup  window can't be on
    " the last line of the screen; the lowest it can be is `&lines - height`.
    "}}}
    let row = float2nr(s:OPTS.yoffset * (&lines - height))
    let col = float2nr(s:OPTS.xoffset * (&columns - width))
    " to get the exact same position in Vim and Nvim
    if !has('nvim') | let col -= 1 | endif

    return [width, height, row, col]
endfu

fu s:dynamic_border_color(winid) abort "{{{2
    augroup dynamic_border_color
        au! * <buffer>
        if has('nvim')
            exe 'au TermEnter <buffer> '
                \ ..printf('call setwinvar(%d, "&winhighlight", "NormalFloat:%s")',
                \ a:winid, s:OPTS.term_job_highlight)
            exe 'au TermLeave <buffer> '
                \ ..printf('call setwinvar(%d, "&winhighlight", "NormalFloat:%s")',
                \ a:winid, s:OPTS.term_normal_highlight)
        else
            let cmd = printf('call popup_setoptions(%d, %s)',
                \ a:winid, {'borderhighlight': [s:OPTS.term_job_highlight]})
            exe 'au! User TermEnter '..cmd
            " Why inspecting `mode()`?{{{
            "
            " Initially, the border is highlighted by `s:OPTS.term_normal_highlight`.
            " This command resets the highlighting to `s:OPTS.term_job_highlight`.
            " This is correct  the first time we toggle the  popup on, because we're
            " automatically in Terminal-Job mode.
            " Afterwards,  this   is  wrong;   we're  no  longer   automatically  in
            " Terminal-Job mode; we stay in Terminal-Normal mode.
            "
            " I *think* that when you display  a *new* terminal buffer, Vim puts you
            " in Terminal-Job mode automatically.
            " OTOH, when  you display  an *existing*  terminal buffer,  Vim probably
            " remembers the last mode you were in.
            "}}}
            if mode() is# 't' | exe cmd | endif
            exe 'au! User TermLeave '
                \ ..printf('call popup_setoptions(%d, %s)',
                \ a:winid, {'borderhighlight': [s:OPTS.term_normal_highlight]})
        endif
    augroup END
endfu

fu s:persistent_view() abort "{{{2
    " Make the view persistent when we toggle the window on and off.{{{
    "
    " By  default, Vim  doesn't seem  to restore  the cursor  position, nor  the
    " topline.  Nvim restores the cursor, but not the topline.
    "}}}
    " We already have an autocmd restoring the view in `vim-window`.  Why is this necessary?{{{
    "
    " This autocmd doesn't work for special buffers (including terminal buffers).
    " Besides, it can only work when you re-display a buffer in the same window.
    " That's not what is happening here; we re-display a buffer in a *new* window.
    "}}}
    if exists('s:view') | call winrestview(s:view) | endif
endfu
"}}}1
" Util {{{1
fu s:is_toggling_popup_term_on(...) abort "{{{2
    return index(map(getwininfo(), {_,v -> getbufvar(v.bufnr, 'toggling_popup_term')}), v:true) != -1
endfu

