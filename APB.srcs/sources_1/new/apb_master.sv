`timescale 1ns / 1ps
module apb_master #( 
    parameter int WIDTH = 32, 
    parameter int ADDR_WIDTH = 4 
)( 
    input  logic                  pclk, 
    input  logic                  preset_n, 
    output logic [ADDR_WIDTH-1:0] paddr, 
    output logic                  psel, 
    output logic                  penable, 
    output logic                  pwrite, 
    output logic [WIDTH-1:0]      pwdata, 
    input  logic [WIDTH-1:0]      prdata, 
    input  logic                  pready, 
    input  logic                  pslverr, 
    input  logic                  start,//needs to be a pulse 
    input  logic [ADDR_WIDTH-1:0] addr_in, 
    input  logic [WIDTH-1:0]      wdata_in, 
    input  logic                  write_in, 
    output logic [WIDTH-1:0]      rdata_out, 
    output logic                  err_out, 
    output logic                  done//note: seperate output from input and it will be easy to see what to add and how to manipualte 
);
//THE WHOLE POINT OF MASTER IS TO ASSERT PSEL AND PENABLE IN THEIR RESPECTIVE STATES 
typedef enum logic [1:0]{ 
    setup, 
    access, 
    idle 
} state_t; 
state_t state, next_state;
//captured transaction information
logic [ADDR_WIDTH-1:0] addr_reg;
logic [WIDTH-1:0]      wdata_reg;
logic                  write_reg;

assign done = (state == access) && pready;//transaction complete
always_ff @(posedge pclk or negedge preset_n) begin 
    if (!preset_n) begin 
        state     <= idle; 
        rdata_out <= '0; 
        err_out   <= 1'b0;
        addr_reg  <= '0;
        wdata_reg <= '0;
        write_reg <= 1'b0;
    end 
    else begin 
        state <= next_state;
        //capture the transaction when start is asserted
        if (state == idle && start) begin
            addr_reg  <= addr_in;
            wdata_reg <= wdata_in;
            write_reg <= write_in;
        end
        if (state == access && pready) begin 
            err_out <= pslverr;              // capture error status every completed transfer 
            if (!write_reg) 
                rdata_out <= prdata;         // only capture data on reads 
        end 
    end 
end 

always_comb begin//defining the next state sequence 
    next_state = state; // default//the next state only depends on the current state and any external signal 
    case (state) 
        idle:   next_state = start ? setup : idle;   // needs a 'start' input! 
        setup:  next_state = access; 
        access: next_state = pready ? idle : access; // stay in access until pready 
        default: next_state = idle; 
    endcase 
end 

//combinational logic for calculation 
always_comb begin 
    psel    = 1'b0; 
    penable = 1'b0; 
    paddr   = '0; 
    pwdata  = '0; 
    pwrite  = 1'b0; 
    case (state) 
        setup: begin 
            psel   = 1'b1; 
            paddr  = addr_reg; 
            pwdata = wdata_reg; 
            pwrite = write_reg; 
        end 
        access: begin 
            psel    = 1'b1; 
            penable = 1'b1; 
            paddr   = addr_reg; 
            pwdata  = wdata_reg; 
            pwrite  = write_reg; 
        end 
        default: ; // idle: all defaults above 
    endcase 
end 
endmodule