/***************************************************************************************
* Bare-metal TraceRTL corner-case tests: shared definitions.
*
* The tests run from reset (0x80000000) in M-mode on NEMU, which records the
* TraceRTL trace. They end with the NEMU trap instruction: a0 = 0 is a good
* trap, anything else a bad one, so a trace is only kept when NEMU passes.
***************************************************************************************/

#ifndef TRACERTL_TEST_COMMON_H
#define TRACERTL_TEST_COMMON_H

#define MSTATUS_MIE      0x8
#define MSTATUS_MPIE     0x80
#define MSTATUS_SPP      0x100
#define MSTATUS_MPP      0x1800
#define MSTATUS_MPP_S    0x800
#define MSTATUS_FS       0x6000
#define MSTATUS_FS_INIT  0x2000

#define MIP_MSIP         0x8
#define MIP_MTIP         0x80

#define CAUSE_ILLEGAL    2
#define CAUSE_BREAKPOINT 3
#define CAUSE_ECALL_U    8
#define CAUSE_ECALL_S    9
#define CAUSE_ECALL_M    11
#define CAUSE_INTR_MSI   3
#define CAUSE_INTR_MTI   7

#define CLINT_MSIP       0x38000000
#define CLINT_MTIMECMP   0x38004000

/* NEMU trap: exit with a0 */
#define NEMU_TRAP        .word 0x0005006b

/* Reset entry: stack, a catch-all trap handler, and a PMP entry that lets
 * S/U-mode reach all memory. */
#define TEST_BEGIN                     \
  .section .text.init, "ax";           \
  .globl _start;                       \
_start:                                \
  la sp, _stack_top;                   \
  la t0, test_unexpected_trap;         \
  csrw mtvec, t0;                      \
  li t0, -1;                           \
  csrw pmpaddr0, t0;                   \
  li t0, 0x1f;                         \
  csrw pmpcfg0, t0;                    \
  csrw mie, zero;                      \
  csrw medeleg, zero;                  \
  csrw mideleg, zero

/* TraceRTL ends the run once the whole trace has been fed to the core, so
 * the nops keep the instructions under test far from the end of the trace:
 * they are committed (and checked) before the run stops. */
#define TEST_PASS                      \
  .rept 1024;                          \
  nop;                                 \
  .endr;                               \
  li a0, 0;                            \
  NEMU_TRAP;                           \
  j .

#define TEST_FAIL(code)                \
  li a0, code;                         \
  NEMU_TRAP;                           \
  j .

/* Default trap handler for traps a test does not expect. */
#define TEST_END                       \
  .align 2;                            \
test_unexpected_trap:                  \
  csrr a1, mcause;                     \
  csrr a2, mepc;                       \
  TEST_FAIL(0x7f)

#endif
