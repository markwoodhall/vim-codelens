if exists('g:loaded_codelens') || &cp
  finish
endif

let g:loaded_codelens = 1
let g:codelens_namespace = nvim_create_namespace('codelens')

if !exists('g:codelens_auto')
  let g:codelens_auto = 0
endif

if !exists('g:codelens_show_references')
  let g:codelens_show_references = 1
endif

if !exists('g:codelens_show_tests')
  let g:codelens_show_tests = 1
endif

if !exists('g:codelens_initial_wait_on_load_seconds')
  let g:codelens_initial_wait_on_load_seconds = 1
endif

if !exists('g:codelens_fg_colour')
  let g:codelens_fg_colour = '#444444'
endif

if !exists('g:codelens_bg_colour')
  let g:codelens_bg_colour = '#292D33'
endif

if !exists('g:codelens_allow_same_line')
  let g:codelens_allow_same_line = 1
endif

function! s:relative_to_seconds(unit, value) abort
  if a:unit == 'years'
    return a:value * 365 * 24 * 60 * 60
  elseif a:unit == 'months'
    return a:value * 30 * 24 * 60 * 60
  elseif a:unit == 'weeks'
    return a:value * 7 * 24 * 60 * 60
  elseif a:unit == 'days'
    return a:value * 24 * 60 * 60
  elseif a:unit == 'hours'
    return a:value * 60 * 60
  elseif a:unit == 'minutes'
    return a:value * 60
  elseif a:unit == 'seconds'
    return a:value
  endif
endfunction

function! s:most_recent(list) abort
  let recent = ''
  let last_score = 100 * 365 * 24 * 60 * 60
  for e in a:list
    if len(split(e, 'Date:')) > 1
      let date = split(e, 'Date:')[1]
      let date = trim(date)
      let parts = split(date, ',')
      let score = 0

      for p in parts
        let number = split(p, ' ')[0]
        let unit = split(p, ' ')[1]
        let score = score + s:relative_to_seconds(unit, number)
      endfor

      if score < last_score
        let last_score = score
        let recent = join(split(date, ' ')[0:-2], ' ') . ' by ' . trim(split(e, 'Date:')[0])
      endif
    endif
  endfor
  return recent
endfunction

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

function! s:process_git_log(job_id, data, event) dict
  if a:event == 'stdout'
    let data = a:data[0:-2]
    if len(data) >= 1
      let parts = split(data[0], '#')

      if len(parts) > 1
        let authors = split(parts[1], 'Author:')

        let named_authors = []
        for a in authors
          let auth = split(a, 'Date:')[0]
          let named_authors += [trim(auth)]
        endfor

        let author_count = len(s:unique(named_authors)) - 1

        let message = ''
        if len(authors) > 0

          let author = s:most_recent(authors)

          let message = author

          if author_count == 1
            let message = message . ' and 1 other'
          elseif author_count > 1
            let message = message . ' and ' . author_count . ' others'
          endif

          if len(parts) > 2
            if g:codelens_show_references == 1
              if exists('b:codelens_func')
                let references = parts[2] - 1
                if references > 1
                  let message = message . ', ' . references . ' references'
                elseif references == 1
                  let message = message . ', ' . references . ' reference'
                endif
              endif
            endif
          endif

          if len(parts) > 3
            if g:codelens_show_tests == 1
              if exists('b:codelens_func')
                let tests = parts[3] - 1
                if tests > 1
                  let message = message . ', ' . tests . ' tests'
                elseif tests == 1
                  let message = message . ', ' . tests . ' test'
                endif
              endif
            endif
          endif
        endif

        let line = parts[0]

        if line > 1 && substitute(getline(line-1), '\s', '', 'g') == ''
          let message = matchstr(getline(line), '^\s\{1,}') . message
          silent! call nvim_buf_set_virtual_text(nvim_get_current_buf(), g:codelens_namespace, line-2, [[message, 'CodeLensReference']], {})
        elseif g:codelens_allow_same_line == 1
          silent! call nvim_buf_set_virtual_text(nvim_get_current_buf(), g:codelens_namespace, line-1, [[message, 'CodeLensReference']], {})
        endif
      endif
    endif
  endif
endfunction

function! codelens#lens(wait_seconds)
  let filename = expand('%')
  call nvim_buf_clear_highlight(nvim_get_current_buf(), g:codelens_namespace, 0, -1)
  let num = 1
  let cmd = 'sleep ' . a:wait_seconds . ';'

  let s:callbacks = {
  \ 'on_stdout': function('s:process_git_log')
  \ }

  for line in getline(1, line('$'))
    if (b:codelens_generic == 1 && num == 1) || (exists('b:codelens_target') && line =~ b:codelens_target)
      let num_end_line = num + 1
      for end_line in getline(num_end_line, line('$'))
        if (b:codelens_generic == 1 && num_end_line == line('$')) || (exists('b:codelens_target') && end_line =~ b:codelens_target)
          break
        endif
        let num_end_line = num_end_line + 1
      endfor
      let cmd = cmd . 'username=$(git config user.name);echo "' . num . '"#$(git blame ' . filename . ' -L ' . num . ',' . (num_end_line - 1) . ' --date=relative  | cut -d "(" -f2 | cut -d ")" -f1 | sed  "s/^/Author: /" | sed "s/\([0-9]\+ [a-z]\+.* ago\)/\nDate: \1/" | sed "s/Not Committed Yet/$username*/")'

      if exists('b:codelens_func')
        let func = trim(matchstr(line, b:codelens_func))

        if g:codelens_show_references == 1
          let cmd = cmd . '#$(git grep --fixed-strings "'.func.'" | wc -l)'
        endif

        if g:codelens_show_tests == 1
          let cmd = cmd . '#$(git grep --fixed-strings "'.func.'" | grep "test/\|tests/" | wc -l)'
        endif
      endif
      let cmd = cmd . ';'
    endif
    let num = num + 1
  endfor
  let gitlogjob = jobstart(['bash', '-c', cmd], extend({'shell': 'shell 1'}, s:callbacks))
endfunction

function! s:should_bind()
  let status = system('git status')
  return status !~ 'fatal: not a git repository'
endfunction

function! s:is_handled()
  return &ft ==# 'clojure' || &ft ==# 'vim' || &ft ==# 'terraform' || &ft ==# 'python' || &ft ==# 'sql' || &ft ==# 'javascript'
endfunction

augroup codelens
  autocmd!

  autocmd filetype * if !s:is_handled() && !exists('b:codelens_generic') | let b:codelens_generic = 1 | endif

  autocmd filetype clojure if !exists('b:codelens_generic') | let b:codelens_generic = 0 | endif
  autocmd filetype clojure if !exists('b:codelens_target') | let b:codelens_target = '^(def\|^(ns\|^(deftest\|^(\w\{1,}\/def\|^(extend-' | endif
  autocmd filetype clojure if !exists('b:codelens_scope_end') | let b:codelens_scope_end = '^(def\|^(ns\|^(deftest\|^(\w\{1,}\/def^(extend-' | endif
  autocmd filetype clojure if !exists('b:codelens_func') | let b:codelens_func = '\s:\{0,}\w\{1,}[-.]\{0,}\w\{1,}' | endif

  autocmd filetype vim if !exists('b:codelens_generic') | let b:codelens_generic = 0 | endif
  autocmd filetype vim if !exists('b:codelens_scope_end') | let b:codelens_scope_end = '^function!\|^augroup' | endif
  autocmd filetype vim if !exists('b:codelens_target') | let b:codelens_target = '^function!\|\(augroup\s\)\(END\)\@!' | endif
  autocmd filetype vim if !exists('b:codelens_func') | let b:codelens_func = '\s\w\{1,}\W\{0,}\w\{1,}' | endif

  autocmd filetype javascript if !exists('b:codelens_generic') | let b:codelens_generic = 0 | endif
  autocmd filetype javascript if !exists('b:codelens_scope_end') | let b:codelens_scope_end = '^function' | endif
  autocmd filetype javascript if !exists('b:codelens_target') | let b:codelens_target = '^function' | endif
  autocmd filetype javascript if !exists('b:codelens_func') | let b:codelens_func = '\s\w\{1,}\w\{1,}' | endif

  autocmd filetype sql if !exists('b:codelens_generic') | let b:codelens_generic = 0 | endif
  autocmd filetype sql if !exists('b:codelens_scope_end') | let b:codelens_scope_end = '--\s:name' | endif
  autocmd filetype sql if !exists('b:codelens_target') | let b:codelens_target = '--\s:name' | endif
  autocmd filetype sql if !exists('b:codelens_func') | let b:codelens_func = '\s\w\{1,}[-.]\{0,}\w\{1,}' | endif

  autocmd filetype python if !exists('b:codelens_generic') | let b:codelens_generic = 0 | endif
  autocmd filetype python if !exists('b:codelens_scope_end') | let b:codelens_scope_end = '^class\s\|^def\s\|\sdef\s' | endif
  autocmd filetype python if !exists('b:codelens_target') | let b:codelens_target = '^class\s\|^def\s\|\sdef\s' | endif
  autocmd filetype python if !exists('b:codelens_func') | let b:codelens_func = '\(\s\{1}\)\(def\)\@!\(\w\{1,}\)' | endif

  autocmd filetype terraform if !exists('b:codelens_generic') | let b:codelens_generic = 0 | endif
  autocmd filetype terraform if !exists('b:codelens_scope_end') | let b:codelens_scope_end = '^module\|^resource\|^output\|^data\|^provider' | endif
  autocmd filetype terraform if !exists('b:codelens_target') | let b:codelens_target = '^module\|^resource\|^output\|^data\|^provider' | endif

  autocmd BufWinEnter * if g:codelens_auto == 1 && (exists('b:codelens_target') || exists('b:codelens_generic')) && s:should_bind() | silent! call codelens#lens(g:codelens_initial_wait_on_load_seconds) | endif
  autocmd BufWritePost * if g:codelens_auto == 1 && (exists('b:codelens_target') || exists('b:codelens_generic')) && s:should_bind() | silent! call codelens#lens(0) | endif

  autocmd filetype * command! -buffer CodelensClear :call nvim_buf_clear_highlight(nvim_get_current_buf(), g:codelens_namespace, 0, -1)
  autocmd filetype * command! -buffer Codelens :call codelens#lens(0)

  autocmd BufEnter * if (exists('b:codelens_target') || exists('b:codelens_generic')) && s:should_bind() | execute 'hi CodeLensReference guifg=' . g:codelens_fg_colour . ' guibg=' . g:codelens_bg_colour | endif
augroup END
