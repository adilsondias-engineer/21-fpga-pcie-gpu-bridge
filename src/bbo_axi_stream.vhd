----------------------------------------------------------------------------------
-- BBO to AXI-Stream Converter
-- Converts 44-byte BBO messages to 64-bit AXI-Stream for XDMA C2H DMA
--
-- BBO Message Format (44 bytes):
--   Bytes 0-7:   Symbol (8 bytes)
--   Bytes 8-11:  Bid Price (4 bytes)
--   Bytes 12-15: Bid Size (4 bytes)
--   Bytes 16-19: Ask Price (4 bytes)
--   Bytes 20-23: Ask Size (4 bytes)
--   Bytes 24-27: Spread (4 bytes)
--   Bytes 28-31: T1 timestamp (ITCH parse)
--   Bytes 32-35: T2 timestamp (CDC FIFO write)
--   Bytes 36-39: T3 timestamp (BBO FIFO read)
--   Bytes 40-43: T4 timestamp (TX start)
--
-- AXI-Stream Output:
--   64-bit data width (8 bytes per beat)
--   6 beats per BBO message (48 bytes, 4 bytes padding)
--   TLAST asserted on final beat
--
-- Clock Domain: axi_aclk (XDMA clock, 125 MHz with Gen1 x4)
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity bbo_axi_stream is
    Generic (
        C_AXI_DATA_WIDTH : integer := 64;   -- 64-bit AXI-Stream (XDMA default)
        C_BBO_SIZE       : integer := 44    -- BBO message size in bytes
    );
    Port (
        -- AXI clock and reset
        aclk           : in  STD_LOGIC;
        aresetn        : in  STD_LOGIC;

        -- BBO Input Interface (from order book)
        bbo_valid      : in  STD_LOGIC;
        bbo_ready      : out STD_LOGIC;
        bbo_symbol     : in  STD_LOGIC_VECTOR(63 downto 0);
        bbo_bid_price  : in  STD_LOGIC_VECTOR(31 downto 0);
        bbo_bid_size   : in  STD_LOGIC_VECTOR(31 downto 0);
        bbo_ask_price  : in  STD_LOGIC_VECTOR(31 downto 0);
        bbo_ask_size   : in  STD_LOGIC_VECTOR(31 downto 0);
        bbo_spread     : in  STD_LOGIC_VECTOR(31 downto 0);
        bbo_ts_t1      : in  STD_LOGIC_VECTOR(31 downto 0);
        bbo_ts_t2      : in  STD_LOGIC_VECTOR(31 downto 0);
        bbo_ts_t3      : in  STD_LOGIC_VECTOR(31 downto 0);
        bbo_ts_t4      : in  STD_LOGIC_VECTOR(31 downto 0);

        -- AXI-Stream Master Interface (to XDMA C2H)
        m_axis_tdata   : out STD_LOGIC_VECTOR(C_AXI_DATA_WIDTH-1 downto 0);
        m_axis_tkeep   : out STD_LOGIC_VECTOR(C_AXI_DATA_WIDTH/8-1 downto 0);
        m_axis_tvalid  : out STD_LOGIC;
        m_axis_tready  : in  STD_LOGIC;
        m_axis_tlast   : out STD_LOGIC;

        -- Status outputs
        bbo_count      : out STD_LOGIC_VECTOR(31 downto 0);
        fifo_overflow  : out STD_LOGIC
    );
end bbo_axi_stream;

architecture Behavioral of bbo_axi_stream is

    -- State machine for AXI-Stream transmission (6 beats for 48 bytes)
    type state_type is (IDLE, BEAT1, BEAT2, BEAT3, BEAT4, BEAT5, BEAT6);
    signal state : state_type := IDLE;

    -- Latched BBO data (352 bits = 44 bytes)
    signal bbo_latched : STD_LOGIC_VECTOR(351 downto 0) := (others => '0');

    -- Padding for 48-byte alignment (4 bytes = 32 bits)
    constant PADDING : STD_LOGIC_VECTOR(31 downto 0) := x"DEADBEEF";

    -- Counter for transmitted BBOs
    signal bbo_counter : unsigned(31 downto 0) := (others => '0');

    -- Internal signals
    signal tdata_int  : STD_LOGIC_VECTOR(63 downto 0) := (others => '0');
    signal tvalid_int : STD_LOGIC := '0';
    signal tlast_int  : STD_LOGIC := '0';
    signal tkeep_int  : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');
    signal ready_int  : STD_LOGIC := '1';

begin

    -- Output assignments
    m_axis_tdata  <= tdata_int;
    m_axis_tvalid <= tvalid_int;
    m_axis_tlast  <= tlast_int;
    m_axis_tkeep  <= tkeep_int;
    bbo_ready     <= ready_int;
    bbo_count     <= std_logic_vector(bbo_counter);

    -- No overflow detection in this simple implementation
    fifo_overflow <= '0';

    -- Main state machine
    process(aclk)
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                state <= IDLE;
                tvalid_int <= '0';
                tlast_int <= '0';
                tkeep_int <= (others => '0');
                tdata_int <= (others => '0');
                bbo_latched <= (others => '0');
                bbo_counter <= (others => '0');
                ready_int <= '1';
            else
                case state is
                    when IDLE =>
                        tvalid_int <= '0';
                        tlast_int <= '0';
                        ready_int <= '1';

                        if bbo_valid = '1' then
                            -- Latch all BBO data (44 bytes = 352 bits)
                            -- Format: Symbol[63:0] | BidPrice[31:0] | BidSize[31:0] | AskPrice[31:0] |
                            --         AskSize[31:0] | Spread[31:0] | T1[31:0] | T2[31:0] | T3[31:0] | T4[31:0]
                            bbo_latched <= bbo_symbol &
                                          bbo_bid_price & bbo_bid_size &
                                          bbo_ask_price & bbo_ask_size &
                                          bbo_spread &
                                          bbo_ts_t1 & bbo_ts_t2 & bbo_ts_t3 & bbo_ts_t4;

                            ready_int <= '0';
                            state <= BEAT1;
                        end if;

                    when BEAT1 =>
                        -- Beat 1: Bytes 0-7 (Symbol)
                        tdata_int <= bbo_latched(351 downto 288);  -- Symbol[63:0]
                        tkeep_int <= (others => '1');  -- All 8 bytes valid
                        tvalid_int <= '1';
                        tlast_int <= '0';

                        if m_axis_tready = '1' and tvalid_int = '1' then
                            state <= BEAT2;
                        end if;

                    when BEAT2 =>
                        -- Beat 2: Bytes 8-15 (BidPrice + BidSize)
                        tdata_int <= bbo_latched(287 downto 224);  -- BidPrice[31:0] | BidSize[31:0]
                        tkeep_int <= (others => '1');
                        tvalid_int <= '1';
                        tlast_int <= '0';

                        if m_axis_tready = '1' and tvalid_int = '1' then
                            state <= BEAT3;
                        end if;

                    when BEAT3 =>
                        -- Beat 3: Bytes 16-23 (AskPrice + AskSize)
                        tdata_int <= bbo_latched(223 downto 160);  -- AskPrice[31:0] | AskSize[31:0]
                        tkeep_int <= (others => '1');
                        tvalid_int <= '1';
                        tlast_int <= '0';

                        if m_axis_tready = '1' and tvalid_int = '1' then
                            state <= BEAT4;
                        end if;

                    when BEAT4 =>
                        -- Beat 4: Bytes 24-31 (Spread + T1)
                        tdata_int <= bbo_latched(159 downto 96);  -- Spread[31:0] | T1[31:0]
                        tkeep_int <= (others => '1');
                        tvalid_int <= '1';
                        tlast_int <= '0';

                        if m_axis_tready = '1' and tvalid_int = '1' then
                            state <= BEAT5;
                        end if;

                    when BEAT5 =>
                        -- Beat 5: Bytes 32-39 (T2 + T3)
                        tdata_int <= bbo_latched(95 downto 32);  -- T2[31:0] | T3[31:0]
                        tkeep_int <= (others => '1');
                        tvalid_int <= '1';
                        tlast_int <= '0';

                        if m_axis_tready = '1' and tvalid_int = '1' then
                            state <= BEAT6;
                        end if;

                    when BEAT6 =>
                        -- Beat 6: Bytes 40-47 (T4 + Padding)
                        tdata_int <= bbo_latched(31 downto 0) & PADDING;  -- T4[31:0] | PADDING[31:0]
                        tkeep_int <= x"F0";  -- First 4 bytes valid (T4), last 4 padding
                        tvalid_int <= '1';
                        tlast_int <= '1';  -- Last beat of this BBO

                        if m_axis_tready = '1' and tvalid_int = '1' then
                            -- Transaction complete
                            bbo_counter <= bbo_counter + 1;
                            tvalid_int <= '0';
                            tlast_int <= '0';
                            state <= IDLE;
                        end if;

                end case;
            end if;
        end if;
    end process;

end Behavioral;
