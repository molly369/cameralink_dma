`timescale 1ns / 1ps
/*
模块1：模拟数据源 (PL端 - 3通道独立输出版)
开发要求：
组员在生成模拟数据时，不能再单纯把64位数据拼接输出，
而是要对照CameraLink Full模式的协议映射表，将生成的8个Tap（像素）拆散，按照协议规定的位置填入 port_x、port_y 和 port_z 这三个28位的总线中。
*/
module cameralink_full_sim_source(
  input  wire        clk,          // 像素时钟 ，80MHz
    input  wire        rst_n,
    
    // 模拟 CameraLink 时钟输出
    output wire        cam_clk_out,//288输出时钟
    
    // 物理通道拆解：3组 28-bit 数据
    output reg [27:0] cam_port_x,   // Base通道 (包含FVAL, LVAL, DVAL及部分数据)
    output reg [27:0] cam_port_y,   // Medium扩展通道
    output reg [27:0] cam_port_z,   // Full扩展通道
    
    // 显式提取的同步信号 (可选，建议保留以方便仿真和验证，
    // 实际硬件中FVAL/LVAL/DVAL其实是复用在cam_port_x的第24, 25, 26位上的)
    output wire        cam_fval,     
    output wire        cam_lval,     
    output wire        cam_dval      
    );
    assign  cam_clk_out=clk;//恢复时钟频率与输入时钟频率一致 
    assign cam_lval= cam_port_x[24];
    assign cam_fval= cam_port_x[25];
    assign cam_dval= cam_port_x[26];
    //产生8个像素
    reg[7:0] tap1=8'h01;
    reg[7:0] tap2=8'h23;
    reg[7:0] tap3=8'h45;
    reg[7:0] tap4=8'h67;
    reg[7:0] tap5=8'h89;
    reg[7:0] tap6=8'hab;
    reg[7:0] tap7=8'hcd;
    reg[7:0] tap8=8'hef;
    reg [11:0]L_count;
    reg[21:0] F_count;
    reg[9:0] L_num=0;
    //相机分辨率1280 × 1024 像素
    reg FVAL=0;
    reg LVAL=0;
    wire DVAL;
    assign DVAL=LVAL;

    parameter H=1024;
    parameter W=1280/8;
    parameter LCNT_H=W-1;
    parameter LCNT_L=20;
    
    parameter FCNT_H=(LCNT_H+LCNT_L+1)*H-1;//FCNT与LCNT同时拉高
    parameter FCNT_L=50;
    //记录传了多少行
    always@(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
       L_num<=0;
    end
    else if(L_count==W)begin
           L_num<=L_num+1;
       end
    end
    
    //帧计数器
    always@(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
       F_count<=0;
    end
    else begin
       if(F_count==FCNT_H+FCNT_L)begin
          F_count<=0;
       end
       else begin
          F_count<=F_count+1;
       end
    end
    end
    wire en_L_count;
        //行计数器
    assign en_L_count=(F_count<=((LCNT_H+LCNT_L+1)*H-1));
    always@(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
       L_count<=0;
    end
    else if(en_L_count) begin
       if(L_count==LCNT_H+LCNT_L)begin
          L_count<=0;
       end
       else begin
          L_count<=L_count+1;
       end
    end
    else begin
        L_count<=0;
    end
    end
    //有效信号输出
    always@(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
       FVAL<=0;
    end
    else if(F_count<FCNT_H)begin
      FVAL<=1;
    end
    else begin
      FVAL<=0;
    end
    end
     always@(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
       LVAL<=0;
    end
    else if((L_count<=LCNT_H)&& en_L_count)begin
      LVAL<=1;
    end
    else begin
      LVAL<=0;
    end
    end
    //自加模拟像素值变换
    always@(posedge clk)begin
       tap1=tap1+1;
       tap2=tap2+1;
       tap3=tap3+1;
       tap4=tap4+1;
       tap5=tap5+1;
       tap6=tap6+1;
       tap7=tap7+1;
       tap8=tap8+1; 
    end

    
//下降沿变换数据
    always@(negedge clk or negedge rst_n)begin
    if(!rst_n)begin
       cam_port_x<=0;
    end
    else begin    //第一个像素
       cam_port_x[23]<=1;
       cam_port_x[24]<=LVAL;
       cam_port_x[25]<=FVAL;
       cam_port_x[26]<=DVAL;
       cam_port_x[4:0]<=tap1[4:0];
       cam_port_x[6]<=tap1[5];
       cam_port_x[27]<=tap1[6];
       cam_port_x[5]<=tap1[7];
      //第二个像素 
       cam_port_x[9:7]<=tap2[2:0]; 
        cam_port_x[14:12]<=tap2[5:3];
         cam_port_x[11:10]<=tap2[7:6];   
        //第三个像素
          cam_port_x[15]<=tap3[0];   
          cam_port_x[22:18]<=tap3[5:1];
          cam_port_x[17:16]<=tap3[7:6];
           
    end
    end
        always@(negedge clk or negedge rst_n)begin
    if(!rst_n)begin
       cam_port_y<=0;
    end
    else begin    //第四个像素
        cam_port_y[23]<=1;
       cam_port_y[24]<=LVAL;
       cam_port_y[25]<=FVAL;
       cam_port_y[26]<=DVAL;
       cam_port_y[4:0]<=tap4[4:0];
       cam_port_y[6]<=tap4[5];
       cam_port_y[27]<=tap4[6];
       cam_port_y[5]<=tap4[7];
      //第五个像素 
       cam_port_y[9:7]<=tap5[2:0]; 
        cam_port_y[14:12]<=tap5[5:3];
         cam_port_y[11:10]<=tap5[7:6];   
        //第六个像素
          cam_port_y[15]<=tap6[0];   
          cam_port_y[22:18]<=tap6[5:1];
          cam_port_y[17:16]<=tap6[7:6];
    end
    end
     always@(negedge clk or negedge rst_n) begin
    if(!rst_n)begin
       cam_port_z<=0;
    end
    else begin
       cam_port_z[23]<=1;
       cam_port_z[24]<=LVAL;
       cam_port_z[25]<=FVAL;
       cam_port_z[26]<=DVAL;
    //第七个像素
       cam_port_z[4:0]<=tap7[4:0];
       cam_port_z[6]<=tap7[5];
       cam_port_z[27]<=tap7[6];
       cam_port_z[5]<=tap7[7];
      //第八个像素 
       cam_port_z[9:7]<=tap8[2:0]; 
        cam_port_z[14:12]<=tap8[5:3];
         cam_port_z[11:10]<=tap8[7:6];   
        //剩余位未定义
          cam_port_z[15]<=0;   
          cam_port_z[22:18]<=0;
          cam_port_z[17:16]<=0;
    end
    end
    
endmodule
