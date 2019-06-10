if exists('g:loaded_codelens') || &cp
  finish
endif

let g:loaded_codelens = 1
let g:codelens_namespace = nvim_create_namespace('codelens')

if !exists('g:codelens_auto')
  let g:codelens_auto = 0
endif

function! s:unique(list) abort
    let seen = {}
    let uniques = []
    for e in a:list
        let k = string(e)
        if !has_key(seen, k)
            let seen[k] = 1
            call add(uniques, e)
        endif
    endfor
    return uniques
endfunction

function! s:ProcessGitLog(job_id, data, event) dict
  if a:event == 'stdout'
    let data = a:data[0:-2]
    if len(data) >= 1
      let parts = split(data[0], '#')
      let authors = split(parts[1], 'Author:')

      let named_authors = []
      for a in authors
        let auth = split(a, 'Date:')[0]
        let named_authors += [trim(auth)]
      endfor

      let author_count = len(s:unique(named_authors)) - 1
      let latest_author_and_date = split(parts[1], 'Author:')[0] 
      let author = split(split(latest_author_and_date, 'Date:')[0], '<')[0]
      let date = split(latest_author_and_date, 'Date:')[1]
      let message = trim(date) . ' by ' . trim(author) 
      if author_count == 1
        let message = message . ' and 1 other' 
      elseif author_count > 1
        let message = message . ' and ' . author_count . ' others' 
      endif

      let line = parts[0]
  
      if getline(line) =~ b:codelens_target
        if line > 1 && substitute(getline(line-1), '\s', '', 'g') == ''
          silent! call nvim_buf_set_virtual_text(nvim_get_current_buf(), g:codelens_namespace, line-2, [[message, 'Comment']], {})
        else
          silent! call nvim_buf_set_virtual_text(nvim_get_current_buf(), g:codelens_namespace, line-1, [[message, 'Comment']], {})
        endif
      endif
    endif
  endif
endfunction

function! codelens#lens()
  let filename = expand('%')

  let num = 1
  for line in getline(1, line('$'))
    call nvim_buf_clear_highlight(nvim_get_current_buf(), g:codelens_namespace, 0, -1)
    if line =~ b:codelens_target
      let s:callbacks = {
      \ 'on_stdout': function('s:ProcessGitLog')
      \ }

      let num_end_line = num + 1
      for end_line in getline(num_end_line, line('$'))
        if end_line =~ b:codelens_scope_end
          let num_end_line = num_end_line - 2
          break 
        endif
        let num_end_line = num_end_line +  1
      endfor
      let cmd = 'echo "' . num . '"#$(git log -L ' . num . ',' . num_end_line . ':' . filename . ' --date=relative --no-patch | grep "^Author:\|^Date:");'
      let gitlogjob = jobstart(['bash', '-c', cmd], extend({'shell': 'shell 1'}, s:callbacks))
    endif
    let num = num + 1
  endfor
endfunction

function! s:should_bind()
  let status = system('git status') 
  return status !~ 'fatal: not a git repository'
endfunction

augroup codelens
  autocmd!
  autocmd filetype clojure if !exists('b:codelens_target') | let b:codelens_target = '^(def\|^(ns\|^(deftest\|^(\w\{1,}\/def' | endif
  autocmd filetype clojure if !exists('b:codelens_scope_end') | let b:codelens_scope_end = '^(def\|^(ns\|^(deftest\|^(\w\{1,}\/def' | endif

  autocmd filetype vim if !exists('b:codelens_scope_end') | let b:codelens_scope_end = 'function!' | endif
  autocmd filetype vim if !exists('b:codelens_target') | let b:codelens_target = '^function!' | endif

  autocmd BufRead * if g:codelens_auto == 1 && exists('b:codelens_target') && s:should_bind() | silent! call codelens#lens() | endif
  autocmd BufWrite * if g:codelens_auto == 1 && exists('b:codelens_target') && s:should_bind() | silent! call codelens#lens() | endif

  autocmd filetype * command! -buffer CodelensClear :call nvim_buf_clear_highlight(nvim_get_current_buf(), g:codelens_namespace, 0, -1)
  autocmd filetype * command! -buffer Codelens :call codelens#lens()
augroup END

