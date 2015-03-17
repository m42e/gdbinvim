"
" GDBinVim : interface for GDB inside Vim
" Copyright (C) 2014  Joel
"
" This program is free software: you can redistribute it and/or modify
" it under the terms of the GNU General Public License as published by
" the Free Software Foundation, either version 3 of the License, or
" (at your option) any later version.
"
" This program is distributed in the hope that it will be useful,
" but WITHOUT ANY WARRANTY; without even the implied warranty of
" MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
" GNU General Public License for more details.
"
" You should have received a copy of the GNU General Public License
" along with this program.  If not, see <http://www.gnu.org/licenses/>.
"

let g:STACK_NB_LINES = 15
let g:HEXDUMP_NB_LINES = 15
let s:KEEP_N_LINES_BEFORE = 10

let s:plugin_started = 0
let s:disassembled_addr = []  " lines printed on vim
let s:curr_line = 0           " current line on vim of the instruction pointer
let s:curr_addr = ""          " current instruction pointer address
let s:hexdump_addr = ""
let s:breakpoints = []
let s:id_breakpoints = []
let s:history_disasm = []
let s:START_LINE = 1      " first line in vim for the disassembled code 
                          " (we can put other infos on top)

let s:buffer_code = -1
let s:buffer_registers = -1
let s:buffer_stack = -1
let s:buffer_hexdump = -1


fu! s:Select_buffer_code()
  wincmd h
  wincmd k
endf


fu! s:Select_buffer_hexdump()
  wincmd l
  wincmd k
endf


fu! s:Select_buffer_stack()
  wincmd l
  wincmd j
endf


fu! s:Select_buffer_registers()
  wincmd h
  wincmd j
endf


fu!  s:Create_buffers()
  setlocal modifiable
  bdelete

  " for showing sign column
  sign define dummy

  vnew

  " CODE
  setlocal nomodifiable
  setlocal buftype=nowrite
  setlocal noswapfile
  setlocal nonumber
  setlocal scrolloff=5
  setlocal filetype=nasm
  silent file [CODE]
  let s:buffer_code = bufnr("")

  syn match GdbBreakpoint /^B/
  syn match GdbCurrentLine /=>.*$/
  hi GdbBreakpoint ctermbg=196 ctermfg=196
  hi GdbCurrentLine ctermbg=202 ctermfg=255
  hi SignBreak ctermbg=196 ctermfg=196
  hi CursorLine ctermbg=none guibg=none

  sign define break text=B texthl=SignBreak

  belowright 11new

  " REGISTERS
  setlocal nomodifiable
  setlocal buftype=nowrite
  setlocal nonumber
  setlocal noswapfile
  silent file [REGISTERS]
  let s:buffer_registers = bufnr("")

  syn match GdbRegister "^[0-9a-zA-Z]\+"
  syn match GdbNumber "0x[0-9a-fA-F]\+"
  syn match GdbString "\".*\""
  syn keyword GdbFlagSet carry parity adjust zero sign trap interrupt direction overflow
  syn keyword GdbFlagUnset CARRY PARITY ADJUST ZERO SIGN TRAP INTERRUPT DIRECTION OVERFLOw
  hi GdbRegister ctermfg=11
  hi GdbNumber ctermfg=135
  hi GdbString ctermfg=144
  hi GdbFlagSet ctermfg=82
  hi GdbFlagUnset ctermfg=160
  hi CursorLine ctermbg=none guibg=none

  wincmd l
  wincmd k

  belowright new

  " STACK
  setlocal nomodifiable
  setlocal buftype=nowrite
  setlocal nonumber
  setlocal noswapfile
  silent file [STACK]
  let s:buffer_stack = bufnr("")

  syn match GdbNumber "0x[0-9a-fA-F]\+"
  syn match GdbString "\".*\""
  hi GdbNumber ctermfg=135
  hi GdbString ctermfg=144
  hi CursorLine ctermbg=none guibg=none

  wincmd k

  " HEXDUMP
  setlocal nomodifiable
  setlocal buftype=nowrite
  setlocal nonumber
  setlocal noswapfile
  silent file [HEXDUMP]
  let s:buffer_hexdump = bufnr("")

  exec "sign place 9996 line=1 name=dummy buffer=" . s:buffer_hexdump
  exec "sign place 9997 line=1 name=dummy buffer=" . s:buffer_registers
  exec "sign place 9998 line=1 name=dummy buffer=" . s:buffer_stack
  exec "sign place 9999 line=1 name=dummy buffer=" . s:buffer_code

  redraw!
endf


fu! s:Start_plugin()
  if s:plugin_started
    return
  endif

  if ! s:CheckGdbIsRunning()
    return
  endif

  call s:Create_buffers()

  let asmsyntax = "nasm"

  call s:Map()
  call s:Info_target()

  let s:plugin_started = 1
endf


fu! s:CheckGdbIsRunning()
  call s:Select_buffer_code()
  call system("test -e result_fifo && test -e recv_cmd_fifo")
  if v:shell_error == 1
    echo "Gdb is not running or you are not in the same directory"
    return 0
  endif
  return 1
endf


fu! s:Map()
  nmap <silent> t :call Gdb_start()<CR>
  nmap <silent> s :call Gdb_step()<CR>
  nmap <silent> n :call Gdb_next()<CR>
  nmap <silent> r :call Gdb_reload()<CR>
  nmap <silent> c :call Gdb_continue()<CR>
  nmap <silent> p :GdbPrint "<C-r><C-w>"<CR>
  nmap <silent> x :GdbHexdump "<C-r><C-w>"<CR>
  nmap <silent> d :GdbDisassemble "<C-r><C-w>"<CR>
  nmap <silent> h :call Gdb_back_disassemble_history()<CR>
  nmap <silent> b :call Gdb_toggle_breakpoints()<CR>
  nmap <silent> k :GdbStack "<C-r><C-w>"<CR>
  nmap <silent> _b :call Gdb_save_breakpoints()<CR>
  nmap _d :GdbDisassemble 
  nmap _p :GdbPrint 
  nmap _x :GdbHexdump 
  nmap _k :GdbStack 
  nmap <silent> _c :call Gdb_clear_hexdump()<CR>
endf


fu! s:Print_value(addr)
  if s:Is_addr(a:addr)
    echo s:Command_vimget("xprint " . a:addr)[0]
  endif
endf


fu! s:Disassemble_addr(addr)
  if s:Is_addr(a:addr)
    call s:Disassemble(a:addr)
  endif
endf


fu! s:Command(cmd)
  " call this function only if it a special command for vim !
  " otherwise call Command_vim[get,exec_silent] which are wrappers for any commands
  call writefile([a:cmd . "\n"], "recv_cmd_fifo")
  return readfile("result_fifo")
endf


fu! s:Command_vimget(cmd)
  call writefile(["vimget \"" . a:cmd . "\"\n"], "recv_cmd_fifo")
  return readfile("result_fifo")
endf


fu! s:Command_vimexec_silent(cmd)
  call writefile(["vimexecsilent \"" . a:cmd . "\"\n"], "recv_cmd_fifo")
  call readfile("result_fifo") " for synchro
endf


fu! s:Info_target()
  call s:Select_buffer_code()
  let data = s:Command("viminfotarget")
  setlocal modifiable
  exec "silent file [CODE]\\ " . substitute(data[0], " ", "\\ ", "g")
  call append(0, "GDBinVim by Joel  http://hippersoft.fr/projects/gdbinvim/")
  call append(1, "")
  call append(2, " t : start the program")
  call append(3, " s : step into")
  call append(4, " n : next instruction")
  call append(5, " c : continue")
  call append(6, " b : toggle breakpoint")
  call append(7, "")
  call append(8, " r : reload")
  call append(9, " d : disassemble at the address under the cursor")
  call append(10," h : back in the history (if d was used)")
  call append(11, " p : print value at the address under the cursor")
  call append(12, " x : hexdump at the address under the cursor")
  call append(13, " _c : clear hexdump display")
  call append(14, " k : print the stack at the address under the cursor")
  call append(15, "")
  call append(16, "_d, _x, _p, _k : same functionnality as above but here you can")
  call append(17, "  specify an address")
  setlocal nomodifiable
endf


fu! s:Current_state()
  call s:Print_stack("$sp")
  call s:Print_registers()
  if s:hexdump_addr != ""
    call s:Hexdump(s:hexdump_addr)
  endif
  call s:Disassemble("")
endf


fu! s:Current_state_addr(addr)
  call s:Print_stack("$sp")
  call s:Print_registers()
  call s:Disassemble(a:addr)
endf


fu! s:Print_registers()
  let dump = s:Command_vimget("context_register")
  call s:Select_buffer_registers()
  setlocal modifiable
  normal! ggdG
  call append(0, dump[1:])
  setlocal nomodifiable
endf


fu! s:Print_stack(addr)
  let dump = s:Command_vimget("telescope " . a:addr . " " . g:STACK_NB_LINES)
  call s:Select_buffer_stack()
  setlocal modifiable
  normal! ggdG
  call append(0, dump)
  normal! gg
  setlocal nomodifiable
endf


fu! s:Print_stack_addr(addr)
  if s:Is_addr(a:addr)
    call s:Print_stack(a:addr)
  endif
endf


fu! s:Hexdump(addr)
  if s:Is_addr(a:addr)
    let s:hexdump_addr = a:addr 
    call s:Select_buffer_hexdump()
    setlocal modifiable
    normal! ggdG
    let dump = s:Command_vimget("hexdump " . a:addr . " /" . g:HEXDUMP_NB_LINES)
    call append(0, dump)
    setlocal nomodifiable
    normal! gg
  endif
endf


fu! s:Update_current_line(next)
  call cursor(s:curr_line, 1)
  exec "normal! R  "
  
  let s:curr_line = a:next
  call cursor(s:curr_line, 1)

  normal! R=>
  normal! hh
endf


fu! s:Extract_disassembled_addr(data)
  for line in a:data
    let s:disassembled_addr += [str2nr(matchstr(line, "0x[0-9a-f]\\+"), 16)]
  endfor
endf


fu! s:Delete_first_lines(line)
  if a:line > s:KEEP_N_LINES_BEFORE
    let diff = a:line - s:KEEP_N_LINES_BEFORE
    let s:disassembled_addr = s:disassembled_addr[diff : ]
    let s:curr_line = s:curr_line - diff

    let pos = getcurpos()
    call cursor(s:START_LINE, 1)

    if diff == 1
      normal! dd
    else
      exec "normal! " . (diff-1) . "dj"
    endif

    call cursor(s:curr_line, 1)
  endif
endf


" return hex string
fu! s:Get_addr(line)
  return substitute(a:line, "^...\\(0x[0-9a-f]\\+\\).*", "\\1", "")
endf


fu! s:Set_breakpoints()
  for id in s:id_breakpoints
    exec "sign unplace " . id
  endfor

  let s:id_breakpoints = []

  let i = 0
  while i < len(s:breakpoints)
    let s:breakpoints[i] = str2nr(s:breakpoints[i], 10)
    let line = index(s:disassembled_addr, s:breakpoints[i])

    if line != -1
      exec "sign place " . (i+1) . " line=" . (line + s:START_LINE) . " name=break buffer=" . s:buffer_code
      call add(s:id_breakpoints, i+1)
    endif

    let i += 1
  endwhile
endf


fu! s:Is_addr(addr)
  let STRING = 1
  if type(a:addr) == STRING && match(a:addr, "0x[0-9a-f]\\+") == -1
    echo "\"" . a:addr . "\" is not an hex address"
    return 0
  endif
  return 1
endf


fu! s:Disassemble(start_addr)
  call s:Select_buffer_code()

  if a:start_addr == ""
    " will disassemble at $pc
    let dump = s:Command("vimdisassemble")
  else
    let dump = s:Command("vimdisassembleat " . a:start_addr)
  endif

  " the first line contains the breakpoints list
  let s:breakpoints = split(dump[0], " ")
  let dump = dump[1:]

  setlocal modifiable

  if len(dump) == 0
    call cursor(s:START_LINE, 1)
    normal! dG
    call append(1, "Program is not running")
    let s:disassembled_addr = []
    let s:curr_line = 0
    let s:curr_addr = ""    
    setlocal nomodifiable
    return
  endif

  let first_addr = str2nr(s:Get_addr(dump[0]), 16)

  " check if the first disassembled address is already printed
  let idx = index(s:disassembled_addr, first_addr)

  if idx == -1 || a:start_addr != ""
    " first display if the address is not in the list
    " here if start_addr != "" : 
    "    start_addr == first_addr

    call cursor(s:START_LINE, 1)
    normal! dG

    let s:curr_line = s:START_LINE

    if a:start_addr == ""
      let s:history_disasm = [first_addr]
    else
      let s:history_disasm += [a:start_addr]
    endif

    let s:disassembled_addr = []

    call append(s:START_LINE - 1, dump)
    call s:Extract_disassembled_addr(dump)

    " need to update the curr_line if the current line is on the screen
    " it can occurs with back disassemble history
    if s:curr_addr != ""
      let idx_curr = index(s:disassembled_addr, s:curr_addr)
      if idx_curr != -1
        let s:curr_line += idx_curr
      endif
    endif

    call cursor(s:curr_line, 1)

  elseif first_addr != s:curr_addr
    " second display, move to the current line
    " not call when we disassemble a specific address
    " append new disassembled lines
    " optimization to not reload everything

    let nb_lines = len(s:disassembled_addr)
    call s:Update_current_line(idx + s:START_LINE)
    call append(nb_lines + s:START_LINE - 1, dump[nb_lines - idx : ])
    call s:Extract_disassembled_addr(dump[nb_lines - idx : ])
    call s:Delete_first_lines(idx + 1)

    let first_disasm_addr = str2nr(s:Get_addr(getline(s:START_LINE)), 16)
    let s:history_disasm = [first_disasm_addr]
  endif

  if a:start_addr == ""
    let s:curr_addr = first_addr
  endif

  call s:Set_breakpoints()

  setlocal nomodifiable
endf


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"                    Exported functions                             "
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""


fu! Gdb_start()
  let s:curr_addr = ""
  let s:history_disasm = []
  call s:Command_vimexec_silent("start")
  call s:Current_state()
endf


fu! Gdb_step()
  call s:Command_vimexec_silent("si")
  call s:Current_state()
endf


fu! Gdb_next()
  call s:Command_vimexec_silent("ni")
  call s:Current_state()
endf


fu! Gdb_continue()
  echo "Press Control-c in the GDB console, for stopping the execution"
  call s:Command_vimexec_silent("continue")
  call s:Current_state()
endf


fu! Gdb_clear_hexdump()
  let s:hexdump_addr = ""
  call s:Select_buffer_hexdump()
  set modifiable
  normal! ggdG
  set nomodifiable
endf


fu! Gdb_reload()
  if len(s:history_disasm) == 0
    call s:Current_state()
  else
    let addr = s:history_disasm[0]
    let s:history_disasm = []
    let s:curr_line = 0
    let s:curr_addr = 0
    call s:Current_state_addr(addr)
  endif
endf


fu! Gdb_back_disassemble_history()
  if len(s:history_disasm) <= 1
    echo "No more address in history"
    return
  endif

  " the address will be re-added, so remove 2 items
  let addr = s:history_disasm[-2]
  let s:history_disasm = s:history_disasm[:-3]

  call s:Disassemble_addr(addr)
endf


fu! Gdb_toggle_breakpoints()
  let pos = getcurpos()
  let line = getline(".")
  setlocal modifiable

  let addr = s:Get_addr(line)
  let idx = index(s:breakpoints, str2nr(addr, 16))

  if idx == -1
    let id = len(s:id_breakpoints) + 1
    call add(s:id_breakpoints, id)
    call add(s:breakpoints, str2nr(addr, 16))
    exec "sign place " . id . " line=" . line(".") . " name=break buffer=" . s:buffer_code
    call s:Command_vimexec_silent("break *" . addr)
  else
    exec "sign unplace " . s:id_breakpoints[idx]
    call remove(s:id_breakpoints, idx)
    call remove(s:breakpoints, idx)
    call s:Command("vimdeletebreakpoint " . addr)
  endif

  setlocal nomodifiable
endf


fu! Gdb_save_breakpoints()
  call s:Command_vimexec_silent("save breakpoints .gdb_breakpoints")
  echo "Breakpoints to .gdb_breakpoints"
endf


fu! s:Check_started_disassemble_addr(addr)
  if s:plugin_started
    call s:Disassemble_addr(a:addr)
  endif
endf


fu! s:Check_started_print_value(value)
  if s:plugin_started
    call s:Print_value(a:value)
  endif
endf


fu! s:Check_started_hexdump(addr)
  if s:plugin_started
    call s:Hexdump(a:addr)
  endif
endf


fu! s:Check_started_print_stack_addr(addr)
  if s:plugin_started
    call s:Print_stack_addr(a:addr)
  endif
endf


command! Gdb call s:Start_plugin()
command! -nargs=1 GdbDisassemble call s:Check_started_disassemble_addr(<f-args>)
command! -nargs=1 GdbPrint call s:Check_started_print_value(<f-args>)
command! -nargs=1 GdbHexdump call s:Check_started_hexdump(<f-args>)
command! -nargs=1 GdbStack call s:Check_started_print_stack_addr(<f-args>)

