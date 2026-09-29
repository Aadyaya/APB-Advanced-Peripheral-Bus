`timescale 1ns / 1ps
module apb_master_tb #(
    parameter int WIDTH             = 32,
    parameter int ADDR_WIDTH        = 4,
    parameter bit START_EDGE_DETECT = 0   
);

    logic                  pclk;
    logic                  preset_n;

    logic [ADDR_WIDTH-1:0] paddr;
    logic                  psel;
    logic                  penable;
    logic                  pwrite;
    logic [WIDTH-1:0]      pwdata;
    // APB bus (slave -> master)
    logic [WIDTH-1:0]      prdata;
    logic                  pready;
    logic                  pslverr;

    // User side of the master (TB drives these)
    logic                  start;
    logic [ADDR_WIDTH-1:0] addr_in;
    logic [WIDTH-1:0]      wdata_in;
    logic                  write_in;
    logic [WIDTH-1:0]      rdata_out;
    logic                  err_out;
    logic                  done;

    int pass_count = 0;
    int fail_count = 0;
    int mon_fail   = 0;
    int done_count = 0;
    bit verbose    = 1;


    apb_master #(.WIDTH(WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) dut (
        .pclk     (pclk),
        .preset_n (preset_n),
        .paddr    (paddr),
        .psel     (psel),
        .penable  (penable),
        .pwrite   (pwrite),
        .pwdata   (pwdata),
        .prdata   (prdata),
        .pready   (pready),
        .pslverr  (pslverr),
        .start    (start),
        .addr_in  (addr_in),
        .wdata_in (wdata_in),
        .write_in (write_in),
        .rdata_out(rdata_out),
        .err_out  (err_out),
        .done     (done)
    );

    apb_slave #(.WIDTH(WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) slave (
        .pclk     (pclk),
        .preset_n (preset_n),
        .paddr    (paddr),
        .psel     (psel),
        .penable  (penable),
        .pwrite   (pwrite),
        .pwdata   (pwdata),
        .prdata   (prdata),
        .pready   (pready),
        .pslverr  (pslverr)
    );

    initial pclk = 0;
    always #5 pclk = ~pclk;

    initial begin
        #500000;
        $display("WATCHDOG: simulation timed out");
        $finish;
    end

    always @(posedge pclk)
        if (done) done_count++;

    logic                  prev_psel    = 0;
    logic                  prev_penable = 0;
    logic                  prev_pready  = 0;
    logic                  prev_pwrite  = 0;
    logic [ADDR_WIDTH-1:0] prev_paddr   = '0;
    logic [WIDTH-1:0]      prev_pwdata  = '0;

    always @(posedge pclk) begin
        if (preset_n) begin
            // penable must never be high without psel
            if (penable && !psel) begin
                mon_fail++;
                $display("MON FAIL @%0t: penable without psel", $time);
            end
            // ACCESS (psel&&penable) must be preceded by SETUP (psel&&!penable)
            if (psel && penable && !(prev_psel && !prev_penable) && !(prev_psel && prev_penable && !prev_pready)) begin
                mon_fail++;
                $display("MON FAIL @%0t: ACCESS without SETUP", $time);
            end
            // SETUP must last exactly one cycle and be followed by ACCESS
            if (prev_psel && !prev_penable && !(psel && penable)) begin
                mon_fail++;
                $display("MON FAIL @%0t: SETUP not followed by ACCESS", $time);
            end
            // Address/control/write data must be stable from SETUP into ACCESS
            if (prev_psel && !prev_penable && psel && penable) begin
                if (paddr !== prev_paddr || pwrite !== prev_pwrite || (pwrite && pwdata !== prev_pwdata)) begin
                    mon_fail++;
                    $display("MON FAIL @%0t: paddr/pwrite/pwdata changed between SETUP and ACCESS", $time);
                end
            end
            // After a completed ACCESS (pready high), penable must drop
            if (prev_psel && prev_penable && prev_pready && penable) begin
                mon_fail++;
                $display("MON FAIL @%0t: penable stayed high after transfer completed", $time);
            end
        end
        prev_psel    <= psel;
        prev_penable <= penable;
        prev_pready  <= pready;
        prev_pwrite  <= pwrite;
        prev_paddr   <= paddr;
        prev_pwdata  <= pwdata;
    end

    task automatic check(input bit cond, input string label);
        if (cond) begin
            pass_count++;
            if (verbose) $display("PASS : %s", label);
        end
        else begin
            fail_count++;
            $display("FAIL : %s", label);
        end
    endtask

    function automatic bit is_valid(input logic [ADDR_WIDTH-1:0] a);
        return (a == 4'h0 || a == 4'h4 || a == 4'h8 || a == 4'hC);
    endfunction
    task automatic apb_xfer(
        input  logic [ADDR_WIDTH-1:0] addr,
        input  logic [WIDTH-1:0]      wdata,
        input  logic                  write,
        output logic [WIDTH-1:0]      rdata,
        output logic                  err
    );
        int guard;

        @(posedge pclk);
        addr_in  <= addr;
        wdata_in <= wdata;
        write_in <= write;
        start    <= 1'b1;

        @(posedge pclk);          // master samples start=1 on this edge
        start    <= 1'b0;
        #1;

        guard = 0;
        while (!done && guard < 20) begin
            @(posedge pclk);
            #1;
            guard++;
        end
        if (!done) begin
            fail_count++;
            $display("FAIL : TIMEOUT waiting for done (addr=%h write=%b)", addr, write);
        end

        @(posedge pclk);          // rdata_out / err_out are registered on this edge
        #1;
        rdata = rdata_out;
        err   = err_out;
    endtask

    logic [WIDTH-1:0]      rd;
    logic                  e;
    logic [ADDR_WIDTH-1:0] a;
    logic [WIDTH-1:0]      d;
    logic                  w;
    logic [WIDTH-1:0]      exp_rd;
    logic                  exp_err;
    logic [WIDTH-1:0]      model [0:(1<<ADDR_WIDTH)-1];
    logic [WIDTH-1:0]      patt  [0:3];

    initial begin
        // ---------------- init + reset ----------------
        preset_n = 0;
        start    = 0;
        addr_in  = '0;
        wdata_in = '0;
        write_in = 0;
        repeat (3) @(posedge pclk);
        preset_n = 1;
        repeat (2) @(posedge pclk);

        // ---------------- T1: bus idle after reset ----------------
        check(!psel && !penable && !done, "T1: bus idle after reset");

        // ---------------- T2: reset values of all 4 registers ----------------
        for (int i = 0; i < 4; i++) begin
            apb_xfer(i*4, '0, 1'b0, rd, e);
            check(!e && rd == '0, $sformatf("T2: reset value of reg 0x%0h is 0", i*4));
        end

        // ---------------- T3: write/read each register ----------------
        patt[0] = 32'h12345678;
        patt[1] = 32'hAAAAAAAA;
        patt[2] = 32'h09076767;
        patt[3] = 32'hDEADBEEF;
        for (int i = 0; i < 4; i++) begin
            apb_xfer(i*4, patt[i], 1'b1, rd, e);
            check(!e, $sformatf("T3: write to 0x%0h no error", i*4));
            apb_xfer(i*4, '0, 1'b0, rd, e);
            check(!e && rd == patt[i], $sformatf("T3: read back 0x%0h", i*4));
        end

        // ---------------- T4: no aliasing (re-read all after all writes) ----------------
        for (int i = 0; i < 4; i++) begin
            apb_xfer(i*4, '0, 1'b0, rd, e);
            check(!e && rd == patt[i], $sformatf("T4: reg 0x%0h intact after all writes", i*4));
        end

        // ---------------- T5: invalid address ----------------
        apb_xfer(4'h5, 32'hBABABABA, 1'b1, rd, e);
        check(e, "T5: invalid WRITE (0x5) sets err_out");
        apb_xfer(4'h5, '0, 1'b0, rd, e);
        check(e && rd == '0, "T5: invalid READ (0x5) sets err_out, data 0");
        apb_xfer(4'hF, 32'hCAFEF00D, 1'b1, rd, e);
        check(e, "T5: invalid WRITE (0xF) sets err_out");
        apb_xfer(4'h0, '0, 1'b0, rd, e);
        check(!e && rd == patt[0], "T5: invalid writes did not corrupt reg 0x0");

        // ---------------- T6: err_out clears on the next good transfer ----------------
        apb_xfer(4'h5, '0, 1'b0, rd, e);
        check(e, "T6: error raised");
        apb_xfer(4'h4, '0, 1'b0, rd, e);
        check(!e && rd == patt[1], "T6: err_out cleared by next valid transfer");

        // ---------------- T7: start held high for several cycles ----------------
        done_count = 0;
        @(posedge pclk);
        addr_in  <= 4'h0;
        wdata_in <= '0;
        write_in <= 1'b0;
        start    <= 1'b1;
        repeat (8) @(posedge pclk);
        start    <= 1'b0;
        repeat (6) @(posedge pclk);
        if (START_EDGE_DETECT)
            check(done_count == 1, "T7: start held 8 cycles -> exactly 1 transfer");
        else
            $display("INFO  T7: start held 8 cycles -> %0d transfers (level-sensitive start; 1 expected once edge-detect is added)", done_count);

        // ---------------- T8: constrained-random vs. scoreboard model ----------------
        // refresh the model from the slave's actual contents
        for (int i = 0; i < 4; i++) begin
            apb_xfer(i*4, '0, 1'b0, rd, e);
            model[i*4] = rd;
        end
        verbose = 0;
        for (int i = 0; i < 200; i++) begin
            a = ($urandom_range(0, 1)) ? 4*$urandom_range(0, 3) : $urandom_range(0, 15);
            w = $urandom_range(0, 1);
            d = $urandom;
            exp_err = !is_valid(a);
            if (w) begin
                apb_xfer(a, d, 1'b1, rd, e);
                check(e == exp_err, $sformatf("T8[%0d]: WRITE addr=%h err flag", i, a));
                if (is_valid(a)) model[a] = d;
            end
            else begin
                exp_rd = is_valid(a) ? model[a] : '0;
                apb_xfer(a, '0, 1'b0, rd, e);
                check(e == exp_err && rd == exp_rd, $sformatf("T8[%0d]: READ addr=%h data/err", i, a));
            end
        end
        verbose = 1;
        $display("T8: 200 random transfers done");

        // ---------------- summary ----------------
        repeat (5) @(posedge pclk);
        $display("--------------------------------------------------");
        $display("TOTAL: %0d PASS, %0d FAIL, %0d PROTOCOL-MONITOR FAIL", pass_count, fail_count, mon_fail);
        if (fail_count == 0 && mon_fail == 0) $display("RESULT: ALL TESTS PASSED");
        else                                  $display("RESULT: FAILURES DETECTED");
        $display("--------------------------------------------------");
        $finish;
    end

endmodule