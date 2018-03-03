@ okami.s - the beginnings of a project
@ Copyright (C) 2018 Wolfgang Jaehrling
@
@ ISC License
@
@ Permission to use, copy, modify, and/or distribute this software for any
@ purpose with or without fee is hereby granted, provided that the above
@ copyright notice and this permission notice appear in all copies.
@ 
@ THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
@ WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
@ MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
@ ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
@ WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
@ ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
@ OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

@ registers:
@ r0    - tos
@ r1-r7 - scratch
@ r8-r9 - ??
@ r10   - ip
@ r11   - trs
@ r12   - rsp, full+downward
@ r13   - sp, full+downward
@ r14   - ARM lr
@ r15   - ARM ip

.equ syscallid_exit, 1
.equ syscallid_read, 3
.equ syscallid_write, 4
.equ fd_stdin, 0
.equ fd_stdout, 1
.equ ioctl_TCGETS, 0x5401

.equ io_bufsize, 4096

.bss
  return_stack:
    .space 120  @ 30 items deep
  return_stack_bottom:
    .space 8   @ for safety; TODO: should this be `quit` maybe?

  input_buffer:
    .space io_bufsize
  input_pos:
    .space 4
  input_end:
    .space 4

  output_buffer:
    .space io_bufsize
  output_buffer_end:
    @ here goes nothing
.data
  output_pos:
    .word output_buffer

  name_dup:
    .word 1
    .asciz "dup"
  name_drop:
    .word 2
    .ascii "drop"
    .word 0
  name_lit:
    .word 1
    .asciz "lit"
  name_syscall1:
    .word 3
    .ascii "syscall1"
    .word 0
  name_emit:
    .word 2
    .ascii "emit"
    .word 0

  basic_dictionary:
  dup:
    .word 0, name_dup, code_dup
  drop:
    .word . - 12, name_drop, code_drop
  lit:
    .word . - 12, name_lit, code_lit
  syscall1:
    .word . - 12, name_syscall1, code_syscall1
  emit:
    .word . - 12, name_emit, code_emit

  test_code:
    .word 0, lit+8, 66, dup+8, emit+8, lit+8, 1, syscall1+8

.text
  dodoes:
    str r0, [sp, #-4]!
    @ `next` leaves the CFA in r7
    @ we need to push CFA+8
    @ and setup IP for docol
    @ then we maybe can fall through to dodoes
  docol:
    @ push ip on rs:
    str r11, [r12, #-4]!
    mov r11, r10
    @ set up new ip:
    add r10, r7, #4
    @ fall through to `next`
  next:
    ldr r7, [r10], #4  @ get CFA, keep it here for dodoes
    ldr r6, [r7]       @ get code field value
    bx r6

  code_dup:
    str r0, [sp, #-4]!
    b next

  code_drop:
    ldr r0, [sp, #4]!
    b next

  code_lit:
    str r0, [sp, #-4]!
    ldr r0, [r10], #4
    b next

  code_swap:
    mov r1, r0
    ldr r0, [sp]
    str r1, [sp]
    b next

  code_syscall1:
    mov r7, r0
    ldr r0, [sp, #4]!
    swi 0
    b next

  code_emit:
    bl putc
    b next

  @ expects char in r0
  putc:
    ldr r6, =output_pos
    ldr r5, [r6]
    strb r0, [r5], #1  @ store char
    str r5, [r6]       @ store new pos

    ldr r6, =output_buffer_end
    cmp r5, r6         @ end of buffer..
    cmpne r0, #10      @ ..or newline
    bxne lr
    @ fall through
  flush:
    mov r4, r0 @ backup tos

    mov r7, #syscallid_write
    mov r0, #fd_stdout
    ldr r1, =output_buffer
    ldr r5, =output_pos
    ldr r2, [r5]
    sub r2, r2, r1  @ len
    swi 0

    @ TODO: check result

    str r1, [r5] @ reset pos to start of buffer
    mov r0, r4 @ restore tos
    bx lr

  .global _start
  _start:

    ldr r12, =return_stack_bottom
    ldr r7, =test_code
    b docol

  .Lloop:
    bl getc
    cmp r0, #-1
    beq .Lend
    bl putc
    b .Lloop

  .Lend:
    bl flush
    mov r0, #0
    b sys_exit


  @ expects error code in r0
  sys_exit:
    mov r7, #syscallid_exit
    swi 0


  @ returns char in r0
  getc:
    ldr r5, =input_pos
    ldr r1, [r5]
    ldr r2, =input_end
    ldr r2, [r2]

    cmp r1, r2
    beq .Lfill_buffer

  .Lreturn_char:
    ldrb r0, [r1], #1
    str r1, [r5]
    bx lr

  .Lfill_buffer:
    mov r7, #syscallid_read
    mov r0, #fd_stdin
    ldr r1, =input_buffer
    mov r2, #io_bufsize
    swi #0

    mov r2, #0
    cmp r2, r0
    beq .Leof
    bgt .Lread_error

    ldr r6, =input_pos
    str r1, [r6]

    ldr r6, =input_end
    add r2, r1, r0
    str r2, [r6]
    b .Lreturn_char

  .Leof:
    mov r0, #-1
    bx lr

  .Lread_error:
    mov r0, #1
    b sys_exit
