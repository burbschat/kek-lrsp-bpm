import pyrogue as pr
import surf.axi as axi

class EvrDecoder(pr.Device):
    def __init__(
        self,
        n_trgs=16,  # Must match N_TRGS_G set for decoder in firmware!
        *args,
        **kwargs,
    ):
        super().__init__(*args, **kwargs)

        # Must this be rfsoc.EvrTrgs?
        self.add(EvrTrgs(
            offset     = 0x0000_0000,
            n_trgs     = n_trgs,
        ))

        self.add(EvrDbSd(
            offset     = 0x0010_0000,
        ))


class EvrDbSd(pr.Device):
    def __init__(
        self,
        *args,
        **kwargs,
    ):
        super().__init__(*args, **kwargs)

        self.add(axi.AxiStreamFrameBuffer(
            name   = f'FrameBuff',
            offset = 0x0,
        ))

        self._reg_base = 1 * 0x1000

        self.add(pr.RemoteVariable(
            name         = 'stateReg',
            description  = 'Register indicating the state of the trigger FSM',
            offset       = self._reg_base + 0x00,
            bitSize      = 8,
            mode         = 'RO',
            pollInterval = 1,
            # These are encoding dependent and thus may depend on implementation of enums in the firmware
            enum        = {
                0x0: 'IDLE',
                0x1: 'RECEIVE_S',
            },
        ))

        self.add(pr.RemoteVariable(
            name         = 'SwTrig',
            description  = 'Software ring buffer rigger',
            offset       = self._reg_base + 0x4,
            bitSize      = 1,
            mode         = 'WO',
            hidden       = True,
        ))

        @self.command()
        def SendSwTrig():
            self.SwTrig.set(1)


class EvrTrgs(pr.Device):
    def __init__(
        self,
        n_trgs=16,  # Must match N_TRGS_G set for decoder in firmware!
        *args,
        **kwargs,
    ):
        super().__init__(*args, **kwargs)

        self.n_trgs = n_trgs

        self.reset_vars = {}

        self.add(pr.RemoteVariable(
            name         = 'ignoreIfK',
            description  = 'Ignore event code bits if corresponding k flag set',
            offset       = 0x0,
            bitOffset    = 0,
            bitSize      = 1,
            mode         = 'RW',
            hidden       = False,
        ))

        self.add(pr.RemoteVariable(
            name         = 'ignoreIfInvalid',
            description  = 'Ignore event code byte if corresponding disparity or decode error flag set',
            offset       = 0x0,
            bitOffset    = 2,
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
