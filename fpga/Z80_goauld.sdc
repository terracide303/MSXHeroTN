//Copyright (C)2014-2023 GOWIN Semiconductor Corporation.
//All rights reserved.
//File Title: Timing Constraints file
//GOWIN Version: 1.9.9 Beta-4
//Created Time: 2023-10-11 15:41:18
create_clock -name clock_reset -period 277.778 -waveform {0 138.889} [get_nets {bus_reset_n}] -add
create_clock -name clock_audio -period 277.778 -waveform {0 138.889} [get_nets {vdp4/clk_audio}] -add
//create_clock -name clock_VideoDLClk -period 37.037 -waveform {0 18.518} [get_nets {VideoDLClk}] -add
//create_clock -name clock_3m6 -period 277.778 -waveform {0 138.889} [get_nets {bus_clk_3m6}] -add
//create_clock -name clock_27m -period 37.037 -waveform {0 18.518} [get_ports {ex_clk_27m}] -add
create_clock -name clock_27m -period 37.037 -waveform {0 18.518} [get_nets {clk_27m}] -add
create_generated_clock -name clock_54m -source [get_nets {clk_27m}] -master_clock clock_27m -multiply_by 2 [get_nets {clk_54m}] -add //[get_nets {clk_108m}] -add
create_generated_clock -name clock_108m -source [get_nets {clk_27m}] -master_clock clock_27m -multiply_by 4 [get_ports {O_sdram_clk}] -add //[get_nets {clk_108m}] -add
create_generated_clock -name clock_108i -source [get_nets {clk_27m}] -master_clock clock_27m -multiply_by 4 [get_pins {clk_main/rpll_inst/CLKOUT}] -add
create_generated_clock -name clock_VideoDHClk -source [get_nets {clk_27m}] -master_clock clock_27m -divide_by 2 [get_nets {VideoDHClk}] -add
create_generated_clock -name clock_VideoDLClk -source [get_nets {clk_27m}] -master_clock clock_27m -divide_by 4 [get_nets {VideoDLClk}] -add
set_clock_groups -asynchronous -group [get_clocks {clock_108m clock_108i clock_54m clock_VideoDHClk clock_VideoDLClk clock_27m }] -group [get_clocks {clock_reset }] -group [get_clocks {clock_env_reset clock_env_reset2 }]
// FPGA-Companion SPI CDC (mcu_spi_new.v): spi_data_in is written in the BL616 SPI-clock
// domain and only captured into spi_target/spi_in_data after a 2-FF-synchronized ready
// flag, so the data is stable for many clk_54m cycles around capture (handshake-safe).
// The return path (in_byte/dout mux -> spi_io_dout) is likewise stable before the BL616
// clocks it out. STA cannot see the handshake -> exclude these specific paths.
// launch FFs (spi_data_in) addressed BY PIN: their clock (BL616 SPI) is not a
// constrained system clock, so -from clock matching would never hit them.
set_false_path -from [get_pins {fpga_companion_inst/mcu/spi_data_in?*?/?*}] -to [get_pins {fpga_companion_inst/mcu/spi_target?*?/?*}]
set_false_path -from [get_pins {fpga_companion_inst/mcu/spi_data_in?*?/?*}] -to [get_pins {fpga_companion_inst/mcu/spi_in_data?*?/?*}]
// async flag entering its 2-FF synchronizer (readyD) -- canonical false path
set_false_path -from [get_pins {fpga_companion_inst/mcu/spi_data_in_ready?*?/?*}] -to [get_pins {fpga_companion_inst/mcu/spi_data_in_readyD?*?/?*}]
// into the SPI-clock capture FFs (spi_data_in): data comes from pads muxed by the
// quasi-static spi_ext dock selector; capture clock is the slow BL616 SPI clock.
set_false_path -from [get_clocks {clock_54m}] -to [get_pins {fpga_companion_inst/mcu/spi_data_in?*?/?*}]
set_false_path -from [get_clocks {clock_27m}] -to [get_pins {fpga_companion_inst/mcu/spi_data_in?*?/?*}]
set_false_path -from [get_pins {fpga_companion_inst/spi_ext?*?/?*}] -to [get_pins {fpga_companion_inst/mcu/spi_data_in?*?/?*}]
set_false_path -from [get_pins {fpga_companion_inst/spi_ext?*?/?*}] -to [get_pins {fpga_companion_inst/mcu/spi_sr_in?*?/?*}]
set_false_path -from [get_clocks {clock_54m}] -to [get_pins {fpga_companion_inst/mcu/spi_io_dout?*?/?*}]
set_false_path -from [get_clocks {clock_27m}] -to [get_pins {fpga_companion_inst/mcu/spi_io_dout?*?/?*}]

set_multicycle_path -from [get_clocks {clock_54m}] -to [get_pins {cpu1/?*?/D}] -setup -end 2
set_multicycle_path -from [get_clocks {clock_54m}] -to [get_pins {cpu1/u0/Regs/?*?/?*}] -setup -end 2
set_multicycle_path -from [get_clocks {clock_54m}] -to [get_pins {cpu1/u0/?*?/?*}] -setup -end 2
set_multicycle_path -from [get_clocks {clock_54m}] -to [get_pins {cpu1/u0/?*?/D}] -setup -end 2
set_multicycle_path -from [get_clocks {clock_54m}] -to [get_pins {cpu1/u0/?*?/CE}] -setup -end 2
set_multicycle_path -from [get_clocks {clock_54m}] -to [get_pins {cpu1/?*?/CE}] -setup -end 2
set_multicycle_path -from [get_clocks {clock_54m}] -to [get_pins {cpu1/u0/Regs/RegsL_RegsL*/DI*}] -setup -end 2

set_multicycle_path -from [get_clocks {clock_54m}] -to [get_pins {cpu1/?*?/D}] -hold -end 2
set_multicycle_path -from [get_clocks {clock_54m}] -to [get_pins {cpu1/u0/Regs/?*?/?*}] -hold -end 2
set_multicycle_path -from [get_clocks {clock_54m}] -to [get_pins {cpu1/u0/?*?/?*}] -hold -end 2
set_multicycle_path -from [get_clocks {clock_54m}] -to [get_pins {cpu1/u0/?*?/D}] -hold -end 2
set_multicycle_path -from [get_clocks {clock_54m}] -to [get_pins {cpu1/u0/?*?/CE}] -hold -end 2
set_multicycle_path -from [get_clocks {clock_54m}] -to [get_pins {cpu1/?*?/CE}] -hold -end 2
set_multicycle_path -from [get_clocks {clock_54m}] -to [get_pins {cpu1/u0/Regs/RegsL_RegsL*/DI*}] -hold -end 2

//ENABLE_SOUND
    create_clock -name clock_env_reset -period 277.778 -waveform {0 138.889} [get_nets {psg1/env_reset}] -add
    set_false_path -from [get_clocks {clock_27m}] -to [get_pins {psg1/?*?/?*}]
    set_false_path -from [get_clocks {clock_54m}] -to [get_pins {psg1/?*?/?*}]
    set_false_path -from [get_clocks {clock_54m}] -to [get_pins {opll/?*?/?*?/CE}]
    // second PSG: same internal env_reset gated clock + same exemptions as psg1
    create_clock -name clock_env_reset2 -period 277.778 -waveform {0 138.889} [get_nets {psg2/env_reset}] -add
    set_false_path -from [get_clocks {clock_27m}] -to [get_pins {psg2/?*?/?*}]
    set_false_path -from [get_clocks {clock_54m}] -to [get_pins {psg2/?*?/?*}]

set_false_path -from [get_clocks {clock_108m}] -to [get_pins {rtc1/?*?/?*}]
set_false_path -from [get_clocks {clock_54m}] -to [get_pins {rtc1/?*?/?*}]
set_false_path -from [get_clocks {clock_54m}] -to [get_pins {rtc1/u_mem/?*?/?*}]
// kanji1: same situation as rtc1 -- I/O-port device (D8-DBh) whose req/data are held
// stable for the whole (slow) Z80 I/O cycle; registered at clk_27m.
set_false_path -from [get_clocks {clock_54m}] -to [get_pins {kanji1/?*?/?*}]
set_false_path -from [get_clocks {clock_54m}] -to [get_pins {ocm_ports/?*?/CE}]
set_false_path -from [get_clocks {clock_54m}] -to [get_pins {ocm_ports/?*?/D}]
//set_false_path -from [get_clocks {clock_54m}] -to [get_pins {debug1/?*?/?*?/D}]   // debug1 removed (production)
//set_false_path -from [get_clocks {clock_54m}] -to [get_pins {debug1/?*?/?*?/CE}]  // debug1 removed (production)
set_false_path -from [get_clocks {clock_27m}] -to [get_pins {vdp4/hdmi_ntsc/true_hdmi_output.packet_picker/audio_sample_word_transfer?*?/D}]
set_false_path -from [get_clocks {clock_108m}] -to [get_pins {vdp4/u_v9958/U_SPRITE/SPRENDERPLANES*/CE}]
set_false_path -from [get_clocks {clock_108m}] -to [get_pins {vdp4/u_v9958/U_SPRITE/FF_SP_OVERMAP*/CE}]
set_false_path -from [get_clocks {clock_108m}] -to [get_pins {vdp4/u_v9958/U_SPRITE/FF_Y_TEST*/CE}]
set_false_path -from [get_clocks {clock_108m}] -to [get_pins {vdp4/u_v9958/U_SPRITE/FF_Y_TEST*/D}]
//uwifi muestrea senales del bus Z80 (IORQ/WR, estables ~280ns) a 27MHz: la
//relacion de medio periodo 54F->27R es pesimista para senales cuasi-estaticas
//uwifi only exists when `ENABLE_WIFI is defined in top.v; PnR errors on these
//otherwise since the pins don't exist in the netlist. Re-enable alongside it.
//set_false_path -from [get_clocks {clock_54m}] -to [get_pins {uwifi/wait_o*/CE}]
//set_false_path -from [get_clocks {clock_54m}] -to [get_pins {uwifi/my_tx_state*/CE}]
set_false_path -from [get_clocks {clock_108m}] -to [get_pins {vdp4/u_v9958/U_SPRITE/FF_Y_TEST_LISTUP_ADDR_*/D}]
set_false_path -from [get_clocks {clock_108m}] -to [get_pins {vdp4/u_v9958/U_SPRITE/FF_Y_TEST_LISTUP_ADDR_*/CE}]



//set_max_delay -from [get_clocks {clock_108m}] -to [get_pins {xffl_s0/D}] 9.6
//set_max_delay -from [get_clocks {clock_108m}] -to [get_pins {cpu_din_*/D}] 30.0
set_max_delay -from [get_clocks {clock_54m}] -to [get_pins {cpu_din_*/D}] 18.2
//set_max_delay -from [get_clocks {clock_54m}] -to [get_pins {mem1/sdram_seq*/D}] 10.5
//set_max_delay -from [get_clocks {clock_54m}] -to [get_pins {mem1/sdram_seq*/CE}] 10.5
//set_max_delay -from [get_clocks {clock_27m}] -to [get_pins {SdrAdr_*/D}] 16.5
//set_max_delay -from [get_clocks {clock_27m}] -to [get_pins {SdrBa_*/D}] 20.0
//set_max_delay -from [get_clocks {clock_27m}] -to [get_pins {SdrUdq_*/D}] 20.0
//set_max_delay -from [get_clocks {clock_27m}] -to [get_pins {SdrLdq_*/D}] 20.0
//set_max_delay -from [get_clocks {clock_27m}] -to [get_pins {RamDbi_*/D}] 16.5
//set_max_delay -from [get_clocks {clock_27m}] -to [get_pins {VrmDbi2_*/D}] 16.5
//set_max_delay -from [get_clocks {clock_27m}] -to [get_pins {VrmDbi2_*/Q}] 16.5
set_max_delay -from [get_pins {mem1/vram_dout_*/Q}] -to [get_clocks {clock_27m}] 10.5
//set_max_delay -from [get_clocks {clock_108m}] -to [get_pins {memory_ctrl/enable_read_seq*/D}] 11.0
//set_max_delay -from [get_clocks {clock_108m}] -to [get_pins {memory_ctrl/enable_write_seq*/D}] 11.0
//set_max_delay -from [get_clocks {clock_108m}] -to [get_pins {memory_ctrl/vram/u_sdram/FF_SDRAM_A*/D}] 12.0
//set_max_delay -from [get_clocks {clock_108m}] -to [get_pins {memory_ctrl/vram/u_sdram/FF_SDRAM_BA*/D}] 12.0
//set_max_delay -from [get_clocks {clock_108m}] -to [get_pins {memory_ctrl/vram/u_sdram/FF_SDRAM_DQM*/D}] 12.0

//set_false_path -from [get_clocks {clock_108m}] -to [get_pins {debug/?*?/CE}]
//set_false_path -from [get_clocks {clock_27m}] -to [get_pins {debug/?*?/CE}]
//set_false_path -from [get_clocks {clock_108m}] -to [get_pins {debug/?*?/D}]
//set_false_path -from [get_clocks {clock_27m}] -to [get_pins {debug/?*?/D}]

set_multicycle_path -from [get_clocks {clock_54m}] -to [get_pins {ff_sd_cd_*/D}] -setup -end 2
set_multicycle_path -from [get_clocks {clock_54m}] -to [get_pins {ff_sd_cd_*/D}] -hold -end 2
set_multicycle_path -from [get_clocks {clock_54m}] -to [get_pins {ff_sd_sector_*/CE}] -setup -end 2
set_multicycle_path -from [get_clocks {clock_54m}] -to [get_pins {ff_sd_sector_*/CE}] -hold -end 2
set_multicycle_path -from [get_clocks {clock_54m}] -to [get_pins {ff_sd_cd_*/CE}] -setup -end 2
set_multicycle_path -from [get_clocks {clock_54m}] -to [get_pins {ff_sd_cd_*/CE}] -hold -end 2

report_timing -setup -max_paths 400 -max_common_paths 1
