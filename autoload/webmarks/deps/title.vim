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
  return type(l:test) == v:t_dict && has_key(l:test, 'title_fetcher') ? l:test.title_fetcher : v:null
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
  let l:title = webmarks#deps#title#extract(a:result.stdout)
  if l:title is v:null
    call call(a:Callback, [s:failed(), a:ctx])
    return
  endif
  call s:finish({'ok': v:true, 'title': l:title}, a:Callback, a:ctx)
endfunction

" extract(html) -> String or v:null. Uses mdlink's pure extractor when it
" can be loaded (a lazily loaded mdlink is E117 until its command runs),
" else the built-in copy of the same rules.
function! webmarks#deps#title#extract(html) abort
  if get(s:, 'use_mdlink', 1)
    try
      return mdlink#core#extractTitleFromHtml(a:html)
    catch /E117/
    catch /.*/
    endtry
  endif
  return webmarks#deps#title#builtin_extract(a:html)
endfunction

" Test helper: 0 forces the built-in extractor.
function! webmarks#deps#title#_use_mdlink(flag) abort
  let s:use_mdlink = a:flag
endfunction

" Same rules as mdlink: prefer <head>, the last non-empty <title>, strip
" tags, decode entities, squeeze whitespace, trim. No charset handling.
function! webmarks#deps#title#builtin_extract(html) abort
  if type(a:html) != v:t_string || a:html ==# ''
    return v:null
  endif
  let l:target = a:html
  let l:head = matchstr(a:html, '\c<head\%(\s\+[^>]*\)\?>\_.\{-}</head>')
  if l:head !=# ''
    let l:target = l:head
  endif
  let l:pattern = '\c<title\%(\s\+[^>]*\)\?>\s*\(\_.\{-}\)\s*</title>'
  let l:last = v:null
  let l:pos = 0
  while 1
    let [l:str, l:start, l:end] = matchstrpos(l:target, l:pattern, l:pos)
    if l:start < 0
      break
    endif
    let l:content = matchstr(l:str, '\c<title\%(\s\+[^>]*\)\?>\s*\zs\_.\{-}\ze\s*</title>')
    let l:content = substitute(l:content, '<[^>]*>', '', 'g')
    let l:content = s:decode_entities(l:content)
    let l:content = trim(substitute(l:content, '\_s\+', ' ', 'g'))
    if l:content !=# ''
      let l:last = l:content
    endif
    let l:pos = l:end
  endwhile
  return l:last
endfunction

function! s:char(nr) abort
  " never produce NUL or a surrogate / out-of-range code point
  if a:nr <= 0 || a:nr > 0x10FFFF || (a:nr >= 0xD800 && a:nr <= 0xDFFF)
    return ''
  endif
  return nr2char(a:nr, 1)
endfunction

function! s:decode_entities(text) abort
  let l:r = substitute(a:text, '&#\(\d\{1,7}\);', '\=s:char(str2nr(submatch(1)))', 'g')
  let l:r = substitute(l:r, '\c&#x\(\x\{1,6}\);', '\=s:char(str2nr(submatch(1), 16))', 'g')
  let l:r = substitute(l:r, '&lt;', '<', 'g')
  let l:r = substitute(l:r, '&gt;', '>', 'g')
  let l:r = substitute(l:r, '&quot;', '"', 'g')
  let l:r = substitute(l:r, '&#39;\|&apos;', "'", 'g')
  let l:r = substitute(l:r, '&nbsp;', ' ', 'g')
  " last, so "&amp;lt;" stays "&lt;"
  let l:r = substitute(l:r, '&amp;', '\&', 'g')
  return l:r
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
