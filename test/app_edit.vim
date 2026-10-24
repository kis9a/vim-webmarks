scriptencoding utf-8
" test/app_edit.vim - the edit-mode grammar and the one-shot apply

let s:suite = themis#suite('app_edit')
let s:assert = themis#helper('assert')

let s:L = "⟨"
let s:R = "⟩"

function! s:m(id) abort
  return ' ' . s:L . a:id . s:R
endfunction

function! s:suite.before_each() abort
  let s:dir = WebmarksTestReset()
  call webmarks#app#store#_reset()
endfunction

function! s:suite.after_each() abort
  call delete(s:dir, 'rf')
endfunction

function! s:parse(lines, ...) abort
  return webmarks#app#edit#parse(a:lines, get(a:000, 0, []))
endfunction

function! s:one(line) abort
  let l:r = s:parse([a:line])
  call s:assert.true(l:r.ok, string(l:r))
  return l:r.entries[0]
endfunction

function! s:err(lines) abort
  let l:r = s:parse(a:lines)
  call s:assert.false(l:r.ok, string(a:lines))
  return l:r
endfunction

" --- grammar -------------------------------------------------------------

function! s:suite.bookmark_line() abort
  let l:e = s:one("★ My  Site  https://a.example/x?y=1" . s:m('b12'))
  call s:assert.equals([l:e.kind, l:e.id, l:e.depth, l:e.name, l:e.url, l:e.favorite],
        \ ['bookmark', 'b12', 0, 'My  Site', 'https://a.example/x?y=1', v:true])
endfunction

function! s:suite.star_slot_variants() abort
  call s:assert.true(s:one('* fav  https://a.example').favorite)
  call s:assert.false(s:one('  plain  https://a.example').favorite)
  call s:assert.equals(s:parse(['Dev/', '    https://a.example']).entries[1].depth, 1)
  call s:assert.equals(s:one('  https://a.example').name, '')
  call s:assert.equals(s:one('  https://a.example').depth, 0)
endfunction

function! s:suite.star_slot_is_required() abort
  let l:r = s:err(['https://a.example'])
  call s:assert.match(l:r.error, 'line 1: bad indent (bookmark lines need the 2-column star slot)')
  call s:assert.equals(s:err(['   x  https://a.example']).code, 'parse_error')
endfunction

function! s:suite.url_with_trailing_slash_is_a_bookmark() abort
  let l:e = s:one('  GitHub  https://github.com/' . s:m('b3'))
  call s:assert.equals([l:e.kind, l:e.url, l:e.name], ['bookmark', 'https://github.com/', 'GitHub'])
  call s:assert.equals(s:one('  https://github.com/').kind, 'bookmark')
endfunction

function! s:suite.only_the_last_url_is_the_url() abort
  let l:e = s:one('  foo https://x.example  https://real.example')
  call s:assert.equals([l:e.name, l:e.url], ['foo https://x.example', 'https://real.example'])
endfunction

function! s:suite.folder_lines() abort
  let l:e = s:one('Dev/' . s:m('f3'))
  call s:assert.equals([l:e.kind, l:e.id, l:e.depth, l:e.name], ['folder', 'f3', 1, 'Dev'])
  " only one trailing / is removed
  call s:assert.equals(s:one('Dev/Tools/').name, 'Dev/Tools')
  let l:r = s:parse(['A/', '  B/'])
  call s:assert.equals(l:r.entries[1].depth, 2)
  call s:assert.equals(l:r.entries[1].parent_lnum, 1)
endfunction

function! s:suite.comments_and_blank_lines_are_ignored() abort
  let l:r = s:parse(['# note', '', '   ', '  # indented note', '  a  https://a.example'])
  call s:assert.true(l:r.ok)
  call s:assert.equals(len(l:r.entries), 1)
  call s:assert.equals(l:r.entries[0].lnum, 5)
endfunction

function! s:suite.marker_anywhere_trailing_space_and_cr() abort
  let l:e = s:one('  name  https://a.example' . s:m('b1') . "  \r")
  call s:assert.equals([l:e.id, l:e.url], ['b1', 'https://a.example'])
  " text appended after a concealed marker is refused (v8: it used to be
  " silently appended to the URL)
  call s:assert.equals(s:err(['  name  https://a.example' . s:m('b1') . 'more']).code, 'parse_error')
  call s:assert.match(s:err(['  x  https://a.example' . s:m('b1') . s:m('b2')]).error, 'multiple ids')
endfunction

function! s:suite.tabs_and_bad_lines() abort
  call s:assert.match(s:err(["\tx  https://a.example"]).error, 'use spaces')
  call s:assert.match(s:err(['just text']).error, 'URL is required')
  call s:assert.equals(s:err(['  x  https://a.example/"q']).code, 'invalid_url')
  call s:assert.equals(s:err(['  x  https://a.example/ä']).code, 'invalid_url')
  call s:assert.equals(s:err(['A/', '  B/', '    C/']).code, 'depth_exceeded')
  call s:assert.equals(s:err(['/']).code, 'empty_name')
  call s:assert.match(s:err(['Dev/' . s:m('b1')]).error, 'belongs to a bookmark')
  call s:assert.match(s:err(['  x  https://a.example' . s:m('f1')]).error, 'a folder line must end with /')
endfunction

function! s:suite.parent_must_be_one_level_up() abort
  " a bookmark nested under a folder of another subtree
  let l:r = s:err(['A/', '  B/', 'C/', '      x  https://a.example'])
  call s:assert.match(l:r.error, 'line 4: bad indent (no parent folder at this level)')
  " under a bookmark
  call s:assert.equals(s:err(['  a  https://a.example', '    b  https://b.example']).code, 'parse_error')
  " ok: siblings, then back up a level
  let l:r = s:parse(['Dev/', '  Docs/', '      g  https://g.example', '    t  https://t.example', '  r  https://r.example'])
  call s:assert.true(l:r.ok, string(l:r))
  call s:assert.equals(map(copy(l:r.entries), 'v:val.parent_lnum'), [0, 1, 2, 1, 0])
endfunction

function! s:suite.duplicate_ids_and_error_limit() abort
  call s:assert.match(s:err(['  a  https://a.example' . s:m('b1'), '  b  https://b.example' . s:m('b1')]).error,
        \ 'line 2: duplicate id b1')
  let l:r = s:err(map(range(15), '"bad line"'))
  call s:assert.equals(len(l:r.errors), 10)
  call s:assert.equals(l:r.code, 'parse_error')
endfunction

function! s:suite.delete_ids_from_snapshot() abort
  let l:r = s:parse(['  a  https://a.example' . s:m('b1')], ['b1', 'b2', 'f3'])
  call s:assert.equals(l:r.delete_ids, ['b2', 'f3'])
endfunction

" --- commit --------------------------------------------------------------

function! s:seed() abort
  " b1 Alpha (root, manual) / f2 Dev / b3 https://g.example (provisional, in Dev) / f4 Docs in Dev
  call webmarks#app#bookmark#add('https://a.example', 'Alpha', v:null, 1)
  call webmarks#app#folder#add('Dev', v:null)
  call webmarks#app#bookmark#add('https://g.example', '', 'f2', 1)
  call webmarks#app#folder#add('Docs', 'f2')
endfunction

function! s:lines() abort
  return webmarks#app#listing#edit_lines(webmarks#app#store#current(),
        \ {'criterion': 'name', 'favorite_first': v:true}, 0)
endfunction

function! s:apply(lines, snapshot) abort
  let l:p = webmarks#app#edit#parse(a:lines, a:snapshot)
  if !l:p.ok
    return l:p
  endif
  return webmarks#app#edit#commit(l:p.entries, l:p.delete_ids, 2000)
endfunction

function! s:get(id) abort
  return webmarks#app#store#find_bookmark(webmarks#app#store#current(), a:id)
endfunction

function! s:folder(id) abort
  return webmarks#app#store#find_folder(webmarks#app#store#current(), a:id)
endfunction

function! s:suite.edit_lines_round_trip_is_no_change() abort
  call s:seed()
  let l:e = s:lines()
  call s:assert.equals(l:e.lines, [
        \ '  Alpha  https://a.example' . s:m('b1'),
        \ 'Dev/' . s:m('f2'),
        \ '  Docs/' . s:m('f4'),
        \ '    https://g.example' . s:m('b3')])
  let l:before = readfile(g:webmarks_file)
  let l:r = s:apply(l:e.lines, l:e.ids)
  call s:assert.true(l:r.ok, string(l:r))
  call s:assert.false(l:r.changed)
  call s:assert.equals(readfile(g:webmarks_file), l:before)
endfunction

function! s:suite.empty_store_hint_line() abort
  let l:e = s:lines()
  call s:assert.equals(l:e.lines, ['# add lines here:  name  https://example.com'])
  call s:assert.true(s:apply(l:e.lines, l:e.ids).ok)
endfunction

function! s:suite.rename_move_favorite_url_add_delete_at_once() abort
  call s:seed()
  call webmarks#app#bookmark#add('https://z.example', 'Zed', v:null, 1)
  let l:e = s:lines()
  let l:r = s:apply([
        \ "★ Alpha 2  https://a2.example" . s:m('b1'),
        \ 'Dev/' . s:m('f2'),
        \ '  Docs/' . s:m('f4'),
        \ '      Guide  https://g.example' . s:m('b3'),
        \ '    New  https://new.example',
        \ 'Fresh/',
        \ '    https://inside.example',
        \ '  https://fresh.example',
        \ ], l:e.ids)
  call s:assert.true(l:r.ok, string(l:r))
  call s:assert.equals(s:get('b1').display_name, 'Alpha 2')
  call s:assert.equals(s:get('b1').url, 'https://a2.example')
  call s:assert.true(s:get('b1').is_favorite)
  call s:assert.equals([s:get('b3').display_name, s:get('b3').name_source, s:get('b3').folder_id], ['Guide', 'manual', 'f4'])
  call s:assert.equals(s:get('b5'), v:null)
  let l:data = webmarks#app#store#current()
  let l:new = filter(copy(l:data.bookmarks), 'v:val.url ==# "https://new.example"')[0]
  call s:assert.equals([l:new.display_name, l:new.folder_id], ['New', 'f2'])
  let l:fresh = filter(copy(l:data.folders), 'v:val.name ==# "Fresh"')[0]
  let l:inside = filter(copy(l:data.bookmarks), 'v:val.url ==# "https://inside.example"')[0]
  call s:assert.equals(l:inside.folder_id, l:fresh.id)
  let l:root_new = filter(copy(l:data.bookmarks), 'v:val.url ==# "https://fresh.example"')[0]
  call s:assert.equals(l:root_new.folder_id, v:null)
  call s:assert.equals(sort(map(copy(l:r.fetch_title), 'v:val.url')), ['https://fresh.example', 'https://inside.example'])
  call s:assert.equals(l:r.counts, {'added': 4, 'renamed': 2, 'moved': 1, 'url_changed': 1,
        \ 'favorite_changed': 1, 'deleted': 1})
endfunction

function! s:suite.empty_name_goes_back_to_automatic() abort
  call s:seed()
  let l:e = s:lines()
  let l:lines = copy(l:e.lines)
  let l:lines[0] = '  https://a.example' . s:m('b1')
  let l:r = s:apply(l:lines, l:e.ids)
  call s:assert.true(l:r.ok)
  call s:assert.equals([s:get('b1').display_name, s:get('b1').name_source], ['https://a.example', 'url'])
  call s:assert.equals(l:r.fetch_title, [{'id': 'b1', 'url': 'https://a.example'}])
endfunction

function! s:suite.provisional_url_change_follows_and_refetches() abort
  call s:seed()
  let l:e = s:lines()
  let l:lines = copy(l:e.lines)
  let l:lines[3] = '    https://g2.example' . s:m('b3')
  let l:r = s:apply(l:lines, l:e.ids)
  call s:assert.equals([s:get('b3').url, s:get('b3').display_name], ['https://g2.example', 'https://g2.example'])
  call s:assert.equals(l:r.fetch_title, [{'id': 'b3', 'url': 'https://g2.example'}])
endfunction

function! s:suite.folder_rename_and_move() abort
  call s:seed()
  let l:e = s:lines()
  let l:r = s:apply(['  Alpha  https://a.example' . s:m('b1'), 'Development/' . s:m('f2'),
        \ '    https://g.example' . s:m('b3'), 'Docs/' . s:m('f4')], l:e.ids)
  call s:assert.true(l:r.ok, string(l:r))
  call s:assert.equals(s:folder('f2').name, 'Development')
  call s:assert.equals(s:folder('f4').parent_id, v:null)
  call s:assert.equals(s:get('b3').folder_id, 'f2')
endfunction

function! s:suite.swapping_two_folders_levels_at_once() abort
  " moving a parent under its child in one edit: validated as a whole
  call s:seed()
  let l:e = s:lines()
  let l:r = s:apply(['  Alpha  https://a.example' . s:m('b1'), 'Docs/' . s:m('f4'),
        \ '  Dev/' . s:m('f2'), '      https://g.example' . s:m('b3')], l:e.ids)
  call s:assert.true(l:r.ok, string(l:r))
  call s:assert.equals([s:folder('f4').parent_id, s:folder('f2').parent_id], [v:null, 'f4'])
endfunction

function! s:suite.failure_saves_nothing() abort
  call s:seed()
  let l:e = s:lines()
  let l:before = readfile(g:webmarks_file)
  " a rename plus a duplicate URL: all or nothing
  let l:r = s:apply(['  Renamed  https://a.example' . s:m('b1'), 'Dev/' . s:m('f2'),
        \ '  Docs/' . s:m('f4'), '    https://g.example' . s:m('b3'), '    Dup  https://a.example'], l:e.ids)
  call s:assert.false(l:r.ok)
  call s:assert.equals(l:r.code, 'duplicate_url')
  call s:assert.equals(l:r.errors[0].lnum, 5)
  call s:assert.equals(readfile(g:webmarks_file), l:before)
endfunction

function! s:suite.items_added_elsewhere_are_kept() abort
  call s:seed()
  let l:e = s:lines()
  " another Vim adds a bookmark after the snapshot
  call webmarks#app#bookmark#add('https://other.example', 'Other', v:null, 1)
  let l:r = s:apply(l:e.lines[0:0] + l:e.lines[1:], l:e.ids)
  call s:assert.true(l:r.ok)
  call s:assert.not_equals(s:get('b5'), v:null)
endfunction

function! s:suite.items_removed_elsewhere_come_back_as_new() abort
  call s:seed()
  let l:e = s:lines()
  call webmarks#app#bookmark#remove('b1')
  let l:r = s:apply(l:e.lines, l:e.ids)
  call s:assert.true(l:r.ok, string(l:r))
  call s:assert.match(l:r.warnings[0], 'line 1: b1 was removed elsewhere')
  let l:back = filter(webmarks#app#store#current().bookmarks, 'v:val.url ==# "https://a.example"')
  call s:assert.equals(len(l:back), 1)
  call s:assert.not_equals(l:back[0].id, 'b1')
endfunction

function! s:suite.deleting_a_folder_with_hidden_children_fails() abort
  call s:seed()
  let l:e = s:lines()
  " the snapshot does not know b5, added to Docs elsewhere
  call webmarks#app#bookmark#add('https://hidden.example', 'Hidden', 'f4', 1)
  let l:r = s:apply(['  Alpha  https://a.example' . s:m('b1'), 'Dev/' . s:m('f2'),
        \ '  https://g.example' . s:m('b3')], l:e.ids)
  call s:assert.false(l:r.ok)
  call s:assert.equals(l:r.code, 'folder_not_empty')
  call s:assert.not_equals(s:folder('f4'), v:null)
endfunction

function! s:suite.deleting_a_folder_line_reparents_its_lines() abort
  call s:seed()
  let l:e = s:lines()
  " drop the Docs/ line only: nothing was inside it
  let l:r = s:apply(['  Alpha  https://a.example' . s:m('b1'), 'Dev/' . s:m('f2'),
        \ '    https://g.example' . s:m('b3')], l:e.ids)
  call s:assert.true(l:r.ok, string(l:r))
  call s:assert.equals(s:folder('f4'), v:null)
  call s:assert.equals(l:r.counts.deleted, 1)
endfunction

" --- review regressions ----------------------------------------------------

function! s:suite.hostile_names_round_trip_without_change() abort
  " names that look like the star slot, a comment, an escape or a URL
  call webmarks#app#folder#add('Dev', v:null)
  call webmarks#app#folder#add('Sub', 'f1')
  call webmarks#app#folder#add('# not a comment', v:null)
  call webmarks#app#folder#add('see https://x.example', v:null)
  let l:names = ['* star', "★ star", '# hash', '\back', 'ends https://y.example']
  let l:n = 0
  for l:folder in [v:null, 'f1', 'f2']
    for l:name in l:names
      let l:n += 1
      call webmarks#app#bookmark#add(printf('https://h%d.example', l:n), l:name, l:folder, 1)
    endfor
  endfor
  let l:before = webmarks#app#store#current()
  let l:e = s:lines()
  let l:p = webmarks#app#edit#parse(l:e.lines, l:e.ids)
  call s:assert.true(l:p.ok, string(l:p))
  let l:r = webmarks#app#edit#commit(l:p.entries, l:p.delete_ids, 2000, l:e.shown)
  call s:assert.true(l:r.ok, string(l:r))
  call s:assert.false(l:r.changed, string(get(l:r, 'counts', {})))
  call s:assert.equals(webmarks#app#store#current(), l:before)
endfunction

function! s:suite.untouched_fields_keep_changes_made_meanwhile() abort
  call s:seed()
  let l:e = s:lines()
  " while editing: the title of b3 arrives, another Vim favourites b1
  call webmarks#app#bookmark#apply_title('b3', 'https://g.example', function('WebmarksTestConst', [1]), 'Late title')
  call webmarks#app#bookmark#toggle_favorite('b1')
  let l:lines = copy(l:e.lines)
  " the user only renames the folder
  let l:lines[1] = 'Development/' . s:m('f2')
  let l:p = webmarks#app#edit#parse(l:lines, l:e.ids)
  let l:r = webmarks#app#edit#commit(l:p.entries, l:p.delete_ids, 2000, l:e.shown)
  call s:assert.true(l:r.ok, string(l:r))
  call s:assert.equals([s:get('b3').display_name, s:get('b3').name_source], ['Late title', 'fetched'])
  call s:assert.true(s:get('b1').is_favorite)
  call s:assert.equals(s:folder('f2').name, 'Development')
  call s:assert.equals(l:r.fetch_title, [])
  call s:assert.equals(l:r.counts.renamed, 1)
endfunction

function! s:suite.folder_marker_decides_the_kind() abort
  let l:e = s:one('see https://x.example/' . s:m('f3'))
  call s:assert.equals([l:e.kind, l:e.name], ['folder', 'see https://x.example'])
  " without a marker the URL wins
  call s:assert.equals(s:one('  see https://x.example/').kind, 'bookmark')
endfunction

function! s:suite.escaped_names_are_unescaped() abort
  call s:assert.equals(s:one('  \* star  https://a.example').name, '* star')
  call s:assert.false(s:one('  \* star  https://a.example').favorite)
  call s:assert.equals(s:one('\# hash/').name, '# hash')
  call s:assert.equals(s:one('  \\back  https://a.example').name, '\back')
endfunction

function! s:suite.only_the_written_escapes_are_removed() abort
  call s:assert.equals(s:one('  \foo  https://a.example').name, '\foo')
  call s:assert.equals(s:one("  \\★ x  https://a.example").name, "★ x")
endfunction

function! s:suite.text_after_the_hidden_id_is_an_error() abort
  " `A` puts text after the concealed marker; it must not join the URL
  let l:r = s:err(['  name  https://a.example/' . s:m('b1') . 'x'])
  call s:assert.match(l:r.error, 'line 1: text after the hidden id')
  " trailing blanks are fine
  call s:assert.equals(s:one('  name  https://a.example/' . s:m('b1') . '  ').id, 'b1')
endfunction

function! s:suite.grammar_helpers_round_trip() abort
  for l:name in ['* x', "★ x", '# x', '\x', 'plain', '\\']
    call s:assert.equals(webmarks#app#listing#unescape_name(webmarks#app#listing#escape_name(l:name)), l:name)
  endfor
  call s:assert.equals(webmarks#app#listing#marker('b3'), s:m('b3'))
  call s:assert.match(s:m('f12'), webmarks#app#listing#conceal_pattern())
endfunction
