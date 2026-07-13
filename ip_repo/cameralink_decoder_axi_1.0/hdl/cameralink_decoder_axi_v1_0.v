
`timescale 1 ns / 1 ps

	module cameralink_decoder_axi_v1_0 #
	(
		// Users to add parameters here

		// User parameters ends
		// Do not modify the parameters beyond this line


		// Parameters of Axi Slave Bus Interface S00_AXI
		parameter integer C_S00_AXI_DATA_WIDTH	= 32,
		parameter integer C_S00_AXI_ADDR_WIDTH	= 4
	)
	(
		// Users to add ports here
    // CameraLink external input ports
    // ===============================
    input  wire        cam_clk_in,
    input  wire [27:0] cam_port_x_in,
    input  wire [27:0] cam_port_y_in,
    input  wire [27:0] cam_port_z_in,
    input  wire        cam_fval_in,
    input  wire        cam_lval_in,
    input  wire        cam_dval_in,

    // ===============================
    // AXI4-Stream Video output
    // ===============================
    output wire [63:0] m_axis_tdata,
    output wire [7:0]  m_axis_tkeep,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire        m_axis_tuser,
    output wire        m_axis_tlast,
		// User ports ends
		// Do not modify the ports beyond this line


		// Ports of Axi Slave Bus Interface S00_AXI
		input wire  s00_axi_aclk,
		input wire  s00_axi_aresetn,
		input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_awaddr,
		input wire [2 : 0] s00_axi_awprot,
		input wire  s00_axi_awvalid,
		output wire  s00_axi_awready,
		input wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_wdata,
		input wire [(C_S00_AXI_DATA_WIDTH/8)-1 : 0] s00_axi_wstrb,
		input wire  s00_axi_wvalid,
		output wire  s00_axi_wready,
		output wire [1 : 0] s00_axi_bresp,
		output wire  s00_axi_bvalid,
		input wire  s00_axi_bready,
		input wire [C_S00_AXI_ADDR_WIDTH-1 : 0] s00_axi_araddr,
		input wire [2 : 0] s00_axi_arprot,
		input wire  s00_axi_arvalid,
		output wire  s00_axi_arready,
		output wire [C_S00_AXI_DATA_WIDTH-1 : 0] s00_axi_rdata,
		output wire [1 : 0] s00_axi_rresp,
		output wire  s00_axi_rvalid,
		input wire  s00_axi_rready
	);
wire        cfg_enable;
wire        cfg_soft_reset_n;
wire        cfg_clear_status;
wire [15:0] cfg_width;
wire [15:0] cfg_height;
wire [31:0] decoder_status;
// Instantiation of Axi Bus Interface S00_AXI
	cameralink_decoder_axi_v1_0_S00_AXI # ( 
		.C_S_AXI_DATA_WIDTH(C_S00_AXI_DATA_WIDTH),
		.C_S_AXI_ADDR_WIDTH(C_S00_AXI_ADDR_WIDTH)
	) cameralink_decoder_axi_v1_0_S00_AXI_inst (
	    .cfg_enable       (cfg_enable),
        .cfg_soft_reset_n (cfg_soft_reset_n),
        .cfg_clear_status (cfg_clear_status),
        .cfg_width        (cfg_width),
        .cfg_height       (cfg_height),
       .decoder_status   (decoder_status),
		.S_AXI_ACLK(s00_axi_aclk),
		.S_AXI_ARESETN(s00_axi_aresetn),
		.S_AXI_AWADDR(s00_axi_awaddr),
		.S_AXI_AWPROT(s00_axi_awprot),
		.S_AXI_AWVALID(s00_axi_awvalid),
		.S_AXI_AWREADY(s00_axi_awready),
		.S_AXI_WDATA(s00_axi_wdata),
		.S_AXI_WSTRB(s00_axi_wstrb),
		.S_AXI_WVALID(s00_axi_wvalid),
		.S_AXI_WREADY(s00_axi_wready),
		.S_AXI_BRESP(s00_axi_bresp),
		.S_AXI_BVALID(s00_axi_bvalid),
		.S_AXI_BREADY(s00_axi_bready),
		.S_AXI_ARADDR(s00_axi_araddr),
		.S_AXI_ARPROT(s00_axi_arprot),
		.S_AXI_ARVALID(s00_axi_arvalid),
		.S_AXI_ARREADY(s00_axi_arready),
		.S_AXI_RDATA(s00_axi_rdata),
		.S_AXI_RRESP(s00_axi_rresp),
		.S_AXI_RVALID(s00_axi_rvalid),
		.S_AXI_RREADY(s00_axi_rready)
	);

	// Add user logic here
cameralink_decoder u_decoder (
    .axis_clk          (s00_axi_aclk),
    .axis_rst_n        (s00_axi_aresetn),

    .cfg_enable        (cfg_enable),
    .cfg_soft_reset_n  (cfg_soft_reset_n),
    .cfg_clear_status  (cfg_clear_status),
    .cfg_width         (cfg_width),
    .cfg_height        (cfg_height),

    .status            (decoder_status),

    .cam_clk_in        (cam_clk_in),
    .cam_port_x_in     (cam_port_x_in),
    .cam_port_y_in     (cam_port_y_in),
    .cam_port_z_in     (cam_port_z_in),
    .cam_fval_in       (cam_fval_in),
    .cam_lval_in       (cam_lval_in),
    .cam_dval_in       (cam_dval_in),

    .m_axis_tready     (m_axis_tready),
    .m_axis_tdata      (m_axis_tdata),
    .m_axis_tkeep      (m_axis_tkeep),
    .m_axis_tvalid     (m_axis_tvalid),
    .m_axis_tuser      (m_axis_tuser),
    .m_axis_tlast      (m_axis_tlast)
);
	// User logic ends

	endmodule
