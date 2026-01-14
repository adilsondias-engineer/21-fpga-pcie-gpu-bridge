----------------------------------------------------------------------------------
-- PCIe BBO Top - Custom Logic Wrapper for PCIe GPU Bridge
-- Integrates BBO streaming with XDMA block design
--
-- This module sits between the trading logic (order book) and the XDMA block design.
-- It handles:
--   1. Clock domain crossing from trading clock to XDMA clock
--   2. BBO to AXI-Stream conversion for C2H DMA
--   3. Latency calculation from 4-point timestamps
--   4. Control registers (via AXI-Lite)
--
-- Interfaces:
--   - Trading side: BBO data + timestamps from order book (200 MHz)
--   - PCIe side: AXI-Stream for C2H, AXI-Lite for control (axi_aclk)
--
-- Target: AX7203 (XC7A200T-2FBG484I)
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity pcie_bbo_top is
    Generic (
        C_AXI_DATA_WIDTH      : integer := 64;   -- 64-bit for XDMA C2H (250 MHz)
        C_AXI_LITE_DATA_WIDTH : integer := 32;
        C_AXI_LITE_ADDR_WIDTH : integer := 6
    );
    Port (
        -- Trading clock domain (200 MHz)
        clk_trading    : in  STD_LOGIC;
        rst_trading    : in  STD_LOGIC;

        -- BBO input from order book
        bbo_update     : in  STD_LOGIC;
        bbo_symbol     : in  STD_LOGIC_VECTOR(63 downto 0);
        bbo_bid_price  : in  STD_LOGIC_VECTOR(31 downto 0);
        bbo_bid_size   : in  STD_LOGIC_VECTOR(31 downto 0);
        bbo_ask_price  : in  STD_LOGIC_VECTOR(31 downto 0);
        bbo_ask_size   : in  STD_LOGIC_VECTOR(31 downto 0);
        bbo_spread     : in  STD_LOGIC_VECTOR(31 downto 0);

        -- 4-point timestamps (125 MHz cycle counts)
        ts_t1          : in  STD_LOGIC_VECTOR(31 downto 0);
        ts_t2          : in  STD_LOGIC_VECTOR(31 downto 0);
        ts_t3          : in  STD_LOGIC_VECTOR(31 downto 0);
        ts_t4          : in  STD_LOGIC_VECTOR(31 downto 0);

        -- XDMA clock domain (from block design)
        axi_aclk       : in  STD_LOGIC;
        axi_aresetn    : in  STD_LOGIC;

        -- AXI-Stream Master Interface (to C2H FIFO in block design)
        m_axis_tdata   : out STD_LOGIC_VECTOR(C_AXI_DATA_WIDTH-1 downto 0);
        m_axis_tkeep   : out STD_LOGIC_VECTOR(C_AXI_DATA_WIDTH/8-1 downto 0);
        m_axis_tvalid  : out STD_LOGIC;
        m_axis_tready  : in  STD_LOGIC;
        m_axis_tlast   : out STD_LOGIC;

        -- AXI-Lite Slave Interface (from block design interconnect)
        S_AXI_AWADDR   : in  STD_LOGIC_VECTOR(C_AXI_LITE_ADDR_WIDTH-1 downto 0);
        S_AXI_AWVALID  : in  STD_LOGIC;
        S_AXI_AWREADY  : out STD_LOGIC;
        S_AXI_WDATA    : in  STD_LOGIC_VECTOR(C_AXI_LITE_DATA_WIDTH-1 downto 0);
        S_AXI_WSTRB    : in  STD_LOGIC_VECTOR(C_AXI_LITE_DATA_WIDTH/8-1 downto 0);
        S_AXI_WVALID   : in  STD_LOGIC;
        S_AXI_WREADY   : out STD_LOGIC;
        S_AXI_BRESP    : out STD_LOGIC_VECTOR(1 downto 0);
        S_AXI_BVALID   : out STD_LOGIC;
        S_AXI_BREADY   : in  STD_LOGIC;
        S_AXI_ARADDR   : in  STD_LOGIC_VECTOR(C_AXI_LITE_ADDR_WIDTH-1 downto 0);
        S_AXI_ARVALID  : in  STD_LOGIC;
        S_AXI_ARREADY  : out STD_LOGIC;
        S_AXI_RDATA    : out STD_LOGIC_VECTOR(C_AXI_LITE_DATA_WIDTH-1 downto 0);
        S_AXI_RRESP    : out STD_LOGIC_VECTOR(1 downto 0);
        S_AXI_RVALID   : out STD_LOGIC;
        S_AXI_RREADY   : in  STD_LOGIC;

        -- Status LEDs
        led_link_up    : out STD_LOGIC;
        led_streaming  : out STD_LOGIC;
        led_overflow   : out STD_LOGIC
    );
end pcie_bbo_top;

architecture Behavioral of pcie_bbo_top is

    ---------------------------------------------------------------------------
    -- Vivado X_INTERFACE attributes for block design module reference
    -- These attributes tell Vivado how to infer AXI interfaces and clock associations
    ---------------------------------------------------------------------------

    -- Attribute declarations
    attribute X_INTERFACE_INFO : string;
    attribute X_INTERFACE_PARAMETER : string;

    -- Clock interface: axi_aclk drives m_axis and S_AXI
    -- PCIe Gen2 x4 with 64-bit AXI: XDMA axi_aclk = 250 MHz
    -- PCIe Gen1 x4 with 64-bit AXI: XDMA axi_aclk = 125 MHz
    -- FREQ_HZ left unspecified to allow Vivado to inherit from XDMA IP
    attribute X_INTERFACE_INFO of axi_aclk : signal is "xilinx.com:signal:clock:1.0 axi_aclk CLK";
    attribute X_INTERFACE_PARAMETER of axi_aclk : signal is "ASSOCIATED_BUSIF m_axis:S_AXI, ASSOCIATED_RESET axi_aresetn";

    -- Reset interface: axi_aresetn (active low)
    attribute X_INTERFACE_INFO of axi_aresetn : signal is "xilinx.com:signal:reset:1.0 axi_aresetn RST";
    attribute X_INTERFACE_PARAMETER of axi_aresetn : signal is "POLARITY ACTIVE_LOW";

    -- Trading clock interface (frequency not constrained - can be 200 MHz or use XDMA clock)
    attribute X_INTERFACE_INFO of clk_trading : signal is "xilinx.com:signal:clock:1.0 clk_trading CLK";
    attribute X_INTERFACE_PARAMETER of clk_trading : signal is "ASSOCIATED_RESET rst_trading";

    -- Trading reset interface
    attribute X_INTERFACE_INFO of rst_trading : signal is "xilinx.com:signal:reset:1.0 rst_trading RST";
    attribute X_INTERFACE_PARAMETER of rst_trading : signal is "POLARITY ACTIVE_HIGH";

    -- AXI-Stream Master interface (m_axis)
    attribute X_INTERFACE_INFO of m_axis_tdata : signal is "xilinx.com:interface:axis:1.0 m_axis TDATA";
    attribute X_INTERFACE_INFO of m_axis_tkeep : signal is "xilinx.com:interface:axis:1.0 m_axis TKEEP";
    attribute X_INTERFACE_INFO of m_axis_tvalid : signal is "xilinx.com:interface:axis:1.0 m_axis TVALID";
    attribute X_INTERFACE_INFO of m_axis_tready : signal is "xilinx.com:interface:axis:1.0 m_axis TREADY";
    attribute X_INTERFACE_INFO of m_axis_tlast : signal is "xilinx.com:interface:axis:1.0 m_axis TLAST";
    attribute X_INTERFACE_PARAMETER of m_axis_tdata : signal is "TDATA_NUM_BYTES 8, TDEST_WIDTH 0, TID_WIDTH 0, TUSER_WIDTH 0, HAS_TREADY 1, HAS_TSTRB 0, HAS_TKEEP 1, HAS_TLAST 1";

    -- AXI-Lite Slave interface (S_AXI)
    attribute X_INTERFACE_INFO of S_AXI_AWADDR : signal is "xilinx.com:interface:aximm:1.0 S_AXI AWADDR";
    attribute X_INTERFACE_INFO of S_AXI_AWVALID : signal is "xilinx.com:interface:aximm:1.0 S_AXI AWVALID";
    attribute X_INTERFACE_INFO of S_AXI_AWREADY : signal is "xilinx.com:interface:aximm:1.0 S_AXI AWREADY";
    attribute X_INTERFACE_INFO of S_AXI_WDATA : signal is "xilinx.com:interface:aximm:1.0 S_AXI WDATA";
    attribute X_INTERFACE_INFO of S_AXI_WSTRB : signal is "xilinx.com:interface:aximm:1.0 S_AXI WSTRB";
    attribute X_INTERFACE_INFO of S_AXI_WVALID : signal is "xilinx.com:interface:aximm:1.0 S_AXI WVALID";
    attribute X_INTERFACE_INFO of S_AXI_WREADY : signal is "xilinx.com:interface:aximm:1.0 S_AXI WREADY";
    attribute X_INTERFACE_INFO of S_AXI_BRESP : signal is "xilinx.com:interface:aximm:1.0 S_AXI BRESP";
    attribute X_INTERFACE_INFO of S_AXI_BVALID : signal is "xilinx.com:interface:aximm:1.0 S_AXI BVALID";
    attribute X_INTERFACE_INFO of S_AXI_BREADY : signal is "xilinx.com:interface:aximm:1.0 S_AXI BREADY";
    attribute X_INTERFACE_INFO of S_AXI_ARADDR : signal is "xilinx.com:interface:aximm:1.0 S_AXI ARADDR";
    attribute X_INTERFACE_INFO of S_AXI_ARVALID : signal is "xilinx.com:interface:aximm:1.0 S_AXI ARVALID";
    attribute X_INTERFACE_INFO of S_AXI_ARREADY : signal is "xilinx.com:interface:aximm:1.0 S_AXI ARREADY";
    attribute X_INTERFACE_INFO of S_AXI_RDATA : signal is "xilinx.com:interface:aximm:1.0 S_AXI RDATA";
    attribute X_INTERFACE_INFO of S_AXI_RRESP : signal is "xilinx.com:interface:aximm:1.0 S_AXI RRESP";
    attribute X_INTERFACE_INFO of S_AXI_RVALID : signal is "xilinx.com:interface:aximm:1.0 S_AXI RVALID";
    attribute X_INTERFACE_INFO of S_AXI_RREADY : signal is "xilinx.com:interface:aximm:1.0 S_AXI RREADY";
    attribute X_INTERFACE_PARAMETER of S_AXI_AWADDR : signal is "PROTOCOL AXI4LITE, DATA_WIDTH 32, ADDR_WIDTH 6";

    ---------------------------------------------------------------------------

    -- Component declarations
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

    component bbo_axi_stream is
        Generic (
            C_AXI_DATA_WIDTH : integer := 64;   -- 64-bit for XDMA C2H
            C_BBO_SIZE       : integer := 44
        );
        Port (
            aclk           : in  STD_LOGIC;
            aresetn        : in  STD_LOGIC;
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
            m_axis_tdata   : out STD_LOGIC_VECTOR(C_AXI_DATA_WIDTH-1 downto 0);
            m_axis_tkeep   : out STD_LOGIC_VECTOR(C_AXI_DATA_WIDTH/8-1 downto 0);
            m_axis_tvalid  : out STD_LOGIC;
            m_axis_tready  : in  STD_LOGIC;
            m_axis_tlast   : out STD_LOGIC;
            bbo_count      : out STD_LOGIC_VECTOR(31 downto 0);
            fifo_overflow  : out STD_LOGIC
        );
    end component;

    component control_registers is
        Generic (
            C_S_AXI_DATA_WIDTH : integer := 32;
            C_S_AXI_ADDR_WIDTH : integer := 6
        );
        Port (
            S_AXI_ACLK     : in  STD_LOGIC;
            S_AXI_ARESETN  : in  STD_LOGIC;
            S_AXI_AWADDR   : in  STD_LOGIC_VECTOR(C_S_AXI_ADDR_WIDTH-1 downto 0);
            S_AXI_AWVALID  : in  STD_LOGIC;
            S_AXI_AWREADY  : out STD_LOGIC;
            S_AXI_WDATA    : in  STD_LOGIC_VECTOR(C_S_AXI_DATA_WIDTH-1 downto 0);
            S_AXI_WSTRB    : in  STD_LOGIC_VECTOR(C_S_AXI_DATA_WIDTH/8-1 downto 0);
            S_AXI_WVALID   : in  STD_LOGIC;
            S_AXI_WREADY   : out STD_LOGIC;
            S_AXI_BRESP    : out STD_LOGIC_VECTOR(1 downto 0);
            S_AXI_BVALID   : out STD_LOGIC;
            S_AXI_BREADY   : in  STD_LOGIC;
            S_AXI_ARADDR   : in  STD_LOGIC_VECTOR(C_S_AXI_ADDR_WIDTH-1 downto 0);
            S_AXI_ARVALID  : in  STD_LOGIC;
            S_AXI_ARREADY  : out STD_LOGIC;
            S_AXI_RDATA    : out STD_LOGIC_VECTOR(C_S_AXI_DATA_WIDTH-1 downto 0);
            S_AXI_RRESP    : out STD_LOGIC_VECTOR(1 downto 0);
            S_AXI_RVALID   : out STD_LOGIC;
            S_AXI_RREADY   : in  STD_LOGIC;
            ctrl_enable    : out STD_LOGIC;
            ctrl_reset     : out STD_LOGIC;
            filter_enable  : out STD_LOGIC;
            filter_symbol  : out STD_LOGIC_VECTOR(63 downto 0);
            status_running : in  STD_LOGIC;
            status_overflow: in  STD_LOGIC;
            bbo_count      : in  STD_LOGIC_VECTOR(31 downto 0);
            last_rx_ts     : in  STD_LOGIC_VECTOR(31 downto 0);
            last_tx_ts     : in  STD_LOGIC_VECTOR(31 downto 0);
            latency_ns     : in  STD_LOGIC_VECTOR(31 downto 0);
            max_latency_ns : in  STD_LOGIC_VECTOR(31 downto 0);
            min_latency_ns : in  STD_LOGIC_VECTOR(31 downto 0)
        );
    end component;

    component latency_calculator is
        Port (
            clk            : in  STD_LOGIC;
            rst            : in  STD_LOGIC;
            ts_valid       : in  STD_LOGIC;
            ts_t1          : in  STD_LOGIC_VECTOR(31 downto 0);
            ts_t2          : in  STD_LOGIC_VECTOR(31 downto 0);
            ts_t3          : in  STD_LOGIC_VECTOR(31 downto 0);
            ts_t4          : in  STD_LOGIC_VECTOR(31 downto 0);
            stats_reset    : in  STD_LOGIC;
            last_latency_ns: out STD_LOGIC_VECTOR(31 downto 0);
            max_latency_ns : out STD_LOGIC_VECTOR(31 downto 0);
            min_latency_ns : out STD_LOGIC_VECTOR(31 downto 0);
            last_rx_ts     : out STD_LOGIC_VECTOR(31 downto 0);
            last_tx_ts     : out STD_LOGIC_VECTOR(31 downto 0)
        );
    end component;

    -- Internal signals - CDC FIFO
    signal cdc_wr_en        : STD_LOGIC;
    signal cdc_wr_full      : STD_LOGIC;
    signal cdc_wr_almost_full : STD_LOGIC;
    signal cdc_rd_en        : STD_LOGIC;
    signal cdc_rd_empty     : STD_LOGIC;
    signal cdc_rd_valid     : STD_LOGIC;
    signal cdc_overflow     : STD_LOGIC;

    -- CDC FIFO read data
    signal cdc_symbol       : STD_LOGIC_VECTOR(63 downto 0);
    signal cdc_bid_price    : STD_LOGIC_VECTOR(31 downto 0);
    signal cdc_bid_size     : STD_LOGIC_VECTOR(31 downto 0);
    signal cdc_ask_price    : STD_LOGIC_VECTOR(31 downto 0);
    signal cdc_ask_size     : STD_LOGIC_VECTOR(31 downto 0);
    signal cdc_spread       : STD_LOGIC_VECTOR(31 downto 0);
    signal cdc_ts_t1        : STD_LOGIC_VECTOR(31 downto 0);
    signal cdc_ts_t2        : STD_LOGIC_VECTOR(31 downto 0);
    signal cdc_ts_t3        : STD_LOGIC_VECTOR(31 downto 0);
    signal cdc_ts_t4        : STD_LOGIC_VECTOR(31 downto 0);

    -- AXI-Stream signals
    signal stream_ready     : STD_LOGIC;
    signal stream_bbo_count : STD_LOGIC_VECTOR(31 downto 0);
    signal stream_overflow  : STD_LOGIC;

    -- Control signals
    signal ctrl_enable      : STD_LOGIC;
    signal ctrl_reset       : STD_LOGIC;
    signal filter_enable    : STD_LOGIC;
    signal filter_symbol    : STD_LOGIC_VECTOR(63 downto 0);

    -- Status signals
    signal status_running   : STD_LOGIC;
    signal status_overflow  : STD_LOGIC;

    -- Latency calculator signals
    signal last_latency_ns  : STD_LOGIC_VECTOR(31 downto 0);
    signal max_latency_ns   : STD_LOGIC_VECTOR(31 downto 0);
    signal min_latency_ns   : STD_LOGIC_VECTOR(31 downto 0);
    signal last_rx_ts       : STD_LOGIC_VECTOR(31 downto 0);
    signal last_tx_ts       : STD_LOGIC_VECTOR(31 downto 0);

    -- Symbol filter match
    signal symbol_match     : STD_LOGIC;

    -- LED blink counter
    signal led_counter      : unsigned(23 downto 0) := (others => '0');
    signal led_blink        : STD_LOGIC := '0';

    -- Reset synchronizer for XDMA domain
    signal rst_sync1        : STD_LOGIC := '1';
    signal rst_sync2        : STD_LOGIC := '1';
    signal axi_rst          : STD_LOGIC;

begin

    -- Reset synchronization to XDMA clock domain
    process(axi_aclk)
    begin
        if rising_edge(axi_aclk) then
            rst_sync1 <= not axi_aresetn;
            rst_sync2 <= rst_sync1;
        end if;
    end process;
    axi_rst <= rst_sync2;

    -- Symbol filter comparison
    symbol_match <= '1' when (filter_enable = '0') or (bbo_symbol = filter_symbol) else '0';

    -- CDC FIFO write enable (only when enabled and symbol matches)
    cdc_wr_en <= bbo_update and ctrl_enable and symbol_match and (not cdc_wr_full);

    -- CDC FIFO read enable (when stream converter is ready)
    cdc_rd_en <= stream_ready and (not cdc_rd_empty);

    -- Status signals
    status_running <= ctrl_enable and (not cdc_rd_empty);
    status_overflow <= cdc_overflow or stream_overflow;

    -- LED outputs
    led_link_up <= '1';  -- Will be connected to PCIe link status
    led_streaming <= ctrl_enable and led_blink;
    led_overflow <= status_overflow;

    -- LED blink process
    process(axi_aclk)
    begin
        if rising_edge(axi_aclk) then
            if axi_rst = '1' then
                led_counter <= (others => '0');
                led_blink <= '0';
            else
                led_counter <= led_counter + 1;
                if led_counter = 0 then
                    led_blink <= not led_blink;
                end if;
            end if;
        end if;
    end process;

    -- CDC FIFO instance
    cdc_fifo_inst : bbo_cdc_fifo
        generic map (
            FIFO_DEPTH_LOG2 => 4
        )
        port map (
            wr_clk         => clk_trading,
            wr_rst         => rst_trading,
            wr_en          => cdc_wr_en,
            wr_full        => cdc_wr_full,
            wr_almost_full => cdc_wr_almost_full,
            wr_symbol      => bbo_symbol,
            wr_bid_price   => bbo_bid_price,
            wr_bid_size    => bbo_bid_size,
            wr_ask_price   => bbo_ask_price,
            wr_ask_size    => bbo_ask_size,
            wr_spread      => bbo_spread,
            wr_ts_t1       => ts_t1,
            wr_ts_t2       => ts_t2,
            wr_ts_t3       => ts_t3,
            wr_ts_t4       => ts_t4,
            rd_clk         => axi_aclk,
            rd_rst         => axi_rst,
            rd_en          => cdc_rd_en,
            rd_empty       => cdc_rd_empty,
            rd_valid       => cdc_rd_valid,
            rd_symbol      => cdc_symbol,
            rd_bid_price   => cdc_bid_price,
            rd_bid_size    => cdc_bid_size,
            rd_ask_price   => cdc_ask_price,
            rd_ask_size    => cdc_ask_size,
            rd_spread      => cdc_spread,
            rd_ts_t1       => cdc_ts_t1,
            rd_ts_t2       => cdc_ts_t2,
            rd_ts_t3       => cdc_ts_t3,
            rd_ts_t4       => cdc_ts_t4,
            overflow       => cdc_overflow
        );

    -- AXI-Stream converter instance
    axi_stream_inst : bbo_axi_stream
        generic map (
            C_AXI_DATA_WIDTH => C_AXI_DATA_WIDTH,
            C_BBO_SIZE       => 44
        )
        port map (
            aclk           => axi_aclk,
            aresetn        => axi_aresetn,
            bbo_valid      => cdc_rd_valid,
            bbo_ready      => stream_ready,
            bbo_symbol     => cdc_symbol,
            bbo_bid_price  => cdc_bid_price,
            bbo_bid_size   => cdc_bid_size,
            bbo_ask_price  => cdc_ask_price,
            bbo_ask_size   => cdc_ask_size,
            bbo_spread     => cdc_spread,
            bbo_ts_t1      => cdc_ts_t1,
            bbo_ts_t2      => cdc_ts_t2,
            bbo_ts_t3      => cdc_ts_t3,
            bbo_ts_t4      => cdc_ts_t4,
            m_axis_tdata   => m_axis_tdata,
            m_axis_tkeep   => m_axis_tkeep,
            m_axis_tvalid  => m_axis_tvalid,
            m_axis_tready  => m_axis_tready,
            m_axis_tlast   => m_axis_tlast,
            bbo_count      => stream_bbo_count,
            fifo_overflow  => stream_overflow
        );

    -- Control registers instance
    ctrl_regs_inst : control_registers
        generic map (
            C_S_AXI_DATA_WIDTH => C_AXI_LITE_DATA_WIDTH,
            C_S_AXI_ADDR_WIDTH => C_AXI_LITE_ADDR_WIDTH
        )
        port map (
            S_AXI_ACLK     => axi_aclk,
            S_AXI_ARESETN  => axi_aresetn,
            S_AXI_AWADDR   => S_AXI_AWADDR,
            S_AXI_AWVALID  => S_AXI_AWVALID,
            S_AXI_AWREADY  => S_AXI_AWREADY,
            S_AXI_WDATA    => S_AXI_WDATA,
            S_AXI_WSTRB    => S_AXI_WSTRB,
            S_AXI_WVALID   => S_AXI_WVALID,
            S_AXI_WREADY   => S_AXI_WREADY,
            S_AXI_BRESP    => S_AXI_BRESP,
            S_AXI_BVALID   => S_AXI_BVALID,
            S_AXI_BREADY   => S_AXI_BREADY,
            S_AXI_ARADDR   => S_AXI_ARADDR,
            S_AXI_ARVALID  => S_AXI_ARVALID,
            S_AXI_ARREADY  => S_AXI_ARREADY,
            S_AXI_RDATA    => S_AXI_RDATA,
            S_AXI_RRESP    => S_AXI_RRESP,
            S_AXI_RVALID   => S_AXI_RVALID,
            S_AXI_RREADY   => S_AXI_RREADY,
            ctrl_enable    => ctrl_enable,
            ctrl_reset     => ctrl_reset,
            filter_enable  => filter_enable,
            filter_symbol  => filter_symbol,
            status_running => status_running,
            status_overflow => status_overflow,
            bbo_count      => stream_bbo_count,
            last_rx_ts     => last_rx_ts,
            last_tx_ts     => last_tx_ts,
            latency_ns     => last_latency_ns,
            max_latency_ns => max_latency_ns,
            min_latency_ns => min_latency_ns
        );

    -- Latency calculator instance
    latency_calc_inst : latency_calculator
        port map (
            clk            => axi_aclk,
            rst            => axi_rst,
            ts_valid       => cdc_rd_valid,
            ts_t1          => cdc_ts_t1,
            ts_t2          => cdc_ts_t2,
            ts_t3          => cdc_ts_t3,
            ts_t4          => cdc_ts_t4,
            stats_reset    => ctrl_reset,
            last_latency_ns => last_latency_ns,
            max_latency_ns => max_latency_ns,
            min_latency_ns => min_latency_ns,
            last_rx_ts     => last_rx_ts,
            last_tx_ts     => last_tx_ts
        );

end Behavioral;
