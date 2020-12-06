#=======================================================================
# Makefrag for instructions employed in CVA6
#-----------------------------------------------------------------------

include $(TESTS_DIR)/rv64ui/Makefrag
include $(TESTS_DIR)/rv64uc/Makefrag
include $(TESTS_DIR)/rv64um/Makefrag
include $(TESTS_DIR)/rv64ua/Makefrag
include $(TESTS_DIR)/rv64uf/Makefrag
include $(TESTS_DIR)/rv64ud/Makefrag
include $(TESTS_DIR)/rv64uv/Makefrag
include $(TESTS_DIR)/rv64si/Makefrag

rv64ui_ara_tests := $(addprefix rv64ui-ara-, $(rv64ui_sc_tests))
rv64um_ara_tests := $(addprefix rv64um-ara-, $(rv64um_sc_tests))
rv64ua_ara_tests := $(addprefix rv64ua-ara-, $(rv64ua_sc_tests))
rv64uc_ara_tests := $(addprefix rv64uc-ara-, $(rv64uc_sc_tests))
rv64uf_ara_tests := $(addprefix rv64uf-ara-, $(rv64uf_sc_tests))
rv64ud_ara_tests := $(addprefix rv64ud-ara-, $(rv64ud_sc_tests))
rv64uv_ara_tests := $(addprefix rv64uv-ara-, $(rv64uv_sc_tests))
rv64si_ara_tests := $(addprefix rv64si-ara-, $(rv64si_sc_tests))

cva6_tests := $(rv64ui_ara_tests) \
							$(rv64um_ara_tests) \
							$(rv64uc_ara_tests) \
							$(rv64uf_ara_tests) \
							$(rv64ud_ara_tests) \
							$(rv64si_ara_tests)

# Atomics are messy, since there is currently no memory region capable of handling them
#							$(rv64ua_ara_tests) \

ara_tests := $(rv64uv_ara_tests)
