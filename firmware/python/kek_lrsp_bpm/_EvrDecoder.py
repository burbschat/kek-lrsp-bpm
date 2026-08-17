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

        self._statesEnum = {
                0x0: 'IDLE',
                0x1: 'RECEIVE_S',
        }

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
            enum         = self._statesEnum,
        ))

        # Publish state name as string for use in PyDM displays
        self.add(pr.LinkVariable(
            name         = "stateStr",
            description  = "String indicating the current state",
            mode         = "RO",
            dependencies = [self.stateReg],
            linkedGet    = lambda: self.getStateString(self.stateReg.value()),
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

    def getStateString(self, stateIdx):
        if stateIdx in self._statesEnum:
            return self._statesEnum[stateIdx]
        else:
            return "UNDEFINED"



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

        self.add(pr.LocalVariable(
            name         = "NumTrigs",
            description  = "Number of Trigger Channels",
            typeStr      = "Int32",
            value        = self.n_trgs,
            mode         = "RO",  # Fixed at initialization
            hidden       = False,
        ))

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

        event_map_base = 0x08
        event_map_last = event_map_base + ((self.n_trgs - 1) // 4) * 4
        trg_count_base = event_map_last + 0x04
        trg_reset_base = trg_count_base + self.n_trgs * 4

        for i in range(self.n_trgs):
            self.add(pr.RemoteVariable(
                name         = f'trg{i}EventCode',
                description  = f'Event code on which to strobe trigger output nr. {i}',
                offset       = event_map_base + (i // 4) * 4,
                bitOffset    = (i * 8) % 32,
                bitSize      = 8,
                mode         = 'RW',
                value        = 0xFF,  # 0xFF should be unused event code (at KEK)
                hidden       = False,
            ))

            self.add(pr.RemoteVariable(
                name         = f'trg{i}Count',
                description  = f'Number of times trigger {i} has fired',
                offset       = trg_count_base + i * 4,
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
            # bulkOpEn = False does not seem to help either (seems like this
            # would be a related option)...
            reset_var = pr.RemoteVariable(
                name         = f'trg{i}ResetReg',
                description  = f'Reset trigger {i} counter',
                offset       = trg_reset_base + (i // 32) * 4,
                # bulkOpEn     = False,
                bitOffset    = i % 32,
                bitSize      = 1,
                mode         = 'WO',
                hidden       = True,
            )

            self.reset_vars[i] = reset_var
            self.add(reset_var)

            @self.command(name=f'trg{i}Reset')
            def reset_workaround(reset_var_ref=reset_var):
                # Workaround for set values ending up sticky...
                # TODO: Find a better way?
                reset_var_ref.set(1)
                reset_var_ref.set(0)
