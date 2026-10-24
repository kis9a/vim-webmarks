scriptencoding utf-8
" deps/browser.vim - find and run the browser command
"
" command() -> Result {argv}
" open(url) -> Result

let s:save_cpo = &cpoptions
set cpoptions&vim

function! s:err(code, msg) abort
  return {'ok': v:false, 'code': a:code, 'error': a:msg, 'changed': v:false}
endfunction

function! webmarks#deps#browser#command() abort
  if exists('g:webmarks_browser_cmd')
    let l:cmd = g:webmarks_browser_cmd
    if type(l:cmd) == v:t_string && l:cmd !=# ''
      " the executable name only; arguments need the List form
      let l:argv = [l:cmd]
    elseif type(l:cmd) == v:t_list && !empty(l:cmd)
          \ && empty(filter(copy(l:cmd), 'type(v:val) != v:t_string'))
      let l:argv = copy(l:cmd)
    else
      return s:err('no_browser', 'no browser command found (set g:webmarks_browser_cmd)')
    endif
    if !executable(l:argv[0]) && !s:stubbed()
      return s:err('not_executable', 'command not found: ' . l:argv[0])
    endif
    return {'ok': v:true, 'code': '', 'error': '', 'changed': v:false, 'argv': l:argv}
  endif
  if has('mac') || has('macunix')
    let l:argv = ['open']
  elseif executable('wslview')
    let l:argv = ['wslview']
  elseif executable('xdg-open')
    let l:argv = ['xdg-open']
  elseif has('win32') || has('win64')
    " not `cmd /c start`: cmd.exe would re-parse the URL
    let l:argv = ['rundll32', 'url.dll,FileProtocolHandler']
  else
    return s:err('no_browser', 'no browser command found (set g:webmarks_browser_cmd)')
  endif
  return {'ok': v:true, 'code': '', 'error': '', 'changed': v:false, 'argv': l:argv}
endfunction

function! s:stubbed() abort
  let l:test = get(g:, 'webmarks_test', {})
  return type(l:test) == v:t_dict && type(get(l:test, 'cmd_runner', 0)) == v:t_func
endfunction

function! webmarks#deps#browser#open(url) abort
  let l:cmd = webmarks#deps#browser#command()
  if !l:cmd.ok
    return l:cmd
  endif
  " stored data may have been edited by hand: check again right before use
  let l:u = webmarks#domain#bookmark#validate_url(a:url)
  if !l:u.ok
    return l:u
  endif
  let l:r = webmarks#deps#cmd#run(l:cmd.argv + [l:u.value], {})
  if l:r.code ==# 'not_executable'
    return s:err('not_executable', l:r.error)
  endif
  if l:r.exit_code != 0
    return s:err('browser_failed', printf('browser command failed (exit %d): %s', l:r.exit_code, l:cmd.argv[0]))
  endif
  return {'ok': v:true, 'code': '', 'error': '', 'changed': v:false}
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
