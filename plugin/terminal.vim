if exists('g:loaded_terminal')
    finish
endif
let g:loaded_terminal = 1

" Inspiration:
" https://github.com/junegunn/fzf/commit/7ceb58b2aadfcf0f5e99da83626cf88d282159b2
" https://github.com/junegunn/fzf/commit/a859aa72ee0ab6e7ae948752906483e468a501ee

" TODO: integrate the `my_terminal` autocmds from vimrc

nno <silent> <c-g><c-g> :<c-u>call terminal#toggle_popup#main()<cr>

