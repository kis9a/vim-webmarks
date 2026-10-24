scriptencoding utf-8
" test/storage_json.vim - real files in a temp dir

let s:suite = themis#suite('storage_json')
let s:assert = themis#helper('assert')

function! s:suite.before_each() abort
  let s:dir = tempname()
  call mkdir(s:dir, 'p')
  let s:path = s:dir . '/sub/bookmarks.json'
endfunction

function! s:suite.after_each() abort
  call delete(s:dir, 'rf')
endfunction

function! s:sample() abort
  return {
        \ 'schema_version': 1, 'next_id': 6,
        \ 'folders': [
        \   {'id': 'f2', 'name': 'Docs "quoted"', 'parent_id': 'f1'},
        \   {'id': 'f1', 'name': 'Dev', 'parent_id': v:null},
        \ ],
        \ 'bookmarks': [
        \   {'id': 'b5', 'url': 'https://b.example/?q=1&r=2', 'display_name': '日本語 \ back',
        \    'name_source': 'manual', 'folder_id': 'f2', 'is_favorite': v:true, 'created_at': 1700000000,
        \    'usage': {'rank': 3, 'open_count': 3, 'last_launch_at': 1700000100}},
        \   {'id': 'b3', 'url': 'https://a.example', 'display_name': 'https://a.example',
        \    'name_source': 'url', 'folder_id': v:null, 'is_favorite': v:false, 'created_at': 1700000000,
        \    'usage': {'rank': 0.5, 'open_count': 0, 'last_launch_at': v:null}},
        \ ]}
endfunction

function! s:by_id(a, b) abort
  return str2nr(a:a.id[1:]) - str2nr(a:b.id[1:])
endfunction

function! s:normalized(data) abort
  let l:d = deepcopy(a:data)
  call map(l:d.bookmarks, 'webmarks#domain#bookmark#validate(v:val).value')
  call sort(l:d.bookmarks, function('s:by_id'))
  call sort(l:d.folders, function('s:by_id'))
  return l:d
endfunction

function! s:write(lines) abort
  call mkdir(fnamemodify(s:path, ':h'), 'p')
  call writefile(a:lines, s:path)
endfunction

function! s:suite.round_trip() abort
  let l:r = webmarks#storage#json#save(s:path, s:sample(), -1)
  call s:assert.true(l:r.ok, string(l:r))
  let l:l = webmarks#storage#json#load(s:path)
  call s:assert.true(l:l.ok, string(l:l))
  call s:assert.equals(l:l.data, s:normalized(s:sample()))
  call s:assert.equals(l:l.warnings, [])
  call s:assert.false(l:l.fresh)
  call s:assert.equals(l:l.mtime, getftime(s:path))
endfunction

function! s:suite.layout_one_element_per_line() abort
  let l:lines = webmarks#storage#json#encode(s:sample()).lines
  call s:assert.equals(l:lines[0:4], ['{', '  "schema_version": 1,', '  "next_id": 6,', '  "folders": [',
        \ '    {"id": "f1", "name": "Dev", "parent_id": null},'])
  call s:assert.equals(l:lines[-4:], [
        \ '    {"id": "b3", "url": "https://a.example", "display_name": "https://a.example", "name_source": "url", "folder_id": null, "is_favorite": false, "created_at": 1700000000, "usage": {"rank": 0.5000, "open_count": 0, "last_launch_at": null}},',
        \ '    {"id": "b5", "url": "https://b.example/?q=1&r=2", "display_name": "日本語 \\ back", "name_source": "manual", "folder_id": "f2", "is_favorite": true, "created_at": 1700000000, "usage": {"rank": 3.0000, "open_count": 3, "last_launch_at": 1700000100}}',
        \ '  ]', '}'])
  call s:assert.equals(len(l:lines), 12)
endfunction

function! s:suite.empty_lists() abort
  let l:lines = webmarks#storage#json#encode(webmarks#storage#json#empty()).lines
  call s:assert.equals(l:lines, ['{', '  "schema_version": 1,', '  "next_id": 1,', '  "folders": [],', '  "bookmarks": []', '}'])
  call s:assert.equals(json_decode(join(l:lines, "\n")), webmarks#storage#json#empty())
endfunction

function! s:suite.trailing_newline() abort
  call webmarks#storage#json#save(s:path, s:sample(), -1)
  let l:bytes = readfile(s:path, 'b')
  call s:assert.equals(l:bytes[-1], '')
endfunction

function! s:suite.missing_file_is_fresh() abort
  let l:l = webmarks#storage#json#load(s:path)
  call s:assert.true(l:l.ok)
  call s:assert.true(l:l.fresh)
  call s:assert.equals(l:l.mtime, -1)
  call s:assert.equals(l:l.data, webmarks#storage#json#empty())
  " loading never creates the directory
  call s:assert.false(isdirectory(fnamemodify(s:path, ':h')))
endfunction

function! s:suite.empty_and_blank_files() abort
  call s:write([])
  call s:assert.equals(webmarks#storage#json#load(s:path).data, webmarks#storage#json#empty())
  call s:write(['', '   ', "\t"])
  let l:l = webmarks#storage#json#load(s:path)
  call s:assert.true(l:l.ok)
  call s:assert.equals(l:l.data, webmarks#storage#json#empty())
endfunction

function! s:suite.bad_json() abort
  call s:write(['{"schema_version": 1,'])
  let l:l = webmarks#storage#json#load(s:path)
  call s:assert.equals(l:l.code, 'load_failed')
  call s:assert.match(l:l.error, 'cannot read')
endfunction

function! s:suite.duplicate_keys_are_rejected() abort
  call s:write(['{"schema_version": 1, "schema_version": 1, "next_id": 1, "folders": [], "bookmarks": []}'])
  let l:l = webmarks#storage#json#load(s:path)
  " Vim: E938; Neovim: a special dict without schema_version
  call s:assert.false(l:l.ok)
  call s:assert.true(index(['invalid_data', 'load_failed'], l:l.code) >= 0, l:l.code)
endfunction

function! s:suite.newer_schema() abort
  call s:write(['{"schema_version": 2, "next_id": 1, "folders": [], "bookmarks": []}'])
  let l:l = webmarks#storage#json#load(s:path)
  call s:assert.equals(l:l.code, 'schema_unsupported')
endfunction

function! s:suite.structure_errors() abort
  for l:text in ['[]', '{"next_id": 1, "folders": [], "bookmarks": []}',
        \ '{"schema_version": 0, "next_id": 1, "folders": [], "bookmarks": []}',
        \ '{"schema_version": "1", "next_id": 1, "folders": [], "bookmarks": []}',
        \ '{"schema_version": 1, "folders": [], "bookmarks": []}',
        \ '{"schema_version": 1, "next_id": 1, "folders": {}, "bookmarks": []}',
        \ '{"schema_version": 1, "next_id": 1, "folders": [], "bookmarks": [{"id": "b1"}]}']
    call s:write([l:text])
    call s:assert.equals(webmarks#storage#json#load(s:path).code, 'invalid_data', l:text)
  endfor
endfunction

function! s:suite.cyclic_folders_are_invalid() abort
  call s:write(['{"schema_version": 1, "next_id": 3, "folders": [',
        \ '{"id": "f1", "name": "a", "parent_id": "f2"}, {"id": "f2", "name": "b", "parent_id": "f1"}],',
        \ '"bookmarks": []}'])
  let l:l = webmarks#storage#json#load(s:path)
  call s:assert.equals(l:l.code, 'invalid_data')
  call s:assert.match(l:l.error, 'f1')
endfunction

function! s:suite.nan_rank_is_invalid() abort
  if has('nvim')
    " Neovim's json_decode() does not accept NaN at all
    call s:write(['{"schema_version": 1, "next_id": 1, "folders": [], "bookmarks": NaN}'])
    call s:assert.equals(webmarks#storage#json#load(s:path).code, 'load_failed')
    return
  endif
  let l:lines = webmarks#storage#json#encode(s:sample()).lines
  let l:lines = map(l:lines, 'substitute(v:val, ''"rank": 3.0000'', ''"rank": NaN'', "")')
  call s:write(l:lines)
  call s:assert.equals(webmarks#storage#json#load(s:path).code, 'invalid_data')
endfunction

function! s:suite.encode_rejects_nan() abort
  let l:d = s:sample()
  let l:d.bookmarks[0].usage.rank = str2float('nan')
  call s:assert.equals(webmarks#storage#json#encode(l:d).code, 'invalid_data')
endfunction

function! s:suite.duplicate_url_is_a_warning() abort
  let l:d = s:sample()
  let l:d.bookmarks[1].url = l:d.bookmarks[0].url
  let l:d.bookmarks[1].display_name = l:d.bookmarks[0].url
  call webmarks#storage#json#save(s:path, l:d, -1)
  let l:l = webmarks#storage#json#load(s:path)
  call s:assert.true(l:l.ok)
  call s:assert.equals(len(l:l.warnings), 1)
  call s:assert.match(l:l.warnings[0], 'duplicate URL')
endfunction

function! s:suite.next_id_is_corrected() abort
  let l:d = s:sample()
  let l:d.next_id = 2
  call webmarks#storage#json#save(s:path, l:d, -1)
  let l:l = webmarks#storage#json#load(s:path)
  call s:assert.true(l:l.ok)
  call s:assert.equals(l:l.data.next_id, 6)
  call s:assert.match(l:l.warnings[0], 'next_id')
endfunction

function! s:suite.no_tmp_left_and_permissions() abort
  call webmarks#storage#json#save(s:path, s:sample(), -1)
  call s:assert.equals(glob(s:path . '.tmp.*', 1, 1), [])
  call s:assert.equals(getfperm(s:path), 'rw-------')
endfunction

function! s:suite.creates_parent_dir() abort
  let l:deep = s:dir . '/a/b/c/bookmarks.json'
  call s:assert.true(webmarks#storage#json#save(l:deep, s:sample(), -1).ok)
  call s:assert.true(filereadable(l:deep))
endfunction

function! s:age(file, seconds) abort
  call system('touch -t ' . strftime('%Y%m%d%H%M.%S', localtime() - a:seconds) . ' ' . shellescape(a:file))
endfunction

function! s:suite.load_cleans_stale_tmp() abort
  call webmarks#storage#json#save(s:path, s:sample(), -1)
  call writefile(['junk'], s:path . '.tmp.99999')
  call s:age(s:path . '.tmp.99999', 120)
  " a fresh one may be another Vim saving right now
  call writefile(['busy'], s:path . '.tmp.88888')
  call writefile(['other'], s:path . '.tmp.notapid')
  call s:age(s:path . '.tmp.notapid', 120)
  call webmarks#storage#json#load(s:path)
  call s:assert.equals(sort(map(glob(s:path . '.tmp.*', 1, 1), 'fnamemodify(v:val, ":e")')), ['88888', 'notapid'])
endfunction

function! s:suite.tmp_cleanup_with_pattern_characters_in_path() abort
  let l:path = s:dir . '/we[ir]d*/bookmarks.json'
  call s:assert.true(webmarks#storage#json#save(l:path, s:sample(), -1).ok)
  call writefile(['junk'], l:path . '.tmp.12345')
  call s:age(l:path . '.tmp.12345', 120)
  call s:assert.true(webmarks#storage#json#load(l:path).ok)
  call s:assert.false(filereadable(l:path . '.tmp.12345'))
  call s:assert.equals(getfperm(fnamemodify(l:path, ':h')), 'rwx------')
endfunction

function! s:suite.invalid_file_is_not_cleaned_or_overwritten() abort
  call s:write(['not json'])
  call writefile(['junk'], s:path . '.tmp.99999')
  call webmarks#storage#json#load(s:path)
  call s:assert.equals(readfile(s:path), ['not json'])
endfunction

function! s:suite.conflict_on_mtime_mismatch() abort
  let l:r = webmarks#storage#json#save(s:path, s:sample(), -1)
  " the file exists now: a writer that believes it is new must not win
  call s:assert.equals(webmarks#storage#json#save(s:path, s:sample(), -1).code, 'conflict')
  call s:assert.equals(webmarks#storage#json#save(s:path, s:sample(), l:r.mtime - 5).code, 'conflict')
  call s:assert.true(webmarks#storage#json#save(s:path, s:sample(), l:r.mtime).ok)
endfunction

function! s:suite.unwritable_dir_is_save_failed() abort
  let l:ro = s:dir . '/ro'
  call mkdir(l:ro, 'p')
  call setfperm(l:ro, 'r-x------')
  let l:r = webmarks#storage#json#save(l:ro . '/x/bookmarks.json', s:sample(), -1)
  call setfperm(l:ro, 'rwx------')
  call s:assert.equals(l:r.code, 'save_failed')
endfunction

function! s:suite.huge_next_id_is_invalid() abort
  call s:write(['{"schema_version": 1, "next_id": 99999999999, "folders": [], "bookmarks": []}'])
  call s:assert.equals(webmarks#storage#json#load(s:path).code, 'invalid_data')
endfunction

function! s:suite.duplicate_key_inside_a_bookmark_is_explained() abort
  let l:lines = webmarks#storage#json#encode(s:sample()).lines
  let l:lines = map(l:lines, 'substitute(v:val, ''"name_source": "url"'', ''"name_source": "url", "name_source": "url"'', "")')
  call s:write(l:lines)
  let l:r = webmarks#storage#json#load(s:path)
  call s:assert.false(l:r.ok)
  if has('nvim')
    call s:assert.match(l:r.error, 'duplicate key')
  endif
endfunction

function! s:suite.last_id_still_loads_and_then_refuses_new_ids() abort
  let l:d = s:sample()
  let l:d.bookmarks[0].id = 'b999999999'
  let l:d.next_id = 7
  call webmarks#storage#json#save(s:path, l:d, -1)
  let l:l = webmarks#storage#json#load(s:path)
  call s:assert.true(l:l.ok, string(l:l))
  call s:assert.equals(l:l.data.next_id, 1000000000)
  " a store with no ids left: adding fails, the file stays readable
  let g:webmarks_file = s:path
  call webmarks#app#store#_reset()
  let l:r = webmarks#app#bookmark#add('https://new.example', '', v:null, 1)
  call s:assert.equals(l:r.code, 'internal_error')
  call s:assert.true(webmarks#storage#json#load(s:path).ok)
endfunction

function! s:suite.names_from_an_older_file_are_cleaned_not_refused() abort
  let l:lines = webmarks#storage#json#encode(s:sample()).lines
  let l:lines = map(l:lines, 'substitute(v:val, ''"name": "Dev"'', ''"name": "D\\u00adev"'', "")')
  call s:write(l:lines)
  let l:l = webmarks#storage#json#load(s:path)
  call s:assert.true(l:l.ok, string(l:l))
  call s:assert.equals(filter(copy(l:l.data.folders), 'v:val.id ==# "f1"')[0].name, 'Dev')
  call s:assert.match(join(l:l.warnings), 'f1: name cleaned')
endfunction

function! s:suite.duplicate_key_in_an_ignored_field_is_refused() abort
  let l:lines = webmarks#storage#json#encode(s:sample()).lines
  let l:lines[1] = '  "extra": {"q": 1, "q": 2}, "schema_version": 1,'
  call s:write(l:lines)
  call s:assert.false(webmarks#storage#json#load(s:path).ok)
endfunction
