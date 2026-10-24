scriptencoding utf-8
let s:suite = themis#suite('domain_bookmark')
let s:assert = themis#helper('assert')

function! s:new(...) abort
  let l:r = webmarks#domain#bookmark#new('b1', get(a:000, 0, 'https://example.com'),
        \ get(a:000, 1, ''), v:null, 100)
  call s:assert.true(l:r.ok, string(l:r))
  return l:r.bookmark
endfunction

function! s:suite.new_defaults() abort
  let l:b = s:new()
  call s:assert.equals(l:b, {
        \ 'id': 'b1', 'url': 'https://example.com', 'display_name': 'https://example.com',
        \ 'name_source': 'url', 'folder_id': v:null, 'is_favorite': v:false,
        \ 'created_at': 100,
        \ 'usage': {'rank': 0.0, 'open_count': 0, 'last_launch_at': v:null}})
endfunction

function! s:suite.new_with_name_is_manual() abort
  let l:b = s:new('https://example.com', "  My\tSite ")
  call s:assert.equals(l:b.display_name, 'My Site')
  call s:assert.equals(l:b.name_source, 'manual')
endfunction

function! s:suite.new_rejects_bad_names() abort
  call s:assert.equals(webmarks#domain#bookmark#new('b1', 'https://a.b', "\xff", v:null, 0).code, 'invalid_text')
  call s:assert.equals(webmarks#domain#bookmark#new('b1', 'https://a.b', "​", v:null, 0).code, 'empty_name')
endfunction

function! s:suite.valid_urls() abort
  for l:u in ['http://a.b', 'https://example.com/', 'https://a.b/x?y=1&z=2#frag',
        \ 'https://[::1]:8080/p', "https://a.b/it's(1)*,;=+!$@~", 'https://a.b/%E3%81%82']
    let l:r = webmarks#domain#bookmark#validate_url(l:u)
    call s:assert.true(l:r.ok, l:u)
    call s:assert.equals(l:r.value, l:u)
  endfor
  call s:assert.equals(webmarks#domain#bookmark#validate_url('  https://a.b/  ').value, 'https://a.b/')
endfunction

function! s:suite.invalid_urls() abort
  for l:u in ['ftp://a.b', 'file:///etc/passwd', '-https://a.b', 'https://a.b/ x',
        \ 'https://a.b/"', 'https://a.b/<', 'https://a.b/>', 'https://a.b/\', 'https://a.b/^',
        \ 'https://a.b/`', 'https://a.b/{', 'https://a.b/|', "https://a.b/\x01x",
        \ 'https://a.b/ä', "https://a.b/　", "https://a.b/‮", 'https://',
        \ 'https://a.b/' . repeat('x', 2049 - strlen('https://a.b/')), 42]
    let l:r = webmarks#domain#bookmark#validate_url(l:u)
    call s:assert.false(l:r.ok, string(l:u))
    call s:assert.equals(l:r.code, 'invalid_url')
  endfor
  call s:assert.true(webmarks#domain#bookmark#validate_url(
        \ 'https://a.b/' . repeat('x', 2048 - strlen('https://a.b/'))).ok)
endfunction

function! s:suite.apply_fetched_title_three_states() abort
  let l:b = s:new()
  let l:r = webmarks#domain#bookmark#apply_fetched_title(l:b, ' Example ')
  call s:assert.true(l:r.changed)
  call s:assert.equals([l:r.bookmark.display_name, l:r.bookmark.name_source], ['Example', 'fetched'])
  " fetched and manual names are kept
  let l:r2 = webmarks#domain#bookmark#apply_fetched_title(l:r.bookmark, 'Other')
  call s:assert.false(l:r2.changed)
  call s:assert.equals(l:r2.bookmark.display_name, 'Example')
  let l:m = s:new('https://example.com', 'Mine')
  let l:r3 = webmarks#domain#bookmark#apply_fetched_title(l:m, 'Other')
  call s:assert.true(l:r3.ok)
  call s:assert.false(l:r3.changed)
  call s:assert.equals(l:r3.bookmark.display_name, 'Mine')
  " invalid title: unchanged, still ok
  let l:r4 = webmarks#domain#bookmark#apply_fetched_title(l:b, "\xff")
  call s:assert.true(l:r4.ok)
  call s:assert.false(l:r4.changed)
endfunction

function! s:suite.force_title_overwrites_manual() abort
  let l:m = s:new('https://example.com', 'Mine')
  let l:r = webmarks#domain#bookmark#force_title(l:m, 'Fetched')
  call s:assert.equals([l:r.bookmark.display_name, l:r.bookmark.name_source], ['Fetched', 'fetched'])
  call s:assert.equals(webmarks#domain#bookmark#force_title(l:m, '').code, 'empty_name')
endfunction

function! s:suite.rename_is_manual() abort
  let l:r = webmarks#domain#bookmark#rename(s:new(), 'New')
  call s:assert.equals([l:r.bookmark.display_name, l:r.bookmark.name_source], ['New', 'manual'])
  call s:assert.equals(webmarks#domain#bookmark#rename(s:new(), '  ').code, 'empty_name')
endfunction

function! s:suite.reset_name() abort
  let l:m = s:new('https://example.com', 'Mine')
  let l:r = webmarks#domain#bookmark#reset_name(l:m)
  call s:assert.equals([l:r.bookmark.display_name, l:r.bookmark.name_source], ['https://example.com', 'url'])
endfunction

function! s:suite.change_url_follows_provisional_name() abort
  let l:r = webmarks#domain#bookmark#change_url(s:new(), 'https://new.example')
  call s:assert.equals([l:r.bookmark.url, l:r.bookmark.display_name], ['https://new.example', 'https://new.example'])
  let l:m = s:new('https://example.com', 'Mine')
  let l:m.usage.rank = 3.0
  let l:r2 = webmarks#domain#bookmark#change_url(l:m, 'https://new.example')
  call s:assert.equals([l:r2.bookmark.url, l:r2.bookmark.display_name], ['https://new.example', 'Mine'])
  call s:assert.equals(l:r2.bookmark.usage.rank, 3.0)
  call s:assert.equals(webmarks#domain#bookmark#change_url(l:m, 'ftp://x').code, 'invalid_url')
endfunction

function! s:suite.toggle_favorite_keeps_usage() abort
  let l:b = s:new()
  let l:b.usage = {'rank': 2.0, 'open_count': 2, 'last_launch_at': 5}
  let l:r = webmarks#domain#bookmark#toggle_favorite(l:b)
  call s:assert.true(l:r.bookmark.is_favorite)
  call s:assert.equals(l:r.bookmark.usage, l:b.usage)
  call s:assert.equals(l:r.bookmark.url, l:b.url)
  call s:assert.false(webmarks#domain#bookmark#toggle_favorite(l:r.bookmark).bookmark.is_favorite)
endfunction

function! s:suite.record_launch_updates_together() abort
  let l:r = webmarks#domain#bookmark#record_launch(s:new(), 500)
  call s:assert.equals(l:r.bookmark.usage, {'rank': 1.0, 'open_count': 1, 'last_launch_at': 500})
endfunction

function! s:suite.move_to() abort
  let l:r = webmarks#domain#bookmark#move_to(s:new(), 'f2')
  call s:assert.equals(l:r.bookmark.folder_id, 'f2')
  call s:assert.true(l:r.changed)
  call s:assert.false(webmarks#domain#bookmark#move_to(l:r.bookmark, 'f2').changed)
endfunction

function! s:suite.input_is_never_modified() abort
  let l:b = s:new()
  let l:copy = deepcopy(l:b)
  call webmarks#domain#bookmark#rename(l:b, 'x')
  call webmarks#domain#bookmark#change_url(l:b, 'https://x.y')
  call webmarks#domain#bookmark#apply_fetched_title(l:b, 't')
  call webmarks#domain#bookmark#force_title(l:b, 't')
  call webmarks#domain#bookmark#toggle_favorite(l:b)
  call webmarks#domain#bookmark#move_to(l:b, 'f1')
  call webmarks#domain#bookmark#record_launch(l:b, 9)
  call webmarks#domain#bookmark#reset_name(l:b)
  call s:assert.equals(l:b, l:copy)
endfunction

function! s:suite.find_duplicate() abort
  let l:a = s:new('https://a.b')
  let l:c = extend(s:new('https://c.d'), {'id': 'b2'})
  call s:assert.equals(webmarks#domain#bookmark#find_duplicate([l:a, l:c], 'https://c.d', v:null).id, 'b2')
  call s:assert.equals(webmarks#domain#bookmark#find_duplicate([l:a, l:c], 'https://c.d', 'b2'), v:null)
  call s:assert.equals(webmarks#domain#bookmark#find_duplicate([l:a, l:c], 'https://C.d', v:null), v:null)
endfunction

function! s:suite.validate_normalizes_rank() abort
  let l:b = s:new()
  let l:b.usage.rank = 3
  let l:r = webmarks#domain#bookmark#validate(l:b)
  call s:assert.true(l:r.ok, string(l:r))
  call s:assert.equals(type(l:r.value.usage.rank), v:t_float)
  call s:assert.equals(l:r.value.usage.rank, 3.0)
endfunction

function! s:suite.validate_rejects() abort
  let l:cases = [
        \ ['id', 'x1'], ['url', 'ftp://a'], ['display_name', "\xff"], ['display_name', ''],
        \ ['name_source', 'auto'], ['folder_id', 3], ['folder_id', 'b1'], ['is_favorite', 1],
        \ ['created_at', 1.5], ['usage', []],
        \ ]
  for [l:k, l:v] in l:cases
    let l:b = s:new()
    let l:b[l:k] = l:v
    let l:r = webmarks#domain#bookmark#validate(l:b)
    call s:assert.equals(l:r.code, 'invalid_data', l:k . '=' . string(l:v))
  endfor
  let l:nan = str2float('nan')
  let l:inf = str2float('inf')
  for [l:k, l:v] in [['rank', l:nan], ['rank', l:inf], ['rank', -1.0], ['rank', 'x'],
        \ ['open_count', 1.0], ['open_count', -1], ['last_launch_at', 'x']]
    let l:b = s:new()
    let l:b.usage[l:k] = l:v
    call s:assert.equals(webmarks#domain#bookmark#validate(l:b).code, 'invalid_data', l:k . '=' . string(l:v))
  endfor
  call s:assert.equals(webmarks#domain#bookmark#validate('x').code, 'invalid_data')
endfunction

function! s:suite.validate_drops_unknown_keys() abort
  let l:b = s:new()
  let l:b.extra = 1
  call s:assert.false(has_key(webmarks#domain#bookmark#validate(l:b).value, 'extra'))
endfunction

function! s:suite.validate_rejects_huge_ids() abort
  let l:b = s:new()
  let l:b.id = 'b99999999999999999999'
  call s:assert.equals(webmarks#domain#bookmark#validate(l:b).code, 'invalid_data')
  let l:b.id = 'b0'
  call s:assert.equals(webmarks#domain#bookmark#validate(l:b).code, 'invalid_data')
  let l:b.id = 'b999999999'
  call s:assert.true(webmarks#domain#bookmark#validate(l:b).ok)
endfunction

function! s:suite.validate_cleans_names_with_a_warning() abort
  let l:b = s:new()
  let l:b.display_name = "Ab\u00adc \u27e8x\u27e9"
  let l:r = webmarks#domain#bookmark#validate(l:b)
  call s:assert.true(l:r.ok)
  call s:assert.equals(l:r.value.display_name, 'Abc x')
  call s:assert.match(l:r.warning, 'cleaned')
  call s:assert.equals(webmarks#domain#bookmark#validate(s:new()).warning, '')
endfunction
