#!/bin/python2.7
#
# GDBinVim : interface for GDB inside Vim
# Copyright (C) 2014    Joel
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.    See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.    If not, see <http://www.gnu.org/licenses/>.
#

import os
import sys
import binascii
import re
import time
import signal
import errno
from threading import Thread, Lock
from readline import ReadLine, yellow

#
#                                         INPUT COMMAND LINE
#                                                |
#                                                |
#                                                V
#          _______     send commands to      _________
#         |       |    recv_command_fifo    |         |
#         |  VIM  | ----------------------> | WRAPPER |
#         |_______|                         |_________|
#             ^                                  |
#             |                                  |
#    if from vim write to                        |
#         result_fifo                            |
#             |            _______               | exec_command
#             +---------- |       |              |
#                         |  GDB  | <------------+
#             +---------- |_______|
#  else print |
#   result    |
#             V
#           STDOUT
#

def fork_gdb():
    peda = os.path.dirname(__file__) + "/peda/peda.py"
    (pid, fd) = os.forkpty()
    if pid == 0:
        os.execv("/usr/bin/gdb", [
            "/usr/bin/gdb", "-q", 
            "--command=" + peda
            ] + sys.argv[1:])
    return (pid, fd)


def read_until_prompt(fd, return_buffer=False, print_new_line=False):
    # the first line is not printed
    # it corresponds to the name of the command entered (or the prompt)
    # endline is \n ONLY

    prompt = yellow("gdb-peda$ ")
    idx = 0
    buf = ""
    line = ""
    first = True
    something_is_printed = False

    while 1:
        try:
            c = os.read(fd, 1)
        except Exception as e:
            print "read until except"
            continue

        if c == "\r":
            continue

        line += c

        if c == prompt[idx]:
            idx += 1
            if idx == len(prompt):
                break
        else:
            idx = 0
            if c == "\n":
                if not first:
                    if return_buffer:
                        buf += line
                    else:
                        if print_new_line and not something_is_printed:
                            rl.tty_restore()
                            os.write(1, "\n")
                        os.write(1, line)
                        something_is_printed = True
                line = ""
                first = False

    if return_buffer:
        return buf

    if print_new_line and something_is_printed:
        rl.new_prompt()
        rl.tty_set_raw()


def reader_fifo():
    while 1:
        fdr = open("recv_cmd_fifo", "r")
        try:
            mutex.acquire()

            cmd = ""
            while 1:
                c = fdr.read(1)
                if c == "\x00":
                    continue
                cmd += c
                if c == "\n":
                    break

            if cmd == "__exit__\n":
                return

            fdr.close()
            os.write(fd_gdb, cmd)
            read_until_prompt(fd_gdb, print_new_line=True)
        finally:
            mutex.release()


def complete(text):
    res = []
    mutex.acquire()
    try:
        os.write(fd_gdb, "complete " + text + "\n")
        res = read_until_prompt(fd_gdb, return_buffer=True).split("\n")
    finally:
        mutex.release()
    # last line is empty, the last char of the buffer is \n
    return res[:-1]


def exec_command(cmd):
    mutex.acquire()
    try:
        os.write(fd_gdb, cmd + "\n")
        if cmd in ["quit", "q"]:
            return
        read_until_prompt(fd_gdb)
    finally:
        mutex.release()
 

def signal_handler(signum, frame):
    send_control_c()


def send_control_c():
    os.write(fd_gdb, "\x15\x03\x15")


#####################################################################


try:
    os.remove("recv_cmd_fifo")
except:
    pass

try:
    os.remove("result_fifo")
except:
    pass

try:
    os.mkfifo("recv_cmd_fifo") # vim and console send commands here
    os.mkfifo("result_fifo") # gdb redirects result here
except:
    print "error: while creating fifos"
    sys.exit(0)


(pid_gdb, fd_gdb) = fork_gdb()

signal.signal(signal.SIGINT, signal_handler)

rl = ReadLine(exec_command, complete, send_control_c)
rl.restore_history()
read_until_prompt(fd_gdb)

mutex = Lock()
t = Thread(target = reader_fifo)
t.start()

exec_command("set history save off")

rl.loop()

# send quit to the thread reader_fifo
fdw = open("recv_cmd_fifo", "w")
fdw.write("__exit__\n")
fdw.close()

exec_command("quit")
os.wait()
os.remove("recv_cmd_fifo")
os.remove("result_fifo")

rl.save_history()

