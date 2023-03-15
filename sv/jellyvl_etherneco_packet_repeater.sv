module jellyvl_etherneco_packet_repeater #(
    parameter bit          DOWN_STREAM   = 1'b0,
    parameter int unsigned REPLACE_DELAY = 0   
) (
    input logic reset,
    input logic clk  ,

    input logic         s_first,
    input logic         s_last ,
    input logic [8-1:0] s_data ,
    input logic         s_valid,

    output logic         m_first,
    output logic         m_last ,
    output logic [8-1:0] m_data ,
    output logic         m_valid,

    output logic rx_start,
    output logic rx_end  ,
    output logic rx_error,

    output logic [16-1:0] rx_length,
    output logic [8-1:0]  rx_type  ,
    output logic [8-1:0]  rx_node  ,

    output logic          payload_first,
    output logic          payload_last ,
    output logic [16-1:0] payload_pos  ,
    output logic [8-1:0]  payload_data ,
    output logic          payload_valid,

    input logic         replace_data ,
    input logic [8-1:0] replace_valid
);

    localparam int unsigned BIT_PREAMBLE = 0;
    localparam int unsigned BIT_LENGTH   = 1;
    localparam int unsigned BIT_TYPE     = 2;
    localparam int unsigned BIT_NODE     = 3;
    localparam int unsigned BIT_PAYLOAD  = 4;
    localparam int unsigned BIT_FCS      = 5;
    localparam int unsigned BIT_ERROR    = 6;

    localparam type t_state_bit = logic [7-1:0];
    typedef 
    enum logic [7-1:0] {
        STATE_IDLE = 7'b0000000,
        STATE_PREAMBLE = 7'b0000001,
        STATE_LENGTH = 7'b0000010,
        STATE_TYPE = 7'b0000100,
        STATE_NODE = 7'b0001000,
        STATE_PAYLOAD = 7'b0010000,
        STATE_FCS = 7'b0100000,
        STATE_ERROR = 7'b1000000
    } STATE;

    STATE       state    ;
    t_state_bit state_bit;
    assign state_bit = t_state_bit'(state);

    localparam type t_count  = logic [4-1:0];
    localparam type t_length = logic [16-1:0];

    t_count          count     ;
    logic            preamble  ;
    logic            fcs_last  ;
    logic            crc_update;
    logic            crc_check ;
    logic   [32-1:0] crc_value ;
    logic            tx_first  ;
    logic            tx_last   ;
    logic   [8-1:0]  tx_data   ;
    logic            tx_valid  ;

    t_length payload_pos_next;
    assign payload_pos_next = payload_pos + t_length'(1);

    always_ff @ (posedge clk) begin
        if (reset) begin
            state         <= STATE_IDLE;
            count         <= 'x;
            preamble      <= 1'b0;
            payload_first <= 'x;
            payload_last  <= 'x;
            payload_pos   <= 'x;
            fcs_last      <= 'x;
            crc_update    <= 'x;
            crc_check     <= 1'b0;

            rx_start  <= 1'b0;
            rx_end    <= 1'b0;
            rx_error  <= 1'b0;
            rx_length <= 'x;
            rx_type   <= 'x;
            rx_node   <= 'x;

            tx_first <= 'x;
            tx_last  <= 'x;
            tx_data  <= 'x;
            tx_valid <= 1'b0;

        end else begin
            rx_start  <= 1'b0;
            rx_end    <= 1'b0;
            rx_error  <= 1'b0;
            crc_check <= 1'b0;

            tx_first <= 1'bx;
            tx_last  <= 1'bx;
            tx_data  <= 'x;
            tx_valid <= 1'b0;

            if (s_valid) begin
                tx_first <= s_first;
                tx_last  <= s_last;
                tx_data  <= s_data;
                tx_valid <= s_valid;

                if (count != '1) begin
                    count <= count + 1'b1;
                end

                payload_first <= 1'b0;
                payload_last  <= 1'b0;
                fcs_last      <= 1'b0;

                case (state)
                    STATE_IDLE: begin
                        if (s_first) begin
                            if (s_data == 8'h55 && !s_last) begin
                                state    <= STATE_PREAMBLE;
                                rx_start <= 1'b1;
                                count    <= '0;
                            end else begin
                                // 送信開始前なので何も中継せずに止める
                                state    <= STATE_ERROR;
                                rx_error <= 1'b1;
                                count    <= 'x;
                                tx_first <= 'x;
                                tx_last  <= 'x;
                                tx_data  <= 'x;
                                tx_valid <= 1'b0;
                            end
                            crc_update <= 'x;
                        end
                    end

                    STATE_PREAMBLE: begin
                        if (count == t_count'(6)) begin
                            state      <= STATE_LENGTH;
                            count      <= '0;
                            crc_update <= 1'b0;
                        end
                    end

                    STATE_LENGTH: begin
                        if (count[0:0] == 1'b1) begin
                            rx_length[15:8] <= s_data;
                            crc_update      <= 1'b1;
                            state           <= STATE_TYPE;
                            count           <= 'x;
                        end else begin
                            rx_length[7:0] <= s_data;
                            crc_update     <= 1'b1;
                        end
                    end

                    STATE_TYPE: begin
                        rx_type <= s_data;
                        state   <= STATE_NODE;
                        count   <= 'x;
                    end

                    STATE_NODE: begin
                        rx_node       <= s_data;
                        state         <= STATE_PAYLOAD;
                        payload_first <= 1'b1;
                        payload_last  <= (rx_length == '0);
                        payload_pos   <= '0;
                        if (DOWN_STREAM) begin
                            tx_data <= s_data - 8'd1;
                        end else begin
                            tx_data <= s_data + 8'd1;
                        end
                    end

                    STATE_PAYLOAD: begin
                        payload_first <= 1'b0;
                        payload_last  <= (payload_pos_next == rx_length);
                        payload_pos   <= payload_pos_next;
                        if (payload_last) begin
                            state     <= STATE_FCS;
                            fcs_last  <= 1'b0;
                            count     <= '0;
                            rx_length <= 'x;
                        end
                    end

                    STATE_FCS: begin
                        fcs_last <= (count[1:0] == 2'd2);
                        if (fcs_last) begin
                            state     <= STATE_IDLE;
                            crc_check <= 1'b1;
                        end
                    end

                    default: begin
                        state <= STATE_IDLE;
                    end
                endcase

                // 不正状態検知
                if ((s_first && state != STATE_IDLE && state != STATE_ERROR) || (s_last && !s_first && !fcs_last) || (state == STATE_PREAMBLE && !((count == 4'd6 && s_data == 8'hd5) || (count != 4'd6 && s_data == 8'h55)))) begin
                    // パケットを打ち切る
                    state    <= STATE_ERROR;
                    rx_error <= 1'b1;
                    tx_first <= 1'b0;
                    tx_last  <= 1'b1;
                    tx_data  <= '0;
                    tx_valid <= 1'b1;
                end
            end

            // エラー処理
            if (state == STATE_ERROR) begin
                state     <= STATE_IDLE;
                rx_type   <= 'x;
                rx_node   <= 'x;
                rx_length <= 'x;
                tx_first  <= 'x;
                tx_last   <= 'x;
                tx_data   <= 'x;
                tx_valid  <= 1'b0;
            end

            // CRC チェック
            if (crc_check) begin
                if (crc_value == 32'h2144df1c) begin
                    rx_end <= 1'b1;
                end else begin
                    rx_error <= 1'b1;
                end
            end
        end
    end

    assign payload_data  = s_data;
    assign payload_valid = s_valid & state_bit[BIT_PAYLOAD];

    jelly2_calc_crc #(
        .DATA_WIDTH (8           ),
        .CRC_WIDTH  (32          ),
        .POLY_REPS  (32'h04C11DB7),
        .REVERSED   (0           )
    ) u_cacl_crc_rx (
        .reset (reset),
        .clk   (clk  ),
        .cke   (1'b1 ),
        .
        in_update (crc_update),
        .in_data   (s_data    ),
        .in_valid  (s_valid   ),
        .
        out_crc (crc_value)
    );

endmodule
