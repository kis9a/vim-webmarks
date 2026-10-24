scriptencoding utf-8
" deps/cmd.vim - run an external command synchronously
"
" run(argv, opts) -> {ok, code, error, exit_code: Number, stdout: String}
"   stdout includes stderr (system() merges them on both editors).
"   g:webmarks_test.cmd_runner(argv, opts) replaces the real call.

let s:save_cpo = &cpoptions
set cpoptions&vim

" -1 unknown, 0 no, 1 yes: can system() take a List (no shell)?
" Vim got that in 9.2; 8.2 .. 9.1 raise E730. Neovim always could.
let s:list_argv = -1

function! s:list_argv_supported() abort
  if s:list_argv < 0
    try
      call systemlist(['printf', ''])
      let s:list_argv = 1
    catch /.*/
      let s:list_argv = 0
    endtry
  endif
  return s:list_argv
endfunction

function! s:result(exit_code, stdout) abort
  let l:ok = a:exit_code == 0
  return {'ok': l:ok ? v:true : v:false, 'code': l:ok ? '' : 'exit',
        \ 'error': l:ok ? '' : 'exit ' . a:exit_code,
        \ 'exit_code': a:exit_code, 'stdout': a:stdout}
endfunction

function! webmarks#deps#cmd#run(argv, opts) abort
  if type(a:argv) != v:t_list || empty(a:argv) || type(a:argv[0]) != v:t_string
    return {'ok': v:false, 'code': 'not_executable', 'error': 'command not found: (empty argv)',
          \ 'exit_code': -1, 'stdout': ''}
  endif
  let l:test = get(g:, 'webmarks_test', {})
  if type(l:test) == v:t_dict && has_key(l:test, 'cmd_runner')
    let l:r = call(l:test.cmd_runner, [a:argv, a:opts])
    let l:code = get(l:r, 'exit_code', get(l:r, 'ok', 1) ? 0 : 1)
    return s:result(l:code, get(l:r, 'stdout', ''))
  endif
  if !executable(a:argv[0])
    return {'ok': v:false, 'code': 'not_executable', 'error': 'command not found: ' . a:argv[0],
          \ 'exit_code': -1, 'stdout': ''}
  endif
  try
    if s:list_argv_supported()
      let l:out = system(a:argv)
    else
      let l:out = system(join(map(copy(a:argv), 'shellescape(v:val)'), ' '))
    endif
  catch /.*/
    return s:result(-1, v:exception)
  endtry
  return s:result(v:shell_error, l:out)
endfunction

" Test helper: force the shell-string path (as on Vim 8.2 .. 9.1).
function! webmarks#deps#cmd#_set_list_argv(value) abort
  let s:list_argv = a:value
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
