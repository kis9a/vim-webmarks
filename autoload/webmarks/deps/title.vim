scriptencoding utf-8
" deps/title.vim - fetch a page title asynchronously with curl
"
" available() -> Bool
" fetch(url, Callback, ctx): Callback({ok, code, error, title}, ctx) runs
"   exactly once (possibly synchronously).
" g:webmarks_test.title_fetcher(url, ctx) -> {ok, title | code, error}
"   replaces the network call (the title still goes through sanitize).
"   Returning v:null means the test calls the callback itself later.

let s:save_cpo = &cpoptions
set cpoptions&vim

let s:max_bytes = 1048576

function! s:fetcher() abort
  let l:test = get(g:, 'webmarks_test', {})
  return type(l:test) == v:t_dict && type(get(l:test, 'title_fetcher', 0)) == v:t_func
        \ ? l:test.title_fetcher : v:null
endfunction

function! webmarks#deps#title#available() abort
  if s:fetcher() isnot v:null
    return v:true
  endif
  return webmarks#compat#job#available() && executable('curl')
endfunction

" The curl command line. Only http(s), also on redirects; the URL comes
" after `--` so it can never be read as an option.
function! webmarks#deps#title#argv(url) abort
  return ['curl', '-fsL', '--compressed',
        \ '--proto', '=http,https', '--proto-redir', '=http,https', '--max-redirs', '5',
        \ '--connect-timeout', '5', '--max-time', '10', '--max-filesize', string(s:max_bytes),
        \ '-A', 'Mozilla/5.0 (compatible; vim-webmarks/1.0)', '--', a:url]
endfunction

function! s:failed() abort
  return {'ok': v:false, 'code': 'fetch_failed', 'error': 'title not found', 'title': ''}
endfunction

function! s:finish(raw, Callback, ctx) abort
  let l:r = type(a:raw) == v:t_dict ? a:raw : {}
  let l:result = s:failed()
  if get(l:r, 'ok', v:false) && type(get(l:r, 'title', v:null)) == v:t_string
    let l:s = webmarks#domain#text#sanitize(l:r.title)
    if l:s.ok
      let l:result = {'ok': v:true, 'code': '', 'error': '', 'title': l:s.value}
    endif
  elseif !get(l:r, 'ok', v:false) && get(l:r, 'code', '') ==# 'no_async'
    let l:result = l:r
  endif
  call call(a:Callback, [l:result, a:ctx])
endfunction

function! webmarks#deps#title#fetch(url, Callback, ctx) abort
  let l:F = s:fetcher()
  if l:F isnot v:null
    let l:raw = call(l:F, [a:url, a:ctx])
    " v:null: the test delivers the result itself later
    if l:raw isnot v:null
      call s:finish(l:raw, a:Callback, a:ctx)
    endif
    return
  endif
  if !webmarks#deps#title#available()
    call call(a:Callback, [{'ok': v:false, 'code': 'no_async',
          \ 'error': 'title fetch unavailable (needs curl and +job / jobstart)', 'title': ''}, a:ctx])
    return
  endif
  let l:r = webmarks#compat#job#start(webmarks#deps#title#argv(a:url),
        \ function('s:on_exit', [a:Callback, a:ctx]), {'max_bytes': s:max_bytes})
  if !l:r.ok
    call call(a:Callback, [s:failed(), a:ctx])
  endif
endfunction

function! s:on_exit(Callback, ctx, result) abort
  if a:result.exit_code != 0 && a:result.stdout ==# ''
    call call(a:Callback, [s:failed(), a:ctx])
    return
  endif
  let l:title = webmarks#domain#html#extract_title(a:result.stdout)
  if l:title is v:null
    call call(a:Callback, [s:failed(), a:ctx])
    return
  endif
  call s:finish({'ok': v:true, 'title': l:title}, a:Callback, a:ctx)
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
