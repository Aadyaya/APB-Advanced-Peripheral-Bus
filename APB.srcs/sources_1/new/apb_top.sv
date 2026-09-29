`timescale 1ns / 1ps
module apb_top #(
    parameter int WIDTH = 32,
    parameter int ADDR_WIDTH = 4
)(
    input  logic                  pclk,
    input  logic                  preset_n,
    input  logic                  start,//needs to be a pulse 
    input  logic [ADDR_WIDTH-1:0] addr_in, 
    input  logic [WIDTH-1:0]      wdata_in, 
    input  logic                  write_in,  

    output logic [WIDTH-1:0]      rdata_out, 
    output logic                  err_out, 
    output logic                  done
    );
    logic   sel;
    logic   enable;
    logic [ADDR_WIDTH-1:0] paddr_bus;
    logic [WIDTH-1:0]      pwdata_bus;
    logic [WIDTH-1:0]      prdata_bus;
    logic                  pwrite_bus;
    logic                  pready_bus;
    logic                  pslverr_bus;
     apb_master #(.WIDTH(WIDTH),
     .ADDR_WIDTH(ADDR_WIDTH))
     p_master(
     .pclk (pclk),
     .preset_n(preset_n),
     .psel (sel),
     .paddr (paddr_bus),
     .penable (enable),
     .pwdata (pwdata_bus),
     .prdata (prdata_bus),
     .pwrite (pwrite_bus),
     .pready (pready_bus),
     .pslverr (pslverr_bus),
     .start (start),
     .addr_in (addr_in),
     .wdata_in (wdata_in),
     .write_in (write_in),
     .rdata_out (rdata_out),
     .err_out(err_out),
     .done(done)
     );
          apb_slave #(.WIDTH(WIDTH),
     .ADDR_WIDTH(ADDR_WIDTH))
     p_slave(
     .pclk (pclk),
     .preset_n(preset_n),
     .psel (sel),
     .paddr (paddr_bus),
     .penable (enable),
     .pwdata (pwdata_bus),
     .prdata (prdata_bus),
     .pwrite (pwrite_bus),
     .pready (pready_bus),
     .pslverr (pslverr_bus)
     );
endmodule
