// 


`ifndef CORE_V_XIF_SVH_
`define CORE_V_XIF_SVH_

`define CORE_V_XIF_BASE(X_NUM_RS, X_ID_WIDTH, X_HARTID_WIDTH, X_DUALREAD, X_DUALWRITE)  \
    typedef logic [X_NUM_RS+X_DUALREAD-1:0] readregflags_t;                             \
  	typedef logic [X_DUALWRITE:0] writeregflags_t;                                      \
  	typedef logic [1:0] mode_t;                                                         \
  	typedef logic [X_ID_WIDTH-1:0] id_t;                                                \
  	typedef logic [X_HARTID_WIDTH-1:0] hartid_t;                                        \

`define CORE_V_XIF_COMPRESSED     \
    typedef struct packed {       \
    logic [15:0] instr;           \
    hartid_t hartid;              \
  } x_compressed_req_t;           \
                                  \
  typedef struct packed {         \
    riscv::instruction_t  instr;  \
    logic accept;                 \
  } x_compressed_resp_t;

`define CORE_V_XIF_ISSUE              \
  typedef struct packed {             \
    riscv::instruction_t instr;       \
    mode_t mode;                      \
    hartid_t hartid;                  \
    id_t id;                          \
  } x_issue_req_t;                    \
                                      \
  typedef struct packed {             \
    logic accept;                     \
    writeregflags_t writeback;        \
    readregflags_t register_read;     \
    logic is_vfp;                     \
  } x_issue_resp_t;

`define CORE_V_XIF_REGISTER(X_NUM_RS, X_RFR_WIDTH)  \
  typedef struct {                                  \
    hartid_t hartid;                                \
    id_t id;                                        \
    logic [X_RFR_WIDTH-1:0] rs[X_NUM_RS-1:0];       \
    readregflags_t rs_valid;                        \
  } x_register_t;

`define CORE_V_XIF_COMMIT   \
  typedef struct packed {   \
    hartid_t hartid;        \
    id_t id;                \
    logic commit_kill;      \
  } x_commit_t;

`define CORE_V_XIF_MEM(X_MEM_WIDTH)   \
  typedef struct packed {             \
    hartid_t hartid;                  \
    id_t id;                          \
    logic [31:0] addr;                \
    mode_t mode;                      \
    logic we;                         \
    logic [2:0] size;                 \
    logic [X_MEM_WIDTH/8-1:0] be;     \
    logic [1:0] attr;                 \
    logic [X_MEM_WIDTH  -1:0] wdata;  \
    logic last;                       \
    logic spec;                       \
  } x_mem_req_t;                      \
                                      \
  typedef struct packed {             \
    logic exc;                        \
    logic [5:0] exccode;              \
    logic dbg;                        \
  } x_mem_resp_t;                     \
                                      \
  typedef struct packed {             \
    hartid_t hartid;                  \
    id_t id;                          \
    logic [X_MEM_WIDTH-1:0] rdata;    \
    logic err;                        \
    logic dbg;                        \
  } x_mem_result_t;

`define CORE_V_XIF_RESULT(X_RFW_WIDTH)  \
  typedef struct packed {               \
    hartid_t hartid;                    \
    id_t id;                            \
    logic [X_RFW_WIDTH     -1:0] data;  \
    logic [4:0] rd;                     \
    writeregflags_t we;                 \
    logic exc;                          \
    logic [5:0] exccode;                \
    logic dbg;                          \
    logic err;                          \
  } x_result_t;

`define CORE_V_XIF_ACC            \
  typedef struct packed {         \
  	fpnew_pkg::roundmode_e frm;   \
    logic store_pending;          \
    logic acc_cons_en;            \
    logic inval_ready;            \
    riscv::instruction_t instr;   \
    logic flush;                  \
  } x_acc_req_t;                  \
                                  \
  typedef struct packed {         \
  	logic error;                  \
    logic store_pending;          \
    logic store_complete;         \
    logic load_complete;          \
    logic [4:0] fflags;           \
    logic fflags_valid;           \
    logic inval_valid;            \
    logic [63:0] inval_addr;      \
  } x_acc_resp_t;

`define CORE_V_XIF_T                        \
  typedef struct {                          \
  	logic             issue_valid;          \
    x_issue_req_t  	  issue_req;            \
    logic             register_valid;       \
    x_register_t   	  register;             \
    logic             commit_valid;         \
    x_commit_t     	  commit;               \
    logic             result_ready;         \
    x_acc_req_t 		  acc_req;              \
  }	x_req_t;                                \
                                            \
  typedef struct packed {                   \
    logic             issue_ready;          \
    x_issue_resp_t 	  issue_resp;           \
    logic             register_ready;       \
    logic             result_valid;         \
    x_result_t      	result;               \
    x_acc_resp_t 			acc_resp;             \
  } x_resp_t;

`endif