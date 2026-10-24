scriptencoding utf-8
let s:suite = themis#suite('deps_title')
let s:assert = themis#helper('assert')

function! s:suite.before_each() abort
  let s:dir = WebmarksTestReset()
  let s:results = []
endfunction

function! s:suite.after_each() abort
  call delete(s:dir, 'rf')
endfunction

function! s:has_result() abort
  return !empty(s:results)
endfunction

function! s:cb(result, ctx) abort
  call add(s:results, [a:result, a:ctx])
endfunction

function! s:suite.argv_shape() abort
  let l:argv = webmarks#deps#title#argv('https://a.example/-x')
  call s:assert.equals(l:argv[0:2], ['curl', '-q', '-g'])
  call s:assert.equals(l:argv[-2:], ['--', 'https://a.example/-x'])
  let l:i = index(l:argv, '--proto-redir')
  call s:assert.equals(l:argv[l:i + 1], '=http,https')
  let l:j = index(l:argv, '--proto')
  call s:assert.equals(l:argv[l:j + 1], '=http,https')
  call s:assert.equals(l:argv[index(l:argv, '--max-redirs') + 1], '5')
  call s:assert.equals(l:argv[index(l:argv, '--max-filesize') + 1], '1048576')
endfunction

function! s:suite.stub_called_once_and_sanitized() abort
  let g:webmarks_test.title_fetcher = function('WebmarksTestTitle', ["  A\tB  "])
  call s:assert.true(webmarks#deps#title#available())
  call webmarks#deps#title#fetch('https://a.example', function('s:cb'), {'id': 'b1'})
  call s:assert.equals(s:results, [[{'ok': v:true, 'code': '', 'error': '', 'title': 'A B'}, {'id': 'b1'}]])
endfunction

function! s:suite.non_utf8_title_is_fetch_failed() abort
  let g:webmarks_test.title_fetcher = function('WebmarksTestTitle', ["\x83\x65\x83\x58\x83\x67"])
  call webmarks#deps#title#fetch('https://a.example', function('s:cb'), {})
  call s:assert.equals(s:results[0][0].code, 'fetch_failed')
endfunction

function! s:suite.empty_title_is_fetch_failed() abort
  let g:webmarks_test.title_fetcher = function('WebmarksTestTitle', [" ​ "])
  call webmarks#deps#title#fetch('https://a.example', function('s:cb'), {})
  call s:assert.equals(s:results[0][0].code, 'fetch_failed')
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
    call s:assert.true(WebmarksTestWaitUntil(function('s:has_result'), 5000))
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
    call s:assert.true(WebmarksTestWaitUntil(function('s:has_result'), 5000))
  finally
    let $PATH = l:path
  endtry
  call s:assert.equals(s:results[0][0].code, 'fetch_failed')
endfunction
