scriptencoding utf-8
let s:suite = themis#suite('deps_title')
let s:assert = themis#helper('assert')

function! s:suite.before_each() abort
  let s:dir = WebmarksTestReset()
  let s:results = []
  call webmarks#deps#title#_use_mdlink(1)
endfunction

function! s:suite.after_each() abort
  call webmarks#deps#title#_use_mdlink(1)
  call delete(s:dir, 'rf')
endfunction

function! s:cb(result, ctx) abort
  call add(s:results, [a:result, a:ctx])
endfunction

function! s:suite.argv_shape() abort
  let l:argv = webmarks#deps#title#argv('https://a.example/-x')
  call s:assert.equals(l:argv[0], 'curl')
  call s:assert.equals(l:argv[-2:], ['--', 'https://a.example/-x'])
  let l:i = index(l:argv, '--proto-redir')
  call s:assert.equals(l:argv[l:i + 1], '=http,https')
  let l:j = index(l:argv, '--proto')
  call s:assert.equals(l:argv[l:j + 1], '=http,https')
  call s:assert.equals(l:argv[index(l:argv, '--max-redirs') + 1], '5')
  call s:assert.equals(l:argv[index(l:argv, '--max-filesize') + 1], '1048576')
endfunction

function! s:suite.stub_called_once_and_sanitized() abort
  let g:webmarks_test.title_fetcher = {url, ctx -> {'ok': v:true, 'title': "  A\tB  "}}
  call s:assert.true(webmarks#deps#title#available())
  call webmarks#deps#title#fetch('https://a.example', function('s:cb'), {'id': 'b1'})
  call s:assert.equals(s:results, [[{'ok': v:true, 'code': '', 'error': '', 'title': 'A B'}, {'id': 'b1'}]])
endfunction

function! s:suite.non_utf8_title_is_fetch_failed() abort
  let g:webmarks_test.title_fetcher = {url, ctx -> {'ok': v:true, 'title': "\x83\x65\x83\x58\x83\x67"}}
  call webmarks#deps#title#fetch('https://a.example', function('s:cb'), {})
  call s:assert.equals(s:results[0][0].code, 'fetch_failed')
endfunction

function! s:suite.empty_title_is_fetch_failed() abort
  let g:webmarks_test.title_fetcher = {url, ctx -> {'ok': v:true, 'title': " ​ "}}
  call webmarks#deps#title#fetch('https://a.example', function('s:cb'), {})
  call s:assert.equals(s:results[0][0].code, 'fetch_failed')
endfunction

function! s:suite.builtin_extract() abort
  call webmarks#deps#title#_use_mdlink(0)
  let l:E = function('webmarks#deps#title#extract')
  call s:assert.equals(l:E('<html><head><title> Hello &amp; &lt;World&gt; </title></head></html>'), 'Hello & <World>')
  call s:assert.equals(l:E("<head><TITLE lang=en>\n  multi\n  line </TITLE></head>"), 'multi line')
  call s:assert.equals(l:E('<head><title>&#26085;&#x672C; &amp;lt;</title></head>'), '日本 &lt;')
  call s:assert.equals(l:E('<head><title>Real</title></head><body><svg><title>Icon</title></svg></body>'), 'Real')
  call s:assert.equals(l:E('<body><title>a</title><title> </title><title>b</title></body>'), 'b')
  call s:assert.equals(l:E('<head><title><b>bold</b> x</title></head>'), 'bold x')
  call s:assert.equals(l:E('<head><title>&#0;&#xD800;ok</title></head>'), 'ok')
  call s:assert.equals(l:E('no title'), v:null)
  call s:assert.equals(l:E(''), v:null)
endfunction

function! s:suite.mdlink_missing_falls_back() abort
  " mdlink is not on 'runtimepath' in the test: E117 -> built-in
  call s:assert.equals(webmarks#deps#title#extract('<title>x</title>'), 'x')
endfunction

function! s:suite.mdlink_used_when_loadable() abort
  let l:mdlink = expand('~/.vim/plugged/mdlink')
  if !isdirectory(l:mdlink)
    call themis#log('mdlink not installed; skipped')
    return
  endif
  execute 'set runtimepath+=' . fnameescape(l:mdlink)
  try
    call s:assert.equals(webmarks#deps#title#extract('<head><title> M </title></head>'), 'M')
    call s:assert.true(exists('*mdlink#core#extractTitleFromHtml'))
  finally
    execute 'set runtimepath-=' . fnameescape(l:mdlink)
  endtry
endfunction

function! s:suite.real_job_with_a_fake_curl() abort
  " a `curl` on PATH that prints HTML: exercises job + extraction
  let l:bin = s:dir . '/bin'
  call mkdir(l:bin, 'p')
  call writefile(['#!/bin/sh', 'for a in "$@"; do last="$a"; done',
        \ 'printf "<html><head><title>Page %s</title></head></html>" "$last"'], l:bin . '/curl')
  call setfperm(l:bin . '/curl', 'rwx------')
  let l:path = $PATH
  let $PATH = l:bin . ':' . $PATH
  try
    call webmarks#deps#title#fetch('https://a.example/x', function('s:cb'), {'id': 'b1'})
    call s:assert.true(WebmarksTestWaitUntil({-> !empty(s:results)}, 5000))
  finally
    let $PATH = l:path
  endtry
  call s:assert.equals(s:results[0][0].title, 'Page https://a.example/x')
  call s:assert.equals(s:results[0][1], {'id': 'b1'})
endfunction

function! s:suite.real_job_failure() abort
  let l:bin = s:dir . '/bin'
  call mkdir(l:bin, 'p')
  call writefile(['#!/bin/sh', 'exit 22'], l:bin . '/curl')
  call setfperm(l:bin . '/curl', 'rwx------')
  let l:path = $PATH
  let $PATH = l:bin . ':' . $PATH
  try
    call webmarks#deps#title#fetch('https://a.example/x', function('s:cb'), {})
    call s:assert.true(WebmarksTestWaitUntil({-> !empty(s:results)}, 5000))
  finally
    let $PATH = l:path
  endtry
  call s:assert.equals(s:results[0][0].code, 'fetch_failed')
endfunction
