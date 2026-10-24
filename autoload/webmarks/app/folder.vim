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

" check_remove(id) -> Result: could the folder be removed now? (asked before
" the confirmation prompt; remove() checks again against fresh data)
function! webmarks#app#folder#check_remove(id) abort
  let l:data = webmarks#app#store#current()
  if webmarks#app#store#find_folder(l:data, a:id) is v:null
    return s:not_found(a:id)
  endif
  return webmarks#domain#folder#can_delete(l:data.folders, l:data.bookmarks, a:id)
endfunction

" choices(data, exclude_id) -> [{id, path}] in tree order: where something
" can be moved to. exclude_id (a folder being moved) and its descendants
" are left out.
function! webmarks#app#folder#choices(data, exclude_id) abort
  let l:skip = {}
  if a:exclude_id isnot v:null
    let l:skip[a:exclude_id] = 1
    for l:f in webmarks#domain#folder#descendants(a:data.folders, a:exclude_id)
      let l:skip[l:f.id] = 1
    endfor
  endif
  let l:out = []
  for l:top in webmarks#domain#folder#children(a:data.folders, v:null)
    for l:f in [l:top] + webmarks#domain#folder#children(a:data.folders, l:top.id)
      if !has_key(l:skip, l:f.id)
        call add(l:out, {'id': l:f.id, 'path': webmarks#domain#folder#path(a:data.folders, l:f.id)})
      endif
    endfor
  endfor
  return l:out
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
