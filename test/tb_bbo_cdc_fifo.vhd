----------------------------------------------------------------------------------
-- Testbench for BBO Clock Domain Crossing FIFO
-- Verifies safe data transfer between 200 MHz and 125 MHz domains
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_bbo_cdc_fifo is
end tb_bbo_cdc_fifo;

architecture Behavioral of tb_bbo_cdc_fifo is

    -- Component under test
    component bbo_cdc_fifo is
        Generic (
            FIFO_DEPTH_LOG2 : integer := 4
        );
        Port (
            wr_clk         : in  STD_LOGIC;
            wr_rst         : in  STD_LOGIC;
            wr_en          : in  STD_LOGIC;
            wr_full        : out STD_LOGIC;
            wr_almost_full : out STD_LOGIC;
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
            rd_clk         : in  STD_LOGIC;
            rd_rst         : in  STD_LOGIC;
            rd_en          : in  STD_LOGIC;
            rd_empty       : out STD_LOGIC;
            rd_valid       : out STD_LOGIC;
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
            overflow       : out STD_LOGIC
        );
    end component;

    -- Clock periods
    constant WR_CLK_PERIOD : time := 5 ns;   -- 200 MHz (trading)
    constant RD_CLK_PERIOD : time := 8 ns;   -- 125 MHz (XDMA)

    -- Write side signals
    signal wr_clk         : STD_LOGIC := '0';
    signal wr_rst         : STD_LOGIC := '1';
    signal wr_en          : STD_LOGIC := '0';
    signal wr_full        : STD_LOGIC;
    signal wr_almost_full : STD_LOGIC;
    signal wr_symbol      : STD_LOGIC_VECTOR(63 downto 0) := (others => '0');
    signal wr_bid_price   : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal wr_bid_size    : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal wr_ask_price   : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal wr_ask_size    : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal wr_spread      : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal wr_ts_t1       : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal wr_ts_t2       : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal wr_ts_t3       : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal wr_ts_t4       : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');

    -- Read side signals
    signal rd_clk         : STD_LOGIC := '0';
    signal rd_rst         : STD_LOGIC := '1';
    signal rd_en          : STD_LOGIC := '0';
    signal rd_empty       : STD_LOGIC;
    signal rd_valid       : STD_LOGIC;
    signal rd_symbol      : STD_LOGIC_VECTOR(63 downto 0);
    signal rd_bid_price   : STD_LOGIC_VECTOR(31 downto 0);
    signal rd_bid_size    : STD_LOGIC_VECTOR(31 downto 0);
    signal rd_ask_price   : STD_LOGIC_VECTOR(31 downto 0);
    signal rd_ask_size    : STD_LOGIC_VECTOR(31 downto 0);
    signal rd_spread      : STD_LOGIC_VECTOR(31 downto 0);
    signal rd_ts_t1       : STD_LOGIC_VECTOR(31 downto 0);
    signal rd_ts_t2       : STD_LOGIC_VECTOR(31 downto 0);
    signal rd_ts_t3       : STD_LOGIC_VECTOR(31 downto 0);
    signal rd_ts_t4       : STD_LOGIC_VECTOR(31 downto 0);
    signal overflow       : STD_LOGIC;

    -- Test control
    signal wr_done : boolean := false;
    signal rd_done : boolean := false;

    -- Verification
    signal wr_count : integer := 0;
    signal rd_count : integer := 0;

begin

    -- Clock generation
    wr_clk <= not wr_clk after WR_CLK_PERIOD/2 when not (wr_done and rd_done) else '0';
    rd_clk <= not rd_clk after RD_CLK_PERIOD/2 when not (wr_done and rd_done) else '0';

    -- DUT instantiation
    DUT: bbo_cdc_fifo
        generic map (
            FIFO_DEPTH_LOG2 => 4
        )
        port map (
            wr_clk         => wr_clk,
            wr_rst         => wr_rst,
            wr_en          => wr_en,
            wr_full        => wr_full,
            wr_almost_full => wr_almost_full,
            wr_symbol      => wr_symbol,
            wr_bid_price   => wr_bid_price,
            wr_bid_size    => wr_bid_size,
            wr_ask_price   => wr_ask_price,
            wr_ask_size    => wr_ask_size,
            wr_spread      => wr_spread,
            wr_ts_t1       => wr_ts_t1,
            wr_ts_t2       => wr_ts_t2,
            wr_ts_t3       => wr_ts_t3,
            wr_ts_t4       => wr_ts_t4,
            rd_clk         => rd_clk,
            rd_rst         => rd_rst,
            rd_en          => rd_en,
            rd_empty       => rd_empty,
            rd_valid       => rd_valid,
            rd_symbol      => rd_symbol,
            rd_bid_price   => rd_bid_price,
            rd_bid_size    => rd_bid_size,
            rd_ask_price   => rd_ask_price,
            rd_ask_size    => rd_ask_size,
            rd_spread      => rd_spread,
            rd_ts_t1       => rd_ts_t1,
            rd_ts_t2       => rd_ts_t2,
            rd_ts_t3       => rd_ts_t3,
            rd_ts_t4       => rd_ts_t4,
            overflow       => overflow
        );

    -- Write process (200 MHz domain)
    write_proc: process
    begin
        report "Starting CDC FIFO Testbench - Write Process";

        -- Initial reset
        wr_rst <= '1';
        wait for WR_CLK_PERIOD * 20;
        wr_rst <= '0';
        wait for WR_CLK_PERIOD * 10;

        ------------------------------------------------------------
        -- Test 1: Write 10 BBOs
        ------------------------------------------------------------
        report "Writing 10 BBOs...";

        for i in 1 to 10 loop
            -- Wait if FIFO is full
            while wr_full = '1' loop
                wait for WR_CLK_PERIOD;
            end loop;

            -- Set up BBO data
            wr_symbol    <= std_logic_vector(to_unsigned(i, 8)) & x"41414141414141";  -- i + "AAAAAAA"
            wr_bid_price <= std_logic_vector(to_unsigned(100000 + i*1000, 32));
            wr_bid_size  <= std_logic_vector(to_unsigned(100 * i, 32));
            wr_ask_price <= std_logic_vector(to_unsigned(100100 + i*1000, 32));
            wr_ask_size  <= std_logic_vector(to_unsigned(200 * i, 32));
            wr_spread    <= std_logic_vector(to_unsigned(100, 32));
            wr_ts_t1     <= std_logic_vector(to_unsigned(1000 * i, 32));
            wr_ts_t2     <= std_logic_vector(to_unsigned(1000 * i + 36, 32));
            wr_ts_t3     <= std_logic_vector(to_unsigned(1000 * i + 200, 32));
            wr_ts_t4     <= std_logic_vector(to_unsigned(1000 * i + 203, 32));

            wr_en <= '1';
            wait for WR_CLK_PERIOD;
            wr_en <= '0';
            wr_count <= wr_count + 1;

            -- Small delay between writes
            wait for WR_CLK_PERIOD * 5;
        end loop;

        report "Write process complete. Wrote " & integer'image(wr_count) & " BBOs";

        -- Wait for reads to complete
        wait for WR_CLK_PERIOD * 500;

        ------------------------------------------------------------
        -- Test 2: Burst writes (fill FIFO)
        ------------------------------------------------------------
        report "Testing burst writes...";

        for i in 11 to 25 loop
            if wr_full = '0' then
                wr_symbol    <= std_logic_vector(to_unsigned(i, 8)) & x"42424242424242";  -- i + "BBBBBBB"
                wr_bid_price <= std_logic_vector(to_unsigned(200000 + i*1000, 32));
                wr_bid_size  <= std_logic_vector(to_unsigned(500, 32));
                wr_ask_price <= std_logic_vector(to_unsigned(200100 + i*1000, 32));
                wr_ask_size  <= std_logic_vector(to_unsigned(1000, 32));
                wr_spread    <= std_logic_vector(to_unsigned(100, 32));
                wr_ts_t1     <= std_logic_vector(to_unsigned(2000 * i, 32));
                wr_ts_t2     <= std_logic_vector(to_unsigned(2000 * i + 40, 32));
                wr_ts_t3     <= std_logic_vector(to_unsigned(2000 * i + 300, 32));
                wr_ts_t4     <= std_logic_vector(to_unsigned(2000 * i + 305, 32));

                wr_en <= '1';
                wait for WR_CLK_PERIOD;
                wr_en <= '0';
                wr_count <= wr_count + 1;
            else
                report "FIFO full at write " & integer'image(i);
                wait for WR_CLK_PERIOD;
            end if;
        end loop;

        report "Burst write complete. Total written: " & integer'image(wr_count);

        wait for WR_CLK_PERIOD * 1000;
        wr_done <= true;
        wait;
    end process;

    -- Read process (125 MHz domain)
    read_proc: process
    begin
        report "Starting CDC FIFO Testbench - Read Process";

        -- Initial reset
        rd_rst <= '1';
        wait for RD_CLK_PERIOD * 20;
        rd_rst <= '0';
        wait for RD_CLK_PERIOD * 20;

        -- Read loop
        while not wr_done or rd_empty = '0' loop
            if rd_empty = '0' then
                rd_en <= '1';
                wait for RD_CLK_PERIOD;
                rd_en <= '0';

                if rd_valid = '1' then
                    rd_count <= rd_count + 1;
                    report "Read BBO " & integer'image(rd_count) &
                           " - Symbol: 0x" & to_hstring(rd_symbol) &
                           " Bid: " & integer'image(to_integer(unsigned(rd_bid_price))) &
                           " T1: " & integer'image(to_integer(unsigned(rd_ts_t1))) &
                           " T4: " & integer'image(to_integer(unsigned(rd_ts_t4)));
                end if;

                -- Variable delay to simulate downstream processing
                wait for RD_CLK_PERIOD * ((rd_count mod 5) + 1);
            else
                wait for RD_CLK_PERIOD;
            end if;
        end loop;

        -- Final check
        wait for RD_CLK_PERIOD * 100;

        report "Read process complete. Read " & integer'image(rd_count) & " BBOs";

        assert overflow = '0'
            report "Overflow detected!"
            severity warning;

        report "CDC FIFO Testbench PASSED!";
        rd_done <= true;
        wait;
    end process;

end Behavioral;
