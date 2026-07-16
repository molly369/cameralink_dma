/*模块2：接收解码与像素重组模块 (PL端 - 核心难点)
总共收到了 3 * 28 = 84-bit 数据，但对于 8-Tap * 8-Bit 模式，
真正有效的图像载荷只有 64-bit。
组员必须使用连线 (assign) 将散落在X、Y、Z三个通道中的位段重新组合成连续的
 64-bit AXI-Stream 数据流。*/

module cameralink_decoder#(
    //parameter W=1280/8-1,
    parameter W=1280,
    parameter H=1024,
    parameter integer PIXELS_PER_BEAT = 8
)(
    // 系统 AXI 工作时钟与复位 (例: 150MHz)
    input  wire        axis_clk,     
    input  wire        axis_rst_n,
       
    input  wire        cfg_enable,
    input  wire        cfg_soft_reset_n,
    input  wire        cfg_clear_status,
    input  wire [15:0] cfg_width,
    input  wire [15:0] cfg_height,

    output wire [31:0] status,
    

    // 前端输入接口 (对接真实的 3组 28-bit 硬件管脚或模拟源)
    input  wire        cam_clk_in,
    input  wire [27:0] cam_port_x_in, 
    input  wire [27:0] cam_port_y_in, 
    input  wire [27:0] cam_port_z_in, 
    input  wire        cam_fval_in,
    input  wire        cam_lval_in,
    input  wire        cam_dval_in,
    
    input  wire        m_axis_tready,

    // 后端输出接口 (组合完毕后，依旧输出清爽的 64-bit AXI-Stream 给 DMA)
    output wire [63:0] m_axis_tdata, // 经过协议重组后的连续 8 个像素数据
    output wire [7:0]  m_axis_tkeep, // 保持 8'hFF
    output wire       m_axis_tvalid,//有效信号标注
    output wire        m_axis_tuser, // 帧起始标志 
    output wire        m_axis_tlast  // 行结束标志 
);
wire [15:0] width_eff;
wire [15:0] height_eff;
wire [15:0] line_beats_eff;
reg error;
wire rst_full;
assign rst_full=cfg_soft_reset_n&axis_rst_n;
//assign width_eff  = (cfg_width  == 16'd0) ? W : cfg_width;
//assign height_eff = (cfg_height == 16'd0) ? H : cfg_height;
assign width_eff  =  W ;
assign height_eff =  H ;
// 当前固定 8 pixel / beat
assign line_beats_eff = width_eff >> 3;
assign m_axis_tkeep=8'hFF;

wire fifo_empty;
wire fifo_full;

wire fifo_rd_en;

wire isfirst;//帧开始信号
wire islast;//行结束信号
wire [65:0]dout;
wire [65:0]data;
reg [15:0] lval_cnt=0;
reg cam_fval_r;
reg cfg_enable_d0;
reg cfg_enable_d1;
always@(posedge cam_clk_in)begin
    cam_fval_r<=cam_fval_in;
end
always@(negedge cam_clk_in)begin
  if(lval_cnt==line_beats_eff-1)begin
    lval_cnt<=0;
  end
  else if(cam_lval_in) begin
    lval_cnt<=lval_cnt+1;
  end
    
end
assign isfirst=(cam_fval_in==1)&&(cam_fval_r==0);
assign islast=(lval_cnt==line_beats_eff-1);
assign m_axis_tuser=dout[64];
assign m_axis_tlast=dout[65];


assign m_axis_tvalid = !fifo_empty;
assign fifo_rd_en     = m_axis_tvalid && m_axis_tready;

//数据存储，一个恢复时钟8个像素
assign data[7:0]={cam_port_x_in[5],cam_port_x_in[27],cam_port_x_in[6],cam_port_x_in[4:0]};
assign data[15:8]={cam_port_x_in[11:10],cam_port_x_in[14:12],cam_port_x_in[9:7]};
assign data[23:16]={cam_port_x_in[17:16],cam_port_x_in[22:18],cam_port_x_in[15]};
assign data[31:24]={cam_port_y_in[5],cam_port_y_in[27],cam_port_y_in[6],cam_port_y_in[4:0]};
assign data[39:32]={cam_port_y_in[11:10],cam_port_y_in[14:12],cam_port_y_in[9:7]};
assign data[47:40]={cam_port_y_in[17:16],cam_port_y_in[22:18],cam_port_y_in[15]};
assign data[55:48]={cam_port_z_in[5],cam_port_z_in[27],cam_port_z_in[6],cam_port_z_in[4:0]};
assign data[63:56]={cam_port_z_in[11:10],cam_port_z_in[14:12],cam_port_z_in[9:7]};
assign data[64]=isfirst;
assign data[65]=islast;

 assign m_axis_tdata[7:0]=dout[7:0];
 assign m_axis_tdata[15:8]=dout[15:8];
 assign m_axis_tdata[23:16]=dout[23:16];
assign m_axis_tdata[31:24]=dout[31:24];
assign m_axis_tdata[39:32]=dout[39:32];
assign m_axis_tdata[47:40]=dout[47:40];
assign m_axis_tdata[55:48]=dout[55:48];
assign m_axis_tdata[63:56]=dout[63:56];

always @(posedge cam_clk_in ) begin
        cfg_enable_d0 <= cfg_enable;
        cfg_enable_d1 <= cfg_enable_d0;
end
always @(posedge axis_clk) begin
    if (cfg_clear_status) begin
        error <= 1'b0;
    end 
    else if ( cfg_enable&& fifo_full) begin//溢出
        error <= 1'b1;
    end
end

assign status[0] = fifo_full;
assign status[1] = m_axis_tvalid;
assign status[2] = error;//粘滞错误，一旦有数据遗漏，除非ps清空，否则错误信息一直保持
assign status[31:3] = 29'd0;


//跨时钟域处理
fifo_generator_0 myfifo (
  .rst(~rst_full),                  // input wire rst
  .wr_clk(cam_clk_in),            // input wire wr_clk
  .rd_clk(axis_clk),            // input wire rd_clk
  .din(data),                  // input wire [65 : 0] din
  .wr_en(cfg_enable_d1&cam_lval_in),              // input wire wr_en
  .rd_en(fifo_rd_en),              // input wire rd_en
  .dout(dout),                // output wire [65: 0] dout
  .full(fifo_full),                // output wire full
  .empty(fifo_empty),              // output wire empty
  .wr_rst_busy(),  // output wire wr_rst_busy
  .rd_rst_busy()  // output wire rd_rst_busy
);

endmodule

