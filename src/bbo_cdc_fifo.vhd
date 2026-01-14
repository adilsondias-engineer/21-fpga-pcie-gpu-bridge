----------------------------------------------------------------------------------
-- BBO Clock Domain Crossing FIFO
-- Transfers BBO data from trading clock (200 MHz) to XDMA clock (125-250 MHz)
--
-- Uses asynchronous FIFO with gray-code pointers for safe CDC
-- FIFO depth: 16 entries (should be sufficient for burst handling)
--
-- Input Clock: clk_trading (200 MHz order book domain)
-- Output Clock: axi_aclk (XDMA clock domain)
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity bbo_cdc_fifo is
    Generic (
        FIFO_DEPTH_LOG2 : integer := 4   -- 2^4 = 16 entries
    );
    Port (
        -- Write side (Trading clock domain - 200 MHz)
        wr_clk         : in  STD_LOGIC;
        wr_rst         : in  STD_LOGIC;
        wr_en          : in  STD_LOGIC;
        wr_full        : out STD_LOGIC;
        wr_almost_full : out STD_LOGIC;

        -- BBO data input
        wr_symbol      : in  STD_LOGIC_VECTOR(63 downto 0);
        wr_bid_price   : in  STD_LOGIC_VECTOR(31 downto 0);
        wr_bid_size    : in  STD_LOGIC_VECTOR(31 downto 0);
        wr_ask_price   : in  STD_LOGIC_VECTOR(31 downto 0);
        wr_ask_size    : in  STD_LOGIC_VECTOR(31 downto 0);
        wr_spread      : in  STD_LOGIC_VECTOR(31 downto 0);
        wr_ts_t1       : in  STD_LOGIC_VECTOR(31 downto 0);
        wr_ts_t2       : in  STD_LOGIC_VECTOR(31 downto 0);
        wr_ts_t3       : in  STD_LOGIC_VECTOR(31 downto 0);
        wr_ts_t4       : in  STD_LOGIC_VECTOR(31 downto 0);

        -- Read side (XDMA clock domain)
        rd_clk         : in  STD_LOGIC;
        rd_rst         : in  STD_LOGIC;
        rd_en          : in  STD_LOGIC;
        rd_empty       : out STD_LOGIC;
        rd_valid       : out STD_LOGIC;

        -- BBO data output
        rd_symbol      : out STD_LOGIC_VECTOR(63 downto 0);
        rd_bid_price   : out STD_LOGIC_VECTOR(31 downto 0);
        rd_bid_size    : out STD_LOGIC_VECTOR(31 downto 0);
        rd_ask_price   : out STD_LOGIC_VECTOR(31 downto 0);
        rd_ask_size    : out STD_LOGIC_VECTOR(31 downto 0);
        rd_spread      : out STD_LOGIC_VECTOR(31 downto 0);
        rd_ts_t1       : out STD_LOGIC_VECTOR(31 downto 0);
        rd_ts_t2       : out STD_LOGIC_VECTOR(31 downto 0);
        rd_ts_t3       : out STD_LOGIC_VECTOR(31 downto 0);
        rd_ts_t4       : out STD_LOGIC_VECTOR(31 downto 0);

        -- Overflow flag (sticky, in read clock domain)
        overflow       : out STD_LOGIC
    );
end bbo_cdc_fifo;

architecture Behavioral of bbo_cdc_fifo is

    constant FIFO_DEPTH : integer := 2**FIFO_DEPTH_LOG2;
    constant DATA_WIDTH : integer := 352;  -- 44 bytes * 8 bits

    -- FIFO memory (352 bits wide)
    type fifo_mem_type is array (0 to FIFO_DEPTH-1) of STD_LOGIC_VECTOR(DATA_WIDTH-1 downto 0);
    signal fifo_mem : fifo_mem_type := (others => (others => '0'));

    -- Write domain signals
    signal wr_ptr_bin  : unsigned(FIFO_DEPTH_LOG2 downto 0) := (others => '0');
    signal wr_ptr_gray : STD_LOGIC_VECTOR(FIFO_DEPTH_LOG2 downto 0) := (others => '0');
    signal rd_ptr_gray_sync1 : STD_LOGIC_VECTOR(FIFO_DEPTH_LOG2 downto 0) := (others => '0');
    signal rd_ptr_gray_sync2 : STD_LOGIC_VECTOR(FIFO_DEPTH_LOG2 downto 0) := (others => '0');
    signal wr_full_int : STD_LOGIC := '0';

    -- Read domain signals
    signal rd_ptr_bin  : unsigned(FIFO_DEPTH_LOG2 downto 0) := (others => '0');
    signal rd_ptr_gray : STD_LOGIC_VECTOR(FIFO_DEPTH_LOG2 downto 0) := (others => '0');
    signal wr_ptr_gray_sync1 : STD_LOGIC_VECTOR(FIFO_DEPTH_LOG2 downto 0) := (others => '0');
    signal wr_ptr_gray_sync2 : STD_LOGIC_VECTOR(FIFO_DEPTH_LOG2 downto 0) := (others => '0');
    signal rd_empty_int : STD_LOGIC := '1';

    -- Data read from FIFO
    signal rd_data : STD_LOGIC_VECTOR(DATA_WIDTH-1 downto 0) := (others => '0');

    -- Overflow detection
    signal overflow_wr : STD_LOGIC := '0';
    signal overflow_sync1 : STD_LOGIC := '0';
    signal overflow_sync2 : STD_LOGIC := '0';

    -- Function to convert binary to gray code
    function bin_to_gray(bin : unsigned) return STD_LOGIC_VECTOR is
        variable gray : STD_LOGIC_VECTOR(bin'range);
    begin
        gray := std_logic_vector(bin xor ('0' & bin(bin'left downto 1)));
        return gray;
    end function;

begin

    -- Output assignments
    wr_full <= wr_full_int;
    wr_almost_full <= '1' when (wr_ptr_bin - unsigned(rd_ptr_gray_sync2(FIFO_DEPTH_LOG2-1 downto 0))) >= FIFO_DEPTH - 2 else '0';
    rd_empty <= rd_empty_int;
    overflow <= overflow_sync2;

    -- Unpack read data
    rd_symbol    <= rd_data(351 downto 288);
    rd_bid_price <= rd_data(287 downto 256);
    rd_bid_size  <= rd_data(255 downto 224);
    rd_ask_price <= rd_data(223 downto 192);
    rd_ask_size  <= rd_data(191 downto 160);
    rd_spread    <= rd_data(159 downto 128);
    rd_ts_t1     <= rd_data(127 downto 96);
    rd_ts_t2     <= rd_data(95 downto 64);
    rd_ts_t3     <= rd_data(63 downto 32);
    rd_ts_t4     <= rd_data(31 downto 0);

    -- Write process (trading clock domain)
    process(wr_clk)
        variable wr_data : STD_LOGIC_VECTOR(DATA_WIDTH-1 downto 0);
    begin
        if rising_edge(wr_clk) then
            if wr_rst = '1' then
                wr_ptr_bin <= (others => '0');
                wr_ptr_gray <= (others => '0');
                overflow_wr <= '0';
            else
                -- Synchronize read pointer to write domain (2-FF synchronizer)
                rd_ptr_gray_sync1 <= rd_ptr_gray;
                rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;

                -- Full detection (compare gray codes)
                -- FIFO is full when write pointer is one cycle ahead of read pointer
                -- In gray code: MSB differs, rest are mirrored
                if (wr_ptr_gray(FIFO_DEPTH_LOG2) /= rd_ptr_gray_sync2(FIFO_DEPTH_LOG2)) and
                   (wr_ptr_gray(FIFO_DEPTH_LOG2-1) /= rd_ptr_gray_sync2(FIFO_DEPTH_LOG2-1)) and
                   (wr_ptr_gray(FIFO_DEPTH_LOG2-2 downto 0) = rd_ptr_gray_sync2(FIFO_DEPTH_LOG2-2 downto 0)) then
                    wr_full_int <= '1';
                else
                    wr_full_int <= '0';
                end if;

                -- Write logic
                if wr_en = '1' then
                    if wr_full_int = '0' then
                        -- Pack BBO data
                        wr_data := wr_symbol & wr_bid_price & wr_bid_size &
                                   wr_ask_price & wr_ask_size & wr_spread &
                                   wr_ts_t1 & wr_ts_t2 & wr_ts_t3 & wr_ts_t4;

                        -- Write to FIFO
                        fifo_mem(to_integer(wr_ptr_bin(FIFO_DEPTH_LOG2-1 downto 0))) <= wr_data;

                        -- Increment write pointer
                        wr_ptr_bin <= wr_ptr_bin + 1;
                        wr_ptr_gray <= bin_to_gray(wr_ptr_bin + 1);
                    else
                        -- Overflow condition (write attempted when full)
                        overflow_wr <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Read process (XDMA clock domain)
    process(rd_clk)
    begin
        if rising_edge(rd_clk) then
            if rd_rst = '1' then
                rd_ptr_bin <= (others => '0');
                rd_ptr_gray <= (others => '0');
                rd_valid <= '0';
                rd_data <= (others => '0');
                overflow_sync1 <= '0';
                overflow_sync2 <= '0';
            else
                -- Synchronize write pointer to read domain (2-FF synchronizer)
                wr_ptr_gray_sync1 <= wr_ptr_gray;
                wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;

                -- Synchronize overflow flag
                overflow_sync1 <= overflow_wr;
                overflow_sync2 <= overflow_sync1;

                -- Empty detection (pointers equal in gray code)
                if rd_ptr_gray = wr_ptr_gray_sync2 then
                    rd_empty_int <= '1';
                else
                    rd_empty_int <= '0';
                end if;

                -- Read logic
                rd_valid <= '0';
                if rd_en = '1' and rd_empty_int = '0' then
                    -- Read from FIFO
                    rd_data <= fifo_mem(to_integer(rd_ptr_bin(FIFO_DEPTH_LOG2-1 downto 0)));
                    rd_valid <= '1';

                    -- Increment read pointer
                    rd_ptr_bin <= rd_ptr_bin + 1;
                    rd_ptr_gray <= bin_to_gray(rd_ptr_bin + 1);
                end if;
            end if;
        end if;
    end process;

end Behavioral;
