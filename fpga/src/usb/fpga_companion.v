module fpga_companion (
    input        clk,
    input        reset,

    // interface to external FPGA companion
    inout [4:0]	m0s,
    // and internal
    input	spi_sclk,
    input	spi_csn,
    output	spi_dir,
    input	spi_dat,
    output	spi_irqn,

    //USB keyboard data
    output [127:0] keyboard,
    output [7:0] joystick0,
    output [7:0] joystick0_console,
    output [7:0] joystick1,
    output [23:0] ws2812_color,

    // OSD channel (SPI target 2) forwarded to the video path, where
    // osd_u8g2 keeps the framebuffer and composites it onto the picture
    output       osd_strobe,
    output       osd_start,
    output [7:0] osd_data,

    // values set by the user in the OSD (sysctrl CMD 4). Ids and meanings
    // are documented in msxnano.xml -- keep the two in step.
    output [1:0] system_reset,
    output       system_turbo,
    output       system_turbo_boot,
    output       system_scanlines,
    output       system_wide_screen,
    output       system_stereo,
    output       system_second_scc,
    output [2:0] system_volume,
    output       system_pal,
    output [1:0] system_keyboard,
    output       system_db9_port,
    output [1:0] system_autofire
);

wire mcu_hid_strobe;
wire mcu_sys_strobe;
wire mcu_osd_strobe;
wire mcu_sdc_strobe;

wire mcu_start;
wire spi_intn;
wire [7:0] mcu_data_out;

// hand the OSD byte stream out to the video path. mcu_osd_din stays 0:
// the OSD is write-only from the MCU, nothing is ever read back from it.
assign osd_strobe = mcu_osd_strobe;
assign osd_start  = mcu_start;
assign osd_data   = mcu_data_out;
wire [7:0] sys_data_out;
wire [7:0] hid_data_out;

//assign m0s[4] = spi_intn;

// -------------------------- M0S MCU interface -----------------------
// intn and dout are outputs driven by the FPGA to the MCU
// din, ss and clk are inputs coming from the MCU
// onboard connection to on-board BL616

assign spi_dir = spi_io_dout;
assign m0s[4:0] = { spi_intn, 3'bzzz, spi_io_dout };
assign spi_irqn = spi_intn;

// by default the internal SPI is being used. Once there is
// a select from the external spi, then the connection is
// being switched
reg spi_ext;
always @(posedge clk) begin
    if(reset)
        spi_ext = 1'b0;
    else begin
        // spi_ext is activated once the m0s pins 2 (ss or csn) is
        // driven low by the m0s dock. This means that a m0s dock
        // is connected and the FPGA switches its inputs to the
        // m0s. Until then the inputs of the internal BL616 are
        // being used.
        if(m0s[2] == 1'b0)
            spi_ext = 1'b1;
    end
end

// switch between internal SPI connected to the on-board bl616
// or to the external one possibly connected to a M0S Dock
wire spi_io_din = spi_ext?m0s[1]:spi_dat;
wire spi_io_ss = spi_ext?m0s[2]:spi_csn;
wire spi_io_clk = spi_ext?m0s[3]:spi_sclk;

mcu_spi mcu (
        .clk(clk),
        .reset(reset),

        .spi_io_ss(spi_io_ss),
        .spi_io_clk(spi_io_clk),
        .spi_io_din(spi_io_din),
        .spi_io_dout(spi_io_dout),

        .mcu_sys_strobe(mcu_sys_strobe),
        .mcu_hid_strobe(mcu_hid_strobe),
        .mcu_osd_strobe(mcu_osd_strobe),
        .mcu_sdc_strobe(mcu_sdc_strobe),
        .mcu_start(mcu_start),
        .mcu_dout(mcu_data_out),
        .mcu_sys_din(sys_data_out),
        .mcu_hid_din(hid_data_out),
        .mcu_osd_din(8'b00000000),
        .mcu_sdc_din(8'b00000000)
        );

wire [7:0] int_ack;
wire hid_int;
wire hid_iack = int_ack[1];

hid hid_inst (
        .clk(clk),
        .reset(reset),

         // interface to receive user data from MCU (mouse, kbd, ...)
        .data_in_strobe(mcu_hid_strobe),
        .data_in_start(mcu_start),
        .data_in(mcu_data_out),
        .data_out(hid_data_out),

        // input local db9 port events to be sent to MCU. Changes also trigger
        // an interrupt, so the MCU doesn't have to poll for joystick events
        //.db9_port( db9_joy ),
        .irq( hid_int ),
        .iack( hid_iack ),

        //.mouse(hid_mouse),
        .keyboard(keyboard),
        .joystick0(joystick0),
        .joystick0_console(joystick0_console),
        .joystick1(joystick1)
         );   


sysctrl sysctrl (
        .clk(clk),
        .reset(reset),

         // interface to send and receive generic system control
        .data_in_strobe(mcu_sys_strobe),
        .data_in_start(mcu_start),
        .data_in(mcu_data_out),
        .data_out(sys_data_out),

        
        .int_out_n(spi_intn),
        .int_in( { 4'b0000, 1'b0, 1'b0, hid_int, 1'b0 }),
        .int_ack( int_ack ),

        .buttons( {1'b0, 1'b0} ),
        .leds(system_leds),
        .color(ws2812_color),

        .system_reset(system_reset),
        .system_turbo(system_turbo),
        .system_turbo_boot(system_turbo_boot),
        .system_scanlines(system_scanlines),
        .system_wide_screen(system_wide_screen),
        .system_stereo(system_stereo),
        .system_second_scc(system_second_scc),
        .system_volume(system_volume),
        .system_pal(system_pal),
        .system_keyboard(system_keyboard),
        .system_db9_port(system_db9_port),
        .system_autofire(system_autofire)
         );   

endmodule