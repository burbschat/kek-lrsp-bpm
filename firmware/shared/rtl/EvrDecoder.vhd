library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;
use ieee.numeric_std.all;

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
        TPD_G    : time    := 1 ns;
        N_TRGS_G : integer := 16        -- Number of mappable trigger outputs
        );
    port (
        usrClk  : in sl;  -- user clock (rx data interface syncrhonous to this clock)
        data    : in slv(15 downto 0);
        dataK   : in slv(1 downto 0);
        dispErr : in slv(1 downto 0);
        decErr  : in slv(1 downto 0);

        eventCode : out slv(7 downto 0);
        distrBus  : out slv(7 downto 0);  -- Apparently every other transmission might be a 'shared data' one, but no idea how to tell those apart.

        -- Trigger outputs. High level names should be better assigned in
        -- software, not firmware. So just use numbers here.
        trgs : out slv(N_TRGS_G - 1 downto 0);

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

    -- Use constants for easy flip in case I get it the wrong way around (order
    -- used in multiple locations below)
    -- TODO: Check that this is indeed the correct way around!
    constant DISTR_BUS_BITS_IDX_C  : integer := 1;  -- Upper 8
    constant EVENT_CODE_BITS_IDX_C : integer := 0;  -- Lower 8

    signal eventCodeInt : slv(7 downto 0);
    signal distrBusInt  : slv(7 downto 0);  -- Apparently every other transmission might be a 'shared data' one, but no idea how to tell those apart.

    -- Counters incremented on trigger of a given trigger line. Both
    -- synchronous to usr clock NOT axil clock!
    signal trgCounts       : Slv32Array(N_TRGS_G - 1 downto 0) := (others => (others => '0'));
    signal trgCountsResets : slv(N_TRGS_G - 1 downto 0);

    type RegType is record
        ignoreIfK   : slv (1 downto 0);
        ignoreIfErr : slv (1 downto 0);

        -- Map storing event code corresponding to each trigger line
        trgsEventMap : Slv8Array(N_TRGS_G - 1 downto 0);

        trgCountsResets : slv(N_TRGS_G - 1 downto 0);

        axilReadSlave  : AxiLiteReadSlaveType;
        axilWriteSlave : AxiLiteWriteSlaveType;
    end record RegType;

    constant REG_INIT_C : RegType := (
        ignoreIfK   => (others => '1'),  -- Ignore if comma by default
        ignoreIfErr => (others => '1'),  -- Ignore if error by default

        trgsEventMap => (others => (others => '0')),

        trgCountsResets => (others => '0'),

        axilReadSlave  => AXI_LITE_READ_SLAVE_INIT_C,
        axilWriteSlave => AXI_LITE_WRITE_SLAVE_INIT_C);

    signal r   : RegType := REG_INIT_C;
    signal rin : RegType;

begin
    -- Assign internal signals to outputs
    eventCode <= eventCodeInt;
    distrBus  <= distrBusInt;

    -- One event code is 8 bit so each trigger line requires an 8 bit register
    -- to set the corresponding event. For 32 triggers we need 32 * 8 = 256
    -- register bits. Could have more, but for now the register interface will
    -- have registers for up to 32 triggers only (should be enough).
    -- assert N_TRGS_G <= N_TRGS_MAX_C report "N_TRGS_G must be <= 32 with current register mapping" severity failure;

    -- 'Decoding' process to extract even code, distributed bus/shared data
    DEC_PROC : process(usrClk)
        variable dataGood     : slv(1 downto 0);
        variable distrBusVar  : slv(7 downto 0);
        variable eventCodeVar : slv(7 downto 0);
        variable trgsVar      : slv(N_TRGS_G - 1 downto 0);
        variable newTrgCounts : Slv32Array(N_TRGS_G - 1 downto 0);
    begin
        if rising_edge(usrClk) then
            -- Initialize variables
            dataGood     := (others => '0');
            eventCodeVar := (others => '0');
            trgsVar      := (others => '0');
            newTrgCounts := trgCounts;  -- Init with current counts, later reset or increment, then assign back to signal

            -- Do same checks for upper (distributed bus) and lower (event code) bits
            for i in 0 to 1 loop
                if (not (r.ignoreIfK(i) = '1' and dataK(i) = '1'))
                    and (not (r.ignoreIfErr(i) = '1' and (dispErr(i) = '1' or decErr(i) = '1'))) then
                    -- Set data good flag variable to trigger further processing below
                    dataGood(i) := '1';
                end if;
            end loop;

            if dataGood(DISTR_BUS_BITS_IDX_C) = '1' then
                distrBusVar := data(7 + DISTR_BUS_BITS_IDX_C * 8 downto 0 + DISTR_BUS_BITS_IDX_C * 8);

                -- TODO: Could do some processing here...
                -- Not sure what sort of data is usually available here and how
                -- we might want to use it.
                -- Something like: State machine that listens for message start
                -- bit, then transitions to receive state until message stop
                -- bit received. 
                -- In any case, distributed bus/shared data is transmitted
                -- alternated. I assume on the message start K either DB or SD
                -- comes first and after that the pattern repeats. This then can
                -- be used for alignment.

                -- Update eventCode signal, but only if new good data received
                distrBusInt <= distrBusVar;
            end if;

            -- Trigger counts reset
            -- Could have this before or after the event code check.
            -- For now, before the check so that even in the reset
            -- cycle we can count a trigger if it occurs. This should
            -- be the more consistent choice as adding trigger counts
            -- between resets is ensured to actually equal the number
            -- of total triggers.
            for i in 0 to N_TRGS_G - 1 loop
                if trgCountsResets(i) = '1' then
                    newTrgCounts(i) := (others => '0');  -- Use variable to control assignment order
                end if;
            end loop;

            if dataGood(EVENT_CODE_BITS_IDX_C) = '1' then
                eventCodeVar := data(7 + EVENT_CODE_BITS_IDX_C * 8 downto 0 + EVENT_CODE_BITS_IDX_C * 8);
                -- Check against all event codes in the triggers to events map
                -- register. Will this result in very complicated logic? If so,
                -- avoidable?
                -- TODO: Should we synchronize this register to usrClk to
                -- ensure no accidental triggers which perhaps could happen if we
                -- read this register at just the time it is changed by the
                -- axil process?
                for i in 0 to N_TRGS_G - 1 loop
                    if r.trgsEventMap(i) = eventCodeVar then
                        trgsVar(i)      := '1';
                        newTrgCounts(i) := newTrgCounts(i) + 1;  -- Increase corresponding counter
                    end if;
                end loop;

                -- TODO: I guess that assumes that lines never stay high in idle? Maybe not a true assumption here...
                -- Update eventCode signal, but only if new good data received
                eventCodeInt <= eventCodeVar;
            end if;

            -- Update counters of which some may have been reset or incremented
            trgCounts    <= newTrgCounts;

            -- Assign trigger outputs. Do this every time as we want to reset them
            -- if no event code matched (strobe)
            trgs <= trgsVar;

        end if;
    end process DEC_PROC;


    -- Synchronize counter reset from axi clock domain (register interface) to usr clock domain.
    -- Use one-shot synchronizer to make sure we don't accidentally keep resets on usr clock side
    -- high for multiple clock cycles which could lead to counts being lost if we keep a slow
    -- tally.
    -- TODO: The counters itself should also be synchronized? Not catching a signal
    -- as for reset strobes should be no problem but perhaps reading it during a transition
    -- might be? But how would the synchronizer resolve such an issue to begin with...
    U_SyncV_Inst : entity surf.SynchronizerOneShotVector
        generic map(
            TPD_G   => TPD_G,
            WIDTH_G => N_TRGS_G)
        port map(
            clk     => usrClk,
            dataIn  => r.trgCountsResets,
            dataOut => trgCountsResets);


    -- AXI-Lite register interface processes
    comb : process(axilReadMaster, axilWriteMaster, r, distrBusInt, eventCodeInt, trgCounts)
        variable v      : RegType;
        variable axilEp : AxiLiteEndPointType;
    begin
        -- Latch the current value
        v := r;

        -- Reset strobes
        v.trgCountsResets := (others => '0');

        ----------------------------------------------------------------------
        --                AXI-Lite Register Logic
        ----------------------------------------------------------------------

        -- Determine the transaction type
        axiSlaveWaitTxn(axilEp, axilWriteMaster, axilReadMaster, v.axilWriteSlave, v.axilReadSlave);

        -------------------------
        -- Map the read registers
        -------------------------

        -- TODO: Decide addresses
        axiSlaveRegister (axilEp, x"00", 0, v.ignoreIfK);
        axiSlaveRegister (axilEp, x"00", 2, v.ignoreIfErr);
        axiSlaveRegisterR (axilEp, x"04", 0, eventCodeInt);
        axiSlaveRegisterR (axilEp, x"04", 8, distrBusInt);

        -- One event code is 8 bit so each trigger line requires an 8 bit register
        -- to set the corresponding event. Place at end of address space as the number
        -- of registers depends on generic and may change.
        for i in 0 to N_TRGS_G - 1 loop
            -- TODO: Check if integer division works as intended!
            axiSlaveRegister (axilEp, x"08" + conv_std_logic_vector((i / 4) * 4, 8), (i * 8) mod 32, v.trgsEventMap(i));
            -- Start at final 32 bit register of event to trigger mapping plus one register (offset by 4)
            axiSlaveRegisterR (axilEp, x"08" + conv_std_logic_vector(((N_TRGS_G - 1) / 4) * 4, 8) + x"04" + i * 4, 0, trgCounts(i));
            -- Ok this becomes silly at this point... Just wanted to see how far I can take this. I'm impressed if this works to begin with...
            axiSlaveRegister (axilEp, x"08" + conv_std_logic_vector(((N_TRGS_G - 1) / 4) * 4, 8) + x"04" + (N_TRGS_G - 1) * 4 + x"04" + (i / 32) * 4, i mod 32, v.trgCountsResets(i));
        end loop;

        -- Closeout the transaction
        axiSlaveDefault(axilEp, v.axilWriteSlave, v.axilReadSlave, AXI_RESP_DECERR_C);

        ----------------------------------------------------------------------

        -- Outputs

        axilWriteSlave <= r.axilWriteSlave;
        axilReadSlave  <= r.axilReadSlave;

        -- Register the variable for next clock cycle
        rin <= v;

    end process comb;

    seq : process (axilClk) is
    begin
        if rising_edge(axilClk) then
            r <= rin after TPD_G;
        end if;
    end process seq;

end architecture rtl;
