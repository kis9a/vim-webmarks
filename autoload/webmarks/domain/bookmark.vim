scriptencoding utf-8
" domain/bookmark.vim - the Bookmark aggregate (usage stats live inside)
"
" Pure: no buffers, files, commands, clock or g: variables. Every
" operation returns a Result and puts a new (deepcopy'd) dict in
" `bookmark`; the input dict is never modified.

let s:save_cpo = &cpoptions
set cpoptions&vim

" http(s) + RFC 3986 reserved/unreserved characters and '%'. Nothing that
" a shell, cmd.exe or an argument parser would reinterpret; no non-ASCII.
let s:url_pattern = '^https\?://[][A-Za-z0-9._~:/?#@!$&''()*+,;=%-]\+$'
let s:url_max = 2048
let s:name_sources = ['manual', 'fetched', 'url']

function! s:ok(extra) abort
  return extend({'ok': v:true, 'code': '', 'error': '', 'changed': v:true}, a:extra)
endfunction

function! s:err(code, msg) abort
  return {'ok': v:false, 'code': a:code, 'error': a:msg, 'changed': v:false}
endfunction

" Result for an operation that produced {new} from {old}.
function! s:result(old, new) abort
  return s:ok({'bookmark': a:new, 'changed': a:new != a:old})
endfunction

" validate_url(url) -> Result {value}
function! webmarks#domain#bookmark#validate_url(url) abort
  if type(a:url) != v:t_string
    return s:err('invalid_url', 'invalid URL (http(s)://, RFC 3986 characters only): ' . string(a:url))
  endif
  let l:v = trim(a:url)
  if l:v !~# s:url_pattern || strlen(l:v) > s:url_max
    return s:err('invalid_url', 'invalid URL (http(s)://, RFC 3986 characters only): '
          \ . strtrans(strcharpart(l:v, 0, 80)))
  endif
  return s:ok({'value': l:v})
endfunction

" new(id, url, name, folder_id, now) -> Result {bookmark}
function! webmarks#domain#bookmark#new(id, url, name, folder_id, now) abort
  let l:u = webmarks#domain#bookmark#validate_url(a:url)
  if !l:u.ok
    return l:u
  endif
  let l:b = {
        \ 'id': a:id,
        \ 'url': l:u.value,
        \ 'display_name': l:u.value,
        \ 'name_source': 'url',
        \ 'folder_id': a:folder_id,
        \ 'is_favorite': v:false,
        \ 'created_at': a:now,
        \ 'usage': {'rank': 0.0, 'open_count': 0, 'last_launch_at': v:null},
        \ }
  if type(a:name) == v:t_string && trim(a:name) ==# ''
    return s:ok({'bookmark': l:b})
  endif
  let l:n = webmarks#domain#text#sanitize(a:name)
  if !l:n.ok
    return l:n
  endif
  let l:b.display_name = l:n.value
  let l:b.name_source = 'manual'
  return s:ok({'bookmark': l:b})
endfunction

function! webmarks#domain#bookmark#rename(b, name) abort
  let l:n = webmarks#domain#text#sanitize(a:name)
  if !l:n.ok
    return l:n
  endif
  let l:new = deepcopy(a:b)
  let l:new.display_name = l:n.value
  let l:new.name_source = 'manual'
  return s:result(a:b, l:new)
endfunction

" Back to the provisional name (= the URL), so a title fetch may fill it.
function! webmarks#domain#bookmark#reset_name(b) abort
  let l:new = deepcopy(a:b)
  let l:new.display_name = l:new.url
  let l:new.name_source = 'url'
  return s:result(a:b, l:new)
endfunction

function! webmarks#domain#bookmark#change_url(b, url) abort
  let l:u = webmarks#domain#bookmark#validate_url(a:url)
  if !l:u.ok
    return l:u
  endif
  let l:new = deepcopy(a:b)
  let l:new.url = l:u.value
  " a provisional name *is* the URL: keep that definition true
  if l:new.name_source ==# 'url'
    let l:new.display_name = l:u.value
  endif
  return s:result(a:b, l:new)
endfunction

" Only replaces a provisional name; never an error.
function! webmarks#domain#bookmark#apply_fetched_title(b, title) abort
  let l:new = deepcopy(a:b)
  if a:b.name_source !=# 'url'
    return s:ok({'bookmark': l:new, 'changed': v:false})
  endif
  let l:n = webmarks#domain#text#sanitize(a:title)
  if !l:n.ok
    return s:ok({'bookmark': l:new, 'changed': v:false})
  endif
  let l:new.display_name = l:n.value
  let l:new.name_source = 'fetched'
  return s:result(a:b, l:new)
endfunction

" Explicit refetch: overwrites even a manual name.
function! webmarks#domain#bookmark#force_title(b, title) abort
  let l:n = webmarks#domain#text#sanitize(a:title)
  if !l:n.ok
    return l:n
  endif
  let l:new = deepcopy(a:b)
  let l:new.display_name = l:n.value
  let l:new.name_source = 'fetched'
  return s:result(a:b, l:new)
endfunction

function! webmarks#domain#bookmark#toggle_favorite(b) abort
  let l:new = deepcopy(a:b)
  let l:new.is_favorite = a:b.is_favorite ? v:false : v:true
  return s:result(a:b, l:new)
endfunction

" Folder existence is the application layer's job (another aggregate).
function! webmarks#domain#bookmark#move_to(b, folder_id) abort
  let l:new = deepcopy(a:b)
  let l:new.folder_id = a:folder_id
  return s:result(a:b, l:new)
endfunction

function! webmarks#domain#bookmark#record_launch(b, now) abort
  let l:new = deepcopy(a:b)
  let l:new.usage.rank = l:new.usage.rank + 1.0
  let l:new.usage.open_count = l:new.usage.open_count + 1
  let l:new.usage.last_launch_at = a:now
  return s:result(a:b, l:new)
endfunction

" The URL uniqueness rule, in one place. Returns the bookmark that owns
" {url} (other than {except_id}), or v:null.
function! webmarks#domain#bookmark#find_duplicate(bookmarks, url, except_id) abort
  for l:b in a:bookmarks
    if l:b.url ==# a:url && !(type(a:except_id) == v:t_string && l:b.id ==# a:except_id)
      return l:b
    endif
  endfor
  return v:null
endfunction

" validate(b) -> Result {value}: type/constraint check of a stored
" bookmark; `value` is the normalized dict (rank as Float, known keys only).
function! webmarks#domain#bookmark#validate(b) abort
  if type(a:b) != v:t_dict
    return s:invalid('?', 'not an object')
  endif
  let l:id = get(a:b, 'id', v:null)
  if type(l:id) != v:t_string || l:id !~# '^b[1-9]\d\{0,8}$'
    return s:invalid(string(l:id), 'bad id')
  endif
  let l:url = get(a:b, 'url', v:null)
  let l:u = webmarks#domain#bookmark#validate_url(l:url)
  if !l:u.ok || l:u.value !=# l:url
    return s:invalid(l:id, 'bad url')
  endif
  let l:name = get(a:b, 'display_name', v:null)
  let l:source = get(a:b, 'name_source', v:null)
  if type(l:source) != v:t_string || index(s:name_sources, l:source) < 0
    return s:invalid(l:id, 'bad name_source')
  endif
  let l:warning = ''
  if l:source ==# 'url'
    " a provisional name is the URL itself (not cut at 200 characters)
    if l:name !=# l:url
      let l:warning = 'bookmark ' . l:id . ': provisional display_name set to the URL'
      let l:name = l:url
    endif
  else
    " a name the current rules would clean (a hand edit, an older version):
    " use the cleaned name and warn, rather than refuse the whole file
    let l:n = webmarks#domain#text#sanitize(l:name)
    if !l:n.ok
      return s:invalid(l:id, 'bad display_name')
    endif
    if l:n.value !=# l:name
      let l:warning = 'bookmark ' . l:id . ': display_name cleaned to ' . string(l:n.value)
      let l:name = l:n.value
    endif
  endif
  let l:folder = get(a:b, 'folder_id', 0)
  if l:folder isnot v:null && (type(l:folder) != v:t_string || l:folder !~# '^f[1-9]\d\{0,8}$')
    return s:invalid(l:id, 'bad folder_id')
  endif
  let l:fav = get(a:b, 'is_favorite', v:null)
  if type(l:fav) != v:t_bool
    return s:invalid(l:id, 'bad is_favorite')
  endif
  let l:created = get(a:b, 'created_at', v:null)
  if type(l:created) != v:t_number || l:created < 0
    return s:invalid(l:id, 'bad created_at')
  endif
  let l:usage = get(a:b, 'usage', v:null)
  if type(l:usage) != v:t_dict
    return s:invalid(l:id, 'bad usage')
  endif
  let l:rank = get(l:usage, 'rank', v:null)
  if index([v:t_number, v:t_float], type(l:rank)) < 0
    return s:invalid(l:id, 'bad usage.rank')
  endif
  let l:rank = l:rank * 1.0
  " NaN is the only value not equal to itself; json_decode() in Vim
  " accepts NaN and Infinity
  if l:rank != l:rank || l:rank < 0.0 || l:rank > 1.0e300
    return s:invalid(l:id, 'bad usage.rank')
  endif
  let l:count = get(l:usage, 'open_count', v:null)
  if type(l:count) != v:t_number || l:count < 0
    return s:invalid(l:id, 'bad usage.open_count')
  endif
  let l:last = get(l:usage, 'last_launch_at', 0)
  if l:last isnot v:null && type(l:last) != v:t_number
    return s:invalid(l:id, 'bad usage.last_launch_at')
  endif
  return s:ok({'changed': v:false, 'warning': l:warning, 'value': {
        \ 'id': l:id,
        \ 'url': l:url,
        \ 'display_name': l:name,
        \ 'name_source': l:source,
        \ 'folder_id': l:folder,
        \ 'is_favorite': l:fav,
        \ 'created_at': l:created,
        \ 'usage': {'rank': l:rank, 'open_count': l:count, 'last_launch_at': l:last},
        \ }})
endfunction

function! s:invalid(id, detail) abort
  return s:err('invalid_data', 'bookmark ' . a:id . ': ' . a:detail)
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
