scriptencoding utf-8
" test/compat_job.vim - real jobs through compat/job (Vim and Neovim)

let s:suite = themis#suite('compat_job')
let s:assert = themis#helper('assert')

function! s:suite.before_each() abort
  let s:results = []
endfunction

function! s:on_exit(result) abort
  call add(s:results, a:result)
endfunction

function! s:done() abort
  return !empty(s:results)
endfunction

function! s:run(argv, opts) abort
  let l:r = webmarks#compat#job#start(a:argv, function('s:on_exit'), a:opts)
  call s:assert.true(l:r.ok, string(l:r))
  call s:assert.true(WebmarksTestWaitUntil(function('s:done'), 5000), 'timeout')
  " a second callback would show up here
  sleep 50m
  call s:assert.equals(len(s:results), 1)
  return s:results[0]
endfunction

function! s:suite.collects_whole_stdout() abort
  let l:r = s:run(['printf', 'hello\nworld\n'], {})
  call s:assert.equals(l:r.exit_code, 0)
  call s:assert.equals(l:r.stdout, "hello\nworld\n")
endfunction

function! s:suite.no_trailing_newline() abort
  let l:r = s:run(['printf', 'a\nb'], {})
  call s:assert.equals(l:r.stdout, "a\nb")
endfunction

function! s:suite.exit_code() abort
  let l:r = s:run(['sh', '-c', 'exit 3'], {})
  call s:assert.equals(l:r.exit_code, 3)
  call s:assert.equals(l:r.stdout, '')
endfunction

function! s:suite.stderr_is_discarded() abort
  let l:r = s:run(['sh', '-c', 'echo out; echo err >&2'], {})
  call s:assert.equals(l:r.stdout, "out\n")
endfunction

function! s:suite.large_output_is_complete() abort
  " 300 KB: output that arrives in many chunks, after the process exits
  let l:r = s:run(['sh', '-c', 'i=0; while [ $i -lt 3000 ]; do printf "%099d\n" $i; i=$((i+1)); done'], {})
  call s:assert.equals(l:r.exit_code, 0)
  call s:assert.equals(strlen(l:r.stdout), 300000)
  call s:assert.equals(split(l:r.stdout, "\n")[-1], printf('%099d', 2999))
endfunction

function! s:suite.missing_command() abort
  let l:r = webmarks#compat#job#start(['webmarks-no-such-command'], function('s:on_exit'), {})
  call s:assert.false(l:r.ok)
  call s:assert.equals(l:r.code, 'not_executable')
  call s:assert.equals(s:results, [])
endfunction

function! s:suite.empty_argv() abort
  let l:r = webmarks#compat#job#start([], function('s:on_exit'), {})
  call s:assert.equals(l:r.code, 'not_executable')
endfunction

function! s:suite.stops_after_max_bytes() abort
  " an endless producer must be stopped by max_bytes
  let l:start = reltime()
  let l:r = s:run(['sh', '-c', 'while :; do printf "%01023d\n" 0; done'], {'max_bytes': 1048576})
  call s:assert.equals(strlen(l:r.stdout), 1048576)
  call s:assert.true(reltimefloat(reltime(l:start)) < 5.0)
endfunction

function! s:suite.a_fast_endless_producer_is_cut_without_running_out_of_memory() abort
  " `yes` floods the main loop; the result must still be capped
  let l:r = s:run(['yes', 'abcdefghijklmnopqrstuvwxyz0123456789'], {'max_bytes': 1048576})
  call s:assert.equals(strlen(l:r.stdout), 1048576)
endfunction
