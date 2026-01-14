// Simple UART TX Debug Module for PCIe Project
// Outputs periodic debug messages: "PCIe:XX\r\n" where XX = link status + counter
// 115200 baud at 250 MHz clock
//
// Output format every ~0.5 second:
//   "L=X C=XXXXXXXX\r\n"
//   L = Link status (0 or 1)
//   C = 32-bit counter value (hex)

module uart_debug_tx #(
    parameter CLK_FREQ = 250_000_000,  // 250 MHz (XDMA axi_aclk)
    parameter BAUD_RATE = 115200
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        link_up,
    input  wire [31:0] counter_val,
    output reg         uart_tx
);

    // Baud rate generator
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;  // ~2170 clocks per bit

    reg [11:0] baud_cnt;
    reg baud_tick;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_cnt <= 0;
            baud_tick <= 0;
        end else begin
            if (baud_cnt >= CLKS_PER_BIT - 1) begin
                baud_cnt <= 0;
                baud_tick <= 1;
            end else begin
                baud_cnt <= baud_cnt + 1;
                baud_tick <= 0;
            end
        end
    end

    // Message interval (~0.5 second = 125M clocks at 250MHz)
    localparam MSG_INTERVAL = CLK_FREQ / 2;
    reg [27:0] msg_timer;
    reg msg_trigger;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            msg_timer <= 0;
            msg_trigger <= 0;
        end else begin
            if (msg_timer >= MSG_INTERVAL - 1) begin
                msg_timer <= 0;
                msg_trigger <= 1;
            end else begin
                msg_timer <= msg_timer + 1;
                msg_trigger <= 0;
            end
        end
    end

    // TX state machine
    localparam IDLE = 0, LOAD = 1, START = 2, DATA = 3, STOP = 4, NEXT = 5;
    reg [2:0] state;
    reg [3:0] bit_cnt;
    reg [7:0] tx_byte;
    reg [4:0] msg_idx;

    // Message buffer: "L=X C=XXXXXXXX\r\n" (16 chars)
    reg [7:0] msg_buf [0:15];
    reg [31:0] latched_counter;
    reg latched_link;

    // Hex to ASCII conversion
    function [7:0] hex_to_ascii;
        input [3:0] hex;
        begin
            if (hex < 10)
                hex_to_ascii = 8'h30 + hex;  // '0'-'9'
            else
                hex_to_ascii = 8'h41 + hex - 10;  // 'A'-'F'
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            uart_tx <= 1;
            bit_cnt <= 0;
            msg_idx <= 0;
            latched_counter <= 0;
            latched_link <= 0;
        end else begin
            case (state)
                IDLE: begin
                    uart_tx <= 1;
                    if (msg_trigger) begin
                        // Latch current values
                        latched_counter <= counter_val;
                        latched_link <= link_up;

                        // Build message: "L=X C=XXXXXXXX\r\n"
                        msg_buf[0]  <= "L";
                        msg_buf[1]  <= "=";
                        msg_buf[2]  <= link_up ? "1" : "0";
                        msg_buf[3]  <= " ";
                        msg_buf[4]  <= "C";
                        msg_buf[5]  <= "=";
                        msg_buf[6]  <= hex_to_ascii(counter_val[31:28]);
                        msg_buf[7]  <= hex_to_ascii(counter_val[27:24]);
                        msg_buf[8]  <= hex_to_ascii(counter_val[23:20]);
                        msg_buf[9]  <= hex_to_ascii(counter_val[19:16]);
                        msg_buf[10] <= hex_to_ascii(counter_val[15:12]);
                        msg_buf[11] <= hex_to_ascii(counter_val[11:8]);
                        msg_buf[12] <= hex_to_ascii(counter_val[7:4]);
                        msg_buf[13] <= hex_to_ascii(counter_val[3:0]);
                        msg_buf[14] <= 8'h0D;  // CR
                        msg_buf[15] <= 8'h0A;  // LF

                        msg_idx <= 0;
                        state <= LOAD;
                    end
                end

                LOAD: begin
                    tx_byte <= msg_buf[msg_idx];
                    bit_cnt <= 0;
                    state <= START;
                end

                START: begin
                    if (baud_tick) begin
                        uart_tx <= 0;  // Start bit
                        state <= DATA;
                    end
                end

                DATA: begin
                    if (baud_tick) begin
                        uart_tx <= tx_byte[bit_cnt];
                        if (bit_cnt == 7) begin
                            state <= STOP;
                        end else begin
                            bit_cnt <= bit_cnt + 1;
                        end
                    end
                end

                STOP: begin
                    if (baud_tick) begin
                        uart_tx <= 1;  // Stop bit
                        state <= NEXT;
                    end
                end

                NEXT: begin
                    if (baud_tick) begin
                        if (msg_idx == 15) begin
                            state <= IDLE;
                        end else begin
                            msg_idx <= msg_idx + 1;
                            state <= LOAD;
                        end
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
