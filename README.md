GDBinVim
========

Copyright (C) 2014  Joel

http://hippersoft.fr/projects/gdbinvim/

GDBinVim is an interface for GDB inside vim. It embeds a patched PEDA
(Python Exploit Development Assistance for GDB) with special commands
to communicate with Vim.

You can control the execution of the program directly in Vim (instruction step
by step, breakpoints, ...). At each state, registers and stack are printed.
You can also "hexdump" an address.

Every patchs/forks are welcome !


## Screenshot
![start](http://hippersoft.fr/projects/gdbinvim/screenshot.jpg)

## Requirements
* python 2.7
* GDB
* Vim

## Installation

    cp gdbin.vim ~/.vim/plugins

## Run

You only have to run gdb.py like if it was GDB :
    
    cd yourproject/
    alias gdb="path/to/gdbinvim/gdb.py"
    gdb --args yourprog

## Shortcuts (Vim side)

Open a new Vim session in the same directory where you launch gdb, and enter
`:Gdb`, or put Gdb in the command line :

    cd yourproject/
    vim -c Gdb

* `t` : start the program
* `s` : step into
* `n` : next instruction
* `c` : continue
* `r` : reload
* `b` : toggle breakpoint on cursor line (represented by a red square on the left)
* `h` : back into the history of disassembled (when you have pressed d)
* `d` : disassemble at the address under the cursor
* `p` : print the value at the address under the cursor
* `x` : hexdump at the address under the cursor
* `k` : print the stack at the address under the cursor
* `_d` : `:GdbDisassemble <ADDR>` disassemble at the specified address
* `_p` : `:GdbPrint <ADDR>` print the value at the specified address
* `_x` : `:GdbHexdump <ADDR>` hexdump at the specified address
* `_k` : `:GdbStack <ADDR>` print the stack at the specified address
* `_b` : save breakpoints to .gdb_breakpoints, you can restore them with
`gdb --command=.gdb_breakpoints --args ...`

