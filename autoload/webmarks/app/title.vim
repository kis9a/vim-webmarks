scriptencoding utf-8
" app/title.vim - coordinates asynchronous title fetches
"
" Only the newest request per bookmark may apply its result. Nothing is
" persisted: pending requests die with Vim. The UI learns about changes
" through registered listeners (app never calls ui).

let s:save_cpo = &cpoptions
set cpoptions&vim

let s:seq = {}
let s:pending = {}
let s:listeners = []

" add_listener(Fn): Fn(event) with event = {id, changed, warning}.
function! webmarks#app#title#add_listener(Fn) abort
  if index(s:listeners, a:Fn) < 0
    call add(s:listeners, a:Fn)
  endif
endfunction

function! webmarks#app#title#pending_ids() abort
  return keys(s:pending)
endfunction

" request(id, url, force, auto_enabled) -> Result {requested}
"   force = explicit refetch (overwrites a manual name, reports failures)
function! webmarks#app#title#request(id, url, force, auto_enabled) abort
  if !a:force && !a:auto_enabled
    return {'ok': v:true, 'code': '', 'error': '', 'changed': v:false, 'requested': v:false}
  endif
  if !webmarks#deps#title#available()
    return {'ok': v:false, 'code': 'no_async', 'changed': v:false, 'requested': v:false,
          \ 'error': 'title fetch unavailable (needs curl and +job / jobstart)'}
  endif
  let l:seq = get(s:seq, a:id, 0) + 1
  let s:seq[a:id] = l:seq
  let s:pending[a:id] = {'url': a:url, 'seq': l:seq, 'force': a:force ? 1 : 0}
  call webmarks#deps#title#fetch(a:url, function('webmarks#app#title#on_result'),
        \ {'id': a:id, 'url': a:url, 'seq': l:seq, 'force': a:force ? 1 : 0})
  return {'ok': v:true, 'code': '', 'error': '', 'changed': v:false, 'requested': v:true}
endfunction

function! s:is_current(id, seq) abort
  return get(s:seq, a:id, -1) == a:seq
endfunction

function! webmarks#app#title#on_result(result, ctx) abort
  let l:id = a:ctx.id
  " an older request: drop it, and keep the newer one pending
  if !s:is_current(l:id, a:ctx.seq)
    return
  endif
  if has_key(s:pending, l:id)
    call remove(s:pending, l:id)
  endif
  if !a:result.ok
    if a:ctx.force
      call s:notify({'id': l:id, 'changed': v:false, 'warning': a:result.error})
    else
      " the pending marker went away: redraw quietly
      call s:notify({'id': l:id, 'changed': v:false, 'warning': ''})
    endif
    return
  endif
  if a:ctx.force
    let l:r = webmarks#app#bookmark#force_title(l:id, a:ctx.url, a:result.title)
    call s:notify({'id': l:id, 'changed': get(l:r, 'changed', v:false) ? v:true : v:false,
          \ 'warning': l:r.ok ? '' : l:r.error})
  else
    let l:r = webmarks#app#bookmark#apply_title(l:id, a:ctx.url,
          \ function('s:is_current', [l:id, a:ctx.seq]), a:result.title)
    call s:notify({'id': l:id, 'changed': l:r.ok && l:r.changed ? v:true : v:false,
          \ 'warning': l:r.ok ? '' : l:r.error})
  endif
endfunction

function! s:notify(event) abort
  for l:F in s:listeners
    try
      call call(l:F, [a:event])
    catch /.*/
    endtry
  endfor
endfunction

" Test helper
function! webmarks#app#title#_reset() abort
  let s:seq = {}
  let s:pending = {}
  let s:listeners = []
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
