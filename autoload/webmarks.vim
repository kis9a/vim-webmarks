scriptencoding utf-8
" webmarks.vim - public API: the only place that combines app and ui

let s:save_cpo = &cpoptions
set cpoptions&vim

" add_listener() ignores a listener that is already registered
function! s:listen() abort
  call webmarks#app#title#add_listener(function('webmarks#ui#tree#on_changed'))
endfunction

function! s:refresh(...) abort
  call webmarks#ui#tree#on_changed()
endfunction

" Open the tree (or go to its window).
function! webmarks#open() abort
  call s:listen()
  return webmarks#ui#tree#open()
endfunction

function! webmarks#toggle() abort
  if webmarks#ui#tree#is_open()
    call webmarks#ui#tree#close()
    return
  endif
  call webmarks#open()
endfunction

" add(url, name, folder_id) -> Result. An empty name fetches the title.
function! webmarks#add(url, name, folder_id) abort
  call s:listen()
  let l:r = webmarks#app#bookmark#add(a:url, a:name, a:folder_id, webmarks#compat#clock#now())
  if !l:r.ok
    if l:r.code ==# 'duplicate_url'
      call webmarks#compat#notify#warn(l:r.error)
      call webmarks#ui#tree#focus('bookmark', l:r.existing.id)
    else
      call webmarks#compat#notify#error(l:r.error)
    endif
    return l:r
  endif
  if l:r.fetch_title
    call webmarks#app#title#request(l:r.id, l:r.bookmark.url, 0, webmarks#ui#tree#option('fetch_title'))
  endif
  call webmarks#compat#notify#info('added: ' . l:r.bookmark.display_name)
  " a user command: redraw now (not deferred) so the cursor can follow
  call webmarks#ui#tree#render()
  call webmarks#ui#tree#focus('bookmark', l:r.id)
  return l:r
endfunction

" :WebmarksAdd [url] [name...]
"   url first -> url + name; anything else -> all of it is the name and the
"   URL is asked for; nothing -> ask for both. Always added to the root.
function! webmarks#add_command(qargs) abort
  let l:args = trim(a:qargs)
  let l:first = matchstr(l:args, '^\S\+')
  if l:first =~# '^https\?://'
    return webmarks#add(l:first, trim(matchstr(l:args, '^\S\+\s\+\zs.*')), v:null)
  endif
  let l:url = webmarks#ui#prompt#text('URL: ', matchstr(expand('<cfile>'), '^https\?://\S\+'))
  if !l:url.ok
    if l:url.code !=# 'cancelled'
      call webmarks#compat#notify#error(l:url.error)
    endif
    return l:url
  endif
  if trim(l:url.value) ==# ''
    return {'ok': v:false, 'code': 'cancelled', 'error': '', 'changed': v:false}
  endif
  let l:name = l:args
  if l:name ==# ''
    let l:answer = webmarks#ui#prompt#text('Name (empty = fetch title): ', '')
    if !l:answer.ok
      if l:answer.code !=# 'cancelled'
        call webmarks#compat#notify#error(l:answer.error)
      endif
      return l:answer
    endif
    let l:name = l:answer.value
  endif
  return webmarks#add(l:url.value, l:name, v:null)
endfunction

function! webmarks#search() abort
  call s:listen()
  return webmarks#ui#fzf#run(webmarks#ui#tree#current_policy(), function('s:refresh'))
endfunction

" Open the tree and start editing it as text.
function! webmarks#edit() abort
  let l:r = webmarks#open()
  if l:r.ok
    call webmarks#ui#tree#enter_edit()
  endif
  return l:r
endfunction

function! webmarks#reload() abort
  let l:r = webmarks#app#store#reload()
  if !l:r.ok
    call webmarks#compat#notify#error(l:r.error)
    return l:r
  endif
  for l:w in l:r.warnings
    call webmarks#compat#notify#warn(l:w)
  endfor
  call webmarks#ui#tree#on_changed()
  return l:r
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
