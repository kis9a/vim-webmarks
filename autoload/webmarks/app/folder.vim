scriptencoding utf-8
" app/folder.vim - folder use cases (all through store#mutate)

let s:save_cpo = &cpoptions
set cpoptions&vim

function! s:ok(extra) abort
  return extend({'ok': v:true, 'code': '', 'error': '', 'changed': v:true}, a:extra)
endfunction

function! s:not_found(id) abort
  return {'ok': v:false, 'code': 'not_found', 'error': 'folder not found: ' . string(a:id), 'changed': v:false}
endfunction

function! s:put(data, r) abort
  if !a:r.ok
    return a:r
  endif
  return s:ok({'data': webmarks#app#store#put_folder(a:data, a:r.folder),
        \ 'folder': a:r.folder, 'changed': a:r.changed})
endfunction

function! s:add_fn(name, parent_id, data) abort
  let l:v = webmarks#domain#folder#validate_parent(a:data.folders, v:null, a:parent_id)
  if !l:v.ok
    return l:v
  endif
  let [l:id, l:data] = webmarks#app#store#next_id(a:data, 'f')
  let l:r = webmarks#domain#folder#new(l:id, a:name, a:parent_id)
  if !l:r.ok
    return l:r
  endif
  let l:data.folders = l:data.folders + [l:r.folder]
  return s:ok({'data': l:data, 'id': l:id, 'folder': l:r.folder})
endfunction

" add(name, parent_id) -> Result {id, folder}
function! webmarks#app#folder#add(name, parent_id) abort
  return webmarks#app#store#mutate(function('s:add_fn', [a:name, a:parent_id]))
endfunction

function! s:rename_fn(id, name, data) abort
  let l:f = webmarks#app#store#find_folder(a:data, a:id)
  if l:f is v:null
    return s:not_found(a:id)
  endif
  return s:put(a:data, webmarks#domain#folder#rename(l:f, a:name))
endfunction

function! webmarks#app#folder#rename(id, name) abort
  return webmarks#app#store#mutate(function('s:rename_fn', [a:id, a:name]))
endfunction

function! s:move_fn(id, parent_id, data) abort
  let l:f = webmarks#app#store#find_folder(a:data, a:id)
  if l:f is v:null
    return s:not_found(a:id)
  endif
  let l:v = webmarks#domain#folder#validate_parent(a:data.folders, a:id, a:parent_id)
  if !l:v.ok
    return l:v
  endif
  return s:put(a:data, webmarks#domain#folder#set_parent(l:f, a:parent_id))
endfunction

function! webmarks#app#folder#move(id, parent_id) abort
  return webmarks#app#store#mutate(function('s:move_fn', [a:id, a:parent_id]))
endfunction

function! s:remove_fn(id, data) abort
  let l:f = webmarks#app#store#find_folder(a:data, a:id)
  if l:f is v:null
    return s:not_found(a:id)
  endif
  let l:c = webmarks#domain#folder#can_delete(a:data.folders, a:data.bookmarks, a:id)
  if !l:c.ok
    return l:c
  endif
  let l:data = copy(a:data)
  let l:data.folders = filter(copy(a:data.folders), 'v:val.id !=# a:id')
  return s:ok({'data': l:data, 'removed': l:f})
endfunction

" remove(id) -> Result {removed}; only empty folders.
function! webmarks#app#folder#remove(id) abort
  return webmarks#app#store#mutate(function('s:remove_fn', [a:id]))
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
