scriptencoding utf-8
" test/domain_html.vim - ported from mdlink/test/title_extraction.vim

let s:suite = themis#suite('domain_html')
let s:assert = themis#helper('assert')

" Test 1: Basic one-line title
function! s:suite.test_basic_title() abort
  let html = '<head><title>Example Domain</title></head>'
  let result = webmarks#domain#html#extract_title(html)
  call s:assert.equal(result, 'Example Domain')
endfunction

" Test 2: Multiline title with whitespace
function! s:suite.test_multiline_title() abort
  let html = "<head>\n  <title>\n    会社名 | サービス名\n  </title>\n</head>"
  let result = webmarks#domain#html#extract_title(html)
  call s:assert.equal(result, '会社名 | サービス名')
endfunction

" Test 3: Uppercase title tags
function! s:suite.test_uppercase_title() abort
  let html = '<HEAD><TITLE>Big Title</TITLE></HEAD>'
  let result = webmarks#domain#html#extract_title(html)
  call s:assert.equal(result, 'Big Title')
endfunction

" Test 4: Title with attributes
function! s:suite.test_title_with_attributes() abort
  let html = '<head><title data-x="1">Attr Title</title></head>'
  let result = webmarks#domain#html#extract_title(html)
  call s:assert.equal(result, 'Attr Title')
endfunction

" Test 5: Head-less HTML (fragment)
function! s:suite.test_headless_html() abort
  let html = '<title>Loose Title</title>'
  let result = webmarks#domain#html#extract_title(html)
  call s:assert.equal(result, 'Loose Title')
endfunction

" Test 6: Multiple titles (last non-empty wins)
function! s:suite.test_multiple_titles() abort
  let html = "<head>\n  <title>Old Title</title>\n  <title>New Title</title>\n</head>"
  let result = webmarks#domain#html#extract_title(html)
  call s:assert.equal(result, 'New Title')
endfunction

" Test 7: Empty title followed by valid title
function! s:suite.test_empty_then_valid_title() abort
  let html = "<head>\n  <title>   </title>\n  <title>Real Title</title>\n</head>"
  let result = webmarks#domain#html#extract_title(html)
  call s:assert.equal(result, 'Real Title')
endfunction

" Test 8: SVG title mixed in (head priority)
function! s:suite.test_svg_title_avoided() abort
  let html = "<head><title>Head Title</title></head>\n<body>\n  <svg><title>Icon</title></svg>\n  <svg><title>Icon2</title></svg>\n</body>"
  let result = webmarks#domain#html#extract_title(html)
  call s:assert.equal(result, 'Head Title')
endfunction

" Test 9: Greater-than character in title
function! s:suite.test_greater_than_in_title() abort
  let html = '<head><title>Foo > Bar</title></head>'
  let result = webmarks#domain#html#extract_title(html)
  call s:assert.equal(result, 'Foo > Bar')
endfunction

" Test 10: HTML entity decoding
function! s:suite.test_html_entity_decoding() abort
  let html = '<head><title>Tom &amp; Jerry &gt; Cat</title></head>'
  let result = webmarks#domain#html#extract_title(html)
  call s:assert.equal(result, 'Tom & Jerry > Cat')
endfunction

" Test 11: Numeric reference decoding (emoji)
function! s:suite.test_numeric_reference_decoding() abort
  let html = '<head><title>Hello &#x1F600; &#128512;</title></head>'
  let result = webmarks#domain#html#extract_title(html)
  call s:assert.equal(result, 'Hello 😀 😀')
endfunction

" Test 12: HTML tags within title
function! s:suite.test_tags_within_title() abort
  let html = '<head><title>Hi <b>Bold</b> Title</title></head>'
  let result = webmarks#domain#html#extract_title(html)
  call s:assert.equal(result, 'Hi Bold Title')
endfunction

" Test 13: No title tag
function! s:suite.test_no_title() abort
  let html = '<head></head><body><div id="app"></div></body>'
  let result = webmarks#domain#html#extract_title(html)
  call s:assert.equal(result, v:null)
endfunction

" Test 14: Broken title tag
function! s:suite.test_broken_title() abort
  let html = '<head><title>Broken...'
  let result = webmarks#domain#html#extract_title(html)
  call s:assert.equal(result, v:null)
endfunction

" Test 15: Empty string input
function! s:suite.test_empty_input() abort
  let html = ''
  let result = webmarks#domain#html#extract_title(html)
  call s:assert.equal(result, v:null)
endfunction

" Test 16: Title with multiple spaces and newlines
function! s:suite.test_multiple_whitespace_normalization() abort
  let html = "<head><title>   Multiple    Spaces\n\n\tAnd\tTabs   </title></head>"
  let result = webmarks#domain#html#extract_title(html)
  call s:assert.equal(result, 'Multiple Spaces And Tabs')
endfunction

" Test 17: Mixed case title tag with attributes and spacing
function! s:suite.test_mixed_case_with_attributes() abort
  let html = '<head><TiTlE   class="test"  id="main-title"  >Mixed Case</TiTlE></head>'
  let result = webmarks#domain#html#extract_title(html)
  call s:assert.equal(result, 'Mixed Case')
endfunction

" Test 18: All common HTML entities
function! s:suite.test_all_common_entities() abort
  let html = '<head><title>&amp; &lt; &gt; &quot; &#39; test&nbsp;space</title></head>'
  let result = webmarks#domain#html#extract_title(html)
  call s:assert.equal(result, '& < > " '' test space')
endfunction

" Test 19: Decimal numeric reference
function! s:suite.test_decimal_numeric_ref() abort
  let html = '<head><title>Copy&#169;right</title></head>'
  let result = webmarks#domain#html#extract_title(html)
  call s:assert.equal(result, 'Copy©right')
endfunction

" Test 20: Multiple numeric references
function! s:suite.test_multiple_numeric_refs() abort
  let html = '<head><title>&#72;&#101;&#108;&#108;&#111;</title></head>'
  let result = webmarks#domain#html#extract_title(html)
  call s:assert.equal(result, 'Hello')
endfunction

" Test 21: Invalid/zero codepoint (edge case)
function! s:suite.test_invalid_codepoint() abort
  let html = '<head><title>Text&#0;here</title></head>'
  let result = webmarks#domain#html#extract_title(html)
  call s:assert.not_equal(result, v:null)
  call s:assert.match(result, 'Text.*here')
endfunction

" Test 22: Very large codepoint (boundary test)
function! s:suite.test_large_codepoint() abort
  let html = '<head><title>Emoji &#128512;</title></head>'
  let result = webmarks#domain#html#extract_title(html)
  call s:assert.equal(result, 'Emoji 😀')
endfunction

" Test 23: Mixed entity types in one title
function! s:suite.test_mixed_entity_types() abort
  let html = '<head><title>&lt;Tag&gt; &#169; &#x00A9;</title></head>'
  let result = webmarks#domain#html#extract_title(html)
  call s:assert.equal(result, '<Tag> © ©')
endfunction

" Added: the double decode kept from the original (documented behaviour)
function! s:suite.test_double_decode_is_kept() abort
  call s:assert.equal(webmarks#domain#html#decode_entities('&amp;lt;'), '<')
  call s:assert.equal(webmarks#domain#html#extract_title('<title>a &amp;lt; b</title>'), 'a < b')
endfunction

" Added: unknown named entities are left alone, non-strings are v:null
function! s:suite.test_unknown_entity_and_types() abort
  call s:assert.equal(webmarks#domain#html#decode_entities('&copy; &foo;'), '&copy; &foo;')
  call s:assert.equal(webmarks#domain#html#extract_title(0), v:null)
endfunction

" Added: a decoded character that is special in a substitute() replacement
function! s:suite.test_decoded_ampersand_and_backslash() abort
  call s:assert.equal(webmarks#domain#html#decode_entities('a&#38;b &#92;n'), 'a&b \n')
endfunction
