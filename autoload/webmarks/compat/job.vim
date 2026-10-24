scriptencoding utf-8
" compat/job.vim - asynchronous jobs (Vim job_start / Neovim jobstart)
"
" start(argv, OnExit, opts) -> Result {ok, code, error, job}
"   OnExit({'exit_code': Number, 'stdout': String}) is called exactly once.
"   opts.max_bytes (Number, 0 = unlimited): stop the job once this many
"   bytes of stdout have arrived and finish with what was collected.
"   stderr is discarded.

let s:save_cpo = &cpoptions
set cpoptions&vim

function! s:err(code, msg) abort
  return {'ok': v:false, 'code': a:code, 'error': a:msg, 'changed': v:false}
endfunction

function! webmarks#compat#job#available() abort
  return has('nvim') ? exists('*jobstart') : (has('job') && exists('*job_start'))
endfunction

function! webmarks#compat#job#start(argv, OnExit, opts) abort
  if type(a:argv) != v:t_list || empty(a:argv)
    return s:err('not_executable', 'command not found: (empty argv)')
  endif
  " Neovim's jobstart() prints E475 for a missing command; check first.
  if !executable(a:argv[0])
    return s:err('not_executable', 'command not found: ' . a:argv[0])
  endif
  if !webmarks#compat#job#available()
    return s:err('no_async', 'jobs are not available')
  endif
  let l:ctx = {
        \ 'chunks': [], 'bytes': 0, 'max': get(a:opts, 'max_bytes', 0),
        \ 'stopped': 0, 'closed': 0, 'exited': 0, 'exit_code': -1,
        \ 'done': 0, 'Cb': a:OnExit, 'job': v:null,
        \ }
  if has('nvim')
    return s:start_nvim(a:argv, l:ctx)
  endif
  return s:start_vim(a:argv, l:ctx)
endfunction

" Stop a job returned by start(). Safe to call on a finished job.
function! webmarks#compat#job#stop(job) abort
  try
    if has('nvim')
      call jobstop(a:job)
    else
      call job_stop(a:job)
    endif
  catch /.*/
  endtry
endfunction

function! s:finish(ctx) abort
  if a:ctx.done
    return
  endif
  let a:ctx.done = 1
  let l:out = join(a:ctx.chunks, '')
  if a:ctx.max > 0 && strlen(l:out) > a:ctx.max
    let l:out = strpart(l:out, 0, a:ctx.max)
  endif
  let a:ctx.chunks = []
  call call(a:ctx.Cb, [{'exit_code': a:ctx.exit_code, 'stdout': l:out}])
endfunction

function! s:collect(ctx, text) abort
  if a:ctx.stopped
    return
  endif
  call add(a:ctx.chunks, a:text)
  let a:ctx.bytes += strlen(a:text)
  if a:ctx.max > 0 && a:ctx.bytes > a:ctx.max
    let a:ctx.stopped = 1
    if has('nvim')
      " stop reading at once; the process is stopped next
      silent! call chanclose(a:ctx.job, 'stdout')
    endif
    call webmarks#compat#job#stop(a:ctx.job)
  endif
endfunction

" --- Vim ---------------------------------------------------------------
" exit_cb may run before the last out_cb (":help job-exit_cb"), close_cb
" marks the end of output (":help close_cb"): finish when both arrived.

function! s:vim_out(ctx, channel, msg) abort
  call s:collect(a:ctx, a:msg)
endfunction

function! s:vim_close(ctx, channel) abort
  let a:ctx.closed = 1
  if a:ctx.exited
    call s:finish(a:ctx)
  endif
endfunction

function! s:vim_exit(ctx, job, status) abort
  let a:ctx.exited = 1
  let a:ctx.exit_code = a:status
  if a:ctx.closed
    call s:finish(a:ctx)
  endif
endfunction

function! s:start_vim(argv, ctx) abort
  try
    let l:job = job_start(a:argv, {
          \ 'out_mode': 'raw',
          \ 'out_cb': function('s:vim_out', [a:ctx]),
          \ 'err_io': 'null',
          \ 'in_io': 'null',
          \ 'close_cb': function('s:vim_close', [a:ctx]),
          \ 'exit_cb': function('s:vim_exit', [a:ctx]),
          \ })
  catch /.*/
    call s:finish(a:ctx)
    return {'ok': v:true, 'code': '', 'error': '', 'changed': v:false, 'job': v:null}
  endtry
  let a:ctx.job = l:job
  if job_status(l:job) ==# 'fail'
    " Windows: the command could not be started at all
    call s:finish(a:ctx)
  endif
  return {'ok': v:true, 'code': '', 'error': '', 'changed': v:false, 'job': l:job}
endfunction

" --- Neovim ------------------------------------------------------------
" on_stdout is streamed (not stdout_buffered) so max_bytes can stop the
" job early. Neovim delivers on_exit only after the output streams are
" closed; test/compat_job.vim checks that with a 300 KB payload.

function! s:nvim_out(ctx, job, data, event) abort
  " data is a list of lines split on NL; consecutive callbacks continue
  " the previous last element. Re-joining with NL restores the bytes.
  if a:ctx.stopped || a:data == ['']
    return
  endif
  if a:ctx.max > 0
    " one callback can carry many MiB when the main loop was busy: take
    " only the lines needed, never join the whole List
    let l:need = a:ctx.max - a:ctx.bytes
    let l:take = []
    let l:size = 0
    for l:line in a:data
      call add(l:take, l:line)
      let l:size += strlen(l:line) + 1
      if l:size > l:need
        break
      endif
    endfor
    call s:collect(a:ctx, join(l:take, "\n"))
  else
    call s:collect(a:ctx, join(a:data, "\n"))
  endif
endfunction

function! s:nvim_exit(ctx, job, status, event) abort
  let a:ctx.exit_code = a:status
  call s:finish(a:ctx)
endfunction

function! s:start_nvim(argv, ctx) abort
  try
    let l:job = jobstart(a:argv, {
          \ 'on_stdout': function('s:nvim_out', [a:ctx]),
          \ 'on_stderr': function('s:nvim_ignore'),
          \ 'on_exit': function('s:nvim_exit', [a:ctx]),
          \ 'stdin': 'null',
          \ })
  catch /.*/
    let l:job = -1
  endtry
  if l:job <= 0
    call s:finish(a:ctx)
    return {'ok': v:true, 'code': '', 'error': '', 'changed': v:false, 'job': v:null}
  endif
  let a:ctx.job = l:job
  return {'ok': v:true, 'code': '', 'error': '', 'changed': v:false, 'job': l:job}
endfunction

function! s:nvim_ignore(...) abort
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
