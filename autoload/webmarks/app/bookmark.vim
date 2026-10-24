scriptencoding utf-8
" app/bookmark.vim - bookmark use cases
"
" Every change goes through store#mutate; the checks run inside the
" transformation against freshly read data (no check-then-act).

let s:save_cpo = &cpoptions
set cpoptions&vim

function! s:ok(extra) abort
  return extend({'ok': v:true, 'code': '', 'error': '', 'changed': v:true}, a:extra)
endfunction

function! s:err(code, msg) abort
  return {'ok': v:false, 'code': a:code, 'error': a:msg, 'changed': v:false}
endfunction

function! s:not_found(id) abort
  return s:err('not_found', 'bookmark not found: ' . a:id)
endfunction

function! s:folder_not_found(id) abort
  return s:err('not_found', 'folder not found: ' . a:id)
endfunction

function! s:duplicate(data, b) abort
  let l:path = webmarks#domain#folder#path(a:data.folders, a:b.folder_id)
  let l:r = s:err('duplicate_url', printf('already registered: %s (%s)',
        \ a:b.display_name, l:path ==# '' ? '/' : l:path))
  let l:r.existing = {'id': a:b.id, 'display_name': a:b.display_name, 'folder_path': l:path}
  return l:r
endfunction

" Result of a domain op on bookmark {b} -> mutate Result with data'
function! s:put(data, r, extra) abort
  if !a:r.ok
    return a:r
  endif
  return s:ok(extend({'data': webmarks#app#store#put_bookmark(a:data, a:r.bookmark),
        \ 'bookmark': a:r.bookmark, 'changed': a:r.changed}, a:extra))
endfunction

" --- add ---------------------------------------------------------------

function! s:add_fn(url, name, folder_id, now, data) abort
  let l:u = webmarks#domain#bookmark#validate_url(a:url)
  if !l:u.ok
    return l:u
  endif
  if a:folder_id isnot v:null && webmarks#app#store#find_folder(a:data, a:folder_id) is v:null
    return s:folder_not_found(a:folder_id)
  endif
  let l:dup = webmarks#domain#bookmark#find_duplicate(a:data.bookmarks, l:u.value, v:null)
  if l:dup isnot v:null
    return s:duplicate(a:data, l:dup)
  endif
  let [l:id, l:data] = webmarks#app#store#next_id(a:data, 'b')
  let l:r = webmarks#domain#bookmark#new(l:id, l:u.value, a:name, a:folder_id, a:now)
  if !l:r.ok
    return l:r
  endif
  let l:data.bookmarks = l:data.bookmarks + [l:r.bookmark]
  return s:ok({'data': l:data, 'id': l:id, 'bookmark': l:r.bookmark,
        \ 'fetch_title': l:r.bookmark.name_source ==# 'url'})
endfunction

" add(url, name, folder_id, now) -> Result {id, bookmark, fetch_title}
function! webmarks#app#bookmark#add(url, name, folder_id, now) abort
  return webmarks#app#store#mutate(function('s:add_fn', [a:url, a:name, a:folder_id, a:now]))
endfunction

" --- simple edits ------------------------------------------------------

function! s:rename_fn(id, name, data) abort
  let l:b = webmarks#app#store#find_bookmark(a:data, a:id)
  if l:b is v:null
    return s:not_found(a:id)
  endif
  return s:put(a:data, webmarks#domain#bookmark#rename(l:b, a:name), {})
endfunction

function! webmarks#app#bookmark#rename(id, name) abort
  return webmarks#app#store#mutate(function('s:rename_fn', [a:id, a:name]))
endfunction

function! s:change_url_fn(id, url, data) abort
  let l:b = webmarks#app#store#find_bookmark(a:data, a:id)
  if l:b is v:null
    return s:not_found(a:id)
  endif
  let l:u = webmarks#domain#bookmark#validate_url(a:url)
  if !l:u.ok
    return l:u
  endif
  let l:dup = webmarks#domain#bookmark#find_duplicate(a:data.bookmarks, l:u.value, a:id)
  if l:dup isnot v:null
    return s:duplicate(a:data, l:dup)
  endif
  let l:r = webmarks#domain#bookmark#change_url(l:b, l:u.value)
  return s:put(a:data, l:r, {'fetch_title': l:r.ok && l:r.changed && l:r.bookmark.name_source ==# 'url'})
endfunction

" change_url(id, url) -> Result {bookmark, fetch_title}
function! webmarks#app#bookmark#change_url(id, url) abort
  return webmarks#app#store#mutate(function('s:change_url_fn', [a:id, a:url]))
endfunction

function! s:move_fn(id, folder_id, data) abort
  let l:b = webmarks#app#store#find_bookmark(a:data, a:id)
  if l:b is v:null
    return s:not_found(a:id)
  endif
  if a:folder_id isnot v:null && webmarks#app#store#find_folder(a:data, a:folder_id) is v:null
    return s:folder_not_found(a:folder_id)
  endif
  return s:put(a:data, webmarks#domain#bookmark#move_to(l:b, a:folder_id), {})
endfunction

function! webmarks#app#bookmark#move(id, folder_id) abort
  return webmarks#app#store#mutate(function('s:move_fn', [a:id, a:folder_id]))
endfunction

function! s:remove_fn(id, data) abort
  let l:b = webmarks#app#store#find_bookmark(a:data, a:id)
  if l:b is v:null
    return s:not_found(a:id)
  endif
  let l:data = copy(a:data)
  let l:data.bookmarks = filter(copy(a:data.bookmarks), 'v:val.id !=# a:id')
  return s:ok({'data': l:data, 'removed': l:b})
endfunction

" remove(id) -> Result {removed}; the usage stats go with it.
function! webmarks#app#bookmark#remove(id) abort
  return webmarks#app#store#mutate(function('s:remove_fn', [a:id]))
endfunction

function! s:favorite_fn(id, data) abort
  let l:b = webmarks#app#store#find_bookmark(a:data, a:id)
  if l:b is v:null
    return s:not_found(a:id)
  endif
  return s:put(a:data, webmarks#domain#bookmark#toggle_favorite(l:b), {})
endfunction

function! webmarks#app#bookmark#toggle_favorite(id) abort
  return webmarks#app#store#mutate(function('s:favorite_fn', [a:id]))
endfunction

" --- launch ------------------------------------------------------------

function! s:record_fn(id, url, now, data) abort
  let l:b = webmarks#app#store#find_bookmark(a:data, a:id)
  " gone, or its URL changed since we opened it: record nothing
  if l:b is v:null || l:b.url !=# a:url
    return s:ok({'changed': v:false, 'recorded': v:false})
  endif
  let l:pre_total = webmarks#domain#frecency#total_rank(a:data.bookmarks)
  let l:r = webmarks#domain#bookmark#record_launch(l:b, a:now)
  let l:data = webmarks#app#store#put_bookmark(a:data, l:r.bookmark)
  let l:aged = webmarks#domain#frecency#age(l:data.bookmarks, l:pre_total)
  let l:data.bookmarks = l:aged.bookmarks
  return s:ok({'data': l:data, 'recorded': v:true})
endfunction

" launch(id, now) -> Result {launched, recorded}
" Open first, record only when the browser command succeeded. A failed
" save after a successful open is {ok: false, launched: true}.
function! webmarks#app#bookmark#launch(id, now) abort
  let l:reload = webmarks#app#store#reload()
  if !l:reload.ok
    return extend(l:reload, {'launched': v:false, 'recorded': v:false})
  endif
  let l:b = webmarks#app#store#find_bookmark(webmarks#app#store#current(), a:id)
  if l:b is v:null
    return extend(s:not_found(a:id), {'launched': v:false, 'recorded': v:false})
  endif
  let l:open = webmarks#deps#browser#open(l:b.url)
  if !l:open.ok
    return extend(l:open, {'launched': v:false, 'recorded': v:false})
  endif
  let l:r = webmarks#app#store#mutate(function('s:record_fn', [a:id, l:b.url, a:now]))
  if !l:r.ok
    return extend(l:r, {'launched': v:true, 'recorded': v:false})
  endif
  return extend(l:r, {'launched': v:true, 'url': l:b.url})
endfunction

" --- titles ------------------------------------------------------------

function! s:apply_title_fn(id, url, SeqCheck, title, data) abort
  let l:b = webmarks#app#store#find_bookmark(a:data, a:id)
  if l:b is v:null || l:b.url !=# a:url || !call(a:SeqCheck, [])
    return s:ok({'changed': v:false})
  endif
  return s:put(a:data, webmarks#domain#bookmark#apply_fetched_title(l:b, a:title), {})
endfunction

" apply_title(id, url, SeqCheck, title) -> Result {changed}
" Applies only if the bookmark still exists, has the same URL, the
" request is still the newest (SeqCheck()) and the name is provisional.
function! webmarks#app#bookmark#apply_title(id, url, SeqCheck, title) abort
  return webmarks#app#store#mutate(function('s:apply_title_fn', [a:id, a:url, a:SeqCheck, a:title]))
endfunction

function! s:force_title_fn(id, url, title, data) abort
  let l:b = webmarks#app#store#find_bookmark(a:data, a:id)
  if l:b is v:null
    return s:not_found(a:id)
  endif
  if l:b.url !=# a:url
    return s:ok({'changed': v:false})
  endif
  return s:put(a:data, webmarks#domain#bookmark#force_title(l:b, a:title), {})
endfunction

function! webmarks#app#bookmark#force_title(id, url, title) abort
  return webmarks#app#store#mutate(function('s:force_title_fn', [a:id, a:url, a:title]))
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
