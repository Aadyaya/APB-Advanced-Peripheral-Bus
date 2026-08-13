`timescale 1ns / 1ps
module apb_slave #(
    parameter int WIDTH = 32,
    parameter int ADDR_WIDTH = 4
)(
    input  logic                  pclk,
    input  logic                  preset_n,
    input  logic [ADDR_WIDTH-1:0] paddr,
    input  logic                  psel,
    input  logic                  penable,
    input  logic                  pwrite,
    input  logic [WIDTH-1:0]      pwdata,
    output logic [WIDTH-1:0]      prdata,
    output logic                  pready,
    output logic                  pslverr
);
logic [WIDTH-1:0] ctrl_reg;
logic [WIDTH-1:0] status_reg;
logic [WIDTH-1:0] config_reg;
logic [WIDTH-1:0] data_reg;
// Register write logic
always_ff @(posedge pclk or negedge preset_n) begin
    if (!preset_n) begin
        ctrl_reg   <= '0;
        status_reg <= '0;
        data_reg   <= '0;
        config_reg <= '0;
    end
    else if (psel && penable && pwrite) begin
        case (paddr)
            4'h0: ctrl_reg   <= pwdata;
            4'h4: status_reg <= pwdata;
            4'h8: data_reg   <= pwdata;
            4'hC: config_reg <= pwdata;
            default: ;
        endcase
    end
end

always_comb begin
    prdata  = '0;
    pready  = 1'b0;
    pslverr = 1'b0;
    if (psel && penable) begin
        pready = 1'b1;
        if (!pwrite) begin
            case (paddr)
                4'h0: prdata = ctrl_reg;
                4'h4: prdata = status_reg;
                4'h8: prdata = data_reg;
                4'hC: prdata = config_reg;

                default: begin
                    prdata  = '0;
                    pslverr = 1'b1;
                end
            endcase
        end

        // Write with invalid address
        else begin
            case (paddr)
                4'h0,
                4'h4,
                4'h8,
                4'hC: pslverr = 1'b0;

                default: pslverr = 1'b1;
            endcase
        end
    end
end

endmodule