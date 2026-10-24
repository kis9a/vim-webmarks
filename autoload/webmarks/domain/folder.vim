scriptencoding utf-8
" domain/folder.vim - the Folder aggregate and hierarchy rules
"
" Invariants (numbered as in the design):
"   H1 depth <= 2   H2 not its own parent   H3 no cycles
"   H4 parent exists   H5 a bookmark's folder exists
" Pure: no buffers, files, commands, clock or g: variables.

let s:save_cpo = &cpoptions
set cpoptions&vim

let s:max_depth = 2

function! s:ok(extra) abort
  return extend({'ok': v:true, 'code': '', 'error': '', 'changed': v:true}, a:extra)
endfunction

function! s:err(code, msg) abort
  return {'ok': v:false, 'code': a:code, 'error': a:msg, 'changed': v:false}
endfunction

" v:null-aware equality for folder ids
function! s:same(a, b) abort
  return type(a:a) == type(a:b) && a:a ==# a:b
endfunction

function! s:index(folders) abort
  let l:map = {}
  for l:f in a:folders
    let l:map[l:f.id] = l:f
  endfor
  return l:map
endfunction

function! webmarks#domain#folder#new(id, name, parent_id) abort
  let l:n = webmarks#domain#text#sanitize(a:name)
  if !l:n.ok
    return l:n
  endif
  return s:ok({'folder': {'id': a:id, 'name': l:n.value, 'parent_id': a:parent_id}})
endfunction

function! webmarks#domain#folder#rename(f, name) abort
  let l:n = webmarks#domain#text#sanitize(a:name)
  if !l:n.ok
    return l:n
  endif
  let l:new = deepcopy(a:f)
  let l:new.name = l:n.value
  return s:ok({'folder': l:new, 'changed': l:new != a:f})
endfunction

function! webmarks#domain#folder#set_parent(f, parent_id) abort
  let l:new = deepcopy(a:f)
  let l:new.parent_id = a:parent_id
  return s:ok({'folder': l:new, 'changed': !s:same(a:f.parent_id, a:parent_id)})
endfunction

function! webmarks#domain#folder#find(folders, id) abort
  for l:f in a:folders
    if s:same(l:f.id, a:id)
      return l:f
    endif
  endfor
  return v:null
endfunction

" Root = 0, a folder directly under the root = 1. Missing or cyclic = -1.
function! webmarks#domain#folder#depth(folders, folder_id) abort
  return s:depth(s:index(a:folders), a:folder_id)
endfunction

function! s:depth(map, folder_id) abort
  let l:depth = 0
  let l:seen = {}
  let l:cur = a:folder_id
  while l:cur isnot v:null
    if type(l:cur) != v:t_string || !has_key(a:map, l:cur) || has_key(l:seen, l:cur)
      return -1
    endif
    let l:seen[l:cur] = 1
    let l:depth += 1
    let l:cur = a:map[l:cur].parent_id
  endwhile
  return l:depth
endfunction

" 'Dev/Docs'; v:null -> ''
function! webmarks#domain#folder#path(folders, folder_id) abort
  let l:map = s:index(a:folders)
  let l:names = []
  let l:seen = {}
  let l:cur = a:folder_id
  while type(l:cur) == v:t_string && has_key(l:map, l:cur) && !has_key(l:seen, l:cur)
    let l:seen[l:cur] = 1
    call insert(l:names, l:map[l:cur].name)
    let l:cur = l:map[l:cur].parent_id
  endwhile
  return join(l:names, '/')
endfunction

function! s:compare(a, b) abort
  let l:x = tolower(a:a.name)
  let l:y = tolower(a:b.name)
  if l:x !=# l:y
    return l:x <# l:y ? -1 : 1
  endif
  let l:i = str2nr(a:a.id[1:])
  let l:j = str2nr(a:b.id[1:])
  return l:i == l:j ? 0 : l:i < l:j ? -1 : 1
endfunction

" Direct child folders, by name (case-insensitive) then id number.
function! webmarks#domain#folder#children(folders, parent_id) abort
  let l:list = filter(copy(a:folders), 's:same(v:val.parent_id, a:parent_id)')
  return sort(l:list, function('s:compare'))
endfunction

" Every folder below {folder_id} (not including it).
function! webmarks#domain#folder#descendants(folders, folder_id) abort
  let l:out = []
  let l:queue = [a:folder_id]
  let l:seen = {}
  while !empty(l:queue)
    let l:cur = remove(l:queue, 0)
    for l:f in a:folders
      if s:same(l:f.parent_id, l:cur) && !has_key(l:seen, l:f.id)
        let l:seen[l:f.id] = 1
        call add(l:out, l:f)
        call add(l:queue, l:f.id)
      endif
    endfor
  endwhile
  return l:out
endfunction

" Height of the subtree below {folder_id}: 0 = no child folders.
function! s:height(folders, folder_id, guard) abort
  if a:guard > s:max_depth + 2
    return a:guard
  endif
  let l:h = 0
  for l:f in a:folders
    if s:same(l:f.parent_id, a:folder_id)
      let l:h = max([l:h, 1 + s:height(a:folders, l:f.id, a:guard + 1)])
    endif
  endfor
  return l:h
endfunction

" Can {folder_id} (v:null = a new folder) live under {new_parent_id}?
function! webmarks#domain#folder#validate_parent(folders, folder_id, new_parent_id) abort
  let l:map = s:index(a:folders)
  if a:new_parent_id isnot v:null
        \ && (type(a:new_parent_id) != v:t_string || !has_key(l:map, a:new_parent_id))
    return s:err('not_found', 'folder not found: ' . string(a:new_parent_id))
  endif
  if a:folder_id isnot v:null
    if s:same(a:folder_id, a:new_parent_id)
      return s:err('cyclic_parent', 'cannot move a folder into itself or its descendant')
    endif
    let l:cur = a:new_parent_id
    let l:seen = {}
    while type(l:cur) == v:t_string && has_key(l:map, l:cur) && !has_key(l:seen, l:cur)
      if l:cur ==# a:folder_id
        return s:err('cyclic_parent', 'cannot move a folder into itself or its descendant')
      endif
      let l:seen[l:cur] = 1
      let l:cur = l:map[l:cur].parent_id
    endwhile
  endif
  let l:base = s:depth(l:map, a:new_parent_id)
  let l:below = a:folder_id is v:null ? 0 : s:height(a:folders, a:folder_id, 0)
  if l:base < 0 || l:base + 1 + l:below > s:max_depth
    return s:err('depth_exceeded', 'folders are limited to 2 levels')
  endif
  return s:ok({'changed': v:false})
endfunction

function! webmarks#domain#folder#can_delete(folders, bookmarks, folder_id) abort
  let l:f = webmarks#domain#folder#find(a:folders, a:folder_id)
  if l:f is v:null
    return s:err('not_found', 'folder not found: ' . string(a:folder_id))
  endif
  for l:c in a:folders
    if s:same(l:c.parent_id, a:folder_id)
      return s:err('folder_not_empty', 'folder is not empty: ' . l:f.name)
    endif
  endfor
  for l:b in a:bookmarks
    if s:same(l:b.folder_id, a:folder_id)
      return s:err('folder_not_empty', 'folder is not empty: ' . l:f.name)
    endif
  endfor
  return s:ok({'changed': v:false})
endfunction

" validate(f) -> Result {value}: type/constraint check of a stored folder.
function! webmarks#domain#folder#validate(f) abort
  if type(a:f) != v:t_dict
    return s:invalid('?', 'not an object')
  endif
  let l:id = get(a:f, 'id', v:null)
  if type(l:id) != v:t_string || l:id !~# '^f\d\+$'
    return s:invalid(string(l:id), 'bad id')
  endif
  let l:name = get(a:f, 'name', v:null)
  let l:n = webmarks#domain#text#sanitize(l:name)
  if !l:n.ok || l:n.value !=# l:name
    return s:invalid(l:id, 'bad name')
  endif
  let l:parent = get(a:f, 'parent_id', 0)
  if l:parent isnot v:null && (type(l:parent) != v:t_string || l:parent !~# '^f\d\+$')
    return s:invalid(l:id, 'bad parent_id')
  endif
  return s:ok({'changed': v:false, 'value': {'id': l:id, 'name': l:name, 'parent_id': l:parent}})
endfunction

" validate_all(folders, bookmarks) -> Result: H1..H5 and unique ids.
function! webmarks#domain#folder#validate_all(folders, bookmarks) abort
  let l:map = {}
  for l:f in a:folders
    if has_key(l:map, l:f.id)
      return s:invalid(l:f.id, 'duplicate id')
    endif
    let l:map[l:f.id] = l:f
  endfor
  for l:f in a:folders
    if s:same(l:f.parent_id, l:f.id)
      return s:invalid(l:f.id, 'is its own parent')
    endif
    if l:f.parent_id isnot v:null && !has_key(l:map, l:f.parent_id)
      return s:invalid(l:f.id, 'parent not found: ' . l:f.parent_id)
    endif
    let l:d = s:depth(l:map, l:f.id)
    if l:d < 0
      return s:invalid(l:f.id, 'cyclic parent')
    endif
    if l:d > s:max_depth
      return s:invalid(l:f.id, 'deeper than 2 levels')
    endif
  endfor
  let l:ids = {}
  for l:b in a:bookmarks
    if has_key(l:ids, l:b.id)
      return s:err('invalid_data', 'bookmark ' . l:b.id . ': duplicate id')
    endif
    let l:ids[l:b.id] = 1
    if l:b.folder_id isnot v:null && !has_key(l:map, l:b.folder_id)
      return s:err('invalid_data', 'bookmark ' . l:b.id . ': folder not found: ' . l:b.folder_id)
    endif
  endfor
  return s:ok({'changed': v:false})
endfunction

function! s:invalid(id, detail) abort
  return s:err('invalid_data', 'folder ' . a:id . ': ' . a:detail)
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
