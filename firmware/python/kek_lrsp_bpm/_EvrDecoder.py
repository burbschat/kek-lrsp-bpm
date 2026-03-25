import pyrogue as pr

class EvrDecoder(pr.Device):
    def __init__(
        self,
        n_trgs=16,  # Must match N_TRGS_G set for decoder in firmware!
        *args,
        **kwargs,
    ):
        super().__init__(*args, **kwargs)

        self.n_trgs = n_trgs

        self.reset_vars = {}

        # Must be set to match firmware!
        self.DISTR_BUS_BITS_IDX_C  = 1;  # Upper 8
        self.EVENT_CODE_BITS_IDX_C = 0;  # Lower 8

        self.add(pr.RemoteVariable(
            name         = 'distrBusIgnoreIfK',
            description  = 'Ignore distributed bus byte if corresponding k flag set',
            offset       = 0x0,
            bitOffset    = self.DISTR_BUS_BITS_IDX_C,
            bitSize      = 1,
            mode         = 'RW',
            hidden       = False,
        ))

        self.add(pr.RemoteVariable(
            name         = 'eventCodeIgnoreIfK',
            description  = 'Ignore event code byte if corresponding k flag set',
            offset       = 0x0,
            bitOffset    = self.EVENT_CODE_BITS_IDX_C,
            bitSize      = 1,
            mode         = 'RW',
            hidden       = False,
        ))

        self.add(pr.RemoteVariable(
            name         = 'distrBusIgnoreIfErr',
            description  = 'Ignore distributed bus byte if corresponding disparity or decode error flag set',
            offset       = 0x0,
            bitOffset    = 2 + self.DISTR_BUS_BITS_IDX_C,
            bitSize      = 1,
            mode         = 'RW',
            hidden       = False,
        ))

        self.add(pr.RemoteVariable(
            name         = 'eventCodeIgnoreIfErr',
            description  = 'Ignore event code byte if corresponding disparity or decode error flag set',
            offset       = 0x0,
            bitOffset    = 2 + self.EVENT_CODE_BITS_IDX_C,
            bitSize      = 1,
            mode         = 'RW',
            hidden       = False,
        ))

        self.add(pr.RemoteVariable(
            name         = 'eventCode',
            description  = 'Value of last received event code',
            offset       = 0x4,
            bitOffset    = 0,
            bitSize      = 8,
            mode         = 'RO',
            pollInterval = 0.1,
            hidden       = False,
        ))

        self.add(pr.RemoteVariable(
            name         = 'distrBus',
            description  = 'Value of last received distributed bus data',
            offset       = 0x4,
            bitOffset    = 8,
            bitSize      = 8,
            mode         = 'RO',
            pollInterval = 0.1,
            hidden       = False,
        ))

        for i in range(self.n_trgs):
            self.add(pr.RemoteVariable(
                name         = f'trg{i}EventCode',
                description  = f'Event code on which to strobe trigger output nr. {i}',
                offset       = 0x8 + (i // 4) * 4,
                bitOffset    = (i * 8) % 32,
                bitSize      = 8,
                mode         = 'RW',
                hidden       = False,
            ))

            self.add(pr.RemoteVariable(
                name         = f'trg{i}Count',
                description  = f'Number of times trigger {i} has fired',
                offset       = 0x8 + ((self.n_trgs - 1) // 4) * 4 + 0x4 + i * 4,
                bitOffset    = 0,
                bitSize      = 32,
                mode         = 'RO',
                pollInterval = 0.1,
                hidden       = False,
            ))

            # TODO: Rogue appears to write the full register keeping the last
            # values from other bit offsets. I.e. if I write 1 to offset 0 then
            # 1 on the second write it actually writes 0b0011 instead of 0b0010
            # as I'd expect...
            reset_var = pr.RemoteVariable(
                name         = f'trg{i}ResetReg',
                description  = f'Reset trigger {i} counter',
                offset       = 0x8 + ((self.n_trgs - 1) // 4) * 4 + 0x4 + (self.n_trgs - 1) * 4 + 0x4 + (i // 32) * 4,
                bitOffset    = i % 32,
                bitSize      = 1,
                mode         = 'WO',
                hidden       = True,
            )

            self.reset_vars[i] = reset_var
            self.add(reset_var)

            @self.command(name=f'trg{i}Reset')
            def foo(reset_var_ref=reset_var):
                # Workaround for set values ending up sticky...
                # TODO: Find a better way?
                reset_var_ref.set(1)
                reset_var_ref.set(0)
