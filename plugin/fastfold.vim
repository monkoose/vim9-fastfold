vim9script

if exists('g:loaded_fastfold')
  finish
endif
g:loaded_fastfold = 1

# Options {{{
extend(g:, {
  fastfold_fdmhook: false,
  fastfold_savehook: true,
  fastfold_force: false,
  fastfold_skip_filetypes: [],
  fastfold_minlines: 100,
  fastfold_fold_command_suffixes: ['x', 'X', 'a', 'A', 'o', 'O', 'c', 'C'],
  fastfold_fold_movement_commands: [']z', '[z', 'zj', 'zk'],
}, 'keep')
# }}}

def EnterWin()
  if Skip()
    if exists('w:lastfdm')
      unlet w:lastfdm
    endif
  else
    w:lastfdm = &l:foldmethod
    &l:foldmethod = 'manual'
  endif
enddef

def LeaveWin()
  if exists('w:predifffdm')
    if empty(&l:foldmethod) || &l:foldmethod == 'manual'
      &l:foldmethod = w:predifffdm
      unlet w:predifffdm
      return
    elseif &l:foldmethod != 'diff'
      unlet w:predifffdm
    endif
  endif

  if exists('w:lastfdm')
    if &l:foldmethod == 'diff'
      w:predifffdm = w:lastfdm
    elseif &l:foldmethod == 'manual'
      &l:foldmethod = w:lastfdm
    endif
  endif
enddef

def WinDo(command: string)
  for winid in gettabinfo(0)[0].windows
    win_execute(winid, 'keepjumps noautocmd ' .. command, 'silent!')
  endfor
enddef

# WinEnter then TabEnter then BufEnter then BufWinEnter
def UpdateWin()
  const curwin: number = winnr()
  WinDo($'if winnr() == {curwin} | LeaveWin() | endif')
  WinDo($'if winnr() == {curwin} | EnterWin() | endif')
enddef

def UpdateBuf(feedback: bool)
  # skip if another session still loading
  if exists('g:SessionLoad') | return | endif

  const curbuf: number = bufnr()
  WinDo($'if bufnr() == {curbuf} | LeaveWin() | endif')
  WinDo($'if bufnr() == {curbuf} | EnterWin() | endif')

  if !feedback | return | endif

  if !exists('w:lastfdm')
    echomsg $"'{&l:foldmethod}' folds already continuously updated"
  else
    echomsg $"updated '{w:lastfdm}' folds"
  endif
enddef

def UpdateTab()
  # skip if another session still loading
  if exists('g:SessionLoad') | return | endif

  WinDo('LeaveWin()')
  WinDo('EnterWin()')
enddef

def Skip(): bool
  if g:fastfold_force ||
      line('$') <= g:fastfold_minlines ||
      !&l:modifiable ||
      !empty(&l:buftype) ||
      &l:foldmethod == 'syntax' ||
      &l:foldmethod == 'expr' ||
      !IsReasonable() ||
      index(g:fastfold_skip_filetypes, &l:filetype) != -1 ||
    return true
  endif

  return false
enddef

command! -bar -bang FastFoldUpdate UpdateBuf(<bang>0)

nnoremap <silent> <Plug>(FastFoldUpdate) <ScriptCmd>FastFoldUpdate!<CR>

if !hasmapto('<Plug>(FastFoldUpdate)', 'n') && empty(mapcheck('zuz', 'n'))
  nmap zuz <Plug>(FastFoldUpdate)
endif

for suffix in g:fastfold_fold_command_suffixes
  exe $'nnoremap <silent> z{suffix} <ScriptCmd>UpdateWin()<CR>z{suffix}'
endfor

for cmd in g:fastfold_fold_movement_commands
  exe $"nnoremap <silent><expr> {cmd} '<ScriptCmd>UpdateWin()<CR>' .. v:count .. '{cmd}'"
  exe $"xnoremap <silent><expr> {cmd} '<ScriptCmd>UpdateWin()<CR>gv' .. v:count .. '{cmd}'"
  exe $"onoremap <silent><expr> {cmd} '<ScriptCmd>UpdateWin()<CR>' .. '\"' .. v:register .. v:operator .. v:count1 .. '{cmd}'"
endfor

def OnWinEnter()
  w:winenterbuf = bufnr()
  if exists('b:lastfdm')
    w:lastfdm = b:lastfdm
  endif
enddef

def OnBufEnter()
  if exists('w:winenterbuf')
    if w:winenterbuf != bufnr()
      unlet! w:lastfdm
    endif
    unlet w:winenterbuf
  endif

  # Update folds after entering a changed buffer
  if !exists('b:lastchangedtick')
    b:lastchangedtick = b:changedtick
  endif
  if b:changedtick != b:lastchangedtick && (&l:foldmethod != 'diff' && exists('b:predifffdm'))
    UpdateBuf(false)
  endif
enddef

def OnWinLeave()
  if exists('w:lastfdm')
    b:lastfdm = w:lastfdm
  elseif exists('b:lastfdm')
    unlet b:lastfdm
  endif

  if exists('w:predifffdm')
    b:predifffdm = w:predifffdm
  elseif exists('b:predifffdm')
    unlet b:predifffdm
  endif
enddef

def OnBufWinEnter()
  if !exists('b:fastfold')
    UpdateBuf(false)
    b:fastfold = 1
  endif
enddef

def Init()
  UpdateTab()

  augroup FastFoldEnter
    autocmd!
    # Make foldmethod local to buffer instead of window
    autocmd WinEnter * OnWinEnter()
    autocmd BufEnter * OnBufEnter()
    autocmd WinLeave * OnWinLeave()
    # Update folds after foldmethod set by filetype autocmd
    autocmd FileType * UpdateBuf(false)
    # Update folds after foldmethod set by :loadview or :source Session.vim
    autocmd SessionLoadPost * UpdateBuf(false)
    # Update folds after foldmethod set by modeline
    if g:fastfold_fdmhook
      autocmd OptionSet foldmethod UpdateBuf(false)
      autocmd BufRead * UpdateBuf(false)
    else
      autocmd BufWinEnter * OnBufWinEnter()
    endif
    # Update folds after entering a changed buffer
    autocmd BufLeave * b:lastchangedtick = b:changedtick
    # Update folds after saving
    if g:fastfold_savehook
      autocmd BufWritePost * UpdateBuf(false)
    endif
  augroup END
enddef

augroup FastFold
  autocmd!
  if !v:vim_did_enter
    autocmd VimEnter * Init()
  else
    Init()
  endif
augroup end

# vim: fdm=marker
