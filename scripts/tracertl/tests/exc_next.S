/*
 * Exceptions whose trap target is the instruction right after the faulting
 * one, so the redirect pc equals the sequential pc. Also covers mret to the
 * next instruction, a compressed ebreak at a 2-mod-4 pc, a trap target that
 * jumps backwards and an exception on a taken-branch target.
 */
#include "common.h"

#define EXPECT_CAUSE(cause, code) \
  csrr t1, mcause;                \
  li t2, cause;                   \
  bne t1, t2, fail_##code

TEST_BEGIN
  .option norvc
  li s0, 8                      /* iterations */

loop:
  /* ecall -> next */
  la t0, 1f
  csrw mtvec, t0
  ecall
1:
  EXPECT_CAUSE(CAUSE_ECALL_M, 1)

  /* ebreak -> next */
  la t0, 2f
  csrw mtvec, t0
  ebreak
2:
  EXPECT_CAUSE(CAUSE_BREAKPOINT, 2)

  /* illegal instruction (write to read-only cycle) -> next */
  la t0, 3f
  csrw mtvec, t0
  .word 0xc0001073              /* csrw cycle, zero */
3:
  EXPECT_CAUSE(CAUSE_ILLEGAL, 3)

  /* c.ebreak at pc 4n+2, target 4n+4 */
  la t0, 4f
  csrw mtvec, t0
  .half 0x0001                  /* c.nop */
  .half 0x9002                  /* c.ebreak */
4:
  EXPECT_CAUSE(CAUSE_BREAKPOINT, 4)

  /* mret with mepc = next instruction, staying in M-mode */
  la t0, 5f
  csrw mepc, t0
  li t0, MSTATUS_MPP
  csrs mstatus, t0
  mret
5:

  /* trap target behind the faulting instruction: ecall re-enters the loop head */
  la t0, 6f
  csrw mtvec, t0
  li s1, 4
6:
  addi s1, s1, -1
  beqz s1, 7f
  ecall
7:

  /* exception on the target of a taken branch */
  la t0, 9f
  csrw mtvec, t0
  beqz zero, 8f
  j fail_8
8:
  ecall
9:
  EXPECT_CAUSE(CAUSE_ECALL_M, 9)

  /* two back-to-back faulting instructions, each trapping to the other's successor */
  la t0, 10f
  csrw mtvec, t0
  ebreak
10:
  la t0, 11f
  csrw mtvec, t0
  ecall
11:
  EXPECT_CAUSE(CAUSE_ECALL_M, 11)

  addi s0, s0, -1
  bnez s0, loop

  la t0, test_unexpected_trap
  csrw mtvec, t0
  TEST_PASS

fail_1: TEST_FAIL(1)
fail_2: TEST_FAIL(2)
fail_3: TEST_FAIL(3)
fail_4: TEST_FAIL(4)
fail_8: TEST_FAIL(8)
fail_9: TEST_FAIL(9)
fail_11: TEST_FAIL(11)

TEST_END
