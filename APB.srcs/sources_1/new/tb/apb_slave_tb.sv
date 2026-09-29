`timescale 1ns / 1ps
module apb_slave_tb
#(
    parameter int WIDTH = 32,
    parameter int ADDR_WIDTH = 4
);
    logic                  pclk;
    logic                  preset_n;
    logic [ADDR_WIDTH-1:0] paddr;
    logic                  psel;
    logic                  penable;
    logic                  pwrite;
    logic [WIDTH-1:0]      pwdata;
    logic [WIDTH-1:0]      prdata;
    logic                  pready;
    logic                  pslverr;
    // Pass/fail bookkeeping
    int pass_count = 0;
    int fail_count = 0;
    apb_slave #(
        .WIDTH(WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    )
    dut(
        .pclk     (pclk),
        .preset_n (preset_n),
        .psel     (psel),
        .paddr    (paddr),
        .penable  (penable),
        .pwdata   (pwdata),
        .prdata   (prdata),
        .pwrite   (pwrite),
        .pready   (pready),
        .pslverr  (pslverr)
    );
    initial
        pclk = 0;
    always
        #5 pclk = ~pclk;
    // WRITE task: now returns the sampled pslverr so the caller can check it
    task apb_write(
        input  [WIDTH-1:0]      data,
        input  [ADDR_WIDTH-1:0] addr,
        output                  err
    );
    begin
        // SETUP phase
        @(posedge pclk);
        paddr   <= addr;
        pwdata  <= data;
        pwrite  <= 1;
        psel    <= 1;
        penable <= 0;
        // ACCESS phase
        @(posedge pclk);
        penable <= 1;
        #1; // let psel && penable propagate through the slave's always_comb before sampling
        // Check transaction completion
        err = pslverr;
        if (pready && !pslverr) begin
            $display("Time = %t, Address = %h, Data = %h, WRITE PASS",
                     $time, addr, data);
        end
        else if (pslverr) begin
            $display("Time = %t, Address = %h, WRITE ERROR",
                     $time, addr);
        end
        else begin
            $display("Time = %t, Address = %h, WRITE NOT READY",
                     $time, addr);
        end
        // Return to IDLE
        @(posedge pclk);
        psel    <= 0;
        penable <= 0;
        pwrite  <= 0;
        paddr   <= '0;
        pwdata  <= '0;
    end
    endtask
// READ task: also returns sampled pslverr
    task apb_read(
        input  [ADDR_WIDTH-1:0] addr,
        output [WIDTH-1:0]      data,
        output                  err
    );
    begin
        // SETUP phase
        @(posedge pclk);
        paddr   <= addr;
        pwrite  <= 0;
        psel    <= 1;
        penable <= 0;
        // ACCESS phase
        @(posedge pclk);
        penable <= 1;
        #1; // let psel && penable propagate through the slave's always_comb before sampling
        // Check transaction completion
        err = pslverr;
        if (pready && !pslverr) begin
            data = prdata;
            $display("Time = %t, Address = %h, Data = %h, READ PASS",
                     $time, addr, data);
        end
        else if (pslverr) begin
            data = '0;
            $display("Time = %t, Address = %h, READ ERROR",
                     $time, addr);
        end
        else begin
            data = '0;
            $display("Time = %t, Address = %h, READ NOT READY",
                     $time, addr);
        end
        // Return to IDLE
        @(posedge pclk);
        psel    <= 0;
        penable <= 0;
        paddr   <= '0;
    end
    endtask
    // Simple scoreboard helper
    task check(input logic cond, input string label);
    begin
        if (cond) begin
            pass_count++;
            $display("PASS : %s", label);
        end
        else begin
            fail_count++;
            $display("FAIL : %s", label);
        end
    end
    endtask

    logic [WIDTH-1:0] read_data;
    logic              werr, rerr;

    initial begin
// Reset conditions for everything
        preset_n = 0;
        psel     = 0;
        penable  = 0;
        pwdata   = 0;
        paddr    = 0;
        pwrite   = 0;
        repeat(3) @(posedge pclk);
        preset_n = 1;
        repeat(2) @(posedge pclk);

        // WRITE and READ REG1 (0x4)
        apb_write(32'hAAAAAAAA, 4'h4, werr);
        apb_read(4'h4, read_data, rerr);
        check(!werr && !rerr && (read_data == 32'hAAAAAAAA), "REG1 write/read");


        // WRITE and READ REG0 (0x0)
        apb_write(32'h12345678, 4'h0, werr);
        apb_read(4'h0, read_data, rerr);
        check(!werr && !rerr && (read_data == 32'h12345678), "REG0 write/read");


        // WRITE and READ REG2 (0x8)
        apb_write(32'h09076767, 4'h8, werr);
        apb_read(4'h8, read_data, rerr);
        check(!werr && !rerr && (read_data == 32'h09076767), "REG2 write/read");


        // WRITE and READ invalid address (0x5)
        apb_write(32'hBABABABA, 4'h5, werr);
        check(werr, "Invalid address detected on WRITE");

        apb_read(4'h5, read_data, rerr);
        check(rerr, "Invalid address detected on READ");

        #40;
        $display("--------------------------------------------------");
        $display("TOTAL: %0d PASS, %0d FAIL", pass_count, fail_count);
        $display("--------------------------------------------------");
        $finish;

    end

endmodule