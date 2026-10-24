scriptencoding utf-8
" test/ui_tree.vim - the tree buffer, driven through its key mappings

let s:suite = themis#suite('ui_tree')
let s:assert = themis#helper('assert')

function! s:suite.before_each() abort
  let s:dir = WebmarksTestReset()
  call webmarks#app#store#_reset()
  call webmarks#app#title#_reset()
  unlet! g:loaded_webmarks
  runtime plugin/webmarks.vim
  let s:opened = []
  let s:texts = []
  let s:folder_answer = v:null
  let s:confirm = 1
  let g:webmarks_browser_cmd = ['fake-browser']
  let g:webmarks_test.cmd_runner = function('s:runner')
  let g:webmarks_test.prompt = {
        \ 'text': function('s:text'),
        \ 'choose_folder': function('s:choose_folder'),
        \ 'confirm': function('s:confirm'),
        \ }
  messages clear
endfunction

function! s:suite.after_each() abort
  silent! tabonly!
  silent! only!
  enew!
  let l:buf = webmarks#ui#tree#bufnr()
  if l:buf > 0
    execute 'silent! bwipeout!' l:buf
  endif
  call delete(s:dir, 'rf')
endfunction

function! s:choose_folder(data, exclude) abort
  return s:folder_answer
endfunction

function! s:confirm(msg) abort
  return s:confirm
endfunction

function! s:runner(argv, opts) abort
  call add(s:opened, a:argv[-1])
  return {'exit_code': 0, 'stdout': ''}
endfunction

" prompt.text answers from a queue; an empty queue means CTRL-C
function! s:text(prompt, default) abort
  if empty(s:texts)
    return {'ok': v:false, 'code': 'cancelled', 'error': ''}
  endif
  return remove(s:texts, 0)
endfunction

function! s:seed() abort
  " root: b1 Alpha, b2 zeta (favorite) / f3 Dev > f4 Docs > b5 Guide, b6 Tool in Dev
  call webmarks#app#bookmark#add('https://alpha.example', 'Alpha', v:null, 1)
  call webmarks#app#bookmark#add('https://zeta.example', 'zeta', v:null, 1)
  call webmarks#app#bookmark#toggle_favorite('b2')
  call webmarks#app#folder#add('Dev', v:null)
  call webmarks#app#folder#add('Docs', 'f3')
  call webmarks#app#bookmark#add('https://guide.example', 'Guide', 'f4', 1)
  call webmarks#app#bookmark#add('https://tool.example', 'Tool', 'f3', 1)
endfunction

function! s:lnum(id) abort
  let l:i = 0
  for l:row in b:webmarks.rows
    let l:i += 1
    if l:row.id ==# a:id
      return l:i
    endif
  endfor
  return 0
endfunction

function! s:press(keys) abort
  execute 'normal' a:keys
endfunction

function! s:suite.open_vsplit_and_close() abort
  call s:seed()
  Webmarks
  call s:assert.equals(winnr('$'), 2)
  call s:assert.equals(winwidth(0), 40)
  call s:assert.equals(bufname('%'), 'webmarks://webmarks')
  call s:assert.equals([&buftype, &bufhidden, &swapfile, &buflisted, &modifiable, &filetype],
        \ ['acwrite', 'hide', 0, 0, 0, 'webmarks'])
  call s:assert.equals(map(copy(b:webmarks.rows), 'v:val.text'), getline(1, '$'))
  " :Webmarks again goes to the existing window
  wincmd p
  Webmarks
  call s:assert.equals(winnr('$'), 2)
  call s:assert.equals(bufname('%'), 'webmarks://webmarks')
  call s:press('q')
  call s:assert.equals(winnr('$'), 1)
  call s:assert.not_equals(bufname('%'), 'webmarks://webmarks')
endfunction

function! s:suite.close_as_only_window_enews() abort
  Webmarks
  only
  call s:press('q')
  call s:assert.equals([winnr('$'), tabpagenr('$')], [1, 1])
  call s:assert.equals(bufname('%'), '')
endfunction

function! s:suite.open_modes() abort
  let g:webmarks_open = 'split'
  Webmarks
  call s:assert.equals(winnr('$'), 2)
  call s:assert.equals(winwidth(0), &columns)
  call s:press('q')
  let g:webmarks_open = 'tab'
  Webmarks
  call s:assert.equals(tabpagenr('$'), 2)
  call s:press('q')
  call s:assert.equals(tabpagenr('$'), 1)
  let g:webmarks_open = 'edit'
  edit! foo.txt
  Webmarks
  call s:assert.equals(winnr('$'), 1)
  call s:press('q')
  call s:assert.equals(fnamemodify(bufname('%'), ':t'), 'foo.txt')
  bwipeout! foo.txt
endfunction

function! s:suite.toggle() abort
  WebmarksToggle
  call s:assert.equals(winnr('$'), 2)
  wincmd p
  WebmarksToggle
  call s:assert.equals(winnr('$'), 1)
endfunction

function! s:suite.bad_option_falls_back_with_warning() abort
  let g:webmarks_open = 'sideways'
  let g:webmarks_width = 'x'
  Webmarks
  call s:assert.equals(winwidth(0), 40)
  call s:assert.match(execute('messages'), 'invalid g:webmarks_open')
endfunction

function! s:suite.rows_lines_folds_and_matches() abort
  call s:seed()
  Webmarks
  call s:assert.equals(getline(1, '$'), ['★ zeta', '  Alpha', 'Dev/', '  Docs/', '      Guide', '    Tool'])
  call s:assert.equals(map(range(1, line('$')), 'webmarks#ui#tree#foldexpr(v:val)'), [0, 0, '>1', '>2', 2, 1])
  call s:assert.equals(map(range(1, line('$')), 'foldlevel(v:val)'), [0, 0, 1, 2, 2, 1])
  " Folder x2 + favorite x1 = 3 positions in 2 groups
  call s:assert.equals(len(w:webmarks_match_ids), 2)
  call s:assert.equals(sort(map(getmatches(), 'v:val.group')), ['WebmarksFavorite', 'WebmarksFolder'])
  call s:press('T')
  " flat: no folder rows, a path highlight per foldered bookmark
  call s:assert.equals(getline(1, '$'), ['★ zeta', '  Alpha', '  Guide  (Dev/Docs)', '  Tool  (Dev)'])
  call s:assert.equals(&l:foldmethod, 'manual')
  call s:assert.equals(sort(map(getmatches(), 'v:val.group')), ['WebmarksFavorite', 'WebmarksPath'])
  call s:press('T')
  call s:assert.equals(&l:foldmethod, 'expr')
endfunction

function! s:suite.many_rows_split_matchaddpos_by_8() abort
  for l:i in range(1, 20)
    call webmarks#app#bookmark#add(printf('https://h%02d.example', l:i), '', v:null, 1)
  endfor
  Webmarks
  " 20 provisional names: one group, ceil(20 / 8) = 3 calls
  call s:assert.equals(len(w:webmarks_match_ids), 3)
endfunction

function! s:suite.closed_fold_survives_redraw() abort
  call s:seed()
  Webmarks
  call cursor(s:lnum('f4'), 1)
  normal! zc
  call s:assert.not_equals(foldclosed(s:lnum('f4')), -1)
  call webmarks#app#bookmark#rename('b6', 'Tool 2')
  call webmarks#ui#tree#render()
  call s:assert.equals(getline(6), '    Tool 2')
  call s:assert.not_equals(foldclosed(s:lnum('f4')), -1)
endfunction

function! s:suite.open_on_folder_toggles_fold() abort
  call s:seed()
  Webmarks
  call cursor(s:lnum('f3'), 1)
  call s:press("\<CR>")
  call s:assert.not_equals(foldclosed(s:lnum('f3')), -1)
  call s:press("\<CR>")
  call s:assert.equals(foldclosed(s:lnum('f3')), -1)
endfunction

function! s:suite.sort_then_enter_launches_the_right_id() abort
  call s:seed()
  call webmarks#app#bookmark#launch('b1', 1700000000)
  Webmarks
  let s:opened = []
  call s:press('P')
  call s:press('S')
  " recent first, favorites not first: Alpha (launched) is line 1
  call s:assert.equals(b:webmarks.policy, {'criterion': 'recent', 'favorite_first': v:false})
  call cursor(1, 1)
  call s:press("\<CR>")
  call s:assert.equals(s:opened, ['https://alpha.example'])
  call s:assert.equals(webmarks#app#store#find_bookmark(webmarks#app#store#current(), 'b1').usage.open_count, 2)
endfunction

function! s:suite.cursor_follows_the_item_across_redraws() abort
  call s:seed()
  Webmarks
  call cursor(s:lnum('b1'), 1)
  call s:press('P')
  call s:assert.equals(line('.'), s:lnum('b1'))
  call s:assert.equals(line('.'), 1)
endfunction

function! s:suite.empty_tree_enter_adds() abort
  Webmarks
  call s:assert.equals(getline(1, '$'), ['[no bookmarks — press a to add]'])
  call s:assert.equals(map(getmatches(), 'v:val.group'), ['WebmarksEmpty'])
  let g:webmarks_test.title_fetcher = function('WebmarksTestTitle', ['Fetched'])
  let s:texts = ['https://new.example', '']
  call s:press("\<CR>")
  call s:assert.equals(getline(1, '$'), ['  Fetched'])
  call s:assert.equals(line('.'), 1)
endfunction

function! s:suite.add_goes_into_the_cursor_folder() abort
  call s:seed()
  Webmarks
  call cursor(s:lnum('b5'), 1)
  let s:texts = ['https://more.example', 'More']
  call s:press('a')
  let l:b = webmarks#app#store#find_bookmark(webmarks#app#store#current(), 'b7')
  call s:assert.equals(l:b.folder_id, 'f4')
  call s:assert.equals(line('.'), s:lnum('b7'))
endfunction

function! s:suite.add_cancelled_or_empty_url_does_nothing() abort
  Webmarks
  call s:press('a')
  let s:texts = ['', 'x']
  call s:press('a')
  call s:assert.equals(webmarks#app#store#current().bookmarks, [])
endfunction

function! s:suite.add_duplicate_moves_cursor_to_existing() abort
  call s:seed()
  Webmarks
  call cursor(1, 1)
  let s:texts = ['https://guide.example', 'Again']
  call s:press('a')
  call s:assert.equals(line('.'), s:lnum('b5'))
  call s:assert.match(execute('messages'), 'already registered: Guide (Dev/Docs)')
endfunction

function! s:suite.add_folder_and_depth_limit() abort
  call s:seed()
  Webmarks
  call cursor(s:lnum('f4'), 1)
  let s:texts = ['Deep']
  call s:press('A')
  call s:assert.match(execute('messages'), 'folders are limited to 2 levels')
  call cursor(1, 1)
  let s:texts = ['Root folder']
  call s:press('A')
  call s:assert.equals(getline('.'), 'Root folder/')
endfunction

function! s:suite.rename_edit_url_favorite_yank() abort
  call s:seed()
  Webmarks
  call cursor(s:lnum('b1'), 1)
  let s:texts = ['Renamed']
  call s:press('r')
  call s:assert.equals(getline(s:lnum('b1')), '  Renamed')
  let s:texts = ['https://alpha2.example']
  call s:press('e')
  call s:assert.equals(webmarks#app#store#find_bookmark(webmarks#app#store#current(), 'b1').url, 'https://alpha2.example')
  call s:press('*')
  call s:assert.equals(getline(s:lnum('b1')), '★ Renamed')
  call s:press('y')
  call s:assert.equals(getreg('"'), 'https://alpha2.example')
  call cursor(s:lnum('f3'), 1)
  let s:texts = ['Development']
  call s:press('r')
  call s:assert.equals(getline(s:lnum('f3')), 'Development/')
  call s:press('e')
  call s:assert.match(execute('messages'), 'not a bookmark')
endfunction

function! s:suite.delete_folder_not_empty() abort
  call s:seed()
  Webmarks
  call cursor(s:lnum('f3'), 1)
  call s:press('d')
  call s:assert.match(execute('messages'), 'folder is not empty: Dev')
  call s:assert.true(s:lnum('f3') > 0)
  call cursor(s:lnum('b1'), 1)
  let s:confirm = 0
  call s:press('d')
  call s:assert.true(s:lnum('b1') > 0)
  let s:confirm = 1
  call s:press('d')
  call s:assert.equals(s:lnum('b1'), 0)
endfunction

function! s:suite.move_depth_exceeded_and_ok() abort
  call s:seed()
  call webmarks#app#folder#add('Other', v:null)
  Webmarks
  " Dev (with child Docs) into Other would be 3 levels
  call cursor(s:lnum('f3'), 1)
  let s:folder_answer = {'ok': v:true, 'value': 'f7'}
  call s:press('m')
  call s:assert.match(execute('messages'), 'folders are limited to 2 levels')
  call cursor(s:lnum('b1'), 1)
  call s:press('m')
  call s:assert.equals(webmarks#app#store#find_bookmark(webmarks#app#store#current(), 'b1').folder_id, 'f7')
  call s:assert.equals(line('.'), s:lnum('b1'))
endfunction

function! s:suite.refetch_overwrites_manual_name() abort
  call s:seed()
  let g:webmarks_test.title_fetcher = function('WebmarksTestTitle', ['From page'])
  call webmarks#open()
  call cursor(s:lnum('b1'), 1)
  call s:press('t')
  call s:assert.equals(getline(s:lnum('b1')), '  From page')
endfunction

function! s:suite.async_title_redraws_without_switching_tabs() abort
  let s:pending = []
  let g:webmarks_test.title_fetcher = function('s:defer')
  call webmarks#add('https://a.example', '', v:null)
  call webmarks#open()
  call s:assert.equals(getline(1), '  https://a.example …')
  " leave the tree in tab 1 and work in tab 2
  tabnew
  let l:tab = tabpagenr()
  call webmarks#app#title#on_result({'ok': v:true, 'code': '', 'error': '', 'title': 'Done'}, s:pending[0])
  call s:assert.equals(tabpagenr(), l:tab)
  let l:buf = webmarks#ui#tree#bufnr()
  call s:assert.equals(getbufline(l:buf, 1), ['  Done'])
endfunction

function! s:defer(url, ctx) abort
  call add(s:pending, a:ctx)
  return v:null
endfunction

function! s:suite.on_changed_without_windows_is_a_noop() abort
  call webmarks#ui#tree#on_changed()
  call s:assert.equals(webmarks#ui#tree#bufnr(), -1)
endfunction

function! s:suite.split_window_gets_settings_and_matches() abort
  call s:seed()
  Webmarks
  split
  call s:assert.equals(&l:foldmethod, 'expr')
  call s:assert.equals(&l:wrap, 0)
  call s:assert.equals(sort(map(getmatches(), 'v:val.group')), ['WebmarksFavorite', 'WebmarksFolder'])
  " another buffer in this window: the tree's matches go away
  enew
  sleep 20m
  call s:assert.equals(getmatches(), [])
  wincmd w
  call s:assert.equals(bufname('%'), 'webmarks://webmarks')
  call s:assert.not_equals(getmatches(), [])
endfunction

function! s:suite.reload_and_broken_file() abort
  call s:seed()
  Webmarks
  call writefile(['broken'], g:webmarks_file)
  call s:press('R')
  call s:assert.match(execute('messages'), 'cannot read')
  " the tree keeps showing the last good data
  call s:assert.equals(getline(1), '★ zeta')
  close
  call s:assert.equals(webmarks#open().code, 'load_failed')
  call s:assert.equals(winnr('$'), 1)
endfunction

function! s:suite.write_in_view_mode_does_nothing() abort
  call s:seed()
  Webmarks
  let l:before = readfile(g:webmarks_file)
  write
  call s:assert.false(&modified)
  call s:assert.equals(readfile(g:webmarks_file), l:before)
endfunction

function! s:suite.help_lists_keys() abort
  Webmarks
  let l:out = execute('normal ?')
  call s:assert.match(l:out, 'webmarks mappings:')
  call s:assert.match(l:out, '<CR>\s\+open the bookmark')
  call s:assert.match(l:out, '?\s\+show this list')
  call s:assert.match(l:out, 's\s\+search with fzf')
  call s:assert.not_match(l:out, '<Leader>')
  call s:assert.equals(maparg('?', 'n'), '<Plug>(webmarks-help)')
  call s:assert.equals(maparg('g?', 'n'), '<Plug>(webmarks-help)')
  call s:assert.match(l:out, '? g?\s\+show this list')
  call s:assert.equals(bufname('%'), 'webmarks://webmarks')
endfunction

function! s:suite.keys_that_clash_get_the_leader() abort
  " the user's own prefixes (like `ss`, `sv`, `qf`) and a plugin's `ds`
  nnoremap ss :echo<CR>
  nnoremap qf :echo<CR>
  nnoremap ds :echo<CR>
  nnoremap S :echo<CR>
  try
    Webmarks
    call s:assert.equals(maparg('<Leader>s', 'n'), '<Plug>(webmarks-search)')
    " open / close / help stay one key even with `qf` around
    call s:assert.equals(maparg('q', 'n'), '<Plug>(webmarks-close)')
    call s:assert.true(maparg('q', 'n', 0, 1).nowait)
    call s:assert.equals(maparg('<Leader>q', 'n'), '')
    call s:assert.equals(maparg('<Leader>d', 'n'), '<Plug>(webmarks-delete)')
    call s:assert.equals(maparg('<Leader>S', 'n'), '<Plug>(webmarks-sort-recent)')
    " the plain keys are left to the user's mappings
    call s:assert.equals(maparg('s', 'n'), '')
    call s:assert.equals(maparg('ss', 'n'), ':echo<CR>')
    " keys without a clash stay plain (and <nowait>)
    call s:assert.equals(maparg('a', 'n'), '<Plug>(webmarks-add)')
    call s:assert.true(maparg('a', 'n', 0, 1).nowait)
    call s:assert.false(maparg('<Leader>s', 'n', 0, 1).nowait)
    let l:out = execute('normal ?')
    call s:assert.match(l:out, '<Leader>s\s\+search with fzf')
    call s:assert.match(l:out, '<Leader> is ')
    " the leader keys work
    call s:press("\\S")
    call s:assert.equals(b:webmarks.policy.criterion, 'recent')
    " and survive a round trip through edit mode
    normal i
    call s:assert.equals(maparg('<Leader>S', 'n'), '')
    call s:assert.equals(maparg('q', 'n'), '<Plug>(webmarks-close)')
    edit!
    call s:assert.equals(maparg('<Leader>S', 'n'), '<Plug>(webmarks-sort-recent)')
  finally
    nunmap ss
    nunmap qf
    nunmap ds
    nunmap S
  endtry
endfunction

function! s:suite.help_in_edit_mode() abort
  Webmarks
  normal i
  let l:out = execute('normal ?')
  call s:assert.match(l:out, 'edit mode')
  call s:assert.match(l:out, ':w\s\+apply')
  call s:assert.not_match(l:out, 'search with fzf')
  call s:assert.equals(b:webmarks.mode, 'edit')
endfunction

function! s:suite.user_mapping_wins() abort
  augroup webmarks_test
    autocmd!
    autocmd FileType webmarks nmap <buffer> o <Plug>(webmarks-open)
  augroup END
  try
    Webmarks
    call s:assert.equals(maparg('o', 'n'), '<Plug>(webmarks-open)')
    call s:assert.equals(maparg('<CR>', 'n'), '')
    call s:assert.equals(maparg('a', 'n'), '<Plug>(webmarks-add)')
  finally
    autocmd! webmarks_test
  endtry
endfunction

function! s:suite.no_default_mappings() abort
  let g:webmarks_no_default_mappings = 1
  Webmarks
  call s:assert.equals(maparg('a', 'n'), '')
  call s:assert.not_equals(maparg('<Plug>(webmarks-add)', 'n'), '')
endfunction

function! s:suite.empty_folder_name_is_reported() abort
  Webmarks
  let s:texts = [{'ok': v:true, 'value': ''}]
  call s:press('A')
  call s:assert.match(execute('messages'), 'name is empty')
endfunction

function! s:suite.open_in_place_over_a_modified_buffer_fails_cleanly() abort
  let g:webmarks_open = 'edit'
  set nohidden
  enew
  call setline(1, 'unsaved')
  let l:r = webmarks#open()
  call s:assert.false(l:r.ok)
  call s:assert.match(l:r.error, 'E37')
  call s:assert.equals(getline(1), 'unsaved')
  setlocal nomodified
endfunction
