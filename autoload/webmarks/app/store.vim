scriptencoding utf-8
" app/store.vim - the in-memory copy, reloading, id allocation and the
" single entry point for changes (mutate). The only caller of storage.

let s:save_cpo = &cpoptions
set cpoptions&vim

let s:data = v:null
let s:mtime = -1
let s:loaded_path = ''

function! s:err(code, msg) abort
  return {'ok': v:false, 'code': a:code, 'error': a:msg, 'changed': v:false}
endfunction

" The data file path (g:webmarks_file, else XDG data dir).
function! webmarks#app#store#path() abort
  let l:file = get(g:, 'webmarks_file', '')
  if type(l:file) == v:t_string && l:file !=# ''
    " not expand(): '%' and '#' in a path must stay literal
    return fnamemodify(substitute(l:file, '^\~', escape(expand('~'), '\&'), ''), ':p')
  endif
  let l:base = $XDG_DATA_HOME
  if l:base ==# ''
    let l:base = expand('~') . '/.local/share'
  endif
  return fnamemodify(l:base . '/webmarks/bookmarks.json', ':p')
endfunction

function! s:loaded() abort
  return s:data isnot v:null && s:loaded_path ==# webmarks#app#store#path()
endfunction

" A deepcopy of the last data read. Loads on first use; an empty store if
" that fails (showing the error is the job of whoever calls reload()).
function! webmarks#app#store#current() abort
  if !s:loaded()
    let l:r = webmarks#app#store#reload()
    if !l:r.ok
      return webmarks#storage#json#empty()
    endif
  endif
  return deepcopy(s:data)
endfunction

" reload() -> Result {warnings}. On failure the memory copy is kept.
function! webmarks#app#store#reload() abort
  let l:path = webmarks#app#store#path()
  let l:r = webmarks#storage#json#load(l:path)
  if !l:r.ok
    return l:r
  endif
  let s:data = l:r.data
  let s:mtime = l:r.mtime
  let s:loaded_path = l:path
  return {'ok': v:true, 'code': '', 'error': '', 'changed': v:false, 'warnings': l:r.warnings}
endfunction

" mutate(Fn) -> Result. The single entry point for every change.
"   Fn(data) gets a fresh copy of the file's current data and returns a
"   Result; when it is ok and changed it must carry the new data in
"   `data`. Fn must be a pure transformation: on a write conflict it is
"   applied once more to the re-read data.
function! webmarks#app#store#mutate(Fn) abort
  let l:path = webmarks#app#store#path()
  let l:attempt = 0
  while 1
    let l:attempt += 1
    let l:loaded = webmarks#storage#json#load(l:path)
    if !l:loaded.ok
      " never overwrite a file we could not read
      return l:loaded
    endif
    try
      let l:r = call(a:Fn, [deepcopy(l:loaded.data)])
    catch /.*/
      return s:err('internal_error', 'internal error: ' . v:exception . ' @ ' . v:throwpoint)
    endtry
    if !l:r.ok
      return l:r
    endif
    if !get(l:r, 'changed', v:true)
      let s:data = l:loaded.data
      let s:mtime = l:loaded.mtime
      let s:loaded_path = l:path
      return extend(s:strip(l:r), {'changed': v:false})
    endif
    let l:saved = webmarks#storage#json#save(l:path, l:r.data, l:loaded.mtime)
    if !l:saved.ok
      if l:saved.code ==# 'conflict' && l:attempt < 2
        continue
      endif
      return l:saved
    endif
    let s:data = l:r.data
    let s:mtime = l:saved.mtime
    let s:loaded_path = l:path
    return extend(s:strip(l:r), {'changed': v:true})
  endwhile
endfunction

function! s:strip(r) abort
  if has_key(a:r, 'data')
    call remove(a:r, 'data')
  endif
  return a:r
endfunction

" next_id(data, kind) -> [id, data']; kind is 'b' or 'f' (one counter).
function! webmarks#app#store#next_id(data, kind) abort
  let l:data = copy(a:data)
  let l:id = printf('%s%d', a:kind, l:data.next_id)
  let l:data.next_id = l:data.next_id + 1
  return [l:id, l:data]
endfunction

function! webmarks#app#store#find_bookmark(data, id) abort
  for l:b in a:data.bookmarks
    if l:b.id ==# a:id
      return l:b
    endif
  endfor
  return v:null
endfunction

function! webmarks#app#store#find_folder(data, id) abort
  if type(a:id) != v:t_string
    return v:null
  endif
  for l:f in a:data.folders
    if l:f.id ==# a:id
      return l:f
    endif
  endfor
  return v:null
endfunction

" Replace the bookmark/folder with the same id; returns data'.
function! webmarks#app#store#put_bookmark(data, b) abort
  let l:data = copy(a:data)
  let l:data.bookmarks = map(copy(a:data.bookmarks), 'v:val.id ==# a:b.id ? a:b : v:val')
  return l:data
endfunction

function! webmarks#app#store#put_folder(data, f) abort
  let l:data = copy(a:data)
  let l:data.folders = map(copy(a:data.folders), 'v:val.id ==# a:f.id ? a:f : v:val')
  return l:data
endfunction

" Test helper: forget the memory copy.
function! webmarks#app#store#_reset() abort
  let s:data = v:null
  let s:mtime = -1
  let s:loaded_path = ''
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
