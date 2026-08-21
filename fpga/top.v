`define ENABLE_V9958
`define ENABLE_BIOS
`define ENABLE_SOUND //v9958, bios required
`define ENABLE_MAPPER //bios required
`define ENABLE_SCAN_LINES
`define ENABLE_SDCARD
`define ENABLE_CONFIG
`define ENABLE_WAIT //extra wait state for mreq+wr
//`define ENABLE_WAIT_ADAPTIVE //wait required
`define ENABLE_M1_WAIT //STANDALONE: 1 wait-state per M1 opcode fetch (the real-MSX brake). Comment out to disable.
//`define SWAP23
// ENABLE_WIFI is off on this fork. The ESP-01S UART pins (27/28) are the
// shield's DB9 Fire 1 and Down lines, so there is physically nothing for the
// WiFi logic to talk to -- but synthesis cannot prune it, because wifi_lite
// still drives the Z80 bus at I/O 0x06/0x07 and wifi_req still decodes the
// UNAPI ROM slot. Compiling it out frees that logic, the 27-bit esp_boot
// counter, and folds esp_boot_ok to a constant.
//
// This matters here: CLS sits at 88% and clock_54m closes or misses depending
// on how the placer lands. Reaching WiFi another way is a roadmap item.
//`define ENABLE_WIFI

module top
#(
    parameter SD_SLOT = 3
)(
    input wire ex_clk_27m,
    input wire s1,
    input wire s2,

    // --- STANDALONE MERGE: MSX bus ports removed; replaced by USB (BL616) + LED ---
    // The old external MSX bus signals (ex_bus_wait_n/int_n/reset_n/clk_3m6,
    // ex_bus_data, ex_msel, ex_bus_m1_n/rfsh_n/mreq_n/iorq_n/rd_n/wr_n,
    // ex_bus_data_reverse_n, ex_bus_mp) are now INTERNAL wires/tie-offs (see below).

    // interface to external FPGA companion - USB KEYBOARD and gamepads (BL616)
    inout wire [4:0] m0s,
    // SPI to on-board BL616 (FPGA Companion).
    // spi_dir is NOT brought out on this build: the MiSTeryShield20k routes its
    // DB9 fire-2 line to pin 75, which is where spi_dir used to sit. The shield
    // always supplies its own companion (RP2040) over m0s[], so the on-board
    // BL616 path is unusable here anyway.
    input  wire spi_sclk,
    input  wire spi_csn,
    input  wire spi_dat,
    output wire spi_irqn,

    // DB9 joystick on the MiSTeryShield20k (active low, switches to GND)
    // db9[0]=Fire1 db9[1]=Down db9[2]=Up db9[3]=Right db9[4]=Left db9[5]=Fire2
    input  wire [5:0] db9,

    // discrete status LEDs (active low)
    output wire [5:0] led,

    //hdmi out
    output wire [2:0] data_p,
    output wire [2:0] data_n,
    output wire clk_p,
    output wire clk_n,

    // flash
    output wire mspi_cs,
    output wire mspi_sclk,
    inout wire mspi_miso,
    inout wire mspi_mosi,

    // MicroSD
    output wire sd_sclk,
    inout wire sd_cmd,      // MOSI
    inout  wire sd_dat0,     // MISO
    output wire sd_dat1,     // 1
    output wire sd_dat2,     // 1
    output wire sd_dat3,     // 1

// ESP-01S UART ports removed: pins 27/28 are the shield's DB9 Fire1 and Down
// lines. uart_tx/uart_rx exist as internal wires further down so wifi_lite
// still elaborates; synthesis prunes it.

    //usb uart
    output wire usb_uart_tx,

    // Magic ports for SDRAM to be inferred
    output wire O_sdram_clk,
    output wire O_sdram_cke,
    output wire O_sdram_cs_n, // chip select
    output wire O_sdram_cas_n, // columns address select
    output wire O_sdram_ras_n, // row address select
    output wire O_sdram_wen_n, // write enable
    inout wire [31:0] IO_sdram_dq, // 32 bit bidirectional data bus
    output wire [10:0] O_sdram_addr, // 11 bit multiplexed address bus
    output wire [1:0] O_sdram_ba, // two banks
    output wire [3:0] O_sdram_dqm // 32/4

    //output wire SLTSL3

);

    // Pins 25/27/28 now carry the shield's DB9 (Up / Fire1 / Down), so the
    // WS2812 case LED and the ESP-01S UART have no pins on this build. They
    // stay as internal wires: the modules driving them still elaborate, and
    // synthesis prunes them. WiFi would need the companion route instead.
    // Settings the user changed in the OSD (sysctrl CMD 4). Declared here rather
    // than beside the companion instance because reset and volume are consumed
    // much earlier in the file. Wired through so far: reset, turbo, volume and
    // the DB9 port assignment. The rest still need merging with
    // config1_ff/config2_ff, which the S menu drives through I/O ports.
    wire [1:0] system_reset;
    wire       system_turbo;
    wire       system_turbo_boot;
    wire       system_scanlines;
    wire       system_wide_screen;
    wire       system_stereo;
    wire       system_second_scc;
    wire [2:0] system_volume;
    wire       system_pal;
    wire [1:0] system_keyboard_sel;
    wire       system_db9_port;
    wire [1:0] system_autofire;
    wire       system_save;

    // Settings that live only in the OSD (the S menu has no equivalent) and so
    // have no bit in config1/config2. They are held here rather than used
    // straight from sysctrl, because sysctrl is reset by PLL lock and knows
    // nothing about what was saved; these are seeded from flash at config_init
    // and then follow the OSD.
    reg [2:0] volume_ff   = 3'd4;   // full
    reg       db9_port_ff = 1'b0;   // MSX port 1

    // change detectors for the OSD settings above (see the config block)
    reg osd_scan_d   = 1'b0;
    reg osd_wide_d   = 1'b0;
    reg osd_stereo_d = 1'b0;
    reg osd_scc2_d   = 1'b0;

    wire ws2812_led;
`ifdef ENABLE_WIFI
    wire uart_tx;                  // driven by wifi_lite
    wire uart_rx = 1'b1;           // no pin: idle high
`else
    wire uart_tx = 1'b1;           // no WiFi logic to drive it; idle high
    wire uart_rx = 1'b1;
`endif


initial begin

end
    //`default_nettype none

    //assign SLTSL3 = bus_mreq_disable ^ bus_iorq_disable ^ xffh ^ xffl ^ mapper_read ^ exp_slotx_req_r ^ bios_req ^ subrom_req ^ vdp_csr_n;

    // ===== STANDALONE MERGE: internalized MSX bus signals =====
    // These used to be top-level ports driven/sensed by a real MSX board.
    // Now: data bus is internal, WAIT/INT tied inactive, RESET from button + PLL lock,
    // 3.58MHz CPU clock generated internally. (Ported verbatim from MSXnano/fpga/top.v.)
    wire [7:0] ex_bus_data;          // internal (no external bus); see assign below
    wire ex_bus_wait_n  = 1'b1;      // no external wait
    wire ex_bus_int_n   = 1'b1;      // INT comes from internal VDP only

    wire clock_locked;
    wire ex_bus_reset_n;
    assign ex_bus_reset_n = ~s1 && clock_locked;   // s1 button = reset (active high press)

    // 108 MHz / 30 = 3.6 MHz internal CPU clock (replaces ex_bus_clk_3m6 pin)
    wire ex_bus_clk_3m6;
    reg [4:0] div30_cnt;
    reg clk_3m6_internal;

    // dangling sinks for the (now internal) bus-control nets the old logic still drives
    wire [1:0] ex_msel;
    wire ex_bus_m1_n;
    wire ex_bus_rfsh_n;
    wire ex_bus_mreq_n;
    wire ex_bus_iorq_n;
    wire ex_bus_rd_n;
    wire ex_bus_wr_n;
    wire ex_bus_data_reverse_n;
    wire [7:0] ex_bus_mp;

    //clocks
    wire clk_108m;
    wire clk_108m_n;
    CLK_108P clk_main (
        .clkout(clk_108m), //output clkout
        .lock(clock_locked), //output lock
        .clkoutp(clk_108m_n), //output clkoutp
        .reset(0), //input reset
        .clkin(ex_clk_27m) //input clkin
    );

    wire clk_enable_27m;
    wire clk_enable_54m;
    reg [1:0] cnt_clk_enable_27m;
    always @ (posedge clk_108m) begin
        cnt_clk_enable_27m <= cnt_clk_enable_27m + 1;
    end
    assign clk_enable_27m = ( cnt_clk_enable_27m == 2'b00 ) ? 1: 0;
    assign clk_enable_54m = ( cnt_clk_enable_27m[0] == 1 ) ? 1: 0;

    wire clk_27m;
    Gowin_CLKDIV div4(
        .clkout(clk_27m), //output clkout
        .hclkin(clk_108m), //input hclkin
        .resetn(1) //input resetn
    );

    wire bus_clk_3m6;
    PINFILTER dn1(
        .clk(clk_54m),
        .reset_n(1),
        .din(ex_bus_clk_3m6),
        .dout(bus_clk_3m6)
    );

    reg bus_clk_3m6_27;
    reg bus_clk_3m6_27_0;
    reg bus_clk_3m6_27_1;
    reg bus_clk_3m6_27_2;
    reg bus_clk_3m6_27_3;
    reg bus_clk_3m6_27_4;
    reg bus_clk_3m6_27_5;
    reg bus_clk_3m6_27_6;

    always @ (posedge clk_27m) begin
        bus_clk_3m6_27_6 <= bus_clk_3m6;
        bus_clk_3m6_27_5 <= bus_clk_3m6_27_6;
        bus_clk_3m6_27_4 <= bus_clk_3m6_27_5;
        bus_clk_3m6_27_3 <= bus_clk_3m6_27_4;
        bus_clk_3m6_27_2 <= bus_clk_3m6_27_3;
        bus_clk_3m6_27_1 <= bus_clk_3m6_27_2;
        bus_clk_3m6_27_0 <= bus_clk_3m6_27_1;
        bus_clk_3m6_27 <= bus_clk_3m6_27_0;
    end

    wire clk_enable_3m6_27;
    wire clk_falling_3m6_27;
    reg bus_clk_3m6_prev_27;
    always @ (posedge clk_27m) begin
        bus_clk_3m6_prev_27 <= bus_clk_3m6_27;
    end
    assign clk_enable_3m6_27 = (bus_clk_3m6_prev_27 == 0 && bus_clk_3m6_27 == 1);
    assign clk_falling_3m6_27 = (bus_clk_3m6_prev_27 == 1 && bus_clk_3m6_27 == 0);

    wire clk_54m;
    Gowin_CLKDIV2 div2(
        .clkout(clk_54m), //output clkout
        .hclkin(clk_108m), //input hclkin
        .resetn(1) //input resetn
    );

    wire clk_enable_3m6_54;
    wire clk_falling_3m6_54;
    reg bus_clk_3m6_54;
    reg bus_clk_3m6_prev_54;
    always @ (posedge clk_54m) begin
        bus_clk_3m6_54 <= bus_clk_3m6;
        bus_clk_3m6_prev_54 <= bus_clk_3m6_54;
    end
    assign clk_enable_3m6_54 = (bus_clk_3m6_54 == 0 && bus_clk_3m6 == 1);
    assign clk_falling_3m6_54 = (bus_clk_3m6_54 == 1 && bus_clk_3m6 == 0);

    wire bus_wait_n;
    PINFILTER dn2(
        .clk(clk_54m),
        .reset_n(1),
        .din(ex_bus_wait_n),
        .dout(bus_wait_n)
    );

    wire bus_reset_n;
    PINFILTER dn3(
        .clk(clk_54m),
        .reset_n(1),
        // OSD reset (sysctrl CMD 4, id "R"): 1 = reset, 3 = cold boot, 0 = run.
        // Safe to use as a level now that fpga_companion is reset from PLL lock
        // rather than from this net -- sysctrl no longer clears the register that
        // is asserting the reset. Two earlier attempts with the companion still on
        // the core reset boot-looped the machine and then killed the picture
        // entirely; see docs/FINDINGS.md before changing this.
        .din(ex_bus_reset_n & ~config_reset & ~(|system_reset)),
        .dout(bus_reset_n)
    );

    // STANDALONE: generate the 3.58MHz CPU bus clock internally (was ex_bus_clk_3m6 pin).
    // 108 MHz / 30 = 3.6 MHz. (Ported verbatim from MSXnano/fpga/top.v.)
    always @(posedge clk_108m or negedge bus_reset_n) begin
        if (~bus_reset_n) begin
            div30_cnt <= 0;
            clk_3m6_internal <= 0;
        end else begin
            if (div30_cnt == 5'd14) begin
                clk_3m6_internal <= ~clk_3m6_internal;
                div30_cnt <= 0;
            end else begin
                div30_cnt <= div30_cnt + 1;
            end
        end
    end
    assign ex_bus_clk_3m6 = clk_3m6_internal;

    wire bus_int_n;
//    PINFILTER dn4(
//        .clk(clk_108m),
//        .reset_n(1),
//        .din(ex_bus_int_n),
//        .dout(bus_int_n)
//    );
    denoise dn4 (
		.data_in (ex_bus_int_n),
		.clock(clk_54m),
		.data_out (bus_int_n)
    );

    reg [7:0] bus_data;
    genvar i;
    generate
        for (i = 0; i <= 7; i++)
        begin: bus_din
            PINFILTER dn(
                .clk(clk_54m),
                .reset_n(1),
                .din(ex_bus_data[i]),
                .dout(bus_data[i])
            );
//            denoise2 dn (
//                .data_in (ex_bus_data[i]),
//                .clock(clk_108m),
//                .data_out (bus_data[i])
//            );
        end
    endgenerate

//    always @ (posedge clk_108m) begin
//        bus_data <= ex_bus_data;
//    end

    //startup logic
    reg reset1_n_ff;
    reg reset2_n_ff;
    reg reset3_n_ff;
    wire reset1_n;
    wire reset2_n;
    wire reset3_n;

    reg [20:0] counter_reset = 0;
    reg [1:0] rst_seq;
    reg rst_step;

    always @ (posedge clk_27m or negedge bus_reset_n) begin
        if (bus_reset_n == 0) begin
            rst_step <= 0;
            counter_reset <= 0;
        end
        else begin
            rst_step <= 0;
            if ( counter_reset <= 21'b100000000000000000000 ) 
                counter_reset <= counter_reset + 1;
            else begin
                rst_step <= 1;
                counter_reset <= 0;
            end
        end
    end

    always @ (posedge clk_27m or negedge bus_reset_n ) begin
        if (bus_reset_n == 0 ) begin
            rst_seq <= 2'b00;
            reset1_n_ff <= 0;
            reset2_n_ff <= 0;
            reset3_n_ff <= 0;
        end
        else begin
            case ( rst_seq )
                2'b00: 
                    if (rst_step == 1 ) begin
                        reset1_n_ff <= 1;
                        rst_seq <= 2'b01;
                    end
                2'b01: 
                    if (rst_step == 1) begin
                        reset2_n_ff <= 1;
                        rst_seq <= 2'b10;
                    end
                2'b10:
                    if (rst_step == 1) begin
                        reset3_n_ff <= 1;
                        rst_seq <= 2'b11;
                    end
            endcase
        end
    end
    assign reset1_n = reset1_n_ff;
    assign reset2_n = reset2_n_ff;
    assign reset3_n = reset3_n_ff;

    //bus demux
    reg [1:0] msel;
    reg [7:0] bus_mp;
    reg [4:0] mp_cnt;
    wire [15:0] bus_addr;
    assign ex_msel = msel;
    assign ex_bus_mp = bus_mp;

    localparam IDLE = 2'd0;
    localparam LATCH = 2'd1;
    localparam FINISH1 = 2'd3;
    localparam FINISH2 = 2'd2;
    localparam [3:0] TON = 4'd3;
    localparam [3:0] TP = 4'd1; //prefetch time
    reg [1:0] state_demux;
    reg [3:0] counter_demux;
    reg low_byte_demux;
    wire update_demux;
    assign bus_mp = ( low_byte_demux == 0 ) ? bus_addr[15:8] : bus_addr[7:0];
    always @ (posedge clk_108m) begin
        if (~bus_reset_n) begin
            state_demux <= LATCH;
            counter_demux <= 4'd0;
            low_byte_demux <= 0;
        end 
        else begin
            counter_demux = counter_demux + 4'd1;
            casex ({state_demux, counter_demux})
                {IDLE, 4'bxxxx}: begin
                    msel <= 2'b00;
                    counter_demux <= 4'd0;
                    low_byte_demux <= 0;
                    if (update_addr == 1 ) begin
                        state_demux <= LATCH;
                    end
                end
                {LATCH, 4'd1} : begin
                    msel[1] <= 1;
                end
                {LATCH, 4'd1 + TON} : begin
                    msel[1] <= 0;
                end
                {LATCH, 4'd1 + TON + TP} : begin
                    low_byte_demux <= 1;
                end
                {LATCH, 4'd1 + TON + TP + TP} : begin
                    msel[0] <= 1;
                end
                {LATCH, 4'd1 + TON + TP + TP + TON} : begin
                    msel[0] <= 0;
                    msel[1] <= 0;
                    state_demux <= FINISH1;
                end
                {FINISH1, 4'bxxxx}: begin
                    if (update_addr == 0 ) begin
                        state_demux <= IDLE;
                    end
                end
                {FINISH2, 4'bxxxx}: begin
                    if (update_addr == 0 ) begin
                        state_demux <= IDLE;
                    end
                end
            endcase
        end
    end




    //bus isolation
    wire bus_data_reverse;
    wire bus_m1_n;
    wire bus_mreq_n;
    wire bus_iorq_n;
    wire bus_rd_n;
    wire bus_wr_n;
    wire bus_rfsh_n;
    reg [7:0] cpu_din;
    wire [7:0] cpu_dout;
    wire bus_mreq_disable;
    wire bus_iorq_disable;
    wire bus_disable;
    assign ex_bus_m1_n = bus_m1_n;
    assign ex_bus_rfsh_n = bus_rfsh_n;
    assign ex_bus_data_reverse_n = ~ bus_data_reverse;
    //assign ex_bus_data_reverse = bus_data_reverse;
    //assign ex_bus_mreq_n = bus_mreq_n;
    //assign ex_bus_iorq_n = bus_iorq_n;
    //assign ex_bus_rd_n = bus_rd_n;
    //assign ex_bus_wr_n = bus_wr_n;

    assign bus_mreq_disable = 0;
    assign bus_iorq_disable = (
                                0
                        `ifdef ENABLE_V9958
                                || vdp_csr_n == 0 || vdp_csw_n == 0 
                        `endif 
                                ) ? 1 : 0;

    assign bus_disable = bus_mreq_disable | bus_iorq_disable;
//    assign ex_bus_data = ( bus_data_reverse == 1 && slot0_req_w == 0 ) ? cpu_dout : 
//                         ( slot0_req_w == 1 ) ? 8'hff :  8'hzz;
`ifndef SWAP23
    assign ex_bus_data =  ( bus_data_reverse == 1 ) ? cpu_dout : 8'hzz;
`else

    function [1:0] swap;
        input [1:0] entrada;
        begin
            case (entrada)
                2'b00: swap = 2'b00;
                2'b01: swap = 2'b01;
                2'b10: swap = 2'b11;
                2'b11: swap = 2'b10;
                default: swap = 2'b00; // Por seguridad
            endcase
        end
    endfunction

    wire [7:0] cpu_dout_swap;
    assign cpu_dout_swap = { swap(cpu_dout[7:6]), swap(cpu_dout[5:4]), swap(cpu_dout[3:2]), swap(cpu_dout[1:0]) };

    reg ppi_swap;
    always @ (posedge clk_27m) begin
        if (~bus_reset_n) begin
            ppi_swap <= 0;
        end
        else begin
            if (ppi_swap == 0) begin
                if (bus_data_reverse == 1  && ppi_req_w == 1) begin
                    ppi_swap <= 1;
                end
            end
            else begin
                if (bus_data_reverse == 0) begin
                    ppi_swap <= 0;
                end
            end
        end
    end

    assign ex_bus_data =  ( bus_data_reverse == 1  && ppi_swap == 0) ? cpu_dout :
                          ( bus_data_reverse == 1  && ppi_swap == 1) ? cpu_dout_swap : 8'hzz;
`endif

// ===== STANDALONE MERGE: USB joystick (PSG 0xA2/reg14) — ported from MSXnano/fpga/top.v =====
wire psg_req_r;
assign psg_req_r = (bus_addr[7:0] == 8'hA2 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_rd_n == 0) ? 1 : 0;

// USB joystick data wires (driven by fpga_companion instance below)
wire [7:0] joystick0;
wire [7:0] joystick1;

// Track which PSG register was last latched via I/O A0h
reg [3:0] psg_addr_latch;
always @(posedge clk_54m or negedge bus_reset_n) begin
    if (!bus_reset_n)
        psg_addr_latch <= 4'd0;
    else if (bus_addr[7:0] == 8'hA0 && bus_iorq_n == 0 && bus_wr_n == 0 && bus_m1_n == 1)
        psg_addr_latch <= cpu_dout[3:0];
end

// Track PSG reg 15 (Port B) bits [7:6] which select joystick port
// bit6=0 selects joy1, bit7=0 selects joy2 (active low)
reg [1:0] psg_reg15_joy_sel;
always @(posedge clk_54m or negedge bus_reset_n) begin
    if (!bus_reset_n)
        psg_reg15_joy_sel <= 2'b11;
    else if (bus_addr[7:0] == 8'hA1 && bus_iorq_n == 0 && bus_wr_n == 0 && bus_m1_n == 1
             && psg_addr_latch == 4'd15)
        psg_reg15_joy_sel <= cpu_dout[7:6];
end

// ===== AUTOFIRE (turbo) on the otherwise-unused joystick buttons 3 & 4 =====
// The FPGA-Companion joy byte uses bits 0-5 (dirs + A + B); bits 6/7 carry the
// extra pad buttons 3/4 (unused by the MSX 2-button joystick). While button 3
// is held it pulses TrigA, button 4 pulses TrigB, at ~10 Hz (50 ms ON / 50 ms
// OFF). Each phase must outlast one MSX PSG scan (~1 frame @50/60 Hz) so every
// press AND release is sampled; 50 ms = 2.5-3 frames is safe even on PAL.
// Ported from the goauld+RP2040 fork (there it lived in firmware; here, no
// RP2040 -> it lives in the FPGA on the PSG joystick-injection path).
//   54 MHz * 0.050 s = 2,700,000 cycles per half period.
//
// The OSD's "F" rate control is PARKED, not forgotten. Two attempts to make this
// rate selectable each cost clock_54m its margin: a 23-bit limit register plus a
// variable comparator (0b3f629: TNS -0.555 ns over 6 endpoints), and then a
// comparator-free free-running counter with the rates a power of two apart
// (aa52343), which came in UNDER the CLS target at 9028 and still made timing
// dramatically worse -- 50.7 MHz, -5.172 ns over 17 endpoints, with a second
// failing family appearing at the CPU/SDRAM boundary that was not there before.
// Resource count is not what governs this design; placement is. So this block is
// back to exactly what shipped in the last build that closed, and
// system_autofire is left unconnected.
reg        af_phase = 1'b0;
reg [21:0] af_cnt   = 22'd0;
always @(posedge clk_54m) begin
    if (af_cnt >= 22'd2700000) begin
        af_cnt   <= 22'd0;
        af_phase <= ~af_phase;
    end else begin
        af_cnt   <= af_cnt + 22'd1;
    end
end
// fire = manual press OR (autofire button held AND square-wave high). If the pad
// has no button 3/4 (bits 6/7 stay 0) this reduces to the original behaviour.
wire af_fa0 = joystick0[4] | (joystick0[6] & af_phase);   // joy0 TrigA: manual + btn3 turbo
wire af_fb0 = joystick0[5] | (joystick0[7] & af_phase);   // joy0 TrigB: manual + btn4 turbo
wire af_fa1 = joystick1[4] | (joystick1[6] & af_phase);   // joy1 TrigA
wire af_fb1 = joystick1[5] | (joystick1[7] & af_phase);   // joy1 TrigB

// Companion joy byte (active-high): bit0=Right, bit1=Left, bit2=Down, bit3=Up, bit4=A, bit5=B
// MSX PSG Port A (active-low):      bit0=Up,    bit1=Down,  bit2=Left, bit3=Right, bit4=TrigA, bit5=TrigB
// The DB9 stick on the MiSTeryShield20k is already active low (switch to GND,
// pin has PULL_MODE=UP), which is exactly what PSG Port A wants -- so it just
// gets AND-ed in: either the USB pad or the DB9 stick can pull a line low.
// Port 0 only; the shield has a single DB9 and port 1 stays USB-only.
// db9[] is NanoMig's js0[] on pins 27,28,25,26,29,30. Its decode is
//   Fire2=js0[5] Fire1=js0[0] Up=js0[2] Down=js0[1] Left=js0[4] Right=js0[3]
// (NanoMig top.sv: db9_joy0 = {!js0[5],!js0[0],!js0[2],!js0[1],!js0[4],!js0[3]}).
// Both sides are active low, so the DB9 just AND-s into the existing lines.
wire [7:0] joy0_msx = {2'b11, ~af_fb0 & db9[5],       // TrigB <- Fire2
                              ~af_fa0 & db9[0],       // TrigA <- Fire1
                              ~joystick0[0] & db9[3], // Right
                              ~joystick0[1] & db9[4], // Left
                              ~joystick0[2] & db9[1], // Down
                              ~joystick0[3] & db9[2]};// Up
wire [7:0] joy1_msx = {2'b11, ~af_fb1, ~af_fa1, ~joystick1[0], ~joystick1[1], ~joystick1[2], ~joystick1[3]};
// OSD "J": which MSX joystick port the shield's DB9 answers on. The DB9 is
// mixed into joy0_msx above; when port 2 is selected the two ports are simply
// swapped, so the stick appears on port 2 and the USB pad on port 1.
wire [7:0] port1_msx = db9_port_ff ? joy1_msx : joy0_msx;
wire [7:0] port2_msx = db9_port_ff ? joy0_msx : joy1_msx;

wire [7:0] psg_joy_data = (!psg_reg15_joy_sel[0]) ? port1_msx :
                          (!psg_reg15_joy_sel[1]) ? port2_msx :
                          8'hFF;

// ===== STANDALONE MERGE: USB keyboard (PPI port B 0xA9 read / port C 0xAA latch) =====
wire ppi_portb_req_r = (bus_addr[7:0] == 8'hA9 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_rd_n == 0) ? 1 : 0;
wire ppi_portc_req_w = (bus_addr[7:0] == 8'hAA && bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0);

wire [3:0] keyboard_addr;
reg [7:0] keyboard_data;
wire [1:12] function_keys;

reg [7:0] ppi_port_c = 8'h00;   // R4: ppi_port_c did not exist in base — created here
always @(posedge clk_54m or negedge bus_reset_n) begin
    if (!bus_reset_n)
        ppi_port_c <= 8'h00;
    else if (ppi_portc_req_w)
        ppi_port_c <= cpu_dout;
end
assign keyboard_addr = ppi_port_c[3:0];

    // v1.9: FPGA/bitstream version readable on I/O port 0x2F. The boot menu reads it and
    // warns if you flashed mismatched .fs/.bin (e.g. a v1.8 bitstream + a v1.7 BIOS pack).
    // Encoding 0x1X = version 1.X. Bump FPGA_VERSION each release together with the pack.
    localparam [7:0] FPGA_VERSION = 8'h19;
    wire ver_req_r = (bus_iorq_n == 1'b0 && bus_m1_n == 1'b1 && bus_rd_n == 1'b0 && bus_addr[7:0] == 8'h2F);
    // ---- cpu_din source groups ---------------------------------------------
    // The CPU read mux below was a single priority chain ~29 ternaries deep.
    // Every level is a mux in series, and cpu_din is the endpoint of two of the
    // paths that miss timing on clock_54m.
    //
    // Split into groups that resolve in parallel, then combined: depth becomes
    // (largest group) + (number of groups) rather than the total count.
    //
    // Priority is preserved EXACTLY -- order within each group is unchanged and
    // the groups are combined in their original order. Deliberately no
    // assumption is made about which decodes can be true at once. Merging the
    // nine ram_dout conditions into one test would be shorter still, but is
    // only correct if those decodes are provably mutually exclusive, and being
    // wrong there returns the wrong byte to the CPU.
    wire g1_hit = ver_req_r | psg_req_r | ppi_portb_req_r
`ifdef ENABLE_SOUND
                | psg2_req_r
`endif
`ifdef ENABLE_V9958
                | (vdp_csr_n == 1'b0)
`endif
                ;
    wire [7:0] g1_val =
                ( ver_req_r == 1 ) ? FPGA_VERSION :
                ( psg_req_r == 1 ) ? ((psg_addr_latch == 4'd14) ? psg_joy_data : 8'hFF) :
`ifdef ENABLE_SOUND
                ( psg2_req_r == 1 ) ? psg2_dout :
`endif
                ( ppi_portb_req_r == 1 ) ? keyboard_data :
`ifdef ENABLE_V9958
                ( vdp_csr_n == 0) ? vdp_dout :
`endif
                8'hFF;

    wire g2_hit = 1'b0
`ifdef ENABLE_MAPPER
                | mapper_read
`endif
`ifdef ENABLE_BIOS
                | exp_slot0_req_r | exp_slotx_req_r | bios_req | subrom_logo_req
`endif
                ;
    wire [7:0] g2_val =
`ifdef ENABLE_MAPPER
                ( mapper_read == 1) ? ram_dout :
`endif
`ifdef ENABLE_BIOS
                ( exp_slot0_req_r == 1) ? ~exp_slot0 :
                ( exp_slotx_req_r == 1) ? ~exp_slotx :
                ( bios_req | subrom_logo_req ) ? ram_dout :
`endif
                8'hFF;

    wire g3_hit = 1'b0
`ifdef ENABLE_SDCARD
                | sd_busreq_w | sram_busreq_w | megarom_req
`endif
`ifdef ENABLE_SOUND
                | megaram_req | scc_rd_r | scc2x_rd_r
`endif
                ;
    wire [7:0] g3_val =
`ifdef ENABLE_SDCARD
                ( sd_busreq_w == 1) ? sd_cd_w :
                ( sram_busreq_w == 1) ? sram_cd_w :
                ( megarom_req == 1) ? ram_dout :
`endif
`ifdef ENABLE_SOUND
                ( megaram_req == 1 ) ? ram_dout :
                ( scc_rd_r == 1 ) ? scc_dout :
                ( scc2x_rd_r == 1 ) ? scc2x_dout :
`endif
                8'hFF;

    wire g4_hit = kanji_driver_req | kanji_data_req_r
`ifdef ENABLE_CONFIG
                | config_req
`endif
                ;
    wire [7:0] g4_val =
`ifdef ENABLE_CONFIG
                ( config_req == 1 && pana_sel == 1 ) ? pana_dout :
                ( config_req == 1 && config_ok == 1) ? config_dout :
                ( config_req == 1 && config_ok == 0) ? swio_dout :
`endif
                ( kanji_driver_req | kanji_data_req_r ) ? ram_dout :
                8'hFF;

    wire g5_hit = rtc_req_r | ppi_req_r
`ifdef ENABLE_WIFI
                | wifi_req | logo_req | f2_req_r | uart_req
`endif
                ;
    wire [7:0] g5_val =
`ifdef ENABLE_WIFI
                ( wifi_req == 1 ) ? ram_dout :
                ( logo_req == 1 ) ? ram_dout :
                ( f2_req_r == 1 ) ? f2_port :
                ( uart_req == 1 ) ? uart_dout :
`endif
                ( rtc_req_r == 1 ) ? rtc_dout :
                ( ppi_req_r == 1 ) ? ppi_port_a :
                8'hFF;

    always @ (posedge clk_54m) begin
        cpu_din <= g1_hit ? g1_val :
                   g2_hit ? g2_val :
                   g3_hit ? g3_val :
                   g4_hit ? g4_val :
                   g5_hit ? g5_val :
                   8'hFF;   // STANDALONE: was bus_data (external MSX board). No bus -> FF.
    end


//    wire ex_bus_rd_n_test;
//    wire ex_bus_wr_n_test;
//    wire ex_bus_iorq_n_test;
//    wire ex_bus_mreq_n_test;
    reg ex_bus_rd_n_ff;
    reg ex_bus_wr_n_ff;
    reg ex_bus_iorq_n_ff;
    reg ex_bus_mreq_n_ff;
    localparam IDLE_ISO = 2'd0;
    localparam ACTIVE_ISO = 2'd1;
    localparam WAIT_ISO = 2'd2;
    reg [1:0] state_iso;
    reg [2:0] counter_iso;
    wire io_active;

    //assign ex_bus_rd_n = ( bus_rd_n | ex_bus_rd_n_ff | bus_disable);
    assign ex_bus_rd_n = bus_rd_n;
    //assign ex_bus_wr_n = ( bus_wr_n | ex_bus_wr_n_ff | bus_disable);
    assign ex_bus_wr_n = bus_wr_n;
    assign ex_bus_iorq_n = ( bus_iorq_n | bus_iorq_disable );
    assign ex_bus_mreq_n = ( bus_mreq_n | bus_mreq_disable );
    assign io_active = ( state_iso != IDLE_ISO ) ? 1 : 0;

    always @ ( posedge clk_108m ) begin
        if (~bus_reset_n) begin
            state_iso <= IDLE_ISO;
            ex_bus_rd_n_ff <= 1;
            ex_bus_wr_n_ff <= 1;
        end 
        else begin
            counter_iso = counter_iso + 3'd1;
            casex ({state_iso, counter_iso})
                {IDLE_ISO, 3'bxxx}: begin
                    ex_bus_rd_n_ff <= 1;
                    ex_bus_wr_n_ff <= 1;
                    counter_iso <= 3'd0;
                    if (bus_rd_n == 0 || bus_wr_n == 0 ) begin
                        state_iso <= ACTIVE_ISO;
                    end
                end
                {ACTIVE_ISO, 3'd2} : begin
                    ex_bus_rd_n_ff <= bus_rd_n;
                    ex_bus_wr_n_ff <= bus_wr_n;
                    state_iso <= WAIT_ISO;
                end
                {WAIT_ISO, 3'bxxx} : begin
                    if ( bus_rd_n == 1 && bus_wr_n == 1 ) begin
                        state_iso <= IDLE_ISO;
                    end
                end
            endcase
        end
    end

`ifdef ENABLE_WAIT
    wire wait_io;
    reg wait_io_ff = 1;
    reg [6:0] wait_cycles;
    reg [6:0] state_wait;
    localparam WAIT_IDLE = 7'd0;
    localparam WAIT_STATE1 = 7'd1;
    localparam WAIT_STATE2 = 7'd3;
    localparam WAIT_STATE3 = 7'd2;
    localparam WAIT_STATE4 = 7'd4;

    assign wait_io = wait_io_ff;

  `ifndef ENABLE_WAIT_ADAPTIVE
    always @ (posedge clk_54m) begin
        if (~bus_reset_n) begin
            state_wait <= WAIT_IDLE;
            wait_io_ff <= 1;
        end 
        else begin
            case (state_wait)
                WAIT_IDLE: begin
                    if ( ram_write == 1 || (ex_bus_iorq_n == 0)&& (bus_rd_n == 0 || bus_wr_n == 0) ) begin
                        wait_io_ff <= 0;
                        state_wait <= WAIT_STATE1;
                    end
                end
                WAIT_STATE1: begin
                    if ( clk_enable_3m6_54 == 1 ) begin
                        state_wait <= WAIT_STATE2;
                    end
                end
                // NOTA v1.9: el wait sigue midiendo y liberando con los pulsos 3m6
                // fijos TAMBIEN en turbo (release 3m6-alineado con el CPU en tren
                // 5m4 swallowed). Validado en HW: juegos/DOS en turbo sin fallos.
                WAIT_STATE2: begin
                    if ( clk_falling_3m6_54 == 1 ) begin
                        wait_io_ff <= 1;
                        state_wait <= WAIT_STATE3;
                    end
                end
                WAIT_STATE3: begin
                    if ( bus_rd_n == 1 && bus_wr_n == 1) begin
                        state_wait <= WAIT_IDLE;
                    end
                end
            endcase
        end
    end
  `else
    always @ (posedge clk_54m) begin
        if (~bus_reset_n) begin
            state_wait <= WAIT_IDLE;
            wait_io_ff <= 1;
        end 
        else begin
            case (state_wait)
                WAIT_IDLE: begin
                    if ( (ex_bus_iorq_n == 0 || bus_mreq_n == 0 ) && (bus_rd_n == 0 || bus_wr_n == 0) ) begin
                        wait_io_ff <= 0;
                        wait_cycles <= 7'd6;
                        state_wait <= WAIT_STATE1;
                    end
                end
                WAIT_STATE1: begin
                    wait_cycles <= wait_cycles - 1;
                    if ( wait_cycles == 0 ) begin
                        state_wait <= WAIT_STATE2;
                    end
                end
                WAIT_STATE2: begin
                    if ( ram_busy == 0 && clk_enable_3m6_54 == 1 ) begin
                        state_wait <= WAIT_STATE3;
                    end
                end
                WAIT_STATE3: begin
                    if ( clk_falling_3m6_54 == 1 ) begin
                        wait_io_ff <= 1;
                        state_wait <= WAIT_STATE4;
                    end
                end
                WAIT_STATE4: begin
                    if ( bus_rd_n == 1 && bus_wr_n == 1) begin
                        state_wait <= WAIT_IDLE;
                    end
                end
            endcase
        end
    end
  `endif

`endif

    // v1.9: CPU cadence wires (assigned in the turbo block below). Forward-declared
    // so the M1-wait FSM tracks the ACTIVE cadence (3.6 normal / 5.37 turbo) instead
    // of the fixed 3.6 pulses — otherwise the M1 stall would last 1.5 T at 5.37 MHz.
    wire clk_enable_cpu_54;
    wire clk_falling_cpu_54;

`ifdef ENABLE_M1_WAIT
    // ===== STANDALONE M1 wait-state generator (frenado a ~100% MSX) =====
    // A real MSX inserts exactly 1 wait-state in every M1 (opcode-fetch) cycle.
    // The goauld got this from the MSX board via ex_bus_wait_n; standalone tied
    // ex_bus_wait_n=1 (top.v ~95), losing the brake -> CPU ran ~16% too fast.
    //
    // MECHANISM: GATE the CPU clock-enable, do NOT use WAIT_n.
    // The earlier WAIT_n version released the pulse at the T1->T2 boundary, so it
    // was already high when the core sampled WAIT_n inside T2 -> no wait inserted
    // (bench stayed at 116%). Instead we mirror the proven wait_io stall: mask
    // exactly one full CPU-clock period (one clk_enable_cpu_54 + one
    // clk_falling_cpu_54, i.e. the ACTIVE cadence) per M1 opcode fetch. Skipping one
    // removes exactly one T-state of progress = one wait-state, independent of
    // the core's internal T-state sampling. RFSH is T3/T4 with M1_n already high
    // (t80.vhd:1077), so refresh cycles are NOT slowed. clk_54m domain.
    reg  wait_m1 = 1'b1;            // active-high CPU clock-enable allow (0 = stall)
    reg  bus_m1_n_prev_54 = 1'b1;
    reg  m1_active = 1'b0;          // currently inserting the wait for this M1
    reg  m1_masked_en = 1'b0;       // masked one clk_enable pulse this wait
    reg  m1_masked_fall = 1'b0;     // masked one clk_falling pulse this wait

    always @ (posedge clk_54m) begin
        if (~bus_reset_n) begin
            wait_m1          <= 1'b1;
            bus_m1_n_prev_54 <= 1'b1;
            m1_active        <= 1'b0;
            m1_masked_en     <= 1'b0;
            m1_masked_fall   <= 1'b0;
        end else begin
            bus_m1_n_prev_54 <= bus_m1_n;
            if (!m1_active) begin
                // Falling edge of M1_n = new opcode fetch -> start one wait.
                if (bus_m1_n_prev_54 == 1'b1 && bus_m1_n == 1'b0) begin
                    m1_active      <= 1'b1;
                    wait_m1        <= 1'b0;   // stall CPU clock from next cycle
                    m1_masked_en   <= 1'b0;
                    m1_masked_fall <= 1'b0;
                end
            end else begin
                // While stalled (wait_m1==0) the coincident enable/falling pulses
                // are masked out of the CPU clock-enable. Track one of each, then
                // release -> exactly one CPU-clock period (one T-state) inserted.
                // v1.9: tracks the MUXED cadence so the wait is exactly 1 T-state
                // in both 3.6 (normal) and 5.37 (turbo) modes.
                if (clk_enable_cpu_54)  m1_masked_en   <= 1'b1;
                if (clk_falling_cpu_54) m1_masked_fall <= 1'b1;
                if ((m1_masked_en  || clk_enable_cpu_54) &&
                    (m1_masked_fall || clk_falling_cpu_54)) begin
                    wait_m1   <= 1'b1;   // release on next cycle
                    m1_active <= 1'b0;
                end
            end
        end
    end
`endif

    // ===== v1.9-fh: retraso de power-on para el ESP-01S (WiFi) =====
    // El INIT del driver ESP corre en el escaneo de slots ~1-2s tras dar
    // corriente, pero el ESP-01S tarda ~3-5s en arrancar: quedaba instalado
    // "sin ESP" (discovery UNAPI = 0 implementaciones) hasta re-init manual
    // via el setup W. Retener el Z80 en reset ~3s SOLO en el power-on da
    // tiempo al ESP y el INIT lo encuentra a la primera. El contador SATURA
    // y no se re-arma: los soft-reset siguen siendo instantaneos (regla de la
    // megaram) y el coste real es ~1.5-2s extra (el stream de flash ya tapa
    // parte). Sin ENABLE_WIFI no aplica.
`ifdef ENABLE_WIFI
    reg [26:0] esp_boot_cnt = 0;
    reg        esp_boot_ok  = 0;
    always @(posedge clk_27m) begin
        if (!esp_boot_ok) begin
            if (esp_boot_cnt == 27'd81000000)   // ~3.0s @ 27 MHz
                esp_boot_ok <= 1;
            else
                esp_boot_cnt <= esp_boot_cnt + 1'b1;
        end
    end
`else
    wire esp_boot_ok = 1'b1;
`endif

    // ===== Turbo mode (OSD setting) =====
    // Default turbo=0 -> M1 wait active -> ~100% real-MSX speed (3.58MHz behaviour).
    // Set it from the OSD (Turbo, id "T"). v1.9: turbo=1 switches the CPU cadence
    // to 5.37 MHz (WSX-style) while the per-M1 wait STAYS active, like the real
    // T9769 does at 5.37 MHz -> benchmarks report ~5.37 (150%). (The v1.8
    // "bypass M1 wait" turbo stacked on the 5.4 clock read as ~6.2 MHz on HW.)
    // Survives MSX soft-reset; powers on in real-MSX mode. LED5 shows the state.
    reg turbo   = 1'b0;
    reg boot_done = 1'b0;   // 1 tras la PRIMERA (fria) salida de reset; sobrevive warm resets

    // Turbo is an OSD setting, not a keyboard shortcut. The core no longer
    // intercepts F11: keys belong to the MSX, and machine settings belong in
    // the overlay. system_turbo arrives from sysctrl CMD 4 in the companion's
    // clock domain, so it is synchronised here and applied on change -- edge
    // rather than level, so that the Panasonic OUT &H41 path below still works
    // between OSD changes.
    reg t_s0 = 1'b0;
    reg t_s1 = 1'b0;
    reg t_prev = 1'b0;
    always @ (posedge clk_54m) begin
        t_s0   <= system_turbo;
        t_s1   <= t_s0;
        t_prev <= t_s1;
        if (t_s1 != t_prev)
            turbo <= t_s1;
        // v1.9: control software Panasonic — OUT &H41,n con el dispositivo 8
        // seleccionado (decode pana41_wr junto al bloque config). bit0 activo-bajo:
        // 0 = turbo 5.37 MHz, 1 = 3.58. Puesto tras el F11: si coinciden en el
        // mismo ciclo gana el software (en el T9769 real el puerto es el unico control).
        if (pana41_wr)
            turbo <= ~cpu_dout[0];
        // v1.9: "Boot Turbo" persistido (ajuste del menu, puerto #45). Siembra el
        // turbo durante la ventana config_init del stream de flash: config_init y
        // config_sig son dominio clk_54m (sin CDC) y config_sig[4] ya esta cargado
        // cuando la ventana abre (se carga con last_bytes_cnt==2). Va el ULTIMO del
        // bloque: domina sobre F11/puerto durante el boot (no disparan ahi de todos
        // modos). Con S2 (rescate) arranca SIEMPRE a 3.58.
        // v1.9b FIX pantalla-negra Save&Reset-con-turbo: el boot-turbo (5.37) SOLO se
        // aplica en arranque en FRIO. Rearrancar a 5.37 en un warm reset (Save&Reset)
        // daba pantalla negra persistente: el cold boot retiene el CPU ~3s via esp_boot_ok
        // (asienta SDRAM/VDP antes de correr a 5.37), pero el warm reset lo suelta al
        // instante -> el primer arranque a 5.37 sin asentar se cuelga. boot_done distingue
        // frio (0) de warm (1): en warm -> turbo=0 -> arranca a 3.58 = un Save&Reset normal
        // (que SI funciona). El boot-turbo se aplica al PROXIMO encendido. Cold boot:
        // boot_done=0 -> se respeta config_sig[4] -> 5.37 intacto (camino validado).
        if (config_init)
            turbo <= (~boot_done && s2 == 0 && config_sig[4] == 8'h54) ? 1'b1 : 1'b0;
        // estado conocido de `turbo` en cualquier reset (mirror del cold boot). Ultimo = prioridad.
        if (~bus_reset_n)
            turbo <= 1'b0;
    end
    // boot_done: se pone a 1 la primera vez que el CPU sale de reset (arranque en frio)
    // y NO se borra nunca (sin clausula de reset -> sobrevive los warm resets; GSR lo
    // inicia a 0 al encender). Es el discriminador frio/warm para el boot-turbo de arriba.
    always @ (posedge clk_54m)
        if (bus_reset_n & reset3_n & flash_idle & esp_boot_ok & ~config_init)
            boot_done <= 1'b1;   // ~config_init: no marcar boot_done durante la siembra
                                 // (robusto tambien si se compilara sin WiFi, esp_boot_ok=1)

    // ===== v1.9 Panasonic-WSX turbo: 5.37 MHz CPU cadence =====
    // /20 divider on 108 MHz -> 5.40 MHz base cadence + "period swallow" trim ->
    // EXACT WSX 5.369318 MHz (see below). The sound chips keep the /30
    // clk_enable_3m6_27 (untouched). At turbo=0 the CPU uses the ORIGINAL
    // clk_enable_3m6_54 verbatim (3.58 behaviour byte-identical). NOTE: NO
    // ram_busy handshake yet, so if HW shows corruption during active display,
    // add the handshake (dormant ENABLE_WAIT_ADAPTIVE, top.v ~707) in iter.2.
    //
    // Divisor /20 PURO (mitades de 10 ciclos, pares: fase constante vs clk_54m).
    // NOTA: durante el desarrollo se probo un divisor fraccionario (17x10+1x11,
    // 5.37 directo reformando el reloj) y se descarto; los "cuelgues" que se le
    // atribuyeron resultaron ser un falso contacto del teclado, pero el esquema
    // /20 puro + trago (abajo) es mas simple, conserva las fases 108->54
    // validadas y da el 5.37 EXACTO. Validado en HW (juegos/DOS en turbo).
    reg [4:0] div20_cnt;
    reg       clk_5m4_internal;
    always @(posedge clk_108m or negedge bus_reset_n) begin
        if (~bus_reset_n) begin div20_cnt <= 0; clk_5m4_internal <= 0; end
        else if (div20_cnt >= 5'd9) begin clk_5m4_internal <= ~clk_5m4_internal; div20_cnt <= 0; end
        else div20_cnt <= div20_cnt + 1;
    end
    wire clk_enable_5m4_raw, clk_falling_5m4_raw;
    reg  s5m4_a, s5m4_b;
    always @(posedge clk_54m) begin s5m4_a <= clk_5m4_internal; s5m4_b <= s5m4_a; end
    assign clk_enable_5m4_raw  = (s5m4_b == 0 && s5m4_a == 1);
    assign clk_falling_5m4_raw = (s5m4_b == 1 && s5m4_a == 0);

    // Ajuste EXACTO a 5.37: "trago" de periodo. De cada 176 periodos de 5.4 MHz
    // se enmascara 1 completo (su enable Y su falling, en pareja) ->
    // 5.4 MHz * 175/176 = 5 369 318 Hz = el turbo WSX exacto (315/88 * 1.5 MHz).
    // Mismo mecanismo probado que los waits M1/IO (saltar pulsos de enable en el
    // dominio 54), SIN tocar la forma del reloj 5m4 ni sus fases 108->54. El CPU
    // solo percibe una pausa de 1 T-state cada ~33 us; la alternancia
    // enable/falling se conserva (se traga la pareja completa).
    reg [7:0] pana_per_cnt   = 0;
    reg       pana_skip_pend = 0;   // enmascarando el falling del periodo tragado
    wire      pana_skip_now  = (pana_per_cnt == 8'd175) && clk_enable_5m4_raw;
    always @(posedge clk_54m) begin
        if (~bus_reset_n) begin
            pana_per_cnt   <= 0;
            pana_skip_pend <= 0;
        end else begin
            if (clk_enable_5m4_raw) begin
                if (pana_per_cnt == 8'd175) begin
                    pana_per_cnt   <= 0;
                    pana_skip_pend <= 1;    // el falling de ESTE periodo tambien se traga
                end else
                    pana_per_cnt <= pana_per_cnt + 1'b1;
            end
            if (pana_skip_pend && clk_falling_5m4_raw)
                pana_skip_pend <= 0;
        end
    end
    wire clk_enable_5m4_54  = clk_enable_5m4_raw  & ~pana_skip_now;
    wire clk_falling_5m4_54 = clk_falling_5m4_raw & ~pana_skip_pend;
    // ===== v1.9a: conmutado de cadencia turbo SIN glitch (fix cuelgue F11 / Save&Reset) =====
    // El mux elige entre dos cadencias de FASE INDEPENDIENTE (3.6 del /30, 5.37 del
    // /20). Conmutarlo sobre el `turbo` crudo a mitad de T-estado puede entregar al
    // Z80 dos ENABLE (o dos FALLING) seguidos SIN pareja -> un opcode mal-latcheado
    // -> cuelgue (F11 en el menu, "a veces"; o pantalla negra saliendo de un
    // Save&Reset con turbo). En BASIC su bucle ocioso absorbia el pulso suelto.
    // Fix: `turbo_eff` (el select REAL del mux) solo adopta `turbo` cuando AMBAS
    // cadencias estan bajas (entre un FALLING y el proximo ENABLE, via cadence_safe)
    // Y el CPU NO esta en ningun wait (wait_io & wait_m1). Asi el conmutado cae en
    // un limite de T-estado limpio: no rompe la alternancia enable/falling NI parte
    // en dos una ventana de wait_io (que se acota con los flancos 3.6 fijos mientras
    // gatea la cadencia muxada -> si el cambio cayera dentro, invertiria la paridad).
    // Mientras el CPU esta en RESET (los mismos 4 terminos de .RESET_n) adopta
    // `turbo` directo: el CPU no cuenta, y asi al soltarlo turbo_eff ya vale el
    // boot-turbo que sembro config_init durante el re-stream (identico al cold boot).
    wire cadence_safe = (bus_clk_3m6 == 1'b0 && bus_clk_3m6_54 == 1'b0) &&
                        (s5m4_a == 1'b0 && s5m4_b == 1'b0);
    // v1.9b: durante un warm reset EN CURSO hay que CRUZAR la entrada del reset a 3.58,
    // no a 5.37. En un Save&Reset con turbo activo (F11) el CPU sigue a 5.37 toda la
    // ventana pre-reset (config_reset espera a que acabe la grabacion en flash, ~decenas
    // de ms, con bus_reset_n aun alto) y cruzaria el borde de reset en turbo. warm_reset_pending
    // se activa en cuanto la grabacion arranca (flash_write_busy) y se mantiene por
    // config_reset_req hasta que baja bus_reset_n -> fuerza turbo_eff=0 en el MISMO borde
    // seguro. A cold boot ambas son 0 -> cold-boot-turbo intacto. (El boot-turbo POST-reset
    // ya no se aplica en warm: lo gestiona boot_done arriba.)
    wire warm_reset_pending = flash_write_busy | config_reset_req;
    reg  turbo_eff = 1'b0;
    always @ (posedge clk_54m) begin
        if (!(bus_reset_n & reset3_n & flash_idle & esp_boot_ok))
            turbo_eff <= turbo;                                 // en reset: sigue a turbo (semilla / 0)
        else if (cadence_safe & wait_io & wait_m1)
            turbo_eff <= warm_reset_pending ? 1'b0 : turbo;     // corriendo: 3.58 si hay warm-reset pendiente
    end
    // CPU cadence mux: turbo_eff (conmutado sin glitch) elige 5.37; si no, la 3.6 intacta.
    assign clk_enable_cpu_54  = turbo_eff ? clk_enable_5m4_54  : clk_enable_3m6_54;
    assign clk_falling_cpu_54 = turbo_eff ? clk_falling_5m4_54 : clk_falling_3m6_54;

    // ----- M1-wait fallback (divisor) -----
    // If on real HW the benchmark still does not land near 100% with the WAIT_n
    // brake above, comment out `define ENABLE_M1_WAIT and instead SLOW the CPU
    // clock by changing the 108MHz divider at top.v ~223 from /30 (3.6MHz) to
    // /35 (~3.09MHz): replace `if (div30_cnt == 5'd14)` with a half-period of
    // ~17.5 -> alternate 17/18, e.g.:
    //     reg div_tgl;  // toggles every edge to alternate 17/18
    //     if (div30_cnt == (div_tgl ? 5'd17 : 5'd16)) begin
    //         clk_3m6_internal <= ~clk_3m6_internal; div30_cnt <= 0; div_tgl <= ~div_tgl;
    //     end else div30_cnt <= div30_cnt + 1;
    // This lowers the clock instead of inserting a wait (less authentic, but a
    // guaranteed % knob). Do NOT enable both at once.

    wire update_addr;
    G80a  #(
        .Mode    (0),     // 0 => Z80, 1 => Fast Z80, 2 => 8080, 3 => GB
        //.T2Write (0),     //0 => WR_n active in T3, /=0 => WR_n active in T2
        .IOWait   (1)      // 0 => Single I/O cycle, 1 => Std I/O cycle
    ) cpu1 (
        .RESET_n   (bus_reset_n & reset3_n & flash_idle & esp_boot_ok),
        .CLK_n     (clk_54m),
    `ifdef ENABLE_WAIT
      `ifdef ENABLE_M1_WAIT
        // v1.9: M1 wait is NOT bypassed in turbo (real WSX keeps it at 5.37 MHz);
        // the speed change comes only from the 3.6/5.37 cadence mux.
        .clk_enable (clk_enable_cpu_54 & wait_io & wait_m1),
        .clk_falling (clk_falling_cpu_54 & wait_io & wait_m1),
      `else
        .clk_enable (clk_enable_3m6_54 & wait_io ),
        .clk_falling (clk_falling_3m6_54 & wait_io ),
      `endif
    `else
      `ifdef ENABLE_M1_WAIT
        // (inactive branch) v1.9 semantics: cadence mux + M1 wait always on
        .clk_enable (clk_enable_cpu_54 & wait_m1),
        .clk_falling (clk_falling_cpu_54 & wait_m1),
      `else
        .clk_enable (clk_enable_3m6_54),
        .clk_falling (clk_falling_3m6_54),
      `endif
    `endif
    `ifdef ENABLE_WIFI
      `ifndef ENABLE_WAIT_ADAPTIVE
        .WAIT_n    (bus_wait_n & wait_uart),
      `else
        .WAIT_n    (wait_uart),
      `endif
    `else
      `ifndef ENABLE_WAIT_ADAPTIVE
        .WAIT_n    (bus_wait_n),
      `else
        .WAIT_n    (1),
      `endif
    `endif
    `ifdef ENABLE_V9958
        .INT_n     (bus_int_n & vdp_int),
    `else
        .INT_n     (bus_int_n),
    `endif
        .NMI_n     (1'b1),
        .BUSRQ_n   (1),
        .M1_n      (bus_m1_n),
        .MREQ_n    (bus_mreq_n),
        .IORQ_n    (bus_iorq_n),
        .RD_n      (bus_rd_n),
        .WR_n      (bus_wr_n),
        .RFSH_n    (bus_rfsh_n),
        .HALT_n    ( ),
        .BUSAK_n   ( ),
        .A         (bus_addr),
        .update_addr(update_addr),
        .DI         (cpu_din),
        .DO         (cpu_dout),
        .Data_Reverse (bus_data_reverse)
    );

    //slots decoding
    reg [7:0] ppi_port_a = 8'h00;
    wire ppi_req_r;
    wire ppi_req_w;
    wire [1:0] pri_slot;
    wire [3:0] pri_slot_num;
    wire [3:0] page_num;

    //----------------------------------------------------------------
    //-- PPI(8255) / primary-slot
    //----------------------------------------------------------------
    assign ppi_req_r = (bus_addr[7:0] == 8'ha8 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_rd_n == 0)? 1:0;
    assign ppi_req_w = (bus_addr[7:0] == 8'ha8 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0)? 1:0;

    always @ (posedge clk_27m or negedge bus_reset_n) begin
        if ( bus_reset_n == 0)
            ppi_port_a <= 8'h00;
        else begin
            if (ppi_req_w == 1 ) begin
                ppi_port_a <= cpu_dout;
            end
        end
    end

    //expanded slots 0 & 3
    reg [7:0] exp_slot0;
    wire [1:0] exp_slot0_page;
    wire [3:0] exp_slot0_num;
    reg exp_slot0_req_r;
    reg exp_slot0_req_w;
    reg [7:0] exp_slotx;
    wire [1:0] exp_slotx_page;
    wire [3:0] exp_slotx_num;
    reg exp_slotx_req_r;
    reg exp_slotx_req_w;
    wire xffff;
    reg xffh;
    reg xffl;
    always @ (posedge clk_54m) begin
        xffh <= bus_addr[15:8] == 8'hff;
        xffl <= bus_addr[7:0] == 8'hff;
        exp_slot0_req_w <= ( bus_mreq_n == 0 && bus_wr_n == 0 && xffh == 1 && xffl == 1 && pri_slot_num[0] == 1 ) ? 1: 0;
        exp_slot0_req_r <= ( bus_mreq_n == 0 && bus_rd_n == 0 && xffh == 1 && xffl == 1 && pri_slot_num[0] == 1 ) ? 1: 0;
        exp_slotx_req_w <= ( bus_mreq_n == 0 && bus_wr_n == 0 && xffh == 1 && xffl == 1 && pri_slot_num[SD_SLOT] == 1 ) ? 1: 0;
        exp_slotx_req_r <= ( bus_mreq_n == 0 && bus_rd_n == 0 && xffh == 1 && xffl == 1 && pri_slot_num[SD_SLOT] == 1 ) ? 1: 0;
    end
    //assign xffff = ( bus_addr == 16'hffff ) ? 1 : 0;
    assign xffff = xffh & xffl;

//    assign exp_slotx_req_w = ( bus_mreq_n == 0 && bus_wr_n == 0 && xffff == 1 && pri_slot_num[0] == 1 ) ? 1: 0;
//    assign exp_slotx_req_r = ( bus_mreq_n == 0 && bus_rd_n == 0 && xffff == 1 && pri_slot_num[0] == 1 ) ? 1: 0;

    // slot #0
    always @ (posedge clk_27m or negedge bus_reset_n) begin
        if ( bus_reset_n == 0 )
            exp_slot0 <= 8'h00;
        else begin
            if (exp_slot0_req_w == 1 ) begin
                exp_slot0 <= cpu_dout;
            end
        end
    end

    // slot #3
    always @ (posedge clk_27m or negedge bus_reset_n) begin
        if ( bus_reset_n == 0 )
            exp_slotx <= 8'h00;
        else begin
            if (exp_slotx_req_w == 1 ) begin
                exp_slotx <= cpu_dout;
            end
        end
    end

    // slots decoding
    assign pri_slot = ( bus_addr[15:14] == 2'b00) ? ppi_port_a[1:0] :
                      ( bus_addr[15:14] == 2'b01) ? ppi_port_a[3:2] :
                      ( bus_addr[15:14] == 2'b10) ? ppi_port_a[5:4] :
                                             ppi_port_a[7:6];

    assign pri_slot_num = ( pri_slot == 2'b00 ) ? 4'b0001 :
                          ( pri_slot == 2'b01 ) ? 4'b0010 :
                          ( pri_slot == 2'b10 ) ? 4'b0100 :
                                                  4'b1000;

    assign page_num = ( bus_addr[15:14] == 2'b00) ? 4'b0001 :
                      ( bus_addr[15:14] == 2'b01) ? 4'b0010 :
                      ( bus_addr[15:14] == 2'b10) ? 4'b0100 :
                                                    4'b1000;
    assign exp_slot0_page = ( bus_addr[15:14] == 2'b00) ? exp_slot0[1:0] :
                            ( bus_addr[15:14] == 2'b01) ? exp_slot0[3:2] :
                            ( bus_addr[15:14] == 2'b10) ? exp_slot0[5:4] :
                                                          exp_slot0[7:6];

    assign exp_slot0_num = ( exp_slot0_page == 2'b00 ) ? 4'b0001 :
                           ( exp_slot0_page == 2'b01 ) ? 4'b0010 :
                           ( exp_slot0_page == 2'b10 ) ? 4'b0100 :
                                                         4'b1000;

    assign exp_slotx_page = ( bus_addr[15:14] == 2'b00) ? exp_slotx[1:0] :
                            ( bus_addr[15:14] == 2'b01) ? exp_slotx[3:2] :
                            ( bus_addr[15:14] == 2'b10) ? exp_slotx[5:4] :
                                                          exp_slotx[7:6];

    assign exp_slotx_num = ( exp_slotx_page == 2'b00 ) ? 4'b0001 :
                           ( exp_slotx_page == 2'b01 ) ? 4'b0010 :
                           ( exp_slotx_page == 2'b10 ) ? 4'b0100 :
                                                         4'b1000;

    reg slot0_req_r;
    reg slotx_req_r;
    always @ (posedge clk_54m) begin
        slot0_req_r <= ( bus_mreq_n == 0 && bus_rd_n == 0 && pri_slot_num[0] == 1 ) ? 1 : 0;
        slotx_req_r <= ( ( config_enable_mapper3 == 1 || config_enable_megaram3 == 1 || config_enable_sdcard == 1 ) && bus_mreq_n == 0 && bus_rd_n == 0 && pri_slot_num[SD_SLOT] == 1 ) ? 1 : 0;
    end

`ifdef ENABLE_BIOS
    //bios
    reg bios_req;
    wire [7:0] bios_dout;
    always @ (posedge clk_54m) begin
        bios_req <= ( bus_mreq_n == 0 && bus_rd_n == 0 && pri_slot_num[0] == 1 && exp_slot0_num[0] == 1) ? 1 : 0;
    end

    //subrom
    reg subrom_req;
    wire [7:0] subrom_dout;
    always @ (posedge clk_54m) begin
        subrom_req <= ( bus_mreq_n == 0 && bus_rd_n == 0 && pri_slot_num[SD_SLOT] == 1 && page_num[0] == 1 && exp_slotx_num[1] == 1 ) ? 1 : 0;
    end

    //msx logo
    reg msx_logo_req;
    wire [7:0] msx_logo_dout;
    always @ (posedge clk_54m) begin
        msx_logo_req <= ( bus_mreq_n == 0 && bus_rd_n == 0 && page_num[1] == 1 && pri_slot_num[SD_SLOT] == 1 && exp_slotx_num[1] == 1 ) ? 1 : 0;
    end

    //subrom + logo
    reg subrom_logo_req;
    always @ (posedge clk_54m) begin
        subrom_logo_req <= ( bus_mreq_n == 0 && bus_rd_n == 0 && (page_num[0] == 1 || page_num[1] == 1) && pri_slot_num[SD_SLOT] == 1 && exp_slotx_num[1] == 1 ) ? 1 : 0;
    end

    //kanji driver
    reg kanji_driver_req;
    always @ (posedge clk_54m) begin
        kanji_driver_req <= ( bus_mreq_n == 0 && bus_rd_n == 0 && (page_num[1] == 1 || page_num[2] == 1) && pri_slot_num[0] == 1 && exp_slot0_num[1] == 1 ) ? 1 : 0;
    end


`else

    wire bios_req;
    wire [7:0] bios_dout;
    wire subrom_req;
    wire [7:0] subrom_dout;
    wire msx_logo_req;
    wire [7:0] msx_logo_dout;
    wire kanji_driver_req;
    wire subrom_logo_req;

`endif

`ifdef ENABLE_WIFI

    //wifi driver
    reg wifi_req;
    always @ (posedge clk_54m) begin
        wifi_req <= ( bus_mreq_n == 0 && bus_rd_n == 0 && page_num[1] == 1 && pri_slot_num[0] == 1 && exp_slot0_num[2] == 1 ) ? 1 : 0;
    end

    //logo ROM (FREE16KB del pack @0x7C000) en slot 0-3 pagina 1: pantalla de
    //marca del menu (rutina+imagen autocontenidas; el menu la llama con CALLF)
    reg logo_req;
    always @ (posedge clk_54m) begin
        logo_req <= ( bus_mreq_n == 0 && bus_rd_n == 0 && page_num[1] == 1 && pri_slot_num[0] == 1 && exp_slot0_num[3] == 1 ) ? 1 : 0;
    end

    //uart
    wire uart_req;
    wire wait_uart;
    wire [7:0] uart_dout;

    assign uart_req = (bus_addr[7:1] == 7'b0000011 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_rd_n == 0)? 1 : 0; // ESP ports 06-07h

    wifi uwifi (
        .clk_i      (clk_27m),
        .wait_o     (wait_uart),
        .reset_i    (bus_reset_n),
        .iorq_i     (bus_iorq_n),
        .wrt_i      (bus_wr_n),
        .rd_i       (bus_rd_n),
        .rx_i       (uart_rx),
        .tx_o       (uart_tx),
        .adr_i      (bus_addr),
        .db_i       (cpu_dout),
        .db_o       (uart_dout)
    );

`endif 

    //rtc
    wire rtc_req_r;
    wire rtc_req_w;
    wire [7:0] rtc_dout;
    assign rtc_req_w = (bus_addr[7:1] == 7'b1011010 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0)? 1 : 0; // I/O:B4-B5h   / RTC
    assign rtc_req_r = (bus_addr[7:1] == 7'b1011010 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_rd_n == 0)? 1 : 0; // I/O:B4-B5h   / RTC

    rtc rtc1(
        .clk21m(clk_27m),
        .reset(0),
        .clkena(clk_enable_3m6_27),
        .req(rtc_req_w | rtc_req_r),
        .ack(),
        .wrt(rtc_req_w),
        .adr(bus_addr),
        .dbi(rtc_dout),
        .dbo(cpu_dout)
    );

    //vdp
	wire vdp_csw_n; //VDP write request
	wire vdp_csr_n; //VDP read request	
    wire [7:0] vdp_dout;
    wire vdp_int;
    wire WeVdp_n;
    wire [16:0] VdpAdr;
    wire [15:0] VrmDbi;
    wire [7:0] VrmDbo;
    wire VideoDHClk;
    wire VideoDLClk;
    //decode del VDP por modo: MSX 98-9Bh; SG-1000 BE/BFh; ColecoVision A0-BFh
    wire vdp_io_hit;
    assign vdp_io_hit = ( bus_addr[7:2] == 6'b100110 );
    assign vdp_csw_n = (vdp_io_hit == 1 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0)? 0:1; // VDP write
    assign vdp_csr_n = (vdp_io_hit == 1 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_rd_n == 0)? 0:1; // VDP read

    v9958_top vdp4 (
        .clk (clk_27m),
        .s1 (0),
        .clk_50 (0),
        .clk_125 (0),

    `ifdef ENABLE_V9958
        .reset_n (bus_reset_n ),
    `else
        .reset_n (0),
    `endif
        .mode    (bus_addr[1:0]),
        .csw_n   (vdp_csw_n),
        .csr_n   (vdp_csr_n),

        .int_n   (vdp_int),
        .gromclk (),
        .cpuclk  (),
        .cdi     (vdp_dout),
        .cdo     (cpu_dout),

        .audio_sample   (audio_sample),
        .audio_sample_r (audio_sample_r),
        .aspect_16_9    (config_enable_16_9),

        // FPGA-Companion OSD channel (framebuffer + compositor live in the VDP,
        // because that is where RGB exists)
        .osd_strobe     (osd_strobe),
        .osd_start      (osd_start),
        .osd_data       (osd_data),

        .adc_clk  (),
        .adc_cs   (),
        .adc_mosi (),
        .adc_miso (0),

        .maxspr_n    (1),
    `ifdef ENABLE_SCAN_LINES
        .scanlin_n   (~config_enable_scanlines),
    `else
        .scanlin_n   (1),
    `endif
        .gromclk_ena_n (1),
        .cpuclk_ena_n  (1),

        .WeVdp_n(WeVdp_n),
        .VdpAdr(VdpAdr),
        .VrmDbi(VrmDbi2),
        .VrmDbo(VrmDbo),

        .VideoDHClk(VideoDHClk),
        .VideoDLClk(VideoDLClk),

        .tmds_clk_p    (clk_p),
        .tmds_clk_n    (clk_n),
        .tmds_data_p   (data_p),
        .tmds_data_n   (data_n)
    );

`ifdef ENABLE_MAPPER
    //mapper
    wire mapper_read;
    wire mapper_write;
    wire mapper_req;
    reg mapper_req3;
    reg mapper_req12;
    reg [7:0] mapper_dout;
    wire [21:0] mapper_addr;
    reg [7:0] mapper_reg0;
    reg [7:0] mapper_reg1;
    reg [7:0] mapper_reg2;
    reg [7:0] mapper_reg3;
    wire mapper_reg_write;

    assign mapper_addr = (bus_addr [15:14] == 2'b00 ) ? { mapper_reg0, bus_addr[13:0] } :
                         (bus_addr [15:14] == 2'b01 ) ? { mapper_reg1, bus_addr[13:0] } :
                         (bus_addr [15:14] == 2'b10 ) ? { mapper_reg2, bus_addr[13:0] } :
                                                        { mapper_reg3, bus_addr[13:0] };

    always @ (posedge clk_54m) begin
        mapper_req3 <= ( bus_rfsh_n == 1 && config_enable_mapper3 == 1 && bus_mreq_n == 0 && (bus_rd_n == 0 || bus_wr_n == 0 ) && pri_slot_num[SD_SLOT] == 1 && exp_slotx_num[0] == 1 && xffff == 0) ? 1 : 0;
        mapper_req12 <= ( config_enable_mapper12 == 1 && bus_mreq_n == 0 && (bus_rd_n == 0 || bus_wr_n == 0 ) && pri_slot == config_mapper_slot ) ? 1 : 0;
    end
    assign mapper_req = mapper_req3 | mapper_req12;
    assign mapper_read = mapper_req & ~bus_rd_n;
    assign mapper_write = mapper_req & ~bus_wr_n;
    assign mapper_reg_write = ( (bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0) && (bus_addr [7:2] == 6'b111111) )?1:0;

    always @(posedge clk_27m or negedge bus_reset_n) begin
        if (bus_reset_n == 0) begin
            mapper_reg0	<= 8'b00000011;
            mapper_reg1	<= 8'b00000010;
            mapper_reg2	<= 8'b00000001;
            mapper_reg3	<= 8'b00000000;
        end
        else if (mapper_reg_write == 1) begin
            case (bus_addr[1:0])
                2'b00: mapper_reg0 <= cpu_dout[7:0];
                2'b01: mapper_reg1 <= cpu_dout[7:0];
                2'b10: mapper_reg2 <= cpu_dout[7:0];
                2'b11: mapper_reg3 <= cpu_dout[7:0];
            endcase
        end
    end
`else
    wire mapper_read;
    wire mapper_write;
    wire mapper_req;
    reg [7:0] mapper_dout;
    wire [21:0] mapper_addr;
    assign mapper_read = 0;
    assign mapper_write = 0;
    assign mapper_addr = 22'd0;
`endif

    reg [15:0] VrmDbi2;
    reg [7:0] megaram_dout;
    wire [22:0] ram_addr;
    wire ram_read;
    wire ram_write;
    wire ram_req;
    wire [7:0] ram_din;
    reg [7:0] ram_dout;
    reg ram_busy;

    //rom map, 512 KB, [18:0]
    //876 54321098 76543210
    //111 11xxxxxx xxxxxxxx free, 16 KB, 0x7c000 - 0x7ffff
    //111 10xxxxxx xxxxxxxx esp8266, 16 KB, 0x78000 - 0x7bfff
    //111 0xxxxxxx xxxxxxxx kanji, 32 KB, 0x70000 - 0x77fff
    //110 11xxxxxx xxxxxxxx fm + logo + boot menu, 16 KB, 0x6c000 - 0x6ffff
    //110 10xxxxxx xxxxxxxx msx2+ subrom, 16 KB, 0x68000 - 0x6bfff
    //110 0xxxxxxx xxxxxxxx msx2+ bios, 32 KB, 0x60000 - 0x67fff
    //10x xxxxxxxx xxxxxxxx wondertang disk, 128 KB, 0x40000 - 0x5ffff
    //01x xxxxxxxx xxxxxxxx jis2, 128 KB, 0x20000 - 0x3ffff
    //00x xxxxxxxx xxxxxxxx jis1, 128 KB, 0x00000 - 0x1ffff

    //sdram map, 8 MB, [22:0]
    //2109876 54321098 76543210
    //11111xx xxxxxxxx xxxxxxxx vram, 256 KB, bank D
    //1110111 10xxxxxx xxxxxxxx esp8266, 16 KB, 0x778000 - 0x77bfff
    //1110111 0xxxxxxx xxxxxxxx kanji driver, 32 KB, 0x770000 - 0x777fff
    //1110110 11xxxxxx xxxxxxxx fm + logo + boot menu, 16 KB, 0x76c000 - 0x76ffff
    //1110110 10xxxxxx xxxxxxxx msx2+ subrom, 16 KB, 0x768000 - 0x76bfff
    //1110110 0xxxxxxx xxxxxxxx msx2+ bios, 32 KB, 0x760000 - 0x767fff
    //111010x xxxxxxxx xxxxxxxx wondertang disk, 128 KB, bank D, 0x740000 - 0x75ffff
    //11100xx xxxxxxxx xxxxxxxx kanji data jis1 + jis2, 256 KB, 0x700000 - 0x73ffff
    //10xxxxx xxxxxxxx xxxxxxxx megaram, 2 MB, bank C
    //0xxxxxx xxxxxxxx xxxxxxxx mapper, 4 MB, banks A+B

    assign ram_addr = (~flash_idle) ? rom_addr :
                `ifdef ENABLE_MAPPER
                        (mapper_req == 1) ? { 1'b0, mapper_addr[21:0] } :  //bank A+B
                `endif
                        (bios_req == 1 ) ? { 8'b11101100, bus_addr[14:0] } : //bank D
                        (subrom_logo_req == 1 ) ? { 8'b11101101, bus_addr[14:0] } : //bank D
                `ifdef ENABLE_SDCARD
                        (megarom_req == 1 ) ? { 6'b111010, megarom_addr[16:0] } : //bank D
                `endif
                        (megaram_req == 1 ) ? { 2'b10, megaram_addr[20:0] } :  //bank C
                        (kanji_driver_req == 1 ) ? { 8'b11101110, ~bus_addr[14], bus_addr[13:0] } : //bank D
                        (kanji_data_ram_req == 1 ) ? { 5'b11100, kanji_data_ram_addr[17:0] } : //bank D
                `ifdef ENABLE_WIFI
                        (wifi_req == 1 ) ? { 9'b111011110, bus_addr[13:0] } : //bank D
                        (logo_req == 1 ) ? { 9'b111011111, bus_addr[13:0] } : //bank D (pack 0x7C000)
                `endif
                        23'h7fffff; 
    
    // Was a serial ?: chain of nine tests that all return the SAME value, so it
    // was only ever asking "did anything request a read". Written as an OR the
    // synthesiser can build a balanced tree instead of a nine-deep mux, which
    // matters because this feeds memory_ctrl -- instantiated on clk_54m despite
    // its port being named clk_27m -- and cpu1/RD -> mem1/sdram_* has been the
    // worst failing path in every timing miss this project has had.
    wire ram_any_read = `ifdef ENABLE_MAPPER  mapper_read       | `endif
                        `ifdef ENABLE_SDCARD  megarom_req       | `endif
                        `ifdef ENABLE_WIFI    wifi_req | logo_req | `endif
                        bios_req | subrom_logo_req | megaram_req |
                        kanji_driver_req | kanji_data_ram_req;
    assign ram_read = (~flash_idle) ? 1'b0 : (ram_any_read & ~bus_rd_n);
    
    // Same shape, same reasoning as ram_read above.
    wire ram_any_write = `ifdef ENABLE_MAPPER mapper_write | `endif
                         megaram_wrt;
    assign ram_write = (~flash_idle) ? rom_write : (ram_any_write & ~bus_wr_n);

    // Every branch of the old chain read (x == 1) ? x : ... -- each one returning
    // its own condition -- so there was never any priority to preserve and the
    // whole tail is simply an OR. All terms are one bit wide (checked), which
    // makes this transformation exact, not an approximation.
    //
    // This is the same fix that e48a96f applied to cpu_din, on the other path
    // family that keeps failing. ram_req drives sdram_seq's clock enable, and
    // cpu1/RD_s0/Q -> mem1/sdram_seq_*/CE was the worst endpoint in c2fcec4
    // (-0.486 ns) while the restructured cpu_din was down to -0.032 ns.
    wire ram_any_req = `ifdef ENABLE_SDCARD megarom_req        | `endif
                       `ifdef ENABLE_WIFI   wifi_req | logo_req | `endif
                       mapper_req | bios_req | subrom_logo_req | megaram_req |
                       kanji_driver_req | kanji_data_ram_req;
    assign ram_req = (~flash_idle) ? rom_write : ram_any_req;

    assign ram_din = (~flash_idle) ? { rom_dout, rom_dout }  : { cpu_dout, cpu_dout };

memory_ctrl mem1 (
    .clk_27m(clk_54m),
    .clk_108m(clk_108m),
    .bus_reset_n(bus_reset_n ),
    .video_dhclk(VideoDHClk),
    .video_dlclk(VideoDLClk),

    .ram_din(ram_din),
    .ram_req(ram_req),
    .ram_write(ram_write),
    .ram_addr(ram_addr),
    .vram_din(VrmDbo),
    .vram_write(~WeVdp_n),
    .vram_addr(VdpAdr),
    .bus_rfsh_n(bus_rfsh_n),

    .ram_dout(ram_dout),
    .vram_dout(VrmDbi2),
    .ram_busy(ram_busy),

    .O_sdram_clk(O_sdram_clk),
    .O_sdram_cke(O_sdram_cke),
    .O_sdram_cs_n(O_sdram_cs_n),
    .O_sdram_cas_n(O_sdram_cas_n),
    .O_sdram_ras_n(O_sdram_ras_n),
    .O_sdram_wen_n(O_sdram_wen_n),
    .IO_sdram_dq(IO_sdram_dq),
    .O_sdram_addr(O_sdram_addr),
    .O_sdram_ba(O_sdram_ba),
    .O_sdram_dqm(O_sdram_dqm)
);




`ifdef ENABLE_SOUND

    //YM219 PSG
    wire psgBdir;
    wire psgBc1;
    wire iorq_wr_n;
    wire iorq_rd_n;
    wire [7:0] psg_dout;
    wire [7:0] psgSound1;
    wire [7:0] psgPA;
    wire [7:0] psgPB;
    reg clk_1m8;
    assign iorq_wr_n = bus_iorq_n | bus_wr_n;
    assign iorq_rd_n = bus_iorq_n | bus_rd_n;
    assign psgBdir = ( bus_addr[7:3]== 5'b10100 && iorq_wr_n == 0 && bus_addr[1]== 0 ) ?  1 : 0; // I/O:A0-A2h / PSG(AY-3-8910) bdir = 1 when writing to &HA0-&Ha1
    assign psgBc1 = ( bus_addr[7:3]== 5'b10100 && ((iorq_rd_n==0 && bus_addr[1]== 1) || (bus_addr[1]==0 && iorq_wr_n==0 && bus_addr[0]==0))) ? 1 : 0; // I/O:A0-A2h / PSG(AY-3-8910) bc1 = 1 when writing A0 or reading A2
    assign psgPA =8'h00;
    reg psgPB = 8'hff;

    wire clk_enable_1m8;
    reg clk_1m8_prev;
    always @ (posedge clk_27m) begin
        if (clk_enable_3m6_27) begin
            clk_1m8 <= ~clk_1m8;
        end
    end
    assign clk_enable_1m8 = (clk_enable_3m6_27 == 1 && clk_1m8 == 1);

    YM2149 psg1 (
        .I_DA(cpu_dout),
        .O_DA(),
        .O_DA_OE_L(),
        .I_A9_L(0),
        .I_A8(1),
        .I_BDIR(psgBdir),
        .I_BC2(1),
        .I_BC1(psgBc1),
        .I_SEL_L(1),
        .O_AUDIO(psgSound1),
        .I_IOA(psgPA),
        .O_IOA(),
        .O_IOA_OE_L(),
        .I_IOB(psgPB),
        .O_IOB(psgPB),
        .O_IOB_OE_L(),
        
        .ENA(clk_enable_1m8), // clock enable for higher speed operation
        .RESET_L(bus_reset_n),
        .CLK(clk_27m),
        .clkHigh(clk_27m),
        .debug ()
    );

    wire [7:0] psgSound3;
    psg_filter filter1 (
        .clk_27m (clk_27m),
        .reset (~bus_reset_n),
        .data_in (psgSound1),
        .data_out (psgSound3)
    );

    // ===== Second PSG (OCM 2nd-gen standard): I/O 10h=latch, 11h=write, 12h=read =====
    wire psg2Bdir;
    wire psg2Bc1;
    assign psg2Bdir = ( bus_addr[7:2] == 6'b000100 && iorq_wr_n == 0 && bus_addr[1] == 0 ) ? 1 : 0;
    assign psg2Bc1  = ( bus_addr[7:2] == 6'b000100 && ((iorq_rd_n == 0 && bus_addr[1] == 1) || (bus_addr[1] == 0 && iorq_wr_n == 0 && bus_addr[0] == 0)) ) ? 1 : 0;

    wire [7:0] psg2Sound1;
    wire [7:0] psg2_dout;

    YM2149 psg2 (
        .I_DA(cpu_dout),
        .O_DA(psg2_dout),
        .O_DA_OE_L(),
        .I_A9_L(0),
        .I_A8(1),
        .I_BDIR(psg2Bdir),
        .I_BC2(1),
        .I_BC1(psg2Bc1),
        .I_SEL_L(1),
        .O_AUDIO(psg2Sound1),
        .I_IOA(8'hff),
        .O_IOA(),
        .O_IOA_OE_L(),
        .I_IOB(8'hff),
        .O_IOB(),
        .O_IOB_OE_L(),

        .ENA(clk_enable_1m8),
        .RESET_L(bus_reset_n),
        .CLK(clk_27m),
        .clkHigh(clk_27m),
        .debug ()
    );

    wire [7:0] psg2Sound3;
    psg_filter filter2 (
        .clk_27m (clk_27m),
        .reset (~bus_reset_n),
        .data_in (psg2Sound1),
        .data_out (psg2Sound3)
    );

    // PSG2 register read-back at port 12h (detection by players/trackers)
    wire psg2_req_r;
    assign psg2_req_r = ( bus_addr[7:0] == 8'h12 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_rd_n == 0 ) ? 1 : 0;

    //opll
    wire opll_req_n; 
    wire [9:0] opll_mo;
    wire [9:0] opll_ro;
    reg [11:0] opll_mix;
    wire [15:0] jt2413_wav;

    assign opll_req_n = ( bus_iorq_n == 1'b0 && bus_addr[7:1] == 7'b0111110  &&  bus_wr_n == 1'b0 )  ? 1'b0 : 1'b1;    // I/O:7C-7Dh   / OPLL (YM2413)
  
    jt2413 opll(
        .rst (~bus_reset_n),        // rst should be at least 6 clk&cen cycles long
        .clk (clk_27m),        // CPU clock
        .cen (clk_enable_3m6_27),        // optional clock enable, if not needed leave as 1'b1
        .din (cpu_dout),
        .addr (bus_addr[0]),
        .cs_n (opll_req_n),
        .wr_n (1'b0),
        // combined output
        .snd (jt2413_wav),
        .sample   ( )
    ); 

    //scc & ghost scc
    wire [14:0] scc_wav;
    wire [7:0] scc_dout;
    wire scc_req;
    reg scc_req3;
    wire scc_req3_r;
    reg scc_req12;

    wire scc_wrt;
    
    reg x98h;
    reg xb8h;
    always @ (posedge clk_27m) begin
        x98h <= ( bus_addr[15:8] == 8'h98 ) ? 1 : 0;
        xb8h <= ( bus_addr[15:8] == 8'hB8 ) ? 1 : 0;
    end

    // SCC-I mode signals (from megaram1, declared here as they gate the sound window)
    wire scc_mode_plus;     // BFFE bit5: 1 = SCC+ layout active
    wire sccplus_win_en;    // SCC+ window enabled (mode bit5 + bank3 bit7)

    reg [7:0] scc_bank2;
    reg scc_enable_req3;
    reg scc_enable_req12;
    wire scc_enable_req;
    always @ (posedge clk_27m) begin
        scc_enable_req3 <= ( bus_addr[15:11] == 5'b10010 && bus_mreq_n == 0 && bus_wr_n == 0 && pri_slot_num[SD_SLOT] == 1 && exp_slotx_num[3] == 1 ) ? 1 : 0;
        scc_enable_req12 <= ( config_enable_megaram12 == 1 && bus_addr[15:11] == 5'b10010 && bus_mreq_n == 0 && bus_wr_n == 0 && pri_slot == config_megaram_slot ) ? 1 : 0;
    end
    assign scc_enable_req = scc_enable_req3 | scc_enable_req12;

    always @ (posedge clk_27m or negedge bus_reset_n) begin
        if ( bus_reset_n == 0)
            scc_bank2 <= 8'h00;
        else begin
            if (scc_enable_req == 1 ) begin
                scc_bank2 <= cpu_dout;
            end
        end
    end

    wire scc_enable;
    assign scc_enable = ( scc_bank2 == 8'h3f ) ? 1 : 0;

    // Sound window: compat = 9800-98FF (bank2==3F, mode bit5=0);
    // SCC+ = B800-B8FF (mode bit5=1 + bank3 bit7, sound not disabled)
    wire scc_win;
    assign scc_win = ( scc_mode_plus == 0 ) ? ( scc_enable & x98h )
                                            : ( sccplus_win_en & xb8h & ~scc_sound_disable );

    always @ (posedge clk_27m) begin
        scc_req3 <= ( config_enable_megaram3 == 1 && scc_win == 1 && bus_mreq_n == 0 && (bus_wr_n == 0 || bus_rd_n == 0 ) && pri_slot == config_megaram_slot && exp_slotx_num[3] == 1  ) ? 1 : 0;
        scc_req12 <= ( config_enable_megaram12 == 1 && (scc_sound_disable == 0 || scc_mode_plus == 1) && scc_win == 1 && bus_mreq_n == 0 && (bus_wr_n == 0 || bus_rd_n == 0 ) && pri_slot == config_megaram_slot ) ? 1 : 0;
    end
    assign scc_req = scc_req3 | scc_req12;
    assign scc_req3_r = ( scc_req3 == 1 && bus_rd_n == 0 ) ? 1 : 0;
    assign scc_wrt = ( scc_req == 1 && bus_wr_n == 0 ) ? 1 : 0;

    // Wave-RAM read-back (SCC detection by trackers/SCC+ software). Any-window read strobe.
    wire scc_rd_r;
    assign scc_rd_r = ( scc_req == 1 && bus_rd_n == 0 ) ? 1 : 0;

    scc_wave2 SccCh (
        .clk21m (clk_27m),
        .reset (~bus_reset_n),
        .clkena (clk_enable_3m6_27),
        .req ( scc_req),
        .ack (),
        .wrt (scc_wrt),
        .adr (bus_addr[7:0]),
        .dbi (scc_dout),
        .dbo (cpu_dout),
        .wave (scc_wav),
        .sccplus (scc_mode_plus)
    );

    reg scc2_req3;
    reg scc2_req12;
    wire scc2_req;
    wire scc2_req_r;
    wire scc2_wrt;
    wire [7:0] scc2_dout;
    wire [14:0] scc2_wav;
    wire megaram_req;
    wire megaram_wrt;
    wire [20:0] megaram_addr;
    wire megaram_enabled;

    always @ (posedge clk_54m) begin
        // NOTE: config1_ff[2] ("ghost SCC", vestigial in standalone) is repurposed below
        // as the SECOND SCC+ enable; it no longer gates the megaram banking path.
        scc2_req3 <= ( config_enable_megaram3 == 1 && bus_mreq_n == 0 && (bus_rd_n == 0 || bus_wr_n == 0 ) && pri_slot == config_megaram_slot && exp_slotx_num[3] == 1  && xffff == 0) ? 1 : 0;
        scc2_req12 <= ( config_enable_megaram12 == 1 && bus_mreq_n == 0 && (bus_rd_n == 0 || bus_wr_n == 0 ) && pri_slot == config_megaram_slot ) ? 1 : 0;
        //scc2_req <= ( bus_mreq_n == 0 && (bus_rd_n == 0 || bus_wr_n == 0 ) && pri_slot_num[2] == 1 ) ? 1 : 0;
    end
    assign scc2_req = scc2_req3 | scc2_req12;
    assign scc2_req_r = ( scc2_req == 1 && bus_rd_n == 0 ) ? 1 : 0;
    assign scc2_wrt = ( scc2_req == 1 && bus_wr_n == 0 ) ? 1 : 0;

    wire [1:0] map_sel;
    wire map_linear;
    wire scc_sound_disable;
    assign map_sel = Slot2Mode;
    assign map_linear = iSlt2_linear;

    megaram_scc megaram1 (
        .clk_27m (clk_54m),
        .bus_reset_n (bus_reset_n),
        .bus_addr (bus_addr),
        .cpu_dout (cpu_dout),
        .bus_rd_n (bus_rd_n),
        .bus_wr_n (bus_wr_n),
        .scc_req (scc2_req),
        .scc_wrt (scc2_wrt),
        .map_sel (map_sel),
        .map_linear (map_linear),
        .sram_cfg (config3_ff),

        .megaram_req (megaram_req),
        .megaram_wrt (megaram_wrt),
        .megaram_addr (megaram_addr),
        .scc_sound_disable (scc_sound_disable),
        .scc_mode_plus (scc_mode_plus),
        .sccplus_win_en (sccplus_win_en)
    );


    // ===== Second SCC+ ("sound-only SCC-I cartridge" in the other free slot) =====
    // Enabled by config1_ff[2] (former "ghost SCC" bit, repurposed; menu toggle).
    // Lives in slot 1 if the megaram is in slot 2 and vice versa, so trackers that
    // drive two SCC carts in two slots find both. Own bank2/bank3/mode regs (SCC-I),
    // wave-RAM read-back included; no memory behind it (reads elsewhere return FF).
    wire [1:0] scc2x_slot;
    assign scc2x_slot = ( config_megaram_slot == 2'b01 ) ? 2'b10 : 2'b01;

    reg [7:0] scc2x_bank2;
    reg [7:0] scc2x_bank3;
    reg [7:0] scc2x_modeb;
    wire scc2x_slot_hit;
    assign scc2x_slot_hit = ( config_enable_ghost_scc == 1 && pri_slot == scc2x_slot ) ? 1 : 0;

    always @ (posedge clk_27m or negedge bus_reset_n) begin
        if (bus_reset_n == 0) begin
            scc2x_bank2 <= 8'h00;
            scc2x_bank3 <= 8'h00;
            scc2x_modeb <= 8'h00;
        end
        else if ( scc2x_slot_hit == 1 && bus_mreq_n == 0 && bus_wr_n == 0 ) begin
            if ( bus_addr[15:11] == 5'b10010 )
                scc2x_bank2 <= cpu_dout;                                    // 9000-97FF
            if ( bus_addr[15:11] == 5'b10110 && scc2x_modeb[4] == 0 )
                scc2x_bank3 <= cpu_dout;                                    // B000-B7FF
            if ( bus_addr[15:11] == 5'b10111 && bus_addr[10:1] == 10'b1111111111 )
                scc2x_modeb <= cpu_dout;                                    // BFFE-BFFF
        end
    end

    wire scc2x_win;
    assign scc2x_win = ( scc2x_modeb[5] == 0 ) ? ( (scc2x_bank2 == 8'h3f ? 1'b1 : 1'b0) & x98h )
                                               : ( scc2x_bank3[7] & xb8h & ~scc2x_modeb[4] );

    reg scc2x_req;
    always @ (posedge clk_27m) begin
        scc2x_req <= ( scc2x_slot_hit == 1 && scc2x_win == 1 && bus_mreq_n == 0 && (bus_wr_n == 0 || bus_rd_n == 0) ) ? 1 : 0;
    end
    wire scc2x_wrt;
    wire scc2x_rd_r;
    assign scc2x_wrt = ( scc2x_req == 1 && bus_wr_n == 0 ) ? 1 : 0;
    assign scc2x_rd_r = ( scc2x_req == 1 && bus_rd_n == 0 ) ? 1 : 0;

    wire [7:0] scc2x_dout;
    wire [14:0] scc2x_wav;

    scc_wave2 SccCh2 (
        .clk21m (clk_27m),
        .reset (~bus_reset_n),
        .clkena (clk_enable_3m6_27),
        .req ( scc2x_req),
        .ack (),
        .wrt (scc2x_wrt),
        .adr (bus_addr[7:0]),
        .dbi (scc2x_dout),
        .dbo (cpu_dout),
        .wave (scc2x_wav),
        .sccplus (scc2x_modeb[5])
    );

    //mixer (L = PSG1+SCC1+OPLL, R = PSG2+SCC2+OPLL; mono = everything on both sides)
	reg [15:0] audio_sample;
	reg [15:0] audio_sample_r;

    wire [15:0] scc_term;
    assign scc_term = (map_sel == 2'b10) ? { scc_wav, 1'b0 } : 16'd0;  // SCC solo en modo SCC (no Konami4/ASCII)

    // (modo consola SG-1000/ColecoVision eliminado en v1.9 -- solo MSX)

    // OSD volume ("V"): mute(0), 25/50/75/100%(1..4).
    // HDMI/IEC60958 carries PCM as SIGNED two's complement, so this must use
    // arithmetic shifts on a signed value. A logical shift turns a negative
    // sample into a large positive one -- which sounds like loud distortion at
    // every setting except 100%, where nothing is shifted at all.
    function signed [15:0] apply_volume;
        input signed [15:0] s;
        input [2:0]  vol;
        begin
            case (vol)
                3'd0: apply_volume = 16'sd0;                     // mute
                3'd1: apply_volume = s >>> 2;                    // 25%
                3'd2: apply_volume = s >>> 1;                    // 50%
                3'd3: apply_volume = (s >>> 1) + (s >>> 2);      // 75%
                default: apply_volume = s;                       // 100%
            endcase
        end
    endfunction

    reg [15:0] mix_l;
    reg [15:0] mix_r;

    always @ (posedge clk_27m) begin
        if (clk_enable_3m6_27 == 1 ) begin
            if (config_enable_stereo == 1) begin
                mix_l <= { 2'b0 , psgSound3 , 6'b000000 } + scc_term + jt2413_wav;
                mix_r <= { 2'b0 , psg2Sound3 , 6'b000000 } + { scc2x_wav, 1'b0 } + jt2413_wav;
            end
            else begin
                mix_l <= { 2'b0 , psgSound3 , 6'b000000 } + { 2'b0 , psg2Sound3 , 6'b000000 } + scc_term + { scc2x_wav, 1'b0 } + jt2413_wav;
                mix_r <= { 2'b0 , psgSound3 , 6'b000000 } + { 2'b0 , psg2Sound3 , 6'b000000 } + scc_term + { scc2x_wav, 1'b0 } + jt2413_wav;
            end
            audio_sample   <= apply_volume(mix_l, volume_ff);
            audio_sample_r <= apply_volume(mix_r, volume_ff);
        end
    end

`else

    wire scc2_req;
    wire [14:0] scc2_wav;
    wire megaram_req;
    wire [20:0] megaram_addr;
    wire megaram_enabled;
    wire [15:0] audio_sample;
    wire [15:0] audio_sample_r;
    wire megaram_wrt;

`endif

    //kanji data
    // Strobes REGISTRADOS a clk_27m: el decode combinacional desde IORQ formaba la
    // ruta critica (IORQ -> decode kanji -> mux ram_addr) a 54MHz. El ciclo I/O del
    // Z80 dura decenas de ciclos, asi que 1 ciclo extra de latencia es inocuo.
    reg kanji_data_req_r;
    reg kanji_data_req_w;
    wire kanji_data_ram_req;
    reg [7:0] kanji_data_dout;
    wire [17:0] kanji_data_ram_addr;
    always @ (posedge clk_27m) begin
        kanji_data_req_w <= (bus_addr[7:2] == 6'b110110 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0)? 1 : 0; // I/O:D8-DBh / Kanji-data
        kanji_data_req_r <= (bus_addr[7:2] == 6'b110110 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_rd_n == 0)? 1 : 0; // I/O:D8-DBh / Kanji-data
    end

    kanji kanji1(
        .clk21m(clk_27m),
        .reset(0),
        .req(kanji_data_req_w | kanji_data_req_r),
        .wrt(kanji_data_req_w),
        .adr(bus_addr),
        .dbo(cpu_dout),
        .ramreq(kanji_data_ram_req),
        .ramadr(kanji_data_ram_addr)
    );

`ifdef ENABLE_WIFI
    //f2 port
    wire f2_req_r;
    wire f2_req_w;
    reg [7:0] f2_port;

    assign f2_req_r = (bus_addr[7:0] == 8'hf2 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_rd_n == 0)? 1:0;
    assign f2_req_w = (bus_addr[7:0] == 8'hf2 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0)? 1:0;

    always @ (posedge clk_27m or negedge bus_reset_n) begin
        if ( bus_reset_n == 0)
            f2_port <= 8'h00;
        else begin
            if (f2_req_w == 1 ) begin
                f2_port <= cpu_dout;
            end
        end
    end
`endif

    localparam CONFIG1_DEFAULT = 8'hf3;  // bit3=0 -> Scanlines OFF by default (was 0xfb)
    localparam CONFIG2_DEFAULT = 8'h07;  // bit3 LIBRE (Compatible Mode eliminado en v1.9)

`ifdef ENABLE_CONFIG
    //config
    reg [7:0] config0_ff = 8'h00;
    reg [7:0] config1_ff = CONFIG1_DEFAULT;
    reg [7:0] config1_temp_ff;
    reg [7:0] config2_ff = CONFIG2_DEFAULT;
    reg [7:0] config2_temp_ff;
    reg [1:0] config_mapper_slot_ff = 2'b11;
    reg [1:0] config_megaram_slot_ff = 2'b11;
    reg [1:0] config_sdcard_slot_ff = 2'b11;
    reg config_enable_mapper3;
    reg config_enable_mapper12;
    wire config_enable_megaram;
    wire config_enable_megaram3;
    wire config_enable_megaram12;
    wire config_enable_ghost_scc;
    reg config_enable_sdcard;
    wire config_enable_stereo;
    wire config_enable_16_9;
    reg config_reset_ff;
    reg config_flash_write_ff;
    // Seeded to sysctrl's own reset values so that no spurious "changed" edge
    // fires at power-on, which would otherwise stamp the default over whatever
    // config_init had just restored from flash.
    reg       osd_db9_d    = 1'b0;
    reg       osd_tboot_d  = 1'b0;
    reg [2:0] osd_vol_prev = 3'd4;
    reg       osd_save_d   = 1'b0;
    reg config_update;
    wire config_enable_scanlines;
    wire [1:0] config_mapper_slot;
    wire [1:0] config_megaram_slot;
    wire [1:0] config_sdcard_slot;
    wire [1:0] config_keyboard;
    wire config0_req;
    wire config1_req;
    wire config2_req;
    wire config3_req;
    reg [7:0] config3_ff = 0;       // puerto #43: sram_cfg de la megaram (volatil)
    wire config5_req;
    reg config_turbo_boot_ff = 0;   // puerto #45 bit0: arrancar en turbo (PERSISTIDO en
                                    // flash byte[4] del bloque config: 'T'=0x54 -> on;
                                    // 0x00/0xFF legados -> off)
    wire config_reset_req;
    wire config_reset;
    wire config_ok;
    wire [7:0] config_dout;
    wire config_req;

    always @ (posedge clk_27m) begin
        config_reset_ff <= 0;
        config_flash_write_ff <= 0;
        config_update <= 0;
        // OSD "Save settings": the same flash write the S menu triggers through
        // port #42 bit 6. Edge-triggered, so it saves once however long the
        // companion leaves the value at 1. No reset is requested -- the S menu
        // offered Save & Exit as well as Save & Reset, and this is the former.
        osd_save_d <= system_save;
        if (system_save && !osd_save_d)
            config_flash_write_ff <= 1;
        if (clk_enable_3m6_27 == 1 ) begin
            if (config0_req == 1 ) begin
                config0_ff <= ~cpu_dout;
            end

            if (config1_req == 1 ) begin
                config_update <= 1;
                config1_temp_ff <= cpu_dout;
            end
            if (config3_req == 1 ) begin
                config3_ff <= cpu_dout;
            end
            if (config2_req == 1 ) begin
                config_update <= 1;
                config2_temp_ff <= cpu_dout[5:0];
                if ( cpu_dout[6] == 1) begin
                    config_flash_write_ff <= 1;
                end
                if ( cpu_dout[7] == 1) begin
                    config_reset_ff <= 1;
                end
            end
        end
    end

    reg [2:0] ocm_slot2_prev; //bit2 = linear ,bits 1,0 = mode
    reg ocm_update;
    always @ (posedge clk_27m) begin
        ocm_update <= 0;
        if ( { iSlt2_linear, Slot2Mode } != ocm_slot2_prev ) begin
            ocm_update <= 1;
        end
    end

    reg config_init_delay = 0;
    always @ (posedge clk_27m) begin
        config_init_delay <= config_init;
        if (config_init == 1 ) begin
            if (s2 == 1) begin
                config1_ff <= CONFIG1_DEFAULT;
                config2_ff <= CONFIG2_DEFAULT;
                config_turbo_boot_ff <= 0;      // rescate S2: boot turbo off
            end
            else begin
                config1_ff <= config_sig[2];
                config2_ff <= config_sig[3];
                config_turbo_boot_ff <= (config_sig[4] == 8'h54) ? 1'b1 : 1'b0;
            end
        end
        // Byte 5 of the flash block, which upstream wrote as 0xFF and never read.
        //
        // It CANNOT be read inside the config_init window above. config_init is
        // asserted while last_bytes_cnt == 1, and config_sig[5] is latched in the
        // very cycle that counter leaves 1 -- so throughout that window byte 5
        // still holds its previous value, which out of reset3_n is 8'd0. Bytes 2
        // to 4 are safe there because they land earlier; the note on boot-turbo
        // above says as much about byte 4 landing at last_bytes_cnt == 2.
        //
        // Reading it one cycle after config_init drops is the first moment it is
        // valid. Getting this wrong seeded volume from 8'd0 and the machine came
        // up muted -- and stayed muted after saving, because every boot re-read
        // the same stale zero.
        //
        // The marker is [7:6] == 01 rather than "bit 7 clear" for the same
        // reason: it must reject BOTH an erased 0xFF and a stale 0x00, so that a
        // byte we have not written can never be mistaken for one we have.
        if (config_init_delay && !config_init) begin
            if (s2 == 1 || config_sig[5][7:6] != 2'b01) begin
                volume_ff   <= 3'd4;    // never saved, erased, or S2 rescue
                db9_port_ff <= 1'b0;
            end
            else begin
                volume_ff   <= config_sig[5][2:0];
                db9_port_ff <= config_sig[5][3];
            end
        end
        // escritura del puerto #45 (menu): mismo bloque que la carga init para un
        // unico driver; config5_req dura todo el ciclo OUT (re-latch inocuo) y no
        // puede coincidir con config_init (el CPU arranca tras el stream de flash)
        if (config5_req == 1 ) begin
            config_turbo_boot_ff <= cpu_dout[0];
        end
        if (config_update == 1) begin
            config1_ff <= config1_temp_ff;
            config2_ff <= config2_temp_ff;
        end
        if (ocm_update == 1) begin
            config1_ff[7:6] <= 2'b10;
            config1_ff[1] <= 1;
            ocm_slot2_prev <= { iSlt2_linear, Slot2Mode };
        end

        // OSD settings (sysctrl CMD 4) write the same config bits the S menu
        // uses, on change rather than continuously -- so whichever was touched
        // last wins and both menus keep working. sysctrl runs on clk_27m too,
        // but these are re-registered here for a clean edge.
        osd_scan_d   <= system_scanlines;
        osd_wide_d   <= system_wide_screen;
        osd_stereo_d <= system_stereo;
        osd_scc2_d   <= system_second_scc;
        if (system_scanlines   != osd_scan_d)   config1_ff[3] <= system_scanlines;
        if (system_second_scc  != osd_scc2_d)   config1_ff[2] <= system_second_scc;
        if (system_wide_screen != osd_wide_d)   config2_ff[4] <= system_wide_screen;
        if (system_stereo      != osd_stereo_d) config2_ff[5] <= system_stereo;

        // Same pattern for the settings with no config1/config2 bit, plus boot
        // turbo, which does have one (flash byte 4) but was never connected to
        // the OSD. Change-triggered rather than continuous, which is what makes
        // the flash seeding survive: at start-up the companion pushes its XML
        // defaults, and those match sysctrl's reset values, so nothing changes
        // and nothing overwrites what config_init just loaded. Keep the XML
        // defaults and sys_ctrl.v's reset values in step or this breaks.
        osd_vol_prev <= system_volume;
        osd_db9_d    <= system_db9_port;
        osd_tboot_d  <= system_turbo_boot;
        if (system_volume      != osd_vol_prev) volume_ff   <= system_volume;
        if (system_db9_port    != osd_db9_d)    db9_port_ff <= system_db9_port;
        if (system_turbo_boot  != osd_tboot_d)  config_turbo_boot_ff <= system_turbo_boot;
    end


    monostable mono (
        .pulse_in(config_reset_ff),
        .clock(clk_27m),
        .pulse_out(config_reset_req)
    );
    assign config_reset = (config_reset_req == 1 && flash_write_busy == 0) ? 1 : 0;

    assign config_ok = (config0_ff == 8'hb7) ? 1 : 0;
    assign config0_req = (bus_addr[7:0] == 8'h40 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0)? 1:0;
    assign config1_req = (config_ok == 1 && bus_addr[7:0] == 8'h41 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0)? 1:0;
    assign config2_req = (config_ok == 1 && bus_addr[7:0] == 8'h42 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0)? 1:0;
    assign config3_req = (config_ok == 1 && bus_addr[7:0] == 8'h43 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0)? 1:0;
    assign config5_req = (config_ok == 1 && bus_addr[7:0] == 8'h45 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0)? 1:0;
    assign config_enable_scanlines = config1_ff[3];
    //assign config_keyboard = config2_ff[4:3];
    assign config_enable_stereo = config2_ff[5];
    assign config_enable_16_9 = config2_ff[4];
    // ===== v1.9 Panasonic switched-I/O device 8 (T9769 turbo, estilo WSX) =====
    // Protocolo (ref. openMSX MSXMatsushita.cc): OUT &H40,8 selecciona el dispositivo;
    // leer $40 devuelve ~8 = 247 (deteccion). $41 write: SOLO bit0, activo-bajo
    // (0 = 5.37 MHz, 1 = 3.58; OUT &H41,154 enciende porque 154 es par). $41 read:
    // bit0 = estado turbo (0=on), bit2 = 0 (turbo disponible), bit7 = 1 (sin
    // firmware switch), resto 1 -> 0xFA turbo / 0xFB normal.
    // config0_ff guarda ~ID, asi que "dispositivo 8 seleccionado" == 0xF7 y el
    // readback de $40 ES config0_ff = 247. Convive con el config goauld (ID 0x48
    // -> config_ok, excluyentes) y con el fallback swio_dout del rango $40-$4F.
    // La escritura del turbo se latchea en el bloque F11 (clk_54m, un solo driver).
    wire pana_sel  = (config0_ff == 8'hf7) ? 1 : 0;
    wire pana41_wr = (pana_sel == 1 && bus_addr[7:0] == 8'h41 &&
                      bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0) ? 1 : 0;
    wire [7:0] pana_dout = ( bus_addr[3:0] == 4'h0 ) ? config0_ff :
                           ( bus_addr[3:0] == 4'h1 ) ? ( turbo ? 8'hfa : 8'hfb ) : 8'hff;

    assign config_req = (bus_addr[7:4] == 4'h4 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_rd_n == 0)? 1:0;
    assign config_dout = ( bus_addr[3:0] == 4'h0 ) ? config0_ff :
                         ( bus_addr[3:0] == 4'h1 ) ? config1_ff :
                         ( bus_addr[3:0] == 4'h2 ) ? config2_ff :
                         ( bus_addr[3:0] == 4'h3 ) ? config3_ff :
                         ( bus_addr[3:0] == 4'h5 ) ? {7'b0, config_turbo_boot_ff} : 8'hff;


    always @ (posedge clk_54m) begin
        if (bus_reset_n == 0 || config_init_delay == 1 ) begin
            config_mapper_slot_ff <= config1_ff[5:4];
            config_enable_mapper3 <= (config1_ff[0] == 1 && config1_ff[5:4] == 2'b11);
            config_enable_mapper12 <= (config1_ff[0] == 1 && config1_ff[5:4] != 2'b11);
            //config_megaram_slot_ff <= config1_ff[7:6];
            config_enable_sdcard <= config2_ff[0];
            config_sdcard_slot_ff <= config2_ff[2:1];
        end
    end
    assign config_mapper_slot = config_mapper_slot_ff;
    assign config_megaram_slot = config1_ff[7:6];;
    assign config_sdcard_slot = config_sdcard_slot_ff;
    assign config_enable_megaram = config1_ff[1];
    assign config_enable_megaram3 = (config1_ff[1] == 1 && config1_ff[7:6] == 2'b11);
    assign config_enable_megaram12 = (config1_ff[1] == 1 && config1_ff[7:6] != 2'b11 );
    assign config_enable_ghost_scc = config1_ff[2];

`else

    wire config_enable_mapper3;
    wire config_enable_mapper12;
    wire config_enable_megaram;
    wire config_enable_megaram3;
    wire config_enable_megaram12;
    wire config_enable_ghost_scc;
    wire config_enable_sdcard;
    wire config_enable_scanlines;
    wire [1:0] config_mapper_slot;
    wire [1:0] config_megaram_slot;
    wire [1:0] config_sdcard_slot;
    wire config_reset;
    assign config_enable_mapper3 = 1;
    assign config_enable_mapper12 = 0;
    assign config_enable_megaram = 1;
    assign config_enable_megaram3 = 1;
    assign config_enable_megaram12 = 0;
    assign config_enable_ghost_scc = 0;
    assign config_enable_sdcard = 0;
    assign config_enable_scanlines = 1;
    assign config_mapper_slot = 2'b11;
    assign config_megaram_slot = 2'b11;
    assign config_sdcard_slot= 2'b11;
    assign config_reset = 0;
    wire config_enable_stereo;
    assign config_enable_stereo = 0;
    wire config_enable_16_9;
    assign config_enable_16_9 = 0;

`endif

    /// FLASH ROM LOADER - BIOS
    localparam FLASH_START_ADDRESS = 24'h200000;
    localparam RAM_START_ADDRESS = 23'h6fffff;
    localparam GOAULD_ROM_SIZE = 512*1024 + 6; //512KB + signature (AB) + config
    reg ff_rom_wr = 0;
    reg [24:0] ff_rom_addr;
    
    wire rom_write;
    wire [7:0] rom_dout;
    wire [24:0] rom_addr;
    assign rom_write = flash_busy;
    assign rom_dout = ff_rom_dout;
    assign rom_addr = ff_rom_addr;
    
    reg [31:0] ff_flash_counter;

//flash
    reg [23:0] ff_flash_addr = 24'd0;
    reg ff_flash_rd = 0;
    reg ff_flash_terminate = 0;
    reg [7:0] ff_rom_dout;
    reg flash_wait_n;
    wire[7:0] flash_dout;
    wire flash_data_ready;
    wire flash_busy;
    // Flash block byte 5. Bit 7 is the "written by us" marker and must stay 0;
    // an erased byte reads 0xFF and is rejected by config_init above.
    //   [7:6] 01 = written by us   [5:4] reserved (autofire, parked)
    //   [3] DB9 port   [2:0] volume
    // 01 and not a single bit, so that an erased 0xFF and a stale-read 0x00 are
    // both rejected -- see the seeding code, where reading 0x00 as valid made
    // the machine boot muted.
    wire [7:0] config_save_byte = { 2'b01, 2'b00, db9_port_ff, volume_ff };

    wire [7:0] flash_write_din;
    wire flash_write_busy;
    wire [7:0] flash_write_counter;
    wire flash_write_terminate;
    assign flash_write_din = (flash_write_counter == 8'd00) ? 8'h41 :
                             (flash_write_counter == 8'd01) ? 8'h42 :
                        `ifdef ENABLE_CONFIG
                             (flash_write_counter == 8'd02) ? config1_ff :
                             (flash_write_counter == 8'd03) ? config2_ff :
                             (flash_write_counter == 8'd04) ? (config_turbo_boot_ff ? 8'h54 : 8'h00) :
                             (flash_write_counter == 8'd05) ? config_save_byte : 8'hff;
                        `else
                             (flash_write_counter == 8'd02) ? CONFIG1_DEFAULT :
                             (flash_write_counter == 8'd03) ? CONFIG2_DEFAULT : 8'hff;
                        `endif
    assign flash_write_terminate = (flash_write_counter == 8'd6) ? 1 : 0;

    flash # (
        .STARTUP_WAIT(1)
    )
    flash1
    (
        .clk(clk_54m),
        .reset_n(bus_reset_n),
        .SCLK(mspi_sclk),
        .CS(mspi_cs),
        .MISO(mspi_miso),
        .MOSI(mspi_mosi),
        .addr(ff_flash_addr),
        .rd(ff_flash_rd),
        .dout(flash_dout),
        .data_ready(flash_data_ready),
        .busy(flash_busy),
        .terminate(ff_flash_terminate),
        .write_enable(config_flash_write_ff),
        .write_din(flash_write_din),
        .write_busy(flash_write_busy),
        .write_counter(flash_write_counter),
        .write_terminate(flash_write_terminate),
        .write_addr(24'h280000) //24'h278000)
    );

    reg [7:0] ff_flash_state = 8'd0;
    
    localparam STATE_RESET          = 8'd0;
    localparam STATE_READ_START     = 8'd1;
    localparam STATE_READ_LOOP      = 8'd2;
    localparam STATE_IDLE           = 8'd3;
    localparam STATE_INIT1          = 8'd4;
    localparam STATE_INIT2          = 8'd5;
    localparam STATE_INIT3          = 8'd6;
    localparam STATE_INIT4          = 8'd7;
    reg [31:0] nose = 0;
    wire flash_idle;
    assign flash_idle = (ff_flash_state == STATE_IDLE ) ? 1'b1 : 1'b0;
    
    always @(posedge clk_54m, negedge reset3_n) begin
    if (reset3_n == 0) begin
        ff_flash_state = STATE_RESET;
        ff_flash_rd <= 0;
        ff_rom_wr <= 0;
        nose <= 0;
    end else
        case (ff_flash_state)
    
            STATE_RESET: begin   // reset
                ff_flash_state <= STATE_READ_START;
                ff_flash_rd <= 0;
                ff_rom_wr <= 0;
                ff_flash_terminate <= 0;
            end
    
            STATE_INIT1: begin  // start read
                if (flash_busy == 0) begin
                    ff_flash_addr <= 24'h000000;
                    ff_flash_rd <= 1;
                    ff_flash_state = STATE_INIT2;
                end
            end
    
            STATE_INIT2: begin  // start read
                if (flash_busy == 1) begin
                    ff_flash_rd <= 0;
                    ff_flash_state = STATE_INIT3;
                end
            end
            
            STATE_INIT3: begin  // start read
                if (flash_busy == 0) begin
                    nose <= 0;
                    ff_flash_terminate <= 1;
                    ff_flash_state = STATE_INIT4;
                end
            end
    
            STATE_INIT4: begin  // start read
                nose <= nose + 1;
                if (nose > 10) begin
                    ff_flash_terminate <= 0;
                    ff_flash_state = STATE_READ_START;
                end
            end
    
            STATE_READ_START: begin  // start read
                if (flash_busy == 0) begin
                    ff_flash_addr <= FLASH_START_ADDRESS;
                    ff_rom_addr <= RAM_START_ADDRESS;
                    ff_flash_rd <= 1;
                    ff_flash_state = STATE_READ_LOOP;
                    ff_flash_counter <= GOAULD_ROM_SIZE;
                end
            end
    
            STATE_READ_LOOP: begin  // loop read
                if (flash_busy == 0) begin
    
                    if (ff_flash_counter > 0) begin
                        
                        if (~ff_flash_rd) begin
    
                            ff_flash_addr <= ff_flash_addr + 1;
                            ff_flash_counter <= ff_flash_counter - 1;
                            ff_flash_rd <= 1;
    
                            ff_rom_wr <= 1;
                            ff_rom_addr <= ff_rom_addr + 1;
                            ff_rom_dout <= flash_dout; 
    
                        end
                    end else begin    
                        ff_rom_wr <= 0;
                        ff_flash_rd <= 0;
                        ff_flash_state <= STATE_IDLE;
                    end
                end else begin
                    ff_rom_wr <= 0;
                    ff_flash_rd <= 0;
                end
            end
    
            STATE_IDLE: begin  // idle
                ff_flash_terminate <= 1;
            end
    
        endcase
    end

    // configuration + signature
    reg [7:0] config_sig [0:5];
    reg [2:0] last_bytes_cnt;
    wire new_byte;
    wire config_init;
    assign new_byte = (~ff_flash_rd && flash_busy == 0);
    assign config_init = (config_sig[0] == 8'h41 && config_sig[1] == 8'h42 && last_bytes_cnt == 3'd1) ? 1 : 0;

    always @(posedge clk_54m or negedge reset3_n) begin
        if (!reset3_n) begin
            last_bytes_cnt <= 3'd0;
            config_sig[0] <= 8'd0;
            config_sig[1] <= 8'd0;
            config_sig[2] <= 8'd0;
            config_sig[3] <= 8'd0;
            config_sig[4] <= 8'd0;
            config_sig[5] <= 8'd0;
        end else begin
            if (ff_flash_counter == 32'd6)
                last_bytes_cnt <= 3'd6;
            if (new_byte && last_bytes_cnt != 3'd0) begin
                case (last_bytes_cnt)
                    3'd6: config_sig[0] <= flash_dout;
                    3'd5: config_sig[1] <= flash_dout;
                    3'd4: config_sig[2] <= flash_dout;
                    3'd3: config_sig[3] <= flash_dout;
                    3'd2: config_sig[4] <= flash_dout;
                    3'd1: config_sig[5] <= flash_dout;
                endcase
                last_bytes_cnt <= last_bytes_cnt - 1;
            end
        end
    end


`ifdef ENABLE_SDCARD

    
   
    //megarom
    reg megarom_req;
    wire [16:0] megarom_addr;
    reg [2:0] megarom_page_ff;
    reg megarom_page_req;
    wire [2:0] megarom_page;

    always @ (posedge clk_54m) begin
        megarom_req <=     ( config_enable_sdcard == 1 && bus_mreq_n == 0 && bus_rfsh_n == 1 && bus_rd_n == 0 && pri_slot_num[SD_SLOT] == 1 && exp_slotx_num[2] == 1 && (page_num[1] == 1 || page_num[2] == 1) ) ? 1 : 0;
        megarom_page_req <= ( bus_mreq_n == 0 && bus_rfsh_n == 1 && bus_wr_n == 0 && pri_slot_num[SD_SLOT] == 1 && exp_slotx_num[2] == 1 && bus_addr == 16'h6000 ) ? 1 : 0;
    end
    assign megarom_page = megarom_page_ff;
    assign megarom_addr = { megarom_page, bus_addr[13:0] };

    always @(posedge clk_27m or negedge bus_reset_n) begin
        if (bus_reset_n == 0) begin
           megarom_page_ff <= 3'b0;
        end 
        else begin
            if (bus_clk_3m6_27 == 1) begin
                if (megarom_page_req == 1) begin
                    megarom_page_ff <= cpu_dout[2:0]; // select page
                end
            end
        end
    end




    /*
    reg [7:0] ff_flash_state = 8'd0;

    localparam STATE_RESET          = 8'd0;
    localparam STATE_READ_START     = 8'd1;
    localparam STATE_READ_WAIT      = 8'd2;
    localparam STATE_READ_LOOP      = 8'd3;
    localparam STATE_IDLE           = 8'd4;

    always @(posedge clk_54m, negedge bus_reset_n) begin
    if (bus_reset_n == 0) begin
        ff_flash_state = STATE_RESET;
        ff_flash_rd <= 0;
        flash_wait_n <= 1;
    end else
        case (ff_flash_state)
            STATE_RESET: begin   // reset
                ff_flash_state <= STATE_READ_START;
                ff_flash_rd <= 0;
                ff_flash_terminate <= 1;
            end
            STATE_READ_START: begin  // start read
                if (flash_busy == 0) begin
                    ff_flash_addr <= 24'h100000;
                    ff_flash_state = STATE_READ_WAIT;
                end
            end
            STATE_READ_WAIT: begin  // start read
                if (megarom_req == 1) begin
                    flash_wait_n <= 0;
                    ff_flash_addr <= megarom_addr ;
                    ff_flash_rd <= 1;
                    ff_flash_terminate <= 0;
                    ff_flash_state = STATE_READ_LOOP;
                end
            end
            STATE_READ_LOOP: begin  // loop read
                if (flash_busy == 0 && ff_flash_rd <= 0) begin
                    ff_rom_dout <= flash_dout; 
                    ff_flash_state <= STATE_IDLE;
                end
                else begin
                    ff_flash_rd <= 0;
                end
            end
            STATE_IDLE: begin  // idle
                flash_wait_n <= 1;
                ff_flash_terminate <= 1;
                if (megarom_req == 0) begin
                    ff_flash_state <= STATE_READ_START;
                end
            end
        endcase
    end*/


    //sd card
    localparam int SDC_SDATA		=  16'h7C00;		 	// rw: 7C00h-7Dff - sector transfer area
    localparam int SDC_ENABLE  	    =  16'h7E00;		    // wo: 1: enable SDC register, 0: disable
    localparam int SDC_CMD			=  SDC_ENABLE+1; 		// wo: cmd to SDC fpga: 1=sd read, 2=sd write
    localparam int SDC_STATUS		=  SDC_CMD+1;	 		// ro: SDC status bits
    localparam int SDC_SADDR		=  SDC_STATUS+1;	 	// wo: 4 bytes: sector addr for read/write
    localparam int SDC_C_SIZE  	    =  SDC_SADDR+4;			// ro: 3 bytes: device size blocks
    localparam int SDC_C_SIZE_MULT	=  SDC_C_SIZE+3;		// ro: 3 bits size multiplier
    localparam int SDC_RD_BL_LEN	=  SDC_C_SIZE_MULT+1;	// ro: 4 bits block length
    localparam int SDC_CTYPE		=  SDC_RD_BL_LEN+1;		// ro: SDC Card type: 0=unknown, 1=SDv1, 2=SDv2, 3=SDHCv2 
    localparam int SDC_MID		    =  SDC_CTYPE+1;		    // ro: manufacture ID: 8 bits unsigned
    localparam int SDC_OID		    =  SDC_MID+1;		    // ro: oem id: 2 character
    localparam int SDC_PNM		    =  SDC_OID+2;		    // ro: product name: 5 character
    localparam int SDC_PSN		    =  SDC_PNM+5;		    // ro: serial number: 32 bits unsigned
    localparam int SCC_ENABLE       =  16'h7E80;            // wo: enable disable SCC+
    localparam int SDC_END          =  16'h7EFF; 
    
    wire [8:0] sram_addr_w;
    reg ff_sram_we = 0;
    reg [7:0] ff_sram_cdin;
    reg [7:0] ff_sram_cdout;
    //
    reg ff_sd_en = 0;
    reg sram_cs_w;
    wire sram_busreq_w;
    wire [7:0] sram_cd_w;
    
    wire [3:0] sd_card_stat_w;
    wire [1:0] sd_card_type_w;
    reg ff_sd_rstart;
    reg ff_sd_init;
    reg [31:0] ff_sd_sector;
    wire sd_busy_w;
    wire sd_done_w;
    wire sd_outen_w;
    wire [8:0] sd_outaddr_w;
    wire [7:0] sd_outbyte_w;
    reg ff_sd_wstart;
    wire [7:0] sd_inbyte_w;
    
    wire [21:0] sd_c_size_w;
    wire [2:0] sd_c_size_mult_w;
    wire [3:0] sd_read_bl_len_w;
    
    wire [7:0] sd_mid_w;
    wire [15:0] sd_oid_w;
    wire [39:0] sd_pnm_w;
    wire [31:0] sd_psn_w;
    wire sd_crc_error_w;
    wire sd_timeout_error_w;
    //reg ff_scc_enable;
    //wire scc_enable_w;
    //assign scc_enable_w = ff_scc_enable;
    always @ (posedge clk_27m) begin
        sram_cs_w <= config_enable_sdcard == 1 && bus_reset_n && ff_sd_en && bus_iorq_n == 1 && bus_m1_n == 1 && bus_mreq_n == 0 && pri_slot_num[SD_SLOT] == 1 && exp_slotx_num[2] == 1 && ( bus_addr >= SDC_SDATA && bus_addr < SDC_ENABLE) ? 1 : 0;
    end
    assign sram_busreq_w = sram_cs_w && ~bus_rd_n;
    
    dpram#(
        .widthad_a(9),
        .width_a(8)
    ) dpram1 (
        .clock_a(clk_27m),
        .wren_a(bus_clk_3m6_27 && sram_cs_w && ~bus_wr_n),
        .rden_a(bus_clk_3m6_27 && sram_cs_w && ~bus_rd_n),
        .address_a(bus_addr[8:0]),
        .data_a(cpu_dout),
        .q_a(sram_cd_w),
    
        .clock_b(clk_27m),
        .wren_b(ff_sd_rstart && sd_outen_w),
        .rden_b(ff_sd_wstart && sd_outen_w),
        .address_b(sd_outaddr_w),
        .data_b(sd_outbyte_w),
        .q_b(sd_inbyte_w)
    );
    
    sd_reader #(
        .CLK_DIV(3'd2),
        .SIMULATE(0)
    ) sd1 (
        .rstn(bus_reset_n),
        .clk(clk_27m),
        .sdclk(sd_sclk),
        .sdcmd(sd_cmd),
        .sddat0(sd_dat0),                  
        .card_stat(sd_card_stat_w),        // show the sdcard initialize status
        .card_type(sd_card_type_w),        // 0=UNKNOWN    , 1=SDv1    , 2=SDv2  , 3=SDHCv2
        .rstart(ff_sd_rstart), 
        .rsector(ff_sd_sector),
        .rbusy(sd_busy_w),
        .rdone(sd_done_w),
        .outen(sd_outen_w),                // when outen=1, a byte of sector content is read out from outbyte
        .outaddr(sd_outaddr_w),            // outaddr from 0 to 511, because the sector size is 512
        .outbyte(sd_outbyte_w),            // a byte of sector content
        .wstart(ff_sd_wstart), 
        .inbyte(sd_inbyte_w),
        .c_size(sd_c_size_w),
        .c_size_mult(sd_c_size_mult_w),
        .read_bl_len(sd_read_bl_len_w),
        .mid(sd_mid_w),
        .oid(sd_oid_w),
        .pnm(sd_pnm_w),
        .psn(sd_psn_w),
        .crc_error(sd_crc_error_w),
        .timeout_error(sd_timeout_error_w),
        .init(ff_sd_init)
    );
    
    assign sd_dat1 = 1;
    assign sd_dat2 = 1;
    assign sd_dat3 = 1; // Must set sddat1~3 to 1 to avoid SD card from entering SPI mode
    
    
    always @(posedge clk_27m or negedge bus_reset_n) begin
        if (~bus_reset_n) begin
            ff_sd_en <= 0;
        end else begin
            if (config_enable_sdcard == 1 && pri_slot_num[SD_SLOT] == 1 && exp_slotx_num[2] == 1 && bus_addr == SDC_ENABLE && ~bus_wr_n && bus_iorq_n && bus_m1_n) 
                ff_sd_en <= cpu_dout[0];
        end
    end
    
    reg sd_cs_w;
    always @ (posedge clk_27m) begin
        sd_cs_w <= config_enable_sdcard == 1 && bus_reset_n && ff_sd_en && bus_iorq_n && bus_m1_n && bus_mreq_n == 0 && pri_slot_num[SD_SLOT] == 1 && exp_slotx_num[2] == 1 && (bus_addr >= SDC_ENABLE && bus_addr <= SDC_END) ? 1 : 0;
    end
    wire sd_busreq_w;
    assign sd_busreq_w = sd_cs_w && ~bus_rd_n;
    reg [7:0] ff_sd_cd;
    wire [7:0] sd_cd_w;
    assign sd_cd_w = ff_sd_cd;
    
    always @(posedge clk_27m or negedge bus_reset_n) begin
        if (~bus_reset_n) begin
            ff_sd_rstart <= '0;
            ff_sd_wstart <= '0;
            ff_sd_init <= '0;
        end else begin
            if (sd_done_w) begin
                ff_sd_rstart <= '0;
                ff_sd_wstart <= '0;
            end
    
            if (sd_cs_w) begin
                if (~bus_wr_n) begin
                    case(bus_addr) 
                        SDC_CMD: begin
                            ff_sd_rstart <= ff_sd_rstart | cpu_dout[0];
                            ff_sd_wstart <= ff_sd_wstart | cpu_dout[1];
                            ff_sd_init   <= ff_sd_init   | cpu_dout[7];
                            //ff_sms_init  <= ff_sms_init  | cdin_w[7];
                        end
                        SDC_SADDR+0:    ff_sd_sector[ 7: 0] <= cpu_dout;
                        SDC_SADDR+1:    ff_sd_sector[15: 8] <= cpu_dout;
                        SDC_SADDR+2:    ff_sd_sector[23:16] <= cpu_dout;
                        SDC_SADDR+3:    ff_sd_sector[31:24] <= cpu_dout;
                    endcase
                end else
                if (~bus_rd_n) begin
                    case(bus_addr) 
                        SDC_ENABLE:     ff_sd_cd <= { 7'b0, ff_sd_en };
                        SDC_STATUS:     ff_sd_cd <= { sd_busy_w, 5'b0, sd_timeout_error_w, sd_crc_error_w };
                        SDC_C_SIZE+0:   ff_sd_cd <= sd_c_size_w[7:0];
                        SDC_C_SIZE+1:   ff_sd_cd <= sd_c_size_w[15:8];
                        SDC_C_SIZE+2:   ff_sd_cd <= { 2'b0, sd_c_size_w[21:16] };
                        SDC_C_SIZE_MULT:ff_sd_cd <= { 5'b0, sd_c_size_mult_w };
                        SDC_RD_BL_LEN:  ff_sd_cd <= { 4'b0, sd_read_bl_len_w };
                        SDC_CTYPE:      ff_sd_cd <= { 6'b0, sd_card_type_w };
                        SDC_MID:        ff_sd_cd <= sd_mid_w;
                        SDC_OID+0:      ff_sd_cd <= sd_oid_w[7:0];
                        SDC_OID+1:      ff_sd_cd <= sd_oid_w[15:8];
                        SDC_PNM+0:      ff_sd_cd <= sd_pnm_w[7:0];
                        SDC_PNM+1:      ff_sd_cd <= sd_pnm_w[15:8];
                        SDC_PNM+2:      ff_sd_cd <= sd_pnm_w[23:16];
                        SDC_PNM+3:      ff_sd_cd <= sd_pnm_w[31:24];
                        SDC_PNM+4:      ff_sd_cd <= sd_pnm_w[39:32];
                        SDC_PSN+0:      ff_sd_cd <= sd_psn_w[7:0];
                        SDC_PSN+1:      ff_sd_cd <= sd_psn_w[15:8];
                        SDC_PSN+2:      ff_sd_cd <= sd_psn_w[23:16];
                        SDC_PSN+3:      ff_sd_cd <= sd_psn_w[31:24];
                        default:        ff_sd_cd <= '1;
                    endcase
                end
            end
        end
    end

`else

    wire sd_busreq_w;
    wire sram_busreq_w;
    wire megarom_req;
    wire megarom_page_req;
    wire sram_cs_w;
    wire sd_cs_w;

`endif

    // Switched I/O ports
    reg [1:0] Slot2Mode;
    wire  swio_req;
    wire [7:0] io42_id212;
    wire iSlt2_linear;
    wire swio_req;
    wire swio_req_r;
    wire swio_req_w;
    wire [7:0] swio_dout;
    assign swio_req_r = (config_enable_megaram == 1 && bus_addr[7:4] == 4'b0100 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_rd_n == 0)? 1:0;
    assign swio_req_w = (config_enable_megaram == 1 && bus_addr[7:4] == 4'b0100 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0)? 1:0;
    assign swio_req = swio_req_r | swio_req_w;

    switched_io_ports ocm_ports (
            .clk21m        (clk_27m),
            .reset         (~bus_reset_n) ,
            .power_on_reset(1),
            .req           (swio_req   ),
            .ack           (           ),
            .wrt           (~bus_wr_n ),
            .adr           (bus_addr   ),
            .dbi           (swio_dout     ),
            .dbo           (cpu_dout      ),
            .io42_id212    (io42_id212    ),
            .iSlt2_linear  (iSlt2_linear  )
        );

    // virtual DIP-SW assignment (2/2)
    always @ ( posedge clk_27m )  begin
        Slot2Mode[1]    <=  io42_id212[4];
        Slot2Mode[0]    <=  io42_id212[5];
    end

    wire send;
    monostable mono2 (
        .pulse_in(s2),
        .clock(clk_27m),
        .pulse_out(send)
    );

//    msx2p_debug debug1 (
//        .clk_27m(clk_27m),
//        .clk (clk_27m),
//        .reset_n ( bus_reset_n ),
//        .clk_enable (clk_enable_3m6_27),
//        .bus_addr(bus_addr),
//        .bus_data(cpu_din),
//        .bus_iorq_n(bus_iorq_n),
//        .bus_mreq_n(bus_mreq_n),
//        .bus_wr_n(bus_wr_n),
//        .send(send),
//        .uart_tx(usb_uart_tx),
//        .boot_ok( )
//    );

    // timing_debug debug1 removed for production: it registered high-fanout bus
    // strobes + a UART, costing area/routing at 91% CLS for a dev-only feature.
    // Re-add temporarily if bus timing needs probing over the USB-C UART.
    assign usb_uart_tx = 1'b1;      // UART idle

    // ===== STANDALONE MERGE: discrete status LEDs (active low) — from MSXnano =====
    // LED[5] TURBO: solid = turbo ON (~4.13MHz); blink (~1.8Hz) = real-MSX speed (also "alive"). LED[4] SD busy;
    // LED[3] joy0 fire B; LED[2] joy0 fire A; LED[1] joy0 any dir; LED[0] joy1 any input
    reg led_heartbeat = 1'b1;
    reg [19:0] led_cnt;
    always @(posedge clk_54m or negedge bus_reset_n) begin
        if (!bus_reset_n) begin
            led_cnt       <= 0;
            led_heartbeat <= 1'b1;
        end else if (clk_enable_3m6_54) begin
            if (led_cnt == 20'd999999) begin
                led_cnt       <= 0;
                led_heartbeat <= ~led_heartbeat;
            end else begin
                led_cnt <= led_cnt + 1;
            end
        end
    end

    assign led[5] = turbo ? 1'b0 : led_heartbeat;  // active-low: 0=solid lit (turbo ON), else heartbeat blink (real-MSX)
    assign led[4] = ~sd_busy_w;
    assign led[3] = ~joystick0[5];
    assign led[2] = ~joystick0[4];
    assign led[1] = ~(|joystick0[3:0]);
    assign led[0] = ~(|joystick1[5:0]);

    // ===== External WS2812B status strip (8 LEDs, e.g. CJMCU-2812-8) on the case =====
    // One data pin (ws2812_led) drives the whole chain; colours from internal state.
    wire caps_on  = ~ppi_port_c[6];                       // MSX CAPS LED (PPI port C bit6, active-low)
    wire kana_on  = keyboard[106];                        // CODE/KANA key held (Left Alt)
    wire joy_on   = (|joystick0[5:0]) | (|joystick1[5:0]);
    wire kbd_raw  = |keyboard;                            // any key held
    wire wifi_raw = ~uart_tx | ~uart_rx;                  // WiFi UART active (idle = high)

    wire disk_act, wifi_act, kbd_act;
    led_stretch #(.HOLD(1350000)) st_disk (.clk(clk_27m), .rst_n(bus_reset_n), .trig(sd_busy_w), .active(disk_act)); // ~50ms
    led_stretch #(.HOLD( 540000)) st_wifi (.clk(clk_27m), .rst_n(bus_reset_n), .trig(wifi_raw),  .active(wifi_act)); // ~20ms
    led_stretch #(.HOLD(1350000)) st_kbd  (.clk(clk_27m), .rst_n(bus_reset_n), .trig(kbd_raw),   .active(kbd_act));  // ~50ms

    // 8 colours in GRB (dim). LED0 = first in the chain (DIN side).
    wire [23:0] ws_c0 = 24'h180000;                          // 0 POWER  : solid green
    wire [23:0] ws_c1 = caps_on  ? 24'h180018 : 24'h000000;  // 1 CAPS   : cyan
    wire [23:0] ws_c2 = kana_on  ? 24'h002020 : 24'h000000;  // 2 KANA   : magenta
    wire [23:0] ws_c3 = disk_act ? 24'h102800 : 24'h000000;  // 3 DISK   : amber
    wire [23:0] ws_c4 = turbo    ? 24'h003000 : 24'h040000;  // 4 CPU    : turbo=red / normal=dim green
    wire [23:0] ws_c5 = wifi_act ? 24'h000030 : 24'h000000;  // 5 WiFi   : blue
    wire [23:0] ws_c6 = joy_on   ? 24'h202000 : 24'h000000;  // 6 JOY    : yellow
    wire [23:0] ws_c7 = kbd_act  ? 24'h181818 : 24'h000000;  // 7 KBD    : white flash

    ws2812 #(.NUM_LEDS(8), .CLK_FRE(27)) ws_strip (
        .clk   (clk_27m),
        .rst_n (bus_reset_n),
        .rgb   ({ws_c0, ws_c1, ws_c2, ws_c3, ws_c4, ws_c5, ws_c6, ws_c7}),
        .dout  (ws2812_led)
    );

    // ===== STANDALONE MERGE: USB host (BL616 FPGA Companion) — from MSXnano =====
    wire [127:0] keyboard;
    wire osd_strobe;
    wire osd_start;
    wire [7:0] osd_data;

    fpga_companion fpga_companion_inst
    (
        .clk (clk_27m),
        // Reset from PLL lock, NOT from the core reset. sysctrl lives in here and
        // holds the OSD's settings, so resetting it whenever the MSX resets makes
        // an OSD-driven reset impossible -- it would clear the very register
        // asserting it. NanoMig does the same (sysctrl .reset(!pll_lock)).
        // A side effect worth knowing: the companion link and the OSD's settings
        // now survive an MSX reset, which is the correct behaviour for a
        // peripheral anyway.
        .reset (~clock_locked),

        .m0s (m0s),

        .spi_sclk (spi_sclk),
        .spi_csn (spi_csn),
        .spi_dir (),            // pin 75 reassigned to DB9 fire-2 (see port list)
        .spi_dat (spi_dat),
        .spi_irqn (spi_irqn),

        .keyboard (keyboard),
        .joystick0 (joystick0),
        .joystick0_console (),
        .joystick1 (joystick1),
        .ws2812_color (),   // LEDs are discrete; WS2812 not used

        .osd_strobe (osd_strobe),
        .osd_start  (osd_start),
        .osd_data   (osd_data),

        .system_reset       (system_reset),
        .system_turbo       (system_turbo),
        .system_turbo_boot  (system_turbo_boot),
        .system_scanlines   (system_scanlines),
        .system_wide_screen (system_wide_screen),
        .system_stereo      (system_stereo),
        .system_second_scc  (system_second_scc),
        .system_volume      (system_volume),
        .system_pal         (system_pal),
        .system_keyboard    (system_keyboard_sel),
        .system_db9_port    (system_db9_port),
        .system_autofire    (system_autofire),
        .system_save        (system_save)
    );

    usb_keyboard_msx usb_keyboard_msx
    (
        .CLK (clk_27m),
        .RESET (~bus_reset_n),

        .keyboard (keyboard),
        .A (keyboard_addr),
        .DO (keyboard_data),
        .FN (function_keys)
    );

endmodule