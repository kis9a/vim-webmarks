scriptencoding utf-8
" app/edit.vim - the tree edited as text: parse lines, then apply the
" difference in one store#mutate (all or nothing).
"
"   parse(lines, snapshot_ids)      -> Result {entries, delete_ids, errors}
"   commit(entries, delete_ids, now, shown) -> Result {fetch_title, warnings, counts}
"
" The UI asks for the delete confirmation between the two (app never
" prompts).

let s:save_cpo = &cpoptions
set cpoptions&vim

let s:max_errors = 10
" (documentation of the URL rule; parse_line() implements it directly)
let s:url_token = '\%(^\|\s\+\)\zshttps\?://\S\+$'

function! s:error(errors, lnum, code, msg) abort
  if len(a:errors) < s:max_errors
    call add(a:errors, {'lnum': a:lnum, 'code': a:code,
          \ 'error': (a:lnum > 0 ? 'line ' . a:lnum . ': ' : '') . a:msg})
  endif
endfunction

function! s:failed(errors) abort
  return {'ok': v:false, 'code': a:errors[0].code, 'error': a:errors[0].error,
        \ 'changed': v:false, 'errors': a:errors}
endfunction

" --- parse -------------------------------------------------------------

" One line -> Entry, v:null (ignored line) or an error dict {code, msg}.
function! s:parse_line(text) abort
  let l:line = substitute(a:text, '[[:space:]\r]*$', '', '')
  if l:line =~# '^ *\t'
    return {'code': 'parse_error', 'msg': 'bad indent (use spaces)'}
  endif
  let l:id = ''
  let l:pat = webmarks#app#listing#marker_pattern()
  let [l:mark, l:start, l:end] = matchstrpos(l:line, l:pat)
  if l:start >= 0
    let l:id = matchlist(l:mark, l:pat)[1]
    let l:after = strpart(l:line, l:end)
    if l:after =~# l:pat
      return {'code': 'parse_error', 'msg': 'multiple ids on one line'}
    endif
    " text typed after the (concealed) id, e.g. with A, would silently
    " become part of the URL
    if l:after =~# '\S'
      return {'code': 'parse_error', 'msg': 'text after the hidden id (edit before it, e.g. with $ then i)'}
    endif
    let l:line = substitute(strpart(l:line, 0, l:start), '[[:space:]\r]*$', '', '')
  endif
  if l:line =~# '^\s*$' || l:line =~# '^\s*#'
    return v:null
  endif
  " the URL first: a URL may end with '/' too. The last blank-separated
  " token, when it starts with http(s)://, is the URL (s:url_token; this
  " form avoids a slow backtracking regex on every line).
  let l:url = matchstr(l:line, '\S\+$')
  " a folder marker decides (a folder name may end with a URL-like word)
  if l:id !~# '^f' && l:url =~# '^https\?://'
    let l:rest = strpart(l:line, 0, strlen(l:line) - strlen(l:url))
    let l:h = matchlist(l:rest, webmarks#app#listing#bookmark_head_pattern())
    if empty(l:h) || strlen(l:h[1]) % 2
      return {'code': 'parse_error', 'msg': 'bad indent (bookmark lines need the 2-column star slot)'}
    endif
    let l:u = webmarks#domain#bookmark#validate_url(l:url)
    if !l:u.ok
      return {'code': 'invalid_url', 'msg': l:u.error}
    endif
    return {'kind': 'bookmark', 'id': l:id, 'depth': strlen(l:h[1]) / 2,
          \ 'name': webmarks#app#listing#unescape_name(trim(l:h[3])), 'url': l:u.value, 'favorite': l:h[2] ==# '  ' ? v:false : v:true}
  endif
  if l:line =~# '/$'
    let l:h = matchlist(strpart(l:line, 0, strlen(l:line) - 1), '^\( *\)\(.*\)$')
    if strlen(l:h[1]) % 2
      return {'code': 'parse_error', 'msg': 'bad indent'}
    endif
    let l:depth = strlen(l:h[1]) / 2 + 1
    if l:depth > 2
      return {'code': 'depth_exceeded', 'msg': 'folders are limited to 2 levels'}
    endif
    if webmarks#app#listing#unescape_name(trim(l:h[2])) ==# ''
      return {'code': 'empty_name', 'msg': 'folder name is empty'}
    endif
    if l:id =~# '^b'
      return {'code': 'parse_error', 'msg': 'id ' . l:id . ' belongs to a bookmark'}
    endif
    return {'kind': 'folder', 'id': l:id, 'depth': l:depth, 'name': webmarks#app#listing#unescape_name(trim(l:h[2])),
          \ 'url': '', 'favorite': v:false}
  endif
  if l:id =~# '^f'
    return {'code': 'parse_error', 'msg': 'a folder line must end with /'}
  endif
  return {'code': 'parse_error', 'msg': 'URL is required (or end the line with / for a folder)'}
endfunction

" The column that decides nesting: a folder at depth d sits at 2(d-1),
" a bookmark at depth d at 2d.
function! s:column(e) abort
  return a:e.kind ==# 'folder' ? 2 * (a:e.depth - 1) : 2 * a:e.depth
endfunction

function! webmarks#app#edit#parse(lines, snapshot_ids) abort
  let l:entries = []
  let l:open = []
  let l:errors = []
  let l:seen = {}
  let l:lnum = 0
  for l:text in a:lines
    let l:lnum += 1
    let l:e = s:parse_line(l:text)
    if l:e is v:null
      continue
    endif
    if has_key(l:e, 'code')
      call s:error(l:errors, l:lnum, l:e.code, l:e.msg)
      continue
    endif
    let l:e.lnum = l:lnum
    if l:e.id !=# ''
      if has_key(l:seen, l:e.id)
        call s:error(l:errors, l:lnum, 'parse_error', 'duplicate id ' . l:e.id . ' (also on line ' . l:seen[l:e.id] . ')')
        continue
      endif
      let l:seen[l:e.id] = l:lnum
    endif
    " the tree check: the first line above with a smaller column must be
    " a folder exactly one level up
    " l:open holds the lines above with strictly increasing columns; after
    " popping those at or right of this one, its top is the first line
    " above with a smaller column
    let l:col = s:column(l:e)
    let l:e.col = l:col
    while !empty(l:open) && l:open[-1].col >= l:col
      call remove(l:open, -1)
    endwhile
    let l:e.parent_lnum = 0
    if l:col > 0
      let l:parent = empty(l:open) ? v:null : l:open[-1]
      if l:parent is v:null || l:parent.kind !=# 'folder' || l:parent.col != l:col - 2
        call s:error(l:errors, l:lnum, 'parse_error', 'bad indent (no parent folder at this level)')
        continue
      endif
      let l:e.parent_lnum = l:parent.lnum
    endif
    call add(l:open, l:e)
    call add(l:entries, l:e)
  endfor
  if !empty(l:errors)
    return s:failed(l:errors)
  endif
  let l:delete_ids = filter(copy(a:snapshot_ids), '!has_key(l:seen, v:val)')
  return {'ok': v:true, 'code': '', 'error': '', 'changed': v:false,
        \ 'entries': l:entries, 'delete_ids': l:delete_ids, 'errors': []}
endfunction

" --- commit ------------------------------------------------------------

" commit(entries, delete_ids, now [, shown])
"   shown: id -> {name, url, favorite, parent} as the buffer showed it when
"   edit mode began (app/listing#edit_lines). A field is changed only when
"   its line differs from what was shown, so a title that arrived or a
"   change another Vim made meanwhile is not undone by an unrelated :w.
function! webmarks#app#edit#commit(entries, delete_ids, now, ...) abort
  return webmarks#app#store#mutate(function('s:transform',
        \ [a:entries, a:delete_ids, a:now, get(a:000, 0, {})]))
endfunction

function! s:same(a, b) abort
  return type(a:a) == type(a:b) && a:a ==# a:b
endfunction

" Plan and apply in one go against the freshly read {data}; returns the
" new data (the mutate contract). A line is compared with what was shown
" (or, for an id that was not shown, with the data before this edit), never
" with values changed earlier in the loop. The work is shared through one
" context dict:
"   orig / work      data before / being changed
"   orig_b, orig_f   id -> item of orig
"   at_b, at_f       id -> index into work (no linear scans: an edit of
"                    1,000 lines would otherwise be quadratic)
"   id_of            line number -> id (parents come before children)
"   entry_of         id -> entry
"   errors, warnings, fetch, counts, shown, now
function! s:transform(entries, delete_ids, now, shown, data) abort
  let l:ctx = s:context(a:data, a:shown, a:now)
  for l:e0 in a:entries
    let l:e = copy(l:e0)
    if l:e.id !=# '' && !has_key(l:e.kind ==# 'folder' ? l:ctx.orig_f : l:ctx.orig_b, l:e.id)
      call add(l:ctx.warnings, printf('line %d: %s was removed elsewhere; added again as new', l:e.lnum, l:e.id))
      let l:e.id = ''
    endif
    let l:parent = get(l:ctx.id_of, l:e.parent_lnum, v:null)
    if l:e.kind ==# 'folder'
      call s:apply_folder(l:ctx, l:e, l:parent)
    else
      call s:apply_bookmark(l:ctx, l:e, l:parent)
    endif
  endfor
  call s:apply_deletes(l:ctx, a:delete_ids)
  if empty(l:ctx.errors)
    call s:check_invariants(l:ctx)
  endif
  if !empty(l:ctx.errors)
    return s:failed(l:ctx.errors)
  endif
  return {'ok': v:true, 'code': '', 'error': '', 'changed': l:ctx.work != l:ctx.orig,
        \ 'data': l:ctx.work, 'fetch_title': l:ctx.fetch, 'warnings': l:ctx.warnings,
        \ 'counts': l:ctx.counts}
endfunction

function! s:context(data, shown, now) abort
  let l:ctx = {'orig': a:data, 'work': deepcopy(a:data), 'shown': a:shown, 'now': a:now,
        \ 'errors': [], 'warnings': [], 'fetch': [],
        \ 'counts': {'added': 0, 'renamed': 0, 'moved': 0, 'url_changed': 0,
        \            'favorite_changed': 0, 'deleted': 0},
        \ 'id_of': {0: v:null}, 'entry_of': {},
        \ 'orig_b': {}, 'orig_f': {}, 'at_b': {}, 'at_f': {}}
  for l:b in a:data.bookmarks
    let l:ctx.orig_b[l:b.id] = l:b
  endfor
  for l:f in a:data.folders
    let l:ctx.orig_f[l:f.id] = l:f
  endfor
  for l:i in range(len(l:ctx.work.bookmarks))
    let l:ctx.at_b[l:ctx.work.bookmarks[l:i].id] = l:i
  endfor
  for l:i in range(len(l:ctx.work.folders))
    let l:ctx.at_f[l:ctx.work.folders[l:i].id] = l:i
  endfor
  return l:ctx
endfunction

function! s:new_id(ctx, kind) abort
  let [l:id, a:ctx.work] = webmarks#app#store#next_id(a:ctx.work, a:kind)
  return l:id
endfunction

function! s:apply_folder(ctx, e, parent) abort
  if a:e.id ==# ''
    let l:id = s:new_id(a:ctx, 'f')
    let a:ctx.id_of[a:e.lnum] = l:id
    let l:r = webmarks#domain#folder#new(l:id, a:e.name, a:parent)
    if !l:r.ok
      call s:error(a:ctx.errors, a:e.lnum, l:r.code, l:r.error)
      return
    endif
    let a:ctx.at_f[l:id] = len(a:ctx.work.folders)
    call add(a:ctx.work.folders, l:r.folder)
    let a:ctx.counts.added += 1
    let a:ctx.entry_of[l:id] = a:e
    return
  endif
  let l:id = a:e.id
  let l:before = a:ctx.orig_f[l:id]
  let l:was = get(a:ctx.shown, l:id, {'name': l:before.name, 'parent': l:before.parent_id})
  let l:f = a:ctx.work.folders[a:ctx.at_f[l:id]]
  if a:e.name !=# l:was.name
    let l:r = webmarks#domain#folder#rename(l:f, a:e.name)
    if !l:r.ok
      call s:error(a:ctx.errors, a:e.lnum, l:r.code, l:r.error)
    elseif l:r.folder.name !=# l:f.name
      let l:f = l:r.folder
      let a:ctx.counts.renamed += 1
    endif
  endif
  " only re-parent; depth and cycles are checked once for the whole edit
  " (one by one, a swap of two folders would look invalid half-way)
  if !s:same(l:was.parent, a:parent) && !s:same(l:f.parent_id, a:parent)
    let l:f = webmarks#domain#folder#set_parent(l:f, a:parent).folder
    let a:ctx.counts.moved += 1
  endif
  let a:ctx.work.folders[a:ctx.at_f[l:id]] = l:f
  let a:ctx.id_of[a:e.lnum] = l:id
  let a:ctx.entry_of[l:id] = a:e
endfunction

function! s:apply_bookmark(ctx, e, parent) abort
  if a:e.id ==# ''
    let l:id = s:new_id(a:ctx, 'b')
    let l:r = webmarks#domain#bookmark#new(l:id, a:e.url, a:e.name, a:parent, a:ctx.now)
    if !l:r.ok
      call s:error(a:ctx.errors, a:e.lnum, l:r.code, l:r.error)
      return
    endif
    let l:b = l:r.bookmark
    if a:e.favorite
      let l:b = webmarks#domain#bookmark#toggle_favorite(l:b).bookmark
    endif
    let a:ctx.at_b[l:id] = len(a:ctx.work.bookmarks)
    call add(a:ctx.work.bookmarks, l:b)
    let a:ctx.counts.added += 1
    if l:b.name_source ==# 'url'
      call add(a:ctx.fetch, {'id': l:id, 'url': l:b.url})
    endif
    let a:ctx.entry_of[l:id] = a:e
    return
  endif
  let l:id = a:e.id
  let l:before = a:ctx.orig_b[l:id]
  let l:was = get(a:ctx.shown, l:id, {
        \ 'name': l:before.name_source ==# 'url' ? '' : l:before.display_name,
        \ 'url': l:before.url, 'favorite': l:before.is_favorite, 'parent': l:before.folder_id})
  let l:b = a:ctx.work.bookmarks[a:ctx.at_b[l:id]]
  let l:refetch = 0
  if a:e.url !=# l:was.url && a:e.url !=# l:b.url
    let l:r = webmarks#domain#bookmark#change_url(l:b, a:e.url)
    if !l:r.ok
      call s:error(a:ctx.errors, a:e.lnum, l:r.code, l:r.error)
      return
    endif
    let l:b = l:r.bookmark
    let a:ctx.counts.url_changed += 1
    let l:refetch = l:b.name_source ==# 'url'
  endif
  if a:e.name !=# l:was.name
    if a:e.name ==# ''
      if l:b.name_source !=# 'url'
        " an emptied name: back to the provisional name and fetch a title
        let l:b = webmarks#domain#bookmark#reset_name(l:b).bookmark
        let a:ctx.counts.renamed += 1
        let l:refetch = 1
      endif
    else
      let l:r = webmarks#domain#bookmark#rename(l:b, a:e.name)
      if !l:r.ok
        call s:error(a:ctx.errors, a:e.lnum, l:r.code, l:r.error)
        return
      endif
      if l:r.bookmark.display_name !=# l:b.display_name || l:b.name_source ==# 'url'
        let l:b = l:r.bookmark
        let a:ctx.counts.renamed += 1
        let l:refetch = 0
      endif
    endif
  endif
  let l:fav = a:e.favorite ? 1 : 0
  if l:fav != (l:was.favorite ? 1 : 0) && l:fav != (l:b.is_favorite ? 1 : 0)
    let l:b = webmarks#domain#bookmark#toggle_favorite(l:b).bookmark
    let a:ctx.counts.favorite_changed += 1
  endif
  if !s:same(l:was.parent, a:parent) && !s:same(l:b.folder_id, a:parent)
    let l:b = webmarks#domain#bookmark#move_to(l:b, a:parent).bookmark
    let a:ctx.counts.moved += 1
  endif
  if l:refetch
    call add(a:ctx.fetch, {'id': l:id, 'url': l:b.url})
  endif
  let a:ctx.work.bookmarks[a:ctx.at_b[l:id]] = l:b
  let a:ctx.entry_of[l:id] = a:e
endfunction

" Bookmarks first, then folders; only what is still there. A folder that
" still holds something this buffer did not show (added elsewhere) stays.
function! s:apply_deletes(ctx, delete_ids) abort
  let l:del = {}
  for l:id in a:delete_ids
    let l:del[l:id] = 1
  endfor
  let l:work = a:ctx.work
  let l:before = len(l:work.bookmarks) + len(l:work.folders)
  call filter(l:work.bookmarks, '!has_key(l:del, v:val.id)')
  for l:f in filter(copy(l:work.folders), 'has_key(l:del, v:val.id)')
    let l:blocked = !empty(filter(copy(l:work.folders), '!has_key(l:del, v:val.id) && s:same(v:val.parent_id, l:f.id)'))
          \ || !empty(filter(copy(l:work.bookmarks), 's:same(v:val.folder_id, l:f.id)'))
    if l:blocked
      call s:error(a:ctx.errors, 0, 'folder_not_empty',
            \ 'folder is not empty: ' . l:f.name . ' (it has items that are not in this buffer; :e! to see them)')
    endif
  endfor
  call filter(l:work.folders, '!has_key(l:del, v:val.id)')
  let a:ctx.counts.deleted = l:before - len(l:work.bookmarks) - len(l:work.folders)
endfunction

" The folder invariants (H1..H5) and URL uniqueness over the result.
function! s:check_invariants(ctx) abort
  let l:work = a:ctx.work
  let l:v = webmarks#domain#folder#validate_all(l:work.folders, l:work.bookmarks)
  if !l:v.ok
    call s:error(a:ctx.errors, s:lnum_in(l:v.error, a:ctx.entry_of), l:v.code, l:v.error)
  endif
  " the find_duplicate rule (exact match), indexed by URL
  let l:owner = {}
  for l:b in l:work.bookmarks
    if has_key(l:owner, l:b.url)
      let l:e = get(a:ctx.entry_of, l:b.id, get(a:ctx.entry_of, l:owner[l:b.url], {'lnum': 0}))
      call s:error(a:ctx.errors, l:e.lnum, 'duplicate_url', 'already registered: ' . l:b.url)
    else
      let l:owner[l:b.url] = l:b.id
    endif
  endfor
endfunction

" The line of the item an invariant message names, else 0.
function! s:lnum_in(msg, entry_of) abort
  let l:id = matchstr(a:msg, '\<[bf]\d\+\>')
  return has_key(a:entry_of, l:id) ? a:entry_of[l:id].lnum : 0
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
