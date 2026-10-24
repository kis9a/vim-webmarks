scriptencoding utf-8
" storage/json.vim - read, validate, pretty-print and atomically write
" the bookmarks file (schema_version 1)
"
"   load(path)                      -> Result {data, mtime, warnings, fresh}
"   save(path, data, expected_mtime) -> Result {mtime}
"   encode(data)                    -> Result {lines}
"   decode(lines, path)             -> Result {data, warnings}
"   empty()                         -> a new empty store

let s:save_cpo = &cpoptions
set cpoptions&vim

let s:schema_version = 1

function! s:ok(extra) abort
  return extend({'ok': v:true, 'code': '', 'error': '', 'changed': v:false}, a:extra)
endfunction

function! s:err(code, msg) abort
  return {'ok': v:false, 'code': a:code, 'error': a:msg, 'changed': v:false}
endfunction

function! s:name(path) abort
  return fnamemodify(a:path, ':~')
endfunction

function! webmarks#storage#json#empty() abort
  return {'schema_version': s:schema_version, 'next_id': 1, 'folders': [], 'bookmarks': []}
endfunction

" --- encode ------------------------------------------------------------

function! s:str(s) abort
  " Neovim raises E474 on invalid UTF-8; the caller turns it into save_failed
  return json_encode(a:s)
endfunction

function! s:nullable(v) abort
  return a:v is v:null ? 'null' : s:str(a:v)
endfunction

function! s:by_id(a, b) abort
  let l:x = str2nr(a:a.id[1:])
  let l:y = str2nr(a:b.id[1:])
  return l:x == l:y ? 0 : l:x < l:y ? -1 : 1
endfunction

function! s:encode_folder(f) abort
  return printf('{"id": %s, "name": %s, "parent_id": %s}',
        \ s:str(a:f.id), s:str(a:f.name), s:nullable(a:f.parent_id))
endfunction

function! s:encode_bookmark(b) abort
  let l:u = a:b.usage
  return printf('{"id": %s, "url": %s, "display_name": %s, "name_source": %s, '
        \ . '"folder_id": %s, "is_favorite": %s, "created_at": %d, '
        \ . '"usage": {"rank": %s, "open_count": %d, "last_launch_at": %s}}',
        \ s:str(a:b.id), s:str(a:b.url), s:str(a:b.display_name), s:str(a:b.name_source),
        \ s:nullable(a:b.folder_id), a:b.is_favorite ? 'true' : 'false', a:b.created_at,
        \ printf('%.4f', l:u.rank * 1.0), l:u.open_count,
        \ l:u.last_launch_at is v:null ? 'null' : printf('%d', l:u.last_launch_at))
endfunction

function! s:encode_list(key, items, Fn, last) abort
  if empty(a:items)
    return ['  "' . a:key . '": []' . (a:last ? '' : ',')]
  endif
  let l:lines = ['  "' . a:key . '": [']
  let l:sorted = sort(copy(a:items), function('s:by_id'))
  let l:n = len(l:sorted)
  let l:i = 0
  for l:item in l:sorted
    let l:i += 1
    call add(l:lines, '    ' . call(a:Fn, [l:item]) . (l:i < l:n ? ',' : ''))
  endfor
  call add(l:lines, '  ]' . (a:last ? '' : ','))
  return l:lines
endfunction

" encode(data) -> Result {lines}. Key order is fixed, one element per line.
function! webmarks#storage#json#encode(data) abort
  for l:b in a:data.bookmarks
    let l:r = l:b.usage.rank * 1.0
    if l:r != l:r || l:r < 0.0 || l:r > 1.0e300
      return s:err('invalid_data', 'invalid data: bookmark ' . l:b.id . ': bad usage.rank')
    endif
  endfor
  try
    let l:lines = ['{',
          \ printf('  "schema_version": %d,', s:schema_version),
          \ printf('  "next_id": %d,', a:data.next_id)]
    let l:lines += s:encode_list('folders', a:data.folders, function('s:encode_folder'), 0)
    let l:lines += s:encode_list('bookmarks', a:data.bookmarks, function('s:encode_bookmark'), 1)
    call add(l:lines, '}')
  catch /.*/
    return s:err('save_failed', 'cannot encode data: ' . v:exception)
  endtry
  return s:ok({'lines': l:lines})
endfunction

" --- decode / load -----------------------------------------------------

" decode(lines, path) -> Result {data, warnings}
function! webmarks#storage#json#decode(lines, path) abort
  let l:file = s:name(a:path)
  let l:text = join(a:lines, "\n")
  if l:text =~# '^\_s*$'
    return s:ok({'data': webmarks#storage#json#empty(), 'warnings': []})
  endif
  try
    let l:root = json_decode(l:text)
  catch /.*/
    return s:err('load_failed', 'cannot read ' . l:file . ': ' . substitute(v:exception, '^Vim\%((\a\+)\)\=:', '', ''))
  endtry
  if type(l:root) != v:t_dict
    return s:invalid(l:file, 'top level is not an object')
  endif
  let l:ver = get(l:root, 'schema_version', v:null)
  if type(l:ver) != v:t_number || l:ver < 1
    return s:invalid(l:file, 'missing or bad schema_version')
  endif
  if l:ver > s:schema_version
    return s:err('schema_unsupported', printf('unsupported schema_version %d in %s', l:ver, l:file))
  endif
  let l:next = get(l:root, 'next_id', v:null)
  if type(l:next) != v:t_number || l:next < 1
    return s:invalid(l:file, 'missing or bad next_id')
  endif
  let l:folders_in = get(l:root, 'folders', v:null)
  let l:bookmarks_in = get(l:root, 'bookmarks', v:null)
  if type(l:folders_in) != v:t_list || type(l:bookmarks_in) != v:t_list
    return s:invalid(l:file, 'folders and bookmarks must be arrays')
  endif
  let l:folders = []
  for l:f in l:folders_in
    let l:r = webmarks#domain#folder#validate(l:f)
    if !l:r.ok
      return s:invalid(l:file, l:r.error)
    endif
    call add(l:folders, l:r.value)
  endfor
  let l:bookmarks = []
  for l:b in l:bookmarks_in
    let l:r = webmarks#domain#bookmark#validate(l:b)
    if !l:r.ok
      return s:invalid(l:file, l:r.error)
    endif
    call add(l:bookmarks, l:r.value)
  endfor
  let l:r = webmarks#domain#folder#validate_all(l:folders, l:bookmarks)
  if !l:r.ok
    return s:invalid(l:file, l:r.error)
  endif
  " Business-rule slips from a hand edit are tolerated with a warning so
  " one bad line does not lock the user out.
  let l:warnings = []
  let l:seen = []
  for l:b in l:bookmarks
    let l:dup = webmarks#domain#bookmark#find_duplicate(l:seen, l:b.url, v:null)
    if l:dup isnot v:null
      call add(l:warnings, printf('duplicate URL in %s: %s (%s and %s)', l:file, l:b.url, l:dup.id, l:b.id))
    endif
    call add(l:seen, l:b)
  endfor
  let l:max = 0
  for l:item in l:folders + l:bookmarks
    let l:max = max([l:max, str2nr(l:item.id[1:])])
  endfor
  if l:next <= l:max
    call add(l:warnings, printf('next_id %d in %s is not above existing ids; using %d', l:next, l:file, l:max + 1))
    let l:next = l:max + 1
  endif
  return s:ok({'warnings': l:warnings, 'data': {
        \ 'schema_version': s:schema_version, 'next_id': l:next,
        \ 'folders': l:folders, 'bookmarks': l:bookmarks}})
endfunction

function! s:invalid(file, detail) abort
  return s:err('invalid_data', 'invalid data in ' . a:file . ': ' . a:detail)
endfunction

" load(path) -> Result {data, mtime, warnings, fresh}
function! webmarks#storage#json#load(path) abort
  if !filereadable(a:path)
    return s:ok({'data': webmarks#storage#json#empty(), 'mtime': -1, 'warnings': [], 'fresh': v:true})
  endif
  let l:mtime = getftime(a:path)
  try
    let l:lines = readfile(a:path)
  catch /.*/
    return s:err('load_failed', 'cannot read ' . s:name(a:path) . ': ' . v:exception)
  endtry
  let l:r = webmarks#storage#json#decode(l:lines, a:path)
  if !l:r.ok
    return l:r
  endif
  " leftovers of a crash, possibly from another pid
  for l:tmp in glob(a:path . '.tmp.*', 1, 1)
    call delete(l:tmp)
  endfor
  return s:ok({'data': l:r.data, 'mtime': l:mtime, 'warnings': l:r.warnings, 'fresh': v:false})
endfunction

" --- save --------------------------------------------------------------

" save(path, data, expected_mtime) -> Result {mtime}
" expected_mtime: what load() returned (-1 = the file did not exist).
function! webmarks#storage#json#save(path, data, expected_mtime) abort
  let l:file = s:name(a:path)
  let l:enc = webmarks#storage#json#encode(a:data)
  if !l:enc.ok
    return l:enc
  endif
  if filereadable(a:path) && (a:expected_mtime == -1 || getftime(a:path) != a:expected_mtime)
    return s:err('conflict', l:file . ' was changed by another process; press R and retry')
  endif
  let l:tmp = a:path . '.tmp.' . getpid()
  try
    let l:dir = fnamemodify(a:path, ':h')
    if !isdirectory(l:dir)
      call mkdir(l:dir, 'p')
    endif
    " no 'b' flag: keep the final newline
    if writefile(l:enc.lines, l:tmp) != 0
      throw 'writefile failed'
    endif
    " signed URLs may be stored: owner only
    call setfperm(l:tmp, 'rw-------')
  catch /.*/
    call delete(l:tmp)
    return s:err('save_failed', 'cannot write ' . l:file . ': ' . v:exception)
  endtry
  if rename(l:tmp, a:path) != 0
    call delete(l:tmp)
    return s:err('save_failed', 'cannot write ' . l:file . ': rename failed')
  endif
  return s:ok({'changed': v:true, 'mtime': getftime(a:path)})
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
