scriptencoding utf-8
let s:suite = themis#suite('domain_text')
let s:assert = themis#helper('assert')

function! s:san(s) abort
  return webmarks#domain#text#sanitize(a:s)
endfunction

function! s:suite.plain_text_is_kept() abort
  let l:r = s:san('日本語 ★ Title')
  call s:assert.true(l:r.ok)
  call s:assert.equals(l:r.value, '日本語 ★ Title')
endfunction

function! s:suite.controls_become_spaces() abort
  call s:assert.equals(s:san("a\tb\nc\rd\x01e\x7ff\u0085g").value, 'a b c d e f g')
endfunction

function! s:suite.bidi_and_zero_width_are_removed() abort
  call s:assert.equals(s:san("ab​c‮d⁦e‏f﻿g").value, 'abcdefg')
endfunction

function! s:suite.whitespace_is_squeezed_and_trimmed() abort
  call s:assert.equals(s:san("   a    b   ").value, 'a b')
endfunction

function! s:suite.truncated_to_200_chars() abort
  let l:r = s:san(repeat('あ', 250))
  call s:assert.equals(strchars(l:r.value), 200)
endfunction

function! s:suite.invalid_utf8() abort
  let l:r = s:san("abc\x82def")
  call s:assert.false(l:r.ok)
  call s:assert.equals(l:r.code, 'invalid_text')
  call s:assert.false(webmarks#domain#text#is_utf8("\xff"))
  call s:assert.true(webmarks#domain#text#is_utf8('ok'))
endfunction

function! s:suite.non_string_is_invalid() abort
  call s:assert.equals(s:san(3).code, 'invalid_text')
endfunction

function! s:suite.empty_after_cleaning() abort
  call s:assert.equals(s:san('').code, 'empty_name')
  call s:assert.equals(s:san(" \t​ ").code, 'empty_name')
endfunction
