scriptencoding utf-8
" ui/fzf.vim - pick a bookmark with fzf and open it
"
" Needs fzf's own plugin/fzf.vim (fzf#run / fzf#wrap). Candidates keep the
" SortPolicy order (--no-sort); the hidden first field is the id.

let s:save_cpo = &cpoptions
set cpoptions&vim

let s:options = ['--prompt', 'Webmarks> ', '--delimiter', "\t", '--with-nth', '2..',
      \ '--no-sort', '--tiebreak', 'index']

function! webmarks#ui#fzf#available() abort
  return exists('*fzf#run') && exists('*fzf#wrap')
endfunction

" The fzf#run() spec for {policy}; OnDone(result) runs after a launch.
function! webmarks#ui#fzf#spec(policy, OnDone) abort
  let l:source = webmarks#app#listing#candidates(webmarks#app#store#current(), a:policy,
        \ webmarks#compat#clock#now())
  return {'source': l:source, 'sink': function('s:sink', [a:OnDone]), 'options': copy(s:options)}
endfunction

" run(policy, OnDone) -> Result
function! webmarks#ui#fzf#run(policy, OnDone) abort
  if !webmarks#ui#fzf#available()
    let l:r = {'ok': v:false, 'code': 'fzf_missing', 'changed': v:false,
          \ 'error': 'fzf (plugin/fzf.vim) is not available'}
    call webmarks#compat#notify#error(l:r.error)
    return l:r
  endif
  let l:r = webmarks#app#store#reload()
  if !l:r.ok
    call webmarks#compat#notify#error(l:r.error)
    return l:r
  endif
  let l:spec = webmarks#ui#fzf#spec(a:policy, a:OnDone)
  if empty(l:spec.source)
    call webmarks#compat#notify#info('no bookmarks')
    return {'ok': v:true, 'code': '', 'error': '', 'changed': v:false}
  endif
  try
    let l:wrapped = fzf#wrap(l:spec)
  catch /.*/
    let l:wrapped = l:spec
  endtry
  call fzf#run(l:wrapped)
  return {'ok': v:true, 'code': '', 'error': '', 'changed': v:false}
endfunction

function! s:sink(OnDone, line) abort
  let l:id = split(a:line, "\t", 1)[0]
  if l:id !~# '^b\d\+$'
    return
  endif
  let l:r = webmarks#app#bookmark#launch(l:id, webmarks#compat#clock#now())
  if !l:r.ok
    if get(l:r, 'launched', v:false)
      call webmarks#compat#notify#warn('opened, but could not record usage: ' . l:r.error)
    else
      call webmarks#compat#notify#error(l:r.error)
    endif
  endif
  call call(a:OnDone, [l:r])
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
