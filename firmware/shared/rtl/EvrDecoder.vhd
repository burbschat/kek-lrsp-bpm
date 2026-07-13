library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

library surf;
use surf.StdRtlPkg.all;
use surf.AxiStreamPkg.all;
use surf.AxiLitePkg.all;

library work;
use work.AppPkg.all;

-- Consume (rx) event system data, all syncrhonous to usr clock and extract
-- event code/shared bus.
-- TODO:
-- - How to output triggers? Could have
--    - some fixed, named outputs and perhaps a register that sets the map
--      between those/event codes? + raw event code? I guess that makes sense...
-- - Perhaps add counters for each trigger line?

entity EvrDecoder is
    generic (
        TPD_G            : time    := 1 ns;
        SYNTH_MODE_G     : string  := "inferred";
        N_TRGS_G         : integer := 16;  -- Number of mappable trigger outputs
        AXIL_BASE_ADDR_G : slv(31 downto 0)
        );
    port (
        clk     : in sl;  -- user clock (rx data interface syncrhonous to this clock)
        rst     : in sl;
        data    : in slv(15 downto 0);
        dataK   : in slv(1 downto 0);
        dispErr : in slv(1 downto 0);
        decErr  : in slv(1 downto 0);

        -- Trigger outputs. High level names should be better assigned in
        -- software, not firmware. So just use numbers here.
        trgs : out slv(N_TRGS_G - 1 downto 0);

        -- Trigger input to trigger dump of most recent shared data via AXI
        -- stream interface
        sdReadoutTrig : in sl;

        -- Outputs
        eventCode : out slv(7 downto 0);
        distrBus  : out slv(7 downto 0);  -- Apparently every other transmission might be a 'shared data' one, but no idea how to tell those apart.

        -- AXI-Stream Interface (axisClk domain)
        axisClk    : in  sl;
        axisRst    : in  sl;
        axisMaster : out AxiStreamMasterType;
        axisSlave  : in  AxiStreamSlaveType;

        -- AXI-Lite register interface
        axilClk         : in  sl                     := '0';
        axilRst         : in  sl                     := '0';
        axilReadMaster  : in  AxiLiteReadMasterType  := AXI_LITE_READ_MASTER_INIT_C;
        axilReadSlave   : out AxiLiteReadSlaveType;
        axilWriteMaster : in  AxiLiteWriteMasterType := AXI_LITE_WRITE_MASTER_INIT_C;
        axilWriteSlave  : out AxiLiteWriteSlaveType

        );
end entity EvrDecoder;

architecture rtl of EvrDecoder is

    -- Use constants for easy flip in case I get it the wrong way around
    constant EVENT_CODE_BITS_IDX_C : integer := 0;  -- Lower 8
    constant DBSD_BITS_IDX_C       : integer := 1;  -- Upper 8

    constant TRGS_INDEX_C       : natural := 0;
    constant DBSD_INDEX_C       : natural := 1;
    constant NUM_AXIL_MASTERS_C : natural := 2;

    constant AXIL_CONFIG_C : AxiLiteCrossbarMasterConfigArray(NUM_AXIL_MASTERS_C-1 downto 0) := genAxiLiteConfig(NUM_AXIL_MASTERS_C, AXIL_BASE_ADDR_G, 24, 20);

    signal axilReadMasters  : AxiLiteReadMasterArray(NUM_AXIL_MASTERS_C-1 downto 0);
    signal axilReadSlaves   : AxiLiteReadSlaveArray(NUM_AXIL_MASTERS_C-1 downto 0)  := (others => AXI_LITE_READ_SLAVE_EMPTY_DECERR_C);
    signal axilWriteMasters : AxiLiteWriteMasterArray(NUM_AXIL_MASTERS_C-1 downto 0);
    signal axilWriteSlaves  : AxiLiteWriteSlaveArray(NUM_AXIL_MASTERS_C-1 downto 0) := (others => AXI_LITE_WRITE_SLAVE_EMPTY_DECERR_C);

begin

    U_XBAR : entity surf.AxiLiteCrossbar
        generic map (
            TPD_G              => TPD_G,
            NUM_SLAVE_SLOTS_G  => 1,
            NUM_MASTER_SLOTS_G => NUM_AXIL_MASTERS_C,
            MASTERS_CONFIG_G   => AXIL_CONFIG_C)
        port map (
            axiClk              => axilClk,
            axiClkRst           => axilRst,
            sAxiWriteMasters(0) => axilWriteMaster,
            sAxiWriteSlaves(0)  => axilWriteSlave,
            sAxiReadMasters(0)  => axilReadMaster,
            sAxiReadSlaves(0)   => axilReadSlave,
            mAxiWriteMasters    => axilWriteMasters,
            mAxiWriteSlaves     => axilWriteSlaves,
            mAxiReadMasters     => axilReadMasters,
            mAxiReadSlaves      => axilReadSlaves);

    -- Recover distributed bus and shared data and triggers from corresponding
    -- bits. Break out into a separate modules as this really is an independent
    -- operation which does not have to be implemented here directly.

    U_TRGS : entity work.EvrTrgs
        generic map(
            TPD_G    => TPD_G,
            N_TRGS_G => N_TRGS_G
            )
        port map(
            clk       => clk,
            rst       => rst,
            data      => data(7 + EVENT_CODE_BITS_IDX_C * 8 downto 0 + EVENT_CODE_BITS_IDX_C * 8),
            dataK     => dataK(EVENT_CODE_BITS_IDX_C),
            dataValid => not (dispErr(EVENT_CODE_BITS_IDX_C) or decErr(EVENT_CODE_BITS_IDX_C)),

            -- Axi-lite interface
            axilClk         => axilClk,
            axilRst         => axilRst,
            axilReadMaster  => axilReadMasters(TRGS_INDEX_C),
            axilReadSlave   => axilReadSlaves(TRGS_INDEX_C),
            axilWriteMaster => axilWriteMasters(TRGS_INDEX_C),
            axilWriteSlave  => axilWriteSlaves(TRGS_INDEX_C),

            -- Outputs
            trgs      => trgs,
            eventCode => eventCode
            );

    U_DBSD : entity work.EvrDbSd
        generic map(
            TPD_G            => TPD_G,
            SYNTH_MODE_G     => SYNTH_MODE_G,
            AXIL_BASE_ADDR_G => AXIL_CONFIG_C(DBSD_INDEX_C).baseAddr
            )
        port map(
            -- Inputs
            clk       => clk,
            rst       => rst,
            data      => data(7 + DBSD_BITS_IDX_C * 8 downto 0 + DBSD_BITS_IDX_C * 8),
            dataK     => dataK(DBSD_BITS_IDX_C),
            dataValid => not (dispErr(DBSD_BITS_IDX_C) or decErr(DBSD_BITS_IDX_C)),
            extTrig   => sdReadoutTrig,

            -- Axi-lite interface
            axilClk         => axilClk,
            axilRst         => axilRst,
            axilReadMaster  => axilReadMasters(DBSD_INDEX_C),
            axilReadSlave   => axilReadSlaves(DBSD_INDEX_C),
            axilWriteMaster => axilWriteMasters(DBSD_INDEX_C),
            axilWriteSlave  => axilWriteSlaves(DBSD_INDEX_C),

            -- Outputs
            distrBus => distrBus,

            -- AXI-Stream Interface (axisClk domain)
            axisClk    => axisClk,
            axisRst    => axisRst,
            axisMaster => axisMaster,
            axisSlave  => axisSlave
            );

end architecture rtl;
