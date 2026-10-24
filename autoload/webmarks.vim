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

let s:how = ['vsplit', 'split', 'edit', 'tab']

" '' or a valid way to open, else an error Result
function! s:check_how(args) abort
  let l:how = trim(get(a:args, 0, ''))
  if l:how ==# '' || index(s:how, l:how) >= 0
    return {'ok': v:true, 'how': l:how}
  endif
  let l:msg = printf('unknown way to open: %s (%s)', l:how, join(s:how, ', '))
  call webmarks#compat#notify#error(l:msg)
  return {'ok': v:false, 'code': 'bad_option', 'error': l:msg, 'changed': v:false}
endfunction

" Open the tree (or go to its window). [how]: vsplit / split / edit / tab;
" 'edit' uses the current window (default: g:webmarks_open).
function! webmarks#open(...) abort
  let l:c = s:check_how(a:000)
  if !l:c.ok
    return l:c
  endif
  call s:listen()
  return webmarks#ui#tree#open(l:c.how)
endfunction

" Open or close. With 'edit' (argument or g:webmarks_open) only the
" current window counts, like netrw's :Explore / :Rexplore: the tree goes
" back to where it came from, any other buffer is replaced by the tree.
function! webmarks#toggle(...) abort
  let l:c = s:check_how(a:000)
  if !l:c.ok
    return l:c
  endif
  let l:how = l:c.how ==# '' ? webmarks#ui#tree#option('open') : l:c.how
  if l:how ==# 'edit' ? webmarks#ui#tree#is_current() : webmarks#ui#tree#is_open()
    call webmarks#ui#tree#close()
    return {'ok': v:true, 'code': '', 'error': '', 'changed': v:false}
  endif
  return webmarks#open(l:c.how)
endfunction

" Completion for the [how] argument of :Webmarks and friends.
function! webmarks#complete_open(arg, line, pos) abort
  return filter(copy(s:how), 'stridx(v:val, a:arg) == 0')
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
  " any scheme:// is meant as a URL (and refused if not http(s))
  if l:first =~# '^\a[[:alnum:]+.-]*://'
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
function! webmarks#edit(...) abort
  let l:r = call('webmarks#open', a:000)
  if !l:r.ok
    return l:r
  endif
  return webmarks#ui#tree#enter_edit()
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
