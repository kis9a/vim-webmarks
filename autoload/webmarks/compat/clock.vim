scriptencoding utf-8
" compat/clock.vim - the current time (Unix seconds), injectable for tests

let s:save_cpo = &cpoptions
set cpoptions&vim

function! webmarks#compat#clock#now() abort
  let l:test = get(g:, 'webmarks_test', {})
  if type(l:test) == v:t_dict && type(get(l:test, 'now', v:null)) == v:t_number
    return l:test.now
  endif
  return localtime()
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
