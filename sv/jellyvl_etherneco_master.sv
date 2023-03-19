module jellyvl_etherneco_master #(
    parameter int unsigned TIMER_WIDTH = 64, // タイマのbit幅
    parameter int unsigned NUMERATOR   = 8 , // クロック周期の分子
    parameter int unsigned DENOMINATOR = 1  // クロック周期の分母
) (
    input logic reset,
    input logic clk  ,

    output logic [TIMER_WIDTH-1:0] current_time,

    output logic         m_down_tx_first,
    output logic         m_down_tx_last ,
    output logic [8-1:0] m_down_tx_data ,
    output logic         m_down_tx_valid,
    input  logic         m_down_tx_ready,
    input  logic         s_down_rx_first,
    input  logic         s_down_rx_last ,
    input  logic [8-1:0] s_down_rx_data ,
    input  logic         s_down_rx_valid,

    output logic         m_up_tx_first,
    output logic         m_up_tx_last ,
    output logic [8-1:0] m_up_tx_data ,
    output logic         m_up_tx_valid,
    input  logic         m_up_tx_ready,
    input  logic         s_up_rx_first,
    input  logic         s_up_rx_last ,
    input  logic [8-1:0] s_up_rx_data ,
    input  logic         s_up_rx_valid
);


    // -------------------------------------
    //  Control
    // -------------------------------------

    logic [TIMER_WIDTH-1:0] set_time  ;
    logic                   set_valid ;
    logic                   set_valid2;

    logic trig_enable;

    always_ff @ (posedge clk) begin
        if (reset) begin
            set_time    <= 64'd0; // h0123456789abcdef;
            set_valid   <= 1'b1;
            set_valid2  <= 1'b1;
            trig_enable <= 1'b0;
        end else begin
            //            set_time  = 64'd0;
            set_valid   <= set_valid2;
            set_valid2  <= 1'b0;
            trig_enable <= !set_valid && !set_valid2;
        end
    end

    localparam int unsigned PERIOD_WIDTH = 16;

    logic          timsync_trigger ;
    logic          timsync_override;
    logic          timsync_correct ;
    logic [8-1:0]  timsync_type    ;
    logic [8-1:0]  timsync_node    ;
    logic [16-1:0] timsync_length  ;

    // とりあえず時間合わせパケットに固定
    assign timsync_type = 8'h10;
    assign timsync_node = 8'h01;
    //  assign request_length = 16'd13 - 16'd1;


    // 通信タイミング生成
    jellyvl_periodic_trigger #(
        .TIMER_WIDTH  (TIMER_WIDTH ),
        .PERIOD_WIDTH (PERIOD_WIDTH)
    ) u_periodic_trigger (
        .reset (reset),
        .clk   (clk  ),
        .
        enable (1'b1     ), //trig_enable ,
        .phase  ('0       ), //current_time as PERIOD_WIDTH,
        .period (16'd20000),
        .
        current_time (current_time),
        .
        trigger (timsync_trigger)
    );

    always_ff @ (posedge clk) begin
        if (reset) begin
            timsync_override <= 1'b0;
            timsync_correct  <= 1'b0;
        end else begin
            if (timsync_trigger) begin
                timsync_override <= 1'b1; // ~timsync_correct;
                timsync_correct  <= 1'b1;
            end
        end
    end


    // -------------------------------------
    //  Ring bus
    // -------------------------------------

    // Outer ring TX (send command)
    logic         outer_tx_payload_last ;
    logic [8-1:0] outer_tx_payload_data ;
    logic         outer_tx_payload_valid;
    logic         outer_tx_payload_ready;

    jellyvl_etherneco_packet_tx u_etherneco_packet_tx_outer (
        .reset (reset),
        .clk   (clk  ),
        .
        tx_start  (timsync_trigger),
        .tx_length (timsync_length ),
        .tx_type   (timsync_type   ),
        .tx_node   (timsync_node   ),
        .
        tx_cancel (1'b0),
        .
        s_payload_last  (outer_tx_payload_last ),
        .s_payload_data  (outer_tx_payload_data ),
        .s_payload_valid (outer_tx_payload_valid),
        .s_payload_ready (outer_tx_payload_ready),
        .
        m_tx_first (m_down_tx_first),
        .m_tx_last  (m_down_tx_last ),
        .m_tx_data  (m_down_tx_data ),
        .m_tx_valid (m_down_tx_valid),
        .m_tx_ready (m_down_tx_ready)
    );


    // Outer ring RX and Inner ring TX (loop back)
    logic          outer_rx_start ;
    logic          outer_rx_end   ;
    logic          outer_rx_error ;
    logic [16-1:0] outer_rx_length;
    logic [8-1:0]  outer_rx_type  ;
    logic [8-1:0]  outer_rx_node  ;

    logic          outer_rx_payload_first;
    logic          outer_rx_payload_last ;
    logic [16-1:0] outer_rx_payload_pos  ;
    logic [8-1:0]  outer_rx_payload_data ;
    logic          outer_rx_payload_valid;
    logic [8-1:0]  outer_rx_replace_data ;
    logic          outer_rx_replace_valid;

    jellyvl_etherneco_packet_rx #(
        .DOWN_STREAM   (1'b1),
        .REPLACE_DELAY (0   )
    ) u_etherneco_packet_rx_outer (
        .reset (reset),
        .clk   (clk  ),
        .
        s_rx_first (s_up_rx_first),
        .s_rx_last  (s_up_rx_last ),
        .s_rx_data  (s_up_rx_data ),
        .s_rx_valid (s_up_rx_valid),
        .
        m_tx_first (m_up_tx_first),
        .m_tx_last  (m_up_tx_last ),
        .m_tx_data  (m_up_tx_data ),
        .m_tx_valid (m_up_tx_valid),
        .
        rx_start  (outer_rx_start ),
        .rx_end    (outer_rx_end   ),
        .rx_error  (outer_rx_error ),
        .rx_length (outer_rx_length),
        .rx_type   (outer_rx_type  ),
        .rx_node   (outer_rx_node  ),
        .
        payload_first (outer_rx_payload_first),
        .payload_last  (outer_rx_payload_last ),
        .payload_pos   (outer_rx_payload_pos  ),
        .payload_data  (outer_rx_payload_data ),
        .payload_valid (outer_rx_payload_valid),
        .replace_data  (outer_rx_replace_data ),
        .replace_valid (outer_rx_replace_valid)
    );


    // Inner ring RX (receive response)
    logic          inner_rx_start ;
    logic          inner_rx_end   ;
    logic          inner_rx_error ;
    logic [16-1:0] inner_rx_length;
    logic [8-1:0]  inner_rx_type  ;
    logic [8-1:0]  inner_rx_node  ;

    logic         inner_terminate_first;
    logic         inner_terminate_last ;
    logic [8-1:0] inner_terminate_data ;
    logic         inner_terminate_valid;

    logic          inner_rx_payload_first;
    logic          inner_rx_payload_last ;
    logic [16-1:0] inner_rx_payload_pos  ;
    logic [8-1:0]  inner_rx_payload_data ;
    logic          inner_rx_payload_valid;

    jellyvl_etherneco_packet_rx #(
        .DOWN_STREAM   (1'b0),
        .REPLACE_DELAY (0   )
    ) u_etherneco_packet_rx_inner (
        .reset (reset),
        .clk   (clk  ),
        .
        s_rx_first (s_down_rx_first),
        .s_rx_last  (s_down_rx_last ),
        .s_rx_data  (s_down_rx_data ),
        .s_rx_valid (s_down_rx_valid),
        .
        m_tx_first (inner_terminate_first),
        .m_tx_last  (inner_terminate_last ),
        .m_tx_data  (inner_terminate_data ),
        .m_tx_valid (inner_terminate_valid),
        .
        rx_start  (inner_rx_start ),
        .rx_end    (inner_rx_end   ),
        .rx_error  (inner_rx_error ),
        .rx_length (inner_rx_length),
        .rx_type   (inner_rx_type  ),
        .rx_node   (inner_rx_node  ),
        .
        payload_first (inner_rx_payload_first),
        .payload_last  (inner_rx_payload_last ),
        .payload_pos   (inner_rx_payload_pos  ),
        .payload_data  (inner_rx_payload_data ),
        .payload_valid (inner_rx_payload_valid),
        .replace_data  ('0                    ),
        .replace_valid (1'b0                  )
    );




    // -------------------------------------
    //  Functions
    // -------------------------------------

    // タイマ合わせマスター
    jellyvl_etherneco_synctimer_master #(
        .TIMER_WIDTH (TIMER_WIDTH),
        .NUMERATOR   (NUMERATOR  ),
        .DENOMINATOR (DENOMINATOR)
    ) u_etherneco_synctimer_master (
        .reset (reset),
        .clk   (clk  ),
        .
        current_time (current_time),
        .
        set_time  (set_time ),
        .set_valid (set_valid),
        .
        cmd_tx_start    (timsync_trigger       ),
        .cmd_tx_correct  (timsync_correct       ),
        .cmd_tx_override (timsync_override      ),
        .cmt_tx_length   (timsync_length        ),
        .m_cmd_tx_last   (outer_tx_payload_last ),
        .m_cmd_tx_data   (outer_tx_payload_data ),
        .m_cmd_tx_valid  (outer_tx_payload_valid),
        .m_cmd_tx_ready  (outer_tx_payload_ready),
        .
        ret_rx_start      (outer_rx_start        ),
        .ret_rx_end        (outer_rx_end          ),
        .ret_rx_error      (outer_rx_error        ),
        .ret_rx_length     (outer_rx_length       ),
        .ret_rx_type       (outer_rx_type         ),
        .ret_rx_node       (outer_rx_node         ),
        .ret_payload_first (outer_rx_payload_first),
        .ret_payload_last  (outer_rx_payload_last ),
        .ret_payload_pos   (outer_rx_payload_pos  ),
        .ret_payload_data  (outer_rx_payload_data ),
        .ret_payload_valid (outer_rx_payload_valid),
        .ret_replace_data  (outer_rx_replace_data ),
        .ret_replace_valid (outer_rx_replace_valid),
        .
        res_rx_start      (inner_rx_start        ),
        .res_rx_end        (inner_rx_end          ),
        .res_rx_error      (inner_rx_error        ),
        .res_rx_length     (inner_rx_length       ),
        .res_rx_type       (inner_rx_type         ),
        .res_rx_node       (inner_rx_node         ),
        .res_payload_first (inner_rx_payload_first),
        .res_payload_last  (inner_rx_payload_last ),
        .res_payload_pos   (inner_rx_payload_pos  ),
        .res_payload_data  (inner_rx_payload_data ),
        .res_payload_valid (inner_rx_payload_valid)
    );

endmodule
