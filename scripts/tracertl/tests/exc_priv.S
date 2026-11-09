/*
 * Privilege transitions: M -> S (mret), S -> M -> S (ecall), S -> U (sret),
 * U-mode ecall and illegal CSR access delegated to S through medeleg, and a
 * final U-mode ebreak that is not delegated and traps to M.
 */
#include "common.h"

TEST_BEGIN
  .option norvc
  la t0, m_handler
  csrw mtvec, t0
  la t0, s_handler
  csrw stvec, t0
  li t0, (1 << CAUSE_ECALL_U) | (1 << CAUSE_ILLEGAL)
  csrw medeleg, t0
  csrw satp, zero
  li s0, 0                      /* traps handled so far */

  /* M -> S */
  li t0, MSTATUS_MPP
  csrc mstatus, t0
  li t0, MSTATUS_MPP_S
  csrs mstatus, t0
  la t0, s_entry
  csrw mepc, t0
  mret

s_entry:
  ecall                         /* S -> M -> S */
  li t0, 1
  bne s0, t0, fail_1

  /* S -> U */
  li t0, MSTATUS_SPP
  csrc sstatus, t0
  la t0, u_entry
  csrw sepc, t0
  sret

u_entry:
  ecall                         /* delegated to S */
  csrr t0, mstatus              /* illegal in U, delegated to S */
  li t0, 3
  bne s0, t0, fail_2
  ebreak                        /* not delegated: U -> M */
  j fail_3

  .align 2
s_handler:
  addi s0, s0, 1
  csrr t0, scause
  li t1, CAUSE_ECALL_U
  beq t0, t1, 1f
  li t1, CAUSE_ILLEGAL
  beq t0, t1, 1f
  j fail_4
1:
  csrr t0, sepc
  addi t0, t0, 4
  csrw sepc, t0
  sret

  .align 2
m_handler:
  addi s0, s0, 1
  csrr t0, mcause
  li t1, CAUSE_ECALL_S
  beq t0, t1, 1f
  li t1, CAUSE_BREAKPOINT
  bne t0, t1, fail_5
  /* the ebreak came from U-mode */
  csrr t0, mstatus
  li t1, MSTATUS_MPP
  and t0, t0, t1
  bnez t0, fail_6
  li t0, 4
  bne s0, t0, fail_7
  TEST_PASS
1:
  csrr t0, mepc
  addi t0, t0, 4
  csrw mepc, t0
  mret

fail_1: TEST_FAIL(1)
fail_2: TEST_FAIL(2)
fail_3: TEST_FAIL(3)
fail_4: TEST_FAIL(4)
fail_5: TEST_FAIL(5)
fail_6: TEST_FAIL(6)
fail_7: TEST_FAIL(7)

TEST_END
