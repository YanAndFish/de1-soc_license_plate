// (C) 1992-2018 Intel Corporation.                            
// Intel, the Intel logo, Intel, MegaCore, NIOS II, Quartus and TalkBack words    
// and logos are trademarks of Intel Corporation or its subsidiaries in the U.S.  
// and/or other countries. Other marks and brands may be claimed as the property  
// of others. See Trademarks on intel.com for full list of Intel trademarks or    
// the Trademarks & Brands Names Database (if Intel) or See www.Intel.com/legal (if Altera) 
// Your use of Intel Corporation's design tools, logic functions and other        
// software and tools, and its AMPP partner logic functions, and any output       
// files any of the foregoing (including device programming or simulation         
// files), and any associated documentation or information are expressly subject  
// to the terms and conditions of the Altera Program License Subscription         
// Agreement, Intel MegaCore Function License Agreement, or other applicable      
// license agreement, including, without limitation, that your use is for the     
// sole purpose of programming logic devices manufactured by Intel and sold by    
// Intel or its authorized distributors.  Please refer to the applicable          
// agreement for further details.                                                 

module top (
	fpga_clk_50,
  	fpga_reset_n,
  	fpga_led_output,
  
 	memory_mem_a,
  	memory_mem_ba,
  	memory_mem_ck,
  	memory_mem_ck_n,
  	memory_mem_cke,
  	memory_mem_cs_n,
  	memory_mem_ras_n,
  	memory_mem_cas_n,
  	memory_mem_we_n,
  	memory_mem_reset_n,
  	memory_mem_dq,
  	memory_mem_dqs,
  	memory_mem_dqs_n,
  	memory_mem_odt,
  	memory_mem_dm,
  	memory_oct_rzqin,
  
  	emac_mdio,
	emac_mdc,
	emac_tx_ctl,
	emac_tx_clk,
	emac_txd,
  	emac_rx_ctl,
	emac_rx_clk,
  	emac_rxd,

  	sd_cmd,
  	sd_clk,
  	sd_d,
  	uart_rx,
  	uart_tx,
  	led,
  	i2c_sda,
  	i2c_scl,

  	fpga_memory_mem_a,
	fpga_memory_mem_ba,
	fpga_memory_mem_ck,
	fpga_memory_mem_ck_n,
	fpga_memory_mem_cke,
	fpga_memory_mem_cs_n,
	fpga_memory_mem_dm,
	fpga_memory_mem_ras_n,
	fpga_memory_mem_cas_n,
	fpga_memory_mem_we_n,
	fpga_memory_mem_reset_n,
	fpga_memory_mem_dq,
	fpga_memory_mem_dqs,
	fpga_memory_mem_dqs_n,
	fpga_memory_mem_odt,
	fpga_memory_oct_rzqin
);

  input  wire 		fpga_clk_50;
  input  wire 		fpga_reset_n;
  output wire [3:0] 	fpga_led_output;
  
  output wire [14:0] 	memory_mem_a;
  output wire [2:0] 	memory_mem_ba;
  output wire 		memory_mem_ck;
  output wire 		memory_mem_ck_n;
  output wire 		memory_mem_cke;
  output wire 		memory_mem_cs_n;
  output wire 		memory_mem_ras_n;
  output wire 		memory_mem_cas_n;
  output wire 		memory_mem_we_n;
  output wire 		memory_mem_reset_n;
  inout  wire [39:0] 	memory_mem_dq;
  inout  wire [4:0] 	memory_mem_dqs;
  inout  wire [4:0] 	memory_mem_dqs_n;
  output wire 		memory_mem_odt;
  output wire [4:0] 	memory_mem_dm;
  input  wire 		memory_oct_rzqin;

  inout  wire 		emac_mdio;
  output wire 		emac_mdc;
  output wire 		emac_tx_ctl;
  output wire 		emac_tx_clk;
  output wire [3:0] 	emac_txd;
  input  wire 		emac_rx_ctl;
  input  wire 		emac_rx_clk;
  input  wire [3:0] 	emac_rxd;

  inout  wire 		sd_cmd;
  output wire 		sd_clk;
  inout  wire [3:0] 	sd_d;
  input  wire 		uart_rx;
  output wire 		uart_tx;
  inout  wire [3:0] 	led;
  inout  wire 		i2c_scl;
  inout  wire 		i2c_sda;

  output wire [14:0] 	fpga_memory_mem_a;
  output wire [2:0] 	fpga_memory_mem_ba;
  output wire 		fpga_memory_mem_ck;
  output wire 		fpga_memory_mem_ck_n;
  output wire 		fpga_memory_mem_cke;
  output wire 		fpga_memory_mem_cs_n;
  output wire [3:0] 	  fpga_memory_mem_dm;
//  output wire [1:0] 	fpga_memory_mem_dm;
  output wire 		fpga_memory_mem_ras_n;
  output wire 		fpga_memory_mem_cas_n;
  output wire 		fpga_memory_mem_we_n;
  output wire 		fpga_memory_mem_reset_n;
  inout wire [31:0] 	  fpga_memory_mem_dq;
//  inout  wire [15:0] 	fpga_memory_mem_dq;
  inout wire [3:0] 	  fpga_memory_mem_dqs;
//  inout  wire [1:0] 	fpga_memory_mem_dqs;
  inout wire [3:0] 	  fpga_memory_mem_dqs_n;
//  inout  wire [1:0] 	fpga_memory_mem_dqs_n;
  output wire 		fpga_memory_mem_odt;
  input  wire 		fpga_memory_oct_rzqin;

// wires for conduits
  wire        	fpga_sdram_status_local_init_done;
  wire        	fpga_sdram_status_local_cal_success;
  wire        	fpga_sdram_status_local_cal_fail;

  wire	[29:0]	fpga_internal_led;
  wire		kernel_clk;

  system the_system (
	.reset_50_reset_n                    			(fpga_reset_n),
	.clk_50_clk                          			(fpga_clk_50),
        .kernel_clk_clk						(kernel_clk),
	.memory_mem_a                        			(memory_mem_a),
	.memory_mem_ba                       			(memory_mem_ba),
	.memory_mem_ck                       			(memory_mem_ck),
	.memory_mem_ck_n                     			(memory_mem_ck_n),
	.memory_mem_cke                      			(memory_mem_cke),
	.memory_mem_cs_n                     			(memory_mem_cs_n),
	.memory_mem_ras_n                    			(memory_mem_ras_n),
	.memory_mem_cas_n                    			(memory_mem_cas_n),
	.memory_mem_we_n                     			(memory_mem_we_n),
	.memory_mem_reset_n                  			(memory_mem_reset_n),
	.memory_mem_dq                       			(memory_mem_dq),
	.memory_mem_dqs                      			(memory_mem_dqs),
	.memory_mem_dqs_n                    			(memory_mem_dqs_n),
	.memory_mem_odt                      			(memory_mem_odt),
	.memory_mem_dm                       			(memory_mem_dm),
	.memory_oct_rzqin                    			(memory_oct_rzqin),
    	.peripheral_hps_io_emac0_inst_MDIO   			(emac_mdio),
    	.peripheral_hps_io_emac0_inst_MDC    			(emac_mdc),
    	.peripheral_hps_io_emac0_inst_TX_CLK 			(emac_tx_clk),
    	.peripheral_hps_io_emac0_inst_TX_CTL 			(emac_tx_ctl),
    	.peripheral_hps_io_emac0_inst_TXD0   			(emac_txd[0]),
    	.peripheral_hps_io_emac0_inst_TXD1   			(emac_txd[1]),
    	.peripheral_hps_io_emac0_inst_TXD2   			(emac_txd[2]),
    	.peripheral_hps_io_emac0_inst_TXD3   			(emac_txd[3]),
    	.peripheral_hps_io_emac0_inst_RX_CLK 			(emac_rx_clk),
    	.peripheral_hps_io_emac0_inst_RX_CTL 			(emac_rx_ctl),
    	.peripheral_hps_io_emac0_inst_RXD0   			(emac_rxd[0]),
    	.peripheral_hps_io_emac0_inst_RXD1   			(emac_rxd[1]),
    	.peripheral_hps_io_emac0_inst_RXD2   			(emac_rxd[2]),
    	.peripheral_hps_io_emac0_inst_RXD3   			(emac_rxd[3]),
    	.peripheral_hps_io_sdio_inst_CMD     			(sd_cmd),
    	.peripheral_hps_io_sdio_inst_CLK     			(sd_clk),
    	.peripheral_hps_io_sdio_inst_D0      			(sd_d[0]),
    	.peripheral_hps_io_sdio_inst_D1      			(sd_d[1]),
    	.peripheral_hps_io_sdio_inst_D2      			(sd_d[2]),
    	.peripheral_hps_io_sdio_inst_D3      			(sd_d[3]),
    	.peripheral_hps_io_uart0_inst_RX     			(uart_rx),
    	.peripheral_hps_io_uart0_inst_TX     			(uart_tx),
    	.peripheral_hps_io_gpio_inst_GPIO41  			(led[3]),
    	.peripheral_hps_io_gpio_inst_GPIO42  			(led[2]),
    	.peripheral_hps_io_gpio_inst_GPIO43  			(led[1]),
    	.peripheral_hps_io_gpio_inst_GPIO44  			(led[0]),
	.peripheral_hps_io_i2c0_inst_SDA     			(i2c_sda),
	.peripheral_hps_io_i2c0_inst_SCL     			(i2c_scl), 
    	.fpga_memory_mem_a                   			(fpga_memory_mem_a),
	.fpga_memory_mem_ba                  			(fpga_memory_mem_ba),
	.fpga_memory_mem_ck                  			(fpga_memory_mem_ck),
	.fpga_memory_mem_ck_n                			(fpga_memory_mem_ck_n),
	.fpga_memory_mem_cke                 			(fpga_memory_mem_cke),
	.fpga_memory_mem_cs_n                			(fpga_memory_mem_cs_n),
	.fpga_memory_mem_dm                  			(fpga_memory_mem_dm),
	.fpga_memory_mem_ras_n               			(fpga_memory_mem_ras_n),
	.fpga_memory_mem_cas_n               			(fpga_memory_mem_cas_n),
	.fpga_memory_mem_we_n                			(fpga_memory_mem_we_n),
	.fpga_memory_mem_reset_n             			(fpga_memory_mem_reset_n),
	.fpga_memory_mem_dq                  			(fpga_memory_mem_dq),
	.fpga_memory_mem_dqs                 			(fpga_memory_mem_dqs),
	.fpga_memory_mem_dqs_n               			(fpga_memory_mem_dqs_n),
	.fpga_memory_mem_odt                 			(fpga_memory_mem_odt),
	.fpga_memory_oct_rzqin               			(fpga_memory_oct_rzqin),
  	.fpga_sdram_status_local_init_done   			(fpga_sdram_status_local_init_done),
	.fpga_sdram_status_local_cal_success 			(fpga_sdram_status_local_cal_success),
	.fpga_sdram_status_local_cal_fail    			(fpga_sdram_status_local_cal_fail)
  );
 
  // module for visualizing the kernel clock with 4 LEDs
  async_counter_30 AC30 (
        .clk 	(kernel_clk),
        .count	(fpga_internal_led)
    );
  assign fpga_led_output[3:0] = ~fpga_internal_led[29:26];  

endmodule



module async_counter_30(clk, count);
  input			clk;
  output 	[29:0]	count;
  reg		[14:0] 	count_a;
  reg           [14:0]  count_b;  

  initial count_a = 15'b0;
  initial count_b = 15'b0;

always @(negedge clk)
	count_a <= count_a + 1'b1;

always @(negedge count_a[14])
	count_b <= count_b + 1'b1;

assign count = {count_b, count_a};

endmodule



