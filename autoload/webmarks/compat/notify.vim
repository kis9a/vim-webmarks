scriptencoding utf-8
" compat/notify.vim - messages
"
" echohl + echomsg on both editors. nvim_notify() at ERROR level aborts
" the caller on Neovim, so it is not used.

let s:save_cpo = &cpoptions
set cpoptions&vim

let s:warned = {}

function! s:emit(group, msg) abort
  let l:text = '[webmarks] ' . a:msg
  if a:group !=# ''
    execute 'echohl' a:group
  endif
  echomsg l:text
  if a:group !=# ''
    echohl None
  endif
endfunction

function! webmarks#compat#notify#info(msg) abort
  call s:emit('', a:msg)
endfunction

function! webmarks#compat#notify#warn(msg) abort
  call s:emit('WarningMsg', a:msg)
endfunction

function! webmarks#compat#notify#error(msg) abort
  call s:emit('ErrorMsg', a:msg)
endfunction

" Warn once per {key} for the whole session.
function! webmarks#compat#notify#warn_once(key, msg) abort
  if has_key(s:warned, a:key)
    return
  endif
  let s:warned[a:key] = 1
  call webmarks#compat#notify#warn(a:msg)
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
