//============================================================================
//  Arcade: Spy Hunter
//
//  Port to MiSTer
//  Copyright (C) 2019 Sorgelig
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [45:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        VGA_CLK,

	//Multiple resolutions are supported using different VGA_CE rates.
	//Must be based on CLK_VIDEO
	output        VGA_CE,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,

	//Base video clock. Usually equals to CLK_SYS.
	output        HDMI_CLK,

	//Multiple resolutions are supported using different HDMI_CE rates.
	//Must be based on CLK_VIDEO
	output        HDMI_CE,

	output  [7:0] HDMI_R,
	output  [7:0] HDMI_G,
	output  [7:0] HDMI_B,
	output        HDMI_HS,
	output        HDMI_VS,
	output        HDMI_DE,   // = ~(VBlank | HBlank)
	output  [1:0] HDMI_SL,   // scanlines fx

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output  [7:0] HDMI_ARX,
	output  [7:0] HDMI_ARY,

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,    // 1 - signed audio samples, 0 - unsigned

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE, 

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT
);

assign VGA_F1    = 0;
assign USER_OUT  = '1;
assign LED_USER  = ioctl_download;
assign LED_DISK  = 0;
assign LED_POWER = 0;

//assign HDMI_ARX = status[1] ? 8'd16 : status[2] ? 8'd4 : 8'd3;
//assign HDMI_ARY = status[1] ? 8'd9  : status[2] ? 8'd3 : 8'd4;
assign HDMI_ARX = status[1] ? 8'd16 : status[2] ? 8'd21 : 8'd20;
assign HDMI_ARY = status[1] ? 8'd9  : status[2] ? 8'd20 : 8'd21;

`include "build_id.v" 
localparam CONF_STR = {
	"A.RAMPAGE;;",
	"H0O1,Aspect Ratio,Original,Wide;",
	"H0O2,Orientation,Vert,Horz;",
	"O35,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"-;",
	"OA,Accelerator,Digital,Analog;",
	"OB,Steering,Digital,Analog;",
	"-;",
	"O6,Service,Off,On;",
	"O8,Demo Sounds,Off,On;",
	"O9,Show Lamps,Off,On;",
        "OD,Deinterlacer,Off,On;",
	"-;",
	"R0,Reset;",
	"J1,Machine Gun,Missiles,Smoke Screen,Oil Slick,Weapon Truck,Gear Shift,Coin;",
	"jn,A,B,X,Y,L,R,Start;",
	"V,v",`BUILD_DATE
};

////////////////////   CLOCKS   ///////////////////

wire clk_sys,clk_80M;
wire clk_mem = clk_80M;
wire pll_locked;

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys), // 40M
	.outclk_1(clk_80M), // 80M
	.locked(pll_locked)
);

///////////////////////////////////////////////////

wire [31:0] status;
wire  [1:0] buttons;
wire        forced_scandoubler;
wire        direct_video;

wire        ioctl_download;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;

wire [10:0] ps2_key;

wire [15:0] joystick_0, joystick_1;
wire [15:0] joy = joystick_0 | joystick_1;
wire [15:0] joy_a;

wire [21:0] gamma_bus;

hps_io #(.STRLEN($size(CONF_STR)>>3)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.conf_str(CONF_STR),

	.buttons(buttons),
	.status(status),
	.status_menumask(direct_video),
	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus),
	.direct_video(direct_video),

	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.joystick_analog_0(joy_a),
	.ps2_key(ps2_key)
);



`define CORE_NAME "RAMPAGE"
reg       sg; // Sounds Good board
reg [7:0] input0;
reg [7:0] input1;
reg [7:0] input2;
reg [7:0] input3;
reg [7:0] input4;
reg [7:0] output5;
reg [7:0] output6;

// Game specific sound board/DIP/input settings
always @(*) begin
        if (`CORE_NAME == "SARGE" ||
            `CORE_NAME == "MAXRPM")
                sg = 0;
        else
                sg = 1;

        input0 = 8'hff;
        input1 = 8'hff;
        input2 = 8'hff;
        input3 = 8'hff;
        input4 = 8'hff;
/*
        if (`CORE_NAME == "SARGE") begin
                // Two stick/player like the original
                input0 = ~{2'b00, service, 1'b0, m_two_players, m_one_player, m_coin2, m_coin1};
                input1 = ~{m_fireA | m_fireB, m_fireA | m_fireB, m_fire2A | m_fire2B, m_fire2A | m_fire2B, m_down, m_up, m_down, m_up};
                input2 = ~{m_fire3A | m_fire3B, m_fire3A | m_fire3B, m_fire4A | m_fire4B, m_fire4A | m_fire4B, m_down3, m_up3, m_down4, m_up4};
        end else if (`CORE_NAME == "MAXRPM") begin
                input0 = ~{service, 3'b000, m_one_player, m_two_players, m_coin1, m_coin2};
                input1 = ~{maxrpm_adc_data};
                input2 = ~{maxrpm_gear1, maxrpm_gear2};
        end else if (`CORE_NAME == "RAMPAGE") begin
                // normal controls for 3 players
                input0 = ~{2'b00, service, 1'b0, 2'b00, m_coin2, m_coin1};
                input1 = ~{2'b00, m_fireB, m_fireA, m_left, m_down, m_right, m_up};
                input2 = ~{2'b00, m_fire2B, m_fire2A, m_left2, m_down2, m_right2, m_up2};
                input4 = ~{2'b00, m_fire3B, m_fire3A, m_left3, m_down3, m_right3, m_up3};
        end else if (`CORE_NAME == "POWERDRV") begin
                // Controls for 3 players using 4 buttons/joystick
                input0 = ~{2'b00, service, 1'b0, 1'b0, m_coin3, m_coin2, m_coin1};
                input1 = ~{m_fire2B, m_fire2A, powerdrv_gear[1], m_fire2C, m_fireB, m_fireA, powerdrv_gear[0], m_fireC};
                input2 = ~{sndstat[0], 3'b000, m_fire3B, m_fire3A, powerdrv_gear[2], m_fire3C};
        end
*/
end

wire [15:0] rom_addr;
wire [15:0] rom_do;
wire [17:0] snd_addr;
wire [15:0] snd_do;
wire [15:0] sp_addr;
wire [31:0] sp_do;
wire [24:0] sp_ioctl_addr = ioctl_addr - 17'h10000;
wire [24:0] snd_ioctl_addr = ioctl_addr - snd_offset;
reg         port1_req, port2_req;
reg  [23:0] port1_a;
reg  [23:0] port2_a;
reg  [19:0] snd_offset;
reg  [19:0] gfx1_offset;

always @(*) begin
        if (sg) begin
                snd_offset  = 20'h58000;
                gfx1_offset = 20'h50000;
                port1_a = ioctl_addr[23:0];
                port1_a = (ioctl_addr < snd_offset) ? ioctl_addr[23:0] : // 8 bit main ROM
              snd_offset + {snd_ioctl_addr[17], snd_ioctl_addr[15:0], snd_ioctl_addr[16]}; // 16 bit Sounds Good ROM

                // merge sprite roms (4x64k) into 32-bit wide words
                port2_a     = {sp_ioctl_addr[23:18], sp_ioctl_addr[15:0], sp_ioctl_addr[17:16]};
        end else begin
                snd_offset  = 20'h38000;
                gfx1_offset = 20'h30000;
                port1_a = ioctl_addr[23:0];
                // merge sprite roms (4x32k) into 32-bit wide words
                port2_a     = {sp_ioctl_addr[23:17], sp_ioctl_addr[14:0], sp_ioctl_addr[16:15]};
        end
end
sdram sdram(
        .*,
        .init_n        ( pll_locked   ),
        .clk           ( clk_mem      ),

        // port1 used for main + sound CPU
        .port1_req     ( port1_req    ),
        .port1_ack     ( ),
        .port1_a       ( port1_a[23:1] ),
        .port1_ds      ( {port1_a[0], ~port1_a[0]} ),
        .port1_we      ( ioctl_download ),
        .port1_d       ( {ioctl_dout, ioctl_dout} ),
        .port1_q       ( ),

        .cpu1_addr     ( cpu1_addr ), //Turbo Cheap Squeak/Sounds Good with higher priority
        .cpu1_q        ( snd_do ),
        .cpu2_addr     ( ioctl_download ? 18'h3ffff : {3'b000, rom_addr[15:1]} ),
        .cpu2_q        ( rom_do ),

        // port2 for sprite graphics
        .port2_req     ( port2_req ),
        .port2_ack     ( ),
        .port2_a       ( port2_a[23:1] ),
        .port2_ds      ( {port2_a[0], ~port2_a[0]} ),
        .port2_we      ( ioctl_download ),
        .port2_d       ( {ioctl_dout, ioctl_dout} ),
        .port2_q       ( ),

        .sp_addr       ( ioctl_download ? 16'hffff : sp_addr ),
        .sp_q          ( sp_do )
);

reg [19:1] cpu1_addr;

// ROM download controller
always @(posedge clk_sys) begin
        reg        ioctl_wr_last = 0;

        ioctl_wr_last <= ioctl_wr;
        if (ioctl_download) begin
                if (~ioctl_wr_last && ioctl_wr) begin
                        port1_req <= ~port1_req;
                        port2_req <= ~port2_req;
                end
        end
        // register for better timings
        cpu1_addr <= ioctl_download ? 19'h7ffff : (snd_offset[19:1] + snd_addr[17:1]);
end

// reset signal generation
reg reset = 1;
reg rom_loaded = 0;
always @(posedge clk_sys) begin
        reg ioctl_downlD;
        reg [15:0] reset_count;
        ioctl_downlD <= ioctl_download;

        // generate a second reset signal - needed for some reason
        if (status[0] | buttons[1] | ~rom_loaded) reset_count <= 16'hffff;
        else if (reset_count != 0) reset_count <= reset_count - 1'd1;

        if (ioctl_downlD & ~ioctl_download) rom_loaded <= 1;
        reset <= status[0] | buttons[1] | ioctl_download | ~rom_loaded | (reset_count == 16'h0001);
end

wire [1:0] sndstat;
mcr3mono mcr3mono (
        .clock_40(clk_sys),
        .reset(reset),
        .video_r(r),
        .video_g(g),
        .video_b(b),
        .video_blankn(),
        .video_hblank(hblank),
        .video_vblank(vblank),
        .video_hs(hs),
        .video_vs(vs),
        .video_csync(),
        .video_ce(ce_pix_old),
        .tv15Khz_mode(~status[13]),

        .soundsgood(sg),
        .snd_stat(sndstat),
        .audio_out(audio),

        .input_0(input0),
        .input_1(input1),
        .input_2(input2),
        .input_3(input3),
        .input_4(input4),
        .output_5(output5),
        .output_6(output6),

        .cpu_rom_addr ( rom_addr        ),
        .cpu_rom_do   ( rom_addr[0] ? rom_do[15:8] : rom_do[7:0] ),
        .snd_rom_addr ( snd_addr        ),
        .snd_rom_do   ( snd_do          ),
        .sp_addr      ( sp_addr         ),
        .sp_graphx32_do ( sp_do         ),

        .dl_addr(ioctl_addr-gfx1_offset),
        .dl_data(ioctl_dout),
        .dl_wr(ioctl_wr)
);


wire       pressed = ps2_key[9];
wire [8:0] code    = ps2_key[8:0];
always @(posedge clk_sys) begin
	reg old_state;
	old_state <= ps2_key[10];
	
	if(old_state != ps2_key[10]) begin
		casex(code)
			'hX75: btn_up          <= pressed; // up
			'hX72: btn_down        <= pressed; // down
			'hX6B: btn_left        <= pressed; // left
			'hX74: btn_right       <= pressed; // right
			'h029: btn_fire1       <= pressed; // space
			'h014: btn_fire3       <= pressed; // ctrl

			'h004: btn_coin        <= pressed; // F3

			// JPAC/IPAC/MAME Style Codes
			'h02E: btn_coin        <= pressed; // 5
			'h036: btn_coin        <= pressed; // 6
			'h02D: btn_up          <= pressed; // R
			'h02B: btn_down        <= pressed; // F
			'h023: btn_left        <= pressed; // D
			'h034: btn_right       <= pressed; // G
			'h01C: btn_fire1       <= pressed; // A

			'h00D: btn_van         <= pressed; // TAB
			'h01A: btn_shift       <= pressed; // Z
			'h012: btn_fire4       <= pressed; // shift left
			'h011: btn_fire2       <= pressed; // alt
		endcase
	end
end

reg btn_van   = 0;
reg btn_shift = 0;
reg btn_fire1 = 0;
reg btn_fire2 = 0;
reg btn_fire3 = 0;
reg btn_fire4 = 0;


reg btn_up    = 0;
reg btn_down  = 0;
reg btn_right = 0;
reg btn_left  = 0;
reg btn_coin  = 0;

wire m_up     = no_rotate ? btn_left  | joy[1] : btn_up    | joy[3];
wire m_down   = no_rotate ? btn_right | joy[0] : btn_down  | joy[2];
wire m_left   = no_rotate ? btn_down  | joy[2] : btn_left  | joy[1];
wire m_right  = no_rotate ? btn_up    | joy[3] : btn_right | joy[0];

wire m_fire1  = btn_fire1 | joy[4];
wire m_fire2  = btn_fire2 | joy[5];
wire m_fire3  = btn_fire3 | joy[6];
wire m_fire4  = btn_fire4 | joy[7];
wire m_van    = btn_van   | joy[8];
wire m_shift  = btn_shift | joy[9];
wire m_coin   = btn_coin  | joy[10];

wire ce_pix_old;

wire hblank, vblank;
wire hs, vs;
wire [2:0] r,g;
wire [2:0] b;

wire no_rotate = status[2] & ~direct_video;

reg ce_pix;
always @(posedge clk_sys) begin
        reg [2:0] div;

        div <= div + 1'd1;
        ce_pix <= !div;
end

arcade_fx #(512,9) arcade_video//505?
(
        .*,
        .ce_pix(status[13] ? ce_pix_old: ce_pix),
        .clk_video(clk_sys),
        .RGB_in({r,g,b}),
        .HBlank(hblank),
        .VBlank(vblank),
        .HSync(hs),
        .VSync(vs),

        .fx(status[5:3])
);
/*
// 512x480
arcade_rotate_fx #(496,240,9) arcade_video
(
	.*,

	.clk_video(clk_sys),
	.RGB_in({r,g,b}),
	.HBlank(hblank),
	.VBlank(vblank),
	.HSync(hs),
	.VSync(vs),

	.fx(status[5:3])
);
*/

assign AUDIO_S = 0;
//wire [15:0] audio_l, audio_r;
wire  [9:0] audio;


assign AUDIO_L = { audio, 5'd0 };
assign AUDIO_R = { audio, 5'd0 };
/*
mcr3mono mcr3mono (
        .clock_40(clk_sys),
        .reset(reset),
        .video_r(r),
        .video_g(g),
        .video_b(b),
        .video_blankn(blankn),
        .video_hs(hs),
        .video_vs(vs),
        .video_csync(cs),
        .tv15Khz_mode(scandoublerD),

        .soundsgood(sg),
        .snd_stat(sndstat),
        .audio_out(audio),

        .input_0(input0),
        .input_1(input1),
        .input_2(input2),
        .input_3(input3),
        .input_4(input4),
        .output_5(output5),
        .output_6(output6),

        .cpu_rom_addr ( rom_addr        ),
        .cpu_rom_do   ( rom_addr[0] ? rom_do[15:8] : rom_do[7:0] ),
        .snd_rom_addr ( snd_addr        ),
        .snd_rom_do   ( snd_do          ),
        .sp_addr      ( sp_addr         ),
        .sp_graphx32_do ( sp_do         ),

        .dl_addr(ioctl_addr-gfx1_offset),
        .dl_data(ioctl_dout),
        .dl_wr(ioctl_wr)
);
*/
endmodule
