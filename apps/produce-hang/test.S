# Auther: Yanghao Hua <huayanghao@gmail.com>

.section .text
.global test_hang
# a0: parallel computes
# a1: loops
test_hang:
	li a2, 0 # loop index
	li a7, 3 # random value
	vsetvli t0, a0, e16, m1, ta, ma
	bne t0, a0, size_error

core_loop:
	# doesn't matter what are the values
	# in the vector registers
	vadd.vv v31, v28, v24, v0.t
	srl t4, a2, a7
	mv t4, zero
	# slideup zero element means a copy
	vslideup.vx v30, v28, t4
	vadd.vv v16, v30, v27
core_loop_end:
	addi a2, a2, 1
	ble  a2, a1, core_loop

	li a0, 0
debug:
	ret

size_error:
	li a0, 1
	ret

test_end:
	j test_end
